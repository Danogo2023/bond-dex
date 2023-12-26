// Bid Limit
use aiken/bytearray
use aiken/dict
use aiken/list
use aiken/transaction.{InlineDatum, Output, ScriptContext, Spend, Transaction}
use aiken/transaction/credential.{Address}
use aiken/transaction/value
use bond/limit_bid/utils.{collect_biz_tx_info} as limit_bid_utils
use bond/types.{
  BidLimit, BizOutput, BizTxInfo, BondConfigLimit, EscrowDatum, EscrowInfo,
  UniqBidLimitMulti,
}
use bond/utils.{
  get_escrow_info_1, get_escrow_ref, get_price_of_bond, list_escrow_ref,
}
use common/convert
use common/hash_out_refs.{hash_out_ref_salt}
use common/string.{bconcat_3} as common_string
use common/time.{EpochTime, posix_time_to_relative_epoch, tx_validity_valid}
use common/types.{Error, OK} as common_types
use common/util.{get_data} as common_utils

fn matching_correct(
  tx: Transaction,
  cfg: BondConfigLimit,
  sbid_dt: BidLimit,
  in: BizOutput,
  out: BizOutput,
  escrow_info: EscrowInfo,
  sc_out_utxo: Option<Output>,
) -> Bool {
  let buyer_receive_bonds_qty = out.owner.bond_qty
  // Tong tien lender nhan duoc cuoi chu ky dao han bao gom ca goc va lai tuong ung vs so bond ma buyer mua
  let received_at_maturity =
    escrow_info.value_at_maturity * buyer_receive_bonds_qty
  // Tong tien buyer(owner of bid) phai tra/seller nhan duoc chua tru phi
  let received_with_yield =
    get_price_of_bond(
      escrow_info.value_at_maturity,
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
    when sc_out_utxo is {
      Some(utxo) ->
        when get_data(tx.datums, utxo.datum) is {
          Some(d) -> {
            expect sc_out_datum: BidLimit = d
            and {
              (sc_out_datum.quantity > 0)?,
              (sc_out_datum.quantity == sc_out_remain)?,
            }
          }
          _ -> {
            trace @"not found output bid datum"
            False
          }
        }
      _ -> (sc_out_remain == 0)?
    },
  }
}

