// Bid Limit Multi
use aiken/dict.{Dict}
use aiken/list
use aiken/transaction.{Input, Output}
use aiken/transaction/credential.{Address}
use aiken/transaction/value.{AssetName}
use bond/constraint.{bid_limit_multi_valid, epoch_valid, yield_valid}
use bond/types.{
  BidLimitMulti, BizOutput, BizOutputInfo, BizTxInfo, BondConfigLimit, DatumOf,
  EscrowInfo, OtherDatum, ScDatum,
}
use bond/utils.{bond_assets} as bond_utils
use common/types.{Datums} as common_types
use common/util.{get_data}

fn datum_is_valid(
  cfg: BondConfigLimit,
  out_data: Data,
  sdt: BidLimitMulti,
) -> Bool {
  expect out_datum: BidLimitMulti = out_data
  yield_valid(cfg.platform.basis, out_datum.requested_yield) && epoch_valid(
    out_datum.from_epoch,
    out_datum.to_epoch,
    out_datum.quantity,
  ) && bid_limit_multi_valid(sdt, out_datum)
}

fn build_biz_output_info(
  self: BizOutputInfo,
  output: Output,
  bond_values: Dict<AssetName, Int>,
  datum_of: DatumOf,
  datums: Datums,
  cfg: BondConfigLimit,
  sdt: BidLimitMulti,
) -> BizOutputInfo {
  let addresses =
    if list.has(self.addresses, output.address) {
      self.addresses
    } else {
      [output.address, ..self.addresses]
    }
  let bond_datum_valid =
    datum_of == OtherDatum || when get_data(datums, output.datum) is {
      Some(d) -> datum_is_valid(cfg, d, sdt)
      None -> {
        trace @"not found datum"
        False
      }
    }
  let (output_bond, output_other) =
    if dict.size(bond_values) > 0 {
      ([output, ..self.bond_outputs], self.other_outputs)
    } else {
      (self.bond_outputs, [output, ..self.other_outputs])
    }
  BizOutputInfo {
    addresses,
    bond_datum_valid,
    bond_outputs: output_bond,
    bond_assets: bond_assets(bond_values, self.bond_assets),
    bond_qty: dict.foldl(bond_values, self.bond_qty, fn(_, v, z) { v + z }),
    lovelace: self.lovelace + value.lovelace_of(output.value),
    other_outputs: output_other,
  }
}

fn build_biz_data(
  cfg: BondConfigLimit,
  output: Output,
  owner_addr: Address,
  sbid_addr: Address,
  datums: Datums,
  data: BizOutput,
  escrow_info: EscrowInfo,
  sdt: BidLimitMulti,
) -> BizOutput {
  let bond_values = value.tokens(output.value, escrow_info.bond_symbol)
  let biz_out_info =
    build_biz_output_info(
      if output.address == sbid_addr {
        data.sc
      } else if output.address == owner_addr {
        data.owner
      } else if output.address == cfg.exchange.address {
        data.exchange
      } else {
        data.other
      },
      output,
      bond_values,
      if output.address == sbid_addr {
        ScDatum
      } else {
        OtherDatum
      },
      datums,
      cfg,
      sdt,
    )
  BizOutput {
    valid: biz_out_info.bond_datum_valid,
    unique_bonds: bond_assets(data.unique_bonds, bond_values),
    sc: when (output.address, sbid_addr) is {
      (a, b) if a == b -> biz_out_info
      _ -> data.sc
    },
    owner: when (output.address, owner_addr) is {
      (a, b) if a == b -> biz_out_info
      _ -> data.owner
    },
    exchange: when (output.address, cfg.exchange.address) is {
      (a, b) if a == b -> biz_out_info
      _ -> data.exchange
    },
    other: when
      (output.address, sbid_addr, owner_addr, cfg.exchange.address)
    is {
      (a, b, c, d) if a != b && a != c && a != d -> biz_out_info
      _ -> data.other
    },
  }
}

fn get_biz_output(
  cfg: BondConfigLimit,
  outputs: List<Output>,
  owner_addr: Address,
  sbid_addr: Address,
  datums: Datums,
  zero: BizOutput,
  escrow_info: EscrowInfo,
  sdt: BidLimitMulti,
) -> BizOutput {
  when outputs is {
    [] -> zero
    [x, ..xs] -> {
      let biz_data: BizOutput =
        build_biz_data(
          cfg,
          x,
          owner_addr,
          sbid_addr,
          datums,
          zero,
          escrow_info,
          sdt,
        )
      if !biz_data.valid {
        biz_data
      } else {
        get_biz_output(
          cfg,
          xs,
          owner_addr,
          sbid_addr,
          datums,
          biz_data,
          escrow_info,
          sdt,
        )
      }
    }
  }
}

fn get_biz_input(
  cfg: BondConfigLimit,
  inputs: List<Input>,
  owner_addr: Address,
  sbid_addr: Address,
  datums: Datums,
  zero: BizOutput,
  escrow_info: EscrowInfo,
  sdt: BidLimitMulti,
) -> BizOutput {
  when inputs is {
    [] -> zero
    [x, ..xs] -> {
      let biz_data: BizOutput =
        build_biz_data(
          cfg,
          x.output,
          owner_addr,
          sbid_addr,
          datums,
          zero,
          escrow_info,
          sdt,
        )
      if !biz_data.valid {
        biz_data
      } else {
        get_biz_input(
          cfg,
          xs,
          owner_addr,
          sbid_addr,
          datums,
          biz_data,
          escrow_info,
          sdt,
        )
      }
    }
  }
}

pub fn collect_biz_tx_info(
  cfg: BondConfigLimit,
  inputs: List<Input>,
  outputs: List<Output>,
  owner_addr: Address,
  sbid_addr: Address,
  datums: Datums,
  escrow_info: EscrowInfo,
  sdt: BidLimitMulti,
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
      exchange: biz_out_info_init,
      owner: biz_out_info_init,
      other: biz_out_info_init,
    }
  let biz_tx_in: BizOutput =
    get_biz_input(
      cfg,
      inputs,
      owner_addr,
      sbid_addr,
      datums,
      biz_out_init,
      escrow_info,
      sdt,
    )
  if biz_tx_in.valid {
    let biz_tx_out: BizOutput =
      get_biz_output(
        cfg,
        outputs,
        owner_addr,
        sbid_addr,
        datums,
        biz_out_init,
        escrow_info,
        sdt,
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
