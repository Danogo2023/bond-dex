use aiken/builtin
use aiken/bytearray
use aiken/dict
use aiken/hash.{blake2b_256}
use aiken/transaction.{DatumHash, InlineDatum, NoDatum}
use aiken/transaction/value
use bond/fixture.{
  calc_escrow_full_info, gen_input, gen_listing_datum, gen_output, get_bond_id_1,
  get_bond_id_2, get_bond_policy_id, get_buyer_address, get_config_test_1,
  get_config_test_2, get_escrow_datum, get_escrow_policy_id, get_input_escrow,
  get_market_address, get_not_escrow_policy_id, get_owner_address,
  get_owner_address_hash, get_payment_datum, get_smart_contract_address,
  scripthash_address,
}
use bond/utils.{get_price_of_bond}
use bond/validation_listing

test listing_update_fail_miss_signed_by_owner() {
  let listing_datum =
    gen_listing_datum(get_owner_address(), 500)
  let input_sm_1 =
    gen_input(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 5)),
      InlineDatum(listing_datum),
    )
  let output_sm_1 =
    gen_output(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 5)),
      InlineDatum(listing_datum),
    )
  !validation_listing.update(
    fixture.tx(
      [input_sm_1],
      [],
      [output_sm_1],
      Some([#"00010203040506"]),
      None,
      None,
      None,
    ),
    get_config_test_1(),
    get_owner_address(),
    get_smart_contract_address(),
  )
}

test listing_update_fail_miss_requested_yield() {
  let listing_datum =
    gen_listing_datum(get_owner_address(), 500)
  let listing_datum_invalid =
    gen_listing_datum(get_owner_address(), 0)
  let input_sm_1 =
    gen_input(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 5)),
      InlineDatum(listing_datum),
    )
  let output_sm_1 =
    gen_output(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 5)),
      InlineDatum(listing_datum_invalid),
    )
  !validation_listing.update(
    fixture.tx(
      [input_sm_1],
      [],
      [output_sm_1],
      Some([get_owner_address_hash()]),
      None,
      None,
      None,
    ),
    get_config_test_1(),
    get_owner_address(),
    get_smart_contract_address(),
  )
}

test listing_update_fail_must_only_one_bond_name_1() {
  let listing_datum =
    gen_listing_datum(get_owner_address(), 500)
  let input_sm_1 =
    gen_input(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 5)),
      InlineDatum(listing_datum),
    )
  let input_sm_2 =
    gen_input(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_2(), 3)),
      InlineDatum(listing_datum),
    )
  let output_sm_1 =
    gen_output(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 5)),
      InlineDatum(listing_datum),
    )
  !validation_listing.update(
    fixture.tx(
      [input_sm_1, input_sm_2],
      [],
      [output_sm_1],
      Some([get_owner_address_hash()]),
      None,
      None,
      None,
    ),
    get_config_test_1(),
    get_owner_address(),
    get_smart_contract_address(),
  )
}

test listing_update_fail_must_only_one_bond_name_2() {
  let listing_datum =
    gen_listing_datum(get_owner_address(), 500)
  let input_sm_1 =
    gen_input(
      get_owner_address(),
      1300000,
      Some(
        value.add(
          value.from_asset(get_bond_policy_id(), get_bond_id_1(), 5),
          value.from_asset(get_bond_policy_id(), get_bond_id_2(), 2),
        ),
      ),
      InlineDatum(listing_datum),
    )
  let input_sm_2 =
    gen_input(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_2(), 3)),
      InlineDatum(listing_datum),
    )
  let output_sm_1 =
    gen_output(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_2(), 5)),
      InlineDatum(listing_datum),
    )
  let output_sm_2 =
    gen_output(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 4)),
      InlineDatum(listing_datum),
    )
  !validation_listing.update(
    fixture.tx(
      [input_sm_1, input_sm_2],
      [],
      [output_sm_1, output_sm_2],
      Some([get_owner_address_hash()]),
      None,
      None,
      None,
    ),
    get_config_test_1(),
    get_owner_address(),
    get_smart_contract_address(),
  )
}

