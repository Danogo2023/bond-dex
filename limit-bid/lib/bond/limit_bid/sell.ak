use aiken/dict
use aiken/transaction.{ScriptContext, Spend, Transaction, WithdrawFrom}
use aiken/transaction/credential.{Address, Inline, ScriptCredential}
use bond/limit_bid/types.{SellMulti, WithdrawAction} as dtypes
use common/types.{ScriptKeyHash} as ctypes

pub fn constraint(ctx: ScriptContext, multi_bid_sell_skh: ScriptKeyHash) {
  let tx = ctx.transaction
  expect Spend(ibid_out_ref) = ctx.purpose
  expect Some(ibid) = transaction.find_input(tx.inputs, ibid_out_ref)
  expect Some(redeemer) =
    dict.get(
      tx.redeemers,
      WithdrawFrom(Inline(ScriptCredential(multi_bid_sell_skh))),
    )
  expect SellMulti(bid_skh): WithdrawAction = redeemer
  (ScriptCredential(bid_skh) == ibid.output.address.payment_credential)?
}
