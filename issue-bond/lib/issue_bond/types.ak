use aiken/transaction.{OutputReference}
use aiken/transaction/value.{PolicyId}
use common/types.{ScriptKeyHash}

pub type BondIssueAction {
  // mint request nft => RequestCreate { out_ref, req_skh, borrower_pid }
  // mint borrower nft => RequestCreate { out_ref, req_skh, request_pid }
  RequestCreate {
    out_ref: OutputReference,
    req_skh: ScriptKeyHash,
    pid: PolicyId,
  }
  RequestUpdate { pid: PolicyId }
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
  BondPayInterest { pid: PolicyId }
  BondChangeStakeKey { pid: PolicyId }
  RedeemFee { pid: PolicyId }
  ForceRedeem { pid: PolicyId }
  GarbageCollector
}