test listing_update_succ_single_1() {
  let input_owner_1 =
    gen_input(
      get_owner_address(),
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
      InlineDatum(gen_listing_datum(get_owner_address(), 1000)),
    )
  //
  let output_owner_1 =
    gen_output(
      get_owner_address(),
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
      InlineDatum(gen_listing_datum(get_owner_address(), 500)),
    )
  validation_listing.update(
    fixture.tx(
      [input_owner_1, input_sm_2],
      [],
      [output_owner_1, output_sm_1],
      Some([get_owner_address_hash()]),
      None,
      None,
      None,
    ),
    get_config_test_1(),
    get_owner_address(),
    get_smart_contract_address(),
  )
}

test listing_update_succ_single_2() {
  let listing_datum =
    gen_listing_datum(get_owner_address(), 500)
  let input_owner_1 =
    gen_input(
      get_owner_address(),
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
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_2(), 3)),
      InlineDatum(listing_datum),
    )
  // 
  let output_owner_1 =
    gen_output(
      get_owner_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_2(), 5)),
      NoDatum,
    )
  let output_sm_1 =
    gen_output(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 5)),
      InlineDatum(listing_datum),
    )
  validation_listing.update(
    fixture.tx(
      [input_sm_1, input_owner_1],
      [],
      [output_owner_1, output_sm_1],
      Some([get_owner_address_hash()]),
      None,
      None,
      None,
    ),
    get_config_test_1(),
    get_owner_address(),
    get_smart_contract_address(),
  )
}

test listing_update_succ_multi_1() {
  let input_owner_1 =
    gen_input(
      get_owner_address(),
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
      InlineDatum(gen_listing_datum(get_owner_address(), 1000)),
    )
  let input_sm_2 =
    gen_input(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 3)),
      InlineDatum(gen_listing_datum(get_owner_address(), 500)),
    )
  //
  let output_owner_1 =
    gen_output(
      get_owner_address(),
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
      InlineDatum(gen_listing_datum(get_owner_address(), 2345)),
    )
  validation_listing.update(
    fixture.tx(
      [input_owner_1, input_sm_1, input_sm_2],
      [],
      [output_owner_1, output_sm_1],
      Some([get_owner_address_hash()]),
      None,
      None,
      None,
    ),
    get_config_test_1(),
    get_owner_address(),
    get_smart_contract_address(),
  )
}

test listing_update_succ_multi_2() {
  let input_owner_1 =
    gen_input(
      get_owner_address(),
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
      InlineDatum(gen_listing_datum(get_owner_address(), 1000)),
    )
  let input_sm_2 =
    gen_input(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 3)),
      InlineDatum(gen_listing_datum(get_owner_address(), 500)),
    )
  //
  let output_owner_1 =
    gen_output(
      get_owner_address(),
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
      InlineDatum(gen_listing_datum(get_owner_address(), 2345)),
    )
  let output_sm_2 =
    gen_output(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 4)),
      InlineDatum(gen_listing_datum(get_owner_address(), 5463)),
    )
  validation_listing.update(
    fixture.tx(
      [input_owner_1, input_sm_1, input_sm_2],
      [],
      [output_owner_1, output_sm_1, output_sm_2],
      Some([get_owner_address_hash()]),
      None,
      None,
      None,
    ),
    get_config_test_1(),
    get_owner_address(),
    get_smart_contract_address(),
  )
}

test listing_update_succ_multi_3() {
  let input_owner_1 =
    gen_input(
      get_owner_address(),
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
      InlineDatum(gen_listing_datum(get_owner_address(), 1000)),
    )
  let input_sm_2 =
    gen_input(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 3)),
      InlineDatum(gen_listing_datum(get_owner_address(), 500)),
    )
  //
  let output_owner_1 =
    gen_output(
      get_owner_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 11)),
      NoDatum,
    )
  let output_sm_1 =
    gen_output(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_2(), 2)),
      InlineDatum(gen_listing_datum(get_owner_address(), 2345)),
    )
  validation_listing.update(
    fixture.tx(
      [input_owner_1, input_sm_1, input_sm_2],
      [],
      [output_owner_1, output_sm_1],
      Some([get_owner_address_hash()]),
      None,
      None,
      None,
    ),
    get_config_test_1(),
    get_owner_address(),
    get_smart_contract_address(),
  )
}

