use aiken/bytearray
use aiken/dict.{Dict}
use aiken/list
use aiken/math
use aiken/transaction.{Input, Output}
use aiken/transaction/credential.{
  Address, ScriptCredential, VerificationKeyCredential,
}
use aiken/transaction/value.{AssetName}
use bond/types.{
  AskLimit, AskMaking, BidLimit, BidMaking, BizOutput, BizOutputInfo, BizTxInfo,
  BondConfig, Config, DatumOf, DatumType, DatumTypeAskLimit, DatumTypeAskMaking,
  DatumTypeBidLimit, DatumTypeBidMaking, EpochConfig, Error, EscrowDatum,
  EscrowInfo, EscrowInfoResult, OK, OrderDatum, OrderTypeDatum, OtherDatum,
  OwnerDatum, ScDatum,
}
use common/types.{Datums, PublicKeyHash} as common_types
use common/utils.{get_data, get_payment_key}

pub fn must_be_signed_by(
  pkh_valid: List<PublicKeyHash>,
  address: Address,
) -> Bool {
  list.has(pkh_valid, get_payment_key(address))
}

pub fn get_escrow_ref_inputs(
  ref_inputs: List<Input>,
  cfg: BondConfig,
) -> Option<Input> {
  list.find(
    ref_inputs,
    fn(i) {
      when i.output.address.payment_credential is {
        VerificationKeyCredential(_) -> False
        ScriptCredential(k) -> {
          let escrow_asset = value.tokens(i.output.value, cfg.escrow_policy_id)
          k == cfg.escrow_payment_key && dict.size(escrow_asset) == 1 && when
            list.at(dict.values(escrow_asset), 0)
          is {
            Some(v) -> v > 0
            None -> False
          }
        }
      }
    },
  )
}

pub fn get_escrow_info(
  cfg: BondConfig,
  escrow_lovelace: Int,
  escrow_datum: EscrowDatum,
  tx_posix_time: Int,
  current_epoch: Int,
  start_epoch: Int,
  end_epoch: Int,
) -> EscrowInfoResult<EscrowInfo, ByteArray> {
  // Tong tien lai moi epoch Borrower phai tra
  let epoch_rewards_lovelace = value.lovelace_of(escrow_datum.epo_rewards)
  // Tien goc cua toan bo bond phat hanh
  let principal_lovelace = escrow_datum.bond_amount * cfg.bond_face_value
  // Tong tien lai tich luy hien tai cho toan bo bond phat hanh
  let premium_paid_lovelace = escrow_lovelace - principal_lovelace
  // Tong tien lai tich luy hien tai tinh theo epoch cho toan bo bond phat hanh
  // let premium_paid_epoch =
  //   premium_paid_lovelace / epoch_rewards_lovelace
  // Tong epoch phai tra lai tinh den epoch hien tai
  let interest_due_paid_epoch =
    if current_epoch >= end_epoch {
      escrow_datum.duration
    } else {
      current_epoch - start_epoch + 1
    }
  // Tong tien lai Borrower can phai tra tinh den epoch hien tai
  let interest_due_paid_lovelace =
    interest_due_paid_epoch * epoch_rewards_lovelace
  // Tong so epoch ma Borrower tra du tinh tu epoch hien tai
  let interest_level_epoch =
    ( premium_paid_lovelace - interest_due_paid_lovelace ) / epoch_rewards_lovelace
  let interest_lovelace_max = escrow_datum.duration * epoch_rewards_lovelace
  // So epoch con lai cho den khi bond se duoc phep dong
  let closable_in =
    if
    interest_due_paid_epoch >= escrow_datum.duration || escrow_lovelace >= interest_lovelace_max{
    
      end_epoch - current_epoch
    } else {
      interest_level_epoch - escrow_datum.buffer + 1
    }
  if current_epoch > end_epoch || closable_in <= 0 {
    Error("Escrow closable")
  } else {
    // Tien phi Optim thu cua Borrower 3%
    let lend_after_fee = 1 * cfg.basis_points_ref_unit - escrow_datum.otm_fee
    // Tong tien lai lender nhan duoc cua tat ca bond phat hanh khi ket thuc chu ky dao han
    let lender_interest =
      epoch_rewards_lovelace * escrow_datum.duration * lend_after_fee
    // Tong tien lai lender nhan duoc khi den ky dao han cua 1 bond da tru phi cua Optim 3%
    let interest_at_maturity_one_bond_lovelace =
      lender_interest / cfg.basis_points_ref_unit / escrow_datum.bond_amount
    OK(
      EscrowInfo {
        token_name: escrow_datum.token_name,
        // Tong tien goc + lai cua 1 bond theo lai suat Optim ma lender nhan duoc 
        received_at_maturity_one_bond: interest_at_maturity_one_bond_lovelace + cfg.bond_face_value,
        // So ngay den ky dao han cua bond
        day_to_maturity: get_day_to_maturity(
          tx_posix_time,
          end_epoch,
          cfg.epoch_config,
        ),
      },
    )
  }
}

