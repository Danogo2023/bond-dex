// Bid Making
use aiken/transaction.{ScriptContext}
use bond/making_bid/sell.{Sell, TradeAction, Update}
use bond/types.{BidMaking, BondConfigMakingRaw, bond_config_making_from_raw}
use common/util.{must_be_signed_by_key} as common_utils

validator(cfg: BondConfigMakingRaw) {
  fn bid(sdt: BidMaking, ac: TradeAction, ctx: ScriptContext) -> Bool {
    when ac is {
      Update ->
        must_be_signed_by_key(ctx.transaction.extra_signatories, sdt.owner_vk)?
      Sell -> sell.spending(ctx, bond_config_making_from_raw(cfg), sdt)
      _ -> False
    }
  }
}
