// Bid Limit Multi
use aiken/bytearray
use aiken/dict
use aiken/list
use aiken/option
use aiken/transaction.{InlineDatum, Output, ScriptContext, Spend, Transaction}
use aiken/transaction/credential.{Address}
use aiken/transaction/value
use bond/limit_bid_multi/utils.{collect_biz_tx_info}
use bond/types.{
  BidLimitMulti, BizOutput, BizTxInfo, BondConfigLimit, EscrowDatum, EscrowInfo,
}
use bond/utils.{get_price_of_bond, head_escrow_ref} as bond_utils
use common/string.{bconcat_3} as common_string
use common/time.{EpochTime, posix_time_to_relative_epoch, tx_validity_valid}
use common/types.{Error, Lovelace, OK} as common_types
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
  let trade_qty = out.owner.bond_qty
  // Tong tien lender nhan duoc cuoi chu ky dao han bao gom ca goc va lai tuong ung vs so bond ma buyer mua
  let received_at_maturity = escrow_info.value_at_maturity * trade_qty
  // Tong tien buyer(owner of bid) phai tra/seller nhan duoc chua tru phi
  let received_with_yield =
    get_price_of_bond(
      escrow_info.value_at_maturity,
      escrow_info.day_to_maturity,
      sbid_dt.requested_yield,
      cfg.platform.basis.base,
    ) * trade_qty
  // Chenh lech tien lai nhan duoc
  let received_diff = received_at_maturity - received_with_yield
  // phi seller phai tra cho san theo ti le trong config
  let exchange_fee_seller =
    received_diff * cfg.exchange.seller_fee / cfg.platform.basis.base
  // phi buyer(owner of bid) phai tra cho san theo ti le trong config
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.platform.basis.base
  let exchange_fee_total_tmp = exchange_fee_buyer + exchange_fee_seller
  let oseller_total = received_with_yield - exchange_fee_seller
  let obid_qty_remain = sbid_dt.quantity - trade_qty
  let (obuyer_value, exchange_fee_total) =
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
    (seller_ou_lovelace <= seller_in_lovelace + oseller_total + lovelace_seller_is_exchange - value.lovelace_of(
      tx.fee,
    ))?,
    (out.sc.lovelace == in.sc.lovelace - exchange_fee_total - oseller_total - obuyer_value)?,
    when sc_out_utxo is {
      Some(utxo) ->
        when get_data(tx.datums, utxo.datum) is {
          Some(d) -> {
            expect sc_out_datum: BidLimitMulti = d
            and {
              (sc_out_datum.quantity > 0)?,
              (sc_out_datum.quantity == obid_qty_remain)?,
            }
          }
          _ -> {
            trace @"not found output bid datum"
            False
          }
        }
      _ -> (obid_qty_remain == 0)?
    },
  }
}

