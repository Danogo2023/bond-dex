// Bid Making
use aiken/transaction.{ScriptContext}
use bond/common/types.{
  BidMaking, BondConfigMakingRaw, Sell, TradeAction, Update,
  bond_config_making_from_raw,
}
use bond/making_bid/sell
use common/types.{ScriptKeyHash} as common_types
use common/util.{must_be_signed_by_key} as common_utils

validator(cfg: BondConfigMakingRaw, script_blacklist: List<ScriptKeyHash>) {
  fn bid(sdt: BidMaking, ac: TradeAction, ctx: ScriptContext) -> Bool {
    when ac is {
      Update ->
        must_be_signed_by_key(ctx.transaction.extra_signatories, sdt.owner_vk)?
      Sell ->
        sell.spending(
          ctx,
          bond_config_making_from_raw(cfg),
          sdt,
          script_blacklist,
        )
      _ -> False
    }
  }
}
