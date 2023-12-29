use aiken/dict
use aiken/list
use aiken/option
use aiken/transaction.{
  InlineDatum, Input, Output, ScriptContext, Spend, Transaction, ValidityRange,
}
use aiken/transaction/credential.{Address, PaymentCredential, ScriptCredential}
use aiken/transaction/value.{AssetName, MintedValue, PolicyId}
use bond_issue/types.{BondDatum, BondIssueConfig, RequestDatum}
use borrow_request/types.{BondCreateOutput} as borrow_request_types
use common/hash_out_refs.{hash_out_ref_salt}
use common/time.{get_current_epoch_with_ttl}
use common/types.{ScriptKeyHash} as common_types
use issue_bond/utils.{check_output_request_base}

pub fn spending(
  cfg: BondIssueConfig,
  ctx: ScriptContext,
  sreq_dt: RequestDatum,
  bond_skh: ScriptKeyHash,
  nft_pid: PolicyId,
  bond_pid: PolicyId,
  req_pid: PolicyId,
) -> Bool {
  expect Spend(sreq_out_ref) = ctx.purpose
  let tx = ctx.transaction
  let bond_pk = ScriptCredential(bond_skh)
  //
  when
    list.filter(
      tx.inputs,
      fn(i) {
        i.output.address.payment_credential == bond_pk || i.output_reference == sreq_out_ref
      },
    )
  is {
    [sreq] ->
      if
      (value.quantity_of(sreq.output.value, req_pid, sreq_dt.borrower) == 1)?{
      
        let bond_name =
          hash_out_ref_salt(sreq.output_reference, sreq_dt.borrower)
        when
          get_create_output(
            cfg,
            tx.outputs,
            bond_pk,
            sreq.output,
            sreq_dt,
            req_pid,
            nft_pid,
            bond_name,
          )
        is {
          (oreq_found, Some(obond), mint_qty) ->
            bond_output_valid(
              cfg,
              tx.validity_range,
              tx.mint,
              sreq_dt,
              obond,
              mint_qty,
              nft_pid,
              bond_pid,
              bond_name,
              req_pid,
              oreq_found,
            )
          (_, None, _) -> fail @"not found bond output"
        }
      } else {
        fail @"not found request nft at input"
      }
    _ ->
      fail @"borrow_request/bond_create.spending: bond utxo are not allowed in tx input"
  }
}

pub fn get_create_output(
  cfg: BondIssueConfig,
  outputs: List<Output>,
  bond_pk: PaymentCredential,
  sreq: Output,
  sreq_dt: RequestDatum,
  req_pid: PolicyId,
  nft_pid: PolicyId,
  bond_name: AssetName,
) -> BondCreateOutput {
  let bond_addr =
    Address {
      payment_credential: bond_pk,
      stake_credential: sreq.address.stake_credential,
    }
  list.foldr(
    outputs,
    (False, None, sreq_dt.requested - sreq_dt.issued),
    fn(o, z) {
      if and {
        o.address == sreq.address,
        value.quantity_of(o.value, req_pid, sreq_dt.borrower) == 1,
      } {
        expect oreq_dt: RequestDatum =
          when o.datum is {
            InlineDatum(d) -> d
            _ -> fail @"only supports InlineDatum for borrow request"
          }
        if and {
          (z.1st == False)?,
          //
          check_output_request_base(cfg, sreq, sreq_dt)?,
          (sreq_dt.requested >= sreq_dt.issued)?,
          (sreq_dt.issued >= 0)?,
          //
          (oreq_dt.symbol == sreq_dt.symbol)?,
          (oreq_dt.borrower == sreq_dt.borrower)?,
          (oreq_dt.apr == sreq_dt.apr)?,
          (oreq_dt.duration == sreq_dt.duration)?,
          (oreq_dt.requested == sreq_dt.requested)?,
          (oreq_dt.issued <= oreq_dt.requested)?,
          (oreq_dt.issued > sreq_dt.issued)?,
          (oreq_dt.issued >= 0)?,
          (oreq_dt.prepaid == sreq_dt.prepaid)?,
          (oreq_dt.buffer == sreq_dt.buffer)?,
          (oreq_dt.fee == sreq_dt.fee)?,
          //
          (oreq_dt.epo_rewards >= ( oreq_dt.requested - oreq_dt.issued ) * cfg.platform.bond_face_value * oreq_dt.apr / cfg.basis.base / cfg.epoch.year_to_epoch)?,
          (value.lovelace_of(o.value) >= oreq_dt.epo_rewards * oreq_dt.prepaid)?,
        } {
          (True, z.2nd, oreq_dt.issued - sreq_dt.issued)
        } else {
          fail
        }
      } else if and {
        o.address == bond_addr,
        value.quantity_of(o.value, nft_pid, bond_name) == 1,
      } {
        if (z.2nd == None)? {
          (z.1st, Some(o), z.3rd)
        } else {
          fail
        }
      } else {
        z
      }
    },
  )
}

