use aiken/builtin
use aiken/bytearray
use aiken/dict
use aiken/hash.{blake2b_256}
use aiken/transaction.{DatumHash, InlineDatum, NoDatum}
use aiken/transaction/value
use bond/fixture.{
  calc_escrow_full_info, get_bond_id_1, get_bond_id_2, get_bond_policy_id,
  get_buyer_address, get_config_test_1, get_config_test_2, get_escrow_datum,
  get_escrow_policy_id, get_input_escrow, get_input_listing, get_listing_datum,
  get_market_address, get_not_escrow_policy_id, get_output_listing,
  get_owner_address, get_owner_address_hash, get_payment_datum,
  get_smart_contract_address, scripthash_address,
}
use bond/utils.{get_price_of_bond}
use bond/validation_listing

test listing_buy_partial_failure_must_only_one_bond_1() {
  let time_of_tx =
    1681095094000
  let config_test_2 =
    get_config_test_2()
  let owner_address =
    get_owner_address()
  let listing_datum =
    get_listing_datum(owner_address, 515)
  let bond_name_listing_1 =
    get_bond_id_1()
  let bond_name_listing_2 =
    get_bond_id_2()
  let escrow_datum =
    get_escrow_datum(bond_name_listing_1, 10000, 753424657, 72, 63)
  let escrow_lovelace =
    1017328767112
  let escrow_full_info =
    calc_escrow_full_info(
      config_test_2.bond,
      escrow_lovelace,
      escrow_datum,
      time_of_tx,
    )
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.received_at_maturity_one_bond,
      escrow_full_info.day_to_maturity,
      listing_datum.requested_yield,
      config_test_2.bond.basis_points_ref_unit,
    )
  //
  let reference_input_1 =
    get_input_escrow(
      get_escrow_policy_id(),
      bond_name_listing_1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  //
  let sm_qty_input =
    5
  let sm_min_ada_input =
    2068800
  let sm_address =
    get_smart_contract_address()
  let input_sm_bond_spending_1 =
    get_input_listing(
      sm_address,
      sm_min_ada_input,
      Some(
        value.add(
          value.from_asset(
            get_bond_policy_id(),
            bond_name_listing_1,
            sm_qty_input,
          ),
          value.from_asset(get_bond_policy_id(), bond_name_listing_2, 3),
        ),
      ),
      InlineDatum(listing_datum),
    )
  let buyer_fee_ada =
    3000000000
  let buyer_address =
    get_buyer_address()
  let input_buyer_1 =
    get_input_listing(
      buyer_address,
      buyer_fee_ada,
      Some(value.from_asset(get_bond_policy_id(), bond_name_listing_2, 3)),
      NoDatum,
    )
  //
  let buyer_qty =
    2
  let received_at_maturity =
    escrow_full_info.received_at_maturity_one_bond * buyer_qty
  let received_with_yield =
    price_of_one_bond * buyer_qty
  let received_diff =
    received_at_maturity - received_with_yield
  let market_fee_seller =
    received_diff * config_test_2.market.seller_fee / config_test_2.bond.basis_points_ref_unit
  let market_fee_buyer =
    received_diff * config_test_2.market.buyer_fee / config_test_2.bond.basis_points_ref_unit
  //
  let min_ada_to_market =
    when sm_qty_input - buyer_qty is {
      0 ->
        sm_min_ada_input
      _ ->
        0
    }
  let market_received =
    market_fee_buyer + market_fee_seller + min_ada_to_market

  // market_received == 82755 * 2
  let payment_datum =
    get_payment_datum()
  let payment_datum_data =
    builtin.serialise_data(payment_datum)
  let payment_datum_hash =
    blake2b_256(payment_datum_data)
  let tx_datums =
    dict.new()
      |> dict.insert(
           payment_datum_hash,
           builtin.b_data(payment_datum_data),
           bytearray.compare,
         )
  let market_address =
    get_market_address()
  let output_market =
    get_output_listing(
      market_address,
      market_received,
      None,
      DatumHash(payment_datum_hash),
    )
  let owner_received =
    received_with_yield - market_fee_seller
  let output_owner =
    get_output_listing(
      owner_address,
      owner_received,
      None,
      DatumHash(payment_datum_hash),
    )
  let buyer_received =
    buyer_fee_ada + sm_min_ada_input - market_received - owner_received
  let output_buyer =
    get_output_listing(
      buyer_address,
      buyer_received,
      Some(
        value.add(
          value.from_asset(get_bond_policy_id(), bond_name_listing_2, buyer_qty),
          value.from_asset(get_bond_policy_id(), bond_name_listing_1, 6),
        ),
      ),
      DatumHash(payment_datum_hash),
    )
  let output_sm =
    get_output_listing(
      sm_address,
      sm_min_ada_input - min_ada_to_market,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_listing_1,
          sm_qty_input - buyer_qty,
        ),
      ),
      InlineDatum(listing_datum),
    )
  !validation_listing.buy(
    fixture.tx(
      [input_sm_bond_spending_1, input_buyer_1],
      [reference_input_1],
      [output_market, output_owner, output_buyer, output_sm],
      Some([get_owner_address_hash()]),
      Some(tx_datums),
      Some(time_of_tx),
    ),
    config_test_2,
    input_sm_bond_spending_1,
    listing_datum.requested_yield,
    owner_address,
    sm_address,
  )
}

