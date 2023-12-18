use aiken/list.{concat, indexed_map, map, push, repeat}
use aiken/transaction.{
  Datum, InlineDatum, Input, NoDatum, Output, OutputReference, Transaction,
  TransactionId, placeholder,
}
use aiken/transaction/credential.{Address, Inline, VerificationKeyCredential}
use aiken/transaction/value.{AssetName, PolicyId}
use bond_issue/types.{BondIssueConfig, PlatformConfig, RequestDatum}
use borrow_request/request_nft
use common/fixture.{get_epoch_config_mainnet}
use common/hash_out_refs.{hash_out_ref}
use common/time.{BasisPoints, get_slot_config_network_mainnet}

// ========= Params ==========
const user_stake_cred = "user_stake_key"

const user_payment_cred = "user_payment_key"

const req_pid = "req_pid"

const borrower_pid = "borrower_pid"

const req_skh = "borrowing_script_pkh"

// ========= Tests ==========
test succ_when_all_rules_are_satisfied() {
  let tx = build_tx(None)
  validate(tx, None)
}

test succ_when_seed_input_isnt_first() {
  let seed_input =
    Input {
      ..build_user_input(),
      output_reference: OutputReference(TransactionId("seed_tx"), 1337),
    }

  let tx =
    build_tx(Some(seed_input))
      |> fn(t) {
           Transaction {
             ..t,
             inputs: t.inputs |> push(seed_input) |> push(build_user_input()),
           }
         }
  validate(tx, Some(seed_input.output_reference))
}

test fail_when_wrong_seed() fail {
  let unknown_ref = OutputReference(TransactionId("unknown"), 2)
  let tx = build_tx(None)
  validate(tx, Some(unknown_ref))
}

// Minting
test fail_when_minting_no_nft() {
  let tx =
    build_tx(None)
      |> fn(t: Transaction) {
           expect [input] = t.inputs
           let borrower = hash_out_ref(input.output_reference)
           Transaction {
             ..t,
             mint: value.zero()
               |> value.add(borrower_pid, borrower, 1)
               |> value.to_minted_value(),
           }
         }
  !validate(tx, None)
}

test fail_when_minting_incorrect_borrower_nft_name() {
  let tx =
    build_tx(None)
      |> fn(t: Transaction) {
           expect [input] = t.inputs
           let borrower = hash_out_ref(input.output_reference)
           Transaction {
             ..t,
             mint: value.from_asset(req_pid, borrower, 1)
               |> value.add(borrower_pid, "other_nft", 1)
               |> value.to_minted_value(),
           }
         }
  !validate(tx, None)
}

test fail_when_minting_incorrect_request_nft_name() {
  let tx =
    build_tx(None)
      |> fn(t: Transaction) {
           expect [input] = t.inputs
           let borrower = hash_out_ref(input.output_reference)
           Transaction {
             ..t,
             mint: value.from_asset(req_pid, "other_nft", 1)
               |> value.add(borrower_pid, borrower, 1)
               |> value.to_minted_value(),
           }
         }
  !validate(tx, None)
}

