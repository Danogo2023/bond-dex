use aiken/dict.{Dict}
use aiken/int
use aiken/list
use aiken/time.{PosixTime}
use aiken/transaction.{
  DatumHash, InlineDatum, Input, NoDatum, Output, ScriptContext, Spend,
  Transaction,
}
use aiken/transaction/credential.{
  Address, ScriptCredential, VerificationKeyCredential,
}
use aiken/transaction/value.{AssetName, PolicyId, Value}
use bond/constraint.{bid_limit_multi_valid, epoch_valid, yield_valid}
use bond/limit_bid/types.{Sell, TradeAction} as dtypes
use bond/limit_bid/utils.{contains, get_escrow_info}
use bond/types.{BidLimitMulti, BondConfigLimit, EscrowDatum, EscrowInfo}
use bond/utils.{get_price_of_bond} as butils
use common/data
use common/pvalue
use common/string.{bconcat_3, to_unit_3}
use common/time.{EpochTime,
  posix_time_to_relative_epoch, tx_validity_valid} as ctime
use common/types.{AssetUnit, Error, Lovelace, OK} as ctypes

type OutputDt {
  sum_exchange_fee: Lovelace,
  buyer_lovelace: Lovelace,
  escrow_bond: Dict<AssetUnit, EscrowInfo>,
  cont_bid: Option<Output>,
  value_by_owner: Value,
  sum_bid_lovelace_by_owner: Lovelace,
}

type InputDt {
  sum_bid_lovelace_by_owner: Lovelace,
}

// data get tu redeemer cua bid
type RedeemerDt {
  sum_exchange_fee: Lovelace,
  sum_seller_receive: Lovelace,
  bond_by_owner: Value,
  cont_idx_set: Dict<Int, Bool>,
}