pub fn get_price_of_bond(
  received_at_maturity: Int,
  day_to_maturity: Int,
  yield: Int,
  basis_points_ref_unit: Int,
) -> Int {
  received_at_maturity * basis_points_ref_unit * basis_points_ref_unit / (
    basis_points_ref_unit * basis_points_ref_unit + yield * basis_points_ref_unit * day_to_maturity / 365
  )
}

pub fn get_milliseconds_of_day(epoch_config: EpochConfig) -> Int {
  epoch_config.epoch_length * 86400000 / epoch_config.epoch_length_base
}

pub fn get_day_to_maturity(
  tx_time: Int,
  end_epoch: Int,
  epoch_config: EpochConfig,
) -> Int {
  let maturity_time: Int =
    relative_epoch_to_posix_time_start(end_epoch, epoch_config)
  if tx_time > maturity_time {
    0
  } else {
    let time_of_day = get_milliseconds_of_day(epoch_config)
    let diff_time = maturity_time - tx_time
    let maturity_day = diff_time / time_of_day
    if diff_time % time_of_day == 0 {
      maturity_day
    } else {
      maturity_day + 1
    }
  }
}

pub fn posix_time_to_relative_epoch(
  posix_time: Int,
  epoch_config: EpochConfig,
) -> Int {
  ( posix_time - epoch_config.epoch_boundary ) / epoch_config.epoch_length + epoch_config.epoch_boundary_as_epoch
}

pub fn relative_epoch_to_posix_time_start(
  relative_epoch: Int,
  epoch_config: EpochConfig,
) -> Int {
  ( relative_epoch - epoch_config.epoch_boundary_as_epoch ) * epoch_config.epoch_length + epoch_config.epoch_boundary
}

pub fn relative_epoch_to_posix_time_end(
  relative_epoch: Int,
  epoch_config: EpochConfig,
) -> Int {
  relative_epoch_to_posix_time_start(relative_epoch, epoch_config) + epoch_config.epoch_length
}

pub fn bond_assets(
  left: Dict<AssetName, Int>,
  right: Dict<AssetName, Int>,
) -> Dict<AssetName, Int> {
  dict.union_with(
    left,
    right,
    fn(_, v1, v2) { Some(v1 + v2) },
    bytearray.compare,
  )
}

fn datum_owner_valid(
  conf: Config,
  pkh_valid: List<PublicKeyHash>,
  out_payment_key: ByteArray,
  out_requested_yield: Int,
) -> Bool {
  list.has(pkh_valid, out_payment_key)? && (math.clamp(
    out_requested_yield,
    conf.bond.basis_points_min,
    conf.bond.basis_points_max,
  ) == out_requested_yield)?
}

fn datum_epoch_valid(
  out_from_epoch: Int,
  out_to_epoch: Int,
  out_quantity: Int,
) -> Bool {
  (out_to_epoch >= out_from_epoch)? && (out_quantity > 0)?
}

fn datum_making_valid(
  conf: Config,
  spd_sc_payment_key: ByteArray,
  out_sc_payment_key: ByteArray,
  spd_margin: Int,
  out_margin: Int,
  out_requested_yield: Int,
) -> Bool {
  (out_sc_payment_key == spd_sc_payment_key)? && (out_margin == spd_margin)? && (math.clamp(
    out_margin + out_requested_yield,
    conf.bond.basis_points_min,
    conf.bond.basis_points_max,
  ) == out_margin + out_requested_yield)?
}

