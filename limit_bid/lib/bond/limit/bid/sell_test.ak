// Bid Limit
use aiken/transaction.{InlineDatum, NoDatum}
use aiken/transaction/value
use bond/fixture.{
  calc_escrow_full_info, gen_bid_limit_datum, gen_input, gen_output,
  get_bid_sc_address, get_bond_id_1, get_bond_policy_id, get_buyer_address,
  get_buyer_address_hash, get_buyer_address_scripthash, get_config_limit_mainnet,
  get_escrow_address, get_escrow_address_unexpect, get_escrow_datum,
  get_escrow_policy_id, get_exchange_address, get_input_escrow,
  get_not_bond_policy_id, get_not_escrow_policy_id, get_seller_address,
}
use bond/limit/bid/sell
use bond/utils.{get_price_of_bond}

test sell_succ_full() {
  let time_of_tx = 1681095094000
  let cfg = get_config_limit_mainnet()
  let owner_address = get_buyer_address()
  let seller_address = get_seller_address()
  let sc_in_datum_1 = gen_bid_limit_datum(owner_address, 390, 480, 5, 500)
  let bond_name_1 = get_bond_id_1()
  //
  let escrow_dt = get_escrow_datum(bond_name_1, 10000, 753424657, 72, 63)
  let escrow_lovelace = 1017328767112
  let escrow_full_info =
    calc_escrow_full_info(cfg.bond, escrow_lovelace, escrow_dt, time_of_tx)
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.bond.basis_points_ref_unit,
    )
  //  
  let bond_sell_qty = 5
  let received_at_maturity = escrow_full_info.value_at_maturity * bond_sell_qty
  let received_with_yield = price_of_one_bond * bond_sell_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.seller_fee / cfg.bond.basis_points_ref_unit
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.bond.basis_points_ref_unit
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
      InlineDatum(escrow_dt),
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
  // let sc_out_lovelace =
  //   sc_in_lovelace - received_with_yield - exchange_fee_buyer - owner_out_lovelace
  // let sc_out_datum_1 =
  //   gen_bid_limit_datum(
  //     owner_address,
  //     390,
  //     480,
  //     sc_in_datum_1.quantity - bond_sell_qty,
  //     500,
  //   )
  // let sc_out_utxo =
  //   gen_output(sc_address, sc_out_lovelace, None, InlineDatum(sc_out_datum_1))
  sell.matching(
    fixture.tx(
      [sc_in_1, seller_in_1],
      [refer_in_1],
      [exchange_out_1, seller_out_1, owner_out_1],
      // [exchange_out_1, seller_out_1, owner_out_1, sc_out_utxo],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    ),
    cfg,
    sc_in_datum_1,
    owner_address,
    sc_address,
  )
}

test sell_succ_partial() {
  let time_of_tx = 1681095094000
  let cfg = get_config_limit_mainnet()
  let owner_address = get_buyer_address()
  let seller_address = get_seller_address()
  let sc_in_datum_1 = gen_bid_limit_datum(owner_address, 390, 480, 5, 500)
  let bond_name_1 = get_bond_id_1()
  //
  let escrow_dt = get_escrow_datum(bond_name_1, 10000, 753424657, 72, 63)
  let escrow_lovelace = 1017328767112
  let escrow_full_info =
    calc_escrow_full_info(cfg.bond, escrow_lovelace, escrow_dt, time_of_tx)
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.bond.basis_points_ref_unit,
    )
  //  
  let bond_sell_qty = 2
  let received_at_maturity = escrow_full_info.value_at_maturity * bond_sell_qty
  let received_with_yield = price_of_one_bond * bond_sell_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.seller_fee / cfg.bond.basis_points_ref_unit
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.bond.basis_points_ref_unit
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
      InlineDatum(escrow_dt),
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
    gen_bid_limit_datum(
      owner_address,
      390,
      480,
      sc_in_datum_1.quantity - bond_sell_qty,
      500,
    )
  let sc_out_utxo =
    gen_output(sc_address, sc_out_lovelace, None, InlineDatum(sc_out_datum_1))
  sell.matching(
    fixture.tx(
      [sc_in_1, seller_in_1],
      [refer_in_1],
      [exchange_out_1, seller_out_1, owner_out_1, sc_out_utxo],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    ),
    cfg,
    sc_in_datum_1,
    owner_address,
    sc_address,
  )
}

