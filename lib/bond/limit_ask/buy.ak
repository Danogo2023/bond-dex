// Ask Limit
use aiken/bytearray
use aiken/dict
use aiken/list
use aiken/transaction.{InlineDatum, ScriptContext, Spend, Transaction}
use aiken/transaction/credential.{Address, VerificationKeyCredential}
use aiken/transaction/value.{Value}
use bond/common/constraint.{ask_limit_valid, yield_valid}
use bond/common/types.{AskLimit, BondConfigLimit, EscrowInfo}
use bond/common/utils.{
  get_price_of_bond, has_safe_datum, head_escrow_ref, is_deprecated_sm_input,
} as bond_utils
use common/string.{bconcat_3} as common_string
use common/time.{EpochTime, posix_time_to_relative_epoch, tx_validity_valid}
use common/types.{Error, Lovelace, OK, ScriptKeyHash} as common_types

pub type BizInput {
  sc_value: Lovelace,
  sc_bond_qty: Int,
  sc_tokens: Value,
}

pub type BizOutput {
  sc_value: Lovelace,
  sc_bond_qty: Int,
  sc_tokens: Value,
  seller_value: Lovelace,
  seller_bond_qty: Int,
  fee_value: Lovelace,
}

pub fn spending(
  ctx: ScriptContext,
  cfg: BondConfigLimit,
  sask_dt: AskLimit,
  script_blacklist: List<ScriptKeyHash>,
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
                  let seller_addr =
                    Address {
                      payment_credential: VerificationKeyCredential(
                        sask_dt.owner_vk,
                      ),
                      stake_credential: sask_addr.stake_credential,
                    }
                  let fee_addr: Address = cfg.exchange.fee_addr
                  let biz_input =
                    list.foldr(
                      tx.inputs,
                      BizInput {
                        sc_value: 0,
                        sc_bond_qty: 0,
                        sc_tokens: value.zero(),
                      },
                      fn(i, z) {
                        let ivalue = value.lovelace_of(i.output.value)
                        let ibond_qty =
                          value.quantity_of(
                            i.output.value,
                            escrow_info.bond_symbol,
                            escrow_info.token_name,
                          )
                        if
                        i.output.address.payment_credential == sask_addr.payment_credential{
                        
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
                                  sc_tokens: value.without_lovelace(
                                    i.output.value,
                                  ),
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
                          when is_deprecated_sm_input(i, script_blacklist) is {
                            True -> fail @"do not allow spend deprecated ask"
                            False -> z
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
                        sc_tokens: value.zero(),
                        seller_value: 0,
                        seller_bond_qty: 0,
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
                        if
                        o.address.payment_credential == sask_addr.payment_credential{
                        
                          if and {
                            (z.sc_bond_qty == 0)?,
                            (o.address.stake_credential == sask_addr.stake_credential)?,
                          } {
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
                                BizOutput {
                                  ..z,
                                  sc_value: ovalue,
                                  sc_bond_qty: obond_qty,
                                  sc_tokens: value.without_lovelace(o.value),
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
                          expect has_safe_datum(o)
                          if (z.seller_value == 0)? {
                            BizOutput {
                              ..z,
                              seller_value: ovalue,
                              seller_bond_qty: obond_qty,
                            }
                          } else {
                            fail @"must only one owner output for ask order allowed"
                          }
                        } else if oaddr == fee_addr {
                          expect has_safe_datum(o)
                          BizOutput { ..z, fee_value: z.fee_value + ovalue }
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
                    (biz_output.seller_bond_qty == 0)?,
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
                    (biz_input.sc_tokens == value.add(
                      biz_output.sc_tokens,
                      escrow_info.bond_symbol,
                      escrow_info.token_name,
                      biz_input.sc_bond_qty - biz_output.sc_bond_qty,
                    ))?,
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
  biz_input: BizInput,
  biz_output: BizOutput,
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
    if seller_addr == cfg.exchange.fee_addr {
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
