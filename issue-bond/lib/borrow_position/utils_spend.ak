use aiken/bytearray
use aiken/dict.{Dict}
use aiken/transaction.{Output}
use aiken/transaction/value
use bond_issue/types.{BondDatum, BondIssueConfig} as bond_issue_types

pub fn fee_pay_interest_valid(
  cfg: BondIssueConfig,
  ibond_utxos: Dict<ByteArray, (BondDatum, Output, Int)>,
  obond_utxos: Dict<ByteArray, (BondDatum, Output, Int)>,
  ofee: Option<Output>,
) -> Bool {
  when ofee is {
    Some(o) -> {
      let obond_data =
        dict.union_with(
          ibond_utxos,
          obond_utxos,
          fn(_, v1, v2) {
            // v1 => ibond
            let (ibond_dt, ibond, _) = v1
            // v2 => obond
            let (obond_dt, obond, _) = v2

            let (ibond_lovelace, obond_lovelace) =
              (value.lovelace_of(ibond.value), value.lovelace_of(obond.value))
            let (ibond_assets, obond_assets) =
              (
                value.without_lovelace(ibond.value),
                value.without_lovelace(obond.value),
              )

            if and {
              (obond.address == ibond.address)?,
              (obond_assets == ibond_assets)?,
              (obond_dt.epo_rewards == ibond_dt.epo_rewards)?,
              (obond_dt.duration == ibond_dt.duration)?,
              (obond_dt.bond_amount == ibond_dt.bond_amount)?,
              (obond_dt.buffer == ibond_dt.buffer)?,
              (obond_dt.fee == ibond_dt.fee)?,
              (obond_dt.start == ibond_dt.start)?,
            } {
              let interest = obond_lovelace - ibond_lovelace
              let interest_min =
                value.lovelace_of(ibond_dt.epo_rewards) * (
                  cfg.basis.base - ibond_dt.fee
                ) / cfg.basis.base
              if (interest >= interest_min)? {
                Some(
                  (obond_dt, obond, interest * ibond_dt.fee / cfg.basis.base),
                )
              } else {
                fail
              }
            } else {
              fail @"borrow_position/utils_spend.fee_pay_interest_valid: bond output invalid"
            }
          },
          bytearray.compare,
        )
      let total_fee =
        dict.foldr(
          obond_data,
          0,
          fn(_, v, z) {
            let (_, _, f) = v
            z + f
          },
        )
      (value.lovelace_of(o.value) >= total_fee)?
    }
    _ ->
      fail @"borrow_position/utils_spend.fee_pay_interest_valid: not found platform fee output"
  }
}
