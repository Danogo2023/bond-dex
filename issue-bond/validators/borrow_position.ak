use aiken/transaction.{Mint, ScriptContext}
use aiken/transaction/value.{PolicyId}
use bond_issue/types.{BondDatum, BondIssueConfig} as bond_issue_types
use borrow_position/bond_nft
use borrow_position/bond_token
use borrow_position/change_stake_key
use borrow_position/pay_interest
use borrow_position/redeem
use borrow_position/types.{
  BondAction, BondChangeStakeKey, BondCreate, BondPayInterest, BondRedeem,
}
use common/util.{get_spending_input}

validator {
  fn mint_nft(ac: BondAction, ctx: ScriptContext) -> Bool {
    expect Mint(nft_pid) = ctx.purpose
    let tx = ctx.transaction
    when ac is {
      BondCreate { bond_skh, .. } -> bond_nft.minting(tx, bond_skh, nft_pid)
      BondRedeem { .. } -> bond_nft.burning(tx, nft_pid)
      _ -> fail @"invalid action"
    }
  }
}

validator(cfg: BondIssueConfig) {
  fn mint_token(ac: BondAction, ctx: ScriptContext) -> Bool {
    expect Mint(bond_pid) = ctx.purpose
    let tx = ctx.transaction
    when ac is {
      BondCreate { req_skh, bond_skh, .. } ->
        bond_token.minting(cfg, tx, req_skh, bond_skh, bond_pid)
      BondRedeem { .. } -> bond_token.burning(tx, bond_pid)
      _ -> fail @"invalid action"
    }
  }
}

validator(cfg: BondIssueConfig, borrower_pid: PolicyId, nft_pid: PolicyId) {
  fn spend_position(sdt: BondDatum, ac: BondAction, ctx: ScriptContext) -> Bool {
    let sbond = get_spending_input(ctx).output
    let addr = sbond.address
    let tx = ctx.transaction
    when ac is {
      BondRedeem { .. } -> redeem.spending(cfg, tx, sbond, addr, sdt, nft_pid)
      BondPayInterest -> pay_interest.spending(cfg, tx, addr, nft_pid)
      BondChangeStakeKey ->
        change_stake_key.spending(tx, sbond, addr, sdt, borrower_pid, nft_pid)
      _ -> fail @"invalid action"
    }
  }
}
