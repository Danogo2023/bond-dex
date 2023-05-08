use aiken/transaction.{InlineDatum, NoDatum}
use aiken/transaction/value
use bond/fixture.{
  get_bond_id_1, get_bond_id_2, get_bond_policy_id, get_buyer_address,
  get_config_test_1, get_input_listing, get_listing_datum, get_market_address,
  get_output_listing, get_owner_address, get_owner_address_hash,
  get_smart_contract_address,
}
use bond/validation_listing.{update_listing}

test listing_update_failure_miss_signed_by_owner() {
  let listing_datum =
    get_listing_datum(get_owner_address(), 500)
  let input_sm_1 =
    get_input_listing(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 5)),
      InlineDatum(listing_datum),
    )
  let output_sm_1 =
    get_output_listing(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 5)),
      InlineDatum(listing_datum),
    )
  !update_listing(
    fixture.tx(
      [input_sm_1],
      [],
      [output_sm_1],
      Some([#"00010203040506"]),
      None,
      None,
    ),
    get_config_test_1(),
    get_owner_address(),
    get_smart_contract_address(),
  )
}

test listing_update_failure_miss_datum_requested_yield_inside_range_0001_9999() {
  let listing_datum =
    get_listing_datum(get_owner_address(), 500)
  let listing_datum_invalid =
    get_listing_datum(get_owner_address(), 0)
  let input_sm_1 =
    get_input_listing(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 5)),
      InlineDatum(listing_datum),
    )
  let output_sm_1 =
    get_output_listing(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 5)),
      InlineDatum(listing_datum_invalid),
    )
  !update_listing(
    fixture.tx(
      [input_sm_1],
      [],
      [output_sm_1],
      Some([get_owner_address_hash()]),
      None,
      None,
    ),
    get_config_test_1(),
    get_owner_address(),
    get_smart_contract_address(),
  )
}

test listing_update_failure_must_only_one_bond_name_market_1() {
  let listing_datum =
    get_listing_datum(get_owner_address(), 500)
  let input_sm_1 =
    get_input_listing(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 5)),
      InlineDatum(listing_datum),
    )
  let input_sm_2 =
    get_input_listing(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_2(), 3)),
      InlineDatum(listing_datum),
    )
  let output_sm_1 =
    get_output_listing(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 5)),
      InlineDatum(listing_datum),
    )
  !update_listing(
    fixture.tx(
      [input_sm_1, input_sm_2],
      [],
      [output_sm_1],
      Some([get_owner_address_hash()]),
      None,
      None,
    ),
    get_config_test_1(),
    get_owner_address(),
    get_smart_contract_address(),
  )
}

test listing_update_failure_must_only_one_bond_name_market_2() {
  let listing_datum =
    get_listing_datum(get_owner_address(), 500)
  let input_sm_1 =
    get_input_listing(
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
    get_input_listing(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_2(), 3)),
      InlineDatum(listing_datum),
    )
  let output_sm_1 =
    get_output_listing(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_2(), 5)),
      InlineDatum(listing_datum),
    )
  let output_sm_2 =
    get_output_listing(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 4)),
      InlineDatum(listing_datum),
    )
  !update_listing(
    fixture.tx(
      [input_sm_1, input_sm_2],
      [],
      [output_sm_1, output_sm_2],
      Some([get_owner_address_hash()]),
      None,
      None,
    ),
    get_config_test_1(),
    get_owner_address(),
    get_smart_contract_address(),
  )
}

test listing_update_single_success_1() {
  let input_owner_1 =
    get_input_listing(
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
    get_input_listing(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 3)),
      InlineDatum(get_listing_datum(get_owner_address(), 1000)),
    )
  //
  let output_owner_1 =
    get_output_listing(
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
    get_output_listing(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 6)),
      InlineDatum(get_listing_datum(get_owner_address(), 500)),
    )
  update_listing(
    fixture.tx(
      [input_owner_1, input_sm_2],
      [],
      [output_owner_1, output_sm_1],
      Some([get_owner_address_hash()]),
      None,
      None,
    ),
    get_config_test_1(),
    get_owner_address(),
    get_smart_contract_address(),
  )
}

