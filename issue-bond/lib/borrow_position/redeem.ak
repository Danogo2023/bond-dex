use aiken/list
use aiken/transaction.{InlineDatum, Output, Transaction}
use aiken/transaction/credential.{Address}
use aiken/transaction/value.{PolicyId, Value}
use bond_issue/types.{BondDatum, BondIssueConfig} as bond_issue_types
use common/time.{get_current_epoch_with_ttl}

pub fn spending(
  cfg: BondIssueConfig,
  tx: Transaction,
  sbond: Output,
  sbond_addr: Address,
  sbond_dt: BondDatum,
  nft_pid: PolicyId,
) -> Bool {
  let sbond_balance = value.lovelace_of(sbond.value)
  and {
    bond_violate(cfg, tx, sbond_balance, sbond_dt),
    redeem_valid(
      tx,
      sbond_balance,
      value.without_lovelace(sbond.value),
      sbond_addr,
      sbond_dt,
      nft_pid,
    ),
  }
}

pub fn bond_violate(
  cfg: BondIssueConfig,
  tx: Transaction,
  sbond_balance: Int,
  sbond_dt: BondDatum,
) -> Bool {
  let epoch_curr =
    get_current_epoch_with_ttl(
      tx.validity_range,
      cfg.epoch,
      cfg.platform.tx_ttl,
      cfg.slot.slot_length,
    )
  let epoch_start = sbond_dt.start + cfg.epoch.epoch_boundary_as_epoch
  let epoch_end = epoch_start + sbond_dt.duration
  or {
    (epoch_curr >= epoch_end)?,
    epoch_required_premium_valid(
      cfg,
      sbond_balance,
      sbond_dt,
      epoch_curr,
      epoch_start,
    ),
  }
}

fn epoch_required_premium_valid(
  cfg: BondIssueConfig,
  sbond_balance: Int,
  sbond_dt: BondDatum,
  epoch_curr: Int,
  epoch_start: Int,
) -> Bool {
  let epoch_passed = epoch_curr - epoch_start + 1
  // let epoch_remain = epoch_end - epoch_passed
  let epoch_required_premium = epoch_passed + sbond_dt.buffer
  let principal = sbond_dt.bond_amount * cfg.platform.bond_face_value
  let paid = sbond_balance - principal
  let paid_epoch = paid / value.lovelace_of(sbond_dt.epo_rewards)
  (paid_epoch < epoch_required_premium)?
}

pub fn redeem_valid(
  tx: Transaction,
  sbond_balance: Int,
  sbond_assets: Value,
  sbond_addr: Address,
  sbond_dt: BondDatum,
  nft_pid: PolicyId,
) -> Bool {
  let mint_value = value.from_minted_value(tx.mint)
  let bond_redeem_amt =
    when
      list.foldl(
        tx.outputs,
        None,
        fn(o, z) {
          if and {
            o.address.payment_credential == sbond_addr.payment_credential,
            value.quantity_of(o.value, nft_pid, sbond_dt.token_name) == 1,
          } {
            if (z == None)? {
              Some(o)
            } else {
              fail @"borrow_position/redeem.redeem_valid: one bond input must only a bond output allowed"
            }
          } else {
            z
          }
        },
      )
    is {
      Some(o) -> {
        expect obond_dt: BondDatum =
          when o.datum is {
            InlineDatum(d) -> d
            _ ->
              fail @"borrow_position/redeem.redeem_valid: only supports InlineDatum for bond"
          }
        let redeem_amt = sbond_dt.bond_amount - obond_dt.bond_amount
        let redeem_val = sbond_balance / sbond_dt.bond_amount * redeem_amt
        let obond_dt_valid = and {
            (obond_dt.bond_symbol == sbond_dt.bond_symbol)?,
            (obond_dt.token_name == sbond_dt.token_name)?,
            (obond_dt.borrower == sbond_dt.borrower)?,
            (obond_dt.epo_rewards == sbond_dt.epo_rewards)?,
            (obond_dt.duration == sbond_dt.duration)?,
            (obond_dt.bond_amount < sbond_dt.bond_amount)?,
            (obond_dt.buffer == sbond_dt.buffer)?,
            (obond_dt.fee == sbond_dt.fee)?,
            (obond_dt.start == sbond_dt.start)?,
            (value.without_lovelace(o.value) == sbond_assets)?,
            (value.lovelace_of(o.value) == sbond_balance - redeem_val)?,
          }

        if obond_dt_valid {
          redeem_val
        } else {
          fail
        }
      }
      _ ->
        if
        (value.quantity_of(mint_value, nft_pid, sbond_dt.token_name) == -1)?{
        
          sbond_dt.bond_amount
        } else {
          fail
        }
    }

  (value.quantity_of(mint_value, sbond_dt.bond_symbol, sbond_dt.token_name) == -bond_redeem_amt)?
}
