use aiken/transaction.{Mint, ScriptContext}
use aiken/transaction/value.{PolicyId}
use bond_issue/types.{BondIssueConfig, RequestDatum} as bond_issue_types
use borrow_request/bond_create
use borrow_request/borrower_nft
use borrow_request/request_nft
use borrow_request/request_update
use borrow_request/types.{
  BondCreate, RequestAction, RequestCreate, RequestUpdate,
}
use common/types.{ScriptKeyHash} as common_types
use common/util.{get_spending_input}

validator {
  fn mint_request(ac: RequestAction, ctx: ScriptContext) -> Bool {
    expect Mint(req_pid) = ctx.purpose
    let tx = ctx.transaction
    when ac is {
      RequestCreate { out_ref, .. } ->
        request_nft.create_simple(tx, req_pid, out_ref)
      BondCreate -> request_nft.burning(tx, req_pid)
      _ -> fail @"invalid action"
    }
  }
}

validator {
  fn mint_borrower(ac: RequestAction, ctx: ScriptContext) -> Bool {
    when ac is {
      // pid: req_pid
      RequestCreate { out_ref, .. } -> {
        expect Mint(borrower_pid) = ctx.purpose
        borrower_nft.create_simple(ctx.transaction, borrower_pid, out_ref)
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
  req_pid: PolicyId,
) {
  fn spend_request(
    sdt: RequestDatum,
    ac: RequestAction,
    ctx: ScriptContext,
  ) -> Bool {
    when ac is {
      BondCreate ->
        bond_create.spending(
          cfg,
          ctx,
          sdt,
          bond_skh,
          nft_pid,
          bond_pid,
          req_pid,
        )
      RequestUpdate ->
        request_update.spending(
          cfg,
          ctx.transaction,
          get_spending_input(ctx),
          sdt,
          req_pid,
        )
      _ -> fail @"invalid action"
    }
  }
}
