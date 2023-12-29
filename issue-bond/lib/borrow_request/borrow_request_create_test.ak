use aiken/list
use aiken/string
use aiken/transaction.{
  Datum, InlineDatum, Input, NoDatum, Output, OutputReference, Transaction,
  TransactionId, placeholder,
}
use aiken/transaction/credential.{Address, Inline, VerificationKeyCredential}
use aiken/transaction/value.{AssetName, PolicyId}
use bond_issue/types.{BondIssueConfig, PlatformConfig, RequestDatum}
use borrow_request/borrower_nft
use borrow_request/request_nft
use common/fixture.{get_epoch_config_mainnet}
use common/hash_out_refs.{hash_out_ref}
use common/time.{BasisPoints, get_slot_config_network_mainnet}

// ========= Params ==========
const borrower_stake_key = "borrower_stake_key"

const borrower_public_key = "borrower_payment_key"

const req_pid = "req_pid"

const req_skh = "req_skh"

const borrower_pid = "borrower_pid"

const ada = 1_000_000

// ========= Builders ==========

fn add_asset(self: Output, policy_id: PolicyId, token_name: ByteArray, amt: Int) {
  Output {
    ..self,
    value: self.value
      |> value.add(policy_id, token_name, amt),
  }
}

fn set_stake_credential(self: Output, cred: Option<ByteArray>) {
  Output {
    ..self,
    address: Address {
      ..self.address,
      stake_credential: when cred is {
        None -> None
        Some(c) -> Some(Inline(VerificationKeyCredential(c)))
      },
    },
  }
}

fn get_datum(self: Output) -> Data {
  expect InlineDatum(datum) = self.datum
  datum
}

fn set_apr(self: Output, apr: Int) {
  expect datum: RequestDatum = self |> get_datum()
  Output { ..self, datum: InlineDatum(RequestDatum { ..datum, apr: apr }) }
}

fn set_duration(self: Output, duration: Int) {
  expect datum: RequestDatum = self |> get_datum()
  Output {
    ..self,
    datum: InlineDatum(RequestDatum { ..datum, duration: duration }),
  }
}

fn set_symbol(self: Output, symbol: PolicyId) {
  expect datum: RequestDatum = self |> get_datum()
  Output {
    ..self,
    datum: InlineDatum(RequestDatum { ..datum, symbol: symbol }),
  }
}

fn set_borrower(self: Output, borrower: AssetName) {
  expect datum: RequestDatum = self |> get_datum()
  Output {
    ..self,
    datum: InlineDatum(RequestDatum { ..datum, borrower: borrower }),
  }
}

fn set_requested(self: Output, requested: Int) {
  expect datum: RequestDatum = self |> get_datum()
  Output {
    ..self,
    datum: InlineDatum(RequestDatum { ..datum, requested: requested }),
  }
}

fn set_issued(self: Output, issued: Int) {
  expect datum: RequestDatum = self |> get_datum()
  Output {
    ..self,
    datum: InlineDatum(RequestDatum { ..datum, issued: issued }),
  }
}

fn set_epo_rewards(self: Output, epo_rewards: Int) {
  expect datum: RequestDatum = self |> get_datum()
  Output {
    ..self,
    datum: InlineDatum(RequestDatum { ..datum, epo_rewards: epo_rewards }),
  }
}

fn set_prepaid(self: Output, prepaid: Int) {
  expect datum: RequestDatum = self |> get_datum()
  Output {
    ..self,
    datum: InlineDatum(RequestDatum { ..datum, prepaid: prepaid }),
  }
}

fn set_buffer(self: Output, buffer: Int) {
  expect datum: RequestDatum = self |> get_datum()
  Output {
    ..self,
    datum: InlineDatum(RequestDatum { ..datum, buffer: buffer }),
  }
}

fn set_fee(self: Output, fee: Int) {
  expect datum: RequestDatum = self |> get_datum()
  Output { ..self, datum: InlineDatum(RequestDatum { ..datum, fee: fee }) }
}

fn set_datum(self: Output, datum: Datum) -> Output {
  Output { ..self, datum: datum }
}

