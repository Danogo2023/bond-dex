use aiken/dict
use aiken/list
use aiken/option
use aiken/transaction.{InlineDatum, Input, Output, OutputReference, Transaction}
use aiken/transaction/credential.{Address, ScriptCredential}
use aiken/transaction/value.{PolicyId}
use bond_issue/types.{BondDatum,
  BondIssueConfig, RequestDatum} as bond_issue_types
use borrow_request/types.{BondCreateOutput, BorrowRequestOutput}
use borrow_request/utils.{
  get_bond_create_output, get_borrow_request_output, mint_only_one,
  request_output_valid,
}
use common/hash_inputs.{hash_sorted, hash_sorted_salt}
use common/time.{get_current_epoch_with_ttl}
use common/types.{ScriptKeyHash} as common_types

pub fn minting(
  cfg: BondIssueConfig,
  tx: Transaction,
  req_pid: PolicyId,
  out_ref: OutputReference,
  sk: ScriptKeyHash,
) -> Bool {
  let req_credential = ScriptCredential(sk)
  when
    list.foldr(
      tx.outputs,
      None,
      fn(o, z) {
        if o.address.payment_credential == req_credential {
          if z == None {
            expect oreq_dt: RequestDatum =
              when o.datum is {
                InlineDatum(d) -> d
                _ -> fail @"only supports InlineDatum for request"
              }
            Some((oreq_dt, o))
          } else {
            fail @"only 1 request output is allowed"
          }
        } else {
          z
        }
      },
    )
  is {
    Some((oreq_dt, output)) -> and {
        (output.address.stake_credential != None)?,
        (oreq_dt.issued == 0)?,
        (oreq_dt.symbol == req_pid)?,
        request_output_valid(value.lovelace_of(output.value), oreq_dt, cfg),
        (oreq_dt.borrower == hash_sorted(
          list.find(tx.inputs, fn(i) { i.output_reference == out_ref }),
        ))?,
        mint_only_one(tx, req_pid, oreq_dt.borrower),
      }
    _ -> fail @"only 1 request output is allowed"
  }
}

pub fn spending_request_update(
  cfg: BondIssueConfig,
  tx: Transaction,
  sreq: Input,
  sreq_dt: RequestDatum,
) -> Bool {
  let outs =
    list.foldr(
      tx.outputs,
      BorrowRequestOutput { oreq_valid: 0, nft_valid: False },
      fn(o, z) { get_borrow_request_output(cfg, o, sreq.output, sreq_dt, z) },
    )
  and {
    outs.nft_valid?,
    (outs.oreq_valid < 2)?,
  }
}

pub fn spending_bond_create(
  cfg: BondIssueConfig,
  tx: Transaction,
  sreq: Input,
  sreq_dt: RequestDatum,
  out_ref: Option<Input>,
  bond_sk: ScriptKeyHash,
  nft_pid: PolicyId,
  bond_pid: PolicyId,
) -> Bool {
  let bond_credential = ScriptCredential(bond_sk)
<<<<<<< borrow-request/lib/borrow_request/constraint.ak
=======
  // đảm bảo trong inputs của giao dịch ko có bond utxo để trách nách phí phải trả
>>>>>>> borrow-request/lib/borrow_request/constraint.ak
  expect None =
    list.find(
      tx.inputs,
      fn(i) { i.output.address.payment_credential == bond_credential },
    )
  //
  let bond_addr =
    Address {
      payment_credential: bond_credential,
      stake_credential: sreq.output.address.stake_credential,
    }
  let outs =
    list.foldr(
      tx.outputs,
      BondCreateOutput { oreq_valid: 0, obond: None, mint_qty: 0 },
      fn(o, z) {
        get_bond_create_output(cfg, bond_addr, o, sreq.output, sreq_dt, z)
      },
    )

  and {
    // trace @"borrow request output invalid"
    (outs.oreq_valid < 2)?,
    // trace @"Not found bond output"
    (outs.obond != None)?,
    bond_output_valid(cfg, tx, sreq_dt, out_ref, nft_pid, bond_pid, outs),
  }
}

