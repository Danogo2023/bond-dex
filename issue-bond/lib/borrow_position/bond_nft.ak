use aiken/bytearray
use aiken/dict
use aiken/list
use aiken/transaction.{InlineDatum, OutputReference, Transaction}
use aiken/transaction/credential.{Address, ScriptCredential}
use aiken/transaction/value.{PolicyId}
use bond_issue/types.{BondDatum, BondIssueConfig, RequestDatum}
use common/hash_out_refs.{hash_out_ref_salt}
use common/time.{get_current_epoch_with_ttl}
use common/types.{ScriptKeyHash} as common_types
use issue_bond/utils.{
  check_output_request_base, get_burn_nft_names, get_input_by_nft_names,
  get_output_by_nft_names,
}

pub fn burning_bond_redeem(
  tx: Transaction,
  nft_pid: PolicyId,
  _bond_pid: PolicyId,
) -> Bool {
  burning_valid(tx, nft_pid)
}

pub fn burning_force_redeem(tx: Transaction, nft_pid: PolicyId) -> Bool {
  burning_valid(tx, nft_pid)
}

fn burning_valid(tx: Transaction, nft_pid: PolicyId) -> Bool {
  let burn_names = get_burn_nft_names(tx, nft_pid)
  let ibond = get_input_by_nft_names(tx, burn_names, nft_pid)
  let obond = get_output_by_nft_names(tx, burn_names, nft_pid)
  and {
    (list.length(burn_names) > 0)?,
    (list.length(ibond) == list.length(burn_names))?,
    (list.length(obond) == 0)?,
  }
}

pub fn minting(
  cfg: BondIssueConfig,
  tx: Transaction,
  req_skh: ScriptKeyHash,
  bond_skh: ScriptKeyHash,
  nft_pid: PolicyId,
  req_pid: PolicyId,
  _out_ref: OutputReference,
) -> Bool {
  let mint_bond_nfts = value.tokens(value.from_minted_value(tx.mint), nft_pid)
  let mint_bond_nfts_valid =
    dict.filter(mint_bond_nfts, fn(_n, q) { (q == 1)? })
  if (dict.size(mint_bond_nfts) == dict.size(mint_bond_nfts_valid))? {
    let req_pk = ScriptCredential(req_skh)
    let req_inputs_valid =
      list.foldr(
        tx.inputs,
        dict.new(),
        fn(i, z) {
          let req_tokens = value.tokens(i.output.value, req_pid)
          if and {
            i.output.address.payment_credential == req_pk,
            dict.size(req_tokens) == 1,
          } {
            expect sreq_dt: RequestDatum =
              when i.output.datum is {
                InlineDatum(d) -> d
                _ -> fail @"only supports InlineDatum for borrow request"
              }
            if and {
              //
              (i.output.address.stake_credential != None)?,
              check_output_request_base(cfg, i.output, sreq_dt)?,
              (sreq_dt.requested > sreq_dt.issued)?,
              (sreq_dt.issued >= 0)?,
              (value.quantity_of(i.output.value, req_pid, sreq_dt.borrower) == 1)?,
            } {
              let bond_name =
                hash_out_ref_salt(i.output_reference, sreq_dt.borrower)
              if !dict.has_key(z, bond_name) {
                dict.insert(z, bond_name, i.output, compare: bytearray.compare)
              } else {
                fail @"borrow request input is unique"
              }
            } else {
              fail
            }
          } else {
            z
          }
        },
      )
    // let bond_name_inputs_valid = dict.keys(req_inputs_valid)
    let epoch_curr =
      get_current_epoch_with_ttl(
        tx.validity_range,
        cfg.epoch,
        cfg.platform.tx_ttl,
        cfg.slot.slot_length,
      )
    let bond_pk = ScriptCredential(bond_skh)
    let bond_outputs_valid =
      list.foldr(
        tx.outputs,
        dict.new(),
        fn(o, z) {
          let nft_tokens = value.tokens(o.value, nft_pid)
          if and {
            o.address.payment_credential == bond_pk,
            dict.size(nft_tokens) == 1,
          } {
            expect obond_dt: BondDatum =
              when o.datum is {
                InlineDatum(d) -> d
                _ ->
                  fail @"borrow_position/bond_nft.minting: only supports InlineDatum for bond"
              }
            if and {
              (value.quantity_of(o.value, nft_pid, obond_dt.token_name) == 1)?,
              //
              dict.has_key(mint_bond_nfts_valid, obond_dt.token_name)?,
              //
              (obond_dt.duration >= cfg.platform.min_duration)?,
              (obond_dt.buffer >= cfg.platform.min_buffer)?,
              (obond_dt.fee >= cfg.platform.fee)?,
              (obond_dt.bond_amount > 0)?,
              (obond_dt.start == epoch_curr - cfg.epoch.epoch_boundary_as_epoch)?,
            } {
              if !dict.has_key(z, obond_dt.token_name) {
                dict.insert(
                  z,
                  obond_dt.token_name,
                  o,
                  compare: bytearray.compare,
                )
              } else {
                fail @"bond utxo output is unique"
              }
            } else {
              fail
            }
          } else {
            z
          }
        },
      )
    and {
      (dict.size(bond_outputs_valid) == dict.size(req_inputs_valid))?,
      (dict.size(bond_outputs_valid) == dict.size(mint_bond_nfts_valid))?,
      (list.difference(
        dict.keys(mint_bond_nfts_valid),
        dict.keys(bond_outputs_valid),
      ) == [])?,
    }
  } else {
    fail
  }
}