fn build_borrower_output() {
  Output {
    address: credential.from_verification_key(borrower_public_key)
      |> credential.with_delegation_key(borrower_stake_key),
    value: value.from_lovelace(1029382),
    datum: NoDatum,
    reference_script: None,
  }
}

fn build_borrower_input() {
  Input {
    output_reference: OutputReference(TransactionId("user_tx"), 1),
    output: build_borrower_output(),
  }
}

fn get_min_prepaid(cfg: BondIssueConfig, buffer: Int) {
  cfg.platform.prepaid_plus + buffer
}

fn get_borrow_request_min_ada(epo_rewards: Int, prepaid: Int) {
  epo_rewards * prepaid
}

fn get_min_epo_rewards(
  cfg: BondIssueConfig,
  requested: Int,
  issued: Int,
  apr: Int,
) {
  ( requested - issued ) * cfg.platform.bond_face_value * apr / cfg.basis.base / cfg.epoch.year_to_epoch
}

fn get_request_datum(self: Output) {
  expect InlineDatum(datum) = self.datum
  expect request_datum: RequestDatum = datum
  request_datum
}

fn build_borrow_request_output(borrower: PolicyId) {
  let cfg: BondIssueConfig = build_cfg()
  let buffer = 10
  let prepaid = get_min_prepaid(cfg, buffer)
  let duration = prepaid * 10
  let apr = cfg.platform.min_apr
  let requested = cfg.platform.min_requested
  let issued = 0
  let fee = 500
  let epo_rewards = get_min_epo_rewards(cfg, requested, issued, apr)
  Output {
    address: credential.from_script(req_skh)
      |> credential.with_delegation_key(borrower_stake_key),
    value: value.from_lovelace(get_borrow_request_min_ada(epo_rewards, prepaid))
      |> value.add(req_pid, borrower, 1),
    datum: InlineDatum(
      RequestDatum {
        apr,
        duration,
        symbol: borrower_pid,
        borrower,
        requested,
        issued,
        epo_rewards,
        prepaid,
        buffer,
        fee,
      },
    ),
    reference_script: None,
  }
}

fn with_tx_summary(tx: Transaction) {
  trace @"==================="
  trace string.concat(
    @"count inputs: ",
    string.from_int(list.length(tx.inputs)),
  )
  trace string.concat(
    @"count reference_inputs: ",
    string.from_int(list.length(tx.reference_inputs)),
  )
  trace string.concat(
    @"count outputs: ",
    string.from_int(list.length(tx.outputs)),
  )
  trace string.concat(
    @"count minted: ",
    string.from_int(
      list.length(tx.mint |> value.from_minted_value |> value.flatten),
    ),
  )
  tx
}

fn build_tx() {
  let borrower_in = build_borrower_input()
  let borrower = hash_out_ref(borrower_in.output_reference)
  let borrow_request_out = build_borrow_request_output(borrower)
  (
    Transaction {
      ..placeholder(),
      mint: value.from_asset(req_pid, borrower, 1)
        |> value.add(borrower_pid, borrower, 1)
        |> value.to_minted_value,
      inputs: [borrower_in],
      outputs: [
        borrow_request_out,
        borrower_in.output
          |> add_asset(borrower_pid, borrower, 1),
      ],
    },
    borrower_in,
  )
}

fn build_cfg() {
  BondIssueConfig {
    slot: get_slot_config_network_mainnet(),
    epoch: get_epoch_config_mainnet(),
    basis: BasisPoints { base: 10_000, min: 1, max: 9_999 },
    platform: PlatformConfig {
      bond_face_value: 100_000_000,
      fee: 500,
      fee_addr: credential.from_verification_key("fee_addr"),
      tx_ttl: 3 * 60,
      min_buffer: 6,
      prepaid_plus: 3,
      min_requested: 100,
      min_apr: 200,
      min_duration: 6,
      garbage_addr: credential.from_verification_key("garbage_addr"),
    },
  }
}

