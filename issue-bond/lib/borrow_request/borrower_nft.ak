use aiken/dict
use aiken/list
use aiken/math
use aiken/transaction.{InlineDatum, Output, OutputReference, Transaction}
use aiken/transaction/credential.{ScriptCredential}
use aiken/transaction/value.{PolicyId}
use bond_issue/types.{BondIssueConfig, RequestDatum} as bond_issue_types
use borrow_request/utils.{get_input_out_ref}
use common/hash_out_refs.{hash_out_ref}
use common/types.{ScriptKeyHash} as common_types

pub fn create_simple(
  tx: Transaction,
  borrower_pid: PolicyId,
  out_ref: OutputReference,
) -> Bool {
  let mint_names =
    dict.foldl(
      value.from_minted_value(tx.mint) |> value.tokens(borrower_pid),
      [],
      fn(n, q, z) {
        if (q == 1)? {
          [n, ..z]
        } else {
          fail
        }
      },
    )
  let borrower = hash_out_ref(get_input_out_ref(tx.inputs, out_ref))
  list.has(mint_names, borrower)?
}

pub fn create_2(
  _cfg: BondIssueConfig,
  tx: Transaction,
  borrower_pid: PolicyId,
  out_ref: OutputReference,
  _req_skh: ScriptKeyHash,
) -> Bool {
  let borrower = hash_out_ref(get_input_out_ref(tx.inputs, out_ref))
  let mint_qty =
    value.quantity_of(value.from_minted_value(tx.mint), borrower_pid, borrower)
  (mint_qty == 1)?
}

pub fn create(
  cfg: BondIssueConfig,
  tx: Transaction,
  borrower_pid: PolicyId,
  out_ref: OutputReference,
  req_skh: ScriptKeyHash,
) -> Bool {
  let req_credential = ScriptCredential(req_skh)
  let req_outputs =
    list.foldl(
      tx.outputs,
      [],
      fn(o, z) {
        if o.address.payment_credential == req_credential {
          [o, ..z]
        } else {
          z
        }
      },
    )
  when req_outputs is {
    [o] -> {
      expect odt: RequestDatum =
        when o.datum is {
          InlineDatum(d) -> d
          _ ->
            fail @"borrow_request/request_nft.create: only supports InlineDatum for request"
        }
      and {
        (o.address.stake_credential != None)?,
        (odt.issued == 0)?,
        (odt.symbol == borrower_pid)?,
        //
        (odt.apr >= cfg.platform.min_apr)?,
        (odt.duration >= cfg.platform.min_duration)?,
        (odt.requested >= cfg.platform.min_requested)?,
        (odt.buffer >= cfg.platform.min_buffer)?,
        (odt.prepaid >= math.min(
          odt.buffer + cfg.platform.prepaid_plus,
          odt.duration,
        ))?,
        (odt.prepaid <= odt.duration)?,
        (odt.fee >= cfg.platform.fee)?,
        (odt.requested >= odt.issued)?,
        (odt.epo_rewards >= ( odt.requested - odt.issued ) * cfg.platform.bond_face_value * odt.apr / cfg.basis.base / cfg.epoch.year_to_epoch)?,
        (value.lovelace_of(o.value) >= odt.epo_rewards * odt.prepaid)?,
        //
        (odt.borrower == hash_out_ref(get_input_out_ref(tx.inputs, out_ref)))?,
        //
        (value.quantity_of(
          value.from_minted_value(tx.mint),
          borrower_pid,
          odt.borrower,
        ) == 1)?,
      }
    }
    _ ->
      fail @"borrow_request/request_nft.create: only 1 request output is allowed"
  }
}
