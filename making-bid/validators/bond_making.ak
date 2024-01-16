// Bid Making
use aiken/transaction.{ScriptContext}
use bond/making_bid/sell
use bond/types.{BidMaking, BondConfigMaking, Sell, TradeAction, Update}
use common/util.{must_be_signed_by_key} as common_utils

validator(cfg: BondConfigMaking) {
  fn bid(sdt: BidMaking, ac: TradeAction, ctx: ScriptContext) -> Bool {
    when ac is {
      Update ->
        must_be_signed_by_key(ctx.transaction.extra_signatories, sdt.owner_vk)?
      Sell -> sell.spending(ctx, cfg, sdt)
      _ -> False
    }
  }
}
