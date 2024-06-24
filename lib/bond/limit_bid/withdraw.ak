use aiken/bytearray
use aiken/dict.{Dict}
use aiken/int
use aiken/list
use aiken/time.{PosixTime}
use aiken/transaction.{
  DatumHash, InlineDatum, Input, NoDatum, Output, OutputReference, ScriptContext,
  Spend, Transaction,
}
use aiken/transaction/credential.{
  Address, Credential, ScriptCredential, StakeCredential,
  VerificationKeyCredential,
}
use aiken/transaction/value.{
  AssetName, PolicyId, Value, ada_asset_name, ada_policy_id,
}
use bond/common/constraint.{bid_limit_multi_valid, epoch_valid, yield_valid}
use bond/common/types.{
  AddressId, BidLimitMulti, BondConfigLimit, EscrowDatum, EscrowInfo,
  ExchangeConfigLimit, PlatformConfig,
}
use bond/common/utils.{
  get_address_id, get_escrow_info, get_price_of_bond, has_safe_datum,
  is_deprecated_sm_input,
} as butils
use bond/limit_bid/types.{BidValue,
  BuyerValue, EscrowBond, Sell, TradeAction} as dtypes
use common/data
use common/pvalue
use common/string.{bconcat_3, to_unit_3}
use common/time.{EpochTime,
  posix_time_to_relative_epoch, tx_validity_valid} as ctime
use common/types.{AssetUnit,
  Error, Lovelace, OK, Result, ScriptKeyHash} as ctypes

pub fn constraint(
  ctx: ScriptContext,
  cfg: BondConfigLimit,
  bid_skh: ScriptKeyHash,
  script_blacklist: List<ScriptKeyHash>,
) {
  let ScriptContext { transaction: tx, .. } = ctx
  let BondConfigLimit {
    platform: PlatformConfig { epoch, slot, min_ada, one_ada_2_lovelace, .. },
    exchange: ExchangeConfigLimit { tx_buy_ttl, fee_addr, .. },
    ..
  } = cfg

  expect OK(tx_time_valid) =
    tx_validity_valid(tx.validity_range, slot.slot_length, tx_buy_ttl, True)

  let epo_curr = posix_time_to_relative_epoch(tx_time_valid, epoch)
  let min_lovelace = min_ada * one_ada_2_lovelace

  let bid_cred = ScriptCredential(bid_skh)
  let OutputData {
    sum_exchange_fee,
    escrow_by_unit,
    bid_by_idx: obid_by_idx,
    data_by_owner: odata_by_owner,
  } = calc_output_data(tx, cfg, tx_time_valid, epo_curr, bid_cred)
  let InputData {
    sum_exchange_fee: expected_exchange_fee,
    all_buyer_addr,
    data_by_owner: idata_by_owner,
    ..
  } =
    calc_input_data(
      tx,
      cfg,
      bid_cred,
      script_blacklist,
      sum_redeemer_dt(tx),
      get_escrow_bond_from_ref(tx, cfg, escrow_by_unit, tx_time_valid, epo_curr),
      epo_curr,
      obid_by_idx,
    )

  and {
    // Protocol must receive enough exchange fee
    (expected_exchange_fee <= sum_exchange_fee)?,
    // Each buyer must receive expected assets
    list.foldr(
      all_buyer_addr,
      True,
      fn(buyer_addr, valid) {
        let buyer_id = get_address_id(buyer_addr)
        let (exchange_tokens, ibid_assets) =
          must_get_buyer_data(buyer_id, idata_by_owner)
        let (obuyer_assets, obid_assets) =
          must_get_buyer_data(buyer_id, odata_by_owner)
        let obuyer_lovelace = value.lovelace_of(obuyer_assets)
        expect and {
            // The buyer must own exactly expected assets
            {
              let expected_own_assets =
                value.merge(ibid_assets, exchange_tokens)
              let actual_own_assets = value.merge(obid_assets, obuyer_assets)
              expected_own_assets == actual_own_assets
            }?,
            // If buyer is protocol, they must receive both min lovelace and exchange fee
            if buyer_addr.payment_credential == fee_addr.payment_credential {
              (min_lovelace + expected_exchange_fee <= obuyer_lovelace)?
            } else {
              (min_lovelace <= obuyer_lovelace)?
            },
          }
        valid
      },
    )?,
  }
}

