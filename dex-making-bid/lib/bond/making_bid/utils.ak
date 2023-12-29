// Bid Making
use aiken/bytearray
use aiken/cbor
use aiken/dict.{Dict}
use aiken/list
use aiken/string
use aiken/time.{PosixTime} as aiken_time
use aiken/transaction.{
  DatumHash, InlineDatum, Input, NoDatum, Output, Transaction,
}
use aiken/transaction/credential.{Address, ScriptCredential}
use aiken/transaction/value
use bond/types.{
  BondConfigMaking, BondType, EscrowConfig, EscrowDatum, EscrowInfo,
  PlatformConfig,
} as bond_types
use bond/utils.{get_day_to_maturity, get_garbage_collector_value} as bond_utils
use common/string.{bconcat_1, bconcat_3, to_unit_3} as common_string
use common/time.{Basis, EpochTime} as common_time
use common/types.{AssetUnit, Datums, Error, Lovelace, OK, Result}
use common/util.{data_valid, find_while}

fn check_data_valid(dt: String) -> Bool {
  let l1 =
    [["', 122([]), "], ["', 121([_ h'", "']), "]]
  find_while(
    l1,
    False,
    fn(i1, _) {
      let c1 =
        data_valid(
          bytearray.from_string(dt),
          "121([_ h'",
          list.concat(i1, [", ", ", ", ", ", ", h'", "', "]),
          "])",
        )
      (c1, c1)
    },
  )
}

pub fn garbage_collector(
  d: Data,
  tx: Transaction,
  cfg: BondConfigMaking,
) -> Bool {
  let dt = cbor.diagnostic(d)
  let bid_making_valid =
    if dt == @"121([])" {
      False
    } else {
      check_data_valid(dt)
    }
  if bid_making_valid {
    fail @"its datum valid"
  } else {
    when
      list.find(tx.outputs, fn(o) { o.address == cfg.exchange.garbage_addr })
    is {
      Some(o) ->
        when get_garbage_collector_value(tx) is {
          OK((val, assets)) -> and {
              (value.lovelace_of(o.value) >= val)?,
              (value.without_lovelace(o.value) == assets)?,
            }
          Error(e) -> fail e
        }
      _ -> fail @"not found garbage address output"
    }
  }
}

pub type EscrowRef =
  Dict<AssetUnit, EscrowInfo>

pub fn head_escrow_ref(
  platform_cfg: PlatformConfig,
  escrow_cfg: EscrowConfig,
  tx_ref_inputs: List<Input>,
  tx_datums: Datums,
  bond_types: List<BondType>,
  tx_time: PosixTime,
  epo_curr: EpochTime,
) -> Result<EscrowRef, String> {
  find_escrow_ref_with(
    escrow_cfg,
    tx_ref_inputs,
    tx_datums,
    bond_types,
    fn(escrow_ref, bond_unit, escrow_dt, escrow_input) {
      find_escrow_ref_finalize(
        platform_cfg,
        escrow_ref,
        bond_unit,
        escrow_dt,
        escrow_input,
        tx_time,
        epo_curr,
        True,
      )
    },
  )
}

fn find_escrow_ref_with(
  escrow_cfg: EscrowConfig,
  tx_ref_inputs: List<Input>,
  tx_datums: Datums,
  bond_types: List<BondType>,
  with: fn(EscrowRef, AssetUnit, EscrowDatum, Input) ->
    (Bool, Result<EscrowRef, String>),
) -> Result<EscrowRef, String> {
  find_while(
    tx_ref_inputs,
    OK(dict.new()),
    fn(i, z) {
      when i.output.address.payment_credential is {
        ScriptCredential(k) ->
          when dict.get(escrow_cfg, k) is {
            Some((escrow_nft_pid, bond_type)) ->
              if list.has(bond_types, bond_type) {
                when
                  value.tokens(i.output.value, escrow_nft_pid) |> dict.to_list
                is {
                  [(n, q)] ->
                    if q == 1 {
                      expect OK(escrow_ref) = z
                      let data =
                        when i.output.datum is {
                          NoDatum -> None
                          DatumHash(h) -> dict.get(tx_datums, h)
                          InlineDatum(d) -> Some(d)
                        }
                      when data is {
                        Some(dt) -> {
                          expect escrow_dt: EscrowDatum = dt
                          if n == escrow_dt.token_name {
                            with(
                              escrow_ref,
                              to_unit_3(
                                escrow_dt.bond_symbol,
                                @".",
                                escrow_dt.token_name,
                              ),
                              escrow_dt,
                              i,
                            )
                          } else {
                            (
                              True,
                              Error(
                                bconcat_1(
                                  bconcat_1(
                                    @"escrow policy id ",
                                    escrow_nft_pid,
                                    @" asset name invalid (expected: ",
                                  ),
                                  escrow_dt.token_name,
                                  bconcat_1(@", actual: ", n, @")"),
                                ),
                              ),
                            )
                          }
                        }
                        _ -> (True, Error(@"Escrow datum can't be None"))
                      }
                    } else {
                      (
                        True,
                        Error(
                          bconcat_3(
                            @"escrow asset ",
                            to_unit_3(escrow_nft_pid, @".", n),
                            bconcat_3(
                              @" qty invalid (expected: 1, actual: ",
                              string.from_int(q),
                              @")",
                            ),
                          ),
                        ),
                      )
                    }
                  _ ->
                    (
                      True,
                      Error(
                        bconcat_1(
                          @"escrow policy id ",
                          escrow_nft_pid,
                          @" asset invalid",
                        ),
                      ),
                    )
                }
              } else {
                (False, z)
              }
            _ -> (False, z)
          }
        _ -> (False, z)
      }
    },
  )
}

fn find_escrow_ref_finalize(
  platform_cfg: PlatformConfig,
  escrow_ref: EscrowRef,
  bond_unit: AssetUnit,
  escrow_dt: EscrowDatum,
  escrow_input: Input,
  tx_time: PosixTime,
  epo_curr: EpochTime,
  break: Bool,
) -> (Bool, Result<EscrowRef, String>) {
  // Tong tien lai moi epoch Borrower phai tra
  let escrow_epo_rewards = value.lovelace_of(escrow_dt.epo_rewards)
  if and {
    (escrow_dt.bond_amount > 0)?,
    (escrow_epo_rewards > 0)?,
  } {
    let escrow_bal: Lovelace = value.lovelace_of(escrow_input.output.value)
    when
      get_escrow_info(
        platform_cfg,
        bond_unit,
        escrow_bal,
        escrow_dt,
        escrow_epo_rewards,
        tx_time,
        epo_curr,
      )
    is {
      OK(escrow_info) ->
        (
          break,
          OK(
            dict.insert(
              escrow_ref,
              bond_unit,
              escrow_info,
              common_string.compare,
            ),
          ),
        )
      Error(s) -> (True, Error(s))
    }
  } else {
    (True, Error(bconcat_3(@"bond ", bond_unit, @" datum invalid")))
  }
}

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
