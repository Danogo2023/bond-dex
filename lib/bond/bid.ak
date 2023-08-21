use aiken/bytearray
use aiken/dict
use aiken/interval.{Finite}
use aiken/list
use aiken/transaction.{Output, Transaction}
use aiken/transaction/credential.{Address}
use aiken/transaction/value
use bond/types.{
  BidLimit, BidMaking, BizOutput, BizTxInfo, BondDatum, Config,
  DatumTypeBidLimit, DatumTypeBidMaking, Error, EscrowDatum, EscrowInfo,
  MakingDatum, OK,
}
use bond/utils.{
  collect_biz_tx_info, get_escrow_info, get_escrow_ref_inputs, get_price_of_bond,
  posix_time_to_relative_epoch,
}
use common/utils.{get_data} as common_utils

fn sell_correct(
  tx: Transaction,
  conf: Config,
  spd_bid_datum: BondDatum<Option<BidLimit>, Option<BidMaking>>,
  in: BizOutput,
  out: BizOutput,
  escrow_info: EscrowInfo,
  sc_out_utxo: Option<Output>,
) -> Bool {
  let buyer_receive_bonds_qty = out.owner.bond_qty
  let buyer_receive_lovelace = out.owner.lovelace
  let (
    spending_quantity,
    spending_to_epoch,
    spending_from_epoch,
    spending_requested_yield,
    spending_owner_payment_key,
    spending_owner_stake_key,
  ) =
    when spd_bid_datum.making is {
      Some(m) ->
        (
          m.quantity,
          m.to_epoch,
          m.from_epoch,
          m.requested_yield,
          m.owner_payment_key,
          m.owner_stake_key,
        )
      _ ->
        when spd_bid_datum.limit is {
          Some(l) ->
            (
              l.quantity,
              l.to_epoch,
              l.from_epoch,
              l.requested_yield,
              l.owner_payment_key,
              l.owner_stake_key,
            )
          _ -> (-1, -1, -1, -1, #"", None)
        }
    }

  let seller_in_lovelace = in.other.lovelace
  // Tong tien lender nhan duoc cuoi chu ky dao han bao gom ca goc va lai tuong ung vs so bond ma buyer mua
  let received_at_maturity =
    escrow_info.received_at_maturity_one_bond * buyer_receive_bonds_qty
  // Tong tien buyer(owner of bid) phai tra/seller nhan duoc chua tru phi
  let received_with_yield =
    get_price_of_bond(
      escrow_info.received_at_maturity_one_bond,
      escrow_info.day_to_maturity,
      spending_requested_yield,
      conf.bond.basis_points_ref_unit,
    ) * buyer_receive_bonds_qty
  // Chenh lech tien lai nhan duoc
  let received_diff = received_at_maturity - received_with_yield
  // phi seller phai tra cho san theo ti le trong config
  let market_fee_seller =
    received_diff * conf.market.seller_fee / conf.bond.basis_points_ref_unit
  // phi buyer(owner of bid) phai tra cho san theo ti le trong config
  let market_fee_buyer =
    received_diff * conf.market.buyer_fee / conf.bond.basis_points_ref_unit
  let market_fee_total = market_fee_buyer + market_fee_seller
  let seller_receive_total = received_with_yield - market_fee_seller

  (out.market.lovelace >= market_fee_total)? && (out.other.lovelace <= seller_in_lovelace + seller_receive_total - value.lovelace_of(
    tx.fee,
  ))? && (out.sc.lovelace == in.sc.lovelace - market_fee_total - seller_receive_total - buyer_receive_lovelace)? && when
    sc_out_utxo
  is {
    Some(utxo) ->
      when get_data(tx.datums, utxo.datum) is {
        Some(datum) -> {
          expect sc_out_datum: BidLimit = datum
          (sc_out_datum.owner_payment_key == spending_owner_payment_key)? && (sc_out_datum.owner_stake_key == spending_owner_stake_key)? && (sc_out_datum.to_epoch == spending_to_epoch)? && (sc_out_datum.from_epoch == spending_from_epoch)? && (sc_out_datum.requested_yield == spending_requested_yield)? && (sc_out_datum.quantity == spending_quantity - buyer_receive_bonds_qty)?
        }
        None ->
          // trace @"not found output bid datum"
          False
      }
    None -> True
  }
}

pub fn sell(
  tx: Transaction,
  conf: Config,
  spd_bid_datum: BondDatum<Option<BidLimit>, Option<BidMaking>>,
  owner: Address,
  sc: Address,
) -> Bool {
  let validity_after_must_set =
    when tx.validity_range.lower_bound.bound_type is {
      Finite(x) -> x
      _ -> 0
    }
  let (owner_vk, spending_quantity, spending_to_epoch, spending_from_epoch) =
    when spd_bid_datum.making is {
      Some(m) -> (m.owner_payment_key, m.quantity, m.to_epoch, m.from_epoch)
      _ ->
        when spd_bid_datum.limit is {
          Some(l) -> (l.owner_payment_key, l.quantity, l.to_epoch, l.from_epoch)
          _ -> (#"", -1, -1, -1)
        }
    }
  (spending_quantity > 0)? && (spending_to_epoch >= spending_from_epoch)? && (validity_after_must_set > 0)? && not(
    bytearray.is_empty(owner_vk),
  )? && when get_escrow_ref_inputs(tx.reference_inputs, conf.bond) is {
    Some(ref_in_escrow) ->
      when get_data(tx.datums, ref_in_escrow.output.datum) is {
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
          (end_epoch >= current_epoch)? && (end_epoch >= spending_from_epoch)? && (end_epoch <= spending_to_epoch)? && when
            get_escrow_info(
              conf.bond,
              value.lovelace_of(ref_in_escrow.output.value),
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
                biz_tx_in: in,
                biz_tx_out: out,
              } =
                collect_biz_tx_info(
                  conf,
                  tx.inputs,
                  tx.outputs,
                  owner,
                  sc,
                  [owner_vk],
                  tx.datums,
                  when spd_bid_datum.making is {
                    Some(_) -> DatumTypeBidMaking
                    _ -> DatumTypeBidLimit
                  },
                  escrow_datum.bond_symbol,
                  MakingDatum(None, spd_bid_datum.making),
                )
              biz_tx_info_valid && when out is {
                None -> {
                  trace @"out is None"
                  False
                }
                Some(ou) -> {
                  let sc_out_utxos =
                    list.concat(ou.sc.bond_outputs, ou.sc.other_outputs)
                  (in.owner.lovelace <= 0)? && (in.market.lovelace <= 0)? && (dict.size(
                    ou.owner.bond_assets,
                  ) > 0)? && (dict.size(ou.owner.bond_assets) <= 1)? && dict.has_key(
                    ou.owner.bond_assets,
                    escrow_info.token_name,
                  )? && (list.length(sc_out_utxos) <= 1)? && (
                    (ou.owner.bond_qty > 0)? && (ou.owner.bond_qty <= in.other.bond_qty)? && (ou.owner.bond_qty <= spending_quantity)?
                  ) && sell_correct(
                    tx,
                    conf,
                    spd_bid_datum,
                    in,
                    ou,
                    escrow_info,
                    list.at(sc_out_utxos, 0),
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
