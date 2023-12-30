// Bid Making
use aiken/builtin
// use aiken/cbor
use aiken/dict
use aiken/transaction.{InlineDatum, NoDatum, Spend, Transaction}
use aiken/transaction/credential.{Address}
use aiken/transaction/value
use bond/making_bid/utils
use bond/types.{GarbageCollector}
// use bond/types.{Buy, GarbageCollector, Sell, Update, Upgrade}
use bond/utils as bond_utils
use bond/v2/fixture.{
  calc_escrow_full_info, gen_ask_making_datum, gen_bid_making_datum, gen_input,
  gen_output, get_bid_sc_address, get_bond_id_1, get_bond_policy_id,
  get_buyer_address, get_buyer_address_hash, get_config_making_mainnet,
  get_escrow_address, get_escrow_datum, get_escrow_policy_id,
  get_exchange_address, get_garbage_address, get_input_escrow,
  get_seller_address,
}

const owner_stake_key = "owner_stake"

fn get_owner_address() -> Address {
  let seller_addr = get_buyer_address()
  if owner_stake_key != "" {
    seller_addr |> credential.with_delegation_key(owner_stake_key)
  } else {
    seller_addr
  }
}

fn get_revert_address(k: ByteArray) -> Address {
  let revert_addr = credential.from_script(k)
  if owner_stake_key != "" {
    revert_addr |> credential.with_delegation_key(owner_stake_key)
  } else {
    revert_addr
  }
}

test succ_bid_making() {
  let time_of_tx = 1681095094000
  let cfg = get_config_making_mainnet()
  let owner_address = get_owner_address()
  let owner_in_datum_1 = gen_ask_making_datum(owner_address, 499)
  // trace cbor.diagnostic(Update)
  // trace cbor.diagnostic(Buy)
  // trace cbor.diagnostic(Sell)
  // trace cbor.diagnostic(Upgrade)
  // trace cbor.diagnostic(GarbageCollector)
  let sc_in_datum_1 = gen_bid_making_datum(owner_address, 390, 480, 5, 500)
  let bond_name_1 = get_bond_id_1()
  // get_escrow_datum(asset_name: AssetName, bond_amount: Int, epo_rewards: Int, duration: Int, start: Int)
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
  let exchange_fee_buyer =
    received_diff * cfg.exchange.maker_fee / cfg.platform.basis.base
  //
  let owner_out_lovelace = 1310316
  let sc_address = get_bid_sc_address()
  let sc_in_lovelace =
    received_with_yield + exchange_fee_buyer + owner_out_lovelace
  let sc_in_1 =
    gen_input(sc_address, sc_in_lovelace, None, InlineDatum(sc_in_datum_1))
  //
  let garbage_address = get_garbage_address()
  let garbage_out_lovelace = sc_in_lovelace
  let garbage_out_1 =
    gen_output(garbage_address, garbage_out_lovelace, None, NoDatum)
  let (i, l) = builtin.un_constr_data(GarbageCollector)
  let tx =
    Transaction {
      ..fixture.tx(
        [sc_in_1],
        [],
        [garbage_out_1],
        Some([get_buyer_address_hash()]),
        None,
        Some(time_of_tx),
        Some(time_of_tx + 3 * 60 * 1000),
      ),
      redeemers: dict.new()
        |> dict.insert(
             Spend(sc_in_1.output_reference),
             builtin.constr_data(i, l),
             fn(_, _) { Less },
           ),
    }
  // trace cbor.diagnostic(owner_in_datum_1)
  utils.garbage_collector(owner_in_datum_1, tx, cfg)
}