test listing_update_single_success_2() {
  let listing_datum =
    get_listing_datum(get_owner_address(), 500)
  let input_owner_1 =
    get_input_listing(
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
    get_input_listing(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_2(), 3)),
      InlineDatum(listing_datum),
    )
  // 
  let output_sm_1 =
    get_output_listing(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 5)),
      InlineDatum(listing_datum),
    )
  !update_listing(
    fixture.tx(
      [input_owner_1, input_sm_2],
      [],
      [output_sm_1],
      Some([get_owner_address_hash()]),
      None,
      None,
    ),
    get_config_test_1(),
    get_owner_address(),
    get_smart_contract_address(),
  )
}

test listing_update_multi_success_1() {
  let input_owner_1 =
    get_input_listing(
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
    get_input_listing(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 3)),
      InlineDatum(get_listing_datum(get_owner_address(), 1000)),
    )
  let input_sm_2 =
    get_input_listing(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 3)),
      InlineDatum(get_listing_datum(get_owner_address(), 500)),
    )
  //
  let output_owner_1 =
    get_output_listing(
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
    get_output_listing(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 5)),
      InlineDatum(get_listing_datum(get_owner_address(), 2345)),
    )
  update_listing(
    fixture.tx(
      [input_owner_1, input_sm_1, input_sm_2],
      [],
      [output_owner_1, output_sm_1],
      Some([get_owner_address_hash()]),
      None,
      None,
    ),
    get_config_test_1(),
    get_owner_address(),
    get_smart_contract_address(),
  )
}

test listing_update_multi_success_2() {
  let input_owner_1 =
    get_input_listing(
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
    get_input_listing(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 3)),
      InlineDatum(get_listing_datum(get_owner_address(), 1000)),
    )
  let input_sm_2 =
    get_input_listing(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 3)),
      InlineDatum(get_listing_datum(get_owner_address(), 500)),
    )
  //
  let output_owner_1 =
    get_output_listing(
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
    get_output_listing(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 2)),
      InlineDatum(get_listing_datum(get_owner_address(), 2345)),
    )
  let output_sm_2 =
    get_output_listing(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 4)),
      InlineDatum(get_listing_datum(get_owner_address(), 5463)),
    )
  update_listing(
    fixture.tx(
      [input_owner_1, input_sm_1, input_sm_2],
      [],
      [output_owner_1, output_sm_1, output_sm_2],
      Some([get_owner_address_hash()]),
      None,
      None,
    ),
    get_config_test_1(),
    get_owner_address(),
    get_smart_contract_address(),
  )
}

test listing_update_multi_success_3() {
  let input_owner_1 =
    get_input_listing(
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
    get_input_listing(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 3)),
      InlineDatum(get_listing_datum(get_owner_address(), 1000)),
    )
  let input_sm_2 =
    get_input_listing(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 3)),
      InlineDatum(get_listing_datum(get_owner_address(), 500)),
    )
  //
  let output_owner_1 =
    get_output_listing(
      get_owner_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 11)),
      NoDatum,
    )
  let output_sm_1 =
    get_output_listing(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_2(), 2)),
      InlineDatum(get_listing_datum(get_owner_address(), 2345)),
    )
  update_listing(
    fixture.tx(
      [input_owner_1, input_sm_1, input_sm_2],
      [],
      [output_owner_1, output_sm_1],
      Some([get_owner_address_hash()]),
      None,
      None,
    ),
    get_config_test_1(),
    get_owner_address(),
    get_smart_contract_address(),
  )
}

test listing_update_multi_success_4() {
  let input_owner_1 =
    get_input_listing(
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
    get_input_listing(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 3)),
      InlineDatum(get_listing_datum(get_owner_address(), 1000)),
    )
  let input_sm_2 =
    get_input_listing(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_2(), 3)),
      InlineDatum(get_listing_datum(get_owner_address(), 500)),
    )
  //
  let output_owner_1 =
    get_output_listing(
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
    get_output_listing(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 2)),
      InlineDatum(get_listing_datum(get_owner_address(), 2345)),
    )
  let output_sm_2 =
    get_output_listing(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 4)),
      InlineDatum(get_listing_datum(get_owner_address(), 5463)),
    )
  update_listing(
    fixture.tx(
      [input_owner_1, input_sm_1, input_sm_2],
      [],
      [output_owner_1, output_sm_1, output_sm_2],
      Some([get_owner_address_hash()]),
      None,
      None,
    ),
    get_config_test_1(),
    get_owner_address(),
    get_smart_contract_address(),
  )
}