test listing_update_succ_multi_4() {
  let input_owner_1 =
    gen_input(
      get_owner_address(),
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
      InlineDatum(gen_listing_datum(get_owner_address(), 1000)),
    )
  let input_sm_2 =
    gen_input(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_2(), 3)),
      InlineDatum(gen_listing_datum(get_owner_address(), 500)),
    )
  //
  let output_owner_1 =
    gen_output(
      get_owner_address(),
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
      InlineDatum(gen_listing_datum(get_owner_address(), 2345)),
    )
  let output_sm_2 =
    gen_output(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 4)),
      InlineDatum(gen_listing_datum(get_owner_address(), 5463)),
    )
  validation_listing.update(
    fixture.tx(
      [input_owner_1, input_sm_1, input_sm_2],
      [],
      [output_owner_1, output_sm_1, output_sm_2],
      Some([get_owner_address_hash()]),
      None,
      None,
      None,
    ),
    get_config_test_1(),
    get_owner_address(),
    get_smart_contract_address(),
  )
}

test listing_update_fail_multi_1() {
  let input_owner_1 =
    gen_input(
      get_owner_address(),
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
      InlineDatum(gen_listing_datum(get_owner_address(), 1000)),
    )
  let input_sm_2 =
    gen_input(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 3)),
      InlineDatum(gen_listing_datum(get_owner_address(), 500)),
    )
  //
  let output_owner_1 =
    gen_output(
      get_owner_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 7)),
      NoDatum,
    )
  let output_sm_1 =
    gen_output(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_2(), 2)),
      InlineDatum(gen_listing_datum(get_owner_address(), 2345)),
    )
  let output_sm_2 =
    gen_output(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 4)),
      InlineDatum(gen_listing_datum(get_owner_address(), 1345)),
    )
  !validation_listing.update(
    fixture.tx(
      [input_owner_1, input_sm_1, input_sm_2],
      [],
      [output_owner_1, output_sm_1, output_sm_2],
      Some([get_owner_address_hash()]),
      None,
      None,
      None,
    ),
    get_config_test_1(),
    get_owner_address(),
    get_smart_contract_address(),
  )
}

test listing_update_fail_multi_2() {
  let input_owner_1 =
    gen_input(
      get_owner_address(),
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
      InlineDatum(gen_listing_datum(get_owner_address(), 1000)),
    )
  let input_sm_2 =
    gen_input(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 3)),
      InlineDatum(gen_listing_datum(get_buyer_address(), 500)),
    )
  //
  let output_owner_1 =
    gen_output(
      get_owner_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 7)),
      NoDatum,
    )
  let output_sm_1 =
    gen_output(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_2(), 2)),
      InlineDatum(gen_listing_datum(get_owner_address(), 2345)),
    )
  let output_sm_2 =
    gen_output(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 4)),
      InlineDatum(gen_listing_datum(get_owner_address(), 1345)),
    )
  !validation_listing.update(
    fixture.tx(
      [input_owner_1, input_sm_1, input_sm_2],
      [],
      [output_owner_1, output_sm_1, output_sm_2],
      Some([get_owner_address_hash()]),
      None,
      None,
      None,
    ),
    get_config_test_1(),
    get_owner_address(),
    get_smart_contract_address(),
  )
}

test listing_update_fail_multi_3() {
  let input_owner_1 =
    gen_input(
      get_owner_address(),
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
      InlineDatum(gen_listing_datum(get_owner_address(), 1000)),
    )
  let input_sm_2 =
    gen_input(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 3)),
      InlineDatum(gen_listing_datum(get_owner_address(), 500)),
    )
  //
  let output_owner_1 =
    gen_output(
      get_owner_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 7)),
      NoDatum,
    )
  let output_sm_1 =
    gen_output(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_2(), 2)),
      InlineDatum(gen_listing_datum(get_owner_address(), 2345)),
    )
  let output_sm_2 =
    gen_output(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 4)),
      InlineDatum(gen_listing_datum(get_buyer_address(), 1345)),
    )
  !validation_listing.update(
    fixture.tx(
      [input_owner_1, input_sm_1, input_sm_2],
      [],
      [output_owner_1, output_sm_1, output_sm_2],
      Some([get_owner_address_hash()]),
      None,
      None,
      None,
    ),
    get_config_test_1(),
    get_owner_address(),
    get_smart_contract_address(),
  )
}