test succ_when_all_rules_are_satisfied() {
  let cfg = build_cfg()
  let (tx, borrower_in) = build_tx()
  and {
    request_nft.minting(
      cfg,
      tx |> with_tx_summary,
      req_skh,
      req_pid,
      borrower_pid,
      borrower_in.output_reference,
    ),
    borrower_nft.minting(
      cfg,
      tx,
      req_skh,
      req_pid,
      borrower_pid,
      borrower_in.output_reference,
    ),
  }
}

test succ_when_creating_5_requests() {
  let cfg = build_cfg()
  let t = placeholder()
  let request_count = 5
  let (inputs, outputs, mint, borrower_nfts) =
    list.repeat(0, request_count)
      |> list.indexed_map(
           fn(idx, _) {
             let borrower_in =
               Input {
                 output_reference: OutputReference(
                   TransactionId("borrower_tx"),
                   idx,
                 ),
                 output: build_borrower_output(),
               }
             let borrower = hash_out_ref(borrower_in.output_reference)
             let request_out = build_borrow_request_output(borrower)
             (borrower_in, request_out)
           },
         )
      |> list.reduce(
           ([], [], value.zero(), value.zero()),
           fn(acc, cur) {
             let (inputs, outputs, mint, borrower_nfts) = acc
             let (borrower_in, request_out) = cur
             let datum = get_request_datum(request_out)
             (
               [borrower_in, ..inputs],
               [request_out, ..outputs],
               mint
                 |> value.add(req_pid, datum.borrower, 1)
                 |> value.add(borrower_pid, datum.borrower, 1),
               borrower_nfts |> value.add(borrower_pid, datum.borrower, 1),
             )
           },
         )
  let borrower_out =
    Output {
      ..build_borrower_output(),
      value: value.from_lovelace(10 * ada) |> value.merge(borrower_nfts),
    }
  let tx =
    Transaction {
      ..t,
      mint: mint |> value.to_minted_value,
      inputs: inputs,
      outputs: [borrower_out, ..outputs],
    }
      |> with_tx_summary
  list.all(inputs, fn(borrower_in) { and {
        request_nft.minting(
          cfg,
          tx,
          req_skh,
          req_pid,
          borrower_pid,
          borrower_in.output_reference,
        ),
        borrower_nft.minting(
          cfg,
          tx,
          req_skh,
          req_pid,
          borrower_pid,
          borrower_in.output_reference,
        ),
      } })
}

test succ_when_creating_10_requests() {
  let cfg = build_cfg()
  let t = placeholder()
  let request_count = 10
  let (inputs, outputs, mint, borrower_nfts) =
    list.repeat(0, request_count)
      |> list.indexed_map(
           fn(idx, _) {
             let borrower_in =
               Input {
                 output_reference: OutputReference(
                   TransactionId("borrower_tx"),
                   idx,
                 ),
                 output: build_borrower_output(),
               }
             let borrower = hash_out_ref(borrower_in.output_reference)
             let request_out = build_borrow_request_output(borrower)
             (borrower_in, request_out)
           },
         )
      |> list.reduce(
           ([], [], value.zero(), value.zero()),
           fn(acc, cur) {
             let (inputs, outputs, mint, borrower_nfts) = acc
             let (borrower_in, request_out) = cur
             let datum = get_request_datum(request_out)
             (
               [borrower_in, ..inputs],
               [request_out, ..outputs],
               mint
                 |> value.add(req_pid, datum.borrower, 1)
                 |> value.add(borrower_pid, datum.borrower, 1),
               borrower_nfts |> value.add(borrower_pid, datum.borrower, 1),
             )
           },
         )
  let borrower_out =
    Output {
      ..build_borrower_output(),
      value: value.from_lovelace(10 * ada) |> value.merge(borrower_nfts),
    }
  let tx =
    Transaction {
      ..t,
      mint: mint |> value.to_minted_value,
      inputs: inputs,
      outputs: [borrower_out, ..outputs],
    }
      |> with_tx_summary
  list.all(inputs, fn(borrower_in) { and {
        request_nft.minting(
          cfg,
          tx,
          req_skh,
          req_pid,
          borrower_pid,
          borrower_in.output_reference,
        ),
        borrower_nft.minting(
          cfg,
          tx,
          req_skh,
          req_pid,
          borrower_pid,
          borrower_in.output_reference,
        ),
      } })
}