test sell_fail_input_epoch_1() {
  let time_of_tx = 1681095094000
  let cfg = get_config_limit_mainnet()
  let owner_address = get_buyer_address()
  let seller_address = get_seller_address()
  let sc_in_datum_1 = gen_bid_limit_datum(owner_address, 480, 390, 5, 500)
  let bond_name_1 = get_bond_id_1()
  //
  let escrow_dt = get_escrow_datum(bond_name_1, 10000, 753424657, 72, 63)
  let escrow_lovelace = 1017328767112
  let escrow_full_info =
    calc_escrow_full_info(cfg.bond, escrow_lovelace, escrow_dt, time_of_tx)
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.bond.basis_points_ref_unit,
    )
  //  
  let bond_sell_qty = 5
  let received_at_maturity = escrow_full_info.value_at_maturity * bond_sell_qty
  let received_with_yield = price_of_one_bond * bond_sell_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.seller_fee / cfg.bond.basis_points_ref_unit
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.bond.basis_points_ref_unit
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
      InlineDatum(escrow_dt),
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
    gen_bid_limit_datum(
      owner_address,
      390,
      480,
      sc_in_datum_1.quantity - bond_sell_qty,
      500,
    )
  let sc_out_utxo =
    gen_output(sc_address, sc_out_lovelace, None, InlineDatum(sc_out_datum_1))
  !sell.matching(
    fixture.tx(
      [sc_in_1, seller_in_1],
      [refer_in_1],
      [exchange_out_1, seller_out_1, owner_out_1, sc_out_utxo],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    ),
    cfg,
    sc_in_datum_1,
    owner_address,
    sc_address,
  )
}

test sell_fail_input_epoch_2() {
  let time_of_tx = 1681095094000
  let cfg = get_config_limit_mainnet()
  let owner_address = get_buyer_address()
  let seller_address = get_seller_address()
  let sc_in_datum_1 = gen_bid_limit_datum(owner_address, 464, 480, 5, 500)
  let bond_name_1 = get_bond_id_1()
  //
  let escrow_dt = get_escrow_datum(bond_name_1, 10000, 753424657, 72, 63)
  let escrow_lovelace = 1017328767112
  let escrow_full_info =
    calc_escrow_full_info(cfg.bond, escrow_lovelace, escrow_dt, time_of_tx)
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.bond.basis_points_ref_unit,
    )
  //  
  let bond_sell_qty = 5
  let received_at_maturity = escrow_full_info.value_at_maturity * bond_sell_qty
  let received_with_yield = price_of_one_bond * bond_sell_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.seller_fee / cfg.bond.basis_points_ref_unit
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.bond.basis_points_ref_unit
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
      InlineDatum(escrow_dt),
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
    gen_bid_limit_datum(
      owner_address,
      390,
      480,
      sc_in_datum_1.quantity - bond_sell_qty,
      500,
    )
  let sc_out_utxo =
    gen_output(sc_address, sc_out_lovelace, None, InlineDatum(sc_out_datum_1))
  !sell.matching(
    fixture.tx(
      [sc_in_1, seller_in_1],
      [refer_in_1],
      [exchange_out_1, seller_out_1, owner_out_1, sc_out_utxo],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    ),
    cfg,
    sc_in_datum_1,
    owner_address,
    sc_address,
  )
  // let current_epoch =
  //   posix_time_to_relative_epoch(
  //     time_of_tx,
  //     cfg.bond.epoch_config,
  //   )
  // current_epoch = 404
  // let end_epoch =
  //   escrow_dt.start + cfg.bond.epoch_config.epoch_boundary_as_epoch + escrow_dt.duration
  // end_epoch = 463
  // sc_in_datum_1.from_epoch = 390
  // bid_limit_datum.to_epoch = 480
  // end_epoch == sc_in_datum_1.from_epoch
  // end_epoch == current_epoch
}

