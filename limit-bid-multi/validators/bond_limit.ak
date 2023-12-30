// Bid Limit Multi
use aiken/transaction.{ScriptContext}
use bond/limit_bid_multi/sell
use bond/limit_bid_multi/utils
use bond/types.{
  BidLimitMulti, BondConfigLimit, GarbageCollector, Sell, TradeAction, Update,
}
use common/util.{must_be_signed_by_key} as common_utils

validator(cfg: BondConfigLimit) {
  fn bid_multi(d: Data, ac: TradeAction, ctx: ScriptContext) -> Bool {
    let tx = ctx.transaction
    if ac == GarbageCollector {
      utils.garbage_collector(d, tx, cfg)
    } else {
      expect sdt: BidLimitMulti = d
      when ac is {
        Update -> must_be_signed_by_key(tx.extra_signatories, sdt.owner_vk)?
        Sell -> sell.spending(ctx, cfg, sdt)
        _ -> False
      }
    }
  }
}