test listing_update_fail_multi_4() {
  let input_owner_1 =
    gen_input(
      get_owner_address(),
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
      InlineDatum(gen_listing_datum(get_owner_address(), 1000)),
    )
  let input_sm_2 =
    gen_input(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_2(), 3)),
      InlineDatum(gen_listing_datum(get_owner_address(), 500)),
    )
  //
  let output_owner_1 =
    gen_output(
      get_owner_address(),
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
      InlineDatum(gen_listing_datum(get_owner_address(), 2345)),
    )
  let output_sm_2 =
    gen_output(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 4)),
      InlineDatum(gen_listing_datum(get_buyer_address(), 5463)),
    )
  !validation_listing.update(
    fixture.tx(
      [input_owner_1, input_sm_1, input_sm_2],
      [],
      [output_owner_1, output_sm_1, output_sm_2],
      Some([get_owner_address_hash()]),
      None,
      None,
      None,
    ),
    get_config_test_1(),
    get_owner_address(),
    get_smart_contract_address(),
  )
}

test listing_update_succ_cancel_single() {
  let input_sm_1 =
    gen_input(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 5)),
      InlineDatum(gen_listing_datum(get_owner_address(), 500)),
    )
  let input_sm_2 =
    gen_input(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 3)),
      InlineDatum(gen_listing_datum(get_owner_address(), 1000)),
    )
  let output_owner_1 =
    gen_output(
      get_owner_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 8)),
      NoDatum,
    )
  validation_listing.update(
    fixture.tx(
      [input_sm_1, input_sm_2],
      [],
      [output_owner_1],
      Some([get_owner_address_hash()]),
      None,
      None,
      None,
    ),
    get_config_test_1(),
    get_owner_address(),
    get_smart_contract_address(),
  )
}

test listing_update_succ_cancel_multi() {
  let input_sm_1 =
    gen_input(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 5)),
      InlineDatum(gen_listing_datum(get_owner_address(), 500)),
    )
  let input_sm_2 =
    gen_input(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 3)),
      InlineDatum(gen_listing_datum(get_owner_address(), 1000)),
    )
  let input_sm_3 =
    gen_input(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 4)),
      InlineDatum(gen_listing_datum(get_owner_address(), 500)),
    )
  let output_owner_1 =
    gen_output(
      get_owner_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 12)),
      NoDatum,
    )
  validation_listing.update(
    fixture.tx(
      [input_sm_1, input_sm_2, input_sm_3],
      [],
      [output_owner_1],
      Some([get_owner_address_hash()]),
      None,
      None,
      None,
    ),
    get_config_test_1(),
    get_owner_address(),
    get_smart_contract_address(),
  )
}

test listing_update_fail_cancel_multi() {
  let input_sm_1 =
    gen_input(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 5)),
      InlineDatum(gen_listing_datum(get_owner_address(), 500)),
    )
  let input_sm_2 =
    gen_input(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 3)),
      InlineDatum(gen_listing_datum(get_owner_address(), 1000)),
    )
  let input_sm_3 =
    gen_input(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 4)),
      InlineDatum(gen_listing_datum(get_buyer_address(), 500)),
    )
  let output_owner_1 =
    gen_output(
      get_owner_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 12)),
      NoDatum,
    )
  !validation_listing.update(
    fixture.tx(
      [input_sm_1, input_sm_2, input_sm_3],
      [],
      [output_owner_1],
      Some([get_owner_address_hash()]),
      None,
      None,
      None,
    ),
    get_config_test_1(),
    get_owner_address(),
    get_smart_contract_address(),
  )
}

test listing_update_fail_cancel_miss_qty() {
  let listing_datum =
    gen_listing_datum(get_owner_address(), 500)
  let input_sm_1 =
    gen_input(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 5)),
      InlineDatum(listing_datum),
    )
  let input_sm_2 =
    gen_input(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 3)),
      InlineDatum(listing_datum),
    )
  let output_owner_1 =
    gen_output(
      get_owner_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 5)),
      NoDatum,
    )
  let output_market_1 =
    gen_output(
      get_market_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 2)),
      NoDatum,
    )
  !validation_listing.update(
    fixture.tx(
      [input_sm_1, input_sm_2],
      [],
      [output_owner_1, output_market_1],
      Some([get_owner_address_hash()]),
      None,
      None,
      None,
    ),
    get_config_test_1(),
    get_owner_address(),
    get_smart_contract_address(),
  )
}

