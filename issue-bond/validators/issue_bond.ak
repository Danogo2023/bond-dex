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
  ForceRedeem, GarbageCollector, RedeemFee, RequestCreate, RequestUpdate,
} as issue_bond_types
use issue_bond/utils

// num deploy 1
validator(cfg: BondIssueConfig) {
  fn mint_borrower(ac: BondIssueAction, ctx: ScriptContext) -> Bool {
    expect Mint(borrower_pid) = ctx.purpose
    let tx = ctx.transaction
    when ac is {
      RequestCreate { out_ref, req_skh, pid: req_pid } ->
        borrower_nft.minting(cfg, tx, req_skh, req_pid, borrower_pid, out_ref)
      ForceRedeem { .. } -> borrower_nft.burning_force_redeem(tx, borrower_pid)
      _ ->
        fail @"minting borrower nft only support RequestCreate | ForceRedeem action"
    }
  }
}

// num deploy 2
validator(cfg: BondIssueConfig, borrower_pid: PolicyId, num_epoch_force: Int) {
  fn spend_position(d: Data, ac: BondIssueAction, ctx: ScriptContext) -> Bool {
    let tx = ctx.transaction
    if ac == GarbageCollector {
      utils.garbage_collector_position(d, tx, cfg)
    } else {
      expect sdt: BondDatum = d
      let sbond = get_spending_input(ctx).output
      let addr = sbond.address
      when ac is {
        BondRedeem { pid: nft_pid } ->
          redeem_bond.spending_with_fee(cfg, tx, sbond, addr, sdt, nft_pid)
        BondPayInterest { pid: nft_pid } ->
          pay_interest.spending_without_fee(tx, sbond, addr, sdt, nft_pid)
        BondChangeStakeKey { pid: nft_pid } ->
          change_stake_key.spending(tx, sbond, addr, sdt, nft_pid, borrower_pid)
        RedeemFee { pid: nft_pid } ->
          redeem_fee.spending(cfg, tx, sbond, addr, sdt, nft_pid)
        ForceRedeem { pid: nft_pid } ->
          redeem_force.spending(
            cfg,
            tx,
            sbond,
            addr,
            sdt,
            nft_pid,
            num_epoch_force,
          )
        _ ->
          fail @"spending bond position only support BondRedeem | BondPayInterest | BondChangeStakeKey | RedeemFee | ForceRedeem action"
      }
    }
  }
}

// num deploy 3
validator(cfg: BondIssueConfig, bond_skh: ScriptKeyHash) {
  fn mint_nft(ac: BondIssueAction, ctx: ScriptContext) -> Bool {
    expect Mint(nft_pid) = ctx.purpose
    let tx = ctx.transaction
    when ac is {
      BondCreate { out_ref, req_skh, pid: req_pid, .. } ->
        bond_nft.minting(cfg, tx, req_skh, bond_skh, nft_pid, req_pid, out_ref)
      BondRedeem { pid: bond_pid } ->
        bond_nft.burning_bond_redeem(tx, nft_pid, bond_pid)
      ForceRedeem { pid: _ } -> bond_nft.burning_force_redeem(tx, nft_pid)
      _ ->
        fail @"minting bond nft only support BondCreate | BondRedeem | ForceRedeem action"
    }
  }
}

// num deploy 4
validator(cfg: BondIssueConfig, bond_skh: ScriptKeyHash, nft_pid: PolicyId) {
  fn mint_token(ac: BondIssueAction, ctx: ScriptContext) -> Bool {
    expect Mint(bond_pid) = ctx.purpose
    let tx = ctx.transaction
    when ac is {
      BondCreate { out_ref, req_skh, .. } ->
        bond_token.minting_without_fee(
          cfg,
          tx,
          req_skh,
          bond_skh,
          nft_pid,
          bond_pid,
          out_ref,
        )
      BondRedeem { .. } -> bond_token.burning_bond_redeem(tx, bond_pid, nft_pid)
      _ ->
        fail @"minting bond token only support BondCreate | BondRedeem action"
    }
  }
}

// num deploy 5
validator(
  cfg: BondIssueConfig,
  bond_skh: ScriptKeyHash,
  nft_pid: PolicyId,
  bond_pid: PolicyId,
) {
  fn spend_request(d: Data, ac: BondIssueAction, ctx: ScriptContext) -> Bool {
    let tx = ctx.transaction
    if ac == GarbageCollector {
      utils.garbage_collector_request(d, tx, cfg)
    } else {
      expect sdt: RequestDatum = d
      when ac is {
        BondCreate {
          out_ref: _out_ref,
          req_skh: _req_skh,
          bond_skh: _bond_skh,
          pid: req_pid,
        } ->
          bond_create.spending(
            cfg,
            ctx,
            sdt,
            bond_skh,
            nft_pid,
            bond_pid,
            req_pid,
          )
        RequestUpdate { pid: req_pid } ->
          request_update.spending(cfg, tx, sdt, req_pid)
        _ ->
          fail @"spending borrow request only support BondCreate | RequestUpdate action"
      }
    }
  }
}

// num deploy 6
validator(
  cfg: BondIssueConfig,
  req_skh: ScriptKeyHash,
  bond_skh: ScriptKeyHash,
  borrower_pid: PolicyId,
) {
  fn mint_request(ac: BondIssueAction, ctx: ScriptContext) -> Bool {
    expect Mint(req_pid) = ctx.purpose
    let tx = ctx.transaction
    when ac is {
      RequestCreate { out_ref, .. } ->
        request_nft.minting(cfg, tx, req_skh, req_pid, borrower_pid, out_ref)
      BondCreate { out_ref, .. } ->
        request_nft.burning_bond_create(
          tx,
          req_skh,
          bond_skh,
          req_pid,
          borrower_pid,
          out_ref,
        )
      RequestUpdate { pid: _ } ->
        request_nft.burning_request_update(tx, req_pid)
      _ ->
        fail @"minting request nft only support RequestCreate | RequestUpdate | BondCreate action"
    }
  }
}