type InputData {
  sum_exchange_fee: Lovelace,
  // (exchange_tokens, bid_assets) 
  data_by_owner: Dict<AddressId, (BuyerValue, BidValue)>,
  cont_idx_set: List<Int>,
  all_buyer_addr: List<Address>,
}

type OutputData {
  sum_exchange_fee: Lovelace,
  // (owner_assets, bid_assets)
  data_by_owner: Dict<AddressId, (BuyerValue, BidValue)>,
  escrow_by_unit: Dict<AssetUnit, EscrowBond>,
  bid_by_idx: Dict<Int, (BidLimitMulti, Lovelace, Option<StakeCredential>)>,
}

fn merge_pair_assets(_, a: (Value, Value), b: (Value, Value)) {
  Some((value.merge(a.1st, b.1st), value.merge(a.2nd, b.2nd)))
}

fn must_get_buyer_data(buyer_addr: AddressId, data: Dict<AddressId, a>) -> a {
  when dict.get(data, buyer_addr) is {
    None -> fail @"data of buyer is invalid"
    Some(v) -> v
  }
}

fn calc_output_data(
  tx: Transaction,
  cfg: BondConfigLimit,
  tx_time_valid: PosixTime,
  epo_curr: EpochTime,
  bid_cred: Credential,
) -> OutputData {
  list.indexed_foldr(
    tx.outputs,
    OutputData {
      sum_exchange_fee: 0,
      escrow_by_unit: dict.new(),
      bid_by_idx: dict.new(),
      data_by_owner: dict.new(),
    },
    fn(idx, o, z) {
      if o.address == cfg.exchange.fee_addr {
        expect has_safe_datum(o)
        OutputData {
          ..z,
          sum_exchange_fee: z.sum_exchange_fee + value.lovelace_of(o.value),
        }
      } else if o.address.payment_credential == bid_cred {
        expect odt: BidLimitMulti = data.output_datum(o)
        OutputData {
          ..z,
          data_by_owner: dict.insert_with(
            z.data_by_owner,
            get_address_id(
              Address {
                payment_credential: VerificationKeyCredential(odt.owner_vk),
                stake_credential: o.address.stake_credential,
              },
            ),
            (value.zero(), o.value),
            merge_pair_assets,
            bytearray.compare,
          ),
          bid_by_idx: dict.insert(
            z.bid_by_idx,
            idx,
            (odt, value.lovelace_of(o.value), o.address.stake_credential),
            int.compare,
          ),
        }
      } else {
        when o.address.payment_credential is {
          ScriptCredential(k) ->
            when dict.get(cfg.escrow, k) is {
              Some((escrow_nft_pid, bond_type)) -> {
                let (bond_unit, escrow_info) =
                  get_escrow_bond(
                    tx,
                    escrow_nft_pid,
                    o,
                    cfg,
                    tx_time_valid,
                    epo_curr,
                  )
                OutputData {
                  ..z,
                  escrow_by_unit: dict.insert(
                    z.escrow_by_unit,
                    bond_unit,
                    (bond_type, escrow_info),
                    string.compare,
                  ),
                }
              }
              _ -> z
            }
          VerificationKeyCredential(_) -> {
            expect has_safe_datum(o)
            OutputData {
              ..z,
              data_by_owner: dict.insert_with(
                z.data_by_owner,
                get_address_id(o.address),
                (o.value, value.zero()),
                merge_pair_assets,
                bytearray.compare,
              ),
            }
          }
        }
      }
    },
  )
}

