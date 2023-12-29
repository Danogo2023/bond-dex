use aiken/bytearray
use aiken/cbor
use aiken/dict
use aiken/interval.{Finite, Interval, IntervalBound, entirely_between}
use aiken/list
use aiken/string
use aiken/transaction.{
  InlineDatum, Input, Mint, NoDatum, Output, OutputReference, ScriptPurpose,
  Spend, Transaction, TransactionId,
}
use aiken/transaction/credential.{Address, Inline, VerificationKeyCredential}
use aiken/transaction/value.{PolicyId}
use bond_issue/types.{BondDatum,
  BondIssueConfig, PlatformConfig} as bond_issue_types
use borrow_position/bond_nft
use borrow_position/bond_token
use borrow_position/redeem_bond
use common/time.{
  BasisPoints, get_epoch_config_mainnet, get_slot_config_network_mainnet,
}
use issue_bond/types.{BondRedeem} as issue_bond_types

const ada = 1_000_000

const epo_rewards = 1_000_000

const nft_pid = "nft_pid"

const bond_pid = "bond_pid"

const bond_token_name = "bond_name"

const bond_skh = "bond_skh"

// =================Builders===================

fn get_datum(self: Output) -> Data {
  expect InlineDatum(datum) = self.datum
  datum
}

fn get_bond_datum(self: Output) {
  expect bond_datum: BondDatum = get_datum(self)
  bond_datum
}

fn build_cfg() {
  BondIssueConfig {
    slot: get_slot_config_network_mainnet(),
    epoch: get_epoch_config_mainnet(),
    basis: BasisPoints { base: 10_000, min: 1, max: 9_999 },
    platform: PlatformConfig {
      bond_face_value: 100 * ada,
      fee: 500,
      fee_addr: credential.from_verification_key("fee_addr"),
      tx_ttl: 1 * 60,
      min_buffer: 6,
      prepaid_plus: 3,
      min_requested: 100,
      min_apr: 200,
      min_duration: 6,
      garbage_addr: credential.from_verification_key("garbage_addr"),
    },
  }
}