test listing_update_multi_failure_1() {
  let input_owner_1 =
    get_input_listing(
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
    get_input_listing(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 3)),
      InlineDatum(get_listing_datum(get_owner_address(), 1000)),
    )
  let input_sm_2 =
    get_input_listing(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 3)),
      InlineDatum(get_listing_datum(get_owner_address(), 500)),
    )
  //
  let output_owner_1 =
    get_output_listing(
      get_owner_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 7)),
      NoDatum,
    )
  let output_sm_1 =
    get_output_listing(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_2(), 2)),
      InlineDatum(get_listing_datum(get_owner_address(), 2345)),
    )
  let output_sm_2 =
    get_output_listing(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 4)),
      InlineDatum(get_listing_datum(get_owner_address(), 1345)),
    )
  !update_listing(
    fixture.tx(
      [input_owner_1, input_sm_1, input_sm_2],
      [],
      [output_owner_1, output_sm_1, output_sm_2],
      Some([get_owner_address_hash()]),
      None,
      None,
    ),
    get_config_test_1(),
    get_owner_address(),
    get_smart_contract_address(),
  )
}

test listing_update_multi_failure_2() {
  let input_owner_1 =
    get_input_listing(
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
    get_input_listing(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 3)),
      InlineDatum(get_listing_datum(get_owner_address(), 1000)),
    )
  let input_sm_2 =
    get_input_listing(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 3)),
      InlineDatum(get_listing_datum(get_buyer_address(), 500)),
    )
  //
  let output_owner_1 =
    get_output_listing(
      get_owner_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 7)),
      NoDatum,
    )
  let output_sm_1 =
    get_output_listing(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_2(), 2)),
      InlineDatum(get_listing_datum(get_owner_address(), 2345)),
    )
  let output_sm_2 =
    get_output_listing(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 4)),
      InlineDatum(get_listing_datum(get_owner_address(), 1345)),
    )
  !update_listing(
    fixture.tx(
      [input_owner_1, input_sm_1, input_sm_2],
      [],
      [output_owner_1, output_sm_1, output_sm_2],
      Some([get_owner_address_hash()]),
      None,
      None,
    ),
    get_config_test_1(),
    get_owner_address(),
    get_smart_contract_address(),
  )
}

test listing_update_multi_failure_3() {
  let input_owner_1 =
    get_input_listing(
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
    get_input_listing(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 3)),
      InlineDatum(get_listing_datum(get_owner_address(), 1000)),
    )
  let input_sm_2 =
    get_input_listing(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 3)),
      InlineDatum(get_listing_datum(get_owner_address(), 500)),
    )
  //
  let output_owner_1 =
    get_output_listing(
      get_owner_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 7)),
      NoDatum,
    )
  let output_sm_1 =
    get_output_listing(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_2(), 2)),
      InlineDatum(get_listing_datum(get_owner_address(), 2345)),
    )
  let output_sm_2 =
    get_output_listing(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 4)),
      InlineDatum(get_listing_datum(get_buyer_address(), 1345)),
    )
  !update_listing(
    fixture.tx(
      [input_owner_1, input_sm_1, input_sm_2],
      [],
      [output_owner_1, output_sm_1, output_sm_2],
      Some([get_owner_address_hash()]),
      None,
      None,
    ),
    get_config_test_1(),
    get_owner_address(),
    get_smart_contract_address(),
  )
}

