// Bid Making
use aiken/transaction.{
  DatumHash, InlineDatum, NoDatum, Output, ScriptContext, Spend,
}
use aiken/transaction/credential.{
  Address, from_script, with_delegation_key, with_delegation_script,
}
use aiken/transaction/value.{AssetName, PolicyId}
use bond/common/fixture.{
  calc_escrow_full_info, gen_ask_making_datum, gen_bid_making_datum, gen_input,
  gen_output, gen_tampered_ask_making_datum, gen_tampered_bid_making_datum,
  get_bid_sc_address, get_bond_id_1, get_bond_policy_id, get_buyer_address,
  get_buyer_address_hash, get_config_making_mainnet, get_escrow_address,
  get_escrow_address_unexpect, get_escrow_datum, get_escrow_policy_id,
  get_exchange_address, get_fraud_address, get_input_escrow,
  get_not_bond_policy_id, get_not_escrow_policy_id, get_seller_address,
}
use bond/common/utils as bond_utils
use bond/making_bid/sell

fn get_owner_address() -> Address {
  let seller_addr = get_buyer_address()
  let sbid_addr = get_bid_sc_address()
  Address {
    payment_credential: seller_addr.payment_credential,
    stake_credential: sbid_addr.stake_credential,
  }
}

fn add_asset(self: Output, pid: PolicyId, tkn: AssetName, qty: Int) {
  Output { ..self, value: self.value |> value.add(pid, tkn, qty) }
}

