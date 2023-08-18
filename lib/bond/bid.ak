use aiken/bytearray
use aiken/dict
use aiken/interval.{Finite}
use aiken/list
use aiken/transaction.{Output, Transaction}
use aiken/transaction/credential.{Address, VerificationKeyCredential}
use aiken/transaction/value
use bond/types.{
  BidLimit, BizOutput, BizTxInfo, Config, DatumTypeBidLimit, Error, EscrowDatum,
  EscrowInfo, OK,
}
use bond/utils.{
  collect_biz_tx_info, get_escrow_info, get_escrow_ref_inputs, get_price_of_bond,
  posix_time_to_relative_epoch,
}
use common/utils.{get_data} as common_utils

fn sell_correct(
  tx: Transaction,
  conf: Config,
  bid_limit_datum: BidLimit,
  biz_input_obj: BizOutput,
  biz_output_obj: BizOutput,
  escrow_info: EscrowInfo,
  sm_output_utxo: Option<Output>,
) -> Bool {
  let buyer_receive_bonds_qty = biz_output_obj.owner.bond_qty
  let buyer_receive_lovelace = biz_output_obj.owner.lovelace
  let buyer_bidding_bonds_qty = bid_limit_datum.quantity

  let seller_input_lovelace = biz_input_obj.other.lovelace
  // Tong tien lender nhan duoc cuoi chu ky dao han bao gom ca goc va lai tuong ung vs so bond ma buyer mua
  let received_at_maturity =
    escrow_info.received_at_maturity_one_bond * buyer_receive_bonds_qty
  // Tong tien buyer(owner of bidding) phai tra/seller nhan duoc chua tru phi
  let received_with_yield =
    get_price_of_bond(
      escrow_info.received_at_maturity_one_bond,
      escrow_info.day_to_maturity,
      bid_limit_datum.requested_yield,
      conf.bond.basis_points_ref_unit,
    ) * buyer_receive_bonds_qty
  // Chenh lech tien lai nhan duoc
  let received_diff = received_at_maturity - received_with_yield
  // phi seller phai tra cho san theo ti le trong config
  let market_fee_seller =
    received_diff * conf.market.seller_fee / conf.bond.basis_points_ref_unit
  // phi buyer(owner of bidding) phai tra cho san theo ti le trong config
  let market_fee_buyer =
    received_diff * conf.market.buyer_fee / conf.bond.basis_points_ref_unit
  let market_fee_total = market_fee_buyer + market_fee_seller
  let seller_receive_total = received_with_yield - market_fee_seller

  (biz_output_obj.market.lovelace >= market_fee_total)? && (biz_output_obj.other.lovelace <= seller_input_lovelace + seller_receive_total - value.lovelace_of(
    tx.fee,
  ))? && (biz_output_obj.smart_contract.lovelace == biz_input_obj.smart_contract.lovelace - market_fee_total - seller_receive_total - buyer_receive_lovelace)? && when
    sm_output_utxo
  is {
    Some(utxo) ->
      when get_data(tx.datums, utxo.datum) is {
        Some(datum) -> {
          expect sm_output_bid_limit_datum: BidLimit = datum
          (sm_output_bid_limit_datum.owner_payment_key == bid_limit_datum.owner_payment_key)? && (sm_output_bid_limit_datum.owner_stake_key == bid_limit_datum.owner_stake_key)? && (sm_output_bid_limit_datum.to_epoch == bid_limit_datum.to_epoch)? && (sm_output_bid_limit_datum.from_epoch == bid_limit_datum.from_epoch)? && (sm_output_bid_limit_datum.requested_yield == bid_limit_datum.requested_yield)? && (sm_output_bid_limit_datum.quantity == buyer_bidding_bonds_qty - buyer_receive_bonds_qty)?
        }
        None ->
          // trace @"not found output bidding datum"
          False
      }
    None -> True
  }
}

pub fn sell(
  tx: Transaction,
  conf: Config,
  bid_limit_datum: BidLimit,
  owner: Address,
  smart_contract: Address,
) -> Bool {
  let validity_after_must_set =
    when tx.validity_range.lower_bound.bound_type is {
      Finite(x) -> x
      _ -> 0
    }
  let owner_vk =
    when owner.payment_credential is {
      VerificationKeyCredential(x) -> x
      _ -> #""
    }
  (bid_limit_datum.quantity > 0)? && (bid_limit_datum.to_epoch >= bid_limit_datum.from_epoch)? && (validity_after_must_set > 0)? && not(
    bytearray.is_empty(owner_vk),
  )? && when get_escrow_ref_inputs(tx.reference_inputs, conf.bond) is {
    Some(ref_input_escrow) ->
      when get_data(tx.datums, ref_input_escrow.output.datum) is {
        Some(d) -> {
          expect escrow_datum: EscrowDatum = d
          let current_epoch =
            posix_time_to_relative_epoch(
              validity_after_must_set,
              conf.bond.epoch_config,
            )
          let start_epoch =
            escrow_datum.start + conf.bond.epoch_config.epoch_boundary_as_epoch
          let end_epoch = start_epoch + escrow_datum.duration
          (end_epoch >= current_epoch)? && (end_epoch >= bid_limit_datum.from_epoch)? && (end_epoch <= bid_limit_datum.to_epoch)? && when
            get_escrow_info(
              conf.bond,
              value.lovelace_of(ref_input_escrow.output.value),
              escrow_datum,
              validity_after_must_set,
              current_epoch,
              start_epoch,
              end_epoch,
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
                  DatumTypeBidLimit,
                  escrow_datum.bond_symbol,
                  None,
                )
              biz_tx_info_valid && when biz_output_obj is {
                None -> {
                  trace @"biz_output_obj is None"
                  False
                }
                Some(biz_output) -> {
                  let sm_output_utxos =
                    list.concat(
                      biz_output.smart_contract.bond_outputs,
                      biz_output.smart_contract.other_outputs,
                    )
                  (biz_input_obj.owner.lovelace <= 0)? && (biz_input_obj.market.lovelace <= 0)? && (dict.size(
                    biz_output.owner.bond_assets,
                  ) > 0)? && (dict.size(biz_output.owner.bond_assets) <= 1)? && dict.has_key(
                    biz_output.owner.bond_assets,
                    escrow_info.token_name,
                  )? && (list.length(sm_output_utxos) <= 1)? && (
                    (biz_output.owner.bond_qty > 0)? && (biz_output.owner.bond_qty <= bid_limit_datum.quantity)?
                  ) && sell_correct(
                    tx,
                    conf,
                    bid_limit_datum,
                    biz_input_obj,
                    biz_output,
                    escrow_info,
                    list.at(sm_output_utxos, 0),
                  )
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
