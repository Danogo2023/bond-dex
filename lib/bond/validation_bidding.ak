use aiken/bytearray
use aiken/dict
use aiken/interval.{Finite}
use aiken/list
use aiken/option
use aiken/transaction.{Transaction}
use aiken/transaction/credential.{Address, VerificationKeyCredential}
use aiken/transaction/value
use bond/types.{
  BizOutput, BizTxInfo, Config, DatumTypeBidding, Error, EscrowDatum, EscrowInfo,
  OK,
}
use bond/utils.{
  collect_biz_tx_info, get_escrow_info, get_price_of_bond, must_be_signed_by,
}
use common/utils.{get_data} as common_utils

pub fn update(tx: Transaction, owner: Address) -> Bool {
  let owner_is_valid =
    must_be_signed_by(
      list.at(tx.extra_signatories, 0)
        |> option.and_then(fn(a) { Some([a]) })
        |> option.or_else([]),
      owner,
    )
  owner_is_valid?
}

fn sell_is_valid(
  conf: Config,
  biz_input_obj: BizOutput,
  biz_output_obj: BizOutput,
  escrow_info: EscrowInfo,
  buyer_qty: Int,
  price_of_one_bond: Int,
  min_ada_to_market: Int,
) -> Bool {
  // trace @"start sell_is_valid"
  // Tong tien lender nhan duoc cuoi chu ky dao han bao gom ca goc va lai tuong ung vs so bond ma buyer mua
  let received_at_maturity =
    escrow_info.received_at_maturity_one_bond * buyer_qty
  // Tong tien buyer phai tra/owner nhan duoc chua tru phi
  let received_with_yield =
    price_of_one_bond * buyer_qty
  // Chenh lech tien lai nhan duoc
  let received_diff =
    received_at_maturity - received_with_yield
  // phi owner phai tra cho san theo ti le trong config
  let market_fee_seller =
    received_diff * conf.market.seller_fee / conf.bond.basis_points_ref_unit
  // phi buyer phai tra cho san theo ti le trong config
  let market_fee_buyer =
    received_diff * conf.market.buyer_fee / conf.bond.basis_points_ref_unit
  list.and(
    [
      // So tien fee + min ada cua lenh toi thieu ma san phai nhan duoc
      (biz_output_obj.market.lovelace >= market_fee_buyer + market_fee_seller + min_ada_to_market)?,
      // So tien owner lenh nhan duoc sau khi tru phi
      (biz_output_obj.owner.lovelace >= received_with_yield - market_fee_seller)?,
      // So bond cua giao dich chuyen ve cho owner
      (biz_input_obj.smart_contract.bond_qty + biz_input_obj.other.bond_qty - biz_output_obj.smart_contract.bond_qty == biz_output_obj.other.bond_qty)?,
    ],
  )
}

fn sell_correct(
  conf: Config,
  requested_yield: Int,
  biz_input_obj: BizOutput,
  biz_output: BizOutput,
  escrow_info: EscrowInfo,
) -> Bool {
  let miss_balance_qty_bond =
    biz_input_obj.smart_contract.bond_qty + biz_input_obj.other.bond_qty == biz_output.smart_contract.bond_qty + biz_output.other.bond_qty
  let buyer_must_not_owner =
    biz_output.other.bond_qty > 0
  let buyer_must_not_market =
    not(biz_output.market.bond_qty > 0)
  if buyer_must_not_market? && buyer_must_not_owner? && miss_balance_qty_bond? {
    // trace @"total in SM+buyer bond inputs == outputs"
    // Gia bond theo requested_yield cua owner
    let price_of_one_bond =
      get_price_of_bond(
        escrow_info.received_at_maturity_one_bond,
        escrow_info.day_to_maturity,
        requested_yield,
        conf.bond.basis_points_ref_unit,
      )
    let (qty_owner_2_buyer, min_ada_to_sm, min_ada_to_market) =
      when biz_output.smart_contract.bond_outputs is {
        [_, ..] ->
          // trace @"buy partial"
          (
            biz_input_obj.smart_contract.bond_qty - biz_output.smart_contract.bond_qty,
            biz_input_obj.smart_contract.lovelace,
            0,
          )
        [] ->
          // trace @"buy all"
          (
            biz_input_obj.smart_contract.bond_qty,
            0,
            biz_input_obj.smart_contract.lovelace,
          )
      }
    when
      list.find(
        dict.keys(biz_output.smart_contract.bond_assets),
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
      _ -> {
        let buy_partial_return_sm_matchs =
          min_ada_to_sm <= 0 || (biz_output.smart_contract.lovelace >= min_ada_to_sm)? && biz_output.smart_contract.bond_datum_valid?
        buy_partial_return_sm_matchs && sell_is_valid(
          conf,
          biz_input_obj,
          biz_output,
          escrow_info,
          qty_owner_2_buyer,
          price_of_one_bond,
          min_ada_to_market,
        )?
      }
    }
  } else {
    trace @"total in SM+buyer bond inputs != outputs"
    False
  }
}

pub fn sell(
  tx: Transaction,
  conf: Config,
  requested_yield: Int,
  owner: Address,
  smart_contract: Address,
) -> Bool {
  let validity_after_must_set =
    when tx.validity_range.lower_bound.bound_type is {
      Finite(x) ->
        x
      _ ->
        0
    }
  let validity_before_must_set =
    when tx.validity_range.upper_bound.bound_type is {
      Finite(x) ->
        x
      _ ->
        0
    }
  let owner_vk =
    when owner.payment_credential is {
      VerificationKeyCredential(x) ->
        x
      _ ->
        #""
    }
  let tx_time_range =
    validity_before_must_set - validity_after_must_set

  list.and(
    [
      (validity_after_must_set > 0)?,
      (validity_before_must_set > 0)?,
      (tx_time_range > 0)?,
      (tx_time_range <= conf.market.bidding_validity_time)?,
    ],
  ) && not(bytearray.is_empty(owner_vk))? && when
    list.find(
      tx.reference_inputs,
      fn(input) {
        dict.size(value.tokens(input.output.value, conf.bond.escrow_policy_id)) > 0
      },
    )
  is {
    Some(ref_input_escrow) ->
      // trace @"found ref_input_escrow in reference_inputs"
      when get_data(tx.datums, ref_input_escrow.output.datum) is {
        Some(d) -> {
          expect escrow_datum: EscrowDatum =
            d
          when
            get_escrow_info(
              conf.bond,
              value.lovelace_of(ref_input_escrow.output.value),
              escrow_datum,
              validity_after_must_set,
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
                  DatumTypeBidding,
                )
              biz_tx_info_valid && when biz_output_obj is {
                Some(biz_output) -> {
                  let output_must_only_one_bond_name =
                    dict.size(biz_output.owner.bond_assets) <= 1
                  let owner_receive_bond_same_escrow =
                    dict.has_key(
                      biz_output.owner.bond_assets,
                      escrow_datum.token_name,
                    )
                  output_must_only_one_bond_name? && owner_receive_bond_same_escrow? && sell_correct(
                    conf,
                    requested_yield,
                    biz_input_obj,
                    biz_output,
                    escrow_info,
                  )
                }
                None -> {
                  trace @"biz_output_obj is None"
                  False
                }
              }
            }
            Error(_) -> {
              trace @"is closable"
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
      trace @"not found reference_inputs with escrow_policy_id"
      False
    }
  }
}
