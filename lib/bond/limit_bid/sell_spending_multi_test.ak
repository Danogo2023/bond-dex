use aiken/bytearray
use aiken/cbor
use aiken/dict
use aiken/interval.{Finite, entirely_between}
use aiken/time.{PosixTime}
use aiken/transaction.{
  InlineDatum, Input, NoDatum, Output, OutputReference, ScriptContext,
  ScriptPurpose, Spend, Transaction, TransactionId, WithdrawFrom,
}
use aiken/transaction/credential.{
  Inline, ScriptCredential, StakeCredential, from_script, from_verification_key,
  with_delegation_key, with_delegation_script,
}
use aiken/transaction/value.{AssetName, PolicyId, ada_asset_name, ada_policy_id}
use bond/common/fixture.{
  gen_bid_limit_multi_datum, get_buyer_address_hash, get_config_limit_mainnet,
  get_escrow_policy_id,
}
use bond/common/types.{
  BidLimitMulti, BondConfigLimit, DanogoBond, EscrowDatum, ExchangeConfigLimit,
} as bond_types
use bond/common/utils.{get_day_to_maturity, get_price_of_bond} as bond_utils
use bond/limit_bid/sell
use bond/limit_bid/types.{Sell, SellMulti}
use bond/limit_bid/withdraw
use common/pvalue
use common/types.{ScriptKeyHash} as common_types

const ada = 1_000_000

const bid_skh = "bid_1"

const multi_bid_skh = "multi_bid_skh"

const script_blacklist = "script_blacklist"

// ================ utils =================
fn escrow_like(
  epo_rewards: Int,
  duration: Int,
  bond_symbol: PolicyId,
  token_name: AssetName,
  bond_amount: Int,
  buffer: Int,
  start: Int,
) {
  let cfg = get_config_limit_mainnet()
  expect [escrow_skh] = dict.keys(cfg.escrow)
  Output {
    value: value.from_lovelace(1_000_000 * ada)
      |> value.add(get_escrow_policy_id(), token_name, 1),
    address: from_script(escrow_skh),
    datum: InlineDatum(
      EscrowDatum {
        epo_rewards: value.from_lovelace(epo_rewards) |> pvalue.from_value,
        duration,
        bond_symbol,
        token_name,
        bond_amount,
        buffer,
        start,
        otm_fee: 3,
        og_lender: "lender_stake",
      },
    ),
    reference_script: None,
  }
}

fn stake_credential_like(script: ScriptKeyHash) -> StakeCredential {
  Inline(ScriptCredential(script))
}

fn bid_like(
  yield: Int,
  owner: ByteArray,
  from_epoch: Int,
  to_epoch: Int,
  quantity: Int,
) {
  // (100 ada bond face value + 2 min ada + 10 buffer) each bond
  let lock_ada = quantity * 100 * ada + 2 * ada * quantity + 10
  Output {
    value: value.from_lovelace(lock_ada),
    address: from_script(bid_skh)
      |> with_delegation_key(bytearray.concat("stake_", owner)),
    datum: InlineDatum(
      BidLimitMulti {
        owner_vk: owner,
        owner_sk: Some(bytearray.concat("stake_", owner)),
        from_epoch,
        to_epoch,
        quantity,
        requested_yield: yield,
        bond_types: [DanogoBond],
      },
    ),
    reference_script: None,
  }
}

fn get_bid_datum(output: Output) {
  expect InlineDatum(inl_dtm) = output.datum
  expect dtm: BidLimitMulti = inl_dtm
  dtm
}

fn get_escrow_datum(output: Output) {
  expect InlineDatum(inl_dtm) = output.datum
  expect dtm: EscrowDatum = inl_dtm
  dtm
}

fn get_buyer_address(output: Output) {
  let BidLimitMulti { owner_vk, owner_sk, .. } = get_bid_datum(output)
  when owner_sk is {
    Some(stake_vk) ->
      from_verification_key(owner_vk)
        |> with_delegation_key(stake_vk)
    None -> from_verification_key(owner_vk)
  }
}

fn calculate_fee(
  cfg: BondConfigLimit,
  escrow: EscrowDatum,
  qty: Int,
  yield: Int,
  now: PosixTime,
) {
  let base = cfg.platform.basis.base
  let interest_at_maturity = {
    let lender_rate = base - escrow.otm_fee
    let lender_interest =
      ( escrow.epo_rewards |> pvalue.to_value |> value.lovelace_of ) * escrow.duration * lender_rate
    lender_interest / base / escrow.bond_amount
  }
  let bond_value_at_maturity =
    cfg.platform.bond_face_value + interest_at_maturity
  let day_to_maturity = {
    let issuance_epoch =
      escrow.start + cfg.platform.epoch.epoch_boundary_as_epoch
    let maturity_epoch = issuance_epoch + escrow.duration
    get_day_to_maturity(now, maturity_epoch, cfg.platform.epoch)
  }
  let received_at_maturity = bond_value_at_maturity * qty
  let received_by_yield =
    get_price_of_bond(bond_value_at_maturity, day_to_maturity, yield, base) * qty
  let benefit = received_at_maturity - received_by_yield
  let buyer_fee = benefit * cfg.exchange.buyer_fee / base
  let seller_fee = benefit * cfg.exchange.seller_fee / base
  let seller_receive = received_by_yield - seller_fee
  (buyer_fee, seller_fee, seller_receive)
}

fn add_asset(self: Output, pid: PolicyId, name: AssetName, qty: Int) {
  Output { ..self, value: value.add(self.value, pid, name, qty) }
}

fn purpose_compare(a: ScriptPurpose, b: ScriptPurpose) {
  bytearray.compare(cbor.serialise(a), cbor.serialise(b))
}

// ================ tests =================

test succ_fulfill_2_bids_same_owner_fully_by_1_seller() {
  let cfg = get_config_limit_mainnet()
  let fee_addr = cfg.exchange.fee_addr
  expect [(bond_pid, _bond_type)] = dict.values(cfg.escrow)
  let bond_name = "bond_name"
  let ibid_1 =
    Input {
      output_reference: OutputReference(TransactionId("tx_bid_1"), 0),
      output: bid_like(
        yield: 10,
        owner: "owner_1",
        from_epoch: 400,
        to_epoch: 500,
        quantity: 10,
      ),
    }
  let bid_1 = get_bid_datum(ibid_1.output)
  let ibid_2 =
    Input {
      output_reference: OutputReference(TransactionId("tx_bid_2"), 1),
      output: bid_like(
        yield: 10,
        owner: "owner_1",
        from_epoch: 400,
        to_epoch: 500,
        quantity: 10,
      ),
    }
  let bid_2 = get_bid_datum(ibid_2.output)
  let oescrow =
    escrow_like(
      epo_rewards: 1 * ada,
      start: 10,
      duration: 150,
      bond_amount: 100,
      bond_symbol: bond_pid,
      token_name: bond_name,
      buffer: 10,
    )
  let iseller =
    Input {
      output_reference: OutputReference(TransactionId("tx_seller"), 1),
      output: Output {
        value: value.from_lovelace(2 * ada)
          |> value.add(bond_pid, bond_name, 50),
        address: from_verification_key("seller_pk"),
        datum: NoDatum,
        reference_script: None,
      },
    }
  let validity_range = entirely_between(1700553367000, 1700553370000)
  expect Finite(now) = validity_range.lower_bound.bound_type
  let (buyer_1_fee, seller_1_fee, seller_1_receive) =
    calculate_fee(
      cfg,
      get_escrow_datum(oescrow),
      bid_1.quantity,
      bid_1.requested_yield,
      now,
    )
  let (buyer_2_fee, seller_2_fee, seller_2_receive) =
    calculate_fee(
      cfg,
      get_escrow_datum(oescrow),
      bid_2.quantity,
      bid_2.requested_yield,
      now,
    )
  let bid_1_fee = seller_1_fee + buyer_1_fee
  let bid_2_fee = seller_2_fee + buyer_2_fee
  let ofee =
    Output {
      value: value.from_lovelace(bid_1_fee + bid_2_fee),
      address: fee_addr,
      datum: NoDatum,
      reference_script: None,
    }
  let oseller =
    iseller.output
      |> add_asset(
          ada_policy_id,
          ada_asset_name,
          seller_2_receive + seller_1_receive - seller_1_fee - seller_2_fee,
        )
      |> add_asset(bond_pid, bond_name, -bid_1.quantity - bid_2.quantity)
  let obuyer_1 =
    Output {
      value: value.lovelace_of(ibid_1.output.value) + value.lovelace_of(
        ibid_2.output.value,
      ) - bid_1_fee - bid_2_fee - seller_1_receive - seller_2_receive
        |> value.from_lovelace
        |> value.add(bond_pid, bond_name, bid_2.quantity)
        |> value.add(bond_pid, bond_name, bid_1.quantity),
      address: get_buyer_address(ibid_1.output),
      datum: NoDatum,
      reference_script: None,
    }
  let t = transaction.placeholder()
  let tx =
    Transaction {
      ..t,
      validity_range: validity_range,
      reference_inputs: [
        Input {
          output_reference: OutputReference(TransactionId("es_01"), 0),
          output: oescrow,
        },
      ],
      redeemers: t.redeemers
        |> dict.insert(
            Spend(ibid_1.output_reference),
            Sell {
              exchange_fee: bid_1_fee,
              seller_receive: seller_1_receive,
              offers: [(bond_pid, bond_name, bid_1.quantity)],
              cont_idx: None,
            },
            purpose_compare,
          )
        |> dict.insert(
            Spend(ibid_2.output_reference),
            Sell {
              exchange_fee: bid_2_fee,
              seller_receive: seller_2_receive,
              offers: [(bond_pid, bond_name, bid_2.quantity)],
              cont_idx: None,
            },
            purpose_compare,
          )
        |> dict.insert(
            WithdrawFrom(stake_credential_like(multi_bid_skh)),
            SellMulti { bid_skh },
            purpose_compare,
          ),
      inputs: [ibid_1, ibid_2, iseller],
      outputs: [obuyer_1, oseller, ofee],
    }
  and {
    withdraw.constraint(
      ScriptContext { purpose: Spend(ibid_1.output_reference), transaction: tx },
      cfg,
      bid_skh,
      [script_blacklist],
    ),
    sell.constraint(
      ScriptContext { purpose: Spend(ibid_1.output_reference), transaction: tx },
      multi_bid_skh,
    ),
  }
}

test succ_different_bonds() {
  let cfg = get_config_limit_mainnet()
  let fee_addr = cfg.exchange.fee_addr
  expect [(bond_pid, _bond_type)] = dict.values(cfg.escrow)
  let bond_name_1 = "bond_name_1"
  let bond_name_2 = "bond_name_2"
  let ibid_1 =
    Input {
      output_reference: OutputReference(TransactionId("tx_bid_1"), 0),
      output: bid_like(
        yield: 10,
        owner: "owner_1",
        from_epoch: 400,
        to_epoch: 500,
        quantity: 10,
      ),
    }
  let bid_1 = get_bid_datum(ibid_1.output)
  let ibid_2 =
    Input {
      output_reference: OutputReference(TransactionId("tx_bid_2"), 1),
      output: bid_like(
        yield: 10,
        owner: "owner_1",
        from_epoch: 400,
        to_epoch: 500,
        quantity: 10,
      ),
    }
  let bid_2 = get_bid_datum(ibid_2.output)
  let oescrow_1 =
    escrow_like(
      epo_rewards: 1 * ada,
      start: 10,
      duration: 150,
      bond_amount: 100,
      bond_symbol: bond_pid,
      token_name: bond_name_1,
      buffer: 10,
    )
  let oescrow_2 =
    escrow_like(
      epo_rewards: 1 * ada,
      start: 10,
      duration: 150,
      bond_amount: 100,
      bond_symbol: bond_pid,
      token_name: bond_name_2,
      buffer: 10,
    )
  let iseller =
    Input {
      output_reference: OutputReference(TransactionId("tx_seller"), 1),
      output: Output {
        value: value.from_lovelace(2 * ada)
          |> value.add(bond_pid, bond_name_1, 10)
          |> value.add(bond_pid, bond_name_2, 10),
        address: from_verification_key("seller_pk"),
        datum: NoDatum,
        reference_script: None,
      },
    }
  let validity_range = entirely_between(1700553367000, 1700553370000)
  expect Finite(now) = validity_range.lower_bound.bound_type
  let (buyer_1_fee, seller_1_fee, seller_1_receive) =
    calculate_fee(
      cfg,
      get_escrow_datum(oescrow_1),
      bid_1.quantity,
      bid_1.requested_yield,
      now,
    )
  let (buyer_2_fee, seller_2_fee, seller_2_receive) =
    calculate_fee(
      cfg,
      get_escrow_datum(oescrow_2),
      bid_2.quantity,
      bid_2.requested_yield,
      now,
    )
  let bid_1_fee = seller_1_fee + buyer_1_fee
  let bid_2_fee = seller_2_fee + buyer_2_fee
  let ofee =
    Output {
      value: value.from_lovelace(bid_1_fee + bid_2_fee),
      address: fee_addr,
      datum: NoDatum,
      reference_script: None,
    }
  let oseller =
    iseller.output
      |> add_asset(bond_pid, bond_name_1, -bid_1.quantity)
      |> add_asset(bond_pid, bond_name_2, -bid_2.quantity)
  let obuyer_1 =
    Output {
      value: value.lovelace_of(ibid_1.output.value) + value.lovelace_of(
        ibid_2.output.value,
      ) - bid_1_fee - bid_2_fee - seller_1_receive - seller_2_receive
        |> value.from_lovelace
        |> value.add(bond_pid, bond_name_2, bid_2.quantity)
        |> value.add(bond_pid, bond_name_1, bid_1.quantity),
      address: get_buyer_address(ibid_1.output),
      datum: NoDatum,
      reference_script: None,
    }
  let t = transaction.placeholder()
  let tx =
    Transaction {
      ..t,
      validity_range: validity_range,
      reference_inputs: [
        Input {
          output_reference: OutputReference(TransactionId("es_01"), 0),
          output: oescrow_1,
        },
        Input {
          output_reference: OutputReference(TransactionId("es_02"), 0),
          output: oescrow_2,
        },
      ],
      redeemers: t.redeemers
        |> dict.insert(
            Spend(ibid_1.output_reference),
            Sell {
              exchange_fee: bid_1_fee,
              seller_receive: seller_1_receive,
              offers: [(bond_pid, bond_name_1, bid_1.quantity)],
              cont_idx: None,
            },
            purpose_compare,
          )
        |> dict.insert(
            Spend(ibid_2.output_reference),
            Sell {
              exchange_fee: bid_2_fee,
              seller_receive: seller_2_receive,
              offers: [(bond_pid, bond_name_2, bid_2.quantity)],
              cont_idx: None,
            },
            purpose_compare,
          )
        |> dict.insert(
            WithdrawFrom(stake_credential_like(multi_bid_skh)),
            SellMulti { bid_skh },
            purpose_compare,
          ),
      inputs: [ibid_1, ibid_2, iseller],
      outputs: [obuyer_1, oseller, ofee],
    }
  and {
    withdraw.constraint(
      ScriptContext { purpose: Spend(ibid_1.output_reference), transaction: tx },
      cfg,
      bid_skh,
      [script_blacklist],
    ),
    sell.constraint(
      ScriptContext { purpose: Spend(ibid_1.output_reference), transaction: tx },
      multi_bid_skh,
    ),
  }
}

test succ_mint_bonds() {
  let cfg = get_config_limit_mainnet()
  let fee_addr = cfg.exchange.fee_addr
  expect [(bond_pid, _bond_type)] = dict.values(cfg.escrow)
  let bond_name = "bond_name"
  let ibid_1 =
    Input {
      output_reference: OutputReference(TransactionId("tx_bid_1"), 0),
      output: bid_like(
        yield: 10,
        owner: "owner_1",
        from_epoch: 400,
        to_epoch: 500,
        quantity: 10,
      ),
    }
  let bid_1 = get_bid_datum(ibid_1.output)
  let ibid_2 =
    Input {
      output_reference: OutputReference(TransactionId("tx_bid_2"), 1),
      output: bid_like(
        yield: 10,
        owner: "owner_1",
        from_epoch: 400,
        to_epoch: 500,
        quantity: 10,
      ),
    }
  let bid_2 = get_bid_datum(ibid_2.output)
  let oescrow =
    escrow_like(
      epo_rewards: 1 * ada,
      start: 10,
      duration: 150,
      bond_amount: 100,
      bond_symbol: bond_pid,
      token_name: bond_name,
      buffer: 10,
    )
  let iseller =
    Input {
      output_reference: OutputReference(TransactionId("tx_seller"), 1),
      output: Output {
        value: value.from_lovelace(2 * ada),
        address: from_verification_key("seller_pk"),
        datum: NoDatum,
        reference_script: None,
      },
    }
  let validity_range = entirely_between(1700553367000, 1700553370000)
  expect Finite(now) = validity_range.lower_bound.bound_type
  let (buyer_1_fee, seller_1_fee, seller_1_receive) =
    calculate_fee(
      cfg,
      get_escrow_datum(oescrow),
      bid_1.quantity,
      bid_1.requested_yield,
      now,
    )
  let (buyer_2_fee, seller_2_fee, seller_2_receive) =
    calculate_fee(
      cfg,
      get_escrow_datum(oescrow),
      bid_2.quantity,
      bid_2.requested_yield,
      now,
    )
  let bid_1_fee = seller_1_fee + buyer_1_fee
  let bid_2_fee = seller_2_fee + buyer_2_fee
  let ofee =
    Output {
      value: value.from_lovelace(bid_1_fee + bid_2_fee),
      address: fee_addr,
      datum: NoDatum,
      reference_script: None,
    }
  let oseller =
    iseller.output
      |> add_asset(
          ada_policy_id,
          ada_asset_name,
          seller_2_receive + seller_1_receive - seller_1_fee - seller_2_fee,
        )
  let obuyer_1 =
    Output {
      value: value.lovelace_of(ibid_1.output.value) + value.lovelace_of(
        ibid_2.output.value,
      ) - bid_1_fee - bid_2_fee - seller_1_receive - seller_2_receive
        |> value.from_lovelace
        |> value.add(bond_pid, bond_name, bid_2.quantity)
        |> value.add(bond_pid, bond_name, bid_1.quantity),
      address: get_buyer_address(ibid_1.output),
      datum: NoDatum,
      reference_script: None,
    }
  let t = transaction.placeholder()
  let tx =
    Transaction {
      ..t,
      validity_range: validity_range,
      mint: t.mint
        |> value.from_minted_value
        |> value.add(bond_pid, bond_name, bid_1.quantity + bid_2.quantity)
        |> value.to_minted_value,
      redeemers: t.redeemers
        |> dict.insert(
            Spend(ibid_1.output_reference),
            Sell {
              exchange_fee: bid_1_fee,
              seller_receive: seller_1_receive,
              offers: [(bond_pid, bond_name, bid_1.quantity)],
              cont_idx: None,
            },
            purpose_compare,
          )
        |> dict.insert(
            Spend(ibid_2.output_reference),
            Sell {
              exchange_fee: bid_2_fee,
              seller_receive: seller_2_receive,
              offers: [(bond_pid, bond_name, bid_2.quantity)],
              cont_idx: None,
            },
            purpose_compare,
          )
        |> dict.insert(
            WithdrawFrom(stake_credential_like(multi_bid_skh)),
            SellMulti { bid_skh },
            purpose_compare,
          ),
      inputs: [ibid_1, ibid_2, iseller],
      outputs: [obuyer_1, oseller, ofee, oescrow],
    }
  and {
    withdraw.constraint(
      ScriptContext { purpose: Spend(ibid_1.output_reference), transaction: tx },
      cfg,
      bid_skh,
      [script_blacklist],
    ),
    sell.constraint(
      ScriptContext { purpose: Spend(ibid_1.output_reference), transaction: tx },
      multi_bid_skh,
    ),
  }
}