pub fn constraint(
  ctx: ScriptContext,
  cfg: BondConfigLimit,
  sbid_dt: BidLimitMulti,
  exchange_fee: Lovelace,
  seller_receive: Lovelace,
  offers: List<(PolicyId, AssetName, Int)>,
  cont_idx: Option<Int>,
) {
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
      expect Spend(sbid_out_ref) = ctx.purpose
      expect Some(sbid) = transaction.find_input(tx.inputs, sbid_out_ref)
      let epo_curr: EpochTime =
        posix_time_to_relative_epoch(tx_time_valid, cfg.platform.epoch)
      let redeemer_dt = sum_redeemer_dt(sbid_dt, tx, sbid)
      let output_dt =
        sum_output_dt(tx, cont_idx, sbid, cfg, sbid_dt, tx_time_valid, epo_curr)
      let escrow_bond =
        get_escrow_bond_from_ref(
          tx,
          cfg,
          sbid_dt,
          output_dt.escrow_bond,
          tx_time_valid,
          epo_curr,
        )
      // get data from offers
      let (sell_qty, want_exchange_fee, want_seller_receive) =
        list.foldl(
          offers,
          (0, 0, 0),
          fn(i, z) {
            let (p, a, q) = i
            let bond_unit = to_unit_3(p, @".", a)
            let (z_qty, z_exchange_fee, z_seller_receive) = z
            when dict.get(escrow_bond, bond_unit) is {
              Some(escrow_info) -> {
                let (qty, exchange_fee, seller_receive) =
                  escrow_info_valid(
                    escrow_info,
                    epo_curr,
                    sbid_dt,
                    q,
                    cfg,
                    bond_unit,
                  )
                (
                  z_qty + qty,
                  z_exchange_fee + exchange_fee,
                  z_seller_receive + seller_receive,
                )
              }
              None -> fail @"bond is invalid"
            }
          },
        )
      let owner_vkc = VerificationKeyCredential(sbid_dt.owner_vk)
      let input_dt =
        list.foldl(
          tx.inputs,
          InputDt { sum_bid_lovelace_by_owner: 0 },
          fn(i, z) {
            if i.output.address == cfg.exchange.fee_addr {
              fail @"exchange input is not allowed"
            } else if i.output.address.payment_credential == owner_vkc {
              fail @"buyer input is not allowed"
            } else if i.output.address.payment_credential == sbid.output.address.payment_credential {
              expect idt: BidLimitMulti = data.input_datum(i)
              if owner_vkc == VerificationKeyCredential(idt.owner_vk) {
                InputDt {
                  sum_bid_lovelace_by_owner: z.sum_bid_lovelace_by_owner + value.lovelace_of(
                    i.output.value,
                  ),
                }
              } else {
                z
              }
            } else {
              z
            }
          },
        )
      let min_ada = cfg.platform.min_ada * cfg.platform.one_ada_2_lovelace
      and {
        (exchange_fee == want_exchange_fee)?,
        (seller_receive == want_seller_receive)?,
        (redeemer_dt.sum_exchange_fee <= output_dt.sum_exchange_fee)?,
        if owner_vkc == cfg.exchange.fee_addr.payment_credential {
          (min_ada + redeemer_dt.sum_exchange_fee <= output_dt.buyer_lovelace)?
        } else {
          (min_ada <= output_dt.buyer_lovelace)?
        },
        (input_dt.sum_bid_lovelace_by_owner - redeemer_dt.sum_exchange_fee - redeemer_dt.sum_seller_receive == output_dt.buyer_lovelace + output_dt.sum_bid_lovelace_by_owner)?,
        contains(redeemer_dt.bond_by_owner, output_dt.value_by_owner)?,
        when output_dt.cont_bid is {
          Some(obid) -> {
            expect obid_dt: BidLimitMulti = data.output_datum(obid)
            and {
              yield_valid(cfg.platform.basis, obid_dt.requested_yield)?,
              epoch_valid(
                obid_dt.from_epoch,
                obid_dt.to_epoch,
                obid_dt.quantity,
              ),
              bid_limit_multi_valid(obid_dt, sbid_dt),
              (obid_dt.quantity > 0)?,
              (value.lovelace_of(sbid.output.value) - seller_receive - exchange_fee - min_ada <= value.lovelace_of(
                obid.value,
              ))?,
            }
          }
          _ -> True
        },
        (sbid_dt.quantity - sell_qty >= 0)?,
      }
    }
    Error(e) -> fail e
  }
}

fn sum_redeemer_dt(
  sbid_dt: BidLimitMulti,
  tx: Transaction,
  sbid: Input,
) -> RedeemerDt {
  dict.foldl(
    tx.redeemers,
    RedeemerDt {
      sum_exchange_fee: 0,
      sum_seller_receive: 0,
      bond_by_owner: value.zero(),
      cont_idx_set: dict.new(),
    },
    fn(k, v, z) {
      when k is {
        Spend(out_ref) -> {
          expect Some(in) = transaction.find_input(tx.inputs, out_ref)
          if
          in.output.address.payment_credential == sbid.output.address.payment_credential{
          
            expect idt: BidLimitMulti = data.input_datum(in)
            expect r: TradeAction = v
            when r is {
              Sell { exchange_fee, seller_receive, offers, cont_idx } ->
                if idt.owner_vk == sbid_dt.owner_vk {
                  let (bond_by_owner, sum_seller_receive) =
                    (
                      list.foldl(
                        offers,
                        z.bond_by_owner,
                        fn(i, r) { value.add(r, i.1st, i.2nd, i.3rd) },
                      ),
                      z.sum_seller_receive + seller_receive,
                    )
                  when cont_idx is {
                    Some(i) ->
                      when dict.get(z.cont_idx_set, i) is {
                        Some(_) -> fail @"duplicate cont idx"
                        _ ->
                          RedeemerDt {
                            sum_exchange_fee: exchange_fee + z.sum_exchange_fee,
                            bond_by_owner,
                            cont_idx_set: dict.insert(
                              z.cont_idx_set,
                              i,
                              True,
                              int.compare,
                            ),
                            sum_seller_receive,
                          }
                      }
                    _ ->
                      RedeemerDt {
                        ..z,
                        sum_exchange_fee: exchange_fee + z.sum_exchange_fee,
                        bond_by_owner: bond_by_owner,
                        sum_seller_receive: sum_seller_receive,
                      }
                  }
                } else {
                  z
                }
              _ -> z
            }
          } else {
            z
          }
        }
        _ -> z
      }
    },
  )
}