test succ_on_large_inputs_and_outputs() {
  let cfg = build_cfg()
  let (t, borrower_in) = build_tx()
  let dust_count = 50
  let dust_inputs =
    list.repeat(0, dust_count)
      |> list.indexed_map(
           fn(idx, _) {
             Input {
               output_reference: OutputReference(
                 TransactionId("borrower_tx_1"),
                 idx,
               ),
               output: Output {
                 value: value.from_lovelace(100 * ada),
                 address: credential.from_verification_key(borrower_public_key)
                   |> credential.with_delegation_key(borrower_stake_key),
                 datum: NoDatum,
                 reference_script: None,
               },
             }
           },
         )
  let dust_outputs = dust_inputs |> list.map(fn(i) { i.output })
  let tx =
    Transaction {
      ..t,
      inputs: t.inputs |> list.concat(dust_inputs),
      outputs: t.outputs |> list.concat(dust_outputs),
    }
      |> with_tx_summary
  and {
    request_nft.minting(
      cfg,
      tx,
      req_skh,
      req_pid,
      borrower_pid,
      borrower_in.output_reference,
    ),
    borrower_nft.minting(
      cfg,
      tx,
      req_skh,
      req_pid,
      borrower_pid,
      borrower_in.output_reference,
    ),
  }
}

test fail_when_borrow_request_doesnt_hold_nft() {
  let cfg = build_cfg()
  let (t, borrower_in) = build_tx()
  expect [request_out, borrower_out] = t.outputs
  let req_datum = get_request_datum(request_out)
  let tx =
    Transaction {
      ..t,
      outputs: [
        request_out |> add_asset(req_pid, req_datum.borrower, -1),
        borrower_out |> add_asset(req_pid, req_datum.borrower, 1),
      ],
    }
      |> with_tx_summary
  and {
    request_nft.minting(
      cfg,
      tx,
      req_skh,
      req_pid,
      borrower_pid,
      borrower_in.output_reference,
    ),
    borrower_nft.minting(
      cfg,
      tx,
      req_skh,
      req_pid,
      borrower_pid,
      borrower_in.output_reference,
    ),
  } |> not
}

test fail_when_minting_unexpected_borrower_nft() {
  let cfg = build_cfg()
  let (t, borrower_in) = build_tx()
  expect [request_out, borrower_out] = t.outputs
  let other_borrower = "other_borrower"
  let tx =
    Transaction {
      ..t,
      mint: t.mint
        |> value.from_minted_value
        |> value.add(borrower_pid, other_borrower, 1)
        |> value.to_minted_value,
      outputs: [
        request_out,
        borrower_out |> add_asset(borrower_pid, other_borrower, 1),
      ],
    }
      |> with_tx_summary
  and {
    request_nft.minting(
      cfg,
      tx,
      req_skh,
      req_pid,
      borrower_pid,
      borrower_in.output_reference,
    ),
    borrower_nft.minting(
      cfg,
      tx,
      req_skh,
      req_pid,
      borrower_pid,
      borrower_in.output_reference,
    ),
  } |> not
}

test fail_when_minting_unexpected_request_nft() {
  let cfg = build_cfg()
  let (t, borrower_in) = build_tx()
  expect [request_out, borrower_out] = t.outputs
  let other_borrower = "other_borrower"
  let tx =
    Transaction {
      ..t,
      mint: t.mint
        |> value.from_minted_value
        |> value.add(req_pid, other_borrower, 1)
        |> value.to_minted_value,
      outputs: [
        request_out,
        borrower_out |> add_asset(req_pid, other_borrower, 1),
      ],
    }
      |> with_tx_summary
  and {
    request_nft.minting(
      cfg,
      tx,
      req_skh,
      req_pid,
      borrower_pid,
      borrower_in.output_reference,
    ),
    borrower_nft.minting(
      cfg,
      tx,
      req_skh,
      req_pid,
      borrower_pid,
      borrower_in.output_reference,
    ),
  } |> not
}

