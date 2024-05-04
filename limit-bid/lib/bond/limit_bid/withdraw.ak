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
use aiken/transaction/value.{AssetName, PolicyId, Value}
use bond/constraint.{bid_limit_multi_valid, epoch_valid, yield_valid}
use bond/limit_bid/types.{EscrowBond, Sell, TradeAction} as dtypes
use bond/limit_bid/utils.{contains}
use bond/types.{
  BidLimitMulti, BondConfigLimit, EscrowDatum, EscrowInfo, PlatformConfig,
}
use bond/utils.{get_day_to_maturity, get_price_of_bond} as butils
use common/data
use common/pvalue
use common/string.{bconcat_3, to_unit_3}
use common/time.{
  Basis, EpochTime, posix_time_to_relative_epoch, tx_validity_valid,
} as ctime
use common/types.{
  AssetUnit, Error, Lovelace, OK, PublicKeyHash, Result, ScriptKeyHash,
} as ctypes

pub fn constraint(
  ctx: ScriptContext,
  cfg: BondConfigLimit,
  bid_skh: ScriptKeyHash,
  script_blacklist: List<ScriptKeyHash>,
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
      let bid_sc = ScriptCredential(bid_skh)
      let epo_curr: EpochTime =
        posix_time_to_relative_epoch(tx_time_valid, cfg.platform.epoch)
      let output_dt = sum_output_dt(tx, cfg, tx_time_valid, epo_curr, bid_sc)

      let escrow_bond =
        get_escrow_bond_from_ref(
          tx,
          cfg,
          output_dt.escrow_bond,
          tx_time_valid,
          epo_curr,
        )

      let redeemer_dt = sum_redeemer_dt(tx)
      // validate for each bid redeemer
      let input_dt =
        sum_input_dt(
          tx,
          cfg,
          bid_sc,
          script_blacklist,
          redeemer_dt,
          escrow_bond,
          epo_curr,
          output_dt.bid_by_idx,
        )

      let min_ada = cfg.platform.min_ada * cfg.platform.one_ada_2_lovelace
      let is_buyer_data_valid =
        list.foldl(
          input_dt.buyer,
          True,
          fn(buyer_vk, z) {
            let (exchange_fee, seller_receive, redeemer_bond) =
              get_buyer_data(buyer_vk, input_dt.data_by_owner)
            let (buyer_lovelace, obid_lovelace, value) =
              get_buyer_data(buyer_vk, output_dt.data_by_owner)
            let ibid_lovelace =
              get_buyer_data(buyer_vk, input_dt.sum_bid_lovelace_by_owner)
            and {
              z,
              (ibid_lovelace - exchange_fee - seller_receive == buyer_lovelace + obid_lovelace)?,
              contains(redeemer_bond, value)?,
              (list.has(input_dt.vk_input, buyer_vk) == False)?,
              if
              VerificationKeyCredential(buyer_vk) == cfg.exchange.fee_addr.payment_credential{
              
                (min_ada + input_dt.sum_exchange_fee <= buyer_lovelace)?
              } else {
                (min_ada <= buyer_lovelace)?
              },
            }
          },
        )
      and {
        (input_dt.sum_exchange_fee <= output_dt.sum_exchange_fee)?,
        is_buyer_data_valid?,
      }
    }

    // is_buyer_data_valid?,
    Error(e) -> fail e
  }
}

type InputDt {
  sum_bid_lovelace_by_owner: Dict<PublicKeyHash, Lovelace>,
  vk_input: List<PublicKeyHash>,
  sum_exchange_fee: Lovelace,
  // exchange_fee, seller_receive, offer
  data_by_owner: Dict<PublicKeyHash, (Lovelace, Lovelace, Value)>,
  cont_idx_set: List<Int>,
  buyer: List<PublicKeyHash>,
}

type OutputDt {
  sum_exchange_fee: Lovelace,
  // Lovelace, bid lovelace, value
  data_by_owner: Dict<PublicKeyHash, (Lovelace, Lovelace, Value)>,
  escrow_bond: Dict<AssetUnit, EscrowBond>,
  bid_by_idx: Dict<Int, (BidLimitMulti, Lovelace, Option<StakeCredential>)>,
}

fn sum_data_by_owner(
  _k,
  a: (Lovelace, Lovelace, Value),
  b: (Lovelace, Lovelace, Value),
) {
  Some((a.1st + b.1st, a.2nd + b.2nd, value.merge(a.3rd, b.3rd)))
}

fn get_buyer_data(buyer_vk: PublicKeyHash, data: Dict<PublicKeyHash, a>) -> a {
  when dict.get(data, buyer_vk) is {
    None -> fail @"data of buyer is invalid"
    Some(v) -> v
  }
}