test listing_buy_partial_failure_must_only_one_bond_2() {
  let time_of_tx =
    1681095094000
  let config_test_2 =
    get_config_test_2()
  let owner_address =
    get_owner_address()
  let listing_datum =
    get_listing_datum(owner_address, 515)
  let bond_name_listing_1 =
    get_bond_id_1()
  let bond_name_listing_2 =
    get_bond_id_2()
  let escrow_datum =
    get_escrow_datum(bond_name_listing_1, 10000, 753424657, 72, 63)
  let escrow_lovelace =
    1017328767112
  let escrow_full_info =
    calc_escrow_full_info(
      config_test_2.bond,
      escrow_lovelace,
      escrow_datum,
      time_of_tx,
    )
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.received_at_maturity_one_bond,
      escrow_full_info.day_to_maturity,
      listing_datum.requested_yield,
      config_test_2.bond.basis_points_ref_unit,
    )
  //
  let reference_input_1 =
    get_input_escrow(
      get_escrow_policy_id(),
      bond_name_listing_1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  //
  let sm_qty_input =
    5
  let sm_min_ada_input =
    2068800
  let sm_address =
    get_smart_contract_address()
  let input_sm_bond_spending_1 =
    get_input_listing(
      sm_address,
      sm_min_ada_input,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_listing_1,
          sm_qty_input,
        ),
      ),
      InlineDatum(listing_datum),
    )
  let input_sm_bond_spending_2 =
    get_input_listing(
      sm_address,
      sm_min_ada_input,
      Some(value.from_asset(get_bond_policy_id(), bond_name_listing_2, 3)),
      InlineDatum(listing_datum),
    )
  let buyer_fee_ada =
    3000000000
  let buyer_address =
    get_buyer_address()
  let input_buyer_1 =
    get_input_listing(
      buyer_address,
      buyer_fee_ada,
      Some(value.from_asset(get_bond_policy_id(), bond_name_listing_2, 3)),
      NoDatum,
    )
  //
  let buyer_qty =
    2
  let received_at_maturity =
    escrow_full_info.received_at_maturity_one_bond * buyer_qty
  let received_with_yield =
    price_of_one_bond * buyer_qty
  let received_diff =
    received_at_maturity - received_with_yield
  let market_fee_seller =
    received_diff * config_test_2.market.seller_fee / config_test_2.bond.basis_points_ref_unit
  let market_fee_buyer =
    received_diff * config_test_2.market.buyer_fee / config_test_2.bond.basis_points_ref_unit
  //
  let min_ada_to_market =
    when sm_qty_input - buyer_qty is {
      0 ->
        sm_min_ada_input
      _ ->
        0
    }
  let market_received =
    market_fee_buyer + market_fee_seller + min_ada_to_market

  // market_received == 82755 * 2
  let payment_datum =
    get_payment_datum()
  let payment_datum_data =
    builtin.serialise_data(payment_datum)
  let payment_datum_hash =
    blake2b_256(payment_datum_data)
  let tx_datums =
    dict.new()
      |> dict.insert(
           payment_datum_hash,
           builtin.b_data(payment_datum_data),
           bytearray.compare,
         )
  let market_address =
    get_market_address()
  let output_market =
    get_output_listing(
      market_address,
      market_received,
      None,
      DatumHash(payment_datum_hash),
    )
  let owner_received =
    received_with_yield - market_fee_seller
  let output_owner =
    get_output_listing(
      owner_address,
      owner_received,
      None,
      DatumHash(payment_datum_hash),
    )
  let buyer_received =
    buyer_fee_ada + sm_min_ada_input - market_received - owner_received
  let output_buyer =
    get_output_listing(
      buyer_address,
      buyer_received,
      Some(
        value.add(
          value.from_asset(get_bond_policy_id(), bond_name_listing_2, buyer_qty),
          value.from_asset(get_bond_policy_id(), bond_name_listing_1, 6),
        ),
      ),
      DatumHash(payment_datum_hash),
    )
  let output_sm =
    get_output_listing(
      sm_address,
      sm_min_ada_input - min_ada_to_market,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_listing_1,
          sm_qty_input - buyer_qty,
        ),
      ),
      InlineDatum(listing_datum),
    )
  !validation_listing.buy(
    fixture.tx(
      [input_sm_bond_spending_1, input_sm_bond_spending_2, input_buyer_1],
      [reference_input_1],
      [output_market, output_owner, output_buyer, output_sm],
      Some([get_owner_address_hash()]),
      Some(tx_datums),
      Some(time_of_tx),
    ),
    config_test_2,
    input_sm_bond_spending_1,
    listing_datum.requested_yield,
    owner_address,
    sm_address,
  )
}

test listing_buy_partial_failure_change_bond_name_1() {
  let time_of_tx =
    1681095094000
  let config_test_2 =
    get_config_test_2()
  let owner_address =
    get_owner_address()
  let listing_datum =
    get_listing_datum(owner_address, 515)
  let bond_name_listing_1 =
    get_bond_id_1()
  let bond_name_listing_2 =
    get_bond_id_2()
  let escrow_datum =
    get_escrow_datum(bond_name_listing_1, 10000, 753424657, 72, 63)
  let escrow_lovelace =
    1017328767112
  let escrow_full_info =
    calc_escrow_full_info(
      config_test_2.bond,
      escrow_lovelace,
      escrow_datum,
      time_of_tx,
    )
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.received_at_maturity_one_bond,
      escrow_full_info.day_to_maturity,
      listing_datum.requested_yield,
      config_test_2.bond.basis_points_ref_unit,
    )
  //
  let reference_input_1 =
    get_input_escrow(
      get_escrow_policy_id(),
      bond_name_listing_1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  //
  let sm_qty_input =
    5
  let sm_min_ada_input =
    2068800
  let sm_address =
    get_smart_contract_address()
  let input_sm_bond_spending_1 =
    get_input_listing(
      sm_address,
      sm_min_ada_input,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_listing_1,
          sm_qty_input,
        ),
      ),
      InlineDatum(listing_datum),
    )
  let buyer_fee_ada =
    3000000000
  let buyer_address =
    get_buyer_address()
  let input_buyer_1 =
    get_input_listing(
      buyer_address,
      buyer_fee_ada,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_listing_2,
          sm_qty_input,
        ),
      ),
      NoDatum,
    )
  //
  let buyer_qty =
    0
  let received_at_maturity =
    escrow_full_info.received_at_maturity_one_bond * buyer_qty
  let received_with_yield =
    price_of_one_bond * buyer_qty
  let received_diff =
    received_at_maturity - received_with_yield
  let market_fee_seller =
    received_diff * config_test_2.market.seller_fee / config_test_2.bond.basis_points_ref_unit
  let market_fee_buyer =
    received_diff * config_test_2.market.buyer_fee / config_test_2.bond.basis_points_ref_unit
  //
  let min_ada_to_market =
    when sm_qty_input - buyer_qty is {
      0 ->
        sm_min_ada_input
      _ ->
        0
    }
  let market_received =
    market_fee_buyer + market_fee_seller + min_ada_to_market

  // market_received == 82755 * 2
  let payment_datum =
    get_payment_datum()
  let payment_datum_data =
    builtin.serialise_data(payment_datum)
  let payment_datum_hash =
    blake2b_256(payment_datum_data)
  let tx_datums =
    dict.new()
      |> dict.insert(
           payment_datum_hash,
           builtin.b_data(payment_datum_data),
           bytearray.compare,
         )
  let market_address =
    get_market_address()
  let output_market =
    get_output_listing(
      market_address,
      market_received,
      None,
      DatumHash(payment_datum_hash),
    )
  let owner_received =
    received_with_yield - market_fee_seller
  let output_owner =
    get_output_listing(
      owner_address,
      owner_received,
      None,
      DatumHash(payment_datum_hash),
    )
  let buyer_received =
    buyer_fee_ada + sm_min_ada_input - market_received - owner_received
  let output_buyer =
    get_output_listing(
      buyer_address,
      buyer_received,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_listing_1,
          sm_qty_input,
        ),
      ),
      DatumHash(payment_datum_hash),
    )
  let output_sm =
    get_output_listing(
      sm_address,
      sm_min_ada_input - min_ada_to_market,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_listing_2,
          sm_qty_input,
        ),
      ),
      InlineDatum(listing_datum),
    )
  !validation_listing.buy(
    fixture.tx(
      [input_sm_bond_spending_1, input_buyer_1],
      [reference_input_1],
      [output_market, output_owner, output_buyer, output_sm],
      Some([get_owner_address_hash()]),
      Some(tx_datums),
      Some(time_of_tx),
    ),
    config_test_2,
    input_sm_bond_spending_1,
    listing_datum.requested_yield,
    owner_address,
    sm_address,
  )
}

