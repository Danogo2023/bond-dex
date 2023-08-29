use aiken/transaction.{ScriptContext}
use aiken/transaction/credential.{
  Address, Inline, ScriptCredential, VerificationKeyCredential,
}
use bond/ask_making.{buy}
use bond/bid_making.{sell}
use bond/types.{AskMaking, BidMaking, Buy, Config, Sell, TradeAction, Update}
use common/utils.{get_spending_input, must_be_signed_by} as common_utils

validator(conf: Config) {
  fn ask_20230829(
    datum: AskMaking,
    action: TradeAction,
    ctx: ScriptContext,
  ) -> Bool {
    let tx = ctx.transaction
    let owner_sk =
      when datum.owner_stake_key is {
        Some(sk) -> Some(Inline(VerificationKeyCredential(sk)))
        _ -> None
      }
    when action is {
      Update ->
        must_be_signed_by(
          tx.extra_signatories,
          Address {
            payment_credential: VerificationKeyCredential(
              datum.owner_payment_key,
            ),
            stake_credential: owner_sk,
          },
        )?
      Buy ->
        buy(
          tx,
          conf,
          datum,
          Address {
            payment_credential: ScriptCredential(datum.bid_sc),
            stake_credential: owner_sk,
          },
          get_spending_input(ctx).output.address,
        )
      _ -> False
    }
  }
}

validator(conf: Config) {
  fn bid_20230829(
    datum: BidMaking,
    action: TradeAction,
    ctx: ScriptContext,
  ) -> Bool {
    let tx = ctx.transaction
    let owner_sk =
      when datum.owner_stake_key is {
        Some(sk) -> Some(Inline(VerificationKeyCredential(sk)))
        _ -> None
      }
    when action is {
      Update ->
        must_be_signed_by(
          tx.extra_signatories,
          Address {
            payment_credential: VerificationKeyCredential(
              datum.owner_payment_key,
            ),
            stake_credential: owner_sk,
          },
        )?
      Sell ->
        sell(
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