pub fn matching(
  tx: Transaction,
  cfg: BondConfigLimit,
  sbid_dt: BidLimit,
  owner: Address,
  spending: Address,
) -> Bool {
  when
    tx_validity_valid(
      tx.validity_range,
      cfg.platform.slot.slot_length,
      Some(60 * 60),
      True,
    )
  is {
    OK(tx_time_valid) -> and {
        (sbid_dt.quantity > 0)?,
        (sbid_dt.to_epoch >= sbid_dt.from_epoch)?,
        (tx_time_valid > 0)?,
        not(bytearray.is_empty(sbid_dt.owner_vk))?,
        when get_escrow_ref(cfg.escrow, tx.reference_inputs) is {
          Some(ref_in_escrow) ->
            when get_data(tx.datums, ref_in_escrow.output.datum) is {
              Some(d) -> {
                expect escrow_datum: EscrowDatum = d
                let epo_curr: EpochTime =
                  posix_time_to_relative_epoch(
                    tx_time_valid,
                    cfg.platform.epoch,
                  )
                let epo_start: EpochTime =
                  escrow_datum.start + cfg.platform.epoch.epoch_boundary_as_epoch
                let epo_end: EpochTime = epo_start + escrow_datum.duration
                and {
                  (epo_end >= epo_curr)?,
                  (epo_end >= sbid_dt.from_epoch)?,
                  (epo_end <= sbid_dt.to_epoch)?,
                  (escrow_datum.bond_amount > 0)?,
                  (value.lovelace_of(escrow_datum.epo_rewards) > 0)?,
                  (value.lovelace_of(ref_in_escrow.output.value) > escrow_datum.bond_amount * cfg.platform.bond_face_value)?,
                  when
                    get_escrow_info_1(
                      cfg.platform,
                      value.lovelace_of(ref_in_escrow.output.value),
                      escrow_datum,
                      tx_time_valid,
                      epo_curr,
                      epo_start,
                      epo_end,
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
                          None -> {
                            trace @"out is None"
                            False
                          }
                          Some(ou) -> {
                            let owner_in_utxos_len =
                              list.length(
                                list.concat(
                                  in.owner.bond_outputs,
                                  in.owner.other_outputs,
                                ),
                              )
                            let sc_out_utxos =
                              list.concat(
                                ou.sc.bond_outputs,
                                ou.sc.other_outputs,
                              )
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
                              (ou.owner.bond_qty <= escrow_datum.bond_amount)?,
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
                    Error(_) -> {
                      trace @"bond is closable"
                      False
                    }
                  },
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
        },
      }
    Error(e) -> fail e
  }
}

pub fn spending(
  cfg: BondConfigLimit,
  ctx: ScriptContext,
  sbid_dt: UniqBidLimitMulti,
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
          list_escrow_ref(
            cfg.platform,
            cfg.escrow,
            tx.reference_inputs,
            tx.datums,
            sbid_dt.bond_types,
            tx_time_valid,
            epo_curr,
          )
        is {
          OK(_escrow_refs) -> {
            // let bond_units = dict.keys(escrow_refs)
            // trace cbor.diagnostic(bond_units)
            let owner_addr = sbid_dt.receive_addr
            // trace cbor.diagnostic(owner_addr)
            expect Spend(sbid_out_ref) = ctx.purpose
            expect Some(sbid) =
              list.find(tx.inputs, fn(i) { i.output_reference == sbid_out_ref })
            let sbid_addr = sbid.output.address
            // bid_inputs: Dict<ByteArray , (Output, UniqBidLimitMulti)>
            let (bid_inputs, _) =
              list.foldl(
                tx.inputs,
                (dict.new(), 0),
                fn(i, z) {
                  // if and {
                  //   i.output.address.payment_credential == sbid_addr.payment_credential,
                  //   i.output_reference != sbid_out_ref,
                  // } {
                  let is_ibid_order =
                    i.output.address.payment_credential == sbid_addr.payment_credential
                  if is_ibid_order {
                    expect ibid_dt: UniqBidLimitMulti =
                      when i.output.datum is {
                        InlineDatum(d) -> d
                        _ -> fail @"only supports InlineDatum for bid order"
                      }
                    // let order_id_correct =
                    //   hash_out_ref_salt(
                    //     ibid_dt.input_ref,
                    //     convert.int_to_digit(z.2nd),
                    //   )
                    // if (ibid_dt.order_id == order_id_correct)? {
                    //   if dict.has_key(z.1st, ibid_dt.uniq_id) {
                    //     fail bconcat_3(
                    //       @"spending uniq_id ",
                    //       bytearray.to_hex(ibid_dt.uniq_id),
                    //       @" is duplicate",
                    //     )
                    //   } else {
                    //     (
                    //       dict.insert(
                    //         z.1st,
                    //         ibid_dt.uniq_id,
                    //         (i.output, ibid_dt),
                    //         bytearray.compare,
                    //       ),
                    //       z.2nd + 1,
                    //     )
                    //   }
                    // } else {
                    //   fail bconcat_3(
                    //     bconcat_3(
                    //       @"spending order_id invalid (expected: ",
                    //       bytearray.to_hex(order_id_correct),
                    //       @", actual: ",
                    //     ),
                    //     bytearray.to_hex(ibid_dt.order_id),
                    //     @")",
                    //   )
                    // }
                    if dict.has_key(z.1st, ibid_dt.uniq_id) {
                      fail bconcat_3(
                        @"spending uniq_id ",
                        bytearray.to_hex(ibid_dt.uniq_id),
                        @" is duplicate",
                      )
                    } else {
                      (
                        dict.insert(
                          z.1st,
                          ibid_dt.uniq_id,
                          (i.output, ibid_dt),
                          bytearray.compare,
                        ),
                        z.2nd + 1,
                      )
                    }
                  } else {
                    (z.1st, z.2nd + 1)
                  }
                },
              )
            // (sbid_out: Option<Output>, bid_outs: List<Output>, owner_outs: List<Output>, fee_out: Option<Output>)
            let (_sbid_out, _bid_outs, owner_outs, fee_out, _) =
              list.foldl(
                tx.outputs,
                (None, dict.new(), [], None, 0),
                fn(o, z) {
                  let out_addr = o.address
                  let is_obid_order =
                    out_addr.payment_credential == sbid_addr.payment_credential
                  if is_obid_order {
                    expect obid_dt: UniqBidLimitMulti =
                      when o.datum is {
                        InlineDatum(d) -> d
                        _ -> fail @"only supports InlineDatum for bid order"
                      }
                    if out_addr.stake_credential == sbid_addr.stake_credential {
                      if (z.1st == None)? {
                        (Some(o), z.2nd, z.3rd, z.4th, z.5th + 1)
                      } else {
                        fail @"must only one spending bid output allowed"
                      }
                    } else {
                      let order_id_correct =
                        hash_out_ref_salt(
                          obid_dt.input_ref,
                          convert.int_to_digit(z.5th),
                        )
                      if (obid_dt.order_id == order_id_correct)? {
                        if dict.has_key(z.2nd, obid_dt.uniq_id) {
                          fail bconcat_3(
                            @"spending uniq_id ",
                            bytearray.to_hex(obid_dt.uniq_id),
                            @" is duplicate",
                          )
                        } else {
                          (
                            z.1st,
                            dict.insert(
                              z.2nd,
                              obid_dt.uniq_id,
                              (o, obid_dt),
                              bytearray.compare,
                            ),
                            z.3rd,
                            z.4th,
                            z.5th + 1,
                          )
                        }
                      } else {
                        fail bconcat_3(
                          bconcat_3(
                            @"spending order_id invalid (expected: ",
                            bytearray.to_hex(order_id_correct),
                            @", actual: ",
                          ),
                          bytearray.to_hex(obid_dt.order_id),
                          @")",
                        )
                      }
                    }
                  } else if out_addr == owner_addr {
                    (z.1st, z.2nd, [o, ..z.3rd], z.4th, z.5th + 1)
                  } else if out_addr == cfg.exchange.address {
                    if (z.4th == None)? {
                      (z.1st, z.2nd, z.3rd, Some(o), z.5th + 1)
                    } else {
                      fail @"must only one fee output for bid allowed"
                    }
                  } else {
                    z
                  }
                },
              )
            and {
              !dict.is_empty(bid_inputs)?,
              (owner_outs != [])?,
              (fee_out != None)?,
            }
          }
          Error(s) -> fail s
        },
      }
    }
    Error(e) -> fail e
  }
}
