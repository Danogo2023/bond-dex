use aiken/bytearray
use aiken/cbor
use aiken/dict.{Dict}
use aiken/interval
use aiken/list
use aiken/string
use aiken/transaction.{
  InlineDatum, Input, Mint, NoDatum, Output, OutputReference, Redeemer,
  ScriptContext, ScriptPurpose, Spend, Transaction, TransactionId,
}
use aiken/transaction/credential
use aiken/transaction/value.{PolicyId, Value}
use bond_issue/types.{BondDatum, BondIssueConfig, PlatformConfig, RequestDatum}
use borrow_position/bond_nft
use borrow_position/bond_token
use borrow_request/bond_create
use common/hash_out_refs.{hash_out_ref_salt}
use common/time.{
  BasisPoints, get_current_epoch, get_epoch_config_mainnet,
  get_slot_config_network_mainnet,
}
use common/types.{ScriptKeyHash} as common_types
use issue_bond/types.{BondCreate, BondRedeem} as issue_bond_types

// ===============Params==============
const ada = 1_000_000

const req_skh = "borrow-req-skh"

const req_pid = "borrow-request-policy-id"

const bond_skh = "bond-skh"

const nft_pid = "bond-nft-policy-id"

const lender_st = "lender-stake-credential"

const lender_pk = "lender-payment-credential"

const borrower_st = "borrower-stake-credential"

const bond_pid = "bond-policy-id"

const borrower = "hashed-asset-name"

// ===============Builders==============
fn build_cfg() {
  BondIssueConfig {
    slot: get_slot_config_network_mainnet(),
    epoch: get_epoch_config_mainnet(),
    basis: BasisPoints { base: 10_000, min: 1, max: 9_999 },
    platform: PlatformConfig {
      bond_face_value: 100 * ada,
      fee: 500,
      fee_addr: credential.from_verification_key("fee_addr"),
      tx_ttl: 30,
      min_buffer: 6,
      prepaid_plus: 3,
      min_requested: 100,
      min_apr: 200,
      min_duration: 6,
      garbage_addr: credential.from_verification_key("garbage_addr"),
    },
  }
}

fn get_tx_validity_range() {
  interval.between(1702616373000, 1702616373000 + 30_000)
}

fn get_datum(self: Output) -> Data {
  expect InlineDatum(datum) = self.datum
  datum
}

fn get_lovelace(self: Output) {
  self.value |> value.quantity_of(value.ada_policy_id, value.ada_asset_name)
}

fn add_lovelace(self: Output, amt: Int) {
  Output {
    ..self,
    value: self.value
      |> value.add(value.ada_policy_id, value.ada_asset_name, amt),
  }
}

fn get_request_datum(self: Output) {
  expect request_datum: RequestDatum = get_datum(self)
  request_datum
}

fn get_bond_datum(self: Output) {
  expect request_datum: BondDatum = get_datum(self)
  request_datum
}

fn add_bond_start(self: Output, amt: Int) {
  let datum = get_bond_datum(self)
  Output {
    ..self,
    datum: InlineDatum(BondDatum { ..datum, start: datum.start + amt }),
  }
}

fn set_bond_borrower(self: Output, brr: ByteArray) {
  let datum = get_bond_datum(self)
  Output { ..self, datum: InlineDatum(BondDatum { ..datum, borrower: brr }) }
}

fn add_bond_fee(self: Output, amt: Int) {
  let datum = get_bond_datum(self)
  Output {
    ..self,
    datum: InlineDatum(BondDatum { ..datum, fee: datum.fee + amt }),
  }
}

fn add_bond_buffer(self: Output, amt: Int) {
  let datum = get_bond_datum(self)
  Output {
    ..self,
    datum: InlineDatum(BondDatum { ..datum, buffer: datum.buffer + amt }),
  }
}

fn add_bond_amount(self: Output, amt: Int) {
  let datum = get_bond_datum(self)
  Output {
    ..self,
    datum: InlineDatum(
      BondDatum { ..datum, bond_amount: datum.bond_amount + amt },
    ),
  }
}

fn add_bond_duration(self: Output, amt: Int) {
  let datum = get_bond_datum(self)
  Output {
    ..self,
    datum: InlineDatum(BondDatum { ..datum, duration: datum.duration + amt }),
  }
}

fn set_bond_symbol(self: Output, symbol: PolicyId) {
  let datum = get_bond_datum(self)
  Output {
    ..self,
    datum: InlineDatum(BondDatum { ..datum, bond_symbol: symbol }),
  }
}

fn value_without_token(self: Value, pid: PolicyId, asset_name: ByteArray) {
  let current = self |> value.quantity_of(pid, asset_name)
  self
    |> value.add(pid, asset_name, 0 - current)
}

fn build_lender_input(index: Int) {
  Input {
    output_reference: OutputReference(TransactionId("lender_tx"), index),
    output: Output {
      address: credential.from_verification_key(lender_pk)
        |> credential.with_delegation_key(lender_st),
      value: value.from_lovelace(10_000 * ada),
      datum: NoDatum,
      reference_script: None,
    },
  }
}

fn get_min_prepaid(cfg: BondIssueConfig, buffer: Int) {
  cfg.platform.prepaid_plus + buffer
}

fn get_epo_rewards(cfg: BondIssueConfig, bond_amount: Int, apr: Int) {
  bond_amount * cfg.platform.bond_face_value * apr / cfg.basis.base / cfg.epoch.year_to_epoch
}

fn script_purpose_compare(a: ScriptPurpose, b: ScriptPurpose) {
  bytearray.compare(
    cbor.diagnostic(a) |> string.to_bytearray,
    cbor.diagnostic(b) |> string.to_bytearray,
  )
}

fn build_request_input(
  issued: Int,
  borrower: ByteArray,
  requested: Int,
  apr: Int,
) {
  let cfg: BondIssueConfig = build_cfg()
  let buffer = 10
  let prepaid = get_min_prepaid(cfg, buffer)
  let duration = prepaid * 10
  let fee = 500
  let epo_rewards = get_epo_rewards(cfg, requested - issued, apr)
  Input {
    output_reference: OutputReference(TransactionId("borrower_tx"), 0),
    output: Output {
      address: credential.from_script(req_skh)
        |> credential.with_delegation_key(borrower_st),
      value: value.from_lovelace(100 * ada)
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
    },
  }
}

