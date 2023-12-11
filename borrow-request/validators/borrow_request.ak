use aiken/transaction.{Mint, ScriptContext}
use aiken/transaction/value.{PolicyId}
use bond_issue/types.{BondIssueConfig, RequestDatum} as bond_issue_types
use borrow_request/constraint
use borrow_request/types.{
  BondCreate, RequestAction, RequestCreate, RequestUpdate,
}
use common/types.{ScriptKeyHash} as common_types
use common/util.{get_spending_input}

validator(cfg: BondIssueConfig) {
  fn mint(ac: RequestAction, ctx: ScriptContext) -> Bool {
    expect Mint(pid) = ctx.purpose
    when ac is {
      RequestCreate { sk } -> constraint.minting(cfg, ctx.transaction, pid, sk)
      _ -> fail @"invalid action"
    }
  }
}

validator(
  cfg: BondIssueConfig,
  bond_sk: ScriptKeyHash,
  nft_pid: PolicyId,
  bond_pid: PolicyId,
) {
  fn spend(idt: RequestDatum, ac: RequestAction, ctx: ScriptContext) -> Bool {
    if ac == RequestUpdate || ac == BondCreate {
      let ireq = get_spending_input(ctx)
      if ac == RequestUpdate {
        constraint.spending_request_update(cfg, ctx.transaction, ireq, idt)
      } else {
        constraint.spending_bond_create(
          cfg,
          ctx.transaction,
          ireq,
          idt,
          bond_sk,
          nft_pid,
          bond_pid,
        )
      }
    } else {
      fail @"invalid action"
    }
  }
}
