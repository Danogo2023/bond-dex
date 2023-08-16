use aiken/transaction.{InlineDatum, NoDatum}
use aiken/transaction/value
use bond/fixture.{
  calc_escrow_full_info, gen_bidding_datum, gen_input, gen_output, get_bond_id_1,
  get_bond_policy_id, get_buyer_address, get_buyer_address_hash,
  get_buyer_address_scripthash, get_config_mainnet, get_escrow_address,
  get_escrow_address_unexpect, get_escrow_datum, get_escrow_policy_id,
  get_input_escrow, get_market_address, get_not_bond_policy_id,
  get_not_escrow_policy_id, get_seller_address, get_smart_contract_address,
}
use bond/utils.{get_price_of_bond}
use bond/validation_bidding

test bidding_sell_succ_full() {
  let time_of_tx = 1681095094000
  let cfg = get_config_mainnet()
  let owner_address = get_buyer_address()
  let seller_address = get_seller_address()
  let input_bidding_datum = gen_bidding_datum(owner_address, 390, 480, 5, 500)
  let bond_name_1 = get_bond_id_1()
  //
  let escrow_datum = get_escrow_datum(bond_name_1, 10000, 753424657, 72, 63)
  let escrow_lovelace = 1017328767112
  let escrow_full_info =
    calc_escrow_full_info(cfg.bond, escrow_lovelace, escrow_datum, time_of_tx)
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.received_at_maturity_one_bond,
      escrow_full_info.day_to_maturity,
      input_bidding_datum.requested_yield,
      cfg.bond.basis_points_ref_unit,
    )
  //  
  let bond_sell_qty = 5
  let received_at_maturity =
    escrow_full_info.received_at_maturity_one_bond * bond_sell_qty
  let received_with_yield = price_of_one_bond * bond_sell_qty
  let received_diff = received_at_maturity - received_with_yield
  let market_fee_seller =
    received_diff * cfg.market.seller_fee / cfg.bond.basis_points_ref_unit
  let market_fee_buyer =
    received_diff * cfg.market.buyer_fee / cfg.bond.basis_points_ref_unit
  //
  let output_buyer_lovelace = 1310316
  let sm_address = get_smart_contract_address()
  let sm_input_lovelace =
    received_with_yield + market_fee_buyer + output_buyer_lovelace
  let input_sm_1 =
    gen_input(
      sm_address,
      sm_input_lovelace,
      None,
      InlineDatum(input_bidding_datum),
    )
  let input_seller_lovelace = 1310316
  let asset_sell =
    value.from_asset(get_bond_policy_id(), bond_name_1, bond_sell_qty)
  let input_seller_1 =
    gen_input(seller_address, input_seller_lovelace, Some(asset_sell), NoDatum)
  let reference_input_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  //
  let market_address = get_market_address()
  let output_market_lovelace = market_fee_buyer + market_fee_seller
  let output_market_utxo =
    gen_output(market_address, output_market_lovelace, None, NoDatum)
  let output_seller_lovelace =
    input_seller_lovelace + received_with_yield - market_fee_seller
  let output_seller_utxo =
    gen_output(seller_address, output_seller_lovelace, None, NoDatum)
  let output_buyer_utxo =
    gen_output(owner_address, output_buyer_lovelace, Some(asset_sell), NoDatum)
  let output_sm_lovelace =
    sm_input_lovelace - received_with_yield - market_fee_buyer - output_buyer_lovelace
  let output_bidding_datum =
    gen_bidding_datum(
      owner_address,
      390,
      480,
      input_bidding_datum.quantity - bond_sell_qty,
      500,
    )
  let output_sm_utxo =
    gen_output(
      sm_address,
      output_sm_lovelace,
      None,
      InlineDatum(output_bidding_datum),
    )
  validation_bidding.sell(
    fixture.tx(
      [input_sm_1, input_seller_1],
      [reference_input_1],
      [
        output_market_utxo,
        output_seller_utxo,
        output_buyer_utxo,
        output_sm_utxo,
      ],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 5 * 60 * 1000),
    ),
    cfg,
    input_bidding_datum,
    owner_address,
    sm_address,
  )
}

test bidding_sell_succ_partial() {
  let time_of_tx = 1681095094000
  let cfg = get_config_mainnet()
  let owner_address = get_buyer_address()
  let seller_address = get_seller_address()
  let input_bidding_datum = gen_bidding_datum(owner_address, 390, 480, 5, 500)
  let bond_name_1 = get_bond_id_1()
  //
  let escrow_datum = get_escrow_datum(bond_name_1, 10000, 753424657, 72, 63)
  let escrow_lovelace = 1017328767112
  let escrow_full_info =
    calc_escrow_full_info(cfg.bond, escrow_lovelace, escrow_datum, time_of_tx)
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.received_at_maturity_one_bond,
      escrow_full_info.day_to_maturity,
      input_bidding_datum.requested_yield,
      cfg.bond.basis_points_ref_unit,
    )
  //  
  let bond_sell_qty = 2
  let received_at_maturity =
    escrow_full_info.received_at_maturity_one_bond * bond_sell_qty
  let received_with_yield = price_of_one_bond * bond_sell_qty
  let received_diff = received_at_maturity - received_with_yield
  let market_fee_seller =
    received_diff * cfg.market.seller_fee / cfg.bond.basis_points_ref_unit
  let market_fee_buyer =
    received_diff * cfg.market.buyer_fee / cfg.bond.basis_points_ref_unit
  //
  let output_buyer_lovelace = 1310316
  let sm_address = get_smart_contract_address()
  let sm_input_lovelace =
    received_with_yield + market_fee_buyer + output_buyer_lovelace
  let input_sm_1 =
    gen_input(
      sm_address,
      sm_input_lovelace,
      None,
      InlineDatum(input_bidding_datum),
    )
  let input_seller_lovelace = 1310316
  let asset_sell =
    value.from_asset(get_bond_policy_id(), bond_name_1, bond_sell_qty)
  let input_seller_1 =
    gen_input(seller_address, input_seller_lovelace, Some(asset_sell), NoDatum)
  let reference_input_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  //
  let market_address = get_market_address()
  let output_market_lovelace = market_fee_buyer + market_fee_seller
  let output_market_utxo =
    gen_output(market_address, output_market_lovelace, None, NoDatum)
  let output_seller_lovelace =
    input_seller_lovelace + received_with_yield - market_fee_seller
  let output_seller_utxo =
    gen_output(seller_address, output_seller_lovelace, None, NoDatum)
  let output_buyer_utxo =
    gen_output(owner_address, output_buyer_lovelace, Some(asset_sell), NoDatum)
  let output_sm_lovelace =
    sm_input_lovelace - received_with_yield - market_fee_buyer - output_buyer_lovelace
  let output_bidding_datum =
    gen_bidding_datum(
      owner_address,
      390,
      480,
      input_bidding_datum.quantity - bond_sell_qty,
      500,
    )
  let output_sm_utxo =
    gen_output(
      sm_address,
      output_sm_lovelace,
      None,
      InlineDatum(output_bidding_datum),
    )
  validation_bidding.sell(
    fixture.tx(
      [input_sm_1, input_seller_1],
      [reference_input_1],
      [
        output_market_utxo,
        output_seller_utxo,
        output_buyer_utxo,
        output_sm_utxo,
      ],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 5 * 60 * 1000),
    ),
    cfg,
    input_bidding_datum,
    owner_address,
    sm_address,
  )
}

