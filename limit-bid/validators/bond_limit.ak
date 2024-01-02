// Bid Limit
use aiken/transaction.{ScriptContext}
use bond/limit_bid/sell
use bond/limit_bid/utils
use bond/types.{
  BidLimit, BondConfigLimit, GarbageCollector, Sell, TradeAction, Update,
}
use common/util.{must_be_signed_by_key} as common_utils

validator(cfg: BondConfigLimit) {
  fn bid(d: Data, ac: TradeAction, ctx: ScriptContext) -> Bool {
    let tx = ctx.transaction
    if ac == GarbageCollector {
      utils.garbage_collector(d, tx, cfg)
    } else {
      expect sdt: BidLimit = d
      when ac is {
        Update ->
          must_be_signed_by_key(ctx.transaction.extra_signatories, sdt.owner_vk)?
        Sell -> sell.spending(ctx, cfg, sdt)
        _ -> False
      }
    }
  }
}
