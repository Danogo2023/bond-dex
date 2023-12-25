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
use bond/utils.{get_price_of_bond,
  head_escrow_ref, list_escrow_ref} as bond_utils
use common/string.{bconcat_3} as common_string
use common/time.{EpochTime, posix_time_to_relative_epoch, tx_validity_valid}
use common/types.{Error, OK} as common_types
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
  owner_addr: Address,
  sbid_addr: Address,
) -> Bool {
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
          OK(escrow_refs) ->
            when escrow_refs |> dict.to_list is {
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
                      owner_addr,
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
  cfg: BondConfigLimit,
  ctx: ScriptContext,
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
            let owner_addr =
              sbid_dt.owner_sk
                |> option.and_then(
                     fn(s) {
                       Some(
                         credential.from_verification_key(sbid_dt.owner_vk)
                           |> credential.with_delegation_key(s),
                       )
                     },
                   )
                |> option.or_else(
                     credential.from_verification_key(sbid_dt.owner_vk),
                   )
            // trace cbor.diagnostic(owner_addr)
            expect Spend(sbid_out_ref) = ctx.purpose
            expect Some(sbid) =
              list.find(tx.inputs, fn(i) { i.output_reference == sbid_out_ref })
            let sbid_addr = sbid.output.address
            // bid_inputs: List<Output>
            let bid_inputs: List<Output> =
              list.foldl(
                tx.inputs,
                [],
                fn(i, z) {
                  if and {
                    i.output.address.payment_credential == sbid_addr.payment_credential,
                    i.output_reference != sbid_out_ref,
                  } {
                    expect ibid_dt: BidLimitMulti =
                      when i.output.datum is {
                        InlineDatum(d) -> d
                        _ -> fail @"only supports InlineDatum for bid order"
                      }
                    [i.output, ..z]
                  } else {
                    z
                  }
                },
              )
            // (sbid_out: Option<Output>, bid_outs: List<Output>, owner_outs: List<Output>, fee_out: Option<Output>)
            let (_sbid_out, _bid_outs, owner_outs, fee_out) =
              list.foldl(
                tx.outputs,
                (None, [], [], None),
                fn(o, z) {
                  let out_addr = o.address
                  if
                  out_addr.payment_credential == sbid_addr.payment_credential{
                  
                    if out_addr.stake_credential == sbid_addr.stake_credential {
                      if (z.1st == None)? {
                        (Some(o), z.2nd, z.3rd, z.4th)
                      } else {
                        fail @"must only one spending bid output allowed"
                      }
                    } else {
                      (z.1st, [o, ..z.2nd], z.3rd, z.4th)
                    }
                  } else if out_addr == owner_addr {
                    (z.1st, z.2nd, [o, ..z.3rd], z.4th)
                  } else if out_addr == cfg.exchange.address {
                    if (z.4th == None)? {
                      (z.1st, z.2nd, z.3rd, Some(o))
                    } else {
                      fail @"must only one fee output for bid allowed"
                    }
                  } else {
                    z
                  }
                },
              )
            and {
              (bid_inputs == [])?,
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
