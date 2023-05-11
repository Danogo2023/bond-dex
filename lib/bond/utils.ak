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
  BiddingDatum, BizOutput, BizOutputInfo, BizTxInfo, BondConfig, Config,
  DatumType, DatumTypeBidding, DatumTypeListing, EpochConfig, Error, EscrowDatum,
  EscrowInfo, EscrowInfoResult, ListingDatum, OK,
}
use common/types.{Datums, PublicKeyHash} as common_types
use common/utils.{get_data}

pub fn must_be_signed_by(
  extra_signatories: List<PublicKeyHash>,
  address: Address,
) -> Bool {
  when address.payment_credential is {
    VerificationKeyCredential(vhk) ->
      list.has(extra_signatories, vhk)
    ScriptCredential(_) ->
      False
  }
}

pub fn get_escrow_info(
  bond_config: BondConfig,
  escrow_lovelace: Int,
  escrow_datum: EscrowDatum,
  tx_posix_time: Int,
) -> EscrowInfoResult<EscrowInfo, ByteArray> {
  let current_epoch =
    posix_time_to_relative_epoch(tx_posix_time, bond_config.epoch_config)
  let start_epoch =
    escrow_datum.start + bond_config.epoch_config.epoch_boundary_as_epoch
  let end_epoch =
    start_epoch + escrow_datum.duration
  // Tong tien lai moi epoch Borrower phai tra
  let epoch_rewards_lovelace =
    value.lovelace_of(escrow_datum.epo_rewards)
  // Tien goc cua toan bo bond phat hanh
  let principal_lovelace =
    escrow_datum.bond_amount * bond_config.bond_face_value
  // Tong tien lai tich luy hien tai cho toan bo bond phat hanh
  let premium_paid_lovelace =
    escrow_lovelace - principal_lovelace
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
  // So epoch con lai cho den khi bond se duoc phep dong
  let closable_in =
    if interest_due_paid_epoch >= escrow_datum.duration {
      end_epoch - current_epoch
    } else {
      interest_level_epoch - escrow_datum.buffer + 1
    }
  if list.or([current_epoch > end_epoch, closable_in <= 0]) {
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
    relative_epoch_to_posix_time_end(end_epoch, epoch_config)
  if tx_time > maturity_time {
    0
  } else {
    let time_of_day =
      get_milliseconds_of_day(epoch_config)
    let diff_time =
      maturity_time - tx_time
    let maturity_day =
      diff_time / time_of_day
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

pub fn accumulation(self: Dict<AssetName, Int>, zero: Int) -> Int {
  dict.fold(self, fn(_, v, c) { v + c }, zero)
}

fn datum_is_valid(
  conf: Config,
  extra_signatories: List<PublicKeyHash>,
  datum_type: DatumType,
  datum: Data,
) -> Bool {
  when datum_type is {
    DatumTypeListing -> {
      expect listing_datum: ListingDatum =
        datum
      list.has(extra_signatories, listing_datum.owner_payment_key)? && (math.clamp(
        listing_datum.requested_yield,
        conf.bond.basis_points_min,
        conf.bond.basis_points_max,
      ) == listing_datum.requested_yield)?
    }
    DatumTypeBidding -> {
      expect bidding_datum: BiddingDatum =
        datum
      list.has(extra_signatories, bidding_datum.owner_payment_key)? && (math.clamp(
        bidding_datum.requested_yield,
        conf.bond.basis_points_min,
        conf.bond.basis_points_max,
      ) == bidding_datum.requested_yield)? && (bidding_datum.to_epoch >= bidding_datum.from_epoch)? && (bidding_datum.quantity > 0)?
    }
    _ ->
      False
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
          Some(datum) ->
            datum_is_valid(conf, extra_signatories, datum_type, datum)
          None ->
            False
        }
      BizOutputInfo {
        addresses,
        bond_datum_valid,
        bond_outputs: [output, ..self.bond_outputs],
        bond_assets: bond_assets(self.bond_assets, bond_values),
        bond_qty: accumulation(bond_values, self.bond_qty),
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
  smart_contract: Address,
  extra_signatories: List<PublicKeyHash>,
  datums: Datums,
  data: BizOutput,
  datum_type: DatumType,
) -> BizOutput {
  let bond_values =
    value.tokens(output.value, conf.bond.bond_policy_id)
  let biz_output_info =
    build_biz_output_info(
      if output.address == smart_contract {
        data.smart_contract
      } else if output.address == owner {
        data.owner
      } else if output.address == conf.market.address {
        data.market
      } else {
        data.other
      },
      output,
      bond_values,
      if output.address == smart_contract {
        True
      } else {
        False
      },
      extra_signatories,
      datums,
      conf,
      datum_type,
    )
  BizOutput {
    valid: biz_output_info.bond_datum_valid,
    unique_bonds: bond_assets(data.unique_bonds, bond_values),
    smart_contract: when (output.address, smart_contract) is {
      (a, b) if a == b ->
        biz_output_info
      _ ->
        data.smart_contract
    },
    owner: when (output.address, owner) is {
      (a, b) if a == b ->
        biz_output_info
      _ ->
        data.owner
    },
    market: when (output.address, conf.market.address) is {
      (a, b) if a == b ->
        biz_output_info
      _ ->
        data.market
    },
    other: when
      (output.address, smart_contract, owner, conf.market.address)
    is {
      (a, b, c, d) if a != b && a != c && a != d ->
        biz_output_info
      _ ->
        data.other
    },
  }
}

fn get_biz_output(
  conf: Config,
  outputs: List<Output>,
  owner: Address,
  smart_contract: Address,
  extra_signatories: List<PublicKeyHash>,
  datums: Datums,
  recursive: BizOutput,
  datum_type: DatumType,
) -> BizOutput {
  when outputs is {
    [] ->
      recursive
    [x, ..xs] -> {
      let biz_data: BizOutput =
        build_biz_data(
          conf,
          x,
          owner,
          smart_contract,
          extra_signatories,
          datums,
          recursive,
          datum_type,
        )
      if !biz_data.valid {
        biz_data
      } else {
        get_biz_output(
          conf,
          xs,
          owner,
          smart_contract,
          extra_signatories,
          datums,
          biz_data,
          datum_type,
        )
      }
    }
  }
}

fn get_biz_input(
  conf: Config,
  outputs: List<Input>,
  owner: Address,
  smart_contract: Address,
  extra_signatories: List<PublicKeyHash>,
  datums: Datums,
  recursive: BizOutput,
  datum_type: DatumType,
) -> BizOutput {
  when outputs is {
    [] ->
      recursive
    [x, ..xs] -> {
      let biz_data: BizOutput =
        build_biz_data(
          conf,
          x.output,
          owner,
          smart_contract,
          extra_signatories,
          datums,
          recursive,
          datum_type,
        )
      if !biz_data.valid {
        biz_data
      } else {
        get_biz_input(
          conf,
          xs,
          owner,
          smart_contract,
          extra_signatories,
          datums,
          biz_data,
          datum_type,
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
  smart_contract: Address,
  extra_signatories: List<PublicKeyHash>,
  datums: Datums,
  is_buy: Bool,
  datum_type: DatumType,
) -> BizTxInfo {
  let biz_output_info_init =
    BizOutputInfo {
      addresses: [],
      bond_datum_valid: True,
      bond_outputs: [],
      bond_assets: dict.new(),
      bond_qty: 0,
      lovelace: 0,
      other_outputs: [],
    }
  let biz_output_init =
    BizOutput {
      valid: True,
      unique_bonds: dict.new(),
      smart_contract: biz_output_info_init,
      market: biz_output_info_init,
      owner: biz_output_info_init,
      other: biz_output_info_init,
    }
  let biz_input_obj: BizOutput =
    get_biz_input(
      conf,
      inputs,
      owner,
      smart_contract,
      extra_signatories,
      datums,
      biz_output_init,
      datum_type,
    )
  if
  biz_input_obj.valid? && (
    !is_buy || (dict.size(biz_input_obj.smart_contract.bond_assets) <= 1)?
  ){
  
    let biz_output_obj: BizOutput =
      get_biz_output(
        conf,
        outputs,
        owner,
        smart_contract,
        extra_signatories,
        datums,
        biz_output_init,
        datum_type,
      )
    if
    biz_output_obj.valid? && (dict.size(
      biz_output_obj.smart_contract.bond_assets,
    ) <= 1)?{
    
      BizTxInfo {
        valid: True,
        biz_input_obj,
        biz_output_obj: Some(biz_output_obj),
      }
    } else {
      BizTxInfo { valid: False, biz_input_obj, biz_output_obj: None }
    }
  } else {
    BizTxInfo { valid: False, biz_input_obj, biz_output_obj: None }
  }
}