test bidding_sell_fail_input_epoch_1() {
  let time_of_tx = 1681095094000
  let cfg = get_config_mainnet()
  let owner_address = get_buyer_address()
  let seller_address = get_seller_address()
  let input_bidding_datum = gen_bidding_datum(owner_address, 480, 390, 5, 500)
  let bond_name_1 = get_bond_id_1()
  //
  let escrow_datum = get_escrow_datum(bond_name_1, 10000, 753424657, 72, 63)
  let escrow_lovelace = 1017328767112
  let escrow_full_info =
    calc_escrow_full_info(cfg.bond, escrow_lovelace, escrow_datum, time_of_tx)
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.received_at_maturity_one_bond,
      escrow_full_info.day_to_maturity,
      input_bidding_datum.requested_yield,
      cfg.bond.basis_points_ref_unit,
    )
  //  
  let bond_sell_qty = 5
  let received_at_maturity =
    escrow_full_info.received_at_maturity_one_bond * bond_sell_qty
  let received_with_yield = price_of_one_bond * bond_sell_qty
  let received_diff = received_at_maturity - received_with_yield
  let market_fee_seller =
    received_diff * cfg.market.seller_fee / cfg.bond.basis_points_ref_unit
  let market_fee_buyer =
    received_diff * cfg.market.buyer_fee / cfg.bond.basis_points_ref_unit
  //
  let output_buyer_lovelace = 1310316
  let sm_address = get_smart_contract_address()
  let sm_input_lovelace =
    received_with_yield + market_fee_buyer + output_buyer_lovelace
  let input_sm_1 =
    gen_input(
      sm_address,
      sm_input_lovelace,
      None,
      InlineDatum(input_bidding_datum),
    )
  let input_seller_lovelace = 1310316
  let asset_sell =
    value.from_asset(get_bond_policy_id(), bond_name_1, bond_sell_qty)
  let input_seller_1 =
    gen_input(seller_address, input_seller_lovelace, Some(asset_sell), NoDatum)
  let reference_input_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  //
  let market_address = get_market_address()
  let output_market_lovelace = market_fee_buyer + market_fee_seller
  let output_market_utxo =
    gen_output(market_address, output_market_lovelace, None, NoDatum)
  let output_seller_lovelace =
    input_seller_lovelace + received_with_yield - market_fee_seller
  let output_seller_utxo =
    gen_output(seller_address, output_seller_lovelace, None, NoDatum)
  let output_buyer_utxo =
    gen_output(owner_address, output_buyer_lovelace, Some(asset_sell), NoDatum)
  let output_sm_lovelace =
    sm_input_lovelace - received_with_yield - market_fee_buyer - output_buyer_lovelace
  let output_bidding_datum =
    gen_bidding_datum(
      owner_address,
      390,
      480,
      input_bidding_datum.quantity - bond_sell_qty,
      500,
    )
  let output_sm_utxo =
    gen_output(
      sm_address,
      output_sm_lovelace,
      None,
      InlineDatum(output_bidding_datum),
    )
  !validation_bidding.sell(
    fixture.tx(
      [input_sm_1, input_seller_1],
      [reference_input_1],
      [
        output_market_utxo,
        output_seller_utxo,
        output_buyer_utxo,
        output_sm_utxo,
      ],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 5 * 60 * 1000),
    ),
    cfg,
    input_bidding_datum,
    owner_address,
    sm_address,
  )
}

test bidding_sell_fail_input_epoch_2() {
  let time_of_tx = 1681095094000
  let cfg = get_config_mainnet()
  let owner_address = get_buyer_address()
  let seller_address = get_seller_address()
  let input_bidding_datum = gen_bidding_datum(owner_address, 464, 480, 5, 500)
  let bond_name_1 = get_bond_id_1()
  //
  let escrow_datum = get_escrow_datum(bond_name_1, 10000, 753424657, 72, 63)
  let escrow_lovelace = 1017328767112
  let escrow_full_info =
    calc_escrow_full_info(cfg.bond, escrow_lovelace, escrow_datum, time_of_tx)
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.received_at_maturity_one_bond,
      escrow_full_info.day_to_maturity,
      input_bidding_datum.requested_yield,
      cfg.bond.basis_points_ref_unit,
    )
  //  
  let bond_sell_qty = 5
  let received_at_maturity =
    escrow_full_info.received_at_maturity_one_bond * bond_sell_qty
  let received_with_yield = price_of_one_bond * bond_sell_qty
  let received_diff = received_at_maturity - received_with_yield
  let market_fee_seller =
    received_diff * cfg.market.seller_fee / cfg.bond.basis_points_ref_unit
  let market_fee_buyer =
    received_diff * cfg.market.buyer_fee / cfg.bond.basis_points_ref_unit
  //
  let output_buyer_lovelace = 1310316
  let sm_address = get_smart_contract_address()
  let sm_input_lovelace =
    received_with_yield + market_fee_buyer + output_buyer_lovelace
  let input_sm_1 =
    gen_input(
      sm_address,
      sm_input_lovelace,
      None,
      InlineDatum(input_bidding_datum),
    )
  let input_seller_lovelace = 1310316
  let asset_sell =
    value.from_asset(get_bond_policy_id(), bond_name_1, bond_sell_qty)
  let input_seller_1 =
    gen_input(seller_address, input_seller_lovelace, Some(asset_sell), NoDatum)
  let reference_input_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  //
  let market_address = get_market_address()
  let output_market_lovelace = market_fee_buyer + market_fee_seller
  let output_market_utxo =
    gen_output(market_address, output_market_lovelace, None, NoDatum)
  let output_seller_lovelace =
    input_seller_lovelace + received_with_yield - market_fee_seller
  let output_seller_utxo =
    gen_output(seller_address, output_seller_lovelace, None, NoDatum)
  let output_buyer_utxo =
    gen_output(owner_address, output_buyer_lovelace, Some(asset_sell), NoDatum)
  let output_sm_lovelace =
    sm_input_lovelace - received_with_yield - market_fee_buyer - output_buyer_lovelace
  let output_bidding_datum =
    gen_bidding_datum(
      owner_address,
      390,
      480,
      input_bidding_datum.quantity - bond_sell_qty,
      500,
    )
  let output_sm_utxo =
    gen_output(
      sm_address,
      output_sm_lovelace,
      None,
      InlineDatum(output_bidding_datum),
    )
  !validation_bidding.sell(
    fixture.tx(
      [input_sm_1, input_seller_1],
      [reference_input_1],
      [
        output_market_utxo,
        output_seller_utxo,
        output_buyer_utxo,
        output_sm_utxo,
      ],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 5 * 60 * 1000),
    ),
    cfg,
    input_bidding_datum,
    owner_address,
    sm_address,
  )
  // let current_epoch =
  //   posix_time_to_relative_epoch(
  //     time_of_tx,
  //     cfg.bond.epoch_config,
  //   )
  // current_epoch = 404
  // let end_epoch =
  //   escrow_datum.start + cfg.bond.epoch_config.epoch_boundary_as_epoch + escrow_datum.duration
  // end_epoch = 463
  // input_bidding_datum.from_epoch = 390
  // bidding_datum.to_epoch = 480
  // end_epoch == input_bidding_datum.from_epoch
  // end_epoch == current_epoch
}

