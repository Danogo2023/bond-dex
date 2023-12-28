// Bid Making
use aiken/transaction.{ScriptContext}
use bond/making_bid/sell
use bond/types.{BidMaking,
  BondConfigMaking, BondType, Sell, TradeAction, Update}
use common/util.{must_be_signed_by_key} as common_utils

validator(conf: BondConfigMaking, bond_type: BondType) {
  fn bid(sdt: BidMaking, ac: TradeAction, ctx: ScriptContext) -> Bool {
    when ac is {
      Update ->
        must_be_signed_by_key(ctx.transaction.extra_signatories, sdt.owner_vk)?
      Sell -> sell.spending(ctx, conf, sdt, bond_type)
      _ -> False
    }
  }
}