fn get_escrow_bond(
  tx: Transaction,
  escrow_nft_pid: PolicyId,
  o: Output,
  cfg: BondConfigLimit,
  tx_time_valid: PosixTime,
  epo_curr: EpochTime,
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
  init: Dict<AssetUnit, EscrowBond>,
  tx_time_valid: PosixTime,
  epo_curr: EpochTime,
) -> Dict<AssetUnit, EscrowBond> {
  list.foldr(
    tx.reference_inputs,
    init,
    fn(i, z) {
      when i.output.address.payment_credential is {
        ScriptCredential(k) ->
          when dict.get(cfg.escrow, k) is {
            Some((escrow_nft_pid, bond_type)) -> {
              let (bond_unit, escrow_info) =
                get_escrow_bond(
                  tx,
                  escrow_nft_pid,
                  i.output,
                  cfg,
                  tx_time_valid,
                  epo_curr,
                )
              dict.insert(
                z,
                bond_unit,
                (bond_type, escrow_info),
                string.compare,
              )
            }
            _ -> z
          }
        _ -> z
      }
    },
  )
}

fn calc_input_data(
  tx: Transaction,
  cfg: BondConfigLimit,
  bid_cred: Credential,
  script_blacklist: List<ScriptKeyHash>,
  redeemer_dt: Dict<OutputReference, Data>,
  escrow_by_unit: Dict<AssetUnit, EscrowBond>,
  epo_curr: EpochTime,
  obid_by_idx: Dict<Int, (BidLimitMulti, Lovelace, Option<StakeCredential>)>,
) -> InputData {
  list.foldr(
    tx.inputs,
    InputData {
      sum_exchange_fee: 0,
      data_by_owner: dict.new(),
      cont_idx_set: [],
      all_buyer_addr: [],
    },
    fn(i, z) {
      if i.output.address == cfg.exchange.fee_addr {
        fail @"exchange input is not allowed"
      } else if i.output.address.payment_credential == bid_cred {
        expect Some(redeemer) = dict.get(redeemer_dt, i.output_reference)
        expect r: TradeAction = redeemer
        when r is {
          Sell { exchange_fee, seller_receive, offers, cont_idx } -> {
            expect ibid_dt: BidLimitMulti = data.input_datum(i)
            when
              is_valid_sell(
                i,
                cfg,
                ibid_dt,
                exchange_fee,
                seller_receive,
                offers,
                escrow_by_unit,
                cont_idx,
                epo_curr,
                obid_by_idx,
              )
            is {
              OK(bond_by_owner) -> {
                let owner_addr =
                  Address {
                    payment_credential: VerificationKeyCredential(
                      ibid_dt.owner_vk,
                    ),
                    stake_credential: i.output.address.stake_credential,
                  }
                let r =
                  InputData {
                    ..z,
                    sum_exchange_fee: z.sum_exchange_fee + exchange_fee,
                    all_buyer_addr: [owner_addr, ..z.all_buyer_addr],
                    data_by_owner: dict.insert_with(
                      z.data_by_owner,
                      get_address_id(owner_addr),
                      (
                        bond_by_owner,
                        i.output.value
                          |> value.add(
                              ada_policy_id,
                              ada_asset_name,
                              -exchange_fee - seller_receive,
                            ),
                      ),
                      merge_pair_assets,
                      bytearray.compare,
                    ),
                  }
                when cont_idx is {
                  Some(i) ->
                    if list.has(z.cont_idx_set, i) {
                      fail @"duplicate cont idx"
                    } else {
                      InputData { ..r, cont_idx_set: [i, ..z.cont_idx_set] }
                    }
                  _ -> r
                }
              }
              Error(e) -> fail e
            }
          }
          _ -> fail @"redeemer is invalid"
        }
      } else {
        expect not(is_deprecated_sm_input(i, script_blacklist))?
        z
      }
    },
  )
}