fn fulfill_borrow_request(request: Input, lend_amt: LendAmount) {
  let cfg = build_cfg()
  let RequestDatum {
    duration,
    borrower,
    requested,
    issued,
    buffer,
    fee,
    apr,
    prepaid,
    ..
  } = get_request_datum(request.output)
  let token_name = hash_out_ref_salt(request.output_reference, borrower)
  let bond_amount = resolve_lend_amount(lend_amt, requested, issued)
  let current_epoch = get_current_epoch(get_tx_validity_range(), cfg.epoch)
  let start = current_epoch - cfg.epoch.epoch_boundary_as_epoch
  let epo_rewards_ada = get_epo_rewards(cfg, bond_amount, apr)
  let principal = bond_amount * cfg.platform.bond_face_value
  let required_premium = epo_rewards_ada * prepaid
  let locked_value =
    required_premium + principal
      |> value.from_lovelace
      |> value.add(nft_pid, token_name, 1)
  let epo_rewards_assets =
    principal * apr / cfg.basis.base / cfg.epoch.year_to_epoch
      |> value.from_lovelace
      |> value.add(nft_pid, token_name, 1)
  let bond_out =
    Output {
      address: credential.from_script(bond_skh)
        |> credential.with_delegation_key(borrower_st),
      value: locked_value,
      datum: InlineDatum(
        BondDatum {
          epo_rewards: epo_rewards_assets,
          duration,
          bond_symbol: bond_pid,
          token_name,
          buffer,
          fee,
          borrower,
          start,
          bond_amount,
        },
      ),
      reference_script: None,
    }
  if bond_amount + issued == requested {
    (bond_out, None)
  } else {
    (
      bond_out,
      Some(
        build_request_input(
          issued: bond_amount + issued,
          borrower: borrower,
          requested: requested,
          apr: apr,
        ).output,
      ),
    )
  }
}

fn calc_fee(bond: BondDatum, request: RequestDatum) {
  let cfg = build_cfg()
  value.lovelace_of(bond.epo_rewards) * request.prepaid * request.fee / cfg.basis.base
}

fn build_fee_output(fee: Int) {
  let cfg = build_cfg()
  Output {
    address: cfg.platform.fee_addr,
    value: value.from_lovelace(fee),
    datum: NoDatum,
    reference_script: None,
  }
}

type MintingRedeemer {
  out_ref: OutputReference,
  req_skh: ScriptKeyHash,
  pid: PolicyId,
}

fn with_expected_redeemers(
  self: Dict<ScriptPurpose, Redeemer>,
  spending_request: Input,
) {
  self
    |> dict.insert(
         Spend(spending_request.output_reference),
         BondCreate {
           out_ref: spending_request.output_reference,
           req_skh,
           bond_skh,
           pid: bond_pid,
         },
         script_purpose_compare,
       )
    |> dict.insert(
         Mint(nft_pid),
         MintingRedeemer {
           out_ref: spending_request.output_reference,
           req_skh,
           pid: nft_pid,
         },
         script_purpose_compare,
       )
    |> dict.insert(
         Mint(bond_pid),
         MintingRedeemer {
           out_ref: spending_request.output_reference,
           req_skh,
           pid: bond_pid,
         },
         script_purpose_compare,
       )
}

type FulfillmentState {
  FulfilledZero
  FulfilledPartially(Input)
}

type LendAmount {
  Entire
  Partial(Int)
}

fn resolve_spending_request(
  state: FulfillmentState,
  brr: ByteArray,
  requested: Int,
  apr: Int,
) {
  when state is {
    FulfilledZero ->
      build_request_input(
        issued: 0,
        borrower: brr,
        requested: requested,
        apr: apr,
      )
    FulfilledPartially(r) -> r
  }
}

fn resolve_lend_amount(amt: LendAmount, requested: Int, issued: Int) {
  when amt is {
    Entire -> requested - issued
    Partial(v) -> v
  }
}

fn build_tx(request: FulfillmentState, lend_amount: LendAmount) {
  let cfg = build_cfg()
  let t = transaction.placeholder()
  let lender_in = build_lender_input(index: 2)
  let request_in =
    resolve_spending_request(
      request,
      borrower,
      cfg.platform.min_requested,
      cfg.platform.min_apr,
    )
  let request_datum = get_request_datum(request_in.output)
  let (bond_out, remain_request) =
    fulfill_borrow_request(request_in, lend_amount)
  let bond_datum = get_bond_datum(bond_out)
  let fee_out = build_fee_output(calc_fee(bond_datum, request_datum))
  let lender_out = add_lovelace(lender_in.output, -get_lovelace(fee_out))
  let mint =
    value.zero()
      |> value.add(nft_pid, bond_datum.token_name, 1)
      |> value.add(bond_pid, bond_datum.token_name, bond_datum.bond_amount)
      |> value.to_minted_value
  (
    request_in,
    ScriptContext {
      purpose: Spend(request_in.output_reference),
      transaction: Transaction {
        ..t,
        redeemers: t.redeemers |> with_expected_redeemers(request_in),
        validity_range: get_tx_validity_range(),
        inputs: [lender_in, request_in],
        outputs: [lender_out, bond_out, fee_out]
          |> list.concat(
               when remain_request is {
                 None ->
                   []
                 Some(r) ->
                   [r]
               },
             ),
        mint: mint,
      },
    },
  )
}

fn build_multi_requests_tx(
  requests: List<(FulfillmentState, LendAmount, Int, Int)>,
) {
  let t = transaction.placeholder()
  let lender_in = build_lender_input(index: 0)
  let lender_out = lender_in.output
  let (inputs, outputs, minted, redeemers) =
    requests
      |> list.indexed_foldr(
           ([], [], value.zero(), t.redeemers),
           fn(idx, req, acc) {
             let (fulfillment_state, lend_amt, requested, apr) = req
             let (inputs, outputs, minted, redeemers) = acc
             let request_in =
               Input {
                 ..resolve_spending_request(
                   fulfillment_state,
                   "borrower-"
                     |> bytearray.concat(
                          bytearray.from_string(idx |> string.from_int),
                        ),
                   requested,
                   apr,
                 ),
                 output_reference: OutputReference(
                   TransactionId("request_tx"),
                   idx,
                 ),
               }
             let (bond_out, remain_request) =
               fulfill_borrow_request(request_in, lend_amt)
             let bond_datum = get_bond_datum(bond_out)
             (
               inputs |> list.concat([request_in]),
               outputs
                 |> list.concat([bond_out])
                 |> list.concat(
                      when remain_request is {
                        None ->
                          []
                        Some(r) ->
                          [r]
                      },
                    ),
               minted
                 |> value.add(nft_pid, bond_datum.token_name, 1)
                 |> value.add(
                      bond_pid,
                      bond_datum.token_name,
                      bond_datum.bond_amount,
                    ),
               redeemers
                 |> with_expected_redeemers(request_in),
             )
           },
         )
  (
    inputs,
    Transaction {
      ..t,
      redeemers: redeemers,
      validity_range: get_tx_validity_range(),
      inputs: [lender_in, ..inputs],
      outputs: [lender_out, ..outputs],
      mint: minted |> value.to_minted_value,
    },
  )
}

