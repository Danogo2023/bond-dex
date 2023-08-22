use aiken/dict.{Dict}
use aiken/list
use aiken/transaction.{Input, Output}
use aiken/transaction/credential.{Address}
use aiken/transaction/value.{AssetName}
use bond/common.{
  bond_assets, datum_bid_limit_compare,
  datum_epoch_valid, datum_yield_valid,
}
use bond/types.{
  BidLimit, BizOutput, BizOutputInfo, BizTxInfo, Config, DatumOf,
  EscrowInfo,
  OtherDatum, ScDatum,
}
use common/types.{Datums} as common_types
use common/utils.{get_data}

fn datum_is_valid(
  conf: Config,
  out_data: Data,
  spd_datum: BidLimit,
) -> Bool {
  expect out_datum: BidLimit = out_data
  datum_yield_valid(conf, out_datum.requested_yield) && datum_epoch_valid(
    out_datum.from_epoch,
    out_datum.to_epoch,
    out_datum.quantity,
  ) && datum_bid_limit_compare(spd_datum, out_datum)
}

fn build_biz_output_info(
  self: BizOutputInfo,
  output: Output,
  bond_values: Dict<AssetName, Int>,
  datum_of: DatumOf,
  datums: Datums,
  conf: Config,
  spd_datum: BidLimit,
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
          Some(d) -> datum_is_valid(conf, d, spd_datum)
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
  datums: Datums,
  data: BizOutput,
  escrow_info: EscrowInfo,
  spd_datum: BidLimit,
) -> BizOutput {
  let bond_values = value.tokens(output.value, escrow_info.bond_symbol)
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
      } else {
        OtherDatum
      },
      datums,
      conf,
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
  datums: Datums,
  recursive: BizOutput,
  escrow_info: EscrowInfo,
  spd_datum: BidLimit,
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
          datums,
          recursive,
          escrow_info,
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
          datums,
          biz_data,
          escrow_info,
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
  datums: Datums,
  recursive: BizOutput,
  escrow_info: EscrowInfo,
  spd_datum: BidLimit,
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
          datums,
          recursive,
          escrow_info,
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
          datums,
          biz_data,
          escrow_info,
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
  datums: Datums,
  escrow_info: EscrowInfo,
  spd_datum: BidLimit,
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
      datums,
      biz_out_init,
      escrow_info,
      spd_datum,
    )
  if biz_tx_in.valid {
    let biz_tx_out: BizOutput =
      get_biz_output(
        conf,
        outputs,
        owner,
        sc,
        datums,
        biz_out_init,
        escrow_info,
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
