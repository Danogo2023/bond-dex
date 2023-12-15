use aiken/dict
use aiken/math
use aiken/transaction.{
  InlineDatum, Input, Output, OutputReference, ScriptContext, Spend, Transaction,
}
use aiken/transaction/credential.{Address}
use aiken/transaction/value.{AssetName, PolicyId}
use bond_issue/types.{BondDatum, BondIssueConfig, RequestDatum}
use borrow_request/types.{BondCreateOutput, BorrowRequestOutput} as br_types
use common/util.{find_while}

pub fn get_out_ref(
  ctx: ScriptContext,
  out_ref: OutputReference,
) -> (Input, Option<Input>) {
  expect Spend(sout_ref) = ctx.purpose
  expect (Some(spending_input), out_ref_input) =
    find_while(
      ctx.transaction.inputs,
      (None, None),
      fn(i, z) {
        let r =
          if i.output_reference == sout_ref {
            (Some(i), z.2nd)
          } else if i.output_reference == out_ref {
            (z.1st, Some(i))
          } else {
            z
          }
        (r.1st != None && r.2nd != None, r)
      },
    )
  (spending_input, out_ref_input)
}

pub fn request_output_valid(
  required_premium: Int,
  oreq_dt: RequestDatum,
  cfg: BondIssueConfig,
) -> Bool {
  and {
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
    (oreq_dt.epo_rewards >= ( oreq_dt.requested - oreq_dt.issued ) * cfg.platform.bond_face_value * oreq_dt.apr / cfg.basis.base / cfg.epoch.year_to_epoch)?,
    (required_premium >= oreq_dt.epo_rewards * oreq_dt.prepaid)?,
  }
}

pub fn mint_only_one(
  tx: Transaction,
  req_pid: PolicyId,
  req_nft: AssetName,
) -> Bool {
  let (mint_nft, mint_count) =
    dict.foldr(
      value.from_minted_value(tx.mint) |> value.tokens(req_pid),
      (0, 0),
      fn(k, v, z) {
        if k == req_nft {
          (z.1st + v, z.2nd + 1)
        } else {
          (z.1st, z.2nd + 1)
        }
      },
    )
  and {
    (mint_count == 1)?,
    (mint_nft == 1)?,
  }
}

pub fn get_borrow_request_output(
  cfg: BondIssueConfig,
  o: Output,
  sreq: Output,
  sreq_dt: RequestDatum,
  z: BorrowRequestOutput,
) -> BorrowRequestOutput {
  if o.address.payment_credential == sreq.address.payment_credential {
    expect oreq_dt: RequestDatum =
      when o.datum is {
        InlineDatum(d) -> d
        _ ->
          fail @"borrow_request/utils.get_borrow_request_output: only supports InlineDatum for request"
      }
    if and {
      oreq_dt.symbol == sreq_dt.symbol,
      oreq_dt.borrower == sreq_dt.borrower,
    } {
      if (z.oreq_valid == 0)? {
        if and {
          (oreq_dt.issued == sreq_dt.issued)?,
          (o.address.stake_credential != None)?,
          request_output_valid(value.lovelace_of(o.value), oreq_dt, cfg),
        } {
          // trace @"borrow request output valid"
          BorrowRequestOutput { ..z, oreq_valid: 1 }
        } else {
          // trace @"borrow request output2b405c773982c6cddf1d8b8a80769a84851f3ce21febbb227777b3ba43be14f1 invalid"
          BorrowRequestOutput { ..z, oreq_valid: 2 }
        }
      } else {
        fail @"borrow_request/utils.get_borrow_request_output: one borrow request input allows only one borrow request output"
      }
    } else {
      z
    }
  } else if !z.nft_valid && value.quantity_of(
    o.value,
    sreq_dt.symbol,
    sreq_dt.borrower,
  ) > 0 {
    BorrowRequestOutput { ..z, nft_valid: True }
  } else {
    z
  }
}

pub fn get_bond_create_output(
  cfg: BondIssueConfig,
  bond_addr: Address,
  o: Output,
  sreq: Output,
  sreq_dt: RequestDatum,
  z: BondCreateOutput,
) -> BondCreateOutput {
  if o.address.payment_credential == sreq.address.payment_credential {
    expect oreq_dt: RequestDatum =
      when o.datum is {
        InlineDatum(d) -> d
        _ ->
          fail @"borrow_request/utils.get_bond_create_output: only supports InlineDatum for borrow request"
      }
    if and {
      oreq_dt.symbol == sreq_dt.symbol,
      oreq_dt.borrower == sreq_dt.borrower,
    } {
      if (z.oreq_valid == 0)? {
        if and {
          (o.address.stake_credential == sreq.address.stake_credential)?,
          (oreq_dt.apr == sreq_dt.apr)?,
          (oreq_dt.duration == sreq_dt.duration)?,
          (oreq_dt.requested == sreq_dt.requested)?,
          (oreq_dt.issued > sreq_dt.issued)?,
          (oreq_dt.prepaid == sreq_dt.prepaid)?,
          (oreq_dt.buffer == sreq_dt.buffer)?,
          (oreq_dt.fee == sreq_dt.fee)?,
          request_output_valid(value.lovelace_of(o.value), oreq_dt, cfg),
        } {
          // trace @"borrow request output valid"
          BondCreateOutput {
            ..z,
            oreq_valid: 1,
            mint_qty: oreq_dt.issued - sreq_dt.issued,
          }
        } else {
          // trace @"borrow request output invalid"
          BondCreateOutput { ..z, oreq_valid: 2 }
        }
      } else {
        fail @"borrow_request/utils.get_bond_create_output: one borrow request input allows only one borrow request output"
      }
    } else {
      z
    }
  } else if o.address == bond_addr {
    expect obond_dt: BondDatum =
      when o.datum is {
        InlineDatum(d) -> d
        _ ->
          fail @"borrow_request/utils.get_bond_create_output: only supports InlineDatum for bond"
      }
    if obond_dt.borrower == sreq_dt.borrower {
      if (z.obond == None)? {
        BondCreateOutput { ..z, obond: Some((obond_dt, o)) }
      } else {
        fail @"borrow_request/utils.get_bond_create_output: one borrow request allows only one bond output"
      }
    } else {
      z
    }
  } else {
    z
  }
}
