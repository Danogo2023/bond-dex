// Ask Limit
use aiken/transaction.{ScriptContext}
use aiken/transaction/credential.{Address, Inline, VerificationKeyCredential}
use bond/limit/ask/buy.{matching}
use bond/types.{AskLimit, Buy, ConfigLimit, TradeAction, Update}
use common/utils.{get_spending_input, must_be_signed_by}

validator(conf: ConfigLimit) {
  fn ask_20230829(
    datum: AskLimit,
    action: TradeAction,
    ctx: ScriptContext,
  ) -> Bool {
    let tx = ctx.transaction
    let owner_address =
      Address {
        payment_credential: VerificationKeyCredential(datum.owner_payment_key),
        stake_credential: when datum.owner_stake_key is {
          Some(sk) -> Some(Inline(VerificationKeyCredential(sk)))
          _ -> None
        },
      }
    when action is {
      Update -> must_be_signed_by(tx.extra_signatories, owner_address)?
      Buy ->
        matching(
          tx,
          conf,
          datum,
          owner_address,
          get_spending_input(ctx).output.address,
        )
      _ -> False
    }
  }
}
