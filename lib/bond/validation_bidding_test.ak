// use aiken/builtin
// use aiken/bytearray
// use aiken/dict
// use aiken/hash.{blake2b_256}
use aiken/transaction.{InlineDatum, NoDatum}
use aiken/transaction/value
use bond/fixture.{
  // calc_escrow_full_info, 
  gen_bidding_datum, gen_input, gen_output, get_bond_id_1,
  get_bond_id_2, get_bond_policy_id, 
  // get_buyer_address, 
  // get_config_test_2,
  // get_escrow_datum, 
  // get_escrow_policy_id, 
  // get_input_escrow, 
  // get_market_address,
  get_seller_address, get_seller_address_hash, get_smart_contract_address,
}
// get_payment_datum, 
// use bond/utils.{get_price_of_bond}
use bond/validation_bidding

test bidding_update_fail_miss_signed_by_owner() {
  let bidding_datum =
    gen_bidding_datum(get_seller_address(), 100, 172, 10, 500)
  let input_sm_1 =
    gen_input(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 5)),
      InlineDatum(bidding_datum),
    )
  let output_sm_1 =
    gen_output(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 5)),
      InlineDatum(bidding_datum),
    )
  !validation_bidding.update(
    fixture.tx(
      [input_sm_1],
      [],
      [output_sm_1],
      Some([#"00010203040506"]),
      None,
      None,
      None,
    ),
    get_seller_address(),
  )
}

test bidding_update_succ_single() {
  let input_owner_1 =
    gen_input(
      get_seller_address(),
      1300000,
      Some(
        value.add(
          value.from_asset(get_bond_policy_id(), get_bond_id_1(), 5),
          value.from_asset(get_bond_policy_id(), get_bond_id_2(), 2),
        ),
      ),
      NoDatum,
    )
  let input_sm_2 =
    gen_input(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 3)),
      InlineDatum(gen_bidding_datum(get_seller_address(), 100, 172, 10, 1000)),
    )
  //
  let output_owner_1 =
    gen_output(
      get_seller_address(),
      1300000,
      Some(
        value.add(
          value.from_asset(get_bond_policy_id(), get_bond_id_1(), 2),
          value.from_asset(get_bond_policy_id(), get_bond_id_2(), 2),
        ),
      ),
      NoDatum,
    )
  let output_sm_1 =
    gen_output(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 6)),
      InlineDatum(gen_bidding_datum(get_seller_address(), 100, 172, 10, 500)),
    )
  validation_bidding.update(
    fixture.tx(
      [input_owner_1, input_sm_2],
      [],
      [output_owner_1, output_sm_1],
      Some([get_seller_address_hash()]),
      None,
      None,
      None,
    ),
    get_seller_address(),
  )
}

test bidding_update_succ_multi_1() {
  let input_owner_1 =
    gen_input(
      get_seller_address(),
      1300000,
      Some(
        value.add(
          value.from_asset(get_bond_policy_id(), get_bond_id_1(), 5),
          value.from_asset(get_bond_policy_id(), get_bond_id_2(), 2),
        ),
      ),
      NoDatum,
    )
  let input_sm_1 =
    gen_input(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 3)),
      InlineDatum(gen_bidding_datum(get_seller_address(), 100, 172, 10, 1000)),
    )
  let input_sm_2 =
    gen_input(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 3)),
      InlineDatum(gen_bidding_datum(get_seller_address(), 100, 172, 10, 500)),
    )
  //
  let output_owner_1 =
    gen_output(
      get_seller_address(),
      1300000,
      Some(
        value.add(
          value.from_asset(get_bond_policy_id(), get_bond_id_1(), 6),
          value.from_asset(get_bond_policy_id(), get_bond_id_2(), 2),
        ),
      ),
      NoDatum,
    )
  let output_sm_1 =
    gen_output(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 5)),
      InlineDatum(gen_bidding_datum(get_seller_address(), 100, 172, 10, 2345)),
    )
  validation_bidding.update(
    fixture.tx(
      [input_owner_1, input_sm_1, input_sm_2],
      [],
      [output_owner_1, output_sm_1],
      Some([get_seller_address_hash()]),
      None,
      None,
      None,
    ),
    get_seller_address(),
  )
}

