// Bid Limit
use aiken/bytearray
use aiken/cbor
use aiken/dict
use aiken/string
use aiken/transaction.{
  InlineDatum, NoDatum, ScriptContext, ScriptPurpose, Spend, Transaction,
}
use aiken/transaction/value
use bond/limit_bid/sell
use bond/limit_bid/types.{Sell} as dtypes
use bond/types.{DanogoBond, OptimBond}
use bond/utils.{get_price_of_bond}
use bond/v2/fixture.{
  calc_escrow_full_info, gen_bid_limit_multi_datum, gen_input, gen_output,
  get_bid_sc_address, get_bond_id_1, get_bond_policy_id, get_buyer_address,
  get_buyer_address_hash, get_config_limit_mainnet, get_escrow_address,
  get_escrow_address_unexpect, get_escrow_datum, get_escrow_policy_id,
  get_exchange_address, get_input_escrow, get_not_bond_policy_id,
  get_not_escrow_policy_id, get_seller_address,
}

const min_ada = 2_000_000

fn script_purpose_compare(a: ScriptPurpose, b: ScriptPurpose) {
  bytearray.compare(
    cbor.diagnostic(a) |> string.to_bytearray,
    cbor.diagnostic(b) |> string.to_bytearray,
  )
}

test succ_full() {
  let time_of_tx = 1681095094000
  let cfg = get_config_limit_mainnet()
  let owner_address = get_buyer_address()
  let seller_address = get_seller_address()
  let sc_in_datum_1 =
    gen_bid_limit_multi_datum(
      owner_address,
      390,
      480,
      5,
      500,
      [DanogoBond, OptimBond],
    )
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
    get_price_of_bond(
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
    received_diff * cfg.exchange.seller_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.platform.basis.base
  //
  let owner_out_lovelace = min_ada
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
    gen_output(owner_address, owner_out_lovelace, Some(asset_sell), NoDatum)
  let txn =
    fixture.tx(
      [sc_in_1, seller_in_1],
      [refer_in_1],
      [exchange_out_1, seller_out_1, owner_out_1],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  let seller_receive = received_with_yield - exchange_fee_seller
  let tx =
    Transaction {
      ..txn,
      redeemers: dict.insert(
        txn.redeemers,
        Spend(sc_in_1.output_reference),
        Sell {
          exchange_fee: exchange_out_lovelace,
          seller_receive,
          offers: [(get_bond_policy_id(), bond_name_1, bond_sell_qty)],
          cont_idx: None,
        },
        script_purpose_compare,
      ),
    }
  sell.constraint(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    sc_in_datum_1,
    exchange_out_lovelace,
    seller_receive,
    [(get_bond_policy_id(), bond_name_1, bond_sell_qty)],
    None,
  )
}

test succ_partial() {
  let time_of_tx = 1681095094000
  let cfg = get_config_limit_mainnet()
  let owner_address = get_buyer_address()
  let seller_address = get_seller_address()
  let sc_in_datum_1 =
    gen_bid_limit_multi_datum(
      owner_address,
      390,
      480,
      5,
      500,
      [DanogoBond, OptimBond],
    )
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
    get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  //  
  let bond_sell_qty = 2
  let received_at_maturity = escrow_full_info.value_at_maturity * bond_sell_qty
  let received_with_yield = price_of_one_bond * bond_sell_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.seller_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.platform.basis.base
  //
  let owner_out_lovelace = min_ada
  let sc_address = get_bid_sc_address()
  let sc_in_lovelace = received_with_yield + exchange_fee_buyer + 10000000
  let sc_in_1 =
    gen_input(sc_address, sc_in_lovelace, None, InlineDatum(sc_in_datum_1))
  let seller_in_lovelace = min_ada
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
    gen_output(owner_address, owner_out_lovelace, Some(asset_sell), NoDatum)
  let sc_out_lovelace =
    sc_in_lovelace - received_with_yield - exchange_fee_buyer - owner_out_lovelace
  let sc_out_datum_1 =
    gen_bid_limit_multi_datum(
      owner_address,
      390,
      480,
      sc_in_datum_1.quantity - bond_sell_qty,
      500,
      [DanogoBond, OptimBond],
    )
  let sc_out_utxo =
    gen_output(sc_address, sc_out_lovelace, None, InlineDatum(sc_out_datum_1))
  let txn =
    fixture.tx(
      [sc_in_1, seller_in_1],
      [refer_in_1],
      [exchange_out_1, seller_out_1, owner_out_1, sc_out_utxo],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  let seller_receive = received_with_yield - exchange_fee_seller
  let tx =
    Transaction {
      ..txn,
      redeemers: dict.insert(
        txn.redeemers,
        Spend(sc_in_1.output_reference),
        Sell {
          exchange_fee: exchange_out_lovelace,
          seller_receive,
          offers: [(get_bond_policy_id(), bond_name_1, bond_sell_qty)],
          cont_idx: Some(3),
        },
        script_purpose_compare,
      ),
    }
  sell.constraint(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    sc_in_datum_1,
    exchange_out_lovelace,
    seller_receive,
    [(get_bond_policy_id(), bond_name_1, bond_sell_qty)],
    Some(3),
  )
}

test fail_input_epoch_1() fail {
  let time_of_tx = 1681095094000
  let cfg = get_config_limit_mainnet()
  let owner_address = get_buyer_address()
  let seller_address = get_seller_address()
  let sc_in_datum_1 =
    gen_bid_limit_multi_datum(
      owner_address,
      480,
      390,
      5,
      500,
      [DanogoBond, OptimBond],
    )
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
    get_price_of_bond(
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
    received_diff * cfg.exchange.seller_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.platform.basis.base
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
    gen_output(owner_address, owner_out_lovelace, Some(asset_sell), NoDatum)
  let sc_out_lovelace =
    sc_in_lovelace - received_with_yield - exchange_fee_buyer - owner_out_lovelace
  let sc_out_datum_1 =
    gen_bid_limit_multi_datum(
      owner_address,
      390,
      480,
      sc_in_datum_1.quantity - bond_sell_qty,
      500,
      [DanogoBond, OptimBond],
    )
  let sc_out_utxo =
    gen_output(sc_address, sc_out_lovelace, None, InlineDatum(sc_out_datum_1))
  let txn =
    fixture.tx(
      [sc_in_1, seller_in_1],
      [refer_in_1],
      [exchange_out_1, seller_out_1, owner_out_1, sc_out_utxo],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  let seller_receive = received_with_yield - exchange_fee_seller
  let tx =
    Transaction {
      ..txn,
      redeemers: dict.insert(
        txn.redeemers,
        Spend(sc_in_1.output_reference),
        Sell {
          exchange_fee: exchange_out_lovelace,
          seller_receive,
          offers: [(get_bond_policy_id(), bond_name_1, bond_sell_qty)],
          cont_idx: None,
        },
        script_purpose_compare,
      ),
    }
  sell.constraint(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    sc_in_datum_1,
    exchange_out_lovelace,
    seller_receive,
    [(get_bond_policy_id(), bond_name_1, bond_sell_qty)],
    Some(3),
  )
}

test fail_input_epoch_2() fail {
  let time_of_tx = 1681095094000
  let cfg = get_config_limit_mainnet()
  let owner_address = get_buyer_address()
  let seller_address = get_seller_address()
  let sc_in_datum_1 =
    gen_bid_limit_multi_datum(
      owner_address,
      464,
      480,
      5,
      500,
      [DanogoBond, OptimBond],
    )
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
    get_price_of_bond(
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
    received_diff * cfg.exchange.seller_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.platform.basis.base
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
    gen_output(owner_address, owner_out_lovelace, Some(asset_sell), NoDatum)
  let sc_out_lovelace =
    sc_in_lovelace - received_with_yield - exchange_fee_buyer - owner_out_lovelace
  let sc_out_datum_1 =
    gen_bid_limit_multi_datum(
      owner_address,
      390,
      480,
      sc_in_datum_1.quantity - bond_sell_qty,
      500,
      [DanogoBond, OptimBond],
    )
  let sc_out_utxo =
    gen_output(sc_address, sc_out_lovelace, None, InlineDatum(sc_out_datum_1))
  let txn =
    fixture.tx(
      [sc_in_1, seller_in_1],
      [refer_in_1],
      [exchange_out_1, seller_out_1, owner_out_1, sc_out_utxo],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  let seller_receive = received_with_yield - exchange_fee_seller
  let tx =
    Transaction {
      ..txn,
      redeemers: dict.insert(
        txn.redeemers,
        Spend(sc_in_1.output_reference),
        Sell {
          exchange_fee: exchange_out_lovelace,
          seller_receive,
          offers: [(get_bond_policy_id(), bond_name_1, bond_sell_qty)],
          cont_idx: None,
        },
        script_purpose_compare,
      ),
    }
  sell.constraint(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    sc_in_datum_1,
    exchange_out_lovelace,
    seller_receive,
    [(get_bond_policy_id(), bond_name_1, bond_sell_qty)],
    Some(3),
  )
}

test fail_input_epoch_3() fail {
  let time_of_tx = 1681095094000
  let cfg = get_config_limit_mainnet()
  let owner_address = get_buyer_address()
  let seller_address = get_seller_address()
  let sc_in_datum_1 =
    gen_bid_limit_multi_datum(
      owner_address,
      390,
      462,
      5,
      500,
      [DanogoBond, OptimBond],
    )
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
    get_price_of_bond(
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
    received_diff * cfg.exchange.seller_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.platform.basis.base
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
    gen_output(owner_address, owner_out_lovelace, Some(asset_sell), NoDatum)
  let sc_out_lovelace =
    sc_in_lovelace - received_with_yield - exchange_fee_buyer - owner_out_lovelace
  let sc_out_datum_1 =
    gen_bid_limit_multi_datum(
      owner_address,
      390,
      480,
      sc_in_datum_1.quantity - bond_sell_qty,
      500,
      [DanogoBond, OptimBond],
    )
  let sc_out_utxo =
    gen_output(sc_address, sc_out_lovelace, None, InlineDatum(sc_out_datum_1))
  let txn =
    fixture.tx(
      [sc_in_1, seller_in_1],
      [refer_in_1],
      [exchange_out_1, seller_out_1, owner_out_1, sc_out_utxo],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  let seller_receive = received_with_yield - exchange_fee_seller
  let tx =
    Transaction {
      ..txn,
      redeemers: dict.insert(
        txn.redeemers,
        Spend(sc_in_1.output_reference),
        Sell {
          exchange_fee: exchange_out_lovelace,
          seller_receive,
          offers: [(get_bond_policy_id(), bond_name_1, bond_sell_qty)],
          cont_idx: None,
        },
        script_purpose_compare,
      ),
    }
  sell.constraint(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    sc_in_datum_1,
    exchange_out_lovelace,
    seller_receive,
    [(get_bond_policy_id(), bond_name_1, bond_sell_qty)],
    Some(3),
  )
}

test fail_input_epoch_4() fail {
  let time_of_tx = 1681095094000 + 25920000000
  let cfg = get_config_limit_mainnet()
  let owner_address = get_buyer_address()
  let seller_address = get_seller_address()
  let sc_in_datum_1 =
    gen_bid_limit_multi_datum(
      owner_address,
      390,
      462,
      5,
      500,
      [DanogoBond, OptimBond],
    )
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
    get_price_of_bond(
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
    received_diff * cfg.exchange.seller_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.platform.basis.base
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
    gen_output(owner_address, owner_out_lovelace, Some(asset_sell), NoDatum)
  let sc_out_lovelace =
    sc_in_lovelace - received_with_yield - exchange_fee_buyer - owner_out_lovelace
  let sc_out_datum_1 =
    gen_bid_limit_multi_datum(
      owner_address,
      390,
      480,
      sc_in_datum_1.quantity - bond_sell_qty,
      500,
      [DanogoBond, OptimBond],
    )
  let sc_out_utxo =
    gen_output(sc_address, sc_out_lovelace, None, InlineDatum(sc_out_datum_1))
  let txn =
    fixture.tx(
      [sc_in_1, seller_in_1],
      [refer_in_1],
      [exchange_out_1, seller_out_1, owner_out_1, sc_out_utxo],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  let seller_receive = received_with_yield - exchange_fee_seller
  let tx =
    Transaction {
      ..txn,
      redeemers: dict.insert(
        txn.redeemers,
        Spend(sc_in_1.output_reference),
        Sell {
          exchange_fee: exchange_out_lovelace,
          seller_receive,
          offers: [(get_bond_policy_id(), bond_name_1, bond_sell_qty)],
          cont_idx: None,
        },
        script_purpose_compare,
      ),
    }
  sell.constraint(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    sc_in_datum_1,
    exchange_out_lovelace,
    seller_receive,
    [(get_bond_policy_id(), bond_name_1, bond_sell_qty)],
    Some(3),
  )
}

test fail_input_qty() fail {
  let time_of_tx = 1681095094000
  let cfg = get_config_limit_mainnet()
  let owner_address = get_buyer_address()
  let seller_address = get_seller_address()
  let sc_in_datum_1 =
    gen_bid_limit_multi_datum(
      owner_address,
      390,
      480,
      0,
      500,
      [DanogoBond, OptimBond],
    )
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
    get_price_of_bond(
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
    received_diff * cfg.exchange.seller_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.platform.basis.base
  //
  let owner_out_lovelace = min_ada
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
    gen_output(owner_address, owner_out_lovelace, Some(asset_sell), NoDatum)
  let sc_out_lovelace =
    sc_in_lovelace - received_with_yield - exchange_fee_buyer - owner_out_lovelace
  let sc_out_datum_1 =
    gen_bid_limit_multi_datum(
      owner_address,
      390,
      480,
      sc_in_datum_1.quantity - bond_sell_qty,
      500,
      [DanogoBond, OptimBond],
    )
  let sc_out_utxo =
    gen_output(sc_address, sc_out_lovelace, None, InlineDatum(sc_out_datum_1))
  let txn =
    fixture.tx(
      [sc_in_1, seller_in_1],
      [refer_in_1],
      [exchange_out_1, seller_out_1, owner_out_1, sc_out_utxo],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  let seller_receive = received_with_yield - exchange_fee_seller
  let tx =
    Transaction {
      ..txn,
      redeemers: dict.insert(
        txn.redeemers,
        Spend(sc_in_1.output_reference),
        Sell {
          exchange_fee: exchange_out_lovelace,
          seller_receive,
          offers: [(get_bond_policy_id(), bond_name_1, bond_sell_qty)],
          cont_idx: Some(3),
        },
        script_purpose_compare,
      ),
    }
  sell.constraint(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    sc_in_datum_1,
    exchange_out_lovelace,
    seller_receive,
    [(get_bond_policy_id(), bond_name_1, bond_sell_qty)],
    Some(3),
  )
}

test fail_output_qty() {
  let time_of_tx = 1681095094000
  let cfg = get_config_limit_mainnet()
  let owner_address = get_buyer_address()
  let seller_address = get_seller_address()
  let sc_in_datum_1 =
    gen_bid_limit_multi_datum(
      owner_address,
      390,
      480,
      5,
      500,
      [DanogoBond, OptimBond],
    )
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
    get_price_of_bond(
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
    received_diff * cfg.exchange.seller_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.platform.basis.base
  //
  let owner_out_lovelace = min_ada
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
    gen_output(owner_address, owner_out_lovelace, Some(asset_sell), NoDatum)
  let sc_out_lovelace =
    sc_in_lovelace - received_with_yield - exchange_fee_buyer - owner_out_lovelace
  let sc_out_datum_1 =
    gen_bid_limit_multi_datum(
      owner_address,
      390,
      480,
      4,
      500,
      [DanogoBond, OptimBond],
    )
  let sc_out_utxo =
    gen_output(sc_address, sc_out_lovelace, None, InlineDatum(sc_out_datum_1))
  let txn =
    fixture.tx(
      [sc_in_1, seller_in_1],
      [refer_in_1],
      [exchange_out_1, seller_out_1, owner_out_1, sc_out_utxo],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  let seller_receive = received_with_yield - exchange_fee_seller
  let tx =
    Transaction {
      ..txn,
      redeemers: dict.insert(
        txn.redeemers,
        Spend(sc_in_1.output_reference),
        Sell {
          exchange_fee: exchange_out_lovelace,
          seller_receive,
          offers: [(get_bond_policy_id(), bond_name_1, bond_sell_qty)],
          cont_idx: Some(3),
        },
        script_purpose_compare,
      ),
    }
  sell.constraint(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    sc_in_datum_1,
    exchange_out_lovelace,
    seller_receive,
    [(get_bond_policy_id(), bond_name_1, bond_sell_qty)],
    Some(3),
  )
}

test fail_validity_after_not_set() fail {
  let time_of_tx = 1681095094000
  let cfg = get_config_limit_mainnet()
  let owner_address = get_buyer_address()
  let seller_address = get_seller_address()
  let sc_in_datum_1 =
    gen_bid_limit_multi_datum(
      owner_address,
      390,
      480,
      5,
      500,
      [DanogoBond, OptimBond],
    )
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
    get_price_of_bond(
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
    received_diff * cfg.exchange.seller_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.platform.basis.base
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
    gen_output(owner_address, owner_out_lovelace, Some(asset_sell), NoDatum)
  let sc_out_lovelace =
    sc_in_lovelace - received_with_yield - exchange_fee_buyer - owner_out_lovelace
  let sc_out_datum_1 =
    gen_bid_limit_multi_datum(
      owner_address,
      390,
      480,
      sc_in_datum_1.quantity - bond_sell_qty,
      500,
      [DanogoBond, OptimBond],
    )
  let sc_out_utxo =
    gen_output(sc_address, sc_out_lovelace, None, InlineDatum(sc_out_datum_1))
  let txn =
    fixture.tx(
      [sc_in_1, seller_in_1],
      [refer_in_1],
      [exchange_out_1, seller_out_1, owner_out_1, sc_out_utxo],
      Some([get_buyer_address_hash()]),
      None,
      None,
      None,
    )
  let seller_receive = received_with_yield - exchange_fee_seller
  let tx =
    Transaction {
      ..txn,
      redeemers: dict.insert(
        txn.redeemers,
        Spend(sc_in_1.output_reference),
        Sell {
          exchange_fee: exchange_out_lovelace,
          seller_receive,
          offers: [(get_bond_policy_id(), bond_name_1, bond_sell_qty)],
          cont_idx: None,
        },
        script_purpose_compare,
      ),
    }
  sell.constraint(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    sc_in_datum_1,
    exchange_out_lovelace,
    seller_receive,
    [(get_bond_policy_id(), bond_name_1, bond_sell_qty)],
    Some(3),
  )
}

test fail_escrow_policy_id_unexpect() fail {
  let time_of_tx = 1681095094000
  let cfg = get_config_limit_mainnet()
  let owner_address = get_buyer_address()
  let seller_address = get_seller_address()
  let sc_in_datum_1 =
    gen_bid_limit_multi_datum(
      owner_address,
      390,
      480,
      5,
      500,
      [DanogoBond, OptimBond],
    )
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
    get_price_of_bond(
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
    received_diff * cfg.exchange.seller_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.platform.basis.base
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
      get_not_escrow_policy_id(),
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
    gen_output(owner_address, owner_out_lovelace, Some(asset_sell), NoDatum)
  let sc_out_lovelace =
    sc_in_lovelace - received_with_yield - exchange_fee_buyer - owner_out_lovelace
  let sc_out_datum_1 =
    gen_bid_limit_multi_datum(
      owner_address,
      390,
      480,
      sc_in_datum_1.quantity - bond_sell_qty,
      500,
      [DanogoBond, OptimBond],
    )
  let sc_out_utxo =
    gen_output(sc_address, sc_out_lovelace, None, InlineDatum(sc_out_datum_1))
  let txn =
    fixture.tx(
      [sc_in_1, seller_in_1],
      [refer_in_1],
      [exchange_out_1, seller_out_1, owner_out_1, sc_out_utxo],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  let seller_receive = received_with_yield - exchange_fee_seller
  let tx =
    Transaction {
      ..txn,
      redeemers: dict.insert(
        txn.redeemers,
        Spend(sc_in_1.output_reference),
        Sell {
          exchange_fee: exchange_out_lovelace,
          seller_receive,
          offers: [(get_bond_policy_id(), bond_name_1, bond_sell_qty)],
          cont_idx: None,
        },
        script_purpose_compare,
      ),
    }
  sell.constraint(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    sc_in_datum_1,
    exchange_out_lovelace,
    seller_receive,
    [(get_bond_policy_id(), bond_name_1, bond_sell_qty)],
    Some(3),
  )
}

test fail_escrow_address_unexpect() fail {
  let time_of_tx = 1681095094000
  let cfg = get_config_limit_mainnet()
  let owner_address = get_buyer_address()
  let seller_address = get_seller_address()
  let sc_in_datum_1 =
    gen_bid_limit_multi_datum(
      owner_address,
      390,
      480,
      5,
      500,
      [DanogoBond, OptimBond],
    )
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
    get_price_of_bond(
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
    received_diff * cfg.exchange.seller_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.platform.basis.base
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
      get_escrow_address_unexpect(),
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
    gen_output(owner_address, owner_out_lovelace, Some(asset_sell), NoDatum)
  let sc_out_lovelace =
    sc_in_lovelace - received_with_yield - exchange_fee_buyer - owner_out_lovelace
  let sc_out_datum_1 =
    gen_bid_limit_multi_datum(
      owner_address,
      390,
      480,
      sc_in_datum_1.quantity - bond_sell_qty,
      500,
      [DanogoBond, OptimBond],
    )
  let sc_out_utxo =
    gen_output(sc_address, sc_out_lovelace, None, InlineDatum(sc_out_datum_1))
  let txn =
    fixture.tx(
      [sc_in_1, seller_in_1],
      [refer_in_1],
      [exchange_out_1, seller_out_1, owner_out_1, sc_out_utxo],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  let seller_receive = received_with_yield - exchange_fee_seller
  let tx =
    Transaction {
      ..txn,
      redeemers: dict.insert(
        txn.redeemers,
        Spend(sc_in_1.output_reference),
        Sell {
          exchange_fee: exchange_out_lovelace,
          seller_receive,
          offers: [(get_bond_policy_id(), bond_name_1, bond_sell_qty)],
          cont_idx: None,
        },
        script_purpose_compare,
      ),
    }
  sell.constraint(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    sc_in_datum_1,
    exchange_out_lovelace,
    seller_receive,
    [(get_bond_policy_id(), bond_name_1, bond_sell_qty)],
    Some(3),
  )
}

test fail_escrow_datum_not_found() fail {
  let time_of_tx = 1681095094000
  let cfg = get_config_limit_mainnet()
  let owner_address = get_buyer_address()
  let seller_address = get_seller_address()
  let sc_in_datum_1 =
    gen_bid_limit_multi_datum(
      owner_address,
      390,
      480,
      5,
      500,
      [DanogoBond, OptimBond],
    )
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
    get_price_of_bond(
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
    received_diff * cfg.exchange.seller_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.platform.basis.base
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
      NoDatum,
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
    gen_output(owner_address, owner_out_lovelace, Some(asset_sell), NoDatum)
  let sc_out_lovelace =
    sc_in_lovelace - received_with_yield - exchange_fee_buyer - owner_out_lovelace
  let sc_out_datum_1 =
    gen_bid_limit_multi_datum(
      owner_address,
      390,
      480,
      sc_in_datum_1.quantity - bond_sell_qty,
      500,
      [DanogoBond, OptimBond],
    )
  let sc_out_utxo =
    gen_output(sc_address, sc_out_lovelace, None, InlineDatum(sc_out_datum_1))
  let txn =
    fixture.tx(
      [sc_in_1, seller_in_1],
      [refer_in_1],
      [exchange_out_1, seller_out_1, owner_out_1, sc_out_utxo],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  let seller_receive = received_with_yield - exchange_fee_seller
  let tx =
    Transaction {
      ..txn,
      redeemers: dict.insert(
        txn.redeemers,
        Spend(sc_in_1.output_reference),
        Sell {
          exchange_fee: exchange_out_lovelace,
          seller_receive,
          offers: [(get_bond_policy_id(), bond_name_1, bond_sell_qty)],
          cont_idx: None,
        },
        script_purpose_compare,
      ),
    }
  sell.constraint(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    sc_in_datum_1,
    exchange_out_lovelace,
    seller_receive,
    [(get_bond_policy_id(), bond_name_1, bond_sell_qty)],
    Some(3),
  )
}

test fail_escrow_datum_unexpect() fail {
  let time_of_tx = 1681095094000
  let cfg = get_config_limit_mainnet()
  let owner_address = get_buyer_address()
  let seller_address = get_seller_address()
  let sc_in_datum_1 =
    gen_bid_limit_multi_datum(
      owner_address,
      390,
      480,
      5,
      500,
      [DanogoBond, OptimBond],
    )
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
    get_price_of_bond(
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
    received_diff * cfg.exchange.seller_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.platform.basis.base
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
      InlineDatum(sc_in_datum_1),
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
    gen_output(owner_address, owner_out_lovelace, Some(asset_sell), NoDatum)
  let sc_out_lovelace =
    sc_in_lovelace - received_with_yield - exchange_fee_buyer - owner_out_lovelace
  let sc_out_datum_1 =
    gen_bid_limit_multi_datum(
      owner_address,
      390,
      480,
      sc_in_datum_1.quantity - bond_sell_qty,
      500,
      [DanogoBond, OptimBond],
    )
  let sc_out_utxo =
    gen_output(sc_address, sc_out_lovelace, None, InlineDatum(sc_out_datum_1))
  let txn =
    fixture.tx(
      [sc_in_1, seller_in_1],
      [refer_in_1],
      [exchange_out_1, seller_out_1, owner_out_1, sc_out_utxo],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  let seller_receive = received_with_yield - exchange_fee_seller
  let tx =
    Transaction {
      ..txn,
      redeemers: dict.insert(
        txn.redeemers,
        Spend(sc_in_1.output_reference),
        Sell {
          exchange_fee: exchange_out_lovelace,
          seller_receive,
          offers: [(get_bond_policy_id(), bond_name_1, bond_sell_qty)],
          cont_idx: None,
        },
        script_purpose_compare,
      ),
    }
  sell.constraint(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    sc_in_datum_1,
    exchange_out_lovelace,
    seller_receive,
    [(get_bond_policy_id(), bond_name_1, bond_sell_qty)],
    Some(3),
  )
}

test succ_bond_policy_id_valid() {
  let time_of_tx = 1681095094000
  let cfg = get_config_limit_mainnet()
  let owner_address = get_buyer_address()
  let seller_address = get_seller_address()
  let sc_in_datum_1 =
    gen_bid_limit_multi_datum(
      owner_address,
      390,
      480,
      5,
      500,
      [DanogoBond, OptimBond],
    )
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
    get_price_of_bond(
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
    received_diff * cfg.exchange.seller_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.platform.basis.base
  //
  let owner_out_lovelace = min_ada
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
    gen_output(owner_address, owner_out_lovelace, Some(asset_sell), NoDatum)
  let txn =
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
  let seller_receive = received_with_yield - exchange_fee_seller
  let tx =
    Transaction {
      ..txn,
      redeemers: dict.insert(
        txn.redeemers,
        Spend(sc_in_1.output_reference),
        Sell {
          exchange_fee: exchange_out_lovelace,
          seller_receive,
          offers: [(get_bond_policy_id(), bond_name_1, bond_sell_qty)],
          cont_idx: None,
        },
        script_purpose_compare,
      ),
    }
  sell.constraint(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    sc_in_datum_1,
    exchange_out_lovelace,
    seller_receive,
    [(get_bond_policy_id(), bond_name_1, bond_sell_qty)],
    None,
  )
}

test fail_bond_policy_id_invalid() {
  let time_of_tx = 1681095094000
  let cfg = get_config_limit_mainnet()
  let owner_address = get_buyer_address()
  let seller_address = get_seller_address()
  let sc_in_datum_1 =
    gen_bid_limit_multi_datum(
      owner_address,
      390,
      480,
      5,
      500,
      [DanogoBond, OptimBond],
    )
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
    get_price_of_bond(
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
    received_diff * cfg.exchange.seller_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.platform.basis.base
  //
  let owner_out_lovelace = min_ada
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
    gen_output(owner_address, owner_out_lovelace, Some(asset_sell), NoDatum)
  let sc_out_lovelace =
    sc_in_lovelace - received_with_yield - exchange_fee_buyer - owner_out_lovelace
  let sc_out_datum_1 =
    gen_bid_limit_multi_datum(
      owner_address,
      390,
      480,
      sc_in_datum_1.quantity - bond_sell_qty,
      500,
      [DanogoBond, OptimBond],
    )
  let sc_out_utxo =
    gen_output(sc_address, sc_out_lovelace, None, InlineDatum(sc_out_datum_1))
  let txn =
    fixture.tx(
      [sc_in_1, seller_in_1],
      [refer_in_1],
      [exchange_out_1, seller_out_1, owner_out_1, sc_out_utxo],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  let seller_receive = received_with_yield - exchange_fee_seller
  let tx =
    Transaction {
      ..txn,
      redeemers: dict.insert(
        txn.redeemers,
        Spend(sc_in_1.output_reference),
        Sell {
          exchange_fee: exchange_out_lovelace,
          seller_receive,
          offers: [(get_bond_policy_id(), bond_name_1, bond_sell_qty)],
          cont_idx: Some(3),
        },
        script_purpose_compare,
      ),
    }
  !sell.constraint(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    sc_in_datum_1,
    exchange_out_lovelace,
    seller_receive,
    [(get_bond_policy_id(), bond_name_1, bond_sell_qty)],
    Some(3),
  )
}
