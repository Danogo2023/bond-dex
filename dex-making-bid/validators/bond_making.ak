// Bid Making
use aiken/option
use aiken/transaction.{ScriptContext}
use aiken/transaction/credential
use bond/making_bid/sell.{matching}
use bond/types.{BidMaking, ConfigMaking, Sell, TradeAction, Update}
use common/util.{get_spending_input, must_be_signed_by_key} as common_utils

validator(conf: ConfigMaking) {
  fn bid(sdt: BidMaking, ac: TradeAction, ctx: ScriptContext) -> Bool {
    let tx = ctx.transaction
    when ac is {
      Update -> must_be_signed_by_key(tx.extra_signatories, sdt.owner_vk)?
      Sell ->
        matching(
          tx,
          conf,
          sdt,
          sdt.owner_sk
            |> option.and_then(
                 fn(s) {
                   Some(
                     credential.from_verification_key(sdt.ask_sc)
                       |> credential.with_delegation_key(s),
                   )
                 },
               )
            |> option.or_else(credential.from_verification_key(sdt.ask_sc)),
          get_spending_input(ctx).output.address,
        )
      _ -> False
    }
  }
}