test succ_when_escrows_are_included_in_both_reference_inputs_and_outputs() {
  let cfg = get_config_limit_mainnet()
  let fee_addr = cfg.exchange.fee_addr
  expect [(bond_pid, _bond_type)] = dict.values(cfg.escrow)
  let bond_name = "bond_name"
  let ibid_1 =
    Input {
      output_reference: OutputReference(TransactionId("tx_bid_1"), 0),
      output: bid_like(
        yield: 10,
        owner: "owner_1",
        from_epoch: 400,
        to_epoch: 500,
        quantity: 10,
      ),
    }
  let bid_1 = get_bid_datum(ibid_1.output)
  let ibid_2 =
    Input {
      output_reference: OutputReference(TransactionId("tx_bid_2"), 1),
      output: bid_like(
        yield: 10,
        owner: "owner_1",
        from_epoch: 400,
        to_epoch: 500,
        quantity: 10,
      ),
    }
  let oescrow =
    escrow_like(
      epo_rewards: 1 * ada,
      start: 10,
      duration: 150,
      bond_amount: 100,
      bond_symbol: bond_pid,
      token_name: bond_name,
      buffer: 10,
    )
  let bid_2 = get_bid_datum(ibid_2.output)
  let iseller =
    Input {
      output_reference: OutputReference(TransactionId("tx_seller"), 1),
      output: Output {
        value: value.from_lovelace(2 * ada)
          |> value.add(bond_pid, bond_name, 50),
        address: from_verification_key("seller_pk"),
        datum: NoDatum,
        reference_script: None,
      },
    }

  let validity_range = entirely_between(1700553367000, 1700553370000)
  expect Finite(now) = validity_range.lower_bound.bound_type
  let (buyer_1_fee, seller_1_fee, seller_1_receive) =
    calculate_fee(
      cfg,
      get_escrow_datum(oescrow),
      bid_1.quantity,
      bid_1.requested_yield,
      now,
    )
  let (buyer_2_fee, seller_2_fee, seller_2_receive) =
    calculate_fee(
      cfg,
      get_escrow_datum(oescrow),
      bid_2.quantity,
      bid_2.requested_yield,
      now,
    )
  let bid_1_fee = seller_1_fee + buyer_1_fee
  let bid_2_fee = seller_2_fee + buyer_2_fee
  let ofee =
    Output {
      value: value.from_lovelace(bid_1_fee + bid_2_fee),
      address: fee_addr,
      datum: NoDatum,
      reference_script: None,
    }
  let obuyer_1 =
    Output {
      value: value.lovelace_of(ibid_1.output.value) + value.lovelace_of(
        ibid_2.output.value,
      ) - bid_1_fee - bid_2_fee - seller_1_receive - seller_2_receive
        |> value.from_lovelace
        |> value.add(bond_pid, bond_name, bid_1.quantity)
        |> value.add(bond_pid, bond_name, bid_2.quantity),
      address: get_buyer_address(ibid_1.output),
      datum: NoDatum,
      reference_script: None,
    }

  let oseller =
    iseller.output
      |> add_asset(bond_pid, bond_name, -bid_1.quantity)
  let t = transaction.placeholder()
  let tx =
    Transaction {
      ..t,
      validity_range: validity_range,
      mint: t.mint
        |> value.from_minted_value
        |> value.add(bond_pid, bond_name, bid_2.quantity)
        |> value.to_minted_value,
      reference_inputs: [
        Input {
          output_reference: OutputReference(TransactionId("es_01"), 0),
          output: oescrow,
        },
      ],
      redeemers: t.redeemers
        |> dict.insert(
            Spend(ibid_1.output_reference),
            Sell {
              exchange_fee: bid_1_fee,
              seller_receive: seller_1_receive,
              offers: [(bond_pid, bond_name, bid_1.quantity)],
              cont_idx: None,
            },
            purpose_compare,
          )
        |> dict.insert(
            Spend(ibid_2.output_reference),
            Sell {
              exchange_fee: bid_2_fee,
              seller_receive: seller_2_receive,
              offers: [(bond_pid, bond_name, bid_2.quantity)],
              cont_idx: None,
            },
            purpose_compare,
          )
        |> dict.insert(
            WithdrawFrom(stake_credential_like(multi_bid_skh)),
            SellMulti { bid_skh },
            purpose_compare,
          ),
      inputs: [ibid_1, ibid_2, iseller],
      outputs: [obuyer_1, oseller, ofee, oescrow],
    }
  and {
    withdraw.constraint(
      ScriptContext { purpose: Spend(ibid_1.output_reference), transaction: tx },
      cfg,
      bid_skh,
      [script_blacklist],
    ),
    sell.constraint(
      ScriptContext { purpose: Spend(ibid_1.output_reference), transaction: tx },
      multi_bid_skh,
    ),
  }
}

test succ_multiple_sellers_same_bonds() {
  let cfg = get_config_limit_mainnet()
  let fee_addr = cfg.exchange.fee_addr
  expect [(bond_pid, _bond_type)] = dict.values(cfg.escrow)
  let bond_name = "bond_name"
  let ibid_1 =
    Input {
      output_reference: OutputReference(TransactionId("tx_bid_1"), 0),
      output: bid_like(
        yield: 10,
        owner: "owner_1",
        from_epoch: 400,
        to_epoch: 500,
        quantity: 10,
      ),
    }
  let bid_1 = get_bid_datum(ibid_1.output)
  let ibid_2 =
    Input {
      output_reference: OutputReference(TransactionId("tx_bid_2"), 1),
      output: bid_like(
        yield: 10,
        owner: "owner_1",
        from_epoch: 400,
        to_epoch: 500,
        quantity: 10,
      ),
    }
  let bid_2 = get_bid_datum(ibid_2.output)
  let oescrow =
    escrow_like(
      epo_rewards: 1 * ada,
      start: 10,
      duration: 150,
      bond_amount: 100,
      bond_symbol: bond_pid,
      token_name: bond_name,
      buffer: 10,
    )
  let iseller_1 =
    Input {
      output_reference: OutputReference(TransactionId("tx_seller_1"), 1),
      output: Output {
        value: value.from_lovelace(2 * ada)
          |> value.add(bond_pid, bond_name, 50),
        address: from_verification_key("seller_1_pk"),
        datum: NoDatum,
        reference_script: None,
      },
    }
  let iseller_2 =
    Input {
      output_reference: OutputReference(TransactionId("tx_seller_2"), 1),
      output: Output {
        value: value.from_lovelace(2 * ada)
          |> value.add(bond_pid, bond_name, 50),
        address: from_verification_key("seller_2_pk"),
        datum: NoDatum,
        reference_script: None,
      },
    }
  let validity_range = entirely_between(1700553367000, 1700553370000)
  expect Finite(now) = validity_range.lower_bound.bound_type
  let (buyer_1_fee, seller_1_fee, seller_1_receive) =
    calculate_fee(
      cfg,
      get_escrow_datum(oescrow),
      bid_1.quantity,
      bid_1.requested_yield,
      now,
    )
  let (buyer_2_fee, seller_2_fee, seller_2_receive) =
    calculate_fee(
      cfg,
      get_escrow_datum(oescrow),
      bid_2.quantity,
      bid_2.requested_yield,
      now,
    )
  let bid_1_fee = seller_1_fee + buyer_1_fee
  let bid_2_fee = seller_2_fee + buyer_2_fee
  let ofee =
    Output {
      value: value.from_lovelace(bid_1_fee + bid_2_fee),
      address: fee_addr,
      datum: NoDatum,
      reference_script: None,
    }
  let obuyer_1 =
    Output {
      value: value.lovelace_of(ibid_1.output.value) + value.lovelace_of(
        ibid_2.output.value,
      ) - bid_1_fee - bid_2_fee - seller_1_receive - seller_2_receive
        |> value.from_lovelace
        |> value.add(bond_pid, bond_name, bid_2.quantity)
        |> value.add(bond_pid, bond_name, bid_1.quantity),
      address: get_buyer_address(ibid_1.output),
      datum: NoDatum,
      reference_script: None,
    }
  let oseller_1 =
    iseller_1.output
      |> add_asset(bond_pid, bond_name, -bid_1.quantity)
  let oseller_2 =
    iseller_2.output
      |> add_asset(bond_pid, bond_name, -bid_2.quantity)
  let t = transaction.placeholder()
  let tx =
    Transaction {
      ..t,
      validity_range: validity_range,
      reference_inputs: [
        Input {
          output_reference: OutputReference(TransactionId("es_01"), 0),
          output: oescrow,
        },
      ],
      redeemers: t.redeemers
        |> dict.insert(
            Spend(ibid_1.output_reference),
            Sell {
              exchange_fee: bid_1_fee,
              seller_receive: seller_1_receive,
              offers: [(bond_pid, bond_name, bid_1.quantity)],
              cont_idx: None,
            },
            purpose_compare,
          )
        |> dict.insert(
            Spend(ibid_2.output_reference),
            Sell {
              exchange_fee: bid_2_fee,
              seller_receive: seller_2_receive,
              offers: [(bond_pid, bond_name, bid_2.quantity)],
              cont_idx: None,
            },
            purpose_compare,
          )
        |> dict.insert(
            WithdrawFrom(stake_credential_like(multi_bid_skh)),
            SellMulti { bid_skh },
            purpose_compare,
          ),
      inputs: [ibid_1, ibid_2, iseller_1, iseller_2],
      outputs: [obuyer_1, oseller_1, oseller_2, ofee],
    }
  and {
    withdraw.constraint(
      ScriptContext { purpose: Spend(ibid_1.output_reference), transaction: tx },
      cfg,
      bid_skh,
      [script_blacklist],
    ),
    sell.constraint(
      ScriptContext { purpose: Spend(ibid_1.output_reference), transaction: tx },
      multi_bid_skh,
    ),
  }
}

test succ_multiple_sellers_different_bonds_with_6_bids() {
  let cfg = get_config_limit_mainnet()
  let fee_addr = cfg.exchange.fee_addr
  expect [(bond_pid, _bond_type)] = dict.values(cfg.escrow)
  let bond_name_1 = "bond_name_1"
  let bond_name_2 = "bond_name_2"
  let bond_name_3 = "bond_name_3"
  let bond_name_4 = "bond_name_4"
  let bond_name_5 = "bond_name_5"
  let bond_name_6 = "bond_name_6"
  let ibid_1 =
    Input {
      output_reference: OutputReference(TransactionId("tx_bid_1"), 0),
      output: bid_like(
        yield: 10,
        owner: "owner_1",
        from_epoch: 400,
        to_epoch: 500,
        quantity: 10,
      ),
    }
  let bid_1 = get_bid_datum(ibid_1.output)
  let ibid_2 =
    Input {
      output_reference: OutputReference(TransactionId("tx_bid_2"), 1),
      output: bid_like(
        yield: 10,
        owner: "owner_1",
        from_epoch: 400,
        to_epoch: 500,
        quantity: 10,
      ),
    }
  let bid_2 = get_bid_datum(ibid_2.output)
  let ibid_3 =
    Input {
      output_reference: OutputReference(TransactionId("tx_bid_3"), 1),
      output: bid_like(
        yield: 10,
        owner: "owner_3",
        from_epoch: 400,
        to_epoch: 500,
        quantity: 10,
      ),
    }
  let bid_3 = get_bid_datum(ibid_3.output)
  let ibid_4 =
    Input {
      output_reference: OutputReference(TransactionId("tx_bid_4"), 1),
      output: bid_like(
        yield: 10,
        owner: "owner_4",
        from_epoch: 400,
        to_epoch: 500,
        quantity: 10,
      ),
    }
  let bid_4 = get_bid_datum(ibid_4.output)
  let ibid_5 =
    Input {
      output_reference: OutputReference(TransactionId("tx_bid_5"), 1),
      output: bid_like(
        yield: 10,
        owner: "owner_5",
        from_epoch: 400,
        to_epoch: 500,
        quantity: 10,
      ),
    }
  let bid_5 = get_bid_datum(ibid_5.output)
  let ibid_6 =
    Input {
      output_reference: OutputReference(TransactionId("tx_bid_6"), 1),
      output: bid_like(
        yield: 10,
        owner: "owner_6",
        from_epoch: 400,
        to_epoch: 500,
        quantity: 10,
      ),
    }
  let bid_6 = get_bid_datum(ibid_6.output)
  let oescrow_1 =
    escrow_like(
      epo_rewards: 1 * ada,
      start: 10,
      duration: 150,
      bond_amount: 100,
      bond_symbol: bond_pid,
      token_name: bond_name_1,
      buffer: 10,
    )
  let oescrow_2 =
    escrow_like(
      epo_rewards: 1 * ada,
      start: 10,
      duration: 150,
      bond_amount: 100,
      bond_symbol: bond_pid,
      token_name: bond_name_2,
      buffer: 10,
    )
  let oescrow_3 =
    escrow_like(
      epo_rewards: 1 * ada,
      start: 10,
      duration: 150,
      bond_amount: 100,
      bond_symbol: bond_pid,
      token_name: bond_name_3,
      buffer: 10,
    )
  let oescrow_4 =
    escrow_like(
      epo_rewards: 1 * ada,
      start: 10,
      duration: 150,
      bond_amount: 100,
      bond_symbol: bond_pid,
      token_name: bond_name_4,
      buffer: 10,
    )
  let oescrow_5 =
    escrow_like(
      epo_rewards: 1 * ada,
      start: 10,
      duration: 150,
      bond_amount: 100,
      bond_symbol: bond_pid,
      token_name: bond_name_5,
      buffer: 10,
    )
  let oescrow_6 =
    escrow_like(
      epo_rewards: 1 * ada,
      start: 10,
      duration: 150,
      bond_amount: 100,
      bond_symbol: bond_pid,
      token_name: bond_name_6,
      buffer: 10,
    )
  let iseller_1 =
    Input {
      output_reference: OutputReference(TransactionId("tx_seller_1"), 1),
      output: Output {
        value: value.from_lovelace(2 * ada)
          |> value.add(bond_pid, bond_name_1, 50),
        address: from_verification_key("seller_1_pk"),
        datum: NoDatum,
        reference_script: None,
      },
    }
  let iseller_2 =
    Input {
      output_reference: OutputReference(TransactionId("tx_seller_2"), 1),
      output: Output {
        value: value.from_lovelace(2 * ada)
          |> value.add(bond_pid, bond_name_2, 50),
        address: from_verification_key("seller_2_pk"),
        datum: NoDatum,
        reference_script: None,
      },
    }

  let validity_range = entirely_between(1700553367000, 1700553370000)
  expect Finite(now) = validity_range.lower_bound.bound_type
  let (buyer_1_fee, seller_1_fee, seller_1_receive) =
    calculate_fee(
      cfg,
      get_escrow_datum(oescrow_1),
      bid_1.quantity,
      bid_1.requested_yield,
      now,
    )
  let (buyer_2_fee, seller_2_fee, seller_2_receive) =
    calculate_fee(
      cfg,
      get_escrow_datum(oescrow_2),
      bid_2.quantity,
      bid_2.requested_yield,
      now,
    )
  let (buyer_3_fee, seller_3_fee, seller_3_receive) =
    calculate_fee(
      cfg,
      get_escrow_datum(oescrow_3),
      bid_3.quantity,
      bid_3.requested_yield,
      now,
    )
  let (buyer_4_fee, seller_4_fee, seller_4_receive) =
    calculate_fee(
      cfg,
      get_escrow_datum(oescrow_4),
      bid_4.quantity,
      bid_4.requested_yield,
      now,
    )
  let (buyer_5_fee, seller_5_fee, seller_5_receive) =
    calculate_fee(
      cfg,
      get_escrow_datum(oescrow_4),
      bid_5.quantity,
      bid_5.requested_yield,
      now,
    )
  let (buyer_6_fee, seller_6_fee, seller_6_receive) =
    calculate_fee(
      cfg,
      get_escrow_datum(oescrow_4),
      bid_5.quantity,
      bid_5.requested_yield,
      now,
    )
  let bid_1_fee = seller_1_fee + buyer_1_fee
  let bid_2_fee = seller_2_fee + buyer_2_fee
  let bid_3_fee = seller_3_fee + buyer_3_fee
  let bid_4_fee = seller_4_fee + buyer_4_fee
  let bid_5_fee = seller_5_fee + buyer_5_fee
  let bid_6_fee = seller_6_fee + buyer_6_fee

  let ofee =
    Output {
      value: value.from_lovelace(
        bid_1_fee + bid_2_fee + bid_3_fee + bid_4_fee + bid_5_fee + bid_6_fee,
      ),
      address: fee_addr,
      datum: NoDatum,
      reference_script: None,
    }
  let oseller_1 =
    iseller_1.output
      |> add_asset(bond_pid, bond_name_1, -bid_1.quantity)

  let oseller_2 =
    iseller_2.output
      |> add_asset(bond_pid, bond_name_2, -bid_2.quantity)
  let obuyer_1 =
    Output {
      value: value.lovelace_of(ibid_1.output.value) + value.lovelace_of(
        ibid_2.output.value,
      ) - bid_1_fee - bid_2_fee - seller_1_receive - seller_2_receive
        |> value.from_lovelace
        |> value.add(bond_pid, bond_name_2, bid_2.quantity)
        |> value.add(bond_pid, bond_name_1, bid_1.quantity),
      address: get_buyer_address(ibid_1.output),
      datum: NoDatum,
      reference_script: None,
    }
  let obuyer_3 =
    Output {
      value: value.lovelace_of(ibid_3.output.value) - bid_3_fee - seller_3_receive
        |> value.from_lovelace
        |> value.add(bond_pid, bond_name_3, bid_3.quantity),
      address: get_buyer_address(ibid_3.output),
      datum: NoDatum,
      reference_script: None,
    }
  let obuyer_4 =
    Output {
      value: value.lovelace_of(ibid_4.output.value) - bid_4_fee - seller_4_receive
        |> value.from_lovelace
        |> value.add(bond_pid, bond_name_4, bid_4.quantity),
      address: get_buyer_address(ibid_4.output),
      datum: NoDatum,
      reference_script: None,
    }
  let obuyer_5 =
    Output {
      value: value.lovelace_of(ibid_5.output.value) - bid_5_fee - seller_5_receive
        |> value.from_lovelace
        |> value.add(bond_pid, bond_name_5, bid_5.quantity),
      address: get_buyer_address(ibid_5.output),
      datum: NoDatum,
      reference_script: None,
    }
  let obuyer_6 =
    Output {
      value: value.lovelace_of(ibid_6.output.value) - bid_6_fee - seller_6_receive
        |> value.from_lovelace
        |> value.add(bond_pid, bond_name_6, bid_6.quantity),
      address: get_buyer_address(ibid_6.output),
      datum: NoDatum,
      reference_script: None,
    }
  let t = transaction.placeholder()
  let tx =
    Transaction {
      ..t,
      validity_range: validity_range,
      reference_inputs: [
        Input {
          output_reference: OutputReference(TransactionId("es_01"), 0),
          output: oescrow_1,
        },
        Input {
          output_reference: OutputReference(TransactionId("es_02"), 0),
          output: oescrow_2,
        },
        Input {
          output_reference: OutputReference(TransactionId("es_03"), 0),
          output: oescrow_3,
        },
        Input {
          output_reference: OutputReference(TransactionId("es_04"), 0),
          output: oescrow_4,
        },
        Input {
          output_reference: OutputReference(TransactionId("es_05"), 0),
          output: oescrow_5,
        },
        Input {
          output_reference: OutputReference(TransactionId("es_06"), 0),
          output: oescrow_6,
        },
      ],
      redeemers: t.redeemers
        |> dict.insert(
            Spend(ibid_1.output_reference),
            Sell {
              exchange_fee: bid_1_fee,
              seller_receive: seller_1_receive,
              offers: [(bond_pid, bond_name_1, bid_1.quantity)],
              cont_idx: None,
            },
            purpose_compare,
          )
        |> dict.insert(
            Spend(ibid_2.output_reference),
            Sell {
              exchange_fee: bid_2_fee,
              seller_receive: seller_2_receive,
              offers: [(bond_pid, bond_name_2, bid_2.quantity)],
              cont_idx: None,
            },
            purpose_compare,
          )
        |> dict.insert(
            Spend(ibid_3.output_reference),
            Sell {
              exchange_fee: bid_3_fee,
              seller_receive: seller_3_receive,
              offers: [(bond_pid, bond_name_3, bid_3.quantity)],
              cont_idx: None,
            },
            purpose_compare,
          )
        |> dict.insert(
            Spend(ibid_4.output_reference),
            Sell {
              exchange_fee: bid_4_fee,
              seller_receive: seller_4_receive,
              offers: [(bond_pid, bond_name_4, bid_4.quantity)],
              cont_idx: None,
            },
            purpose_compare,
          )
        |> dict.insert(
            Spend(ibid_5.output_reference),
            Sell {
              exchange_fee: bid_5_fee,
              seller_receive: seller_5_receive,
              offers: [(bond_pid, bond_name_5, bid_5.quantity)],
              cont_idx: None,
            },
            purpose_compare,
          )
        |> dict.insert(
            Spend(ibid_6.output_reference),
            Sell {
              exchange_fee: bid_6_fee,
              seller_receive: seller_6_receive,
              offers: [(bond_pid, bond_name_6, bid_6.quantity)],
              cont_idx: None,
            },
            purpose_compare,
          )
        |> dict.insert(
            WithdrawFrom(stake_credential_like(multi_bid_skh)),
            SellMulti { bid_skh },
            purpose_compare,
          ),
      inputs: [
        ibid_1,
        ibid_2,
        ibid_3,
        ibid_4,
        ibid_5,
        ibid_6,
        iseller_1,
        iseller_2,
      ],
      outputs: [
        obuyer_1,
        obuyer_3,
        obuyer_4,
        obuyer_5,
        obuyer_6,
        oseller_1,
        oseller_2,
        ofee,
      ],
    }
  and {
    withdraw.constraint(
      ScriptContext { purpose: Spend(ibid_1.output_reference), transaction: tx },
      cfg,
      bid_skh,
      [script_blacklist],
    ),
    sell.constraint(
      ScriptContext { purpose: Spend(ibid_1.output_reference), transaction: tx },
      multi_bid_skh,
    ),
  }
}

