// Ask Making
use aiken/transaction.{
  DatumHash, InlineDatum, NoDatum, Output, ScriptContext, Spend,
}
use aiken/transaction/credential.{
  from_script, with_delegation_key, with_delegation_script,
}
use aiken/transaction/value.{AssetName, PolicyId}
use bond/common/fixture.{
  calc_escrow_full_info, gen_ask_making_datum, gen_bid_making_datum, gen_input,
  gen_output, gen_tampered_ask_making_datum, gen_tampered_bid_making_datum,
  get_ask_sc_address, get_bond_id_1, get_bond_id_2, get_bond_policy_id,
  get_buyer_address, get_config_making_mainnet, get_config_making_preview,
  get_escrow_address, get_escrow_address_unexpect, get_escrow_datum,
  get_escrow_policy_id, get_exchange_address, get_fraud_address,
  get_input_escrow, get_not_bond_policy_id, get_not_escrow_policy_id,
  get_seller_address, get_seller_address_hash,
}
use bond/common/utils.{get_price_of_bond}
use bond/making_ask/buy

const dummy_pid = "dummy_pid"

const dummy_tkn = "dummy_tkn"

fn add_asset(self: Output, pid: PolicyId, tkn: AssetName, qty: Int) {
  Output { ..self, value: self.value |> value.add(pid, tkn, qty) }
}