test bidding_sell_fail_input_epoch_3() {
  let time_of_tx = 1681095094000
  let cfg = get_config_mainnet()
  let owner_address = get_buyer_address()
  let seller_address = get_seller_address()
  let input_bidding_datum = gen_bidding_datum(owner_address, 390, 462, 5, 500)
  let bond_name_1 = get_bond_id_1()
  //
  let escrow_datum = get_escrow_datum(bond_name_1, 10000, 753424657, 72, 63)
  let escrow_lovelace = 1017328767112
  let escrow_full_info =
    calc_escrow_full_info(cfg.bond, escrow_lovelace, escrow_datum, time_of_tx)
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.received_at_maturity_one_bond,
      escrow_full_info.day_to_maturity,
      input_bidding_datum.requested_yield,
      cfg.bond.basis_points_ref_unit,
    )
  //  
  let bond_sell_qty = 5
  let received_at_maturity =
    escrow_full_info.received_at_maturity_one_bond * bond_sell_qty
  let received_with_yield = price_of_one_bond * bond_sell_qty
  let received_diff = received_at_maturity - received_with_yield
  let market_fee_seller =
    received_diff * cfg.market.seller_fee / cfg.bond.basis_points_ref_unit
  let market_fee_buyer =
    received_diff * cfg.market.buyer_fee / cfg.bond.basis_points_ref_unit
  //
  let output_buyer_lovelace = 1310316
  let sm_address = get_smart_contract_address()
  let sm_input_lovelace =
    received_with_yield + market_fee_buyer + output_buyer_lovelace
  let input_sm_1 =
    gen_input(
      sm_address,
      sm_input_lovelace,
      None,
      InlineDatum(input_bidding_datum),
    )
  let input_seller_lovelace = 1310316
  let asset_sell =
    value.from_asset(get_bond_policy_id(), bond_name_1, bond_sell_qty)
  let input_seller_1 =
    gen_input(seller_address, input_seller_lovelace, Some(asset_sell), NoDatum)
  let reference_input_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  //
  let market_address = get_market_address()
  let output_market_lovelace = market_fee_buyer + market_fee_seller
  let output_market_utxo =
    gen_output(market_address, output_market_lovelace, None, NoDatum)
  let output_seller_lovelace =
    input_seller_lovelace + received_with_yield - market_fee_seller
  let output_seller_utxo =
    gen_output(seller_address, output_seller_lovelace, None, NoDatum)
  let output_buyer_utxo =
    gen_output(owner_address, output_buyer_lovelace, Some(asset_sell), NoDatum)
  let output_sm_lovelace =
    sm_input_lovelace - received_with_yield - market_fee_buyer - output_buyer_lovelace
  let output_bidding_datum =
    gen_bidding_datum(
      owner_address,
      390,
      480,
      input_bidding_datum.quantity - bond_sell_qty,
      500,
    )
  let output_sm_utxo =
    gen_output(
      sm_address,
      output_sm_lovelace,
      None,
      InlineDatum(output_bidding_datum),
    )
  !validation_bidding.sell(
    fixture.tx(
      [input_sm_1, input_seller_1],
      [reference_input_1],
      [
        output_market_utxo,
        output_seller_utxo,
        output_buyer_utxo,
        output_sm_utxo,
      ],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 5 * 60 * 1000),
    ),
    cfg,
    input_bidding_datum,
    owner_address,
    sm_address,
  )
}

test bidding_sell_fail_input_epoch_4() {
  let time_of_tx = 1681095094000 + 25920000000
  let cfg = get_config_mainnet()
  let owner_address = get_buyer_address()
  let seller_address = get_seller_address()
  let input_bidding_datum = gen_bidding_datum(owner_address, 390, 462, 5, 500)
  let bond_name_1 = get_bond_id_1()
  //
  let escrow_datum = get_escrow_datum(bond_name_1, 10000, 753424657, 72, 63)
  let escrow_lovelace = 1017328767112
  let escrow_full_info =
    calc_escrow_full_info(cfg.bond, escrow_lovelace, escrow_datum, time_of_tx)
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.received_at_maturity_one_bond,
      escrow_full_info.day_to_maturity,
      input_bidding_datum.requested_yield,
      cfg.bond.basis_points_ref_unit,
    )
  //  
  let bond_sell_qty = 5
  let received_at_maturity =
    escrow_full_info.received_at_maturity_one_bond * bond_sell_qty
  let received_with_yield = price_of_one_bond * bond_sell_qty
  let received_diff = received_at_maturity - received_with_yield
  let market_fee_seller =
    received_diff * cfg.market.seller_fee / cfg.bond.basis_points_ref_unit
  let market_fee_buyer =
    received_diff * cfg.market.buyer_fee / cfg.bond.basis_points_ref_unit
  //
  let output_buyer_lovelace = 1310316
  let sm_address = get_smart_contract_address()
  let sm_input_lovelace =
    received_with_yield + market_fee_buyer + output_buyer_lovelace
  let input_sm_1 =
    gen_input(
      sm_address,
      sm_input_lovelace,
      None,
      InlineDatum(input_bidding_datum),
    )
  let input_seller_lovelace = 1310316
  let asset_sell =
    value.from_asset(get_bond_policy_id(), bond_name_1, bond_sell_qty)
  let input_seller_1 =
    gen_input(seller_address, input_seller_lovelace, Some(asset_sell), NoDatum)
  let reference_input_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  //
  let market_address = get_market_address()
  let output_market_lovelace = market_fee_buyer + market_fee_seller
  let output_market_utxo =
    gen_output(market_address, output_market_lovelace, None, NoDatum)
  let output_seller_lovelace =
    input_seller_lovelace + received_with_yield - market_fee_seller
  let output_seller_utxo =
    gen_output(seller_address, output_seller_lovelace, None, NoDatum)
  let output_buyer_utxo =
    gen_output(owner_address, output_buyer_lovelace, Some(asset_sell), NoDatum)
  let output_sm_lovelace =
    sm_input_lovelace - received_with_yield - market_fee_buyer - output_buyer_lovelace
  let output_bidding_datum =
    gen_bidding_datum(
      owner_address,
      390,
      480,
      input_bidding_datum.quantity - bond_sell_qty,
      500,
    )
  let output_sm_utxo =
    gen_output(
      sm_address,
      output_sm_lovelace,
      None,
      InlineDatum(output_bidding_datum),
    )
  !validation_bidding.sell(
    fixture.tx(
      [input_sm_1, input_seller_1],
      [reference_input_1],
      [
        output_market_utxo,
        output_seller_utxo,
        output_buyer_utxo,
        output_sm_utxo,
      ],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 5 * 60 * 1000),
    ),
    cfg,
    input_bidding_datum,
    owner_address,
    sm_address,
  )
  // let current_epoch =
  //   posix_time_to_relative_epoch(
  //     time_of_tx,
  //     cfg.bond.epoch_config,
  //   )
  // // current_epoch = 464
  // let end_epoch =
  //   escrow_datum.start + cfg.bond.epoch_config.epoch_boundary_as_epoch + escrow_datum.duration
  // // end_epoch = 463
  // current_epoch == end_epoch
}

