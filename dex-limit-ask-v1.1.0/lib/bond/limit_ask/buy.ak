// Ask Limit
use aiken/bytearray
use aiken/dict
use aiken/list
use aiken/option
use aiken/transaction.{InlineDatum, Output, ScriptContext, Spend, Transaction}
use aiken/transaction/credential.{Address}
use aiken/transaction/value
use bond/constraint.{ask_limit_valid, yield_valid}
use bond/limit_ask/utils.{collect_biz_tx_info, head_escrow_ref}
use bond/types.{
  AskLimit, BizOutput, BizTxInfo, BondConfigLimit, DanogoBond, EscrowDatum,
  EscrowInfo,
}
use bond/utils.{get_escrow_info_1,
  get_escrow_ref, get_price_of_bond} as bond_utils
use common/string.{bconcat_3} as common_string
use common/time.{EpochTime, posix_time_to_relative_epoch, tx_validity_valid}
use common/types.{Error, Lovelace, OK} as common_types
use common/util.{get_data} as common_utils

fn matching_is_valid(
  cfg: BondConfigLimit,
  in: BizOutput,
  out: BizOutput,
  escrow_info: EscrowInfo,
  buyer_qty: Int,
  price_of_one_bond: Int,
  min_ada_to_exchange: Int,
) -> Bool {
  // Tong tien lender nhan duoc cuoi chu ky dao han bao gom ca goc va lai tuong ung vs so bond ma buyer mua
  let received_at_maturity = escrow_info.value_at_maturity * buyer_qty
  // Tong tien buyer phai tra/seller(owner of listing) nhan duoc chua tru phi
  let received_with_yield = price_of_one_bond * buyer_qty
  // Chenh lech tien lai nhan duoc
  let received_diff = received_at_maturity - received_with_yield
  // phi seller(owner of listing) phai tra cho san theo ti le trong config
  let exchange_fee_seller =
    received_diff * cfg.exchange.seller_fee / cfg.platform.basis.base
  // phi buyer phai tra cho san theo ti le trong config
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.platform.basis.base
  let owner_out_utxos =
    list.concat(out.owner.bond_outputs, out.owner.other_outputs)
  let owner_output_len = list.length(owner_out_utxos)
  let sc_output_len =
    list.length(list.concat(out.sc.bond_outputs, out.sc.other_outputs))
  let exchange_receive_lovelace_tmp =
    exchange_fee_buyer + exchange_fee_seller + min_ada_to_exchange
  let owner_receive_lovelace_tmp = received_with_yield - exchange_fee_seller
  let (owner_receive_lovelace, exchange_receive_lovelace) =
    when list.at(out.owner.addresses, 0) is {
      Some(a) ->
        if owner_output_len > 0 && a == cfg.exchange.address {
          (owner_receive_lovelace_tmp + exchange_receive_lovelace_tmp, 0)
        } else {
          (owner_receive_lovelace_tmp, exchange_receive_lovelace_tmp)
        }
      _ -> (owner_receive_lovelace_tmp, exchange_receive_lovelace_tmp)
    }
  and {
    (sc_output_len <= 1)?,
    (owner_output_len <= 1)?,
    (buyer_qty >= 0)?,
    (out.sc.bond_qty >= in.sc.bond_qty - buyer_qty)?,
    (out.exchange.lovelace >= exchange_receive_lovelace)?,
    (owner_output_len > 0)?,
    (out.owner.lovelace == owner_receive_lovelace)?,
  }
}

