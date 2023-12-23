// Ask Making
use aiken/dict.{Dict}
use aiken/list
use aiken/transaction.{Input, Output}
use aiken/transaction/credential.{Address}
use aiken/transaction/value.{AssetName}
use bond/constraint.{
  ask_making_valid, bid_making_valid, epoch_valid, yield_making_valid,
}
use bond/types.{
  AskMaking, BidMaking, BizOutput, BizOutputInfo, BizTxInfo, ConfigMaking,
  DatumOf, EscrowInfo, OtherDatum, OwnerDatum, ScDatum,
}
use bond/utils.{bond_assets}
use common/types.{Datums} as common_types
use common/util.{get_data, get_payment_key}

fn datum_is_valid(
  conf: ConfigMaking,
  out_data: Data,
  spd_sc_payment_key: ByteArray,
  spd_datum: AskMaking,
  datum_of: DatumOf,
  escrow_info: EscrowInfo,
) -> Bool {
  when datum_of is {
    OwnerDatum -> {
      expect out_datum: BidMaking = out_data
      yield_making_valid(conf, out_datum.requested_yield + out_datum.margin) && epoch_valid(
        out_datum.from_epoch,
        out_datum.to_epoch,
        out_datum.quantity,
      ) && bid_making_valid(
        BidMaking {
          owner_vk: spd_datum.owner_vk,
          owner_sk: spd_datum.owner_sk,
          from_epoch: escrow_info.end_epoch,
          to_epoch: escrow_info.end_epoch,
          quantity: 0,
          requested_yield: spd_datum.requested_yield + spd_datum.margin,
          ask_sc: spd_sc_payment_key,
          margin: spd_datum.margin,
        },
        out_datum,
      )
    }
    ScDatum -> {
      expect out_datum: AskMaking = out_data
      yield_making_valid(conf, out_datum.requested_yield + out_datum.margin) && ask_making_valid(
        spd_datum,
        out_datum,
      )
    }
    _ -> False
  }
}

fn build_biz_output_info(
  self: BizOutputInfo,
  output: Output,
  bond_values: Dict<AssetName, Int>,
  datum_of: DatumOf,
  datums: Datums,
  conf: ConfigMaking,
  spd_sc_payment_key: ByteArray,
  spd_datum: AskMaking,
  escrow_info: EscrowInfo,
) -> BizOutputInfo {
  let addresses =
    if list.has(self.addresses, output.address) {
      self.addresses
    } else {
      [output.address, ..self.addresses]
    }
  let bond_datum_valid =
    datum_of == OtherDatum || when get_data(datums, output.datum) is {
      Some(d) ->
        datum_is_valid(
          conf,
          d,
          spd_sc_payment_key,
          spd_datum,
          datum_of,
          escrow_info,
        )
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
  conf: ConfigMaking,
  output: Output,
  owner: Address,
  spending: Address,
  datums: Datums,
  data: BizOutput,
  escrow_info: EscrowInfo,
  spd_datum: AskMaking,
) -> BizOutput {
  let bond_values = value.tokens(output.value, escrow_info.bond_symbol)
  let biz_out_info =
    build_biz_output_info(
      if output.address == spending {
        data.sc
      } else if output.address == owner {
        data.owner
      } else if output.address == conf.exchange.address {
        data.exchange
      } else {
        data.other
      },
      output,
      bond_values,
      if output.address == spending {
        ScDatum
      } else if output.address == owner {
        OwnerDatum
      } else {
        OtherDatum
      },
      datums,
      conf,
      get_payment_key(spending),
      spd_datum,
      escrow_info,
    )
  BizOutput {
    valid: biz_out_info.bond_datum_valid,
    unique_bonds: bond_assets(data.unique_bonds, bond_values),
    sc: when (output.address, spending) is {
      (a, b) if a == b -> biz_out_info
      _ -> data.sc
    },
    owner: when (output.address, owner) is {
      (a, b) if a == b -> biz_out_info
      _ -> data.owner
    },
    exchange: when (output.address, conf.exchange.address) is {
      (a, b) if a == b -> biz_out_info
      _ -> data.exchange
    },
    other: when (output.address, spending, owner, conf.exchange.address) is {
      (a, b, c, d) if a != b && a != c && a != d -> biz_out_info
      _ -> data.other
    },
  }
}

fn get_biz_output(
  conf: ConfigMaking,
  outputs: List<Output>,
  owner: Address,
  spending: Address,
  datums: Datums,
  recursive: BizOutput,
  escrow_info: EscrowInfo,
  spd_datum: AskMaking,
) -> BizOutput {
  when outputs is {
    [] -> recursive
    [x, ..xs] -> {
      let biz_data: BizOutput =
        build_biz_data(
          conf,
          x,
          owner,
          spending,
          datums,
          recursive,
          escrow_info,
          spd_datum,
        )
      if !biz_data.valid {
        trace @"invalid biz_data"
        biz_data
      } else {
        get_biz_output(
          conf,
          xs,
          owner,
          spending,
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
  conf: ConfigMaking,
  outputs: List<Input>,
  owner: Address,
  spending: Address,
  datums: Datums,
  recursive: BizOutput,
  escrow_info: EscrowInfo,
  spd_datum: AskMaking,
) -> BizOutput {
  when outputs is {
    [] -> recursive
    [x, ..xs] -> {
      let biz_data: BizOutput =
        build_biz_data(
          conf,
          x.output,
          owner,
          spending,
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
          spending,
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
  conf: ConfigMaking,
  inputs: List<Input>,
  outputs: List<Output>,
  owner: Address,
  spending: Address,
  datums: Datums,
  escrow_info: EscrowInfo,
  spd_datum: AskMaking,
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
      conf,
      inputs,
      owner,
      spending,
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
        spending,
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