test bidding_sell_fail_input_qty() {
  let time_of_tx = 1681095094000
  let cfg = get_config_mainnet()
  let owner_address = get_buyer_address()
  let seller_address = get_seller_address()
  let input_bidding_datum = gen_bidding_datum(owner_address, 390, 480, 0, 500)
  let bond_name_1 = get_bond_id_1()
  //
  let escrow_datum = get_escrow_datum(bond_name_1, 10000, 753424657, 72, 63)
  let escrow_lovelace = 1017328767112
  let escrow_full_info =
    calc_escrow_full_info(cfg.bond, escrow_lovelace, escrow_datum, time_of_tx)
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.received_at_maturity_one_bond,
      escrow_full_info.day_to_maturity,
      input_bidding_datum.requested_yield,
      cfg.bond.basis_points_ref_unit,
    )
  //  
  let bond_sell_qty = 5
  let received_at_maturity =
    escrow_full_info.received_at_maturity_one_bond * bond_sell_qty
  let received_with_yield = price_of_one_bond * bond_sell_qty
  let received_diff = received_at_maturity - received_with_yield
  let market_fee_seller =
    received_diff * cfg.market.seller_fee / cfg.bond.basis_points_ref_unit
  let market_fee_buyer =
    received_diff * cfg.market.buyer_fee / cfg.bond.basis_points_ref_unit
  //
  let output_buyer_lovelace = 1310316
  let sm_address = get_smart_contract_address()
  let sm_input_lovelace =
    received_with_yield + market_fee_buyer + output_buyer_lovelace
  let input_sm_1 =
    gen_input(
      sm_address,
      sm_input_lovelace,
      None,
      InlineDatum(input_bidding_datum),
    )
  let input_seller_lovelace = 1310316
  let asset_sell =
    value.from_asset(get_bond_policy_id(), bond_name_1, bond_sell_qty)
  let input_seller_1 =
    gen_input(seller_address, input_seller_lovelace, Some(asset_sell), NoDatum)
  let reference_input_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  //
  let market_address = get_market_address()
  let output_market_lovelace = market_fee_buyer + market_fee_seller
  let output_market_utxo =
    gen_output(market_address, output_market_lovelace, None, NoDatum)
  let output_seller_lovelace =
    input_seller_lovelace + received_with_yield - market_fee_seller
  let output_seller_utxo =
    gen_output(seller_address, output_seller_lovelace, None, NoDatum)
  let output_buyer_utxo =
    gen_output(owner_address, output_buyer_lovelace, Some(asset_sell), NoDatum)
  let output_sm_lovelace =
    sm_input_lovelace - received_with_yield - market_fee_buyer - output_buyer_lovelace
  let output_bidding_datum =
    gen_bidding_datum(
      owner_address,
      390,
      480,
      input_bidding_datum.quantity - bond_sell_qty,
      500,
    )
  let output_sm_utxo =
    gen_output(
      sm_address,
      output_sm_lovelace,
      None,
      InlineDatum(output_bidding_datum),
    )
  !validation_bidding.sell(
    fixture.tx(
      [input_sm_1, input_seller_1],
      [reference_input_1],
      [
        output_market_utxo,
        output_seller_utxo,
        output_buyer_utxo,
        output_sm_utxo,
      ],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 5 * 60 * 1000),
    ),
    cfg,
    input_bidding_datum,
    owner_address,
    sm_address,
  )
}

test bidding_sell_fail_output_qty() {
  let time_of_tx = 1681095094000
  let cfg = get_config_mainnet()
  let owner_address = get_buyer_address()
  let seller_address = get_seller_address()
  let input_bidding_datum = gen_bidding_datum(owner_address, 390, 480, 1, 500)
  let bond_name_1 = get_bond_id_1()
  //
  let escrow_datum = get_escrow_datum(bond_name_1, 10000, 753424657, 72, 63)
  let escrow_lovelace = 1017328767112
  let escrow_full_info =
    calc_escrow_full_info(cfg.bond, escrow_lovelace, escrow_datum, time_of_tx)
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.received_at_maturity_one_bond,
      escrow_full_info.day_to_maturity,
      input_bidding_datum.requested_yield,
      cfg.bond.basis_points_ref_unit,
    )
  //  
  let bond_sell_qty = 5
  let received_at_maturity =
    escrow_full_info.received_at_maturity_one_bond * bond_sell_qty
  let received_with_yield = price_of_one_bond * bond_sell_qty
  let received_diff = received_at_maturity - received_with_yield
  let market_fee_seller =
    received_diff * cfg.market.seller_fee / cfg.bond.basis_points_ref_unit
  let market_fee_buyer =
    received_diff * cfg.market.buyer_fee / cfg.bond.basis_points_ref_unit
  //
  let output_buyer_lovelace = 1310316
  let sm_address = get_smart_contract_address()
  let sm_input_lovelace =
    received_with_yield + market_fee_buyer + output_buyer_lovelace
  let input_sm_1 =
    gen_input(
      sm_address,
      sm_input_lovelace,
      None,
      InlineDatum(input_bidding_datum),
    )
  let input_seller_lovelace = 1310316
  let asset_sell =
    value.from_asset(get_bond_policy_id(), bond_name_1, bond_sell_qty)
  let input_seller_1 =
    gen_input(seller_address, input_seller_lovelace, Some(asset_sell), NoDatum)
  let reference_input_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  //
  let market_address = get_market_address()
  let output_market_lovelace = market_fee_buyer + market_fee_seller
  let output_market_utxo =
    gen_output(market_address, output_market_lovelace, None, NoDatum)
  let output_seller_lovelace =
    input_seller_lovelace + received_with_yield - market_fee_seller
  let output_seller_utxo =
    gen_output(seller_address, output_seller_lovelace, None, NoDatum)
  let output_buyer_utxo =
    gen_output(owner_address, output_buyer_lovelace, Some(asset_sell), NoDatum)
  let output_sm_lovelace =
    sm_input_lovelace - received_with_yield - market_fee_buyer - output_buyer_lovelace
  let output_bidding_datum =
    gen_bidding_datum(
      owner_address,
      390,
      480,
      input_bidding_datum.quantity - bond_sell_qty,
      500,
    )
  let output_sm_utxo =
    gen_output(
      sm_address,
      output_sm_lovelace,
      None,
      InlineDatum(output_bidding_datum),
    )
  !validation_bidding.sell(
    fixture.tx(
      [input_sm_1, input_seller_1],
      [reference_input_1],
      [
        output_market_utxo,
        output_seller_utxo,
        output_buyer_utxo,
        output_sm_utxo,
      ],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 5 * 60 * 1000),
    ),
    cfg,
    input_bidding_datum,
    owner_address,
    sm_address,
  )
}