test listing_update_fail_cancel_miss_owner() {
  let listing_datum =
    gen_listing_datum(get_owner_address(), 500)
  let input_sm_1 =
    gen_input(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 5)),
      InlineDatum(listing_datum),
    )
  let input_sm_2 =
    gen_input(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 3)),
      InlineDatum(listing_datum),
    )
  let output_market_1 =
    gen_output(
      get_market_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 8)),
      NoDatum,
    )
  !validation_listing.update(
    fixture.tx(
      [input_sm_1, input_sm_2],
      [],
      [output_market_1],
      Some([get_owner_address_hash()]),
      None,
      None,
      None,
    ),
    get_config_test_1(),
    get_owner_address(),
    get_smart_contract_address(),
  )
}

test listing_update_fail_miss_output_datum() {
  let listing_datum =
    gen_listing_datum(get_owner_address(), 500)
  let input_sm_1 =
    gen_input(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 5)),
      InlineDatum(listing_datum),
    )
  let input_sm_2 =
    gen_input(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 3)),
      InlineDatum(listing_datum),
    )
  let output_sm_1 =
    gen_output(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 4)),
      NoDatum,
    )
  let output_owner_1 =
    gen_output(
      get_owner_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 4)),
      NoDatum,
    )
  !validation_listing.update(
    fixture.tx(
      [input_sm_1, input_sm_2],
      [],
      [output_sm_1, output_owner_1],
      Some([get_owner_address_hash()]),
      None,
      None,
      None,
    ),
    get_config_test_1(),
    get_owner_address(),
    get_smart_contract_address(),
  )
}

test listing_update_fail_miss_output_token_with_amount_not_greater_than_zero() {
  let listing_datum =
    gen_listing_datum(get_owner_address(), 500)
  let input_sm_1 =
    gen_input(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 1)),
      InlineDatum(listing_datum),
    )
  let output_sm_1 =
    gen_output(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 0)),
      NoDatum,
    )
  let output_market_1 =
    gen_output(
      get_market_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 1)),
      NoDatum,
    )
  !validation_listing.update(
    fixture.tx(
      [input_sm_1],
      [],
      [output_sm_1, output_market_1],
      Some([get_owner_address_hash()]),
      None,
      None,
      None,
    ),
    get_config_test_1(),
    get_owner_address(),
    get_smart_contract_address(),
  )
}

test listing_update_fail_miss_output_token() {
  let listing_datum =
    gen_listing_datum(get_owner_address(), 500)
  let input_sm_1 =
    gen_input(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 3)),
      InlineDatum(listing_datum),
    )
  let output_owner_1 =
    gen_output(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 1)),
      InlineDatum(listing_datum),
    )
  let output_market_1 =
    gen_output(
      get_market_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 3)),
      NoDatum,
    )
  !validation_listing.update(
    fixture.tx(
      [input_sm_1],
      [],
      [output_owner_1, output_market_1],
      Some([get_owner_address_hash()]),
      None,
      None,
      None,
    ),
    get_config_test_1(),
    get_owner_address(),
    get_smart_contract_address(),
  )
}

test listing_update_fail_miss_output_datum_owner() {
  let listing_datum =
    gen_listing_datum(get_owner_address(), 500)
  let input_sm_1 =
    gen_input(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 5)),
      InlineDatum(listing_datum),
    )
  let input_sm_2 =
    gen_input(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 3)),
      InlineDatum(listing_datum),
    )
  let output_sm_1 =
    gen_output(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 5)),
      InlineDatum(gen_listing_datum(get_market_address(), 500)),
    )
  let output_owner_1 =
    gen_output(
      get_owner_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 3)),
      NoDatum,
    )
  !validation_listing.update(
    fixture.tx(
      [input_sm_1, input_sm_2],
      [],
      [output_sm_1, output_owner_1],
      Some([get_owner_address_hash()]),
      None,
      None,
      None,
    ),
    get_config_test_1(),
    get_owner_address(),
    get_smart_contract_address(),
  )
}

