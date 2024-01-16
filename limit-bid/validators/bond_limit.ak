// Bid Limit Multi
use aiken/transaction.{ScriptContext}
use bond/limit_bid/sell
use bond/types.{BidLimitMulti, BondConfigLimit, Sell, TradeAction, Update}
use common/util.{must_be_signed_by_key} as common_utils

validator(cfg: BondConfigLimit) {
  fn bid_multi(sdt: BidLimitMulti, ac: TradeAction, ctx: ScriptContext) -> Bool {
    when ac is {
      Update ->
        must_be_signed_by_key(ctx.transaction.extra_signatories, sdt.owner_vk)?
      Sell -> sell.spending(ctx, cfg, sdt)
      _ -> False
    }
  }
}