test succ_buyer_is_exchange() {
  let time_of_tx = 1681095094000
  let cfg = get_config_making_mainnet()
  let exchange_address = get_exchange_address()
  let owner_address = get_seller_address()
  let sc_in_datum_1 = gen_ask_making_datum(owner_address, 515)
  let revert_address = from_script(sc_in_datum_1.bid_sc)
  let bond_name_ask_1 = get_bond_id_1()
  let bond_name_ask_2 = get_bond_id_2()
  // get_escrow_datum(asset_name: AssetName, bond_amount: Int, epo_rewards: Int, duration: Int, start: Int)
  let escrow_bond_amount = 10000
  let escrow_epo_rewards = 753424657
  let escrow_duration = 72
  let escrow_datum =
    get_escrow_datum(
      bond_name_ask_1,
      escrow_bond_amount,
      escrow_epo_rewards,
      escrow_duration,
      63,
    )
  // => epoch_start = 22190 epoch_end = 22244
  let escrow_lovelace =
    escrow_bond_amount * 100_000_000 + escrow_epo_rewards * escrow_duration
  let escrow_full_info =
    calc_escrow_full_info(
      cfg.platform,
      escrow_lovelace,
      escrow_datum,
      time_of_tx,
    )
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  //
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_ask_1,
      1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  //
  let sc_in_bond_qty = 5
  let sc_in_lovelace = 2068800
  let sc_address = get_ask_sc_address()
  let sc_in_1 =
    gen_input(
      sc_address,
      sc_in_lovelace,
      Some(
        value.from_asset(get_bond_policy_id(), bond_name_ask_1, sc_in_bond_qty),
      ),
      InlineDatum(sc_in_datum_1),
    )
  let buyer_fee_ada = 3000000000
  let buyer_address = exchange_address
  let buyer_in_1 =
    gen_input(
      buyer_address,
      buyer_fee_ada,
      Some(value.from_asset(get_bond_policy_id(), bond_name_ask_2, 3)),
      NoDatum,
    )
  //
  let buyer_qty = 2
  let received_at_maturity = escrow_full_info.value_at_maturity * buyer_qty
  let received_with_yield = price_of_one_bond * buyer_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.maker_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.taker_fee / cfg.platform.basis.base
  //
  let sc_remaining_qty = sc_in_bond_qty - buyer_qty
  let min_ada_to_exchange =
    when sc_remaining_qty is {
      0 -> sc_in_lovelace
      _ -> 0
    }
  let exchange_received = exchange_fee_buyer + exchange_fee_seller

  let exchange_out_1 =
    gen_output(exchange_address, exchange_received, None, NoDatum)
  let owner_received =
    received_with_yield - exchange_fee_seller + min_ada_to_exchange
  let owner_out_bid_datum_1 =
    gen_bid_making_datum(owner_address, 463, 463, buyer_qty, 516)
  let owner_out_1 =
    gen_output(
      revert_address,
      owner_received,
      None,
      InlineDatum(owner_out_bid_datum_1),
    )
  let buyer_received =
    buyer_fee_ada + sc_in_lovelace - exchange_received - owner_received
  let buyer_out_1 =
    gen_output(
      buyer_address,
      buyer_received,
      Some(
        value.add(
          value.from_asset(get_bond_policy_id(), bond_name_ask_2, buyer_qty),
          get_bond_policy_id(),
          bond_name_ask_1,
          3,
        ),
      ),
      NoDatum,
    )
  let sc_out_1 =
    gen_output(
      sc_address,
      sc_in_lovelace - min_ada_to_exchange,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_ask_1,
          sc_remaining_qty,
        ),
      ),
      InlineDatum(sc_in_datum_1),
    )
  let tx =
    fixture.tx(
      [sc_in_1, buyer_in_1],
      [refer_in_1],
      [exchange_out_1, owner_out_1, buyer_out_1, sc_out_1],
      Some([get_seller_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  buy.spending(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    sc_in_datum_1,
    [],
  )
}

test succ_partial() {
  let time_of_tx = 1681095094000
  let cfg = get_config_making_mainnet()
  let owner_address = get_seller_address()
  let sc_in_datum_1 = gen_ask_making_datum(owner_address, 515)
  let revert_address = from_script(sc_in_datum_1.bid_sc)
  let bond_name_ask_1 = get_bond_id_1()
  let bond_name_ask_2 = get_bond_id_2()
  // get_escrow_datum(asset_name: AssetName, bond_amount: Int, epo_rewards: Int, duration: Int, start: Int)
  let escrow_bond_amount = 10000
  let escrow_epo_rewards = 753424657
  let escrow_duration = 72
  let escrow_datum =
    get_escrow_datum(
      bond_name_ask_1,
      escrow_bond_amount,
      escrow_epo_rewards,
      escrow_duration,
      63,
    )
  // => epoch_start = 22190 epoch_end = 22244
  let escrow_lovelace =
    escrow_bond_amount * 100_000_000 + escrow_epo_rewards * escrow_duration
  let escrow_full_info =
    calc_escrow_full_info(
      cfg.platform,
      escrow_lovelace,
      escrow_datum,
      time_of_tx,
    )
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  //
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_ask_1,
      1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  //
  let sc_in_bond_qty = 5
  let sc_in_lovelace = 2068800
  let sc_address = get_ask_sc_address()
  let sc_in_1 =
    gen_input(
      sc_address,
      sc_in_lovelace,
      Some(
        value.from_asset(get_bond_policy_id(), bond_name_ask_1, sc_in_bond_qty),
      ),
      InlineDatum(sc_in_datum_1),
    )
  let buyer_fee_ada = 3000000000
  let buyer_address = get_buyer_address()
  let buyer_in_1 =
    gen_input(
      buyer_address,
      buyer_fee_ada,
      Some(value.from_asset(get_bond_policy_id(), bond_name_ask_2, 3)),
      NoDatum,
    )
  //
  let buyer_qty = 2
  let received_at_maturity = escrow_full_info.value_at_maturity * buyer_qty
  let received_with_yield = price_of_one_bond * buyer_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.maker_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.taker_fee / cfg.platform.basis.base
  //
  let sc_remaining_qty = sc_in_bond_qty - buyer_qty
  let min_ada_to_exchange =
    when sc_remaining_qty is {
      0 -> sc_in_lovelace
      _ -> 0
    }
  let exchange_received = exchange_fee_buyer + exchange_fee_seller

  let exchange_address = get_exchange_address()
  let exchange_out_1 =
    gen_output(exchange_address, exchange_received, None, NoDatum)
  let owner_received =
    received_with_yield - exchange_fee_seller + min_ada_to_exchange
  let owner_out_bid_datum_1 =
    gen_bid_making_datum(owner_address, 463, 463, buyer_qty, 516)
  let owner_out_1 =
    gen_output(
      revert_address,
      owner_received,
      None,
      InlineDatum(owner_out_bid_datum_1),
    )
  let buyer_received =
    buyer_fee_ada + sc_in_lovelace - exchange_received - owner_received
  let buyer_out_1 =
    gen_output(
      buyer_address,
      buyer_received,
      Some(
        value.add(
          value.from_asset(get_bond_policy_id(), bond_name_ask_2, buyer_qty),
          get_bond_policy_id(),
          bond_name_ask_1,
          3,
        ),
      ),
      NoDatum,
    )
  let sc_out_1 =
    gen_output(
      sc_address,
      sc_in_lovelace - min_ada_to_exchange,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_ask_1,
          sc_remaining_qty,
        ),
      ),
      InlineDatum(sc_in_datum_1),
    )
  let tx =
    fixture.tx(
      [sc_in_1, buyer_in_1],
      [refer_in_1],
      [exchange_out_1, owner_out_1, buyer_out_1, sc_out_1],
      Some([get_seller_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  buy.spending(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    sc_in_datum_1,
    [],
  )
}

test succ_when_sask_stake_key_is_script() {
  let sask_stake_key_hash = #"080201"
  let owner_sk = #"080203"
  let time_of_tx = 1681095094000
  let cfg = get_config_making_mainnet()
  let owner_address = get_seller_address() |> with_delegation_key(owner_sk)
  let sc_in_datum_1 = gen_ask_making_datum(owner_address, 515)
  // let revert_address = from_script(sc_in_datum_1.bid_sc)
  let revert_address =
    from_script(sc_in_datum_1.bid_sc)
      |> with_delegation_script(sask_stake_key_hash)
  let bond_name_ask_1 = get_bond_id_1()
  let bond_name_ask_2 = get_bond_id_2()
  // get_escrow_datum(asset_name: AssetName, bond_amount: Int, epo_rewards: Int, duration: Int, start: Int)
  let escrow_bond_amount = 10000
  let escrow_epo_rewards = 753424657
  let escrow_duration = 72
  let escrow_datum =
    get_escrow_datum(
      bond_name_ask_1,
      escrow_bond_amount,
      escrow_epo_rewards,
      escrow_duration,
      63,
    )
  // => epoch_start = 22190 epoch_end = 22244
  let escrow_lovelace =
    escrow_bond_amount * 100_000_000 + escrow_epo_rewards * escrow_duration
  let escrow_full_info =
    calc_escrow_full_info(
      cfg.platform,
      escrow_lovelace,
      escrow_datum,
      time_of_tx,
    )
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  //
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_ask_1,
      1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  //
  let sc_in_bond_qty = 5
  let sc_in_lovelace = 2068800
  let sc_address =
    get_ask_sc_address() |> with_delegation_script(sask_stake_key_hash)
  let sc_in_1 =
    gen_input(
      sc_address,
      sc_in_lovelace,
      Some(
        value.from_asset(get_bond_policy_id(), bond_name_ask_1, sc_in_bond_qty),
      ),
      InlineDatum(sc_in_datum_1),
    )
  let buyer_fee_ada = 3000000000
  let buyer_address = get_buyer_address()
  let buyer_in_1 =
    gen_input(
      buyer_address,
      buyer_fee_ada,
      Some(value.from_asset(get_bond_policy_id(), bond_name_ask_2, 3)),
      NoDatum,
    )
  //
  let buyer_qty = 2
  let received_at_maturity = escrow_full_info.value_at_maturity * buyer_qty
  let received_with_yield = price_of_one_bond * buyer_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.maker_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.taker_fee / cfg.platform.basis.base
  //
  let sc_remaining_qty = sc_in_bond_qty - buyer_qty
  let min_ada_to_exchange =
    when sc_remaining_qty is {
      0 -> sc_in_lovelace
      _ -> 0
    }
  let exchange_received = exchange_fee_buyer + exchange_fee_seller

  let exchange_address = get_exchange_address()
  let exchange_out_1 =
    gen_output(exchange_address, exchange_received, None, NoDatum)
  let owner_received =
    received_with_yield - exchange_fee_seller + min_ada_to_exchange
  let owner_out_bid_datum_1 =
    gen_bid_making_datum(owner_address, 463, 463, buyer_qty, 516)
  let owner_out_1 =
    gen_output(
      revert_address,
      owner_received,
      None,
      InlineDatum(owner_out_bid_datum_1),
    )
  let buyer_received =
    buyer_fee_ada + sc_in_lovelace - exchange_received - owner_received
  let buyer_out_1 =
    gen_output(
      buyer_address,
      buyer_received,
      Some(
        value.add(
          value.from_asset(get_bond_policy_id(), bond_name_ask_2, buyer_qty),
          get_bond_policy_id(),
          bond_name_ask_1,
          3,
        ),
      ),
      NoDatum,
    )
  let sc_out_1 =
    gen_output(
      sc_address,
      sc_in_lovelace - min_ada_to_exchange,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_ask_1,
          sc_remaining_qty,
        ),
      ),
      InlineDatum(sc_in_datum_1),
    )
  let tx =
    fixture.tx(
      [sc_in_1, buyer_in_1],
      [refer_in_1],
      [exchange_out_1, owner_out_1, buyer_out_1, sc_out_1],
      Some([get_seller_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  buy.spending(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    sc_in_datum_1,
    [],
  )
}

test succ_when_sask_stake_key_is_verification_key() {
  let sask_stake_key_hash = #"080201"
  let owner_sk = #"080203"
  let time_of_tx = 1681095094000
  let cfg = get_config_making_mainnet()
  let owner_address = get_seller_address() |> with_delegation_key(owner_sk)
  let sc_in_datum_1 = gen_ask_making_datum(owner_address, 515)
  // let revert_address = from_script(sc_in_datum_1.bid_sc)
  let revert_address =
    from_script(sc_in_datum_1.bid_sc)
      |> with_delegation_key(sask_stake_key_hash)
  let bond_name_ask_1 = get_bond_id_1()
  let bond_name_ask_2 = get_bond_id_2()
  // get_escrow_datum(asset_name: AssetName, bond_amount: Int, epo_rewards: Int, duration: Int, start: Int)
  let escrow_bond_amount = 10000
  let escrow_epo_rewards = 753424657
  let escrow_duration = 72
  let escrow_datum =
    get_escrow_datum(
      bond_name_ask_1,
      escrow_bond_amount,
      escrow_epo_rewards,
      escrow_duration,
      63,
    )
  // => epoch_start = 22190 epoch_end = 22244
  let escrow_lovelace =
    escrow_bond_amount * 100_000_000 + escrow_epo_rewards * escrow_duration
  let escrow_full_info =
    calc_escrow_full_info(
      cfg.platform,
      escrow_lovelace,
      escrow_datum,
      time_of_tx,
    )
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  //
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_ask_1,
      1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  //
  let sc_in_bond_qty = 5
  let sc_in_lovelace = 2068800
  let sc_address =
    get_ask_sc_address() |> with_delegation_key(sask_stake_key_hash)
  let sc_in_1 =
    gen_input(
      sc_address,
      sc_in_lovelace,
      Some(
        value.from_asset(get_bond_policy_id(), bond_name_ask_1, sc_in_bond_qty),
      ),
      InlineDatum(sc_in_datum_1),
    )
  let buyer_fee_ada = 3000000000
  let buyer_address = get_buyer_address()
  let buyer_in_1 =
    gen_input(
      buyer_address,
      buyer_fee_ada,
      Some(value.from_asset(get_bond_policy_id(), bond_name_ask_2, 3)),
      NoDatum,
    )
  //
  let buyer_qty = 2
  let received_at_maturity = escrow_full_info.value_at_maturity * buyer_qty
  let received_with_yield = price_of_one_bond * buyer_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.maker_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.taker_fee / cfg.platform.basis.base
  //
  let sc_remaining_qty = sc_in_bond_qty - buyer_qty
  let min_ada_to_exchange =
    when sc_remaining_qty is {
      0 -> sc_in_lovelace
      _ -> 0
    }
  let exchange_received = exchange_fee_buyer + exchange_fee_seller

  let exchange_address = get_exchange_address()
  let exchange_out_1 =
    gen_output(exchange_address, exchange_received, None, NoDatum)
  let owner_received =
    received_with_yield - exchange_fee_seller + min_ada_to_exchange
  let owner_out_bid_datum_1 =
    gen_bid_making_datum(owner_address, 463, 463, buyer_qty, 516)
  let owner_out_1 =
    gen_output(
      revert_address,
      owner_received,
      None,
      InlineDatum(owner_out_bid_datum_1),
    )
  let buyer_received =
    buyer_fee_ada + sc_in_lovelace - exchange_received - owner_received
  let buyer_out_1 =
    gen_output(
      buyer_address,
      buyer_received,
      Some(
        value.add(
          value.from_asset(get_bond_policy_id(), bond_name_ask_2, buyer_qty),
          get_bond_policy_id(),
          bond_name_ask_1,
          3,
        ),
      ),
      NoDatum,
    )
  let sc_out_1 =
    gen_output(
      sc_address,
      sc_in_lovelace - min_ada_to_exchange,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_ask_1,
          sc_remaining_qty,
        ),
      ),
      InlineDatum(sc_in_datum_1),
    )
  let tx =
    fixture.tx(
      [sc_in_1, buyer_in_1],
      [refer_in_1],
      [exchange_out_1, owner_out_1, buyer_out_1, sc_out_1],
      Some([get_seller_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  buy.spending(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    sc_in_datum_1,
    [],
  )
}

test succ_full() {
  let time_of_tx = 1681095094000
  let cfg = get_config_making_mainnet()
  let owner_address = get_seller_address()
  let sc_in_datum_1 = gen_ask_making_datum(owner_address, 515)
  let revert_address = from_script(sc_in_datum_1.bid_sc)
  let bond_name_ask_1 = get_bond_id_1()
  // get_escrow_datum(asset_name: AssetName, bond_amount: Int, epo_rewards: Int, duration: Int, start: Int)
  let escrow_bond_amount = 10000
  let escrow_epo_rewards = 753424657
  let escrow_duration = 72
  let escrow_datum =
    get_escrow_datum(
      bond_name_ask_1,
      escrow_bond_amount,
      escrow_epo_rewards,
      escrow_duration,
      63,
    )
  // => epoch_start = 22190 epoch_end = 22244
  let escrow_lovelace =
    escrow_bond_amount * 100_000_000 + escrow_epo_rewards * escrow_duration
  let escrow_full_info =
    calc_escrow_full_info(
      cfg.platform,
      escrow_lovelace,
      escrow_datum,
      time_of_tx,
    )
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  //
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_ask_1,
      1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  //
  let sc_in_bond_qty = 5
  let sc_in_lovelace = 2068800
  let sc_address = get_ask_sc_address()
  let sc_in_1 =
    gen_input(
      sc_address,
      sc_in_lovelace,
      Some(
        value.from_asset(get_bond_policy_id(), bond_name_ask_1, sc_in_bond_qty),
      ),
      InlineDatum(sc_in_datum_1),
    )
  let buyer_fee_ada = 3000000000
  let buyer_address = get_buyer_address()
  let bond_name_ask_2 = get_bond_id_2()
  let buyer_in_1 =
    gen_input(
      buyer_address,
      buyer_fee_ada,
      Some(value.from_asset(get_bond_policy_id(), bond_name_ask_2, 3)),
      NoDatum,
    )
  //
  let buyer_qty = 5
  let received_at_maturity = escrow_full_info.value_at_maturity * buyer_qty
  let received_with_yield = price_of_one_bond * buyer_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.maker_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.taker_fee / cfg.platform.basis.base
  //
  let sc_remaining_qty = sc_in_bond_qty - buyer_qty
  let min_ada_to_exchange =
    when sc_remaining_qty is {
      0 -> sc_in_lovelace
      _ -> 0
    }
  let exchange_received = exchange_fee_buyer + exchange_fee_seller

  let exchange_address = get_exchange_address()
  let exchange_out_1 =
    gen_output(exchange_address, exchange_received, None, NoDatum)
  let owner_received =
    received_with_yield - exchange_fee_seller + min_ada_to_exchange
  let owner_out_bid_datum_1 =
    gen_bid_making_datum(owner_address, 463, 463, buyer_qty, 516)
  let owner_out_1 =
    gen_output(
      revert_address,
      owner_received,
      None,
      InlineDatum(owner_out_bid_datum_1),
    )
  let buyer_received =
    buyer_fee_ada + sc_in_lovelace - exchange_received - owner_received
  let buyer_out_1 =
    gen_output(
      buyer_address,
      buyer_received,
      Some(
        value.add(
          value.from_asset(get_bond_policy_id(), bond_name_ask_2, 3),
          get_bond_policy_id(),
          bond_name_ask_1,
          buyer_qty,
        ),
      ),
      NoDatum,
    )
  let sc_out_1 =
    gen_output(
      sc_address,
      sc_in_lovelace - min_ada_to_exchange,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_ask_1,
          sc_remaining_qty,
        ),
      ),
      InlineDatum(sc_in_datum_1),
    )
  let tx =
    fixture.tx(
      [sc_in_1, buyer_in_1],
      [refer_in_1],
      [exchange_out_1, owner_out_1, buyer_out_1, sc_out_1],
      Some([get_seller_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  buy.spending(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    sc_in_datum_1,
    [],
  )
}

test fail_when_bid_output_stake_addr_is_owner_sk() fail {
  let owner_sk = #"080203"
  let time_of_tx = 1681095094000
  let cfg = get_config_making_mainnet()
  let owner_address = get_seller_address() |> with_delegation_key(owner_sk)
  let sc_in_datum_1 = gen_ask_making_datum(owner_address, 515)
  let revert_address =
    from_script(sc_in_datum_1.bid_sc)
      |> with_delegation_key(owner_sk)
  let bond_name_ask_1 = get_bond_id_1()
  let bond_name_ask_2 = get_bond_id_2()
  // get_escrow_datum(asset_name: AssetName, bond_amount: Int, epo_rewards: Int, duration: Int, start: Int)
  let escrow_bond_amount = 10000
  let escrow_epo_rewards = 753424657
  let escrow_duration = 72
  let escrow_datum =
    get_escrow_datum(
      bond_name_ask_1,
      escrow_bond_amount,
      escrow_epo_rewards,
      escrow_duration,
      63,
    )
  // => epoch_start = 22190 epoch_end = 22244
  let escrow_lovelace =
    escrow_bond_amount * 100_000_000 + escrow_epo_rewards * escrow_duration
  let escrow_full_info =
    calc_escrow_full_info(
      cfg.platform,
      escrow_lovelace,
      escrow_datum,
      time_of_tx,
    )
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  //
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_ask_1,
      1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  //
  let sc_in_bond_qty = 5
  let sc_in_lovelace = 2068800
  let sc_address = get_ask_sc_address()
  let sc_in_1 =
    gen_input(
      sc_address,
      sc_in_lovelace,
      Some(
        value.from_asset(get_bond_policy_id(), bond_name_ask_1, sc_in_bond_qty),
      ),
      InlineDatum(sc_in_datum_1),
    )
  let buyer_fee_ada = 3000000000
  let buyer_address = get_buyer_address()
  let buyer_in_1 =
    gen_input(
      buyer_address,
      buyer_fee_ada,
      Some(value.from_asset(get_bond_policy_id(), bond_name_ask_2, 3)),
      NoDatum,
    )
  //
  let buyer_qty = 2
  let received_at_maturity = escrow_full_info.value_at_maturity * buyer_qty
  let received_with_yield = price_of_one_bond * buyer_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.maker_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.taker_fee / cfg.platform.basis.base
  //
  let sc_remaining_qty = sc_in_bond_qty - buyer_qty
  let min_ada_to_exchange =
    when sc_remaining_qty is {
      0 -> sc_in_lovelace
      _ -> 0
    }
  let exchange_received = exchange_fee_buyer + exchange_fee_seller

  let exchange_address = get_exchange_address()
  let exchange_out_1 =
    gen_output(exchange_address, exchange_received, None, NoDatum)
  let owner_received =
    received_with_yield - exchange_fee_seller + min_ada_to_exchange
  let owner_out_bid_datum_1 =
    gen_bid_making_datum(owner_address, 463, 463, buyer_qty, 516)
  let owner_out_1 =
    gen_output(
      revert_address,
      owner_received,
      None,
      InlineDatum(owner_out_bid_datum_1),
    )
  let buyer_received =
    buyer_fee_ada + sc_in_lovelace - exchange_received - owner_received
  let buyer_out_1 =
    gen_output(
      buyer_address,
      buyer_received,
      Some(
        value.add(
          value.from_asset(get_bond_policy_id(), bond_name_ask_2, buyer_qty),
          get_bond_policy_id(),
          bond_name_ask_1,
          3,
        ),
      ),
      NoDatum,
    )
  let sc_out_1 =
    gen_output(
      sc_address,
      sc_in_lovelace - min_ada_to_exchange,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_ask_1,
          sc_remaining_qty,
        ),
      ),
      InlineDatum(sc_in_datum_1),
    )
  let tx =
    fixture.tx(
      [sc_in_1, buyer_in_1],
      [refer_in_1],
      [exchange_out_1, owner_out_1, buyer_out_1, sc_out_1],
      Some([get_seller_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  buy.spending(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    sc_in_datum_1,
    [],
  )
}

test fail_partial_when_wrong_stake_key_output() fail {
  let time_of_tx = 1681095094000
  let cfg = get_config_making_mainnet()
  let owner_address = get_seller_address()
  let sc_in_datum_1 = gen_ask_making_datum(owner_address, 515)
  let revert_address = from_script(sc_in_datum_1.bid_sc)
  let bond_name_ask_1 = get_bond_id_1()
  let bond_name_ask_2 = get_bond_id_2()
  // get_escrow_datum(asset_name: AssetName, bond_amount: Int, epo_rewards: Int, duration: Int, start: Int)
  let escrow_bond_amount = 10000
  let escrow_epo_rewards = 753424657
  let escrow_duration = 72
  let escrow_datum =
    get_escrow_datum(
      bond_name_ask_1,
      escrow_bond_amount,
      escrow_epo_rewards,
      escrow_duration,
      63,
    )
  // => epoch_start = 22190 epoch_end = 22244
  let escrow_lovelace =
    escrow_bond_amount * 100_000_000 + escrow_epo_rewards * escrow_duration
  let escrow_full_info =
    calc_escrow_full_info(
      cfg.platform,
      escrow_lovelace,
      escrow_datum,
      time_of_tx,
    )
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  //
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_ask_1,
      1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  //
  let sc_in_bond_qty = 5
  let sc_in_lovelace = 2068800
  let sc_address = get_ask_sc_address()
  let sc_in_1 =
    gen_input(
      sc_address |> with_delegation_key("stake key"),
      sc_in_lovelace,
      Some(
        value.from_asset(get_bond_policy_id(), bond_name_ask_1, sc_in_bond_qty),
      ),
      InlineDatum(sc_in_datum_1),
    )
  let buyer_fee_ada = 3000000000
  let buyer_address = get_buyer_address()
  let buyer_in_1 =
    gen_input(
      buyer_address,
      buyer_fee_ada,
      Some(value.from_asset(get_bond_policy_id(), bond_name_ask_2, 3)),
      NoDatum,
    )
  //
  let buyer_qty = 2
  let received_at_maturity = escrow_full_info.value_at_maturity * buyer_qty
  let received_with_yield = price_of_one_bond * buyer_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.maker_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.taker_fee / cfg.platform.basis.base
  //
  let sc_remaining_qty = sc_in_bond_qty - buyer_qty
  let min_ada_to_exchange =
    when sc_remaining_qty is {
      0 -> sc_in_lovelace
      _ -> 0
    }
  let exchange_received = exchange_fee_buyer + exchange_fee_seller

  let exchange_address = get_exchange_address()
  let exchange_out_1 =
    gen_output(exchange_address, exchange_received, None, NoDatum)
  let owner_received =
    received_with_yield - exchange_fee_seller + min_ada_to_exchange
  let owner_out_bid_datum_1 =
    gen_bid_making_datum(owner_address, 463, 463, buyer_qty, 516)
  let owner_out_1 =
    gen_output(
      revert_address,
      owner_received,
      None,
      InlineDatum(owner_out_bid_datum_1),
    )
  let buyer_received =
    buyer_fee_ada + sc_in_lovelace - exchange_received - owner_received
  let buyer_out_1 =
    gen_output(
      buyer_address,
      buyer_received,
      Some(
        value.add(
          value.from_asset(get_bond_policy_id(), bond_name_ask_2, buyer_qty),
          get_bond_policy_id(),
          bond_name_ask_1,
          3,
        ),
      ),
      NoDatum,
    )
  let sc_out_1 =
    gen_output(
      sc_address |> with_delegation_key("fake stake key"),
      sc_in_lovelace - min_ada_to_exchange,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_ask_1,
          sc_remaining_qty,
        ),
      ),
      InlineDatum(sc_in_datum_1),
    )
  let tx =
    fixture.tx(
      [sc_in_1, buyer_in_1],
      [refer_in_1],
      [exchange_out_1, owner_out_1, buyer_out_1, sc_out_1],
      Some([get_seller_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  !buy.spending(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    sc_in_datum_1,
    [],
  )
}

test fail_partial_must_only_one_bond_1() fail {
  let time_of_tx = 1681095094000
  let cfg = get_config_making_mainnet()
  let owner_address = get_seller_address()
  let sc_in_datum_1 = gen_ask_making_datum(owner_address, 515)
  let revert_address = from_script(sc_in_datum_1.bid_sc)
  let bond_name_ask_1 = get_bond_id_1()
  let bond_name_ask_2 = get_bond_id_2()
  let escrow_datum =
    get_escrow_datum(bond_name_ask_1, 10000, 753_424_657, 72, 63)
  let escrow_lovelace = 1_017_328_767_112
  let escrow_full_info =
    calc_escrow_full_info(
      cfg.platform,
      escrow_lovelace,
      escrow_datum,
      time_of_tx,
    )
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  //
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_ask_1,
      1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  //
  let sc_in_bond_qty = 5
  let sc_in_lovelace = 2068800
  let sc_address = get_ask_sc_address()
  let sc_in_1 =
    gen_input(
      sc_address,
      sc_in_lovelace,
      Some(
        value.add(
          value.from_asset(
            get_bond_policy_id(),
            bond_name_ask_1,
            sc_in_bond_qty,
          ),
          get_bond_policy_id(),
          bond_name_ask_2,
          3,
        ),
      ),
      InlineDatum(sc_in_datum_1),
    )
  let buyer_fee_ada = 3000000000
  let buyer_address = get_buyer_address()
  let buyer_in_1 =
    gen_input(
      buyer_address,
      buyer_fee_ada,
      Some(value.from_asset(get_bond_policy_id(), bond_name_ask_2, 3)),
      NoDatum,
    )
  //
  let buyer_qty = 2
  let received_at_maturity = escrow_full_info.value_at_maturity * buyer_qty
  let received_with_yield = price_of_one_bond * buyer_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.maker_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.taker_fee / cfg.platform.basis.base
  //
  let sc_remaining_qty = sc_in_bond_qty - buyer_qty
  let min_ada_to_exchange =
    when sc_remaining_qty is {
      0 -> sc_in_lovelace
      _ -> 0
    }
  let exchange_received = exchange_fee_buyer + exchange_fee_seller

  let exchange_address = get_exchange_address()
  let exchange_out_1 =
    gen_output(exchange_address, exchange_received, None, NoDatum)
  let owner_received =
    received_with_yield - exchange_fee_seller + min_ada_to_exchange
  let owner_out_datum_1 =
    gen_bid_making_datum(owner_address, 463, 463, buyer_qty, 516)
  let owner_out_1 =
    gen_output(
      revert_address,
      owner_received,
      None,
      InlineDatum(owner_out_datum_1),
    )
  let buyer_received =
    buyer_fee_ada + sc_in_lovelace - exchange_received - owner_received
  let buyer_out_1 =
    gen_output(
      buyer_address,
      buyer_received,
      Some(
        value.add(
          value.from_asset(get_bond_policy_id(), bond_name_ask_2, buyer_qty),
          get_bond_policy_id(),
          bond_name_ask_1,
          6,
        ),
      ),
      NoDatum,
    )
  let sc_out_1 =
    gen_output(
      sc_address,
      sc_in_lovelace - min_ada_to_exchange,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_ask_1,
          sc_remaining_qty,
        ),
      ),
      InlineDatum(sc_in_datum_1),
    )
  let tx =
    fixture.tx(
      [sc_in_1, buyer_in_1],
      [refer_in_1],
      [exchange_out_1, owner_out_1, buyer_out_1, sc_out_1],
      Some([get_seller_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  !buy.spending(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    sc_in_datum_1,
    [],
  )
}

test fail_partial_must_only_one_bond_2() fail {
  let time_of_tx = 1681095094000
  let cfg = get_config_making_mainnet()
  let owner_address = get_seller_address()
  let sc_in_datum_1 = gen_ask_making_datum(owner_address, 515)
  let revert_address = from_script(sc_in_datum_1.bid_sc)
  let bond_name_ask_1 = get_bond_id_1()
  let bond_name_ask_2 = get_bond_id_2()
  // get_escrow_datum(asset_name: AssetName, bond_amount: Int, epo_rewards: Int, duration: Int, start: Int)
  let escrow_bond_amount = 10000
  let escrow_epo_rewards = 753424657
  let escrow_duration = 72
  let escrow_datum =
    get_escrow_datum(
      bond_name_ask_1,
      escrow_bond_amount,
      escrow_epo_rewards,
      escrow_duration,
      63,
    )
  // => epoch_start = 22190 epoch_end = 22244
  let escrow_lovelace =
    escrow_bond_amount * 100_000_000 + escrow_epo_rewards * escrow_duration
  let escrow_full_info =
    calc_escrow_full_info(
      cfg.platform,
      escrow_lovelace,
      escrow_datum,
      time_of_tx,
    )
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  //
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_ask_1,
      1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  //
  let sc_in_bond_qty = 5
  let sc_in_lovelace = 2068800
  let sc_address = get_ask_sc_address()
  let sc_in_1 =
    gen_input(
      sc_address,
      sc_in_lovelace,
      Some(
        value.from_asset(get_bond_policy_id(), bond_name_ask_1, sc_in_bond_qty),
      ),
      InlineDatum(sc_in_datum_1),
    )
  let sc_in_2 =
    gen_input(
      sc_address,
      sc_in_lovelace,
      Some(value.from_asset(get_bond_policy_id(), bond_name_ask_2, 3)),
      InlineDatum(sc_in_datum_1),
    )
  let buyer_fee_ada = 3000000000
  let buyer_address = get_buyer_address()
  let buyer_in_1 =
    gen_input(
      buyer_address,
      buyer_fee_ada,
      Some(value.from_asset(get_bond_policy_id(), bond_name_ask_2, 3)),
      NoDatum,
    )
  //
  let buyer_qty = 2
  let received_at_maturity = escrow_full_info.value_at_maturity * buyer_qty
  let received_with_yield = price_of_one_bond * buyer_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.maker_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.taker_fee / cfg.platform.basis.base
  //
  let sc_remaining_qty = sc_in_bond_qty - buyer_qty
  let min_ada_to_exchange =
    when sc_remaining_qty is {
      0 -> sc_in_lovelace
      _ -> 0
    }
  let exchange_received = exchange_fee_buyer + exchange_fee_seller

  let exchange_address = get_exchange_address()
  let exchange_out_1 =
    gen_output(exchange_address, exchange_received, None, NoDatum)
  let owner_received =
    received_with_yield - exchange_fee_seller + min_ada_to_exchange
  let owner_out_datum_1 =
    gen_bid_making_datum(owner_address, 463, 463, buyer_qty, 516)
  let owner_out_1 =
    gen_output(
      revert_address,
      owner_received,
      None,
      InlineDatum(owner_out_datum_1),
    )
  let buyer_received =
    buyer_fee_ada + sc_in_lovelace - exchange_received - owner_received
  let buyer_out_1 =
    gen_output(
      buyer_address,
      buyer_received,
      Some(
        value.add(
          value.from_asset(get_bond_policy_id(), bond_name_ask_2, buyer_qty),
          get_bond_policy_id(),
          bond_name_ask_1,
          6,
        ),
      ),
      NoDatum,
    )
  let sc_out_1 =
    gen_output(
      sc_address,
      sc_in_lovelace - min_ada_to_exchange,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_ask_1,
          sc_remaining_qty,
        ),
      ),
      InlineDatum(sc_in_datum_1),
    )
  let tx =
    fixture.tx(
      [sc_in_1, sc_in_2, buyer_in_1],
      [refer_in_1],
      [exchange_out_1, owner_out_1, buyer_out_1, sc_out_1],
      Some([get_seller_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  !buy.spending(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    sc_in_datum_1,
    [],
  )
}

test fail_partial_change_bond_name() fail {
  let time_of_tx = 1681095094000
  let cfg = get_config_making_mainnet()
  let owner_address = get_seller_address()
  let sc_in_datum_1 = gen_ask_making_datum(owner_address, 515)
  let revert_address = from_script(sc_in_datum_1.bid_sc)
  let bond_name_ask_1 = get_bond_id_1()
  let bond_name_ask_2 = get_bond_id_2()
  // get_escrow_datum(asset_name: AssetName, bond_amount: Int, epo_rewards: Int, duration: Int, start: Int)
  let escrow_bond_amount = 10000
  let escrow_epo_rewards = 753424657
  let escrow_duration = 72
  let escrow_datum =
    get_escrow_datum(
      bond_name_ask_1,
      escrow_bond_amount,
      escrow_epo_rewards,
      escrow_duration,
      63,
    )
  // => epoch_start = 22190 epoch_end = 22244
  let escrow_lovelace =
    escrow_bond_amount * 100_000_000 + escrow_epo_rewards * escrow_duration
  let escrow_full_info =
    calc_escrow_full_info(
      cfg.platform,
      escrow_lovelace,
      escrow_datum,
      time_of_tx,
    )
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  //
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_ask_1,
      1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  //
  let sc_in_bond_qty = 5
  let sc_in_lovelace = 2068800
  let sc_address = get_ask_sc_address()
  let sc_in_1 =
    gen_input(
      sc_address,
      sc_in_lovelace,
      Some(
        value.from_asset(get_bond_policy_id(), bond_name_ask_1, sc_in_bond_qty),
      ),
      InlineDatum(sc_in_datum_1),
    )
  let buyer_fee_ada = 3000000000
  let buyer_address = get_buyer_address()
  let buyer_in_1 =
    gen_input(
      buyer_address,
      buyer_fee_ada,
      Some(
        value.from_asset(get_bond_policy_id(), bond_name_ask_2, sc_in_bond_qty),
      ),
      NoDatum,
    )
  //
  let buyer_qty = 0
  let received_at_maturity = escrow_full_info.value_at_maturity * buyer_qty
  let received_with_yield = price_of_one_bond * buyer_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.maker_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.taker_fee / cfg.platform.basis.base
  //
  let sc_remaining_qty = sc_in_bond_qty - buyer_qty
  let min_ada_to_exchange =
    when sc_remaining_qty is {
      0 -> sc_in_lovelace
      _ -> 0
    }
  let exchange_received = exchange_fee_buyer + exchange_fee_seller

  let exchange_address = get_exchange_address()
  let exchange_out_1 =
    gen_output(exchange_address, exchange_received, None, NoDatum)
  let owner_received =
    received_with_yield - exchange_fee_seller + min_ada_to_exchange
  let owner_out_datum_1 =
    gen_bid_making_datum(owner_address, 463, 463, buyer_qty, 516)
  let owner_out_1 =
    gen_output(
      revert_address,
      owner_received,
      None,
      InlineDatum(owner_out_datum_1),
    )
  let buyer_received =
    buyer_fee_ada + sc_in_lovelace - exchange_received - owner_received
  let buyer_out_1 =
    gen_output(
      buyer_address,
      buyer_received,
      Some(
        value.from_asset(get_bond_policy_id(), bond_name_ask_1, sc_in_bond_qty),
      ),
      NoDatum,
    )
  let sc_out_1 =
    gen_output(
      sc_address,
      sc_in_lovelace - min_ada_to_exchange,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_ask_2,
          sc_remaining_qty,
        ),
      ),
      InlineDatum(sc_in_datum_1),
    )
  let tx =
    fixture.tx(
      [sc_in_1, buyer_in_1],
      [refer_in_1],
      [exchange_out_1, owner_out_1, buyer_out_1, sc_out_1],
      Some([get_seller_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  !buy.spending(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    sc_in_datum_1,
    [],
  )
}

test fail_partial_datum_owner_vk_invalid_1() fail {
  let time_of_tx = 1681095094000
  let cfg = get_config_making_mainnet()
  let owner_address = get_seller_address()
  let sc_in_datum_1 = gen_ask_making_datum(owner_address, 515)
  let revert_address = from_script(sc_in_datum_1.bid_sc)
  let bond_name_ask_1 = get_bond_id_1()
  let bond_name_ask_2 = get_bond_id_2()
  // get_escrow_datum(asset_name: AssetName, bond_amount: Int, epo_rewards: Int, duration: Int, start: Int)
  let escrow_bond_amount = 10000
  let escrow_epo_rewards = 753424657
  let escrow_duration = 72
  let escrow_datum =
    get_escrow_datum(
      bond_name_ask_1,
      escrow_bond_amount,
      escrow_epo_rewards,
      escrow_duration,
      63,
    )
  // => epoch_start = 22190 epoch_end = 22244
  let escrow_lovelace =
    escrow_bond_amount * 100_000_000 + escrow_epo_rewards * escrow_duration
  let escrow_full_info =
    calc_escrow_full_info(
      cfg.platform,
      escrow_lovelace,
      escrow_datum,
      time_of_tx,
    )
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  //
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_ask_1,
      1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  //
  let sc_in_bond_qty = 5
  let sc_in_lovelace = 2068800
  let sc_address = get_ask_sc_address()
  let sc_in_1 =
    gen_input(
      sc_address,
      sc_in_lovelace,
      Some(
        value.from_asset(get_bond_policy_id(), bond_name_ask_1, sc_in_bond_qty),
      ),
      InlineDatum(sc_in_datum_1),
    )
  let buyer_fee_ada = 3000000000
  let buyer_address = get_buyer_address()
  let buyer_in_1 =
    gen_input(
      buyer_address,
      buyer_fee_ada,
      Some(value.from_asset(get_bond_policy_id(), bond_name_ask_2, 3)),
      NoDatum,
    )
  //
  let buyer_qty = 2
  let received_at_maturity = escrow_full_info.value_at_maturity * buyer_qty
  let received_with_yield = price_of_one_bond * buyer_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.maker_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.taker_fee / cfg.platform.basis.base
  //
  let sc_remaining_qty = sc_in_bond_qty - buyer_qty
  let min_ada_to_exchange =
    when sc_remaining_qty is {
      0 -> sc_in_lovelace
      _ -> 0
    }
  let exchange_received = exchange_fee_buyer + exchange_fee_seller

  let exchange_address = get_exchange_address()
  let exchange_out_1 =
    gen_output(exchange_address, exchange_received, None, NoDatum)
  let owner_received =
    received_with_yield - exchange_fee_seller + min_ada_to_exchange
  let owner_out_datum_1 =
    gen_bid_making_datum(owner_address, 463, 463, buyer_qty, 516)
  let owner_out_1 =
    gen_output(
      revert_address,
      owner_received,
      None,
      InlineDatum(owner_out_datum_1),
    )
  let buyer_received =
    buyer_fee_ada + sc_in_lovelace - exchange_received - owner_received
  let buyer_out_1 =
    gen_output(
      buyer_address,
      buyer_received,
      Some(
        value.add(
          value.from_asset(get_bond_policy_id(), bond_name_ask_2, buyer_qty),
          get_bond_policy_id(),
          bond_name_ask_1,
          3,
        ),
      ),
      NoDatum,
    )
  let sc_out_datum_1 = gen_ask_making_datum(from_script(#"010203040506"), 515)
  let sc_out_1 =
    gen_output(
      sc_address,
      sc_in_lovelace - min_ada_to_exchange,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_ask_1,
          sc_remaining_qty,
        ),
      ),
      InlineDatum(sc_out_datum_1),
    )
  let tx =
    fixture.tx(
      [sc_in_1, buyer_in_1],
      [refer_in_1],
      [exchange_out_1, owner_out_1, buyer_out_1, sc_out_1],
      Some([get_seller_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  !buy.spending(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    sc_in_datum_1,
    [],
  )
}

test fail_partial_datum_owner_vk_invalid_2() fail {
  let time_of_tx = 1681095094000
  let cfg = get_config_making_mainnet()
  let owner_address = get_seller_address()
  let buyer_address = get_buyer_address()
  let sc_in_datum_1 = gen_ask_making_datum(owner_address, 515)
  let revert_address = from_script(sc_in_datum_1.bid_sc)
  let bond_name_ask_1 = get_bond_id_1()
  let bond_name_ask_2 = get_bond_id_2()
  // get_escrow_datum(asset_name: AssetName, bond_amount: Int, epo_rewards: Int, duration: Int, start: Int)
  let escrow_bond_amount = 10000
  let escrow_epo_rewards = 753424657
  let escrow_duration = 72
  let escrow_datum =
    get_escrow_datum(
      bond_name_ask_1,
      escrow_bond_amount,
      escrow_epo_rewards,
      escrow_duration,
      63,
    )
  // => epoch_start = 22190 epoch_end = 22244
  let escrow_lovelace =
    escrow_bond_amount * 100_000_000 + escrow_epo_rewards * escrow_duration
  let escrow_full_info =
    calc_escrow_full_info(
      cfg.platform,
      escrow_lovelace,
      escrow_datum,
      time_of_tx,
    )
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  //
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_ask_1,
      1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  //
  let sc_in_bond_qty = 5
  let sc_in_lovelace = 2068800
  let sc_address = get_ask_sc_address()
  let sc_in_1 =
    gen_input(
      sc_address,
      sc_in_lovelace,
      Some(
        value.from_asset(get_bond_policy_id(), bond_name_ask_1, sc_in_bond_qty),
      ),
      InlineDatum(sc_in_datum_1),
    )
  let buyer_fee_ada = 3000000000
  let buyer_in_1 =
    gen_input(
      buyer_address,
      buyer_fee_ada,
      Some(value.from_asset(get_bond_policy_id(), bond_name_ask_2, 3)),
      NoDatum,
    )
  //
  let buyer_qty = 2
  let received_at_maturity = escrow_full_info.value_at_maturity * buyer_qty
  let received_with_yield = price_of_one_bond * buyer_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.maker_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.taker_fee / cfg.platform.basis.base
  //
  let sc_remaining_qty = sc_in_bond_qty - buyer_qty
  let min_ada_to_exchange =
    when sc_remaining_qty is {
      0 -> sc_in_lovelace
      _ -> 0
    }
  let exchange_received = exchange_fee_buyer + exchange_fee_seller

  let exchange_address = get_exchange_address()
  let exchange_out_1 =
    gen_output(exchange_address, exchange_received, None, NoDatum)
  let owner_received =
    received_with_yield - exchange_fee_seller + min_ada_to_exchange
  let owner_out_datum_1 =
    gen_bid_making_datum(owner_address, 463, 463, buyer_qty, 516)
  let owner_out_1 =
    gen_output(
      revert_address,
      owner_received,
      None,
      InlineDatum(owner_out_datum_1),
    )
  let buyer_received =
    buyer_fee_ada + sc_in_lovelace - exchange_received - owner_received
  let buyer_out_1 =
    gen_output(
      buyer_address,
      buyer_received,
      Some(
        value.add(
          value.from_asset(get_bond_policy_id(), bond_name_ask_2, buyer_qty),
          get_bond_policy_id(),
          bond_name_ask_1,
          3,
        ),
      ),
      NoDatum,
    )
  let sc_out_datum_1 = gen_ask_making_datum(buyer_address, 515)
  let sc_out_1 =
    gen_output(
      sc_address,
      sc_in_lovelace - min_ada_to_exchange,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_ask_1,
          sc_remaining_qty,
        ),
      ),
      InlineDatum(sc_out_datum_1),
    )
  let tx =
    fixture.tx(
      [sc_in_1, buyer_in_1],
      [refer_in_1],
      [exchange_out_1, owner_out_1, buyer_out_1, sc_out_1],
      Some([get_seller_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  !buy.spending(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    sc_in_datum_1,
    [],
  )
}

test fail_partial_datum_owner_sk_invalid_1() fail {
  let time_of_tx = 1681095094000
  let cfg = get_config_making_mainnet()
  let owner_address = get_seller_address()
  let sc_in_datum_1 =
    gen_ask_making_datum(
      with_delegation_key(owner_address, #"010203040506"),
      515,
    )
  let revert_address = from_script(sc_in_datum_1.bid_sc)
  let bond_name_ask_1 = get_bond_id_1()
  let bond_name_ask_2 = get_bond_id_2()
  // get_escrow_datum(asset_name: AssetName, bond_amount: Int, epo_rewards: Int, duration: Int, start: Int)
  let escrow_bond_amount = 10000
  let escrow_epo_rewards = 753424657
  let escrow_duration = 72
  let escrow_datum =
    get_escrow_datum(
      bond_name_ask_1,
      escrow_bond_amount,
      escrow_epo_rewards,
      escrow_duration,
      63,
    )
  // => epoch_start = 22190 epoch_end = 22244
  let escrow_lovelace =
    escrow_bond_amount * 100_000_000 + escrow_epo_rewards * escrow_duration
  let escrow_full_info =
    calc_escrow_full_info(
      cfg.platform,
      escrow_lovelace,
      escrow_datum,
      time_of_tx,
    )
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  //
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_ask_1,
      1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  //
  let sc_in_bond_qty = 5
  let sc_in_lovelace = 2068800
  let sc_address = get_ask_sc_address()
  let sc_in_1 =
    gen_input(
      sc_address,
      sc_in_lovelace,
      Some(
        value.from_asset(get_bond_policy_id(), bond_name_ask_1, sc_in_bond_qty),
      ),
      InlineDatum(sc_in_datum_1),
    )
  let buyer_fee_ada = 3000000000
  let buyer_address = get_buyer_address()
  let buyer_in_1 =
    gen_input(
      buyer_address,
      buyer_fee_ada,
      Some(value.from_asset(get_bond_policy_id(), bond_name_ask_2, 3)),
      NoDatum,
    )
  //
  let buyer_qty = 2
  let received_at_maturity = escrow_full_info.value_at_maturity * buyer_qty
  let received_with_yield = price_of_one_bond * buyer_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.maker_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.taker_fee / cfg.platform.basis.base
  //
  let sc_remaining_qty = sc_in_bond_qty - buyer_qty
  let min_ada_to_exchange =
    when sc_remaining_qty is {
      0 -> sc_in_lovelace
      _ -> 0
    }
  let exchange_received = exchange_fee_buyer + exchange_fee_seller

  let exchange_address = get_exchange_address()
  let exchange_out_1 =
    gen_output(exchange_address, exchange_received, None, NoDatum)
  let owner_received =
    received_with_yield - exchange_fee_seller + min_ada_to_exchange
  let owner_out_datum_1 =
    gen_bid_making_datum(owner_address, 463, 463, buyer_qty, 516)
  let owner_out_1 =
    gen_output(
      revert_address,
      owner_received,
      None,
      InlineDatum(owner_out_datum_1),
    )
  let buyer_received =
    buyer_fee_ada + sc_in_lovelace - exchange_received - owner_received
  let buyer_out_1 =
    gen_output(
      buyer_address,
      buyer_received,
      Some(
        value.add(
          value.from_asset(get_bond_policy_id(), bond_name_ask_2, buyer_qty),
          get_bond_policy_id(),
          bond_name_ask_1,
          3,
        ),
      ),
      NoDatum,
    )
  let sc_out_datum_1 =
    gen_ask_making_datum(
      with_delegation_key(owner_address, #"010203040507"),
      515,
    )
  let sc_out_1 =
    gen_output(
      sc_address,
      sc_in_lovelace - min_ada_to_exchange,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_ask_1,
          sc_remaining_qty,
        ),
      ),
      InlineDatum(sc_out_datum_1),
    )
  let tx =
    fixture.tx(
      [sc_in_1, buyer_in_1],
      [refer_in_1],
      [exchange_out_1, owner_out_1, buyer_out_1, sc_out_1],
      Some([get_seller_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  !buy.spending(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    sc_in_datum_1,
    [],
  )
}

test fail_partial_datum_owner_sk_invalid_2() fail {
  let time_of_tx = 1681095094000
  let cfg = get_config_making_mainnet()
  let owner_address = get_seller_address()
  let sc_in_datum_1 =
    gen_ask_making_datum(
      with_delegation_key(owner_address, #"010203040506"),
      515,
    )
  let revert_address = from_script(sc_in_datum_1.bid_sc)
  let bond_name_ask_1 = get_bond_id_1()
  let bond_name_ask_2 = get_bond_id_2()
  // get_escrow_datum(asset_name: AssetName, bond_amount: Int, epo_rewards: Int, duration: Int, start: Int)
  let escrow_bond_amount = 10000
  let escrow_epo_rewards = 753424657
  let escrow_duration = 72
  let escrow_datum =
    get_escrow_datum(
      bond_name_ask_1,
      escrow_bond_amount,
      escrow_epo_rewards,
      escrow_duration,
      63,
    )
  // => epoch_start = 22190 epoch_end = 22244
  let escrow_lovelace =
    escrow_bond_amount * 100_000_000 + escrow_epo_rewards * escrow_duration
  let escrow_full_info =
    calc_escrow_full_info(
      cfg.platform,
      escrow_lovelace,
      escrow_datum,
      time_of_tx,
    )
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  //
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_ask_1,
      1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  //
  let sc_in_bond_qty = 5
  let sc_in_lovelace = 2068800
  let sc_address = get_ask_sc_address()
  let sc_in_1 =
    gen_input(
      sc_address,
      sc_in_lovelace,
      Some(
        value.from_asset(get_bond_policy_id(), bond_name_ask_1, sc_in_bond_qty),
      ),
      InlineDatum(sc_in_datum_1),
    )
  let buyer_fee_ada = 3000000000
  let buyer_address = get_buyer_address()
  let buyer_in_1 =
    gen_input(
      buyer_address,
      buyer_fee_ada,
      Some(value.from_asset(get_bond_policy_id(), bond_name_ask_2, 3)),
      NoDatum,
    )
  //
  let buyer_qty = 2
  let received_at_maturity = escrow_full_info.value_at_maturity * buyer_qty
  let received_with_yield = price_of_one_bond * buyer_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.maker_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.taker_fee / cfg.platform.basis.base
  //
  let sc_remaining_qty = sc_in_bond_qty - buyer_qty
  let min_ada_to_exchange =
    when sc_remaining_qty is {
      0 -> sc_in_lovelace
      _ -> 0
    }
  let exchange_received = exchange_fee_buyer + exchange_fee_seller

  let exchange_address = get_exchange_address()
  let exchange_out_1 =
    gen_output(exchange_address, exchange_received, None, NoDatum)
  let owner_received =
    received_with_yield - exchange_fee_seller + min_ada_to_exchange
  let owner_out_datum_1 =
    gen_bid_making_datum(owner_address, 463, 463, buyer_qty, 516)
  let owner_out_1 =
    gen_output(
      revert_address,
      owner_received,
      None,
      InlineDatum(owner_out_datum_1),
    )
  let buyer_received =
    buyer_fee_ada + sc_in_lovelace - exchange_received - owner_received
  let buyer_out_1 =
    gen_output(
      buyer_address,
      buyer_received,
      Some(
        value.add(
          value.from_asset(get_bond_policy_id(), bond_name_ask_2, buyer_qty),
          get_bond_policy_id(),
          bond_name_ask_1,
          3,
        ),
      ),
      NoDatum,
    )
  let sc_out_datum_1 =
    gen_ask_making_datum(
      with_delegation_script(owner_address, #"010203040506"),
      515,
    )
  let sc_out_1 =
    gen_output(
      sc_address,
      sc_in_lovelace - min_ada_to_exchange,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_ask_1,
          sc_remaining_qty,
        ),
      ),
      InlineDatum(sc_out_datum_1),
    )
  let tx =
    fixture.tx(
      [sc_in_1, buyer_in_1],
      [refer_in_1],
      [exchange_out_1, owner_out_1, buyer_out_1, sc_out_1],
      Some([get_seller_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  !buy.spending(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    sc_in_datum_1,
    [],
  )
}

test fail_partial_datum_requested_yield_invalid() fail {
  let time_of_tx = 1681095094000
  let cfg = get_config_making_mainnet()
  let owner_address = get_seller_address()
  let sc_in_datum_1 = gen_ask_making_datum(owner_address, 515)
  let revert_address = from_script(sc_in_datum_1.bid_sc)
  let bond_name_ask_1 = get_bond_id_1()
  let bond_name_ask_2 = get_bond_id_2()
  // get_escrow_datum(asset_name: AssetName, bond_amount: Int, epo_rewards: Int, duration: Int, start: Int)
  let escrow_bond_amount = 10000
  let escrow_epo_rewards = 753424657
  let escrow_duration = 72
  let escrow_datum =
    get_escrow_datum(
      bond_name_ask_1,
      escrow_bond_amount,
      escrow_epo_rewards,
      escrow_duration,
      63,
    )
  // => epoch_start = 22190 epoch_end = 22244
  let escrow_lovelace =
    escrow_bond_amount * 100_000_000 + escrow_epo_rewards * escrow_duration
  let escrow_full_info =
    calc_escrow_full_info(
      cfg.platform,
      escrow_lovelace,
      escrow_datum,
      time_of_tx,
    )
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  //
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_ask_1,
      1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  //
  let sc_in_bond_qty = 5
  let sc_in_lovelace = 2068800
  let sc_address = get_ask_sc_address()
  let sc_in_1 =
    gen_input(
      sc_address,
      sc_in_lovelace,
      Some(
        value.from_asset(get_bond_policy_id(), bond_name_ask_1, sc_in_bond_qty),
      ),
      InlineDatum(sc_in_datum_1),
    )
  let buyer_fee_ada = 3000000000
  let buyer_address = get_buyer_address()
  let buyer_in_1 =
    gen_input(
      buyer_address,
      buyer_fee_ada,
      Some(value.from_asset(get_bond_policy_id(), bond_name_ask_2, 3)),
      NoDatum,
    )
  //
  let buyer_qty = 2
  let received_at_maturity = escrow_full_info.value_at_maturity * buyer_qty
  let received_with_yield = price_of_one_bond * buyer_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.maker_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.taker_fee / cfg.platform.basis.base
  //
  let sc_remaining_qty = sc_in_bond_qty - buyer_qty
  let min_ada_to_exchange =
    when sc_remaining_qty is {
      0 -> sc_in_lovelace
      _ -> 0
    }
  let exchange_received = exchange_fee_buyer + exchange_fee_seller

  let exchange_address = get_exchange_address()
  let exchange_out_1 =
    gen_output(exchange_address, exchange_received, None, NoDatum)
  let owner_received =
    received_with_yield - exchange_fee_seller + min_ada_to_exchange
  let owner_out_datum_1 =
    gen_bid_making_datum(owner_address, 463, 463, buyer_qty, 516)
  let owner_out_1 =
    gen_output(
      revert_address,
      owner_received,
      None,
      InlineDatum(owner_out_datum_1),
    )
  let buyer_received =
    buyer_fee_ada + sc_in_lovelace - exchange_received - owner_received
  let buyer_out_1 =
    gen_output(
      buyer_address,
      buyer_received,
      Some(
        value.add(
          value.from_asset(get_bond_policy_id(), bond_name_ask_2, buyer_qty),
          get_bond_policy_id(),
          bond_name_ask_1,
          3,
        ),
      ),
      NoDatum,
    )
  let sc_out_datum_1 = gen_ask_making_datum(owner_address, 785)
  let sc_out_1 =
    gen_output(
      sc_address,
      sc_in_lovelace - min_ada_to_exchange,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_ask_1,
          sc_remaining_qty,
        ),
      ),
      InlineDatum(sc_out_datum_1),
    )
  let tx =
    fixture.tx(
      [sc_in_1, buyer_in_1],
      [refer_in_1],
      [exchange_out_1, owner_out_1, buyer_out_1, sc_out_1],
      Some([get_seller_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  !buy.spending(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    sc_in_datum_1,
    [],
  )
}

test fail_partial_escrow_datum_unexpect() fail {
  let time_of_tx = 1681095094000
  let cfg = get_config_making_mainnet()
  let owner_address = get_seller_address()
  let sc_in_datum_1 = gen_ask_making_datum(owner_address, 515)
  let revert_address = from_script(sc_in_datum_1.bid_sc)
  let bond_name_ask_1 = get_bond_id_1()
  let bond_name_ask_2 = get_bond_id_2()
  // get_escrow_datum(asset_name: AssetName, bond_amount: Int, epo_rewards: Int, duration: Int, start: Int)
  let escrow_bond_amount = 10000
  let escrow_epo_rewards = 753424657
  let escrow_duration = 72
  let escrow_datum =
    get_escrow_datum(
      bond_name_ask_1,
      escrow_bond_amount,
      escrow_epo_rewards,
      escrow_duration,
      63,
    )
  // => epoch_start = 22190 epoch_end = 22244
  let escrow_lovelace =
    escrow_bond_amount * 100_000_000 + escrow_epo_rewards * escrow_duration
  let escrow_full_info =
    calc_escrow_full_info(
      cfg.platform,
      escrow_lovelace,
      escrow_datum,
      time_of_tx,
    )
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  //
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_ask_1,
      1,
      escrow_lovelace,
      InlineDatum(sc_in_datum_1),
    )
  //
  let sc_in_bond_qty = 5
  let sc_in_lovelace = 2068800
  let sc_address = get_ask_sc_address()
  let sc_in_1 =
    gen_input(
      sc_address,
      sc_in_lovelace,
      Some(
        value.from_asset(get_bond_policy_id(), bond_name_ask_1, sc_in_bond_qty),
      ),
      InlineDatum(sc_in_datum_1),
    )
  let buyer_fee_ada = 3000000000
  let buyer_address = get_buyer_address()
  let buyer_in_1 =
    gen_input(
      buyer_address,
      buyer_fee_ada,
      Some(value.from_asset(get_bond_policy_id(), bond_name_ask_2, 3)),
      NoDatum,
    )
  //
  let buyer_qty = 2
  let received_at_maturity = escrow_full_info.value_at_maturity * buyer_qty
  let received_with_yield = price_of_one_bond * buyer_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.maker_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.taker_fee / cfg.platform.basis.base
  //
  let sc_remaining_qty = sc_in_bond_qty - buyer_qty
  let min_ada_to_exchange =
    when sc_remaining_qty is {
      0 -> sc_in_lovelace
      _ -> 0
    }
  let exchange_received = exchange_fee_buyer + exchange_fee_seller

  let exchange_address = get_exchange_address()
  let exchange_out_1 =
    gen_output(exchange_address, exchange_received, None, NoDatum)
  let owner_received =
    received_with_yield - exchange_fee_seller + min_ada_to_exchange
  let owner_out_datum_1 =
    gen_bid_making_datum(owner_address, 463, 463, buyer_qty, 516)
  let owner_out_1 =
    gen_output(
      revert_address,
      owner_received,
      None,
      InlineDatum(owner_out_datum_1),
    )
  let buyer_received =
    buyer_fee_ada + sc_in_lovelace - exchange_received - owner_received
  let buyer_out_1 =
    gen_output(
      buyer_address,
      buyer_received,
      Some(
        value.add(
          value.from_asset(get_bond_policy_id(), bond_name_ask_2, buyer_qty),
          get_bond_policy_id(),
          bond_name_ask_1,
          3,
        ),
      ),
      NoDatum,
    )
  let sc_out_1 =
    gen_output(
      sc_address,
      sc_in_lovelace - min_ada_to_exchange,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_ask_1,
          sc_remaining_qty,
        ),
      ),
      InlineDatum(sc_in_datum_1),
    )
  let tx =
    fixture.tx(
      [sc_in_1, buyer_in_1],
      [refer_in_1],
      [exchange_out_1, owner_out_1, buyer_out_1, sc_out_1],
      Some([get_seller_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  !buy.spending(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    sc_in_datum_1,
    [],
  )
}

test fail_escrow_policy_id_unexpect() fail {
  let time_of_tx = 1681095094000
  let cfg = get_config_making_mainnet()
  let owner_address = get_seller_address()
  let sc_in_datum_1 = gen_ask_making_datum(owner_address, 515)
  let revert_address = from_script(sc_in_datum_1.bid_sc)
  let bond_name_ask_1 = get_bond_id_1()
  let bond_name_ask_2 = get_bond_id_2()
  // get_escrow_datum(asset_name: AssetName, bond_amount: Int, epo_rewards: Int, duration: Int, start: Int)
  let escrow_bond_amount = 10000
  let escrow_epo_rewards = 753424657
  let escrow_duration = 72
  let escrow_datum =
    get_escrow_datum(
      bond_name_ask_1,
      escrow_bond_amount,
      escrow_epo_rewards,
      escrow_duration,
      63,
    )
  // => epoch_start = 22190 epoch_end = 22244
  let escrow_lovelace =
    escrow_bond_amount * 100_000_000 + escrow_epo_rewards * escrow_duration
  let escrow_full_info =
    calc_escrow_full_info(
      cfg.platform,
      escrow_lovelace,
      escrow_datum,
      time_of_tx,
    )
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  //
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_not_escrow_policy_id(),
      bond_name_ask_1,
      1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  //
  let sc_in_bond_qty = 5
  let sc_in_lovelace = 2068800
  let sc_address = get_ask_sc_address()
  let sc_in_1 =
    gen_input(
      sc_address,
      sc_in_lovelace,
      Some(
        value.from_asset(get_bond_policy_id(), bond_name_ask_1, sc_in_bond_qty),
      ),
      InlineDatum(sc_in_datum_1),
    )
  let buyer_fee_ada = 3000000000
  let buyer_address = get_buyer_address()
  let buyer_in_1 =
    gen_input(
      buyer_address,
      buyer_fee_ada,
      Some(value.from_asset(get_bond_policy_id(), bond_name_ask_2, 3)),
      NoDatum,
    )
  //
  let buyer_qty = 2
  let received_at_maturity = escrow_full_info.value_at_maturity * buyer_qty
  let received_with_yield = price_of_one_bond * buyer_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.maker_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.taker_fee / cfg.platform.basis.base
  //
  let sc_remaining_qty = sc_in_bond_qty - buyer_qty
  let min_ada_to_exchange =
    when sc_remaining_qty is {
      0 -> sc_in_lovelace
      _ -> 0
    }
  let exchange_received = exchange_fee_buyer + exchange_fee_seller

  let exchange_address = get_exchange_address()
  let exchange_out_1 =
    gen_output(exchange_address, exchange_received, None, NoDatum)
  let owner_received =
    received_with_yield - exchange_fee_seller + min_ada_to_exchange
  let owner_out_datum_1 =
    gen_bid_making_datum(owner_address, 463, 463, buyer_qty, 516)
  let owner_out_1 =
    gen_output(
      revert_address,
      owner_received,
      None,
      InlineDatum(owner_out_datum_1),
    )
  let buyer_received =
    buyer_fee_ada + sc_in_lovelace - exchange_received - owner_received
  let buyer_out_1 =
    gen_output(
      buyer_address,
      buyer_received,
      Some(
        value.add(
          value.from_asset(get_bond_policy_id(), bond_name_ask_2, buyer_qty),
          get_bond_policy_id(),
          bond_name_ask_1,
          6,
        ),
      ),
      NoDatum,
    )
  let sc_out_1 =
    gen_output(
      sc_address,
      sc_in_lovelace - min_ada_to_exchange,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_ask_1,
          sc_remaining_qty,
        ),
      ),
      InlineDatum(sc_in_datum_1),
    )
  let tx =
    fixture.tx(
      [sc_in_1, buyer_in_1],
      [refer_in_1],
      [exchange_out_1, owner_out_1, buyer_out_1, sc_out_1],
      Some([get_seller_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  !buy.spending(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    sc_in_datum_1,
    [],
  )
}

test fail_escrow_address_unexpect() fail {
  let time_of_tx = 1681095094000
  let cfg = get_config_making_mainnet()
  let owner_address = get_seller_address()
  let sc_in_datum_1 = gen_ask_making_datum(owner_address, 515)
  let revert_address = from_script(sc_in_datum_1.bid_sc)
  let bond_name_ask_1 = get_bond_id_1()
  let bond_name_ask_2 = get_bond_id_2()
  // get_escrow_datum(asset_name: AssetName, bond_amount: Int, epo_rewards: Int, duration: Int, start: Int)
  let escrow_bond_amount = 10000
  let escrow_epo_rewards = 753424657
  let escrow_duration = 72
  let escrow_datum =
    get_escrow_datum(
      bond_name_ask_1,
      escrow_bond_amount,
      escrow_epo_rewards,
      escrow_duration,
      63,
    )
  // => epoch_start = 22190 epoch_end = 22244
  let escrow_lovelace =
    escrow_bond_amount * 100_000_000 + escrow_epo_rewards * escrow_duration
  let escrow_full_info =
    calc_escrow_full_info(
      cfg.platform,
      escrow_lovelace,
      escrow_datum,
      time_of_tx,
    )
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  //
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address_unexpect(),
      get_escrow_policy_id(),
      bond_name_ask_1,
      1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  //
  let sc_in_bond_qty = 5
  let sc_in_lovelace = 2068800
  let sc_address = get_ask_sc_address()
  let sc_in_1 =
    gen_input(
      sc_address,
      sc_in_lovelace,
      Some(
        value.from_asset(get_bond_policy_id(), bond_name_ask_1, sc_in_bond_qty),
      ),
      InlineDatum(sc_in_datum_1),
    )
  let sc_in_2 =
    gen_input(
      sc_address,
      sc_in_lovelace,
      Some(value.from_asset(get_bond_policy_id(), bond_name_ask_2, 3)),
      InlineDatum(sc_in_datum_1),
    )
  let buyer_fee_ada = 3000000000
  let buyer_address = get_buyer_address()
  let buyer_in_1 =
    gen_input(
      buyer_address,
      buyer_fee_ada,
      Some(value.from_asset(get_bond_policy_id(), bond_name_ask_2, 3)),
      NoDatum,
    )
  //
  let buyer_qty = 2
  let received_at_maturity = escrow_full_info.value_at_maturity * buyer_qty
  let received_with_yield = price_of_one_bond * buyer_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.maker_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.taker_fee / cfg.platform.basis.base
  //
  let sc_remaining_qty = sc_in_bond_qty - buyer_qty
  let min_ada_to_exchange =
    when sc_remaining_qty is {
      0 -> sc_in_lovelace
      _ -> 0
    }
  let exchange_received = exchange_fee_buyer + exchange_fee_seller

  let exchange_address = get_exchange_address()
  let exchange_out_1 =
    gen_output(exchange_address, exchange_received, None, NoDatum)
  let owner_received =
    received_with_yield - exchange_fee_seller + min_ada_to_exchange
  let owner_out_datum_1 =
    gen_bid_making_datum(owner_address, 463, 463, buyer_qty, 516)
  let owner_out_1 =
    gen_output(
      revert_address,
      owner_received,
      None,
      InlineDatum(owner_out_datum_1),
    )
  let buyer_received =
    buyer_fee_ada + sc_in_lovelace - exchange_received - owner_received
  let buyer_out_1 =
    gen_output(
      buyer_address,
      buyer_received,
      Some(
        value.add(
          value.from_asset(get_bond_policy_id(), bond_name_ask_2, buyer_qty),
          get_bond_policy_id(),
          bond_name_ask_1,
          6,
        ),
      ),
      NoDatum,
    )
  let sc_out_1 =
    gen_output(
      sc_address,
      sc_in_lovelace - min_ada_to_exchange,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_ask_1,
          sc_remaining_qty,
        ),
      ),
      InlineDatum(sc_in_datum_1),
    )
  let tx =
    fixture.tx(
      [sc_in_1, sc_in_2, buyer_in_1],
      [refer_in_1],
      [exchange_out_1, owner_out_1, buyer_out_1, sc_out_1],
      Some([get_seller_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  !buy.spending(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    sc_in_datum_1,
    [],
  )
}

test fail_escrow_datum_not_found() fail {
  let time_of_tx = 1681095094000
  let cfg = get_config_making_mainnet()
  let owner_address = get_seller_address()
  let sc_in_datum_1 = gen_ask_making_datum(owner_address, 515)
  let revert_address = from_script(sc_in_datum_1.bid_sc)
  let bond_name_ask_1 = get_bond_id_1()
  let bond_name_ask_2 = get_bond_id_2()
  // get_escrow_datum(asset_name: AssetName, bond_amount: Int, epo_rewards: Int, duration: Int, start: Int)
  let escrow_bond_amount = 10000
  let escrow_epo_rewards = 753424657
  let escrow_duration = 72
  let escrow_datum =
    get_escrow_datum(
      bond_name_ask_1,
      escrow_bond_amount,
      escrow_epo_rewards,
      escrow_duration,
      63,
    )
  // => epoch_start = 22190 epoch_end = 22244
  let escrow_lovelace =
    escrow_bond_amount * 100_000_000 + escrow_epo_rewards * escrow_duration
  let escrow_full_info =
    calc_escrow_full_info(
      cfg.platform,
      escrow_lovelace,
      escrow_datum,
      time_of_tx,
    )
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  //
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_ask_1,
      1,
      escrow_lovelace,
      NoDatum,
    )
  //
  let sc_in_bond_qty = 5
  let sc_in_lovelace = 2068800
  let sc_address = get_ask_sc_address()
  let sc_in_1 =
    gen_input(
      sc_address,
      sc_in_lovelace,
      Some(
        value.from_asset(get_bond_policy_id(), bond_name_ask_1, sc_in_bond_qty),
      ),
      InlineDatum(sc_in_datum_1),
    )
  let buyer_fee_ada = 3000000000
  let buyer_address = get_buyer_address()
  let buyer_in_1 =
    gen_input(
      buyer_address,
      buyer_fee_ada,
      Some(value.from_asset(get_bond_policy_id(), bond_name_ask_2, 3)),
      NoDatum,
    )
  //
  let buyer_qty = 2
  let received_at_maturity = escrow_full_info.value_at_maturity * buyer_qty
  let received_with_yield = price_of_one_bond * buyer_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.maker_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.taker_fee / cfg.platform.basis.base
  //
  let sc_remaining_qty = sc_in_bond_qty - buyer_qty
  let min_ada_to_exchange =
    when sc_remaining_qty is {
      0 -> sc_in_lovelace
      _ -> 0
    }
  let exchange_received = exchange_fee_buyer + exchange_fee_seller

  let exchange_address = get_exchange_address()
  let exchange_out_1 =
    gen_output(exchange_address, exchange_received, None, NoDatum)
  let owner_received =
    received_with_yield - exchange_fee_seller + min_ada_to_exchange
  let owner_out_datum_1 =
    gen_bid_making_datum(owner_address, 463, 463, buyer_qty, 516)
  let owner_out_1 =
    gen_output(
      revert_address,
      owner_received,
      None,
      InlineDatum(owner_out_datum_1),
    )
  let buyer_received =
    buyer_fee_ada + sc_in_lovelace - exchange_received - owner_received
  let buyer_out_1 =
    gen_output(
      buyer_address,
      buyer_received,
      Some(
        value.add(
          value.from_asset(get_bond_policy_id(), bond_name_ask_1, buyer_qty),
          get_bond_policy_id(),
          bond_name_ask_2,
          3,
        ),
      ),
      NoDatum,
    )
  let sc_out_1 =
    gen_output(
      sc_address,
      sc_in_lovelace - min_ada_to_exchange,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_ask_1,
          sc_remaining_qty,
        ),
      ),
      InlineDatum(sc_in_datum_1),
    )
  let tx =
    fixture.tx(
      [sc_in_1, buyer_in_1],
      [refer_in_1],
      [exchange_out_1, owner_out_1, buyer_out_1, sc_out_1],
      Some([get_seller_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  !buy.spending(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    sc_in_datum_1,
    [],
  )
}

test fail_escrow_datum_unexpect() fail {
  let time_of_tx = 1681095094000
  let cfg = get_config_making_mainnet()
  let owner_address = get_seller_address()
  let sc_in_datum_1 = gen_ask_making_datum(owner_address, 515)
  let revert_address = from_script(sc_in_datum_1.bid_sc)
  let bond_name_ask_1 = get_bond_id_1()
  let bond_name_ask_2 = get_bond_id_2()
  // get_escrow_datum(asset_name: AssetName, bond_amount: Int, epo_rewards: Int, duration: Int, start: Int)
  let escrow_bond_amount = 10000
  let escrow_epo_rewards = 753424657
  let escrow_duration = 72
  let escrow_datum =
    get_escrow_datum(
      bond_name_ask_1,
      escrow_bond_amount,
      escrow_epo_rewards,
      escrow_duration,
      63,
    )
  // => epoch_start = 22190 epoch_end = 22244
  let escrow_lovelace =
    escrow_bond_amount * 100_000_000 + escrow_epo_rewards * escrow_duration
  let escrow_full_info =
    calc_escrow_full_info(
      cfg.platform,
      escrow_lovelace,
      escrow_datum,
      time_of_tx,
    )
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  //
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_ask_1,
      1,
      escrow_lovelace,
      InlineDatum(sc_in_datum_1),
    )
  //
  let sc_in_bond_qty = 5
  let sc_in_lovelace = 2068800
  let sc_address = get_ask_sc_address()
  let sc_in_1 =
    gen_input(
      sc_address,
      sc_in_lovelace,
      Some(
        value.from_asset(get_bond_policy_id(), bond_name_ask_1, sc_in_bond_qty),
      ),
      InlineDatum(sc_in_datum_1),
    )
  let buyer_fee_ada = 3000000000
  let buyer_address = get_buyer_address()
  let buyer_in_1 =
    gen_input(
      buyer_address,
      buyer_fee_ada,
      Some(value.from_asset(get_bond_policy_id(), bond_name_ask_2, 3)),
      NoDatum,
    )
  //
  let buyer_qty = 2
  let received_at_maturity = escrow_full_info.value_at_maturity * buyer_qty
  let received_with_yield = price_of_one_bond * buyer_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.maker_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.taker_fee / cfg.platform.basis.base
  //
  let sc_remaining_qty = sc_in_bond_qty - buyer_qty
  let min_ada_to_exchange =
    when sc_remaining_qty is {
      0 -> sc_in_lovelace
      _ -> 0
    }
  let exchange_received = exchange_fee_buyer + exchange_fee_seller

  let exchange_address = get_exchange_address()
  let exchange_out_1 =
    gen_output(exchange_address, exchange_received, None, NoDatum)
  let owner_received =
    received_with_yield - exchange_fee_seller + min_ada_to_exchange
  let owner_out_datum_1 =
    gen_bid_making_datum(owner_address, 463, 463, buyer_qty, 516)
  let owner_out_1 =
    gen_output(
      revert_address,
      owner_received,
      None,
      InlineDatum(owner_out_datum_1),
    )
  let buyer_received =
    buyer_fee_ada + sc_in_lovelace - exchange_received - owner_received
  let buyer_out_1 =
    gen_output(
      buyer_address,
      buyer_received,
      Some(
        value.add(
          value.from_asset(get_bond_policy_id(), bond_name_ask_1, buyer_qty),
          get_bond_policy_id(),
          bond_name_ask_2,
          3,
        ),
      ),
      NoDatum,
    )
  let sc_out_1 =
    gen_output(
      sc_address,
      sc_in_lovelace - min_ada_to_exchange,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_ask_1,
          sc_remaining_qty,
        ),
      ),
      InlineDatum(sc_in_datum_1),
    )
  let tx =
    fixture.tx(
      [sc_in_1, buyer_in_1],
      [refer_in_1],
      [exchange_out_1, owner_out_1, buyer_out_1, sc_out_1],
      Some([get_seller_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  !buy.spending(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    sc_in_datum_1,
    [],
  )
}

test fail_escrow_closable() fail {
  // increase time
  let time_of_tx = 1781095094000
  let cfg = get_config_making_mainnet()
  let owner_address = get_seller_address()
  let sc_in_datum_1 = gen_ask_making_datum(owner_address, 515)
  let revert_address = from_script(sc_in_datum_1.bid_sc)
  let bond_name_ask_1 = get_bond_id_1()
  let bond_name_ask_2 = get_bond_id_2()
  // get_escrow_datum(asset_name: AssetName, bond_amount: Int, epo_rewards: Int, duration: Int, start: Int)
  let escrow_amount_remaining = 10000
  let escrow_start = 63
  let escrow_duration = 72
  let epoch_rewards_lovelace = 753424657
  let escrow_datum =
    get_escrow_datum(
      bond_name_ask_1,
      escrow_amount_remaining,
      epoch_rewards_lovelace,
      escrow_duration,
      escrow_start,
    )
  // => epoch_start = 22190 epoch_end = 22244
  let escrow_lovelace =
    escrow_amount_remaining * 100_000_000 + epoch_rewards_lovelace * escrow_duration

  let escrow_full_info =
    calc_escrow_full_info(
      cfg.platform,
      escrow_lovelace,
      escrow_datum,
      time_of_tx,
    )
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  //
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_ask_1,
      1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  //
  let sc_in_bond_qty = 5
  let sc_in_lovelace = 2068800
  let sc_address = get_ask_sc_address()
  let sc_in_1 =
    gen_input(
      sc_address,
      sc_in_lovelace,
      Some(
        value.from_asset(get_bond_policy_id(), bond_name_ask_1, sc_in_bond_qty),
      ),
      InlineDatum(sc_in_datum_1),
    )
  let buyer_fee_ada = 3000000000
  let buyer_address = get_buyer_address()
  let buyer_in_1 =
    gen_input(
      buyer_address,
      buyer_fee_ada,
      Some(value.from_asset(get_bond_policy_id(), bond_name_ask_2, 3)),
      NoDatum,
    )
  //
  let buyer_qty = 2
  let received_at_maturity = escrow_full_info.value_at_maturity * buyer_qty
  let received_with_yield = price_of_one_bond * buyer_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.maker_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.taker_fee / cfg.platform.basis.base
  //
  let sc_remaining_qty = sc_in_bond_qty - buyer_qty
  let min_ada_to_exchange =
    when sc_remaining_qty is {
      0 -> sc_in_lovelace
      _ -> 0
    }
  let exchange_received = exchange_fee_buyer + exchange_fee_seller

  let exchange_address = get_exchange_address()
  let exchange_out_1 =
    gen_output(exchange_address, exchange_received, None, NoDatum)
  let owner_received =
    received_with_yield - exchange_fee_seller + min_ada_to_exchange
  let owner_out_datum_1 =
    gen_bid_making_datum(owner_address, 463, 463, buyer_qty, 516)
  let owner_out_1 =
    gen_output(
      revert_address,
      owner_received,
      None,
      InlineDatum(owner_out_datum_1),
    )
  let buyer_received =
    buyer_fee_ada + sc_in_lovelace - exchange_received - owner_received
  let buyer_out_1 =
    gen_output(
      buyer_address,
      buyer_received,
      Some(
        value.add(
          value.from_asset(get_bond_policy_id(), bond_name_ask_1, buyer_qty),
          get_bond_policy_id(),
          bond_name_ask_2,
          3,
        ),
      ),
      NoDatum,
    )
  let sc_out_1 =
    gen_output(
      sc_address,
      sc_in_lovelace - min_ada_to_exchange,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_ask_1,
          sc_remaining_qty,
        ),
      ),
      InlineDatum(sc_in_datum_1),
    )
  let tx =
    fixture.tx(
      [sc_in_1, buyer_in_1],
      [refer_in_1],
      [exchange_out_1, owner_out_1, buyer_out_1, sc_out_1],
      Some([get_seller_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  !buy.spending(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    sc_in_datum_1,
    [],
  )
}

test fail_buyer_must_not_owner_1() {
  let time_of_tx = 1681095094000
  let cfg = get_config_making_mainnet()
  let owner_address = get_seller_address()
  let sc_in_datum_1 = gen_ask_making_datum(owner_address, 515)
  let revert_address = from_script(sc_in_datum_1.bid_sc)
  let bond_name_ask_1 = get_bond_id_1()
  let bond_name_ask_2 = get_bond_id_2()
  let escrow_datum = get_escrow_datum(bond_name_ask_1, 10000, 753424657, 72, 63)
  let escrow_lovelace = 1017328767112
  let escrow_full_info =
    calc_escrow_full_info(
      cfg.platform,
      escrow_lovelace,
      escrow_datum,
      time_of_tx,
    )
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  //
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_ask_1,
      1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  //
  let sc_in_bond_qty = 5
  let sc_in_lovelace = 2068800
  let sc_address = get_ask_sc_address()
  let sc_in_1 =
    gen_input(
      sc_address,
      sc_in_lovelace,
      Some(
        value.from_asset(get_bond_policy_id(), bond_name_ask_1, sc_in_bond_qty),
      ),
      InlineDatum(sc_in_datum_1),
    )
  let buyer_fee_ada = 3000000000
  let buyer_address = owner_address
  let buyer_in_1 =
    gen_input(
      buyer_address,
      buyer_fee_ada,
      Some(value.from_asset(get_bond_policy_id(), bond_name_ask_2, 3)),
      NoDatum,
    )
  //
  let buyer_qty = 2
  let received_at_maturity = escrow_full_info.value_at_maturity * buyer_qty
  let received_with_yield = price_of_one_bond * buyer_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.maker_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.taker_fee / cfg.platform.basis.base
  //
  let sc_remaining_qty = sc_in_bond_qty - buyer_qty
  let min_ada_to_exchange =
    when sc_remaining_qty is {
      0 -> sc_in_lovelace
      _ -> 0
    }
  let exchange_received = exchange_fee_buyer + exchange_fee_seller

  let exchange_address = get_exchange_address()
  let exchange_out_1 =
    gen_output(exchange_address, exchange_received, None, NoDatum)
  let owner_received =
    received_with_yield - exchange_fee_seller + min_ada_to_exchange
  let owner_out_datum_1 =
    gen_bid_making_datum(owner_address, 463, 463, buyer_qty, 516)
  let owner_out_1 =
    gen_output(
      revert_address,
      owner_received,
      None,
      InlineDatum(owner_out_datum_1),
    )
  let buyer_received =
    buyer_fee_ada + sc_in_lovelace - exchange_received - owner_received
  let buyer_out_1 =
    gen_output(
      buyer_address,
      buyer_received,
      Some(
        value.add(
          value.from_asset(get_bond_policy_id(), bond_name_ask_2, buyer_qty),
          get_bond_policy_id(),
          bond_name_ask_1,
          3,
        ),
      ),
      NoDatum,
    )
  let sc_out_1 =
    gen_output(
      sc_address,
      sc_in_lovelace - min_ada_to_exchange,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_ask_1,
          sc_remaining_qty,
        ),
      ),
      InlineDatum(sc_in_datum_1),
    )
  let tx =
    fixture.tx(
      [sc_in_1, buyer_in_1],
      [refer_in_1],
      [exchange_out_1, owner_out_1, buyer_out_1, sc_out_1],
      Some([get_seller_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  !buy.spending(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    sc_in_datum_1,
    [],
  )
}

test fail_buyer_must_not_owner_2() {
  let time_of_tx = 1681095094000
  let cfg = get_config_making_mainnet()
  let owner_address = get_seller_address()
  let sc_in_datum_1 = gen_ask_making_datum(owner_address, 515)
  let revert_address = from_script(sc_in_datum_1.bid_sc)
  let bond_name_ask_1 = get_bond_id_1()
  let bond_name_ask_2 = get_bond_id_2()
  let escrow_datum = get_escrow_datum(bond_name_ask_1, 10000, 753424657, 72, 63)
  let escrow_lovelace = 1017328767112
  let escrow_full_info =
    calc_escrow_full_info(
      cfg.platform,
      escrow_lovelace,
      escrow_datum,
      time_of_tx,
    )
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  //
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_ask_1,
      1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  //
  let sc_in_bond_qty = 5
  let sc_in_lovelace = 2068800
  let sc_address = get_ask_sc_address()
  let sc_in_1 =
    gen_input(
      sc_address,
      sc_in_lovelace,
      Some(
        value.from_asset(get_bond_policy_id(), bond_name_ask_1, sc_in_bond_qty),
      ),
      InlineDatum(sc_in_datum_1),
    )
  let buyer_fee_ada = 3000000000
  let buyer_address = get_buyer_address()
  let buyer_in_1 =
    gen_input(
      buyer_address,
      buyer_fee_ada,
      Some(value.from_asset(get_bond_policy_id(), bond_name_ask_2, 3)),
      NoDatum,
    )
  //
  let buyer_qty = 2
  let received_at_maturity = escrow_full_info.value_at_maturity * buyer_qty
  let received_with_yield = price_of_one_bond * buyer_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.maker_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.taker_fee / cfg.platform.basis.base
  //
  let sc_remaining_qty = sc_in_bond_qty - buyer_qty
  let min_ada_to_exchange =
    when sc_remaining_qty is {
      0 -> sc_in_lovelace
      _ -> 0
    }
  let exchange_received = exchange_fee_buyer + exchange_fee_seller

  let exchange_address = get_exchange_address()
  let exchange_out_1 =
    gen_output(exchange_address, exchange_received, None, NoDatum)
  let owner_received =
    received_with_yield - exchange_fee_seller + min_ada_to_exchange
  let owner_out_datum_1 =
    gen_bid_making_datum(owner_address, 463, 463, buyer_qty, 516)
  let owner_out_1 =
    gen_output(
      revert_address,
      owner_received,
      None,
      InlineDatum(owner_out_datum_1),
    )
  let buyer_received =
    buyer_fee_ada + sc_in_lovelace - exchange_received - owner_received
  let buyer_out_1 =
    gen_output(
      owner_address,
      buyer_received,
      Some(
        value.add(
          value.from_asset(get_bond_policy_id(), bond_name_ask_2, buyer_qty),
          get_bond_policy_id(),
          bond_name_ask_1,
          3,
        ),
      ),
      NoDatum,
    )
  let sc_out_1 =
    gen_output(
      sc_address,
      sc_in_lovelace - min_ada_to_exchange,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_ask_1,
          sc_remaining_qty,
        ),
      ),
      InlineDatum(sc_in_datum_1),
    )
  let tx =
    fixture.tx(
      [sc_in_1, buyer_in_1],
      [refer_in_1],
      [exchange_out_1, owner_out_1, buyer_out_1, sc_out_1],
      Some([get_seller_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  !buy.spending(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    sc_in_datum_1,
    [],
  )
}

test fail_invalid_revert_address() {
  let time_of_tx = 1681095094000
  let cfg = get_config_making_mainnet()
  let owner_address = get_seller_address()
  let sc_in_datum_1 = gen_ask_making_datum(owner_address, 515)
  // let revert_address = from_script(sc_in_datum_1.bid_sc)
  let bond_name_ask_1 = get_bond_id_1()
  let bond_name_ask_2 = get_bond_id_2()
  let escrow_datum = get_escrow_datum(bond_name_ask_1, 10000, 753424657, 72, 63)
  let escrow_lovelace = 1017328767112
  let escrow_full_info =
    calc_escrow_full_info(
      cfg.platform,
      escrow_lovelace,
      escrow_datum,
      time_of_tx,
    )
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  //
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_ask_1,
      1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  //
  let sc_in_bond_qty = 5
  let sc_in_lovelace = 2068800
  let sc_address = get_ask_sc_address()
  let sc_in_1 =
    gen_input(
      sc_address,
      sc_in_lovelace,
      Some(
        value.from_asset(get_bond_policy_id(), bond_name_ask_1, sc_in_bond_qty),
      ),
      InlineDatum(sc_in_datum_1),
    )
  let buyer_fee_ada = 3000000000
  let buyer_address = get_buyer_address()
  let buyer_in_1 =
    gen_input(
      buyer_address,
      buyer_fee_ada,
      Some(value.from_asset(get_bond_policy_id(), bond_name_ask_2, 3)),
      NoDatum,
    )
  //
  let buyer_qty = 2
  let received_at_maturity = escrow_full_info.value_at_maturity * buyer_qty
  let received_with_yield = price_of_one_bond * buyer_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.maker_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.taker_fee / cfg.platform.basis.base
  //
  let sc_remaining_qty = sc_in_bond_qty - buyer_qty
  let min_ada_to_exchange =
    when sc_remaining_qty is {
      0 -> sc_in_lovelace
      _ -> 0
    }
  let exchange_received = exchange_fee_buyer + exchange_fee_seller

  let exchange_address = get_exchange_address()
  let exchange_out_1 =
    gen_output(exchange_address, exchange_received, None, NoDatum)
  let owner_received =
    received_with_yield - exchange_fee_seller + min_ada_to_exchange
  let owner_out_bid_datum_1 =
    gen_bid_making_datum(owner_address, 463, 463, buyer_qty, 516)
  let owner_out_1 =
    gen_output(
      get_fraud_address(),
      owner_received,
      None,
      InlineDatum(owner_out_bid_datum_1),
    )
  let buyer_received =
    buyer_fee_ada + sc_in_lovelace - exchange_received - owner_received
  let buyer_out_1 =
    gen_output(
      buyer_address,
      buyer_received,
      Some(
        value.add(
          value.from_asset(get_bond_policy_id(), bond_name_ask_2, buyer_qty),
          get_bond_policy_id(),
          bond_name_ask_1,
          3,
        ),
      ),
      NoDatum,
    )
  let sc_out_1 =
    gen_output(
      sc_address,
      sc_in_lovelace - min_ada_to_exchange,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_ask_1,
          sc_remaining_qty,
        ),
      ),
      InlineDatum(sc_in_datum_1),
    )
  let tx =
    fixture.tx(
      [sc_in_1, buyer_in_1],
      [refer_in_1],
      [exchange_out_1, owner_out_1, buyer_out_1, sc_out_1],
      Some([get_seller_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  !buy.spending(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    sc_in_datum_1,
    [],
  )
}

test fail_partial_validity_end_not_set() fail {
  let time_of_tx = 1681095094000
  let cfg = get_config_making_mainnet()
  let owner_address = get_seller_address()
  let sc_in_datum_1 = gen_ask_making_datum(owner_address, 515)
  let revert_address = from_script(sc_in_datum_1.bid_sc)
  let bond_name_ask_1 = get_bond_id_1()
  let bond_name_ask_2 = get_bond_id_2()
  let escrow_datum = get_escrow_datum(bond_name_ask_1, 10000, 753424657, 72, 63)
  let escrow_lovelace = 1017328767112
  let escrow_full_info =
    calc_escrow_full_info(
      cfg.platform,
      escrow_lovelace,
      escrow_datum,
      time_of_tx,
    )
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  //
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_ask_1,
      1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  //
  let sc_in_bond_qty = 5
  let sc_in_lovelace = 2068800
  let sc_address = get_ask_sc_address()
  let sc_in_1 =
    gen_input(
      sc_address,
      sc_in_lovelace,
      Some(
        value.from_asset(get_bond_policy_id(), bond_name_ask_1, sc_in_bond_qty),
      ),
      InlineDatum(sc_in_datum_1),
    )
  let buyer_fee_ada = 3000000000
  let buyer_address = get_buyer_address()
  let buyer_in_1 =
    gen_input(
      buyer_address,
      buyer_fee_ada,
      Some(value.from_asset(get_bond_policy_id(), bond_name_ask_2, 3)),
      NoDatum,
    )
  //
  let buyer_qty = 2
  let received_at_maturity = escrow_full_info.value_at_maturity * buyer_qty
  let received_with_yield = price_of_one_bond * buyer_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.maker_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.taker_fee / cfg.platform.basis.base
  //
  let sc_remaining_qty = sc_in_bond_qty - buyer_qty
  let min_ada_to_exchange =
    when sc_remaining_qty is {
      0 -> sc_in_lovelace
      _ -> 0
    }
  let exchange_received = exchange_fee_buyer + exchange_fee_seller

  let exchange_address = get_exchange_address()
  let exchange_out_1 =
    gen_output(exchange_address, exchange_received, None, NoDatum)
  let owner_received =
    received_with_yield - exchange_fee_seller + min_ada_to_exchange
  let owner_out_datum_1 =
    gen_bid_making_datum(owner_address, 463, 463, buyer_qty, 516)
  let owner_out_1 =
    gen_output(
      revert_address,
      owner_received,
      None,
      InlineDatum(owner_out_datum_1),
    )
  let buyer_received =
    buyer_fee_ada + sc_in_lovelace - exchange_received - owner_received
  let buyer_out_1 =
    gen_output(
      buyer_address,
      buyer_received,
      Some(
        value.add(
          value.from_asset(get_bond_policy_id(), bond_name_ask_2, buyer_qty),
          get_bond_policy_id(),
          bond_name_ask_1,
          3,
        ),
      ),
      NoDatum,
    )
  let sc_out_1 =
    gen_output(
      sc_address,
      sc_in_lovelace - min_ada_to_exchange,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_ask_1,
          sc_remaining_qty,
        ),
      ),
      InlineDatum(sc_in_datum_1),
    )
  let tx =
    fixture.tx(
      [sc_in_1, buyer_in_1],
      [refer_in_1],
      [exchange_out_1, owner_out_1, buyer_out_1, sc_out_1],
      Some([get_seller_address_hash()]),
      None,
      Some(time_of_tx),
      None,
    )
  !buy.spending(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    sc_in_datum_1,
    [],
  )
}

test fail_full_validity_end_not_set_1() fail {
  let time_of_tx = 1681095094000
  let cfg = get_config_making_mainnet()
  let owner_address = get_seller_address()
  let sc_in_datum_1 = gen_ask_making_datum(owner_address, 515)
  let revert_address = from_script(sc_in_datum_1.bid_sc)
  let bond_name_ask_1 = get_bond_id_1()
  let bond_name_ask_2 = get_bond_id_2()
  let escrow_datum = get_escrow_datum(bond_name_ask_1, 10000, 753424657, 72, 63)
  let escrow_lovelace = 1017328767112
  let escrow_full_info =
    calc_escrow_full_info(
      cfg.platform,
      escrow_lovelace,
      escrow_datum,
      time_of_tx,
    )
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  //
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_ask_1,
      1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  //
  let sc_in_bond_qty = 5
  let sc_in_lovelace = 2068800
  let sc_address = get_ask_sc_address()
  let sc_in_1 =
    gen_input(
      sc_address,
      sc_in_lovelace,
      Some(
        value.from_asset(get_bond_policy_id(), bond_name_ask_1, sc_in_bond_qty),
      ),
      InlineDatum(sc_in_datum_1),
    )
  let buyer_fee_ada = 3000000000
  let buyer_address = get_buyer_address()
  let buyer_in_1 =
    gen_input(
      buyer_address,
      buyer_fee_ada,
      Some(value.from_asset(get_bond_policy_id(), bond_name_ask_2, 3)),
      NoDatum,
    )
  //
  let buyer_qty = 5
  let received_at_maturity = escrow_full_info.value_at_maturity * buyer_qty
  let received_with_yield = price_of_one_bond * buyer_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.maker_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.taker_fee / cfg.platform.basis.base
  //
  let sc_remaining_qty = sc_in_bond_qty - buyer_qty
  let min_ada_to_exchange =
    when sc_remaining_qty is {
      0 -> sc_in_lovelace
      _ -> 0
    }
  let exchange_received = exchange_fee_buyer + exchange_fee_seller

  let exchange_address = get_exchange_address()
  let exchange_out_1 =
    gen_output(exchange_address, exchange_received, None, NoDatum)
  let owner_received =
    received_with_yield - exchange_fee_seller + min_ada_to_exchange
  let owner_out_datum_1 =
    gen_bid_making_datum(owner_address, 463, 463, buyer_qty, 516)
  let owner_out_1 =
    gen_output(
      revert_address,
      owner_received,
      None,
      InlineDatum(owner_out_datum_1),
    )
  let buyer_received =
    buyer_fee_ada + sc_in_lovelace - exchange_received - owner_received
  let buyer_out_1 =
    gen_output(
      buyer_address,
      buyer_received,
      Some(
        value.add(
          value.from_asset(get_bond_policy_id(), bond_name_ask_2, buyer_qty),
          get_bond_policy_id(),
          bond_name_ask_1,
          3,
        ),
      ),
      NoDatum,
    )
  let sc_out_1 =
    gen_output(
      sc_address,
      sc_in_lovelace - min_ada_to_exchange,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_ask_1,
          sc_remaining_qty,
        ),
      ),
      InlineDatum(sc_in_datum_1),
    )
  let tx =
    fixture.tx(
      [sc_in_1, buyer_in_1],
      [refer_in_1],
      [exchange_out_1, owner_out_1, buyer_out_1, sc_out_1],
      Some([get_seller_address_hash()]),
      None,
      Some(time_of_tx),
      None,
    )
  !buy.spending(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    sc_in_datum_1,
    [],
  )
}

test fail_full_validity_end_not_set_2() fail {
  // let time_of_tx = 1666656000 000
  let time_of_tx = 1687343990000
  // => current_epoch = 22241
  let cfg = get_config_making_preview()
  let owner_address = get_seller_address()
  let sc_in_datum_1 = gen_ask_making_datum(owner_address, 7)
  let revert_address = from_script(sc_in_datum_1.bid_sc)
  let bond_name_ask_1 = get_bond_id_1()
  let bond_name_ask_2 = get_bond_id_2()
  // get_escrow_datum(asset_name: AssetName, bond_amount: Int, epo_rewards: Int, duration: Int, start: Int)
  let escrow_datum = get_escrow_datum(bond_name_ask_1, 20, 1084931, 54, 21862)
  // => epoch_start = 22190 epoch_end = 22244
  let escrow_lovelace = 701430920
  let escrow_full_info =
    calc_escrow_full_info(
      cfg.platform,
      escrow_lovelace,
      escrow_datum,
      time_of_tx,
    )
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  //
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_ask_1,
      1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  //
  let sc_in_bond_qty = 1
  let buyer_qty = 0
  let sc_in_lovelace = 1599010
  let sc_address = get_ask_sc_address()
  let sc_in_1 =
    gen_input(
      sc_address,
      sc_in_lovelace,
      Some(
        value.from_asset(get_bond_policy_id(), bond_name_ask_1, sc_in_bond_qty),
      ),
      InlineDatum(sc_in_datum_1),
    )
  let buyer_fee_ada = 18704383567
  let buyer_address = get_buyer_address()
  let buyer_in_1 =
    gen_input(
      buyer_address,
      buyer_fee_ada,
      Some(value.from_asset(get_bond_policy_id(), bond_name_ask_2, 1)),
      NoDatum,
    )
  //
  let received_at_maturity = escrow_full_info.value_at_maturity * buyer_qty
  let received_with_yield = price_of_one_bond * buyer_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.maker_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.taker_fee / cfg.platform.basis.base
  //
  let sc_remaining_qty = sc_in_bond_qty - buyer_qty
  let min_ada_to_exchange =
    when sc_remaining_qty is {
      0 -> sc_in_lovelace
      _ -> 0
    }
  let exchange_received = exchange_fee_buyer + exchange_fee_seller

  let exchange_address = get_exchange_address()
  let exchange_out_1 =
    gen_output(exchange_address, exchange_received, None, NoDatum)
  let owner_received =
    received_with_yield - exchange_fee_seller + min_ada_to_exchange
  let owner_out_datum_1 =
    gen_bid_making_datum(owner_address, 463, 463, buyer_qty, 516)
  let owner_out_1 =
    gen_output(
      revert_address,
      owner_received,
      None,
      InlineDatum(owner_out_datum_1),
    )
  let buyer_received =
    buyer_fee_ada + sc_in_lovelace - exchange_received - owner_received
  let buyer_out_1 =
    gen_output(
      buyer_address,
      buyer_received,
      Some(value.from_asset(get_bond_policy_id(), bond_name_ask_2, 1)),
      NoDatum,
    )
  let sc_out_1 =
    gen_output(
      sc_address,
      sc_in_lovelace - min_ada_to_exchange,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_ask_1,
          sc_remaining_qty,
        ),
      ),
      InlineDatum(sc_in_datum_1),
    )
  let tx =
    fixture.tx(
      [sc_in_1, buyer_in_1],
      [refer_in_1],
      [exchange_out_1, owner_out_1, buyer_out_1, sc_out_1],
      Some([get_seller_address_hash()]),
      None,
      Some(time_of_tx),
      None,
    )
  !buy.spending(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    sc_in_datum_1,
    [],
  )
}

test fail_partial_validity_end_invalid_aft() fail {
  let time_of_tx = 1681095094000
  let cfg = get_config_making_mainnet()
  let owner_address = get_seller_address()
  let sc_in_datum_1 = gen_ask_making_datum(owner_address, 515)
  let revert_address = from_script(sc_in_datum_1.bid_sc)
  let bond_name_ask_1 = get_bond_id_1()
  let bond_name_ask_2 = get_bond_id_2()
  let escrow_datum = get_escrow_datum(bond_name_ask_1, 10000, 753424657, 72, 63)
  let escrow_lovelace = 1017328767112
  let escrow_full_info =
    calc_escrow_full_info(
      cfg.platform,
      escrow_lovelace,
      escrow_datum,
      time_of_tx,
    )
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  //
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_ask_1,
      1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  //
  let sc_in_bond_qty = 5
  let sc_in_lovelace = 2068800
  let sc_address = get_ask_sc_address()
  let sc_in_1 =
    gen_input(
      sc_address,
      sc_in_lovelace,
      Some(
        value.from_asset(get_bond_policy_id(), bond_name_ask_1, sc_in_bond_qty),
      ),
      InlineDatum(sc_in_datum_1),
    )
  let buyer_fee_ada = 3000000000
  let buyer_address = get_buyer_address()
  let buyer_in_1 =
    gen_input(
      buyer_address,
      buyer_fee_ada,
      Some(value.from_asset(get_bond_policy_id(), bond_name_ask_2, 3)),
      NoDatum,
    )
  //
  let buyer_qty = 2
  let received_at_maturity = escrow_full_info.value_at_maturity * buyer_qty
  let received_with_yield = price_of_one_bond * buyer_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.maker_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.taker_fee / cfg.platform.basis.base
  //
  let sc_remaining_qty = sc_in_bond_qty - buyer_qty
  let min_ada_to_exchange =
    when sc_remaining_qty is {
      0 -> sc_in_lovelace
      _ -> 0
    }
  let exchange_received = exchange_fee_buyer + exchange_fee_seller

  let exchange_address = get_exchange_address()
  let exchange_out_1 =
    gen_output(exchange_address, exchange_received, None, NoDatum)
  let owner_received =
    received_with_yield - exchange_fee_seller + min_ada_to_exchange
  let owner_out_datum_1 =
    gen_bid_making_datum(owner_address, 463, 463, buyer_qty, 516)
  let owner_out_1 =
    gen_output(
      revert_address,
      owner_received,
      None,
      InlineDatum(owner_out_datum_1),
    )
  let buyer_received =
    buyer_fee_ada + sc_in_lovelace - exchange_received - owner_received
  let buyer_out_1 =
    gen_output(
      buyer_address,
      buyer_received,
      Some(
        value.add(
          value.from_asset(get_bond_policy_id(), bond_name_ask_2, buyer_qty),
          get_bond_policy_id(),
          bond_name_ask_1,
          3,
        ),
      ),
      NoDatum,
    )
  let sc_out_1 =
    gen_output(
      sc_address,
      sc_in_lovelace - min_ada_to_exchange,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_ask_1,
          sc_remaining_qty,
        ),
      ),
      InlineDatum(sc_in_datum_1),
    )
  let tx =
    fixture.tx(
      [sc_in_1, buyer_in_1],
      [refer_in_1],
      [exchange_out_1, owner_out_1, buyer_out_1, sc_out_1],
      Some([get_seller_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 6 * 60 * 1000 + 1),
    )
  !buy.spending(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    sc_in_datum_1,
    [],
  )
}

test fail_full_validity_end_invalid_aft_1() fail {
  let time_of_tx = 1681095094000
  let cfg = get_config_making_mainnet()
  let owner_address = get_seller_address()
  let sc_in_datum_1 = gen_ask_making_datum(owner_address, 515)
  let revert_address = from_script(sc_in_datum_1.bid_sc)
  let bond_name_ask_1 = get_bond_id_1()
  let bond_name_ask_2 = get_bond_id_2()
  let escrow_datum = get_escrow_datum(bond_name_ask_1, 10000, 753424657, 72, 63)
  let escrow_lovelace = 1017328767112
  let escrow_full_info =
    calc_escrow_full_info(
      cfg.platform,
      escrow_lovelace,
      escrow_datum,
      time_of_tx,
    )
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  //
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_ask_1,
      1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  //
  let sc_in_bond_qty = 5
  let sc_in_lovelace = 2068800
  let sc_address = get_ask_sc_address()
  let sc_in_1 =
    gen_input(
      sc_address,
      sc_in_lovelace,
      Some(
        value.from_asset(get_bond_policy_id(), bond_name_ask_1, sc_in_bond_qty),
      ),
      InlineDatum(sc_in_datum_1),
    )
  let buyer_fee_ada = 3000000000
  let buyer_address = get_buyer_address()
  let buyer_in_1 =
    gen_input(
      buyer_address,
      buyer_fee_ada,
      Some(value.from_asset(get_bond_policy_id(), bond_name_ask_2, 3)),
      NoDatum,
    )
  //
  let buyer_qty = 5
  let received_at_maturity = escrow_full_info.value_at_maturity * buyer_qty
  let received_with_yield = price_of_one_bond * buyer_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.maker_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.taker_fee / cfg.platform.basis.base
  //
  let sc_remaining_qty = sc_in_bond_qty - buyer_qty
  let min_ada_to_exchange =
    when sc_remaining_qty is {
      0 -> sc_in_lovelace
      _ -> 0
    }
  let exchange_received = exchange_fee_buyer + exchange_fee_seller

  let exchange_address = get_exchange_address()
  let exchange_out_1 =
    gen_output(exchange_address, exchange_received, None, NoDatum)
  let owner_received =
    received_with_yield - exchange_fee_seller + min_ada_to_exchange
  let owner_out_datum_1 =
    gen_bid_making_datum(owner_address, 463, 463, buyer_qty, 516)
  let owner_out_1 =
    gen_output(
      revert_address,
      owner_received,
      None,
      InlineDatum(owner_out_datum_1),
    )
  let buyer_received =
    buyer_fee_ada + sc_in_lovelace - exchange_received - owner_received
  let buyer_out_1 =
    gen_output(
      buyer_address,
      buyer_received,
      Some(
        value.add(
          value.from_asset(get_bond_policy_id(), bond_name_ask_2, buyer_qty),
          get_bond_policy_id(),
          bond_name_ask_1,
          3,
        ),
      ),
      NoDatum,
    )
  let sc_out_1 =
    gen_output(
      sc_address,
      sc_in_lovelace - min_ada_to_exchange,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_ask_1,
          sc_remaining_qty,
        ),
      ),
      InlineDatum(sc_in_datum_1),
    )
  let tx =
    fixture.tx(
      [sc_in_1, buyer_in_1],
      [refer_in_1],
      [exchange_out_1, owner_out_1, buyer_out_1, sc_out_1],
      Some([get_seller_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 6 * 60 * 1000 + 1),
    )
  !buy.spending(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    sc_in_datum_1,
    [],
  )
}

test fail_full_validity_end_invalid_aft_2() fail {
  // let time_of_tx = 1666656000 000
  let time_of_tx = 1687343990000
  // => current_epoch = 22241
  let cfg = get_config_making_preview()
  let owner_address = get_seller_address()
  let sc_in_datum_1 = gen_ask_making_datum(owner_address, 7)
  let revert_address = from_script(sc_in_datum_1.bid_sc)
  let bond_name_ask_1 = get_bond_id_1()
  let bond_name_ask_2 = get_bond_id_2()
  // get_escrow_datum(asset_name: AssetName, bond_amount: Int, epo_rewards: Int, duration: Int, start: Int)
  let escrow_datum = get_escrow_datum(bond_name_ask_1, 20, 1084931, 54, 21862)
  // => epoch_start = 22190 epoch_end = 22244
  let escrow_lovelace = 701430920
  let escrow_full_info =
    calc_escrow_full_info(
      cfg.platform,
      escrow_lovelace,
      escrow_datum,
      time_of_tx,
    )
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  //
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_ask_1,
      1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  //
  let sc_in_bond_qty = 1
  let buyer_qty = 0
  let sc_in_lovelace = 1599010
  let sc_address = get_ask_sc_address()
  let sc_in_1 =
    gen_input(
      sc_address,
      sc_in_lovelace,
      Some(
        value.from_asset(get_bond_policy_id(), bond_name_ask_1, sc_in_bond_qty),
      ),
      InlineDatum(sc_in_datum_1),
    )
  let buyer_fee_ada = 18704383567
  let buyer_address = get_buyer_address()
  let buyer_in_1 =
    gen_input(
      buyer_address,
      buyer_fee_ada,
      Some(value.from_asset(get_bond_policy_id(), bond_name_ask_2, 1)),
      NoDatum,
    )
  //
  let received_at_maturity = escrow_full_info.value_at_maturity * buyer_qty
  let received_with_yield = price_of_one_bond * buyer_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.maker_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.taker_fee / cfg.platform.basis.base
  //
  let sc_remaining_qty = sc_in_bond_qty - buyer_qty
  let min_ada_to_exchange =
    when sc_remaining_qty is {
      0 -> sc_in_lovelace
      _ -> 0
    }
  let exchange_received = exchange_fee_buyer + exchange_fee_seller

  let exchange_address = get_exchange_address()
  let exchange_out_1 =
    gen_output(exchange_address, exchange_received, None, NoDatum)
  let owner_received =
    received_with_yield - exchange_fee_seller + min_ada_to_exchange
  let owner_out_datum_1 =
    gen_bid_making_datum(owner_address, 463, 463, buyer_qty, 516)
  let owner_out_1 =
    gen_output(
      revert_address,
      owner_received,
      None,
      InlineDatum(owner_out_datum_1),
    )
  let buyer_received =
    buyer_fee_ada + sc_in_lovelace - exchange_received - owner_received
  let buyer_out_1 =
    gen_output(
      buyer_address,
      buyer_received,
      Some(value.from_asset(get_bond_policy_id(), bond_name_ask_2, 1)),
      NoDatum,
    )
  let sc_out_1 =
    gen_output(
      sc_address,
      sc_in_lovelace - min_ada_to_exchange,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_ask_1,
          sc_remaining_qty,
        ),
      ),
      InlineDatum(sc_in_datum_1),
    )
  let tx =
    fixture.tx(
      [sc_in_1, buyer_in_1],
      [refer_in_1],
      [exchange_out_1, owner_out_1, buyer_out_1, sc_out_1],
      Some([get_seller_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 6 * 60 * 1000 + 1),
    )
  !buy.spending(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    sc_in_datum_1,
    [],
  )
}

test fail_partial_validity_end_invalid_pre() fail {
  let time_of_tx = 1681095094000
  let cfg = get_config_making_mainnet()
  let owner_address = get_seller_address()
  let sc_in_datum_1 = gen_ask_making_datum(owner_address, 515)
  let revert_address = from_script(sc_in_datum_1.bid_sc)
  let bond_name_ask_1 = get_bond_id_1()
  let bond_name_ask_2 = get_bond_id_2()
  let escrow_datum = get_escrow_datum(bond_name_ask_1, 10000, 753424657, 72, 63)
  let escrow_lovelace = 1017328767112
  let escrow_full_info =
    calc_escrow_full_info(
      cfg.platform,
      escrow_lovelace,
      escrow_datum,
      time_of_tx,
    )
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  //
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_ask_1,
      1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  //
  let sc_in_bond_qty = 5
  let sc_in_lovelace = 2068800
  let sc_address = get_ask_sc_address()
  let sc_in_1 =
    gen_input(
      sc_address,
      sc_in_lovelace,
      Some(
        value.from_asset(get_bond_policy_id(), bond_name_ask_1, sc_in_bond_qty),
      ),
      InlineDatum(sc_in_datum_1),
    )
  let buyer_fee_ada = 3000000000
  let buyer_address = get_buyer_address()
  let buyer_in_1 =
    gen_input(
      buyer_address,
      buyer_fee_ada,
      Some(value.from_asset(get_bond_policy_id(), bond_name_ask_2, 3)),
      NoDatum,
    )
  //
  let buyer_qty = 2
  let received_at_maturity = escrow_full_info.value_at_maturity * buyer_qty
  let received_with_yield = price_of_one_bond * buyer_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.maker_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.taker_fee / cfg.platform.basis.base
  //
  let sc_remaining_qty = sc_in_bond_qty - buyer_qty
  let min_ada_to_exchange =
    when sc_remaining_qty is {
      0 -> sc_in_lovelace
      _ -> 0
    }
  let exchange_received = exchange_fee_buyer + exchange_fee_seller

  let exchange_address = get_exchange_address()
  let exchange_out_1 =
    gen_output(exchange_address, exchange_received, None, NoDatum)
  let owner_received =
    received_with_yield - exchange_fee_seller + min_ada_to_exchange
  let owner_out_datum_1 =
    gen_bid_making_datum(owner_address, 463, 463, buyer_qty, 516)
  let owner_out_1 =
    gen_output(
      revert_address,
      owner_received,
      None,
      InlineDatum(owner_out_datum_1),
    )
  let buyer_received =
    buyer_fee_ada + sc_in_lovelace - exchange_received - owner_received
  let buyer_out_1 =
    gen_output(
      buyer_address,
      buyer_received,
      Some(
        value.add(
          value.from_asset(get_bond_policy_id(), bond_name_ask_2, buyer_qty),
          get_bond_policy_id(),
          bond_name_ask_1,
          3,
        ),
      ),
      NoDatum,
    )
  let sc_out_1 =
    gen_output(
      sc_address,
      sc_in_lovelace - min_ada_to_exchange,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_ask_1,
          sc_remaining_qty,
        ),
      ),
      InlineDatum(sc_in_datum_1),
    )
  let tx =
    fixture.tx(
      [sc_in_1, buyer_in_1],
      [refer_in_1],
      [exchange_out_1, owner_out_1, buyer_out_1, sc_out_1],
      Some([get_seller_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx - 1),
    )
  !buy.spending(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    sc_in_datum_1,
    [],
  )
}

test fail_full_validity_end_invalid_pre_1() fail {
  let time_of_tx = 1681095094000
  let cfg = get_config_making_mainnet()
  let owner_address = get_seller_address()
  let sc_in_datum_1 = gen_ask_making_datum(owner_address, 515)
  let revert_address = from_script(sc_in_datum_1.bid_sc)
  let bond_name_ask_1 = get_bond_id_1()
  let bond_name_ask_2 = get_bond_id_2()
  let escrow_datum = get_escrow_datum(bond_name_ask_1, 10000, 753424657, 72, 63)
  let escrow_lovelace = 1017328767112
  let escrow_full_info =
    calc_escrow_full_info(
      cfg.platform,
      escrow_lovelace,
      escrow_datum,
      time_of_tx,
    )
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  //
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_ask_1,
      1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  //
  let sc_in_bond_qty = 5
  let sc_in_lovelace = 2068800
  let sc_address = get_ask_sc_address()
  let sc_in_1 =
    gen_input(
      sc_address,
      sc_in_lovelace,
      Some(
        value.from_asset(get_bond_policy_id(), bond_name_ask_1, sc_in_bond_qty),
      ),
      InlineDatum(sc_in_datum_1),
    )
  let buyer_fee_ada = 3000000000
  let buyer_address = get_buyer_address()
  let buyer_in_1 =
    gen_input(
      buyer_address,
      buyer_fee_ada,
      Some(value.from_asset(get_bond_policy_id(), bond_name_ask_2, 3)),
      NoDatum,
    )
  //
  let buyer_qty = 5
  let received_at_maturity = escrow_full_info.value_at_maturity * buyer_qty
  let received_with_yield = price_of_one_bond * buyer_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.maker_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.taker_fee / cfg.platform.basis.base
  //
  let sc_remaining_qty = sc_in_bond_qty - buyer_qty
  let min_ada_to_exchange =
    when sc_remaining_qty is {
      0 -> sc_in_lovelace
      _ -> 0
    }
  let exchange_received = exchange_fee_buyer + exchange_fee_seller

  let exchange_address = get_exchange_address()
  let exchange_out_1 =
    gen_output(exchange_address, exchange_received, None, NoDatum)
  let owner_received =
    received_with_yield - exchange_fee_seller + min_ada_to_exchange
  let owner_out_datum_1 =
    gen_bid_making_datum(owner_address, 463, 463, buyer_qty, 516)
  let owner_out_1 =
    gen_output(
      revert_address,
      owner_received,
      None,
      InlineDatum(owner_out_datum_1),
    )
  let buyer_received =
    buyer_fee_ada + sc_in_lovelace - exchange_received - owner_received
  let buyer_out_1 =
    gen_output(
      buyer_address,
      buyer_received,
      Some(
        value.add(
          value.from_asset(get_bond_policy_id(), bond_name_ask_2, buyer_qty),
          get_bond_policy_id(),
          bond_name_ask_1,
          3,
        ),
      ),
      NoDatum,
    )
  let sc_out_1 =
    gen_output(
      sc_address,
      sc_in_lovelace - min_ada_to_exchange,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_ask_1,
          sc_remaining_qty,
        ),
      ),
      InlineDatum(sc_in_datum_1),
    )
  let tx =
    fixture.tx(
      [sc_in_1, buyer_in_1],
      [refer_in_1],
      [exchange_out_1, owner_out_1, buyer_out_1, sc_out_1],
      Some([get_seller_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx - 1),
    )
  !buy.spending(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    sc_in_datum_1,
    [],
  )
}

test fail_full_validity_end_invalid_pre_2() fail {
  // let time_of_tx = 1666656000 000
  let time_of_tx = 1687343990000
  // => current_epoch = 22241
  let cfg = get_config_making_preview()
  let owner_address = get_seller_address()
  let sc_in_datum_1 = gen_ask_making_datum(owner_address, 7)
  let revert_address = from_script(sc_in_datum_1.bid_sc)
  let bond_name_ask_1 = get_bond_id_1()
  let bond_name_ask_2 = get_bond_id_2()
  // get_escrow_datum(asset_name: AssetName, bond_amount: Int, epo_rewards: Int, duration: Int, start: Int)
  let escrow_datum = get_escrow_datum(bond_name_ask_1, 20, 1084931, 54, 21862)
  // => epoch_start = 22190 epoch_end = 22244
  let escrow_lovelace = 701430920
  let escrow_full_info =
    calc_escrow_full_info(
      cfg.platform,
      escrow_lovelace,
      escrow_datum,
      time_of_tx,
    )
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  //
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_ask_1,
      1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  //
  let sc_in_bond_qty = 1
  let buyer_qty = 0
  let sc_in_lovelace = 1599010
  let sc_address = get_ask_sc_address()
  let sc_in_1 =
    gen_input(
      sc_address,
      sc_in_lovelace,
      Some(
        value.from_asset(get_bond_policy_id(), bond_name_ask_1, sc_in_bond_qty),
      ),
      InlineDatum(sc_in_datum_1),
    )
  let buyer_fee_ada = 18704383567
  let buyer_address = get_buyer_address()
  let buyer_in_1 =
    gen_input(
      buyer_address,
      buyer_fee_ada,
      Some(value.from_asset(get_bond_policy_id(), bond_name_ask_2, 1)),
      NoDatum,
    )
  //
  let received_at_maturity = escrow_full_info.value_at_maturity * buyer_qty
  let received_with_yield = price_of_one_bond * buyer_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.maker_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.taker_fee / cfg.platform.basis.base
  //
  let sc_remaining_qty = sc_in_bond_qty - buyer_qty
  let min_ada_to_exchange =
    when sc_remaining_qty is {
      0 -> sc_in_lovelace
      _ -> 0
    }
  let exchange_received = exchange_fee_buyer + exchange_fee_seller

  let exchange_address = get_exchange_address()
  let exchange_out_1 =
    gen_output(exchange_address, exchange_received, None, NoDatum)
  let owner_received =
    received_with_yield - exchange_fee_seller + min_ada_to_exchange
  let owner_out_datum_1 =
    gen_bid_making_datum(owner_address, 463, 463, buyer_qty, 516)
  let owner_out_1 =
    gen_output(
      revert_address,
      owner_received,
      None,
      InlineDatum(owner_out_datum_1),
    )
  let buyer_received =
    buyer_fee_ada + sc_in_lovelace - exchange_received - owner_received
  let buyer_out_1 =
    gen_output(
      buyer_address,
      buyer_received,
      Some(value.from_asset(get_bond_policy_id(), bond_name_ask_2, 1)),
      NoDatum,
    )
  let sc_out_1 =
    gen_output(
      sc_address,
      sc_in_lovelace - min_ada_to_exchange,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_ask_1,
          sc_remaining_qty,
        ),
      ),
      InlineDatum(sc_in_datum_1),
    )
  let tx =
    fixture.tx(
      [sc_in_1, buyer_in_1],
      [refer_in_1],
      [exchange_out_1, owner_out_1, buyer_out_1, sc_out_1],
      Some([get_seller_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx - 1),
    )
  !buy.spending(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    sc_in_datum_1,
    [],
  )
}

test succ_bond_policy_id_valid() {
  let time_of_tx = 1681095094000
  let cfg = get_config_making_mainnet()
  let owner_address = get_seller_address()
  let sc_in_datum_1 = gen_ask_making_datum(owner_address, 515)
  let revert_address = from_script(sc_in_datum_1.bid_sc)
  let bond_name_ask_1 = get_bond_id_1()
  let bond_name_ask_2 = get_bond_id_2()
  let escrow_datum = get_escrow_datum(bond_name_ask_1, 10000, 753424657, 72, 63)
  let escrow_lovelace = 1017328767112
  let escrow_full_info =
    calc_escrow_full_info(
      cfg.platform,
      escrow_lovelace,
      escrow_datum,
      time_of_tx,
    )
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  //
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_ask_1,
      1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  //
  let sc_in_bond_qty = 5
  let sc_in_lovelace = 2068800
  let sc_address = get_ask_sc_address()
  let sc_in_1 =
    gen_input(
      sc_address,
      sc_in_lovelace,
      Some(
        value.from_asset(get_bond_policy_id(), bond_name_ask_1, sc_in_bond_qty),
      ),
      InlineDatum(sc_in_datum_1),
    )
  let buyer_fee_ada = 3000000000
  let buyer_address = get_buyer_address()
  let buyer_in_1 =
    gen_input(
      buyer_address,
      buyer_fee_ada,
      Some(value.from_asset(get_bond_policy_id(), bond_name_ask_2, 3)),
      NoDatum,
    )
  //
  let buyer_qty = 5
  let received_at_maturity = escrow_full_info.value_at_maturity * buyer_qty
  let received_with_yield = price_of_one_bond * buyer_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.maker_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.taker_fee / cfg.platform.basis.base
  //
  let sc_remaining_qty = sc_in_bond_qty - buyer_qty
  let min_ada_to_exchange =
    when sc_remaining_qty is {
      0 -> sc_in_lovelace
      _ -> 0
    }
  let exchange_received = exchange_fee_buyer + exchange_fee_seller

  let exchange_address = get_exchange_address()
  let exchange_out_1 =
    gen_output(exchange_address, exchange_received, None, NoDatum)
  let owner_received =
    received_with_yield - exchange_fee_seller + min_ada_to_exchange
  let owner_out_bid_datum_1 =
    gen_bid_making_datum(owner_address, 463, 463, buyer_qty, 516)
  let owner_out_1 =
    gen_output(
      revert_address,
      owner_received,
      None,
      InlineDatum(owner_out_bid_datum_1),
    )
  let buyer_received =
    buyer_fee_ada + sc_in_lovelace - exchange_received - owner_received
  let buyer_out_1 =
    gen_output(
      buyer_address,
      buyer_received,
      Some(
        value.add(
          value.from_asset(get_bond_policy_id(), bond_name_ask_2, buyer_qty),
          get_bond_policy_id(),
          bond_name_ask_1,
          3,
        ),
      ),
      NoDatum,
    )
  let sc_out_1 =
    gen_output(
      sc_address,
      sc_in_lovelace - min_ada_to_exchange,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_ask_1,
          sc_remaining_qty,
        ),
      ),
      InlineDatum(sc_in_datum_1),
    )
  let tx =
    fixture.tx(
      [sc_in_1, buyer_in_1],
      [refer_in_1],
      [exchange_out_1, owner_out_1, buyer_out_1, sc_out_1],
      Some([get_seller_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  buy.spending(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    sc_in_datum_1,
    [],
  )
}

test fail_bond_policy_id_invalid() fail {
  let time_of_tx = 1681095094000
  let cfg = get_config_making_mainnet()
  let owner_address = get_seller_address()
  let sc_in_datum_1 = gen_ask_making_datum(owner_address, 515)
  let revert_address = from_script(sc_in_datum_1.bid_sc)
  let bond_name_ask_1 = get_bond_id_1()
  let bond_name_ask_2 = get_bond_id_2()
  let escrow_datum = get_escrow_datum(bond_name_ask_1, 10000, 753424657, 72, 63)
  let escrow_lovelace = 1017328767112
  let escrow_full_info =
    calc_escrow_full_info(
      cfg.platform,
      escrow_lovelace,
      escrow_datum,
      time_of_tx,
    )
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  //
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_ask_1,
      1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  //
  let sc_in_bond_qty = 5
  let sc_in_lovelace = 2068800
  let sc_address = get_ask_sc_address()
  let sc_in_1 =
    gen_input(
      sc_address,
      sc_in_lovelace,
      Some(
        value.from_asset(
          get_not_bond_policy_id(),
          bond_name_ask_1,
          sc_in_bond_qty,
        ),
      ),
      InlineDatum(sc_in_datum_1),
    )
  let buyer_fee_ada = 3000000000
  let buyer_address = get_buyer_address()
  let buyer_in_1 =
    gen_input(
      buyer_address,
      buyer_fee_ada,
      Some(value.from_asset(get_not_bond_policy_id(), bond_name_ask_2, 3)),
      NoDatum,
    )
  //
  let buyer_qty = 2
  let received_at_maturity = escrow_full_info.value_at_maturity * buyer_qty
  let received_with_yield = price_of_one_bond * buyer_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.maker_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.taker_fee / cfg.platform.basis.base
  //
  let sc_remaining_qty = sc_in_bond_qty - buyer_qty
  let min_ada_to_exchange =
    when sc_remaining_qty is {
      0 -> sc_in_lovelace
      _ -> 0
    }
  let exchange_received = exchange_fee_buyer + exchange_fee_seller

  let exchange_address = get_exchange_address()
  let exchange_out_1 =
    gen_output(exchange_address, exchange_received, None, NoDatum)
  let owner_received =
    received_with_yield - exchange_fee_seller + min_ada_to_exchange
  let owner_out_bid_datum_1 =
    gen_bid_making_datum(owner_address, 463, 463, buyer_qty, 516)
  let owner_out_1 =
    gen_output(
      revert_address,
      owner_received,
      None,
      InlineDatum(owner_out_bid_datum_1),
    )
  let buyer_received =
    buyer_fee_ada + sc_in_lovelace - exchange_received - owner_received
  let buyer_out_1 =
    gen_output(
      buyer_address,
      buyer_received,
      Some(
        value.add(
          value.from_asset(get_not_bond_policy_id(), bond_name_ask_2, buyer_qty),
          get_not_bond_policy_id(),
          bond_name_ask_1,
          3,
        ),
      ),
      NoDatum,
    )
  let sc_out_1 =
    gen_output(
      sc_address,
      sc_in_lovelace - min_ada_to_exchange,
      Some(
        value.from_asset(
          get_not_bond_policy_id(),
          bond_name_ask_1,
          sc_remaining_qty,
        ),
      ),
      InlineDatum(sc_in_datum_1),
    )
  let tx =
    fixture.tx(
      [sc_in_1, buyer_in_1],
      [refer_in_1],
      [exchange_out_1, owner_out_1, buyer_out_1, sc_out_1],
      Some([get_seller_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  !buy.spending(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    sc_in_datum_1,
    [],
  )
}

test fail_buy_more_than_expect() {
  // fixed config
  let time_of_tx = 1681095094000
  let cfg = get_config_making_mainnet()
  // refer: escrow
  let owner_address = get_seller_address()
  let sc_in_datum_1 = gen_ask_making_datum(owner_address, 515)
  let revert_address = from_script(sc_in_datum_1.bid_sc)
  let bond_name_ask_1 = get_bond_id_1()
  let escrow_datum = get_escrow_datum(bond_name_ask_1, 10000, 753424657, 72, 63)
  let escrow_lovelace = 1017328767112
  let escrow_full_info =
    calc_escrow_full_info(
      cfg.platform,
      escrow_lovelace,
      escrow_datum,
      time_of_tx,
    )
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  //
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_ask_1,
      1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )

  //
  let sc_in_bond_qty = 5
  let sc_in_lovelace = 2068800
  let sc_address = get_ask_sc_address()
  let sc_in_1 =
    gen_input(
      sc_address,
      sc_in_lovelace,
      Some(
        value.from_asset(get_bond_policy_id(), bond_name_ask_1, sc_in_bond_qty),
      ),
      InlineDatum(sc_in_datum_1),
    )
  let buyer_fee_ada = 3000000000
  let buyer_address = get_buyer_address()
  let buyer_in_1 = gen_input(buyer_address, buyer_fee_ada, None, NoDatum)
  //
  let buyer_qty = 2
  let received_at_maturity = escrow_full_info.value_at_maturity * buyer_qty
  let received_with_yield = price_of_one_bond * buyer_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.maker_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.taker_fee / cfg.platform.basis.base
  //
  let sc_remaining_qty = sc_in_bond_qty - buyer_qty
  let min_ada_to_exchange =
    when sc_remaining_qty is {
      0 -> sc_in_lovelace
      _ -> 0
    }
  // = 124543
  let exchange_received = exchange_fee_buyer + exchange_fee_seller

  let exchange_address = get_exchange_address()
  let exchange_out_1 =
    gen_output(exchange_address, exchange_received, None, NoDatum)
  let owner_received =
    received_with_yield - exchange_fee_seller + min_ada_to_exchange
  let owner_out_bid_datum_1 =
    gen_bid_making_datum(owner_address, 463, 463, buyer_qty, 516)
  let owner_out_1 =
    gen_output(
      revert_address,
      owner_received,
      None,
      InlineDatum(owner_out_bid_datum_1),
    )
  // = 2_797_696_105
  let buyer_received = buyer_fee_ada - exchange_received - owner_received
  let buyer_out_1 =
    gen_output(
      buyer_address,
      buyer_received,
      Some(
        // try to buy more than requested qty
        value.from_asset(get_bond_policy_id(), bond_name_ask_1, buyer_qty + 1),
      ),
      NoDatum,
    )
  let sc_out_1 =
    gen_output(
      sc_address,
      sc_in_lovelace - min_ada_to_exchange,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_ask_1,
          // try to buy more than requested qty
          sc_remaining_qty - 1,
        ),
      ),
      InlineDatum(sc_in_datum_1),
    )
  let tx =
    fixture.tx(
      [sc_in_1, buyer_in_1],
      [refer_in_1],
      [exchange_out_1, owner_out_1, buyer_out_1, sc_out_1],
      Some([get_seller_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  !buy.spending(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    sc_in_datum_1,
    [],
  )
}

test fail_buy_less_than_expect() {
  // fixed config
  let time_of_tx = 1681095094000
  let cfg = get_config_making_mainnet()
  // refer: escrow
  let owner_address = get_seller_address()
  let sc_in_datum_1 = gen_ask_making_datum(owner_address, 515)
  let revert_address = from_script(sc_in_datum_1.bid_sc)
  let bond_name_ask_1 = get_bond_id_1()
  let escrow_datum = get_escrow_datum(bond_name_ask_1, 10000, 753424657, 72, 63)
  let escrow_lovelace = 1017328767112
  let escrow_full_info =
    calc_escrow_full_info(
      cfg.platform,
      escrow_lovelace,
      escrow_datum,
      time_of_tx,
    )
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  //
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_ask_1,
      1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )

  //
  let sc_in_bond_qty = 5
  let sc_in_lovelace = 2068800
  let sc_address = get_ask_sc_address()
  let sc_in_1 =
    gen_input(
      sc_address,
      sc_in_lovelace,
      Some(
        value.from_asset(get_bond_policy_id(), bond_name_ask_1, sc_in_bond_qty),
      ),
      InlineDatum(sc_in_datum_1),
    )
  let buyer_fee_ada = 3000000000
  let buyer_address = get_buyer_address()
  let buyer_in_1 = gen_input(buyer_address, buyer_fee_ada, None, NoDatum)
  //
  let buyer_qty = 2
  let received_at_maturity = escrow_full_info.value_at_maturity * buyer_qty
  let received_with_yield = price_of_one_bond * buyer_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.maker_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.taker_fee / cfg.platform.basis.base
  //
  let sc_remaining_qty = sc_in_bond_qty - buyer_qty
  let min_ada_to_exchange =
    when sc_remaining_qty is {
      0 -> sc_in_lovelace
      _ -> 0
    }
  // = 124543
  let exchange_received = exchange_fee_buyer + exchange_fee_seller

  let exchange_address = get_exchange_address()
  let exchange_out_1 =
    gen_output(exchange_address, exchange_received, None, NoDatum)
  let owner_received =
    received_with_yield - exchange_fee_seller + min_ada_to_exchange
  let owner_out_bid_datum_1 =
    gen_bid_making_datum(owner_address, 463, 463, buyer_qty, 516)
  let owner_out_1 =
    gen_output(
      revert_address,
      owner_received,
      None,
      InlineDatum(owner_out_bid_datum_1),
    )
  // = 2_797_696_105
  let buyer_received = buyer_fee_ada - exchange_received - owner_received
  let buyer_out_1 =
    gen_output(
      buyer_address,
      buyer_received,
      Some(
        // try to buy less than requested qty
        value.from_asset(get_bond_policy_id(), bond_name_ask_1, buyer_qty - 1),
      ),
      NoDatum,
    )
  let sc_out_1 =
    gen_output(
      sc_address,
      sc_in_lovelace - min_ada_to_exchange,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_ask_1,
          // try to buy less than requested qty
          sc_remaining_qty + 1,
        ),
      ),
      InlineDatum(sc_in_datum_1),
    )
  let tx =
    fixture.tx(
      [sc_in_1, buyer_in_1],
      [refer_in_1],
      [exchange_out_1, owner_out_1, buyer_out_1, sc_out_1],
      Some([get_seller_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  !buy.spending(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    sc_in_datum_1,
    [],
  )
}

test fail_tampered_bid_datum_address() fail {
  // fixed config
  let time_of_tx = 1681095094000
  let cfg = get_config_making_mainnet()
  // refer: escrow
  let owner_address = get_seller_address()
  let sc_in_datum_1 = gen_ask_making_datum(owner_address, 515)
  let revert_address = from_script(sc_in_datum_1.bid_sc)
  let bond_name_ask_1 = get_bond_id_1()
  let escrow_datum = get_escrow_datum(bond_name_ask_1, 10000, 753424657, 72, 63)
  let escrow_lovelace = 1017328767112
  let escrow_full_info =
    calc_escrow_full_info(
      cfg.platform,
      escrow_lovelace,
      escrow_datum,
      time_of_tx,
    )
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  //
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_ask_1,
      1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )

  //
  let sc_in_bond_qty = 5
  let sc_in_lovelace = 2068800
  let sc_address = get_ask_sc_address()
  let sc_in_1 =
    gen_input(
      sc_address,
      sc_in_lovelace,
      Some(
        value.from_asset(get_bond_policy_id(), bond_name_ask_1, sc_in_bond_qty),
      ),
      InlineDatum(sc_in_datum_1),
    )
  let buyer_fee_ada = 3000000000
  let buyer_address = get_buyer_address()
  let buyer_in_1 = gen_input(buyer_address, buyer_fee_ada, None, NoDatum)
  //
  let buyer_qty = 2
  let received_at_maturity = escrow_full_info.value_at_maturity * buyer_qty
  let received_with_yield = price_of_one_bond * buyer_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.maker_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.taker_fee / cfg.platform.basis.base
  //
  let sc_remaining_qty = sc_in_bond_qty - buyer_qty
  let min_ada_to_exchange =
    when sc_remaining_qty is {
      0 -> sc_in_lovelace
      _ -> 0
    }
  // = 124543
  let exchange_received = exchange_fee_buyer + exchange_fee_seller

  let exchange_address = get_exchange_address()
  let exchange_out_1 =
    gen_output(exchange_address, exchange_received, None, NoDatum)
  let owner_received =
    received_with_yield - exchange_fee_seller + min_ada_to_exchange
  let tampered_owner_out_bid_datum_1 =
    gen_tampered_bid_making_datum(owner_address, 463, 463, buyer_qty, 515)
  let owner_out_1 =
    gen_output(
      revert_address,
      owner_received,
      None,
      InlineDatum(tampered_owner_out_bid_datum_1),
    )
  // = 2_797_696_105
  let buyer_received = buyer_fee_ada - exchange_received - owner_received
  let buyer_out_1 =
    gen_output(
      buyer_address,
      buyer_received,
      Some(value.from_asset(get_bond_policy_id(), bond_name_ask_1, buyer_qty)),
      NoDatum,
    )
  let sc_out_1 =
    gen_output(
      sc_address,
      sc_in_lovelace - min_ada_to_exchange,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_ask_1,
          sc_remaining_qty,
        ),
      ),
      InlineDatum(sc_in_datum_1),
    )
  let tx =
    fixture.tx(
      [sc_in_1, buyer_in_1],
      [refer_in_1],
      [exchange_out_1, owner_out_1, buyer_out_1, sc_out_1],
      Some([get_seller_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  !buy.spending(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    sc_in_datum_1,
    [],
  )
}

test fail_tampered_ask_datum_address() fail {
  // fixed config
  let time_of_tx = 1681095094000
  let cfg = get_config_making_mainnet()
  // refer: escrow
  let owner_address = get_seller_address()
  let sc_in_datum_1 = gen_ask_making_datum(owner_address, 515)
  let revert_address = from_script(sc_in_datum_1.bid_sc)
  let bond_name_ask_1 = get_bond_id_1()
  let escrow_datum = get_escrow_datum(bond_name_ask_1, 10000, 753424657, 72, 63)
  let escrow_lovelace = 1017328767112
  let escrow_full_info =
    calc_escrow_full_info(
      cfg.platform,
      escrow_lovelace,
      escrow_datum,
      time_of_tx,
    )
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  //
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_ask_1,
      1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )

  //
  let sc_in_bond_qty = 5
  let sc_in_lovelace = 2068800
  let sc_address = get_ask_sc_address()
  let sc_in_1 =
    gen_input(
      sc_address,
      sc_in_lovelace,
      Some(
        value.from_asset(get_bond_policy_id(), bond_name_ask_1, sc_in_bond_qty),
      ),
      InlineDatum(sc_in_datum_1),
    )
  let buyer_fee_ada = 3000000000
  let buyer_address = get_buyer_address()
  let buyer_in_1 = gen_input(buyer_address, buyer_fee_ada, None, NoDatum)
  //
  let buyer_qty = 2
  let received_at_maturity = escrow_full_info.value_at_maturity * buyer_qty
  let received_with_yield = price_of_one_bond * buyer_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.maker_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.taker_fee / cfg.platform.basis.base
  //
  let sc_remaining_qty = sc_in_bond_qty - buyer_qty
  let min_ada_to_exchange =
    when sc_remaining_qty is {
      0 -> sc_in_lovelace
      _ -> 0
    }
  // = 124543
  let exchange_received = exchange_fee_buyer + exchange_fee_seller

  let exchange_address = get_exchange_address()
  let exchange_out_1 =
    gen_output(exchange_address, exchange_received, None, NoDatum)
  let owner_received =
    received_with_yield - exchange_fee_seller + min_ada_to_exchange
  let owner_out_bid_datum_1 =
    gen_bid_making_datum(owner_address, 463, 463, buyer_qty, 516)
  let owner_out_1 =
    gen_output(
      revert_address,
      owner_received,
      None,
      InlineDatum(owner_out_bid_datum_1),
    )
  // = 2_797_696_105
  let buyer_received = buyer_fee_ada - exchange_received - owner_received
  let buyer_out_1 =
    gen_output(
      buyer_address,
      buyer_received,
      Some(value.from_asset(get_bond_policy_id(), bond_name_ask_1, buyer_qty)),
      NoDatum,
    )

  let sc_out_datum_tampered = gen_tampered_ask_making_datum(owner_address, 515)
  let sc_out_1 =
    gen_output(
      sc_address,
      sc_in_lovelace - min_ada_to_exchange,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_ask_1,
          sc_remaining_qty,
        ),
      ),
      InlineDatum(sc_out_datum_tampered),
    )
  let tx =
    fixture.tx(
      [sc_in_1, buyer_in_1],
      [refer_in_1],
      [exchange_out_1, owner_out_1, buyer_out_1, sc_out_1],
      Some([get_seller_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  !buy.spending(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    sc_in_datum_1,
    [],
  )
}

test fail_when_spend_deprecated_ask() fail {
  // fixed config
  let time_of_tx = 1681095094000
  let cfg = get_config_making_mainnet()
  // refer: escrow
  let owner_address = get_seller_address()
  let sc_in_datum_1 = gen_ask_making_datum(owner_address, 515)
  let revert_address = from_script(sc_in_datum_1.bid_sc)
  let bond_name_ask_1 = get_bond_id_1()
  let escrow_datum = get_escrow_datum(bond_name_ask_1, 10000, 753424657, 72, 63)
  let escrow_lovelace = 1017328767112
  let escrow_full_info =
    calc_escrow_full_info(
      cfg.platform,
      escrow_lovelace,
      escrow_datum,
      time_of_tx,
    )
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  //
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_ask_1,
      1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )

  //
  let sc_in_bond_qty = 5
  let sc_in_lovelace = 2068800
  let sc_address = get_ask_sc_address()
  let sc_in_1 =
    gen_input(
      sc_address,
      sc_in_lovelace,
      Some(
        value.from_asset(get_bond_policy_id(), bond_name_ask_1, sc_in_bond_qty),
      ),
      InlineDatum(sc_in_datum_1),
    )
  let buyer_fee_ada = 3000000000
  let buyer_address = get_buyer_address()
  let buyer_in_1 = gen_input(buyer_address, buyer_fee_ada, None, NoDatum)
  let deprecated_ask_skh = "deprecated_ask_skh"
  let deprecated_ask_in =
    gen_input(
      from_script(deprecated_ask_skh),
      sc_in_lovelace,
      Some(
        value.from_asset(get_bond_policy_id(), bond_name_ask_1, sc_in_bond_qty),
      ),
      InlineDatum(sc_in_datum_1),
    )
  //
  let buyer_qty = 2
  let received_at_maturity = escrow_full_info.value_at_maturity * buyer_qty
  let received_with_yield = price_of_one_bond * buyer_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.maker_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.taker_fee / cfg.platform.basis.base
  //
  let sc_remaining_qty = sc_in_bond_qty - buyer_qty
  let min_ada_to_exchange =
    when sc_remaining_qty is {
      0 -> sc_in_lovelace
      _ -> 0
    }
  // = 124543
  let exchange_received = exchange_fee_buyer + exchange_fee_seller

  let exchange_address = get_exchange_address()
  let exchange_out_1 =
    gen_output(exchange_address, exchange_received, None, NoDatum)
  let owner_received =
    received_with_yield - exchange_fee_seller + min_ada_to_exchange
  let owner_out_bid_datum_1 =
    gen_bid_making_datum(owner_address, 463, 463, buyer_qty, 516)
  let owner_out_1 =
    gen_output(
      revert_address,
      owner_received,
      None,
      InlineDatum(owner_out_bid_datum_1),
    )
  // = 2_797_696_105
  let buyer_received = buyer_fee_ada - exchange_received - owner_received
  let buyer_out_1 =
    gen_output(
      buyer_address,
      buyer_received,
      Some(value.from_asset(get_bond_policy_id(), bond_name_ask_1, buyer_qty)),
      NoDatum,
    )

  let sc_out_datum_tampered = gen_tampered_ask_making_datum(owner_address, 515)
  let sc_out_1 =
    gen_output(
      sc_address,
      sc_in_lovelace - min_ada_to_exchange,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_ask_1,
          sc_remaining_qty,
        ),
      ),
      InlineDatum(sc_out_datum_tampered),
    )
  let tx =
    fixture.tx(
      [sc_in_1, buyer_in_1, deprecated_ask_in],
      [refer_in_1],
      [exchange_out_1, owner_out_1, buyer_out_1, sc_out_1],
      Some([get_seller_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  !buy.spending(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    sc_in_datum_1,
    [deprecated_ask_skh],
  )
}

test fail_when_attempting_unbound_value_attack_on_buy_full() {
  let time_of_tx = 1681095094000
  let cfg = get_config_making_mainnet()
  let owner_address = get_seller_address()
  let sc_in_datum_1 = gen_ask_making_datum(owner_address, 515)
  let revert_address = from_script(sc_in_datum_1.bid_sc)
  let bond_name_ask_1 = get_bond_id_1()
  // get_escrow_datum(asset_name: AssetName, bond_amount: Int, epo_rewards: Int, duration: Int, start: Int)
  let escrow_bond_amount = 10000
  let escrow_epo_rewards = 753424657
  let escrow_duration = 72
  let escrow_datum =
    get_escrow_datum(
      bond_name_ask_1,
      escrow_bond_amount,
      escrow_epo_rewards,
      escrow_duration,
      63,
    )
  // => epoch_start = 22190 epoch_end = 22244
  let escrow_lovelace =
    escrow_bond_amount * 100_000_000 + escrow_epo_rewards * escrow_duration
  let escrow_full_info =
    calc_escrow_full_info(
      cfg.platform,
      escrow_lovelace,
      escrow_datum,
      time_of_tx,
    )
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  //
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_ask_1,
      1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  //
  let sc_in_bond_qty = 5
  let sc_in_lovelace = 2068800
  let sc_address = get_ask_sc_address()
  let sc_in_1 =
    gen_input(
      sc_address,
      sc_in_lovelace,
      Some(
        value.from_asset(get_bond_policy_id(), bond_name_ask_1, sc_in_bond_qty),
      ),
      InlineDatum(sc_in_datum_1),
    )
  let buyer_fee_ada = 3000000000
  let buyer_address = get_buyer_address()
  let bond_name_ask_2 = get_bond_id_2()
  let buyer_in_1 =
    gen_input(
      buyer_address,
      buyer_fee_ada,
      Some(value.from_asset(get_bond_policy_id(), bond_name_ask_2, 3)),
      NoDatum,
    )
  //
  let buyer_qty = 5
  let received_at_maturity = escrow_full_info.value_at_maturity * buyer_qty
  let received_with_yield = price_of_one_bond * buyer_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.maker_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.taker_fee / cfg.platform.basis.base
  //
  let sc_remaining_qty = sc_in_bond_qty - buyer_qty
  let min_ada_to_exchange =
    when sc_remaining_qty is {
      0 -> sc_in_lovelace
      _ -> 0
    }
  let exchange_received = exchange_fee_buyer + exchange_fee_seller

  let exchange_address = get_exchange_address()
  let exchange_out_1 =
    gen_output(exchange_address, exchange_received, None, NoDatum)
  let owner_received =
    received_with_yield - exchange_fee_seller + min_ada_to_exchange
  let owner_out_bid_datum_1 =
    gen_bid_making_datum(owner_address, 463, 463, buyer_qty, 516)
  let owner_out_1 =
    gen_output(
      revert_address,
      owner_received,
      None,
      InlineDatum(owner_out_bid_datum_1),
    )
  let buyer_received =
    buyer_fee_ada + sc_in_lovelace - exchange_received - owner_received
  let buyer_out_1 =
    gen_output(
      buyer_address,
      buyer_received,
      Some(
        value.add(
          value.from_asset(get_bond_policy_id(), bond_name_ask_2, 3),
          get_bond_policy_id(),
          bond_name_ask_1,
          buyer_qty,
        ),
      ),
      NoDatum,
    )
  let sc_out_1 =
    gen_output(
      sc_address,
      sc_in_lovelace - min_ada_to_exchange,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_ask_1,
          sc_remaining_qty,
        ),
      ),
      InlineDatum(sc_in_datum_1),
    )

  let tx =
    fixture.tx(
      [sc_in_1, buyer_in_1],
      [refer_in_1],
      [
        exchange_out_1,
        owner_out_1 |> add_asset(dummy_pid, dummy_tkn, 1),
        buyer_out_1,
        sc_out_1,
      ],
      Some([get_seller_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  !buy.spending(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    sc_in_datum_1,
    [],
  )
}

test fail_when_attempting_unbound_value_attack_on_buy_partial_1() {
  let time_of_tx = 1681095094000
  let cfg = get_config_making_mainnet()
  let owner_address = get_seller_address()
  let sc_in_datum_1 = gen_ask_making_datum(owner_address, 515)
  let revert_address = from_script(sc_in_datum_1.bid_sc)
  let bond_name_ask_1 = get_bond_id_1()
  let bond_name_ask_2 = get_bond_id_2()
  // get_escrow_datum(asset_name: AssetName, bond_amount: Int, epo_rewards: Int, duration: Int, start: Int)
  let escrow_bond_amount = 10000
  let escrow_epo_rewards = 753424657
  let escrow_duration = 72
  let escrow_datum =
    get_escrow_datum(
      bond_name_ask_1,
      escrow_bond_amount,
      escrow_epo_rewards,
      escrow_duration,
      63,
    )
  // => epoch_start = 22190 epoch_end = 22244
  let escrow_lovelace =
    escrow_bond_amount * 100_000_000 + escrow_epo_rewards * escrow_duration
  let escrow_full_info =
    calc_escrow_full_info(
      cfg.platform,
      escrow_lovelace,
      escrow_datum,
      time_of_tx,
    )
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  //
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_ask_1,
      1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  //
  let sc_in_bond_qty = 5
  let sc_in_lovelace = 2068800
  let sc_address = get_ask_sc_address()
  let sc_in_1 =
    gen_input(
      sc_address,
      sc_in_lovelace,
      Some(
        value.from_asset(get_bond_policy_id(), bond_name_ask_1, sc_in_bond_qty),
      ),
      InlineDatum(sc_in_datum_1),
    )
  let buyer_fee_ada = 3000000000
  let buyer_address = get_buyer_address()
  let buyer_in_1 =
    gen_input(
      buyer_address,
      buyer_fee_ada,
      Some(value.from_asset(get_bond_policy_id(), bond_name_ask_2, 3)),
      NoDatum,
    )
  //
  let buyer_qty = 2
  let received_at_maturity = escrow_full_info.value_at_maturity * buyer_qty
  let received_with_yield = price_of_one_bond * buyer_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.maker_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.taker_fee / cfg.platform.basis.base
  //
  let sc_remaining_qty = sc_in_bond_qty - buyer_qty
  let min_ada_to_exchange =
    when sc_remaining_qty is {
      0 -> sc_in_lovelace
      _ -> 0
    }
  let exchange_received = exchange_fee_buyer + exchange_fee_seller

  let exchange_address = get_exchange_address()
  let exchange_out_1 =
    gen_output(exchange_address, exchange_received, None, NoDatum)
  let owner_received =
    received_with_yield - exchange_fee_seller + min_ada_to_exchange
  let owner_out_bid_datum_1 =
    gen_bid_making_datum(owner_address, 463, 463, buyer_qty, 516)
  let owner_out_1 =
    gen_output(
      revert_address,
      owner_received,
      None,
      InlineDatum(owner_out_bid_datum_1),
    )
  let buyer_received =
    buyer_fee_ada + sc_in_lovelace - exchange_received - owner_received
  let buyer_out_1 =
    gen_output(
      buyer_address,
      buyer_received,
      Some(
        value.add(
          value.from_asset(get_bond_policy_id(), bond_name_ask_2, buyer_qty),
          get_bond_policy_id(),
          bond_name_ask_1,
          3,
        ),
      ),
      NoDatum,
    )
  let sc_out_1 =
    gen_output(
      sc_address,
      sc_in_lovelace - min_ada_to_exchange,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_ask_1,
          sc_remaining_qty,
        ),
      ),
      InlineDatum(sc_in_datum_1),
    )
  let tx =
    fixture.tx(
      [sc_in_1, buyer_in_1],
      [refer_in_1],
      [
        exchange_out_1,
        owner_out_1 |> add_asset(dummy_pid, dummy_tkn, 1),
        buyer_out_1,
        sc_out_1,
      ],
      Some([get_seller_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  !buy.spending(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    sc_in_datum_1,
    [],
  )
}

test fail_when_attempting_unbound_value_attack_on_buy_partial_2() {
  let time_of_tx = 1681095094000
  let cfg = get_config_making_mainnet()
  let owner_address = get_seller_address()
  let sc_in_datum_1 = gen_ask_making_datum(owner_address, 515)
  let revert_address = from_script(sc_in_datum_1.bid_sc)
  let bond_name_ask_1 = get_bond_id_1()
  let bond_name_ask_2 = get_bond_id_2()
  // get_escrow_datum(asset_name: AssetName, bond_amount: Int, epo_rewards: Int, duration: Int, start: Int)
  let escrow_bond_amount = 10000
  let escrow_epo_rewards = 753424657
  let escrow_duration = 72
  let escrow_datum =
    get_escrow_datum(
      bond_name_ask_1,
      escrow_bond_amount,
      escrow_epo_rewards,
      escrow_duration,
      63,
    )
  // => epoch_start = 22190 epoch_end = 22244
  let escrow_lovelace =
    escrow_bond_amount * 100_000_000 + escrow_epo_rewards * escrow_duration
  let escrow_full_info =
    calc_escrow_full_info(
      cfg.platform,
      escrow_lovelace,
      escrow_datum,
      time_of_tx,
    )
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  //
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_ask_1,
      1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  //
  let sc_in_bond_qty = 5
  let sc_in_lovelace = 2068800
  let sc_address = get_ask_sc_address()
  let sc_in_1 =
    gen_input(
      sc_address,
      sc_in_lovelace,
      Some(
        value.from_asset(get_bond_policy_id(), bond_name_ask_1, sc_in_bond_qty),
      ),
      InlineDatum(sc_in_datum_1),
    )
  let buyer_fee_ada = 3000000000
  let buyer_address = get_buyer_address()
  let buyer_in_1 =
    gen_input(
      buyer_address,
      buyer_fee_ada,
      Some(value.from_asset(get_bond_policy_id(), bond_name_ask_2, 3)),
      NoDatum,
    )
  //
  let buyer_qty = 2
  let received_at_maturity = escrow_full_info.value_at_maturity * buyer_qty
  let received_with_yield = price_of_one_bond * buyer_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.maker_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.taker_fee / cfg.platform.basis.base
  //
  let sc_remaining_qty = sc_in_bond_qty - buyer_qty
  let min_ada_to_exchange =
    when sc_remaining_qty is {
      0 -> sc_in_lovelace
      _ -> 0
    }
  let exchange_received = exchange_fee_buyer + exchange_fee_seller

  let exchange_address = get_exchange_address()
  let exchange_out_1 =
    gen_output(exchange_address, exchange_received, None, NoDatum)
  let owner_received =
    received_with_yield - exchange_fee_seller + min_ada_to_exchange
  let owner_out_bid_datum_1 =
    gen_bid_making_datum(owner_address, 463, 463, buyer_qty, 516)
  let owner_out_1 =
    gen_output(
      revert_address,
      owner_received,
      None,
      InlineDatum(owner_out_bid_datum_1),
    )
  let buyer_received =
    buyer_fee_ada + sc_in_lovelace - exchange_received - owner_received
  let buyer_out_1 =
    gen_output(
      buyer_address,
      buyer_received,
      Some(
        value.add(
          value.from_asset(get_bond_policy_id(), bond_name_ask_2, buyer_qty),
          get_bond_policy_id(),
          bond_name_ask_1,
          3,
        ),
      ),
      NoDatum,
    )
  let sc_out_1 =
    gen_output(
      sc_address,
      sc_in_lovelace - min_ada_to_exchange,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_ask_1,
          sc_remaining_qty,
        ),
      ),
      InlineDatum(sc_in_datum_1),
    )
  let tx =
    fixture.tx(
      [sc_in_1, buyer_in_1],
      [refer_in_1],
      [
        exchange_out_1,
        owner_out_1,
        buyer_out_1,
        sc_out_1 |> add_asset(dummy_pid, dummy_tkn, 1),
      ],
      Some([get_seller_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  !buy.spending(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    sc_in_datum_1,
    [],
  )
}

test fail_unsafe_fee_datum() fail {
  let time_of_tx = 1681095094000
  let cfg = get_config_making_mainnet()
  let exchange_address = get_exchange_address()
  let owner_address = get_seller_address()
  let sc_in_datum_1 = gen_ask_making_datum(owner_address, 515)
  let revert_address = from_script(sc_in_datum_1.bid_sc)
  let bond_name_ask_1 = get_bond_id_1()
  let bond_name_ask_2 = get_bond_id_2()
  // get_escrow_datum(asset_name: AssetName, bond_amount: Int, epo_rewards: Int, duration: Int, start: Int)
  let escrow_bond_amount = 10000
  let escrow_epo_rewards = 753424657
  let escrow_duration = 72
  let escrow_datum =
    get_escrow_datum(
      bond_name_ask_1,
      escrow_bond_amount,
      escrow_epo_rewards,
      escrow_duration,
      63,
    )
  // => epoch_start = 22190 epoch_end = 22244
  let escrow_lovelace =
    escrow_bond_amount * 100_000_000 + escrow_epo_rewards * escrow_duration
  let escrow_full_info =
    calc_escrow_full_info(
      cfg.platform,
      escrow_lovelace,
      escrow_datum,
      time_of_tx,
    )
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  //
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_ask_1,
      1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  //
  let sc_in_bond_qty = 5
  let sc_in_lovelace = 2068800
  let sc_address = get_ask_sc_address()
  let sc_in_1 =
    gen_input(
      sc_address,
      sc_in_lovelace,
      Some(
        value.from_asset(get_bond_policy_id(), bond_name_ask_1, sc_in_bond_qty),
      ),
      InlineDatum(sc_in_datum_1),
    )
  let buyer_fee_ada = 3000000000
  let buyer_address = exchange_address
  let buyer_in_1 =
    gen_input(
      buyer_address,
      buyer_fee_ada,
      Some(value.from_asset(get_bond_policy_id(), bond_name_ask_2, 3)),
      NoDatum,
    )
  //
  let buyer_qty = 2
  let received_at_maturity = escrow_full_info.value_at_maturity * buyer_qty
  let received_with_yield = price_of_one_bond * buyer_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.maker_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.taker_fee / cfg.platform.basis.base
  //
  let sc_remaining_qty = sc_in_bond_qty - buyer_qty
  let min_ada_to_exchange =
    when sc_remaining_qty is {
      0 -> sc_in_lovelace
      _ -> 0
    }
  let exchange_received = exchange_fee_buyer + exchange_fee_seller

  let exchange_out_1 =
    gen_output(
      exchange_address,
      exchange_received,
      None,
      DatumHash("abitrary_digest"),
    )
  let owner_received =
    received_with_yield - exchange_fee_seller + min_ada_to_exchange
  let owner_out_bid_datum_1 =
    gen_bid_making_datum(owner_address, 463, 463, buyer_qty, 516)
  let owner_out_1 =
    gen_output(
      revert_address,
      owner_received,
      None,
      InlineDatum(owner_out_bid_datum_1),
    )
  let buyer_received =
    buyer_fee_ada + sc_in_lovelace - exchange_received - owner_received
  let buyer_out_1 =
    gen_output(
      buyer_address,
      buyer_received,
      Some(
        value.add(
          value.from_asset(get_bond_policy_id(), bond_name_ask_2, buyer_qty),
          get_bond_policy_id(),
          bond_name_ask_1,
          3,
        ),
      ),
      NoDatum,
    )
  let sc_out_1 =
    gen_output(
      sc_address,
      sc_in_lovelace - min_ada_to_exchange,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_ask_1,
          sc_remaining_qty,
        ),
      ),
      InlineDatum(sc_in_datum_1),
    )
  let tx =
    fixture.tx(
      [sc_in_1, buyer_in_1],
      [refer_in_1],
      [exchange_out_1, owner_out_1, buyer_out_1, sc_out_1],
      Some([get_seller_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  buy.spending(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    sc_in_datum_1,
    [],
  )
}