test listing_update_multi_failure_4() {
  let input_owner_1 =
    get_input_listing(
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
    get_input_listing(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 3)),
      InlineDatum(get_listing_datum(get_owner_address(), 1000)),
    )
  let input_sm_2 =
    get_input_listing(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_2(), 3)),
      InlineDatum(get_listing_datum(get_owner_address(), 500)),
    )
  //
  let output_owner_1 =
    get_output_listing(
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
    get_output_listing(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 2)),
      InlineDatum(get_listing_datum(get_owner_address(), 2345)),
    )
  let output_sm_2 =
    get_output_listing(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 4)),
      InlineDatum(get_listing_datum(get_buyer_address(), 5463)),
    )
  !update_listing(
    fixture.tx(
      [input_owner_1, input_sm_1, input_sm_2],
      [],
      [output_owner_1, output_sm_1, output_sm_2],
      Some([get_owner_address_hash()]),
      None,
      None,
    ),
    get_config_test_1(),
    get_owner_address(),
    get_smart_contract_address(),
  )
}

test listing_update_cancel_listing_success() {
  let input_sm_1 =
    get_input_listing(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 5)),
      InlineDatum(get_listing_datum(get_owner_address(), 500)),
    )
  let input_sm_2 =
    get_input_listing(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 3)),
      InlineDatum(get_listing_datum(get_owner_address(), 1000)),
    )
  let output_owner_1 =
    get_output_listing(
      get_owner_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 8)),
      NoDatum,
    )
  update_listing(
    fixture.tx(
      [input_sm_1, input_sm_2],
      [],
      [output_owner_1],
      Some([get_owner_address_hash()]),
      None,
      None,
    ),
    get_config_test_1(),
    get_owner_address(),
    get_smart_contract_address(),
  )
}

test listing_update_multi_cancel_listing_success_1() {
  let input_sm_1 =
    get_input_listing(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 5)),
      InlineDatum(get_listing_datum(get_owner_address(), 500)),
    )
  let input_sm_2 =
    get_input_listing(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 3)),
      InlineDatum(get_listing_datum(get_owner_address(), 1000)),
    )
  let input_sm_3 =
    get_input_listing(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 4)),
      InlineDatum(get_listing_datum(get_owner_address(), 500)),
    )
  let output_owner_1 =
    get_output_listing(
      get_owner_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 12)),
      NoDatum,
    )
  update_listing(
    fixture.tx(
      [input_sm_1, input_sm_2, input_sm_3],
      [],
      [output_owner_1],
      Some([get_owner_address_hash()]),
      None,
      None,
    ),
    get_config_test_1(),
    get_owner_address(),
    get_smart_contract_address(),
  )
}

test listing_update_multi_cancel_listing_failure_1() {
  let input_sm_1 =
    get_input_listing(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 5)),
      InlineDatum(get_listing_datum(get_owner_address(), 500)),
    )
  let input_sm_2 =
    get_input_listing(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 3)),
      InlineDatum(get_listing_datum(get_owner_address(), 1000)),
    )
  let input_sm_3 =
    get_input_listing(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 4)),
      InlineDatum(get_listing_datum(get_buyer_address(), 500)),
    )
  let output_owner_1 =
    get_output_listing(
      get_owner_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 12)),
      NoDatum,
    )
  !update_listing(
    fixture.tx(
      [input_sm_1, input_sm_2, input_sm_3],
      [],
      [output_owner_1],
      Some([get_owner_address_hash()]),
      None,
      None,
    ),
    get_config_test_1(),
    get_owner_address(),
    get_smart_contract_address(),
  )
}

test listing_update_failure_cancel_listing_miss_qty() {
  let listing_datum =
    get_listing_datum(get_owner_address(), 500)
  let input_sm_1 =
    get_input_listing(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 5)),
      InlineDatum(listing_datum),
    )
  let input_sm_2 =
    get_input_listing(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 3)),
      InlineDatum(listing_datum),
    )
  let output_owner_1 =
    get_output_listing(
      get_owner_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 5)),
      NoDatum,
    )
  let output_market_1 =
    get_output_listing(
      get_market_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 2)),
      NoDatum,
    )
  !update_listing(
    fixture.tx(
      [input_sm_1, input_sm_2],
      [],
      [output_owner_1, output_market_1],
      Some([get_owner_address_hash()]),
      None,
      None,
    ),
    get_config_test_1(),
    get_owner_address(),
    get_smart_contract_address(),
  )
}