fn build_bond_output(datum: BondDatum) {
  // paid interest for 60 epochs
  let interest = 60 * epo_rewards
  let locked_value = principal_of(datum.bond_amount) + interest
  Output {
    address: credential.from_script(bond_skh)
      |> credential.with_delegation_key("borrower_stake"),
    value: value.from_lovelace(locked_value)
      |> value.add(nft_pid, datum.token_name, 1),
    datum: InlineDatum(datum),
    reference_script: None,
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

fn script_purpose_compare(a: ScriptPurpose, b: ScriptPurpose) {
  bytearray.compare(
    cbor.diagnostic(a) |> string.to_bytearray,
    cbor.diagnostic(b) |> string.to_bytearray,
  )
}

fn add_asset(self: Output, pid: PolicyId, name: ByteArray, amt: Int) {
  Output { ..self, value: self.value |> value.add(pid, name, amt) }
}

fn set_bond_datum(self: Output, updater: fn(BondDatum) -> BondDatum) {
  Output { ..self, datum: InlineDatum(updater(get_bond_datum(self))) }
}

fn set_bond_amount(self: Output, amt: Int) {
  set_bond_datum(self, fn(datum) { BondDatum { ..datum, bond_amount: amt } })
}

type RedeemType {
  RedeemPartially(Int)
  RedeemAll
}

fn resolve_redeem_amount(redeem_type, datum: BondDatum) {
  when redeem_type is {
    RedeemPartially(amt) -> amt
    RedeemAll -> datum.bond_amount
  }
}

fn principal_of(bond_amt: Int) {
  let cfg = build_cfg()
  bond_amt * cfg.platform.bond_face_value
}

fn resolve_sbond(self: Output, lender_in: Input, redeem_type: RedeemType) {
  let cfg = build_cfg()
  let datum = get_bond_datum(self)
  let redeem_amt = resolve_redeem_amount(redeem_type, datum)
  let remain_bond_amount = datum.bond_amount - redeem_amt
  let locked_amt =
    self.value |> value.quantity_of(value.ada_policy_id, value.ada_asset_name)
  let total_interest = locked_amt - principal_of(datum.bond_amount)
  let redeem_interest = total_interest * redeem_amt / datum.bond_amount
  let fee_amt = redeem_interest * datum.fee / cfg.basis.base
  let lender_received_amt = principal_of(redeem_amt) + redeem_interest - fee_amt
  let fee_out =
    Output {
      address: cfg.platform.fee_addr,
      value: value.from_lovelace(fee_amt),
      datum: NoDatum,
      reference_script: None,
    }
  let lender_out =
    lender_in.output
      |> add_asset(value.ada_policy_id, value.ada_asset_name, lender_received_amt)
      |> add_asset(datum.bond_symbol, datum.token_name, -redeem_amt)
  if remain_bond_amount == 0 {
    [lender_out, fee_out]
  } else {
    let bond_out =
      self
        |> set_bond_amount(remain_bond_amount)
        |> add_asset(
             value.ada_policy_id,
             value.ada_asset_name,
             -(lender_received_amt + fee_amt),
           )
    [lender_out, fee_out, bond_out]
  }
}

fn build_lender_output(lovelace: Int, bond_token_qty: Int) {
  Output {
    address: credential.from_verification_key("lender_public_key")
      |> credential.with_delegation_key("lender_delegation_key"),
    value: value.from_lovelace(lovelace)
      |> value.add(bond_pid, bond_token_name, bond_token_qty),
    datum: NoDatum,
    reference_script: None,
  }
}

fn valid_in_next_30s(bond: BondDatum) {
  let cfg = build_cfg()
  let current_epoch = bond.start + bond.duration
  let from = cfg.epoch.epoch_boundary + current_epoch * cfg.epoch.epoch_length
  let to = from + 30 * cfg.slot.slot_length
  entirely_between(from, to)
}

fn shift_interval(itv: Interval<Int>, diff: Int) {
  expect Finite(from) = itv.lower_bound.bound_type
  expect Finite(to) = itv.upper_bound.bound_type
  entirely_between(from + diff, to + diff)
}

fn build_tx(redeem_type: RedeemType) {
  let cfg = build_cfg()
  let t = transaction.placeholder()
  let bond_datum =
    BondDatum {
      epo_rewards: value.from_lovelace(epo_rewards),
      bond_symbol: bond_pid,
      token_name: bond_token_name,
      bond_amount: 122,
      fee: 500,
      borrower: "borrower_1",
      start: 400,
      buffer: cfg.platform.min_buffer,
      duration: 100,
    }
  let redeem_amt = resolve_redeem_amount(redeem_type, bond_datum)
  let sbond =
    Input {
      output_reference: OutputReference(TransactionId("tx_sbond_1"), 2),
      output: build_bond_output(bond_datum),
    }
  let lender_in =
    Input {
      output_reference: OutputReference(TransactionId("lender_tx_1"), 0),
      output: build_lender_output(lovelace: 100 * ada, bond_token_qty: 500),
    }
  let outputs = resolve_sbond(sbond.output, lender_in, redeem_type)
  let mint =
    value.from_asset(bond_pid, bond_datum.token_name, -redeem_amt)
      |> fn(v) {
           if redeem_amt == bond_datum.bond_amount {
             v |> value.add(nft_pid, bond_datum.token_name, -1)
           } else {
             v
           }
         }
      |> value.to_minted_value
  let redeemers =
    t.redeemers
      |> dict.insert(
           Spend(sbond.output_reference),
           BondRedeem { pid: nft_pid },
           script_purpose_compare,
         )
      |> dict.insert(
           Mint(nft_pid),
           BondRedeem { pid: nft_pid },
           script_purpose_compare,
         )
      |> dict.insert(
           Mint(bond_pid),
           BondRedeem { pid: bond_pid },
           script_purpose_compare,
         )
  let tx =
    Transaction {
      ..t,
      validity_range: valid_in_next_30s(bond_datum),
      mint: mint,
      redeemers: redeemers,
      inputs: [sbond, lender_in],
      outputs: outputs,
    }
  (tx, sbond.output)
}

// =================Implementation===================

test succ_when_redeeming_1_bond() {
  let cfg = build_cfg()
  let (tx, sbond) = build_tx(RedeemPartially(1))
  and {
    redeem_bond.spending_with_fee(
      cfg,
      tx,
      sbond,
      sbond.address,
      get_bond_datum(sbond),
      nft_pid,
    ),
    bond_token.burning_bond_redeem(tx, bond_pid, nft_pid),
    True,
  }
}

test succ_when_redeeming_all_bonds() {
  let cfg = build_cfg()
  let (tx, sbond) = build_tx(RedeemAll)
  and {
    redeem_bond.spending_with_fee(
      cfg,
      tx,
      sbond,
      sbond.address,
      get_bond_datum(sbond),
      nft_pid,
    ),
    bond_nft.burning_bond_redeem(tx, nft_pid, bond_pid),
    bond_token.burning_bond_redeem(tx, bond_pid, nft_pid),
  }
}

// bond tokens
test fail_when_burning_not_enough_bond_tokens_if_redeeming_partially() {
  let cfg = build_cfg()
  let (tx, sbond) = build_tx(RedeemPartially(10))
  and {
    redeem_bond.spending_with_fee(
      cfg,
      tx
        |> fn(t) {
             Transaction {
               ..t,
               mint: t.mint
                 |> value.from_minted_value
                 |> value.add(bond_pid, bond_token_name, 1)
                 |> value.to_minted_value,
             }
           },
      sbond,
      sbond.address,
      get_bond_datum(sbond),
      nft_pid,
    ),
    bond_token.burning_bond_redeem(tx, bond_pid, nft_pid),
    True,
  } |> not
}

test fail_when_burning_not_enough_bond_tokens_if_redeeming_all() {
  let cfg = build_cfg()
  let (tx, sbond) = build_tx(RedeemAll)
  and {
    redeem_bond.spending_with_fee(
      cfg,
      tx
        |> fn(t) {
             Transaction {
               ..t,
               mint: t.mint
                 |> value.from_minted_value
                 |> value.add(bond_pid, bond_token_name, 1)
                 |> value.to_minted_value,
             }
           },
      sbond,
      sbond.address,
      get_bond_datum(sbond),
      nft_pid,
    ),
    bond_nft.burning_bond_redeem(tx, nft_pid, bond_pid),
    bond_token.burning_bond_redeem(tx, bond_pid, nft_pid),
    True,
  } |> not
}

test fail_when_doesnt_burn_bond_tokens_if_redeeming_partially() {
  let cfg = build_cfg()
  let (tx, sbond) = build_tx(RedeemPartially(1))
  and {
    redeem_bond.spending_with_fee(
      cfg,
      tx
        |> fn(t) {
             Transaction {
               ..t,
               mint: t.mint
                 |> value.from_minted_value
                 |> value.add(bond_pid, bond_token_name, 1)
                 |> value.to_minted_value,
             }
           },
      sbond,
      sbond.address,
      get_bond_datum(sbond),
      nft_pid,
    ),
    True,
  } |> not
}

test fail_when_doesnt_burn_bond_tokens_if_redeeming_all() {
  let cfg = build_cfg()
  let (tx, sbond) = build_tx(RedeemAll)
  and {
    redeem_bond.spending_with_fee(
      cfg,
      tx
        |> fn(t) {
             Transaction {
               ..t,
               mint: t.mint
                 |> value.from_minted_value
                 |> value.add(bond_pid, bond_token_name, 100)
                 |> value.to_minted_value,
             }
           },
      sbond,
      sbond.address,
      get_bond_datum(sbond),
      nft_pid,
    ),
    bond_nft.burning_bond_redeem(tx, nft_pid, bond_pid),
    True,
  } |> not
}

test fail_when_doesnt_burn_bond_nft_if_redeeming_all() fail {
  let cfg = build_cfg()
  let (tx, sbond) = build_tx(RedeemAll)
  and {
    redeem_bond.spending_with_fee(
      cfg,
      tx
        |> fn(t) {
             Transaction {
               ..t,
               mint: t.mint
                 |> value.from_minted_value
                 |> value.add(nft_pid, bond_token_name, 1)
                 |> value.to_minted_value,
             }
           },
      sbond,
      sbond.address,
      get_bond_datum(sbond),
      nft_pid,
    ),
    bond_token.burning_bond_redeem(tx, bond_pid, nft_pid),
    True,
  } |> not
}

test fail_when_burning_bond_nft_if_redeeming_partially() fail {
  let cfg = build_cfg()
  let (tx, sbond) = build_tx(RedeemPartially(10))
  and {
    redeem_bond.spending_with_fee(
      cfg,
      tx
        |> fn(t: Transaction) {
             expect [lender_out, fee_out, bond_out] = t.outputs
             Transaction {
               ..t,
               mint: t.mint
                 |> value.from_minted_value
                 |> value.add(nft_pid, bond_token_name, -1)
                 |> value.to_minted_value,
               outputs: [
                 lender_out,
                 fee_out,
                 bond_out
                   |> add_asset(nft_pid, bond_token_name, -1),
               ],
             }
           },
      sbond,
      sbond.address,
      get_bond_datum(sbond),
      nft_pid,
    ),
    bond_nft.burning_bond_redeem(tx, nft_pid, bond_pid),
    bond_token.burning_bond_redeem(tx, bond_pid, nft_pid),
    True,
  } |> not
}

// redeem partially
test fail_when_setting_lower_epo_rewards() fail {
  let cfg = build_cfg()
  let (tx, sbond) = build_tx(RedeemPartially(1))
  and {
    redeem_bond.spending_with_fee(
      cfg,
      tx
        |> fn(t: Transaction) {
             expect [lender_out, fee_out, bond_out] = t.outputs
             Transaction {
               ..t,
               outputs: [
                 lender_out,
                 fee_out,
                 bond_out
                   |> set_bond_datum(
                        fn(datum) {
                          BondDatum {
                            ..datum,
                            epo_rewards: datum.epo_rewards
                              |> value.add(
                                   value.ada_policy_id,
                                   value.ada_asset_name,
                                   -1,
                                 ),
                          }
                        },
                      ),
               ],
             }
           },
      sbond,
      sbond.address,
      get_bond_datum(sbond),
      nft_pid,
    ),
    bond_token.burning_bond_redeem(tx, bond_pid, nft_pid),
    True,
  } |> not
}

test fail_when_setting_higher_epo_rewards() fail {
  let cfg = build_cfg()
  let (tx, sbond) = build_tx(RedeemPartially(1))
  and {
    redeem_bond.spending_with_fee(
      cfg,
      tx
        |> fn(t: Transaction) {
             expect [lender_out, fee_out, bond_out] = t.outputs
             Transaction {
               ..t,
               outputs: [
                 lender_out,
                 fee_out,
                 bond_out
                   |> set_bond_datum(
                        fn(datum) {
                          BondDatum {
                            ..datum,
                            epo_rewards: datum.epo_rewards
                              |> value.add(
                                   value.ada_policy_id,
                                   value.ada_asset_name,
                                   1,
                                 ),
                          }
                        },
                      ),
               ],
             }
           },
      sbond,
      sbond.address,
      get_bond_datum(sbond),
      nft_pid,
    ),
    bond_token.burning_bond_redeem(tx, bond_pid, nft_pid),
    True,
  } |> not
}

test fail_when_attempting_unbounded_value_attack_on_epo_rewards() fail {
  let cfg = build_cfg()
  let (tx, sbond) = build_tx(RedeemPartially(1))
  and {
    redeem_bond.spending_with_fee(
      cfg,
      tx
        |> fn(t: Transaction) {
             expect [lender_out, fee_out, bond_out] = t.outputs
             Transaction {
               ..t,
               outputs: [
                 lender_out,
                 fee_out,
                 bond_out
                   |> set_bond_datum(
                        fn(datum) {
                          BondDatum {
                            ..datum,
                            epo_rewards: datum.epo_rewards
                              |> value.add(
                                   "other_policy_id",
                                   "other_asset_name",
                                   1,
                                 ),
                          }
                        },
                      ),
               ],
             }
           },
      sbond,
      sbond.address,
      get_bond_datum(sbond),
      nft_pid,
    ),
    bond_token.burning_bond_redeem(tx, bond_pid, nft_pid),
    True,
  } |> not
}

test fail_when_setting_lower_duration() fail {
  let cfg = build_cfg()
  let (tx, sbond) = build_tx(RedeemPartially(1))
  and {
    redeem_bond.spending_with_fee(
      cfg,
      tx
        |> fn(t: Transaction) {
             expect [lender_out, fee_out, bond_out] = t.outputs
             Transaction {
               ..t,
               outputs: [
                 lender_out,
                 fee_out,
                 bond_out
                   |> set_bond_datum(
                        fn(datum) {
                          BondDatum { ..datum, duration: datum.duration - 1 }
                        },
                      ),
               ],
             }
           },
      sbond,
      sbond.address,
      get_bond_datum(sbond),
      nft_pid,
    ),
    bond_token.burning_bond_redeem(tx, bond_pid, nft_pid),
    True,
  } |> not
}

test fail_when_setting_higher_duration() fail {
  let cfg = build_cfg()
  let (tx, sbond) = build_tx(RedeemPartially(1))
  and {
    redeem_bond.spending_with_fee(
      cfg,
      tx
        |> fn(t: Transaction) {
             expect [lender_out, fee_out, bond_out] = t.outputs
             Transaction {
               ..t,
               outputs: [
                 lender_out,
                 fee_out,
                 bond_out
                   |> set_bond_datum(
                        fn(datum) {
                          BondDatum { ..datum, duration: datum.duration + 1 }
                        },
                      ),
               ],
             }
           },
      sbond,
      sbond.address,
      get_bond_datum(sbond),
      nft_pid,
    ),
    bond_token.burning_bond_redeem(tx, bond_pid, nft_pid),
    True,
  } |> not
}

test fail_when_setting_incorrect_bond_symbol() fail {
  let cfg = build_cfg()
  let (tx, sbond) = build_tx(RedeemPartially(1))
  and {
    redeem_bond.spending_with_fee(
      cfg,
      tx
        |> fn(t: Transaction) {
             expect [lender_out, fee_out, bond_out] = t.outputs
             Transaction {
               ..t,
               outputs: [
                 lender_out,
                 fee_out,
                 bond_out
                   |> set_bond_datum(
                        fn(datum) {
                          BondDatum { ..datum, bond_symbol: "other_symbol" }
                        },
                      ),
               ],
             }
           },
      sbond,
      sbond.address,
      get_bond_datum(sbond),
      nft_pid,
    ),
    bond_token.burning_bond_redeem(tx, bond_pid, nft_pid),
    True,
  } |> not
}

test fail_when_setting_incorrect_token_name() fail {
  let cfg = build_cfg()
  let (tx, sbond) = build_tx(RedeemPartially(1))
  and {
    redeem_bond.spending_with_fee(
      cfg,
      tx
        |> fn(t: Transaction) {
             expect [lender_out, fee_out, bond_out] = t.outputs
             Transaction {
               ..t,
               outputs: [
                 lender_out,
                 fee_out,
                 bond_out
                   |> set_bond_datum(
                        fn(datum) {
                          BondDatum { ..datum, token_name: "other_token" }
                        },
                      ),
               ],
             }
           },
      sbond,
      sbond.address,
      get_bond_datum(sbond),
      nft_pid,
    ),
    bond_token.burning_bond_redeem(tx, bond_pid, nft_pid),
    True,
  } |> not
}

test fail_when_setting_lower_bond_amount() fail {
  let cfg = build_cfg()
  let (tx, sbond) = build_tx(RedeemPartially(10))
  and {
    redeem_bond.spending_with_fee(
      cfg,
      tx
        |> fn(t: Transaction) {
             expect [lender_out, fee_out, bond_out] = t.outputs
             Transaction {
               ..t,
               outputs: [
                 lender_out,
                 fee_out,
                 bond_out
                   |> set_bond_datum(
                        fn(datum) {
                          BondDatum {
                            ..datum,
                            bond_amount: datum.bond_amount - 1,
                          }
                        },
                      ),
               ],
             }
           },
      sbond,
      sbond.address,
      get_bond_datum(sbond),
      nft_pid,
    ),
    bond_token.burning_bond_redeem(tx, bond_pid, nft_pid),
    True,
  } |> not
}

test fail_when_setting_higher_bond_amount() fail {
  let cfg = build_cfg()
  let (tx, sbond) = build_tx(RedeemPartially(10))
  and {
    redeem_bond.spending_with_fee(
      cfg,
      tx
        |> fn(t: Transaction) {
             expect [lender_out, fee_out, bond_out] = t.outputs
             Transaction {
               ..t,
               outputs: [
                 lender_out,
                 fee_out,
                 bond_out
                   |> set_bond_datum(
                        fn(datum) {
                          BondDatum {
                            ..datum,
                            bond_amount: datum.bond_amount + 1,
                          }
                        },
                      ),
               ],
             }
           },
      sbond,
      sbond.address,
      get_bond_datum(sbond),
      nft_pid,
    ),
    bond_token.burning_bond_redeem(tx, bond_pid, nft_pid),
    True,
  } |> not
}

test fail_when_setting_lower_buffer() fail {
  let cfg = build_cfg()
  let (tx, sbond) = build_tx(RedeemPartially(10))
  and {
    redeem_bond.spending_with_fee(
      cfg,
      tx
        |> fn(t: Transaction) {
             expect [lender_out, fee_out, bond_out] = t.outputs
             Transaction {
               ..t,
               outputs: [
                 lender_out,
                 fee_out,
                 bond_out
                   |> set_bond_datum(
                        fn(datum) {
                          BondDatum { ..datum, buffer: datum.buffer - 1 }
                        },
                      ),
               ],
             }
           },
      sbond,
      sbond.address,
      get_bond_datum(sbond),
      nft_pid,
    ),
    bond_token.burning_bond_redeem(tx, bond_pid, nft_pid),
    True,
  } |> not
}

test fail_when_setting_higher_buffer() fail {
  let cfg = build_cfg()
  let (tx, sbond) = build_tx(RedeemPartially(10))
  and {
    redeem_bond.spending_with_fee(
      cfg,
      tx
        |> fn(t: Transaction) {
             expect [lender_out, fee_out, bond_out] = t.outputs
             Transaction {
               ..t,
               outputs: [
                 lender_out,
                 fee_out,
                 bond_out
                   |> set_bond_datum(
                        fn(datum) {
                          BondDatum { ..datum, buffer: datum.buffer + 1 }
                        },
                      ),
               ],
             }
           },
      sbond,
      sbond.address,
      get_bond_datum(sbond),
      nft_pid,
    ),
    bond_token.burning_bond_redeem(tx, bond_pid, nft_pid),
    True,
  } |> not
}

test fail_when_setting_lower_fee() fail {
  let cfg = build_cfg()
  let (tx, sbond) = build_tx(RedeemPartially(10))
  and {
    redeem_bond.spending_with_fee(
      cfg,
      tx
        |> fn(t: Transaction) {
             expect [lender_out, fee_out, bond_out] = t.outputs
             Transaction {
               ..t,
               outputs: [
                 lender_out,
                 fee_out,
                 bond_out
                   |> set_bond_datum(
                        fn(datum) { BondDatum { ..datum, fee: datum.fee - 1 } },
                      ),
               ],
             }
           },
      sbond,
      sbond.address,
      get_bond_datum(sbond),
      nft_pid,
    ),
    bond_token.burning_bond_redeem(tx, bond_pid, nft_pid),
    True,
  } |> not
}

test fail_when_setting_higher_fee() fail {
  let cfg = build_cfg()
  let (tx, sbond) = build_tx(RedeemPartially(10))
  and {
    redeem_bond.spending_with_fee(
      cfg,
      tx
        |> fn(t: Transaction) {
             expect [lender_out, fee_out, bond_out] = t.outputs
             Transaction {
               ..t,
               outputs: [
                 lender_out,
                 fee_out,
                 bond_out
                   |> set_bond_datum(
                        fn(datum) { BondDatum { ..datum, fee: datum.fee + 1 } },
                      ),
               ],
             }
           },
      sbond,
      sbond.address,
      get_bond_datum(sbond),
      nft_pid,
    ),
    bond_token.burning_bond_redeem(tx, bond_pid, nft_pid),
    True,
  } |> not
}

test fail_when_setting_incorrect_borrower() fail {
  let cfg = build_cfg()
  let (tx, sbond) = build_tx(RedeemPartially(10))
  and {
    redeem_bond.spending_with_fee(
      cfg,
      tx
        |> fn(t: Transaction) {
             expect [lender_out, fee_out, bond_out] = t.outputs
             Transaction {
               ..t,
               outputs: [
                 lender_out,
                 fee_out,
                 bond_out
                   |> set_bond_datum(
                        fn(datum) {
                          BondDatum { ..datum, borrower: "other_borrower" }
                        },
                      ),
               ],
             }
           },
      sbond,
      sbond.address,
      get_bond_datum(sbond),
      nft_pid,
    ),
    bond_token.burning_bond_redeem(tx, bond_pid, nft_pid),
    True,
  } |> not
}

test fail_when_setting_lower_start() fail {
  let cfg = build_cfg()
  let (tx, sbond) = build_tx(RedeemPartially(10))
  and {
    redeem_bond.spending_with_fee(
      cfg,
      tx
        |> fn(t: Transaction) {
             expect [lender_out, fee_out, bond_out] = t.outputs
             Transaction {
               ..t,
               outputs: [
                 lender_out,
                 fee_out,
                 bond_out
                   |> set_bond_datum(
                        fn(datum) {
                          BondDatum { ..datum, start: datum.start - 1 }
                        },
                      ),
               ],
             }
           },
      sbond,
      sbond.address,
      get_bond_datum(sbond),
      nft_pid,
    ),
    bond_token.burning_bond_redeem(tx, bond_pid, nft_pid),
    True,
  } |> not
}

test fail_when_setting_higher_start() fail {
  let cfg = build_cfg()
  let (tx, sbond) = build_tx(RedeemPartially(10))
  and {
    redeem_bond.spending_with_fee(
      cfg,
      tx
        |> fn(t: Transaction) {
             expect [lender_out, fee_out, bond_out] = t.outputs
             Transaction {
               ..t,
               outputs: [
                 lender_out,
                 fee_out,
                 bond_out
                   |> set_bond_datum(
                        fn(datum) {
                          BondDatum { ..datum, start: datum.start + 1 }
                        },
                      ),
               ],
             }
           },
      sbond,
      sbond.address,
      get_bond_datum(sbond),
      nft_pid,
    ),
    bond_token.burning_bond_redeem(tx, bond_pid, nft_pid),
    True,
  } |> not
}

test fail_when_bond_out_hasnt_nft() fail {
  let cfg = build_cfg()
  let (tx, sbond) = build_tx(RedeemPartially(10))
  and {
    redeem_bond.spending_with_fee(
      cfg,
      tx
        |> fn(t: Transaction) {
             expect [lender_out, fee_out, bond_out] = t.outputs
             Transaction {
               ..t,
               outputs: [
                 lender_out,
                 fee_out,
                 bond_out
                   |> add_asset(nft_pid, bond_token_name, -1),
               ],
             }
           },
      sbond,
      sbond.address,
      get_bond_datum(sbond),
      nft_pid,
    ),
    bond_token.burning_bond_redeem(tx, bond_pid, nft_pid),
    True,
  } |> not
}

test fail_when_bond_out_has_incorrect_nft_policy() fail {
  let cfg = build_cfg()
  let (tx, sbond) = build_tx(RedeemPartially(10))
  and {
    redeem_bond.spending_with_fee(
      cfg,
      tx
        |> fn(t: Transaction) {
             expect [lender_out, fee_out, bond_out] = t.outputs
             Transaction {
               ..t,
               outputs: [
                 lender_out,
                 fee_out,
                 bond_out
                   |> add_asset(nft_pid, bond_token_name, -1)
                   |> add_asset("other_nft_pid", bond_token_name, 1),
               ],
             }
           },
      sbond,
      sbond.address,
      get_bond_datum(sbond),
      nft_pid,
    ),
    bond_token.burning_bond_redeem(tx, bond_pid, nft_pid),
    True,
  } |> not
}

test fail_when_removing_bond_when_claiming_partially() fail {
  let cfg = build_cfg()
  let (tx, sbond) = build_tx(RedeemPartially(1))
  and {
    redeem_bond.spending_with_fee(
      cfg,
      tx
        |> fn(t: Transaction) {
             expect [lender_out, fee_out, ..] = t.outputs
             Transaction { ..t, outputs: [lender_out, fee_out] }
           },
      sbond,
      sbond.address,
      get_bond_datum(sbond),
      nft_pid,
    ),
    bond_token.burning_bond_redeem(tx, bond_pid, nft_pid),
    True,
  } |> not
}

// fee
test fail_when_paying_lower_fee() fail {
  let cfg = build_cfg()
  let (tx, sbond) = build_tx(RedeemAll)
  and {
    redeem_bond.spending_with_fee(
      cfg,
      tx
        |> fn(t: Transaction) {
             expect [lender_out, fee_out] = t.outputs
             Transaction {
               ..t,
               outputs: [
                 lender_out
                   |> add_asset(value.ada_policy_id, value.ada_asset_name, 1),
                 fee_out
                   |> add_asset(value.ada_policy_id, value.ada_asset_name, -1),
               ],
             }
           },
      sbond,
      sbond.address,
      get_bond_datum(sbond),
      nft_pid,
    ),
    bond_nft.burning_bond_redeem(tx, nft_pid, bond_pid),
    bond_token.burning_bond_redeem(tx, bond_pid, nft_pid),
  } |> not
}

test fail_when_doesnt_pay_fee() fail {
  let cfg = build_cfg()
  let (tx, sbond) = build_tx(RedeemAll)
  and {
    redeem_bond.spending_with_fee(
      cfg,
      tx
        |> fn(t: Transaction) {
             expect [lender_out, fee_out] = t.outputs
             Transaction {
               ..t,
               outputs: [
                 lender_out
                   |> add_asset(
                        value.ada_policy_id,
                        value.ada_asset_name,
                        value.lovelace_of(fee_out.value),
                      ),
               ],
             }
           },
      sbond,
      sbond.address,
      get_bond_datum(sbond),
      nft_pid,
    ),
    bond_nft.burning_bond_redeem(tx, nft_pid, bond_pid),
    bond_token.burning_bond_redeem(tx, bond_pid, nft_pid),
  } |> not
}

test fail_when_doesnt_pay_fee_for_protocol() fail {
  let cfg = build_cfg()
  let (tx, sbond) = build_tx(RedeemAll)
  and {
    redeem_bond.spending_with_fee(
      cfg,
      tx
        |> fn(t: Transaction) {
             expect [lender_out, fee_out] = t.outputs
             Transaction {
               ..t,
               outputs: [
                 lender_out,
                 Output {
                   ..fee_out,
                   address: credential.from_verification_key(
                     "lender_public_key",
                   ),
                 },
               ],
             }
           },
      sbond,
      sbond.address,
      get_bond_datum(sbond),
      nft_pid,
    ),
    bond_nft.burning_bond_redeem(tx, nft_pid, bond_pid),
    bond_token.burning_bond_redeem(tx, bond_pid, nft_pid),
  } |> not
}

// others
test fail_when_batching_bonds() fail {
  let cfg = build_cfg()
  let (tx, sbond) = build_tx(RedeemAll)
  and {
    redeem_bond.spending_with_fee(
      cfg,
      tx
        |> fn(t: Transaction) {
             expect [lender_in, bond_in] = t.inputs
             expect [lender_out, fee_out] = t.outputs
             let bond_2_name = "other_bond_name"
             let bond_2_datum =
               BondDatum {
                 epo_rewards: value.from_lovelace(epo_rewards),
                 bond_symbol: bond_pid,
                 token_name: bond_2_name,
                 bond_amount: 120,
                 fee: 200,
                 borrower: "borrower_1",
                 start: 400,
                 buffer: cfg.platform.min_buffer,
                 duration: cfg.platform.min_duration,
               }
             let sbond2 =
               Input {
                 output_reference: OutputReference(
                   TransactionId("tx_sbond_2"),
                   1,
                 ),
                 output: build_bond_output(bond_2_datum),
               }
             let lender_2_in =
               Input {
                 output_reference: OutputReference(
                   TransactionId("lender_tx_2"),
                   0,
                 ),
                 output: Output {
                   ..lender_in.output,
                   value: value.from_lovelace(12 * ada)
                     |> value.add(bond_pid, bond_2_name, bond_2_datum.bond_amount),
                 },
               }
             let bond_2_outs =
               resolve_sbond(sbond2.output, lender_2_in, RedeemAll)
             Transaction {
               ..t,
               inputs: [lender_in, lender_2_in, bond_in],
               outputs: [lender_out, fee_out, ..bond_2_outs],
             }
           },
      sbond,
      sbond.address,
      get_bond_datum(sbond),
      nft_pid,
    ),
    bond_nft.burning_bond_redeem(tx, nft_pid, bond_pid),
    bond_token.burning_bond_redeem(tx, bond_pid, nft_pid),
  } |> not
}

test succ_when_lender_redeems_early_due_to_interest_buffer_violation() {
  let cfg = build_cfg()
  let (tx, sbond) = build_tx(RedeemAll)
  and {
    redeem_bond.spending_with_fee(
      cfg,
      tx
        |> fn(t) {
             // duration is 100 epochs
             // paid interest for 60 epochs
             // buffer is 6 epochs
             // -> lender shouldn't redeem before epoch 54
             Transaction {
               ..t,
               validity_range: t.validity_range
                 |> shift_interval(-46 * cfg.epoch.epoch_length),
             }
           },
      sbond,
      sbond.address,
      get_bond_datum(sbond),
      nft_pid,
    ),
    bond_nft.burning_bond_redeem(tx, nft_pid, bond_pid),
    bond_token.burning_bond_redeem(tx, bond_pid, nft_pid),
  }
}

test succ_when_lender_redeems_after_maturity() {
  let cfg = build_cfg()
  let (tx, sbond) = build_tx(RedeemAll)
  and {
    redeem_bond.spending_with_fee(
      cfg,
      tx
        |> fn(t) {
             Transaction {
               ..t,
               validity_range: t.validity_range
                 |> shift_interval(10 * cfg.epoch.epoch_length),
             }
           },
      sbond,
      sbond.address,
      get_bond_datum(sbond),
      nft_pid,
    ),
    bond_nft.burning_bond_redeem(tx, nft_pid, bond_pid),
    bond_token.burning_bond_redeem(tx, bond_pid, nft_pid),
  }
}

test fail_when_lender_redeems_early_but_borrower_paid_for_buffer() {
  let cfg = build_cfg()
  let (tx, sbond) = build_tx(RedeemAll)
  and {
    redeem_bond.spending_with_fee(
      cfg,
      tx
        |> fn(t) {
             // duration is 100 epoch
             // paid interest for 60 epochs
             // buffer is 6 epochs
             // -> lender shouldn't redeem before epoch 54
             Transaction {
               ..t,
               validity_range: t.validity_range
                 |> shift_interval(-47 * cfg.epoch.epoch_length),
             }
           },
      sbond,
      sbond.address,
      get_bond_datum(sbond),
      nft_pid,
    ),
    bond_nft.burning_bond_redeem(tx, nft_pid, bond_pid),
    bond_token.burning_bond_redeem(tx, bond_pid, nft_pid),
  } |> not
}

test fail_when_changing_bond_stake_key() fail {
  let cfg = build_cfg()
  let (tx, sbond) = build_tx(RedeemPartially(1))
  and {
    redeem_bond.spending_with_fee(
      cfg,
      tx
        |> fn(t: Transaction) {
             expect [lender_out, fee_out, bond_out] = t.outputs
             Transaction {
               ..t,
               outputs: [
                 lender_out,
                 fee_out,
                 bond_out |> set_stake_credential(Some("lender_stake_key")),
               ],
             }
           },
      sbond,
      sbond.address,
      get_bond_datum(sbond),
      nft_pid,
    ),
    bond_nft.burning_bond_redeem(tx, nft_pid, bond_pid),
    bond_token.burning_bond_redeem(tx, bond_pid, nft_pid),
  } |> not
}

test fail_when_removing_bond_stake_key() fail {
  let cfg = build_cfg()
  let (tx, sbond) = build_tx(RedeemPartially(1))
  and {
    redeem_bond.spending_with_fee(
      cfg,
      tx
        |> fn(t: Transaction) {
             expect [lender_out, fee_out, bond_out] = t.outputs
             Transaction {
               ..t,
               outputs: [
                 lender_out,
                 fee_out,
                 bond_out |> set_stake_credential(None),
               ],
             }
           },
      sbond,
      sbond.address,
      get_bond_datum(sbond),
      nft_pid,
    ),
    bond_nft.burning_bond_redeem(tx, nft_pid, bond_pid),
    bond_token.burning_bond_redeem(tx, bond_pid, nft_pid),
  } |> not
}

test succ_on_large_inputs_and_outputs() {
  let cfg = build_cfg()
  let (tx, sbond) = build_tx(RedeemPartially(1))
  and {
    redeem_bond.spending_with_fee(
      cfg,
      tx
        |> fn(t: Transaction) {
             let additional_inputs =
               list.repeat(0, 50)
                 |> list.indexed_map(
                      fn(idx, _) {
                        Input {
                          output_reference: OutputReference(
                            TransactionId("lender_tx_11"),
                            idx,
                          ),
                          output: build_lender_output(100 * ada, 0),
                        }
                      },
                    )
             let additional_outputs =
               additional_inputs |> list.map(fn(i) { i.output })
             Transaction {
               ..t,
               inputs: t.inputs
                 |> list.concat(additional_inputs),
               outputs: t.outputs |> list.concat(additional_outputs),
             }
           },
      sbond,
      sbond.address,
      get_bond_datum(sbond),
      nft_pid,
    ),
    bond_token.burning_bond_redeem(tx, bond_pid, nft_pid),
  }
}
