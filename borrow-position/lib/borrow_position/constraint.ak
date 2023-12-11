use aiken/list
use aiken/transaction.{Transaction}
use aiken/transaction/value.{PolicyId}
use bond_issue/types.{BondIssueConfig} as bond_issue_types
use borrow_position/utils.{
  get_bond_mint, get_bond_output, get_borrow_request_input,
}
use common/types.{ScriptKeyHash} as common_types

pub fn minting_nft(
  _cfg: BondIssueConfig,
  tx: Transaction,
  nft_pid: PolicyId,
  req_sk: ScriptKeyHash,
  bond_sk: ScriptKeyHash,
) -> Bool {
  let ireqs = get_borrow_request_input(tx, req_sk)
  let obonds = get_bond_output(tx, nft_pid, bond_sk)
  let mint = get_bond_mint(tx, nft_pid)
  and {
    // must found bond output
    (obonds.count > 0)?,
    // must found mint nft
    (mint.count > 0)?,
    (obonds.count == mint.count)?,
    // request input count must equal bond output count
    (ireqs.count > 0)?,
    (obonds.count == ireqs.count)?,
    // bond nft in output must matching with bond nft minting
    (list.length(list.difference(mint.tokens, obonds.tokens)) <= 0)?,
    // bond name in bond output must matching with bond name of request input
    (list.length(list.difference(ireqs.tokens, obonds.tokens)) <= 0)?,
  }
}
