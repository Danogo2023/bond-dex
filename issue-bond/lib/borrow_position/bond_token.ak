use aiken/bytearray
use aiken/dict
use aiken/list
use aiken/math
use aiken/option
use aiken/transaction.{InlineDatum, OutputReference, Transaction}
use aiken/transaction/credential.{Address, ScriptCredential}
use aiken/transaction/value.{PolicyId}
use bond_issue/types.{BondDatum, BondIssueConfig, RequestDatum}
use common/hash_out_refs.{hash_out_ref_salt}
use common/types.{ScriptKeyHash} as common_types
use issue_bond/utils.{get_burn_token_names, get_input_by_nft_names}

pub fn burning_bond_redeem(
  tx: Transaction,
  bond_pid: PolicyId,
  nft_pid: PolicyId,
) -> Bool {
  let burn_names = get_burn_token_names(tx, bond_pid)
  let ibond = get_input_by_nft_names(tx, burn_names, nft_pid)
  and {
    (list.length(burn_names) > 0)?,
    (list.length(ibond) == list.length(burn_names))?,
  }
}

pub fn burning_force_redeem(tx: Transaction, bond_pid: PolicyId) -> Bool {
  let burn_names = get_burn_token_names(tx, bond_pid)
  (list.length(burn_names) > 0)?
}

pub fn minting_without_fee(
  cfg: BondIssueConfig,
  tx: Transaction,
  req_skh: ScriptKeyHash,
  bond_skh: ScriptKeyHash,
  nft_pid: PolicyId,
  bond_pid: PolicyId,
  out_ref: OutputReference,
) -> Bool {
  let mint_value = value.from_minted_value(tx.mint)
  let mint_bond_tokens = value.tokens(mint_value, bond_pid)
  let mint_nft_tokens = value.tokens(mint_value, nft_pid)
  if and {
    (dict.size(mint_bond_tokens) == dict.size(mint_nft_tokens))?,
    (list.at(
      list.difference(dict.keys(mint_bond_tokens), dict.keys(mint_nft_tokens)),
      0,
    ) == None)?,
  } {
    let req_pk = ScriptCredential(req_skh)
    when
      list.foldl(
        tx.inputs,
        (None, None),
        fn(i, z) {
          if and {
            i.output_reference == out_ref,
            i.output.address.payment_credential == req_pk,
          } {
            expect sreq_dt: RequestDatum =
              when i.output.datum is {
                InlineDatum(d) -> d
                _ -> fail @"only supports InlineDatum for request"
              }
            if and {
              // (value.quantity_of(i.output.value, req_pid, sreq_dt.borrower) == 1)?,
              (i.output.address.stake_credential != None)?,
              (sreq_dt.apr >= cfg.platform.min_apr)?,
              (sreq_dt.duration >= cfg.platform.min_duration)?,
              (sreq_dt.requested >= cfg.platform.min_requested)?,
              (sreq_dt.buffer >= cfg.platform.min_buffer)?,
              (sreq_dt.prepaid >= math.min(
                sreq_dt.buffer + cfg.platform.prepaid_plus,
                sreq_dt.duration,
              ))?,
              (sreq_dt.prepaid <= sreq_dt.duration)?,
              (sreq_dt.fee >= cfg.platform.fee)?,
              (sreq_dt.requested >= sreq_dt.issued)?,
              (sreq_dt.epo_rewards >= ( sreq_dt.requested - sreq_dt.issued ) * cfg.platform.bond_face_value * sreq_dt.apr / cfg.basis.base / cfg.epoch.year_to_epoch)?,
            } {
              if z.1st == None {
                (Some(sreq_dt), Some(i))
              } else {
                fail @"borrow request is unique"
              }
            } else {
              z
            }
          } else {
            z
          }
        },
      )
    is {
      (Some(sreq_dt), Some(i)) -> {
        let bond_name = hash_out_ref_salt(out_ref, sreq_dt.borrower)
        let mint_qty = value.quantity_of(mint_value, bond_pid, bond_name)
        let bond_addr =
          Address {
            payment_credential: ScriptCredential(bond_skh),
            stake_credential: i.output.address.stake_credential,
          }
        when
          list.filter(
            tx.outputs,
            fn(o) {
              if o.address == bond_addr {
                expect obond_dt: BondDatum =
                  when o.datum is {
                    InlineDatum(d) -> d
                    _ ->
                      fail @"borrow_position/bond_nft.minting: only supports InlineDatum for bond"
                  }
                and {
                  (obond_dt.borrower == sreq_dt.borrower)?,
                  (mint_qty == obond_dt.bond_amount)?,
                  (value.quantity_of(o.value, nft_pid, bond_name) == 1)?,
                }
              } else {
                False
              }
            },
          )
        is {
          [_o] -> True
          _ -> fail @"not found borrow request output"
        }
      }
      _ -> fail @"not found borrow request input"
    }
  } else {
    fail
  }
}

pub fn minting_with_fee(
  cfg: BondIssueConfig,
  tx: Transaction,
  req_skh: ScriptKeyHash,
  bond_skh: ScriptKeyHash,
  bond_pid: PolicyId,
) -> Bool {
  let req_pk = ScriptCredential(req_skh)
  let prepaid_ireqs =
    list.foldl(
      tx.inputs,
      dict.new(),
      fn(i, z) {
        if i.output.address.payment_credential == req_pk {
          expect ireq_dt: RequestDatum =
            when i.output.datum is {
              InlineDatum(d) -> d
              _ -> fail @"only supports InlineDatum for request"
            }
          if !dict.has_key(z, ireq_dt.borrower) {
            dict.insert(
              z,
              key: ireq_dt.borrower,
              value: ireq_dt.prepaid,
              compare: bytearray.compare,
            )
          } else {
            fail @"borrow request is unique"
          }
        } else {
          z
        }
      },
    )

  let bond_pk = ScriptCredential(bond_skh)
  let mint_value = value.from_minted_value(tx.mint) |> value.tokens(bond_pid)
  let (dist_names, total_fee, ofee) =
    list.foldl(
      tx.outputs,
      ([], 0, 0),
      fn(o, z) {
        if o.address.payment_credential == bond_pk {
          expect obond_dt: BondDatum =
            when o.datum is {
              InlineDatum(d) -> d
              _ -> fail @"only supports InlineDatum for bond"
            }
          let bond_qty =
            dict.get(mint_value, obond_dt.token_name) |> option.or_else(0)
          if (bond_qty == obond_dt.bond_amount)? {
            when dict.get(prepaid_ireqs, obond_dt.borrower) is {
              Some(prepaid) -> {
                let fee_amt =
                  value.lovelace_of(obond_dt.epo_rewards) * prepaid * obond_dt.fee / cfg.basis.base

                ([obond_dt.token_name, ..z.1st], z.2nd + fee_amt, z.3rd)
              }
              _ -> fail @"not found request input matching with bond output"
            }
          } else {
            fail
          }
        } else if o.address == cfg.platform.address {
          if (z.3rd == 0)? {
            (z.1st, z.2nd, value.lovelace_of(o.value))
          } else {
            fail @"only 1 platform fee output is allowed"
          }
        } else {
          z
        }
      },
    )
  let mint_names = mint_value |> dict.keys()

  and {
    // must pay the correct fees to the platform
    (ofee >= total_fee)?,
    // bond mint must matching with bond output
    (list.at(list.difference(mint_names, dist_names), 0) == None)?,
  }
}