test sell_fail_input_epoch_3() {
  let time_of_tx = 1681095094000
  let cfg = get_config_limit_mainnet()
  let owner_address = get_buyer_address()
  let seller_address = get_seller_address()
  let sc_in_datum_1 = gen_bid_limit_datum(owner_address, 390, 462, 5, 500)
  let bond_name_1 = get_bond_id_1()
  //
  let escrow_dt = get_escrow_datum(bond_name_1, 10000, 753424657, 72, 63)
  let escrow_lovelace = 1017328767112
  let escrow_full_info =
    calc_escrow_full_info(cfg.bond, escrow_lovelace, escrow_dt, time_of_tx)
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.bond.basis_points_ref_unit,
    )
  //  
  let bond_sell_qty = 5
  let received_at_maturity = escrow_full_info.value_at_maturity * bond_sell_qty
  let received_with_yield = price_of_one_bond * bond_sell_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.seller_fee / cfg.bond.basis_points_ref_unit
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.bond.basis_points_ref_unit
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
      InlineDatum(escrow_dt),
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
    gen_bid_limit_datum(
      owner_address,
      390,
      480,
      sc_in_datum_1.quantity - bond_sell_qty,
      500,
    )
  let sc_out_utxo =
    gen_output(sc_address, sc_out_lovelace, None, InlineDatum(sc_out_datum_1))
  !sell.matching(
    fixture.tx(
      [sc_in_1, seller_in_1],
      [refer_in_1],
      [exchange_out_1, seller_out_1, owner_out_1, sc_out_utxo],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    ),
    cfg,
    sc_in_datum_1,
    owner_address,
    sc_address,
  )
}

test sell_fail_input_epoch_4() {
  let time_of_tx = 1681095094000 + 25920000000
  let cfg = get_config_limit_mainnet()
  let owner_address = get_buyer_address()
  let seller_address = get_seller_address()
  let sc_in_datum_1 = gen_bid_limit_datum(owner_address, 390, 462, 5, 500)
  let bond_name_1 = get_bond_id_1()
  //
  let escrow_dt = get_escrow_datum(bond_name_1, 10000, 753424657, 72, 63)
  let escrow_lovelace = 1017328767112
  let escrow_full_info =
    calc_escrow_full_info(cfg.bond, escrow_lovelace, escrow_dt, time_of_tx)
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.bond.basis_points_ref_unit,
    )
  //  
  let bond_sell_qty = 5
  let received_at_maturity = escrow_full_info.value_at_maturity * bond_sell_qty
  let received_with_yield = price_of_one_bond * bond_sell_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.seller_fee / cfg.bond.basis_points_ref_unit
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.bond.basis_points_ref_unit
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
      InlineDatum(escrow_dt),
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
    gen_bid_limit_datum(
      owner_address,
      390,
      480,
      sc_in_datum_1.quantity - bond_sell_qty,
      500,
    )
  let sc_out_utxo =
    gen_output(sc_address, sc_out_lovelace, None, InlineDatum(sc_out_datum_1))
  !sell.matching(
    fixture.tx(
      [sc_in_1, seller_in_1],
      [refer_in_1],
      [exchange_out_1, seller_out_1, owner_out_1, sc_out_utxo],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    ),
    cfg,
    sc_in_datum_1,
    owner_address,
    sc_address,
  )
  // let current_epoch =
  //   posix_time_to_relative_epoch(
  //     time_of_tx,
  //     cfg.bond.epoch_config,
  //   )
  // // current_epoch = 464
  // let end_epoch =
  //   escrow_dt.start + cfg.bond.epoch_config.epoch_boundary_as_epoch + escrow_dt.duration
  // // end_epoch = 463
  // current_epoch == end_epoch
}

