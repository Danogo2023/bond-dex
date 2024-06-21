use aiken/transaction/value.{AssetName, PolicyId, Value}
use bond/common/types.{BondType, EscrowInfo}
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

pub type BidValue =
  Value

pub type BuyerValue =
  Value
