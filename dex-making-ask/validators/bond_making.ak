// Ask Making
use aiken/transaction.{ScriptContext}
use bond/making_ask/buy
use bond/making_ask/utils
use bond/types.{
  AskMaking, BondConfigMaking, BondType, Buy, GarbageCollector, TradeAction,
  Update,
}
use common/util.{must_be_signed_by_key} as common_utils

validator(cfg: BondConfigMaking, bond_type: BondType) {
  fn ask(d: Data, ac: TradeAction, ctx: ScriptContext) -> Bool {
    let tx = ctx.transaction
    if ac == GarbageCollector {
      utils.garbage_collector(d, tx, cfg)
    } else {
      expect sdt: AskMaking = d
      when ac is {
        Update -> must_be_signed_by_key(tx.extra_signatories, sdt.owner_vk)?
        Buy -> buy.spending(ctx, cfg, sdt, bond_type)
        _ -> False
      }
    }
  }
}