test succ_multiple_sellers_different_bonds() {
  let cfg = get_config_limit_mainnet()
  let fee_addr = cfg.exchange.fee_addr
  expect [(bond_pid, _bond_type)] = dict.values(cfg.escrow)
  let bond_name_1 = "bond_name_1"
  let bond_name_2 = "bond_name_2"
  let ibid_1 =
    Input {
      output_reference: OutputReference(TransactionId("tx_bid_1"), 0),
      output: bid_like(
        yield: 10,
        owner: "owner_1",
        from_epoch: 400,
        to_epoch: 500,
        quantity: 10,
      ),
    }
  let bid_1 = get_bid_datum(ibid_1.output)
  let ibid_2 =
    Input {
      output_reference: OutputReference(TransactionId("tx_bid_2"), 1),
      output: bid_like(
        yield: 10,
        owner: "owner_1",
        from_epoch: 400,
        to_epoch: 500,
        quantity: 10,
      ),
    }
  let bid_2 = get_bid_datum(ibid_2.output)
  let oescrow_1 =
    escrow_like(
      epo_rewards: 1 * ada,
      start: 10,
      duration: 150,
      bond_amount: 100,
      bond_symbol: bond_pid,
      token_name: bond_name_1,
      buffer: 10,
    )
  let oescrow_2 =
    escrow_like(
      epo_rewards: 1 * ada,
      start: 10,
      duration: 150,
      bond_amount: 100,
      bond_symbol: bond_pid,
      token_name: bond_name_2,
      buffer: 10,
    )
  let iseller_1 =
    Input {
      output_reference: OutputReference(TransactionId("tx_seller_1"), 1),
      output: Output {
        value: value.from_lovelace(2 * ada)
          |> value.add(bond_pid, bond_name_1, 50),
        address: from_verification_key("seller_1_pk"),
        datum: NoDatum,
        reference_script: None,
      },
    }
  let iseller_2 =
    Input {
      output_reference: OutputReference(TransactionId("tx_seller_2"), 1),
      output: Output {
        value: value.from_lovelace(2 * ada)
          |> value.add(bond_pid, bond_name_2, 50),
        address: from_verification_key("seller_2_pk"),
        datum: NoDatum,
        reference_script: None,
      },
    }

  let validity_range = entirely_between(1700553367000, 1700553370000)
  expect Finite(now) = validity_range.lower_bound.bound_type
  let (buyer_1_fee, seller_1_fee, seller_1_receive) =
    calculate_fee(
      cfg,
      get_escrow_datum(oescrow_1),
      bid_1.quantity,
      bid_1.requested_yield,
      now,
    )
  let (buyer_2_fee, seller_2_fee, seller_2_receive) =
    calculate_fee(
      cfg,
      get_escrow_datum(oescrow_2),
      bid_2.quantity,
      bid_2.requested_yield,
      now,
    )
  let bid_1_fee = seller_1_fee + buyer_1_fee
  let bid_2_fee = seller_2_fee + buyer_2_fee
  let ofee =
    Output {
      value: value.from_lovelace(bid_1_fee + bid_2_fee),
      address: fee_addr,
      datum: NoDatum,
      reference_script: None,
    }
  let oseller_1 =
    iseller_1.output
      |> add_asset(bond_pid, bond_name_1, -bid_1.quantity)

  let oseller_2 =
    iseller_2.output
      |> add_asset(bond_pid, bond_name_2, -bid_2.quantity)
  let obuyer_1 =
    Output {
      value: value.lovelace_of(ibid_1.output.value) + value.lovelace_of(
        ibid_2.output.value,
      ) - bid_1_fee - bid_2_fee - seller_1_receive - seller_2_receive
        |> value.from_lovelace
        |> value.add(bond_pid, bond_name_2, bid_2.quantity)
        |> value.add(bond_pid, bond_name_1, bid_1.quantity),
      address: get_buyer_address(ibid_1.output),
      datum: NoDatum,
      reference_script: None,
    }
  let t = transaction.placeholder()
  let tx =
    Transaction {
      ..t,
      validity_range: validity_range,
      reference_inputs: [
        Input {
          output_reference: OutputReference(TransactionId("es_01"), 0),
          output: oescrow_1,
        },
        Input {
          output_reference: OutputReference(TransactionId("es_02"), 0),
          output: oescrow_2,
        },
      ],
      redeemers: t.redeemers
        |> dict.insert(
            Spend(ibid_1.output_reference),
            Sell {
              exchange_fee: bid_1_fee,
              seller_receive: seller_1_receive,
              offers: [(bond_pid, bond_name_1, bid_1.quantity)],
              cont_idx: None,
            },
            purpose_compare,
          )
        |> dict.insert(
            Spend(ibid_2.output_reference),
            Sell {
              exchange_fee: bid_2_fee,
              seller_receive: seller_2_receive,
              offers: [(bond_pid, bond_name_2, bid_2.quantity)],
              cont_idx: None,
            },
            purpose_compare,
          )
        |> dict.insert(
            WithdrawFrom(stake_credential_like(multi_bid_skh)),
            SellMulti { bid_skh },
            purpose_compare,
          ),
      inputs: [ibid_1, ibid_2, iseller_1, iseller_2],
      outputs: [obuyer_1, oseller_1, oseller_2, ofee],
    }
  and {
    withdraw.constraint(
      ScriptContext { purpose: Spend(ibid_1.output_reference), transaction: tx },
      cfg,
      bid_skh,
      [script_blacklist],
    ),
    sell.constraint(
      ScriptContext { purpose: Spend(ibid_1.output_reference), transaction: tx },
      multi_bid_skh,
    ),
  }
}

test succ_different_bid_owners() {
  let cfg = get_config_limit_mainnet()
  let fee_addr = cfg.exchange.fee_addr
  expect [(bond_pid, _bond_type)] = dict.values(cfg.escrow)
  let bond_name = "bond_name"
  let ibid_1 =
    Input {
      output_reference: OutputReference(TransactionId("tx_bid_1"), 0),
      output: bid_like(
        yield: 10,
        owner: "owner_1",
        from_epoch: 400,
        to_epoch: 500,
        quantity: 10,
      ),
    }
  let bid_1 = get_bid_datum(ibid_1.output)
  let ibid_2 =
    Input {
      output_reference: OutputReference(TransactionId("tx_bid_2"), 1),
      output: bid_like(
        yield: 10,
        owner: "owner_2",
        from_epoch: 400,
        to_epoch: 500,
        quantity: 10,
      ),
    }
  let bid_2 = get_bid_datum(ibid_2.output)
  let oescrow =
    escrow_like(
      epo_rewards: 1 * ada,
      start: 10,
      duration: 150,
      bond_amount: 100,
      bond_symbol: bond_pid,
      token_name: bond_name,
      buffer: 10,
    )
  let iseller =
    Input {
      output_reference: OutputReference(TransactionId("tx_seller"), 1),
      output: Output {
        value: value.from_lovelace(2 * ada)
          |> value.add(bond_pid, bond_name, 50),
        address: from_verification_key("seller_pk"),
        datum: NoDatum,
        reference_script: None,
      },
    }
  let validity_range = entirely_between(1700553367000, 1700553370000)
  expect Finite(now) = validity_range.lower_bound.bound_type
  let (buyer_1_fee, seller_1_fee, seller_1_receive) =
    calculate_fee(
      cfg,
      get_escrow_datum(oescrow),
      bid_1.quantity,
      bid_1.requested_yield,
      now,
    )
  let (buyer_2_fee, seller_2_fee, seller_2_receive) =
    calculate_fee(
      cfg,
      get_escrow_datum(oescrow),
      bid_2.quantity,
      bid_2.requested_yield,
      now,
    )
  let bid_1_fee = seller_1_fee + buyer_1_fee
  let bid_2_fee = seller_2_fee + buyer_2_fee
  let ofee =
    Output {
      value: value.from_lovelace(bid_1_fee + bid_2_fee),
      address: fee_addr,
      datum: NoDatum,
      reference_script: None,
    }
  let obuyer_1 =
    Output {
      value: value.lovelace_of(ibid_1.output.value) - bid_1_fee - seller_1_receive
        |> value.from_lovelace
        |> value.add(bond_pid, bond_name, bid_1.quantity),
      address: get_buyer_address(ibid_1.output),
      datum: NoDatum,
      reference_script: None,
    }
  let obuyer_2 =
    Output {
      value: value.lovelace_of(ibid_2.output.value) - bid_2_fee - seller_2_receive
        |> value.from_lovelace
        |> value.add(bond_pid, bond_name, bid_2.quantity),
      address: get_buyer_address(ibid_2.output),
      datum: NoDatum,
      reference_script: None,
    }
  let oseller =
    iseller.output
      |> add_asset(
          ada_policy_id,
          ada_asset_name,
          seller_2_receive + seller_1_receive - seller_1_fee - seller_2_fee,
        )
      |> add_asset(bond_pid, bond_name, -bid_1.quantity - bid_2.quantity)
  let t = transaction.placeholder()
  let tx =
    Transaction {
      ..t,
      validity_range: validity_range,
      reference_inputs: [
        Input {
          output_reference: OutputReference(TransactionId("es_01"), 0),
          output: oescrow,
        },
      ],
      redeemers: t.redeemers
        |> dict.insert(
            Spend(ibid_1.output_reference),
            Sell {
              exchange_fee: bid_1_fee,
              seller_receive: seller_1_receive,
              offers: [(bond_pid, bond_name, bid_1.quantity)],
              cont_idx: None,
            },
            purpose_compare,
          )
        |> dict.insert(
            Spend(ibid_2.output_reference),
            Sell {
              exchange_fee: bid_2_fee,
              seller_receive: seller_2_receive,
              offers: [(bond_pid, bond_name, bid_2.quantity)],
              cont_idx: None,
            },
            purpose_compare,
          )
        |> dict.insert(
            WithdrawFrom(stake_credential_like(multi_bid_skh)),
            SellMulti { bid_skh },
            purpose_compare,
          ),
      inputs: [ibid_1, ibid_2, iseller],
      outputs: [obuyer_1, obuyer_2, oseller, ofee],
    }
  and {
    withdraw.constraint(
      ScriptContext { purpose: Spend(ibid_1.output_reference), transaction: tx },
      cfg,
      bid_skh,
      [script_blacklist],
    ),
    sell.constraint(
      ScriptContext { purpose: Spend(ibid_1.output_reference), transaction: tx },
      multi_bid_skh,
    ),
  }
}

test succ_spending_partially_and_fully() {
  let cfg = get_config_limit_mainnet()
  let fee_addr = cfg.exchange.fee_addr
  expect [(bond_pid, _bond_type)] = dict.values(cfg.escrow)
  let bond_name = "bond_name"
  let ibid_1 =
    Input {
      output_reference: OutputReference(TransactionId("tx_bid_1"), 0),
      output: bid_like(
        yield: 10,
        owner: "owner_1",
        from_epoch: 400,
        to_epoch: 500,
        quantity: 10,
      ),
    }
  let bond_sell_qty_1 = 2
  let bid_1 = get_bid_datum(ibid_1.output)
  let ibid_2 =
    Input {
      output_reference: OutputReference(TransactionId("tx_bid_2"), 1),
      output: bid_like(
        yield: 10,
        owner: "owner_1",
        from_epoch: 400,
        to_epoch: 500,
        quantity: 10,
      ),
    }
  let bid_2 = get_bid_datum(ibid_2.output)
  let oescrow =
    escrow_like(
      epo_rewards: 1 * ada,
      start: 10,
      duration: 150,
      bond_amount: 100,
      bond_symbol: bond_pid,
      token_name: bond_name,
      buffer: 10,
    )
  let iseller =
    Input {
      output_reference: OutputReference(TransactionId("tx_seller"), 1),
      output: Output {
        value: value.from_lovelace(2 * ada)
          |> value.add(bond_pid, bond_name, 50),
        address: from_verification_key("seller_pk"),
        datum: NoDatum,
        reference_script: None,
      },
    }
  let validity_range = entirely_between(1700553367000, 1700553370000)
  expect Finite(now) = validity_range.lower_bound.bound_type
  let (buyer_1_fee, seller_1_fee, seller_1_receive) =
    calculate_fee(
      cfg,
      get_escrow_datum(oescrow),
      bond_sell_qty_1,
      bid_1.requested_yield,
      now,
    )
  let (buyer_2_fee, seller_2_fee, seller_2_receive) =
    calculate_fee(
      cfg,
      get_escrow_datum(oescrow),
      bid_2.quantity,
      bid_2.requested_yield,
      now,
    )
  let bid_1_fee = seller_1_fee + buyer_1_fee
  let bid_2_fee = seller_2_fee + buyer_2_fee
  let ofee =
    Output {
      value: value.from_lovelace(bid_1_fee + bid_2_fee),
      address: fee_addr,
      datum: NoDatum,
      reference_script: None,
    }
  let obid_1 =
    bid_like(
      yield: 10,
      owner: "owner_1",
      from_epoch: 400,
      to_epoch: 500,
      quantity: bid_1.quantity - bond_sell_qty_1,
    )
  let obuyer_1 =
    Output {
      value: value.lovelace_of(ibid_1.output.value) + value.lovelace_of(
        ibid_2.output.value,
      ) - value.lovelace_of(obid_1.value) - bid_1_fee - bid_2_fee - seller_1_receive - seller_2_receive
        |> value.from_lovelace
        |> value.add(bond_pid, bond_name, bond_sell_qty_1)
        |> value.add(bond_pid, bond_name, bid_2.quantity),
      address: get_buyer_address(ibid_1.output),
      datum: NoDatum,
      reference_script: None,
    }
  let oseller =
    iseller.output
      |> add_asset(
          ada_policy_id,
          ada_asset_name,
          seller_2_receive + seller_1_receive - seller_1_fee - seller_2_fee,
        )
      |> add_asset(bond_pid, bond_name, -bond_sell_qty_1 - bid_2.quantity)
  let t = transaction.placeholder()
  let tx =
    Transaction {
      ..t,
      validity_range: validity_range,
      reference_inputs: [
        Input {
          output_reference: OutputReference(TransactionId("es_01"), 0),
          output: oescrow,
        },
      ],
      redeemers: t.redeemers
        |> dict.insert(
            Spend(ibid_1.output_reference),
            Sell {
              exchange_fee: bid_1_fee,
              seller_receive: seller_1_receive,
              offers: [(bond_pid, bond_name, bond_sell_qty_1)],
              cont_idx: Some(3),
            },
            purpose_compare,
          )
        |> dict.insert(
            Spend(ibid_2.output_reference),
            Sell {
              exchange_fee: bid_2_fee,
              seller_receive: seller_2_receive,
              offers: [(bond_pid, bond_name, bid_2.quantity)],
              cont_idx: None,
            },
            purpose_compare,
          )
        |> dict.insert(
            WithdrawFrom(stake_credential_like(multi_bid_skh)),
            SellMulti { bid_skh },
            purpose_compare,
          ),
      inputs: [ibid_1, ibid_2, iseller],
      outputs: [obuyer_1, oseller, ofee, obid_1],
    }
  and {
    withdraw.constraint(
      ScriptContext { purpose: Spend(ibid_1.output_reference), transaction: tx },
      cfg,
      bid_skh,
      [script_blacklist],
    ),
    sell.constraint(
      ScriptContext { purpose: Spend(ibid_1.output_reference), transaction: tx },
      multi_bid_skh,
    ),
  }
}

test succ_spending_partially() {
  let cfg = get_config_limit_mainnet()
  let fee_addr = cfg.exchange.fee_addr
  expect [(bond_pid, _bond_type)] = dict.values(cfg.escrow)
  let bond_name = "bond_name"
  let ibid_1 =
    Input {
      output_reference: OutputReference(TransactionId("tx_bid_1"), 0),
      output: bid_like(
        yield: 10,
        owner: "owner_1",
        from_epoch: 400,
        to_epoch: 500,
        quantity: 10,
      ),
    }
  let bond_sell_qty_1 = 2
  let bid_1 = get_bid_datum(ibid_1.output)
  let ibid_2 =
    Input {
      output_reference: OutputReference(TransactionId("tx_bid_2"), 1),
      output: bid_like(
        yield: 10,
        owner: "owner_1",
        from_epoch: 400,
        to_epoch: 500,
        quantity: 10,
      ),
    }
  let bond_sell_qty_2 = 2
  let bid_2 = get_bid_datum(ibid_2.output)
  let obid_1_remain =
    Input {
      output_reference: OutputReference(TransactionId("tx_bid_1"), 0),
      output: bid_like(
        yield: 10,
        owner: "owner_1",
        from_epoch: 400,
        to_epoch: 500,
        quantity: bid_1.quantity - bond_sell_qty_1,
      ),
    }
  let obid_2_remain =
    Input {
      output_reference: OutputReference(TransactionId("tx_bid_2"), 1),
      output: bid_like(
        yield: 10,
        owner: "owner_1",
        from_epoch: 400,
        to_epoch: 500,
        quantity: bid_2.quantity - bond_sell_qty_2,
      ),
    }
  let oescrow =
    escrow_like(
      epo_rewards: 1 * ada,
      start: 10,
      duration: 150,
      bond_amount: 100,
      bond_symbol: bond_pid,
      token_name: bond_name,
      buffer: 10,
    )
  let iseller =
    Input {
      output_reference: OutputReference(TransactionId("tx_seller"), 1),
      output: Output {
        value: value.from_lovelace(2 * ada)
          |> value.add(bond_pid, bond_name, 50),
        address: from_verification_key("seller_pk"),
        datum: NoDatum,
        reference_script: None,
      },
    }

  let validity_range = entirely_between(1700553367000, 1700553370000)
  expect Finite(now) = validity_range.lower_bound.bound_type
  let (buyer_1_fee, seller_1_fee, seller_1_receive) =
    calculate_fee(
      cfg,
      get_escrow_datum(oescrow),
      bond_sell_qty_1,
      bid_1.requested_yield,
      now,
    )
  let (buyer_2_fee, seller_2_fee, seller_2_receive) =
    calculate_fee(
      cfg,
      get_escrow_datum(oescrow),
      bond_sell_qty_2,
      bid_2.requested_yield,
      now,
    )
  let bid_1_fee = seller_1_fee + buyer_1_fee
  let bid_2_fee = seller_2_fee + buyer_2_fee
  let ofee =
    Output {
      value: value.from_lovelace(bid_1_fee + bid_2_fee),
      address: fee_addr,
      datum: NoDatum,
      reference_script: None,
    }
  let obuyer_1 =
    Output {
      value: value.lovelace_of(ibid_1.output.value) + value.lovelace_of(
        ibid_2.output.value,
      ) - value.lovelace_of(obid_1_remain.output.value) - value.lovelace_of(
        obid_2_remain.output.value,
      ) - bid_1_fee - bid_2_fee - seller_1_receive - seller_2_receive
        |> value.from_lovelace
        |> value.add(bond_pid, bond_name, bond_sell_qty_1)
        |> value.add(bond_pid, bond_name, bond_sell_qty_2),
      address: get_buyer_address(ibid_1.output),
      datum: NoDatum,
      reference_script: None,
    }

  let obid_1 = obid_1_remain.output
  let obid_2 = obid_2_remain.output
  let oseller =
    iseller.output
      |> add_asset(
          ada_policy_id,
          ada_asset_name,
          seller_2_receive + seller_1_receive - seller_1_fee - seller_2_fee,
        )
      |> add_asset(bond_pid, bond_name, -bond_sell_qty_1 - bond_sell_qty_2)

  let t = transaction.placeholder()
  let tx =
    Transaction {
      ..t,
      validity_range: validity_range,
      reference_inputs: [
        Input {
          output_reference: OutputReference(TransactionId("es_01"), 0),
          output: oescrow,
        },
      ],
      redeemers: t.redeemers
        |> dict.insert(
            Spend(ibid_1.output_reference),
            Sell {
              exchange_fee: bid_1_fee,
              seller_receive: seller_1_receive,
              offers: [(bond_pid, bond_name, bond_sell_qty_1)],
              cont_idx: Some(3),
            },
            purpose_compare,
          )
        |> dict.insert(
            Spend(ibid_2.output_reference),
            Sell {
              exchange_fee: bid_2_fee,
              seller_receive: seller_2_receive,
              offers: [(bond_pid, bond_name, bond_sell_qty_2)],
              cont_idx: Some(4),
            },
            purpose_compare,
          )
        |> dict.insert(
            WithdrawFrom(stake_credential_like(multi_bid_skh)),
            SellMulti { bid_skh },
            purpose_compare,
          ),
      inputs: [ibid_1, ibid_2, iseller],
      outputs: [obuyer_1, oseller, ofee, obid_1, obid_2],
    }
  and {
    withdraw.constraint(
      ScriptContext { purpose: Spend(ibid_1.output_reference), transaction: tx },
      cfg,
      bid_skh,
      [script_blacklist],
    ),
    sell.constraint(
      ScriptContext { purpose: Spend(ibid_1.output_reference), transaction: tx },
      multi_bid_skh,
    ),
  }
}

