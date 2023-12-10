use aiken/dict
use aiken/math
use aiken/option
use aiken/transaction.{InlineDatum, Output, Transaction}
use aiken/transaction/credential.{Address}
use aiken/transaction/value.{AssetName, PolicyId}
use bond_issue/types.{BondDatum,
  BondIssueConfig, RequestDatum} as bond_issue_types
use borrow_request/types.{BondCreateOutput, BorrowRequestOutput}

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
    (oreq_dt.epo_rewards >= ( oreq_dt.requested - oreq_dt.issued ) * cfg.platform.bond_face_value * oreq_dt.apr / cfg.basis_points.base / cfg.epoch.year_to_epoch)?,
    (required_premium >= oreq_dt.epo_rewards * oreq_dt.prepaid)?,
  }
}

pub fn mint_only_one(tx: Transaction, pid: PolicyId, tn: AssetName) -> Bool {
  let mint_assets = value.from_minted_value(tx.mint) |> value.tokens(pid)
  and {
    (dict.size(mint_assets) == 1)?,
    (option.or_else(dict.get(mint_assets, tn), 0) == 1)?,
  }
}

pub fn get_borrow_request_output(
  cfg: BondIssueConfig,
  o: Output,
  ireq: Output,
  ireq_dt: RequestDatum,
  zero: BorrowRequestOutput,
) -> BorrowRequestOutput {
  if o.address.payment_credential == ireq.address.payment_credential {
    expect oreq_dt: RequestDatum =
      when o.datum is {
        InlineDatum(d) -> d
        _ -> fail @"only supports InlineDatum for request"
      }
    if and {
      oreq_dt.symbol == ireq_dt.symbol,
      oreq_dt.borrower == ireq_dt.borrower,
    } {
      if zero.oreq_valid == 0 {
        if and {
          (oreq_dt.issued == ireq_dt.issued)?,
          (o.address.stake_credential != None)?,
          request_output_valid(value.lovelace_of(o.value), oreq_dt, cfg),
        } {
          // trace @"borrow request output valid"
          BorrowRequestOutput { ..zero, oreq_valid: 1 }
        } else {
          // trace @"borrow request output2b405c773982c6cddf1d8b8a80769a84851f3ce21febbb227777b3ba43be14f1 invalid"
          BorrowRequestOutput { ..zero, oreq_valid: 2 }
        }
      } else {
        fail @"one borrow request input allows only one borrow request output"
      }
    } else {
      zero
    }
  } else if !zero.nft_valid && value.quantity_of(
    o.value,
    ireq_dt.symbol,
    ireq_dt.borrower,
  ) > 0 {
    BorrowRequestOutput { ..zero, nft_valid: True }
  } else {
    zero
  }
}

pub fn get_bond_create_output(
  cfg: BondIssueConfig,
  bond_addr: Address,
  o: Output,
  ireq: Output,
  ireq_dt: RequestDatum,
  zero: BondCreateOutput,
) -> BondCreateOutput {
  if o.address.payment_credential == ireq.address.payment_credential {
    expect oreq_dt: RequestDatum =
      when o.datum is {
        InlineDatum(d) -> d
        _ -> fail @"only supports InlineDatum for borrow request"
      }
    if and {
      oreq_dt.symbol == ireq_dt.symbol,
      oreq_dt.borrower == ireq_dt.borrower,
    } {
      if zero.oreq_valid == 0 {
        if and {
          (o.address.stake_credential == ireq.address.stake_credential)?,
          (oreq_dt.apr == ireq_dt.apr)?,
          (oreq_dt.duration == ireq_dt.duration)?,
          (oreq_dt.requested == ireq_dt.requested)?,
          (oreq_dt.issued > ireq_dt.issued)?,
          (oreq_dt.prepaid == ireq_dt.prepaid)?,
          (oreq_dt.buffer == ireq_dt.buffer)?,
          (oreq_dt.fee == ireq_dt.fee)?,
          request_output_valid(value.lovelace_of(o.value), oreq_dt, cfg),
        } {
          // trace @"borrow request output valid"
          BondCreateOutput {
            ..zero,
            oreq_valid: 1,
            mint_qty: oreq_dt.issued - ireq_dt.issued,
          }
        } else {
          // trace @"borrow request output invalid"
          BondCreateOutput { ..zero, oreq_valid: 2 }
        }
      } else {
        fail @"one borrow request input allows only one borrow request output"
      }
    } else {
      zero
    }
  } else if o.address == bond_addr {
    expect obond_dt: BondDatum =
      when o.datum is {
        InlineDatum(d) -> d
        _ -> fail @"only supports InlineDatum for bond"
      }
    if obond_dt.borrower == ireq_dt.borrower {
      if zero.obond == None {
        BondCreateOutput { ..zero, obond: Some((obond_dt, o)) }
      } else {
        fail @"one borrow request allows only one bond output"
      }
    } else {
      zero
    }
  } else {
    zero
  }
}
