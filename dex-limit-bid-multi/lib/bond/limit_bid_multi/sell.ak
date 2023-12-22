// Bid Limit Multi
use aiken/bytearray
use aiken/dict
use aiken/list
use aiken/transaction.{Output, Transaction}
use aiken/transaction/credential.{Address}
use aiken/transaction/value
use bond/limit_bid_multi/utils.{collect_biz_tx_info}
use bond/types.{
  BidLimitMulti, BizOutput, BizTxInfo, BondConfigLimit, Error, EscrowDatum,
  EscrowInfo, OK,
}
use bond/v2/constraint.{
  get_escrow_info, get_escrow_ref_inputs, get_price_of_bond,
}
use common/time.{posix_time_to_relative_epoch, tx_validity_valid}
use common/util.{get_data} as common_utils

fn matching_correct(
  tx: Transaction,
  cfg: BondConfigLimit,
  sbid_dt: BidLimitMulti,
  in: BizOutput,
  out: BizOutput,
  escrow_info: EscrowInfo,
  sc_out_utxo: Option<Output>,
) -> Bool {
  let buyer_receive_bonds_qty = out.owner.bond_qty
  // Tong tien lender nhan duoc cuoi chu ky dao han bao gom ca goc va lai tuong ung vs so bond ma buyer mua
  let received_at_maturity =
    escrow_info.received_at_maturity_one_bond * buyer_receive_bonds_qty
  // Tong tien buyer(owner of bid) phai tra/seller nhan duoc chua tru phi
  let received_with_yield =
    get_price_of_bond(
      escrow_info.received_at_maturity_one_bond,
      escrow_info.day_to_maturity,
      sbid_dt.requested_yield,
      cfg.platform.basis.base,
    ) * buyer_receive_bonds_qty
  // Chenh lech tien lai nhan duoc
  let received_diff = received_at_maturity - received_with_yield
  // phi seller phai tra cho san theo ti le trong config
  let exchange_fee_seller =
    received_diff * cfg.exchange.seller_fee / cfg.platform.basis.base
  // phi buyer(owner of bid) phai tra cho san theo ti le trong config
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.platform.basis.base
  let exchange_fee_total_tmp = exchange_fee_buyer + exchange_fee_seller
  let seller_receive_total = received_with_yield - exchange_fee_seller
  let sc_out_remain = sbid_dt.quantity - buyer_receive_bonds_qty
  let (buyer_receive_lovelace, exchange_fee_total) =
    when list.at(out.owner.addresses, 0) is {
      Some(a) ->
        if a == cfg.exchange.address {
          (out.owner.lovelace, 0)
        } else {
          (out.owner.lovelace, exchange_fee_total_tmp)
        }
      _ -> (out.owner.lovelace, exchange_fee_total_tmp)
    }
  let seller_in_utxos_len =
    list.length(list.concat(in.other.bond_outputs, in.other.other_outputs))
  let (
    seller_in_lovelace,
    seller_in_bond_qty,
    seller_ou_lovelace,
    lovelace_seller_is_exchange,
  ) =
    if seller_in_utxos_len == 0 && in.exchange.bond_qty > 0 {
      (
        in.exchange.lovelace,
        in.exchange.bond_qty,
        out.exchange.lovelace,
        exchange_fee_total,
      )
    } else {
      (in.other.lovelace, in.other.bond_qty, out.other.lovelace, 0)
    }
  and {
    (out.exchange.lovelace >= exchange_fee_total)?,
    (out.owner.bond_qty <= seller_in_bond_qty)?,
    (seller_ou_lovelace <= seller_in_lovelace + seller_receive_total + lovelace_seller_is_exchange - value.lovelace_of(
      tx.fee,
    ))?,
    (out.sc.lovelace == in.sc.lovelace - exchange_fee_total - seller_receive_total - buyer_receive_lovelace)?,
    (sc_out_remain == 0)? || when sc_out_utxo is {
      Some(utxo) -> and {
          (sc_out_remain > 0)?,
          when get_data(tx.datums, utxo.datum) is {
            Some(d) -> {
              expect sc_out_datum: BidLimitMulti = d
              and {
                (sc_out_datum.quantity > 0)?,
                (sc_out_datum.quantity == sc_out_remain)?,
              }
            }
            None -> {
              trace @"not found output bid datum"
              False
            }
          },
        }
      None -> True
    },
  }
}