test fail_when_minting_more_than_1_request_nft() fail {
  let cfg = build_cfg()
  let (t, borrower_in) = build_tx()
  expect [request_out, borrower_out] = t.outputs
  let req_datum = get_request_datum(request_out)
  let tx =
    Transaction {
      ..t,
      mint: t.mint
        |> value.from_minted_value
        |> value.add(req_pid, req_datum.borrower, 1)
        |> value.to_minted_value,
      outputs: [
        request_out,
        borrower_out |> add_asset(req_pid, req_datum.borrower, 1),
      ],
    }
      |> with_tx_summary
  and {
    request_nft.minting(
      cfg,
      tx,
      req_skh,
      req_pid,
      borrower_pid,
      borrower_in.output_reference,
    ),
    borrower_nft.minting(
      cfg,
      tx,
      req_skh,
      req_pid,
      borrower_pid,
      borrower_in.output_reference,
    ),
  } |> not
}

test fail_when_minting_more_than_1_borrower_nft() {
  let cfg = build_cfg()
  let (t, borrower_in) = build_tx()
  expect [request_out, borrower_out] = t.outputs
  let req_datum = get_request_datum(request_out)
  let tx =
    Transaction {
      ..t,
      mint: t.mint
        |> value.from_minted_value
        |> value.add(borrower_pid, req_datum.borrower, 1)
        |> value.to_minted_value,
      outputs: [
        request_out,
        borrower_out |> add_asset(borrower_pid, req_datum.borrower, 1),
      ],
    }
      |> with_tx_summary
  and {
    request_nft.minting(
      cfg,
      tx,
      req_skh,
      req_pid,
      borrower_pid,
      borrower_in.output_reference,
    ),
    borrower_nft.minting(
      cfg,
      tx,
      req_skh,
      req_pid,
      borrower_pid,
      borrower_in.output_reference,
    ),
  } |> not
}

test fail_when_borrow_request_holds_incorrect_nft() fail {
  let cfg = build_cfg()
  let (t, borrower_in) = build_tx()
  expect [request_out, borrower_out] = t.outputs
  let req_datum = get_request_datum(request_out)
  let other_name = "other_nft"
  let tx =
    Transaction {
      ..t,
      inputs: [
        Input {
          ..borrower_in,
          output: borrower_in.output |> add_asset(req_pid, other_name, 1),
        },
      ],
      outputs: [
        request_out
          |> add_asset(req_pid, req_datum.borrower, -1)
          |> add_asset(req_pid, other_name, 1),
        borrower_out |> add_asset(req_pid, req_datum.borrower, 1),
      ],
    }
      |> with_tx_summary
  and {
    request_nft.minting(
      cfg,
      tx,
      req_skh,
      req_pid,
      borrower_pid,
      borrower_in.output_reference,
    ),
    borrower_nft.minting(
      cfg,
      tx,
      req_skh,
      req_pid,
      borrower_pid,
      borrower_in.output_reference,
    ),
  } |> not
}

test fail_when_doesnt_set_stake_credential() fail {
  let cfg = build_cfg()
  let (t, borrower_in) = build_tx()
  expect [request_out, borrower_out] = t.outputs
  let tx =
    Transaction {
      ..t,
      outputs: [request_out |> set_stake_credential(None), borrower_out],
    }
      |> with_tx_summary
  and {
    request_nft.minting(
      cfg,
      tx,
      req_skh,
      req_pid,
      borrower_pid,
      borrower_in.output_reference,
    ),
    borrower_nft.minting(
      cfg,
      tx,
      req_skh,
      req_pid,
      borrower_pid,
      borrower_in.output_reference,
    ),
  } |> not
}

