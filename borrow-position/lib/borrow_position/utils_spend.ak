use aiken/bytearray.{concat}
use aiken/dict
use aiken/hash.{blake2b_256}
use aiken/list
use aiken/option
use aiken/string
use aiken/transaction.{InlineDatum, Output, Transaction}
use aiken/transaction/credential.{Address}
use aiken/transaction/value.{PolicyId}
use bond_issue/types.{BondDatum, BondIssueConfig} as bond_issue_types
use borrow_position/types.{BondOutputDict} as borrow_position_types
use borrow_position/utils_nft
use borrow_position/utils_token
use common/time.{get_current_epoch_with_ttl}
use common/util.{find_while}

pub fn get_bond_inputs(
  tx: Transaction,
  bond_addr: Address,
) -> (Int, List<ByteArray>, BondOutputDict) {
  list.foldr(
    tx.inputs,
    (0, [], dict.new()),
    fn(i, z) {
      if i.output.address.payment_credential == bond_addr.payment_credential {
        expect dt: BondDatum =
          when i.output.datum is {
            InlineDatum(d) -> d
            _ ->
              fail @"borrow_position/utils_spend.get_bond_inputs: only supports InlineDatum for bond"
          }
        let bond_key =
          blake2b_256(
            dt.bond_symbol
              |> concat(dt.token_name)
              |> concat(dt.borrower),
          )
        let bond_output =
          dict.insert_with(
            z.3rd,
            bond_key,
            (
              value.lovelace_of(i.output.value),
              value.without_lovelace(i.output.value),
              dt,
              i.output,
              0,
            ),
            fn(k, _, _) {
              let log =
                @"borrow_position/utils_spend.get_bond_inputs: bond utxo must be unique (bond_key="
                  |> string.concat(string.from_bytearray(k))
                  |> string.concat(@")")
              fail log
            },
            bytearray.compare,
          )
        (z.1st + 1, [bond_key, ..z.2nd], bond_output)
      } else {
        z
      }
    },
  )
}

pub fn get_bond_outputs(
  cfg: BondIssueConfig,
  tx: Transaction,
  bond_addr: Address,
) -> (Int, List<ByteArray>, BondOutputDict, Option<Output>) {
  list.foldr(
    tx.outputs,
    (0, [], dict.new(), None),
    fn(o, z) {
      if o.address.payment_credential == bond_addr.payment_credential {
        expect dt: BondDatum =
          when o.datum is {
            InlineDatum(d) -> d
            _ ->
              fail @"borrow_position/utils_spend.get_bond_outputs: only supports InlineDatum for bond"
          }
        let bond_key =
          blake2b_256(
            dt.bond_symbol
              |> concat(dt.token_name)
              |> concat(dt.borrower),
          )
        let bond_output =
          dict.insert_with(
            z.3rd,
            bond_key,
            (
              value.lovelace_of(o.value),
              value.without_lovelace(o.value),
              dt,
              o,
              0,
            ),
            fn(k, _, _) {
              let log =
                @"borrow_position/utils_spend.get_bond_outputs: bond utxo must be unique (bond_key="
                  |> string.concat(string.from_bytearray(k))
                  |> string.concat(@")")
              fail log
            },
            bytearray.compare,
          )
        (z.1st + 1, [bond_key, ..z.2nd], bond_output, z.4th)
      } else if o.address == cfg.platform.address {
        if (z.4th == None)? {
          (z.1st, z.2nd, z.3rd, Some(o))
        } else {
          fail @"borrow_position/utils_spend.get_bond_outputs: only 1 platform fee output is allowed"
        }
      } else {
        z
      }
    },
  )
}