test fail_bid_making_invalid_garbage_value() {
  let time_of_tx = 1681095094000
  let cfg = get_config_making_mainnet()
  let owner_address = get_owner_address()
  let owner_in_datum_1 = gen_ask_making_datum(owner_address, 499)
  // trace cbor.diagnostic(builtin.un_constr_data(Update))
  // trace cbor.diagnostic(builtin.constr_data(0, [Update]))
  // trace cbor.diagnostic(Update)
  // trace cbor.diagnostic(Buy)
  // trace cbor.diagnostic(Sell)
  // trace cbor.diagnostic(Upgrade)
  // trace cbor.diagnostic(GarbageCollector)
  let sc_in_datum_1 = gen_bid_making_datum(owner_address, 390, 480, 5, 500)
  let bond_name_1 = get_bond_id_1()
  // get_escrow_datum(asset_name: AssetName, bond_amount: Int, epo_rewards: Int, duration: Int, start: Int)
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
  let exchange_fee_buyer =
    received_diff * cfg.exchange.maker_fee / cfg.platform.basis.base
  //
  let owner_out_lovelace = 1310316
  let sc_address = get_bid_sc_address()
  let sc_in_lovelace =
    received_with_yield + exchange_fee_buyer + owner_out_lovelace
  let sc_in_1 =
    gen_input(sc_address, sc_in_lovelace, None, InlineDatum(sc_in_datum_1))
  //
  let garbage_address = get_garbage_address()
  let garbage_out_lovelace = sc_in_lovelace
  let garbage_out_1 =
    gen_output(garbage_address, garbage_out_lovelace - 1, None, NoDatum)
  let (i, l) = builtin.un_constr_data(GarbageCollector)
  let tx =
    Transaction {
      ..fixture.tx(
        [sc_in_1],
        [],
        [garbage_out_1],
        Some([get_buyer_address_hash()]),
        None,
        Some(time_of_tx),
        Some(time_of_tx + 3 * 60 * 1000),
      ),
      redeemers: dict.new()
        |> dict.insert(
             Spend(sc_in_1.output_reference),
             builtin.constr_data(i, l),
             fn(_, _) { Less },
           ),
    }
  // trace cbor.diagnostic(owner_in_datum_1)
  !utils.garbage_collector(owner_in_datum_1, tx, cfg)
}

test fail_bid_making_datum_valid() fail {
  let time_of_tx = 1681095094000
  let cfg = get_config_making_mainnet()
  let owner_address = get_owner_address()
  // let owner_in_datum_1 = gen_ask_making_datum(owner_address, 499)
  // trace cbor.diagnostic(builtin.un_constr_data(Update))
  // trace cbor.diagnostic(builtin.constr_data(0, [Update]))
  // trace cbor.diagnostic(Update)
  // trace cbor.diagnostic(Buy)
  // trace cbor.diagnostic(Sell)
  // trace cbor.diagnostic(Upgrade)
  // trace cbor.diagnostic(GarbageCollector)
  let sc_in_datum_1 = gen_bid_making_datum(owner_address, 390, 480, 5, 500)
  let bond_name_1 = get_bond_id_1()
  // get_escrow_datum(asset_name: AssetName, bond_amount: Int, epo_rewards: Int, duration: Int, start: Int)
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
  let exchange_fee_buyer =
    received_diff * cfg.exchange.maker_fee / cfg.platform.basis.base
  //
  let owner_out_lovelace = 1310316
  let sc_address = get_bid_sc_address()
  let sc_in_lovelace =
    received_with_yield + exchange_fee_buyer + owner_out_lovelace
  let sc_in_1 =
    gen_input(sc_address, sc_in_lovelace, None, InlineDatum(sc_in_datum_1))
  //
  let garbage_address = get_garbage_address()
  let garbage_out_lovelace = sc_in_lovelace
  let garbage_out_1 =
    gen_output(garbage_address, garbage_out_lovelace, None, NoDatum)
  let (i, l) = builtin.un_constr_data(GarbageCollector)
  let tx =
    Transaction {
      ..fixture.tx(
        [sc_in_1],
        [],
        [garbage_out_1],
        Some([get_buyer_address_hash()]),
        None,
        Some(time_of_tx),
        Some(time_of_tx + 3 * 60 * 1000),
      ),
      redeemers: dict.new()
        |> dict.insert(
             Spend(sc_in_1.output_reference),
             builtin.constr_data(i, l),
             fn(_, _) { Less },
           ),
    }
  // trace cbor.diagnostic(sc_in_datum_1)
  !utils.garbage_collector(sc_in_datum_1, tx, cfg)
}

test fail_bid_making_not_found_garbage_output() fail {
  let time_of_tx = 1681095094000
  let cfg = get_config_making_mainnet()
  let owner_address = get_owner_address()
  let seller_address = get_seller_address()
  let owner_in_datum_1 = gen_ask_making_datum(owner_address, 499)
  let sc_in_datum_1 = gen_bid_making_datum(owner_address, 390, 480, 5, 500)
  // sc address that will be used to continue to make ask order
  let revert_address = get_revert_address(sc_in_datum_1.ask_sc)
  let bond_name_1 = get_bond_id_1()
  // get_escrow_datum(asset_name: AssetName, bond_amount: Int, epo_rewards: Int, duration: Int, start: Int)
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
  // trace cbor.diagnostic(owner_in_datum_1)
  !utils.garbage_collector(owner_in_datum_1, tx, cfg)
}
