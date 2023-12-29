use aiken/list
use aiken/transaction.{InlineDatum, Output, Transaction}
use aiken/transaction/credential.{Address}
use aiken/transaction/value.{PolicyId, Value}
use bond_issue/types.{BondDatum, BondIssueConfig} as bond_issue_types
use common/time.{get_current_epoch_with_ttl}

pub fn spending_with_fee(
  cfg: BondIssueConfig,
  tx: Transaction,
  sbond: Output,
  sbond_addr: Address,
  sbond_dt: BondDatum,
  nft_pid: PolicyId,
) -> Bool {
  when
    list.filter(
      tx.inputs,
      fn(i) {
        i.output.address.payment_credential == sbond_addr.payment_credential
      },
    )
  is {
    [ibond] ->
      if (ibond.output.address == sbond_addr)? {
        let sbond_balance = value.lovelace_of(sbond.value)
        let epoch_curr =
          get_current_epoch_with_ttl(
            tx.validity_range,
            cfg.epoch,
            cfg.platform.tx_ttl,
            cfg.slot.slot_length,
          )
        let epoch_start = sbond_dt.start + cfg.epoch.epoch_boundary_as_epoch
        let epoch_end = epoch_start + sbond_dt.duration

        let epoch_passed = epoch_curr - epoch_start + 1
        // let epoch_remain = epoch_end - epoch_passed
        let epoch_required_premium = epoch_passed + sbond_dt.buffer
        let sbond_principal =
          sbond_dt.bond_amount * cfg.platform.bond_face_value
        let sbond_interest_paid = sbond_balance - sbond_principal
        let sbond_paid_epoch =
          sbond_interest_paid / value.lovelace_of(sbond_dt.epo_rewards)
        and {
          or {
            (epoch_curr >= epoch_end)?,
            (sbond_paid_epoch < epoch_required_premium)?,
          },
          redeem_with_fee_valid(
            cfg,
            tx,
            sbond_balance,
            value.without_lovelace(sbond.value),
            sbond_addr,
            sbond_dt,
            nft_pid,
            sbond_interest_paid,
          ),
        }
      } else {
        False
      }
    _ -> fail @"must only one bond utxo input"
  }
}

pub fn redeem_with_fee_valid(
  cfg: BondIssueConfig,
  tx: Transaction,
  sbond_balance: Int,
  sbond_assets: Value,
  sbond_addr: Address,
  sbond_dt: BondDatum,
  nft_pid: PolicyId,
  sbond_interest_paid: Int,
) -> Bool {
  let mint_value = value.from_minted_value(tx.mint)
  let bond_redeem_amt =
    when
      list.foldr(
        tx.outputs,
        (None, 0),
        fn(o, z) {
          if and {
            o.address == sbond_addr,
            value.quantity_of(o.value, nft_pid, sbond_dt.token_name) == 1,
          } {
            if (z.1st == None)? {
              (Some(o), z.2nd)
            } else {
              fail @"only 1 bond output is allowed"
            }
          } else if o.address == cfg.platform.fee_addr {
            if (z.2nd == 0)? {
              (z.1st, value.lovelace_of(o.value))
            } else {
              fail @"only 1 platform fee output is allowed"
            }
          } else {
            z
          }
        },
      )
    is {
      (Some(obond), ofee) -> {
        expect obond_dt: BondDatum =
          when obond.datum is {
            InlineDatum(d) -> d
            _ ->
              fail @"borrow_position/redeem.redeem_valid: only supports InlineDatum for bond"
          }
        let redeem_amt = sbond_dt.bond_amount - obond_dt.bond_amount
        let redeem_principal = redeem_amt * cfg.platform.bond_face_value
        let redeem_val = sbond_interest_paid * redeem_amt / sbond_dt.bond_amount
        if and {
          (obond_dt.bond_symbol == sbond_dt.bond_symbol)?,
          (obond_dt.token_name == sbond_dt.token_name)?,
          (obond_dt.borrower == sbond_dt.borrower)?,
          (obond_dt.epo_rewards == sbond_dt.epo_rewards)?,
          (obond_dt.duration == sbond_dt.duration)?,
          (obond_dt.bond_amount < sbond_dt.bond_amount)?,
          (obond_dt.buffer == sbond_dt.buffer)?,
          (obond_dt.fee == sbond_dt.fee)?,
          (obond_dt.start == sbond_dt.start)?,
          (value.without_lovelace(obond.value) == sbond_assets)?,
          (value.lovelace_of(obond.value) == sbond_balance - redeem_principal - redeem_val)?,
          (ofee >= redeem_val * sbond_dt.fee / cfg.basis.base)?,
        } {
          redeem_amt
        } else {
          fail
        }
      }
      (None, ofee) ->
        if and {
          (ofee >= sbond_interest_paid * sbond_dt.fee / cfg.basis.base)?,
          (value.quantity_of(mint_value, nft_pid, sbond_dt.token_name) == -1)?,
        } {
          sbond_dt.bond_amount
        } else {
          fail
        }
    }

  (value.quantity_of(mint_value, sbond_dt.bond_symbol, sbond_dt.token_name) == -bond_redeem_amt)?
}

pub fn spending_without_fee(
  cfg: BondIssueConfig,
  tx: Transaction,
  sbond: Output,
  sbond_addr: Address,
  sbond_dt: BondDatum,
  nft_pid: PolicyId,
) -> Bool {
  let sbond_balance = value.lovelace_of(sbond.value)
  let epoch_curr =
    get_current_epoch_with_ttl(
      tx.validity_range,
      cfg.epoch,
      cfg.platform.tx_ttl,
      cfg.slot.slot_length,
    )
  let epoch_start = sbond_dt.start + cfg.epoch.epoch_boundary_as_epoch
  let epoch_end = epoch_start + sbond_dt.duration

  let epoch_passed = epoch_curr - epoch_start + 1
  // let epoch_remain = epoch_end - epoch_passed
  let epoch_required_premium = epoch_passed + sbond_dt.buffer
  let sbond_principal = sbond_dt.bond_amount * cfg.platform.bond_face_value
  let sbond_paid = sbond_balance - sbond_principal
  let sbond_paid_epoch = sbond_paid / value.lovelace_of(sbond_dt.epo_rewards)
  and {
    or {
      (epoch_curr >= epoch_end)?,
      (sbond_paid_epoch < epoch_required_premium)?,
    },
    redeem_without_fee_valid(
      tx,
      sbond_balance,
      value.without_lovelace(sbond.value),
      sbond_addr,
      sbond_dt,
      nft_pid,
    ),
  }
}

pub fn redeem_without_fee_valid(
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
      list.filter(
        tx.outputs,
        fn(o) {
          o.address == sbond_addr && //
          value.quantity_of(o.value, nft_pid, sbond_dt.token_name) == 1
        },
      )
    is {
      [obond] -> {
        expect obond_dt: BondDatum =
          when obond.datum is {
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
            (value.without_lovelace(obond.value) == sbond_assets)?,
            (value.lovelace_of(obond.value) == sbond_balance - redeem_val)?,
          }

        if obond_dt_valid {
          redeem_amt
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
