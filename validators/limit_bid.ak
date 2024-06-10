use aiken/transaction.{ScriptContext, WithdrawFrom}
use bond/common/types.{
  BidLimitMulti, BondConfigLimitRaw, bond_config_limit_from_raw,
} as bond_types
// Bid Limit Multi
use bond/limit_bid/sell
use bond/limit_bid/types.{Sell,
  SellMulti, TradeAction, Update, WithdrawAction} as ctypes
use bond/limit_bid/withdraw
use common/types.{ScriptKeyHash} as common_types
use common/util.{must_be_signed_by_key} as common_utils

validator(multi_bid_sell_skh: ScriptKeyHash) {
  fn bid_multi(sdt: BidLimitMulti, ac: TradeAction, ctx: ScriptContext) -> Bool {
    when ac is {
      Update ->
        must_be_signed_by_key(ctx.transaction.extra_signatories, sdt.owner_vk)?
      Sell { .. } -> sell.constraint(ctx, multi_bid_sell_skh)
      _ -> False
    }
  }
}

validator(cfg: BondConfigLimitRaw, script_blacklist: List<ScriptKeyHash>) {
  fn withdraw(redeemer: WithdrawAction, ctx: ScriptContext) -> Bool {
    when ctx.purpose is {
      WithdrawFrom { .. } -> {
        let SellMulti(bid_skh) = redeemer
        withdraw.constraint(
          ctx,
          bond_config_limit_from_raw(cfg),
          bid_skh,
          script_blacklist,
        )
      }
      _ -> False
    }
  }
}
