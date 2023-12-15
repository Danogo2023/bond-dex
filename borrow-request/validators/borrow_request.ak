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
      RequestCreate { out_ref, sk: req_skh } -> {
        expect Mint(req_pid) = ctx.purpose
        constraint.minting(cfg, ctx.transaction, req_pid, out_ref, req_skh)
      }
      _ -> fail @"invalid action"
    }
  }
}

validator(
  cfg: BondIssueConfig,
  bond_skh: ScriptKeyHash,
  nft_pid: PolicyId,
  bond_pid: PolicyId,
) {
  fn spend(sdt: RequestDatum, ac: RequestAction, ctx: ScriptContext) -> Bool {
    when ac is {
      BondCreate { out_ref } -> {
        let (sreq, out_ref_input) = get_out_ref(ctx, out_ref)
        constraint.spending_bond_create(
          cfg,
          ctx.transaction,
          sreq,
          sdt,
          out_ref_input,
          bond_skh,
          nft_pid,
          bond_pid,
        )
      }
      RequestUpdate ->
        constraint.spending_request_update(
          cfg,
          ctx.transaction,
          get_spending_input(ctx),
          sdt,
        )
      _ -> fail @"invalid action"
    }
  }
}
