use aiken/list
use aiken/transaction.{InlineDatum, Output, Transaction}
use aiken/transaction/credential.{Address}
use aiken/transaction/value.{PolicyId}
use bond_issue/types.{BondDatum}

pub fn spending(
  tx: Transaction,
  sbond: Output,
  sbond_addr: Address,
  sbond_dt: BondDatum,
  borrower_pid: PolicyId,
  nft_pid: PolicyId,
) -> Bool {
  when
    list.find(
      tx.inputs,
      fn(i) {
        value.quantity_of(i.output.value, borrower_pid, sbond_dt.borrower) == 1
      },
    )
  is {
    Some(_) -> constraint(tx, sbond, sbond_addr, sbond_dt, nft_pid)
    _ ->
      fail @"borrow_position/change_stake_key.spending: not found borrower nft of bond utxo"
  }
}

pub fn constraint(
  tx: Transaction,
  sbond: Output,
  sbond_addr: Address,
  sbond_dt: BondDatum,
  nft_pid: PolicyId,
) -> Bool {
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
            fail @"borrow_position/change_stake_key.constraint: one bond input must only a bond output allowed"
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
            fail @"borrow_position/change_stake_key.constraint: only supports InlineDatum for bond"
        }
      and {
        (obond_dt.bond_symbol == sbond_dt.bond_symbol)?,
        (obond_dt.token_name == sbond_dt.token_name)?,
        (obond_dt.borrower == sbond_dt.borrower)?,
        (obond_dt.epo_rewards == sbond_dt.epo_rewards)?,
        (obond_dt.duration == sbond_dt.duration)?,
        (obond_dt.bond_amount == sbond_dt.bond_amount)?,
        (obond_dt.buffer == sbond_dt.buffer)?,
        (obond_dt.fee == sbond_dt.fee)?,
        (obond_dt.start == sbond_dt.start)?,
        (o.value == sbond.value)?,
      }
    }
    _ ->
      fail @"borrow_position/change_stake_key.constraint: bond utxo output invalid"
  }
}