test bidding_sell_fail_validity_after_not_set() {
  let time_of_tx = 1681095094000
  let cfg = get_config_mainnet()
  let owner_address = get_buyer_address()
  let seller_address = get_seller_address()
  let input_bidding_datum = gen_bidding_datum(owner_address, 390, 480, 5, 500)
  let bond_name_1 = get_bond_id_1()
  //
  let escrow_datum = get_escrow_datum(bond_name_1, 10000, 753424657, 72, 63)
  let escrow_lovelace = 1017328767112
  let escrow_full_info =
    calc_escrow_full_info(cfg.bond, escrow_lovelace, escrow_datum, time_of_tx)
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.received_at_maturity_one_bond,
      escrow_full_info.day_to_maturity,
      input_bidding_datum.requested_yield,
      cfg.bond.basis_points_ref_unit,
    )
  //  
  let bond_sell_qty = 5
  let received_at_maturity =
    escrow_full_info.received_at_maturity_one_bond * bond_sell_qty
  let received_with_yield = price_of_one_bond * bond_sell_qty
  let received_diff = received_at_maturity - received_with_yield
  let market_fee_seller =
    received_diff * cfg.market.seller_fee / cfg.bond.basis_points_ref_unit
  let market_fee_buyer =
    received_diff * cfg.market.buyer_fee / cfg.bond.basis_points_ref_unit
  //
  let output_buyer_lovelace = 1310316
  let sm_address = get_smart_contract_address()
  let sm_input_lovelace =
    received_with_yield + market_fee_buyer + output_buyer_lovelace
  let input_sm_1 =
    gen_input(
      sm_address,
      sm_input_lovelace,
      None,
      InlineDatum(input_bidding_datum),
    )
  let input_seller_lovelace = 1310316
  let asset_sell =
    value.from_asset(get_bond_policy_id(), bond_name_1, bond_sell_qty)
  let input_seller_1 =
    gen_input(seller_address, input_seller_lovelace, Some(asset_sell), NoDatum)
  let reference_input_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  //
  let market_address = get_market_address()
  let output_market_lovelace = market_fee_buyer + market_fee_seller
  let output_market_utxo =
    gen_output(market_address, output_market_lovelace, None, NoDatum)
  let output_seller_lovelace =
    input_seller_lovelace + received_with_yield - market_fee_seller
  let output_seller_utxo =
    gen_output(seller_address, output_seller_lovelace, None, NoDatum)
  let output_buyer_utxo =
    gen_output(owner_address, output_buyer_lovelace, Some(asset_sell), NoDatum)
  let output_sm_lovelace =
    sm_input_lovelace - received_with_yield - market_fee_buyer - output_buyer_lovelace
  let output_bidding_datum =
    gen_bidding_datum(
      owner_address,
      390,
      480,
      input_bidding_datum.quantity - bond_sell_qty,
      500,
    )
  let output_sm_utxo =
    gen_output(
      sm_address,
      output_sm_lovelace,
      None,
      InlineDatum(output_bidding_datum),
    )
  !validation_bidding.sell(
    fixture.tx(
      [input_sm_1, input_seller_1],
      [reference_input_1],
      [
        output_market_utxo,
        output_seller_utxo,
        output_buyer_utxo,
        output_sm_utxo,
      ],
      Some([get_buyer_address_hash()]),
      None,
      None,
      None,
    ),
    cfg,
    input_bidding_datum,
    owner_address,
    sm_address,
  )
}

test bidding_sell_fail_owner_address_format() {
  let time_of_tx = 1681095094000
  let cfg = get_config_mainnet()
  let owner_address = get_buyer_address()
  let seller_address = get_seller_address()
  let input_bidding_datum = gen_bidding_datum(owner_address, 390, 480, 5, 500)
  let bond_name_1 = get_bond_id_1()
  //
  let escrow_datum = get_escrow_datum(bond_name_1, 10000, 753424657, 72, 63)
  let escrow_lovelace = 1017328767112
  let escrow_full_info =
    calc_escrow_full_info(cfg.bond, escrow_lovelace, escrow_datum, time_of_tx)
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.received_at_maturity_one_bond,
      escrow_full_info.day_to_maturity,
      input_bidding_datum.requested_yield,
      cfg.bond.basis_points_ref_unit,
    )
  //  
  let bond_sell_qty = 5
  let received_at_maturity =
    escrow_full_info.received_at_maturity_one_bond * bond_sell_qty
  let received_with_yield = price_of_one_bond * bond_sell_qty
  let received_diff = received_at_maturity - received_with_yield
  let market_fee_seller =
    received_diff * cfg.market.seller_fee / cfg.bond.basis_points_ref_unit
  let market_fee_buyer =
    received_diff * cfg.market.buyer_fee / cfg.bond.basis_points_ref_unit
  //
  let output_buyer_lovelace = 1310316
  let sm_address = get_smart_contract_address()
  let sm_input_lovelace =
    received_with_yield + market_fee_buyer + output_buyer_lovelace
  let input_sm_1 =
    gen_input(
      sm_address,
      sm_input_lovelace,
      None,
      InlineDatum(input_bidding_datum),
    )
  let input_seller_lovelace = 1310316
  let asset_sell =
    value.from_asset(get_bond_policy_id(), bond_name_1, bond_sell_qty)
  let input_seller_1 =
    gen_input(seller_address, input_seller_lovelace, Some(asset_sell), NoDatum)
  let reference_input_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  //
  let market_address = get_market_address()
  let output_market_lovelace = market_fee_buyer + market_fee_seller
  let output_market_utxo =
    gen_output(market_address, output_market_lovelace, None, NoDatum)
  let output_seller_lovelace =
    input_seller_lovelace + received_with_yield - market_fee_seller
  let output_seller_utxo =
    gen_output(seller_address, output_seller_lovelace, None, NoDatum)
  let output_buyer_utxo =
    gen_output(owner_address, output_buyer_lovelace, Some(asset_sell), NoDatum)
  let output_sm_lovelace =
    sm_input_lovelace - received_with_yield - market_fee_buyer - output_buyer_lovelace
  let output_bidding_datum =
    gen_bidding_datum(
      owner_address,
      390,
      480,
      input_bidding_datum.quantity - bond_sell_qty,
      500,
    )
  let output_sm_utxo =
    gen_output(
      sm_address,
      output_sm_lovelace,
      None,
      InlineDatum(output_bidding_datum),
    )
  !validation_bidding.sell(
    fixture.tx(
      [input_sm_1, input_seller_1],
      [reference_input_1],
      [
        output_market_utxo,
        output_seller_utxo,
        output_buyer_utxo,
        output_sm_utxo,
      ],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 5 * 60 * 1000),
    ),
    cfg,
    input_bidding_datum,
    get_buyer_address_scripthash(),
    sm_address,
  )
}

