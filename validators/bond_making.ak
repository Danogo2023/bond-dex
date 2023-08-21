use aiken/transaction.{ScriptContext}
use aiken/transaction/credential.{
  Address, Inline, ScriptCredential, VerificationKeyCredential,
}
use bond/ask
use bond/bid
use bond/types.{
  AskMaking, BidMaking, Buy, Config, OrderTypeDatum, Sell, TradeAction, Update,
}
use bond/utils.{must_be_signed_by}
use common/utils.{get_spending_input} as common_utils

validator(conf: Config) {
  fn ask_20230822(
    datum: AskMaking,
    action: TradeAction,
    ctx: ScriptContext,
  ) -> Bool {
    let tx = ctx.transaction
    when action is {
      Update ->
        must_be_signed_by(
          tx.extra_signatories,
          Address {
            payment_credential: VerificationKeyCredential(
              datum.owner_payment_key,
            ),
            stake_credential: when datum.owner_stake_key is {
              Some(sk) -> Some(Inline(VerificationKeyCredential(sk)))
              _ -> None
            },
          },
        )?
      Buy ->
        ask.buy(
          tx,
          conf,
          OrderTypeDatum(None, Some(datum)),
          Address {
            payment_credential: ScriptCredential(datum.bid_sc),
            stake_credential: when datum.owner_stake_key is {
              Some(sk) -> Some(Inline(VerificationKeyCredential(sk)))
              _ -> None
            },
          },
          get_spending_input(ctx).output.address,
        )
      _ -> False
    }
  }
}

validator(conf: Config) {
  fn bid_20230822(
    datum: BidMaking,
    action: TradeAction,
    ctx: ScriptContext,
  ) -> Bool {
    let tx = ctx.transaction
    when action is {
      Update ->
        must_be_signed_by(
          tx.extra_signatories,
          Address {
            payment_credential: VerificationKeyCredential(
              datum.owner_payment_key,
            ),
            stake_credential: when datum.owner_stake_key is {
              Some(sk) -> Some(Inline(VerificationKeyCredential(sk)))
              _ -> None
            },
          },
        )?
      Sell ->
        bid.sell(
          tx,
          conf,
          OrderTypeDatum(None, Some(datum)),
          Address {
            payment_credential: ScriptCredential(datum.ask_sc),
            stake_credential: when datum.owner_stake_key is {
              Some(sk) -> Some(Inline(VerificationKeyCredential(sk)))
              _ -> None
            },
          },
          get_spending_input(ctx).output.address,
        )
      _ -> False
    }
  }
}