test fail_when_setting_apr_lower_than_min_apr() fail {
  let cfg = build_cfg()
  let (t, borrower_in) = build_tx()
  expect [request_out, borrower_out] = t.outputs
  let tx =
    Transaction {
      ..t,
      outputs: [request_out |> set_apr(cfg.platform.min_apr - 1), borrower_out],
    }
      |> with_tx_summary
  and {
    request_nft.minting(
      cfg,
      tx,
      req_skh,
      req_pid,
      borrower_pid,
      borrower_in.output_reference,
    ),
    borrower_nft.minting(
      cfg,
      tx,
      req_skh,
      req_pid,
      borrower_pid,
      borrower_in.output_reference,
    ),
  } |> not
}

test fail_when_setting_duration_lower_than_min_duration() fail {
  let cfg = build_cfg()
  let (t, borrower_in) = build_tx()
  expect [request_out, borrower_out] = t.outputs
  let tx =
    Transaction {
      ..t,
      outputs: [
        request_out |> set_duration(cfg.platform.min_duration - 1),
        borrower_out,
      ],
    }
      |> with_tx_summary
  and {
    request_nft.minting(
      cfg,
      tx,
      req_skh,
      req_pid,
      borrower_pid,
      borrower_in.output_reference,
    ),
    borrower_nft.minting(
      cfg,
      tx,
      req_skh,
      req_pid,
      borrower_pid,
      borrower_in.output_reference,
    ),
  } |> not
}

test fail_when_setting_incorrect_symbol() fail {
  let cfg = build_cfg()
  let (t, borrower_in) = build_tx()
  expect [request_out, borrower_out] = t.outputs
  let tx =
    Transaction {
      ..t,
      outputs: [request_out |> set_symbol("other_symbol"), borrower_out],
    }
      |> with_tx_summary
  and {
    request_nft.minting(
      cfg,
      tx,
      req_skh,
      req_pid,
      borrower_pid,
      borrower_in.output_reference,
    ),
    borrower_nft.minting(
      cfg,
      tx,
      req_skh,
      req_pid,
      borrower_pid,
      borrower_in.output_reference,
    ),
  } |> not
}

test fail_when_setting_incorrect_borrower() fail {
  let cfg = build_cfg()
  let (t, borrower_in) = build_tx()
  expect [request_out, borrower_out] = t.outputs
  let tx =
    Transaction {
      ..t,
      outputs: [request_out |> set_borrower("other_borrower"), borrower_out],
    }
      |> with_tx_summary
  and {
    request_nft.minting(
      cfg,
      tx,
      req_skh,
      req_pid,
      borrower_pid,
      borrower_in.output_reference,
    ),
    borrower_nft.minting(
      cfg,
      tx,
      req_skh,
      req_pid,
      borrower_pid,
      borrower_in.output_reference,
    ),
  } |> not
}

test fail_when_setting_requested_lower_than_min_requested() fail {
  let cfg = build_cfg()
  let (t, borrower_in) = build_tx()
  expect [request_out, borrower_out] = t.outputs
  let tx =
    Transaction {
      ..t,
      outputs: [
        request_out |> set_requested(cfg.platform.min_requested - 1),
        borrower_out,
      ],
    }
      |> with_tx_summary
  and {
    request_nft.minting(
      cfg,
      tx,
      req_skh,
      req_pid,
      borrower_pid,
      borrower_in.output_reference,
    ),
    borrower_nft.minting(
      cfg,
      tx,
      req_skh,
      req_pid,
      borrower_pid,
      borrower_in.output_reference,
    ),
  } |> not
}

test fail_when_setting_negative_issued() fail {
  let cfg = build_cfg()
  let (t, borrower_in) = build_tx()
  expect [request_out, borrower_out] = t.outputs
  let tx =
    Transaction { ..t, outputs: [request_out |> set_issued(-1), borrower_out] }
      |> with_tx_summary
  and {
    request_nft.minting(
      cfg,
      tx,
      req_skh,
      req_pid,
      borrower_pid,
      borrower_in.output_reference,
    ),
    borrower_nft.minting(
      cfg,
      tx,
      req_skh,
      req_pid,
      borrower_pid,
      borrower_in.output_reference,
    ),
  } |> not
}

