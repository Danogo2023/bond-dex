use aiken/transaction.{Mint, ScriptContext}
use bond_issue/types.{BondIssueConfig} as bond_issue_types
use borrow_position/constraint
use borrow_position/types.{BondAction, BondCreate, BondRedeem}

validator {
  fn mint_nft(ac: BondAction, ctx: ScriptContext) -> Bool {
    expect Mint(nft_pid) = ctx.purpose
    when ac is {
      BondCreate { out_ref, req_sk, bond_sk, .. } ->
        constraint.minting_nft(
          ctx.transaction,
          out_ref,
          req_sk,
          bond_sk,
          nft_pid,
        )
      BondRedeem { pid } ->
        constraint.burning_nft(ctx.transaction, nft_pid, pid)
      _ -> fail @"invalid action"
    }
  }
}

validator(cfg: BondIssueConfig) {
  fn mint_token(ac: BondAction, ctx: ScriptContext) -> Bool {
    expect Mint(bond_pid) = ctx.purpose
    when ac is {
      BondCreate { out_ref, req_sk, bond_sk, pid } ->
        constraint.minting_token(
          cfg,
          ctx.transaction,
          out_ref,
          req_sk,
          bond_sk,
          pid,
          bond_pid,
        )
      BondRedeem { pid } ->
        constraint.burning_token(ctx.transaction, pid, bond_pid)
      _ -> fail @"invalid action"
    }
  }
}
