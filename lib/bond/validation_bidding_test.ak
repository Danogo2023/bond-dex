use aiken/transaction.{InlineDatum, NoDatum}
use aiken/transaction/value
use bond/fixture.{
  get_bond_id_1, get_bond_id_2, get_bond_policy_id, get_input_listing,
  get_listing_datum, get_output_listing, get_owner_address,
  get_owner_address_hash, get_smart_contract_address,
}
use bond/validation_bidding

test bidding_update_failure_miss_signed_by_owner() {
  let listing_datum = get_listing_datum(get_owner_address(), 500)
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
  !validation_bidding.update_simple(
    fixture.tx(
      [input_sm_1],
      [],
      [output_sm_1],
      Some([#"00010203040506"]),
      None,
      None,
    ),
    get_owner_address(),
  )
}

test bidding_update_single_success_1() {
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
  validation_bidding.update_simple(
    fixture.tx(
      [input_owner_1, input_sm_2],
      [],
      [output_owner_1, output_sm_1],
      Some([get_owner_address_hash()]),
      None,
      None,
    ),
    get_owner_address(),
  )
}

test bidding_update_multi_success_1() {
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
  validation_bidding.update_simple(
    fixture.tx(
      [input_owner_1, input_sm_1, input_sm_2],
      [],
      [output_owner_1, output_sm_1],
      Some([get_owner_address_hash()]),
      None,
      None,
    ),
    get_owner_address(),
  )
}

test bidding_update_multi_success_2() {
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
  validation_bidding.update_simple(
    fixture.tx(
      [input_owner_1, input_sm_1, input_sm_2],
      [],
      [output_owner_1, output_sm_1, output_sm_2],
      Some([get_owner_address_hash()]),
      None,
      None,
    ),
    get_owner_address(),
  )
}

test bidding_update_multi_success_3() {
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
  validation_bidding.update_simple(
    fixture.tx(
      [input_owner_1, input_sm_1, input_sm_2],
      [],
      [output_owner_1, output_sm_1],
      Some([get_owner_address_hash()]),
      None,
      None,
    ),
    get_owner_address(),
  )
}

test bidding_update_multi_success_4() {
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
  validation_bidding.update_simple(
    fixture.tx(
      [input_owner_1, input_sm_1, input_sm_2],
      [],
      [output_owner_1, output_sm_1, output_sm_2],
      Some([get_owner_address_hash()]),
      None,
      None,
    ),
    get_owner_address(),
  )
}

test bidding_update_cancel_listing_success() {
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
  validation_bidding.update_simple(
    fixture.tx(
      [input_sm_1, input_sm_2],
      [],
      [output_owner_1],
      Some([get_owner_address_hash()]),
      None,
      None,
    ),
    get_owner_address(),
  )
}

test bidding_update_multi_cancel_listing_success_1() {
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
  validation_bidding.update_simple(
    fixture.tx(
      [input_sm_1, input_sm_2, input_sm_3],
      [],
      [output_owner_1],
      Some([get_owner_address_hash()]),
      None,
      None,
    ),
    get_owner_address(),
  )
}
