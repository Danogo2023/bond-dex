// Bid Making
use aiken/bytearray
use aiken/dict
use aiken/list
use aiken/option
use aiken/transaction.{InlineDatum, Output, ScriptContext, Spend, Transaction}
use aiken/transaction/credential.{Address, PaymentCredential}
use aiken/transaction/value
use bond/constraint.{
  ask_making_valid, bid_making_valid, epoch_valid, yield_valid,
}
use bond/making_bid/utils.{head_escrow_ref}
use bond/types.{AskMaking, BidMaking, BondConfigMaking, EscrowInfo}
use bond/utils.{get_price_of_bond} as bond_utils
use common/string.{bconcat_3} as common_string
use common/time.{EpochTime, posix_time_to_relative_epoch, tx_validity_valid}
use common/types.{Error, Lovelace, OK} as common_types
use common/util.{get_payment_key} as common_utils

pub type BizInput {
  sc_value: Lovelace,
  seller_value: Int,
  seller_bond_qty: Int,
  seller_addr: List<Address>,
  seller_pk: List<PaymentCredential>,
}

pub type BizOutput {
  sc_value: Lovelace,
  sc_bond_qty: Int,
  buyer_value: Lovelace,
  buyer_bond_qty: Int,
  fee_value: Lovelace,
  seller_value: Lovelace,
  seller_pk: List<PaymentCredential>,
}