test sell_fail_input_qty() {
  let time_of_tx = 1681095094000
  let cfg = get_config_limit_mainnet()
  let owner_address = get_buyer_address()
  let seller_address = get_seller_address()
  let sc_in_datum_1 = gen_bid_limit_datum(owner_address, 390, 480, 0, 500)
  let bond_name_1 = get_bond_id_1()
  //
  let escrow_dt = get_escrow_datum(bond_name_1, 10000, 753424657, 72, 63)
  let escrow_lovelace = 1017328767112
  let escrow_full_info =
    calc_escrow_full_info(cfg.bond, escrow_lovelace, escrow_dt, time_of_tx)
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.bond.basis_points_ref_unit,
    )
  //  
  let bond_sell_qty = 5
  let received_at_maturity = escrow_full_info.value_at_maturity * bond_sell_qty
  let received_with_yield = price_of_one_bond * bond_sell_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.seller_fee / cfg.bond.basis_points_ref_unit
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.bond.basis_points_ref_unit
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
      InlineDatum(escrow_dt),
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
    gen_bid_limit_datum(
      owner_address,
      390,
      480,
      sc_in_datum_1.quantity - bond_sell_qty,
      500,
    )
  let sc_out_utxo =
    gen_output(sc_address, sc_out_lovelace, None, InlineDatum(sc_out_datum_1))
  !sell.matching(
    fixture.tx(
      [sc_in_1, seller_in_1],
      [refer_in_1],
      [exchange_out_1, seller_out_1, owner_out_1, sc_out_utxo],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    ),
    cfg,
    sc_in_datum_1,
    owner_address,
    sc_address,
  )
}

test sell_fail_output_qty() {
  let time_of_tx = 1681095094000
  let cfg = get_config_limit_mainnet()
  let owner_address = get_buyer_address()
  let seller_address = get_seller_address()
  let sc_in_datum_1 = gen_bid_limit_datum(owner_address, 390, 480, 1, 500)
  let bond_name_1 = get_bond_id_1()
  //
  let escrow_dt = get_escrow_datum(bond_name_1, 10000, 753424657, 72, 63)
  let escrow_lovelace = 1017328767112
  let escrow_full_info =
    calc_escrow_full_info(cfg.bond, escrow_lovelace, escrow_dt, time_of_tx)
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.bond.basis_points_ref_unit,
    )
  //  
  let bond_sell_qty = 5
  let received_at_maturity = escrow_full_info.value_at_maturity * bond_sell_qty
  let received_with_yield = price_of_one_bond * bond_sell_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.seller_fee / cfg.bond.basis_points_ref_unit
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.bond.basis_points_ref_unit
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
      InlineDatum(escrow_dt),
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
    gen_bid_limit_datum(
      owner_address,
      390,
      480,
      sc_in_datum_1.quantity - bond_sell_qty,
      500,
    )
  let sc_out_utxo =
    gen_output(sc_address, sc_out_lovelace, None, InlineDatum(sc_out_datum_1))
  !sell.matching(
    fixture.tx(
      [sc_in_1, seller_in_1],
      [refer_in_1],
      [exchange_out_1, seller_out_1, owner_out_1, sc_out_utxo],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    ),
    cfg,
    sc_in_datum_1,
    owner_address,
    sc_address,
  )
}

test sell_fail_validity_after_not_set() {
  let time_of_tx = 1681095094000
  let cfg = get_config_limit_mainnet()
  let owner_address = get_buyer_address()
  let seller_address = get_seller_address()
  let sc_in_datum_1 = gen_bid_limit_datum(owner_address, 390, 480, 5, 500)
  let bond_name_1 = get_bond_id_1()
  //
  let escrow_dt = get_escrow_datum(bond_name_1, 10000, 753424657, 72, 63)
  let escrow_lovelace = 1017328767112
  let escrow_full_info =
    calc_escrow_full_info(cfg.bond, escrow_lovelace, escrow_dt, time_of_tx)
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.bond.basis_points_ref_unit,
    )
  //  
  let bond_sell_qty = 5
  let received_at_maturity = escrow_full_info.value_at_maturity * bond_sell_qty
  let received_with_yield = price_of_one_bond * bond_sell_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.seller_fee / cfg.bond.basis_points_ref_unit
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.bond.basis_points_ref_unit
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
      InlineDatum(escrow_dt),
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
    gen_bid_limit_datum(
      owner_address,
      390,
      480,
      sc_in_datum_1.quantity - bond_sell_qty,
      500,
    )
  let sc_out_utxo =
    gen_output(sc_address, sc_out_lovelace, None, InlineDatum(sc_out_datum_1))
  !sell.matching(
    fixture.tx(
      [sc_in_1, seller_in_1],
      [refer_in_1],
      [exchange_out_1, seller_out_1, owner_out_1, sc_out_utxo],
      Some([get_buyer_address_hash()]),
      None,
      None,
      None,
    ),
    cfg,
    sc_in_datum_1,
    owner_address,
    sc_address,
  )
}