test fail_when_wrong_stake_credential_bid_output() fail {
  let cfg = get_config_limit_mainnet()
  let fee_addr = cfg.exchange.fee_addr
  expect [(bond_pid, _bond_type)] = dict.values(cfg.escrow)
  let bond_name = "bond_name"
  let output_bid_1 =
    bid_like(
      yield: 10,
      owner: "owner_1",
      from_epoch: 400,
      to_epoch: 500,
      quantity: 10,
    )
  let ibid_1 =
    Input {
      output_reference: OutputReference(TransactionId("tx_bid_1"), 0),
      output: Output {
        ..output_bid_1,
        address: output_bid_1.address |> with_delegation_key("bid_1"),
      },
    }
  let bond_sell_qty_1 = 2
  let bid_1 = get_bid_datum(ibid_1.output)
  let ibid_2 =
    Input {
      output_reference: OutputReference(TransactionId("tx_bid_2"), 1),
      output: bid_like(
        yield: 10,
        owner: "owner_1",
        from_epoch: 400,
        to_epoch: 500,
        quantity: 10,
      ),
    }
  let bond_sell_qty_2 = 2
  let bid_2 = get_bid_datum(ibid_2.output)
  let obid_1_remain_output =
    bid_like(
      yield: 10,
      owner: "owner_1",
      from_epoch: 400,
      to_epoch: 500,
      quantity: bid_1.quantity - bond_sell_qty_1,
    )
  let obid_1_remain =
    Input {
      output_reference: OutputReference(TransactionId("tx_bid_1"), 0),
      output: Output {
        ..obid_1_remain_output,
        address: obid_1_remain_output.address
          |> with_delegation_key("bid_1_fake"),
      },
    }
  let obid_2_remain =
    Input {
      output_reference: OutputReference(TransactionId("tx_bid_2"), 1),
      output: bid_like(
        yield: 10,
        owner: "owner_1",
        from_epoch: 400,
        to_epoch: 500,
        quantity: bid_2.quantity - bond_sell_qty_2,
      ),
    }
  let oescrow =
    escrow_like(
      epo_rewards: 1 * ada,
      start: 10,
      duration: 150,
      bond_amount: 100,
      bond_symbol: bond_pid,
      token_name: bond_name,
      buffer: 10,
    )
  let iseller =
    Input {
      output_reference: OutputReference(TransactionId("tx_seller"), 1),
      output: Output {
        value: value.from_lovelace(2 * ada)
          |> value.add(bond_pid, bond_name, 50),
        address: from_verification_key("seller_pk"),
        datum: NoDatum,
        reference_script: None,
      },
    }

  let validity_range = entirely_between(1700553367000, 1700553370000)
  expect Finite(now) = validity_range.lower_bound.bound_type
  let (buyer_1_fee, seller_1_fee, seller_1_receive) =
    calculate_fee(
      cfg,
      get_escrow_datum(oescrow),
      bond_sell_qty_1,
      bid_1.requested_yield,
      now,
    )
  let (buyer_2_fee, seller_2_fee, seller_2_receive) =
    calculate_fee(
      cfg,
      get_escrow_datum(oescrow),
      bond_sell_qty_2,
      bid_2.requested_yield,
      now,
    )
  let bid_1_fee = seller_1_fee + buyer_1_fee
  let bid_2_fee = seller_2_fee + buyer_2_fee
  let ofee =
    Output {
      value: value.from_lovelace(bid_1_fee + bid_2_fee),
      address: fee_addr,
      datum: NoDatum,
      reference_script: None,
    }
  let obuyer_1 =
    Output {
      value: value.lovelace_of(ibid_1.output.value) + value.lovelace_of(
        ibid_2.output.value,
      ) - value.lovelace_of(obid_1_remain.output.value) - value.lovelace_of(
        obid_2_remain.output.value,
      ) - bid_1_fee - bid_2_fee - seller_1_receive - seller_2_receive
        |> value.from_lovelace
        |> value.add(bond_pid, bond_name, bond_sell_qty_1)
        |> value.add(bond_pid, bond_name, bond_sell_qty_2),
      address: get_buyer_address(ibid_1.output),
      datum: NoDatum,
      reference_script: None,
    }

  let obid_1 = obid_1_remain.output
  let obid_2 = obid_2_remain.output
  let oseller =
    iseller.output
      |> add_asset(
          ada_policy_id,
          ada_asset_name,
          seller_2_receive + seller_1_receive - seller_1_fee - seller_2_fee,
        )
      |> add_asset(bond_pid, bond_name, -bond_sell_qty_1 - bond_sell_qty_2)

  let t = transaction.placeholder()
  let tx =
    Transaction {
      ..t,
      validity_range: validity_range,
      reference_inputs: [
        Input {
          output_reference: OutputReference(TransactionId("es_01"), 0),
          output: oescrow,
        },
      ],
      redeemers: t.redeemers
        |> dict.insert(
            Spend(ibid_1.output_reference),
            Sell {
              exchange_fee: bid_1_fee,
              seller_receive: seller_1_receive,
              offers: [(bond_pid, bond_name, bond_sell_qty_1)],
              cont_idx: Some(3),
            },
            purpose_compare,
          )
        |> dict.insert(
            Spend(ibid_2.output_reference),
            Sell {
              exchange_fee: bid_2_fee,
              seller_receive: seller_2_receive,
              offers: [(bond_pid, bond_name, bond_sell_qty_2)],
              cont_idx: Some(4),
            },
            purpose_compare,
          )
        |> dict.insert(
            WithdrawFrom(stake_credential_like(multi_bid_skh)),
            SellMulti { bid_skh },
            purpose_compare,
          ),
      inputs: [ibid_1, ibid_2, iseller],
      outputs: [obuyer_1, oseller, ofee, obid_1, obid_2],
    }
  and {
    !withdraw.constraint(
      ScriptContext { purpose: Spend(ibid_1.output_reference), transaction: tx },
      cfg,
      bid_skh,
      [script_blacklist],
    ),
    sell.constraint(
      ScriptContext { purpose: Spend(ibid_1.output_reference), transaction: tx },
      multi_bid_skh,
    ),
  }
}

test fail_doesnt_pay_enough_fee() fail {
  let cfg = get_config_limit_mainnet()
  let fee_addr = cfg.exchange.fee_addr
  expect [(bond_pid, _bond_type)] = dict.values(cfg.escrow)
  let bond_name_1 = "bond_name_1"
  let bond_name_2 = "bond_name_2"

  let ibid_1 =
    Input {
      output_reference: OutputReference(TransactionId("tx_bid_1"), 0),
      output: bid_like(
        yield: 10,
        owner: "owner_1",
        from_epoch: 400,
        to_epoch: 500,
        quantity: 10,
      ),
    }
  let bid_1 = get_bid_datum(ibid_1.output)
  let ibid_2 =
    Input {
      output_reference: OutputReference(TransactionId("tx_bid_2"), 1),
      output: bid_like(
        yield: 10,
        owner: "owner_1",
        from_epoch: 400,
        to_epoch: 500,
        quantity: 10,
      ),
    }
  let bid_2 = get_bid_datum(ibid_2.output)
  let oescrow_1 =
    escrow_like(
      epo_rewards: 1 * ada,
      start: 10,
      duration: 150,
      bond_amount: 100,
      bond_symbol: bond_pid,
      token_name: bond_name_1,
      buffer: 10,
    )
  let oescrow_2 =
    escrow_like(
      epo_rewards: 1 * ada,
      start: 10,
      duration: 150,
      bond_amount: 100,
      bond_symbol: bond_pid,
      token_name: bond_name_2,
      buffer: 10,
    )
  let iseller =
    Input {
      output_reference: OutputReference(TransactionId("tx_seller"), 1),
      output: Output {
        value: value.from_lovelace(2 * ada)
          |> value.add(bond_pid, bond_name_1, 10)
          |> value.add(bond_pid, bond_name_2, 10),
        address: from_verification_key("seller_pk"),
        datum: NoDatum,
        reference_script: None,
      },
    }

  let validity_range = entirely_between(1700553367000, 1700553370000)
  expect Finite(now) = validity_range.lower_bound.bound_type
  let (buyer_1_fee, seller_1_fee, seller_1_receive) =
    calculate_fee(
      cfg,
      get_escrow_datum(oescrow_1),
      bid_1.quantity,
      bid_1.requested_yield,
      now,
    )
  let (buyer_2_fee, seller_2_fee, seller_2_receive) =
    calculate_fee(
      cfg,
      get_escrow_datum(oescrow_2),
      bid_2.quantity,
      bid_2.requested_yield,
      now,
    )
  let bid_1_fee = seller_1_fee + buyer_1_fee - 100
  let bid_2_fee = seller_2_fee + buyer_2_fee - 100
  let ofee =
    Output {
      value: value.from_lovelace(bid_1_fee + bid_2_fee),
      address: fee_addr,
      datum: NoDatum,
      reference_script: None,
    }
  let obuyer_1 =
    Output {
      value: value.lovelace_of(ibid_1.output.value) + value.lovelace_of(
        ibid_2.output.value,
      ) - bid_1_fee - bid_2_fee - seller_1_receive - seller_2_receive
        |> value.from_lovelace
        |> value.add(bond_pid, bond_name_1, bid_1.quantity)
        |> value.add(bond_pid, bond_name_2, bid_2.quantity),
      address: get_buyer_address(ibid_1.output),
      datum: NoDatum,
      reference_script: None,
    }
  let oseller =
    iseller.output
      |> add_asset(
          ada_policy_id,
          ada_asset_name,
          seller_2_receive + seller_1_receive - seller_1_fee - seller_2_fee,
        )
      |> add_asset(bond_pid, bond_name_1, -bid_1.quantity)
      |> add_asset(bond_pid, bond_name_2, -bid_2.quantity)
  let t = transaction.placeholder()
  let tx =
    Transaction {
      ..t,
      validity_range: validity_range,
      reference_inputs: [
        Input {
          output_reference: OutputReference(TransactionId("es_01"), 0),
          output: oescrow_1,
        },
        Input {
          output_reference: OutputReference(TransactionId("es_02"), 1),
          output: oescrow_2,
        },
      ],
      redeemers: t.redeemers
        |> dict.insert(
            Spend(ibid_1.output_reference),
            Sell {
              exchange_fee: bid_1_fee,
              seller_receive: seller_1_receive,
              offers: [(bond_pid, bond_name_1, bid_1.quantity)],
              cont_idx: None,
            },
            purpose_compare,
          )
        |> dict.insert(
            Spend(ibid_2.output_reference),
            Sell {
              exchange_fee: bid_2_fee,
              seller_receive: seller_2_receive,
              offers: [(bond_pid, bond_name_2, bid_2.quantity)],
              cont_idx: None,
            },
            purpose_compare,
          ),
      inputs: [ibid_1, ibid_2, iseller],
      outputs: [obuyer_1, ofee, oseller],
    }
  withdraw.constraint(
    ScriptContext { purpose: Spend(ibid_1.output_reference), transaction: tx },
    cfg,
    bid_skh,
    [script_blacklist],
  )
}

test fail_buyer_doesnt_receive_enough_bond_tokens() fail {
  let cfg = get_config_limit_mainnet()
  let fee_addr = cfg.exchange.fee_addr
  expect [(bond_pid, _bond_type)] = dict.values(cfg.escrow)
  let bond_name = "bond_name"
  let ibid_1 =
    Input {
      output_reference: OutputReference(TransactionId("tx_bid_1"), 0),
      output: bid_like(
        yield: 10,
        owner: "owner_1",
        from_epoch: 400,
        to_epoch: 500,
        quantity: 10,
      ),
    }
  let bid_1 = get_bid_datum(ibid_1.output)
  let ibid_2 =
    Input {
      output_reference: OutputReference(TransactionId("tx_bid_2"), 1),
      output: bid_like(
        yield: 10,
        owner: "owner_1",
        from_epoch: 400,
        to_epoch: 500,
        quantity: 10,
      ),
    }
  let bid_2 = get_bid_datum(ibid_2.output)
  let oescrow =
    escrow_like(
      epo_rewards: 1 * ada,
      start: 10,
      duration: 150,
      bond_amount: 100,
      bond_symbol: bond_pid,
      token_name: bond_name,
      buffer: 10,
    )
  let iseller =
    Input {
      output_reference: OutputReference(TransactionId("tx_seller"), 1),
      output: Output {
        value: value.from_lovelace(2 * ada)
          |> value.add(bond_pid, bond_name, 50),
        address: from_verification_key("seller_pk"),
        datum: NoDatum,
        reference_script: None,
      },
    }
  let validity_range = entirely_between(1700553367000, 1700553370000)
  expect Finite(now) = validity_range.lower_bound.bound_type
  let (buyer_1_fee, seller_1_fee, seller_1_receive) =
    calculate_fee(
      cfg,
      get_escrow_datum(oescrow),
      bid_1.quantity,
      bid_1.requested_yield,
      now,
    )
  let (buyer_2_fee, seller_2_fee, seller_2_receive) =
    calculate_fee(
      cfg,
      get_escrow_datum(oescrow),
      bid_2.quantity,
      bid_2.requested_yield,
      now,
    )
  let bid_1_fee = seller_1_fee + buyer_1_fee
  let bid_2_fee = seller_2_fee + buyer_2_fee
  let ofee =
    Output {
      value: value.from_lovelace(bid_1_fee + bid_2_fee),
      address: fee_addr,
      datum: NoDatum,
      reference_script: None,
    }
  let oseller =
    iseller.output
      |> add_asset(
          ada_policy_id,
          ada_asset_name,
          seller_2_receive + seller_1_receive - seller_1_fee - seller_2_fee,
        )
      |> add_asset(bond_pid, bond_name, -bid_1.quantity - bid_2.quantity)
  let obuyer_1 =
    Output {
      value: value.lovelace_of(ibid_1.output.value) + value.lovelace_of(
        ibid_2.output.value,
      ) - bid_1_fee - bid_2_fee - seller_1_receive - seller_2_receive
        |> value.from_lovelace
        |> value.add(bond_pid, bond_name, bid_2.quantity)
        |> value.add(bond_pid, bond_name, bid_1.quantity - 1),
      address: get_buyer_address(ibid_1.output),
      datum: NoDatum,
      reference_script: None,
    }
  let t = transaction.placeholder()
  let tx =
    Transaction {
      ..t,
      validity_range: validity_range,
      reference_inputs: [
        Input {
          output_reference: OutputReference(TransactionId("es_01"), 0),
          output: oescrow,
        },
      ],
      redeemers: t.redeemers
        |> dict.insert(
            Spend(ibid_1.output_reference),
            Sell {
              exchange_fee: bid_1_fee,
              seller_receive: seller_1_receive,
              offers: [(bond_pid, bond_name, bid_1.quantity)],
              cont_idx: None,
            },
            purpose_compare,
          )
        |> dict.insert(
            Spend(ibid_2.output_reference),
            Sell {
              exchange_fee: bid_2_fee,
              seller_receive: seller_2_receive,
              offers: [(bond_pid, bond_name, bid_2.quantity)],
              cont_idx: None,
            },
            purpose_compare,
          ),
      inputs: [ibid_1, ibid_2, iseller],
      outputs: [obuyer_1, oseller, ofee],
    }
  withdraw.constraint(
    ScriptContext { purpose: Spend(ibid_1.output_reference), transaction: tx },
    cfg,
    bid_skh,
    [script_blacklist],
  )
}

test fail_attempting_double_sastification_1() fail {
  let cfg = get_config_limit_mainnet()
  let fee_addr = cfg.exchange.fee_addr
  expect [(bond_pid, _bond_type)] = dict.values(cfg.escrow)
  let bond_name = "bond_name"
  let ibid_1 =
    Input {
      output_reference: OutputReference(TransactionId("tx_bid_1"), 0),
      output: bid_like(
        yield: 10,
        owner: "owner_1",
        from_epoch: 400,
        to_epoch: 500,
        quantity: 10,
      ),
    }
  let bid_1 = get_bid_datum(ibid_1.output)
  let ibid_2 =
    Input {
      output_reference: OutputReference(TransactionId("tx_bid_2"), 1),
      output: bid_like(
        yield: 10,
        owner: "owner_1",
        from_epoch: 400,
        to_epoch: 500,
        quantity: 10,
      ),
    }
  let bid_2 = get_bid_datum(ibid_2.output)
  let oescrow =
    escrow_like(
      epo_rewards: 1 * ada,
      start: 10,
      duration: 150,
      bond_amount: 100,
      bond_symbol: bond_pid,
      token_name: bond_name,
      buffer: 10,
    )
  let iseller =
    Input {
      output_reference: OutputReference(TransactionId("tx_seller"), 1),
      output: Output {
        value: value.from_lovelace(2 * ada)
          |> value.add(bond_pid, bond_name, 50),
        address: from_verification_key("seller_pk"),
        datum: NoDatum,
        reference_script: None,
      },
    }

  let validity_range = entirely_between(1700553367000, 1700553370000)
  expect Finite(now) = validity_range.lower_bound.bound_type
  let (buyer_1_fee, seller_1_fee, seller_1_receive) =
    calculate_fee(
      cfg,
      get_escrow_datum(oescrow),
      bid_1.quantity,
      bid_1.requested_yield,
      now,
    )
  let (buyer_2_fee, seller_2_fee, seller_2_receive) =
    calculate_fee(
      cfg,
      get_escrow_datum(oescrow),
      bid_2.quantity,
      bid_2.requested_yield,
      now,
    )
  let bid_1_fee = seller_1_fee + buyer_1_fee
  let bid_2_fee = seller_2_fee + buyer_2_fee
  let seller_1_receive_modified = seller_1_receive - 1_000
  let ofee =
    Output {
      value: value.from_lovelace(bid_1_fee + bid_2_fee),
      address: fee_addr,
      datum: NoDatum,
      reference_script: None,
    }
  let obuyer_1 =
    Output {
      value: value.lovelace_of(ibid_1.output.value) + value.lovelace_of(
        ibid_2.output.value,
      ) - bid_1_fee - bid_2_fee - seller_1_receive - seller_2_receive
        |> value.from_lovelace
        |> value.add(bond_pid, bond_name, bid_1.quantity)
        |> value.add(bond_pid, bond_name, bid_2.quantity),
      address: get_buyer_address(ibid_1.output),
      datum: NoDatum,
      reference_script: None,
    }
  let oseller =
    iseller.output
      |> add_asset(
          ada_policy_id,
          ada_asset_name,
          seller_2_receive + seller_1_receive - seller_1_fee - seller_2_fee,
        )
      |> add_asset(bond_pid, bond_name, -bid_1.quantity - bid_2.quantity)
  let t = transaction.placeholder()
  let tx =
    Transaction {
      ..t,
      validity_range: validity_range,
      reference_inputs: [
        Input {
          output_reference: OutputReference(TransactionId("es_01"), 0),
          output: oescrow,
        },
      ],
      redeemers: t.redeemers
        |> dict.insert(
            Spend(ibid_1.output_reference),
            Sell {
              exchange_fee: bid_1_fee,
              seller_receive: seller_1_receive_modified,
              offers: [(bond_pid, bond_name, bid_1.quantity)],
              cont_idx: None,
            },
            purpose_compare,
          )
        |> dict.insert(
            Spend(ibid_2.output_reference),
            Sell {
              exchange_fee: bid_2_fee,
              seller_receive: seller_2_receive,
              offers: [(bond_pid, bond_name, bid_2.quantity)],
              cont_idx: None,
            },
            purpose_compare,
          ),
      inputs: [ibid_1, ibid_2, iseller],
      outputs: [obuyer_1, oseller, ofee],
    }
  withdraw.constraint(
    ScriptContext { purpose: Spend(ibid_1.output_reference), transaction: tx },
    cfg,
    bid_skh,
    [script_blacklist],
  )
}

