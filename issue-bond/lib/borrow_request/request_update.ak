use aiken/list
use aiken/transaction.{InlineDatum, Transaction}
use aiken/transaction/credential.{ScriptCredential, VerificationKeyCredential}
use aiken/transaction/value.{PolicyId}
use bond_issue/types.{BondIssueConfig, RequestDatum} as bond_issue_types
use borrow_request/types.{BorrowRequestOutput}
use issue_bond/utils.{check_output_request_base}

pub fn spending(
  cfg: BondIssueConfig,
  tx: Transaction,
  sreq_dt: RequestDatum,
  req_pid: PolicyId,
) -> Bool {
  let (oreq_found, borrower_found) =
    get_request_output(cfg, tx, sreq_dt, req_pid)
  let nft_burn_qty =
    value.quantity_of(
      value.from_minted_value(tx.mint),
      req_pid,
      sreq_dt.borrower,
    )
  and {
    borrower_found,
    or {
      oreq_found == True,
      (nft_burn_qty == -1)?,
    },
  }
}

pub fn get_request_output(
  cfg: BondIssueConfig,
  tx: Transaction,
  sreq_dt: RequestDatum,
  req_pid: PolicyId,
) -> BorrowRequestOutput {
  list.foldr(
    tx.outputs,
    (False, False),
    fn(o, z) {
      if and {
        when o.address.payment_credential is {
          VerificationKeyCredential(_) -> False
          ScriptCredential(_) -> True
        },
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
            (oreq_dt.issued >= 0)?,
            (o.address.stake_credential != None)?,
            check_output_request_base(cfg, o, oreq_dt)?,
            (oreq_dt.requested >= oreq_dt.issued)?,
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
