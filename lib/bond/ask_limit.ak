use aiken/bytearray
use aiken/dict
use aiken/interval.{Finite}
use aiken/list
use aiken/transaction.{Transaction}
use aiken/transaction/credential.{Address}
use aiken/transaction/value
use bond/common.{
  get_escrow_info, get_escrow_ref_inputs, get_price_of_bond,
  posix_time_to_relative_epoch,
}
use bond/types.{
  AskLimit, BizOutput, BizTxInfo, Config, Error, EscrowDatum, EscrowInfo, OK,
}
use bond/utils_limit_ask.{collect_biz_tx_info}
use common/utils.{get_data} as common_utils

fn buy_is_valid(
  conf: Config,
  in: BizOutput,
  out: BizOutput,
  escrow_info: EscrowInfo,
  buyer_qty: Int,
  price_of_one_bond: Int,
  min_ada_to_market: Int,
) -> Bool {
  // Tong tien lender nhan duoc cuoi chu ky dao han bao gom ca goc va lai tuong ung vs so bond ma buyer mua
  let received_at_maturity =
    escrow_info.received_at_maturity_one_bond * buyer_qty
  // Tong tien buyer phai tra/seller(owner of listing) nhan duoc chua tru phi
  let received_with_yield = price_of_one_bond * buyer_qty
  // Chenh lech tien lai nhan duoc
  let received_diff = received_at_maturity - received_with_yield
  // phi seller(owner of listing) phai tra cho san theo ti le trong config
  let market_fee_seller =
    received_diff * conf.market.seller_fee / conf.bond.basis_points_ref_unit
  // phi buyer phai tra cho san theo ti le trong config
  let market_fee_buyer =
    received_diff * conf.market.buyer_fee / conf.bond.basis_points_ref_unit
  let owner_out_utxos =
    list.concat(out.owner.bond_outputs, out.owner.other_outputs)
  let owner_output_len = list.length(owner_out_utxos)
  let sc_output_len =
    list.length(list.concat(out.sc.bond_outputs, out.sc.other_outputs))
  let market_receive_lovelace_tmp =
    market_fee_buyer + market_fee_seller + min_ada_to_market
  let owner_receive_lovelace_tmp = received_with_yield - market_fee_seller
  let (owner_receive_lovelace, market_receive_lovelace) =
    when list.at(out.owner.addresses, 0) is {
      Some(a) ->
        if owner_output_len > 0 && a == conf.market.address {
          (owner_receive_lovelace_tmp + market_receive_lovelace_tmp, 0)
        } else {
          (owner_receive_lovelace_tmp, market_receive_lovelace_tmp)
        }
      _ -> (owner_receive_lovelace_tmp, market_receive_lovelace_tmp)
    }
  (sc_output_len <= 1)? && (owner_output_len <= 1)? && (buyer_qty >= 0)? && (out.sc.bond_qty >= in.sc.bond_qty - buyer_qty)? && (out.market.lovelace >= market_receive_lovelace)? && (owner_output_len > 0)? && (out.owner.lovelace == owner_receive_lovelace)?
}

fn buy_correct(
  conf: Config,
  spd_ask_datum: AskLimit,
  in: BizOutput,
  out: BizOutput,
  escrow_info: EscrowInfo,
) -> Bool {
  let (
    qty_owner_2_buyer,
    min_ada_to_sm,
    min_ada_to_market,
    sm_out_must_only_one_bond_name,
    sm_out_bond_same_escrow,
  ) =
    when out.sc.bond_outputs is {
      [_, ..] ->
        // trace @"buy partial"
        (
          in.sc.bond_qty - out.sc.bond_qty,
          in.sc.lovelace,
          0,
          dict.size(out.sc.bond_assets) <= 1,
          dict.has_key(out.sc.bond_assets, escrow_info.token_name),
        )
      [] ->
        // trace @"buy all"
        (in.sc.bond_qty, 0, in.sc.lovelace, True, True)
    }
  sm_out_must_only_one_bond_name? && sm_out_bond_same_escrow? && (qty_owner_2_buyer <= escrow_info.bond_amount)? && (qty_owner_2_buyer == 0 || (
    dict.has_key(out.other.bond_assets, escrow_info.token_name) || dict.has_key(
      out.market.bond_assets,
      escrow_info.token_name,
    )
  ))? && when
    list.find(
      dict.keys(out.sc.bond_assets),
      fn(sm_bond_name_output) {
        !list.has(dict.keys(in.sc.bond_assets), sm_bond_name_output)
      },
    )
  is {
    Some(_) -> {
      trace @"output to smart contract contain bond name invalid!"
      False
    }
    _ ->
      (
        min_ada_to_sm == 0 || (out.sc.lovelace >= min_ada_to_sm)? && out.sc.bond_datum_valid?
      ) && buy_is_valid(
        conf,
        in,
        out,
        escrow_info,
        qty_owner_2_buyer,
        get_price_of_bond(
          escrow_info.received_at_maturity_one_bond,
          escrow_info.day_to_maturity,
          spd_ask_datum.requested_yield,
          conf.bond.basis_points_ref_unit,
        ),
        min_ada_to_market,
      )?
  }
}