fn bond_output_valid(
  cfg: BondIssueConfig,
  tx: Transaction,
  sreq_dt: RequestDatum,
  out_ref: Option<Input>,
  nft_pid: PolicyId,
  bond_pid: PolicyId,
  outs: BondCreateOutput,
) -> Bool {
  // expect Some((_oreq_dt, _oreq)) = outs.oreq
  expect Some((obond_dt, obond)) = outs.obond
  let bond_name = hash_sorted_salt(out_ref, sreq_dt.borrower)
  let bond_qty_must_mint =
    if outs.oreq_valid == 0 {
      // bond create all remain
      sreq_dt.requested - sreq_dt.issued
    } else {
      // bond create partial remain
      outs.mint_qty
    }
  let curr_epoch =
    get_current_epoch_with_ttl(
      tx.validity_range,
      cfg.epoch,
      when cfg.platform.tx_ttl is {
        Some(i) -> i
        _ -> 3 * 60
      } * cfg.slot.slot_length,
    )
  and {
    (obond_dt.duration == sreq_dt.duration)?,
    (obond_dt.bond_symbol == bond_pid)?,
    (obond_dt.token_name == bond_name)?,
    (obond_dt.bond_amount == bond_qty_must_mint)?,
    (obond_dt.buffer == sreq_dt.buffer)?,
    (obond_dt.fee == sreq_dt.fee)?,
    // (obond_dt.borrower == sreq_dt.borrower)?,
    (obond_dt.start == curr_epoch - cfg.epoch.epoch_boundary_as_epoch)?,
    tx_mint_valid(tx, nft_pid, obond_dt),
    bond_value_valid(cfg, sreq_dt, nft_pid, obond_dt, obond),
  }
}

fn tx_mint_valid(
  tx: Transaction,
  nft_pid: PolicyId,
  obond_dt: BondDatum,
) -> Bool {
  let (nft_qty_must_minted, bond_qty_must_minted) =
    dict.foldr(
      value.to_dict(value.from_minted_value(tx.mint)),
      (0, 0),
      fn(k, v, z) {
        if k == nft_pid || k == obond_dt.bond_symbol {
          let qty = dict.get(v, obond_dt.token_name) |> option.or_else(0)
          if k == nft_pid {
            (qty, z.2nd)
          } else {
            (z.1st, qty)
          }
        } else {
          z
        }
      },
    )
  and {
    (nft_qty_must_minted == 1)?,
    (bond_qty_must_minted == obond_dt.bond_amount)?,
  }
}

fn bond_value_valid(
  cfg: BondIssueConfig,
  sreq_dt: RequestDatum,
  nft_pid: PolicyId,
  obond_dt: BondDatum,
  obond: Output,
) -> Bool {
  let obond_principal = obond_dt.bond_amount * cfg.platform.bond_face_value
  let obond_epo_rewards =
    obond_principal * sreq_dt.apr / cfg.basis.base / cfg.epoch.year_to_epoch
  and {
    (value.lovelace_of(obond_dt.epo_rewards) == obond_epo_rewards)?,
    bond_asset_valid(
      cfg,
      sreq_dt,
      nft_pid,
      obond_dt,
      obond,
      obond_principal,
      obond_epo_rewards,
    ),
  }
}

fn bond_asset_valid(
  cfg: BondIssueConfig,
  sreq_dt: RequestDatum,
  nft_pid: PolicyId,
  obond_dt: BondDatum,
  obond: Output,
  obond_principal: Int,
  obond_epo_rewards: Int,
) -> Bool {
  let (obond_nft, obond_lovelace) =
    dict.foldr(
      value.to_dict(obond.value),
      (0, 0),
      fn(k, v, z) {
        if k == value.ada_policy_id {
          (z.1st, dict.get(v, value.ada_asset_name) |> option.or_else(0))
        } else if k == nft_pid {
          (dict.get(v, obond_dt.token_name) |> option.or_else(0), z.2nd)
        } else {
          z
        }
      },
    )
  let obond_apy = cfg.basis.base - obond_dt.fee
  let obond_required_premium =
    obond_epo_rewards * sreq_dt.prepaid * obond_apy / cfg.basis.base
  and {
    (obond_nft == 1)?,
    (obond_lovelace >= obond_principal + obond_required_premium)?,
  }
}