test listing_buy_fail_partial_must_only_one_bond_1() {
  let time_of_tx =
    1681095094000
  let config_test_2 =
    get_config_test_2()
  let owner_address =
    get_owner_address()
  let listing_datum =
    gen_listing_datum(owner_address, 515)
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
    gen_input(
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
    gen_input(
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
    gen_output(
      market_address,
      market_received,
      None,
      DatumHash(payment_datum_hash),
    )
  let owner_received =
    received_with_yield - market_fee_seller
  let output_owner =
    gen_output(
      owner_address,
      owner_received,
      None,
      DatumHash(payment_datum_hash),
    )
  let buyer_received =
    buyer_fee_ada + sm_min_ada_input - market_received - owner_received
  let output_buyer =
    gen_output(
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
    gen_output(
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
      None,
    ),
    config_test_2,
    listing_datum.requested_yield,
    owner_address,
    sm_address,
  )
}

test listing_buy_fail_partial_must_only_one_bond_2() {
  let time_of_tx =
    1681095094000
  let config_test_2 =
    get_config_test_2()
  let owner_address =
    get_owner_address()
  let listing_datum =
    gen_listing_datum(owner_address, 515)
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
    gen_input(
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
    gen_input(
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
    gen_input(
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
    gen_output(
      market_address,
      market_received,
      None,
      DatumHash(payment_datum_hash),
    )
  let owner_received =
    received_with_yield - market_fee_seller
  let output_owner =
    gen_output(
      owner_address,
      owner_received,
      None,
      DatumHash(payment_datum_hash),
    )
  let buyer_received =
    buyer_fee_ada + sm_min_ada_input - market_received - owner_received
  let output_buyer =
    gen_output(
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
    gen_output(
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
      None,
    ),
    config_test_2,
    listing_datum.requested_yield,
    owner_address,
    sm_address,
  )
}

test listing_buy_fail_partial_change_bond_name() {
  let time_of_tx =
    1681095094000
  let config_test_2 =
    get_config_test_2()
  let owner_address =
    get_owner_address()
  let listing_datum =
    gen_listing_datum(owner_address, 515)
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
    gen_input(
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
    gen_input(
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
    gen_output(
      market_address,
      market_received,
      None,
      DatumHash(payment_datum_hash),
    )
  let owner_received =
    received_with_yield - market_fee_seller
  let output_owner =
    gen_output(
      owner_address,
      owner_received,
      None,
      DatumHash(payment_datum_hash),
    )
  let buyer_received =
    buyer_fee_ada + sm_min_ada_input - market_received - owner_received
  let output_buyer =
    gen_output(
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
    gen_output(
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
      None,
    ),
    config_test_2,
    listing_datum.requested_yield,
    owner_address,
    sm_address,
  )
}

test listing_buy_fail_partial_listing_datum_owner_invalid() {
  let time_of_tx =
    1681095094000
  let config_test_2 =
    get_config_test_2()
  let owner_address =
    get_owner_address()
  let listing_datum =
    gen_listing_datum(scripthash_address(#"010203040506"), 515)
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
    gen_input(
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
    gen_input(
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
    gen_output(
      market_address,
      market_received,
      None,
      DatumHash(payment_datum_hash),
    )
  let owner_received =
    received_with_yield - market_fee_seller
  let output_owner =
    gen_output(
      owner_address,
      owner_received,
      None,
      DatumHash(payment_datum_hash),
    )
  let buyer_received =
    buyer_fee_ada + sm_min_ada_input - market_received - owner_received
  let output_buyer =
    gen_output(
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
    gen_output(
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
      None,
    ),
    config_test_2,
    listing_datum.requested_yield,
    owner_address,
    sm_address,
  )
}

test listing_buy_fail_partial_invalid_escrow_datum() {
  let time_of_tx =
    1681095094000
  let config_test_2 =
    get_config_test_2()
  let owner_address =
    get_owner_address()
  let listing_datum =
    gen_listing_datum(owner_address, 515)
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
    gen_input(
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
    gen_input(
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
    gen_output(
      market_address,
      market_received,
      None,
      DatumHash(payment_datum_hash),
    )
  let owner_received =
    received_with_yield - market_fee_seller
  let output_owner =
    gen_output(
      owner_address,
      owner_received,
      None,
      DatumHash(payment_datum_hash),
    )
  let buyer_received =
    buyer_fee_ada + sm_min_ada_input - market_received - owner_received
  let output_buyer =
    gen_output(
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
    gen_output(
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
      None,
    ),
    config_test_2,
    listing_datum.requested_yield,
    owner_address,
    sm_address,
  )
}

test listing_buy_fail_partial_invalid_escrow_policy_id() {
  let time_of_tx =
    1681095094000
  let config_test_2 =
    get_config_test_2()
  let owner_address =
    get_owner_address()
  let listing_datum =
    gen_listing_datum(owner_address, 515)
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
    gen_input(
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
    gen_input(
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
    gen_input(
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
    gen_output(
      market_address,
      market_received,
      None,
      DatumHash(payment_datum_hash),
    )
  let owner_received =
    received_with_yield - market_fee_seller
  let output_owner =
    gen_output(
      owner_address,
      owner_received,
      None,
      DatumHash(payment_datum_hash),
    )
  let buyer_received =
    buyer_fee_ada + sm_min_ada_input - market_received - owner_received
  let output_buyer =
    gen_output(
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
    gen_output(
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
      None,
    ),
    config_test_2,
    listing_datum.requested_yield,
    owner_address,
    sm_address,
  )
}

test listing_buy_fail_partial_invalid_escrow_nodatum() {
  let time_of_tx =
    1681095094000
  let config_test_2 =
    get_config_test_2()
  let owner_address =
    get_owner_address()
  let listing_datum =
    gen_listing_datum(owner_address, 515)
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
    gen_input(
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
    gen_input(
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
    gen_output(
      market_address,
      market_received,
      None,
      DatumHash(payment_datum_hash),
    )
  let owner_received =
    received_with_yield - market_fee_seller
  let output_owner =
    gen_output(
      owner_address,
      owner_received,
      None,
      DatumHash(payment_datum_hash),
    )
  let buyer_received =
    buyer_fee_ada + sm_min_ada_input - market_received - owner_received
  let output_buyer =
    gen_output(
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
    gen_output(
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
      None,
    ),
    config_test_2,
    listing_datum.requested_yield,
    owner_address,
    sm_address,
  )
}

test listing_buy_fail_partial_invalid_escrow_closable() {
  let time_of_tx =
    1681095094000
  let config_test_2 =
    get_config_test_2()
  let owner_address =
    get_owner_address()
  let listing_datum =
    gen_listing_datum(owner_address, 515)
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
    gen_input(
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
    gen_input(
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
    gen_output(
      market_address,
      market_received,
      None,
      DatumHash(payment_datum_hash),
    )
  let owner_received =
    received_with_yield - market_fee_seller
  let output_owner =
    gen_output(
      owner_address,
      owner_received,
      None,
      DatumHash(payment_datum_hash),
    )
  let buyer_received =
    buyer_fee_ada + sm_min_ada_input - market_received - owner_received
  let output_buyer =
    gen_output(
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
    gen_output(
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
      None,
    ),
    config_test_2,
    listing_datum.requested_yield,
    owner_address,
    sm_address,
  )
}

test listing_buy_fail_buyer_must_not_owner() {
  let time_of_tx =
    1681095094000
  let config_test_2 =
    get_config_test_2()
  let owner_address =
    get_owner_address()
  let listing_datum =
    gen_listing_datum(owner_address, 515)
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
    gen_input(
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
    gen_input(
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
    gen_output(
      market_address,
      market_received,
      None,
      DatumHash(payment_datum_hash),
    )
  let owner_received =
    received_with_yield - market_fee_seller
  let output_owner =
    gen_output(
      owner_address,
      owner_received,
      None,
      DatumHash(payment_datum_hash),
    )
  let buyer_received =
    buyer_fee_ada + sm_min_ada_input - market_received - owner_received
  let output_buyer =
    gen_output(
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
    gen_output(
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
      None,
    ),
    config_test_2,
    listing_datum.requested_yield,
    owner_address,
    sm_address,
  )
}

test listing_buy_fail_buyer_must_not_market() {
  let time_of_tx =
    1681095094000
  let config_test_2 =
    get_config_test_2()
  let market_address =
    get_market_address()
  let owner_address =
    get_owner_address()
  let listing_datum =
    gen_listing_datum(owner_address, 515)
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
    gen_input(
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
    gen_input(
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
    gen_output(
      market_address,
      market_received,
      None,
      DatumHash(payment_datum_hash),
    )
  let owner_received =
    received_with_yield - market_fee_seller
  let output_owner =
    gen_output(
      owner_address,
      owner_received,
      None,
      DatumHash(payment_datum_hash),
    )
  let buyer_received =
    buyer_fee_ada + sm_min_ada_input - market_received - owner_received
  let output_buyer =
    gen_output(
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
    gen_output(
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
      None,
    ),
    config_test_2,
    listing_datum.requested_yield,
    owner_address,
    sm_address,
  )
}

test listing_buy_succ_partial() {
  let time_of_tx =
    1681095094000
  let config_test_2 =
    get_config_test_2()
  let owner_address =
    get_owner_address()
  let listing_datum =
    gen_listing_datum(owner_address, 515)
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
    gen_input(
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
    gen_input(
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
    gen_output(
      market_address,
      market_received,
      None,
      DatumHash(payment_datum_hash),
    )
  let owner_received =
    received_with_yield - market_fee_seller
  let output_owner =
    gen_output(
      owner_address,
      owner_received,
      None,
      DatumHash(payment_datum_hash),
    )
  let buyer_received =
    buyer_fee_ada + sm_min_ada_input - market_received - owner_received
  let output_buyer =
    gen_output(
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
    gen_output(
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
      None,
    ),
    config_test_2,
    listing_datum.requested_yield,
    owner_address,
    sm_address,
  )
}

test listing_buy_succ_full_1() {
  let time_of_tx =
    1681095094000
  let config_test_2 =
    get_config_test_2()
  let owner_address =
    get_owner_address()
  let listing_datum =
    gen_listing_datum(owner_address, 515)
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
    gen_input(
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
    gen_input(
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
    gen_output(
      market_address,
      market_received,
      None,
      DatumHash(payment_datum_hash),
    )
  let owner_received =
    received_with_yield - market_fee_seller
  let output_owner =
    gen_output(
      owner_address,
      owner_received,
      None,
      DatumHash(payment_datum_hash),
    )
  let buyer_received =
    buyer_fee_ada + sm_min_ada_input - market_received - owner_received
  let output_buyer =
    gen_output(
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
    gen_output(
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
      None,
    ),
    config_test_2,
    listing_datum.requested_yield,
    owner_address,
    sm_address,
  )
}

test listing_buy_succ_full_2() {
  let time_of_tx =
    1666656000000
  let config_test_1 =
    get_config_test_1()
  let owner_address =
    get_owner_address()
  let listing_datum =
    gen_listing_datum(owner_address, 7)
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
  let buyer_qty =
    0
  let sm_min_ada_input =
    1599010
  let sm_address =
    get_smart_contract_address()
  let input_sm_bond_spending_1 =
    gen_input(
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
    gen_input(
      buyer_address,
      buyer_fee_ada,
      Some(value.from_asset(get_bond_policy_id(), bond_name_listing_2, 1)),
      NoDatum,
    )
  //
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
    gen_output(
      market_address,
      market_received,
      None,
      DatumHash(payment_datum_hash),
    )
  let owner_received =
    received_with_yield - market_fee_seller
  let output_owner =
    gen_output(
      owner_address,
      owner_received,
      None,
      DatumHash(payment_datum_hash),
    )
  let buyer_received =
    buyer_fee_ada + sm_min_ada_input - market_received - owner_received
  let output_buyer =
    gen_output(
      buyer_address,
      buyer_received,
      Some(value.from_asset(get_bond_policy_id(), bond_name_listing_2, 1)),
      DatumHash(payment_datum_hash),
    )
  let output_sm =
    gen_output(
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
      None,
    ),
    config_test_1,
    listing_datum.requested_yield,
    owner_address,
    sm_address,
  )
}
