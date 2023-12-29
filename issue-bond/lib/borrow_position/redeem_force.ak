use aiken/list
use aiken/transaction.{Output, Transaction}
use aiken/transaction/credential.{Address}
use aiken/transaction/value.{PolicyId}
use bond_issue/types.{BondDatum, BondIssueConfig} as bond_issue_types
use common/time.{get_current_epoch_with_ttl}

pub fn spending(
  cfg: BondIssueConfig,
  tx: Transaction,
  sbond: Output,
  sbond_addr: Address,
  sbond_dt: BondDatum,
  nft_pid: PolicyId,
  num_epoch_force: Int,
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
        let epoch_end =
          sbond_dt.start + cfg.epoch.epoch_boundary_as_epoch + sbond_dt.duration
        and {
          (epoch_curr >= epoch_end + num_epoch_force)?,
          redeem_with_fee_valid(
            cfg,
            tx,
            sbond_balance,
            sbond_addr,
            sbond_dt,
            nft_pid,
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
  sbond_addr: Address,
  sbond_dt: BondDatum,
  nft_pid: PolicyId,
) -> Bool {
  let ofee =
    list.foldr(
      tx.outputs,
      0,
      fn(o, z) {
        if and {
          o.address == sbond_addr,
          value.quantity_of(o.value, nft_pid, sbond_dt.token_name) == 1,
        } {
          fail @"bond output not is allowed"
        } else if o.address == cfg.platform.fee_addr {
          if (z == 0)? {
            value.lovelace_of(o.value)
          } else {
            fail @"only 1 platform fee output is allowed"
          }
        } else {
          z
        }
      },
    )
  and {
    (ofee >= sbond_balance)?,
    (value.quantity_of(
      value.from_minted_value(tx.mint),
      nft_pid,
      sbond_dt.token_name,
    ) == -1)?,
  }
}
