use aiken/transaction.{ScriptContext}
use aiken/transaction/credential.{Address, Inline, VerificationKeyCredential}
use bond/ask_limit.{buy}
use bond/bid_limit.{sell}
use bond/types.{
  AskLimit, BidLimit, Buy, Config, Sell, TradeAction, Update,
}
use common/utils.{get_spending_input, must_be_signed_by} as common_utils

validator(conf: Config) {
  fn ask_20230822(
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
        buy(
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

validator(conf: Config) {
  fn bid_20230822(
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
        sell(
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