pub fn spending(
  ctx: ScriptContext,
  cfg: BondConfigMaking,
  sbid_dt: BidMaking,
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
            tx_time_valid,
            epo_curr,
          )
        is {
          OK(escrow_ref) ->
            when escrow_ref |> dict.to_list is {
              [(bond_unit, escrow_info)] ->
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
                  let sbid_pk: ByteArray = get_payment_key(sbid_addr)
                  let owner_addr: Address =
                    credential.from_verification_key(sbid_dt.owner_vk)
                  let buyer_addr: Address =
                    sbid_dt.owner_sk
                      |> option.and_then(
                          fn(s) {
                            Some(
                              credential.from_script(sbid_dt.ask_sc)
                                |> credential.with_delegation_key(s),
                            )
                          },
                        )
                      |> option.or_else(credential.from_script(sbid_dt.ask_sc))
                  let fee_addr: Address = cfg.exchange.fee_addr
                  let biz_input =
                    list.foldr(
                      tx.inputs,
                      BizInput {
                        sc_value: 0,
                        seller_value: 0,
                        seller_bond_qty: 0,
                        seller_addr: [],
                        seller_pk: [],
                      },
                      fn(i, z) {
                        let ivalue = value.lovelace_of(i.output.value)
                        let iaddr = i.output.address
                        if
                        iaddr.payment_credential == sbid_addr.payment_credential{
                        
                          if z.sc_value == 0 {
                            BizInput { ..z, sc_value: ivalue }
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
                          if or {
                            iaddr == buyer_addr,
                            iaddr == fee_addr,
                          } {
                            z
                          } else {
                            BizInput {
                              ..z,
                              seller_value: z.seller_value + ivalue,
                              seller_bond_qty: z.seller_bond_qty + ibond_qty,
                              seller_addr: [iaddr, ..z.seller_addr],
                              seller_pk: [
                                iaddr.payment_credential,
                                ..z.seller_pk
                              ],
                            }
                          }
                        }
                      },
                    )
                  let biz_output =
                    list.foldr(
                      tx.outputs,
                      BizOutput {
                        sc_value: 0,
                        sc_bond_qty: 0,
                        buyer_value: 0,
                        buyer_bond_qty: 0,
                        fee_value: 0,
                        seller_value: 0,
                        seller_pk: [],
                      },
                      fn(o, z) {
                        let ovalue = value.lovelace_of(o.value)
                        let oaddr = o.address
                        if
                        oaddr.payment_credential == sbid_addr.payment_credential{
                        
                          if and {
                            (z.sc_value == 0)?,
                            (oaddr.stake_credential == sbid_addr.stake_credential)?,
                          } {
                            expect obid_dt: BidMaking =
                              when o.datum is {
                                InlineDatum(d) -> d
                                _ ->
                                  fail @"only supports InlineDatum for bid order"
                              }
                            if and {
                              yield_valid(
                                cfg.platform.basis,
                                obid_dt.requested_yield + obid_dt.margin,
                              )?,
                              epoch_valid(
                                obid_dt.from_epoch,
                                obid_dt.to_epoch,
                                obid_dt.quantity,
                              )?,
                              bid_making_valid(obid_dt, sbid_dt)?,
                              (obid_dt.quantity > 0)?,
                              (obid_dt.quantity < sbid_dt.quantity)?,
                            } {
                              BizOutput {
                                ..z,
                                sc_value: ovalue,
                                sc_bond_qty: obid_dt.quantity,
                              }
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
                            if (z.buyer_value == 0)? {
                              if and {
                                (obond_qty > 0)?,
                                (obond_qty <= sbid_dt.quantity)?,
                                (obond_qty <= escrow_info.bond_amount)?,
                              } {
                                expect oask_dt: AskMaking =
                                  when o.datum is {
                                    InlineDatum(d) -> d
                                    _ ->
                                      fail @"only supports InlineDatum for ask order"
                                  }
                                let sask_dt: AskMaking =
                                  AskMaking {
                                    owner_vk: sbid_dt.owner_vk,
                                    owner_sk: sbid_dt.owner_sk,
                                    requested_yield: sbid_dt.requested_yield - sbid_dt.margin,
                                    bid_sc: sbid_pk,
                                    margin: sbid_dt.margin,
                                  }
                                if and {
                                  yield_valid(
                                    cfg.platform.basis,
                                    oask_dt.requested_yield + oask_dt.margin,
                                  ),
                                  ask_making_valid(oask_dt, sask_dt),
                                } {
                                  BizOutput {
                                    ..z,
                                    buyer_value: ovalue,
                                    buyer_bond_qty: obond_qty,
                                  }
                                } else {
                                  fail @"ask order output invalid datum"
                                }
                              } else {
                                fail @"buyer bond qty output invalid"
                              }
                            } else {
                              fail @"must only one owner output for bid order allowed"
                            }
                          } else if oaddr == fee_addr {
                            if (z.fee_value == 0)? {
                              BizOutput { ..z, fee_value: ovalue }
                            } else {
                              fail @"must only one fee output for bid order allowed"
                            }
                          } else {
                            BizOutput {
                              ..z,
                              seller_value: z.seller_value + ovalue,
                              seller_pk: [
                                o.address.payment_credential,
                                ..z.seller_pk
                              ],
                            }
                          }
                        }
                      },
                    )
                  // SC chuyển tiền ==> buyer nhận bond
                  // seller chuyển bond nhận tiền
                  let seller_is_not_owner = and {
                      !list.has(
                        biz_input.seller_pk,
                        owner_addr.payment_credential,
                      ),
                      !list.has(
                        biz_output.seller_pk,
                        owner_addr.payment_credential,
                      ),
                    }
                  and {
                    seller_is_not_owner?,
                    (biz_output.buyer_bond_qty > 0)?,
                    spending_correct(
                      tx,
                      cfg,
                      escrow_info,
                      sbid_dt,
                      biz_input,
                      biz_output,
                      buyer_addr,
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
  tx: Transaction,
  cfg: BondConfigMaking,
  escrow_info: EscrowInfo,
  sbid_dt: BidMaking,
  biz_input: BizInput,
  biz_output: BizOutput,
  buyer_addr: Address,
) -> Bool {
  // Tong tien lender nhan duoc cuoi chu ky dao han bao gom ca goc va lai tuong ung vs so bond ma buyer mua
  let received_at_maturity: Lovelace =
    escrow_info.value_at_maturity * biz_output.buyer_bond_qty
  // Tong tien buyer(owner of bid) phai tra/seller nhan duoc chua tru phi
  let received_with_yield: Lovelace =
    get_price_of_bond(
      escrow_info.value_at_maturity,
      escrow_info.day_to_maturity,
      sbid_dt.requested_yield,
      cfg.platform.basis.base,
    ) * biz_output.buyer_bond_qty
  // Chenh lech tien lai nhan duoc
  let received_diff: Lovelace = received_at_maturity - received_with_yield
  // phi seller phai tra cho san theo ti le trong config
  let exchange_fee_seller: Lovelace =
    received_diff * cfg.exchange.taker_fee / cfg.platform.basis.base
  // phi buyer(owner of bid) phai tra cho san theo ti le trong config
  let exchange_fee_buyer: Lovelace =
    received_diff * cfg.exchange.maker_fee / cfg.platform.basis.base
  //
  let exchange_fee: Lovelace = exchange_fee_buyer + exchange_fee_seller
  //
  let oseller_max_recevie: Lovelace = received_with_yield - exchange_fee_seller
  //
  let sc_bond_qty_remain: Int = sbid_dt.quantity - biz_output.buyer_bond_qty
  // buyer is exchange addr
  let exchange_fee_for_buyer: Lovelace =
    if buyer_addr == cfg.exchange.fee_addr {
      exchange_fee
    } else {
      0
    }
  //
  // seller is exchange addr
  let exchange_fee_for_seller: Lovelace =
    if list.has(biz_input.seller_addr, cfg.exchange.fee_addr) {
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
  // SC chuyển tiền ==> buyer nhận bond
  // seller chuyển bond nhận tiền
  // sell partial ==> biz_output.sc_bond_qty == obid_dt.quantity == sbid_dt.quantity - biz_output.buyer_bond_qty
  // sell all ==> biz_output.sc_bond_qty == obid_dt.quantity == 0 and biz_output.sc_value == 0
  let seller_value_output =
    biz_input.seller_value + oseller_max_recevie + exchange_fee_for_seller - tx_fee
  let sc_value_output =
    biz_input.sc_value - exchange_fee_total - oseller_max_recevie - biz_output.buyer_value
  and {
    (biz_output.fee_value >= exchange_fee_total)?,
    (biz_output.buyer_bond_qty <= biz_input.seller_bond_qty)?,
    (biz_output.seller_value <= seller_value_output)?,
    (biz_output.sc_value == sc_value_output)?,
    (biz_output.sc_bond_qty == sc_bond_qty_remain)?,
  }
}