fn sum_output_dt(
  tx: Transaction,
  cont_idx: Option<Int>,
  sbid: Input,
  cfg: BondConfigLimit,
  sbid_dt: BidLimitMulti,
  tx_time_valid: PosixTime,
  epo_curr: PosixTime,
) -> OutputDt {
  let sbid_owner_vkc = VerificationKeyCredential(sbid_dt.owner_vk)
  list.indexed_foldr(
    tx.outputs,
    OutputDt {
      sum_exchange_fee: 0,
      escrow_bond: dict.new(),
      cont_bid: None,
      value_by_owner: value.zero(),
      buyer_lovelace: 0,
      sum_bid_lovelace_by_owner: 0,
    },
    fn(idx, o, z) {
      if o.address == cfg.exchange.fee_addr {
        OutputDt {
          ..z,
          sum_exchange_fee: z.sum_exchange_fee + value.lovelace_of(o.value),
        }
      } else if o.address.payment_credential == sbid_owner_vkc {
        OutputDt {
          ..z,
          value_by_owner: value.merge(
            z.value_by_owner,
            value.without_lovelace(o.value),
          ),
          buyer_lovelace: z.buyer_lovelace + value.lovelace_of(o.value),
        }
      } else if o.address == sbid.output.address {
        expect odt: BidLimitMulti = data.output_datum(o)
        if sbid_owner_vkc == VerificationKeyCredential(odt.owner_vk) {
          let r =
            when cont_idx is {
              Some(i) ->
                if i == idx {
                  OutputDt { ..z, cont_bid: Some(o) }
                } else {
                  z
                }
              _ -> z
            }
          OutputDt {
            ..r,
            sum_bid_lovelace_by_owner: r.sum_bid_lovelace_by_owner + value.lovelace_of(
              o.value,
            ),
          }
        } else {
          z
        }
      } else {
        when o.address.payment_credential is {
          ScriptCredential(k) ->
            when dict.get(cfg.escrow, k) is {
              Some((escrow_nft_pid, bond_type)) ->
                if list.has(sbid_dt.bond_types, bond_type) {
                  let (bond_unit, escrow_info) =
                    get_escrow_bond(
                      tx,
                      escrow_nft_pid,
                      o,
                      cfg,
                      tx_time_valid,
                      epo_curr,
                    )
                  OutputDt {
                    ..z,
                    escrow_bond: dict.insert(
                      z.escrow_bond,
                      bond_unit,
                      escrow_info,
                      string.compare,
                    ),
                  }
                } else {
                  z
                }
              _ -> z
            }
          _ -> z
        }
      }
    },
  )
}

