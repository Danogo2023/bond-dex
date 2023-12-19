use aiken/transaction.{OutputReference}
use aiken/transaction/value.{PolicyId}
use common/types.{ScriptKeyHash}

pub type BondAction {
  // mint bond nft => BondCreate { out_ref, req_skh, bond_skh, bond_pid }
  // mint bond token => BondCreate { out_ref, req_skh, bond_skh, nft_pid }
  BondCreate {
    out_ref: OutputReference,
    req_skh: ScriptKeyHash,
    bond_skh: ScriptKeyHash,
    pid: PolicyId,
  }
  // burn bond nft => BondRedeem { bond_pid }
  // burn bond token => BondRedeem { nft_pid }
  // spending bond utxo => BondRedeem { nft_pid || bond_pid }
  BondRedeem { pid: PolicyId }
  BondPayInterest
  BondChangeStakeKey
  ClaimFee
}
