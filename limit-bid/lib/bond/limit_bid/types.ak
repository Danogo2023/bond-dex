use aiken/transaction/value.{AssetName, PolicyId}
use bond/types.{BondType, EscrowInfo}
use common/types.{Lovelace, ScriptKeyHash} as common_types

pub type TradeAction {
  Update
  Buy
  Sell {
    exchange_fee: Lovelace,
    seller_receive: Lovelace,
    offers: List<(PolicyId, AssetName, Int)>,
    cont_idx: Option<Int>,
  }
  Upgrade
  GarbageCollector
}

pub type WithdrawAction {
  SellMulti { bid_skh: ScriptKeyHash }
}

pub type EscrowBond =
  (BondType, EscrowInfo)