fn bond_output_valid(
  cfg: BondIssueConfig,
  validity_range: ValidityRange,
  tx_mint: MintedValue,
  sreq_dt: RequestDatum,
  obond: Output,
  mint_qty: Int,
  nft_pid: PolicyId,
  bond_pid: PolicyId,
  bond_name: AssetName,
  req_pid: PolicyId,
  oreq_found: Bool,
) -> Bool {
  expect obond_dt: BondDatum =
    when obond.datum is {
      InlineDatum(d) -> d
      _ ->
        fail @"borrow_request/bond_create.bond_output_valid: only supports InlineDatum for bond"
    }
  let epoch_curr =
    get_current_epoch_with_ttl(
      validity_range,
      cfg.epoch,
      cfg.platform.tx_ttl,
      cfg.slot.slot_length,
    )
  and {
    (obond_dt.duration == sreq_dt.duration)?,
    (obond_dt.bond_symbol == bond_pid)?,
    (obond_dt.token_name == bond_name)?,
    (obond_dt.bond_amount > 0)?,
    (obond_dt.bond_amount == mint_qty)?,
    (obond_dt.buffer == sreq_dt.buffer)?,
    (obond_dt.fee == sreq_dt.fee)?,
    (obond_dt.borrower == sreq_dt.borrower)?,
    (obond_dt.start == epoch_curr - cfg.epoch.epoch_boundary_as_epoch)?,
    tx_mint_valid(tx_mint, nft_pid, obond_dt, req_pid, oreq_found),
    bond_value_valid(cfg, sreq_dt, nft_pid, obond_dt, obond),
  }
}

fn tx_mint_valid(
  tx_mint: MintedValue,
  nft_pid: PolicyId,
  obond_dt: BondDatum,
  req_pid: PolicyId,
  oreq_found: Bool,
) -> Bool {
  dict.foldr(
    value.to_dict(value.from_minted_value(tx_mint)),
    True,
    fn(k, v, z) {
      if k == nft_pid || k == req_pid || k == obond_dt.bond_symbol {
        let bond_qty = dict.get(v, obond_dt.token_name) |> option.or_else(0)
        if k == nft_pid && bond_qty != 1 {
          fail @"bond nft mint qty invalid"
        } else if k == obond_dt.bond_symbol && bond_qty != obond_dt.bond_amount {
          fail @"bond token mint qty invalid"
        } else {
          let req_qty = dict.get(v, obond_dt.borrower) |> option.or_else(0)
          if oreq_found == False && k == req_pid && req_qty != -1 {
            fail @"request nft burn qty invalid"
          } else {
            z
          }
        }
      } else {
        z
      }
    },
  )
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
  let required_premium = obond_epo_rewards * sreq_dt.prepaid
  and {
    (value.lovelace_of(obond_dt.epo_rewards) == obond_epo_rewards)?,
    bond_asset_valid(
      nft_pid,
      obond_dt,
      obond,
      obond_principal + required_premium,
    ),
  }
}

fn bond_asset_valid(
  nft_pid: PolicyId,
  obond_dt: BondDatum,
  obond: Output,
  obond_paid: Int,
) -> Bool {
  dict.foldr(
    value.to_dict(obond.value),
    True,
    fn(k, v, z) {
      if k == value.ada_policy_id || k == nft_pid {
        if
        k == value.ada_policy_id && (
          dict.get(v, value.ada_asset_name) |> option.or_else(0)
        ) < obond_paid{
        
          fail @"lovelace qty of bond ouput invalid"
        } else if k == nft_pid && (
          dict.get(v, obond_dt.token_name) |> option.or_else(0)
        ) != 1 {
          fail @"bond nft qty of bond ouput invalid"
        } else {
          z
        }
      } else {
        z
      }
    },
  )
}
