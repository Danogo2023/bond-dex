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
  BondConfig, Config, DatumType, DatumTypeAskLimit, DatumTypeAskMaking,
  DatumTypeBidLimit, DatumTypeBidMaking, EpochConfig, Error, EscrowDatum,
  EscrowInfo, EscrowInfoResult, OK,
}
use common/types.{Datums, PublicKeyHash} as common_types
use common/utils.{get_data, get_payment_key}

pub fn must_be_signed_by(
  extra_signatories: List<PublicKeyHash>,
  address: Address,
) -> Bool {
  list.has(extra_signatories, get_payment_key(address))
}

pub fn get_escrow_ref_inputs(
  ref_inputs: List<Input>,
  bond_config: BondConfig,
) -> Option<Input> {
  list.find(
    ref_inputs,
    fn(i) {
      when i.output.address.payment_credential is {
        VerificationKeyCredential(_) -> False
        ScriptCredential(k) -> {
          let escrow_asset =
            value.tokens(i.output.value, bond_config.escrow_policy_id)
          k == bond_config.escrow_payment_key && dict.size(escrow_asset) == 1 && when
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
  bond_config: BondConfig,
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
  let principal_lovelace =
    escrow_datum.bond_amount * bond_config.bond_face_value
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
    let lend_after_fee =
      1 * bond_config.basis_points_ref_unit - escrow_datum.otm_fee
    // Tong tien lai lender nhan duoc cua tat ca bond phat hanh khi ket thuc chu ky dao han
    let lender_interest =
      epoch_rewards_lovelace * escrow_datum.duration * lend_after_fee
    // Tong tien lai lender nhan duoc khi den ky dao han cua 1 bond da tru phi cua Optim 3%
    let interest_at_maturity_one_bond_lovelace =
      lender_interest / bond_config.basis_points_ref_unit / escrow_datum.bond_amount
    OK(
      EscrowInfo {
        token_name: escrow_datum.token_name,
        // Tong tien goc + lai cua 1 bond theo lai suat Optim ma lender nhan duoc 
        received_at_maturity_one_bond: interest_at_maturity_one_bond_lovelace + bond_config.bond_face_value,
        // So ngay den ky dao han cua bond
        day_to_maturity: get_day_to_maturity(
          tx_posix_time,
          end_epoch,
          bond_config.epoch_config,
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
  extra_signatories: List<PublicKeyHash>,
  out_payment_key: ByteArray,
  out_requested_yield: Int,
) -> Bool {
  list.has(extra_signatories, out_payment_key)? && (math.clamp(
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
  spd_payment_key: ByteArray,
  out_payment_key: ByteArray,
  spd_margin: Int,
  out_margin: Option<Int>,
  out_requested_yield: Int,
) -> Bool {
  (out_payment_key == spd_payment_key)? && when out_margin is {
    Some(m) ->
      (m == spd_margin)? && (math.clamp(
        m + out_requested_yield,
        conf.bond.basis_points_min,
        conf.bond.basis_points_max,
      ) == m + out_requested_yield)?
    None -> False
  }?
}

fn datum_is_valid(
  conf: Config,
  extra_signatories: List<PublicKeyHash>,
  datum_type: DatumType,
  out_datum: Data,
  spd_payment_key: ByteArray,
  spd_margin: Option<Int>,
) -> Bool {
  when datum_type is {
    DatumTypeAskLimit -> {
      expect ask_limit_datum: AskLimit = out_datum
      datum_owner_valid(
        conf,
        extra_signatories,
        ask_limit_datum.owner_payment_key,
        ask_limit_datum.requested_yield,
      )
    }
    DatumTypeAskMaking -> {
      expect ask_making_datum: AskMaking = out_datum
      datum_owner_valid(
        conf,
        extra_signatories,
        ask_making_datum.owner_payment_key,
        ask_making_datum.requested_yield,
      ) && datum_making_valid(
        conf,
        ask_making_datum.bid_sc,
        spd_payment_key,
        ask_making_datum.margin,
        spd_margin,
        ask_making_datum.requested_yield,
      )
    }
    DatumTypeBidLimit -> {
      expect bid_limit_datum: BidLimit = out_datum
      datum_owner_valid(
        conf,
        extra_signatories,
        bid_limit_datum.owner_payment_key,
        bid_limit_datum.requested_yield,
      ) && datum_epoch_valid(
        bid_limit_datum.from_epoch,
        bid_limit_datum.to_epoch,
        bid_limit_datum.quantity,
      )
    }
    DatumTypeBidMaking -> {
      expect bid_making_datum: BidMaking = out_datum
      datum_owner_valid(
        conf,
        extra_signatories,
        bid_making_datum.owner_payment_key,
        bid_making_datum.requested_yield,
      ) && datum_epoch_valid(
        bid_making_datum.from_epoch,
        bid_making_datum.to_epoch,
        bid_making_datum.quantity,
      ) && datum_making_valid(
        conf,
        bid_making_datum.ask_sc,
        spd_payment_key,
        bid_making_datum.margin,
        spd_margin,
        0 - bid_making_datum.requested_yield,
      )
    }
    _ -> False
  }
}

fn build_biz_output_info(
  self: BizOutputInfo,
  output: Output,
  bond_values: Dict<AssetName, Int>,
  check_datum: Bool,
  extra_signatories: List<PublicKeyHash>,
  datums: Datums,
  conf: Config,
  datum_type: DatumType,
  spd_payment_key: ByteArray,
  spd_margin: Option<Int>,
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
        !check_datum || when get_data(datums, output.datum) is {
          Some(d) ->
            datum_is_valid(
              conf,
              extra_signatories,
              datum_type,
              d,
              spd_payment_key,
              spd_margin,
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
  extra_signatories: List<PublicKeyHash>,
  datums: Datums,
  data: BizOutput,
  datum_type: DatumType,
  bond_policy_id: ByteArray,
  spd_margin: Option<Int>,
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
        True
      } else {
        False
      },
      extra_signatories,
      datums,
      conf,
      datum_type,
      get_payment_key(sc),
      spd_margin,
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
  extra_signatories: List<PublicKeyHash>,
  datums: Datums,
  recursive: BizOutput,
  datum_type: DatumType,
  bond_policy_id: ByteArray,
  spd_margin: Option<Int>,
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
          extra_signatories,
          datums,
          recursive,
          datum_type,
          bond_policy_id,
          spd_margin,
        )
      if !biz_data.valid {
        biz_data
      } else {
        get_biz_output(
          conf,
          xs,
          owner,
          sc,
          extra_signatories,
          datums,
          biz_data,
          datum_type,
          bond_policy_id,
          spd_margin,
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
  extra_signatories: List<PublicKeyHash>,
  datums: Datums,
  recursive: BizOutput,
  datum_type: DatumType,
  bond_policy_id: ByteArray,
  spd_margin: Option<Int>,
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
          extra_signatories,
          datums,
          recursive,
          datum_type,
          bond_policy_id,
          spd_margin,
        )
      if !biz_data.valid {
        biz_data
      } else {
        get_biz_input(
          conf,
          xs,
          owner,
          sc,
          extra_signatories,
          datums,
          biz_data,
          datum_type,
          bond_policy_id,
          spd_margin,
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
  extra_signatories: List<PublicKeyHash>,
  datums: Datums,
  datum_type: DatumType,
  bond_policy_id: ByteArray,
  spd_margin: Option<Int>,
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
      extra_signatories,
      datums,
      biz_out_init,
      datum_type,
      bond_policy_id,
      spd_margin,
    )
  if biz_tx_in.valid {
    let biz_tx_out: BizOutput =
      get_biz_output(
        conf,
        outputs,
        owner,
        sc,
        extra_signatories,
        datums,
        biz_out_init,
        datum_type,
        bond_policy_id,
        spd_margin,
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