test sell_fail_owner_address_format() {
  let time_of_tx = 1681095094000
  let cfg = get_config_limit_mainnet()
  let owner_address = get_buyer_address()
  let seller_address = get_seller_address()
  let sc_in_datum_1 = gen_bid_limit_datum(owner_address, 390, 480, 5, 500)
  let bond_name_1 = get_bond_id_1()
  //
  let escrow_dt = get_escrow_datum(bond_name_1, 10000, 753424657, 72, 63)
  let escrow_lovelace = 1017328767112
  let escrow_full_info =
    calc_escrow_full_info(cfg.bond, escrow_lovelace, escrow_dt, time_of_tx)
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.bond.basis_points_ref_unit,
    )
  //  
  let bond_sell_qty = 5
  let received_at_maturity = escrow_full_info.value_at_maturity * bond_sell_qty
  let received_with_yield = price_of_one_bond * bond_sell_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.seller_fee / cfg.bond.basis_points_ref_unit
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.bond.basis_points_ref_unit
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
      InlineDatum(escrow_dt),
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
    gen_bid_limit_datum(
      owner_address,
      390,
      480,
      sc_in_datum_1.quantity - bond_sell_qty,
      500,
    )
  let sc_out_utxo =
    gen_output(sc_address, sc_out_lovelace, None, InlineDatum(sc_out_datum_1))
  !sell.matching(
    fixture.tx(
      [sc_in_1, seller_in_1],
      [refer_in_1],
      [exchange_out_1, seller_out_1, owner_out_1, sc_out_utxo],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    ),
    cfg,
    sc_in_datum_1,
    get_buyer_address_scripthash(),
    sc_address,
  )
}

test sell_fail_escrow_policy_id_unexpect() {
  let time_of_tx = 1681095094000
  let cfg = get_config_limit_mainnet()
  let owner_address = get_buyer_address()
  let seller_address = get_seller_address()
  let sc_in_datum_1 = gen_bid_limit_datum(owner_address, 390, 480, 5, 500)
  let bond_name_1 = get_bond_id_1()
  //
  let escrow_dt = get_escrow_datum(bond_name_1, 10000, 753424657, 72, 63)
  let escrow_lovelace = 1017328767112
  let escrow_full_info =
    calc_escrow_full_info(cfg.bond, escrow_lovelace, escrow_dt, time_of_tx)
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.bond.basis_points_ref_unit,
    )
  //  
  let bond_sell_qty = 5
  let received_at_maturity = escrow_full_info.value_at_maturity * bond_sell_qty
  let received_with_yield = price_of_one_bond * bond_sell_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.seller_fee / cfg.bond.basis_points_ref_unit
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.bond.basis_points_ref_unit
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
      InlineDatum(escrow_dt),
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
    gen_bid_limit_datum(
      owner_address,
      390,
      480,
      sc_in_datum_1.quantity - bond_sell_qty,
      500,
    )
  let sc_out_utxo =
    gen_output(sc_address, sc_out_lovelace, None, InlineDatum(sc_out_datum_1))
  !sell.matching(
    fixture.tx(
      [sc_in_1, seller_in_1],
      [refer_in_1],
      [exchange_out_1, seller_out_1, owner_out_1, sc_out_utxo],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    ),
    cfg,
    sc_in_datum_1,
    owner_address,
    sc_address,
  )
}