pub fn fee_pay_interest_valid(
  cfg: BondIssueConfig,
  ibond_utxos: BondOutputDict,
  obond_utxos: BondOutputDict,
  ofee: Option<Output>,
) -> Bool {
  when ofee is {
    Some(o) -> {
      let obond_data =
        dict.union_with(
          ibond_utxos,
          obond_utxos,
          fn(_, v1, v2) {
            // v1 => ibond
            let (ibond_lovelace, ibond_assets, ibond_dt, ibond, _) = v1
            // v2 => obond
            let (obond_lovelace, obond_assets, obond_dt, obond, _) = v2

            if and {
              (obond.address == ibond.address)?,
              (obond_assets == ibond_assets)?,
              (obond_dt.epo_rewards == ibond_dt.epo_rewards)?,
              (obond_dt.duration == ibond_dt.duration)?,
              (obond_dt.bond_amount == ibond_dt.bond_amount)?,
              (obond_dt.buffer == ibond_dt.buffer)?,
              (obond_dt.fee == ibond_dt.fee)?,
              (obond_dt.start == ibond_dt.start)?,
            } {
              let interest = obond_lovelace - ibond_lovelace
              let interest_min =
                value.lovelace_of(ibond_dt.epo_rewards) * (
                  cfg.basis.base - ibond_dt.fee
                ) / cfg.basis.base
              if (interest >= interest_min)? {
                Some(
                  (
                    obond_lovelace,
                    obond_assets,
                    obond_dt,
                    obond,
                    interest * ibond_dt.fee / cfg.basis.base,
                  ),
                )
              } else {
                let log =
                  @"borrow_position/utils_spend.fee_pay_interest_valid: minimum interest payments are not guaranteed ("
                    |> string.concat(string.from_int(interest))
                    |> string.concat(@">=")
                    |> string.concat(string.from_int(interest_min))
                    |> string.concat(@")")
                fail log
              }
            } else {
              fail @"borrow_position/utils_spend.fee_pay_interest_valid: bond output invalid"
            }
          },
          bytearray.compare,
        )
      let total_fee =
        dict.foldr(
          obond_data,
          0,
          fn(_, v, z) {
            let (_, _, _, _, f) = v
            z + f
          },
        )
      (value.lovelace_of(o.value) >= total_fee)?
    }
    _ ->
      fail @"borrow_position/utils_spend.fee_pay_interest_valid: not found platform fee output"
  }
}

pub fn change_stake_key_valid(
  tx: Transaction,
  sbond: Output,
  sbond_addr: Address,
  sbond_dt: BondDatum,
) -> Bool {
  let (obond_found, obond_valid) =
    find_while(
      tx.outputs,
      (False, False),
      fn(o, z) {
        if o.address.payment_credential == sbond_addr.payment_credential {
          expect obond_dt: BondDatum =
            when o.datum is {
              InlineDatum(d) -> d
              _ ->
                fail @"borrow_position/utils_spend.change_stake_key_valid: only supports InlineDatum for bond"
            }
          if and {
            obond_dt.bond_symbol == sbond_dt.bond_symbol,
            obond_dt.token_name == sbond_dt.token_name,
            obond_dt.borrower == sbond_dt.borrower,
          } {
            if (z.1st == False)? {
              let datum_valid = and {
                  (obond_dt.epo_rewards == sbond_dt.epo_rewards)?,
                  (obond_dt.duration == sbond_dt.duration)?,
                  (obond_dt.bond_amount == sbond_dt.bond_amount)?,
                  (obond_dt.buffer == sbond_dt.buffer)?,
                  (obond_dt.fee == sbond_dt.fee)?,
                  (obond_dt.start == sbond_dt.start)?,
                  (o.value == sbond.value)?,
                }
              (False, (True, datum_valid))
            } else {
              fail @"borrow_position/utils_spend.change_stake_key_valid: bond utxo must be unique"
            }
          } else {
            (False, z)
          }
        } else {
          (False, z)
        }
      },
    )
  if obond_found? {
    obond_valid
  } else {
    fail @"borrow_position/utils_spend.change_stake_key_valid: bond utxo output invalid"
  }
}

