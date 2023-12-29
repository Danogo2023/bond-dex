use aiken/bytearray
use aiken/dict.{Dict}
use aiken/list
use aiken/transaction.{InlineDatum, Output, Transaction}
use aiken/transaction/credential.{Address}
use aiken/transaction/value.{PolicyId}
use bond_issue/types.{BondDatum, BondIssueConfig} as bond_issue_types

pub fn spending_without_fee(
  tx: Transaction,
  sbond: Output,
  sbond_addr: Address,
  sbond_dt: BondDatum,
  nft_pid: PolicyId,
) -> Bool {
  when
    list.filter(
      tx.outputs,
      fn(o) {
        o.address == sbond_addr && //
        value.quantity_of(o.value, nft_pid, sbond_dt.token_name) == 1
      },
    )
  is {
    [obond] -> {
      expect obond_dt: BondDatum =
        when obond.datum is {
          InlineDatum(d) -> d
          _ ->
            fail @"borrow_position/pay_interest.spending_without_fee: only supports InlineDatum for bond"
        }
      let (sbond_assets, obond_assets) =
        (
          value.without_lovelace(sbond.value),
          value.without_lovelace(obond.value),
        )
      let (sbond_lovelace, obond_lovelace) =
        (value.lovelace_of(sbond.value), value.lovelace_of(obond.value))

      let interest = obond_lovelace - sbond_lovelace
      let interest_min = value.lovelace_of(sbond_dt.epo_rewards)
      let interest_max = interest_min * sbond_dt.duration
      and {
        (obond_assets == sbond_assets)?,
        (obond_dt.epo_rewards == sbond_dt.epo_rewards)?,
        (obond_dt.duration == sbond_dt.duration)?,
        (obond_dt.bond_symbol == sbond_dt.bond_symbol)?,
        (obond_dt.token_name == sbond_dt.token_name)?,
        (obond_dt.bond_amount == sbond_dt.bond_amount)?,
        (obond_dt.buffer == sbond_dt.buffer)?,
        (obond_dt.fee == sbond_dt.fee)?,
        (obond_dt.borrower == sbond_dt.borrower)?,
        (obond_dt.start == sbond_dt.start)?,
        (interest > 0)?,
        (interest >= interest_min)?,
        (interest <= interest_max)?,
      }
    }
    _ -> fail @"bond output invalid"
  }
}

pub fn spending_with_fee(
  cfg: BondIssueConfig,
  tx: Transaction,
  sbond_addr: Address,
  nft_pid: PolicyId,
) -> Bool {
  let ibonds = get_bond_inputs(tx, sbond_addr, nft_pid)
  let (obonds, ofee) = get_bond_outputs(cfg, tx, sbond_addr, nft_pid)

  and {
    (ofee != None)?,
    (list.difference(dict.keys(ibonds), dict.keys(obonds)) == [])?,
    fee_pay_interest_valid(cfg, ibonds, obonds, ofee),
  }
}

pub fn get_bond_inputs(
  tx: Transaction,
  sbond_addr: Address,
  nft_pid: PolicyId,
) -> Dict<ByteArray, (BondDatum, Output, Int)> {
  list.foldr(
    tx.inputs,
    dict.new(),
    fn(i, z) {
      if and {
        i.output.address.payment_credential == sbond_addr.payment_credential,
        list.at(i.output.value |> value.tokens(nft_pid) |> dict.to_list(), 0) != None,
      } {
        expect ibond_dt: BondDatum =
          when i.output.datum is {
            InlineDatum(d) -> d
            _ ->
              fail @"borrow_position/pay_interest.get_bond_inputs: only supports InlineDatum for bond"
          }
        when dict.get(z, ibond_dt.token_name) is {
          Some(_) -> fail @"bond is unique"
          _ ->
            dict.insert(
              z,
              ibond_dt.token_name,
              (ibond_dt, i.output, 0),
              bytearray.compare,
            )
        }
      } else {
        z
      }
    },
  )
}

