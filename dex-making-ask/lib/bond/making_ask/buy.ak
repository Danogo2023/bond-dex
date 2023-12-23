// Ask Making
use aiken/bytearray
use aiken/dict
use aiken/list
use aiken/transaction.{Transaction}
use aiken/transaction/credential.{Address, VerificationKeyCredential}
use aiken/transaction/value
use bond/constraint.{get_escrow_info, get_escrow_ref}
use bond/making_ask/utils.{collect_biz_tx_info}
use bond/types.{
  AskMaking, BidMaking, BizOutput, BizTxInfo, ConfigMaking, EscrowDatum,
  EscrowInfo,
}
use bond/utils.{get_price_of_bond} as bond_utils
use common/time.{posix_time_to_relative_epoch, tx_validity_valid}
use common/types.{Error, OK} as common_types
use common/util.{get_data} as common_utils

fn matching_is_valid(
  tx: Transaction,
  conf: ConfigMaking,
  in: BizOutput,
  out: BizOutput,
  escrow_info: EscrowInfo,
  buyer_qty: Int,
  price_of_one_bond: Int,
) -> Bool {
  // Tong tien lender nhan duoc cuoi chu ky dao han bao gom ca goc va lai tuong ung vs so bond ma buyer mua
  let received_at_maturity = escrow_info.value_at_maturity * buyer_qty
  // Tong tien buyer phai tra/seller(owner of listing) nhan duoc chua tru phi
  let received_with_yield = price_of_one_bond * buyer_qty
  // Chenh lech tien lai nhan duoc
  let received_diff = received_at_maturity - received_with_yield
  // phi seller(owner of listing) phai tra cho san theo ti le trong config
  let exchange_fee_seller =
    received_diff * conf.exchange.maker_fee / conf.bond.basis_points_ref_unit
  // phi buyer phai tra cho san theo ti le trong config
  let exchange_fee_buyer =
    received_diff * conf.exchange.taker_fee / conf.bond.basis_points_ref_unit
  let owner_out_utxos =
    list.concat(out.owner.bond_outputs, out.owner.other_outputs)
  let owner_output_len = list.length(owner_out_utxos)
  let sc_output_len =
    list.length(list.concat(out.sc.bond_outputs, out.sc.other_outputs))
  let exchange_receive_lovelace_tmp = exchange_fee_buyer + exchange_fee_seller
  let owner_receive_lovelace_tmp = received_with_yield - exchange_fee_seller
  let (owner_receive_lovelace, exchange_receive_lovelace) =
    when list.at(out.owner.addresses, 0) is {
      Some(a) ->
        if owner_output_len > 0 && a == conf.exchange.address {
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
    (out.sc.lovelace + out.owner.lovelace == in.sc.lovelace + owner_receive_lovelace)?,
    when list.at(owner_out_utxos, 0) is {
      Some(utxo) ->
        when get_data(tx.datums, utxo.datum) is {
          Some(d) -> {
            expect owner_out_datum: BidMaking = d
            (owner_out_datum.quantity <= buyer_qty)?
          }
          None -> {
            trace @"not found owner output bid making datum"
            False
          }
        }
      None -> True
    },
  }
}

fn matching_correct(
  tx: Transaction,
  conf: ConfigMaking,
  spd_ask_datum: AskMaking,
  in: BizOutput,
  out: BizOutput,
  escrow_info: EscrowInfo,
) -> Bool {
  let (
    qty_owner_2_buyer,
    sm_out_must_only_one_bond_name,
    sm_out_bond_same_escrow,
  ) =
    when out.sc.bond_outputs is {
      [_, ..] ->
        // trace @"buy partial"
        (
          in.sc.bond_qty - out.sc.bond_qty,
          dict.size(out.sc.bond_assets) <= 1,
          dict.has_key(out.sc.bond_assets, escrow_info.token_name),
        )
      [] ->
        // trace @"buy all"
        (in.sc.bond_qty, True, True)
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
          out.sc.bond_datum_valid?,
          out.owner.bond_datum_valid?,
          matching_is_valid(
            tx,
            conf,
            in,
            out,
            escrow_info,
            qty_owner_2_buyer,
            get_price_of_bond(
              escrow_info.value_at_maturity,
              escrow_info.day_to_maturity,
              spd_ask_datum.requested_yield,
              conf.bond.basis_points_ref_unit,
            ),
          ),
        }
    },
  }
}

pub fn matching(
  tx: Transaction,
  conf: ConfigMaking,
  spd_ask_datum: AskMaking,
  owner: Address,
  spending: Address,
) -> Bool {
  let tx_time_valid =
    tx_validity_valid(
      tx.validity_range,
      conf.slot.slot_length,
      conf.exchange.tx_buy_ttl,
    )
  and {
    not(bytearray.is_empty(spd_ask_datum.owner_vk))?,
    when get_escrow_ref(tx.reference_inputs, conf.bond) is {
      Some(ref_in_escrow) ->
        when get_data(tx.datums, ref_in_escrow.output.datum) is {
          Some(d) -> {
            expect escrow_datum: EscrowDatum = d
            let start_epoch =
              escrow_datum.start + conf.bond.epoch_config.epoch_boundary_as_epoch
            let end_epoch = start_epoch + escrow_datum.duration
            and {
              (escrow_datum.bond_amount > 0)?,
              (value.lovelace_of(escrow_datum.epo_rewards) > 0)?,
              (value.lovelace_of(ref_in_escrow.output.value) > escrow_datum.bond_amount * conf.bond.bond_face_value)?,
              when
                get_escrow_info(
                  conf.bond,
                  value.lovelace_of(ref_in_escrow.output.value),
                  escrow_datum,
                  tx_time_valid,
                  posix_time_to_relative_epoch(
                    tx_time_valid,
                    conf.bond.epoch_config,
                  ),
                  start_epoch,
                  end_epoch,
                )
              is {
                OK(escrow_info) -> {
                  let spd_ask_datum_owner =
                    Address {
                      payment_credential: VerificationKeyCredential(
                        spd_ask_datum.owner_vk,
                      ),
                      stake_credential: owner.stake_credential,
                    }
                  let BizTxInfo {
                    valid: biz_tx_info_valid,
                    biz_tx_in: in,
                    biz_tx_out: out,
                  } =
                    collect_biz_tx_info(
                      conf,
                      tx.inputs,
                      tx.outputs,
                      owner,
                      spending,
                      tx.datums,
                      escrow_info,
                      spd_ask_datum,
                    )
                  and {
                    biz_tx_info_valid,
                    (dict.size(in.sc.bond_assets) == 1)?,
                    dict.has_key(in.sc.bond_assets, escrow_info.token_name)?,
                    !list.has(in.other.addresses, spd_ask_datum_owner),
                    when out is {
                      Some(ou) -> and {
                          !list.has(ou.other.addresses, spd_ask_datum_owner),
                          (in.owner.bond_qty <= 0)?,
                          matching_correct(
                            tx,
                            conf,
                            spd_ask_datum,
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
}