// ===============Implementation==============

fn validate(args: (Input, ScriptContext)) {
  let cfg = build_cfg()
  let (spending_request, ctx) = args
  let tx = ctx.transaction
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
  and {
    bond_nft.minting(
      cfg,
      tx,
      req_skh,
      bond_skh,
      nft_pid,
      req_pid,
      spending_request.output_reference,
    ),
    bond_token.minting_without_fee(
      cfg,
      tx,
      req_skh,
      bond_skh,
      nft_pid,
      bond_pid,
      spending_request.output_reference,
    ),
    bond_create.spending(
      cfg,
      ctx,
      get_request_datum(spending_request.output),
      bond_skh,
      nft_pid,
      bond_pid,
      req_pid,
    ),
  }
}

test succ_when_fulfilling_single_borrow_request_entirely() {
  build_tx(request: FulfilledZero, lend_amount: Entire)
    |> validate
}

test succ_when_fulfilling_multiple_borrow_requests_entirely() {
  let cfg = build_cfg()
  let requested = 200
  let apr = cfg.platform.min_apr
  let (requests, tx) =
    build_multi_requests_tx(
      [
        (FulfilledZero, Entire, requested, apr),
        (FulfilledZero, Entire, requested + 10, apr + 10),
      ],
    )
  trace string.concat(
    @"request count: ",
    string.from_int(list.length(requests)),
  )
  list.all(
    requests,
    fn(req) {
      let ctx =
        ScriptContext { purpose: Spend(req.output_reference), transaction: tx }
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
      and {
        bond_nft.minting(
          cfg,
          ctx.transaction,
          req_skh,
          bond_skh,
          nft_pid,
          req_pid,
          req.output_reference,
        ),
        bond_token.minting_without_fee(
          cfg,
          ctx.transaction,
          req_skh,
          bond_skh,
          nft_pid,
          bond_pid,
          req.output_reference,
        ),
        bond_create.spending(
          cfg,
          ctx,
          get_request_datum(req.output),
          bond_skh,
          nft_pid,
          bond_pid,
          req_pid,
        ),
      }
    },
  )
}

test succ_when_fulfilling_multiple_borrow_requests_entirely_and_partially() {
  let cfg = build_cfg()
  let requested = 200
  let apr = cfg.platform.min_apr
  let (requests, tx) =
    build_multi_requests_tx(
      [
        // entirely the remain request
        (
          FulfilledPartially(build_request_input(100, "brw-01", requested, apr)),
          Entire,
          requested,
          apr,
        ),
        // partially the remain request
        (
          FulfilledPartially(build_request_input(50, "brw-02", requested, apr)),
          Entire,
          requested,
          apr,
        ),
        // entirely request
        (FulfilledZero, Entire, requested + 10, apr + 10),
        // partially request
        (FulfilledZero, Partial(10), requested + 10, apr + 10),
      ],
    )
  trace string.concat(
    @"request count: ",
    string.from_int(list.length(requests)),
  )
  list.all(
    requests,
    fn(req) {
      let ctx =
        ScriptContext { purpose: Spend(req.output_reference), transaction: tx }
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
      and {
        bond_nft.minting(
          cfg,
          ctx.transaction,
          req_skh,
          bond_skh,
          nft_pid,
          req_pid,
          req.output_reference,
        ),
        bond_token.minting_without_fee(
          cfg,
          ctx.transaction,
          req_skh,
          bond_skh,
          nft_pid,
          bond_pid,
          req.output_reference,
        ),
        bond_create.spending(
          cfg,
          ctx,
          get_request_datum(req.output),
          bond_skh,
          nft_pid,
          bond_pid,
          req_pid,
        ),
      }
    },
  )
}

test succ_when_fulfilling_5_borrow_requests() {
  let cfg = build_cfg()
  let requested = 200
  let apr = cfg.platform.min_apr
  let (requests, tx) =
    build_multi_requests_tx(
      [
        // entirely the remain request
        (
          FulfilledPartially(build_request_input(100, "brw-01", requested, apr)),
          Entire,
          requested,
          apr,
        ),
        // partially the remain request
        (
          FulfilledPartially(build_request_input(50, "brw-02", requested, apr)),
          Entire,
          requested,
          apr,
        ),
        // entirely request
        (FulfilledZero, Entire, requested + 10, apr + 11),
        (FulfilledZero, Entire, requested + 10, apr + 12),
        (FulfilledZero, Entire, requested + 10, apr + 13),
      ],
    )
  trace string.concat(
    @"request count: ",
    string.from_int(list.length(requests)),
  )
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
  list.all(
    requests,
    fn(req) {
      let ctx =
        ScriptContext { purpose: Spend(req.output_reference), transaction: tx }
      and {
        bond_nft.minting(
          cfg,
          ctx.transaction,
          req_skh,
          bond_skh,
          nft_pid,
          req_pid,
          req.output_reference,
        ),
        bond_token.minting_without_fee(
          cfg,
          ctx.transaction,
          req_skh,
          bond_skh,
          nft_pid,
          bond_pid,
          req.output_reference,
        ),
        bond_create.spending(
          cfg,
          ctx,
          get_request_datum(req.output),
          bond_skh,
          nft_pid,
          bond_pid,
          req_pid,
        ),
      }
    },
  )
}