test sell_fail_escrow_address_unexpect() {
  let time_of_tx = 1681095094000
  let cfg = get_config_limit_mainnet()
  let owner_address = get_buyer_address()
  let seller_address = get_seller_address()
  let sc_in_datum_1 = gen_bid_limit_datum(owner_address, 390, 480, 5, 500)
  let bond_name_1 = get_bond_id_1()
  //
  let escrow_dt = get_escrow_datum(bond_name_1, 10000, 753424657, 72, 63)
  let escrow_lovelace = 1017328767112
  let escrow_full_info =
    calc_escrow_full_info(cfg.bond, escrow_lovelace, escrow_dt, time_of_tx)
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.bond.basis_points_ref_unit,
    )
  //  
  let bond_sell_qty = 5
  let received_at_maturity = escrow_full_info.value_at_maturity * bond_sell_qty
  let received_with_yield = price_of_one_bond * bond_sell_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.seller_fee / cfg.bond.basis_points_ref_unit
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.bond.basis_points_ref_unit
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
      InlineDatum(escrow_dt),
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
    gen_bid_limit_datum(
      owner_address,
      390,
      480,
      sc_in_datum_1.quantity - bond_sell_qty,
      500,
    )
  let sc_out_utxo =
    gen_output(sc_address, sc_out_lovelace, None, InlineDatum(sc_out_datum_1))
  !sell.matching(
    fixture.tx(
      [sc_in_1, seller_in_1],
      [refer_in_1],
      [exchange_out_1, seller_out_1, owner_out_1, sc_out_utxo],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    ),
    cfg,
    sc_in_datum_1,
    owner_address,
    sc_address,
  )
}

test sell_fail_escrow_datum_not_found() {
  let time_of_tx = 1681095094000
  let cfg = get_config_limit_mainnet()
  let owner_address = get_buyer_address()
  let seller_address = get_seller_address()
  let sc_in_datum_1 = gen_bid_limit_datum(owner_address, 390, 480, 5, 500)
  let bond_name_1 = get_bond_id_1()
  //
  let escrow_dt = get_escrow_datum(bond_name_1, 10000, 753424657, 72, 63)
  let escrow_lovelace = 1017328767112
  let escrow_full_info =
    calc_escrow_full_info(cfg.bond, escrow_lovelace, escrow_dt, time_of_tx)
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.bond.basis_points_ref_unit,
    )
  //  
  let bond_sell_qty = 5
  let received_at_maturity = escrow_full_info.value_at_maturity * bond_sell_qty
  let received_with_yield = price_of_one_bond * bond_sell_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.seller_fee / cfg.bond.basis_points_ref_unit
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.bond.basis_points_ref_unit
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
    gen_bid_limit_datum(
      owner_address,
      390,
      480,
      sc_in_datum_1.quantity - bond_sell_qty,
      500,
    )
  let sc_out_utxo =
    gen_output(sc_address, sc_out_lovelace, None, InlineDatum(sc_out_datum_1))
  !sell.matching(
    fixture.tx(
      [sc_in_1, seller_in_1],
      [refer_in_1],
      [exchange_out_1, seller_out_1, owner_out_1, sc_out_utxo],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    ),
    cfg,
    sc_in_datum_1,
    owner_address,
    sc_address,
  )
}

test sell_fail_escrow_datum_unexpect() fail {
  let time_of_tx = 1681095094000
  let cfg = get_config_limit_mainnet()
  let owner_address = get_buyer_address()
  let seller_address = get_seller_address()
  let sc_in_datum_1 = gen_bid_limit_datum(owner_address, 390, 480, 5, 500)
  let bond_name_1 = get_bond_id_1()
  //
  let escrow_dt = get_escrow_datum(bond_name_1, 10000, 753424657, 72, 63)
  let escrow_lovelace = 1017328767112
  let escrow_full_info =
    calc_escrow_full_info(cfg.bond, escrow_lovelace, escrow_dt, time_of_tx)
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.bond.basis_points_ref_unit,
    )
  //  
  let bond_sell_qty = 5
  let received_at_maturity = escrow_full_info.value_at_maturity * bond_sell_qty
  let received_with_yield = price_of_one_bond * bond_sell_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.seller_fee / cfg.bond.basis_points_ref_unit
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.bond.basis_points_ref_unit
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
    gen_bid_limit_datum(
      owner_address,
      390,
      480,
      sc_in_datum_1.quantity - bond_sell_qty,
      500,
    )
  let sc_out_utxo =
    gen_output(sc_address, sc_out_lovelace, None, InlineDatum(sc_out_datum_1))
  !sell.matching(
    fixture.tx(
      [sc_in_1, seller_in_1],
      [refer_in_1],
      [exchange_out_1, seller_out_1, owner_out_1, sc_out_utxo],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    ),
    cfg,
    sc_in_datum_1,
    owner_address,
    sc_address,
  )
}