test bidding_update_succ_multi_2() {
  let input_owner_1 =
    gen_input(
      get_seller_address(),
      1300000,
      Some(
        value.add(
          value.from_asset(get_bond_policy_id(), get_bond_id_1(), 5),
          value.from_asset(get_bond_policy_id(), get_bond_id_2(), 2),
        ),
      ),
      NoDatum,
    )
  let input_sm_1 =
    gen_input(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 3)),
      InlineDatum(gen_bidding_datum(get_seller_address(), 100, 172, 10, 1000)),
    )
  let input_sm_2 =
    gen_input(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 3)),
      InlineDatum(gen_bidding_datum(get_seller_address(), 100, 172, 10, 500)),
    )
  //
  let output_owner_1 =
    gen_output(
      get_seller_address(),
      1300000,
      Some(
        value.add(
          value.from_asset(get_bond_policy_id(), get_bond_id_1(), 5),
          value.from_asset(get_bond_policy_id(), get_bond_id_2(), 2),
        ),
      ),
      NoDatum,
    )
  let output_sm_1 =
    gen_output(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 2)),
      InlineDatum(gen_bidding_datum(get_seller_address(), 100, 172, 10, 2345)),
    )
  let output_sm_2 =
    gen_output(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 4)),
      InlineDatum(gen_bidding_datum(get_seller_address(), 100, 172, 10, 5463)),
    )
  validation_bidding.update(
    fixture.tx(
      [input_owner_1, input_sm_1, input_sm_2],
      [],
      [output_owner_1, output_sm_1, output_sm_2],
      Some([get_seller_address_hash()]),
      None,
      None,
      None,
    ),
    get_seller_address(),
  )
}

test bidding_update_succ_multi_3() {
  let input_owner_1 =
    gen_input(
      get_seller_address(),
      1300000,
      Some(
        value.add(
          value.from_asset(get_bond_policy_id(), get_bond_id_1(), 5),
          value.from_asset(get_bond_policy_id(), get_bond_id_2(), 2),
        ),
      ),
      NoDatum,
    )
  let input_sm_1 =
    gen_input(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 3)),
      InlineDatum(gen_bidding_datum(get_seller_address(), 100, 172, 10, 1000)),
    )
  let input_sm_2 =
    gen_input(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 3)),
      InlineDatum(gen_bidding_datum(get_seller_address(), 100, 172, 10, 500)),
    )
  //
  let output_owner_1 =
    gen_output(
      get_seller_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 11)),
      NoDatum,
    )
  let output_sm_1 =
    gen_output(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_2(), 2)),
      InlineDatum(gen_bidding_datum(get_seller_address(), 100, 172, 10, 2345)),
    )
  validation_bidding.update(
    fixture.tx(
      [input_owner_1, input_sm_1, input_sm_2],
      [],
      [output_owner_1, output_sm_1],
      Some([get_seller_address_hash()]),
      None,
      None,
      None,
    ),
    get_seller_address(),
  )
}