test fail_when_output_incorrect_request_nft_name() {
  let tx =
    build_tx(None)
      |> fn(t: Transaction) {
           expect [input] = t.inputs
           let borrow_request_out = build_borrow_request_output(#"")
           let borrower = hash_out_ref(input.output_reference)
           Transaction {
             ..t,
             outputs: [
               borrow_request_out,
               input.output
                 |> set_asset(borrower_pid, borrower, 1),
             ],
           }
         }
  !validate(tx, None)
}

test fail_when_minting_double_nft() fail {
  let tx =
    build_tx(None)
      |> fn(t: Transaction) {
           expect [input] = t.inputs
           let borrower = hash_out_ref(input.output_reference)
           Transaction {
             ..t,
             mint: value.from_asset(req_pid, borrower, 2)
               |> value.add(borrower_pid, borrower, 1)
               |> value.to_minted_value(),
           }
         }
  !validate(tx, None)
}

test fail_when_not_minting_borrower_nft() {
  let tx =
    build_tx(None)
      |> fn(t: Transaction) {
           expect [input] = t.inputs
           let borrower = hash_out_ref(input.output_reference)
           Transaction {
             ..t,
             mint: value.from_asset(req_pid, borrower, 1)
               |> value.to_minted_value(),
           }
         }
  !validate(tx, None)
}

test succ_when_minting_other_tokens_additionally() {
  let tx =
    build_tx(None)
      |> fn(t) {
           Transaction {
             ..t,
             mint: t.mint
               |> value.from_minted_value()
               |> value.add(req_pid, "other_token", 1)
               |> value.to_minted_value(),
           }
         }
  validate(tx, None)
}

// Borrow Request UTxO

test succ_when_doesnt_set_stake_credential() {
  let tx =
    build_tx(None)
      |> fn(t: Transaction) {
           expect [borrow_request_out, user_out] = t.outputs
           Transaction {
             ..t,
             outputs: [
               borrow_request_out
                 |> set_stake_credential(None),
               user_out,
             ],
           }
         }
  validate(tx, None)
}

test succ_when_setting_apr_lower_than_min_apr() {
  let cfg: BondIssueConfig = build_cfg()
  let tx =
    build_tx(None)
      |> fn(t: Transaction) {
           expect [borrow_request_out, user_out] = t.outputs
           Transaction {
             ..t,
             outputs: [
               borrow_request_out
                 |> set_apr(cfg.platform.min_apr - 1),
               user_out,
             ],
           }
         }
  validate(tx, None)
}

test succ_when_setting_duration_lowwer_than_min_duration() {
  let cfg: BondIssueConfig = build_cfg()
  let tx =
    build_tx(None)
      |> fn(t: Transaction) {
           expect [borrow_request_out, user_out] = t.outputs
           Transaction {
             ..t,
             outputs: [
               borrow_request_out
                 |> set_duration(cfg.platform.min_duration - 1),
               user_out,
             ],
           }
         }
  validate(tx, None)
}

test succ_when_setting_incorrect_symbol() {
  let tx =
    build_tx(None)
      |> fn(t: Transaction) {
           expect [borrow_request_out, user_out] = t.outputs
           Transaction {
             ..t,
             outputs: [
               borrow_request_out
                 |> set_symbol("not_req_pid"),
               user_out,
             ],
           }
         }
  validate(tx, None)
}

test succ_when_setting_incorrect_borrower() {
  let tx =
    build_tx(None)
      |> fn(t: Transaction) {
           expect [borrow_request_out, user_out] = t.outputs
           Transaction {
             ..t,
             outputs: [
               borrow_request_out
                 |> set_borrower("not_nft_name"),
               user_out,
             ],
           }
         }
  validate(tx, None)
}

test succ_when_setting_requested_lower_than_min_requested() {
  let cfg: BondIssueConfig = build_cfg()
  let tx =
    build_tx(None)
      |> fn(t: Transaction) {
           expect [borrow_request_out, user_out] = t.outputs
           Transaction {
             ..t,
             outputs: [
               borrow_request_out
                 |> set_requested(cfg.platform.min_requested - 1),
               user_out,
             ],
           }
         }
  validate(tx, None)
}

test succ_when_setting_negative_issued() {
  let tx =
    build_tx(None)
      |> fn(t: Transaction) {
           expect [borrow_request_out, user_out] = t.outputs
           Transaction {
             ..t,
             outputs: [
               borrow_request_out
                 |> set_issued(-1),
               user_out,
             ],
           }
         }
  validate(tx, None)
}

test succ_when_setting_positive_issued() {
  let tx =
    build_tx(None)
      |> fn(t: Transaction) {
           expect [borrow_request_out, user_out] = t.outputs
           Transaction {
             ..t,
             outputs: [
               borrow_request_out
                 |> set_issued(1),
               user_out,
             ],
           }
         }
  validate(tx, None)
}

test succ_when_setting_epo_rewards_lower_than_expected() {
  let cfg: BondIssueConfig = build_cfg()
  let tx =
    build_tx(None)
      |> fn(t: Transaction) {
           expect [borrow_request_out, user_out] = t.outputs
           expect odatum: RequestDatum = get_datum(borrow_request_out)
           Transaction {
             ..t,
             outputs: [
               borrow_request_out
                 |> set_epo_rewards(
                      get_min_epo_rewards(
                        cfg,
                        odatum.requested,
                        odatum.issued,
                        odatum.apr,
                      ) - 1,
                    ),
               user_out,
             ],
           }
         }
  validate(tx, None)
}

test succ_when_setting_buffer_lower_than_min_buffer() {
  let cfg: BondIssueConfig = build_cfg()
  let tx =
    build_tx(None)
      |> fn(t: Transaction) {
           expect [borrow_request_out, user_out] = t.outputs
           Transaction {
             ..t,
             outputs: [
               borrow_request_out
                 |> set_buffer(cfg.platform.min_buffer - 1),
               user_out,
             ],
           }
         }
  validate(tx, None)
}

test succ_when_setting_fee_lower_than_min_fee() {
  let cfg: BondIssueConfig = build_cfg()
  let tx =
    build_tx(None)
      |> fn(t: Transaction) {
           expect [borrow_request_out, user_out] = t.outputs
           Transaction {
             ..t,
             outputs: [
               borrow_request_out
                 |> set_fee(cfg.platform.fee - 1),
               user_out,
             ],
           }
         }
  validate(tx, None)
}

test succ_when_setting_deposit_ada_lower_than_expected() {
  let tx =
    build_tx(None)
      |> fn(t: Transaction) {
           expect [borrow_request_out, user_out] = t.outputs
           expect odatum: RequestDatum = get_datum(borrow_request_out)
           Transaction {
             ..t,
             outputs: [
               borrow_request_out
                 |> set_asset(
                      value.ada_policy_id,
                      value.ada_asset_name,
                      get_borrow_request_min_ada(
                        odatum.epo_rewards,
                        odatum.prepaid,
                      ) - 1,
                    ),
               user_out,
             ],
           }
         }
  validate(tx, None)
}

test succ_when_doesnt_create_borrow_request() fail {
  let tx =
    build_tx(None)
      |> fn(t: Transaction) {
           expect [_, user_out] = t.outputs
           Transaction { ..t, outputs: [user_out] }
         }
  validate(tx, None)
}

test succ_when_borrow_request_has_no_datum() {
  let tx =
    build_tx(None)
      |> fn(t: Transaction) {
           expect [borrow_request_out, user_out] = t.outputs
           Transaction {
             ..t,
             outputs: [borrow_request_out |> set_datum(NoDatum), user_out],
           }
         }
  validate(tx, None)
}

type UnkownDatum {
  owner: ByteArray,
}

test succ_when_borrow_request_has_invalid_datum() {
  let tx =
    build_tx(None)
      |> fn(t: Transaction) {
           expect [borrow_request_out, user_out] = t.outputs
           Transaction {
             ..t,
             outputs: [
               borrow_request_out
                 |> set_datum(InlineDatum(UnkownDatum { owner: "unknown_pk" })),
               user_out,
             ],
           }
         }
  validate(tx, None)
}

// Attacks
test fail_when_attempting_double_sastification() fail {
  let tx =
    build_tx(None)
      |> fn(t: Transaction) {
           expect [borrow_request_out, user_out] = t.outputs
           Transaction {
             ..t,
             outputs: [
               borrow_request_out,
               user_out,
               borrow_request_out
                 |> set_prepaid(0)
                 |> set_issued(10000)
                 |> set_fee(0),
             ],
           }
         }
  !validate(tx, None)
}

// Benchmarks
test succ_on_large_inputs() {
  let tx =
    build_tx(None)
      |> fn(t: Transaction) {
           let dusts =
             repeat("normal_tx", 100)
               |> indexed_map(
                    fn(index, tx_hash) {
                      Input {
                        output_reference: OutputReference(
                          TransactionId(tx_hash),
                          index,
                        ),
                        output: Output {
                          address: credential.from_verification_key(
                            user_payment_cred,
                          )
                            |> credential.with_delegation_key(user_stake_cred),
                          value: value.from_lovelace(1238),
                          datum: NoDatum,
                          reference_script: None,
                        },
                      }
                    },
                  )
           expect [input] = t.inputs
           let inputs = t.inputs |> concat(dusts)
           let borrower = hash_out_ref(input.output_reference)
           let borrow_request_out = build_borrow_request_output(borrower)
           let user_in: Input = build_user_input()

           Transaction {
             ..placeholder(),
             mint: value.from_asset(req_pid, borrower, 1)
               |> value.add(borrower_pid, borrower, 1)
               |> value.to_minted_value(),
             inputs: inputs,
             outputs: [
               borrow_request_out,
               user_in.output
                 |> set_asset(borrower_pid, borrower, 1),
             ],
           }
         }
  validate(tx, None)
}

test succ_on_large_outputs() {
  let tx =
    build_tx(None)
      |> fn(t: Transaction) {
           let dusts =
             repeat("normal_tx", 100)
               |> map(
                    fn(_) {
                      Output {
                        address: credential.from_verification_key(
                          user_payment_cred,
                        )
                          |> credential.with_delegation_key(user_stake_cred),
                        value: value.from_lovelace(1238),
                        datum: NoDatum,
                        reference_script: None,
                      }
                    },
                  )
           Transaction { ..t, outputs: t.outputs |> concat(dusts) }
         }
  validate(tx, None)
}

// ========= Helpers ==========

fn set_asset(self: Output, policy_id: PolicyId, token_name: ByteArray, qty: Int) {
  Output {
    ..self,
    value: self.value
      |> value.add(
           policy_id,
           token_name,
           qty - value.quantity_of(self.value, policy_id, token_name),
         ),
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

fn build_user_input() {
  Input {
    output_reference: OutputReference(TransactionId("user_tx"), 1),
    output: Output {
      address: credential.from_verification_key(user_payment_cred)
        |> credential.with_delegation_key(user_stake_cred),
      value: value.from_lovelace(1029382),
      datum: NoDatum,
      reference_script: None,
    },
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
      |> credential.with_delegation_key(user_stake_cred),
    value: value.from_lovelace(get_borrow_request_min_ada(epo_rewards, prepaid))
      |> value.add(req_pid, borrower, 1),
    datum: InlineDatum(
      RequestDatum {
        apr,
        duration,
        symbol: req_pid,
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

fn build_tx(seed: Option<Input>) -> Transaction {
  let user_in = build_user_input()
  let inputs =
    [user_in]
  let seed_input =
    when seed is {
      None -> user_in
      Some(in) -> in
    }
  let borrower = hash_out_ref(seed_input.output_reference)
  let borrow_request_out = build_borrow_request_output(borrower)
  Transaction {
    ..placeholder(),
    mint: value.from_asset(req_pid, borrower, 1)
      |> value.add(borrower_pid, borrower, 1)
      |> value.to_minted_value,
    inputs: inputs,
    outputs: [
      borrow_request_out,
      user_in.output
        |> set_asset(borrower_pid, borrower, 1),
    ],
  }
}

fn build_cfg() {
  BondIssueConfig {
    slot: get_slot_config_network_mainnet(),
    epoch: get_epoch_config_mainnet(),
    basis: BasisPoints { base: 10_000, min: 1, max: 9_999 },
    platform: PlatformConfig {
      bond_face_value: 100_000_000,
      fee: 500,
      address: credential.from_script("collector_addr"),
      tx_ttl: 3 * 60,
      min_buffer: 6,
      prepaid_plus: 3,
      min_requested: 100,
      min_apr: 200,
      min_duration: 6,
    },
  }
}

fn validate(tx: Transaction, seed_out_ref: Option<OutputReference>) {
  let seed =
    when seed_out_ref is {
      None -> {
        expect [input, ..] = tx.inputs
        input.output_reference
      }
      Some(out_ref) -> out_ref
    }
  request_nft.create(tx, req_pid, seed, req_skh, borrower_pid)
}
