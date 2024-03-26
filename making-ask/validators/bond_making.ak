// Ask Making
use aiken/transaction.{ScriptContext}
use bond/making_ask/buy
use bond/types.{
  AskMaking, BondConfigMakingRaw, Buy, TradeAction, Update,
  bond_config_making_from_raw,
}
use common/util.{must_be_signed_by_key} as common_utils

validator(cfg: BondConfigMakingRaw) {
  fn ask(sdt: AskMaking, ac: TradeAction, ctx: ScriptContext) -> Bool {
    when ac is {
      Update ->
        must_be_signed_by_key(ctx.transaction.extra_signatories, sdt.owner_vk)?
      Buy -> buy.spending(ctx, bond_config_making_from_raw(cfg), sdt)
      _ -> False
    }
  }
}
