use aiken/transaction.{Output}

// (output_request_valid, found_borrower_nft)
pub type BorrowRequestOutput =
  (Bool, Bool)

// (request_valid, bond_output, mint_qty)
pub type BondCreateOutput =
  (Bool, Option<Output>, Int)