fn escrow_info_valid(
  escrow_info: EscrowInfo,
  epo_curr: PosixTime,
  sbid_dt: BidLimitMulti,
  qty: Int,
  cfg: BondConfigLimit,
  bond_unit: AssetUnit,
) -> (Int, Lovelace, Lovelace) {
  if and {
    (escrow_info.end_epoch >= epo_curr)?,
    (escrow_info.end_epoch >= sbid_dt.from_epoch)?,
    (escrow_info.end_epoch <= sbid_dt.to_epoch)?,
    (qty > 0)?,
  } {
    // Tong tien lender nhan duoc cuoi chu ky dao han bao gom ca goc va lai tuong ung vs so bond ma buyer mua
    let received_at_maturity: Lovelace = escrow_info.value_at_maturity * qty
    // Tong tien buyer(owner of bid) phai tra/seller nhan duoc chua tru phi
    let received_with_yield: Lovelace =
      get_price_of_bond(
        escrow_info.value_at_maturity,
        escrow_info.day_to_maturity,
        sbid_dt.requested_yield,
        cfg.platform.basis.base,
      ) * qty
    // Chenh lech tien lai nhan duoc
    let received_diff: Lovelace = received_at_maturity - received_with_yield
    // phi seller phai tra cho san theo ti le trong config
    let exchange_fee_seller: Lovelace =
      received_diff * cfg.exchange.seller_fee / cfg.platform.basis.base
    // phi buyer(owner of bid) phai tra cho san theo ti le trong config
    let exchange_fee_buyer: Lovelace =
      received_diff * cfg.exchange.buyer_fee / cfg.platform.basis.base
    let exchange_fee: Lovelace = exchange_fee_buyer + exchange_fee_seller
    let seller_receive: Lovelace = received_with_yield - exchange_fee_seller
    (qty, exchange_fee, seller_receive)
  } else {
    fail bconcat_3(@"escrow of bond ", bond_unit, @" invalid epoch")
  }
}

fn get_escrow_bond(
  tx: Transaction,
  escrow_nft_pid: PolicyId,
  o: Output,
  cfg: BondConfigLimit,
  tx_time_valid: PosixTime,
  epo_curr: PosixTime,
) -> (AssetUnit, EscrowInfo) {
  when
    value.tokens(o.value, escrow_nft_pid)
      |> dict.to_list
  is {
    [(n, q)] ->
      if q == 1 {
        let data =
          when o.datum is {
            NoDatum -> None
            DatumHash(h) -> dict.get(tx.datums, h)
            InlineDatum(d) -> Some(d)
          }
        when data is {
          Some(dt) -> {
            expect escrow_dt: EscrowDatum = dt
            let bond_unit =
              to_unit_3(escrow_dt.bond_symbol, @".", escrow_dt.token_name)
            if n == escrow_dt.token_name {
              let escrow_epo_rewards =
                value.lovelace_of(escrow_dt.epo_rewards |> pvalue.to_value)
              if and {
                (escrow_dt.bond_amount > 0)?,
                (escrow_epo_rewards > 0)?,
              } {
                let escrow_bal: Lovelace = value.lovelace_of(o.value)
                when
                  get_escrow_info(
                    cfg.platform,
                    bond_unit,
                    escrow_bal,
                    escrow_dt,
                    escrow_epo_rewards,
                    tx_time_valid,
                    epo_curr,
                  )
                is {
                  OK(escrow_info) -> (bond_unit, escrow_info)
                  Error(e) -> fail e
                }
              } else {
                fail @"bond data is invalid"
              }
            } else {
              fail @"bond token name is not equal nft name"
            }
          }
          _ -> fail @"datum is invalid"
        }
      } else {
        fail @"quantity of nft is not 1"
      }
    _ -> fail @"tokens in valid"
  }
}

fn get_escrow_bond_from_ref(
  tx: Transaction,
  cfg: BondConfigLimit,
  sbid_dt: BidLimitMulti,
  init: Dict<AssetUnit, EscrowInfo>,
  tx_time_valid: PosixTime,
  epo_curr: PosixTime,
) -> Dict<AssetUnit, EscrowInfo> {
  list.foldl(
    tx.reference_inputs,
    init,
    fn(i, z) {
      when i.output.address.payment_credential is {
        ScriptCredential(k) ->
          when dict.get(cfg.escrow, k) is {
            Some((escrow_nft_pid, bond_type)) ->
              if list.has(sbid_dt.bond_types, bond_type) {
                let (bond_unit, escrow_info) =
                  get_escrow_bond(
                    tx,
                    escrow_nft_pid,
                    i.output,
                    cfg,
                    tx_time_valid,
                    epo_curr,
                  )
                dict.insert(z, bond_unit, escrow_info, string.compare)
              } else {
                z
              }
            _ -> z
          }
        _ -> z
      }
    },
  )
}
