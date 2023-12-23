// Bid Limit Multi
use aiken/option
use aiken/transaction.{ScriptContext}
use aiken/transaction/credential
use bond/limit_bid_multi/sell.{matching}
use bond/types.{BidLimitMulti, BondConfigLimit, Sell, TradeAction, Update}
use common/util.{get_spending_input, must_be_signed_by_key} as common_utils

validator(cfg: BondConfigLimit) {
  fn bid_multi(sdt: BidLimitMulti, ac: TradeAction, ctx: ScriptContext) -> Bool {
    when ac is {
      Update ->
        must_be_signed_by_key(ctx.transaction.extra_signatories, sdt.owner_vk)?
      Sell ->
        matching(
          ctx.transaction,
          cfg,
          sdt,
          sdt.owner_sk
            |> option.and_then(
                 fn(s) {
                   Some(
                     credential.from_verification_key(sdt.owner_vk)
                       |> credential.with_delegation_key(s),
                   )
                 },
               )
            |> option.or_else(credential.from_verification_key(sdt.owner_vk)),
          get_spending_input(ctx).output.address,
        )
      _ -> False
    }
  }
}