test fail_attempting_double_sastification_2() fail {
  let cfg = get_config_limit_mainnet()
  let fee_addr = cfg.exchange.fee_addr
  expect [(bond_pid, _bond_type)] = dict.values(cfg.escrow)
  let bond_name = "bond_name"
  let ibid_1 =
    Input {
      output_reference: OutputReference(TransactionId("tx_bid_1"), 0),
      output: bid_like(
        yield: 10,
        owner: "owner_1",
        from_epoch: 400,
        to_epoch: 500,
        quantity: 10,
      ),
    }
  let bid_1 = get_bid_datum(ibid_1.output)
  let ibid_2 =
    Input {
      output_reference: OutputReference(TransactionId("tx_bid_2"), 1),
      output: bid_like(
        yield: 10,
        owner: "owner_1",
        from_epoch: 400,
        to_epoch: 500,
        quantity: 10,
      ),
    }
  let bid_2 = get_bid_datum(ibid_2.output)
  let oescrow =
    escrow_like(
      epo_rewards: 1 * ada,
      start: 10,
      duration: 150,
      bond_amount: 100,
      bond_symbol: bond_pid,
      token_name: bond_name,
      buffer: 10,
    )
  let iseller =
    Input {
      output_reference: OutputReference(TransactionId("tx_seller"), 1),
      output: Output {
        value: value.from_lovelace(2 * ada)
          |> value.add(bond_pid, bond_name, 50),
        address: from_verification_key("seller_pk"),
        datum: NoDatum,
        reference_script: None,
      },
    }

  let validity_range = entirely_between(1700553367000, 1700553370000)
  expect Finite(now) = validity_range.lower_bound.bound_type
  let (buyer_1_fee, seller_1_fee, seller_1_receive) =
    calculate_fee(
      cfg,
      get_escrow_datum(oescrow),
      bid_1.quantity,
      bid_1.requested_yield,
      now,
    )
  let (buyer_2_fee, seller_2_fee, seller_2_receive) =
    calculate_fee(
      cfg,
      get_escrow_datum(oescrow),
      bid_2.quantity,
      bid_2.requested_yield,
      now,
    )
  let bid_1_fee = seller_1_fee + buyer_1_fee
  let bid_2_fee = seller_2_fee + buyer_2_fee
  let seller_2_receive_modified = seller_2_receive - 1_000
  let ofee =
    Output {
      value: value.from_lovelace(bid_1_fee + bid_2_fee),
      address: fee_addr,
      datum: NoDatum,
      reference_script: None,
    }
  let obuyer_1 =
    Output {
      value: value.lovelace_of(ibid_1.output.value) + value.lovelace_of(
        ibid_2.output.value,
      ) - bid_1_fee - bid_2_fee - seller_1_receive - seller_2_receive_modified
        |> value.from_lovelace
        |> value.add(bond_pid, bond_name, bid_1.quantity)
        |> value.add(bond_pid, bond_name, bid_2.quantity),
      address: get_buyer_address(ibid_1.output),
      datum: NoDatum,
      reference_script: None,
    }
  let oseller =
    iseller.output
      |> add_asset(
          ada_policy_id,
          ada_asset_name,
          seller_2_receive_modified + seller_1_receive - seller_1_fee - seller_2_fee,
        )
      |> add_asset(bond_pid, bond_name, -bid_1.quantity - bid_2.quantity)
  let t = transaction.placeholder()
  let tx =
    Transaction {
      ..t,
      validity_range: validity_range,
      reference_inputs: [
        Input {
          output_reference: OutputReference(TransactionId("es_01"), 0),
          output: oescrow,
        },
      ],
      redeemers: t.redeemers
        |> dict.insert(
            Spend(ibid_1.output_reference),
            Sell {
              exchange_fee: bid_1_fee,
              seller_receive: seller_1_receive,
              offers: [(bond_pid, bond_name, bid_1.quantity)],
              cont_idx: None,
            },
            purpose_compare,
          )
        |> dict.insert(
            Spend(ibid_2.output_reference),
            Sell {
              exchange_fee: bid_2_fee,
              seller_receive: seller_2_receive_modified,
              offers: [(bond_pid, bond_name, bid_2.quantity)],
              cont_idx: None,
            },
            purpose_compare,
          ),
      inputs: [ibid_1, ibid_2, iseller],
      outputs: [obuyer_1, oseller, ofee],
    }
  withdraw.constraint(
    ScriptContext { purpose: Spend(ibid_1.output_reference), transaction: tx },
    cfg,
    bid_skh,
    [script_blacklist],
  )
}

test fail_invalid_redeemer_seller_receive() fail {
  let cfg = get_config_limit_mainnet()
  let fee_addr = cfg.exchange.fee_addr
  expect [(bond_pid, _bond_type)] = dict.values(cfg.escrow)
  let bond_name = "bond_name"
  let ibid_1 =
    Input {
      output_reference: OutputReference(TransactionId("tx_bid_1"), 0),
      output: bid_like(
        yield: 10,
        owner: "owner_1",
        from_epoch: 400,
        to_epoch: 500,
        quantity: 10,
      ),
    }
  let bid_1 = get_bid_datum(ibid_1.output)
  let ibid_2 =
    Input {
      output_reference: OutputReference(TransactionId("tx_bid_2"), 1),
      output: bid_like(
        yield: 10,
        owner: "owner_1",
        from_epoch: 400,
        to_epoch: 500,
        quantity: 10,
      ),
    }
  let bid_2 = get_bid_datum(ibid_2.output)
  let oescrow =
    escrow_like(
      epo_rewards: 1 * ada,
      start: 10,
      duration: 150,
      bond_amount: 100,
      bond_symbol: bond_pid,
      token_name: bond_name,
      buffer: 10,
    )
  let iseller =
    Input {
      output_reference: OutputReference(TransactionId("tx_seller"), 1),
      output: Output {
        value: value.from_lovelace(2 * ada)
          |> value.add(bond_pid, bond_name, 50),
        address: from_verification_key("seller_pk"),
        datum: NoDatum,
        reference_script: None,
      },
    }
  let validity_range = entirely_between(1700553367000, 1700553370000)
  expect Finite(now) = validity_range.lower_bound.bound_type
  let (buyer_1_fee, seller_1_fee, seller_1_receive) =
    calculate_fee(
      cfg,
      get_escrow_datum(oescrow),
      bid_1.quantity,
      bid_1.requested_yield,
      now,
    )
  let (buyer_2_fee, seller_2_fee, seller_2_receive) =
    calculate_fee(
      cfg,
      get_escrow_datum(oescrow),
      bid_2.quantity,
      bid_2.requested_yield,
      now,
    )
  let bid_1_fee = seller_1_fee + buyer_1_fee
  let bid_2_fee = seller_2_fee + buyer_2_fee
  let ofee =
    Output {
      value: value.from_lovelace(bid_1_fee + bid_2_fee),
      address: fee_addr,
      datum: NoDatum,
      reference_script: None,
    }
  let oseller =
    iseller.output
      |> add_asset(
          ada_policy_id,
          ada_asset_name,
          seller_2_receive + seller_1_receive - seller_1_fee - seller_2_fee,
        )
      |> add_asset(bond_pid, bond_name, -bid_1.quantity - bid_2.quantity)
  let obuyer_1 =
    Output {
      value: value.lovelace_of(ibid_1.output.value) + value.lovelace_of(
        ibid_2.output.value,
      ) - bid_1_fee - bid_2_fee - seller_1_receive - seller_2_receive
        |> value.from_lovelace
        |> value.add(bond_pid, bond_name, bid_2.quantity)
        |> value.add(bond_pid, bond_name, bid_1.quantity),
      address: get_buyer_address(ibid_1.output),
      datum: NoDatum,
      reference_script: None,
    }
  let t = transaction.placeholder()
  let tx =
    Transaction {
      ..t,
      validity_range: validity_range,
      reference_inputs: [
        Input {
          output_reference: OutputReference(TransactionId("es_01"), 0),
          output: oescrow,
        },
      ],
      redeemers: t.redeemers
        |> dict.insert(
            Spend(ibid_1.output_reference),
            Sell {
              exchange_fee: bid_1_fee,
              seller_receive: 1122,
              offers: [(bond_pid, bond_name, bid_1.quantity)],
              cont_idx: None,
            },
            purpose_compare,
          )
        |> dict.insert(
            Spend(ibid_2.output_reference),
            Sell {
              exchange_fee: bid_2_fee,
              seller_receive: seller_2_receive,
              offers: [(bond_pid, bond_name, bid_2.quantity)],
              cont_idx: None,
            },
            purpose_compare,
          ),
      inputs: [ibid_1, ibid_2, iseller],
      outputs: [obuyer_1, oseller, ofee],
    }
  !withdraw.constraint(
    ScriptContext { purpose: Spend(ibid_1.output_reference), transaction: tx },
    cfg,
    bid_skh,
    [script_blacklist],
  )
}

test fail_invalid_redeemer_cont_idx() fail {
  let cfg = get_config_limit_mainnet()
  let fee_addr = cfg.exchange.fee_addr
  expect [(bond_pid, _bond_type)] = dict.values(cfg.escrow)
  let bond_name = "bond_name"
  let ibid_1 =
    Input {
      output_reference: OutputReference(TransactionId("tx_bid_1"), 0),
      output: bid_like(
        yield: 10,
        owner: "owner_1",
        from_epoch: 400,
        to_epoch: 500,
        quantity: 10,
      ),
    }
  let bid_1 = get_bid_datum(ibid_1.output)
  let ibid_2 =
    Input {
      output_reference: OutputReference(TransactionId("tx_bid_2"), 1),
      output: bid_like(
        yield: 10,
        owner: "owner_1",
        from_epoch: 400,
        to_epoch: 500,
        quantity: 10,
      ),
    }
  let bid_2 = get_bid_datum(ibid_2.output)
  let oescrow =
    escrow_like(
      epo_rewards: 1 * ada,
      start: 10,
      duration: 150,
      bond_amount: 100,
      bond_symbol: bond_pid,
      token_name: bond_name,
      buffer: 10,
    )
  let iseller =
    Input {
      output_reference: OutputReference(TransactionId("tx_seller"), 1),
      output: Output {
        value: value.from_lovelace(2 * ada)
          |> value.add(bond_pid, bond_name, 50),
        address: from_verification_key("seller_pk"),
        datum: NoDatum,
        reference_script: None,
      },
    }
  let validity_range = entirely_between(1700553367000, 1700553370000)
  expect Finite(now) = validity_range.lower_bound.bound_type
  let (buyer_1_fee, seller_1_fee, seller_1_receive) =
    calculate_fee(
      cfg,
      get_escrow_datum(oescrow),
      bid_1.quantity,
      bid_1.requested_yield,
      now,
    )
  let (buyer_2_fee, seller_2_fee, seller_2_receive) =
    calculate_fee(
      cfg,
      get_escrow_datum(oescrow),
      bid_2.quantity,
      bid_2.requested_yield,
      now,
    )
  let bid_1_fee = seller_1_fee + buyer_1_fee
  let bid_2_fee = seller_2_fee + buyer_2_fee
  let ofee =
    Output {
      value: value.from_lovelace(bid_1_fee + bid_2_fee),
      address: fee_addr,
      datum: NoDatum,
      reference_script: None,
    }
  let oseller =
    iseller.output
      |> add_asset(
          ada_policy_id,
          ada_asset_name,
          seller_2_receive + seller_1_receive - seller_1_fee - seller_2_fee,
        )
      |> add_asset(bond_pid, bond_name, -bid_1.quantity - bid_2.quantity)
  let obuyer_1 =
    Output {
      value: value.lovelace_of(ibid_1.output.value) + value.lovelace_of(
        ibid_2.output.value,
      ) - bid_1_fee - bid_2_fee - seller_1_receive - seller_2_receive
        |> value.from_lovelace
        |> value.add(bond_pid, bond_name, bid_2.quantity)
        |> value.add(bond_pid, bond_name, bid_1.quantity),
      address: get_buyer_address(ibid_1.output),
      datum: NoDatum,
      reference_script: None,
    }
  let t = transaction.placeholder()
  let tx =
    Transaction {
      ..t,
      validity_range: validity_range,
      reference_inputs: [
        Input {
          output_reference: OutputReference(TransactionId("es_01"), 0),
          output: oescrow,
        },
      ],
      redeemers: t.redeemers
        |> dict.insert(
            Spend(ibid_1.output_reference),
            Sell {
              exchange_fee: bid_1_fee,
              seller_receive: seller_1_receive,
              offers: [(bond_pid, bond_name, bid_1.quantity)],
              cont_idx: Some(1),
            },
            purpose_compare,
          )
        |> dict.insert(
            Spend(ibid_2.output_reference),
            Sell {
              exchange_fee: bid_2_fee,
              seller_receive: seller_2_receive,
              offers: [(bond_pid, bond_name, bid_2.quantity)],
              cont_idx: None,
            },
            purpose_compare,
          ),
      inputs: [ibid_1, ibid_2, iseller],
      outputs: [obuyer_1, oseller, ofee],
    }
  !withdraw.constraint(
    ScriptContext { purpose: Spend(ibid_1.output_reference), transaction: tx },
    cfg,
    bid_skh,
    [script_blacklist],
  )
}

test fail_invalid_redeemer_exchange_fee() fail {
  let cfg = get_config_limit_mainnet()
  let fee_addr = cfg.exchange.fee_addr
  expect [(bond_pid, _bond_type)] = dict.values(cfg.escrow)
  let bond_name = "bond_name"
  let ibid_1 =
    Input {
      output_reference: OutputReference(TransactionId("tx_bid_1"), 0),
      output: bid_like(
        yield: 10,
        owner: "owner_1",
        from_epoch: 400,
        to_epoch: 500,
        quantity: 10,
      ),
    }
  let bid_1 = get_bid_datum(ibid_1.output)
  let ibid_2 =
    Input {
      output_reference: OutputReference(TransactionId("tx_bid_2"), 1),
      output: bid_like(
        yield: 10,
        owner: "owner_1",
        from_epoch: 400,
        to_epoch: 500,
        quantity: 10,
      ),
    }
  let bid_2 = get_bid_datum(ibid_2.output)
  let oescrow =
    escrow_like(
      epo_rewards: 1 * ada,
      start: 10,
      duration: 150,
      bond_amount: 100,
      bond_symbol: bond_pid,
      token_name: bond_name,
      buffer: 10,
    )
  let iseller =
    Input {
      output_reference: OutputReference(TransactionId("tx_seller"), 1),
      output: Output {
        value: value.from_lovelace(2 * ada)
          |> value.add(bond_pid, bond_name, 50),
        address: from_verification_key("seller_pk"),
        datum: NoDatum,
        reference_script: None,
      },
    }
  let validity_range = entirely_between(1700553367000, 1700553370000)
  expect Finite(now) = validity_range.lower_bound.bound_type
  let (buyer_1_fee, seller_1_fee, seller_1_receive) =
    calculate_fee(
      cfg,
      get_escrow_datum(oescrow),
      bid_1.quantity,
      bid_1.requested_yield,
      now,
    )
  let (buyer_2_fee, seller_2_fee, seller_2_receive) =
    calculate_fee(
      cfg,
      get_escrow_datum(oescrow),
      bid_2.quantity,
      bid_2.requested_yield,
      now,
    )
  let bid_1_fee = seller_1_fee + buyer_1_fee
  let bid_2_fee = seller_2_fee + buyer_2_fee
  let ofee =
    Output {
      value: value.from_lovelace(bid_1_fee + bid_2_fee),
      address: fee_addr,
      datum: NoDatum,
      reference_script: None,
    }
  let oseller =
    iseller.output
      |> add_asset(
          ada_policy_id,
          ada_asset_name,
          seller_2_receive + seller_1_receive - seller_1_fee - seller_2_fee,
        )
      |> add_asset(bond_pid, bond_name, -bid_1.quantity - bid_2.quantity)
  let obuyer_1 =
    Output {
      value: value.lovelace_of(ibid_1.output.value) + value.lovelace_of(
        ibid_2.output.value,
      ) - bid_1_fee - bid_2_fee - seller_1_receive - seller_2_receive
        |> value.from_lovelace
        |> value.add(bond_pid, bond_name, bid_2.quantity)
        |> value.add(bond_pid, bond_name, bid_1.quantity),
      address: get_buyer_address(ibid_1.output),
      datum: NoDatum,
      reference_script: None,
    }
  let t = transaction.placeholder()
  let tx =
    Transaction {
      ..t,
      validity_range: validity_range,
      reference_inputs: [
        Input {
          output_reference: OutputReference(TransactionId("es_01"), 0),
          output: oescrow,
        },
      ],
      redeemers: t.redeemers
        |> dict.insert(
            Spend(ibid_1.output_reference),
            Sell {
              exchange_fee: 0,
              seller_receive: seller_1_receive,
              offers: [(bond_pid, bond_name, bid_1.quantity)],
              cont_idx: None,
            },
            purpose_compare,
          )
        |> dict.insert(
            Spend(ibid_2.output_reference),
            Sell {
              exchange_fee: bid_2_fee,
              seller_receive: seller_2_receive,
              offers: [(bond_pid, bond_name, bid_2.quantity)],
              cont_idx: None,
            },
            purpose_compare,
          ),
      inputs: [ibid_1, ibid_2, iseller],
      outputs: [obuyer_1, oseller, ofee],
    }
  withdraw.constraint(
    ScriptContext { purpose: Spend(ibid_1.output_reference), transaction: tx },
    cfg,
    bid_skh,
    [script_blacklist],
  )
}

test fail_when_moving_funds_between_bids_exceeded_min_ada() fail {
  let cfg = get_config_limit_mainnet()
  let fee_addr = cfg.exchange.fee_addr
  expect [(bond_pid, _bond_type)] = dict.values(cfg.escrow)
  let bond_name = "bond_name"
  let ibid_1 =
    Input {
      output_reference: OutputReference(TransactionId("tx_bid_1"), 0),
      output: bid_like(
        yield: 10,
        owner: "owner_1",
        from_epoch: 400,
        to_epoch: 500,
        quantity: 10,
      ),
    }
  let bond_sell_qty_1 = 3
  let bid_1 = get_bid_datum(ibid_1.output)
  let ibid_2 =
    Input {
      output_reference: OutputReference(TransactionId("tx_bid_2"), 1),
      output: bid_like(
        yield: 10,
        owner: "owner_1",
        from_epoch: 400,
        to_epoch: 500,
        quantity: 10,
      ),
    }
  let bond_sell_qty_2 = 3
  let bid_2 = get_bid_datum(ibid_2.output)
  let obid_1_remain =
    Input {
      output_reference: OutputReference(TransactionId("tx_bid_1"), 0),
      output: bid_like(
        yield: 10,
        owner: "owner_1",
        from_epoch: 400,
        to_epoch: 500,
        quantity: bid_1.quantity - bond_sell_qty_1,
      ),
    }
  let obid_2_remain =
    Input {
      output_reference: OutputReference(TransactionId("tx_bid_2"), 1),
      output: bid_like(
        yield: 10,
        owner: "owner_1",
        from_epoch: 400,
        to_epoch: 500,
        quantity: bid_2.quantity - bond_sell_qty_2,
      ),
    }
  let oescrow =
    escrow_like(
      epo_rewards: 1 * ada,
      start: 10,
      duration: 150,
      bond_amount: 100,
      bond_symbol: bond_pid,
      token_name: bond_name,
      buffer: 10,
    )
  let iseller =
    Input {
      output_reference: OutputReference(TransactionId("tx_seller"), 1),
      output: Output {
        value: value.from_lovelace(2 * ada)
          |> value.add(bond_pid, bond_name, 50),
        address: from_verification_key("seller_pk"),
        datum: NoDatum,
        reference_script: None,
      },
    }

  let validity_range = entirely_between(1700553367000, 1700553370000)
  expect Finite(now) = validity_range.lower_bound.bound_type
  let (buyer_1_fee, seller_1_fee, seller_1_receive) =
    calculate_fee(
      cfg,
      get_escrow_datum(oescrow),
      bond_sell_qty_1,
      bid_1.requested_yield,
      now,
    )
  let (buyer_2_fee, seller_2_fee, seller_2_receive) =
    calculate_fee(
      cfg,
      get_escrow_datum(oescrow),
      bond_sell_qty_2,
      bid_2.requested_yield,
      now,
    )
  let bid_1_fee = seller_1_fee + buyer_1_fee
  let bid_2_fee = seller_2_fee + buyer_2_fee
  let ofee =
    Output {
      value: value.from_lovelace(bid_1_fee + bid_2_fee),
      address: fee_addr,
      datum: NoDatum,
      reference_script: None,
    }
  let obuyer_1 =
    Output {
      value: value.lovelace_of(ibid_1.output.value) + value.lovelace_of(
        ibid_2.output.value,
      ) - value.lovelace_of(obid_1_remain.output.value) - value.lovelace_of(
        obid_2_remain.output.value,
      ) - bid_1_fee - bid_2_fee - seller_1_receive - seller_2_receive
        |> value.from_lovelace
        |> value.add(bond_pid, bond_name, bond_sell_qty_1)
        |> value.add(bond_pid, bond_name, bond_sell_qty_2),
      address: get_buyer_address(ibid_1.output),
      datum: NoDatum,
      reference_script: None,
    }

  let obid_1 =
    obid_1_remain.output
      |> add_asset(ada_policy_id, ada_asset_name, -3 * ada)
  let obid_2 =
    obid_2_remain.output
      |> add_asset(ada_policy_id, ada_asset_name, 3 * ada)
  let oseller =
    iseller.output
      |> add_asset(
          ada_policy_id,
          ada_asset_name,
          seller_2_receive + seller_1_receive - seller_1_fee - seller_2_fee,
        )
      |> add_asset(bond_pid, bond_name, -bond_sell_qty_1 - bond_sell_qty_2)

  let t = transaction.placeholder()
  let tx =
    Transaction {
      ..t,
      validity_range: validity_range,
      reference_inputs: [
        Input {
          output_reference: OutputReference(TransactionId("es_01"), 0),
          output: oescrow,
        },
      ],
      redeemers: t.redeemers
        |> dict.insert(
            Spend(ibid_1.output_reference),
            Sell {
              exchange_fee: bid_1_fee,
              seller_receive: seller_1_receive,
              offers: [(bond_pid, bond_name, bond_sell_qty_1)],
              cont_idx: Some(3),
            },
            purpose_compare,
          )
        |> dict.insert(
            Spend(ibid_2.output_reference),
            Sell {
              exchange_fee: bid_2_fee,
              seller_receive: seller_2_receive,
              offers: [(bond_pid, bond_name, bond_sell_qty_2)],
              cont_idx: Some(4),
            },
            purpose_compare,
          ),
      inputs: [ibid_1, ibid_2, iseller],
      outputs: [obuyer_1, oseller, ofee, obid_1, obid_2],
    }
  withdraw.constraint(
    ScriptContext { purpose: Spend(ibid_1.output_reference), transaction: tx },
    cfg,
    bid_skh,
    [script_blacklist],
  )
}