test bidding_sell_fail_escrow_policy_id_unexpect() {
  let time_of_tx = 1681095094000
  let cfg = get_config_mainnet()
  let owner_address = get_buyer_address()
  let seller_address = get_seller_address()
  let input_bidding_datum = gen_bidding_datum(owner_address, 390, 480, 5, 500)
  let bond_name_1 = get_bond_id_1()
  //
  let escrow_datum = get_escrow_datum(bond_name_1, 10000, 753424657, 72, 63)
  let escrow_lovelace = 1017328767112
  let escrow_full_info =
    calc_escrow_full_info(cfg.bond, escrow_lovelace, escrow_datum, time_of_tx)
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.received_at_maturity_one_bond,
      escrow_full_info.day_to_maturity,
      input_bidding_datum.requested_yield,
      cfg.bond.basis_points_ref_unit,
    )
  //  
  let bond_sell_qty = 5
  let received_at_maturity =
    escrow_full_info.received_at_maturity_one_bond * bond_sell_qty
  let received_with_yield = price_of_one_bond * bond_sell_qty
  let received_diff = received_at_maturity - received_with_yield
  let market_fee_seller =
    received_diff * cfg.market.seller_fee / cfg.bond.basis_points_ref_unit
  let market_fee_buyer =
    received_diff * cfg.market.buyer_fee / cfg.bond.basis_points_ref_unit
  //
  let output_buyer_lovelace = 1310316
  let sm_address = get_smart_contract_address()
  let sm_input_lovelace =
    received_with_yield + market_fee_buyer + output_buyer_lovelace
  let input_sm_1 =
    gen_input(
      sm_address,
      sm_input_lovelace,
      None,
      InlineDatum(input_bidding_datum),
    )
  let input_seller_lovelace = 1310316
  let asset_sell =
    value.from_asset(get_bond_policy_id(), bond_name_1, bond_sell_qty)
  let input_seller_1 =
    gen_input(seller_address, input_seller_lovelace, Some(asset_sell), NoDatum)
  let reference_input_1 =
    get_input_escrow(
      get_escrow_address(),
      get_not_escrow_policy_id(),
      bond_name_1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  //
  let market_address = get_market_address()
  let output_market_lovelace = market_fee_buyer + market_fee_seller
  let output_market_utxo =
    gen_output(market_address, output_market_lovelace, None, NoDatum)
  let output_seller_lovelace =
    input_seller_lovelace + received_with_yield - market_fee_seller
  let output_seller_utxo =
    gen_output(seller_address, output_seller_lovelace, None, NoDatum)
  let output_buyer_utxo =
    gen_output(owner_address, output_buyer_lovelace, Some(asset_sell), NoDatum)
  let output_sm_lovelace =
    sm_input_lovelace - received_with_yield - market_fee_buyer - output_buyer_lovelace
  let output_bidding_datum =
    gen_bidding_datum(
      owner_address,
      390,
      480,
      input_bidding_datum.quantity - bond_sell_qty,
      500,
    )
  let output_sm_utxo =
    gen_output(
      sm_address,
      output_sm_lovelace,
      None,
      InlineDatum(output_bidding_datum),
    )
  !validation_bidding.sell(
    fixture.tx(
      [input_sm_1, input_seller_1],
      [reference_input_1],
      [
        output_market_utxo,
        output_seller_utxo,
        output_buyer_utxo,
        output_sm_utxo,
      ],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 5 * 60 * 1000),
    ),
    cfg,
    input_bidding_datum,
    owner_address,
    sm_address,
  )
}

test bidding_sell_fail_escrow_address_unexpect() {
  let time_of_tx = 1681095094000
  let cfg = get_config_mainnet()
  let owner_address = get_buyer_address()
  let seller_address = get_seller_address()
  let input_bidding_datum = gen_bidding_datum(owner_address, 390, 480, 5, 500)
  let bond_name_1 = get_bond_id_1()
  //
  let escrow_datum = get_escrow_datum(bond_name_1, 10000, 753424657, 72, 63)
  let escrow_lovelace = 1017328767112
  let escrow_full_info =
    calc_escrow_full_info(cfg.bond, escrow_lovelace, escrow_datum, time_of_tx)
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.received_at_maturity_one_bond,
      escrow_full_info.day_to_maturity,
      input_bidding_datum.requested_yield,
      cfg.bond.basis_points_ref_unit,
    )
  //  
  let bond_sell_qty = 5
  let received_at_maturity =
    escrow_full_info.received_at_maturity_one_bond * bond_sell_qty
  let received_with_yield = price_of_one_bond * bond_sell_qty
  let received_diff = received_at_maturity - received_with_yield
  let market_fee_seller =
    received_diff * cfg.market.seller_fee / cfg.bond.basis_points_ref_unit
  let market_fee_buyer =
    received_diff * cfg.market.buyer_fee / cfg.bond.basis_points_ref_unit
  //
  let output_buyer_lovelace = 1310316
  let sm_address = get_smart_contract_address()
  let sm_input_lovelace =
    received_with_yield + market_fee_buyer + output_buyer_lovelace
  let input_sm_1 =
    gen_input(
      sm_address,
      sm_input_lovelace,
      None,
      InlineDatum(input_bidding_datum),
    )
  let input_seller_lovelace = 1310316
  let asset_sell =
    value.from_asset(get_bond_policy_id(), bond_name_1, bond_sell_qty)
  let input_seller_1 =
    gen_input(seller_address, input_seller_lovelace, Some(asset_sell), NoDatum)
  let reference_input_1 =
    get_input_escrow(
      get_escrow_address_unexpect(),
      get_escrow_policy_id(),
      bond_name_1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  //
  let market_address = get_market_address()
  let output_market_lovelace = market_fee_buyer + market_fee_seller
  let output_market_utxo =
    gen_output(market_address, output_market_lovelace, None, NoDatum)
  let output_seller_lovelace =
    input_seller_lovelace + received_with_yield - market_fee_seller
  let output_seller_utxo =
    gen_output(seller_address, output_seller_lovelace, None, NoDatum)
  let output_buyer_utxo =
    gen_output(owner_address, output_buyer_lovelace, Some(asset_sell), NoDatum)
  let output_sm_lovelace =
    sm_input_lovelace - received_with_yield - market_fee_buyer - output_buyer_lovelace
  let output_bidding_datum =
    gen_bidding_datum(
      owner_address,
      390,
      480,
      input_bidding_datum.quantity - bond_sell_qty,
      500,
    )
  let output_sm_utxo =
    gen_output(
      sm_address,
      output_sm_lovelace,
      None,
      InlineDatum(output_bidding_datum),
    )
  !validation_bidding.sell(
    fixture.tx(
      [input_sm_1, input_seller_1],
      [reference_input_1],
      [
        output_market_utxo,
        output_seller_utxo,
        output_buyer_utxo,
        output_sm_utxo,
      ],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 5 * 60 * 1000),
    ),
    cfg,
    input_bidding_datum,
    owner_address,
    sm_address,
  )
}

