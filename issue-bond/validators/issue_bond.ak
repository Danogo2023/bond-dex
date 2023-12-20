use aiken/transaction.{Mint, ScriptContext}
use aiken/transaction/value.{PolicyId}
use bond_issue/types.{BondDatum, BondIssueConfig, RequestDatum}
use borrow_position/bond_nft
use borrow_position/bond_token
use borrow_position/change_stake_key
use borrow_position/pay_interest
use borrow_position/redeem_bond
use borrow_position/redeem_fee
use borrow_position/redeem_force
use borrow_request/bond_create
use borrow_request/borrower_nft
use borrow_request/request_nft
use borrow_request/request_update
use common/types.{ScriptKeyHash} as common_types
use common/util.{get_spending_input}
use issue_bond/types.{
  BondChangeStakeKey, BondCreate, BondIssueAction, BondPayInterest, BondRedeem,
  ForceRedeem, RedeemFee, RequestCreate, RequestUpdate,
} as issue_bond_types

validator {
  fn mint_nft(ac: BondIssueAction, ctx: ScriptContext) -> Bool {
    expect Mint(nft_pid) = ctx.purpose
    let tx = ctx.transaction
    when ac is {
      BondCreate { bond_skh, .. } -> bond_nft.minting(tx, bond_skh, nft_pid)
      BondRedeem { .. } -> bond_nft.burning(tx, nft_pid)
      RedeemFee | ForceRedeem -> bond_nft.burning(tx, nft_pid)
      _ -> fail @"invalid action"
    }
  }
}

validator(cfg: BondIssueConfig) {
  fn mint_token(ac: BondIssueAction, ctx: ScriptContext) -> Bool {
    expect Mint(bond_pid) = ctx.purpose
    let tx = ctx.transaction
    when ac is {
      BondCreate { req_skh, bond_skh, .. } ->
        bond_token.minting_without_fee(cfg, tx, req_skh, bond_skh, bond_pid)
      BondRedeem { .. } -> bond_token.burning(tx, bond_pid)
      _ -> fail @"invalid action"
    }
  }
}

validator(
  cfg: BondIssueConfig,
  borrower_pid: PolicyId,
  nft_pid: PolicyId,
  num_epoch_force: Int,
) {
  fn spend_position(
    sdt: BondDatum,
    ac: BondIssueAction,
    ctx: ScriptContext,
  ) -> Bool {
    let sbond = get_spending_input(ctx).output
    let addr = sbond.address
    let tx = ctx.transaction
    when ac is {
      BondRedeem { .. } ->
        redeem_bond.spending_with_fee(cfg, tx, sbond, addr, sdt, nft_pid)
      BondPayInterest ->
        pay_interest.spending_without_fee(tx, sbond, addr, sdt, nft_pid)
      BondChangeStakeKey ->
        change_stake_key.spending(tx, sbond, addr, sdt, nft_pid, borrower_pid)
      RedeemFee -> redeem_fee.spending(cfg, tx, sbond, addr, sdt, nft_pid)
      ForceRedeem ->
        redeem_force.spending(
          cfg,
          tx,
          sbond,
          addr,
          sdt,
          nft_pid,
          num_epoch_force,
        )
      _ -> fail @"invalid action"
    }
  }
}

validator {
  fn mint_request(ac: BondIssueAction, ctx: ScriptContext) -> Bool {
    expect Mint(req_pid) = ctx.purpose
    let tx = ctx.transaction
    when ac is {
      RequestCreate { out_ref, .. } ->
        request_nft.create_simple(tx, req_pid, out_ref)
      BondCreate { .. } -> request_nft.burning(tx, req_pid)
      RequestUpdate -> request_nft.burning(tx, req_pid)
      _ -> fail @"invalid action"
    }
  }
}

validator {
  fn mint_borrower(ac: BondIssueAction, ctx: ScriptContext) -> Bool {
    when ac is {
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
    ac: BondIssueAction,
    ctx: ScriptContext,
  ) -> Bool {
    when ac is {
      BondCreate { .. } ->
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
        request_update.spending(cfg, ctx.transaction, sdt, req_pid)
      _ -> fail @"invalid action"
    }
  }
}