test succ_sell_require_withdraw() {
  let cfg = get_config_limit_mainnet()
  let fee_addr = cfg.exchange.fee_addr
  expect [(bond_pid, _bond_type)] = dict.values(cfg.escrow)
  let bond_name_1 = "bond_name_1"
  let bond_name_2 = "bond_name_2"
  let ibid_1 =
    Input {
      output_reference: OutputReference(TransactionId("tx_bid_1"), 0),
      output: bid_like(
        yield: 10,
        owner: "owner_1",
        from_epoch: 400,
        to_epoch: 500,
        quantity: 10,
      ),
    }
  let bid_1 = get_bid_datum(ibid_1.output)
  let ibid_2 =
    Input {
      output_reference: OutputReference(TransactionId("tx_bid_2"), 1),
      output: bid_like(
        yield: 10,
        owner: "owner_1",
        from_epoch: 400,
        to_epoch: 500,
        quantity: 10,
      ),
    }
  let bid_2 = get_bid_datum(ibid_2.output)
  let oescrow_1 =
    escrow_like(
      epo_rewards: 1 * ada,
      start: 10,
      duration: 150,
      bond_amount: 100,
      bond_symbol: bond_pid,
      token_name: bond_name_1,
      buffer: 10,
    )
  let oescrow_2 =
    escrow_like(
      epo_rewards: 1 * ada,
      start: 10,
      duration: 150,
      bond_amount: 100,
      bond_symbol: bond_pid,
      token_name: bond_name_2,
      buffer: 10,
    )
  let iseller =
    Input {
      output_reference: OutputReference(TransactionId("tx_seller"), 1),
      output: Output {
        value: value.from_lovelace(2 * ada)
          |> value.add(bond_pid, bond_name_1, 10)
          |> value.add(bond_pid, bond_name_2, 10),
        address: from_verification_key("seller_pk"),
        datum: NoDatum,
        reference_script: None,
      },
    }
  let validity_range = entirely_between(1700553367000, 1700553370000)
  expect Finite(now) = validity_range.lower_bound.bound_type
  let (buyer_1_fee, seller_1_fee, seller_1_receive) =
    calculate_fee(
      cfg,
      get_escrow_datum(oescrow_1),
      bid_1.quantity,
      bid_1.requested_yield,
      now,
    )
  let (buyer_2_fee, seller_2_fee, seller_2_receive) =
    calculate_fee(
      cfg,
      get_escrow_datum(oescrow_2),
      bid_2.quantity,
      bid_2.requested_yield,
      now,
    )
  let bid_1_fee = seller_1_fee + buyer_1_fee
  let bid_2_fee = seller_2_fee + buyer_2_fee
  let ofee =
    Output {
      value: value.from_lovelace(bid_1_fee + bid_2_fee),
      address: fee_addr,
      datum: NoDatum,
      reference_script: None,
    }
  let oseller =
    iseller.output
      |> add_asset(bond_pid, bond_name_1, -bid_1.quantity)
      |> add_asset(bond_pid, bond_name_2, -bid_2.quantity)
  let obuyer_1 =
    Output {
      value: value.lovelace_of(ibid_1.output.value) + value.lovelace_of(
        ibid_2.output.value,
      ) - bid_1_fee - bid_2_fee - seller_1_receive - seller_2_receive
        |> value.from_lovelace
        |> value.add(bond_pid, bond_name_2, bid_2.quantity)
        |> value.add(bond_pid, bond_name_1, bid_1.quantity),
      address: get_buyer_address(ibid_1.output),
      datum: NoDatum,
      reference_script: None,
    }
  let t = transaction.placeholder()
  let tx =
    Transaction {
      ..t,
      validity_range: validity_range,
      reference_inputs: [
        Input {
          output_reference: OutputReference(TransactionId("es_01"), 0),
          output: oescrow_1,
        },
        Input {
          output_reference: OutputReference(TransactionId("es_02"), 0),
          output: oescrow_2,
        },
      ],
      redeemers: t.redeemers
        |> dict.insert(
            Spend(ibid_1.output_reference),
            Sell {
              exchange_fee: bid_1_fee,
              seller_receive: seller_1_receive,
              offers: [(bond_pid, bond_name_1, bid_1.quantity)],
              cont_idx: None,
            },
            purpose_compare,
          )
        |> dict.insert(
            Spend(ibid_2.output_reference),
            Sell {
              exchange_fee: bid_2_fee,
              seller_receive: seller_2_receive,
              offers: [(bond_pid, bond_name_2, bid_2.quantity)],
              cont_idx: None,
            },
            purpose_compare,
          )
        |> dict.insert(
            WithdrawFrom(stake_credential_like(multi_bid_skh)),
            SellMulti { bid_skh },
            purpose_compare,
          ),
      inputs: [ibid_1, ibid_2, iseller],
      outputs: [obuyer_1, oseller, ofee],
    }
  sell.constraint(
    ScriptContext { purpose: Spend(ibid_1.output_reference), transaction: tx },
    multi_bid_skh,
  )
}

test fail_sell_require_withdraw_wrong_bid_skh() {
  let cfg = get_config_limit_mainnet()
  let fee_addr = cfg.exchange.fee_addr
  expect [(bond_pid, _bond_type)] = dict.values(cfg.escrow)
  let bond_name_1 = "bond_name_1"
  let bond_name_2 = "bond_name_2"
  let ibid_1 =
    Input {
      output_reference: OutputReference(TransactionId("tx_bid_1"), 0),
      output: bid_like(
        yield: 10,
        owner: "owner_1",
        from_epoch: 400,
        to_epoch: 500,
        quantity: 10,
      ),
    }
  let bid_1 = get_bid_datum(ibid_1.output)
  let ibid_2 =
    Input {
      output_reference: OutputReference(TransactionId("tx_bid_2"), 1),
      output: bid_like(
        yield: 10,
        owner: "owner_1",
        from_epoch: 400,
        to_epoch: 500,
        quantity: 10,
      ),
    }
  let bid_2 = get_bid_datum(ibid_2.output)
  let oescrow_1 =
    escrow_like(
      epo_rewards: 1 * ada,
      start: 10,
      duration: 150,
      bond_amount: 100,
      bond_symbol: bond_pid,
      token_name: bond_name_1,
      buffer: 10,
    )
  let oescrow_2 =
    escrow_like(
      epo_rewards: 1 * ada,
      start: 10,
      duration: 150,
      bond_amount: 100,
      bond_symbol: bond_pid,
      token_name: bond_name_2,
      buffer: 10,
    )
  let iseller =
    Input {
      output_reference: OutputReference(TransactionId("tx_seller"), 1),
      output: Output {
        value: value.from_lovelace(2 * ada)
          |> value.add(bond_pid, bond_name_1, 10)
          |> value.add(bond_pid, bond_name_2, 10),
        address: from_verification_key("seller_pk"),
        datum: NoDatum,
        reference_script: None,
      },
    }
  let validity_range = entirely_between(1700553367000, 1700553370000)
  expect Finite(now) = validity_range.lower_bound.bound_type
  let (buyer_1_fee, seller_1_fee, seller_1_receive) =
    calculate_fee(
      cfg,
      get_escrow_datum(oescrow_1),
      bid_1.quantity,
      bid_1.requested_yield,
      now,
    )
  let (buyer_2_fee, seller_2_fee, seller_2_receive) =
    calculate_fee(
      cfg,
      get_escrow_datum(oescrow_2),
      bid_2.quantity,
      bid_2.requested_yield,
      now,
    )
  let bid_1_fee = seller_1_fee + buyer_1_fee
  let bid_2_fee = seller_2_fee + buyer_2_fee
  let ofee =
    Output {
      value: value.from_lovelace(bid_1_fee + bid_2_fee),
      address: fee_addr,
      datum: NoDatum,
      reference_script: None,
    }
  let oseller =
    iseller.output
      |> add_asset(bond_pid, bond_name_1, -bid_1.quantity)
      |> add_asset(bond_pid, bond_name_2, -bid_2.quantity)
  let obuyer_1 =
    Output {
      value: value.lovelace_of(ibid_1.output.value) + value.lovelace_of(
        ibid_2.output.value,
      ) - bid_1_fee - bid_2_fee - seller_1_receive - seller_2_receive
        |> value.from_lovelace
        |> value.add(bond_pid, bond_name_2, bid_2.quantity)
        |> value.add(bond_pid, bond_name_1, bid_1.quantity),
      address: get_buyer_address(ibid_1.output),
      datum: NoDatum,
      reference_script: None,
    }
  let t = transaction.placeholder()
  let fake_bid_skh = "fake_bid_skh"
  let tx =
    Transaction {
      ..t,
      validity_range: validity_range,
      reference_inputs: [
        Input {
          output_reference: OutputReference(TransactionId("es_01"), 0),
          output: oescrow_1,
        },
        Input {
          output_reference: OutputReference(TransactionId("es_02"), 0),
          output: oescrow_2,
        },
      ],
      redeemers: t.redeemers
        |> dict.insert(
            Spend(ibid_1.output_reference),
            Sell {
              exchange_fee: bid_1_fee,
              seller_receive: seller_1_receive,
              offers: [(bond_pid, bond_name_1, bid_1.quantity)],
              cont_idx: None,
            },
            purpose_compare,
          )
        |> dict.insert(
            Spend(ibid_2.output_reference),
            Sell {
              exchange_fee: bid_2_fee,
              seller_receive: seller_2_receive,
              offers: [(bond_pid, bond_name_2, bid_2.quantity)],
              cont_idx: None,
            },
            purpose_compare,
          )
        |> dict.insert(
            WithdrawFrom(stake_credential_like(multi_bid_skh)),
            SellMulti { bid_skh: fake_bid_skh },
            purpose_compare,
          ),
      inputs: [ibid_1, ibid_2, iseller],
      outputs: [obuyer_1, oseller, ofee],
    }
  !sell.constraint(
    ScriptContext { purpose: Spend(ibid_1.output_reference), transaction: tx },
    multi_bid_skh,
  )
}

test fail_sell_require_withdraw_not_exist_withdraw_skh() fail {
  let cfg = get_config_limit_mainnet()
  let fee_addr = cfg.exchange.fee_addr
  expect [(bond_pid, _bond_type)] = dict.values(cfg.escrow)
  let bond_name_1 = "bond_name_1"
  let bond_name_2 = "bond_name_2"
  let ibid_1 =
    Input {
      output_reference: OutputReference(TransactionId("tx_bid_1"), 0),
      output: bid_like(
        yield: 10,
        owner: "owner_1",
        from_epoch: 400,
        to_epoch: 500,
        quantity: 10,
      ),
    }
  let bid_1 = get_bid_datum(ibid_1.output)
  let ibid_2 =
    Input {
      output_reference: OutputReference(TransactionId("tx_bid_2"), 1),
      output: bid_like(
        yield: 10,
        owner: "owner_1",
        from_epoch: 400,
        to_epoch: 500,
        quantity: 10,
      ),
    }
  let bid_2 = get_bid_datum(ibid_2.output)
  let oescrow_1 =
    escrow_like(
      epo_rewards: 1 * ada,
      start: 10,
      duration: 150,
      bond_amount: 100,
      bond_symbol: bond_pid,
      token_name: bond_name_1,
      buffer: 10,
    )
  let oescrow_2 =
    escrow_like(
      epo_rewards: 1 * ada,
      start: 10,
      duration: 150,
      bond_amount: 100,
      bond_symbol: bond_pid,
      token_name: bond_name_2,
      buffer: 10,
    )
  let iseller =
    Input {
      output_reference: OutputReference(TransactionId("tx_seller"), 1),
      output: Output {
        value: value.from_lovelace(2 * ada)
          |> value.add(bond_pid, bond_name_1, 10)
          |> value.add(bond_pid, bond_name_2, 10),
        address: from_verification_key("seller_pk"),
        datum: NoDatum,
        reference_script: None,
      },
    }
  let validity_range = entirely_between(1700553367000, 1700553370000)
  expect Finite(now) = validity_range.lower_bound.bound_type
  let (buyer_1_fee, seller_1_fee, seller_1_receive) =
    calculate_fee(
      cfg,
      get_escrow_datum(oescrow_1),
      bid_1.quantity,
      bid_1.requested_yield,
      now,
    )
  let (buyer_2_fee, seller_2_fee, seller_2_receive) =
    calculate_fee(
      cfg,
      get_escrow_datum(oescrow_2),
      bid_2.quantity,
      bid_2.requested_yield,
      now,
    )
  let bid_1_fee = seller_1_fee + buyer_1_fee
  let bid_2_fee = seller_2_fee + buyer_2_fee
  let ofee =
    Output {
      value: value.from_lovelace(bid_1_fee + bid_2_fee),
      address: fee_addr,
      datum: NoDatum,
      reference_script: None,
    }
  let oseller =
    iseller.output
      |> add_asset(bond_pid, bond_name_1, -bid_1.quantity)
      |> add_asset(bond_pid, bond_name_2, -bid_2.quantity)
  let obuyer_1 =
    Output {
      value: value.lovelace_of(ibid_1.output.value) + value.lovelace_of(
        ibid_2.output.value,
      ) - bid_1_fee - bid_2_fee - seller_1_receive - seller_2_receive
        |> value.from_lovelace
        |> value.add(bond_pid, bond_name_2, bid_2.quantity)
        |> value.add(bond_pid, bond_name_1, bid_1.quantity),
      address: get_buyer_address(ibid_1.output),
      datum: NoDatum,
      reference_script: None,
    }
  let t = transaction.placeholder()
  let tx =
    Transaction {
      ..t,
      validity_range: validity_range,
      reference_inputs: [
        Input {
          output_reference: OutputReference(TransactionId("es_01"), 0),
          output: oescrow_1,
        },
        Input {
          output_reference: OutputReference(TransactionId("es_02"), 0),
          output: oescrow_2,
        },
      ],
      redeemers: t.redeemers
        |> dict.insert(
            Spend(ibid_1.output_reference),
            Sell {
              exchange_fee: bid_1_fee,
              seller_receive: seller_1_receive,
              offers: [(bond_pid, bond_name_1, bid_1.quantity)],
              cont_idx: None,
            },
            purpose_compare,
          )
        |> dict.insert(
            Spend(ibid_2.output_reference),
            Sell {
              exchange_fee: bid_2_fee,
              seller_receive: seller_2_receive,
              offers: [(bond_pid, bond_name_2, bid_2.quantity)],
              cont_idx: None,
            },
            purpose_compare,
          )
        |> dict.insert(
            WithdrawFrom(stake_credential_like("fake multi_bid_skh")),
            SellMulti { bid_skh },
            purpose_compare,
          ),
      inputs: [ibid_1, ibid_2, iseller],
      outputs: [obuyer_1, oseller, ofee],
    }
  !sell.constraint(
    ScriptContext { purpose: Spend(ibid_1.output_reference), transaction: tx },
    multi_bid_skh,
  )
}

test fail_when_spend_deprecated_bid() fail {
  let cfg = get_config_limit_mainnet()
  let fee_addr = cfg.exchange.fee_addr
  expect [(bond_pid, _bond_type)] = dict.values(cfg.escrow)
  let bond_name = "bond_name"
  let ibid_1 =
    Input {
      output_reference: OutputReference(TransactionId("tx_bid_1"), 0),
      output: bid_like(
        yield: 10,
        owner: "owner_1",
        from_epoch: 400,
        to_epoch: 500,
        quantity: 10,
      ),
    }
  let bid_1 = get_bid_datum(ibid_1.output)
  let ibid_2 =
    Input {
      output_reference: OutputReference(TransactionId("tx_bid_2"), 1),
      output: bid_like(
        yield: 10,
        owner: "owner_1",
        from_epoch: 400,
        to_epoch: 500,
        quantity: 10,
      ),
    }
  let bid_2 = get_bid_datum(ibid_2.output)
  let oescrow =
    escrow_like(
      epo_rewards: 1 * ada,
      start: 10,
      duration: 150,
      bond_amount: 100,
      bond_symbol: bond_pid,
      token_name: bond_name,
      buffer: 10,
    )
  let deprecated_bid =
    Input {
      output_reference: OutputReference(TransactionId("tx_deprecated_bid"), 1),
      output: Output {
        value: value.from_lovelace(1000000),
        address: from_script(script_blacklist),
        datum: InlineDatum(
          BidLimitMulti {
            owner_vk: "owner_1",
            owner_sk: Some(bytearray.concat("stake_", "owner_1")),
            from_epoch: 400,
            to_epoch: 500,
            quantity: 10,
            requested_yield: 100,
            bond_types: [DanogoBond],
          },
        ),
        reference_script: None,
      },
    }
  let iseller =
    Input {
      output_reference: OutputReference(TransactionId("tx_seller"), 1),
      output: Output {
        value: value.from_lovelace(2 * ada)
          |> value.add(bond_pid, bond_name, 50),
        address: from_verification_key("seller_pk"),
        datum: NoDatum,
        reference_script: None,
      },
    }
  let validity_range = entirely_between(1700553367000, 1700553370000)
  expect Finite(now) = validity_range.lower_bound.bound_type
  let (buyer_1_fee, seller_1_fee, seller_1_receive) =
    calculate_fee(
      cfg,
      get_escrow_datum(oescrow),
      bid_1.quantity,
      bid_1.requested_yield,
      now,
    )
  let (buyer_2_fee, seller_2_fee, seller_2_receive) =
    calculate_fee(
      cfg,
      get_escrow_datum(oescrow),
      bid_2.quantity,
      bid_2.requested_yield,
      now,
    )
  let bid_1_fee = seller_1_fee + buyer_1_fee
  let bid_2_fee = seller_2_fee + buyer_2_fee
  let ofee =
    Output {
      value: value.from_lovelace(bid_1_fee + bid_2_fee),
      address: fee_addr,
      datum: NoDatum,
      reference_script: None,
    }
  let oseller =
    iseller.output
      |> add_asset(
          ada_policy_id,
          ada_asset_name,
          seller_2_receive + seller_1_receive - seller_1_fee - seller_2_fee,
        )
      |> add_asset(bond_pid, bond_name, -bid_1.quantity - bid_2.quantity)
  let obuyer_1 =
    Output {
      value: value.lovelace_of(ibid_1.output.value) + value.lovelace_of(
        ibid_2.output.value,
      ) - bid_1_fee - bid_2_fee - seller_1_receive - seller_2_receive
        |> value.from_lovelace
        |> value.add(bond_pid, bond_name, bid_2.quantity)
        |> value.add(bond_pid, bond_name, bid_1.quantity),
      address: get_buyer_address(ibid_1.output),
      datum: NoDatum,
      reference_script: None,
    }
  let t = transaction.placeholder()
  let tx =
    Transaction {
      ..t,
      validity_range: validity_range,
      reference_inputs: [
        Input {
          output_reference: OutputReference(TransactionId("es_01"), 0),
          output: oescrow,
        },
      ],
      redeemers: t.redeemers
        |> dict.insert(
            Spend(ibid_1.output_reference),
            Sell {
              exchange_fee: bid_1_fee,
              seller_receive: seller_1_receive,
              offers: [(bond_pid, bond_name, bid_1.quantity)],
              cont_idx: None,
            },
            purpose_compare,
          )
        |> dict.insert(
            Spend(ibid_2.output_reference),
            Sell {
              exchange_fee: bid_2_fee,
              seller_receive: seller_2_receive,
              offers: [(bond_pid, bond_name, bid_2.quantity)],
              cont_idx: None,
            },
            purpose_compare,
          )
        |> dict.insert(
            WithdrawFrom(stake_credential_like(multi_bid_skh)),
            SellMulti { bid_skh },
            purpose_compare,
          ),
      inputs: [ibid_1, ibid_2, iseller, deprecated_bid],
      outputs: [obuyer_1, oseller, ofee],
    }
  !and {
    withdraw.constraint(
      ScriptContext { purpose: Spend(ibid_1.output_reference), transaction: tx },
      cfg,
      bid_skh,
      [script_blacklist],
    ),
    sell.constraint(
      ScriptContext { purpose: Spend(ibid_1.output_reference), transaction: tx },
      multi_bid_skh,
    ),
  }
}