test listing_buy_partial_failure_listing_datum_owner_invalid_1() {
  let time_of_tx =
    1681095094000
  let config_test_2 =
    get_config_test_2()
  let owner_address =
    get_owner_address()
  let listing_datum =
    get_listing_datum(scripthash_address(#"010203040506"), 515)
  let bond_name_listing_1 =
    get_bond_id_1()
  let bond_name_listing_2 =
    get_bond_id_2()
  let escrow_datum =
    get_escrow_datum(bond_name_listing_1, 10000, 753424657, 72, 63)
  let escrow_lovelace =
    1017328767112
  let escrow_full_info =
    calc_escrow_full_info(
      config_test_2.bond,
      escrow_lovelace,
      escrow_datum,
      time_of_tx,
    )
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.received_at_maturity_one_bond,
      escrow_full_info.day_to_maturity,
      listing_datum.requested_yield,
      config_test_2.bond.basis_points_ref_unit,
    )
  //
  let reference_input_1 =
    get_input_escrow(
      get_escrow_policy_id(),
      bond_name_listing_1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  //
  let sm_qty_input =
    5
  let sm_min_ada_input =
    2068800
  let sm_address =
    get_smart_contract_address()
  let input_sm_bond_spending_1 =
    get_input_listing(
      sm_address,
      sm_min_ada_input,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_listing_1,
          sm_qty_input,
        ),
      ),
      InlineDatum(listing_datum),
    )
  let buyer_fee_ada =
    3000000000
  let buyer_address =
    get_buyer_address()
  let input_buyer_1 =
    get_input_listing(
      buyer_address,
      buyer_fee_ada,
      Some(value.from_asset(get_bond_policy_id(), bond_name_listing_2, 3)),
      NoDatum,
    )
  //
  let buyer_qty =
    2
  let received_at_maturity =
    escrow_full_info.received_at_maturity_one_bond * buyer_qty
  let received_with_yield =
    price_of_one_bond * buyer_qty
  let received_diff =
    received_at_maturity - received_with_yield
  let market_fee_seller =
    received_diff * config_test_2.market.seller_fee / config_test_2.bond.basis_points_ref_unit
  let market_fee_buyer =
    received_diff * config_test_2.market.buyer_fee / config_test_2.bond.basis_points_ref_unit
  //
  let min_ada_to_market =
    when sm_qty_input - buyer_qty is {
      0 ->
        sm_min_ada_input
      _ ->
        0
    }
  let market_received =
    market_fee_buyer + market_fee_seller + min_ada_to_market

  // market_received == 82755 * 2
  let payment_datum =
    get_payment_datum()
  let payment_datum_data =
    builtin.serialise_data(payment_datum)
  let payment_datum_hash =
    blake2b_256(payment_datum_data)
  let tx_datums =
    dict.new()
      |> dict.insert(
           payment_datum_hash,
           builtin.b_data(payment_datum_data),
           bytearray.compare,
         )
  let market_address =
    get_market_address()
  let output_market =
    get_output_listing(
      market_address,
      market_received,
      None,
      DatumHash(payment_datum_hash),
    )
  let owner_received =
    received_with_yield - market_fee_seller
  let output_owner =
    get_output_listing(
      owner_address,
      owner_received,
      None,
      DatumHash(payment_datum_hash),
    )
  let buyer_received =
    buyer_fee_ada + sm_min_ada_input - market_received - owner_received
  let output_buyer =
    get_output_listing(
      buyer_address,
      buyer_received,
      Some(
        value.add(
          value.from_asset(get_bond_policy_id(), bond_name_listing_2, buyer_qty),
          value.from_asset(get_bond_policy_id(), bond_name_listing_1, 3),
        ),
      ),
      DatumHash(payment_datum_hash),
    )
  let output_sm =
    get_output_listing(
      sm_address,
      sm_min_ada_input - min_ada_to_market,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_listing_1,
          sm_qty_input - buyer_qty,
        ),
      ),
      InlineDatum(listing_datum),
    )
  !validation_listing.buy(
    fixture.tx(
      [input_sm_bond_spending_1, input_buyer_1],
      [reference_input_1],
      [output_market, output_owner, output_buyer, output_sm],
      Some([get_owner_address_hash()]),
      Some(tx_datums),
      Some(time_of_tx),
    ),
    config_test_2,
    input_sm_bond_spending_1,
    listing_datum.requested_yield,
    owner_address,
    sm_address,
  )
}

test listing_buy_partial_failure_invalid_escrow_datum() {
  let time_of_tx =
    1681095094000
  let config_test_2 =
    get_config_test_2()
  let owner_address =
    get_owner_address()
  let listing_datum =
    get_listing_datum(owner_address, 515)
  let bond_name_listing_1 =
    get_bond_id_1()
  let bond_name_listing_2 =
    get_bond_id_2()
  let escrow_datum =
    get_escrow_datum(bond_name_listing_1, 10000, 753424657, 72, 63)
  let escrow_lovelace =
    1017328767112
  let escrow_full_info =
    calc_escrow_full_info(
      config_test_2.bond,
      escrow_lovelace,
      escrow_datum,
      time_of_tx,
    )
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.received_at_maturity_one_bond,
      escrow_full_info.day_to_maturity,
      listing_datum.requested_yield,
      config_test_2.bond.basis_points_ref_unit,
    )
  //
  let reference_input_1 =
    get_input_escrow(
      get_escrow_policy_id(),
      bond_name_listing_1,
      escrow_lovelace,
      InlineDatum(listing_datum),
    )
  //
  let sm_qty_input =
    5
  let sm_min_ada_input =
    2068800
  let sm_address =
    get_smart_contract_address()
  let input_sm_bond_spending_1 =
    get_input_listing(
      sm_address,
      sm_min_ada_input,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_listing_1,
          sm_qty_input,
        ),
      ),
      InlineDatum(listing_datum),
    )
  let buyer_fee_ada =
    3000000000
  let buyer_address =
    get_buyer_address()
  let input_buyer_1 =
    get_input_listing(
      buyer_address,
      buyer_fee_ada,
      Some(value.from_asset(get_bond_policy_id(), bond_name_listing_2, 3)),
      NoDatum,
    )
  //
  let buyer_qty =
    2
  let received_at_maturity =
    escrow_full_info.received_at_maturity_one_bond * buyer_qty
  let received_with_yield =
    price_of_one_bond * buyer_qty
  let received_diff =
    received_at_maturity - received_with_yield
  let market_fee_seller =
    received_diff * config_test_2.market.seller_fee / config_test_2.bond.basis_points_ref_unit
  let market_fee_buyer =
    received_diff * config_test_2.market.buyer_fee / config_test_2.bond.basis_points_ref_unit
  //
  let min_ada_to_market =
    when sm_qty_input - buyer_qty is {
      0 ->
        sm_min_ada_input
      _ ->
        0
    }
  let market_received =
    market_fee_buyer + market_fee_seller + min_ada_to_market

  // market_received == 82755 * 2
  let payment_datum =
    get_payment_datum()
  let payment_datum_data =
    builtin.serialise_data(payment_datum)
  let payment_datum_hash =
    blake2b_256(payment_datum_data)
  let tx_datums =
    dict.new()
      |> dict.insert(
           payment_datum_hash,
           builtin.b_data(payment_datum_data),
           bytearray.compare,
         )
  let market_address =
    get_market_address()
  let output_market =
    get_output_listing(
      market_address,
      market_received,
      None,
      DatumHash(payment_datum_hash),
    )
  let owner_received =
    received_with_yield - market_fee_seller
  let output_owner =
    get_output_listing(
      owner_address,
      owner_received,
      None,
      DatumHash(payment_datum_hash),
    )
  let buyer_received =
    buyer_fee_ada + sm_min_ada_input - market_received - owner_received
  let output_buyer =
    get_output_listing(
      buyer_address,
      buyer_received,
      Some(
        value.add(
          value.from_asset(get_bond_policy_id(), bond_name_listing_2, buyer_qty),
          value.from_asset(get_bond_policy_id(), bond_name_listing_1, 3),
        ),
      ),
      DatumHash(payment_datum_hash),
    )
  let output_sm =
    get_output_listing(
      sm_address,
      sm_min_ada_input - min_ada_to_market,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_listing_1,
          sm_qty_input - buyer_qty,
        ),
      ),
      InlineDatum(listing_datum),
    )
  !validation_listing.buy(
    fixture.tx(
      [input_sm_bond_spending_1, input_buyer_1],
      [reference_input_1],
      [output_market, output_owner, output_buyer, output_sm],
      Some([get_owner_address_hash()]),
      Some(tx_datums),
      Some(time_of_tx),
    ),
    config_test_2,
    input_sm_bond_spending_1,
    listing_datum.requested_yield,
    owner_address,
    sm_address,
  )
}