fn sum_output_dt(
  tx: Transaction,
  cfg: BondConfigLimit,
  tx_time_valid: PosixTime,
  epo_curr: PosixTime,
  bid_sc: Credential,
) -> OutputDt {
  list.indexed_foldr(
    tx.outputs,
    OutputDt {
      sum_exchange_fee: 0,
      escrow_bond: dict.new(),
      bid_by_idx: dict.new(),
      data_by_owner: dict.new(),
    },
    fn(idx, o, z) {
      if o.address == cfg.exchange.fee_addr {
        OutputDt {
          ..z,
          sum_exchange_fee: z.sum_exchange_fee + value.lovelace_of(o.value),
        }
      } else if o.address.payment_credential == bid_sc {
        expect odt: BidLimitMulti = data.output_datum(o)
        OutputDt {
          ..z,
          data_by_owner: dict.insert_with(
            z.data_by_owner,
            odt.owner_vk,
            (0, value.lovelace_of(o.value), value.zero()),
            sum_data_by_owner,
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
                OutputDt {
                  ..z,
                  escrow_bond: dict.insert(
                    z.escrow_bond,
                    bond_unit,
                    (bond_type, escrow_info),
                    string.compare,
                  ),
                }
              }
              _ -> z
            }
          VerificationKeyCredential(k) ->
            OutputDt {
              ..z,
              data_by_owner: dict.insert_with(
                z.data_by_owner,
                k,
                (value.lovelace_of(o.value), 0, value.without_lovelace(o.value)),
                sum_data_by_owner,
                bytearray.compare,
              ),
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
  init: Dict<AssetUnit, EscrowBond>,
  tx_time_valid: PosixTime,
  epo_curr: PosixTime,
) -> Dict<AssetUnit, EscrowBond> {
  list.foldl(
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

pub fn get_escrow_info(
  platform_cfg: PlatformConfig,
  bond_unit: AssetUnit,
  escrow_bal: Lovelace,
  escrow_dt: EscrowDatum,
  escrow_epo_rewards: Lovelace,
  tx_time: PosixTime,
  epo_curr: EpochTime,
) -> Result<EscrowInfo, String> {
  let escrow_epo_start: EpochTime =
    escrow_dt.start + platform_cfg.epoch.epoch_boundary_as_epoch
  let escrow_epo_end: EpochTime = escrow_epo_start + escrow_dt.duration
  // Tong epoch phai tra lai tinh den epoch hien tai
  let escrow_due_paid_epo: EpochTime =
    if epo_curr >= escrow_epo_end {
      escrow_dt.duration
    } else {
      epo_curr - escrow_epo_start + 1
    }
  // Tong tien lai Borrower can phai tra tinh den epoch hien tai
  let escrow_due_paid: Lovelace = escrow_due_paid_epo * escrow_epo_rewards
  // Tien goc cua toan bo bond phat hanh
  let escrow_principal: Lovelace =
    escrow_dt.bond_amount * platform_cfg.bond_face_value
  let escrow_bal_min: Lovelace = escrow_principal + escrow_due_paid
  if (escrow_bal >= escrow_bal_min)? {
    // Tong tien lai tich luy hien tai cho toan bo bond phat hanh
    let premium_paid: Lovelace = escrow_bal - escrow_principal
    // Tong tien lai tich luy hien tai tinh theo epoch cho toan bo bond phat hanh
    // let epo_premium_paid: EpochTime = premium_paid / escrow_epo_rewards
    // Tong so epoch ma Borrower tra du tinh tu epoch hien tai
    let interest_level: EpochTime =
      ( premium_paid - escrow_due_paid ) / escrow_epo_rewards
    let interest_max: Lovelace = escrow_epo_rewards * escrow_dt.duration
    // So epoch con lai cho den khi bond se duoc phep dong
    let closable_in: EpochTime =
      if or {
        escrow_due_paid_epo >= escrow_dt.duration,
        escrow_bal >= interest_max,
      } {
        escrow_epo_end - epo_curr
      } else {
        interest_level - escrow_dt.buffer + 1
      }
    if or {
      epo_curr > escrow_epo_end,
      closable_in <= 0,
    } {
      Error(bconcat_3(@"bond ", bond_unit, @" closable"))
    } else {
      // Tien phi Optim thu cua Borrower 3%
      let lender_rate: Basis = platform_cfg.basis.base - escrow_dt.otm_fee
      // Tong tien lai lender nhan duoc cua tat ca bond phat hanh khi ket thuc chu ky dao han
      let lender_interest: Lovelace =
        escrow_epo_rewards * escrow_dt.duration * lender_rate
      // Tong tien lai lender nhan duoc khi den ky dao han cua 1 bond da tru phi cua Optim 3%
      let interest_at_maturity: Lovelace =
        lender_interest / platform_cfg.basis.base / escrow_dt.bond_amount
      OK(
        EscrowInfo {
          bond_symbol: escrow_dt.bond_symbol,
          token_name: escrow_dt.token_name,
          bond_amount: escrow_dt.bond_amount,
          start_epoch: escrow_epo_start,
          end_epoch: escrow_epo_end,
          // Tong tien goc + lai cua 1 bond theo lai suat Optim ma lender nhan duoc 
          value_at_maturity: interest_at_maturity + platform_cfg.bond_face_value,
          // So ngay den ky dao han cua bond
          day_to_maturity: get_day_to_maturity(
            tx_time,
            escrow_epo_end,
            platform_cfg.epoch,
          ),
        },
      )
    }
  } else {
    Error(bconcat_3(@"bond ", bond_unit, @" missing interest"))
  }
}

fn sum_input_dt(
  tx: Transaction,
  cfg: BondConfigLimit,
  bid_sc: Credential,
  script_blacklist: List<ScriptKeyHash>,
  redeemer_dt: Dict<OutputReference, Data>,
  escrow_bond: Dict<AssetUnit, EscrowBond>,
  epo_curr: PosixTime,
  obid_by_idx: Dict<Int, (BidLimitMulti, Lovelace)>,
) -> InputDt {
  list.foldl(
    tx.inputs,
    InputDt {
      sum_bid_lovelace_by_owner: dict.new(),
      vk_input: [],
      sum_exchange_fee: 0,
      data_by_owner: dict.new(),
      cont_idx_set: [],
      buyer: [],
    },
    fn(i, z) {
      if i.output.address == cfg.exchange.fee_addr {
        fail @"exchange input is not allowed"
      } else if i.output.address.payment_credential == bid_sc {
        expect Some(redeemer) = dict.get(redeemer_dt, i.output_reference)
        expect r: TradeAction = redeemer
        when r is {
          Sell { exchange_fee, seller_receive, offers, cont_idx } -> {
            expect ibid_dt: BidLimitMulti = data.input_datum(i)
            when
              is_redeemer_valid(
                i,
                cfg,
                ibid_dt,
                exchange_fee,
                seller_receive,
                offers,
                escrow_bond,
                cont_idx,
                epo_curr,
                obid_by_idx,
              )
            is {
              OK(bond_by_owner) -> {
                let sum_bid_lovelace_by_owner =
                  dict.insert_with(
                    z.sum_bid_lovelace_by_owner,
                    ibid_dt.owner_vk,
                    value.lovelace_of(i.output.value),
                    fn(_k, a, b) { Some(a + b) },
                    bytearray.compare,
                  )
                let r =
                  InputDt {
                    ..z,
                    sum_bid_lovelace_by_owner: sum_bid_lovelace_by_owner,
                    sum_exchange_fee: z.sum_exchange_fee + exchange_fee,
                    buyer: [ibid_dt.owner_vk, ..z.buyer],
                    data_by_owner: dict.insert_with(
                      z.data_by_owner,
                      ibid_dt.owner_vk,
                      (exchange_fee, seller_receive, bond_by_owner),
                      sum_data_by_owner,
                      bytearray.compare,
                    ),
                  }
                when cont_idx is {
                  Some(i) ->
                    if list.has(z.cont_idx_set, i) {
                      fail @"duplicate cont idx"
                    } else {
                      InputDt { ..r, cont_idx_set: [i, ..z.cont_idx_set] }
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
        when i.output.address.payment_credential is {
          VerificationKeyCredential(k) ->
            InputDt { ..z, vk_input: [k, ..z.vk_input] }
          ScriptCredential(k) ->
            if script_blacklist |> list.has(k) {
              fail @"do not allow spend deprecated bid"
            } else {
              z
            }
        }
      }
    },
  )
}

fn sum_redeemer_dt(tx: Transaction) -> Dict<OutputReference, Data> {
  dict.foldl(
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

fn is_redeemer_valid(
  in_bid: Input,
  cfg: BondConfigLimit,
  ibid_dt: BidLimitMulti,
  exchange_fee: Lovelace,
  seller_receive: Lovelace,
  offers: List<(PolicyId, AssetName, Int)>,
  escrow_bond: Dict<AssetUnit, EscrowBond>,
  cont_bid_idx: Option<Int>,
  epo_curr: PosixTime,
  obid_by_idx: Dict<Int, (BidLimitMulti, Lovelace, Option<StakeCredential>)>,
) -> Result<Value, String> {
  let (sell_qty, want_exchange_fee, want_seller_receive, bond_by_owner) =
    list.foldl(
      offers,
      (0, 0, 0, value.zero()),
      fn(i, z) {
        let (p, a, q) = i
        let bond_unit = to_unit_3(p, @".", a)
        let (z_qty, z_exchange_fee, z_seller_receive, z_bond_by_owner) = z
        when dict.get(escrow_bond, bond_unit) is {
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
    Error(@"redeemer is invalid")
  }
}

fn escrow_info_valid(
  escrow_bond: EscrowBond,
  epo_curr: PosixTime,
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
