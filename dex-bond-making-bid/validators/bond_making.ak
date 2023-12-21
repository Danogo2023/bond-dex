// Bid Making
use aiken/transaction.{ScriptContext}
use aiken/transaction/credential.{
  Address, Inline, ScriptCredential, VerificationKeyCredential,
}
use bond/making/bid/sell.{matching}
use bond/types.{BidMaking, ConfigMaking, Sell, TradeAction, Update}
use common/util.{get_spending_input, must_be_signed_by} as common_utils

validator(conf: ConfigMaking) {
  fn bid(datum: BidMaking, action: TradeAction, ctx: ScriptContext) -> Bool {
    let tx = ctx.transaction
    let owner_sk =
      when datum.owner_sk is {
        Some(sk) -> Some(Inline(VerificationKeyCredential(sk)))
        _ -> None
      }
    when action is {
      Update ->
        must_be_signed_by(
          tx.extra_signatories,
          Address {
            payment_credential: VerificationKeyCredential(datum.owner_vk),
            stake_credential: owner_sk,
          },
        )?
      Sell ->
        matching(
          tx,
          conf,
          datum,
          Address {
            payment_credential: ScriptCredential(datum.ask_sc),
            stake_credential: owner_sk,
          },
          get_spending_input(ctx).output.address,
        )
      _ -> False
    }
  }
}