test sell_succ_bond_policy_id_valid() {
  let time_of_tx = 1681095094000
  let cfg = get_config_limit_mainnet()
  let owner_address = get_buyer_address()
  let seller_address = get_seller_address()
  let sc_in_datum_1 = gen_bid_limit_datum(owner_address, 390, 480, 5, 500)
  let bond_name_1 = get_bond_id_1()
  //
  let escrow_dt = get_escrow_datum(bond_name_1, 10000, 753424657, 72, 63)
  let escrow_lovelace = 1017328767112
  let escrow_full_info =
    calc_escrow_full_info(cfg.bond, escrow_lovelace, escrow_dt, time_of_tx)
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.bond.basis_points_ref_unit,
    )
  //  
  let bond_sell_qty = 5
  let received_at_maturity = escrow_full_info.value_at_maturity * bond_sell_qty
  let received_with_yield = price_of_one_bond * bond_sell_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.seller_fee / cfg.bond.basis_points_ref_unit
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.bond.basis_points_ref_unit
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
      InlineDatum(escrow_dt),
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
  // let sc_out_lovelace =
  //   sc_in_lovelace - received_with_yield - exchange_fee_buyer - owner_out_lovelace
  // let sc_out_datum_1 =
  //   gen_bid_limit_datum(
  //     owner_address,
  //     390,
  //     480,
  //     sc_in_datum_1.quantity - bond_sell_qty,
  //     500,
  //   )
  // let sc_out_utxo =
  //   gen_output(sc_address, sc_out_lovelace, None, InlineDatum(sc_out_datum_1))
  sell.matching(
    fixture.tx(
      [sc_in_1, seller_in_1],
      [refer_in_1],
      [exchange_out_1, seller_out_1, owner_out_1],
      // [exchange_out_1, seller_out_1, owner_out_1, sc_out_utxo],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    ),
    cfg,
    sc_in_datum_1,
    owner_address,
    sc_address,
  )
}

test sell_fail_bond_policy_id_invalid() {
  let time_of_tx = 1681095094000
  let cfg = get_config_limit_mainnet()
  let owner_address = get_buyer_address()
  let seller_address = get_seller_address()
  let sc_in_datum_1 = gen_bid_limit_datum(owner_address, 390, 480, 5, 500)
  let bond_name_1 = get_bond_id_1()
  //
  let escrow_dt = get_escrow_datum(bond_name_1, 10000, 753424657, 72, 63)
  let escrow_lovelace = 1017328767112
  let escrow_full_info =
    calc_escrow_full_info(cfg.bond, escrow_lovelace, escrow_dt, time_of_tx)
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.bond.basis_points_ref_unit,
    )
  //  
  let bond_sell_qty = 5
  let received_at_maturity = escrow_full_info.value_at_maturity * bond_sell_qty
  let received_with_yield = price_of_one_bond * bond_sell_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.seller_fee / cfg.bond.basis_points_ref_unit
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.bond.basis_points_ref_unit
  //
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
      InlineDatum(escrow_dt),
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
    gen_bid_limit_datum(
      owner_address,
      390,
      480,
      sc_in_datum_1.quantity - bond_sell_qty,
      500,
    )
  let sc_out_utxo =
    gen_output(sc_address, sc_out_lovelace, None, InlineDatum(sc_out_datum_1))
  !sell.matching(
    fixture.tx(
      [sc_in_1, seller_in_1],
      [refer_in_1],
      [exchange_out_1, seller_out_1, owner_out_1, sc_out_utxo],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    ),
    cfg,
    sc_in_datum_1,
    owner_address,
    sc_address,
  )
}