test bidding_update_succ_multi_4() {
  let input_owner_1 =
    gen_input(
      get_seller_address(),
      1300000,
      Some(
        value.add(
          value.from_asset(get_bond_policy_id(), get_bond_id_1(), 5),
          value.from_asset(get_bond_policy_id(), get_bond_id_2(), 2),
        ),
      ),
      NoDatum,
    )
  let input_sm_1 =
    gen_input(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 3)),
      InlineDatum(gen_bidding_datum(get_seller_address(), 100, 172, 10, 1000)),
    )
  let input_sm_2 =
    gen_input(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_2(), 3)),
      InlineDatum(gen_bidding_datum(get_seller_address(), 100, 172, 10, 500)),
    )
  //
  let output_owner_1 =
    gen_output(
      get_seller_address(),
      1300000,
      Some(
        value.add(
          value.from_asset(get_bond_policy_id(), get_bond_id_1(), 2),
          value.from_asset(get_bond_policy_id(), get_bond_id_2(), 5),
        ),
      ),
      NoDatum,
    )
  let output_sm_1 =
    gen_output(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 2)),
      InlineDatum(gen_bidding_datum(get_seller_address(), 100, 172, 10, 2345)),
    )
  let output_sm_2 =
    gen_output(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 4)),
      InlineDatum(gen_bidding_datum(get_seller_address(), 100, 172, 10, 5463)),
    )
  validation_bidding.update(
    fixture.tx(
      [input_owner_1, input_sm_1, input_sm_2],
      [],
      [output_owner_1, output_sm_1, output_sm_2],
      Some([get_seller_address_hash()]),
      None,
      None,
      None,
    ),
    get_seller_address(),
  )
}

test bidding_update_succ_cancel_single() {
  let input_sm_1 =
    gen_input(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 5)),
      InlineDatum(gen_bidding_datum(get_seller_address(), 100, 172, 10, 500)),
    )
  let input_sm_2 =
    gen_input(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 3)),
      InlineDatum(gen_bidding_datum(get_seller_address(), 100, 172, 10, 1000)),
    )
  let output_owner_1 =
    gen_output(
      get_seller_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 8)),
      NoDatum,
    )
  validation_bidding.update(
    fixture.tx(
      [input_sm_1, input_sm_2],
      [],
      [output_owner_1],
      Some([get_seller_address_hash()]),
      None,
      None,
      None,
    ),
    get_seller_address(),
  )
}

test bidding_update_succ_cancel_multi() {
  let input_sm_1 =
    gen_input(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 5)),
      InlineDatum(gen_bidding_datum(get_seller_address(), 100, 172, 10, 500)),
    )
  let input_sm_2 =
    gen_input(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 3)),
      InlineDatum(gen_bidding_datum(get_seller_address(), 100, 172, 10, 1000)),
    )
  let input_sm_3 =
    gen_input(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 4)),
      InlineDatum(gen_bidding_datum(get_seller_address(), 100, 172, 10, 500)),
    )
  let output_owner_1 =
    gen_output(
      get_seller_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 12)),
      NoDatum,
    )
  validation_bidding.update(
    fixture.tx(
      [input_sm_1, input_sm_2, input_sm_3],
      [],
      [output_owner_1],
      Some([get_seller_address_hash()]),
      None,
      None,
      None,
    ),
    get_seller_address(),
  )
}