test succ_when_fulfilling_10_borrow_requests() {
  let cfg = build_cfg()
  let requested = 200
  let apr = cfg.platform.min_apr
  let (requests, tx) =
    build_multi_requests_tx(
      [
        // entirely the remain request
        (
          FulfilledPartially(build_request_input(100, "brw-01", requested, apr)),
          Entire,
          requested,
          apr,
        ),
        // partially the remain request
        (
          FulfilledPartially(build_request_input(50, "brw-02", requested, apr)),
          Entire,
          requested,
          apr,
        ),
        // entirely request
        (FulfilledZero, Entire, requested + 10, apr + 11),
        (FulfilledZero, Entire, requested + 10, apr + 12),
        (FulfilledZero, Entire, requested + 10, apr + 13),
        (FulfilledZero, Entire, requested + 10, apr + 14),
        (FulfilledZero, Entire, requested + 10, apr + 15),
        (FulfilledZero, Entire, requested + 10, apr + 16),
        (FulfilledZero, Entire, requested + 10, apr + 17),
        (FulfilledZero, Entire, requested + 10, apr + 18),
      ],
    )
  trace string.concat(
    @"request count: ",
    string.from_int(list.length(requests)),
  )
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
  list.all(
    requests,
    fn(req) {
      let ctx =
        ScriptContext { purpose: Spend(req.output_reference), transaction: tx }
      and {
        bond_nft.minting(
          cfg,
          ctx.transaction,
          req_skh,
          bond_skh,
          nft_pid,
          req_pid,
          req.output_reference,
        ),
        bond_token.minting_without_fee(
          cfg,
          ctx.transaction,
          req_skh,
          bond_skh,
          nft_pid,
          bond_pid,
          req.output_reference,
        ),
        bond_create.spending(
          cfg,
          ctx,
          get_request_datum(req.output),
          bond_skh,
          nft_pid,
          bond_pid,
          req_pid,
        ),
      }
    },
  )
}

test succ_when_fulfilling_the_rest_borrow_request_entirely() {
  let cfg = build_cfg()
  let issued = 12
  build_tx(
    request: FulfilledPartially(
      build_request_input(
        issued,
        borrower: borrower,
        requested: cfg.platform.min_requested,
        apr: cfg.platform.min_apr,
      ),
    ),
    lend_amount: Entire,
  )
    |> validate
}

test succ_when_fulfilling_borrow_request_partially() {
  build_tx(request: FulfilledZero, lend_amount: Partial(8))
    |> validate
}

test succ_when_fulfilling_the_rest_borrow_request_partially() {
  let cfg = build_cfg()
  let issued = 12
  build_tx(
    request: FulfilledPartially(
      build_request_input(
        issued,
        borrower: borrower,
        requested: cfg.platform.min_requested,
        apr: cfg.platform.min_apr,
      ),
    ),
    lend_amount: Partial(100 - issued - 1),
  )
    |> validate
}

// ====================Minting====================

test fail_when_minting_exceeded_bond_nft_quantity() fail {
  build_tx(request: FulfilledZero, lend_amount: Entire)
    |> fn(args: (Input, ScriptContext)) {
         let (sreq, ctx) = args
         let tx = ctx.transaction
         expect [_, bond_out, ..] = tx.outputs
         (
           sreq,
           ScriptContext {
             ..ctx,
             transaction: Transaction {
               ..tx,
               mint: tx.mint
                 |> value.from_minted_value
                 |> value.add(bond_pid, get_bond_datum(bond_out).token_name, 1)
                 |> value.to_minted_value,
             },
           },
         )
       }
    |> validate
    |> not
}

test fail_when_burning_bond_nft() fail {
  build_tx(request: FulfilledZero, lend_amount: Entire)
    |> fn(args: (Input, ScriptContext)) {
         let (sreq, ctx) = args
         let tx = ctx.transaction
         expect [_, bond_out, ..] = tx.outputs
         (
           sreq,
           ScriptContext {
             ..ctx,
             transaction: Transaction {
               ..tx,
               mint: tx.mint
                 |> value.from_minted_value
                 |> value.add(nft_pid, get_bond_datum(bond_out).token_name, -2)
                 |> value.to_minted_value,
             },
           },
         )
       }
    |> validate
    |> not
}

test fail_when_minting_zero_bond_tokens() {
  build_tx(request: FulfilledZero, lend_amount: Entire)
    |> fn(args: (Input, ScriptContext)) {
         let (sreq, ctx) = args
         let tx = ctx.transaction
         expect [_, bond_out, ..] = tx.outputs
         (
           sreq,
           ScriptContext {
             ..ctx,
             transaction: Transaction {
               ..tx,
               mint: tx.mint
                 |> value.from_minted_value
                 |> value_without_token(
                      bond_pid,
                      get_bond_datum(bond_out).token_name,
                    )
                 |> value.to_minted_value,
             },
           },
         )
       }
    |> validate
    |> not
}

test fail_when_minting_not_enough_bond_tokens() fail {
  build_tx(request: FulfilledZero, lend_amount: Entire)
    |> fn(args: (Input, ScriptContext)) {
         let (sreq, ctx) = args
         let tx = ctx.transaction
         expect [_, bond_out, ..] = tx.outputs
         (
           sreq,
           ScriptContext {
             ..ctx,
             transaction: Transaction {
               ..tx,
               mint: tx.mint
                 |> value.from_minted_value
                 |> value.add(bond_pid, get_bond_datum(bond_out).token_name, -1)
                 |> value.to_minted_value,
             },
           },
         )
       }
    |> validate
    |> not
}

test fail_when_minting_exceeded_bond_tokens() fail {
  build_tx(request: FulfilledZero, lend_amount: Entire)
    |> fn(args: (Input, ScriptContext)) {
         let (sreq, ctx) = args
         let tx = ctx.transaction
         expect [_, bond_out, ..] = tx.outputs
         (
           sreq,
           ScriptContext {
             ..ctx,
             transaction: Transaction {
               ..tx,
               mint: tx.mint
                 |> value.from_minted_value
                 |> value.add(bond_pid, get_bond_datum(bond_out).token_name, 1)
                 |> value.to_minted_value,
             },
           },
         )
       }
    |> validate
    |> not
}

test fail_when_burning_bond_tokens() fail {
  build_tx(request: FulfilledZero, lend_amount: Entire)
    |> fn(args: (Input, ScriptContext)) {
         let (sreq, ctx) = args
         let tx = ctx.transaction
         expect [_, bond_out, ..] = tx.outputs
         (
           sreq,
           ScriptContext {
             ..ctx,
             transaction: Transaction {
               ..tx,
               mint: tx.mint
                 |> value.from_minted_value
                 |> value_without_token(
                      bond_pid,
                      get_bond_datum(bond_out).token_name,
                    )
                 |> value.add(bond_pid, get_bond_datum(bond_out).token_name, -1)
                 |> value.to_minted_value,
             },
           },
         )
       }
    |> validate
    |> not
}

