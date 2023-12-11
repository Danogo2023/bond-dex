use aiken/bytearray
use aiken/dict
use aiken/list
use aiken/transaction.{InlineDatum, Transaction}
use aiken/transaction/credential.{ScriptCredential}
use aiken/transaction/value.{PolicyId}
use bond_issue/types.{BondDatum, RequestDatum} as bond_issue_types
use borrow_position/types.{BondMint, BondOutput, BorrowRequestOutput}
use common/hash_inputs.{hash_sorted_salt, sort_inputs}
use common/types.{ScriptKeyHash} as common_types

pub fn get_bond_mint(tx: Transaction, pid: PolicyId) -> BondMint {
  dict.foldr(
    value.from_minted_value(tx.mint) |> value.tokens(pid),
    BondMint { count: 0, tokens: [] },
    fn(k, v, z) { BondMint { count: z.count + v, tokens: [k, ..z.tokens] } },
  )
  // if (v == 1)? {
  // } else {
  //   fail @"only 1 bond nft can be mined"
  // }
}

pub fn get_borrow_request_input(
  tx: Transaction,
  req_sk: ScriptKeyHash,
) -> BorrowRequestOutput {
  let first_input = list.head(sort_inputs(tx.inputs))
  list.foldr(
    tx.inputs,
    BorrowRequestOutput { count: 0, tokens: [], data: dict.new() },
    fn(o, c) {
      if o.output.address.payment_credential == ScriptCredential(req_sk) {
        expect ireq_dt: RequestDatum =
          when o.output.datum is {
            InlineDatum(d) -> d
            _ -> fail @"only supports InlineDatum for request"
          }
        BorrowRequestOutput {
          data: dict.insert_with(
            c.data,
            ireq_dt.borrower,
            (ireq_dt, o.output),
            fn(_, _, _) {
              fail @"only 1 borrow request input is allowed for 1 borrow nft"
            },
            bytearray.compare,
          ),
          count: c.count + 1,
          tokens: [hash_sorted_salt(first_input, ireq_dt.borrower), ..c.tokens],
        }
      } else {
        c
      }
    },
  )
}

pub fn get_bond_output(
  tx: Transaction,
  nft_pid: PolicyId,
  bond_sk: ScriptKeyHash,
) -> BondOutput {
  list.foldr(
    tx.outputs,
    BondOutput { count: 0, tokens: [], data: dict.new() },
    fn(o, c) {
      if o.address.payment_credential == ScriptCredential(bond_sk) {
        expect obond_dt: BondDatum =
          when o.datum is {
            InlineDatum(d) -> d
            _ -> fail @"only supports InlineDatum for bond"
          }
        if (value.quantity_of(o.value, nft_pid, obond_dt.token_name) == 1)? {
          BondOutput {
            data: dict.insert_with(
              c.data,
              obond_dt.borrower,
              (obond_dt, o),
              fn(_, _, _) {
                fail @"only 1 nft mining is allowed"
              },
              bytearray.compare,
            ),
            count: c.count + 1,
            tokens: [obond_dt.token_name, ..c.tokens],
          }
        } else {
          fail @"each bond only contains 1 nft"
        }
      } else {
        c
      }
    },
  )
}
