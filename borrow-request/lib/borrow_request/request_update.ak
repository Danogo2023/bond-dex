use aiken/list
use aiken/math
use aiken/transaction.{InlineDatum, Input, Output, Transaction}
use aiken/transaction/value.{PolicyId}
use bond_issue/types.{BondIssueConfig, RequestDatum} as bond_issue_types
use borrow_request/types.{BorrowRequestOutput}

pub fn spending(
  cfg: BondIssueConfig,
  tx: Transaction,
  sreq: Input,
  sreq_dt: RequestDatum,
  req_pid: PolicyId,
) -> Bool {
  let (found_oreq, found_borrower) =
    get_request_output(cfg, tx, sreq.output, sreq_dt, req_pid)
  and {
    found_borrower,
    or {
      found_oreq == True,
      (value.quantity_of(
        value.from_minted_value(tx.mint),
        req_pid,
        sreq_dt.borrower,
      ) == 1)?,
    },
  }
}

pub fn get_request_output(
  cfg: BondIssueConfig,
  tx: Transaction,
  sreq: Output,
  sreq_dt: RequestDatum,
  req_pid: PolicyId,
) -> BorrowRequestOutput {
  list.foldr(
    tx.outputs,
    (False, False),
    fn(o, z) {
      if and {
        o.address.payment_credential == sreq.address.payment_credential,
        value.quantity_of(o.value, req_pid, sreq_dt.borrower) == 1,
      } {
        expect oreq_dt: RequestDatum =
          when o.datum is {
            InlineDatum(d) -> d
            _ ->
              fail @"borrow_request/utils.get_request_output: only supports InlineDatum for request"
          }
        let oreq_valid = and {
            (z.1st == False)?,
            (oreq_dt.symbol == sreq_dt.symbol)?,
            (oreq_dt.borrower == sreq_dt.borrower)?,
            (oreq_dt.issued == sreq_dt.issued)?,
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
            (oreq_dt.epo_rewards >= ( oreq_dt.requested - oreq_dt.issued ) * cfg.platform.bond_face_value * oreq_dt.apr / cfg.basis.base / cfg.epoch.year_to_epoch)?,
            (value.lovelace_of(o.value) >= oreq_dt.epo_rewards * oreq_dt.prepaid)?,
          }
        if oreq_valid {
          (True, z.2nd)
        } else {
          fail
        }
      } else if value.quantity_of(o.value, sreq_dt.symbol, sreq_dt.borrower) > 0 {
        if (z.2nd == False)? {
          (z.1st, True)
        } else {
          fail
        }
      } else {
        z
      }
    },
  )
}