test fail_when_attempting_other_token_attack_on_nft_policy() {
  build_tx(request: FulfilledZero, lend_amount: Entire)
    |> fn(args: (Input, ScriptContext)) {
         let (sreq, ctx) = args
         let tx = ctx.transaction
         (
           sreq,
           ScriptContext {
             ..ctx,
             transaction: Transaction {
               ..tx,
               mint: tx.mint
                 |> value.from_minted_value
                 |> value.add(nft_pid, "calculated-nft", 1)
                 |> value.to_minted_value,
             },
           },
         )
       }
    |> validate
    |> not
}

test fail_when_attempting_other_token_attack_on_bond_policy() {
  build_tx(request: FulfilledZero, lend_amount: Entire)
    |> fn(args: (Input, ScriptContext)) {
         let (sreq, ctx) = args
         let tx = ctx.transaction
         (
           sreq,
           ScriptContext {
             ..ctx,
             transaction: Transaction {
               ..tx,
               mint: tx.mint
                 |> value.from_minted_value
                 |> value.add(bond_pid, "calculated-bond-name", 1)
                 |> value.to_minted_value,
             },
           },
         )
       }
    |> validate
    |> not
}

test fail_when_attempting_other_redeemer_attack_on_bond_nft_policy() fail {
  build_tx(request: FulfilledZero, lend_amount: Entire)
    |> fn(args: (Input, ScriptContext)) {
         let (sreq, ctx) = args
         let tx = ctx.transaction
         (
           sreq,
           ScriptContext {
             ..ctx,
             transaction: Transaction {
               ..tx,
               redeemers: tx.redeemers
                 |> dict.delete(Mint(nft_pid))
                 |> dict.insert(
                      Spend(sreq.output_reference),
                      BondRedeem { pid: nft_pid },
                      script_purpose_compare,
                    ),
             },
           },
         )
       }
    |> fn(args: (Input, ScriptContext)) {
         let cfg = build_cfg()
         let (spending_request, ctx) = args
         let tx = ctx.transaction
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
         and {
           bond_nft.burning_force_redeem(ctx.transaction, nft_pid),
           bond_token.minting_with_fee(
             cfg,
             ctx.transaction,
             req_skh,
             bond_skh,
             bond_pid,
           ),
           bond_create.spending(
             cfg,
             ctx,
             get_request_datum(spending_request.output),
             bond_skh,
             nft_pid,
             bond_pid,
             req_pid,
           ),
         }
       }
    |> not
}

test fail_when_attempting_other_redeemer_attack_on_bond_policy() fail {
  build_tx(request: FulfilledZero, lend_amount: Entire)
    |> fn(args: (Input, ScriptContext)) {
         let (sreq, ctx) = args
         let tx = ctx.transaction
         (
           sreq,
           ScriptContext {
             ..ctx,
             transaction: Transaction {
               ..tx,
               redeemers: tx.redeemers
                 |> dict.delete(Mint(bond_pid))
                 |> dict.insert(
                      Spend(sreq.output_reference),
                      BondRedeem { pid: bond_pid },
                      script_purpose_compare,
                    ),
             },
           },
         )
       }
    |> fn(args: (Input, ScriptContext)) {
         let cfg = build_cfg()
         let (spending_request, ctx) = args
         let tx = ctx.transaction
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
         and {
           bond_nft.minting(
             cfg,
             ctx.transaction,
             req_skh,
             bond_skh,
             nft_pid,
             req_pid,
             spending_request.output_reference,
           ),
           bond_token.burning_force_redeem(ctx.transaction, bond_pid),
           bond_create.spending(
             cfg,
             ctx,
             get_request_datum(spending_request.output),
             bond_skh,
             nft_pid,
             bond_pid,
             req_pid,
           ),
         }
       }
    |> not
}

// ====================Bond====================
// pub type BondDatum {
//   epo_rewards: Value,
//   duration: Int,
//   bond_symbol: PolicyId,
//   token_name: AssetName,
//   bond_amount: Int,
//   buffer: Int,
//   fee: Int,
//   borrower: AssetName,
//   start: Int,
// }
test fail_when_setting_locked_bond_lovelace_lower() fail {
  build_tx(request: FulfilledZero, lend_amount: Entire)
    |> fn(args: (Input, ScriptContext)) {
         let (sreq, ctx) = args
         let tx = ctx.transaction
         expect [lender_out, bond_out, ..rest] = tx.outputs
         (
           sreq,
           ScriptContext {
             ..ctx,
             transaction: Transaction {
               ..tx,
               outputs: [lender_out, bond_out |> add_lovelace(-1), ..rest],
             },
           },
         )
       }
    |> validate
    |> not
}

test fail_when_setting_bond_duration_shorter() {
  build_tx(request: FulfilledZero, lend_amount: Entire)
    |> fn(args: (Input, ScriptContext)) {
         let (sreq, ctx) = args
         let tx = ctx.transaction
         expect [lender_out, bond_out, ..rest] = tx.outputs
         (
           sreq,
           ScriptContext {
             ..ctx,
             transaction: Transaction {
               ..tx,
               outputs: [lender_out, bond_out |> add_bond_duration(-1), ..rest],
             },
           },
         )
       }
    |> validate
    |> not
}

test fail_when_setting_bond_duration_longer() {
  build_tx(request: FulfilledZero, lend_amount: Entire)
    |> fn(args: (Input, ScriptContext)) {
         let (sreq, ctx) = args
         let tx = ctx.transaction
         expect [lender_out, bond_out, ..rest] = tx.outputs
         (
           sreq,
           ScriptContext {
             ..ctx,
             transaction: Transaction {
               ..tx,
               outputs: [lender_out, bond_out |> add_bond_duration(1), ..rest],
             },
           },
         )
       }
    |> validate
    |> not
}

test fail_when_setting_incorrect_bond_symbol() fail {
  build_tx(request: FulfilledZero, lend_amount: Entire)
    |> fn(args: (Input, ScriptContext)) {
         let (sreq, ctx) = args
         let tx = ctx.transaction
         expect [lender_out, bond_out, ..rest] = tx.outputs
         (
           sreq,
           ScriptContext {
             ..ctx,
             transaction: Transaction {
               ..tx,
               outputs: [
                 lender_out,
                 bond_out |> set_bond_symbol("incorect"),
                 ..rest
               ],
             },
           },
         )
       }
    |> validate
    |> not
}