test fail_when_setting_positive_issued() fail {
  let cfg = build_cfg()
  let (t, borrower_in) = build_tx()
  expect [request_out, borrower_out] = t.outputs
  let tx =
    Transaction { ..t, outputs: [request_out |> set_issued(1), borrower_out] }
      |> with_tx_summary
  and {
    request_nft.minting(
      cfg,
      tx,
      req_skh,
      req_pid,
      borrower_pid,
      borrower_in.output_reference,
    ),
    borrower_nft.minting(
      cfg,
      tx,
      req_skh,
      req_pid,
      borrower_pid,
      borrower_in.output_reference,
    ),
  } |> not
}

test fail_when_setting_epo_rewards_lower_than_expected() fail {
  let cfg = build_cfg()
  let (t, borrower_in) = build_tx()
  expect [request_out, borrower_out] = t.outputs
  let datum = get_request_datum(request_out)
  let tx =
    Transaction {
      ..t,
      outputs: [
        request_out |> set_epo_rewards(datum.epo_rewards - 1),
        borrower_out,
      ],
    }
      |> with_tx_summary
  and {
    request_nft.minting(
      cfg,
      tx,
      req_skh,
      req_pid,
      borrower_pid,
      borrower_in.output_reference,
    ),
    borrower_nft.minting(
      cfg,
      tx,
      req_skh,
      req_pid,
      borrower_pid,
      borrower_in.output_reference,
    ),
  } |> not
}

test fail_when_setting_buffer_lower_than_min_buffer() fail {
  let cfg = build_cfg()
  let (t, borrower_in) = build_tx()
  expect [request_out, borrower_out] = t.outputs
  let tx =
    Transaction {
      ..t,
      outputs: [
        request_out |> set_buffer(cfg.platform.min_buffer - 1),
        borrower_out,
      ],
    }
      |> with_tx_summary
  and {
    request_nft.minting(
      cfg,
      tx,
      req_skh,
      req_pid,
      borrower_pid,
      borrower_in.output_reference,
    ),
    borrower_nft.minting(
      cfg,
      tx,
      req_skh,
      req_pid,
      borrower_pid,
      borrower_in.output_reference,
    ),
  } |> not
}

test fail_when_setting_fee_lower_than_min_fee() fail {
  let cfg = build_cfg()
  let (t, borrower_in) = build_tx()
  expect [request_out, borrower_out] = t.outputs
  let tx =
    Transaction {
      ..t,
      outputs: [request_out |> set_fee(cfg.platform.fee - 1), borrower_out],
    }
      |> with_tx_summary
  and {
    request_nft.minting(
      cfg,
      tx,
      req_skh,
      req_pid,
      borrower_pid,
      borrower_in.output_reference,
    ),
    borrower_nft.minting(
      cfg,
      tx,
      req_skh,
      req_pid,
      borrower_pid,
      borrower_in.output_reference,
    ),
  } |> not
}

test fail_when_setting_prepaid_lower_min_prepaid() fail {
  let cfg = build_cfg()
  let (t, borrower_in) = build_tx()
  expect [request_out, borrower_out] = t.outputs
  let datum = get_request_datum(request_out)
  let tx =
    Transaction {
      ..t,
      outputs: [
        request_out |> set_prepaid(get_min_prepaid(cfg, datum.buffer) - 1),
        borrower_out,
      ],
    }
      |> with_tx_summary
  and {
    request_nft.minting(
      cfg,
      tx,
      req_skh,
      req_pid,
      borrower_pid,
      borrower_in.output_reference,
    ),
    borrower_nft.minting(
      cfg,
      tx,
      req_skh,
      req_pid,
      borrower_pid,
      borrower_in.output_reference,
    ),
  } |> not
}