fn matching_correct(
  cfg: BondConfigLimit,
  sask_dt: AskLimit,
  in: BizOutput,
  out: BizOutput,
  escrow_info: EscrowInfo,
) -> Bool {
  let (
    qty_owner_2_buyer,
    min_ada_to_sm,
    min_ada_to_exchange,
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
  and {
    sm_out_must_only_one_bond_name?,
    sm_out_bond_same_escrow?,
    (qty_owner_2_buyer <= escrow_info.bond_amount)?,
    or {
      qty_owner_2_buyer == 0,
      dict.has_key(out.other.bond_assets, escrow_info.token_name),
      dict.has_key(out.exchange.bond_assets, escrow_info.token_name),
    }?,
    when
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
      _ -> and {
          min_ada_to_sm == 0 || (out.sc.lovelace >= min_ada_to_sm)? && out.sc.bond_datum_valid?,
          matching_is_valid(
            cfg,
            in,
            out,
            escrow_info,
            qty_owner_2_buyer,
            get_price_of_bond(
              escrow_info.value_at_maturity,
              escrow_info.day_to_maturity,
              sask_dt.requested_yield,
              cfg.platform.basis.base,
            ),
            min_ada_to_exchange,
          )?,
        }
    },
  }
}

pub fn matching(
  tx: Transaction,
  cfg: BondConfigLimit,
  sask_dt: AskLimit,
  owner: Address,
  spending: Address,
) -> Bool {
  when
    tx_validity_valid(
      tx.validity_range,
      cfg.platform.slot.slot_length,
      cfg.exchange.tx_buy_ttl,
      True,
    )
  is {
    OK(tx_time_valid) -> and {
        not(bytearray.is_empty(sask_dt.owner_vk))?,
        when get_escrow_ref(cfg.escrow, tx.reference_inputs) is {
          Some(ref_in_escrow) ->
            when get_data(tx.datums, ref_in_escrow.output.datum) is {
              Some(d) -> {
                expect escrow_datum: EscrowDatum = d
                let epo_start: EpochTime =
                  escrow_datum.start + cfg.platform.epoch.epoch_boundary_as_epoch
                let epo_end: EpochTime = epo_start + escrow_datum.duration
                and {
                  (escrow_datum.bond_amount > 0)?,
                  (value.lovelace_of(escrow_datum.epo_rewards) > 0)?,
                  (value.lovelace_of(ref_in_escrow.output.value) > escrow_datum.bond_amount * cfg.platform.bond_face_value)?,
                  when
                    get_escrow_info_1(
                      cfg.platform,
                      value.lovelace_of(ref_in_escrow.output.value),
                      escrow_datum,
                      tx_time_valid,
                      posix_time_to_relative_epoch(
                        tx_time_valid,
                        cfg.platform.epoch,
                      ),
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
                          sask_dt,
                        )
                      and {
                        biz_tx_info_valid,
                        (dict.size(in.sc.bond_assets) == 1)?,
                        dict.has_key(in.sc.bond_assets, escrow_info.token_name)?,
                        when out is {
                          Some(ou) -> and {
                              (in.owner.bond_qty <= 0)?,
                              matching_correct(
                                cfg,
                                sask_dt,
                                in,
                                ou,
                                escrow_info,
                              ),
                            }
                          None -> {
                            trace @"out is None"
                            False
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

pub type AskInput {
  sc_value: Lovelace,
  sc_bond_qty: Int,
}

pub type AskOutput {
  sc_value: Lovelace,
  sc_bond_qty: Int,
  seller_value: Lovelace,
  fee_value: Lovelace,
}

pub fn spending(
  ctx: ScriptContext,
  cfg: BondConfigLimit,
  sask_dt: AskLimit,
) -> Bool {
  let tx = ctx.transaction
  when
    tx_validity_valid(
      tx.validity_range,
      cfg.platform.slot.slot_length,
      cfg.exchange.tx_buy_ttl,
      True,
    )
  is {
    OK(tx_time_valid) -> {
      let epo_curr: EpochTime =
        posix_time_to_relative_epoch(tx_time_valid, cfg.platform.epoch)
      let bond_types =
        [DanogoBond]
      and {
        not(bytearray.is_empty(sask_dt.owner_vk))?,
        when
          head_escrow_ref(
            cfg.platform,
            cfg.escrow,
            tx.reference_inputs,
            tx.datums,
            bond_types,
            tx_time_valid,
            epo_curr,
          )
        is {
          OK(escrow_ref) ->
            when escrow_ref |> dict.to_list is {
              [(bond_unit, escrow_info)] ->
                if (escrow_info.end_epoch >= epo_curr)? {
                  expect Spend(sask_out_ref) = ctx.purpose
                  expect Some(sask) =
                    list.find(
                      tx.inputs,
                      fn(i) { i.output_reference == sask_out_ref },
                    )
                  let sask_addr: Address = sask.output.address
                  let seller_addr: Address =
                    sask_dt.owner_sk
                      |> option.and_then(
                           fn(s) {
                             Some(
                               credential.from_verification_key(
                                 sask_dt.owner_vk,
                               )
                                 |> credential.with_delegation_key(s),
                             )
                           },
                         )
                      |> option.or_else(
                           credential.from_verification_key(sask_dt.owner_vk),
                         )
                  let fee_addr: Address = cfg.exchange.address
                  let biz_input =
                    list.foldl(
                      tx.inputs,
                      AskInput { sc_value: 0, sc_bond_qty: 0 },
                      fn(i, z) {
                        let ivalue = value.lovelace_of(i.output.value)
                        let ibond_qty =
                          value.quantity_of(
                            i.output.value,
                            escrow_info.bond_symbol,
                            escrow_info.token_name,
                          )
                        let iaddr = i.output.address
                        let is_iask_order =
                          iaddr.payment_credential == sask_addr.payment_credential
                        if is_iask_order {
                          if z.sc_bond_qty == 0 {
                            let sc_bond_names =
                              dict.keys(
                                value.tokens(
                                  i.output.value,
                                  escrow_info.bond_symbol,
                                ),
                              )
                            if list.at(sc_bond_names, 1) == None {
                              if (ibond_qty > 0)? {
                                AskInput {
                                  sc_value: ivalue,
                                  sc_bond_qty: ibond_qty,
                                }
                              } else {
                                fail @"not found bond matching in ask order"
                              }
                            } else {
                              fail @"ask input must only one bond name allowed"
                            }
                          } else {
                            fail @"matching only one ask order allowed"
                          }
                        } else {
                          z
                        }
                      },
                    )
                  let biz_output =
                    list.foldl(
                      tx.outputs,
                      AskOutput {
                        sc_value: 0,
                        sc_bond_qty: 0,
                        seller_value: 0,
                        fee_value: 0,
                      },
                      fn(o, z) {
                        let ovalue = value.lovelace_of(o.value)
                        let obond_qty =
                          value.quantity_of(
                            o.value,
                            escrow_info.bond_symbol,
                            escrow_info.token_name,
                          )
                        let oaddr = o.address
                        let is_oask_order =
                          oaddr.payment_credential == sask_addr.payment_credential
                        if is_oask_order {
                          if (z.sc_bond_qty == 0)? {
                            let sc_bond_names =
                              dict.keys(
                                value.tokens(o.value, escrow_info.bond_symbol),
                              )
                            if list.at(sc_bond_names, 1) == None {
                              expect oask_dt: AskLimit =
                                when o.datum is {
                                  InlineDatum(d) -> d
                                  _ ->
                                    fail @"only supports InlineDatum for ask order"
                                }
                              if and {
                                yield_valid(
                                  cfg.platform.basis,
                                  oask_dt.requested_yield,
                                )?,
                                ask_limit_valid(oask_dt, sask_dt),
                              } {
                                AskOutput {
                                  ..z,
                                  sc_value: ovalue,
                                  sc_bond_qty: obond_qty,
                                }
                              } else {
                                fail @"ask order output invalid datum"
                              }
                            } else {
                              fail @"ask output must only one bond name allowed"
                            }
                          } else {
                            fail @"must only one ask order output allowed"
                          }
                        } else if oaddr == seller_addr {
                          if (z.seller_value == 0)? {
                            AskOutput { ..z, seller_value: ovalue }
                          } else {
                            fail @"must only one owner output for ask order allowed"
                          }
                        } else if oaddr == fee_addr {
                          // if (z.fee_value == 0)? {
                          // } else {
                          //   fail @"must only one fee output for ask order allowed"
                          // }
                          AskOutput { ..z, fee_value: z.fee_value + ovalue }
                        } else {
                          z
                        }
                      },
                    )
                  // SC chuyển bond ==> seller nhận tiền
                  // buyer chuyển tiền nhận bond
                  // buy all ==> biz_output.sc_bond_qty == 0
                  // buy partial ==> biz_output.sc_bond_qty > 0
                  and {
                    (biz_input.sc_bond_qty > 0)?,
                    (biz_output.sc_bond_qty >= 0)?,
                    (biz_output.sc_bond_qty < biz_input.sc_bond_qty)?,
                    (biz_output.seller_value > 0)?,
                    spending_correct(
                      cfg,
                      escrow_info,
                      sask_dt,
                      biz_input,
                      biz_output,
                      seller_addr,
                    ),
                  }
                } else {
                  fail bconcat_3(
                    @"escrow of bond ",
                    bond_unit,
                    @" invalid epoch",
                  )
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

fn spending_correct(
  cfg: BondConfigLimit,
  escrow_info: EscrowInfo,
  sask_dt: AskLimit,
  biz_input: AskInput,
  biz_output: AskOutput,
  seller_addr: Address,
) -> Bool {
  let matching_bond_qty: Int = biz_input.sc_bond_qty - biz_output.sc_bond_qty
  let (min_ada_to_sm, min_ada_to_exchange) =
    if matching_bond_qty == biz_input.sc_bond_qty {
      // buy all
      (0, biz_input.sc_value)
    } else {
      // buy partial
      (biz_input.sc_value, 0)
    }
  // Tong tien lender nhan duoc cuoi chu ky dao han bao gom ca goc va lai tuong ung vs so bond ma buyer mua
  let received_at_maturity: Lovelace =
    escrow_info.value_at_maturity * matching_bond_qty
  // Tong tien buyer phai tra/seller(owner of listing) nhan duoc chua tru phi
  let received_with_yield: Lovelace =
    get_price_of_bond(
      escrow_info.value_at_maturity,
      escrow_info.day_to_maturity,
      sask_dt.requested_yield,
      cfg.platform.basis.base,
    ) * matching_bond_qty
  // Chenh lech tien lai nhan duoc
  let received_diff: Lovelace = received_at_maturity - received_with_yield
  // phi seller(owner of listing) phai tra cho san theo ti le trong config
  let exchange_fee_seller: Lovelace =
    received_diff * cfg.exchange.seller_fee / cfg.platform.basis.base
  // phi buyer phai tra cho san theo ti le trong config
  let exchange_fee_buyer: Lovelace =
    received_diff * cfg.exchange.buyer_fee / cfg.platform.basis.base
  //
  let exchange_receive_lovelace_tmp: Lovelace =
    exchange_fee_buyer + exchange_fee_seller + min_ada_to_exchange
  //
  let seller_receive_lovelace_tmp: Lovelace =
    received_with_yield - exchange_fee_seller
  //
  // SC chuyển bond ==> seller nhận tiền
  // buyer chuyển tiền nhận bond
  let (seller_receive_lovelace, exchange_receive_lovelace) =
    if seller_addr == cfg.exchange.address {
      (seller_receive_lovelace_tmp + exchange_receive_lovelace_tmp, 0)
    } else {
      (seller_receive_lovelace_tmp, exchange_receive_lovelace_tmp)
    }
  and {
    (matching_bond_qty > 0)?,
    (biz_output.sc_bond_qty >= biz_input.sc_bond_qty - matching_bond_qty)?,
    (biz_output.fee_value >= exchange_receive_lovelace)?,
    (biz_output.seller_value == seller_receive_lovelace)?,
    or {
      min_ada_to_sm == 0,
      (biz_output.sc_value >= min_ada_to_sm)?,
    },
  }
}
