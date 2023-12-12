use aiken/transaction.{Mint, ScriptContext}
use aiken/transaction/value.{PolicyId}
use bond_issue/types.{BondIssueConfig, RequestDatum} as bond_issue_types
use borrow_request/constraint
use borrow_request/types.{
  BondCreate, RequestAction, RequestCreate, RequestUpdate,
}
use borrow_request/utils.{get_out_ref}
use common/types.{ScriptKeyHash} as common_types
use common/util.{get_spending_input}

validator(cfg: BondIssueConfig) {
  fn mint(ac: RequestAction, ctx: ScriptContext) -> Bool {
    when ac is {
      RequestCreate { out_ref, sk } -> {
        expect Mint(pid) = ctx.purpose
        constraint.minting(cfg, ctx.transaction, pid, out_ref, sk)
      }
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
    when ac is {
      BondCreate { out_ref } -> {
        let (ireq, out_ref_input) = get_out_ref(ctx, out_ref)
        constraint.spending_bond_create(
          cfg,
          ctx.transaction,
          ireq,
          idt,
          out_ref_input,
          bond_sk,
          nft_pid,
          bond_pid,
        )
      }
      RequestUpdate ->
        constraint.spending_request_update(
          cfg,
          ctx.transaction,
          get_spending_input(ctx),
          idt,
        )
      _ -> fail @"invalid action"
    }
  }
}
