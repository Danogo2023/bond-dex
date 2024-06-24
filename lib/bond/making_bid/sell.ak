// Bid Making
use aiken/bytearray
use aiken/dict
use aiken/list
use aiken/transaction.{InlineDatum, Output, ScriptContext, Spend, Transaction}
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

pub type BizInput {
  sbid_value: Value,
  seller_value: Value,
  seller_addrs: List<Address>,
  seller_payment_creds: List<PaymentCredential>,
}

pub type BizOutput {
  obid_value: Value,
  obid_qty: Int,
  rask_value: Value,
  fee_lovelace: Lovelace,
  seller_value: Value,
  seller_payment_creds: List<PaymentCredential>,
}

pub fn spending(
  ctx: ScriptContext,
  cfg: BondConfigMaking,
  sbid_dt: BidMaking,
  script_blacklist: List<ScriptKeyHash>,
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
                  let EscrowInfo { bond_symbol, token_name, .. } = escrow_info
                  let bond_quantity_of =
                    fn(v: Value) {
                      value.quantity_of(v, bond_symbol, token_name)
                    }
                  expect Spend(sbid_out_ref) = ctx.purpose
                  expect Some(sbid) =
                    list.find(
                      tx.inputs,
                      fn(i) { i.output_reference == sbid_out_ref },
                    )
                  let sbid_addr: Address = sbid.output.address
                  let sbid_pk: ByteArray = get_payment_key(sbid_addr)
                  let rask_addr =
                    Address {
                      payment_credential: ScriptCredential(sbid_dt.ask_sc),
                      stake_credential: sbid_addr.stake_credential,
                    }
                  let fee_addr: Address = cfg.exchange.fee_addr
                  let biz_input =
                    list.foldr(
                      tx.inputs,
                      BizInput {
                        sbid_value: value.zero(),
                        seller_value: value.zero(),
                        seller_addrs: [],
                        seller_payment_creds: [],
                      },
                      fn(i, z) {
                        let iaddr = i.output.address
                        if
                        iaddr.payment_credential == sbid_addr.payment_credential{
                        
                          if z.sbid_value == value.zero() {
                            BizInput { ..z, sbid_value: i.output.value }
                          } else {
                            fail @"matching only one bid order allowed"
                          }
                        } else {
                          when is_deprecated_sm_input(i, script_blacklist) is {
                            True -> fail @"do not allow spend deprecated bid"
                            False ->
                              if or {
                                iaddr == rask_addr,
                                iaddr == fee_addr,
                              } {
                                z
                              } else {
                                BizInput {
                                  ..z,
                                  seller_value: value.merge(
                                    z.seller_value,
                                    i.output.value,
                                  ),
                                  seller_addrs: [iaddr, ..z.seller_addrs],
                                  seller_payment_creds: [
                                    iaddr.payment_credential,
                                    ..z.seller_payment_creds
                                  ],
                                }
                              }
                          }
                        }
                      },
                    )
                  let biz_output =
                    list.foldr(
                      tx.outputs,
                      BizOutput {
                        obid_value: value.zero(),
                        obid_qty: 0,
                        rask_value: value.zero(),
                        seller_value: value.zero(),
                        fee_lovelace: 0,
                        seller_payment_creds: [],
                      },
                      fn(o, z) {
                        let oaddr = o.address
                        if
                        oaddr.payment_credential == sbid_addr.payment_credential{
                        
                          if and {
                            (z.obid_value == value.zero())?,
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
                                obid_value: o.value,
                                obid_qty: obid_dt.quantity,
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
                          if oaddr == rask_addr {
                            if (z.rask_value == value.zero())? {
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
                                  BizOutput { ..z, rask_value: o.value }
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
                            expect has_safe_datum(o)
                            if (z.fee_lovelace == 0)? {
                              BizOutput {
                                ..z,
                                fee_lovelace: value.lovelace_of(o.value),
                              }
                            } else {
                              fail @"must only one fee output for bid order allowed"
                            }
                          } else {
                            BizOutput {
                              ..z,
                              seller_value: value.merge(z.seller_value, o.value),
                              seller_payment_creds: [
                                o.address.payment_credential,
                                ..z.seller_payment_creds
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
                        biz_input.seller_payment_creds,
                        VerificationKeyCredential(sbid_dt.owner_vk),
                      ),
                      !list.has(
                        biz_output.seller_payment_creds,
                        VerificationKeyCredential(sbid_dt.owner_vk),
                      ),
                    }
                  and {
                    seller_is_not_owner?,
                    (bond_quantity_of(biz_output.rask_value) > 0)?,
                    spending_correct(
                      tx,
                      cfg,
                      escrow_info,
                      sbid_dt,
                      biz_input,
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
  tx: Transaction,
  cfg: BondConfigMaking,
  escrow_info: EscrowInfo,
  sbid_dt: BidMaking,
  biz_input: BizInput,
  biz_output: BizOutput,
  bond_quantity_of: fn(Value) -> Int,
) -> Bool {
  let BizInput { sbid_value, seller_value: iseller_value, .. } = biz_input
  let BizOutput {
    obid_value,
    obid_qty,
    rask_value,
    fee_lovelace,
    seller_value: oseller_value,
    ..
  } = biz_output
  let rask_bond_qty = bond_quantity_of(rask_value)
  // Tong tien lender nhan duoc cuoi chu ky dao han bao gom ca goc va lai tuong ung vs so bond ma buyer mua
  let received_at_maturity: Lovelace =
    escrow_info.value_at_maturity * rask_bond_qty
  // Tong tien buyer(owner of bid) phai tra/seller nhan duoc chua tru phi
  let received_with_yield: Lovelace =
    get_price_of_bond(
      escrow_info.value_at_maturity,
      escrow_info.day_to_maturity,
      sbid_dt.requested_yield,
      cfg.platform.basis.base,
    ) * rask_bond_qty
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
  // seller is exchange addr
  let exchange_fee_for_seller: Lovelace =
    if list.has(biz_input.seller_addrs, cfg.exchange.fee_addr) {
      exchange_fee
    } else {
      0
    }
  //
  let exchange_fee_total: Lovelace =
    if exchange_fee_for_seller > 0 {
      0
    } else {
      exchange_fee
    }
  //
  let tx_fee: Lovelace = value.lovelace_of(tx.fee)
  //
  let expected_oseller_lovelace =
    value.lovelace_of(iseller_value) + oseller_max_recevie + exchange_fee_for_seller - tx_fee
  and {
    // Must pay for exchange fee
    (fee_lovelace >= exchange_fee_total)?,
    // Sellers must not receive more than the funds for sale bond tokens
    (value.lovelace_of(oseller_value) <= expected_oseller_lovelace)?,
    // Owner assets are expected, no unbound value:
    // assets(remain_bid) + assets(reversed_ask) == assets(spending_bid) + sale_bond_tokens - exchange_fee - exchange_prices 
    (value.merge(obid_value, rask_value) == (
      sbid_value
        |> value.add(
            escrow_info.bond_symbol,
            escrow_info.token_name,
            rask_bond_qty,
          )
        |> value.add(
            ada_policy_id,
            ada_asset_name,
            -exchange_fee_total - oseller_max_recevie,
          )
    ))?,
    // Must introduce remaining bid with expected quantity
    obid_qty == sbid_dt.quantity - rask_bond_qty,
  }
}