pub fn matching(
  tx: Transaction,
  cfg: BondConfigLimit,
  sbid_dt: BidLimitMulti,
  sbid_addr: Address,
) -> Bool {
  let buyer_addr: Address =
    sbid_dt.owner_sk
      |> option.and_then(
           fn(s) {
             Some(
               credential.from_verification_key(sbid_dt.owner_vk)
                 |> credential.with_delegation_key(s),
             )
           },
         )
      |> option.or_else(credential.from_verification_key(sbid_dt.owner_vk))
  when
    tx_validity_valid(
      tx.validity_range,
      cfg.platform.slot.slot_length,
      Some(60 * 60),
      True,
    )
  is {
    OK(tx_time_valid) -> {
      let epo_curr: EpochTime =
        posix_time_to_relative_epoch(tx_time_valid, cfg.platform.epoch)
      and {
        (tx_time_valid > 0)?,
        (sbid_dt.quantity > 0)?,
        (sbid_dt.to_epoch >= sbid_dt.from_epoch)?,
        not(bytearray.is_empty(sbid_dt.owner_vk))?,
        when
          head_escrow_ref(
            cfg.platform,
            cfg.escrow,
            tx.reference_inputs,
            tx.datums,
            sbid_dt.bond_types,
            tx_time_valid,
            epo_curr,
          )
        is {
          OK(escrow_ref) ->
            when escrow_ref |> dict.to_list is {
              [(bond_unit, escrow_data)] -> {
                let (
                  _escrow_input,
                  escrow_dt,
                  _bond_type,
                  _escrow_bal,
                  escrow_info,
                ) = escrow_data
                if and {
                  (escrow_info.end_epoch >= epo_curr)?,
                  (escrow_info.end_epoch >= sbid_dt.from_epoch)?,
                  (escrow_info.end_epoch <= sbid_dt.to_epoch)?,
                } {
                  let BizTxInfo {
                    valid: biz_tx_info_valid,
                    biz_tx_in: in,
                    biz_tx_out: out,
                  } =
                    collect_biz_tx_info(
                      cfg,
                      tx.inputs,
                      tx.outputs,
                      buyer_addr,
                      sbid_addr,
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
                } else {
                  fail bconcat_3(
                    @"escrow of bond ",
                    bond_unit,
                    @" invalid epoch",
                  )
                }
              }
              _ -> fail @"not found escrow info in reference_inputs"
            }
          Error(e) -> fail e
        },
      }
    }
    Error(e) -> fail e
  }
}

pub fn spending(
  ctx: ScriptContext,
  cfg: BondConfigLimit,
  sbid_dt: BidLimitMulti,
) -> Bool {
  let tx = ctx.transaction
  when
    tx_validity_valid(
      tx.validity_range,
      cfg.platform.slot.slot_length,
      Some(60 * 60),
      True,
    )
  is {
    OK(tx_time_valid) -> {
      let epo_curr: EpochTime =
        posix_time_to_relative_epoch(tx_time_valid, cfg.platform.epoch)
      and {
        (sbid_dt.quantity > 0)?,
        (sbid_dt.to_epoch >= sbid_dt.from_epoch)?,
        (tx_time_valid > 0)?,
        not(bytearray.is_empty(sbid_dt.owner_vk))?,
        when
          head_escrow_ref(
            cfg.platform,
            cfg.escrow,
            tx.reference_inputs,
            tx.datums,
            sbid_dt.bond_types,
            tx_time_valid,
            epo_curr,
          )
        is {
          OK(escrow_ref) ->
            when escrow_ref |> dict.to_list is {
              [(bond_unit, escrow_data)] -> {
                let (
                  _escrow_input,
                  _escrow_dt,
                  _bond_type,
                  _escrow_bal,
                  escrow_info,
                ) = escrow_data
                if and {
                  (escrow_info.end_epoch >= epo_curr)?,
                  (escrow_info.end_epoch >= sbid_dt.from_epoch)?,
                  (escrow_info.end_epoch <= sbid_dt.to_epoch)?,
                } {
                  expect Spend(sbid_out_ref) = ctx.purpose
                  expect Some(sbid) =
                    list.find(
                      tx.inputs,
                      fn(i) { i.output_reference == sbid_out_ref },
                    )
                  let sbid_addr: Address = sbid.output.address
                  let buyer_addr: Address =
                    sbid_dt.owner_sk
                      |> option.and_then(
                           fn(s) {
                             Some(
                               credential.from_verification_key(
                                 sbid_dt.owner_vk,
                               )
                                 |> credential.with_delegation_key(s),
                             )
                           },
                         )
                      |> option.or_else(
                           credential.from_verification_key(sbid_dt.owner_vk),
                         )
                  // trace cbor.diagnostic(buyer_addr)
                  let fee_addr: Address = cfg.exchange.address
                  // (
                  //   ibid_value: Lovelace, 
                  //   ibuyer_value: Lovelace, 
                  //   ibuyer_bond_qty: Int, 
                  //   ifee_value: Lovelace, 
                  //   ifee_bond_qty: Int,
                  //   iseller_value: Int, 
                  //   iseller_bond_qty: Int,
                  //   iseller_addr: List<Address>, 
                  // )
                  let (
                    ibid_value,
                    _ibuyer_value,
                    _ibuyer_bond_qty,
                    _ifee_value,
                    _ifee_bond_qty,
                    iseller_value,
                    iseller_bond_qty,
                    iseller_addr,
                  ) =
                    list.foldl(
                      tx.inputs,
                      (0, 0, 0, 0, 0, 0, 0, []),
                      fn(i, z) {
                        let ivalue = value.lovelace_of(i.output.value)
                        let iaddr = i.output.address
                        let is_ibid_order =
                          iaddr.payment_credential == sbid_addr.payment_credential
                        if is_ibid_order {
                          if z.1st == 0 {
                            (
                              ivalue,
                              z.2nd,
                              z.3rd,
                              z.4th,
                              z.5th,
                              z.6th,
                              z.7th,
                              z.8th,
                            )
                          } else {
                            fail @"matching only one bid order allowed"
                          }
                        } else {
                          let ibond_qty =
                            value.quantity_of(
                              i.output.value,
                              escrow_info.bond_symbol,
                              escrow_info.token_name,
                            )
                          if iaddr == buyer_addr {
                            (
                              z.1st,
                              z.2nd + ivalue,
                              z.3rd + ibond_qty,
                              z.4th,
                              z.5th,
                              z.6th,
                              z.7th,
                              z.8th,
                            )
                          } else if iaddr == fee_addr {
                            (
                              z.1st,
                              z.2nd,
                              z.3rd,
                              z.4th + ivalue,
                              z.5th + ibond_qty,
                              z.6th,
                              z.7th,
                              z.8th,
                            )
                          } else {
                            (
                              z.1st,
                              z.2nd,
                              z.3rd,
                              z.4th,
                              z.5th,
                              z.6th + ivalue,
                              z.7th + ibond_qty,
                              [iaddr, ..z.8th],
                            )
                          }
                        }
                      },
                    )
                  // ( 
                  //   obid_value: Lovelace,
                  //   dt: Option<BidLimitMulti>, 
                  //   obuyer_value: Lovelace, 
                  //   obuyer_bond_qty: Int, 
                  //   ofee_value: Lovelace, 
                  //   ofee_bond_qty: Int, 
                  //   oseller_value: Lovelace, 
                  //   oseller_bond_qty: Int
                  // )
                  let (
                    obid_value,
                    obid_dt,
                    obuyer_value,
                    obuyer_bond_qty,
                    ofee_value,
                    _ofee_bond_qty,
                    oseller_value,
                    _oseller_bond_qty,
                  ) =
                    list.foldl(
                      tx.outputs,
                      (0, None, 0, 0, 0, 0, 0, 0),
                      fn(o, z) {
                        let oaddr = o.address
                        let ovalue = value.lovelace_of(o.value)
                        let is_obid_order =
                          oaddr.payment_credential == sbid_addr.payment_credential
                        if is_obid_order {
                          if (z.1st == 0)? {
                            expect obid_dt: BidLimitMulti =
                              when o.datum is {
                                InlineDatum(d) -> d
                                _ ->
                                  fail @"only supports InlineDatum for bid order"
                              }
                            if and {
                              (obid_dt.owner_vk == sbid_dt.owner_vk)?,
                              (obid_dt.owner_sk == sbid_dt.owner_sk)?,
                              (obid_dt.from_epoch == sbid_dt.from_epoch)?,
                              (obid_dt.to_epoch == sbid_dt.to_epoch)?,
                              (obid_dt.quantity > 0)?,
                              (obid_dt.quantity < sbid_dt.quantity)?,
                              (obid_dt.requested_yield == sbid_dt.requested_yield)?,
                              (list.difference(
                                obid_dt.bond_types,
                                sbid_dt.bond_types,
                              ) == [])?,
                            } {
                              (
                                ovalue,
                                Some(obid_dt),
                                z.3rd,
                                z.4th,
                                z.5th,
                                z.6th,
                                z.7th,
                                z.8th,
                              )
                            } else {
                              fail @"bid order output invalid datum"
                            }
                          } else {
                            fail @"must only one bid order output allowed"
                          }
                        } else {
                          let obond_qty =
                            value.quantity_of(
                              o.value,
                              escrow_info.bond_symbol,
                              escrow_info.token_name,
                            )
                          if oaddr == buyer_addr {
                            if (z.3rd == 0)? {
                              if (obond_qty > 0)? {
                                (
                                  z.1st,
                                  z.2nd,
                                  ovalue,
                                  obond_qty,
                                  z.5th,
                                  z.6th,
                                  z.7th,
                                  z.8th,
                                )
                              } else {
                                fail @"not found owner bond receive"
                              }
                            } else {
                              fail @"must only one owner output for bid order allowed"
                            }
                          } else if oaddr == fee_addr {
                            if (z.5th == 0)? {
                              (
                                z.1st,
                                z.2nd,
                                z.3rd,
                                z.4th,
                                ovalue,
                                obond_qty,
                                z.7th,
                                z.8th,
                              )
                            } else {
                              fail @"must only one fee output for bid order allowed"
                            }
                          } else {
                            (
                              z.1st,
                              z.2nd,
                              z.3rd,
                              z.4th,
                              z.5th,
                              z.6th,
                              z.7th + ovalue,
                              z.8th + obond_qty,
                            )
                          }
                        }
                      },
                    )
                  and {
                    (obuyer_bond_qty > 0)?,
                    spending_correct(
                      tx,
                      cfg,
                      escrow_info,
                      sbid_dt,
                      ibid_value,
                      obid_value,
                      obid_dt,
                      buyer_addr,
                      obuyer_value,
                      obuyer_bond_qty,
                      ofee_value,
                      iseller_addr,
                      iseller_value,
                      iseller_bond_qty,
                      oseller_value,
                    ),
                  }
                } else {
                  fail bconcat_3(
                    @"escrow of bond ",
                    bond_unit,
                    @" invalid epoch",
                  )
                }
              }
              _ -> fail @"not found escrow info in reference_inputs"
            }
          Error(s) -> fail s
        },
      }
    }
    Error(e) -> fail e
  }
}

fn spending_correct(
  tx: Transaction,
  cfg: BondConfigLimit,
  escrow_info: EscrowInfo,
  sbid_dt: BidLimitMulti,
  ibid_value: Lovelace,
  obid_value: Lovelace,
  obid_dt: Option<BidLimitMulti>,
  buyer_addr: Address,
  obuyer_value: Lovelace,
  obuyer_bond_qty: Int,
  ofee_value: Lovelace,
  seller_addr: List<Address>,
  iseller_value: Lovelace,
  iseller_bond_qty: Int,
  oseller_value: Lovelace,
) -> Bool {
  // Tong tien lender nhan duoc cuoi chu ky dao han bao gom ca goc va lai tuong ung vs so bond ma buyer mua
  let received_at_maturity: Lovelace =
    escrow_info.value_at_maturity * obuyer_bond_qty
  // Tong tien buyer(owner of bid) phai tra/seller nhan duoc chua tru phi
  let received_with_yield: Lovelace =
    get_price_of_bond(
      escrow_info.value_at_maturity,
      escrow_info.day_to_maturity,
      sbid_dt.requested_yield,
      cfg.platform.basis.base,
    ) * obuyer_bond_qty
  // Chenh lech tien lai nhan duoc
  let received_diff: Lovelace = received_at_maturity - received_with_yield
  // phi seller phai tra cho san theo ti le trong config
  let exchange_fee_seller: Lovelace =
    received_diff * cfg.exchange.seller_fee / cfg.platform.basis.base
  // phi buyer(owner of bid) phai tra cho san theo ti le trong config
  let exchange_fee_buyer: Lovelace =
    received_diff * cfg.exchange.buyer_fee / cfg.platform.basis.base
  //
  let oseller_max_recevie: Lovelace = received_with_yield - exchange_fee_seller
  //
  let obid_bond_qty_remain: Int = sbid_dt.quantity - obuyer_bond_qty
  //
  let exchange_fee = exchange_fee_buyer + exchange_fee_seller
  // buyer is exchange addr
  let exchange_fee_for_buyer: Lovelace =
    if buyer_addr == cfg.exchange.address {
      exchange_fee
    } else {
      0
    }
  //
  // seller is exchange addr
  let exchange_fee_for_seller: Lovelace =
    if list.has(seller_addr, cfg.exchange.address) {
      exchange_fee
    } else {
      0
    }
  //
  let exchange_fee_total: Lovelace =
    if or {
      exchange_fee_for_buyer > 0,
      exchange_fee_for_seller > 0,
    } {
      0
    } else {
      exchange_fee
    }
  //
  let tx_fee: Lovelace = value.lovelace_of(tx.fee)
  //
  and {
    (ofee_value >= exchange_fee_total)?,
    (obuyer_bond_qty <= iseller_bond_qty)?,
    (oseller_value <= iseller_value + oseller_max_recevie + exchange_fee_for_seller - tx_fee)?,
    (obid_value == ibid_value - exchange_fee_total - oseller_max_recevie - obuyer_value)?,
    when obid_dt is {
      Some(odt) -> (odt.quantity == obid_bond_qty_remain)?
      _ -> (obid_bond_qty_remain == 0)?
    },
  }
}