pub fn get_bond_outputs(
  cfg: BondIssueConfig,
  tx: Transaction,
  sbond_addr: Address,
  nft_pid: PolicyId,
) -> (Dict<ByteArray, (BondDatum, Output, Int)>, Option<Output>) {
  list.foldr(
    tx.outputs,
    (dict.new(), None),
    fn(o, z) {
      if and {
        o.address.payment_credential == sbond_addr.payment_credential,
        list.at(o.value |> value.tokens(nft_pid) |> dict.to_list(), 0) != None,
      } {
        expect obond_dt: BondDatum =
          when o.datum is {
            InlineDatum(d) -> d
            _ ->
              fail @"borrow_position/pay_interest.get_bond_outputs: only supports InlineDatum for bond"
          }
        when dict.get(z.1st, obond_dt.token_name) is {
          Some(_) -> fail @"bond is unique"
          _ ->
            (
              dict.insert(
                z.1st,
                obond_dt.token_name,
                (obond_dt, o, 0),
                bytearray.compare,
              ),
              z.2nd,
            )
        }
      } else if o.address == cfg.platform.fee_addr {
        if (z.2nd == None)? {
          (z.1st, Some(o))
        } else {
          fail @"borrow_position/pay_interest.get_bond_outputs: only 1 platform fee output is allowed"
        }
      } else {
        z
      }
    },
  )
}

pub fn fee_pay_interest_valid(
  cfg: BondIssueConfig,
  ibond_utxos: Dict<ByteArray, (BondDatum, Output, Int)>,
  obond_utxos: Dict<ByteArray, (BondDatum, Output, Int)>,
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
            let (ibond_dt, ibond, _) = v1
            // v2 => obond
            let (obond_dt, obond, _) = v2

            let (ibond_lovelace, obond_lovelace) =
              (value.lovelace_of(ibond.value), value.lovelace_of(obond.value))
            let (ibond_assets, obond_assets) =
              (
                value.without_lovelace(ibond.value),
                value.without_lovelace(obond.value),
              )

            if and {
              (obond.address == ibond.address)?,
              (obond_assets == ibond_assets)?,
              (obond_dt.epo_rewards == ibond_dt.epo_rewards)?,
              (obond_dt.duration == ibond_dt.duration)?,
              (obond_dt.bond_symbol == ibond_dt.bond_symbol)?,
              (obond_dt.token_name == ibond_dt.token_name)?,
              (obond_dt.bond_amount == ibond_dt.bond_amount)?,
              (obond_dt.buffer == ibond_dt.buffer)?,
              (obond_dt.fee == ibond_dt.fee)?,
              (obond_dt.borrower == ibond_dt.borrower)?,
              (obond_dt.start == ibond_dt.start)?,
            } {
              let epo_rewards = value.lovelace_of(ibond_dt.epo_rewards)
              let interest = obond_lovelace - ibond_lovelace
              let interest_rate = cfg.basis.base - ibond_dt.fee
              let interest_min = epo_rewards * interest_rate / cfg.basis.base
              let interest_max =
                epo_rewards * interest_rate * ibond_dt.duration / cfg.basis.base

              if and {
                (interest > 0)?,
                (interest >= interest_min)?,
                (interest <= interest_max)?,
              } {
                Some(
                  (obond_dt, obond, interest * ibond_dt.fee / cfg.basis.base),
                )
              } else {
                fail
              }
            } else {
              fail @"borrow_position/pay_interest.fee_pay_interest_valid: bond output invalid"
            }
          },
          bytearray.compare,
        )
      let total_fee =
        dict.foldr(
          obond_data,
          0,
          fn(_, v, z) {
            let (_, _, f) = v
            z + f
          },
        )
      (value.lovelace_of(o.value) >= total_fee)?
    }
    _ ->
      fail @"borrow_position/pay_interest.fee_pay_interest_valid: not found platform fee output"
  }
}
