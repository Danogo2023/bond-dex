use aiken/bytearray
use aiken/dict
use aiken/interval.{Finite}
use aiken/list
use aiken/transaction.{Output, Transaction}
use aiken/transaction/credential.{Address, VerificationKeyCredential}
use aiken/transaction/value
use bond/types.{
  BiddingDatum, BizOutput, BizTxInfo, Config, DatumTypeBidding, Error,
  EscrowDatum, EscrowInfo, OK,
}
use bond/utils.{
  collect_biz_tx_info, get_escrow_info, get_price_of_bond,
  posix_time_to_relative_epoch,
}
use common/utils.{get_data} as common_utils

fn sell_correct(
  tx: Transaction,
  conf: Config,
  bidding_datum: BiddingDatum,
  biz_input_obj: BizOutput,
  biz_output_obj: BizOutput,
  escrow_info: EscrowInfo,
  sm_output_utxo: Option<Output>,
) -> Bool {
  let buyer_receive_bonds_qty = biz_output_obj.owner.bond_qty
  let buyer_receive_lovelace = biz_output_obj.owner.lovelace
  let buyer_bidding_bonds_qty = bidding_datum.quantity

  let seller_input_lovelace = biz_input_obj.other.lovelace

  let price_of_one_bond =
    get_price_of_bond(
      escrow_info.received_at_maturity_one_bond,
      escrow_info.day_to_maturity,
      bidding_datum.requested_yield,
      conf.bond.basis_points_ref_unit,
    )
  // Tong tien lender nhan duoc cuoi chu ky dao han bao gom ca goc va lai tuong ung vs so bond ma buyer mua
  let received_at_maturity =
    escrow_info.received_at_maturity_one_bond * buyer_receive_bonds_qty
  // Tong tien buyer(owner of bidding) phai tra/seller nhan duoc chua tru phi
  let received_with_yield = price_of_one_bond * buyer_receive_bonds_qty
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

  // So tien fee + min ada cua listing toi thieu ma san phai nhan duoc
  let market_fee_receive_valid =
    biz_output_obj.market.lovelace >= market_fee_total
  // So tien seller nhan duoc sau khi tru phi
  let seller_receive_valid =
    biz_output_obj.other.lovelace <= seller_input_lovelace + seller_receive_total
  // So tien smart contract phai thu lai sau khi da tru tien phi, tien tra cho seller va tien so du toi thieu gui bond cho buyer(owner of bidding)
  let sm_receive_valid =
    biz_output_obj.smart_contract.lovelace >= biz_input_obj.smart_contract.lovelace - market_fee_total - seller_receive_total - buyer_receive_lovelace

  market_fee_receive_valid? && seller_receive_valid? && sm_receive_valid? && when
    sm_output_utxo
  is {
    Some(utxo) ->
      when get_data(tx.datums, utxo.datum) is {
        Some(datum) -> {
          expect sm_output_bidding_datum: BiddingDatum = datum
          let sm_output_bidding_datum_pk_valid =
            sm_output_bidding_datum.owner_payment_key == bidding_datum.owner_payment_key
          let sm_output_bidding_datum_sk_valid =
            sm_output_bidding_datum.owner_stake_key == bidding_datum.owner_stake_key
          let sm_output_bidding_datum_fepoch_valid =
            sm_output_bidding_datum.from_epoch == bidding_datum.from_epoch
          let sm_output_bidding_datum_tepoch_valid =
            sm_output_bidding_datum.to_epoch == bidding_datum.to_epoch
          let sm_output_bidding_datum_yield_valid =
            sm_output_bidding_datum.requested_yield == bidding_datum.requested_yield
          let sm_output_bidding_datum_quantity_valid =
            sm_output_bidding_datum.quantity == buyer_bidding_bonds_qty - buyer_receive_bonds_qty
          sm_output_bidding_datum_pk_valid? && sm_output_bidding_datum_sk_valid? && sm_output_bidding_datum_tepoch_valid? && sm_output_bidding_datum_fepoch_valid? && sm_output_bidding_datum_yield_valid? && sm_output_bidding_datum_quantity_valid?
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
  bidding_datum: BiddingDatum,
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
  let bidding_datum_valid =
    (bidding_datum.quantity > 0)? && (bidding_datum.to_epoch >= bidding_datum.from_epoch)?
  bidding_datum_valid && (validity_after_must_set > 0)? && not(
    bytearray.is_empty(owner_vk),
  )? && when
    list.find(
      tx.reference_inputs,
      fn(input) {
        dict.size(value.tokens(input.output.value, conf.bond.escrow_policy_id)) > 0
      },
    )
  is {
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
          (end_epoch >= current_epoch)? && (end_epoch >= bidding_datum.from_epoch)? && (end_epoch <= bidding_datum.to_epoch)? && when
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
                  DatumTypeBidding,
                  escrow_datum.bond_symbol,
                )
              biz_tx_info_valid && when biz_output_obj is {
                None -> {
                  trace @"biz_output_obj is None"
                  False
                }
                Some(biz_output) -> {
                  let owner_output_must_only_one_bond_name =
                    dict.size(biz_output.owner.bond_assets) <= 1
                  let owner_output_bond_same_escrow =
                    dict.has_key(
                      biz_output.owner.bond_assets,
                      escrow_info.token_name,
                    )
                  let seller_must_not_owner = biz_input_obj.owner.lovelace <= 0
                  let seller_must_not_market =
                    biz_input_obj.market.lovelace <= 0
                  let seller_input_bond_policy_id_match_escrow =
                    dict.size(biz_output.owner.bond_assets) > 0
                  let sm_output_utxos =
                    list.concat(
                      biz_output.smart_contract.bond_outputs,
                      biz_output.smart_contract.other_outputs,
                    )
                  let sm_output_must_only_one_utxo =
                    list.length(sm_output_utxos) <= 1
                  let buyer_receive_bonds_valid =
                    biz_output.owner.bond_qty > 0 && biz_output.owner.bond_qty <= bidding_datum.quantity
                  seller_input_bond_policy_id_match_escrow? && owner_output_must_only_one_bond_name? && owner_output_bond_same_escrow? && seller_must_not_owner? && seller_must_not_market? && sm_output_must_only_one_utxo? && buyer_receive_bonds_valid? && sell_correct(
                    tx,
                    conf,
                    bidding_datum,
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
      trace @"not found reference_inputs with escrow_policy_id"
      False
    }
  }
}
