use aiken/transaction.{Mint, ScriptContext}
use bond_issue/types.{BondIssueConfig} as bond_issue_types
use borrow_position/constraint
use borrow_position/types.{BondAction, BondCreate}

validator(cfg: BondIssueConfig) {
  fn mint_nft(ac: BondAction, ctx: ScriptContext) -> Bool {
    expect Mint(pid) = ctx.purpose
    when ac is {
      BondCreate { req_sk, bond_sk } ->
        constraint.minting_nft(cfg, ctx.transaction, req_sk, bond_sk, pid)
      _ -> fail @"invalid action"
    }
  }
}