test listing_buy_partial_failure_invalid_escrow_policy_id() {
  let time_of_tx =
    1681095094000
  let config_test_2 =
    get_config_test_2()
  let owner_address =
    get_owner_address()
  let listing_datum =
    get_listing_datum(owner_address, 515)
  let bond_name_listing_1 =
    get_bond_id_1()
  let bond_name_listing_2 =
    get_bond_id_2()
  let escrow_datum =
    get_escrow_datum(bond_name_listing_1, 10000, 753424657, 72, 63)
  let escrow_lovelace =
    1017328767112
  let escrow_full_info =
    calc_escrow_full_info(
      config_test_2.bond,
      escrow_lovelace,
      escrow_datum,
      time_of_tx,
    )
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.received_at_maturity_one_bond,
      escrow_full_info.day_to_maturity,
      listing_datum.requested_yield,
      config_test_2.bond.basis_points_ref_unit,
    )
  //
  let reference_input_1 =
    get_input_escrow(
      get_not_escrow_policy_id(),
      bond_name_listing_1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  //
  let sm_qty_input =
    5
  let sm_min_ada_input =
    2068800
  let sm_address =
    get_smart_contract_address()
  let input_sm_bond_spending_1 =
    get_input_listing(
      sm_address,
      sm_min_ada_input,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_listing_1,
          sm_qty_input,
        ),
      ),
      InlineDatum(listing_datum),
    )
  let input_sm_bond_spending_2 =
    get_input_listing(
      sm_address,
      sm_min_ada_input,
      Some(value.from_asset(get_bond_policy_id(), bond_name_listing_2, 3)),
      InlineDatum(listing_datum),
    )
  let buyer_fee_ada =
    3000000000
  let buyer_address =
    get_buyer_address()
  let input_buyer_1 =
    get_input_listing(
      buyer_address,
      buyer_fee_ada,
      Some(value.from_asset(get_bond_policy_id(), bond_name_listing_2, 3)),
      NoDatum,
    )
  //
  let buyer_qty =
    2
  let received_at_maturity =
    escrow_full_info.received_at_maturity_one_bond * buyer_qty
  let received_with_yield =
    price_of_one_bond * buyer_qty
  let received_diff =
    received_at_maturity - received_with_yield
  let market_fee_seller =
    received_diff * config_test_2.market.seller_fee / config_test_2.bond.basis_points_ref_unit
  let market_fee_buyer =
    received_diff * config_test_2.market.buyer_fee / config_test_2.bond.basis_points_ref_unit
  //
  let min_ada_to_market =
    when sm_qty_input - buyer_qty is {
      0 ->
        sm_min_ada_input
      _ ->
        0
    }
  let market_received =
    market_fee_buyer + market_fee_seller + min_ada_to_market

  // market_received == 82755 * 2
  let payment_datum =
    get_payment_datum()
  let payment_datum_data =
    builtin.serialise_data(payment_datum)
  let payment_datum_hash =
    blake2b_256(payment_datum_data)
  let tx_datums =
    dict.new()
      |> dict.insert(
           payment_datum_hash,
           builtin.b_data(payment_datum_data),
           bytearray.compare,
         )
  let market_address =
    get_market_address()
  let output_market =
    get_output_listing(
      market_address,
      market_received,
      None,
      DatumHash(payment_datum_hash),
    )
  let owner_received =
    received_with_yield - market_fee_seller
  let output_owner =
    get_output_listing(
      owner_address,
      owner_received,
      None,
      DatumHash(payment_datum_hash),
    )
  let buyer_received =
    buyer_fee_ada + sm_min_ada_input - market_received - owner_received
  let output_buyer =
    get_output_listing(
      buyer_address,
      buyer_received,
      Some(
        value.add(
          value.from_asset(get_bond_policy_id(), bond_name_listing_2, buyer_qty),
          value.from_asset(get_bond_policy_id(), bond_name_listing_1, 6),
        ),
      ),
      DatumHash(payment_datum_hash),
    )
  let output_sm =
    get_output_listing(
      sm_address,
      sm_min_ada_input - min_ada_to_market,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_listing_1,
          sm_qty_input - buyer_qty,
        ),
      ),
      InlineDatum(listing_datum),
    )
  !validation_listing.buy(
    fixture.tx(
      [input_sm_bond_spending_1, input_sm_bond_spending_2, input_buyer_1],
      [reference_input_1],
      [output_market, output_owner, output_buyer, output_sm],
      Some([get_owner_address_hash()]),
      Some(tx_datums),
      Some(time_of_tx),
    ),
    config_test_2,
    input_sm_bond_spending_1,
    listing_datum.requested_yield,
    owner_address,
    sm_address,
  )
}

