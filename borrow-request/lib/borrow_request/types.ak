use aiken/transaction.{Output}
use bond_issue/types.{BondDatum} as bond_issue_types
use common/types.{ScriptKeyHash}

pub type BorrowRequestOutput {
  // oreq_valid = 0 => not found
  // oreq_valid = 1 => found and valid
  // oreq_valid = 2 => found and invalid
  oreq_valid: Int,
  nft_valid: Bool,
}

pub type BondCreateOutput {
  oreq_valid: Int,
  obond: Option<(BondDatum, Output)>,
  mint_qty: Int,
}

pub type RequestAction {
  RequestCreate { sk: ScriptKeyHash }
  RequestUpdate
  BondCreate
}