test succ_when_sbid_has_other_tokens() {
  let (other_pid, other_tkn) = ("other_pid", "other_tkn")
  let cfg = get_config_limit_mainnet()
  let fee_addr = cfg.exchange.fee_addr
  expect [(bond_pid, _bond_type)] = dict.values(cfg.escrow)
  let bond_name = "bond_name"
  let ibid_1 =
    Input {
      output_reference: OutputReference(TransactionId("tx_bid_1"), 0),
      output: bid_like(
        yield: 10,
        owner: "owner_1",
        from_epoch: 400,
        to_epoch: 500,
        quantity: 10,
      )
        |> add_asset(other_pid, other_tkn, 1),
    }
  let bond_sell_qty_1 = 2
  let bid_1 = get_bid_datum(ibid_1.output)
  let ibid_2 =
    Input {
      output_reference: OutputReference(TransactionId("tx_bid_2"), 1),
      output: bid_like(
        yield: 10,
        owner: "owner_1",
        from_epoch: 400,
        to_epoch: 500,
        quantity: 10,
      ),
    }
  let bid_2 = get_bid_datum(ibid_2.output)
  let oescrow =
    escrow_like(
      epo_rewards: 1 * ada,
      start: 10,
      duration: 150,
      bond_amount: 100,
      bond_symbol: bond_pid,
      token_name: bond_name,
      buffer: 10,
    )
  let iseller =
    Input {
      output_reference: OutputReference(TransactionId("tx_seller"), 1),
      output: Output {
        value: value.from_lovelace(2 * ada)
          |> value.add(bond_pid, bond_name, 50),
        address: from_verification_key("seller_pk"),
        datum: NoDatum,
        reference_script: None,
      },
    }
  let validity_range = entirely_between(1700553367000, 1700553370000)
  expect Finite(now) = validity_range.lower_bound.bound_type
  let (buyer_1_fee, seller_1_fee, seller_1_receive) =
    calculate_fee(
      cfg,
      get_escrow_datum(oescrow),
      bond_sell_qty_1,
      bid_1.requested_yield,
      now,
    )
  let (buyer_2_fee, seller_2_fee, seller_2_receive) =
    calculate_fee(
      cfg,
      get_escrow_datum(oescrow),
      bid_2.quantity,
      bid_2.requested_yield,
      now,
    )
  let bid_1_fee = seller_1_fee + buyer_1_fee
  let bid_2_fee = seller_2_fee + buyer_2_fee
  let ofee =
    Output {
      value: value.from_lovelace(bid_1_fee + bid_2_fee),
      address: fee_addr,
      datum: NoDatum,
      reference_script: None,
    }
  let obid_1 =
    bid_like(
      yield: 10,
      owner: "owner_1",
      from_epoch: 400,
      to_epoch: 500,
      quantity: bid_1.quantity - bond_sell_qty_1,
    )
      |> add_asset(other_pid, other_tkn, 1)
  let obuyer_1 =
    Output {
      value: value.lovelace_of(ibid_1.output.value) + value.lovelace_of(
        ibid_2.output.value,
      ) - value.lovelace_of(obid_1.value) - bid_1_fee - bid_2_fee - seller_1_receive - seller_2_receive
        |> value.from_lovelace
        |> value.add(bond_pid, bond_name, bond_sell_qty_1)
        |> value.add(bond_pid, bond_name, bid_2.quantity),
      address: get_buyer_address(ibid_1.output),
      datum: NoDatum,
      reference_script: None,
    }
  let oseller =
    iseller.output
      |> add_asset(
          ada_policy_id,
          ada_asset_name,
          seller_2_receive + seller_1_receive - seller_1_fee - seller_2_fee,
        )
      |> add_asset(bond_pid, bond_name, -bond_sell_qty_1 - bid_2.quantity)
  let t = transaction.placeholder()
  let tx =
    Transaction {
      ..t,
      validity_range: validity_range,
      reference_inputs: [
        Input {
          output_reference: OutputReference(TransactionId("es_01"), 0),
          output: oescrow,
        },
      ],
      redeemers: t.redeemers
        |> dict.insert(
            Spend(ibid_1.output_reference),
            Sell {
              exchange_fee: bid_1_fee,
              seller_receive: seller_1_receive,
              offers: [(bond_pid, bond_name, bond_sell_qty_1)],
              cont_idx: Some(3),
            },
            purpose_compare,
          )
        |> dict.insert(
            Spend(ibid_2.output_reference),
            Sell {
              exchange_fee: bid_2_fee,
              seller_receive: seller_2_receive,
              offers: [(bond_pid, bond_name, bid_2.quantity)],
              cont_idx: None,
            },
            purpose_compare,
          )
        |> dict.insert(
            WithdrawFrom(stake_credential_like(multi_bid_skh)),
            SellMulti { bid_skh },
            purpose_compare,
          ),
      inputs: [ibid_1, ibid_2, iseller],
      outputs: [obuyer_1, oseller, ofee, obid_1],
    }
  and {
    withdraw.constraint(
      ScriptContext { purpose: Spend(ibid_1.output_reference), transaction: tx },
      cfg,
      bid_skh,
      [script_blacklist],
    ),
    sell.constraint(
      ScriptContext { purpose: Spend(ibid_1.output_reference), transaction: tx },
      multi_bid_skh,
    ),
  }
}

test fail_when_attempting_unbound_value() fail {
  let cfg = get_config_limit_mainnet()
  let fee_addr = cfg.exchange.fee_addr
  expect [(bond_pid, _bond_type)] = dict.values(cfg.escrow)
  let bond_name = "bond_name"
  let ibid_1 =
    Input {
      output_reference: OutputReference(TransactionId("tx_bid_1"), 0),
      output: bid_like(
        yield: 10,
        owner: "owner_1",
        from_epoch: 400,
        to_epoch: 500,
        quantity: 10,
      ),
    }
  let bond_sell_qty_1 = 2
  let bid_1 = get_bid_datum(ibid_1.output)
  let ibid_2 =
    Input {
      output_reference: OutputReference(TransactionId("tx_bid_2"), 1),
      output: bid_like(
        yield: 10,
        owner: "owner_1",
        from_epoch: 400,
        to_epoch: 500,
        quantity: 10,
      ),
    }
  let bid_2 = get_bid_datum(ibid_2.output)
  let oescrow =
    escrow_like(
      epo_rewards: 1 * ada,
      start: 10,
      duration: 150,
      bond_amount: 100,
      bond_symbol: bond_pid,
      token_name: bond_name,
      buffer: 10,
    )
  let iseller =
    Input {
      output_reference: OutputReference(TransactionId("tx_seller"), 1),
      output: Output {
        value: value.from_lovelace(2 * ada)
          |> value.add(bond_pid, bond_name, 50),
        address: from_verification_key("seller_pk"),
        datum: NoDatum,
        reference_script: None,
      },
    }
  let validity_range = entirely_between(1700553367000, 1700553370000)
  expect Finite(now) = validity_range.lower_bound.bound_type
  let (buyer_1_fee, seller_1_fee, seller_1_receive) =
    calculate_fee(
      cfg,
      get_escrow_datum(oescrow),
      bond_sell_qty_1,
      bid_1.requested_yield,
      now,
    )
  let (buyer_2_fee, seller_2_fee, seller_2_receive) =
    calculate_fee(
      cfg,
      get_escrow_datum(oescrow),
      bid_2.quantity,
      bid_2.requested_yield,
      now,
    )
  let bid_1_fee = seller_1_fee + buyer_1_fee
  let bid_2_fee = seller_2_fee + buyer_2_fee
  let ofee =
    Output {
      value: value.from_lovelace(bid_1_fee + bid_2_fee),
      address: fee_addr,
      datum: NoDatum,
      reference_script: None,
    }
  let obid_1 =
    bid_like(
      yield: 10,
      owner: "owner_1",
      from_epoch: 400,
      to_epoch: 500,
      quantity: bid_1.quantity - bond_sell_qty_1,
    )
      |> add_asset("other_pid", "other_tkn", 1)
  let obuyer_1 =
    Output {
      value: value.lovelace_of(ibid_1.output.value) + value.lovelace_of(
        ibid_2.output.value,
      ) - value.lovelace_of(obid_1.value) - bid_1_fee - bid_2_fee - seller_1_receive - seller_2_receive
        |> value.from_lovelace
        |> value.add(bond_pid, bond_name, bond_sell_qty_1)
        |> value.add(bond_pid, bond_name, bid_2.quantity),
      address: get_buyer_address(ibid_1.output),
      datum: NoDatum,
      reference_script: None,
    }
  let oseller =
    iseller.output
      |> add_asset(
          ada_policy_id,
          ada_asset_name,
          seller_2_receive + seller_1_receive - seller_1_fee - seller_2_fee,
        )
      |> add_asset(bond_pid, bond_name, -bond_sell_qty_1 - bid_2.quantity)
  let t = transaction.placeholder()
  let tx =
    Transaction {
      ..t,
      validity_range: validity_range,
      reference_inputs: [
        Input {
          output_reference: OutputReference(TransactionId("es_01"), 0),
          output: oescrow,
        },
      ],
      redeemers: t.redeemers
        |> dict.insert(
            Spend(ibid_1.output_reference),
            Sell {
              exchange_fee: bid_1_fee,
              seller_receive: seller_1_receive,
              offers: [(bond_pid, bond_name, bond_sell_qty_1)],
              cont_idx: Some(3),
            },
            purpose_compare,
          )
        |> dict.insert(
            Spend(ibid_2.output_reference),
            Sell {
              exchange_fee: bid_2_fee,
              seller_receive: seller_2_receive,
              offers: [(bond_pid, bond_name, bid_2.quantity)],
              cont_idx: None,
            },
            purpose_compare,
          )
        |> dict.insert(
            WithdrawFrom(stake_credential_like(multi_bid_skh)),
            SellMulti { bid_skh },
            purpose_compare,
          ),
      inputs: [ibid_1, ibid_2, iseller],
      outputs: [obuyer_1, oseller, ofee, obid_1],
    }
  and {
    withdraw.constraint(
      ScriptContext { purpose: Spend(ibid_1.output_reference), transaction: tx },
      cfg,
      bid_skh,
      [script_blacklist],
    ),
    sell.constraint(
      ScriptContext { purpose: Spend(ibid_1.output_reference), transaction: tx },
      multi_bid_skh,
    ),
  }
}

test fail_when_missing_token() fail {
  let (other_pid, other_tkn) = ("other_pid", "other_tkn")
  let cfg = get_config_limit_mainnet()
  let fee_addr = cfg.exchange.fee_addr
  expect [(bond_pid, _bond_type)] = dict.values(cfg.escrow)
  let bond_name = "bond_name"
  let ibid_1 =
    Input {
      output_reference: OutputReference(TransactionId("tx_bid_1"), 0),
      output: bid_like(
        yield: 10,
        owner: "owner_1",
        from_epoch: 400,
        to_epoch: 500,
        quantity: 10,
      )
        |> add_asset(other_pid, other_tkn, 1),
    }
  let bond_sell_qty_1 = 2
  let bid_1 = get_bid_datum(ibid_1.output)
  let ibid_2 =
    Input {
      output_reference: OutputReference(TransactionId("tx_bid_2"), 1),
      output: bid_like(
        yield: 10,
        owner: "owner_1",
        from_epoch: 400,
        to_epoch: 500,
        quantity: 10,
      ),
    }
  let bid_2 = get_bid_datum(ibid_2.output)
  let oescrow =
    escrow_like(
      epo_rewards: 1 * ada,
      start: 10,
      duration: 150,
      bond_amount: 100,
      bond_symbol: bond_pid,
      token_name: bond_name,
      buffer: 10,
    )
  let iseller =
    Input {
      output_reference: OutputReference(TransactionId("tx_seller"), 1),
      output: Output {
        value: value.from_lovelace(2 * ada)
          |> value.add(bond_pid, bond_name, 50),
        address: from_verification_key("seller_pk"),
        datum: NoDatum,
        reference_script: None,
      },
    }
  let validity_range = entirely_between(1700553367000, 1700553370000)
  expect Finite(now) = validity_range.lower_bound.bound_type
  let (buyer_1_fee, seller_1_fee, seller_1_receive) =
    calculate_fee(
      cfg,
      get_escrow_datum(oescrow),
      bond_sell_qty_1,
      bid_1.requested_yield,
      now,
    )
  let (buyer_2_fee, seller_2_fee, seller_2_receive) =
    calculate_fee(
      cfg,
      get_escrow_datum(oescrow),
      bid_2.quantity,
      bid_2.requested_yield,
      now,
    )
  let bid_1_fee = seller_1_fee + buyer_1_fee
  let bid_2_fee = seller_2_fee + buyer_2_fee
  let ofee =
    Output {
      value: value.from_lovelace(bid_1_fee + bid_2_fee),
      address: fee_addr,
      datum: NoDatum,
      reference_script: None,
    }
  let obid_1 =
    bid_like(
      yield: 10,
      owner: "owner_1",
      from_epoch: 400,
      to_epoch: 500,
      quantity: bid_1.quantity - bond_sell_qty_1,
    )
  let obuyer_1 =
    Output {
      value: value.lovelace_of(ibid_1.output.value) + value.lovelace_of(
        ibid_2.output.value,
      ) - value.lovelace_of(obid_1.value) - bid_1_fee - bid_2_fee - seller_1_receive - seller_2_receive
        |> value.from_lovelace
        |> value.add(bond_pid, bond_name, bond_sell_qty_1)
        |> value.add(bond_pid, bond_name, bid_2.quantity),
      address: get_buyer_address(ibid_1.output),
      datum: NoDatum,
      reference_script: None,
    }
  let oseller =
    iseller.output
      |> add_asset(
          ada_policy_id,
          ada_asset_name,
          seller_2_receive + seller_1_receive - seller_1_fee - seller_2_fee,
        )
      |> add_asset(bond_pid, bond_name, -bond_sell_qty_1 - bid_2.quantity)
  let t = transaction.placeholder()
  let tx =
    Transaction {
      ..t,
      validity_range: validity_range,
      reference_inputs: [
        Input {
          output_reference: OutputReference(TransactionId("es_01"), 0),
          output: oescrow,
        },
      ],
      redeemers: t.redeemers
        |> dict.insert(
            Spend(ibid_1.output_reference),
            Sell {
              exchange_fee: bid_1_fee,
              seller_receive: seller_1_receive,
              offers: [(bond_pid, bond_name, bond_sell_qty_1)],
              cont_idx: Some(3),
            },
            purpose_compare,
          )
        |> dict.insert(
            Spend(ibid_2.output_reference),
            Sell {
              exchange_fee: bid_2_fee,
              seller_receive: seller_2_receive,
              offers: [(bond_pid, bond_name, bid_2.quantity)],
              cont_idx: None,
            },
            purpose_compare,
          )
        |> dict.insert(
            WithdrawFrom(stake_credential_like(multi_bid_skh)),
            SellMulti { bid_skh },
            purpose_compare,
          ),
      inputs: [ibid_1, ibid_2, iseller],
      outputs: [obuyer_1, oseller, ofee, obid_1],
    }
  and {
    withdraw.constraint(
      ScriptContext { purpose: Spend(ibid_1.output_reference), transaction: tx },
      cfg,
      bid_skh,
      [script_blacklist],
    ),
    sell.constraint(
      ScriptContext { purpose: Spend(ibid_1.output_reference), transaction: tx },
      multi_bid_skh,
    ),
  }
}

test succ_when_fulfill_fully_other_tokens_to_buyer() {
  let (other_pid, other_tkn) = ("other_pid", "other_tkn")
  let cfg = get_config_limit_mainnet()
  let fee_addr = cfg.exchange.fee_addr
  expect [(bond_pid, _bond_type)] = dict.values(cfg.escrow)
  let bond_name = "bond_name"
  let ibid_1 =
    Input {
      output_reference: OutputReference(TransactionId("tx_bid_1"), 0),
      output: bid_like(
        yield: 10,
        owner: "owner_1",
        from_epoch: 400,
        to_epoch: 500,
        quantity: 10,
      )
        |> add_asset(other_pid, other_tkn, 1),
    }
  let bid_1 = get_bid_datum(ibid_1.output)
  let ibid_2 =
    Input {
      output_reference: OutputReference(TransactionId("tx_bid_2"), 1),
      output: bid_like(
        yield: 10,
        owner: "owner_1",
        from_epoch: 400,
        to_epoch: 500,
        quantity: 10,
      ),
    }
  let bid_2 = get_bid_datum(ibid_2.output)
  let oescrow =
    escrow_like(
      epo_rewards: 1 * ada,
      start: 10,
      duration: 150,
      bond_amount: 100,
      bond_symbol: bond_pid,
      token_name: bond_name,
      buffer: 10,
    )
  let iseller =
    Input {
      output_reference: OutputReference(TransactionId("tx_seller"), 1),
      output: Output {
        value: value.from_lovelace(2 * ada)
          |> value.add(bond_pid, bond_name, 50),
        address: from_verification_key("seller_pk"),
        datum: NoDatum,
        reference_script: None,
      },
    }
  let validity_range = entirely_between(1700553367000, 1700553370000)
  expect Finite(now) = validity_range.lower_bound.bound_type
  let (buyer_1_fee, seller_1_fee, seller_1_receive) =
    calculate_fee(
      cfg,
      get_escrow_datum(oescrow),
      bid_1.quantity,
      bid_1.requested_yield,
      now,
    )
  let (buyer_2_fee, seller_2_fee, seller_2_receive) =
    calculate_fee(
      cfg,
      get_escrow_datum(oescrow),
      bid_2.quantity,
      bid_2.requested_yield,
      now,
    )
  let bid_1_fee = seller_1_fee + buyer_1_fee
  let bid_2_fee = seller_2_fee + buyer_2_fee
  let ofee =
    Output {
      value: value.from_lovelace(bid_1_fee + bid_2_fee),
      address: fee_addr,
      datum: NoDatum,
      reference_script: None,
    }
  let oseller =
    iseller.output
      |> add_asset(
          ada_policy_id,
          ada_asset_name,
          seller_2_receive + seller_1_receive - seller_1_fee - seller_2_fee,
        )
      |> add_asset(bond_pid, bond_name, -bid_1.quantity - bid_2.quantity)
  let obuyer_1 =
    Output {
      value: value.lovelace_of(ibid_1.output.value) + value.lovelace_of(
        ibid_2.output.value,
      ) - bid_1_fee - bid_2_fee - seller_1_receive - seller_2_receive
        |> value.from_lovelace
        |> value.add(other_pid, other_tkn, 1)
        |> value.add(bond_pid, bond_name, bid_2.quantity)
        |> value.add(bond_pid, bond_name, bid_1.quantity),
      address: get_buyer_address(ibid_1.output),
      datum: NoDatum,
      reference_script: None,
    }
  let t = transaction.placeholder()
  let tx =
    Transaction {
      ..t,
      validity_range: validity_range,
      reference_inputs: [
        Input {
          output_reference: OutputReference(TransactionId("es_01"), 0),
          output: oescrow,
        },
      ],
      redeemers: t.redeemers
        |> dict.insert(
            Spend(ibid_1.output_reference),
            Sell {
              exchange_fee: bid_1_fee,
              seller_receive: seller_1_receive,
              offers: [(bond_pid, bond_name, bid_1.quantity)],
              cont_idx: None,
            },
            purpose_compare,
          )
        |> dict.insert(
            Spend(ibid_2.output_reference),
            Sell {
              exchange_fee: bid_2_fee,
              seller_receive: seller_2_receive,
              offers: [(bond_pid, bond_name, bid_2.quantity)],
              cont_idx: None,
            },
            purpose_compare,
          )
        |> dict.insert(
            WithdrawFrom(stake_credential_like(multi_bid_skh)),
            SellMulti { bid_skh },
            purpose_compare,
          ),
      inputs: [ibid_1, ibid_2, iseller],
      outputs: [obuyer_1, oseller, ofee],
    }
  and {
    withdraw.constraint(
      ScriptContext { purpose: Spend(ibid_1.output_reference), transaction: tx },
      cfg,
      bid_skh,
      [script_blacklist],
    ),
    sell.constraint(
      ScriptContext { purpose: Spend(ibid_1.output_reference), transaction: tx },
      multi_bid_skh,
    ),
  }
}

