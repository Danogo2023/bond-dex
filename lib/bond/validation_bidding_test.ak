use aiken/transaction.{InlineDatum, NoDatum}
use aiken/transaction/value
use bond/fixture.{
  get_bond_id_1, get_bond_id_2, get_bond_policy_id, gen_input,
  gen_bidding_datum, gen_output, get_owner_address,
  get_owner_address_hash, get_smart_contract_address,
}
use bond/validation_bidding

test bidding_update_failure_miss_signed_by_owner() {
  let bidding_datum =
    gen_bidding_datum(get_owner_address(), 100, 172, 10, 500)
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
  !validation_bidding.update_simple(
    fixture.tx(
      [input_sm_1],
      [],
      [output_sm_1],
      Some([#"00010203040506"]),
      None,
      None,
      None,
    ),
    get_owner_address(),
  )
}

test bidding_update_single_success_1() {
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
      InlineDatum(gen_bidding_datum(get_owner_address(), 100, 172, 10, 1000)),
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
      InlineDatum(gen_bidding_datum(get_owner_address(), 100, 172, 10, 500)),
    )
  validation_bidding.update_simple(
    fixture.tx(
      [input_owner_1, input_sm_2],
      [],
      [output_owner_1, output_sm_1],
      Some([get_owner_address_hash()]),
      None,
      None,
      None,
    ),
    get_owner_address(),
  )
}

test bidding_update_multi_success_1() {
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
      InlineDatum(gen_bidding_datum(get_owner_address(), 100, 172, 10, 1000)),
    )
  let input_sm_2 =
    gen_input(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 3)),
      InlineDatum(gen_bidding_datum(get_owner_address(), 100, 172, 10, 500)),
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
      InlineDatum(gen_bidding_datum(get_owner_address(), 100, 172, 10, 2345)),
    )
  validation_bidding.update_simple(
    fixture.tx(
      [input_owner_1, input_sm_1, input_sm_2],
      [],
      [output_owner_1, output_sm_1],
      Some([get_owner_address_hash()]),
      None,
      None,
      None,
    ),
    get_owner_address(),
  )
}

test bidding_update_multi_success_2() {
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
      InlineDatum(gen_bidding_datum(get_owner_address(), 100, 172, 10, 1000)),
    )
  let input_sm_2 =
    gen_input(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 3)),
      InlineDatum(gen_bidding_datum(get_owner_address(), 100, 172, 10, 500)),
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
      InlineDatum(gen_bidding_datum(get_owner_address(), 100, 172, 10, 2345)),
    )
  let output_sm_2 =
    gen_output(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 4)),
      InlineDatum(gen_bidding_datum(get_owner_address(), 100, 172, 10, 5463)),
    )
  validation_bidding.update_simple(
    fixture.tx(
      [input_owner_1, input_sm_1, input_sm_2],
      [],
      [output_owner_1, output_sm_1, output_sm_2],
      Some([get_owner_address_hash()]),
      None,
      None,
      None,
    ),
    get_owner_address(),
  )
}

test bidding_update_multi_success_3() {
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
      InlineDatum(gen_bidding_datum(get_owner_address(), 100, 172, 10, 1000)),
    )
  let input_sm_2 =
    gen_input(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 3)),
      InlineDatum(gen_bidding_datum(get_owner_address(), 100, 172, 10, 500)),
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
      InlineDatum(gen_bidding_datum(get_owner_address(), 100, 172, 10, 2345)),
    )
  validation_bidding.update_simple(
    fixture.tx(
      [input_owner_1, input_sm_1, input_sm_2],
      [],
      [output_owner_1, output_sm_1],
      Some([get_owner_address_hash()]),
      None,
      None,
      None,
    ),
    get_owner_address(),
  )
}

test bidding_update_multi_success_4() {
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
      InlineDatum(gen_bidding_datum(get_owner_address(), 100, 172, 10, 1000)),
    )
  let input_sm_2 =
    gen_input(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_2(), 3)),
      InlineDatum(gen_bidding_datum(get_owner_address(), 100, 172, 10, 500)),
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
      InlineDatum(gen_bidding_datum(get_owner_address(), 100, 172, 10, 2345)),
    )
  let output_sm_2 =
    gen_output(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 4)),
      InlineDatum(gen_bidding_datum(get_owner_address(), 100, 172, 10, 5463)),
    )
  validation_bidding.update_simple(
    fixture.tx(
      [input_owner_1, input_sm_1, input_sm_2],
      [],
      [output_owner_1, output_sm_1, output_sm_2],
      Some([get_owner_address_hash()]),
      None,
      None,
      None,
    ),
    get_owner_address(),
  )
}

test bidding_update_cancel_listing_success() {
  let input_sm_1 =
    gen_input(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 5)),
      InlineDatum(gen_bidding_datum(get_owner_address(), 100, 172, 10, 500)),
    )
  let input_sm_2 =
    gen_input(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 3)),
      InlineDatum(gen_bidding_datum(get_owner_address(), 100, 172, 10, 1000)),
    )
  let output_owner_1 =
    gen_output(
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
      None,
    ),
    get_owner_address(),
  )
}

test bidding_update_multi_cancel_listing_success_1() {
  let input_sm_1 =
    gen_input(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 5)),
      InlineDatum(gen_bidding_datum(get_owner_address(), 100, 172, 10, 500)),
    )
  let input_sm_2 =
    gen_input(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 3)),
      InlineDatum(gen_bidding_datum(get_owner_address(), 100, 172, 10, 1000)),
    )
  let input_sm_3 =
    gen_input(
      get_smart_contract_address(),
      1300000,
      Some(value.from_asset(get_bond_policy_id(), get_bond_id_1(), 4)),
      InlineDatum(gen_bidding_datum(get_owner_address(), 100, 172, 10, 500)),
    )
  let output_owner_1 =
    gen_output(
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
      None,
    ),
    get_owner_address(),
  )
}