pub fn redeem_valid(
  tx: Transaction,
  sbond: Output,
  sbond_addr: Address,
  sbond_dt: BondDatum,
  nft_pid: PolicyId,
) -> Bool {
  let (obond_found, obond_valid, bond_redeem_amt) =
    find_while(
      tx.outputs,
      (False, False, sbond_dt.bond_amount),
      fn(o, z) {
        if o.address.payment_credential == sbond_addr.payment_credential {
          expect dt: BondDatum =
            when o.datum is {
              InlineDatum(d) -> d
              _ ->
                fail @"borrow_position/utils_spend.redeem_valid: only supports InlineDatum for bond"
            }
          if and {
            dt.bond_symbol == sbond_dt.bond_symbol,
            dt.token_name == sbond_dt.token_name,
            dt.borrower == sbond_dt.borrower,
          } {
            if (z.1st == False)? {
              let balance = value.lovelace_of(sbond.value)
              let redeem_amt = sbond_dt.bond_amount - dt.bond_amount
              let redeem_val = balance / sbond_dt.bond_amount * redeem_amt

              (False, (True, and {
                    (dt.epo_rewards == sbond_dt.epo_rewards)?,
                    (dt.duration == sbond_dt.duration)?,
                    (dt.bond_amount < sbond_dt.bond_amount)?,
                    (dt.buffer == sbond_dt.buffer)?,
                    (dt.fee == sbond_dt.fee)?,
                    (dt.start == sbond_dt.start)?,
                    (value.without_lovelace(o.value) == value.without_lovelace(
                      sbond.value,
                    ))?,
                    (value.lovelace_of(o.value) == balance - redeem_val)?,
                  }, redeem_amt))
            } else {
              fail @"borrow_position/utils_spend.redeem_valid: bond utxo must be unique"
            }
          } else {
            (False, z)
          }
        } else {
          (False, z)
        }
      },
    )
  let mint_value = value.from_minted_value(tx.mint)
  if obond_found {
    let policy_mint =
      utils_nft.get_policy_mint(mint_value, sbond_dt.bond_symbol)

    and {
      obond_valid,
      (option.or_else(dict.get(policy_mint, sbond_dt.token_name), 0) == -bond_redeem_amt)?,
    }
  } else {
    let policy_mint =
      utils_token.get_policy_mint(mint_value, nft_pid, sbond_dt.bond_symbol)
    and {
      (option.or_else(dict.get(policy_mint.nfts, sbond_dt.token_name), 0) == -1)?,
      (option.or_else(dict.get(policy_mint.bonds, sbond_dt.token_name), 0) == -bond_redeem_amt)?,
    }
  }
}

pub fn bond_violate(
  cfg: BondIssueConfig,
  tx: Transaction,
  sbond: Output,
  sbond_dt: BondDatum,
) -> Bool {
  let epoch_curr =
    get_current_epoch_with_ttl(
      tx.validity_range,
      cfg.epoch,
      when cfg.platform.tx_ttl is {
        Some(i) -> i
        _ -> 3 * 60
      } * cfg.slot.slot_length,
    )
  let epoch_start = sbond_dt.start + cfg.epoch.epoch_boundary_as_epoch
  let epoch_end = epoch_start + sbond_dt.duration
  or {
    (epoch_curr >= epoch_end)?,
    epoch_required_premium_valid(cfg, sbond, sbond_dt, epoch_curr, epoch_start),
  }
}

fn epoch_required_premium_valid(
  cfg: BondIssueConfig,
  sbond: Output,
  sbond_dt: BondDatum,
  epoch_curr: Int,
  epoch_start: Int,
) -> Bool {
  let epoch_passed = epoch_curr - epoch_start + 1
  // let epoch_remain = epoch_end - epoch_passed
  let epoch_required_premium = epoch_passed + sbond_dt.buffer
  let principal = sbond_dt.bond_amount * cfg.platform.bond_face_value
  let balance = value.lovelace_of(sbond.value)
  let paid = balance - principal
  let paid_epoch = paid / value.lovelace_of(sbond_dt.epo_rewards)
  (paid_epoch < epoch_required_premium)?
}