test fail_when_fulfill_fully_but_drain_other_tokens() fail {
  let (other_pid, other_tkn) = ("other_pid", "other_tkn")
  let cfg = get_config_limit_mainnet()
  let fee_addr = cfg.exchange.fee_addr
  expect [(bond_pid, _bond_type)] = dict.values(cfg.escrow)
  let bond_name = "bond_name"
  let ibid_1 =
    Input {
      output_reference: OutputReference(TransactionId("tx_bid_1"), 0),
      output: bid_like(
        yield: 10,
        owner: "owner_1",
        from_epoch: 400,
        to_epoch: 500,
        quantity: 10,
      )
        |> add_asset(other_pid, other_tkn, 1),
    }
  let bid_1 = get_bid_datum(ibid_1.output)
  let ibid_2 =
    Input {
      output_reference: OutputReference(TransactionId("tx_bid_2"), 1),
      output: bid_like(
        yield: 10,
        owner: "owner_1",
        from_epoch: 400,
        to_epoch: 500,
        quantity: 10,
      ),
    }
  let bid_2 = get_bid_datum(ibid_2.output)
  let oescrow =
    escrow_like(
      epo_rewards: 1 * ada,
      start: 10,
      duration: 150,
      bond_amount: 100,
      bond_symbol: bond_pid,
      token_name: bond_name,
      buffer: 10,
    )
  let iseller =
    Input {
      output_reference: OutputReference(TransactionId("tx_seller"), 1),
      output: Output {
        value: value.from_lovelace(2 * ada)
          |> value.add(bond_pid, bond_name, 50),
        address: from_verification_key("seller_pk"),
        datum: NoDatum,
        reference_script: None,
      },
    }
  let validity_range = entirely_between(1700553367000, 1700553370000)
  expect Finite(now) = validity_range.lower_bound.bound_type
  let (buyer_1_fee, seller_1_fee, seller_1_receive) =
    calculate_fee(
      cfg,
      get_escrow_datum(oescrow),
      bid_1.quantity,
      bid_1.requested_yield,
      now,
    )
  let (buyer_2_fee, seller_2_fee, seller_2_receive) =
    calculate_fee(
      cfg,
      get_escrow_datum(oescrow),
      bid_2.quantity,
      bid_2.requested_yield,
      now,
    )
  let bid_1_fee = seller_1_fee + buyer_1_fee
  let bid_2_fee = seller_2_fee + buyer_2_fee
  let ofee =
    Output {
      value: value.from_lovelace(bid_1_fee + bid_2_fee),
      address: fee_addr,
      datum: NoDatum,
      reference_script: None,
    }
  let oseller =
    iseller.output
      |> add_asset(
          ada_policy_id,
          ada_asset_name,
          seller_2_receive + seller_1_receive - seller_1_fee - seller_2_fee,
        )
      |> add_asset(bond_pid, bond_name, -bid_1.quantity - bid_2.quantity)
      |> add_asset(other_pid, other_tkn, 1)
  let obuyer_1 =
    Output {
      value: value.lovelace_of(ibid_1.output.value) + value.lovelace_of(
        ibid_2.output.value,
      ) - bid_1_fee - bid_2_fee - seller_1_receive - seller_2_receive
        |> value.from_lovelace
        |> value.add(bond_pid, bond_name, bid_2.quantity)
        |> value.add(bond_pid, bond_name, bid_1.quantity),
      address: get_buyer_address(ibid_1.output),
      datum: NoDatum,
      reference_script: None,
    }
  let t = transaction.placeholder()
  let tx =
    Transaction {
      ..t,
      validity_range: validity_range,
      reference_inputs: [
        Input {
          output_reference: OutputReference(TransactionId("es_01"), 0),
          output: oescrow,
        },
      ],
      redeemers: t.redeemers
        |> dict.insert(
            Spend(ibid_1.output_reference),
            Sell {
              exchange_fee: bid_1_fee,
              seller_receive: seller_1_receive,
              offers: [(bond_pid, bond_name, bid_1.quantity)],
              cont_idx: None,
            },
            purpose_compare,
          )
        |> dict.insert(
            Spend(ibid_2.output_reference),
            Sell {
              exchange_fee: bid_2_fee,
              seller_receive: seller_2_receive,
              offers: [(bond_pid, bond_name, bid_2.quantity)],
              cont_idx: None,
            },
            purpose_compare,
          )
        |> dict.insert(
            WithdrawFrom(stake_credential_like(multi_bid_skh)),
            SellMulti { bid_skh },
            purpose_compare,
          ),
      inputs: [ibid_1, ibid_2, iseller],
      outputs: [obuyer_1, oseller, ofee],
    }
  and {
    withdraw.constraint(
      ScriptContext { purpose: Spend(ibid_1.output_reference), transaction: tx },
      cfg,
      bid_skh,
      [script_blacklist],
    ),
    sell.constraint(
      ScriptContext { purpose: Spend(ibid_1.output_reference), transaction: tx },
      multi_bid_skh,
    ),
  }
}

test succ_when_sc_bid_stake_key_is_key() {
  let cfg = get_config_limit_mainnet()
  let fee_addr = cfg.exchange.fee_addr
  let sc_bid_stake_key_hash = #"080201"
  let owner_address =
    from_verification_key(get_buyer_address_hash())
      |> with_delegation_key(sc_bid_stake_key_hash)
  expect [(bond_pid, _bond_type)] = dict.values(cfg.escrow)
  let bond_name_1 = "bond_name_1"
  let bond_name_2 = "bond_name_2"
  let ibid_1_qty = 10
  let ibid_2_qty = 10
  let ibid_1 =
    Input {
      output_reference: OutputReference(TransactionId("tx_bid_1"), 0),
      output: Output {
        value: value.from_lovelace(
          ibid_1_qty * 100 * ada + 2 * ada * ibid_1_qty + 10,
        ),
        address: from_script(bid_skh)
          |> with_delegation_key(sc_bid_stake_key_hash),
        datum: InlineDatum(
          gen_bid_limit_multi_datum(
            owner_address,
            400,
            500,
            ibid_1_qty,
            10,
            [DanogoBond],
          ),
        ),
        reference_script: None,
      },
    }
  let bid_1 = get_bid_datum(ibid_1.output)
  let ibid_2 =
    Input {
      output_reference: OutputReference(TransactionId("tx_bid_2"), 1),
      output: Output {
        value: value.from_lovelace(
          ibid_2_qty * 100 * ada + 2 * ada * ibid_2_qty + 10,
        ),
        address: from_script(bid_skh)
          |> with_delegation_key(sc_bid_stake_key_hash),
        datum: InlineDatum(
          gen_bid_limit_multi_datum(
            owner_address,
            400,
            500,
            ibid_2_qty,
            10,
            [DanogoBond],
          ),
        ),
        reference_script: None,
      },
    }
  let bid_2 = get_bid_datum(ibid_2.output)
  let oescrow_1 =
    escrow_like(
      epo_rewards: 1 * ada,
      start: 10,
      duration: 150,
      bond_amount: 100,
      bond_symbol: bond_pid,
      token_name: bond_name_1,
      buffer: 10,
    )
  let oescrow_2 =
    escrow_like(
      epo_rewards: 1 * ada,
      start: 10,
      duration: 150,
      bond_amount: 100,
      bond_symbol: bond_pid,
      token_name: bond_name_2,
      buffer: 10,
    )
  let iseller =
    Input {
      output_reference: OutputReference(TransactionId("tx_seller"), 1),
      output: Output {
        value: value.from_lovelace(2 * ada)
          |> value.add(bond_pid, bond_name_1, 10)
          |> value.add(bond_pid, bond_name_2, 10),
        address: from_verification_key("seller_pk"),
        datum: NoDatum,
        reference_script: None,
      },
    }
  let validity_range = entirely_between(1700553367000, 1700553370000)
  expect Finite(now) = validity_range.lower_bound.bound_type
  let (buyer_1_fee, seller_1_fee, seller_1_receive) =
    calculate_fee(
      cfg,
      get_escrow_datum(oescrow_1),
      bid_1.quantity,
      bid_1.requested_yield,
      now,
    )
  let (buyer_2_fee, seller_2_fee, seller_2_receive) =
    calculate_fee(
      cfg,
      get_escrow_datum(oescrow_2),
      bid_2.quantity,
      bid_2.requested_yield,
      now,
    )
  let bid_1_fee = seller_1_fee + buyer_1_fee
  let bid_2_fee = seller_2_fee + buyer_2_fee
  let ofee =
    Output {
      value: value.from_lovelace(bid_1_fee + bid_2_fee),
      address: fee_addr,
      datum: NoDatum,
      reference_script: None,
    }
  let oseller =
    iseller.output
      |> add_asset(bond_pid, bond_name_1, -bid_1.quantity)
      |> add_asset(bond_pid, bond_name_2, -bid_2.quantity)
  let obuyer_1 =
    Output {
      value: value.lovelace_of(ibid_1.output.value) + value.lovelace_of(
        ibid_2.output.value,
      ) - bid_1_fee - bid_2_fee - seller_1_receive - seller_2_receive
        |> value.from_lovelace
        |> value.add(bond_pid, bond_name_2, bid_2.quantity)
        |> value.add(bond_pid, bond_name_1, bid_1.quantity),
      address: get_buyer_address(ibid_1.output),
      datum: NoDatum,
      reference_script: None,
    }
  let t = transaction.placeholder()
  let tx =
    Transaction {
      ..t,
      validity_range: validity_range,
      reference_inputs: [
        Input {
          output_reference: OutputReference(TransactionId("es_01"), 0),
          output: oescrow_1,
        },
        Input {
          output_reference: OutputReference(TransactionId("es_02"), 0),
          output: oescrow_2,
        },
      ],
      redeemers: t.redeemers
        |> dict.insert(
            Spend(ibid_1.output_reference),
            Sell {
              exchange_fee: bid_1_fee,
              seller_receive: seller_1_receive,
              offers: [(bond_pid, bond_name_1, bid_1.quantity)],
              cont_idx: None,
            },
            purpose_compare,
          )
        |> dict.insert(
            Spend(ibid_2.output_reference),
            Sell {
              exchange_fee: bid_2_fee,
              seller_receive: seller_2_receive,
              offers: [(bond_pid, bond_name_2, bid_2.quantity)],
              cont_idx: None,
            },
            purpose_compare,
          )
        |> dict.insert(
            WithdrawFrom(stake_credential_like(multi_bid_skh)),
            SellMulti { bid_skh },
            purpose_compare,
          ),
      inputs: [ibid_1, ibid_2, iseller],
      outputs: [obuyer_1, oseller, ofee],
    }
  and {
    withdraw.constraint(
      ScriptContext { purpose: Spend(ibid_1.output_reference), transaction: tx },
      cfg,
      bid_skh,
      [script_blacklist],
    ),
    sell.constraint(
      ScriptContext { purpose: Spend(ibid_1.output_reference), transaction: tx },
      multi_bid_skh,
    ),
  }
}

test succ_when_sc_bid_stake_key_is_script() {
  let cfg = get_config_limit_mainnet()
  let fee_addr = cfg.exchange.fee_addr
  let sc_bid_stake_key_hash = #"080201"
  let owner_address =
    from_verification_key(get_buyer_address_hash())
      |> with_delegation_script(sc_bid_stake_key_hash)
  expect [(bond_pid, _bond_type)] = dict.values(cfg.escrow)
  let bond_name_1 = "bond_name_1"
  let bond_name_2 = "bond_name_2"
  let ibid_1_qty = 10
  let ibid_2_qty = 10
  let ibid_1 =
    Input {
      output_reference: OutputReference(TransactionId("tx_bid_1"), 0),
      output: Output {
        value: value.from_lovelace(
          ibid_1_qty * 100 * ada + 2 * ada * ibid_1_qty + 10,
        ),
        address: from_script(bid_skh)
          |> with_delegation_script(sc_bid_stake_key_hash),
        datum: InlineDatum(
          gen_bid_limit_multi_datum(
            owner_address,
            400,
            500,
            ibid_1_qty,
            10,
            [DanogoBond],
          ),
        ),
        reference_script: None,
      },
    }
  let bid_1 = get_bid_datum(ibid_1.output)
  let ibid_2 =
    Input {
      output_reference: OutputReference(TransactionId("tx_bid_2"), 1),
      output: Output {
        value: value.from_lovelace(
          ibid_2_qty * 100 * ada + 2 * ada * ibid_2_qty + 10,
        ),
        address: from_script(bid_skh)
          |> with_delegation_script(sc_bid_stake_key_hash),
        datum: InlineDatum(
          gen_bid_limit_multi_datum(
            owner_address,
            400,
            500,
            ibid_2_qty,
            10,
            [DanogoBond],
          ),
        ),
        reference_script: None,
      },
    }
  let bid_2 = get_bid_datum(ibid_2.output)
  let oescrow_1 =
    escrow_like(
      epo_rewards: 1 * ada,
      start: 10,
      duration: 150,
      bond_amount: 100,
      bond_symbol: bond_pid,
      token_name: bond_name_1,
      buffer: 10,
    )
  let oescrow_2 =
    escrow_like(
      epo_rewards: 1 * ada,
      start: 10,
      duration: 150,
      bond_amount: 100,
      bond_symbol: bond_pid,
      token_name: bond_name_2,
      buffer: 10,
    )
  let iseller =
    Input {
      output_reference: OutputReference(TransactionId("tx_seller"), 1),
      output: Output {
        value: value.from_lovelace(2 * ada)
          |> value.add(bond_pid, bond_name_1, 10)
          |> value.add(bond_pid, bond_name_2, 10),
        address: from_verification_key("seller_pk")
          |> with_delegation_script("seller_pk"),
        datum: NoDatum,
        reference_script: None,
      },
    }
  let validity_range = entirely_between(1700553367000, 1700553370000)
  expect Finite(now) = validity_range.lower_bound.bound_type
  let (buyer_1_fee, seller_1_fee, seller_1_receive) =
    calculate_fee(
      cfg,
      get_escrow_datum(oescrow_1),
      bid_1.quantity,
      bid_1.requested_yield,
      now,
    )
  let (buyer_2_fee, seller_2_fee, seller_2_receive) =
    calculate_fee(
      cfg,
      get_escrow_datum(oescrow_2),
      bid_2.quantity,
      bid_2.requested_yield,
      now,
    )
  let bid_1_fee = seller_1_fee + buyer_1_fee
  let bid_2_fee = seller_2_fee + buyer_2_fee
  let ofee =
    Output {
      value: value.from_lovelace(bid_1_fee + bid_2_fee),
      address: fee_addr,
      datum: NoDatum,
      reference_script: None,
    }
  let oseller =
    iseller.output
      |> add_asset(bond_pid, bond_name_1, -bid_1.quantity)
      |> add_asset(bond_pid, bond_name_2, -bid_2.quantity)
  let obuyer_1 =
    Output {
      value: value.lovelace_of(ibid_1.output.value) + value.lovelace_of(
        ibid_2.output.value,
      ) - bid_1_fee - bid_2_fee - seller_1_receive - seller_2_receive
        |> value.from_lovelace
        |> value.add(bond_pid, bond_name_2, bid_2.quantity)
        |> value.add(bond_pid, bond_name_1, bid_1.quantity),
      address: owner_address,
      datum: NoDatum,
      reference_script: None,
    }
  let t = transaction.placeholder()
  let tx =
    Transaction {
      ..t,
      validity_range: validity_range,
      reference_inputs: [
        Input {
          output_reference: OutputReference(TransactionId("es_01"), 0),
          output: oescrow_1,
        },
        Input {
          output_reference: OutputReference(TransactionId("es_02"), 0),
          output: oescrow_2,
        },
      ],
      redeemers: t.redeemers
        |> dict.insert(
            Spend(ibid_1.output_reference),
            Sell {
              exchange_fee: bid_1_fee,
              seller_receive: seller_1_receive,
              offers: [(bond_pid, bond_name_1, bid_1.quantity)],
              cont_idx: None,
            },
            purpose_compare,
          )
        |> dict.insert(
            Spend(ibid_2.output_reference),
            Sell {
              exchange_fee: bid_2_fee,
              seller_receive: seller_2_receive,
              offers: [(bond_pid, bond_name_2, bid_2.quantity)],
              cont_idx: None,
            },
            purpose_compare,
          )
        |> dict.insert(
            WithdrawFrom(stake_credential_like(multi_bid_skh)),
            SellMulti { bid_skh },
            purpose_compare,
          ),
      inputs: [ibid_1, ibid_2, iseller],
      outputs: [obuyer_1, oseller, ofee],
    }
  and {
    withdraw.constraint(
      ScriptContext { purpose: Spend(ibid_1.output_reference), transaction: tx },
      cfg,
      bid_skh,
      [script_blacklist],
    ),
    sell.constraint(
      ScriptContext { purpose: Spend(ibid_1.output_reference), transaction: tx },
      multi_bid_skh,
    ),
  }
}

test fail_when_buyer_stake_key_is_wrong() fail {
  let cfg = get_config_limit_mainnet()
  let fee_addr = cfg.exchange.fee_addr
  let sc_bid_stake_key_hash = #"080201"
  let sc_bid_stake_key_hash_fake = #"080202"
  let owner_address =
    from_verification_key(get_buyer_address_hash())
      |> with_delegation_script(sc_bid_stake_key_hash)
  expect [(bond_pid, _bond_type)] = dict.values(cfg.escrow)
  let bond_name_1 = "bond_name_1"
  let bond_name_2 = "bond_name_2"
  let ibid_1_qty = 10
  let ibid_2_qty = 10
  let ibid_1 =
    Input {
      output_reference: OutputReference(TransactionId("tx_bid_1"), 0),
      output: Output {
        value: value.from_lovelace(
          ibid_1_qty * 100 * ada + 2 * ada * ibid_1_qty + 10,
        ),
        address: from_script(bid_skh)
          |> with_delegation_script(sc_bid_stake_key_hash),
        datum: InlineDatum(
          gen_bid_limit_multi_datum(
            owner_address,
            400,
            500,
            ibid_1_qty,
            10,
            [DanogoBond],
          ),
        ),
        reference_script: None,
      },
    }
  let bid_1 = get_bid_datum(ibid_1.output)
  let ibid_2 =
    Input {
      output_reference: OutputReference(TransactionId("tx_bid_2"), 1),
      output: Output {
        value: value.from_lovelace(
          ibid_2_qty * 100 * ada + 2 * ada * ibid_2_qty + 10,
        ),
        address: from_script(bid_skh)
          |> with_delegation_script(sc_bid_stake_key_hash),
        datum: InlineDatum(
          gen_bid_limit_multi_datum(
            owner_address,
            400,
            500,
            ibid_2_qty,
            10,
            [DanogoBond],
          ),
        ),
        reference_script: None,
      },
    }
  let bid_2 = get_bid_datum(ibid_2.output)
  let oescrow_1 =
    escrow_like(
      epo_rewards: 1 * ada,
      start: 10,
      duration: 150,
      bond_amount: 100,
      bond_symbol: bond_pid,
      token_name: bond_name_1,
      buffer: 10,
    )
  let oescrow_2 =
    escrow_like(
      epo_rewards: 1 * ada,
      start: 10,
      duration: 150,
      bond_amount: 100,
      bond_symbol: bond_pid,
      token_name: bond_name_2,
      buffer: 10,
    )
  let iseller =
    Input {
      output_reference: OutputReference(TransactionId("tx_seller"), 1),
      output: Output {
        value: value.from_lovelace(2 * ada)
          |> value.add(bond_pid, bond_name_1, 10)
          |> value.add(bond_pid, bond_name_2, 10),
        address: from_verification_key("seller_pk")
          |> with_delegation_script("seller_pk"),
        datum: NoDatum,
        reference_script: None,
      },
    }
  let validity_range = entirely_between(1700553367000, 1700553370000)
  expect Finite(now) = validity_range.lower_bound.bound_type
  let (buyer_1_fee, seller_1_fee, seller_1_receive) =
    calculate_fee(
      cfg,
      get_escrow_datum(oescrow_1),
      bid_1.quantity,
      bid_1.requested_yield,
      now,
    )
  let (buyer_2_fee, seller_2_fee, seller_2_receive) =
    calculate_fee(
      cfg,
      get_escrow_datum(oescrow_2),
      bid_2.quantity,
      bid_2.requested_yield,
      now,
    )
  let bid_1_fee = seller_1_fee + buyer_1_fee
  let bid_2_fee = seller_2_fee + buyer_2_fee
  let ofee =
    Output {
      value: value.from_lovelace(bid_1_fee + bid_2_fee),
      address: fee_addr,
      datum: NoDatum,
      reference_script: None,
    }
  let oseller =
    iseller.output
      |> add_asset(bond_pid, bond_name_1, -bid_1.quantity)
      |> add_asset(bond_pid, bond_name_2, -bid_2.quantity)
  let obuyer_1 =
    Output {
      value: value.lovelace_of(ibid_1.output.value) + value.lovelace_of(
        ibid_2.output.value,
      ) - bid_1_fee - bid_2_fee - seller_1_receive - seller_2_receive
        |> value.from_lovelace
        |> value.add(bond_pid, bond_name_2, bid_2.quantity)
        |> value.add(bond_pid, bond_name_1, bid_1.quantity),
      address: from_verification_key(get_buyer_address_hash())
        |> with_delegation_script(sc_bid_stake_key_hash_fake),
      datum: NoDatum,
      reference_script: None,
    }
  let t = transaction.placeholder()
  let tx =
    Transaction {
      ..t,
      validity_range: validity_range,
      reference_inputs: [
        Input {
          output_reference: OutputReference(TransactionId("es_01"), 0),
          output: oescrow_1,
        },
        Input {
          output_reference: OutputReference(TransactionId("es_02"), 0),
          output: oescrow_2,
        },
      ],
      redeemers: t.redeemers
        |> dict.insert(
            Spend(ibid_1.output_reference),
            Sell {
              exchange_fee: bid_1_fee,
              seller_receive: seller_1_receive,
              offers: [(bond_pid, bond_name_1, bid_1.quantity)],
              cont_idx: None,
            },
            purpose_compare,
          )
        |> dict.insert(
            Spend(ibid_2.output_reference),
            Sell {
              exchange_fee: bid_2_fee,
              seller_receive: seller_2_receive,
              offers: [(bond_pid, bond_name_2, bid_2.quantity)],
              cont_idx: None,
            },
            purpose_compare,
          )
        |> dict.insert(
            WithdrawFrom(stake_credential_like(multi_bid_skh)),
            SellMulti { bid_skh },
            purpose_compare,
          ),
      inputs: [ibid_1, ibid_2, iseller],
      outputs: [obuyer_1, oseller, ofee],
    }
  and {
    withdraw.constraint(
      ScriptContext { purpose: Spend(ibid_1.output_reference), transaction: tx },
      cfg,
      bid_skh,
      [script_blacklist],
    ),
    sell.constraint(
      ScriptContext { purpose: Spend(ibid_1.output_reference), transaction: tx },
      multi_bid_skh,
    ),
  }
}