fn sum_redeemer_dt(tx: Transaction) -> Dict<OutputReference, Data> {
  dict.foldr(
    tx.redeemers,
    dict.new(),
    fn(purpose, redeemer, z) {
      when purpose is {
        Spend(out_ref) ->
          z
            |> dict.insert(out_ref, redeemer, fn(_, _) { Equal })

        _ -> z
      }
    },
  )
}

fn is_valid_sell(
  in_bid: Input,
  cfg: BondConfigLimit,
  ibid_dt: BidLimitMulti,
  exchange_fee: Lovelace,
  seller_receive: Lovelace,
  offers: List<(PolicyId, AssetName, Int)>,
  escrow_by_unit: Dict<AssetUnit, EscrowBond>,
  cont_bid_idx: Option<Int>,
  epo_curr: EpochTime,
  obid_by_idx: Dict<Int, (BidLimitMulti, Lovelace, Option<StakeCredential>)>,
) -> Result<Value, String> {
  let (sell_qty, want_exchange_fee, want_seller_receive, bond_by_owner) =
    list.foldr(
      offers,
      (0, 0, 0, value.zero()),
      fn(i, z) {
        let (p, a, q) = i
        let bond_unit = to_unit_3(p, @".", a)
        let (z_qty, z_exchange_fee, z_seller_receive, z_bond_by_owner) = z
        when dict.get(escrow_by_unit, bond_unit) is {
          Some(escrow_info) -> {
            let (qty, exchange_fee, seller_receive) =
              escrow_info_valid(
                escrow_info,
                epo_curr,
                ibid_dt,
                q,
                cfg,
                bond_unit,
              )
            (
              z_qty + qty,
              z_exchange_fee + exchange_fee,
              z_seller_receive + seller_receive,
              value.add(z_bond_by_owner, p, a, q),
            )
          }

          None -> fail @"bond is invalid"
        }
      },
    )
  let min_ada = cfg.platform.min_ada * cfg.platform.one_ada_2_lovelace
  if and {
    (ibid_dt.quantity - sell_qty >= 0)?,
    (want_exchange_fee == exchange_fee)?,
    (seller_receive == want_seller_receive)?,
    when cont_bid_idx is {
      None -> True
      Some(idx) ->
        when dict.get(obid_by_idx, idx) is {
          Some((obid_dt, obid_lovelace, obid_stake_cre)) -> and {
              yield_valid(cfg.platform.basis, obid_dt.requested_yield)?,
              epoch_valid(
                obid_dt.from_epoch,
                obid_dt.to_epoch,
                obid_dt.quantity,
              )?,
              bid_limit_multi_valid(obid_dt, ibid_dt)?,
              (obid_dt.quantity > 0)?,
              (value.lovelace_of(in_bid.output.value) - seller_receive - exchange_fee - min_ada <= obid_lovelace)?,
              (in_bid.output.address.stake_credential == obid_stake_cre)?,
            }
          None -> fail @"cont idx is invalid"
        }
    },
  } {
    OK(bond_by_owner)
  } else {
    Error(@"something went wrong with sell action")
  }
}

fn escrow_info_valid(
  escrow_bond: EscrowBond,
  epo_curr: EpochTime,
  sbid_dt: BidLimitMulti,
  qty: Int,
  cfg: BondConfigLimit,
  bond_unit: AssetUnit,
) -> (Int, Lovelace, Lovelace) {
  let (bond_type, escrow_info) = escrow_bond
  if and {
    (escrow_info.end_epoch >= epo_curr)?,
    (escrow_info.end_epoch >= sbid_dt.from_epoch)?,
    (escrow_info.end_epoch <= sbid_dt.to_epoch)?,
    (qty > 0)?,
    list.has(sbid_dt.bond_types, bond_type)?,
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
    fail bconcat_3(@"escrow of bond ", bond_unit, @" invalid")
  }
}