test listing_update_failure_cancel_listing_miss_owner() {
  let listing_datum =
    get_listing_datum(get_owner_address(), 500)
  let input_sm_1 =
    get_input_listing(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 5)),
      InlineDatum(listing_datum),
    )
  let input_sm_2 =
    get_input_listing(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 3)),
      InlineDatum(listing_datum),
    )
  let output_market_1 =
    get_output_listing(
      get_market_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 8)),
      NoDatum,
    )
  !update_listing(
    fixture.tx(
      [input_sm_1, input_sm_2],
      [],
      [output_market_1],
      Some([get_owner_address_hash()]),
      None,
      None,
    ),
    get_config_test_1(),
    get_owner_address(),
    get_smart_contract_address(),
  )
}

test listing_update_failure_miss_output_datum() {
  let listing_datum =
    get_listing_datum(get_owner_address(), 500)
  let input_sm_1 =
    get_input_listing(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 5)),
      InlineDatum(listing_datum),
    )
  let input_sm_2 =
    get_input_listing(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 3)),
      InlineDatum(listing_datum),
    )
  let output_sm_1 =
    get_output_listing(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 4)),
      NoDatum,
    )
  let output_owner_1 =
    get_output_listing(
      get_owner_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 4)),
      NoDatum,
    )
  !update_listing(
    fixture.tx(
      [input_sm_1, input_sm_2],
      [],
      [output_sm_1, output_owner_1],
      Some([get_owner_address_hash()]),
      None,
      None,
    ),
    get_config_test_1(),
    get_owner_address(),
    get_smart_contract_address(),
  )
}

test listing_update_failure_miss_output_token_with_amount_not_greater_than_zero() {
  let listing_datum =
    get_listing_datum(get_owner_address(), 500)
  let input_sm_1 =
    get_input_listing(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 1)),
      InlineDatum(listing_datum),
    )
  let output_sm_1 =
    get_output_listing(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 0)),
      NoDatum,
    )
  let output_market_1 =
    get_output_listing(
      get_market_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 1)),
      NoDatum,
    )
  !update_listing(
    fixture.tx(
      [input_sm_1],
      [],
      [output_sm_1, output_market_1],
      Some([get_owner_address_hash()]),
      None,
      None,
    ),
    get_config_test_1(),
    get_owner_address(),
    get_smart_contract_address(),
  )
}

test listing_update_failure_miss_output_token() {
  let listing_datum =
    get_listing_datum(get_owner_address(), 500)
  let input_sm_1 =
    get_input_listing(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 3)),
      InlineDatum(listing_datum),
    )
  let output_owner_1 =
    get_output_listing(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 1)),
      InlineDatum(listing_datum),
    )
  let output_market_1 =
    get_output_listing(
      get_market_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 3)),
      NoDatum,
    )
  !update_listing(
    fixture.tx(
      [input_sm_1],
      [],
      [output_owner_1, output_market_1],
      Some([get_owner_address_hash()]),
      None,
      None,
    ),
    get_config_test_1(),
    get_owner_address(),
    get_smart_contract_address(),
  )
}

test listing_update_failure_miss_output_datum_owner() {
  let listing_datum =
    get_listing_datum(get_owner_address(), 500)
  let input_sm_1 =
    get_input_listing(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 5)),
      InlineDatum(listing_datum),
    )
  let input_sm_2 =
    get_input_listing(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 3)),
      InlineDatum(listing_datum),
    )
  let output_sm_1 =
    get_output_listing(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 5)),
      InlineDatum(get_listing_datum(get_market_address(), 500)),
    )
  let output_owner_1 =
    get_output_listing(
      get_owner_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 3)),
      NoDatum,
    )
  !update_listing(
    fixture.tx(
      [input_sm_1, input_sm_2],
      [],
      [output_sm_1, output_owner_1],
      Some([get_owner_address_hash()]),
      None,
      None,
    ),
    get_config_test_1(),
    get_owner_address(),
    get_smart_contract_address(),
  )
}
