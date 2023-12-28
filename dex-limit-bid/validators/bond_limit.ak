// Bid Limit
use aiken/transaction.{ScriptContext}
use bond/limit_bid/sell
use bond/types.{BidLimit, BondConfigLimit, BondType, Sell, TradeAction, Update}
use common/util.{must_be_signed_by_key} as common_utils

validator(cfg: BondConfigLimit, bond_type: BondType) {
  fn bid(sdt: BidLimit, ac: TradeAction, ctx: ScriptContext) -> Bool {
    when ac is {
      Update ->
        must_be_signed_by_key(ctx.transaction.extra_signatories, sdt.owner_vk)?
      Sell -> sell.spending(ctx, cfg, sdt, bond_type)
      _ -> False
    }
  }
}
