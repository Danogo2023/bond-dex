use aiken/bytearray
use aiken/dict.{Dict}
use aiken/list
use aiken/transaction.{InlineDatum, Output, Transaction}
use aiken/transaction/credential.{Address}
use aiken/transaction/value.{PolicyId}
use bond_issue/types.{BondDatum, BondIssueConfig} as bond_issue_types
use borrow_position/utils_spend

pub fn spending(
  cfg: BondIssueConfig,
  tx: Transaction,
  sbond_addr: Address,
  nft_pid: PolicyId,
) -> Bool {
  // let ibond_lovelace = value.lovelace_of(sbond.output.value)
  let ibonds = get_bond_inputs(tx, sbond_addr, nft_pid)
  let (obonds, ofee) = get_bond_outputs(cfg, tx, sbond_addr, nft_pid)

  and {
    (ofee != None)?,
    (list.at(list.difference(dict.keys(ibonds), dict.keys(obonds)), 0) == None)?,
    utils_spend.fee_pay_interest_valid(cfg, ibonds, obonds, ofee),
  }
}

pub fn get_bond_inputs(
  tx: Transaction,
  bond_addr: Address,
  nft_pid: PolicyId,
) -> Dict<ByteArray, (BondDatum, Output, Int)> {
  list.foldr(
    tx.inputs,
    dict.new(),
    fn(i, z) {
      if and {
        i.output.address.payment_credential == bond_addr.payment_credential,
        list.at(i.output.value |> value.tokens(nft_pid) |> dict.to_list(), 0) != None,
      } {
        expect ibond_dt: BondDatum =
          when i.output.datum is {
            InlineDatum(d) -> d
            _ ->
              fail @"borrow_position/utils_spend.get_bond_inputs: only supports InlineDatum for bond"
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
  bond_addr: Address,
  nft_pid: PolicyId,
) -> (Dict<ByteArray, (BondDatum, Output, Int)>, Option<Output>) {
  list.foldr(
    tx.outputs,
    (dict.new(), None),
    fn(o, z) {
      if and {
        o.address.payment_credential == bond_addr.payment_credential,
        list.at(o.value |> value.tokens(nft_pid) |> dict.to_list(), 0) != None,
      } {
        expect obond_dt: BondDatum =
          when o.datum is {
            InlineDatum(d) -> d
            _ ->
              fail @"borrow_position/utils_spend.get_bond_outputs: only supports InlineDatum for bond"
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
      } else if o.address == cfg.platform.address {
        if (z.2nd == None)? {
          (z.1st, Some(o))
        } else {
          fail @"borrow_position/utils_spend.get_bond_outputs: only 1 platform fee output is allowed"
        }
      } else {
        z
      }
    },
  )
}
