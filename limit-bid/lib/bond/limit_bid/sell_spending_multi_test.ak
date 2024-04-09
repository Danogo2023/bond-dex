use aiken/bytearray
use aiken/cbor
use aiken/dict
use aiken/interval.{Finite, entirely_between}
use aiken/time.{PosixTime}
use aiken/transaction.{
  InlineDatum, Input, NoDatum, Output, OutputReference, ScriptContext,
  ScriptPurpose, Spend, Transaction, TransactionId,
}
use aiken/transaction/credential.{
  from_script, from_verification_key, with_delegation_key,
}
use aiken/transaction/value.{AssetName, PolicyId, ada_asset_name, ada_policy_id}
use bond/limit_bid/sell
use bond/limit_bid/types.{Sell}
use bond/types.{
  BidLimitMulti, BondConfigLimit, DanogoBond, EscrowDatum, ExchangeConfigLimit,
} as bond_types
use bond/utils.{get_day_to_maturity, get_price_of_bond} as bond_utils
use bond/v2/fixture.{get_config_limit_mainnet, get_escrow_policy_id}
use common/pvalue

const ada = 1_000_000

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
    address: from_script("bid1"),
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
           ),
      inputs: [ibid_1, ibid_2, iseller],
      outputs: [obuyer_1, oseller, ofee],
    }
  and {
    sell.constraint(
      ScriptContext { purpose: Spend(ibid_1.output_reference), transaction: tx },
      cfg,
      bid_1,
      bid_1_fee,
      seller_1_receive,
      [(bond_pid, bond_name, bid_1.quantity)],
      None,
    )?,
    sell.constraint(
      ScriptContext { purpose: Spend(ibid_2.output_reference), transaction: tx },
      cfg,
      bid_2,
      bid_2_fee,
      seller_2_receive,
      [(bond_pid, bond_name, bid_2.quantity)],
      None,
    )?,
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
           ),
      inputs: [ibid_1, ibid_2, iseller],
      outputs: [obuyer_1, oseller, ofee],
    }
  and {
    sell.constraint(
      ScriptContext { purpose: Spend(ibid_1.output_reference), transaction: tx },
      cfg,
      bid_1,
      bid_1_fee,
      seller_1_receive,
      [(bond_pid, bond_name_1, bid_1.quantity)],
      None,
    )?,
    sell.constraint(
      ScriptContext { purpose: Spend(ibid_2.output_reference), transaction: tx },
      cfg,
      bid_2,
      bid_2_fee,
      seller_2_receive,
      [(bond_pid, bond_name_2, bid_2.quantity)],
      None,
    )?,
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
           ),
      inputs: [ibid_1, ibid_2, iseller],
      outputs: [obuyer_1, oseller, ofee, oescrow],
    }
  and {
    sell.constraint(
      ScriptContext { purpose: Spend(ibid_1.output_reference), transaction: tx },
      cfg,
      bid_1,
      bid_1_fee,
      seller_1_receive,
      [(bond_pid, bond_name, bid_1.quantity)],
      None,
    )?,
    sell.constraint(
      ScriptContext { purpose: Spend(ibid_2.output_reference), transaction: tx },
      cfg,
      bid_2,
      bid_2_fee,
      seller_2_receive,
      [(bond_pid, bond_name, bid_2.quantity)],
      None,
    )?,
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
           ),
      inputs: [ibid_1, ibid_2, iseller],
      outputs: [obuyer_1, oseller, ofee, oescrow],
    }
  and {
    sell.constraint(
      ScriptContext { purpose: Spend(ibid_1.output_reference), transaction: tx },
      cfg,
      bid_1,
      bid_1_fee,
      seller_1_receive,
      [(bond_pid, bond_name, bid_1.quantity)],
      None,
    )?,
    sell.constraint(
      ScriptContext { purpose: Spend(ibid_2.output_reference), transaction: tx },
      cfg,
      bid_2,
      bid_2_fee,
      seller_2_receive,
      [(bond_pid, bond_name, bid_2.quantity)],
      None,
    )?,
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
           ),
      inputs: [ibid_1, ibid_2, iseller_1, iseller_2],
      outputs: [obuyer_1, oseller_1, oseller_2, ofee],
    }
  and {
    sell.constraint(
      ScriptContext { purpose: Spend(ibid_1.output_reference), transaction: tx },
      cfg,
      bid_1,
      bid_1_fee,
      seller_1_receive,
      [(bond_pid, bond_name, bid_1.quantity)],
      None,
    )?,
    sell.constraint(
      ScriptContext { purpose: Spend(ibid_2.output_reference), transaction: tx },
      cfg,
      bid_2,
      bid_2_fee,
      seller_2_receive,
      [(bond_pid, bond_name, bid_2.quantity)],
      None,
    )?,
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
           ),
      inputs: [ibid_1, ibid_2, iseller_1, iseller_2],
      outputs: [obuyer_1, oseller_1, oseller_2, ofee],
    }
  and {
    sell.constraint(
      ScriptContext { purpose: Spend(ibid_1.output_reference), transaction: tx },
      cfg,
      bid_1,
      bid_1_fee,
      seller_1_receive,
      [(bond_pid, bond_name_1, bid_1.quantity)],
      None,
    )?,
    sell.constraint(
      ScriptContext { purpose: Spend(ibid_2.output_reference), transaction: tx },
      cfg,
      bid_2,
      bid_2_fee,
      seller_2_receive,
      [(bond_pid, bond_name_2, bid_2.quantity)],
      None,
    )?,
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
           ),
      inputs: [ibid_1, ibid_2, iseller],
      outputs: [obuyer_1, obuyer_2, oseller, ofee],
    }
  and {
    sell.constraint(
      ScriptContext { purpose: Spend(ibid_1.output_reference), transaction: tx },
      cfg,
      bid_1,
      bid_1_fee,
      seller_1_receive,
      [(bond_pid, bond_name, bid_1.quantity)],
      None,
    )?,
    sell.constraint(
      ScriptContext { purpose: Spend(ibid_2.output_reference), transaction: tx },
      cfg,
      bid_2,
      bid_2_fee,
      seller_2_receive,
      [(bond_pid, bond_name, bid_2.quantity)],
      None,
    )?,
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
  let obid_1 = obid_1_remain.output
  let obuyer_1 =
    Output {
      value: value.lovelace_of(ibid_1.output.value) + value.lovelace_of(
        ibid_2.output.value,
      ) - value.lovelace_of(obid_1_remain.output.value) - bid_1_fee - bid_2_fee - seller_1_receive - seller_2_receive
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
           ),
      inputs: [ibid_1, ibid_2, iseller],
      outputs: [obuyer_1, oseller, ofee, obid_1],
    }
  and {
    sell.constraint(
      ScriptContext { purpose: Spend(ibid_1.output_reference), transaction: tx },
      cfg,
      bid_1,
      bid_1_fee,
      seller_1_receive,
      [(bond_pid, bond_name, bond_sell_qty_1)],
      Some(3),
    )?,
    sell.constraint(
      ScriptContext { purpose: Spend(ibid_2.output_reference), transaction: tx },
      cfg,
      bid_2,
      bid_2_fee,
      seller_2_receive,
      [(bond_pid, bond_name, bid_2.quantity)],
      None,
    )?,
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
               cont_idx: Some(4),
             },
             purpose_compare,
           )
        |> dict.insert(
             Spend(ibid_2.output_reference),
             Sell {
               exchange_fee: bid_2_fee,
               seller_receive: seller_2_receive,
               offers: [(bond_pid, bond_name, bond_sell_qty_2)],
               cont_idx: Some(5),
             },
             purpose_compare,
           ),
      inputs: [ibid_1, ibid_2, iseller],
      outputs: [obuyer_1, oseller, ofee, obid_1, obid_2],
    }
  and {
    sell.constraint(
      ScriptContext { purpose: Spend(ibid_1.output_reference), transaction: tx },
      cfg,
      bid_1,
      bid_1_fee,
      seller_1_receive,
      [(bond_pid, bond_name, bond_sell_qty_1)],
      Some(2),
    )?,
    sell.constraint(
      ScriptContext { purpose: Spend(ibid_2.output_reference), transaction: tx },
      cfg,
      bid_2,
      bid_2_fee,
      seller_2_receive,
      [(bond_pid, bond_name, bond_sell_qty_2)],
      Some(2),
    )?,
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
  and {
    sell.constraint(
      ScriptContext { purpose: Spend(ibid_1.output_reference), transaction: tx },
      cfg,
      bid_1,
      bid_1_fee,
      seller_1_receive,
      [(bond_pid, bond_name_1, bid_1.quantity)],
      None,
    )?,
    sell.constraint(
      ScriptContext { purpose: Spend(ibid_2.output_reference), transaction: tx },
      cfg,
      bid_2,
      bid_2_fee,
      seller_2_receive,
      [(bond_pid, bond_name_2, bid_2.quantity)],
      None,
    )?,
  }
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
  and {
    sell.constraint(
      ScriptContext { purpose: Spend(ibid_1.output_reference), transaction: tx },
      cfg,
      bid_1,
      bid_1_fee,
      seller_1_receive,
      [(bond_pid, bond_name, bid_1.quantity)],
      None,
    )?,
    sell.constraint(
      ScriptContext { purpose: Spend(ibid_2.output_reference), transaction: tx },
      cfg,
      bid_2,
      bid_2_fee,
      seller_2_receive,
      [(bond_pid, bond_name, bid_2.quantity)],
      None,
    )?,
  }
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
  and {
    sell.constraint(
      ScriptContext { purpose: Spend(ibid_1.output_reference), transaction: tx },
      cfg,
      bid_1,
      bid_1_fee,
      seller_1_receive_modified,
      [(bond_pid, bond_name, bid_1.quantity)],
      None,
    )?,
    sell.constraint(
      ScriptContext { purpose: Spend(ibid_2.output_reference), transaction: tx },
      cfg,
      bid_2,
      bid_2_fee,
      seller_2_receive,
      [(bond_pid, bond_name, bid_2.quantity)],
      None,
    )?,
  }
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
  and {
    sell.constraint(
      ScriptContext { purpose: Spend(ibid_1.output_reference), transaction: tx },
      cfg,
      bid_1,
      bid_1_fee,
      seller_1_receive,
      [(bond_pid, bond_name, bid_1.quantity)],
      None,
    )?,
    sell.constraint(
      ScriptContext { purpose: Spend(ibid_2.output_reference), transaction: tx },
      cfg,
      bid_2,
      bid_2_fee,
      seller_2_receive_modified,
      [(bond_pid, bond_name, bid_2.quantity)],
      None,
    )?,
  }
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
  and {
    sell.constraint(
      ScriptContext { purpose: Spend(ibid_1.output_reference), transaction: tx },
      cfg,
      bid_1,
      bid_1_fee,
      // ↓ invalid
      1122,
      [(bond_pid, bond_name, bid_1.quantity)],
      None,
    )?,
    sell.constraint(
      ScriptContext { purpose: Spend(ibid_2.output_reference), transaction: tx },
      cfg,
      bid_2,
      bid_2_fee,
      seller_2_receive,
      [(bond_pid, bond_name, bid_2.quantity)],
      None,
    )?,
  }
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
  !and {
    sell.constraint(
      ScriptContext { purpose: Spend(ibid_1.output_reference), transaction: tx },
      cfg,
      bid_1,
      bid_1_fee,
      seller_1_receive,
      [(bond_pid, bond_name, bid_1.quantity)],
      Some(1),
    )?,
    sell.constraint(
      ScriptContext { purpose: Spend(ibid_2.output_reference), transaction: tx },
      cfg,
      bid_2,
      bid_2_fee,
      seller_2_receive,
      [(bond_pid, bond_name, bid_2.quantity)],
      None,
    )?,
  }
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
  and {
    sell.constraint(
      ScriptContext { purpose: Spend(ibid_1.output_reference), transaction: tx },
      cfg,
      bid_1,
      0,
      seller_1_receive,
      [(bond_pid, bond_name, bid_1.quantity)],
      None,
    )?,
    sell.constraint(
      ScriptContext { purpose: Spend(ibid_2.output_reference), transaction: tx },
      cfg,
      bid_2,
      bid_2_fee,
      seller_2_receive,
      [(bond_pid, bond_name, bid_2.quantity)],
      None,
    )?,
  }
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
               cont_idx: Some(4),
             },
             purpose_compare,
           )
        |> dict.insert(
             Spend(ibid_2.output_reference),
             Sell {
               exchange_fee: bid_2_fee,
               seller_receive: seller_2_receive,
               offers: [(bond_pid, bond_name, bond_sell_qty_2)],
               cont_idx: Some(5),
             },
             purpose_compare,
           ),
      inputs: [ibid_1, ibid_2, iseller],
      outputs: [obuyer_1, oseller, ofee, obid_1, obid_2],
    }
  and {
    sell.constraint(
      ScriptContext { purpose: Spend(ibid_1.output_reference), transaction: tx },
      cfg,
      bid_1,
      bid_1_fee,
      seller_1_receive,
      [(bond_pid, bond_name, bond_sell_qty_1)],
      Some(3),
    )?,
    sell.constraint(
      ScriptContext { purpose: Spend(ibid_2.output_reference), transaction: tx },
      cfg,
      bid_2,
      bid_2_fee,
      seller_2_receive,
      [(bond_pid, bond_name, bond_sell_qty_2)],
      Some(3),
    )?,
  }
}