test listing_buy_partial_failure_invalid_escrow_nodatum() {
  let time_of_tx =
    1681095094000
  let config_test_2 =
    get_config_test_2()
  let owner_address =
    get_owner_address()
  let listing_datum =
    get_listing_datum(owner_address, 515)
  let bond_name_listing_1 =
    get_bond_id_1()
  let bond_name_listing_2 =
    get_bond_id_2()
  let escrow_datum =
    get_escrow_datum(bond_name_listing_1, 10000, 753424657, 72, 63)
  let escrow_lovelace =
    1017328767112
  let escrow_full_info =
    calc_escrow_full_info(
      config_test_2.bond,
      escrow_lovelace,
      escrow_datum,
      time_of_tx,
    )
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.received_at_maturity_one_bond,
      escrow_full_info.day_to_maturity,
      listing_datum.requested_yield,
      config_test_2.bond.basis_points_ref_unit,
    )
  //
  let reference_input_1 =
    get_input_escrow(
      get_escrow_policy_id(),
      bond_name_listing_1,
      escrow_lovelace,
      NoDatum,
    )
  //
  let sm_qty_input =
    5
  let sm_min_ada_input =
    2068800
  let sm_address =
    get_smart_contract_address()
  let input_sm_bond_spending_1 =
    get_input_listing(
      sm_address,
      sm_min_ada_input,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_listing_1,
          sm_qty_input,
        ),
      ),
      InlineDatum(listing_datum),
    )
  let buyer_fee_ada =
    3000000000
  let buyer_address =
    get_buyer_address()
  let input_buyer_1 =
    get_input_listing(
      buyer_address,
      buyer_fee_ada,
      Some(value.from_asset(get_bond_policy_id(), bond_name_listing_2, 3)),
      NoDatum,
    )
  //
  let buyer_qty =
    2
  let received_at_maturity =
    escrow_full_info.received_at_maturity_one_bond * buyer_qty
  let received_with_yield =
    price_of_one_bond * buyer_qty
  let received_diff =
    received_at_maturity - received_with_yield
  let market_fee_seller =
    received_diff * config_test_2.market.seller_fee / config_test_2.bond.basis_points_ref_unit
  let market_fee_buyer =
    received_diff * config_test_2.market.buyer_fee / config_test_2.bond.basis_points_ref_unit
  //
  let min_ada_to_market =
    when sm_qty_input - buyer_qty is {
      0 ->
        sm_min_ada_input
      _ ->
        0
    }
  let market_received =
    market_fee_buyer + market_fee_seller + min_ada_to_market

  // market_received == 82755 * 2
  let payment_datum =
    get_payment_datum()
  let payment_datum_data =
    builtin.serialise_data(payment_datum)
  let payment_datum_hash =
    blake2b_256(payment_datum_data)
  let tx_datums =
    dict.new()
      |> dict.insert(
           payment_datum_hash,
           builtin.b_data(payment_datum_data),
           bytearray.compare,
         )
  let market_address =
    get_market_address()
  let output_market =
    get_output_listing(
      market_address,
      market_received,
      None,
      DatumHash(payment_datum_hash),
    )
  let owner_received =
    received_with_yield - market_fee_seller
  let output_owner =
    get_output_listing(
      owner_address,
      owner_received,
      None,
      DatumHash(payment_datum_hash),
    )
  let buyer_received =
    buyer_fee_ada + sm_min_ada_input - market_received - owner_received
  let output_buyer =
    get_output_listing(
      buyer_address,
      buyer_received,
      Some(
        value.add(
          value.from_asset(get_bond_policy_id(), bond_name_listing_1, buyer_qty),
          value.from_asset(get_bond_policy_id(), bond_name_listing_2, 3),
        ),
      ),
      DatumHash(payment_datum_hash),
    )
  let output_sm =
    get_output_listing(
      sm_address,
      sm_min_ada_input - min_ada_to_market,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_listing_1,
          sm_qty_input - buyer_qty,
        ),
      ),
      InlineDatum(listing_datum),
    )
  !validation_listing.buy(
    fixture.tx(
      [input_sm_bond_spending_1, input_buyer_1],
      [reference_input_1],
      [output_market, output_owner, output_buyer, output_sm],
      Some([get_owner_address_hash()]),
      Some(tx_datums),
      Some(time_of_tx),
    ),
    config_test_2,
    input_sm_bond_spending_1,
    listing_datum.requested_yield,
    owner_address,
    sm_address,
  )
}

test listing_buy_partial_failure_invalid_escrow_claimed() {
  let time_of_tx =
    1681095094000
  let config_test_2 =
    get_config_test_2()
  let owner_address =
    get_owner_address()
  let listing_datum =
    get_listing_datum(owner_address, 515)
  let bond_name_listing_1 =
    get_bond_id_1()
  let bond_name_listing_2 =
    get_bond_id_2()
  let claim_amount =
    1000
  let escrow_datum =
    get_escrow_datum(
      bond_name_listing_1,
      10000 - claim_amount,
      753424657,
      72,
      63,
    )
  let escrow_lovelace =
    1017328767112 - 105261917 * claim_amount
  let escrow_full_info =
    calc_escrow_full_info(
      config_test_2.bond,
      escrow_lovelace,
      escrow_datum,
      time_of_tx,
    )
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.received_at_maturity_one_bond,
      escrow_full_info.day_to_maturity,
      listing_datum.requested_yield,
      config_test_2.bond.basis_points_ref_unit,
    )
  //
  let reference_input_1 =
    get_input_escrow(
      get_escrow_policy_id(),
      bond_name_listing_1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  //
  let sm_qty_input =
    5
  let sm_min_ada_input =
    2068800
  let sm_address =
    get_smart_contract_address()
  let input_sm_bond_spending_1 =
    get_input_listing(
      sm_address,
      sm_min_ada_input,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_listing_1,
          sm_qty_input,
        ),
      ),
      InlineDatum(listing_datum),
    )
  let buyer_fee_ada =
    3000000000
  let buyer_address =
    get_buyer_address()
  let input_buyer_1 =
    get_input_listing(
      buyer_address,
      buyer_fee_ada,
      Some(value.from_asset(get_bond_policy_id(), bond_name_listing_2, 3)),
      NoDatum,
    )
  //
  let buyer_qty =
    2
  let received_at_maturity =
    escrow_full_info.received_at_maturity_one_bond * buyer_qty
  let received_with_yield =
    price_of_one_bond * buyer_qty
  let received_diff =
    received_at_maturity - received_with_yield
  let market_fee_seller =
    received_diff * config_test_2.market.seller_fee / config_test_2.bond.basis_points_ref_unit
  let market_fee_buyer =
    received_diff * config_test_2.market.buyer_fee / config_test_2.bond.basis_points_ref_unit
  //
  let min_ada_to_market =
    when sm_qty_input - buyer_qty is {
      0 ->
        sm_min_ada_input
      _ ->
        0
    }
  let market_received =
    market_fee_buyer + market_fee_seller + min_ada_to_market

  // market_received == 82755 * 2
  let payment_datum =
    get_payment_datum()
  let payment_datum_data =
    builtin.serialise_data(payment_datum)
  let payment_datum_hash =
    blake2b_256(payment_datum_data)
  let tx_datums =
    dict.new()
      |> dict.insert(
           payment_datum_hash,
           builtin.b_data(payment_datum_data),
           bytearray.compare,
         )
  let market_address =
    get_market_address()
  let output_market =
    get_output_listing(
      market_address,
      market_received,
      None,
      DatumHash(payment_datum_hash),
    )
  let owner_received =
    received_with_yield - market_fee_seller
  let output_owner =
    get_output_listing(
      owner_address,
      owner_received,
      None,
      DatumHash(payment_datum_hash),
    )
  let buyer_received =
    buyer_fee_ada + sm_min_ada_input - market_received - owner_received
  let output_buyer =
    get_output_listing(
      buyer_address,
      buyer_received,
      Some(
        value.add(
          value.from_asset(get_bond_policy_id(), bond_name_listing_1, buyer_qty),
          value.from_asset(get_bond_policy_id(), bond_name_listing_2, 3),
        ),
      ),
      DatumHash(payment_datum_hash),
    )
  let output_sm =
    get_output_listing(
      sm_address,
      sm_min_ada_input - min_ada_to_market,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_listing_1,
          sm_qty_input - buyer_qty,
        ),
      ),
      InlineDatum(listing_datum),
    )
  !validation_listing.buy(
    fixture.tx(
      [input_sm_bond_spending_1, input_buyer_1],
      [reference_input_1],
      [output_market, output_owner, output_buyer, output_sm],
      Some([get_owner_address_hash()]),
      Some(tx_datums),
      Some(time_of_tx),
    ),
    config_test_2,
    input_sm_bond_spending_1,
    listing_datum.requested_yield,
    owner_address,
    sm_address,
  )
}

