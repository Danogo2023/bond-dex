use aiken/transaction.{ScriptContext}
use aiken/transaction/credential.{Address, Inline, VerificationKeyCredential}
use bond/ask
use bond/bid
use bond/types.{
  AskLimit, BidLimit, OrderTypeDatum, Buy, Config, Sell, TradeAction, Update,
}
use bond/utils.{must_be_signed_by}
use common/utils.{get_spending_input} as common_utils

validator(conf: Config) {
  fn ask_20230818(
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
        ask.buy(
          tx,
          conf,
          OrderTypeDatum(Some(datum), None),
          owner_address,
          get_spending_input(ctx).output.address,
        )
      _ -> False
    }
  }
}

validator(conf: Config) {
  fn bid_20230818(
    datum: BidLimit,
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
      Sell ->
        bid.sell(
          tx,
          conf,
          OrderTypeDatum(Some(datum), None),
          owner_address,
          get_spending_input(ctx).output.address,
        )
      _ -> False
    }
  }
}
