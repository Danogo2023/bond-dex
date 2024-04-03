// Bid Limit Multi
use aiken/dict.{Dict}
use aiken/list
use aiken/time.{PosixTime} as aiken_time
use aiken/transaction/value.{Value}
use bond/types.{EscrowDatum, EscrowInfo, PlatformConfig} as bond_types
use bond/utils.{get_day_to_maturity} as bond_utils
use common/string.{bconcat_3} as common_string
use common/time.{Basis, EpochTime} as common_time
use common/types.{AssetUnit, Error, Lovelace, OK, Result}

pub type EscrowRef =
  Dict<AssetUnit, EscrowInfo>

pub fn get_escrow_info(
  platform_cfg: PlatformConfig,
  bond_unit: AssetUnit,
  escrow_bal: Lovelace,
  escrow_dt: EscrowDatum,
  escrow_epo_rewards: Lovelace,
  tx_time: PosixTime,
  epo_curr: EpochTime,
) -> Result<EscrowInfo, String> {
  let escrow_epo_start: EpochTime =
    escrow_dt.start + platform_cfg.epoch.epoch_boundary_as_epoch
  let escrow_epo_end: EpochTime = escrow_epo_start + escrow_dt.duration
  // Tong epoch phai tra lai tinh den epoch hien tai
  let escrow_due_paid_epo: EpochTime =
    if epo_curr >= escrow_epo_end {
      escrow_dt.duration
    } else {
      epo_curr - escrow_epo_start + 1
    }
  // Tong tien lai Borrower can phai tra tinh den epoch hien tai
  let escrow_due_paid: Lovelace = escrow_due_paid_epo * escrow_epo_rewards
  // Tien goc cua toan bo bond phat hanh
  let escrow_principal: Lovelace =
    escrow_dt.bond_amount * platform_cfg.bond_face_value
  let escrow_bal_min: Lovelace = escrow_principal + escrow_due_paid
  if (escrow_bal >= escrow_bal_min)? {
    // Tong tien lai tich luy hien tai cho toan bo bond phat hanh
    let premium_paid: Lovelace = escrow_bal - escrow_principal
    // Tong tien lai tich luy hien tai tinh theo epoch cho toan bo bond phat hanh
    // let epo_premium_paid: EpochTime = premium_paid / escrow_epo_rewards
    // Tong so epoch ma Borrower tra du tinh tu epoch hien tai
    let interest_level: EpochTime =
      ( premium_paid - escrow_due_paid ) / escrow_epo_rewards
    let interest_max: Lovelace = escrow_epo_rewards * escrow_dt.duration
    // So epoch con lai cho den khi bond se duoc phep dong
    let closable_in: EpochTime =
      if or {
        escrow_due_paid_epo >= escrow_dt.duration,
        escrow_bal >= interest_max,
      } {
        escrow_epo_end - epo_curr
      } else {
        interest_level - escrow_dt.buffer + 1
      }
    if or {
      epo_curr > escrow_epo_end,
      closable_in <= 0,
    } {
      Error(bconcat_3(@"bond ", bond_unit, @" closable"))
    } else {
      // Tien phi Optim thu cua Borrower 3%
      let lender_rate: Basis = platform_cfg.basis.base - escrow_dt.otm_fee
      // Tong tien lai lender nhan duoc cua tat ca bond phat hanh khi ket thuc chu ky dao han
      let lender_interest: Lovelace =
        escrow_epo_rewards * escrow_dt.duration * lender_rate
      // Tong tien lai lender nhan duoc khi den ky dao han cua 1 bond da tru phi cua Optim 3%
      let interest_at_maturity: Lovelace =
        lender_interest / platform_cfg.basis.base / escrow_dt.bond_amount
      OK(
        EscrowInfo {
          bond_symbol: escrow_dt.bond_symbol,
          token_name: escrow_dt.token_name,
          bond_amount: escrow_dt.bond_amount,
          start_epoch: escrow_epo_start,
          end_epoch: escrow_epo_end,
          // Tong tien goc + lai cua 1 bond theo lai suat Optim ma lender nhan duoc 
          value_at_maturity: interest_at_maturity + platform_cfg.bond_face_value,
          // So ngay den ky dao han cua bond
          day_to_maturity: get_day_to_maturity(
            tx_time,
            escrow_epo_end,
            platform_cfg.epoch,
          ),
        },
      )
    }
  } else {
    Error(bconcat_3(@"bond ", bond_unit, @" missing interest"))
  }
}

/// Prove that the target value is contained inside another value. Each token
/// inside the target must exist inside the total value. The quantity of each
/// token must be at least the target amount or greater.
///
/// ```aiken
/// values.contains(payment_value, output_value)
/// ```
pub fn contains(target: Value, total: Value) -> Bool {
  let flat = target |> value.negate |> value.merge(total) |> value.flatten
  list.all(flat, fn(v) { v.3rd > 0 })
}