test listing_buy_partial_failure_buyer_is_owner_1() {
  let time_of_tx =
    1681095094000
  let config_test_2 =
    get_config_test_2()
  let owner_address =
    get_owner_address()
  let listing_datum =
    get_listing_datum(owner_address, 515)
  let bond_name_listing_1 =
    get_bond_id_1()
  let bond_name_listing_2 =
    get_bond_id_2()
  let escrow_datum =
    get_escrow_datum(bond_name_listing_1, 10000, 753424657, 72, 63)
  let escrow_lovelace =
    1017328767112
  let escrow_full_info =
    calc_escrow_full_info(
      config_test_2.bond,
      escrow_lovelace,
      escrow_datum,
      time_of_tx,
    )
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.received_at_maturity_one_bond,
      escrow_full_info.day_to_maturity,
      listing_datum.requested_yield,
      config_test_2.bond.basis_points_ref_unit,
    )
  //
  let reference_input_1 =
    get_input_escrow(
      get_escrow_policy_id(),
      bond_name_listing_1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  //
  let sm_qty_input =
    5
  let sm_min_ada_input =
    2068800
  let sm_address =
    get_smart_contract_address()
  let input_sm_bond_spending_1 =
    get_input_listing(
      sm_address,
      sm_min_ada_input,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_listing_1,
          sm_qty_input,
        ),
      ),
      InlineDatum(listing_datum),
    )
  let buyer_fee_ada =
    3000000000
  let buyer_address =
    owner_address
  let input_buyer_1 =
    get_input_listing(
      buyer_address,
      buyer_fee_ada,
      Some(value.from_asset(get_bond_policy_id(), bond_name_listing_2, 3)),
      NoDatum,
    )
  //
  let buyer_qty =
    2
  let received_at_maturity =
    escrow_full_info.received_at_maturity_one_bond * buyer_qty
  let received_with_yield =
    price_of_one_bond * buyer_qty
  let received_diff =
    received_at_maturity - received_with_yield
  let market_fee_seller =
    received_diff * config_test_2.market.seller_fee / config_test_2.bond.basis_points_ref_unit
  let market_fee_buyer =
    received_diff * config_test_2.market.buyer_fee / config_test_2.bond.basis_points_ref_unit
  //
  let min_ada_to_market =
    when sm_qty_input - buyer_qty is {
      0 ->
        sm_min_ada_input
      _ ->
        0
    }
  let market_received =
    market_fee_buyer + market_fee_seller + min_ada_to_market

  // market_received == 82755 * 2
  let payment_datum =
    get_payment_datum()
  let payment_datum_data =
    builtin.serialise_data(payment_datum)
  let payment_datum_hash =
    blake2b_256(payment_datum_data)
  let tx_datums =
    dict.new()
      |> dict.insert(
           payment_datum_hash,
           builtin.b_data(payment_datum_data),
           bytearray.compare,
         )
  let market_address =
    get_market_address()
  let output_market =
    get_output_listing(
      market_address,
      market_received,
      None,
      DatumHash(payment_datum_hash),
    )
  let owner_received =
    received_with_yield - market_fee_seller
  let output_owner =
    get_output_listing(
      owner_address,
      owner_received,
      None,
      DatumHash(payment_datum_hash),
    )
  let buyer_received =
    buyer_fee_ada + sm_min_ada_input - market_received - owner_received
  let output_buyer =
    get_output_listing(
      buyer_address,
      buyer_received,
      Some(
        value.add(
          value.from_asset(get_bond_policy_id(), bond_name_listing_2, buyer_qty),
          value.from_asset(get_bond_policy_id(), bond_name_listing_1, 3),
        ),
      ),
      DatumHash(payment_datum_hash),
    )
  let output_sm =
    get_output_listing(
      sm_address,
      sm_min_ada_input - min_ada_to_market,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_listing_1,
          sm_qty_input - buyer_qty,
        ),
      ),
      InlineDatum(listing_datum),
    )
  !validation_listing.buy(
    fixture.tx(
      [input_sm_bond_spending_1, input_buyer_1],
      [reference_input_1],
      [output_market, output_owner, output_buyer, output_sm],
      Some([get_owner_address_hash()]),
      Some(tx_datums),
      Some(time_of_tx),
    ),
    config_test_2,
    input_sm_bond_spending_1,
    listing_datum.requested_yield,
    owner_address,
    sm_address,
  )
}

test listing_buy_partial_failure_buyer_is_market_1() {
  let time_of_tx =
    1681095094000
  let config_test_2 =
    get_config_test_2()
  let market_address =
    get_market_address()
  let owner_address =
    get_owner_address()
  let listing_datum =
    get_listing_datum(owner_address, 515)
  let bond_name_listing_1 =
    get_bond_id_1()
  let bond_name_listing_2 =
    get_bond_id_2()
  let escrow_datum =
    get_escrow_datum(bond_name_listing_1, 10000, 753424657, 72, 63)
  let escrow_lovelace =
    1017328767112
  let escrow_full_info =
    calc_escrow_full_info(
      config_test_2.bond,
      escrow_lovelace,
      escrow_datum,
      time_of_tx,
    )
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.received_at_maturity_one_bond,
      escrow_full_info.day_to_maturity,
      listing_datum.requested_yield,
      config_test_2.bond.basis_points_ref_unit,
    )
  //
  let reference_input_1 =
    get_input_escrow(
      get_escrow_policy_id(),
      bond_name_listing_1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  //
  let sm_qty_input =
    5
  let sm_min_ada_input =
    2068800
  let sm_address =
    get_smart_contract_address()
  let input_sm_bond_spending_1 =
    get_input_listing(
      sm_address,
      sm_min_ada_input,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_listing_1,
          sm_qty_input,
        ),
      ),
      InlineDatum(listing_datum),
    )
  let buyer_fee_ada =
    3000000000
  let buyer_address =
    market_address
  let input_buyer_1 =
    get_input_listing(
      buyer_address,
      buyer_fee_ada,
      Some(value.from_asset(get_bond_policy_id(), bond_name_listing_2, 3)),
      NoDatum,
    )
  //
  let buyer_qty =
    2
  let received_at_maturity =
    escrow_full_info.received_at_maturity_one_bond * buyer_qty
  let received_with_yield =
    price_of_one_bond * buyer_qty
  let received_diff =
    received_at_maturity - received_with_yield
  let market_fee_seller =
    received_diff * config_test_2.market.seller_fee / config_test_2.bond.basis_points_ref_unit
  let market_fee_buyer =
    received_diff * config_test_2.market.buyer_fee / config_test_2.bond.basis_points_ref_unit
  //
  let min_ada_to_market =
    when sm_qty_input - buyer_qty is {
      0 ->
        sm_min_ada_input
      _ ->
        0
    }
  let market_received =
    market_fee_buyer + market_fee_seller + min_ada_to_market

  // market_received == 82755 * 2
  let payment_datum =
    get_payment_datum()
  let payment_datum_data =
    builtin.serialise_data(payment_datum)
  let payment_datum_hash =
    blake2b_256(payment_datum_data)
  let tx_datums =
    dict.new()
      |> dict.insert(
           payment_datum_hash,
           builtin.b_data(payment_datum_data),
           bytearray.compare,
         )
  let output_market =
    get_output_listing(
      market_address,
      market_received,
      None,
      DatumHash(payment_datum_hash),
    )
  let owner_received =
    received_with_yield - market_fee_seller
  let output_owner =
    get_output_listing(
      owner_address,
      owner_received,
      None,
      DatumHash(payment_datum_hash),
    )
  let buyer_received =
    buyer_fee_ada + sm_min_ada_input - market_received - owner_received
  let output_buyer =
    get_output_listing(
      buyer_address,
      buyer_received,
      Some(
        value.add(
          value.from_asset(get_bond_policy_id(), bond_name_listing_2, buyer_qty),
          value.from_asset(get_bond_policy_id(), bond_name_listing_1, 3),
        ),
      ),
      DatumHash(payment_datum_hash),
    )
  let output_sm =
    get_output_listing(
      sm_address,
      sm_min_ada_input - min_ada_to_market,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_listing_1,
          sm_qty_input - buyer_qty,
        ),
      ),
      InlineDatum(listing_datum),
    )
  !validation_listing.buy(
    fixture.tx(
      [input_sm_bond_spending_1, input_buyer_1],
      [reference_input_1],
      [output_market, output_owner, output_buyer, output_sm],
      Some([get_owner_address_hash()]),
      Some(tx_datums),
      Some(time_of_tx),
    ),
    config_test_2,
    input_sm_bond_spending_1,
    listing_datum.requested_yield,
    owner_address,
    sm_address,
  )
}

