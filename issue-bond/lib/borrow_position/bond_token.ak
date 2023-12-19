use aiken/bytearray
use aiken/dict
use aiken/list
use aiken/option
use aiken/transaction.{InlineDatum, Transaction}
use aiken/transaction/credential.{ScriptCredential}
use aiken/transaction/value.{PolicyId}
use bond_issue/types.{BondDatum, BondIssueConfig, RequestDatum}
use common/types.{ScriptKeyHash} as common_types

pub fn minting_without_fee(
  _cfg: BondIssueConfig,
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
  let dist_names =
    list.foldl(
      tx.outputs,
      [],
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
              Some(_) ->
                [obond_dt.token_name, ..z]
              _ -> fail @"not found request input matching with bond output"
            }
          } else {
            fail
          }
        } else {
          z
        }
      },
    )
  let mint_names = mint_value |> dict.keys()
  // bond mint must matching with bond output
  (list.at(list.difference(mint_names, dist_names), 0) == None)?
}

pub fn minting(
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

pub fn burning(tx: Transaction, bond_pid: PolicyId) -> Bool {
  let burn_names =
    dict.foldl(
      value.from_minted_value(tx.mint) |> value.tokens(bond_pid),
      [],
      fn(n, q, z) {
        if (q < 0)? {
          [n, ..z]
        } else {
          fail
        }
      },
    )
  (list.at(burn_names, 0) != None)?
}
