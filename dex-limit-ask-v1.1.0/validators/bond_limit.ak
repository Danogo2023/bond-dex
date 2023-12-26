// Ask Limit
use aiken/transaction.{ScriptContext}
use bond/limit_ask/buy
use bond/types.{AskLimit, BondConfigLimit, Buy, TradeAction, Update}
use common/util.{must_be_signed_by_key}

validator(cfg: BondConfigLimit) {
  fn ask(sdt: AskLimit, ac: TradeAction, ctx: ScriptContext) -> Bool {
    let tx = ctx.transaction
    when ac is {
      Update -> must_be_signed_by_key(tx.extra_signatories, sdt.owner_vk)?
      Buy -> buy.spending(ctx, cfg, sdt)
      _ -> False
    }
  }
}