test listing_buy_partial_success() {
  let time_of_tx =
    1681095094000
  let config_test_2 =
    get_config_test_2()
  let owner_address =
    get_owner_address()
  let listing_datum =
    get_listing_datum(owner_address, 515)
  let bond_name_listing_1 =
    get_bond_id_1()
  let bond_name_listing_2 =
    get_bond_id_2()
  let escrow_datum =
    get_escrow_datum(bond_name_listing_1, 10000, 753424657, 72, 63)
  let escrow_lovelace =
    1017328767112
  let escrow_full_info =
    calc_escrow_full_info(
      config_test_2.bond,
      escrow_lovelace,
      escrow_datum,
      time_of_tx,
    )
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.received_at_maturity_one_bond,
      escrow_full_info.day_to_maturity,
      listing_datum.requested_yield,
      config_test_2.bond.basis_points_ref_unit,
    )
  //
  let reference_input_1 =
    get_input_escrow(
      get_escrow_policy_id(),
      bond_name_listing_1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  //
  let sm_qty_input =
    5
  let sm_min_ada_input =
    2068800
  let sm_address =
    get_smart_contract_address()
  let input_sm_bond_spending_1 =
    get_input_listing(
      sm_address,
      sm_min_ada_input,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_listing_1,
          sm_qty_input,
        ),
      ),
      InlineDatum(listing_datum),
    )
  let buyer_fee_ada =
    3000000000
  let buyer_address =
    get_buyer_address()
  let input_buyer_1 =
    get_input_listing(
      buyer_address,
      buyer_fee_ada,
      Some(value.from_asset(get_bond_policy_id(), bond_name_listing_2, 3)),
      NoDatum,
    )
  //
  let buyer_qty =
    2
  let received_at_maturity =
    escrow_full_info.received_at_maturity_one_bond * buyer_qty
  let received_with_yield =
    price_of_one_bond * buyer_qty
  let received_diff =
    received_at_maturity - received_with_yield
  let market_fee_seller =
    received_diff * config_test_2.market.seller_fee / config_test_2.bond.basis_points_ref_unit
  let market_fee_buyer =
    received_diff * config_test_2.market.buyer_fee / config_test_2.bond.basis_points_ref_unit
  //
  let min_ada_to_market =
    when sm_qty_input - buyer_qty is {
      0 ->
        sm_min_ada_input
      _ ->
        0
    }
  let market_received =
    market_fee_buyer + market_fee_seller + min_ada_to_market

  // market_received == 82755 * 2
  let payment_datum =
    get_payment_datum()
  let payment_datum_data =
    builtin.serialise_data(payment_datum)
  let payment_datum_hash =
    blake2b_256(payment_datum_data)
  let tx_datums =
    dict.new()
      |> dict.insert(
           payment_datum_hash,
           builtin.b_data(payment_datum_data),
           bytearray.compare,
         )
  let market_address =
    get_market_address()
  let output_market =
    get_output_listing(
      market_address,
      market_received,
      None,
      DatumHash(payment_datum_hash),
    )
  let owner_received =
    received_with_yield - market_fee_seller
  let output_owner =
    get_output_listing(
      owner_address,
      owner_received,
      None,
      DatumHash(payment_datum_hash),
    )
  let buyer_received =
    buyer_fee_ada + sm_min_ada_input - market_received - owner_received
  let output_buyer =
    get_output_listing(
      buyer_address,
      buyer_received,
      Some(
        value.add(
          value.from_asset(get_bond_policy_id(), bond_name_listing_2, buyer_qty),
          value.from_asset(get_bond_policy_id(), bond_name_listing_1, 3),
        ),
      ),
      DatumHash(payment_datum_hash),
    )
  let output_sm =
    get_output_listing(
      sm_address,
      sm_min_ada_input - min_ada_to_market,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_listing_1,
          sm_qty_input - buyer_qty,
        ),
      ),
      InlineDatum(listing_datum),
    )
  validation_listing.buy(
    fixture.tx(
      [input_sm_bond_spending_1, input_buyer_1],
      [reference_input_1],
      [output_market, output_owner, output_buyer, output_sm],
      Some([get_owner_address_hash()]),
      Some(tx_datums),
      Some(time_of_tx),
    ),
    config_test_2,
    input_sm_bond_spending_1,
    listing_datum.requested_yield,
    owner_address,
    sm_address,
  )
}