test succ_full() {
  let time_of_tx = 1681095094000
  let cfg = get_config_making_mainnet()
  let owner_address = get_owner_address()
  let seller_address = get_seller_address()
  let owner_in_datum_1 = gen_ask_making_datum(owner_address, 499)
  let sc_in_datum_1 = gen_bid_making_datum(owner_address, 390, 480, 5, 500)
  // sc address that will be used to continue to make ask order
  let revert_address = from_script(sc_in_datum_1.ask_sc)
  let bond_name_1 = get_bond_id_1()
  let escrow_bond_amount = 10000
  let escrow_epo_rewards = 753424657
  let escrow_duration = 72
  let escrow_datum =
    get_escrow_datum(
      bond_name_1,
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
    bond_utils.get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  //  
  let bond_sell_qty = 5
  let received_at_maturity = escrow_full_info.value_at_maturity * bond_sell_qty
  let received_with_yield = price_of_one_bond * bond_sell_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.taker_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.maker_fee / cfg.platform.basis.base
  //
  let owner_out_lovelace = 1310316
  let sc_address = get_bid_sc_address()
  let sc_in_lovelace =
    received_with_yield + exchange_fee_buyer + owner_out_lovelace
  let sc_in_1 =
    gen_input(sc_address, sc_in_lovelace, None, InlineDatum(sc_in_datum_1))
  let seller_in_lovelace = 1310316
  let asset_sell =
    value.from_asset(get_bond_policy_id(), bond_name_1, bond_sell_qty)
  let seller_in_1 =
    gen_input(seller_address, seller_in_lovelace, Some(asset_sell), NoDatum)
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_1,
      1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  //
  let exchange_address = get_exchange_address()
  let exchange_out_lovelace = exchange_fee_buyer + exchange_fee_seller
  let exchange_out_1 =
    gen_output(exchange_address, exchange_out_lovelace, None, NoDatum)
  let seller_out_lovelace =
    seller_in_lovelace + received_with_yield - exchange_fee_seller
  let seller_out_1 =
    gen_output(seller_address, seller_out_lovelace, None, NoDatum)
  let owner_out_1 =
    gen_output(
      revert_address,
      owner_out_lovelace,
      Some(asset_sell),
      InlineDatum(owner_in_datum_1),
    )
  let tx =
    fixture.tx(
      [sc_in_1, seller_in_1],
      [refer_in_1],
      [exchange_out_1, seller_out_1, owner_out_1],
      // [exchange_out_1, seller_out_1, owner_out_1, sc_out_utxo],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  sell.spending(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    sc_in_datum_1,
    [],
  )
}

test succ_partial() {
  let time_of_tx = 1681095094000
  let cfg = get_config_making_mainnet()
  let owner_address = get_owner_address()
  let seller_address = get_seller_address()
  let owner_in_datum_1 = gen_ask_making_datum(owner_address, 499)
  let sc_in_datum_1 = gen_bid_making_datum(owner_address, 390, 480, 5, 500)
  let revert_address = from_script(sc_in_datum_1.ask_sc)
  let bond_name_1 = get_bond_id_1()
  let escrow_bond_amount = 10000
  let escrow_epo_rewards = 753424657
  let escrow_duration = 72
  let escrow_datum =
    get_escrow_datum(
      bond_name_1,
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
    bond_utils.get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  let bond_sell_qty = 2
  let received_at_maturity = escrow_full_info.value_at_maturity * bond_sell_qty
  let received_with_yield = price_of_one_bond * bond_sell_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.taker_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.maker_fee / cfg.platform.basis.base
  let owner_out_lovelace = 1310316
  let sc_address = get_bid_sc_address()
  let sc_in_lovelace =
    received_with_yield + exchange_fee_buyer + owner_out_lovelace
  let sc_in_1 =
    gen_input(sc_address, sc_in_lovelace, None, InlineDatum(sc_in_datum_1))
  let seller_in_lovelace = 1310316
  let asset_sell =
    value.from_asset(get_bond_policy_id(), bond_name_1, bond_sell_qty)
  let seller_in_1 =
    gen_input(seller_address, seller_in_lovelace, Some(asset_sell), NoDatum)
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_1,
      1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  let exchange_address = get_exchange_address()
  let exchange_out_lovelace = exchange_fee_buyer + exchange_fee_seller
  let exchange_out_1 =
    gen_output(exchange_address, exchange_out_lovelace, None, NoDatum)
  let seller_out_lovelace =
    seller_in_lovelace + received_with_yield - exchange_fee_seller
  let seller_out_1 =
    gen_output(seller_address, seller_out_lovelace, None, NoDatum)
  let owner_out_1 =
    gen_output(
      revert_address,
      owner_out_lovelace,
      Some(asset_sell),
      InlineDatum(owner_in_datum_1),
    )
  let sc_out_lovelace =
    sc_in_lovelace - received_with_yield - exchange_fee_buyer - owner_out_lovelace
  let sc_out_datum_1 =
    gen_bid_making_datum(
      owner_address,
      390,
      480,
      sc_in_datum_1.quantity - bond_sell_qty,
      500,
    )
  let sc_out_utxo =
    gen_output(sc_address, sc_out_lovelace, None, InlineDatum(sc_out_datum_1))
  let tx =
    fixture.tx(
      [sc_in_1, seller_in_1],
      [refer_in_1],
      [exchange_out_1, seller_out_1, owner_out_1, sc_out_utxo],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  sell.spending(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    sc_in_datum_1,
    [],
  )
}

test fail_partial_when_wrong_stake_key_output() fail {
  let time_of_tx = 1681095094000
  let cfg = get_config_making_mainnet()
  let owner_address = get_owner_address()
  let seller_address = get_seller_address()
  let owner_in_datum_1 = gen_ask_making_datum(owner_address, 499)
  let sc_in_datum_1 = gen_bid_making_datum(owner_address, 390, 480, 5, 500)
  let revert_address = from_script(sc_in_datum_1.ask_sc)
  let bond_name_1 = get_bond_id_1()
  let escrow_bond_amount = 10000
  let escrow_epo_rewards = 753424657
  let escrow_duration = 72
  let escrow_datum =
    get_escrow_datum(
      bond_name_1,
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
    bond_utils.get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  let bond_sell_qty = 2
  let received_at_maturity = escrow_full_info.value_at_maturity * bond_sell_qty
  let received_with_yield = price_of_one_bond * bond_sell_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.taker_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.maker_fee / cfg.platform.basis.base
  let owner_out_lovelace = 1310316
  let sc_address = get_bid_sc_address()
  let sc_in_lovelace =
    received_with_yield + exchange_fee_buyer + owner_out_lovelace
  let sc_in_1 =
    gen_input(
      sc_address |> with_delegation_key("stake key"),
      sc_in_lovelace,
      None,
      InlineDatum(sc_in_datum_1),
    )
  let seller_in_lovelace = 1310316
  let asset_sell =
    value.from_asset(get_bond_policy_id(), bond_name_1, bond_sell_qty)
  let seller_in_1 =
    gen_input(seller_address, seller_in_lovelace, Some(asset_sell), NoDatum)
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_1,
      1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  let exchange_address = get_exchange_address()
  let exchange_out_lovelace = exchange_fee_buyer + exchange_fee_seller
  let exchange_out_1 =
    gen_output(exchange_address, exchange_out_lovelace, None, NoDatum)
  let seller_out_lovelace =
    seller_in_lovelace + received_with_yield - exchange_fee_seller
  let seller_out_1 =
    gen_output(seller_address, seller_out_lovelace, None, NoDatum)
  let owner_out_1 =
    gen_output(
      revert_address,
      owner_out_lovelace,
      Some(asset_sell),
      InlineDatum(owner_in_datum_1),
    )
  let sc_out_lovelace =
    sc_in_lovelace - received_with_yield - exchange_fee_buyer - owner_out_lovelace
  let sc_out_datum_1 =
    gen_bid_making_datum(
      owner_address,
      390,
      480,
      sc_in_datum_1.quantity - bond_sell_qty,
      500,
    )
  let sc_out_utxo =
    gen_output(
      sc_address |> with_delegation_key("fake stake key"),
      sc_out_lovelace,
      None,
      InlineDatum(sc_out_datum_1),
    )
  let tx =
    fixture.tx(
      [sc_in_1, seller_in_1],
      [refer_in_1],
      [exchange_out_1, seller_out_1, owner_out_1, sc_out_utxo],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  !sell.spending(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    sc_in_datum_1,
    [],
  )
}

test fail_input_epoch_1() {
  let time_of_tx = 1681095094000
  let cfg = get_config_making_mainnet()
  let owner_address = get_owner_address()
  let seller_address = get_seller_address()
  let sc_in_datum_1 = gen_bid_making_datum(owner_address, 480, 390, 5, 500)
  let revert_address = from_script(sc_in_datum_1.ask_sc)
  let bond_name_1 = get_bond_id_1()
  let escrow_bond_amount = 10000
  let escrow_epo_rewards = 753424657
  let escrow_duration = 72
  let escrow_datum =
    get_escrow_datum(
      bond_name_1,
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
    bond_utils.get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  let bond_sell_qty = 5
  let received_at_maturity = escrow_full_info.value_at_maturity * bond_sell_qty
  let received_with_yield = price_of_one_bond * bond_sell_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.taker_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.maker_fee / cfg.platform.basis.base
  let owner_out_lovelace = 1310316
  let sc_address = get_bid_sc_address()
  let sc_in_lovelace =
    received_with_yield + exchange_fee_buyer + owner_out_lovelace
  let sc_in_1 =
    gen_input(sc_address, sc_in_lovelace, None, InlineDatum(sc_in_datum_1))
  let seller_in_lovelace = 1310316
  let asset_sell =
    value.from_asset(get_bond_policy_id(), bond_name_1, bond_sell_qty)
  let seller_in_1 =
    gen_input(seller_address, seller_in_lovelace, Some(asset_sell), NoDatum)
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_1,
      1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  let exchange_address = get_exchange_address()
  let exchange_out_lovelace = exchange_fee_buyer + exchange_fee_seller
  let exchange_out_1 =
    gen_output(exchange_address, exchange_out_lovelace, None, NoDatum)
  let seller_out_lovelace =
    seller_in_lovelace + received_with_yield - exchange_fee_seller
  let seller_out_1 =
    gen_output(seller_address, seller_out_lovelace, None, NoDatum)
  let owner_out_1 =
    gen_output(revert_address, owner_out_lovelace, Some(asset_sell), NoDatum)
  let sc_out_lovelace =
    sc_in_lovelace - received_with_yield - exchange_fee_buyer - owner_out_lovelace
  let sc_out_datum_1 =
    gen_bid_making_datum(
      owner_address,
      390,
      480,
      sc_in_datum_1.quantity - bond_sell_qty,
      500,
    )
  let sc_out_utxo =
    gen_output(sc_address, sc_out_lovelace, None, InlineDatum(sc_out_datum_1))
  let tx =
    fixture.tx(
      [sc_in_1, seller_in_1],
      [refer_in_1],
      [exchange_out_1, seller_out_1, owner_out_1, sc_out_utxo],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  !sell.spending(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    sc_in_datum_1,
    [],
  )
}

test fail_input_epoch_2() fail {
  let time_of_tx = 1681095094000
  let cfg = get_config_making_mainnet()
  let owner_address = get_owner_address()
  let seller_address = get_seller_address()
  let sc_in_datum_1 = gen_bid_making_datum(owner_address, 464, 480, 5, 500)
  let revert_address = from_script(sc_in_datum_1.ask_sc)
  let bond_name_1 = get_bond_id_1()
  let escrow_bond_amount = 10000
  let escrow_epo_rewards = 753424657
  let escrow_duration = 72
  let escrow_datum =
    get_escrow_datum(
      bond_name_1,
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
    bond_utils.get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  let bond_sell_qty = 5
  let received_at_maturity = escrow_full_info.value_at_maturity * bond_sell_qty
  let received_with_yield = price_of_one_bond * bond_sell_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.taker_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.maker_fee / cfg.platform.basis.base
  let owner_out_lovelace = 1310316
  let sc_address = get_bid_sc_address()
  let sc_in_lovelace =
    received_with_yield + exchange_fee_buyer + owner_out_lovelace
  let sc_in_1 =
    gen_input(sc_address, sc_in_lovelace, None, InlineDatum(sc_in_datum_1))
  let seller_in_lovelace = 1310316
  let asset_sell =
    value.from_asset(get_bond_policy_id(), bond_name_1, bond_sell_qty)
  let seller_in_1 =
    gen_input(seller_address, seller_in_lovelace, Some(asset_sell), NoDatum)
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_1,
      1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  let exchange_address = get_exchange_address()
  let exchange_out_lovelace = exchange_fee_buyer + exchange_fee_seller
  let exchange_out_1 =
    gen_output(exchange_address, exchange_out_lovelace, None, NoDatum)
  let seller_out_lovelace =
    seller_in_lovelace + received_with_yield - exchange_fee_seller
  let seller_out_1 =
    gen_output(seller_address, seller_out_lovelace, None, NoDatum)
  let owner_out_1 =
    gen_output(revert_address, owner_out_lovelace, Some(asset_sell), NoDatum)
  let sc_out_lovelace =
    sc_in_lovelace - received_with_yield - exchange_fee_buyer - owner_out_lovelace
  let sc_out_datum_1 =
    gen_bid_making_datum(
      owner_address,
      390,
      480,
      sc_in_datum_1.quantity - bond_sell_qty,
      500,
    )
  let sc_out_utxo =
    gen_output(sc_address, sc_out_lovelace, None, InlineDatum(sc_out_datum_1))
  let tx =
    fixture.tx(
      [sc_in_1, seller_in_1],
      [refer_in_1],
      [exchange_out_1, seller_out_1, owner_out_1, sc_out_utxo],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  !sell.spending(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    sc_in_datum_1,
    [],
  )
}

test fail_input_epoch_3() fail {
  let time_of_tx = 1681095094000
  let cfg = get_config_making_mainnet()
  let owner_address = get_owner_address()
  let seller_address = get_seller_address()
  let sc_in_datum_1 = gen_bid_making_datum(owner_address, 390, 462, 5, 500)
  let revert_address = from_script(sc_in_datum_1.ask_sc)
  let bond_name_1 = get_bond_id_1()
  let escrow_bond_amount = 10000
  let escrow_epo_rewards = 753424657
  let escrow_duration = 72
  let escrow_datum =
    get_escrow_datum(
      bond_name_1,
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
    bond_utils.get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  let bond_sell_qty = 5
  let received_at_maturity = escrow_full_info.value_at_maturity * bond_sell_qty
  let received_with_yield = price_of_one_bond * bond_sell_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.taker_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.maker_fee / cfg.platform.basis.base
  //
  let owner_out_lovelace = 1310316
  let sc_address = get_bid_sc_address()
  let sc_in_lovelace =
    received_with_yield + exchange_fee_buyer + owner_out_lovelace
  let sc_in_1 =
    gen_input(sc_address, sc_in_lovelace, None, InlineDatum(sc_in_datum_1))
  let seller_in_lovelace = 1310316
  let asset_sell =
    value.from_asset(get_bond_policy_id(), bond_name_1, bond_sell_qty)
  let seller_in_1 =
    gen_input(seller_address, seller_in_lovelace, Some(asset_sell), NoDatum)
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_1,
      1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  let exchange_address = get_exchange_address()
  let exchange_out_lovelace = exchange_fee_buyer + exchange_fee_seller
  let exchange_out_1 =
    gen_output(exchange_address, exchange_out_lovelace, None, NoDatum)
  let seller_out_lovelace =
    seller_in_lovelace + received_with_yield - exchange_fee_seller
  let seller_out_1 =
    gen_output(seller_address, seller_out_lovelace, None, NoDatum)
  let owner_out_1 =
    gen_output(revert_address, owner_out_lovelace, Some(asset_sell), NoDatum)
  let sc_out_lovelace =
    sc_in_lovelace - received_with_yield - exchange_fee_buyer - owner_out_lovelace
  let sc_out_datum_1 =
    gen_bid_making_datum(
      owner_address,
      390,
      480,
      sc_in_datum_1.quantity - bond_sell_qty,
      500,
    )
  let sc_out_utxo =
    gen_output(sc_address, sc_out_lovelace, None, InlineDatum(sc_out_datum_1))
  let tx =
    fixture.tx(
      [sc_in_1, seller_in_1],
      [refer_in_1],
      [exchange_out_1, seller_out_1, owner_out_1, sc_out_utxo],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  !sell.spending(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    sc_in_datum_1,
    [],
  )
}

test fail_input_epoch_4() fail {
  let time_of_tx = 1681095094000 + 25920000000
  let cfg = get_config_making_mainnet()
  let owner_address = get_owner_address()
  let seller_address = get_seller_address()
  let sc_in_datum_1 = gen_bid_making_datum(owner_address, 390, 462, 5, 500)
  let revert_address = from_script(sc_in_datum_1.ask_sc)
  let bond_name_1 = get_bond_id_1()
  let escrow_bond_amount = 10000
  let escrow_epo_rewards = 753424657
  let escrow_duration = 72
  let escrow_datum =
    get_escrow_datum(
      bond_name_1,
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
    bond_utils.get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  let bond_sell_qty = 5
  let received_at_maturity = escrow_full_info.value_at_maturity * bond_sell_qty
  let received_with_yield = price_of_one_bond * bond_sell_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.taker_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.maker_fee / cfg.platform.basis.base
  let owner_out_lovelace = 1310316
  let sc_address = get_bid_sc_address()
  let sc_in_lovelace =
    received_with_yield + exchange_fee_buyer + owner_out_lovelace
  let sc_in_1 =
    gen_input(sc_address, sc_in_lovelace, None, InlineDatum(sc_in_datum_1))
  let seller_in_lovelace = 1310316
  let asset_sell =
    value.from_asset(get_bond_policy_id(), bond_name_1, bond_sell_qty)
  let seller_in_1 =
    gen_input(seller_address, seller_in_lovelace, Some(asset_sell), NoDatum)
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_1,
      1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  let exchange_address = get_exchange_address()
  let exchange_out_lovelace = exchange_fee_buyer + exchange_fee_seller
  let exchange_out_1 =
    gen_output(exchange_address, exchange_out_lovelace, None, NoDatum)
  let seller_out_lovelace =
    seller_in_lovelace + received_with_yield - exchange_fee_seller
  let seller_out_1 =
    gen_output(seller_address, seller_out_lovelace, None, NoDatum)
  let owner_out_1 =
    gen_output(revert_address, owner_out_lovelace, Some(asset_sell), NoDatum)
  let sc_out_lovelace =
    sc_in_lovelace - received_with_yield - exchange_fee_buyer - owner_out_lovelace
  let sc_out_datum_1 =
    gen_bid_making_datum(
      owner_address,
      390,
      480,
      sc_in_datum_1.quantity - bond_sell_qty,
      500,
    )
  let sc_out_utxo =
    gen_output(sc_address, sc_out_lovelace, None, InlineDatum(sc_out_datum_1))
  let tx =
    fixture.tx(
      [sc_in_1, seller_in_1],
      [refer_in_1],
      [exchange_out_1, seller_out_1, owner_out_1, sc_out_utxo],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  !sell.spending(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    sc_in_datum_1,
    [],
  )
}

test fail_input_qty() {
  let time_of_tx = 1681095094000
  let cfg = get_config_making_mainnet()
  let owner_address = get_owner_address()
  let seller_address = get_seller_address()
  let sc_in_datum_1 = gen_bid_making_datum(owner_address, 390, 480, 0, 500)
  let revert_address = from_script(sc_in_datum_1.ask_sc)
  let bond_name_1 = get_bond_id_1()
  let escrow_bond_amount = 10000
  let escrow_epo_rewards = 753424657
  let escrow_duration = 72
  let escrow_datum =
    get_escrow_datum(
      bond_name_1,
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
    bond_utils.get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  let bond_sell_qty = 5
  let received_at_maturity = escrow_full_info.value_at_maturity * bond_sell_qty
  let received_with_yield = price_of_one_bond * bond_sell_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.taker_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.maker_fee / cfg.platform.basis.base
  let owner_out_lovelace = 1310316
  let sc_address = get_bid_sc_address()
  let sc_in_lovelace =
    received_with_yield + exchange_fee_buyer + owner_out_lovelace
  let sc_in_1 =
    gen_input(sc_address, sc_in_lovelace, None, InlineDatum(sc_in_datum_1))
  let seller_in_lovelace = 1310316
  let asset_sell =
    value.from_asset(get_bond_policy_id(), bond_name_1, bond_sell_qty)
  let seller_in_1 =
    gen_input(seller_address, seller_in_lovelace, Some(asset_sell), NoDatum)
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_1,
      1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  let exchange_address = get_exchange_address()
  let exchange_out_lovelace = exchange_fee_buyer + exchange_fee_seller
  let exchange_out_1 =
    gen_output(exchange_address, exchange_out_lovelace, None, NoDatum)
  let seller_out_lovelace =
    seller_in_lovelace + received_with_yield - exchange_fee_seller
  let seller_out_1 =
    gen_output(seller_address, seller_out_lovelace, None, NoDatum)
  let owner_out_1 =
    gen_output(revert_address, owner_out_lovelace, Some(asset_sell), NoDatum)
  let sc_out_lovelace =
    sc_in_lovelace - received_with_yield - exchange_fee_buyer - owner_out_lovelace
  let sc_out_datum_1 =
    gen_bid_making_datum(
      owner_address,
      390,
      480,
      sc_in_datum_1.quantity - bond_sell_qty,
      500,
    )
  let sc_out_utxo =
    gen_output(sc_address, sc_out_lovelace, None, InlineDatum(sc_out_datum_1))
  let tx =
    fixture.tx(
      [sc_in_1, seller_in_1],
      [refer_in_1],
      [exchange_out_1, seller_out_1, owner_out_1, sc_out_utxo],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  !sell.spending(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    sc_in_datum_1,
    [],
  )
}

test fail_output_qty() fail {
  let time_of_tx = 1681095094000
  let cfg = get_config_making_mainnet()
  let owner_address = get_owner_address()
  let seller_address = get_seller_address()
  let sc_in_datum_1 = gen_bid_making_datum(owner_address, 390, 480, 1, 500)
  let owner_in_datum_1 = gen_ask_making_datum(owner_address, 499)
  let revert_address = from_script(sc_in_datum_1.ask_sc)
  let bond_name_1 = get_bond_id_1()
  let escrow_bond_amount = 10000
  let escrow_epo_rewards = 753424657
  let escrow_duration = 72
  let escrow_datum =
    get_escrow_datum(
      bond_name_1,
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
    bond_utils.get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  let bond_sell_qty = 5
  let received_at_maturity = escrow_full_info.value_at_maturity * bond_sell_qty
  let received_with_yield = price_of_one_bond * bond_sell_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.taker_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.maker_fee / cfg.platform.basis.base
  let owner_out_lovelace = 1310316
  let sc_address = get_bid_sc_address()
  let sc_in_lovelace =
    received_with_yield + exchange_fee_buyer + owner_out_lovelace
  let sc_in_1 =
    gen_input(sc_address, sc_in_lovelace, None, InlineDatum(sc_in_datum_1))
  let seller_in_lovelace = 1310316
  let asset_sell =
    value.from_asset(get_bond_policy_id(), bond_name_1, bond_sell_qty)
  let seller_in_1 =
    gen_input(seller_address, seller_in_lovelace, Some(asset_sell), NoDatum)
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_1,
      1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  let exchange_address = get_exchange_address()
  let exchange_out_lovelace = exchange_fee_buyer + exchange_fee_seller
  let exchange_out_1 =
    gen_output(exchange_address, exchange_out_lovelace, None, NoDatum)
  let seller_out_lovelace =
    seller_in_lovelace + received_with_yield - exchange_fee_seller
  let seller_out_1 =
    gen_output(seller_address, seller_out_lovelace, None, NoDatum)
  let owner_out_1 =
    gen_output(
      revert_address,
      owner_out_lovelace,
      Some(asset_sell),
      InlineDatum(owner_in_datum_1),
    )
  let sc_out_lovelace =
    sc_in_lovelace - received_with_yield - exchange_fee_buyer - owner_out_lovelace
  let sc_out_datum_1 =
    gen_bid_making_datum(
      owner_address,
      390,
      480,
      sc_in_datum_1.quantity - bond_sell_qty,
      500,
    )
  let sc_out_utxo =
    gen_output(sc_address, sc_out_lovelace, None, InlineDatum(sc_out_datum_1))
  let tx =
    fixture.tx(
      [sc_in_1, seller_in_1],
      [refer_in_1],
      [exchange_out_1, seller_out_1, owner_out_1, sc_out_utxo],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  !sell.spending(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    sc_in_datum_1,
    [],
  )
}

test fail_validity_after_not_set() fail {
  let time_of_tx = 1681095094000
  let cfg = get_config_making_mainnet()
  let owner_address = get_owner_address()
  let seller_address = get_seller_address()
  let sc_in_datum_1 = gen_bid_making_datum(owner_address, 390, 480, 5, 500)
  let revert_address = from_script(sc_in_datum_1.ask_sc)
  let bond_name_1 = get_bond_id_1()
  let escrow_bond_amount = 10000
  let escrow_epo_rewards = 753424657
  let escrow_duration = 72
  let escrow_datum =
    get_escrow_datum(
      bond_name_1,
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
    bond_utils.get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  let bond_sell_qty = 5
  let received_at_maturity = escrow_full_info.value_at_maturity * bond_sell_qty
  let received_with_yield = price_of_one_bond * bond_sell_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.taker_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.maker_fee / cfg.platform.basis.base
  let owner_out_lovelace = 1310316
  let sc_address = get_bid_sc_address()
  let sc_in_lovelace =
    received_with_yield + exchange_fee_buyer + owner_out_lovelace
  let sc_in_1 =
    gen_input(sc_address, sc_in_lovelace, None, InlineDatum(sc_in_datum_1))
  let seller_in_lovelace = 1310316
  let asset_sell =
    value.from_asset(get_bond_policy_id(), bond_name_1, bond_sell_qty)
  let seller_in_1 =
    gen_input(seller_address, seller_in_lovelace, Some(asset_sell), NoDatum)
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_1,
      1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  let exchange_address = get_exchange_address()
  let exchange_out_lovelace = exchange_fee_buyer + exchange_fee_seller
  let exchange_out_1 =
    gen_output(exchange_address, exchange_out_lovelace, None, NoDatum)
  let seller_out_lovelace =
    seller_in_lovelace + received_with_yield - exchange_fee_seller
  let seller_out_1 =
    gen_output(seller_address, seller_out_lovelace, None, NoDatum)
  let owner_out_1 =
    gen_output(revert_address, owner_out_lovelace, Some(asset_sell), NoDatum)
  let sc_out_lovelace =
    sc_in_lovelace - received_with_yield - exchange_fee_buyer - owner_out_lovelace
  let sc_out_datum_1 =
    gen_bid_making_datum(
      owner_address,
      390,
      480,
      sc_in_datum_1.quantity - bond_sell_qty,
      500,
    )
  let sc_out_utxo =
    gen_output(sc_address, sc_out_lovelace, None, InlineDatum(sc_out_datum_1))
  let tx =
    fixture.tx(
      [sc_in_1, seller_in_1],
      [refer_in_1],
      [exchange_out_1, seller_out_1, owner_out_1, sc_out_utxo],
      Some([get_buyer_address_hash()]),
      None,
      None,
      None,
    )
  !sell.spending(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    sc_in_datum_1,
    [],
  )
}

test fail_wrong_owner_address() fail {
  let time_of_tx = 1681095094000
  let cfg = get_config_making_mainnet()
  let owner_address = get_owner_address()
  let seller_address = get_seller_address()
  let owner_in_datum_1 = gen_ask_making_datum(owner_address, 499)
  let sc_in_datum_1 = gen_bid_making_datum(owner_address, 390, 480, 5, 500)
  let revert_address = from_script(sc_in_datum_1.ask_sc)
  let bond_name_1 = get_bond_id_1()
  let escrow_bond_amount = 10000
  let escrow_epo_rewards = 753424657
  let escrow_duration = 72
  let escrow_datum =
    get_escrow_datum(
      bond_name_1,
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
    bond_utils.get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  let bond_sell_qty = 5
  let received_at_maturity = escrow_full_info.value_at_maturity * bond_sell_qty
  let received_with_yield = price_of_one_bond * bond_sell_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.taker_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.maker_fee / cfg.platform.basis.base
  let owner_out_lovelace = 1310316
  let sc_address = get_bid_sc_address()
  let sc_in_lovelace =
    received_with_yield + exchange_fee_buyer + owner_out_lovelace
  let sc_in_1 =
    gen_input(sc_address, sc_in_lovelace, None, InlineDatum(sc_in_datum_1))
  let seller_in_lovelace = 1310316
  let asset_sell =
    value.from_asset(get_bond_policy_id(), bond_name_1, bond_sell_qty)
  let seller_in_1 =
    gen_input(seller_address, seller_in_lovelace, Some(asset_sell), NoDatum)
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_1,
      1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  let exchange_address = get_exchange_address()
  let exchange_out_lovelace = exchange_fee_buyer + exchange_fee_seller
  let exchange_out_1 =
    gen_output(exchange_address, exchange_out_lovelace, None, NoDatum)
  let seller_out_lovelace =
    seller_in_lovelace + received_with_yield - exchange_fee_seller
  let seller_out_1 =
    gen_output(seller_address, seller_out_lovelace, None, NoDatum)
  let owner_out_1 =
    gen_output(
      revert_address,
      owner_out_lovelace,
      Some(asset_sell),
      InlineDatum(owner_in_datum_1),
    )
  let sc_out_lovelace =
    sc_in_lovelace - received_with_yield - exchange_fee_buyer - owner_out_lovelace
  let sc_out_datum_1 =
    gen_bid_making_datum(
      owner_address,
      390,
      480,
      sc_in_datum_1.quantity - bond_sell_qty,
      500,
    )
  let sc_out_utxo =
    gen_output(sc_address, sc_out_lovelace, None, InlineDatum(sc_out_datum_1))
  let tx =
    fixture.tx(
      [sc_in_1, seller_in_1],
      [refer_in_1],
      [exchange_out_1, seller_out_1, owner_out_1, sc_out_utxo],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  !sell.spending(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    sc_in_datum_1,
    [],
  )
}

test fail_escrow_policy_id_unexpect() fail {
  let time_of_tx = 1681095094000
  let cfg = get_config_making_mainnet()
  let owner_address = get_owner_address()
  let seller_address = get_seller_address()
  let sc_in_datum_1 = gen_bid_making_datum(owner_address, 390, 480, 5, 500)
  let revert_address = from_script(sc_in_datum_1.ask_sc)
  let bond_name_1 = get_bond_id_1()
  let escrow_bond_amount = 10000
  let escrow_epo_rewards = 753424657
  let escrow_duration = 72
  let escrow_datum =
    get_escrow_datum(
      bond_name_1,
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
    bond_utils.get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  let bond_sell_qty = 5
  let received_at_maturity = escrow_full_info.value_at_maturity * bond_sell_qty
  let received_with_yield = price_of_one_bond * bond_sell_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.taker_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.maker_fee / cfg.platform.basis.base
  let owner_out_lovelace = 1310316
  let sc_address = get_bid_sc_address()
  let sc_in_lovelace =
    received_with_yield + exchange_fee_buyer + owner_out_lovelace
  let sc_in_1 =
    gen_input(sc_address, sc_in_lovelace, None, InlineDatum(sc_in_datum_1))
  let seller_in_lovelace = 1310316
  let asset_sell =
    value.from_asset(get_bond_policy_id(), bond_name_1, bond_sell_qty)
  let seller_in_1 =
    gen_input(seller_address, seller_in_lovelace, Some(asset_sell), NoDatum)
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_not_escrow_policy_id(),
      bond_name_1,
      1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  let exchange_address = get_exchange_address()
  let exchange_out_lovelace = exchange_fee_buyer + exchange_fee_seller
  let exchange_out_1 =
    gen_output(exchange_address, exchange_out_lovelace, None, NoDatum)
  let seller_out_lovelace =
    seller_in_lovelace + received_with_yield - exchange_fee_seller
  let seller_out_1 =
    gen_output(seller_address, seller_out_lovelace, None, NoDatum)
  let owner_out_1 =
    gen_output(revert_address, owner_out_lovelace, Some(asset_sell), NoDatum)
  let sc_out_lovelace =
    sc_in_lovelace - received_with_yield - exchange_fee_buyer - owner_out_lovelace
  let sc_out_datum_1 =
    gen_bid_making_datum(
      owner_address,
      390,
      480,
      sc_in_datum_1.quantity - bond_sell_qty,
      500,
    )
  let sc_out_utxo =
    gen_output(sc_address, sc_out_lovelace, None, InlineDatum(sc_out_datum_1))
  let tx =
    fixture.tx(
      [sc_in_1, seller_in_1],
      [refer_in_1],
      [exchange_out_1, seller_out_1, owner_out_1, sc_out_utxo],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  !sell.spending(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    sc_in_datum_1,
    [],
  )
}

test fail_escrow_address_unexpect() fail {
  let time_of_tx = 1681095094000
  let cfg = get_config_making_mainnet()
  let owner_address = get_owner_address()
  let seller_address = get_seller_address()
  let sc_in_datum_1 = gen_bid_making_datum(owner_address, 390, 480, 5, 500)
  let revert_address = from_script(sc_in_datum_1.ask_sc)
  let bond_name_1 = get_bond_id_1()
  let escrow_bond_amount = 10000
  let escrow_epo_rewards = 753424657
  let escrow_duration = 72
  let escrow_datum =
    get_escrow_datum(
      bond_name_1,
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
    bond_utils.get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  let bond_sell_qty = 5
  let received_at_maturity = escrow_full_info.value_at_maturity * bond_sell_qty
  let received_with_yield = price_of_one_bond * bond_sell_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.taker_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.maker_fee / cfg.platform.basis.base
  let owner_out_lovelace = 1310316
  let sc_address = get_bid_sc_address()
  let sc_in_lovelace =
    received_with_yield + exchange_fee_buyer + owner_out_lovelace
  let sc_in_1 =
    gen_input(sc_address, sc_in_lovelace, None, InlineDatum(sc_in_datum_1))
  let seller_in_lovelace = 1310316
  let asset_sell =
    value.from_asset(get_bond_policy_id(), bond_name_1, bond_sell_qty)
  let seller_in_1 =
    gen_input(seller_address, seller_in_lovelace, Some(asset_sell), NoDatum)
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address_unexpect(),
      get_escrow_policy_id(),
      bond_name_1,
      1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  let exchange_address = get_exchange_address()
  let exchange_out_lovelace = exchange_fee_buyer + exchange_fee_seller
  let exchange_out_1 =
    gen_output(exchange_address, exchange_out_lovelace, None, NoDatum)
  let seller_out_lovelace =
    seller_in_lovelace + received_with_yield - exchange_fee_seller
  let seller_out_1 =
    gen_output(seller_address, seller_out_lovelace, None, NoDatum)
  let owner_out_1 =
    gen_output(revert_address, owner_out_lovelace, Some(asset_sell), NoDatum)
  let sc_out_lovelace =
    sc_in_lovelace - received_with_yield - exchange_fee_buyer - owner_out_lovelace
  let sc_out_datum_1 =
    gen_bid_making_datum(
      owner_address,
      390,
      480,
      sc_in_datum_1.quantity - bond_sell_qty,
      500,
    )
  let sc_out_utxo =
    gen_output(sc_address, sc_out_lovelace, None, InlineDatum(sc_out_datum_1))
  let tx =
    fixture.tx(
      [sc_in_1, seller_in_1],
      [refer_in_1],
      [exchange_out_1, seller_out_1, owner_out_1, sc_out_utxo],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  !sell.spending(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    sc_in_datum_1,
    [],
  )
}

test fail_escrow_datum_not_found() fail {
  let time_of_tx = 1681095094000
  let cfg = get_config_making_mainnet()
  let owner_address = get_owner_address()
  let seller_address = get_seller_address()
  let sc_in_datum_1 = gen_bid_making_datum(owner_address, 390, 480, 5, 500)
  let revert_address = from_script(sc_in_datum_1.ask_sc)
  let bond_name_1 = get_bond_id_1()
  let escrow_bond_amount = 10000
  let escrow_epo_rewards = 753424657
  let escrow_duration = 72
  let escrow_datum =
    get_escrow_datum(
      bond_name_1,
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
    bond_utils.get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  let bond_sell_qty = 5
  let received_at_maturity = escrow_full_info.value_at_maturity * bond_sell_qty
  let received_with_yield = price_of_one_bond * bond_sell_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.taker_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.maker_fee / cfg.platform.basis.base
  let owner_out_lovelace = 1310316
  let sc_address = get_bid_sc_address()
  let sc_in_lovelace =
    received_with_yield + exchange_fee_buyer + owner_out_lovelace
  let sc_in_1 =
    gen_input(sc_address, sc_in_lovelace, None, InlineDatum(sc_in_datum_1))
  let seller_in_lovelace = 1310316
  let asset_sell =
    value.from_asset(get_bond_policy_id(), bond_name_1, bond_sell_qty)
  let seller_in_1 =
    gen_input(seller_address, seller_in_lovelace, Some(asset_sell), NoDatum)
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_1,
      1,
      escrow_lovelace,
      NoDatum,
    )
  let exchange_address = get_exchange_address()
  let exchange_out_lovelace = exchange_fee_buyer + exchange_fee_seller
  let exchange_out_1 =
    gen_output(exchange_address, exchange_out_lovelace, None, NoDatum)
  let seller_out_lovelace =
    seller_in_lovelace + received_with_yield - exchange_fee_seller
  let seller_out_1 =
    gen_output(seller_address, seller_out_lovelace, None, NoDatum)
  let owner_out_1 =
    gen_output(revert_address, owner_out_lovelace, Some(asset_sell), NoDatum)
  let sc_out_lovelace =
    sc_in_lovelace - received_with_yield - exchange_fee_buyer - owner_out_lovelace
  let sc_out_datum_1 =
    gen_bid_making_datum(
      owner_address,
      390,
      480,
      sc_in_datum_1.quantity - bond_sell_qty,
      500,
    )
  let sc_out_utxo =
    gen_output(sc_address, sc_out_lovelace, None, InlineDatum(sc_out_datum_1))
  let tx =
    fixture.tx(
      [sc_in_1, seller_in_1],
      [refer_in_1],
      [exchange_out_1, seller_out_1, owner_out_1, sc_out_utxo],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  !sell.spending(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    sc_in_datum_1,
    [],
  )
}

test fail_escrow_datum_unexpect() fail {
  let time_of_tx = 1681095094000
  let cfg = get_config_making_mainnet()
  let owner_address = get_owner_address()
  let seller_address = get_seller_address()
  let sc_in_datum_1 = gen_bid_making_datum(owner_address, 390, 480, 5, 500)
  let revert_address = from_script(sc_in_datum_1.ask_sc)
  let bond_name_1 = get_bond_id_1()
  let escrow_bond_amount = 10000
  let escrow_epo_rewards = 753424657
  let escrow_duration = 72
  let escrow_datum =
    get_escrow_datum(
      bond_name_1,
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
    bond_utils.get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  let bond_sell_qty = 5
  let received_at_maturity = escrow_full_info.value_at_maturity * bond_sell_qty
  let received_with_yield = price_of_one_bond * bond_sell_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.taker_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.maker_fee / cfg.platform.basis.base
  let owner_out_lovelace = 1310316
  let sc_address = get_bid_sc_address()
  let sc_in_lovelace =
    received_with_yield + exchange_fee_buyer + owner_out_lovelace
  let sc_in_1 =
    gen_input(sc_address, sc_in_lovelace, None, InlineDatum(sc_in_datum_1))
  let seller_in_lovelace = 1310316
  let asset_sell =
    value.from_asset(get_bond_policy_id(), bond_name_1, bond_sell_qty)
  let seller_in_1 =
    gen_input(seller_address, seller_in_lovelace, Some(asset_sell), NoDatum)
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_1,
      1,
      escrow_lovelace,
      InlineDatum(sc_in_datum_1),
    )
  let exchange_address = get_exchange_address()
  let exchange_out_lovelace = exchange_fee_buyer + exchange_fee_seller
  let exchange_out_1 =
    gen_output(exchange_address, exchange_out_lovelace, None, NoDatum)
  let seller_out_lovelace =
    seller_in_lovelace + received_with_yield - exchange_fee_seller
  let seller_out_1 =
    gen_output(seller_address, seller_out_lovelace, None, NoDatum)
  let owner_out_1 =
    gen_output(revert_address, owner_out_lovelace, Some(asset_sell), NoDatum)
  let sc_out_lovelace =
    sc_in_lovelace - received_with_yield - exchange_fee_buyer - owner_out_lovelace
  let sc_out_datum_1 =
    gen_bid_making_datum(
      owner_address,
      390,
      480,
      sc_in_datum_1.quantity - bond_sell_qty,
      500,
    )
  let sc_out_utxo =
    gen_output(sc_address, sc_out_lovelace, None, InlineDatum(sc_out_datum_1))
  let tx =
    fixture.tx(
      [sc_in_1, seller_in_1],
      [refer_in_1],
      [exchange_out_1, seller_out_1, owner_out_1, sc_out_utxo],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  !sell.spending(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    sc_in_datum_1,
    [],
  )
}

test succ_bond_policy_id_valid() {
  let time_of_tx = 1681095094000
  let cfg = get_config_making_mainnet()
  let owner_address = get_owner_address()
  let seller_address = get_seller_address()
  let owner_in_datum_1 = gen_ask_making_datum(owner_address, 499)
  let sc_in_datum_1 = gen_bid_making_datum(owner_address, 390, 480, 5, 500)
  let revert_address = from_script(sc_in_datum_1.ask_sc)
  let bond_name_1 = get_bond_id_1()
  let escrow_bond_amount = 10000
  let escrow_epo_rewards = 753424657
  let escrow_duration = 72
  let escrow_datum =
    get_escrow_datum(
      bond_name_1,
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
    bond_utils.get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  let bond_sell_qty = 5
  let received_at_maturity = escrow_full_info.value_at_maturity * bond_sell_qty
  let received_with_yield = price_of_one_bond * bond_sell_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.taker_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.maker_fee / cfg.platform.basis.base
  let owner_out_lovelace = 1310316
  let sc_address = get_bid_sc_address()
  let sc_in_lovelace =
    received_with_yield + exchange_fee_buyer + owner_out_lovelace
  let sc_in_1 =
    gen_input(sc_address, sc_in_lovelace, None, InlineDatum(sc_in_datum_1))
  let seller_in_lovelace = 1310316
  let asset_sell =
    value.from_asset(get_bond_policy_id(), bond_name_1, bond_sell_qty)
  let seller_in_1 =
    gen_input(seller_address, seller_in_lovelace, Some(asset_sell), NoDatum)
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_1,
      1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  let exchange_address = get_exchange_address()
  let exchange_out_lovelace = exchange_fee_buyer + exchange_fee_seller
  let exchange_out_1 =
    gen_output(exchange_address, exchange_out_lovelace, None, NoDatum)
  let seller_out_lovelace =
    seller_in_lovelace + received_with_yield - exchange_fee_seller
  let seller_out_1 =
    gen_output(seller_address, seller_out_lovelace, None, NoDatum)
  let owner_out_1 =
    gen_output(
      revert_address,
      owner_out_lovelace,
      Some(asset_sell),
      InlineDatum(owner_in_datum_1),
    )
  let tx =
    fixture.tx(
      [sc_in_1, seller_in_1],
      [refer_in_1],
      [exchange_out_1, seller_out_1, owner_out_1],
      // [exchange_out_1, seller_out_1, owner_out_1, sc_out_utxo],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  sell.spending(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    sc_in_datum_1,
    [],
  )
}

test fail_bond_policy_id_invalid() fail {
  let time_of_tx = 1681095094000
  let cfg = get_config_making_mainnet()
  let owner_address = get_owner_address()
  let seller_address = get_seller_address()
  let owner_in_datum_1 = gen_ask_making_datum(owner_address, 499)
  let sc_in_datum_1 = gen_bid_making_datum(owner_address, 390, 480, 5, 500)
  let revert_address = from_script(sc_in_datum_1.ask_sc)
  let bond_name_1 = get_bond_id_1()
  let escrow_bond_amount = 10000
  let escrow_epo_rewards = 753424657
  let escrow_duration = 72
  let escrow_datum =
    get_escrow_datum(
      bond_name_1,
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
    bond_utils.get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  let bond_sell_qty = 2
  let received_at_maturity = escrow_full_info.value_at_maturity * bond_sell_qty
  let received_with_yield = price_of_one_bond * bond_sell_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.taker_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.maker_fee / cfg.platform.basis.base
  let owner_out_lovelace = 1310316
  let sc_address = get_bid_sc_address()
  let sc_in_lovelace =
    received_with_yield + exchange_fee_buyer + owner_out_lovelace
  let sc_in_1 =
    gen_input(sc_address, sc_in_lovelace, None, InlineDatum(sc_in_datum_1))
  let seller_in_lovelace = 1310316
  let asset_sell =
    value.from_asset(get_not_bond_policy_id(), bond_name_1, bond_sell_qty)
  let seller_in_1 =
    gen_input(seller_address, seller_in_lovelace, Some(asset_sell), NoDatum)
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_1,
      1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  let exchange_address = get_exchange_address()
  let exchange_out_lovelace = exchange_fee_buyer + exchange_fee_seller
  let exchange_out_1 =
    gen_output(exchange_address, exchange_out_lovelace, None, NoDatum)
  let seller_out_lovelace =
    seller_in_lovelace + received_with_yield - exchange_fee_seller
  let seller_out_1 =
    gen_output(seller_address, seller_out_lovelace, None, NoDatum)
  let owner_out_1 =
    gen_output(
      revert_address,
      owner_out_lovelace,
      Some(asset_sell),
      InlineDatum(owner_in_datum_1),
    )
  let sc_out_lovelace =
    sc_in_lovelace - received_with_yield - exchange_fee_buyer - owner_out_lovelace
  let sc_out_datum_1 =
    gen_bid_making_datum(
      owner_address,
      390,
      480,
      sc_in_datum_1.quantity - bond_sell_qty,
      500,
    )
  let sc_out_utxo =
    gen_output(sc_address, sc_out_lovelace, None, InlineDatum(sc_out_datum_1))
  let tx =
    fixture.tx(
      [sc_in_1, seller_in_1],
      [refer_in_1],
      [exchange_out_1, seller_out_1, owner_out_1, sc_out_utxo],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  !sell.spending(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    sc_in_datum_1,
    [],
  )
}

test fail_fraud_address() {
  let time_of_tx = 1681095094000
  let cfg = get_config_making_mainnet()
  let owner_address = get_owner_address()
  let seller_address = get_seller_address()
  let owner_in_datum_1 = gen_ask_making_datum(owner_address, 499)
  let sc_in_datum_1 = gen_bid_making_datum(owner_address, 390, 480, 5, 500)
  // let revert_address = from_script(sc_in_datum_1.ask_sc)
  let bond_name_1 = get_bond_id_1()
  let escrow_bond_amount = 10000
  let escrow_epo_rewards = 753424657
  let escrow_duration = 72
  let escrow_datum =
    get_escrow_datum(
      bond_name_1,
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
    bond_utils.get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  let bond_sell_qty = 2
  let received_at_maturity = escrow_full_info.value_at_maturity * bond_sell_qty
  let received_with_yield = price_of_one_bond * bond_sell_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.taker_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.maker_fee / cfg.platform.basis.base
  let owner_out_lovelace = 1310316
  let sc_address = get_bid_sc_address()
  let sc_in_lovelace =
    received_with_yield + exchange_fee_buyer + owner_out_lovelace
  let sc_in_1 =
    gen_input(sc_address, sc_in_lovelace, None, InlineDatum(sc_in_datum_1))
  let seller_in_lovelace = 1310316
  let asset_sell =
    value.from_asset(get_bond_policy_id(), bond_name_1, bond_sell_qty)
  let seller_in_1 =
    gen_input(seller_address, seller_in_lovelace, Some(asset_sell), NoDatum)
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_1,
      1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  let exchange_address = get_exchange_address()
  let exchange_out_lovelace = exchange_fee_buyer + exchange_fee_seller
  let exchange_out_1 =
    gen_output(exchange_address, exchange_out_lovelace, None, NoDatum)
  let seller_out_lovelace =
    seller_in_lovelace + received_with_yield - exchange_fee_seller
  let seller_out_1 =
    gen_output(seller_address, seller_out_lovelace, None, NoDatum)
  let owner_out_1 =
    gen_output(
      get_fraud_address(),
      owner_out_lovelace,
      Some(asset_sell),
      InlineDatum(owner_in_datum_1),
    )
  let sc_out_lovelace =
    sc_in_lovelace - received_with_yield - exchange_fee_buyer - owner_out_lovelace
  let sc_out_datum_1 =
    gen_bid_making_datum(
      owner_address,
      390,
      480,
      sc_in_datum_1.quantity - bond_sell_qty,
      500,
    )
  let sc_out_utxo =
    gen_output(sc_address, sc_out_lovelace, None, InlineDatum(sc_out_datum_1))
  let tx =
    fixture.tx(
      [sc_in_1, seller_in_1],
      [refer_in_1],
      [exchange_out_1, seller_out_1, owner_out_1, sc_out_utxo],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  !sell.spending(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    sc_in_datum_1,
    [],
  )
}

test fail_seller_must_not_owner() {
  let time_of_tx = 1681095094000
  let cfg = get_config_making_mainnet()
  let owner_address = get_owner_address()
  // seller is the owner -> fail
  let seller_address = owner_address
  let owner_in_datum_1 = gen_ask_making_datum(owner_address, 499)
  let sc_in_datum_1 = gen_bid_making_datum(owner_address, 390, 480, 5, 500)
  let revert_address = from_script(sc_in_datum_1.ask_sc)
  let bond_name_1 = get_bond_id_1()
  let escrow_bond_amount = 10000
  let escrow_epo_rewards = 753424657
  let escrow_duration = 72
  let escrow_datum =
    get_escrow_datum(
      bond_name_1,
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
    bond_utils.get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  let bond_sell_qty = 2
  let received_at_maturity = escrow_full_info.value_at_maturity * bond_sell_qty
  let received_with_yield = price_of_one_bond * bond_sell_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.taker_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.maker_fee / cfg.platform.basis.base
  let owner_out_lovelace = 1310316
  let sc_address = get_bid_sc_address()
  let sc_in_lovelace =
    received_with_yield + exchange_fee_buyer + owner_out_lovelace
  let sc_in_1 =
    gen_input(sc_address, sc_in_lovelace, None, InlineDatum(sc_in_datum_1))
  let seller_in_lovelace = 1310316
  let asset_sell =
    value.from_asset(get_bond_policy_id(), bond_name_1, bond_sell_qty)
  let seller_in_1 =
    gen_input(seller_address, seller_in_lovelace, Some(asset_sell), NoDatum)
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_1,
      1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  let exchange_address = get_exchange_address()
  let exchange_out_lovelace = exchange_fee_buyer + exchange_fee_seller
  let exchange_out_1 =
    gen_output(exchange_address, exchange_out_lovelace, None, NoDatum)
  let seller_out_lovelace =
    seller_in_lovelace + received_with_yield - exchange_fee_seller
  let seller_out_1 =
    gen_output(seller_address, seller_out_lovelace, None, NoDatum)
  let owner_out_1 =
    gen_output(
      revert_address,
      owner_out_lovelace,
      Some(asset_sell),
      InlineDatum(owner_in_datum_1),
    )
  let sc_out_lovelace =
    sc_in_lovelace - received_with_yield - exchange_fee_buyer - owner_out_lovelace
  let sc_out_datum_1 =
    gen_bid_making_datum(
      owner_address,
      390,
      480,
      sc_in_datum_1.quantity - bond_sell_qty,
      500,
    )
  let sc_out_utxo =
    gen_output(sc_address, sc_out_lovelace, None, InlineDatum(sc_out_datum_1))
  let tx =
    fixture.tx(
      [sc_in_1, seller_in_1],
      [refer_in_1],
      [exchange_out_1, seller_out_1, owner_out_1, sc_out_utxo],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  !sell.spending(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    sc_in_datum_1,
    [],
  )
}

test succ_partial_buy_2() {
  let time_of_tx = 1681095094000
  let cfg = get_config_making_mainnet()
  let owner_address = get_owner_address()
  let seller_address = get_seller_address()
  let owner_in_datum_1 = gen_ask_making_datum(owner_address, 499)
  let sc_in_datum_1 = gen_bid_making_datum(owner_address, 390, 480, 5, 500)
  let revert_address = from_script(sc_in_datum_1.ask_sc)
  let bond_name_1 = get_bond_id_1()
  let escrow_bond_amount = 10000
  let escrow_epo_rewards = 753424657
  let escrow_duration = 72
  let escrow_datum =
    get_escrow_datum(
      bond_name_1,
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
    bond_utils.get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  let bond_sell_qty = 2
  let received_at_maturity = escrow_full_info.value_at_maturity * bond_sell_qty
  let received_with_yield = price_of_one_bond * bond_sell_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.taker_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.maker_fee / cfg.platform.basis.base
  let owner_out_lovelace = 1310316
  let sc_address = get_bid_sc_address()
  let sc_in_lovelace = 1000000000
  let sc_in_1 =
    gen_input(sc_address, sc_in_lovelace, None, InlineDatum(sc_in_datum_1))
  let seller_in_lovelace = 1310316
  let asset_sell =
    value.from_asset(get_bond_policy_id(), bond_name_1, bond_sell_qty)
  let seller_in_1 =
    gen_input(seller_address, seller_in_lovelace, Some(asset_sell), NoDatum)
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_1,
      1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  let exchange_address = get_exchange_address()
  let exchange_out_lovelace = exchange_fee_buyer + exchange_fee_seller
  let exchange_out_1 =
    gen_output(exchange_address, exchange_out_lovelace, None, NoDatum)
  let seller_out_lovelace =
    seller_in_lovelace + received_with_yield - exchange_fee_seller
  let seller_out_1 =
    gen_output(seller_address, seller_out_lovelace, None, NoDatum)
  let owner_out_1 =
    gen_output(
      revert_address,
      owner_out_lovelace,
      Some(asset_sell),
      InlineDatum(owner_in_datum_1),
    )
  let sc_out_lovelace =
    sc_in_lovelace - received_with_yield - exchange_fee_buyer - owner_out_lovelace
  let sc_out_datum_1 =
    gen_bid_making_datum(
      owner_address,
      390,
      480,
      sc_in_datum_1.quantity - bond_sell_qty,
      500,
    )
  let sc_out_utxo =
    gen_output(sc_address, sc_out_lovelace, None, InlineDatum(sc_out_datum_1))
  let tx =
    fixture.tx(
      [sc_in_1, seller_in_1],
      [refer_in_1],
      [exchange_out_1, seller_out_1, owner_out_1, sc_out_utxo],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  sell.spending(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    sc_in_datum_1,
    [],
  )
}

test fail_sell_more_lovelace_than_expect() {
  let time_of_tx = 1681095094000
  let cfg = get_config_making_mainnet()
  let owner_address = get_owner_address()
  let seller_address = get_seller_address()
  let owner_in_datum_1 = gen_ask_making_datum(owner_address, 499)
  let sc_in_datum_1 = gen_bid_making_datum(owner_address, 390, 480, 5, 500)
  let revert_address = from_script(sc_in_datum_1.ask_sc)
  let bond_name_1 = get_bond_id_1()
  let escrow_bond_amount = 10000
  let escrow_epo_rewards = 753424657
  let escrow_duration = 72
  let escrow_datum =
    get_escrow_datum(
      bond_name_1,
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
    bond_utils.get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  let bond_sell_qty = 2
  let received_at_maturity = escrow_full_info.value_at_maturity * bond_sell_qty
  let received_with_yield = price_of_one_bond * bond_sell_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.taker_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.maker_fee / cfg.platform.basis.base
  let owner_out_lovelace = 1310316
  let sc_address = get_bid_sc_address()
  let sc_in_lovelace = 1000000000
  let sc_in_1 =
    gen_input(sc_address, sc_in_lovelace, None, InlineDatum(sc_in_datum_1))
  let seller_in_lovelace = 1310316
  let asset_sell =
    value.from_asset(get_bond_policy_id(), bond_name_1, bond_sell_qty)
  let seller_in_1 =
    gen_input(seller_address, seller_in_lovelace, Some(asset_sell), NoDatum)
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_1,
      1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  let exchange_address = get_exchange_address()
  let exchange_out_lovelace = exchange_fee_buyer + exchange_fee_seller
  let exchange_out_1 =
    gen_output(exchange_address, exchange_out_lovelace, None, NoDatum)
  let seller_out_lovelace =
    seller_in_lovelace + received_with_yield - exchange_fee_seller
  // try to oversell
  let seller_out_1 =
    gen_output(seller_address, seller_out_lovelace + 50_000_000, None, NoDatum)
  let owner_out_1 =
    gen_output(
      revert_address,
      owner_out_lovelace,
      Some(asset_sell),
      InlineDatum(owner_in_datum_1),
    )
  // try to oversell
  let sc_out_lovelace =
    sc_in_lovelace - received_with_yield - exchange_fee_buyer - owner_out_lovelace - 50_000_000
  let sc_out_datum_1 =
    gen_bid_making_datum(
      owner_address,
      390,
      480,
      sc_in_datum_1.quantity - bond_sell_qty,
      500,
    )
  let sc_out_utxo =
    gen_output(sc_address, sc_out_lovelace, None, InlineDatum(sc_out_datum_1))
  let tx =
    fixture.tx(
      [sc_in_1, seller_in_1],
      [refer_in_1],
      [exchange_out_1, seller_out_1, owner_out_1, sc_out_utxo],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  !sell.spending(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    sc_in_datum_1,
    [],
  )
}

test fail_sell_less_lovelace_than_expect() {
  let time_of_tx = 1681095094000
  let cfg = get_config_making_mainnet()
  let owner_address = get_owner_address()
  let seller_address = get_seller_address()
  let owner_in_datum_1 = gen_ask_making_datum(owner_address, 499)
  let sc_in_datum_1 = gen_bid_making_datum(owner_address, 390, 480, 5, 500)
  let revert_address = from_script(sc_in_datum_1.ask_sc)
  let bond_name_1 = get_bond_id_1()
  let escrow_bond_amount = 10000
  let escrow_epo_rewards = 753424657
  let escrow_duration = 72
  let escrow_datum =
    get_escrow_datum(
      bond_name_1,
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
    bond_utils.get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  let bond_sell_qty = 2
  let received_at_maturity = escrow_full_info.value_at_maturity * bond_sell_qty
  let received_with_yield = price_of_one_bond * bond_sell_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.taker_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.maker_fee / cfg.platform.basis.base
  let owner_out_lovelace = 1310316
  let sc_address = get_bid_sc_address()
  let sc_in_lovelace = 1000000000
  let sc_in_1 =
    gen_input(sc_address, sc_in_lovelace, None, InlineDatum(sc_in_datum_1))
  let seller_in_lovelace = 1310316
  let asset_sell =
    value.from_asset(get_bond_policy_id(), bond_name_1, bond_sell_qty)
  let seller_in_1 =
    gen_input(seller_address, seller_in_lovelace, Some(asset_sell), NoDatum)
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_1,
      1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  let exchange_address = get_exchange_address()
  let exchange_out_lovelace = exchange_fee_buyer + exchange_fee_seller
  let exchange_out_1 =
    gen_output(exchange_address, exchange_out_lovelace, None, NoDatum)
  let seller_out_lovelace =
    seller_in_lovelace + received_with_yield - exchange_fee_seller
  // try to undersell
  let seller_out_1 =
    gen_output(seller_address, seller_out_lovelace - 50_000_000, None, NoDatum)
  let owner_out_1 =
    gen_output(
      revert_address,
      owner_out_lovelace,
      Some(asset_sell),
      InlineDatum(owner_in_datum_1),
    )
  // try to undersell
  let sc_out_lovelace =
    sc_in_lovelace - received_with_yield - exchange_fee_buyer - owner_out_lovelace + 50_000_000
  let sc_out_datum_1 =
    gen_bid_making_datum(
      owner_address,
      390,
      480,
      sc_in_datum_1.quantity - bond_sell_qty,
      500,
    )
  let sc_out_utxo =
    gen_output(sc_address, sc_out_lovelace, None, InlineDatum(sc_out_datum_1))
  let tx =
    fixture.tx(
      [sc_in_1, seller_in_1],
      [refer_in_1],
      [exchange_out_1, seller_out_1, owner_out_1, sc_out_utxo],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  !sell.spending(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    sc_in_datum_1,
    [],
  )
}

test fail_revert_tampered_bid_address_ask_making() fail {
  let time_of_tx = 1681095094000
  let cfg = get_config_making_mainnet()
  let owner_address = get_owner_address()
  let seller_address = get_seller_address()
  let owner_out_bid_datum_1 = gen_tampered_ask_making_datum(owner_address, 499)
  let sc_in_datum_1 = gen_bid_making_datum(owner_address, 390, 480, 5, 500)
  let revert_address = from_script(sc_in_datum_1.ask_sc)
  let bond_name_1 = get_bond_id_1()
  let escrow_bond_amount = 10000
  let escrow_epo_rewards = 753424657
  let escrow_duration = 72
  let escrow_datum =
    get_escrow_datum(
      bond_name_1,
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
    bond_utils.get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  let bond_sell_qty = 2
  let received_at_maturity = escrow_full_info.value_at_maturity * bond_sell_qty
  let received_with_yield = price_of_one_bond * bond_sell_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.taker_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.maker_fee / cfg.platform.basis.base
  let owner_out_lovelace = 1310316
  let sc_address = get_bid_sc_address()
  let sc_in_lovelace = 1000000000
  let sc_in_1 =
    gen_input(sc_address, sc_in_lovelace, None, InlineDatum(sc_in_datum_1))
  let seller_in_lovelace = 1310316
  let asset_sell =
    value.from_asset(get_bond_policy_id(), bond_name_1, bond_sell_qty)
  let seller_in_1 =
    gen_input(seller_address, seller_in_lovelace, Some(asset_sell), NoDatum)
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_1,
      1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  let exchange_address = get_exchange_address()
  let exchange_out_lovelace = exchange_fee_buyer + exchange_fee_seller
  let exchange_out_1 =
    gen_output(exchange_address, exchange_out_lovelace, None, NoDatum)
  let seller_out_lovelace =
    seller_in_lovelace + received_with_yield - exchange_fee_seller
  let seller_out_1 =
    gen_output(seller_address, seller_out_lovelace, None, NoDatum)
  let owner_out_1 =
    gen_output(
      revert_address,
      owner_out_lovelace,
      Some(asset_sell),
      InlineDatum(owner_out_bid_datum_1),
    )
  let sc_out_lovelace =
    sc_in_lovelace - received_with_yield - exchange_fee_buyer - owner_out_lovelace
  let sc_out_datum_1 =
    gen_bid_making_datum(
      owner_address,
      390,
      480,
      sc_in_datum_1.quantity - bond_sell_qty,
      500,
    )
  let sc_out_utxo =
    gen_output(sc_address, sc_out_lovelace, None, InlineDatum(sc_out_datum_1))
  let tx =
    fixture.tx(
      [sc_in_1, seller_in_1],
      [refer_in_1],
      [exchange_out_1, seller_out_1, owner_out_1, sc_out_utxo],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  !sell.spending(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    sc_in_datum_1,
    [],
  )
}

test fail_revert_tampered_ask_address_sc_out() fail {
  let time_of_tx = 1681095094000
  let cfg = get_config_making_mainnet()
  let owner_address = get_owner_address()
  let seller_address = get_seller_address()
  let owner_out_bid_datum_1 = gen_ask_making_datum(owner_address, 499)
  let sc_in_datum_1 = gen_bid_making_datum(owner_address, 390, 480, 5, 500)
  let revert_address = from_script(sc_in_datum_1.ask_sc)
  let bond_name_1 = get_bond_id_1()
  let escrow_bond_amount = 10000
  let escrow_epo_rewards = 753424657
  let escrow_duration = 72
  let escrow_datum =
    get_escrow_datum(
      bond_name_1,
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
    bond_utils.get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  let bond_sell_qty = 2
  let received_at_maturity = escrow_full_info.value_at_maturity * bond_sell_qty
  let received_with_yield = price_of_one_bond * bond_sell_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.taker_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.maker_fee / cfg.platform.basis.base
  let owner_out_lovelace = 1310316
  let sc_address = get_bid_sc_address()
  let sc_in_lovelace = 1000000000
  let sc_in_1 =
    gen_input(sc_address, sc_in_lovelace, None, InlineDatum(sc_in_datum_1))
  let seller_in_lovelace = 1310316
  let asset_sell =
    value.from_asset(get_bond_policy_id(), bond_name_1, bond_sell_qty)
  let seller_in_1 =
    gen_input(seller_address, seller_in_lovelace, Some(asset_sell), NoDatum)
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_1,
      1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  let exchange_address = get_exchange_address()
  let exchange_out_lovelace = exchange_fee_buyer + exchange_fee_seller
  let exchange_out_1 =
    gen_output(exchange_address, exchange_out_lovelace, None, NoDatum)
  let seller_out_lovelace =
    seller_in_lovelace + received_with_yield - exchange_fee_seller
  let seller_out_1 =
    gen_output(seller_address, seller_out_lovelace, None, NoDatum)
  let owner_out_1 =
    gen_output(
      revert_address,
      owner_out_lovelace,
      Some(asset_sell),
      InlineDatum(owner_out_bid_datum_1),
    )
  let sc_out_lovelace =
    sc_in_lovelace - received_with_yield - exchange_fee_buyer - owner_out_lovelace
  let sc_out_datum_1 =
    gen_tampered_bid_making_datum(
      owner_address,
      390,
      480,
      sc_in_datum_1.quantity - bond_sell_qty,
      500,
    )
  let sc_out_utxo =
    gen_output(sc_address, sc_out_lovelace, None, InlineDatum(sc_out_datum_1))
  let tx =
    fixture.tx(
      [sc_in_1, seller_in_1],
      [refer_in_1],
      [exchange_out_1, seller_out_1, owner_out_1, sc_out_utxo],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  !sell.spending(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    sc_in_datum_1,
    [],
  )
}

test fail_when_spend_deprecated_bid() fail {
  let time_of_tx = 1681095094000
  let cfg = get_config_making_mainnet()
  let owner_address = get_owner_address()
  let seller_address = get_seller_address()
  let owner_in_datum_1 = gen_ask_making_datum(owner_address, 499)
  let sc_in_datum_1 = gen_bid_making_datum(owner_address, 390, 480, 5, 500)
  // sc address that will be used to continue to make ask order
  let revert_address = from_script(sc_in_datum_1.ask_sc)
  let bond_name_1 = get_bond_id_1()
  let escrow_bond_amount = 10000
  let escrow_epo_rewards = 753424657
  let escrow_duration = 72
  let escrow_datum =
    get_escrow_datum(
      bond_name_1,
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
    bond_utils.get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  let bond_sell_qty = 5
  let received_at_maturity = escrow_full_info.value_at_maturity * bond_sell_qty
  let received_with_yield = price_of_one_bond * bond_sell_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.taker_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.maker_fee / cfg.platform.basis.base
  let owner_out_lovelace = 1310316
  let sc_address = get_bid_sc_address()
  let sc_in_lovelace =
    received_with_yield + exchange_fee_buyer + owner_out_lovelace
  let sc_in_1 =
    gen_input(sc_address, sc_in_lovelace, None, InlineDatum(sc_in_datum_1))

  let deprecated_bid_skh = "deprecated_bid_skh"
  let deprecated_bid_in =
    gen_input(
      from_script(deprecated_bid_skh),
      sc_in_lovelace,
      None,
      InlineDatum(sc_in_datum_1),
    )
  let seller_in_lovelace = 1310316
  let asset_sell =
    value.from_asset(get_bond_policy_id(), bond_name_1, bond_sell_qty)
  let seller_in_1 =
    gen_input(seller_address, seller_in_lovelace, Some(asset_sell), NoDatum)
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_1,
      1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  let exchange_address = get_exchange_address()
  let exchange_out_lovelace = exchange_fee_buyer + exchange_fee_seller
  let exchange_out_1 =
    gen_output(exchange_address, exchange_out_lovelace, None, NoDatum)
  let seller_out_lovelace =
    seller_in_lovelace + received_with_yield - exchange_fee_seller
  let seller_out_1 =
    gen_output(seller_address, seller_out_lovelace, None, NoDatum)
  let owner_out_1 =
    gen_output(
      revert_address,
      owner_out_lovelace,
      Some(asset_sell),
      InlineDatum(owner_in_datum_1),
    )
  let tx =
    fixture.tx(
      [sc_in_1, seller_in_1, deprecated_bid_in],
      [refer_in_1],
      [exchange_out_1, seller_out_1, owner_out_1],
      // [exchange_out_1, seller_out_1, owner_out_1, sc_out_utxo],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  sell.spending(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    sc_in_datum_1,
    [deprecated_bid_skh],
  )
}

test fail_when_attempting_unbound_value_attack_on_sell_full() {
  let time_of_tx = 1681095094000
  let cfg = get_config_making_mainnet()
  let owner_address = get_owner_address()
  let seller_address = get_seller_address()
  let owner_in_datum_1 = gen_ask_making_datum(owner_address, 499)
  let sc_in_datum_1 = gen_bid_making_datum(owner_address, 390, 480, 5, 500)
  // sc address that will be used to continue to make ask order
  let revert_address = from_script(sc_in_datum_1.ask_sc)
  let bond_name_1 = get_bond_id_1()
  let escrow_bond_amount = 10000
  let escrow_epo_rewards = 753424657
  let escrow_duration = 72
  let escrow_datum =
    get_escrow_datum(
      bond_name_1,
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
    bond_utils.get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  let bond_sell_qty = 5
  let received_at_maturity = escrow_full_info.value_at_maturity * bond_sell_qty
  let received_with_yield = price_of_one_bond * bond_sell_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.taker_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.maker_fee / cfg.platform.basis.base
  let owner_out_lovelace = 1310316
  let sc_address = get_bid_sc_address()
  let sc_in_lovelace =
    received_with_yield + exchange_fee_buyer + owner_out_lovelace
  let sc_in_1 =
    gen_input(sc_address, sc_in_lovelace, None, InlineDatum(sc_in_datum_1))
  let seller_in_lovelace = 1310316
  let asset_sell =
    value.from_asset(get_bond_policy_id(), bond_name_1, bond_sell_qty)
  let seller_in_1 =
    gen_input(seller_address, seller_in_lovelace, Some(asset_sell), NoDatum)
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_1,
      1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  let exchange_address = get_exchange_address()
  let exchange_out_lovelace = exchange_fee_buyer + exchange_fee_seller
  let exchange_out_1 =
    gen_output(exchange_address, exchange_out_lovelace, None, NoDatum)
  let seller_out_lovelace =
    seller_in_lovelace + received_with_yield - exchange_fee_seller
  let seller_out_1 =
    gen_output(seller_address, seller_out_lovelace, None, NoDatum)
  let owner_out_1 =
    gen_output(
      revert_address,
      owner_out_lovelace,
      Some(asset_sell),
      InlineDatum(owner_in_datum_1),
    )
  let (dummy_pid, dummy_tkn) = ("dummy_pid", "dummy_tkn")
  let tx =
    fixture.tx(
      [sc_in_1, seller_in_1],
      [refer_in_1],
      [
        exchange_out_1,
        seller_out_1,
        owner_out_1 |> add_asset(dummy_pid, dummy_tkn, 1),
      ],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  !sell.spending(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    sc_in_datum_1,
    [],
  )
}

test fail_when_attempting_unbound_value_attack_on_sell_partial_1() {
  let time_of_tx = 1681095094000
  let cfg = get_config_making_mainnet()
  let owner_address = get_owner_address()
  let seller_address = get_seller_address()
  let owner_in_datum_1 = gen_ask_making_datum(owner_address, 499)
  let sc_in_datum_1 = gen_bid_making_datum(owner_address, 390, 480, 5, 500)
  let revert_address = from_script(sc_in_datum_1.ask_sc)
  let bond_name_1 = get_bond_id_1()
  let escrow_bond_amount = 10000
  let escrow_epo_rewards = 753424657
  let escrow_duration = 72
  let escrow_datum =
    get_escrow_datum(
      bond_name_1,
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
    bond_utils.get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  let bond_sell_qty = 2
  let received_at_maturity = escrow_full_info.value_at_maturity * bond_sell_qty
  let received_with_yield = price_of_one_bond * bond_sell_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.taker_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.maker_fee / cfg.platform.basis.base
  let owner_out_lovelace = 1310316
  let sc_address = get_bid_sc_address()
  let sc_in_lovelace =
    received_with_yield + exchange_fee_buyer + owner_out_lovelace
  let sc_in_1 =
    gen_input(sc_address, sc_in_lovelace, None, InlineDatum(sc_in_datum_1))
  let seller_in_lovelace = 1310316
  let asset_sell =
    value.from_asset(get_bond_policy_id(), bond_name_1, bond_sell_qty)
  let seller_in_1 =
    gen_input(seller_address, seller_in_lovelace, Some(asset_sell), NoDatum)
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_1,
      1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  let exchange_address = get_exchange_address()
  let exchange_out_lovelace = exchange_fee_buyer + exchange_fee_seller
  let exchange_out_1 =
    gen_output(exchange_address, exchange_out_lovelace, None, NoDatum)
  let seller_out_lovelace =
    seller_in_lovelace + received_with_yield - exchange_fee_seller
  let seller_out_1 =
    gen_output(seller_address, seller_out_lovelace, None, NoDatum)
  let owner_out_1 =
    gen_output(
      revert_address,
      owner_out_lovelace,
      Some(asset_sell),
      InlineDatum(owner_in_datum_1),
    )
  let sc_out_lovelace =
    sc_in_lovelace - received_with_yield - exchange_fee_buyer - owner_out_lovelace
  let sc_out_datum_1 =
    gen_bid_making_datum(
      owner_address,
      390,
      480,
      sc_in_datum_1.quantity - bond_sell_qty,
      500,
    )
  let sc_out_utxo =
    gen_output(sc_address, sc_out_lovelace, None, InlineDatum(sc_out_datum_1))
  let (dummy_pid, dummy_tkn) = ("dummy_pid", "dummy_tkn")
  let tx =
    fixture.tx(
      [sc_in_1, seller_in_1],
      [refer_in_1],
      [
        exchange_out_1,
        seller_out_1,
        owner_out_1,
        sc_out_utxo |> add_asset(dummy_pid, dummy_tkn, 1),
      ],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  !sell.spending(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    sc_in_datum_1,
    [],
  )
}

test fail_when_attempting_unbound_value_attack_on_sell_partial_2() {
  let time_of_tx = 1681095094000
  let cfg = get_config_making_mainnet()
  let owner_address = get_owner_address()
  let seller_address = get_seller_address()
  let owner_in_datum_1 = gen_ask_making_datum(owner_address, 499)
  let sc_in_datum_1 = gen_bid_making_datum(owner_address, 390, 480, 5, 500)
  let revert_address = from_script(sc_in_datum_1.ask_sc)
  let bond_name_1 = get_bond_id_1()
  let escrow_bond_amount = 10000
  let escrow_epo_rewards = 753424657
  let escrow_duration = 72
  let escrow_datum =
    get_escrow_datum(
      bond_name_1,
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
    bond_utils.get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  let bond_sell_qty = 2
  let received_at_maturity = escrow_full_info.value_at_maturity * bond_sell_qty
  let received_with_yield = price_of_one_bond * bond_sell_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.taker_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.maker_fee / cfg.platform.basis.base
  let owner_out_lovelace = 1310316
  let sc_address = get_bid_sc_address()
  let sc_in_lovelace =
    received_with_yield + exchange_fee_buyer + owner_out_lovelace
  let sc_in_1 =
    gen_input(sc_address, sc_in_lovelace, None, InlineDatum(sc_in_datum_1))
  let seller_in_lovelace = 1310316
  let asset_sell =
    value.from_asset(get_bond_policy_id(), bond_name_1, bond_sell_qty)
  let seller_in_1 =
    gen_input(seller_address, seller_in_lovelace, Some(asset_sell), NoDatum)
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_1,
      1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  let exchange_address = get_exchange_address()
  let exchange_out_lovelace = exchange_fee_buyer + exchange_fee_seller
  let exchange_out_1 =
    gen_output(exchange_address, exchange_out_lovelace, None, NoDatum)
  let seller_out_lovelace =
    seller_in_lovelace + received_with_yield - exchange_fee_seller
  let seller_out_1 =
    gen_output(seller_address, seller_out_lovelace, None, NoDatum)
  let owner_out_1 =
    gen_output(
      revert_address,
      owner_out_lovelace,
      Some(asset_sell),
      InlineDatum(owner_in_datum_1),
    )
  let sc_out_lovelace =
    sc_in_lovelace - received_with_yield - exchange_fee_buyer - owner_out_lovelace
  let sc_out_datum_1 =
    gen_bid_making_datum(
      owner_address,
      390,
      480,
      sc_in_datum_1.quantity - bond_sell_qty,
      500,
    )
  let sc_out_utxo =
    gen_output(sc_address, sc_out_lovelace, None, InlineDatum(sc_out_datum_1))
  let (dummy_pid, dummy_tkn) = ("dummy_pid", "dummy_tkn")
  let tx =
    fixture.tx(
      [sc_in_1, seller_in_1],
      [refer_in_1],
      [
        exchange_out_1,
        seller_out_1,
        owner_out_1 |> add_asset(dummy_pid, dummy_tkn, 1),
        sc_out_utxo,
      ],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  !sell.spending(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    sc_in_datum_1,
    [],
  )
}

test succ_when_sask_stake_key_is_verification_key() {
  let time_of_tx = 1681095094000
  let sbid_stake_key_hash = #"080201"
  let owner_sk = #"080203"
  let cfg = get_config_making_mainnet()
  let owner_address = get_owner_address() |> with_delegation_key(owner_sk)
  let seller_address = get_seller_address()
  let owner_in_datum_1 = gen_ask_making_datum(owner_address, 499)
  let sc_in_datum_1 = gen_bid_making_datum(owner_address, 390, 480, 5, 500)
  // sc address that will be used to continue to make ask order
  let revert_address =
    from_script(sc_in_datum_1.ask_sc)
      |> with_delegation_key(sbid_stake_key_hash)
  let bond_name_1 = get_bond_id_1()
  let escrow_bond_amount = 10000
  let escrow_epo_rewards = 753424657
  let escrow_duration = 72
  let escrow_datum =
    get_escrow_datum(
      bond_name_1,
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
    bond_utils.get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  let bond_sell_qty = 5
  let received_at_maturity = escrow_full_info.value_at_maturity * bond_sell_qty
  let received_with_yield = price_of_one_bond * bond_sell_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.taker_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.maker_fee / cfg.platform.basis.base
  let owner_out_lovelace = 1310316
  let sc_address =
    get_bid_sc_address() |> with_delegation_key(sbid_stake_key_hash)
  let sc_in_lovelace =
    received_with_yield + exchange_fee_buyer + owner_out_lovelace
  let sc_in_1 =
    gen_input(sc_address, sc_in_lovelace, None, InlineDatum(sc_in_datum_1))
  let seller_in_lovelace = 1310316
  let asset_sell =
    value.from_asset(get_bond_policy_id(), bond_name_1, bond_sell_qty)
  let seller_in_1 =
    gen_input(seller_address, seller_in_lovelace, Some(asset_sell), NoDatum)
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_1,
      1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  let exchange_address = get_exchange_address()
  let exchange_out_lovelace = exchange_fee_buyer + exchange_fee_seller
  let exchange_out_1 =
    gen_output(exchange_address, exchange_out_lovelace, None, NoDatum)
  let seller_out_lovelace =
    seller_in_lovelace + received_with_yield - exchange_fee_seller
  let seller_out_1 =
    gen_output(seller_address, seller_out_lovelace, None, NoDatum)
  let owner_out_1 =
    gen_output(
      revert_address,
      owner_out_lovelace,
      Some(asset_sell),
      InlineDatum(owner_in_datum_1),
    )
  let tx =
    fixture.tx(
      [sc_in_1, seller_in_1],
      [refer_in_1],
      [exchange_out_1, seller_out_1, owner_out_1],
      // [exchange_out_1, seller_out_1, owner_out_1, sc_out_utxo],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  sell.spending(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    sc_in_datum_1,
    [],
  )
}

test succ_when_sask_stake_key_is_script() {
  let time_of_tx = 1681095094000
  let sbid_stake_key_hash = #"010203"
  let owner_sk = #"080203"
  let cfg = get_config_making_mainnet()
  let owner_address = get_owner_address() |> with_delegation_script(owner_sk)
  let seller_address = get_seller_address()
  let owner_in_datum_1 = gen_ask_making_datum(owner_address, 499)
  let sc_in_datum_1 = gen_bid_making_datum(owner_address, 390, 480, 5, 500)
  // sc address that will be used to continue to make ask order
  let revert_address =
    from_script(sc_in_datum_1.ask_sc)
      |> with_delegation_script(sbid_stake_key_hash)
  let bond_name_1 = get_bond_id_1()
  let escrow_bond_amount = 10000
  let escrow_epo_rewards = 753424657
  let escrow_duration = 72
  let escrow_datum =
    get_escrow_datum(
      bond_name_1,
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
    bond_utils.get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  let bond_sell_qty = 5
  let received_at_maturity = escrow_full_info.value_at_maturity * bond_sell_qty
  let received_with_yield = price_of_one_bond * bond_sell_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.taker_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.maker_fee / cfg.platform.basis.base
  let owner_out_lovelace = 1310316
  let sc_address =
    get_bid_sc_address() |> with_delegation_script(sbid_stake_key_hash)
  let sc_in_lovelace =
    received_with_yield + exchange_fee_buyer + owner_out_lovelace
  let sc_in_1 =
    gen_input(sc_address, sc_in_lovelace, None, InlineDatum(sc_in_datum_1))
  let seller_in_lovelace = 1310316
  let asset_sell =
    value.from_asset(get_bond_policy_id(), bond_name_1, bond_sell_qty)
  let seller_in_1 =
    gen_input(seller_address, seller_in_lovelace, Some(asset_sell), NoDatum)
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_1,
      1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  let exchange_address = get_exchange_address()
  let exchange_out_lovelace = exchange_fee_buyer + exchange_fee_seller
  let exchange_out_1 =
    gen_output(exchange_address, exchange_out_lovelace, None, NoDatum)
  let seller_out_lovelace =
    seller_in_lovelace + received_with_yield - exchange_fee_seller
  let seller_out_1 =
    gen_output(seller_address, seller_out_lovelace, None, NoDatum)
  let owner_out_1 =
    gen_output(
      revert_address,
      owner_out_lovelace,
      Some(asset_sell),
      InlineDatum(owner_in_datum_1),
    )
  let tx =
    fixture.tx(
      [sc_in_1, seller_in_1],
      [refer_in_1],
      [exchange_out_1, seller_out_1, owner_out_1],
      // [exchange_out_1, seller_out_1, owner_out_1, sc_out_utxo],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  sell.spending(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    sc_in_datum_1,
    [],
  )
}

test fail_when_bid_output_stake_addr_is_owner_sk() fail {
  let time_of_tx = 1681095094000
  let owner_sk = #"080203"
  let cfg = get_config_making_mainnet()
  let owner_address = get_owner_address() |> with_delegation_key(owner_sk)
  let seller_address = get_seller_address()
  let owner_in_datum_1 = gen_ask_making_datum(owner_address, 499)
  let sc_in_datum_1 = gen_bid_making_datum(owner_address, 390, 480, 5, 500)
  // sc address that will be used to continue to make ask order
  let revert_address =
    from_script(sc_in_datum_1.ask_sc)
      |> with_delegation_key(owner_sk)
  let bond_name_1 = get_bond_id_1()
  let escrow_bond_amount = 10000
  let escrow_epo_rewards = 753424657
  let escrow_duration = 72
  let escrow_datum =
    get_escrow_datum(
      bond_name_1,
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
    bond_utils.get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  let bond_sell_qty = 5
  let received_at_maturity = escrow_full_info.value_at_maturity * bond_sell_qty
  let received_with_yield = price_of_one_bond * bond_sell_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.taker_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.maker_fee / cfg.platform.basis.base
  let owner_out_lovelace = 1310316
  let sc_address = get_bid_sc_address()
  let sc_in_lovelace =
    received_with_yield + exchange_fee_buyer + owner_out_lovelace
  let sc_in_1 =
    gen_input(sc_address, sc_in_lovelace, None, InlineDatum(sc_in_datum_1))
  let seller_in_lovelace = 1310316
  let asset_sell =
    value.from_asset(get_bond_policy_id(), bond_name_1, bond_sell_qty)
  let seller_in_1 =
    gen_input(seller_address, seller_in_lovelace, Some(asset_sell), NoDatum)
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_1,
      1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  let exchange_address = get_exchange_address()
  let exchange_out_lovelace = exchange_fee_buyer + exchange_fee_seller
  let exchange_out_1 =
    gen_output(exchange_address, exchange_out_lovelace, None, NoDatum)
  let seller_out_lovelace =
    seller_in_lovelace + received_with_yield - exchange_fee_seller
  let seller_out_1 =
    gen_output(seller_address, seller_out_lovelace, None, NoDatum)
  let owner_out_1 =
    gen_output(
      revert_address,
      owner_out_lovelace,
      Some(asset_sell),
      InlineDatum(owner_in_datum_1),
    )
  let tx =
    fixture.tx(
      [sc_in_1, seller_in_1],
      [refer_in_1],
      [exchange_out_1, seller_out_1, owner_out_1],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  sell.spending(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    sc_in_datum_1,
    [],
  )
}

test fail_unsafe_fee_datum() fail {
  let time_of_tx = 1681095094000
  let cfg = get_config_making_mainnet()
  let owner_address = get_owner_address()
  let seller_address = get_seller_address()
  let owner_in_datum_1 = gen_ask_making_datum(owner_address, 499)
  let sc_in_datum_1 = gen_bid_making_datum(owner_address, 390, 480, 5, 500)
  // sc address that will be used to continue to make ask order
  let revert_address = from_script(sc_in_datum_1.ask_sc)
  let bond_name_1 = get_bond_id_1()
  let escrow_bond_amount = 10000
  let escrow_epo_rewards = 753424657
  let escrow_duration = 72
  let escrow_datum =
    get_escrow_datum(
      bond_name_1,
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
    bond_utils.get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  //  
  let bond_sell_qty = 5
  let received_at_maturity = escrow_full_info.value_at_maturity * bond_sell_qty
  let received_with_yield = price_of_one_bond * bond_sell_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.taker_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.maker_fee / cfg.platform.basis.base
  //
  let owner_out_lovelace = 1310316
  let sc_address = get_bid_sc_address()
  let sc_in_lovelace =
    received_with_yield + exchange_fee_buyer + owner_out_lovelace
  let sc_in_1 =
    gen_input(sc_address, sc_in_lovelace, None, InlineDatum(sc_in_datum_1))
  let seller_in_lovelace = 1310316
  let asset_sell =
    value.from_asset(get_bond_policy_id(), bond_name_1, bond_sell_qty)
  let seller_in_1 =
    gen_input(seller_address, seller_in_lovelace, Some(asset_sell), NoDatum)
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_1,
      1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  //
  let exchange_address = get_exchange_address()
  let exchange_out_lovelace = exchange_fee_buyer + exchange_fee_seller
  let exchange_out_1 =
    gen_output(
      exchange_address,
      exchange_out_lovelace,
      None,
      DatumHash("arbitrary_digest"),
    )
  let seller_out_lovelace =
    seller_in_lovelace + received_with_yield - exchange_fee_seller
  let seller_out_1 =
    gen_output(seller_address, seller_out_lovelace, None, NoDatum)
  let owner_out_1 =
    gen_output(
      revert_address,
      owner_out_lovelace,
      Some(asset_sell),
      InlineDatum(owner_in_datum_1),
    )
  let tx =
    fixture.tx(
      [sc_in_1, seller_in_1],
      [refer_in_1],
      [exchange_out_1, seller_out_1, owner_out_1],
      // [exchange_out_1, seller_out_1, owner_out_1, sc_out_utxo],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  sell.spending(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    sc_in_datum_1,
    [],
  )
}
