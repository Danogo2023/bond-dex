// Bid Making
use aiken/transaction.{ScriptContext}
use bond/making_bid/sell
use bond/making_bid/utils
use bond/types.{
  BidMaking, BondConfigMaking, BondType, GarbageCollector, Sell, TradeAction,
  Update,
}
use common/util.{must_be_signed_by_key} as common_utils

validator(cfg: BondConfigMaking, bond_type: BondType) {
  fn bid(d: Data, ac: TradeAction, ctx: ScriptContext) -> Bool {
    let tx = ctx.transaction
    if ac == GarbageCollector {
      utils.garbage_collector(d, tx, cfg)
    } else {
      expect sdt: BidMaking = d
      when ac is {
        Update -> must_be_signed_by_key(tx.extra_signatories, sdt.owner_vk)?
        Sell -> sell.spending(ctx, cfg, sdt, bond_type)
        _ -> False
      }
    }
  }
}
