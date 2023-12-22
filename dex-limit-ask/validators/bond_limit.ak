// Ask Limit
use aiken/option
use aiken/transaction.{ScriptContext}
use aiken/transaction/credential
use bond/limit_ask/buy.{matching}
use bond/types.{AskLimit, Buy, ConfigLimit, TradeAction, Update}
use common/util.{get_spending_input, must_be_signed_by_key}

validator(conf: ConfigLimit) {
  fn ask(sdt: AskLimit, ac: TradeAction, ctx: ScriptContext) -> Bool {
    let tx = ctx.transaction
    when ac is {
      Update -> must_be_signed_by_key(tx.extra_signatories, sdt.owner_vk)?
      Buy ->
        matching(
          tx,
          conf,
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
