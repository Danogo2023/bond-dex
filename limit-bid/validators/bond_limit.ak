// Bid Limit Multi
use aiken/transaction.{ScriptContext}
use bond/limit_bid/sell.{Sell, TradeAction, Update}
use bond/types.{BidLimitMulti, BondConfigLimitRaw, bond_config_limit_from_raw}
use common/util.{must_be_signed_by_key} as common_utils

validator(cfg: BondConfigLimitRaw) {
  fn bid_multi(sdt: BidLimitMulti, ac: TradeAction, ctx: ScriptContext) -> Bool {
    when ac is {
      Update ->
        must_be_signed_by_key(ctx.transaction.extra_signatories, sdt.owner_vk)?
      Sell -> sell.spending(ctx, bond_config_limit_from_raw(cfg), sdt)
      _ -> False
    }
  }
}