test bidding_sell_fail_escrow_datum_not_found() {
  let time_of_tx = 1681095094000
  let cfg = get_config_mainnet()
  let owner_address = get_buyer_address()
  let seller_address = get_seller_address()
  let input_bidding_datum = gen_bidding_datum(owner_address, 390, 480, 5, 500)
  let bond_name_1 = get_bond_id_1()
  //
  let escrow_datum = get_escrow_datum(bond_name_1, 10000, 753424657, 72, 63)
  let escrow_lovelace = 1017328767112
  let escrow_full_info =
    calc_escrow_full_info(cfg.bond, escrow_lovelace, escrow_datum, time_of_tx)
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.received_at_maturity_one_bond,
      escrow_full_info.day_to_maturity,
      input_bidding_datum.requested_yield,
      cfg.bond.basis_points_ref_unit,
    )
  //  
  let bond_sell_qty = 5
  let received_at_maturity =
    escrow_full_info.received_at_maturity_one_bond * bond_sell_qty
  let received_with_yield = price_of_one_bond * bond_sell_qty
  let received_diff = received_at_maturity - received_with_yield
  let market_fee_seller =
    received_diff * cfg.market.seller_fee / cfg.bond.basis_points_ref_unit
  let market_fee_buyer =
    received_diff * cfg.market.buyer_fee / cfg.bond.basis_points_ref_unit
  //
  let output_buyer_lovelace = 1310316
  let sm_address = get_smart_contract_address()
  let sm_input_lovelace =
    received_with_yield + market_fee_buyer + output_buyer_lovelace
  let input_sm_1 =
    gen_input(
      sm_address,
      sm_input_lovelace,
      None,
      InlineDatum(input_bidding_datum),
    )
  let input_seller_lovelace = 1310316
  let asset_sell =
    value.from_asset(get_bond_policy_id(), bond_name_1, bond_sell_qty)
  let input_seller_1 =
    gen_input(seller_address, input_seller_lovelace, Some(asset_sell), NoDatum)
  let reference_input_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_1,
      escrow_lovelace,
      NoDatum,
    )
  //
  let market_address = get_market_address()
  let output_market_lovelace = market_fee_buyer + market_fee_seller
  let output_market_utxo =
    gen_output(market_address, output_market_lovelace, None, NoDatum)
  let output_seller_lovelace =
    input_seller_lovelace + received_with_yield - market_fee_seller
  let output_seller_utxo =
    gen_output(seller_address, output_seller_lovelace, None, NoDatum)
  let output_buyer_utxo =
    gen_output(owner_address, output_buyer_lovelace, Some(asset_sell), NoDatum)
  let output_sm_lovelace =
    sm_input_lovelace - received_with_yield - market_fee_buyer - output_buyer_lovelace
  let output_bidding_datum =
    gen_bidding_datum(
      owner_address,
      390,
      480,
      input_bidding_datum.quantity - bond_sell_qty,
      500,
    )
  let output_sm_utxo =
    gen_output(
      sm_address,
      output_sm_lovelace,
      None,
      InlineDatum(output_bidding_datum),
    )
  !validation_bidding.sell(
    fixture.tx(
      [input_sm_1, input_seller_1],
      [reference_input_1],
      [
        output_market_utxo,
        output_seller_utxo,
        output_buyer_utxo,
        output_sm_utxo,
      ],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 5 * 60 * 1000),
    ),
    cfg,
    input_bidding_datum,
    owner_address,
    sm_address,
  )
}

test bidding_sell_fail_escrow_datum_unexpect() fail {
  let time_of_tx = 1681095094000
  let cfg = get_config_mainnet()
  let owner_address = get_buyer_address()
  let seller_address = get_seller_address()
  let input_bidding_datum = gen_bidding_datum(owner_address, 390, 480, 5, 500)
  let bond_name_1 = get_bond_id_1()
  //
  let escrow_datum = get_escrow_datum(bond_name_1, 10000, 753424657, 72, 63)
  let escrow_lovelace = 1017328767112
  let escrow_full_info =
    calc_escrow_full_info(cfg.bond, escrow_lovelace, escrow_datum, time_of_tx)
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.received_at_maturity_one_bond,
      escrow_full_info.day_to_maturity,
      input_bidding_datum.requested_yield,
      cfg.bond.basis_points_ref_unit,
    )
  //  
  let bond_sell_qty = 5
  let received_at_maturity =
    escrow_full_info.received_at_maturity_one_bond * bond_sell_qty
  let received_with_yield = price_of_one_bond * bond_sell_qty
  let received_diff = received_at_maturity - received_with_yield
  let market_fee_seller =
    received_diff * cfg.market.seller_fee / cfg.bond.basis_points_ref_unit
  let market_fee_buyer =
    received_diff * cfg.market.buyer_fee / cfg.bond.basis_points_ref_unit
  //
  let output_buyer_lovelace = 1310316
  let sm_address = get_smart_contract_address()
  let sm_input_lovelace =
    received_with_yield + market_fee_buyer + output_buyer_lovelace
  let input_sm_1 =
    gen_input(
      sm_address,
      sm_input_lovelace,
      None,
      InlineDatum(input_bidding_datum),
    )
  let input_seller_lovelace = 1310316
  let asset_sell =
    value.from_asset(get_bond_policy_id(), bond_name_1, bond_sell_qty)
  let input_seller_1 =
    gen_input(seller_address, input_seller_lovelace, Some(asset_sell), NoDatum)
  let reference_input_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_1,
      escrow_lovelace,
      InlineDatum(input_bidding_datum),
    )
  //
  let market_address = get_market_address()
  let output_market_lovelace = market_fee_buyer + market_fee_seller
  let output_market_utxo =
    gen_output(market_address, output_market_lovelace, None, NoDatum)
  let output_seller_lovelace =
    input_seller_lovelace + received_with_yield - market_fee_seller
  let output_seller_utxo =
    gen_output(seller_address, output_seller_lovelace, None, NoDatum)
  let output_buyer_utxo =
    gen_output(owner_address, output_buyer_lovelace, Some(asset_sell), NoDatum)
  let output_sm_lovelace =
    sm_input_lovelace - received_with_yield - market_fee_buyer - output_buyer_lovelace
  let output_bidding_datum =
    gen_bidding_datum(
      owner_address,
      390,
      480,
      input_bidding_datum.quantity - bond_sell_qty,
      500,
    )
  let output_sm_utxo =
    gen_output(
      sm_address,
      output_sm_lovelace,
      None,
      InlineDatum(output_bidding_datum),
    )
  !validation_bidding.sell(
    fixture.tx(
      [input_sm_1, input_seller_1],
      [reference_input_1],
      [
        output_market_utxo,
        output_seller_utxo,
        output_buyer_utxo,
        output_sm_utxo,
      ],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 5 * 60 * 1000),
    ),
    cfg,
    input_bidding_datum,
    owner_address,
    sm_address,
  )
}