pub fn matching(
  tx: Transaction,
  cfg: BondConfigLimit,
  sbid_dt: BidLimitMulti,
  owner: Address,
  spending: Address,
) -> Bool {
  let tx_time_valid =
    tx_validity_valid(
      tx.validity_range,
      cfg.platform.slot.slot_length,
      Some(60 * 60),
    )

  and {
    (sbid_dt.quantity > 0)?,
    (sbid_dt.to_epoch >= sbid_dt.from_epoch)?,
    (tx_time_valid > 0)?,
    not(bytearray.is_empty(sbid_dt.owner_vk))?,
    when get_escrow_ref_inputs(tx.reference_inputs, cfg.escrow) is {
      (Some(ref_escrow), Some(bond_type)) -> and {
          list.has(sbid_dt.bond_types, bond_type)?,
          when get_data(tx.datums, ref_escrow.output.datum) is {
            Some(d) -> {
              expect escrow_dt: EscrowDatum = d
              let current_epoch =
                posix_time_to_relative_epoch(tx_time_valid, cfg.platform.epoch)
              let start_epoch =
                escrow_dt.start + cfg.platform.epoch.epoch_boundary_as_epoch
              let end_epoch = start_epoch + escrow_dt.duration
              let ref_escrow_balance = value.lovelace_of(ref_escrow.output.value)
              and {
                (end_epoch >= current_epoch)?,
                (end_epoch >= sbid_dt.from_epoch)?,
                (end_epoch <= sbid_dt.to_epoch)?,
                (escrow_dt.bond_amount > 0)?,
                (value.lovelace_of(escrow_dt.epo_rewards) > 0)?,
                (ref_escrow_balance > escrow_dt.bond_amount * cfg.platform.bond_face_value)?,
                when
                  get_escrow_info(
                    cfg.platform,
                    ref_escrow_balance,
                    escrow_dt,
                    tx_time_valid,
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
                        cfg,
                        tx.inputs,
                        tx.outputs,
                        owner,
                        spending,
                        tx.datums,
                        escrow_info,
                        sbid_dt,
                      )
                    and {
                      biz_tx_info_valid,
                      when out is {
                        None -> fail @"out is None"
                        Some(ou) -> {
                          let owner_in_utxos_len =
                            list.length(
                              list.concat(
                                in.owner.bond_outputs,
                                in.owner.other_outputs,
                              ),
                            )
                          let sc_out_utxos =
                            list.concat(ou.sc.bond_outputs, ou.sc.other_outputs)
                          let owner_output_len =
                            list.length(
                              list.concat(
                                ou.owner.bond_outputs,
                                ou.owner.other_outputs,
                              ),
                            )
                          and {
                            (owner_in_utxos_len == 0)?,
                            (dict.size(ou.owner.bond_assets) == 1)?,
                            dict.has_key(
                              ou.owner.bond_assets,
                              escrow_info.token_name,
                            )?,
                            (list.length(sc_out_utxos) <= 1)?,
                            (owner_output_len <= 1)?,
                            (ou.owner.bond_qty > 0)?,
                            (ou.owner.bond_qty <= sbid_dt.quantity)?,
                            (ou.owner.bond_qty <= escrow_dt.bond_amount)?,
                            matching_correct(
                              tx,
                              cfg,
                              sbid_dt,
                              in,
                              ou,
                              escrow_info,
                              list.at(sc_out_utxos, 0),
                            ),
                          }
                        }
                      },
                    }
                  }
                  Error(_) -> fail @"bond is closable"
                },
              }
            }
            _ -> fail @"not found escrow datum in reference_inputs"
          },
        }
      _ -> fail @"not found escrow info in reference_inputs"
    },
  }
}
