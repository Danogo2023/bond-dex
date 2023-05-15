use aiken/transaction.{ScriptContext}
use aiken/transaction/credential.{Address, Inline, VerificationKeyCredential}
use bond/types.{
  BiddingDatum, Buy, Config, ListingDatum, Sell, TradeAction, Update,
}
use bond/validation_bidding
use bond/validation_listing
use common/utils.{get_spending_input} as common_utils

validator(conf: Config) {
  fn listing_v1_0(
    datum: ListingDatum,
    action: TradeAction,
    ctx: ScriptContext,
  ) -> Bool {
    let tx =
      ctx.transaction
    let spending_input =
      get_spending_input(ctx)
    let smart_contract_address =
      spending_input.output.address
    let owner_stake_key =
      when datum.owner_stake_key is {
        Some(owner_stake_key) ->
          Some(Inline(VerificationKeyCredential(owner_stake_key)))
        _ ->
          None
      }
    let owner_address =
      Address {
        payment_credential: VerificationKeyCredential(datum.owner_payment_key),
        stake_credential: owner_stake_key,
      }
    when action is {
      Update ->
        validation_listing.update(
          tx,
          conf,
          owner_address,
          smart_contract_address,
        )
      Buy ->
        validation_listing.buy(
          tx,
          conf,
          datum.requested_yield,
          owner_address,
          smart_contract_address,
        )
      _ ->
        False
    }
  }
}

validator(conf: Config) {
  fn bidding_v1_0(
    datum: BiddingDatum,
    action: TradeAction,
    ctx: ScriptContext,
  ) -> Bool {
    let tx =
      ctx.transaction
    let spending_input =
      get_spending_input(ctx)
    let smart_contract_address =
      spending_input.output.address
    let owner_stake_key =
      when datum.owner_stake_key is {
        Some(owner_stake_key) ->
          Some(Inline(VerificationKeyCredential(owner_stake_key)))
        _ ->
          None
      }
    let owner_address =
      Address {
        payment_credential: VerificationKeyCredential(datum.owner_payment_key),
        stake_credential: owner_stake_key,
      }
    when action is {
      Update ->
        validation_bidding.update(tx, owner_address)
      Sell ->
        validation_bidding.sell(
          tx,
          conf,
          datum.requested_yield,
          owner_address,
          smart_contract_address,
        )
      _ ->
        False
    }
  }
}
