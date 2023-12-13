use aiken/dict.{Dict}
use aiken/transaction.{Output, OutputReference}
use aiken/transaction/value.{AssetName, PolicyId, Value}
use bond_issue/types.{BondDatum, RequestDatum} as bond_issue_types
use common/types.{ScriptKeyHash}

pub type BondAction {
  // mint bond nft => BondCreate { out_ref, req_sk, bond_sk, bond_pid }
  // mint bond token => BondCreate { out_ref, req_sk, bond_sk, nft_pid }
  BondCreate {
    out_ref: OutputReference,
    req_sk: ScriptKeyHash,
    bond_sk: ScriptKeyHash,
    pid: PolicyId,
  }
  // burn bond nft => BondRedeem { bond_pid }
  // burn bond token => BondRedeem { nft_pid }
  // spending bond utxo => BondRedeem { nft_pid || bond_pid }
  BondRedeem { pid: PolicyId }
  BondPayInterest
  BondChangeStakeKey
}

pub type AssetNames =
  List<AssetName>

pub type BondData =
  Dict<AssetName, (BondDatum, Output)>

pub type TokenDict =
  Dict<AssetName, Int>

pub type TokenList =
  List<(AssetName, Int)>

pub type BorrowRequestData =
  Dict<AssetName, (RequestDatum, Output)>

pub type MintName {
  count: Int,
  names: AssetNames,
}

pub type PolicyMint {
  nfts: TokenDict,
  bonds: TokenDict,
}

pub type BurnToken {
  count: Int,
  names: AssetNames,
  assets: TokenList,
}

pub type BondCount =
  Int

pub type BondFee =
  Int

pub type BondOutput =
  Output

pub type BondOutputItem =
  (BondCount, Value, BondDatum, BondOutput, BondFee)

pub type BondOutputDict =
  Dict<ByteArray, BondOutputItem>
