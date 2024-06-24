// Ask Limit
use aiken/builtin
use aiken/transaction.{InlineDatum, NoDatum, DatumHash, ScriptContext, Spend}
use aiken/transaction/credential.{
  Address, from_script, with_delegation_key, with_delegation_script,
}
use aiken/transaction/value
use bond/common/fixture.{
  calc_escrow_full_info, gen_ask_limit_datum, gen_input, gen_output,
  get_ask_sc_address, get_bond_id_1, get_bond_id_2, get_bond_policy_id,
  get_buyer_address, get_config_limit_mainnet, get_config_limit_preview,
  get_escrow_address, get_escrow_address_unexpect, get_escrow_datum,
  get_escrow_policy_id, get_exchange_address, get_input_escrow,
  get_not_bond_policy_id, get_not_escrow_policy_id, get_payment_datum,
  get_seller_address, get_seller_address_hash,
}
use bond/common/utils.{get_price_of_bond}
use bond/limit_ask/buy
use common/time.{posix_time_to_relative_epoch}

test fail_partial_must_only_one_bond_1() fail {
  let time_of_tx = 1681095094000
  let cfg = get_config_limit_mainnet()
  let owner_address = get_owner_address()
  let sc_in_datum_1 = gen_ask_limit_datum(owner_address, 515)
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
    received_diff * cfg.exchange.seller_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.platform.basis.base
  //
  let min_ada_to_exchange =
    when sc_in_bond_qty - buyer_qty is {
      0 -> sc_in_lovelace
      _ -> 0
    }
  let exchange_received =
    exchange_fee_buyer + exchange_fee_seller + min_ada_to_exchange

  // exchange_received == 82755 * 2
  let payment_datum = get_payment_datum()
  let payment_datum_data = builtin.serialise_data(payment_datum)
  let exchange_address = get_exchange_address()
  let exchange_out_1 =
    gen_output(
      exchange_address,
      exchange_received,
      None,
      InlineDatum(payment_datum_data),
    )
  let owner_received = received_with_yield - exchange_fee_seller
  let owner_out_1 =
    gen_output(
      owner_address,
      owner_received,
      None,
      InlineDatum(payment_datum_data),
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
      InlineDatum(payment_datum_data),
    )
  let sc_out_1 =
    gen_output(
      sc_address,
      sc_in_lovelace - min_ada_to_exchange,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_ask_1,
          sc_in_bond_qty - buyer_qty,
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
  let cfg = get_config_limit_mainnet()
  let owner_address = get_owner_address()
  let sc_in_datum_1 = gen_ask_limit_datum(owner_address, 515)
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
    received_diff * cfg.exchange.seller_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.platform.basis.base
  //
  let min_ada_to_exchange =
    when sc_in_bond_qty - buyer_qty is {
      0 -> sc_in_lovelace
      _ -> 0
    }
  let exchange_received =
    exchange_fee_buyer + exchange_fee_seller + min_ada_to_exchange

  // exchange_received == 82755 * 2
  let payment_datum = get_payment_datum()
  let payment_datum_data = builtin.serialise_data(payment_datum)
  let exchange_address = get_exchange_address()
  let exchange_out_1 =
    gen_output(
      exchange_address,
      exchange_received,
      None,
      InlineDatum(payment_datum_data),
    )
  let owner_received = received_with_yield - exchange_fee_seller
  let owner_out_1 =
    gen_output(
      owner_address,
      owner_received,
      None,
      InlineDatum(payment_datum_data),
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
      InlineDatum(payment_datum_data),
    )
  let sc_out_1 =
    gen_output(
      sc_address,
      sc_in_lovelace - min_ada_to_exchange,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_ask_1,
          sc_in_bond_qty - buyer_qty,
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

test fail_partial_change_bond_name() {
  let time_of_tx = 1681095094000
  let cfg = get_config_limit_mainnet()
  let owner_address = get_owner_address()
  let sc_in_datum_1 = gen_ask_limit_datum(owner_address, 515)
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
    received_diff * cfg.exchange.seller_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.platform.basis.base
  //
  let min_ada_to_exchange =
    when sc_in_bond_qty - buyer_qty is {
      0 -> sc_in_lovelace
      _ -> 0
    }
  let exchange_received =
    exchange_fee_buyer + exchange_fee_seller + min_ada_to_exchange

  // exchange_received == 82755 * 2
  let payment_datum = get_payment_datum()
  let payment_datum_data = builtin.serialise_data(payment_datum)
  let exchange_address = get_exchange_address()
  let exchange_out_1 =
    gen_output(
      exchange_address,
      exchange_received,
      None,
      InlineDatum(payment_datum_data),
    )
  let owner_received = received_with_yield - exchange_fee_seller
  let owner_out_1 =
    gen_output(
      owner_address,
      owner_received,
      None,
      InlineDatum(payment_datum_data),
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
      InlineDatum(payment_datum_data),
    )
  let sc_out_1 =
    gen_output(
      sc_address,
      sc_in_lovelace - min_ada_to_exchange,
      Some(
        value.from_asset(get_bond_policy_id(), bond_name_ask_2, sc_in_bond_qty),
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
  let cfg = get_config_limit_mainnet()
  let owner_address = get_owner_address()
  let sc_in_datum_1 = gen_ask_limit_datum(owner_address, 515)
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
    received_diff * cfg.exchange.seller_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.platform.basis.base
  //
  let min_ada_to_exchange =
    when sc_in_bond_qty - buyer_qty is {
      0 -> sc_in_lovelace
      _ -> 0
    }
  let exchange_received =
    exchange_fee_buyer + exchange_fee_seller + min_ada_to_exchange

  // exchange_received == 82755 * 2
  let payment_datum = get_payment_datum()
  let payment_datum_data = builtin.serialise_data(payment_datum)
  let exchange_address = get_exchange_address()
  let exchange_out_1 =
    gen_output(
      exchange_address,
      exchange_received,
      None,
      InlineDatum(payment_datum_data),
    )
  let owner_received = received_with_yield - exchange_fee_seller
  let owner_out_1 =
    gen_output(
      owner_address,
      owner_received,
      None,
      InlineDatum(payment_datum_data),
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
      InlineDatum(payment_datum_data),
    )
  let sc_out_datum_1 =
    gen_ask_limit_datum(credential.from_script(#"010203040506"), 515)
  let sc_out_1 =
    gen_output(
      sc_address,
      sc_in_lovelace - min_ada_to_exchange,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_ask_1,
          sc_in_bond_qty - buyer_qty,
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
  let cfg = get_config_limit_mainnet()
  let owner_address = get_owner_address()
  let buyer_address = get_buyer_address()
  let sc_in_datum_1 = gen_ask_limit_datum(owner_address, 515)
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
    received_diff * cfg.exchange.seller_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.platform.basis.base
  //
  let min_ada_to_exchange =
    when sc_in_bond_qty - buyer_qty is {
      0 -> sc_in_lovelace
      _ -> 0
    }
  let exchange_received =
    exchange_fee_buyer + exchange_fee_seller + min_ada_to_exchange

  // exchange_received == 82755 * 2
  let payment_datum = get_payment_datum()
  let payment_datum_data = builtin.serialise_data(payment_datum)
  let exchange_address = get_exchange_address()
  let exchange_out_1 =
    gen_output(
      exchange_address,
      exchange_received,
      None,
      InlineDatum(payment_datum_data),
    )
  let owner_received = received_with_yield - exchange_fee_seller
  let owner_out_1 =
    gen_output(
      owner_address,
      owner_received,
      None,
      InlineDatum(payment_datum_data),
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
      InlineDatum(payment_datum_data),
    )
  let sc_out_datum_1 = gen_ask_limit_datum(buyer_address, 515)
  let sc_out_1 =
    gen_output(
      sc_address,
      sc_in_lovelace - min_ada_to_exchange,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_ask_1,
          sc_in_bond_qty - buyer_qty,
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
  let cfg = get_config_limit_mainnet()
  let owner_address = get_owner_address()
  let sc_in_datum_1 =
    gen_ask_limit_datum(
      credential.with_delegation_key(owner_address, #"010203040506"),
      515,
    )
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
    received_diff * cfg.exchange.seller_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.platform.basis.base
  //
  let min_ada_to_exchange =
    when sc_in_bond_qty - buyer_qty is {
      0 -> sc_in_lovelace
      _ -> 0
    }
  let exchange_received =
    exchange_fee_buyer + exchange_fee_seller + min_ada_to_exchange

  // exchange_received == 82755 * 2
  let payment_datum = get_payment_datum()
  let payment_datum_data = builtin.serialise_data(payment_datum)
  let exchange_address = get_exchange_address()
  let exchange_out_1 =
    gen_output(
      exchange_address,
      exchange_received,
      None,
      InlineDatum(payment_datum_data),
    )
  let owner_received = received_with_yield - exchange_fee_seller
  let owner_out_1 =
    gen_output(
      owner_address,
      owner_received,
      None,
      InlineDatum(payment_datum_data),
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
      InlineDatum(payment_datum_data),
    )
  let sc_out_datum_1 =
    gen_ask_limit_datum(
      credential.with_delegation_key(owner_address, #"010203040507"),
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
          sc_in_bond_qty - buyer_qty,
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
  let cfg = get_config_limit_mainnet()
  let owner_address = get_owner_address()
  let sc_in_datum_1 =
    gen_ask_limit_datum(
      credential.with_delegation_key(owner_address, #"010203040506"),
      515,
    )
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
    received_diff * cfg.exchange.seller_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.platform.basis.base
  //
  let min_ada_to_exchange =
    when sc_in_bond_qty - buyer_qty is {
      0 -> sc_in_lovelace
      _ -> 0
    }
  let exchange_received =
    exchange_fee_buyer + exchange_fee_seller + min_ada_to_exchange

  // exchange_received == 82755 * 2
  let payment_datum = get_payment_datum()
  let payment_datum_data = builtin.serialise_data(payment_datum)
  let exchange_address = get_exchange_address()
  let exchange_out_1 =
    gen_output(
      exchange_address,
      exchange_received,
      None,
      InlineDatum(payment_datum_data),
    )
  let owner_received = received_with_yield - exchange_fee_seller
  let owner_out_1 =
    gen_output(
      owner_address,
      owner_received,
      None,
      InlineDatum(payment_datum_data),
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
      InlineDatum(payment_datum_data),
    )
  let sc_out_datum_1 =
    gen_ask_limit_datum(
      credential.with_delegation_script(owner_address, #"010203040506"),
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
          sc_in_bond_qty - buyer_qty,
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
  let cfg = get_config_limit_mainnet()
  let owner_address = get_owner_address()
  let sc_in_datum_1 = gen_ask_limit_datum(owner_address, 515)
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
    received_diff * cfg.exchange.seller_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.platform.basis.base
  //
  let min_ada_to_exchange =
    when sc_in_bond_qty - buyer_qty is {
      0 -> sc_in_lovelace
      _ -> 0
    }
  let exchange_received =
    exchange_fee_buyer + exchange_fee_seller + min_ada_to_exchange

  // exchange_received == 82755 * 2
  let payment_datum = get_payment_datum()
  let payment_datum_data = builtin.serialise_data(payment_datum)
  let exchange_address = get_exchange_address()
  let exchange_out_1 =
    gen_output(
      exchange_address,
      exchange_received,
      None,
      InlineDatum(payment_datum_data),
    )
  let owner_received = received_with_yield - exchange_fee_seller
  let owner_out_1 =
    gen_output(
      owner_address,
      owner_received,
      None,
      InlineDatum(payment_datum_data),
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
      InlineDatum(payment_datum_data),
    )
  let sc_out_datum_1 = gen_ask_limit_datum(owner_address, 785)
  let sc_out_1 =
    gen_output(
      sc_address,
      sc_in_lovelace - min_ada_to_exchange,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_ask_1,
          sc_in_bond_qty - buyer_qty,
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
  let cfg = get_config_limit_mainnet()
  let owner_address = get_owner_address()
  let sc_in_datum_1 = gen_ask_limit_datum(owner_address, 515)
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
    received_diff * cfg.exchange.seller_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.platform.basis.base
  //
  let min_ada_to_exchange =
    when sc_in_bond_qty - buyer_qty is {
      0 -> sc_in_lovelace
      _ -> 0
    }
  let exchange_received =
    exchange_fee_buyer + exchange_fee_seller + min_ada_to_exchange

  // exchange_received == 82755 * 2
  let payment_datum = get_payment_datum()
  let payment_datum_data = builtin.serialise_data(payment_datum)
  let exchange_address = get_exchange_address()
  let exchange_out_1 =
    gen_output(
      exchange_address,
      exchange_received,
      None,
      InlineDatum(payment_datum_data),
    )
  let owner_received = received_with_yield - exchange_fee_seller
  let owner_out_1 =
    gen_output(
      owner_address,
      owner_received,
      None,
      InlineDatum(payment_datum_data),
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
      InlineDatum(payment_datum_data),
    )
  let sc_out_1 =
    gen_output(
      sc_address,
      sc_in_lovelace - min_ada_to_exchange,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_ask_1,
          sc_in_bond_qty - buyer_qty,
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
  let cfg = get_config_limit_mainnet()
  let owner_address = get_owner_address()
  let sc_in_datum_1 = gen_ask_limit_datum(owner_address, 515)
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
    received_diff * cfg.exchange.seller_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.platform.basis.base
  //
  let min_ada_to_exchange =
    when sc_in_bond_qty - buyer_qty is {
      0 -> sc_in_lovelace
      _ -> 0
    }
  let exchange_received =
    exchange_fee_buyer + exchange_fee_seller + min_ada_to_exchange

  // exchange_received == 82755 * 2
  let payment_datum = get_payment_datum()
  let payment_datum_data = builtin.serialise_data(payment_datum)
  let exchange_address = get_exchange_address()
  let exchange_out_1 =
    gen_output(
      exchange_address,
      exchange_received,
      None,
      InlineDatum(payment_datum_data),
    )
  let owner_received = received_with_yield - exchange_fee_seller
  let owner_out_1 =
    gen_output(
      owner_address,
      owner_received,
      None,
      InlineDatum(payment_datum_data),
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
      InlineDatum(payment_datum_data),
    )
  let sc_out_1 =
    gen_output(
      sc_address,
      sc_in_lovelace - min_ada_to_exchange,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_ask_1,
          sc_in_bond_qty - buyer_qty,
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

test fail_escrow_address_unexpect() fail {
  let time_of_tx = 1681095094000
  let cfg = get_config_limit_mainnet()
  let owner_address = get_owner_address()
  let sc_in_datum_1 = gen_ask_limit_datum(owner_address, 515)
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
    received_diff * cfg.exchange.seller_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.platform.basis.base
  //
  let min_ada_to_exchange =
    when sc_in_bond_qty - buyer_qty is {
      0 -> sc_in_lovelace
      _ -> 0
    }
  let exchange_received =
    exchange_fee_buyer + exchange_fee_seller + min_ada_to_exchange

  // exchange_received == 82755 * 2
  let payment_datum = get_payment_datum()
  let payment_datum_data = builtin.serialise_data(payment_datum)
  let exchange_address = get_exchange_address()
  let exchange_out_1 =
    gen_output(
      exchange_address,
      exchange_received,
      None,
      InlineDatum(payment_datum_data),
    )
  let owner_received = received_with_yield - exchange_fee_seller
  let owner_out_1 =
    gen_output(
      owner_address,
      owner_received,
      None,
      InlineDatum(payment_datum_data),
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
      InlineDatum(payment_datum_data),
    )
  let sc_out_1 =
    gen_output(
      sc_address,
      sc_in_lovelace - min_ada_to_exchange,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_ask_1,
          sc_in_bond_qty - buyer_qty,
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
  let cfg = get_config_limit_mainnet()
  let owner_address = get_owner_address()
  let sc_in_datum_1 = gen_ask_limit_datum(owner_address, 515)
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
    received_diff * cfg.exchange.seller_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.platform.basis.base
  //
  let min_ada_to_exchange =
    when sc_in_bond_qty - buyer_qty is {
      0 -> sc_in_lovelace
      _ -> 0
    }
  let exchange_received =
    exchange_fee_buyer + exchange_fee_seller + min_ada_to_exchange

  // exchange_received == 82755 * 2
  let payment_datum = get_payment_datum()
  let payment_datum_data = builtin.serialise_data(payment_datum)
  let exchange_address = get_exchange_address()
  let exchange_out_1 =
    gen_output(
      exchange_address,
      exchange_received,
      None,
      InlineDatum(payment_datum_data),
    )
  let owner_received = received_with_yield - exchange_fee_seller
  let owner_out_1 =
    gen_output(
      owner_address,
      owner_received,
      None,
      InlineDatum(payment_datum_data),
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
      InlineDatum(payment_datum_data),
    )
  let sc_out_1 =
    gen_output(
      sc_address,
      sc_in_lovelace - min_ada_to_exchange,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_ask_1,
          sc_in_bond_qty - buyer_qty,
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
  let cfg = get_config_limit_mainnet()
  let owner_address = get_owner_address()
  let sc_in_datum_1 = gen_ask_limit_datum(owner_address, 515)
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
    received_diff * cfg.exchange.seller_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.platform.basis.base
  //
  let min_ada_to_exchange =
    when sc_in_bond_qty - buyer_qty is {
      0 -> sc_in_lovelace
      _ -> 0
    }
  let exchange_received =
    exchange_fee_buyer + exchange_fee_seller + min_ada_to_exchange

  // exchange_received == 82755 * 2
  let payment_datum = get_payment_datum()
  let payment_datum_data = builtin.serialise_data(payment_datum)
  let exchange_address = get_exchange_address()
  let exchange_out_1 =
    gen_output(
      exchange_address,
      exchange_received,
      None,
      InlineDatum(payment_datum_data),
    )
  let owner_received = received_with_yield - exchange_fee_seller
  let owner_out_1 =
    gen_output(
      owner_address,
      owner_received,
      None,
      InlineDatum(payment_datum_data),
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
      InlineDatum(payment_datum_data),
    )
  let sc_out_1 =
    gen_output(
      sc_address,
      sc_in_lovelace - min_ada_to_exchange,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_ask_1,
          sc_in_bond_qty - buyer_qty,
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
  let time_of_tx = 1681095094000
  let cfg = get_config_limit_mainnet()
  let owner_address = get_owner_address()
  let sc_in_datum_1 = gen_ask_limit_datum(owner_address, 515)
  let bond_name_ask_1 = get_bond_id_1()
  let bond_name_ask_2 = get_bond_id_2()
  let escrow_datum_start = 63
  let escrow_duration = 72
  let escrow_epo_rewards = 753424657
  let current_epoch =
    posix_time_to_relative_epoch(time_of_tx, cfg.platform.epoch)
  let start_epoch =
    escrow_datum_start + cfg.platform.epoch.epoch_boundary_as_epoch
  let end_epoch = start_epoch + escrow_duration
  let claim_amount = 1000
  let claim_amount_principal_lovelace =
    claim_amount * cfg.platform.bond_face_value
  let claim_amount_interest_lovelace =
    claim_amount * (
      if current_epoch >= end_epoch {
        escrow_duration
      } else {
        current_epoch - start_epoch + 1
      } * escrow_epo_rewards
    )
  let claim_lovelace =
    claim_amount_principal_lovelace + claim_amount_interest_lovelace
  let escrow_bond_amount = 10000
  // get_escrow_datum(asset_name: AssetName, bond_amount: Int, epo_rewards: Int, duration: Int, start: Int)
  let escrow_datum_amount_remaining = escrow_bond_amount - claim_amount
  let escrow_datum =
    get_escrow_datum(
      bond_name_ask_1,
      escrow_datum_amount_remaining,
      escrow_epo_rewards,
      escrow_duration,
      escrow_datum_start,
    )
  // => epoch_start = 22190 epoch_end = 22244
  let escrow_lovelace_pre_claim =
    escrow_bond_amount * 100_000_000 + escrow_epo_rewards * escrow_duration
  let escrow_lovelace = escrow_lovelace_pre_claim - claim_lovelace
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
    received_diff * cfg.exchange.seller_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.platform.basis.base
  //
  let min_ada_to_exchange =
    when sc_in_bond_qty - buyer_qty is {
      0 -> sc_in_lovelace
      _ -> 0
    }
  let exchange_received =
    exchange_fee_buyer + exchange_fee_seller + min_ada_to_exchange

  // exchange_received == 82755 * 2
  let payment_datum = get_payment_datum()
  let payment_datum_data = builtin.serialise_data(payment_datum)
  let exchange_address = get_exchange_address()
  let exchange_out_1 =
    gen_output(
      exchange_address,
      exchange_received,
      None,
      InlineDatum(payment_datum_data),
    )
  let owner_received = received_with_yield - exchange_fee_seller
  let owner_out_1 =
    gen_output(
      owner_address,
      owner_received,
      None,
      InlineDatum(payment_datum_data),
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
      InlineDatum(payment_datum_data),
    )
  let sc_out_1 =
    gen_output(
      sc_address,
      sc_in_lovelace - min_ada_to_exchange,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_ask_1,
          sc_in_bond_qty - buyer_qty,
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

test fail_buyer_must_not_owner() fail {
  let time_of_tx = 1681095094000
  let cfg = get_config_limit_mainnet()
  let owner_address = get_owner_address()
  let sc_in_datum_1 = gen_ask_limit_datum(owner_address, 515)
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
    received_diff * cfg.exchange.seller_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.platform.basis.base
  //
  let min_ada_to_exchange =
    when sc_in_bond_qty - buyer_qty is {
      0 -> sc_in_lovelace
      _ -> 0
    }
  let exchange_received =
    exchange_fee_buyer + exchange_fee_seller + min_ada_to_exchange

  // exchange_received == 82755 * 2
  let payment_datum = get_payment_datum()
  let payment_datum_data = builtin.serialise_data(payment_datum)
  let exchange_address = get_exchange_address()
  let exchange_out_1 =
    gen_output(
      exchange_address,
      exchange_received,
      None,
      InlineDatum(payment_datum_data),
    )
  let owner_received = received_with_yield - exchange_fee_seller
  let owner_out_1 =
    gen_output(
      owner_address,
      owner_received,
      None,
      InlineDatum(payment_datum_data),
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
      InlineDatum(payment_datum_data),
    )
  let sc_out_1 =
    gen_output(
      sc_address,
      sc_in_lovelace - min_ada_to_exchange,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_ask_1,
          sc_in_bond_qty - buyer_qty,
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

test succ_buyer_is_exchange() {
  let time_of_tx = 1681095094000
  let cfg = get_config_limit_mainnet()
  let exchange_address = get_exchange_address()
  let owner_address = get_owner_address()
  let sc_in_datum_1 = gen_ask_limit_datum(owner_address, 515)
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
    received_diff * cfg.exchange.seller_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.platform.basis.base
  //
  let min_ada_to_exchange =
    when sc_in_bond_qty - buyer_qty is {
      0 -> sc_in_lovelace
      _ -> 0
    }
  let exchange_received =
    exchange_fee_buyer + exchange_fee_seller + min_ada_to_exchange

  // exchange_received == 82755 * 2
  let payment_datum = get_payment_datum()
  let payment_datum_data = builtin.serialise_data(payment_datum)
  let exchange_out_1 =
    gen_output(
      exchange_address,
      exchange_received,
      None,
      InlineDatum(payment_datum_data),
    )
  let owner_received = received_with_yield - exchange_fee_seller
  let owner_out_1 =
    gen_output(
      owner_address,
      owner_received,
      None,
      InlineDatum(payment_datum_data),
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
      InlineDatum(payment_datum_data),
    )
  let sc_out_1 =
    gen_output(
      sc_address,
      sc_in_lovelace - min_ada_to_exchange,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_ask_1,
          sc_in_bond_qty - buyer_qty,
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
  let cfg = get_config_limit_mainnet()
  let owner_address = get_owner_address()
  let sc_in_datum_1 = gen_ask_limit_datum(owner_address, 515)
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
    received_diff * cfg.exchange.seller_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.platform.basis.base
  //
  let min_ada_to_exchange =
    when sc_in_bond_qty - buyer_qty is {
      0 -> sc_in_lovelace
      _ -> 0
    }
  let exchange_received =
    exchange_fee_buyer + exchange_fee_seller + min_ada_to_exchange

  // exchange_received == 82755 * 2
  let payment_datum = get_payment_datum()
  let payment_datum_data = builtin.serialise_data(payment_datum)
  let exchange_address = get_exchange_address()
  let exchange_out_1 =
    gen_output(
      exchange_address,
      exchange_received,
      None,
      InlineDatum(payment_datum_data),
    )
  let owner_received = received_with_yield - exchange_fee_seller
  let owner_out_1 =
    gen_output(
      owner_address,
      owner_received,
      None,
      InlineDatum(payment_datum_data),
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
      InlineDatum(payment_datum_data),
    )
  let sc_out_1 =
    gen_output(
      sc_address,
      sc_in_lovelace - min_ada_to_exchange,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_ask_1,
          sc_in_bond_qty - buyer_qty,
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
  let cfg = get_config_limit_mainnet()
  let owner_address = get_owner_address()
  let sc_in_datum_1 = gen_ask_limit_datum(owner_address, 515)
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
    received_diff * cfg.exchange.seller_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.platform.basis.base
  //
  let min_ada_to_exchange =
    when sc_in_bond_qty - buyer_qty is {
      0 -> sc_in_lovelace
      _ -> 0
    }
  let exchange_received =
    exchange_fee_buyer + exchange_fee_seller + min_ada_to_exchange

  // exchange_received == 82755 * 2
  let payment_datum = get_payment_datum()
  let payment_datum_data = builtin.serialise_data(payment_datum)
  let exchange_address = get_exchange_address()
  let exchange_out_1 =
    gen_output(
      exchange_address,
      exchange_received,
      None,
      InlineDatum(payment_datum_data),
    )
  let owner_received = received_with_yield - exchange_fee_seller
  let owner_out_1 =
    gen_output(
      owner_address,
      owner_received,
      None,
      InlineDatum(payment_datum_data),
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
      InlineDatum(payment_datum_data),
    )
  let sc_out_1 =
    gen_output(
      sc_address |> with_delegation_key("fake stake key"),
      sc_in_lovelace - min_ada_to_exchange,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_ask_1,
          sc_in_bond_qty - buyer_qty,
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

fn get_owner_address() -> Address {
  let seller_addr = get_seller_address()
  let sask_addr = get_ask_sc_address()
  Address {
    payment_credential: seller_addr.payment_credential,
    stake_credential: sask_addr.stake_credential,
  }
}

test succ_full_1() {
  let time_of_tx = 1681095094000
  let cfg = get_config_limit_mainnet()
  let owner_address = get_owner_address()
  let sc_in_datum_1 = gen_ask_limit_datum(owner_address, 515)
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
  let buyer_qty = 5
  let received_at_maturity = escrow_full_info.value_at_maturity * buyer_qty
  let received_with_yield = price_of_one_bond * buyer_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.seller_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.platform.basis.base
  //
  let min_ada_to_exchange =
    when sc_in_bond_qty - buyer_qty is {
      0 -> sc_in_lovelace
      _ -> 0
    }
  let exchange_received =
    exchange_fee_buyer + exchange_fee_seller + min_ada_to_exchange

  // exchange_received == 206888 * 2
  let payment_datum = get_payment_datum()
  let payment_datum_data = builtin.serialise_data(payment_datum)
  let exchange_address = get_exchange_address()
  let exchange_out_1 =
    gen_output(
      exchange_address,
      exchange_received,
      None,
      InlineDatum(payment_datum_data),
    )
  let owner_received = received_with_yield - exchange_fee_seller
  let owner_out_1 =
    gen_output(
      owner_address,
      owner_received,
      None,
      InlineDatum(payment_datum_data),
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
      InlineDatum(payment_datum_data),
    )
  let sc_out_1 =
    gen_output(
      sc_address,
      sc_in_lovelace - min_ada_to_exchange,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_ask_1,
          sc_in_bond_qty - buyer_qty,
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

test succ_full_2() {
  // let time_of_tx = 1666656000 000
  let time_of_tx = 1687343990000
  // => current_epoch = 22241
  let cfg = get_config_limit_preview()
  let owner_address = get_owner_address()
  let sc_in_datum_1 = gen_ask_limit_datum(owner_address, 7)
  let bond_name_ask_1 = get_bond_id_1()
  let bond_name_ask_2 = get_bond_id_2()
  // get_escrow_datum(asset_name: AssetName, bond_amount: Int, epo_rewards: Int, duration: Int, start: Int)
  let escrow_bond_amount = 20
  let escrow_epo_rewards = 1084931
  let escrow_duration = 54
  let escrow_datum =
    get_escrow_datum(
      bond_name_ask_1,
      escrow_bond_amount,
      escrow_epo_rewards,
      escrow_duration,
      21862,
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
  let sc_in_bond_qty = 2
  let buyer_qty = 1
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
    received_diff * cfg.exchange.seller_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.platform.basis.base
  //
  let min_ada_to_exchange =
    when sc_in_bond_qty - buyer_qty is {
      0 -> sc_in_lovelace
      _ -> 0
    }
  let exchange_received =
    exchange_fee_buyer + exchange_fee_seller + min_ada_to_exchange

  // exchange_received == 206888 * 2
  let payment_datum = get_payment_datum()
  let payment_datum_data = builtin.serialise_data(payment_datum)
  let exchange_address = get_exchange_address()
  let exchange_out_1 =
    gen_output(
      exchange_address,
      exchange_received,
      None,
      InlineDatum(payment_datum_data),
    )
  let owner_received = received_with_yield - exchange_fee_seller
  let owner_out_1 =
    gen_output(
      owner_address,
      owner_received,
      None,
      InlineDatum(payment_datum_data),
    )
  let buyer_received =
    buyer_fee_ada + sc_in_lovelace - exchange_received - owner_received
  let buyer_out_1 =
    gen_output(
      buyer_address,
      buyer_received,
      Some(value.from_asset(get_bond_policy_id(), bond_name_ask_2, 1)),
      InlineDatum(payment_datum_data),
    )
  let sc_out_1 =
    gen_output(
      sc_address,
      sc_in_lovelace - min_ada_to_exchange,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_ask_1,
          sc_in_bond_qty - buyer_qty,
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
  let sask_stake_key_hash = #"070201"
  let time_of_tx = 1681095094000
  let cfg = get_config_limit_mainnet()
  let owner_address =
    get_owner_address() |> with_delegation_script(sask_stake_key_hash)
  let sc_in_datum_1 = gen_ask_limit_datum(owner_address, 515)
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
  let buyer_qty = 5
  let received_at_maturity = escrow_full_info.value_at_maturity * buyer_qty
  let received_with_yield = price_of_one_bond * buyer_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.seller_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.platform.basis.base
  //
  let min_ada_to_exchange =
    when sc_in_bond_qty - buyer_qty is {
      0 -> sc_in_lovelace
      _ -> 0
    }
  let exchange_received =
    exchange_fee_buyer + exchange_fee_seller + min_ada_to_exchange

  // exchange_received == 206888 * 2
  let payment_datum = get_payment_datum()
  let payment_datum_data = builtin.serialise_data(payment_datum)
  let exchange_address = get_exchange_address()
  let exchange_out_1 =
    gen_output(
      exchange_address,
      exchange_received,
      None,
      InlineDatum(payment_datum_data),
    )
  let owner_received = received_with_yield - exchange_fee_seller
  let owner_out_1 =
    gen_output(
      owner_address,
      owner_received,
      None,
      InlineDatum(payment_datum_data),
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
      InlineDatum(payment_datum_data),
    )
  let sc_out_1 =
    gen_output(
      sc_address,
      sc_in_lovelace - min_ada_to_exchange,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_ask_1,
          sc_in_bond_qty - buyer_qty,
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
  let sask_stake_key_hash = #"070201"
  let time_of_tx = 1681095094000
  let cfg = get_config_limit_mainnet()
  let owner_address =
    get_owner_address() |> with_delegation_key(sask_stake_key_hash)
  let sc_in_datum_1 = gen_ask_limit_datum(owner_address, 515)
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
  let buyer_qty = 5
  let received_at_maturity = escrow_full_info.value_at_maturity * buyer_qty
  let received_with_yield = price_of_one_bond * buyer_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.seller_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.platform.basis.base
  //
  let min_ada_to_exchange =
    when sc_in_bond_qty - buyer_qty is {
      0 -> sc_in_lovelace
      _ -> 0
    }
  let exchange_received =
    exchange_fee_buyer + exchange_fee_seller + min_ada_to_exchange

  // exchange_received == 206888 * 2
  let payment_datum = get_payment_datum()
  let payment_datum_data = builtin.serialise_data(payment_datum)
  let exchange_address = get_exchange_address()
  let exchange_out_1 =
    gen_output(
      exchange_address,
      exchange_received,
      None,
      InlineDatum(payment_datum_data),
    )
  let owner_received = received_with_yield - exchange_fee_seller
  let owner_out_1 =
    gen_output(
      owner_address,
      owner_received,
      None,
      InlineDatum(payment_datum_data),
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
      InlineDatum(payment_datum_data),
    )
  let sc_out_1 =
    gen_output(
      sc_address,
      sc_in_lovelace - min_ada_to_exchange,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_ask_1,
          sc_in_bond_qty - buyer_qty,
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

test fail_when_seller_output_stake_addr_is_owner_sk() fail {
  let owner_sk = #"070209"
  let time_of_tx = 1681095094000
  let cfg = get_config_limit_mainnet()
  let owner_address = get_owner_address() |> with_delegation_key(owner_sk)
  let sc_in_datum_1 = gen_ask_limit_datum(owner_address, 515)
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
  let buyer_qty = 5
  let received_at_maturity = escrow_full_info.value_at_maturity * buyer_qty
  let received_with_yield = price_of_one_bond * buyer_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.seller_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.platform.basis.base
  //
  let min_ada_to_exchange =
    when sc_in_bond_qty - buyer_qty is {
      0 -> sc_in_lovelace
      _ -> 0
    }
  let exchange_received =
    exchange_fee_buyer + exchange_fee_seller + min_ada_to_exchange

  // exchange_received == 206888 * 2
  let payment_datum = get_payment_datum()
  let payment_datum_data = builtin.serialise_data(payment_datum)
  let exchange_address = get_exchange_address()
  let exchange_out_1 =
    gen_output(
      exchange_address,
      exchange_received,
      None,
      InlineDatum(payment_datum_data),
    )
  let owner_received = received_with_yield - exchange_fee_seller
  let owner_out_1 =
    gen_output(
      owner_address,
      owner_received,
      None,
      InlineDatum(payment_datum_data),
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
      InlineDatum(payment_datum_data),
    )
  let sc_out_1 =
    gen_output(
      sc_address,
      sc_in_lovelace - min_ada_to_exchange,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_ask_1,
          sc_in_bond_qty - buyer_qty,
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

test fail_not_buy_any() {
  // let time_of_tx = 1666656000 000
  let time_of_tx = 1687343990000
  // => current_epoch = 22241
  let cfg = get_config_limit_preview()
  let owner_address = get_owner_address()
  let sc_in_datum_1 = gen_ask_limit_datum(owner_address, 7)
  let bond_name_ask_1 = get_bond_id_1()
  let bond_name_ask_2 = get_bond_id_2()
  // get_escrow_datum(asset_name: AssetName, bond_amount: Int, epo_rewards: Int, duration: Int, start: Int)
  let escrow_bond_amount = 20
  let escrow_epo_rewards = 1084931
  let escrow_duration = 54
  let escrow_datum =
    get_escrow_datum(
      bond_name_ask_1,
      escrow_bond_amount,
      escrow_epo_rewards,
      escrow_duration,
      21862,
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
  let sc_in_bond_qty = 2
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
    received_diff * cfg.exchange.seller_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.platform.basis.base
  //
  let min_ada_to_exchange =
    when sc_in_bond_qty - buyer_qty is {
      0 -> sc_in_lovelace
      _ -> 0
    }
  let exchange_received =
    exchange_fee_buyer + exchange_fee_seller + min_ada_to_exchange

  // exchange_received == 206888 * 2
  let payment_datum = get_payment_datum()
  let payment_datum_data = builtin.serialise_data(payment_datum)
  let exchange_address = get_exchange_address()
  let exchange_out_1 =
    gen_output(
      exchange_address,
      exchange_received,
      None,
      InlineDatum(payment_datum_data),
    )
  let owner_received = received_with_yield - exchange_fee_seller
  let owner_out_1 =
    gen_output(
      owner_address,
      owner_received,
      None,
      InlineDatum(payment_datum_data),
    )
  let buyer_received =
    buyer_fee_ada + sc_in_lovelace - exchange_received - owner_received
  let buyer_out_1 =
    gen_output(
      buyer_address,
      buyer_received,
      Some(value.from_asset(get_bond_policy_id(), bond_name_ask_2, 1)),
      InlineDatum(payment_datum_data),
    )
  let sc_out_1 =
    gen_output(
      sc_address,
      sc_in_lovelace - min_ada_to_exchange,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_ask_1,
          sc_in_bond_qty - buyer_qty,
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
  let cfg = get_config_limit_mainnet()
  let owner_address = get_owner_address()
  let sc_in_datum_1 = gen_ask_limit_datum(owner_address, 515)
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
    received_diff * cfg.exchange.seller_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.platform.basis.base
  //
  let min_ada_to_exchange =
    when sc_in_bond_qty - buyer_qty is {
      0 -> sc_in_lovelace
      _ -> 0
    }
  let exchange_received =
    exchange_fee_buyer + exchange_fee_seller + min_ada_to_exchange

  // exchange_received == 82755 * 2
  let payment_datum = get_payment_datum()
  let payment_datum_data = builtin.serialise_data(payment_datum)
  let exchange_address = get_exchange_address()
  let exchange_out_1 =
    gen_output(
      exchange_address,
      exchange_received,
      None,
      InlineDatum(payment_datum_data),
    )
  let owner_received = received_with_yield - exchange_fee_seller
  let owner_out_1 =
    gen_output(
      owner_address,
      owner_received,
      None,
      InlineDatum(payment_datum_data),
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
      InlineDatum(payment_datum_data),
    )
  let sc_out_1 =
    gen_output(
      sc_address,
      sc_in_lovelace - min_ada_to_exchange,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_ask_1,
          sc_in_bond_qty - buyer_qty,
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
  let cfg = get_config_limit_mainnet()
  let owner_address = get_owner_address()
  let sc_in_datum_1 = gen_ask_limit_datum(owner_address, 515)
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
  let buyer_qty = 5
  let received_at_maturity = escrow_full_info.value_at_maturity * buyer_qty
  let received_with_yield = price_of_one_bond * buyer_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.seller_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.platform.basis.base
  //
  let min_ada_to_exchange =
    when sc_in_bond_qty - buyer_qty is {
      0 -> sc_in_lovelace
      _ -> 0
    }
  let exchange_received =
    exchange_fee_buyer + exchange_fee_seller + min_ada_to_exchange

  // exchange_received == 206888 * 2
  let payment_datum = get_payment_datum()
  let payment_datum_data = builtin.serialise_data(payment_datum)
  let exchange_address = get_exchange_address()
  let exchange_out_1 =
    gen_output(
      exchange_address,
      exchange_received,
      None,
      InlineDatum(payment_datum_data),
    )
  let owner_received = received_with_yield - exchange_fee_seller
  let owner_out_1 =
    gen_output(
      owner_address,
      owner_received,
      None,
      InlineDatum(payment_datum_data),
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
      InlineDatum(payment_datum_data),
    )
  let sc_out_1 =
    gen_output(
      sc_address,
      sc_in_lovelace - min_ada_to_exchange,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_ask_1,
          sc_in_bond_qty - buyer_qty,
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
  let cfg = get_config_limit_preview()
  let owner_address = get_owner_address()
  let sc_in_datum_1 = gen_ask_limit_datum(owner_address, 7)
  let bond_name_ask_1 = get_bond_id_1()
  let bond_name_ask_2 = get_bond_id_2()
  // get_escrow_datum(asset_name: AssetName, bond_amount: Int, epo_rewards: Int, duration: Int, start: Int)
  let escrow_bond_amount = 20
  let escrow_epo_rewards = 1084931
  let escrow_duration = 54
  let escrow_datum =
    get_escrow_datum(
      bond_name_ask_1,
      escrow_bond_amount,
      escrow_epo_rewards,
      escrow_duration,
      21862,
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
    received_diff * cfg.exchange.seller_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.platform.basis.base
  //
  let min_ada_to_exchange =
    when sc_in_bond_qty - buyer_qty is {
      0 -> sc_in_lovelace
      _ -> 0
    }
  let exchange_received =
    exchange_fee_buyer + exchange_fee_seller + min_ada_to_exchange

  // exchange_received == 206888 * 2
  let payment_datum = get_payment_datum()
  let payment_datum_data = builtin.serialise_data(payment_datum)
  let exchange_address = get_exchange_address()
  let exchange_out_1 =
    gen_output(
      exchange_address,
      exchange_received,
      None,
      InlineDatum(payment_datum_data),
    )
  let owner_received = received_with_yield - exchange_fee_seller
  let owner_out_1 =
    gen_output(
      owner_address,
      owner_received,
      None,
      InlineDatum(payment_datum_data),
    )
  let buyer_received =
    buyer_fee_ada + sc_in_lovelace - exchange_received - owner_received
  let buyer_out_1 =
    gen_output(
      buyer_address,
      buyer_received,
      Some(value.from_asset(get_bond_policy_id(), bond_name_ask_2, 1)),
      InlineDatum(payment_datum_data),
    )
  let sc_out_1 =
    gen_output(
      sc_address,
      sc_in_lovelace - min_ada_to_exchange,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_ask_1,
          sc_in_bond_qty - buyer_qty,
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
  let cfg = get_config_limit_mainnet()
  let owner_address = get_owner_address()
  let sc_in_datum_1 = gen_ask_limit_datum(owner_address, 515)
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
    received_diff * cfg.exchange.seller_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.platform.basis.base
  //
  let min_ada_to_exchange =
    when sc_in_bond_qty - buyer_qty is {
      0 -> sc_in_lovelace
      _ -> 0
    }
  let exchange_received =
    exchange_fee_buyer + exchange_fee_seller + min_ada_to_exchange

  // exchange_received == 82755 * 2
  let payment_datum = get_payment_datum()
  let payment_datum_data = builtin.serialise_data(payment_datum)
  let exchange_address = get_exchange_address()
  let exchange_out_1 =
    gen_output(
      exchange_address,
      exchange_received,
      None,
      InlineDatum(payment_datum_data),
    )
  let owner_received = received_with_yield - exchange_fee_seller
  let owner_out_1 =
    gen_output(
      owner_address,
      owner_received,
      None,
      InlineDatum(payment_datum_data),
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
      InlineDatum(payment_datum_data),
    )
  let sc_out_1 =
    gen_output(
      sc_address,
      sc_in_lovelace - min_ada_to_exchange,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_ask_1,
          sc_in_bond_qty - buyer_qty,
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
  let cfg = get_config_limit_mainnet()
  let owner_address = get_owner_address()
  let sc_in_datum_1 = gen_ask_limit_datum(owner_address, 515)
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
  let buyer_qty = 5
  let received_at_maturity = escrow_full_info.value_at_maturity * buyer_qty
  let received_with_yield = price_of_one_bond * buyer_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.seller_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.platform.basis.base
  //
  let min_ada_to_exchange =
    when sc_in_bond_qty - buyer_qty is {
      0 -> sc_in_lovelace
      _ -> 0
    }
  let exchange_received =
    exchange_fee_buyer + exchange_fee_seller + min_ada_to_exchange

  // exchange_received == 206888 * 2
  let payment_datum = get_payment_datum()
  let payment_datum_data = builtin.serialise_data(payment_datum)
  let exchange_address = get_exchange_address()
  let exchange_out_1 =
    gen_output(
      exchange_address,
      exchange_received,
      None,
      InlineDatum(payment_datum_data),
    )
  let owner_received = received_with_yield - exchange_fee_seller
  let owner_out_1 =
    gen_output(
      owner_address,
      owner_received,
      None,
      InlineDatum(payment_datum_data),
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
      InlineDatum(payment_datum_data),
    )
  let sc_out_1 =
    gen_output(
      sc_address,
      sc_in_lovelace - min_ada_to_exchange,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_ask_1,
          sc_in_bond_qty - buyer_qty,
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
  let cfg = get_config_limit_preview()
  let owner_address = get_owner_address()
  let sc_in_datum_1 = gen_ask_limit_datum(owner_address, 7)
  let bond_name_ask_1 = get_bond_id_1()
  let bond_name_ask_2 = get_bond_id_2()
  // get_escrow_datum(asset_name: AssetName, bond_amount: Int, epo_rewards: Int, duration: Int, start: Int)
  let escrow_bond_amount = 20
  let escrow_epo_rewards = 1084931
  let escrow_duration = 54
  let escrow_datum =
    get_escrow_datum(
      bond_name_ask_1,
      escrow_bond_amount,
      escrow_epo_rewards,
      escrow_duration,
      21862,
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
    received_diff * cfg.exchange.seller_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.platform.basis.base
  //
  let min_ada_to_exchange =
    when sc_in_bond_qty - buyer_qty is {
      0 -> sc_in_lovelace
      _ -> 0
    }
  let exchange_received =
    exchange_fee_buyer + exchange_fee_seller + min_ada_to_exchange

  // exchange_received == 206888 * 2
  let payment_datum = get_payment_datum()
  let payment_datum_data = builtin.serialise_data(payment_datum)
  let exchange_address = get_exchange_address()
  let exchange_out_1 =
    gen_output(
      exchange_address,
      exchange_received,
      None,
      InlineDatum(payment_datum_data),
    )
  let owner_received = received_with_yield - exchange_fee_seller
  let owner_out_1 =
    gen_output(
      owner_address,
      owner_received,
      None,
      InlineDatum(payment_datum_data),
    )
  let buyer_received =
    buyer_fee_ada + sc_in_lovelace - exchange_received - owner_received
  let buyer_out_1 =
    gen_output(
      buyer_address,
      buyer_received,
      Some(value.from_asset(get_bond_policy_id(), bond_name_ask_2, 1)),
      InlineDatum(payment_datum_data),
    )
  let sc_out_1 =
    gen_output(
      sc_address,
      sc_in_lovelace - min_ada_to_exchange,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_ask_1,
          sc_in_bond_qty - buyer_qty,
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
  let cfg = get_config_limit_mainnet()
  let owner_address = get_owner_address()
  let sc_in_datum_1 = gen_ask_limit_datum(owner_address, 515)
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
    received_diff * cfg.exchange.seller_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.platform.basis.base
  //
  let min_ada_to_exchange =
    when sc_in_bond_qty - buyer_qty is {
      0 -> sc_in_lovelace
      _ -> 0
    }
  let exchange_received =
    exchange_fee_buyer + exchange_fee_seller + min_ada_to_exchange

  // exchange_received == 82755 * 2
  let payment_datum = get_payment_datum()
  let payment_datum_data = builtin.serialise_data(payment_datum)
  let exchange_address = get_exchange_address()
  let exchange_out_1 =
    gen_output(
      exchange_address,
      exchange_received,
      None,
      InlineDatum(payment_datum_data),
    )
  let owner_received = received_with_yield - exchange_fee_seller
  let owner_out_1 =
    gen_output(
      owner_address,
      owner_received,
      None,
      InlineDatum(payment_datum_data),
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
      InlineDatum(payment_datum_data),
    )
  let sc_out_1 =
    gen_output(
      sc_address,
      sc_in_lovelace - min_ada_to_exchange,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_ask_1,
          sc_in_bond_qty - buyer_qty,
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
  let cfg = get_config_limit_mainnet()
  let owner_address = get_owner_address()
  let sc_in_datum_1 = gen_ask_limit_datum(owner_address, 515)
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
  let buyer_qty = 5
  let received_at_maturity = escrow_full_info.value_at_maturity * buyer_qty
  let received_with_yield = price_of_one_bond * buyer_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.seller_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.platform.basis.base
  //
  let min_ada_to_exchange =
    when sc_in_bond_qty - buyer_qty is {
      0 -> sc_in_lovelace
      _ -> 0
    }
  let exchange_received =
    exchange_fee_buyer + exchange_fee_seller + min_ada_to_exchange

  // exchange_received == 206888 * 2
  let payment_datum = get_payment_datum()
  let payment_datum_data = builtin.serialise_data(payment_datum)
  let exchange_address = get_exchange_address()
  let exchange_out_1 =
    gen_output(
      exchange_address,
      exchange_received,
      None,
      InlineDatum(payment_datum_data),
    )
  let owner_received = received_with_yield - exchange_fee_seller
  let owner_out_1 =
    gen_output(
      owner_address,
      owner_received,
      None,
      InlineDatum(payment_datum_data),
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
      InlineDatum(payment_datum_data),
    )
  let sc_out_1 =
    gen_output(
      sc_address,
      sc_in_lovelace - min_ada_to_exchange,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_ask_1,
          sc_in_bond_qty - buyer_qty,
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
  let cfg = get_config_limit_preview()
  let owner_address = get_owner_address()
  let sc_in_datum_1 = gen_ask_limit_datum(owner_address, 7)
  let bond_name_ask_1 = get_bond_id_1()
  let bond_name_ask_2 = get_bond_id_2()
  // get_escrow_datum(asset_name: AssetName, bond_amount: Int, epo_rewards: Int, duration: Int, start: Int)
  let escrow_bond_amount = 20
  let escrow_epo_rewards = 1084931
  let escrow_duration = 54
  let escrow_datum =
    get_escrow_datum(
      bond_name_ask_1,
      escrow_bond_amount,
      escrow_epo_rewards,
      escrow_duration,
      21862,
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
    received_diff * cfg.exchange.seller_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.platform.basis.base
  //
  let min_ada_to_exchange =
    when sc_in_bond_qty - buyer_qty is {
      0 -> sc_in_lovelace
      _ -> 0
    }
  let exchange_received =
    exchange_fee_buyer + exchange_fee_seller + min_ada_to_exchange

  // exchange_received == 206888 * 2
  let payment_datum = get_payment_datum()
  let payment_datum_data = builtin.serialise_data(payment_datum)
  let exchange_address = get_exchange_address()
  let exchange_out_1 =
    gen_output(
      exchange_address,
      exchange_received,
      None,
      InlineDatum(payment_datum_data),
    )
  let owner_received = received_with_yield - exchange_fee_seller
  let owner_out_1 =
    gen_output(
      owner_address,
      owner_received,
      None,
      InlineDatum(payment_datum_data),
    )
  let buyer_received =
    buyer_fee_ada + sc_in_lovelace - exchange_received - owner_received
  let buyer_out_1 =
    gen_output(
      buyer_address,
      buyer_received,
      Some(value.from_asset(get_bond_policy_id(), bond_name_ask_2, 1)),
      InlineDatum(payment_datum_data),
    )
  let sc_out_1 =
    gen_output(
      sc_address,
      sc_in_lovelace - min_ada_to_exchange,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_ask_1,
          sc_in_bond_qty - buyer_qty,
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
  let cfg = get_config_limit_mainnet()
  let owner_address = get_owner_address()
  let sc_in_datum_1 = gen_ask_limit_datum(owner_address, 515)
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
  let buyer_qty = 5
  let received_at_maturity = escrow_full_info.value_at_maturity * buyer_qty
  let received_with_yield = price_of_one_bond * buyer_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.seller_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.platform.basis.base
  //
  let min_ada_to_exchange =
    when sc_in_bond_qty - buyer_qty is {
      0 -> sc_in_lovelace
      _ -> 0
    }
  let exchange_received =
    exchange_fee_buyer + exchange_fee_seller + min_ada_to_exchange

  // exchange_received == 206888 * 2
  let payment_datum = get_payment_datum()
  let payment_datum_data = builtin.serialise_data(payment_datum)
  let exchange_address = get_exchange_address()
  let exchange_out_1 =
    gen_output(
      exchange_address,
      exchange_received,
      None,
      InlineDatum(payment_datum_data),
    )
  let owner_received = received_with_yield - exchange_fee_seller
  let owner_out_1 =
    gen_output(
      owner_address,
      owner_received,
      None,
      InlineDatum(payment_datum_data),
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
      InlineDatum(payment_datum_data),
    )
  let sc_out_1 =
    gen_output(
      sc_address,
      sc_in_lovelace - min_ada_to_exchange,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_ask_1,
          sc_in_bond_qty - buyer_qty,
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
  // let time_of_tx = 1666656000 000
  let time_of_tx = 1687343990000
  // => current_epoch = 22241
  let cfg = get_config_limit_preview()
  let owner_address = get_owner_address()
  let sc_in_datum_1 = gen_ask_limit_datum(owner_address, 7)
  let bond_name_ask_1 = get_bond_id_1()
  let bond_name_ask_2 = get_bond_id_2()
  // get_escrow_datum(asset_name: AssetName, bond_amount: Int, epo_rewards: Int, duration: Int, start: Int)
  let escrow_bond_amount = 20
  let escrow_epo_rewards = 1084931
  let escrow_duration = 54
  let escrow_datum =
    get_escrow_datum(
      bond_name_ask_1,
      escrow_bond_amount,
      escrow_epo_rewards,
      escrow_duration,
      21862,
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
  let sc_in_bond_qty = 1
  let buyer_qty = 0
  let sc_in_lovelace = 1599010
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
    received_diff * cfg.exchange.seller_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.platform.basis.base
  //
  let min_ada_to_exchange =
    when sc_in_bond_qty - buyer_qty is {
      0 -> sc_in_lovelace
      _ -> 0
    }
  let exchange_received =
    exchange_fee_buyer + exchange_fee_seller + min_ada_to_exchange

  // exchange_received == 206888 * 2
  let payment_datum = get_payment_datum()
  let payment_datum_data = builtin.serialise_data(payment_datum)
  let exchange_address = get_exchange_address()
  let exchange_out_1 =
    gen_output(
      exchange_address,
      exchange_received,
      None,
      InlineDatum(payment_datum_data),
    )
  let owner_received = received_with_yield - exchange_fee_seller
  let owner_out_1 =
    gen_output(
      owner_address,
      owner_received,
      None,
      InlineDatum(payment_datum_data),
    )
  let buyer_received =
    buyer_fee_ada + sc_in_lovelace - exchange_received - owner_received
  let buyer_out_1 =
    gen_output(
      buyer_address,
      buyer_received,
      Some(value.from_asset(get_bond_policy_id(), bond_name_ask_2, 1)),
      InlineDatum(payment_datum_data),
    )
  let sc_out_1 =
    gen_output(
      sc_address,
      sc_in_lovelace - min_ada_to_exchange,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_ask_1,
          sc_in_bond_qty - buyer_qty,
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

test fail_when_spend_deprecated_ask() fail {
  let time_of_tx = 1681095094000
  let cfg = get_config_limit_mainnet()
  let owner_address = get_owner_address()
  let sc_in_datum_1 = gen_ask_limit_datum(owner_address, 515)
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
  let buyer_qty = 5
  let received_at_maturity = escrow_full_info.value_at_maturity * buyer_qty
  let received_with_yield = price_of_one_bond * buyer_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.seller_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.platform.basis.base
  //
  let min_ada_to_exchange =
    when sc_in_bond_qty - buyer_qty is {
      0 -> sc_in_lovelace
      _ -> 0
    }
  let exchange_received =
    exchange_fee_buyer + exchange_fee_seller + min_ada_to_exchange

  // exchange_received == 206888 * 2
  let payment_datum = get_payment_datum()
  let payment_datum_data = builtin.serialise_data(payment_datum)
  let exchange_address = get_exchange_address()
  let exchange_out_1 =
    gen_output(
      exchange_address,
      exchange_received,
      None,
      InlineDatum(payment_datum_data),
    )
  let owner_received = received_with_yield - exchange_fee_seller
  let owner_out_1 =
    gen_output(
      owner_address,
      owner_received,
      None,
      InlineDatum(payment_datum_data),
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
      InlineDatum(payment_datum_data),
    )
  let sc_out_1 =
    gen_output(
      sc_address,
      sc_in_lovelace - min_ada_to_exchange,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_ask_1,
          sc_in_bond_qty - buyer_qty,
        ),
      ),
      InlineDatum(sc_in_datum_1),
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
  buy.spending(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    sc_in_datum_1,
    [deprecated_ask_skh],
  )
}

test fail_when_attempting_unbound_value_attack_by_other_token() fail {
  let time_of_tx = 1681095094000
  let cfg = get_config_limit_mainnet()
  let owner_address = get_owner_address()
  let sc_in_datum_1 = gen_ask_limit_datum(owner_address, 515)
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
    received_diff * cfg.exchange.seller_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.platform.basis.base
  //
  let min_ada_to_exchange =
    when sc_in_bond_qty - buyer_qty is {
      0 -> sc_in_lovelace
      _ -> 0
    }
  let exchange_received =
    exchange_fee_buyer + exchange_fee_seller + min_ada_to_exchange

  // exchange_received == 82755 * 2
  let payment_datum = get_payment_datum()
  let payment_datum_data = builtin.serialise_data(payment_datum)
  let exchange_address = get_exchange_address()
  let exchange_out_1 =
    gen_output(
      exchange_address,
      exchange_received,
      None,
      InlineDatum(payment_datum_data),
    )
  let owner_received = received_with_yield - exchange_fee_seller
  let owner_out_1 =
    gen_output(
      owner_address,
      owner_received,
      None,
      InlineDatum(payment_datum_data),
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
      InlineDatum(payment_datum_data),
    )
  let sc_out_1 =
    gen_output(
      sc_address,
      sc_in_lovelace - min_ada_to_exchange,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_ask_1,
          sc_in_bond_qty - buyer_qty,
        )
          |> value.add(get_bond_policy_id(), "other_token", 1),
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

test fail_when_attempting_unbound_value_attack_by_other_policy() fail {
  let time_of_tx = 1681095094000
  let cfg = get_config_limit_mainnet()
  let owner_address = get_owner_address()
  let sc_in_datum_1 = gen_ask_limit_datum(owner_address, 515)
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
    received_diff * cfg.exchange.seller_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.platform.basis.base
  //
  let min_ada_to_exchange =
    when sc_in_bond_qty - buyer_qty is {
      0 -> sc_in_lovelace
      _ -> 0
    }
  let exchange_received =
    exchange_fee_buyer + exchange_fee_seller + min_ada_to_exchange

  // exchange_received == 82755 * 2
  let payment_datum = get_payment_datum()
  let payment_datum_data = builtin.serialise_data(payment_datum)
  let exchange_address = get_exchange_address()
  let exchange_out_1 =
    gen_output(
      exchange_address,
      exchange_received,
      None,
      InlineDatum(payment_datum_data),
    )
  let owner_received = received_with_yield - exchange_fee_seller
  let owner_out_1 =
    gen_output(
      owner_address,
      owner_received,
      None,
      InlineDatum(payment_datum_data),
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
      InlineDatum(payment_datum_data),
    )
  let sc_out_1 =
    gen_output(
      sc_address,
      sc_in_lovelace - min_ada_to_exchange,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_ask_1,
          sc_in_bond_qty - buyer_qty,
        )
          |> value.add("other_policy_id", "other_token", 1),
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

test fail_unsafe_fee_datum() fail {
  let time_of_tx = 1681095094000
  let cfg = get_config_limit_mainnet()
  let exchange_address = get_exchange_address()
  let owner_address = get_owner_address()
  let sc_in_datum_1 = gen_ask_limit_datum(owner_address, 515)
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
    received_diff * cfg.exchange.seller_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.platform.basis.base
  //
  let min_ada_to_exchange =
    when sc_in_bond_qty - buyer_qty is {
      0 -> sc_in_lovelace
      _ -> 0
    }
  let exchange_received =
    exchange_fee_buyer + exchange_fee_seller + min_ada_to_exchange

  // exchange_received == 82755 * 2
  let payment_datum = get_payment_datum()
  let payment_datum_data = builtin.serialise_data(payment_datum)
  let exchange_out_1 =
    gen_output(
      exchange_address,
      exchange_received,
      None,
      DatumHash("arbitrary_digest"),
    )
  let owner_received = received_with_yield - exchange_fee_seller
  let owner_out_1 =
    gen_output(
      owner_address,
      owner_received,
      None,
      InlineDatum(payment_datum_data),
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
      InlineDatum(payment_datum_data),
    )
  let sc_out_1 =
    gen_output(
      sc_address,
      sc_in_lovelace - min_ada_to_exchange,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_ask_1,
          sc_in_bond_qty - buyer_qty,
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

test fail_unsafe_payout_datum() fail {
  let time_of_tx = 1681095094000
  let cfg = get_config_limit_mainnet()
  let exchange_address = get_exchange_address()
  let owner_address = get_owner_address()
  let sc_in_datum_1 = gen_ask_limit_datum(owner_address, 515)
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
    received_diff * cfg.exchange.seller_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.platform.basis.base
  //
  let min_ada_to_exchange =
    when sc_in_bond_qty - buyer_qty is {
      0 -> sc_in_lovelace
      _ -> 0
    }
  let exchange_received =
    exchange_fee_buyer + exchange_fee_seller + min_ada_to_exchange

  // exchange_received == 82755 * 2
  let payment_datum = get_payment_datum()
  let payment_datum_data = builtin.serialise_data(payment_datum)
  let exchange_out_1 =
    gen_output(
      exchange_address,
      exchange_received,
      None,
      NoDatum,
    )
  let owner_received = received_with_yield - exchange_fee_seller
  let owner_out_1 =
    gen_output(
      owner_address,
      owner_received,
      None,
      DatumHash("arbitrary_digest"),
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
      InlineDatum(payment_datum_data),
    )
  let sc_out_1 =
    gen_output(
      sc_address,
      sc_in_lovelace - min_ada_to_exchange,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_ask_1,
          sc_in_bond_qty - buyer_qty,
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