fn datum_is_valid(
  conf: Config,
  pkh_valid: List<PublicKeyHash>,
  spd_datum_type: DatumType,
  out_data: Data,
  spd_sc_payment_key: ByteArray,
  spd_datum: OrderDatum<Option<AskMaking>, Option<BidMaking>>,
  datum_of: DatumOf,
) -> Bool {
  when spd_datum_type is {
    DatumTypeAskLimit -> {
      expect out_datum: AskLimit = out_data
      datum_owner_valid(
        conf,
        pkh_valid,
        out_datum.owner_payment_key,
        out_datum.requested_yield,
      )
    }
    DatumTypeAskMaking -> {
      if datum_of == OwnerDatum {
        expect out_datum: BidMaking = out_data
        out_datum.requested_yield = 
      } else if datum_of == ScDatum {
        expect out_datum: AskMaking = out_data
        datum_owner_valid(
          conf,
          pkh_valid,
          out_datum.owner_payment_key,
          out_datum.requested_yield,
        ) && when spd_datum.bid is {
          Some(d) ->
            datum_making_valid(
              conf,
              spd_sc_payment_key,
              out_datum.bid_sc,
              d.margin,
              out_datum.margin,
              out_datum.requested_yield,
            )
          None -> False
        }
      } else {
        False
      }
    }
    DatumTypeBidLimit -> {
      expect out_datum: BidLimit = out_data
      datum_owner_valid(
        conf,
        pkh_valid,
        out_datum.owner_payment_key,
        out_datum.requested_yield,
      ) && datum_epoch_valid(
        out_datum.from_epoch,
        out_datum.to_epoch,
        out_datum.quantity,
      )
    }
    DatumTypeBidMaking -> {
      expect out_datum: BidMaking = out_data
      datum_owner_valid(
        conf,
        pkh_valid,
        out_datum.owner_payment_key,
        out_datum.requested_yield,
      ) && datum_epoch_valid(
        out_datum.from_epoch,
        out_datum.to_epoch,
        out_datum.quantity,
      ) && when spd_datum.ask is {
        Some(d) ->
          datum_making_valid(
            conf,
            spd_sc_payment_key,
            out_datum.ask_sc,
            d.margin,
            out_datum.margin,
            0 - out_datum.requested_yield,
          )
        None -> False
      }
    }
    _ -> False
  }
}

fn build_biz_output_info(
  self: BizOutputInfo,
  output: Output,
  bond_values: Dict<AssetName, Int>,
  datum_of: DatumOf,
  pkh_valid: List<PublicKeyHash>,
  datums: Datums,
  conf: Config,
  spd_datum_type: DatumType,
  spd_sc_payment_key: ByteArray,
  spd_datum: OrderTypeDatum<
    OrderDatum<Option<AskLimit>, Option<BidLimit>>,
    OrderDatum<Option<AskMaking>, Option<BidMaking>>,
  >,
) -> BizOutputInfo {
  let addresses =
    if list.has(self.addresses, output.address) {
      self.addresses
    } else {
      [output.address, ..self.addresses]
    }
  when dict.keys(bond_values) is {
    [] ->
      BizOutputInfo {
        addresses,
        bond_datum_valid: True,
        bond_outputs: self.bond_outputs,
        bond_assets: self.bond_assets,
        bond_qty: self.bond_qty,
        lovelace: self.lovelace + value.lovelace_of(output.value),
        other_outputs: [output, ..self.other_outputs],
      }
    _ -> {
      let bond_datum_valid =
        datum_of == OtherDatum || when get_data(datums, output.datum) is {
          Some(d) ->
            datum_is_valid(
              conf,
              pkh_valid,
              spd_datum_type,
              d,
              spd_sc_payment_key,
              spd_datum,
              datum_of,
            )
          None -> {
            trace @"not found datum"
            False
          }
        }
      BizOutputInfo {
        addresses,
        bond_datum_valid,
        bond_outputs: [output, ..self.bond_outputs],
        bond_assets: bond_assets(self.bond_assets, bond_values),
        bond_qty: dict.foldl(bond_values, self.bond_qty, fn(_, v, z) { v + z }),
        lovelace: self.lovelace + value.lovelace_of(output.value),
        other_outputs: self.other_outputs,
      }
    }
  }
}

fn build_biz_data(
  conf: Config,
  output: Output,
  owner: Address,
  sc: Address,
  pkh_valid: List<PublicKeyHash>,
  datums: Datums,
  data: BizOutput,
  spd_datum_type: DatumType,
  bond_policy_id: ByteArray,
  spd_datum: OrderTypeDatum<
    OrderDatum<Option<AskLimit>, Option<BidLimit>>,
    OrderDatum<Option<AskMaking>, Option<BidMaking>>,
  >,
) -> BizOutput {
  let bond_values = value.tokens(output.value, bond_policy_id)
  let biz_out_info =
    build_biz_output_info(
      if output.address == sc {
        data.sc
      } else if output.address == owner {
        data.owner
      } else if output.address == conf.market.address {
        data.market
      } else {
        data.other
      },
      output,
      bond_values,
      if output.address == sc {
        ScDatum
      } else if list.has(
        [DatumTypeAskMaking, DatumTypeBidMaking],
        spd_datum_type,
      ) && output.address == owner {
        OwnerDatum
      } else {
        OtherDatum
      },
      pkh_valid,
      datums,
      conf,
      spd_datum_type,
      get_payment_key(sc),
      spd_datum,
    )
  BizOutput {
    valid: biz_out_info.bond_datum_valid,
    unique_bonds: bond_assets(data.unique_bonds, bond_values),
    sc: when (output.address, sc) is {
      (a, b) if a == b -> biz_out_info
      _ -> data.sc
    },
    owner: when (output.address, owner) is {
      (a, b) if a == b -> biz_out_info
      _ -> data.owner
    },
    market: when (output.address, conf.market.address) is {
      (a, b) if a == b -> biz_out_info
      _ -> data.market
    },
    other: when (output.address, sc, owner, conf.market.address) is {
      (a, b, c, d) if a != b && a != c && a != d -> biz_out_info
      _ -> data.other
    },
  }
}

