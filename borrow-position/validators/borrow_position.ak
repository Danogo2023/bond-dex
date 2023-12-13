use aiken/transaction.{Mint, ScriptContext}
use aiken/transaction/value.{PolicyId}
use bond_issue/types.{BondDatum, BondIssueConfig} as bond_issue_types
use borrow_position/constraint
use borrow_position/types.{
  BondAction, BondChangeStakeKey, BondCreate, BondPayInterest, BondRedeem,
}
use common/util.{get_spending_input}

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

validator(cfg: BondIssueConfig, req_pid: PolicyId, nft_pid: PolicyId) {
  fn spend(sdt: BondDatum, ac: BondAction, ctx: ScriptContext) -> Bool {
    when ac is {
      BondRedeem { .. } | BondPayInterest | BondChangeStakeKey -> {
        let sbond = get_spending_input(ctx)
        let sbond_addr = sbond.output.address
        if ac == BondPayInterest {
          constraint.spending_pay_interest(cfg, ctx.transaction, sbond_addr)
        } else if ac == BondChangeStakeKey {
          constraint.spending_change_stake_key(
            ctx.transaction,
            sbond,
            sbond_addr,
            sdt,
            req_pid,
          )
        } else {
          constraint.spending_redeem(
            cfg,
            ctx.transaction,
            sbond,
            sbond_addr,
            sdt,
            nft_pid,
          )
        }
      }
      _ -> fail @"invalid action"
    }
  }
}