test fail_when_setting_exceeded_bond_amount() fail {
  build_tx(request: FulfilledZero, lend_amount: Entire)
    |> fn(args: (Input, ScriptContext)) {
         let (sreq, ctx) = args
         let tx = ctx.transaction
         expect [lender_out, bond_out, ..rest] = tx.outputs
         (
           sreq,
           ScriptContext {
             ..ctx,
             transaction: Transaction {
               ..tx,
               outputs: [lender_out, bond_out |> add_bond_amount(1), ..rest],
             },
           },
         )
       }
    |> validate
    |> not
}

test fail_when_setting_bond_buffer_lower() {
  build_tx(request: FulfilledZero, lend_amount: Entire)
    |> fn(args: (Input, ScriptContext)) {
         let (sreq, ctx) = args
         let tx = ctx.transaction
         expect [lender_out, bond_out, ..rest] = tx.outputs
         (
           sreq,
           ScriptContext {
             ..ctx,
             transaction: Transaction {
               ..tx,
               outputs: [lender_out, bond_out |> add_bond_buffer(-1), ..rest],
             },
           },
         )
       }
    |> validate
    |> not
}

test fail_when_setting_bond_buffer_higher() {
  build_tx(request: FulfilledZero, lend_amount: Entire)
    |> fn(args: (Input, ScriptContext)) {
         let (sreq, ctx) = args
         let tx = ctx.transaction
         expect [lender_out, bond_out, ..rest] = tx.outputs
         (
           sreq,
           ScriptContext {
             ..ctx,
             transaction: Transaction {
               ..tx,
               outputs: [lender_out, bond_out |> add_bond_buffer(1), ..rest],
             },
           },
         )
       }
    |> validate
    |> not
}

test fail_when_setting_bond_fee_lower() fail {
  build_tx(request: FulfilledZero, lend_amount: Entire)
    |> fn(args: (Input, ScriptContext)) {
         let (sreq, ctx) = args
         let tx = ctx.transaction
         expect [lender_out, bond_out, ..rest] = tx.outputs
         (
           sreq,
           ScriptContext {
             ..ctx,
             transaction: Transaction {
               ..tx,
               outputs: [lender_out, bond_out |> add_bond_fee(-1), ..rest],
             },
           },
         )
       }
    |> validate
    |> not
}

test fail_when_setting_bond_fee_higher() {
  build_tx(request: FulfilledZero, lend_amount: Entire)
    |> fn(args: (Input, ScriptContext)) {
         let (sreq, ctx) = args
         let tx = ctx.transaction
         expect [lender_out, bond_out, ..rest] = tx.outputs
         (
           sreq,
           ScriptContext {
             ..ctx,
             transaction: Transaction {
               ..tx,
               outputs: [lender_out, bond_out |> add_bond_fee(1), ..rest],
             },
           },
         )
       }
    |> validate
    |> not
}

test fail_when_setting_bond_borrower_incorrect() fail {
  build_tx(request: FulfilledZero, lend_amount: Entire)
    |> fn(args: (Input, ScriptContext)) {
         let (sreq, ctx) = args
         let tx = ctx.transaction
         expect [lender_out, bond_out, ..rest] = tx.outputs
         (
           sreq,
           ScriptContext {
             ..ctx,
             transaction: Transaction {
               ..tx,
               outputs: [
                 lender_out,
                 bond_out |> set_bond_borrower("unknown-borrower"),
                 ..rest
               ],
             },
           },
         )
       }
    |> validate
    |> not
}

test fail_when_setting_bond_start_sooner() fail {
  build_tx(request: FulfilledZero, lend_amount: Entire)
    |> fn(args: (Input, ScriptContext)) {
         let (sreq, ctx) = args
         let tx = ctx.transaction
         expect [lender_out, bond_out, ..rest] = tx.outputs
         (
           sreq,
           ScriptContext {
             ..ctx,
             transaction: Transaction {
               ..tx,
               outputs: [lender_out, bond_out |> add_bond_start(-1), ..rest],
             },
           },
         )
       }
    |> validate
    |> not
}

test fail_when_setting_bond_start_later() fail {
  build_tx(request: FulfilledZero, lend_amount: Entire)
    |> fn(args: (Input, ScriptContext)) {
         let (sreq, ctx) = args
         let tx = ctx.transaction
         expect [lender_out, bond_out, ..rest] = tx.outputs
         (
           sreq,
           ScriptContext {
             ..ctx,
             transaction: Transaction {
               ..tx,
               outputs: [lender_out, bond_out |> add_bond_start(1), ..rest],
             },
           },
         )
       }
    |> validate
    |> not
}

test fail_when_bond_value_doesnt_hold_bond_nft() {
  build_tx(request: FulfilledZero, lend_amount: Entire)
    |> fn(args: (Input, ScriptContext)) {
         let (sreq, ctx) = args
         let tx = ctx.transaction
         expect [lender_out, bond_out, ..rest] = tx.outputs
         let bond = get_bond_datum(bond_out)
         (
           sreq,
           ScriptContext {
             ..ctx,
             transaction: Transaction {
               ..tx,
               outputs: [
                 lender_out,
                 Output {
                   ..bond_out,
                   value: bond_out.value
                     |> value_without_token(nft_pid, bond.token_name),
                 },
                 ..rest
               ],
             },
           },
         )
       }
    |> validate
    |> not
}

// test fail_when_bond_hold_incorrect_nft_while_lending_multiple_bonds(){}

// ====================Borrow Request====================
// pub type RequestDatum {
//   apr: Int,
//   duration: Int,
//   symbol: PolicyId,
//   borrower: AssetName,
//   requested: Int,
//   issued: Int,
//   epo_rewards: Int,
//   prepaid: Int,
//   buffer: Int,
//   fee: Int,
// }
fn add_request_fee(self: Output, amt: Int) {
  let datum = get_request_datum(self)
  Output {
    ..self,
    datum: InlineDatum(RequestDatum { ..datum, fee: datum.fee + amt }),
  }
}

fn add_request_buffer(self: Output, amt: Int) {
  let datum = get_request_datum(self)
  Output {
    ..self,
    datum: InlineDatum(RequestDatum { ..datum, buffer: datum.buffer + amt }),
  }
}

fn add_request_prepaid(self: Output, amt: Int) {
  let datum = get_request_datum(self)
  Output {
    ..self,
    datum: InlineDatum(RequestDatum { ..datum, prepaid: datum.prepaid + amt }),
  }
}