fn get_biz_output(
  conf: Config,
  outputs: List<Output>,
  owner: Address,
  sc: Address,
  pkh_valid: List<PublicKeyHash>,
  datums: Datums,
  recursive: BizOutput,
  spd_datum_type: DatumType,
  bond_policy_id: ByteArray,
  spd_datum: OrderTypeDatum<
    OrderDatum<Option<AskLimit>, Option<BidLimit>>,
    OrderDatum<Option<AskMaking>, Option<BidMaking>>,
  >,
) -> BizOutput {
  when outputs is {
    [] -> recursive
    [x, ..xs] -> {
      let biz_data: BizOutput =
        build_biz_data(
          conf,
          x,
          owner,
          sc,
          pkh_valid,
          datums,
          recursive,
          spd_datum_type,
          bond_policy_id,
          spd_datum,
        )
      if !biz_data.valid {
        biz_data
      } else {
        get_biz_output(
          conf,
          xs,
          owner,
          sc,
          pkh_valid,
          datums,
          biz_data,
          spd_datum_type,
          bond_policy_id,
          spd_datum,
        )
      }
    }
  }
}

fn get_biz_input(
  conf: Config,
  outputs: List<Input>,
  owner: Address,
  sc: Address,
  pkh_valid: List<PublicKeyHash>,
  datums: Datums,
  recursive: BizOutput,
  spd_datum_type: DatumType,
  bond_policy_id: ByteArray,
  spd_datum: OrderTypeDatum<
    OrderDatum<Option<AskLimit>, Option<BidLimit>>,
    OrderDatum<Option<AskMaking>, Option<BidMaking>>,
  >,
) -> BizOutput {
  when outputs is {
    [] -> recursive
    [x, ..xs] -> {
      let biz_data: BizOutput =
        build_biz_data(
          conf,
          x.output,
          owner,
          sc,
          pkh_valid,
          datums,
          recursive,
          spd_datum_type,
          bond_policy_id,
          spd_datum,
        )
      if !biz_data.valid {
        biz_data
      } else {
        get_biz_input(
          conf,
          xs,
          owner,
          sc,
          pkh_valid,
          datums,
          biz_data,
          spd_datum_type,
          bond_policy_id,
          spd_datum,
        )
      }
    }
  }
}

pub fn collect_biz_tx_info(
  conf: Config,
  inputs: List<Input>,
  outputs: List<Output>,
  owner: Address,
  sc: Address,
  pkh_valid: List<PublicKeyHash>,
  datums: Datums,
  spd_datum_type: DatumType,
  bond_policy_id: ByteArray,
  spd_datum: OrderTypeDatum<
    OrderDatum<Option<AskLimit>, Option<BidLimit>>,
    OrderDatum<Option<AskMaking>, Option<BidMaking>>,
  >,
) -> BizTxInfo {
  let biz_out_info_init =
    BizOutputInfo {
      addresses: [],
      bond_datum_valid: True,
      bond_outputs: [],
      bond_assets: dict.new(),
      bond_qty: 0,
      lovelace: 0,
      other_outputs: [],
    }
  let biz_out_init =
    BizOutput {
      valid: True,
      unique_bonds: dict.new(),
      sc: biz_out_info_init,
      market: biz_out_info_init,
      owner: biz_out_info_init,
      other: biz_out_info_init,
    }
  let biz_tx_in: BizOutput =
    get_biz_input(
      conf,
      inputs,
      owner,
      sc,
      pkh_valid,
      datums,
      biz_out_init,
      spd_datum_type,
      bond_policy_id,
      spd_datum,
    )
  if biz_tx_in.valid {
    let biz_tx_out: BizOutput =
      get_biz_output(
        conf,
        outputs,
        owner,
        sc,
        pkh_valid,
        datums,
        biz_out_init,
        spd_datum_type,
        bond_policy_id,
        spd_datum,
      )
    BizTxInfo {
      valid: biz_tx_out.valid,
      biz_tx_in,
      biz_tx_out: Some(biz_tx_out),
    }
  } else {
    BizTxInfo { valid: False, biz_tx_in, biz_tx_out: None }
  }
}
