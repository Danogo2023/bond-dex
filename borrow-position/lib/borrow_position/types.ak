use aiken/dict.{Dict}
use aiken/transaction.{Output}
use aiken/transaction/value.{AssetName}
use bond_issue/types.{BondDatum, RequestDatum} as bond_issue_types
use common/types.{ScriptKeyHash}

pub type BondAction {
  BondCreate { req_sk: ScriptKeyHash, bond_sk: ScriptKeyHash }
  BondRedeem
  BondPayInterest
  BondChangeStakeKey
}

pub type BorrowRequestOutput {
  count: Int,
  tokens: List<AssetName>,
  data: Dict<AssetName, (RequestDatum, Output)>,
}

pub type BondOutput {
  count: Int,
  tokens: List<AssetName>,
  data: Dict<AssetName, (BondDatum, Output)>,
}

pub type BondMint {
  count: Int,
  tokens: List<AssetName>,
}