pub fn buy(
  tx: Transaction,
  conf: Config,
  spd_ask_datum: AskLimit,
  owner: Address,
  sc: Address,
) -> Bool {
  let validity_after_must_set =
    when tx.validity_range.lower_bound.bound_type is {
      Finite(x) -> x
      _ -> 0
    }
  let validity_end_must_set =
    when tx.validity_range.upper_bound.bound_type is {
      Finite(x) -> x
      _ -> 0
    }
  let owner_vk = spd_ask_datum.owner_payment_key
  (validity_after_must_set > 0)? && (validity_end_must_set > 0)? && (validity_end_must_set > validity_after_must_set)? && (validity_end_must_set - validity_after_must_set <= when
    conf.market.tx_buy_valid_slot
  is {
    Some(x) -> x
    None -> 3 * 60
  } * conf.slot_config_network.slot_length)? && not(
    bytearray.is_empty(owner_vk),
  )? && when get_escrow_ref_inputs(tx.reference_inputs, conf.bond) is {
    Some(ref_in_escrow) ->
      when get_data(tx.datums, ref_in_escrow.output.datum) is {
        Some(d) -> {
          expect escrow_datum: EscrowDatum = d
          let start_epoch =
            escrow_datum.start + conf.bond.epoch_config.epoch_boundary_as_epoch
          let end_epoch = start_epoch + escrow_datum.duration
          (escrow_datum.bond_amount > 0)? && (value.lovelace_of(
            escrow_datum.epo_rewards,
          ) > 0)? && (value.lovelace_of(ref_in_escrow.output.value) > escrow_datum.bond_amount * conf.bond.bond_face_value)? && when
            get_escrow_info(
              conf.bond,
              value.lovelace_of(ref_in_escrow.output.value),
              escrow_datum,
              validity_after_must_set,
              posix_time_to_relative_epoch(
                validity_after_must_set,
                conf.bond.epoch_config,
              ),
              start_epoch,
              end_epoch,
            )
          is {
            OK(escrow_info) -> {
              let BizTxInfo {
                valid: biz_tx_info_valid,
                biz_tx_in: in,
                biz_tx_out: out,
              } =
                collect_biz_tx_info(
                  conf,
                  tx.inputs,
                  tx.outputs,
                  owner,
                  sc,
                  tx.datums,
                  escrow_info,
                  spd_ask_datum,
                )
              biz_tx_info_valid && (dict.size(in.sc.bond_assets) == 1)? && dict.has_key(
                in.sc.bond_assets,
                escrow_info.token_name,
              )? && when out is {
                Some(ou) ->
                  (in.owner.bond_qty <= 0)? && buy_correct(
                    conf,
                    spd_ask_datum,
                    in,
                    ou,
                    escrow_info,
                  )
                None -> {
                  trace @"out is None"
                  False
                }
              }
            }
            Error(_) -> {
              trace @"bond is closable"
              False
            }
          }
        }
        _ -> {
          trace @"not found escrow datum in reference_inputs"
          False
        }
      }
    _ -> {
      trace @"not found escrow info in reference_inputs"
      False
    }
  }
}
