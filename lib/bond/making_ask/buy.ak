// Ask Making
use aiken/bytearray
use aiken/dict
use aiken/list
use aiken/transaction.{InlineDatum, ScriptContext, Spend, Transaction}
use aiken/transaction/credential.{
  Address, PaymentCredential, ScriptCredential, VerificationKeyCredential,
}
use aiken/transaction/value.{Value, ada_asset_name, ada_policy_id}
use bond/common/constraint.{
  ask_making_valid, bid_making_valid, epoch_valid, yield_valid,
}
use bond/common/types.{AskMaking, BidMaking, BondConfigMaking, EscrowInfo}
use bond/common/utils.{
  get_price_of_bond, has_safe_datum, head_escrow_ref, is_deprecated_sm_input,
} as bond_utils
use common/string.{bconcat_3} as common_string
use common/time.{EpochTime, posix_time_to_relative_epoch, tx_validity_valid}
use common/types.{Error, Lovelace, OK, ScriptKeyHash} as common_types
use common/util.{get_payment_key} as common_utils

pub type BizOutput {
  oask_value: Value,
  rbid_value: Value,
  rbid_qty: Int,
  fee_lovelace: Lovelace,
  buyer_payment_creds: List<PaymentCredential>,
}

pub fn spending(
  ctx: ScriptContext,
  cfg: BondConfigMaking,
  sask_dt: AskMaking,
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
                  let EscrowInfo { bond_symbol, token_name, .. } = escrow_info
                  let bond_quantity_of =
                    fn(v: Value) {
                      value.quantity_of(v, bond_symbol, token_name)
                    }

                  expect Spend(sask_out_ref) = ctx.purpose
                  expect Some(sask) =
                    list.find(
                      tx.inputs,
                      fn(i) { i.output_reference == sask_out_ref },
                    )
                  let sask_addr: Address = sask.output.address
                  let sask_pk: ByteArray = get_payment_key(sask_addr)
                  let rbid_addr =
                    Address {
                      payment_credential: ScriptCredential(sask_dt.bid_sc),
                      stake_credential: sask_addr.stake_credential,
                    }
                  let fee_addr: Address = cfg.exchange.fee_addr
                  let sask_value =
                    list.foldr(
                      tx.inputs,
                      value.zero(),
                      fn(i, v) {
                        let ibond_qty = bond_quantity_of(i.output.value)
                        let iaddr = i.output.address
                        if
                        iaddr.payment_credential == sask_addr.payment_credential{
                        
                          if v == value.zero() {
                            let sc_bond_names =
                              dict.keys(
                                value.tokens(
                                  i.output.value,
                                  escrow_info.bond_symbol,
                                ),
                              )
                            if list.at(sc_bond_names, 1) == None {
                              if (ibond_qty > 0)? {
                                i.output.value
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
                            False -> v
                          }
                        }
                      },
                    )
                  let biz_output =
                    list.foldr(
                      tx.outputs,
                      BizOutput {
                        oask_value: value.zero(),
                        rbid_value: value.zero(),
                        fee_lovelace: 0,
                        rbid_qty: 0,
                        buyer_payment_creds: [],
                      },
                      fn(o, z) {
                        let oaddr = o.address
                        if
                        oaddr.payment_credential == sask_addr.payment_credential{
                        
                          if and {
                            (bond_quantity_of(z.oask_value) == 0)?,
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
                                BizOutput { ..z, oask_value: o.value }
                              } else {
                                fail @"ask order output invalid datum"
                              }
                            } else {
                              fail @"ask output must only one bond name allowed"
                            }
                          } else {
                            fail @"must only one ask order output allowed"
                          }
                        } else if oaddr == rbid_addr {
                          if (value.lovelace_of(z.rbid_value) == 0)? {
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
                                rbid_value: o.value,
                                rbid_qty: obid_dt.quantity,
                              }
                            } else {
                              fail @"bid order output invalid datum"
                            }
                          } else {
                            fail @"must only one owner output for ask order allowed"
                          }
                        } else if oaddr == fee_addr {
                          expect has_safe_datum(o)
                          BizOutput {
                            ..z,
                            fee_lovelace: z.fee_lovelace + value.lovelace_of(
                              o.value,
                            ),
                          }
                        } else {
                          BizOutput {
                            ..z,
                            buyer_payment_creds: [
                              o.address.payment_credential,
                              ..z.buyer_payment_creds
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
                      biz_output.buyer_payment_creds,
                      VerificationKeyCredential(sask_dt.owner_vk),
                    )
                  and {
                    buyer_is_not_owner?,
                    (bond_quantity_of(sask_value) > 0)?,
                    (bond_quantity_of(biz_output.oask_value) >= 0)?,
                    (bond_quantity_of(biz_output.oask_value) < bond_quantity_of(
                      sask_value,
                    ))?,
                    (value.lovelace_of(biz_output.rbid_value) > 0)?,
                    spending_correct(
                      cfg,
                      escrow_info,
                      sask_dt,
                      sask_value,
                      biz_output,
                      bond_quantity_of,
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
  sask_value: Value,
  biz_output: BizOutput,
  bond_quantity_of: fn(Value) -> Int,
) -> Bool {
  let BizOutput { oask_value, rbid_value, rbid_qty, fee_lovelace, .. } =
    biz_output
  let sask_bond_qty = bond_quantity_of(sask_value)
  let oask_bond_qty = bond_quantity_of(oask_value)
  let matching_bond_qty = sask_bond_qty - oask_bond_qty
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
  // SC chuyển bond ==> seller nhận tiền
  // buyer chuyển tiền nhận bond
  let (exchange_lovelace_after_fee, expected_fee_lovelace) =
    (
      received_with_yield - exchange_fee_seller,
      exchange_fee_buyer + exchange_fee_seller,
    )

  and {
    // Must exchange bond tokens
    (matching_bond_qty > 0)?,
    // Must withdraw expected amount of bond tokens from spending ask 
    (oask_bond_qty >= sask_bond_qty - matching_bond_qty)?,
    // Must pay correct exchange fee
    (fee_lovelace >= expected_fee_lovelace)?,
    // Must remain correct assets, no unbound value
    (value.merge(oask_value, rbid_value) == (
      sask_value
        |> value.add(
            escrow_info.bond_symbol,
            escrow_info.token_name,
            -matching_bond_qty,
          )
        |> value.add(ada_policy_id, ada_asset_name, exchange_lovelace_after_fee)
    ))?,
    // Must not bid more than sale
    (rbid_qty <= matching_bond_qty)?,
  }
}
