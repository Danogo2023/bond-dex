use aiken/dict
use aiken/list
use aiken/transaction.{InlineDatum, Transaction}
use aiken/transaction/credential.{ScriptCredential}
use aiken/transaction/value.{PolicyId}
use bond_issue/types.{BondDatum} as bond_issue_types
use common/types.{ScriptKeyHash}

pub fn minting(
  tx: Transaction,
  bond_skh: ScriptKeyHash,
  nft_pid: PolicyId,
) -> Bool {
  let mint_names =
    dict.foldl(
      value.from_minted_value(tx.mint) |> value.tokens(nft_pid),
      [],
      fn(n, q, z) {
        if (q == 1)? {
          [n, ..z]
        } else {
          fail
        }
      },
    )
  let bond_pk = ScriptCredential(bond_skh)
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
          if (value.quantity_of(o.value, nft_pid, obond_dt.token_name) == 1)? {
            [obond_dt.token_name, ..z]
          } else {
            fail
          }
        } else {
          z
        }
      },
    )
  (list.at(list.difference(mint_names, dist_names), 0) == None)?
}

pub fn burning(tx: Transaction, nft_pid: PolicyId) -> Bool {
  let burn_names =
    dict.foldl(
      value.from_minted_value(tx.mint) |> value.tokens(nft_pid),
      [],
      fn(n, q, z) {
        if (q == -1)? {
          [n, ..z]
        } else {
          fail
        }
      },
    )
  (list.at(burn_names, 0) != None)?
}
