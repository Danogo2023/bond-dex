use aiken/transaction.{Output, OutputReference}
use aiken/transaction/value.{PolicyId}
use common/types.{ScriptKeyHash}

// (output_request_valid, found_borrower_nft)
pub type BorrowRequestOutput =
  (Bool, Bool)

// (request_valid, bond_output, mint_qty)
pub type BondCreateOutput =
  (Bool, Option<Output>, Int)

pub type RequestAction {
  // mint request nft => RequestCreate { out_ref, req_skh, borrower_pid }
  // mint borrower nft => RequestCreate { out_ref, req_skh, request_pid }
  RequestCreate {
    out_ref: OutputReference,
    req_skh: ScriptKeyHash,
    pid: PolicyId,
  }
  RequestUpdate
  BondCreate
}
