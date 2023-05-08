use aiken/transaction.{ScriptContext}
use aiken/transaction/credential.{Address, Inline, VerificationKeyCredential}
use bond/types.{Buy, Config, ListingDatum, TradeAction, Update}
// use bond/utils.{must_be_signed_by}
use bond/validation_buy.{buy_listing}
use bond/validation_listing.{update_listing}
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
        update_listing(tx, conf, owner_address, smart_contract_address)
      Buy ->
        buy_listing(
          tx,
          conf,
          spending_input,
          datum.requested_yield,
          owner_address,
          smart_contract_address,
        )
      // Cho phep dia chi thu phi cua san rut assets su dung trong truong hop dac biet
      // Withdraw ->
      //   must_be_signed_by(tx.extra_signatories, conf.market.address)?
      _ ->
        False
    }
  }
}
