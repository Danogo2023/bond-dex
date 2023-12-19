use aiken/dict
use aiken/list
use aiken/transaction.{OutputReference, Transaction}
use aiken/transaction/credential.{ScriptCredential}
use aiken/transaction/value.{PolicyId}
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
  (list.at(burn_names, 0) != None)?
}

pub fn create_simple(
  tx: Transaction,
  req_pid: PolicyId,
  out_ref: OutputReference,
) -> Bool {
  let mint_names =
    dict.foldl(
      value.from_minted_value(tx.mint) |> value.tokens(req_pid),
      [],
      fn(n, q, z) {
        if (q == 1)? {
          [n, ..z]
        } else {
          fail
        }
      },
    )

  let borrower = hash_out_ref(get_input_out_ref(tx.inputs, out_ref))
  list.has(mint_names, borrower)?
  // let mint_qty =
  //   value.quantity_of(value.from_minted_value(tx.mint), req_pid, borrower)
  // (mint_qty == 1)?
}

pub fn create(
  tx: Transaction,
  req_pid: PolicyId,
  out_ref: OutputReference,
  req_skh: ScriptKeyHash,
  borrower_pid: PolicyId,
) -> Bool {
  let req_credential = ScriptCredential(req_skh)
  let req_outputs =
    list.foldl(
      tx.outputs,
      [],
      fn(o, z) {
        if o.address.payment_credential == req_credential {
          if list.at(z, 0) == None {
            [o, ..z]
          } else {
            fail @"must only one request output"
          }
        } else {
          z
        }
      },
    )
  when req_outputs is {
    [o] -> {
      let borrower = hash_out_ref(get_input_out_ref(tx.inputs, out_ref))
      // let oreq_request_nft_qty = value.quantity_of(o.value, req_pid, borrower)
      let mint_qty_valid =
        dict.foldr(
          value.from_minted_value(tx.mint) |> value.to_dict,
          0,
          fn(p, a, z) {
            if p == req_pid || p == borrower_pid {
              dict.foldr(
                a,
                z,
                fn(n, q, xs) {
                  if n == borrower {
                    if (q == 1)? {
                      xs + 1
                    } else {
                      fail
                    }
                  } else {
                    xs
                  }
                },
              )
            } else {
              z
            }
          },
        )
      and {
        (value.quantity_of(o.value, req_pid, borrower) == 1)?,
        (mint_qty_valid == 2)?,
      }
    }
    _ ->
      fail @"borrow_request/request_nft.create: only 1 request output is allowed"
  }
}