test bidding_sell_succ_bond_policy_id_valid() {
  let time_of_tx = 1681095094000
  let cfg = get_config_mainnet()
  let owner_address = get_buyer_address()
  let seller_address = get_seller_address()
  let input_bidding_datum = gen_bidding_datum(owner_address, 390, 480, 5, 500)
  let bond_name_1 = get_bond_id_1()
  //
  let escrow_datum = get_escrow_datum(bond_name_1, 10000, 753424657, 72, 63)
  let escrow_lovelace = 1017328767112
  let escrow_full_info =
    calc_escrow_full_info(cfg.bond, escrow_lovelace, escrow_datum, time_of_tx)
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.received_at_maturity_one_bond,
      escrow_full_info.day_to_maturity,
      input_bidding_datum.requested_yield,
      cfg.bond.basis_points_ref_unit,
    )
  //  
  let bond_sell_qty = 5
  let received_at_maturity =
    escrow_full_info.received_at_maturity_one_bond * bond_sell_qty
  let received_with_yield = price_of_one_bond * bond_sell_qty
  let received_diff = received_at_maturity - received_with_yield
  let market_fee_seller =
    received_diff * cfg.market.seller_fee / cfg.bond.basis_points_ref_unit
  let market_fee_buyer =
    received_diff * cfg.market.buyer_fee / cfg.bond.basis_points_ref_unit
  //
  let output_buyer_lovelace = 1310316
  let sm_address = get_smart_contract_address()
  let sm_input_lovelace =
    received_with_yield + market_fee_buyer + output_buyer_lovelace
  let input_sm_1 =
    gen_input(
      sm_address,
      sm_input_lovelace,
      None,
      InlineDatum(input_bidding_datum),
    )
  let input_seller_lovelace = 1310316
  let asset_sell =
    value.from_asset(get_bond_policy_id(), bond_name_1, bond_sell_qty)
  let input_seller_1 =
    gen_input(seller_address, input_seller_lovelace, Some(asset_sell), NoDatum)
  let reference_input_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  //
  let market_address = get_market_address()
  let output_market_lovelace = market_fee_buyer + market_fee_seller
  let output_market_utxo =
    gen_output(market_address, output_market_lovelace, None, NoDatum)
  let output_seller_lovelace =
    input_seller_lovelace + received_with_yield - market_fee_seller
  let output_seller_utxo =
    gen_output(seller_address, output_seller_lovelace, None, NoDatum)
  let output_buyer_utxo =
    gen_output(owner_address, output_buyer_lovelace, Some(asset_sell), NoDatum)
  let output_sm_lovelace =
    sm_input_lovelace - received_with_yield - market_fee_buyer - output_buyer_lovelace
  let output_bidding_datum =
    gen_bidding_datum(
      owner_address,
      390,
      480,
      input_bidding_datum.quantity - bond_sell_qty,
      500,
    )
  let output_sm_utxo =
    gen_output(
      sm_address,
      output_sm_lovelace,
      None,
      InlineDatum(output_bidding_datum),
    )
  validation_bidding.sell(
    fixture.tx(
      [input_sm_1, input_seller_1],
      [reference_input_1],
      [
        output_market_utxo,
        output_seller_utxo,
        output_buyer_utxo,
        output_sm_utxo,
      ],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 5 * 60 * 1000),
    ),
    cfg,
    input_bidding_datum,
    owner_address,
    sm_address,
  )
}

test bidding_sell_fail_bond_policy_id_invalid() {
  let time_of_tx = 1681095094000
  let cfg = get_config_mainnet()
  let owner_address = get_buyer_address()
  let seller_address = get_seller_address()
  let input_bidding_datum = gen_bidding_datum(owner_address, 390, 480, 5, 500)
  let bond_name_1 = get_bond_id_1()
  //
  let escrow_datum = get_escrow_datum(bond_name_1, 10000, 753424657, 72, 63)
  let escrow_lovelace = 1017328767112
  let escrow_full_info =
    calc_escrow_full_info(cfg.bond, escrow_lovelace, escrow_datum, time_of_tx)
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.received_at_maturity_one_bond,
      escrow_full_info.day_to_maturity,
      input_bidding_datum.requested_yield,
      cfg.bond.basis_points_ref_unit,
    )
  //  
  let bond_sell_qty = 5
  let received_at_maturity =
    escrow_full_info.received_at_maturity_one_bond * bond_sell_qty
  let received_with_yield = price_of_one_bond * bond_sell_qty
  let received_diff = received_at_maturity - received_with_yield
  let market_fee_seller =
    received_diff * cfg.market.seller_fee / cfg.bond.basis_points_ref_unit
  let market_fee_buyer =
    received_diff * cfg.market.buyer_fee / cfg.bond.basis_points_ref_unit
  //
  let output_buyer_lovelace = 1310316
  let sm_address = get_smart_contract_address()
  let sm_input_lovelace =
    received_with_yield + market_fee_buyer + output_buyer_lovelace
  let input_sm_1 =
    gen_input(
      sm_address,
      sm_input_lovelace,
      None,
      InlineDatum(input_bidding_datum),
    )
  let input_seller_lovelace = 1310316
  let asset_sell =
    value.from_asset(get_not_bond_policy_id(), bond_name_1, bond_sell_qty)
  let input_seller_1 =
    gen_input(seller_address, input_seller_lovelace, Some(asset_sell), NoDatum)
  let reference_input_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  //
  let market_address = get_market_address()
  let output_market_lovelace = market_fee_buyer + market_fee_seller
  let output_market_utxo =
    gen_output(market_address, output_market_lovelace, None, NoDatum)
  let output_seller_lovelace =
    input_seller_lovelace + received_with_yield - market_fee_seller
  let output_seller_utxo =
    gen_output(seller_address, output_seller_lovelace, None, NoDatum)
  let output_buyer_utxo =
    gen_output(owner_address, output_buyer_lovelace, Some(asset_sell), NoDatum)
  let output_sm_lovelace =
    sm_input_lovelace - received_with_yield - market_fee_buyer - output_buyer_lovelace
  let output_bidding_datum =
    gen_bidding_datum(
      owner_address,
      390,
      480,
      input_bidding_datum.quantity - bond_sell_qty,
      500,
    )
  let output_sm_utxo =
    gen_output(
      sm_address,
      output_sm_lovelace,
      None,
      InlineDatum(output_bidding_datum),
    )
  !validation_bidding.sell(
    fixture.tx(
      [input_sm_1, input_seller_1],
      [reference_input_1],
      [
        output_market_utxo,
        output_seller_utxo,
        output_buyer_utxo,
        output_sm_utxo,
      ],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 5 * 60 * 1000),
    ),
    cfg,
    input_bidding_datum,
    owner_address,
    sm_address,
  )
}
