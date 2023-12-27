// Ask Limit
use aiken/bytearray
use aiken/dict
use aiken/interval.{Finite}
use aiken/list
use aiken/transaction.{Transaction}
use aiken/transaction/credential.{Address}
use aiken/transaction/value
use bond/constraint.{get_escrow_info, get_escrow_ref}
use bond/limit/ask/utils.{collect_biz_tx_info}
use bond/types.{
  AskLimit, BizOutput, BizTxInfo, ConfigLimit, EscrowDatum, EscrowInfo,
} as bond_types
use bond/utils.{bond_assets, get_price_of_bond} as bond_utils
use common/time.{posix_time_to_relative_epoch}
use common/types.{Error, OK} as common_types
use common/util.{get_data} as common_utils

fn matching_is_valid(
  conf: ConfigLimit,
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
    received_diff * conf.exchange.seller_fee / conf.bond.basis_points_ref_unit
  // phi buyer phai tra cho san theo ti le trong config
  let exchange_fee_buyer =
    received_diff * conf.exchange.buyer_fee / conf.bond.basis_points_ref_unit
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
    (owner_output_len > 0)?,
    (out.owner.lovelace == owner_receive_lovelace)?,
  }
}

fn matching_correct(
  conf: ConfigLimit,
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
            conf,
            in,
            out,
            escrow_info,
            qty_owner_2_buyer,
            get_price_of_bond(
              escrow_info.value_at_maturity,
              escrow_info.day_to_maturity,
              sask_dt.requested_yield,
              conf.bond.basis_points_ref_unit,
            ),
            min_ada_to_exchange,
          )?,
        }
    },
  }
}

pub fn matching(
  tx: Transaction,
  conf: ConfigLimit,
  sask_dt: AskLimit,
  owner: Address,
  sask_addr: Address,
) -> Bool {
  let validity_after_must_set =
    when tx.validity_range.lower_bound.bound_type is {
      Finite(x) -> x
      _ -> 0
    }
  let validity_end_must_set =
    when tx.validity_range.upper_bound.bound_type is {
      Finite(x) -> x
      _ -> 0
    }
  let owner_vk = sask_dt.owner_vk
  and {
    (validity_after_must_set > 0)?,
    (validity_end_must_set > 0)?,
    (validity_end_must_set > validity_after_must_set)?,
    (validity_end_must_set - validity_after_must_set <= when
      conf.exchange.tx_buy_ttl
    is {
      Some(x) -> x
      None -> 3 * 60
    } * conf.slot.slot_length)?,
    not(bytearray.is_empty(owner_vk))?,
    when get_escrow_ref(tx.reference_inputs, conf.bond) is {
      Some(escrow_ref) ->
        when get_data(tx.datums, escrow_ref.output.datum) is {
          Some(d) -> {
            expect escrow_dt: EscrowDatum = d
            let start_epoch =
              escrow_dt.start + conf.bond.epoch_config.epoch_boundary_as_epoch
            let end_epoch = start_epoch + escrow_dt.duration
            and {
              (escrow_dt.bond_amount > 0)?,
              (value.lovelace_of(escrow_dt.epo_rewards) > 0)?,
              (value.lovelace_of(escrow_ref.output.value) > escrow_dt.bond_amount * conf.bond.bond_face_value)?,
              when
                get_escrow_info(
                  conf.bond,
                  value.lovelace_of(escrow_ref.output.value),
                  escrow_dt,
                  validity_after_must_set,
                  posix_time_to_relative_epoch(
                    validity_after_must_set,
                    conf.bond.epoch_config,
                  ),
                  start_epoch,
                  end_epoch,
                )
              is {
                OK(escrow_info) -> {
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
                      sask_addr,
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
                          matching_correct(conf, sask_dt, in, ou, escrow_info),
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
