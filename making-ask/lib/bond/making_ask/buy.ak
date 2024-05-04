// Ask Making
use aiken/bytearray
use aiken/dict
use aiken/list
use aiken/option
use aiken/transaction.{InlineDatum, ScriptContext, Spend, Transaction}
use aiken/transaction/credential.{Address, PaymentCredential}
use aiken/transaction/value
use bond/constraint.{
  ask_making_valid, bid_making_valid, epoch_valid, yield_valid,
}
use bond/making_ask/utils.{head_escrow_ref}
use bond/types.{AskMaking, BidMaking, BondConfigMaking, EscrowInfo}
use bond/utils.{get_price_of_bond} as bond_utils
use common/string.{bconcat_3} as common_string
use common/time.{EpochTime, posix_time_to_relative_epoch, tx_validity_valid}
use common/types.{Error, Lovelace, OK} as common_types
use common/util.{get_payment_key} as common_utils

pub type BizInput {
  sc_value: Lovelace,
  sc_bond_qty: Int,
}

pub type BizOutput {
  sc_value: Lovelace,
  sc_bond_qty: Int,
  seller_value: Lovelace,
  seller_bond_qty: Int,
  fee_value: Lovelace,
  buyer_pk: List<PaymentCredential>,
}

pub fn spending(
  ctx: ScriptContext,
  cfg: BondConfigMaking,
  sask_dt: AskMaking,
) -> Bool {
  let tx: Transaction = ctx.transaction
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
      and {
        not(bytearray.is_empty(sask_dt.owner_vk))?,
        when
          head_escrow_ref(
            cfg.platform,
            cfg.escrow,
            tx.reference_inputs,
            tx.datums,
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
                  let sask_pk: ByteArray = get_payment_key(sask_addr)
                  let owner_addr: Address =
                    credential.from_verification_key(sask_dt.owner_vk)
                  let seller_addr: Address =
                    sask_dt.owner_sk
                      |> option.and_then(
                          fn(s) {
                            Some(
                              credential.from_script(sask_dt.bid_sc)
                                |> credential.with_delegation_key(s),
                            )
                          },
                        )
                      |> option.or_else(credential.from_script(sask_dt.bid_sc))
                  let fee_addr: Address = cfg.exchange.fee_addr
                  let biz_input =
                    list.foldr(
                      tx.inputs,
                      BizInput { sc_value: 0, sc_bond_qty: 0 },
                      fn(i, z) {
                        let ivalue = value.lovelace_of(i.output.value)
                        let ibond_qty =
                          value.quantity_of(
                            i.output.value,
                            escrow_info.bond_symbol,
                            escrow_info.token_name,
                          )
                        let iaddr = i.output.address
                        if
                        iaddr.payment_credential == sask_addr.payment_credential{
                        
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
                                BizInput {
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
                    list.foldr(
                      tx.outputs,
                      BizOutput {
                        sc_value: 0,
                        sc_bond_qty: 0,
                        seller_value: 0,
                        seller_bond_qty: 0,
                        fee_value: 0,
                        buyer_pk: [],
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
                        if
                        oaddr.payment_credential == sask_addr.payment_credential{
                        
                          if and {
                            (z.sc_bond_qty == 0)?,
                            (oaddr.stake_credential == sask_addr.stake_credential)?,
                          } {
                            let sc_bond_names =
                              dict.keys(
                                value.tokens(o.value, escrow_info.bond_symbol),
                              )
                            if list.at(sc_bond_names, 1) == None {
                              expect oask_dt: AskMaking =
                                when o.datum is {
                                  InlineDatum(d) -> d
                                  _ ->
                                    fail @"only supports InlineDatum for ask order"
                                }
                              if and {
                                yield_valid(
                                  cfg.platform.basis,
                                  oask_dt.requested_yield + sask_dt.margin,
                                )?,
                                ask_making_valid(oask_dt, sask_dt)?,
                              } {
                                BizOutput {
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
                            expect obid_dt: BidMaking =
                              when o.datum is {
                                InlineDatum(d) -> d
                                _ ->
                                  fail @"only supports InlineDatum for bid making order"
                              }
                            let sbid_dt: BidMaking =
                              BidMaking {
                                owner_vk: sask_dt.owner_vk,
                                owner_sk: sask_dt.owner_sk,
                                from_epoch: escrow_info.end_epoch,
                                to_epoch: escrow_info.end_epoch,
                                quantity: 0,
                                requested_yield: sask_dt.requested_yield + sask_dt.margin,
                                ask_sc: sask_pk,
                                margin: sask_dt.margin,
                              }
                            if and {
                              yield_valid(
                                cfg.platform.basis,
                                obid_dt.requested_yield + obid_dt.margin,
                              ),
                              epoch_valid(
                                obid_dt.from_epoch,
                                obid_dt.to_epoch,
                                obid_dt.quantity,
                              )?,
                              bid_making_valid(obid_dt, sbid_dt)?,
                            } {
                              BizOutput {
                                ..z,
                                seller_value: ovalue,
                                seller_bond_qty: obid_dt.quantity,
                              }
                            } else {
                              fail @"bid order output invalid datum"
                            }
                          } else {
                            fail @"must only one owner output for ask order allowed"
                          }
                        } else if oaddr == fee_addr {
                          // if (z.fee_value == 0)? {
                          // } else {
                          //   fail @"must only one fee output for ask order allowed"
                          // }
                          BizOutput { ..z, fee_value: z.fee_value + ovalue }
                        } else {
                          BizOutput {
                            ..z,
                            buyer_pk: [
                              o.address.payment_credential,
                              ..z.buyer_pk
                            ],
                          }
                        }
                      },
                    )
                  // SC chuyển bond ==> seller nhận tiền
                  // buyer chuyển tiền nhận bond
                  // buy all ==> biz_output.sc_bond_qty == 0
                  // buy partial ==> biz_output.sc_bond_qty > 0
                  let buyer_is_not_owner =
                    !list.has(
                      biz_output.buyer_pk,
                      owner_addr.payment_credential,
                    )
                  and {
                    buyer_is_not_owner?,
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
  cfg: BondConfigMaking,
  escrow_info: EscrowInfo,
  sask_dt: AskMaking,
  biz_input: BizInput,
  biz_output: BizOutput,
  seller_addr: Address,
) -> Bool {
  let matching_bond_qty: Int = biz_input.sc_bond_qty - biz_output.sc_bond_qty
  // let (min_ada_to_sm, min_ada_to_exchange) =
  //   if matching_bond_qty == biz_input.sc_bond_qty {
  //     // buy all
  //     (0, biz_input.sc_value)
  //   } else {
  //     // buy partial
  //     (biz_input.sc_value, 0)
  //   }
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
    received_diff * cfg.exchange.maker_fee / cfg.platform.basis.base
  // phi buyer phai tra cho san theo ti le trong config
  let exchange_fee_buyer: Lovelace =
    received_diff * cfg.exchange.taker_fee / cfg.platform.basis.base
  //
  let exchange_receive_lovelace_tmp: Lovelace =
    exchange_fee_buyer + exchange_fee_seller
  //
  let seller_receive_lovelace_tmp: Lovelace =
    received_with_yield - exchange_fee_seller
  //
  // SC chuyển bond ==> seller nhận tiền
  // buyer chuyển tiền nhận bond
  let (seller_receive_lovelace, exchange_receive_lovelace) =
    if seller_addr == cfg.exchange.fee_addr {
      (seller_receive_lovelace_tmp + exchange_receive_lovelace_tmp, 0)
    } else {
      (seller_receive_lovelace_tmp, exchange_receive_lovelace_tmp)
    }
  and {
    (matching_bond_qty > 0)?,
    (biz_output.sc_bond_qty >= biz_input.sc_bond_qty - matching_bond_qty)?,
    (biz_output.fee_value >= exchange_receive_lovelace)?,
    (biz_output.sc_value + biz_output.seller_value == biz_input.sc_value + seller_receive_lovelace)?,
    (biz_output.seller_bond_qty <= matching_bond_qty)?,
  }
}
