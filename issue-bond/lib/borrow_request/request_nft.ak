use aiken/dict
use aiken/list
use aiken/math
use aiken/transaction.{InlineDatum, OutputReference, Transaction}
use aiken/transaction/credential.{ScriptCredential}
use aiken/transaction/value.{PolicyId}
use bond_issue/types.{BondIssueConfig, RequestDatum} as bond_issue_types
use borrow_request/utils.{get_input_out_ref} as borrow_request_utils
use common/hash_out_refs.{hash_out_ref}
use common/types.{ScriptKeyHash} as common_types
use issue_bond/utils.{get_burn_nft_names, get_output_by_nft_names}

pub fn burning_bond_create(
  tx: Transaction,
  _req_skh: ScriptKeyHash,
  _bond_skh: ScriptKeyHash,
  req_pid: PolicyId,
  _borrower_pid: PolicyId,
  _out_ref: OutputReference,
) -> Bool {
  // let req_pk = ScriptCredential(req_skh)
  burning_valid(tx, req_pid)
}

pub fn burning_request_update(tx: Transaction, req_pid: PolicyId) -> Bool {
  burning_valid(tx, req_pid)
}

fn burning_valid(tx: Transaction, req_pid: PolicyId) -> Bool {
  let burn_names = get_burn_nft_names(tx, req_pid)
  let oreq = get_output_by_nft_names(tx, burn_names, req_pid)
  and {
    (list.length(burn_names) > 0)?,
    (list.length(oreq) == 0)?,
  }
}

pub fn minting(
  cfg: BondIssueConfig,
  tx: Transaction,
  req_skh: ScriptKeyHash,
  req_pid: PolicyId,
  borrower_pid: PolicyId,
  out_ref: OutputReference,
) -> Bool {
  let borrower_valid = hash_out_ref(get_input_out_ref(tx.inputs, out_ref))
  let mint_req_nfts = value.tokens(value.from_minted_value(tx.mint), req_pid)
  let mint_req_nfts_valid = dict.filter(mint_req_nfts, fn(_n, q) { (q == 1)? })
  let req_pk = ScriptCredential(req_skh)
  let dist_req_nfts =
    list.filter(
      tx.outputs,
      fn(o) {
        let req_tokens = value.tokens(o.value, req_pid)
        if and {
          o.address.payment_credential == req_pk,
          dict.size(req_tokens) == 1,
        } {
          expect oreq_dt: RequestDatum =
            when o.datum is {
              InlineDatum(d) -> d
              _ -> fail @"only supports InlineDatum for borrow request"
            }
          if and {
            (value.quantity_of(o.value, req_pid, oreq_dt.borrower) == 1)?,
            dict.has_key(mint_req_nfts_valid, oreq_dt.borrower)?,
            (o.address.stake_credential != None)?,
            (oreq_dt.apr >= cfg.platform.min_apr)?,
            (oreq_dt.duration >= cfg.platform.min_duration)?,
            (oreq_dt.requested >= cfg.platform.min_requested)?,
            (oreq_dt.buffer >= cfg.platform.min_buffer)?,
            (oreq_dt.prepaid >= math.min(
              oreq_dt.buffer + cfg.platform.prepaid_plus,
              oreq_dt.duration,
            ))?,
            (oreq_dt.prepaid <= oreq_dt.duration)?,
            (oreq_dt.fee >= cfg.platform.fee)?,
            (oreq_dt.requested >= oreq_dt.issued)?,
            (oreq_dt.issued == 0)?,
            (oreq_dt.symbol == borrower_pid)?,
            (oreq_dt.epo_rewards >= ( oreq_dt.requested - oreq_dt.issued ) * cfg.platform.bond_face_value * oreq_dt.apr / cfg.basis.base / cfg.epoch.year_to_epoch)?,
            (value.lovelace_of(o.value) >= oreq_dt.epo_rewards * oreq_dt.prepaid)?,
          } {
            True
          } else {
            fail
          }
        } else {
          False
        }
      },
    )
  and {
    dict.has_key(mint_req_nfts_valid, borrower_valid)?,
    (dict.size(mint_req_nfts) == dict.size(mint_req_nfts_valid))?,
    (dict.size(mint_req_nfts) == list.length(dist_req_nfts))?,
  }
}
