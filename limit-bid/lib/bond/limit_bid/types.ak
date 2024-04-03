use aiken/transaction/value.{AssetName, PolicyId}
use common/types.{Lovelace}

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