fn add_request_epo_rewards(self: Output, amt: Int) {
  let datum = get_request_datum(self)
  Output {
    ..self,
    datum: InlineDatum(
      RequestDatum { ..datum, epo_rewards: datum.epo_rewards + amt },
    ),
  }
}

fn add_request_issued(self: Output, amt: Int) {
  let datum = get_request_datum(self)
  Output {
    ..self,
    datum: InlineDatum(RequestDatum { ..datum, issued: datum.issued + amt }),
  }
}

fn add_request_requested(self: Output, amt: Int) {
  let datum = get_request_datum(self)
  Output {
    ..self,
    datum: InlineDatum(
      RequestDatum { ..datum, requested: datum.requested + amt },
    ),
  }
}

fn set_request_borrower(self: Output, brr: ByteArray) {
  let datum = get_request_datum(self)
  Output { ..self, datum: InlineDatum(RequestDatum { ..datum, borrower: brr }) }
}

fn add_request_apr(self: Output, amt: Int) {
  let datum = get_request_datum(self)
  Output {
    ..self,
    datum: InlineDatum(RequestDatum { ..datum, apr: datum.apr + amt }),
  }
}

fn add_request_duration(self: Output, amt: Int) {
  let datum = get_request_datum(self)
  Output {
    ..self,
    datum: InlineDatum(RequestDatum { ..datum, duration: datum.duration + amt }),
  }
}

fn set_request_symbol(self: Output, symbol: PolicyId) {
  let datum = get_request_datum(self)
  Output {
    ..self,
    datum: InlineDatum(RequestDatum { ..datum, symbol: symbol }),
  }
}

test fail_when_consuming_borrow_request_partially_but_remove_request() {
  build_tx(request: FulfilledZero, lend_amount: Partial(10))
    |> fn(args: (Input, ScriptContext)) {
         let (sreq, ctx) = args
         let tx = ctx.transaction
         expect [lender_out, bond_out, fee_out, _remain_request] = tx.outputs
         (
           sreq,
           ScriptContext {
             ..ctx,
             transaction: Transaction {
               ..tx,
               outputs: [lender_out, bond_out, fee_out],
             },
           },
         )
       }
    |> validate
    |> not
}

test fail_when_setting_request_apr_lower() fail {
  build_tx(request: FulfilledZero, lend_amount: Partial(10))
    |> fn(args: (Input, ScriptContext)) {
         let (sreq, ctx) = args
         let tx = ctx.transaction
         expect [lender_out, bond_out, fee_out, remain_request] = tx.outputs
         (
           sreq,
           ScriptContext {
             ..ctx,
             transaction: Transaction {
               ..tx,
               outputs: [
                 lender_out,
                 bond_out,
                 fee_out,
                 remain_request |> add_request_apr(-1),
               ],
             },
           },
         )
       }
    |> validate
    |> not
}

test fail_when_setting_request_apr_higher() fail {
  build_tx(request: FulfilledZero, lend_amount: Partial(10))
    |> fn(args: (Input, ScriptContext)) {
         let (sreq, ctx) = args
         let tx = ctx.transaction
         expect [lender_out, bond_out, fee_out, remain_request] = tx.outputs
         (
           sreq,
           ScriptContext {
             ..ctx,
             transaction: Transaction {
               ..tx,
               outputs: [
                 lender_out,
                 bond_out,
                 fee_out,
                 remain_request |> add_request_apr(1),
               ],
             },
           },
         )
       }
    |> validate
    |> not
}

test fail_when_setting_request_duration_shorter() fail {
  build_tx(request: FulfilledZero, lend_amount: Partial(10))
    |> fn(args: (Input, ScriptContext)) {
         let (sreq, ctx) = args
         let tx = ctx.transaction
         expect [lender_out, bond_out, fee_out, remain_request] = tx.outputs
         (
           sreq,
           ScriptContext {
             ..ctx,
             transaction: Transaction {
               ..tx,
               outputs: [
                 lender_out,
                 bond_out,
                 fee_out,
                 remain_request |> add_request_duration(-1),
               ],
             },
           },
         )
       }
    |> validate
    |> not
}

test fail_when_setting_request_duration_longer() fail {
  build_tx(request: FulfilledZero, lend_amount: Partial(10))
    |> fn(args: (Input, ScriptContext)) {
         let (sreq, ctx) = args
         let tx = ctx.transaction
         expect [lender_out, bond_out, fee_out, remain_request] = tx.outputs
         (
           sreq,
           ScriptContext {
             ..ctx,
             transaction: Transaction {
               ..tx,
               outputs: [
                 lender_out,
                 bond_out,
                 fee_out,
                 remain_request |> add_request_duration(1),
               ],
             },
           },
         )
       }
    |> validate
    |> not
}

test fail_when_setting_incorrect_request_symbol() fail {
  build_tx(request: FulfilledZero, lend_amount: Partial(10))
    |> fn(args: (Input, ScriptContext)) {
         let (sreq, ctx) = args
         let tx = ctx.transaction
         expect [lender_out, bond_out, fee_out, remain_request] = tx.outputs
         (
           sreq,
           ScriptContext {
             ..ctx,
             transaction: Transaction {
               ..tx,
               outputs: [
                 lender_out,
                 bond_out,
                 fee_out,
                 remain_request |> set_request_symbol("another-symbol"),
               ],
             },
           },
         )
       }
    |> validate
    |> not
}

test fail_when_setting_incorrect_request_borrower() fail {
  build_tx(request: FulfilledZero, lend_amount: Partial(10))
    |> fn(args: (Input, ScriptContext)) {
         let (sreq, ctx) = args
         let tx = ctx.transaction
         expect [lender_out, bond_out, fee_out, remain_request] = tx.outputs
         (
           sreq,
           ScriptContext {
             ..ctx,
             transaction: Transaction {
               ..tx,
               outputs: [
                 lender_out,
                 bond_out,
                 fee_out,
                 remain_request |> set_request_borrower("another-borrower"),
               ],
             },
           },
         )
       }
    |> validate
    |> not
}

test fail_when_setting_request_requested_lower() fail {
  build_tx(request: FulfilledZero, lend_amount: Partial(10))
    |> fn(args: (Input, ScriptContext)) {
         let (sreq, ctx) = args
         let tx = ctx.transaction
         expect [lender_out, bond_out, fee_out, remain_request] = tx.outputs
         (
           sreq,
           ScriptContext {
             ..ctx,
             transaction: Transaction {
               ..tx,
               outputs: [
                 lender_out,
                 bond_out,
                 fee_out,
                 remain_request |> add_request_requested(-1),
               ],
             },
           },
         )
       }
    |> validate
    |> not
}

