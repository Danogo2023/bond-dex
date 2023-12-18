// Bid Limit
use aiken/transaction.{ScriptContext}
use aiken/transaction/credential.{Address, Inline, VerificationKeyCredential}
use bond/limit/bid/sell.{matching}
use bond/types.{BidLimit, ConfigLimit, Sell, TradeAction, Update}
use common/util.{get_spending_input, must_be_signed_by} as common_utils

validator(conf: ConfigLimit) {
  fn bid_20230829(
    datum: BidLimit,
    action: TradeAction,
    ctx: ScriptContext,
  ) -> Bool {
    let tx = ctx.transaction
    let owner_address =
      Address {
        payment_credential: VerificationKeyCredential(datum.owner_vk),
        stake_credential: when datum.owner_sk is {
          Some(sk) -> Some(Inline(VerificationKeyCredential(sk)))
          _ -> None
        },
      }
    when action is {
      Update -> must_be_signed_by(tx.extra_signatories, owner_address)?
      Sell ->
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