test listing_buy_full_success() {
  let time_of_tx =
    1681095094000
  let config_test_2 =
    get_config_test_2()
  let owner_address =
    get_owner_address()
  let listing_datum =
    get_listing_datum(owner_address, 515)
  let bond_name_listing_1 =
    get_bond_id_1()
  let bond_name_listing_2 =
    get_bond_id_2()
  let escrow_datum =
    get_escrow_datum(bond_name_listing_1, 10000, 753424657, 72, 63)
  let escrow_lovelace =
    1017328767112
  let escrow_full_info =
    calc_escrow_full_info(
      config_test_2.bond,
      escrow_lovelace,
      escrow_datum,
      time_of_tx,
    )
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.received_at_maturity_one_bond,
      escrow_full_info.day_to_maturity,
      listing_datum.requested_yield,
      config_test_2.bond.basis_points_ref_unit,
    )
  //
  let reference_input_1 =
    get_input_escrow(
      get_escrow_policy_id(),
      bond_name_listing_1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  //
  let sm_qty_input =
    5
  let sm_min_ada_input =
    2068800
  let sm_address =
    get_smart_contract_address()
  let input_sm_bond_spending_1 =
    get_input_listing(
      sm_address,
      sm_min_ada_input,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_listing_1,
          sm_qty_input,
        ),
      ),
      InlineDatum(listing_datum),
    )
  let buyer_fee_ada =
    3000000000
  let buyer_address =
    get_buyer_address()
  let input_buyer_1 =
    get_input_listing(
      buyer_address,
      buyer_fee_ada,
      Some(value.from_asset(get_bond_policy_id(), bond_name_listing_2, 3)),
      NoDatum,
    )
  //
  let buyer_qty =
    5
  let received_at_maturity =
    escrow_full_info.received_at_maturity_one_bond * buyer_qty
  let received_with_yield =
    price_of_one_bond * buyer_qty
  let received_diff =
    received_at_maturity - received_with_yield
  let market_fee_seller =
    received_diff * config_test_2.market.seller_fee / config_test_2.bond.basis_points_ref_unit
  let market_fee_buyer =
    received_diff * config_test_2.market.buyer_fee / config_test_2.bond.basis_points_ref_unit
  //
  let min_ada_to_market =
    when sm_qty_input - buyer_qty is {
      0 ->
        sm_min_ada_input
      _ ->
        0
    }
  let market_received =
    market_fee_buyer + market_fee_seller + min_ada_to_market

  // market_received == 206888 * 2
  let payment_datum =
    get_payment_datum()
  let payment_datum_data =
    builtin.serialise_data(payment_datum)
  let payment_datum_hash =
    blake2b_256(payment_datum_data)
  let tx_datums =
    dict.new()
      |> dict.insert(
           payment_datum_hash,
           builtin.b_data(payment_datum_data),
           bytearray.compare,
         )
  let market_address =
    get_market_address()
  let output_market =
    get_output_listing(
      market_address,
      market_received,
      None,
      DatumHash(payment_datum_hash),
    )
  let owner_received =
    received_with_yield - market_fee_seller
  let output_owner =
    get_output_listing(
      owner_address,
      owner_received,
      None,
      DatumHash(payment_datum_hash),
    )
  let buyer_received =
    buyer_fee_ada + sm_min_ada_input - market_received - owner_received
  let output_buyer =
    get_output_listing(
      buyer_address,
      buyer_received,
      Some(
        value.add(
          value.from_asset(get_bond_policy_id(), bond_name_listing_2, buyer_qty),
          value.from_asset(get_bond_policy_id(), bond_name_listing_1, 3),
        ),
      ),
      DatumHash(payment_datum_hash),
    )
  let output_sm =
    get_output_listing(
      sm_address,
      sm_min_ada_input - min_ada_to_market,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_listing_1,
          sm_qty_input - buyer_qty,
        ),
      ),
      InlineDatum(listing_datum),
    )
  validation_listing.buy(
    fixture.tx(
      [input_sm_bond_spending_1, input_buyer_1],
      [reference_input_1],
      [output_market, output_owner, output_buyer, output_sm],
      Some([get_owner_address_hash()]),
      Some(tx_datums),
      Some(time_of_tx),
    ),
    config_test_2,
    input_sm_bond_spending_1,
    listing_datum.requested_yield,
    owner_address,
    sm_address,
  )
}

test listing_buy_full_success_1() {
  let time_of_tx =
    1666656000000
  let config_test_1 =
    get_config_test_1()
  let owner_address =
    get_owner_address()
  let listing_datum =
    get_listing_datum(owner_address, 7)
  let bond_name_listing_1 =
    get_bond_id_1()
  let bond_name_listing_2 =
    get_bond_id_2()
  let escrow_datum =
    get_escrow_datum(bond_name_listing_1, 7, 958, 54, 18602)
  let escrow_lovelace =
    701430920
  let escrow_full_info =
    calc_escrow_full_info(
      config_test_1.bond,
      escrow_lovelace,
      escrow_datum,
      time_of_tx,
    )
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.received_at_maturity_one_bond,
      escrow_full_info.day_to_maturity,
      listing_datum.requested_yield,
      config_test_1.bond.basis_points_ref_unit,
    )
  //
  let reference_input_1 =
    get_input_escrow(
      get_escrow_policy_id(),
      bond_name_listing_1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  //
  let sm_qty_input =
    1
  let sm_min_ada_input =
    1599010
  let sm_address =
    get_smart_contract_address()
  let input_sm_bond_spending_1 =
    get_input_listing(
      sm_address,
      sm_min_ada_input,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_listing_1,
          sm_qty_input,
        ),
      ),
      InlineDatum(listing_datum),
    )
  let buyer_fee_ada =
    18704383567
  let buyer_address =
    get_buyer_address()
  let input_buyer_1 =
    get_input_listing(buyer_address, buyer_fee_ada, None, NoDatum)
  //
  let buyer_qty =
    1
  let received_at_maturity =
    escrow_full_info.received_at_maturity_one_bond * buyer_qty
  let received_with_yield =
    price_of_one_bond * buyer_qty
  let received_diff =
    received_at_maturity - received_with_yield
  let market_fee_seller =
    received_diff * config_test_1.market.seller_fee / config_test_1.bond.basis_points_ref_unit
  let market_fee_buyer =
    received_diff * config_test_1.market.buyer_fee / config_test_1.bond.basis_points_ref_unit
  //
  let min_ada_to_market =
    when sm_qty_input - buyer_qty is {
      0 ->
        sm_min_ada_input
      _ ->
        0
    }
  let market_received =
    market_fee_buyer + market_fee_seller + min_ada_to_market

  // market_received == 206888 * 2
  let payment_datum =
    get_payment_datum()
  let payment_datum_data =
    builtin.serialise_data(payment_datum)
  let payment_datum_hash =
    blake2b_256(payment_datum_data)
  let tx_datums =
    dict.new()
      |> dict.insert(
           payment_datum_hash,
           builtin.b_data(payment_datum_data),
           bytearray.compare,
         )
  let market_address =
    get_market_address()
  let output_market =
    get_output_listing(
      market_address,
      market_received,
      None,
      DatumHash(payment_datum_hash),
    )
  let owner_received =
    received_with_yield - market_fee_seller
  let output_owner =
    get_output_listing(
      owner_address,
      owner_received,
      None,
      DatumHash(payment_datum_hash),
    )
  let buyer_received =
    buyer_fee_ada + sm_min_ada_input - market_received - owner_received
  let output_buyer =
    get_output_listing(
      buyer_address,
      buyer_received,
      Some(
        value.from_asset(get_bond_policy_id(), bond_name_listing_2, buyer_qty),
      ),
      DatumHash(payment_datum_hash),
    )
  let output_sm =
    get_output_listing(
      sm_address,
      sm_min_ada_input - min_ada_to_market,
      Some(
        value.from_asset(
          get_bond_policy_id(),
          bond_name_listing_1,
          sm_qty_input - buyer_qty,
        ),
      ),
      InlineDatum(listing_datum),
    )
  validation_listing.buy(
    fixture.tx(
      [input_sm_bond_spending_1, input_buyer_1],
      [reference_input_1],
      [output_market, output_owner, output_buyer, output_sm],
      Some([get_owner_address_hash()]),
      Some(tx_datums),
      Some(time_of_tx),
    ),
    config_test_1,
    input_sm_bond_spending_1,
    listing_datum.requested_yield,
    owner_address,
    sm_address,
  )
}