test fail_when_setting_deposit_ada_lower_than_expected() fail {
  let cfg = build_cfg()
  let (t, borrower_in) = build_tx()
  expect [request_out, borrower_out] = t.outputs
  let tx =
    Transaction {
      ..t,
      outputs: [
        request_out |> add_asset(value.ada_policy_id, value.ada_asset_name, -1),
        borrower_out,
      ],
    }
      |> with_tx_summary
  and {
    request_nft.minting(
      cfg,
      tx,
      req_skh,
      req_pid,
      borrower_pid,
      borrower_in.output_reference,
    ),
    borrower_nft.minting(
      cfg,
      tx,
      req_skh,
      req_pid,
      borrower_pid,
      borrower_in.output_reference,
    ),
  } |> not
}

test fail_when_borrow_request_has_no_datum() fail {
  let cfg = build_cfg()
  let (t, borrower_in) = build_tx()
  expect [request_out, borrower_out] = t.outputs
  let tx =
    Transaction {
      ..t,
      outputs: [request_out |> set_datum(NoDatum), borrower_out],
    }
      |> with_tx_summary
  and {
    request_nft.minting(
      cfg,
      tx,
      req_skh,
      req_pid,
      borrower_pid,
      borrower_in.output_reference,
    ),
    borrower_nft.minting(
      cfg,
      tx,
      req_skh,
      req_pid,
      borrower_pid,
      borrower_in.output_reference,
    ),
  } |> not
}

type InvalidDatum {
  owner: ByteArray,
}

test fail_when_borrow_request_has_invalid_datum() fail {
  let cfg = build_cfg()
  let (t, borrower_in) = build_tx()
  expect [request_out, borrower_out] = t.outputs
  let tx =
    Transaction {
      ..t,
      outputs: [
        request_out |> set_datum(InlineDatum(InvalidDatum("asd"))),
        borrower_out,
      ],
    }
      |> with_tx_summary
  and {
    request_nft.minting(
      cfg,
      tx,
      req_skh,
      req_pid,
      borrower_pid,
      borrower_in.output_reference,
    ),
    borrower_nft.minting(
      cfg,
      tx,
      req_skh,
      req_pid,
      borrower_pid,
      borrower_in.output_reference,
    ),
  } |> not
}

test fail_when_attempting_double_satisfaction() {
  let cfg = build_cfg()
  let borrower1_in =
    Input {
      output_reference: OutputReference(TransactionId("borrower_tx_1"), 1),
      output: build_borrower_output(),
    }
  let borrower2_in =
    Input {
      output_reference: OutputReference(TransactionId("borrower_tx_1"), 2),
      output: build_borrower_output(),
    }
  let borrower1 = hash_out_ref(borrower1_in.output_reference)
  let borrower2 = hash_out_ref(borrower2_in.output_reference)
  let borrow_request1_out = build_borrow_request_output(borrower1)
  let borrow_request2_out = build_borrow_request_output(borrower2)
  let tx =
    Transaction {
      ..placeholder(),
      mint: value.from_asset(req_pid, borrower1, 1)
        |> value.add(borrower_pid, borrower1, 1)
        |> value.add(req_pid, borrower2, 1)
        |> value.add(borrower_pid, borrower2, 1)
        |> value.to_minted_value,
      inputs: [borrower1_in, borrower2_in],
      outputs: [
        borrow_request1_out,
        // steal nft of request2
        borrow_request2_out |> add_asset(req_pid, borrower2, -1),
        borrower1_in.output
          |> add_asset(borrower_pid, borrower1, 1)
          |> add_asset(req_pid, borrower2, 1),
        borrower2_in.output
          |> add_asset(borrower_pid, borrower2, 1),
      ],
    }
      |> with_tx_summary
  and {
    request_nft.minting(
      cfg,
      tx,
      req_skh,
      req_pid,
      borrower_pid,
      borrower1_in.output_reference,
    ),
    borrower_nft.minting(
      cfg,
      tx,
      req_skh,
      req_pid,
      borrower_pid,
      borrower1_in.output_reference,
    ),
    request_nft.minting(
      cfg,
      tx,
      req_skh,
      req_pid,
      borrower_pid,
      borrower2_in.output_reference,
    ),
    borrower_nft.minting(
      cfg,
      tx,
      req_skh,
      req_pid,
      borrower_pid,
      borrower2_in.output_reference,
    ),
  } |> not
}
