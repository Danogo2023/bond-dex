use aiken/bytearray
use aiken/dict
use aiken/interval.{Finite}
use aiken/list
use aiken/transaction.{Transaction}
use aiken/transaction/credential.{Address, VerificationKeyCredential}
use aiken/transaction/value
use bond/types.{
  BizOutput, BizTxInfo, Config, DatumTypeListing, Error, EscrowDatum, EscrowInfo,
  OK,
}
use bond/utils.{
  collect_biz_tx_info, get_escrow_info, get_escrow_ref_inputs, get_price_of_bond,
  posix_time_to_relative_epoch,
}
use common/utils.{get_data} as common_utils

fn buy_is_valid(
  conf: Config,
  biz_input_obj: BizOutput,
  biz_output_obj: BizOutput,
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
  (biz_output_obj.market.lovelace >= market_fee_buyer + market_fee_seller + min_ada_to_market)? && (biz_output_obj.owner.lovelace == received_with_yield - market_fee_seller)? && (biz_input_obj.smart_contract.bond_qty + biz_input_obj.other.bond_qty - biz_output_obj.smart_contract.bond_qty == biz_output_obj.other.bond_qty)?
}

fn buy_correct(
  conf: Config,
  requested_yield: Int,
  biz_input_obj: BizOutput,
  biz_output_obj: BizOutput,
  escrow_info: EscrowInfo,
) -> Bool {
  let (
    qty_owner_2_buyer,
    min_ada_to_sm,
    min_ada_to_market,
    sm_output_must_only_one_bond_name,
    sm_output_bond_same_escrow,
  ) =
    when biz_output_obj.smart_contract.bond_outputs is {
      [_, ..] ->
        // trace @"buy partial"
        (
          biz_input_obj.smart_contract.bond_qty - biz_output_obj.smart_contract.bond_qty,
          biz_input_obj.smart_contract.lovelace,
          0,
          dict.size(biz_output_obj.smart_contract.bond_assets) <= 1,
          dict.has_key(
            biz_output_obj.smart_contract.bond_assets,
            escrow_info.token_name,
          ),
        )
      [] ->
        // trace @"buy all"
        (
          biz_input_obj.smart_contract.bond_qty,
          0,
          biz_input_obj.smart_contract.lovelace,
          True,
          True,
        )
    }
  sm_output_must_only_one_bond_name? && sm_output_bond_same_escrow? && (qty_owner_2_buyer == 0 || dict.has_key(
    biz_output_obj.other.bond_assets,
    escrow_info.token_name,
  ))? && when
    list.find(
      dict.keys(biz_output_obj.smart_contract.bond_assets),
      fn(sm_bond_name_output) {
        !list.has(
          dict.keys(biz_input_obj.smart_contract.bond_assets),
          sm_bond_name_output,
        )
      },
    )
  is {
    Some(_) -> {
      trace @"output to smart contract contain bond name invalid!"
      False
    }
    _ ->
      (
        min_ada_to_sm <= 0 || (biz_output_obj.smart_contract.lovelace >= min_ada_to_sm)? && biz_output_obj.smart_contract.bond_datum_valid?
      ) && buy_is_valid(
        conf,
        biz_input_obj,
        biz_output_obj,
        escrow_info,
        qty_owner_2_buyer,
        get_price_of_bond(
          escrow_info.received_at_maturity_one_bond,
          escrow_info.day_to_maturity,
          requested_yield,
          conf.bond.basis_points_ref_unit,
        ),
        min_ada_to_market,
      )?
  }
}

pub fn buy(
  tx: Transaction,
  conf: Config,
  requested_yield: Int,
  owner: Address,
  smart_contract: Address,
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
  let owner_vk =
    when owner.payment_credential is {
      VerificationKeyCredential(x) -> x
      _ -> #""
    }
  (validity_after_must_set > 0)? && (validity_end_must_set > 0)? && (validity_end_must_set > validity_after_must_set)? && (validity_end_must_set - validity_after_must_set <= when
    conf.market.sell_valid_slot
  is {
    Some(x) -> x
    None -> 3 * 60 * 60
  } * conf.slot_config_network.slot_length)? && not(
    bytearray.is_empty(owner_vk),
  )? && when get_escrow_ref_inputs(tx.reference_inputs, conf.bond) is {
    Some(ref_input_escrow) ->
      when get_data(tx.datums, ref_input_escrow.output.datum) is {
        Some(d) -> {
          expect escrow_datum: EscrowDatum = d
          let start_epoch =
            escrow_datum.start + conf.bond.epoch_config.epoch_boundary_as_epoch
          when
            get_escrow_info(
              conf.bond,
              value.lovelace_of(ref_input_escrow.output.value),
              escrow_datum,
              validity_after_must_set,
              posix_time_to_relative_epoch(
                validity_after_must_set,
                conf.bond.epoch_config,
              ),
              start_epoch,
              start_epoch + escrow_datum.duration,
            )
          is {
            OK(escrow_info) -> {
              let BizTxInfo {
                valid: biz_tx_info_valid,
                biz_input_obj,
                biz_output_obj,
              } =
                collect_biz_tx_info(
                  conf,
                  tx.inputs,
                  tx.outputs,
                  owner,
                  smart_contract,
                  [owner_vk],
                  tx.datums,
                  DatumTypeListing,
                  escrow_datum.bond_symbol,
                )
              biz_tx_info_valid && (dict.size(
                biz_input_obj.smart_contract.bond_assets,
              ) > 0)? && (dict.size(biz_input_obj.smart_contract.bond_assets) <= 1)? && dict.has_key(
                biz_input_obj.smart_contract.bond_assets,
                escrow_info.token_name,
              )? && when biz_output_obj is {
                None -> {
                  trace @"biz_output_obj is None"
                  False
                }
                Some(biz_output) ->
                  (biz_input_obj.market.bond_qty <= 0)? && (biz_input_obj.owner.bond_qty <= 0)? && (biz_input_obj.smart_contract.bond_qty + biz_input_obj.other.bond_qty == biz_output.smart_contract.bond_qty + biz_output.other.bond_qty)? && buy_correct(
                    conf,
                    requested_yield,
                    biz_input_obj,
                    biz_output,
                    escrow_info,
                  )
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
