// Ask Making
use aiken/transaction.{ScriptContext}
use bond/making_ask/buy
use bond/types.{AskMaking, BondConfigMaking, BondType, Buy, TradeAction, Update}
use common/util.{must_be_signed_by_key} as common_utils

validator(cfg: BondConfigMaking, bond_type: BondType) {
  fn ask(sdt: AskMaking, ac: TradeAction, ctx: ScriptContext) -> Bool {
    when ac is {
      Update ->
        must_be_signed_by_key(ctx.transaction.extra_signatories, sdt.owner_vk)?
      Buy -> buy.spending(ctx, cfg, sdt, bond_type)
      _ -> False
    }
  }
}