test fail_when_setting_request_requested_higher() fail {
  build_tx(request: FulfilledZero, lend_amount: Partial(10))
    |> fn(args: (Input, ScriptContext)) {
         let (sreq, ctx) = args
         let tx = ctx.transaction
         expect [lender_out, bond_out, fee_out, remain_request] = tx.outputs
         (
           sreq,
           ScriptContext {
             ..ctx,
             transaction: Transaction {
               ..tx,
               outputs: [
                 lender_out,
                 bond_out,
                 fee_out,
                 remain_request |> add_request_requested(1),
               ],
             },
           },
         )
       }
    |> validate
    |> not
}

test fail_when_setting_request_issued_lower() fail {
  build_tx(request: FulfilledZero, lend_amount: Partial(10))
    |> fn(args: (Input, ScriptContext)) {
         let (sreq, ctx) = args
         let tx = ctx.transaction
         expect [lender_out, bond_out, fee_out, remain_request] = tx.outputs
         (
           sreq,
           ScriptContext {
             ..ctx,
             transaction: Transaction {
               ..tx,
               outputs: [
                 lender_out,
                 bond_out,
                 fee_out,
                 remain_request |> add_request_issued(-1),
               ],
             },
           },
         )
       }
    |> validate
    |> not
}

test fail_when_setting_request_issued_higher() {
  build_tx(request: FulfilledZero, lend_amount: Partial(10))
    |> fn(args: (Input, ScriptContext)) {
         let (sreq, ctx) = args
         let tx = ctx.transaction
         expect [lender_out, bond_out, fee_out, remain_request] = tx.outputs
         (
           sreq,
           ScriptContext {
             ..ctx,
             transaction: Transaction {
               ..tx,
               outputs: [
                 lender_out,
                 bond_out,
                 fee_out,
                 remain_request |> add_request_issued(1),
               ],
             },
           },
         )
       }
    |> validate
    |> not
}

test fail_when_setting_request_epo_rewards_lower() fail {
  build_tx(request: FulfilledZero, lend_amount: Partial(10))
    |> fn(args: (Input, ScriptContext)) {
         let (sreq, ctx) = args
         let tx = ctx.transaction
         expect [lender_out, bond_out, fee_out, remain_request] = tx.outputs
         (
           sreq,
           ScriptContext {
             ..ctx,
             transaction: Transaction {
               ..tx,
               outputs: [
                 lender_out,
                 bond_out,
                 fee_out,
                 remain_request |> add_request_epo_rewards(-1),
               ],
             },
           },
         )
       }
    |> validate
    |> not
}

test fail_when_setting_request_prepaid_lower() fail {
  build_tx(request: FulfilledZero, lend_amount: Partial(10))
    |> fn(args: (Input, ScriptContext)) {
         let (sreq, ctx) = args
         let tx = ctx.transaction
         expect [lender_out, bond_out, fee_out, remain_request] = tx.outputs
         (
           sreq,
           ScriptContext {
             ..ctx,
             transaction: Transaction {
               ..tx,
               outputs: [
                 lender_out,
                 bond_out,
                 fee_out,
                 remain_request |> add_request_prepaid(-1),
               ],
             },
           },
         )
       }
    |> validate
    |> not
}

test fail_when_setting_request_prepaid_higher() fail {
  build_tx(request: FulfilledZero, lend_amount: Partial(10))
    |> fn(args: (Input, ScriptContext)) {
         let (sreq, ctx) = args
         let tx = ctx.transaction
         expect [lender_out, bond_out, fee_out, remain_request] = tx.outputs
         (
           sreq,
           ScriptContext {
             ..ctx,
             transaction: Transaction {
               ..tx,
               outputs: [
                 lender_out,
                 bond_out,
                 fee_out,
                 remain_request |> add_request_prepaid(1),
               ],
             },
           },
         )
       }
    |> validate
    |> not
}

test fail_when_setting_request_buffer_lower() fail {
  build_tx(request: FulfilledZero, lend_amount: Partial(10))
    |> fn(args: (Input, ScriptContext)) {
         let (sreq, ctx) = args
         let tx = ctx.transaction
         expect [lender_out, bond_out, fee_out, remain_request] = tx.outputs
         (
           sreq,
           ScriptContext {
             ..ctx,
             transaction: Transaction {
               ..tx,
               outputs: [
                 lender_out,
                 bond_out,
                 fee_out,
                 remain_request |> add_request_buffer(-1),
               ],
             },
           },
         )
       }
    |> validate
    |> not
}

test fail_when_setting_request_buffer_higher() fail {
  build_tx(request: FulfilledZero, lend_amount: Partial(10))
    |> fn(args: (Input, ScriptContext)) {
         let (sreq, ctx) = args
         let tx = ctx.transaction
         expect [lender_out, bond_out, fee_out, remain_request] = tx.outputs
         (
           sreq,
           ScriptContext {
             ..ctx,
             transaction: Transaction {
               ..tx,
               outputs: [
                 lender_out,
                 bond_out,
                 fee_out,
                 remain_request |> add_request_buffer(1),
               ],
             },
           },
         )
       }
    |> validate
    |> not
}

test fail_when_setting_request_fee_lower() fail {
  build_tx(request: FulfilledZero, lend_amount: Partial(10))
    |> fn(args: (Input, ScriptContext)) {
         let (sreq, ctx) = args
         let tx = ctx.transaction
         expect [lender_out, bond_out, fee_out, remain_request] = tx.outputs
         (
           sreq,
           ScriptContext {
             ..ctx,
             transaction: Transaction {
               ..tx,
               outputs: [
                 lender_out,
                 bond_out,
                 fee_out,
                 remain_request |> add_request_fee(-1),
               ],
             },
           },
         )
       }
    |> validate
    |> not
}

test fail_when_setting_request_fee_higher() fail {
  build_tx(request: FulfilledZero, lend_amount: Partial(10))
    |> fn(args: (Input, ScriptContext)) {
         let (sreq, ctx) = args
         let tx = ctx.transaction
         expect [lender_out, bond_out, fee_out, remain_request] = tx.outputs
         (
           sreq,
           ScriptContext {
             ..ctx,
             transaction: Transaction {
               ..tx,
               outputs: [
                 lender_out,
                 bond_out,
                 fee_out,
                 remain_request |> add_request_fee(1),
               ],
             },
           },
         )
       }
    |> validate
    |> not
}