// test bidding_sell_succ_full() {
//   let time_of_tx =
//     1681095094000
//   let cfg =
//     get_config_test_2()
//   let owner_address =
//     get_buyer_address()
//   let bidding_bond_qty =
//     5
//   let seller_address =
//     get_seller_address()
//   let input_bidding_datum =
//     gen_bidding_datum(owner_address, 100, 172, bidding_bond_qty, 500)
//   let bond_name_listing_1 =
//     get_bond_id_1()
//   // let _bond_name_listing_2 = get_bond_id_2()
//   //
//   let escrow_datum_duration =
//     72
//   let escrow_datum =
//     get_escrow_datum(
//       bond_name_listing_1,
//       10000,
//       753424657,
//       escrow_datum_duration,
//       63,
//     )
//   let escrow_lovelace =
//     1017328767112
//   let escrow_full_info =
//     calc_escrow_full_info(cfg.bond, escrow_lovelace, escrow_datum, time_of_tx)
//   let price_of_one_bond =
//     get_price_of_bond(
//       escrow_full_info.received_at_maturity_one_bond,
//       escrow_full_info.day_to_maturity,
//       input_bidding_datum.requested_yield,
//       cfg.bond.basis_points_ref_unit,
//     )
//   //
//   // let bidding_yield_default = 533
//   // let bidding_principal = bidding_bond_qty * cfg.bond.bond_face_value
//   // let bidding_lender_interest = bidding_principal*bidding_yield_default*escrow_datum_duration/cfg.bond.basis_points_ref_unit/73
//   // let bidding_lender_receive = bidding_principal + bidding_lender_interest
//   let bond_sell_qty =
//     5
//   let received_at_maturity =
//     escrow_full_info.received_at_maturity_one_bond * bond_sell_qty
//   let received_with_yield =
//     price_of_one_bond * bond_sell_qty
//   let received_diff =
//     received_at_maturity - received_with_yield
//   let market_fee_seller =
//     received_diff * cfg.market.seller_fee / cfg.bond.basis_points_ref_unit
//   let market_fee_buyer =
//     received_diff * cfg.market.buyer_fee / cfg.bond.basis_points_ref_unit
//   //
//   let output_buyer_lovelace =
//     1310316
//   let sm_address =
//     get_smart_contract_address()
//   let sm_input_lovelace =
//     received_with_yield + market_fee_buyer + output_buyer_lovelace
//   let input_sm_1 =
//     gen_input(
//       sm_address,
//       sm_input_lovelace,
//       None,
//       InlineDatum(input_bidding_datum),
//     )
//   let input_seller_lovelace =
//     1310316
//   let input_seller_1 =
//     gen_input(
//       seller_address,
//       input_seller_lovelace,
//       Some(
//         value.from_asset(
//           get_bond_policy_id(),
//           bond_name_listing_1,
//           bond_sell_qty,
//         ),
//       ),
//       NoDatum,
//     )
//   let reference_input_1 =
//     get_input_escrow(
//       get_escrow_policy_id(),
//       bond_name_listing_1,
//       escrow_lovelace,
//       InlineDatum(escrow_datum),
//     )
//   //
//   // let payment_datum = get_payment_datum()
//   // let payment_datum_data = builtin.serialise_data(payment_datum)
//   // let payment_datum_hash = blake2b_256(payment_datum_data)
//   // let tx_datums = dict.new()|> dict.insert(payment_datum_hash, builtin.b_data(payment_datum_data), bytearray.compare)
//   let market_address =
//     get_market_address()
//   let output_market_lovelace =
//     market_fee_buyer + market_fee_seller
//   let output_market_utxo =
//     gen_output(market_address, output_market_lovelace, None, NoDatum)
//   // DatumHash(payment_datum_hash),
//   let output_seller_lovelace =
//     input_seller_lovelace + received_with_yield - market_fee_seller
//   let output_seller_utxo =
//     gen_output(seller_address, output_seller_lovelace, None, NoDatum)
//   // DatumHash(payment_datum_hash),
//   let output_buyer_utxo =
//     gen_output(
//       owner_address,
//       output_buyer_lovelace,
//       Some(
//         value.from_asset(
//           get_bond_policy_id(),
//           bond_name_listing_1,
//           bond_sell_qty,
//         ),
//       ),
//       NoDatum,
//     )
//   // DatumHash(payment_datum_hash),
//   let output_sm_lovelace =
//     sm_input_lovelace - output_market_lovelace - output_seller_lovelace - output_buyer_lovelace
//   // let output_bidding_datum = gen_bidding_datum(owner_address, 100, 172, input_bidding_datum.quantity - bond_sell_qty, 500)
//   let output_sm_utxo =
//     gen_output(
//       sm_address,
//       output_sm_lovelace,
//       None,
//       InlineDatum(input_bidding_datum),
//     )
//   validation_bidding.sell(
//     fixture.tx(
//       [input_sm_1, input_seller_1],
//       [reference_input_1],
//       [
//         output_market_utxo,
//         output_seller_utxo,
//         output_buyer_utxo,
//         output_sm_utxo,
//       ],
//       Some([get_seller_address_hash()]),
//       // Some(tx_datums),
//       None,
//       Some(time_of_tx),
//       None,
//     ),
//     cfg,
//     input_bidding_datum,
//     owner_address,
//     sm_address,
//   )
// }
