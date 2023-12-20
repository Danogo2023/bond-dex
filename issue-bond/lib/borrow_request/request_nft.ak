use aiken/dict
use aiken/list
use aiken/transaction.{InlineDatum, OutputReference, Transaction}
use aiken/transaction/credential.{ScriptCredential}
use aiken/transaction/value.{PolicyId}
use bond_issue/types.{RequestDatum} as bond_issue_types
use borrow_request/utils.{get_input_out_ref}
use common/hash_out_refs.{hash_out_ref}
use common/types.{ScriptKeyHash} as common_types

pub fn burning(tx: Transaction, req_pid: PolicyId) -> Bool {
  let burn_names =
    dict.foldl(
      value.from_minted_value(tx.mint) |> value.tokens(req_pid),
      [],
      fn(n, q, z) {
        if (q == -1)? {
          [n, ..z]
        } else {
          fail
        }
      },
    )
  (list.length(burn_names) == 1)?
}

pub fn minting(
  tx: Transaction,
  req_skh: ScriptKeyHash,
  req_pid: PolicyId,
  borrower_pid: PolicyId,
  out_ref: OutputReference,
) -> Bool {
  let borrower = hash_out_ref(get_input_out_ref(tx.inputs, out_ref))
  let mint_qty =
    value.quantity_of(value.from_minted_value(tx.mint), req_pid, borrower)
  let req_pk = ScriptCredential(req_skh)
  and {
    (mint_qty == 1)?,
    when
      list.filter(
        tx.outputs,
        fn(o) {
          if o.address.payment_credential == req_pk {
            expect oreq_dt: RequestDatum =
              when o.datum is {
                InlineDatum(d) -> d
                _ -> fail @"only supports InlineDatum for borrow request"
              }
            and {
              (oreq_dt.symbol == borrower_pid)?,
              (oreq_dt.borrower == borrower)?,
              (value.quantity_of(o.value, req_pid, borrower) == 1)?,
            }
          } else {
            False
          }
        },
      )
    is {
      [_o] -> True
      _ -> fail @"not found borrow request output"
    },
  }
}
