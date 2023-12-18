use aiken/dict
use aiken/interval
use aiken/transaction.{
  Datum, InlineDatum, Input, NoDatum, Output, OutputReference, ScriptContext,
  Spend, Transaction, TransactionId,
}
use aiken/transaction/credential.{Address}
use aiken/transaction/value.{Value}
use bond_issue/types.{BondDatum, BondIssueConfig, PlatformConfig, RequestDatum}
use borrow_request/bond_create
use common/time.{
  BasisPoints, get_epoch_config_preview, get_slot_config_network_preview,
  slot_to_begin_posix_time,
}

fn build_input(
  tx_hash: ByteArray,
  tx_id: Int,
  addr: Address,
  val: Value,
  dt: Datum,
) {
  Input {
    output_reference: OutputReference(TransactionId(tx_hash), tx_id),
    output: Output {
      address: addr,
      value: val,
      datum: dt,
      reference_script: None,
    },
  }
}

test fail_check() {
  let fee_addr = credential.from_script("collector_addr")
  let cfg =
    BondIssueConfig {
      slot: get_slot_config_network_preview(),
      epoch: get_epoch_config_preview(),
      basis: BasisPoints { base: 10_000, min: 1, max: 9_999 },
      platform: PlatformConfig {
        bond_face_value: 100_000_000,
        fee: 500,
        address: fee_addr,
        tx_ttl: 6 * 60,
        min_buffer: 6,
        prepaid_plus: 3,
        min_requested: 100,
        min_apr: 200,
        min_duration: 6,
      },
    }
  let owner_addr = credential.from_verification_key("owner")
  let borrow_request_pkh =
    #"54f0dac05dc1b598a9ba832119eec817d31c92802ebbdfbdce3a4473"
  let borrow_request_skh =
    #"2b9f6ee3e1dd784ebba52ba98634ea52f1d78a3601ef20f0bf6b7e80"
  let borrow_request_addr =
    credential.from_script(borrow_request_pkh)
      |> credential.with_delegation_key(borrow_request_skh)
  let req_pid = #"7ba0bf00b89ea52f04e204550c1a38a5b2f411ea90cdc690f048c328"
  let borrower_pid = #"7ba0bf00b89ea52f04e204550c1a38a5b2f411ea90cdc690f048c329"
  let borrower_nft =
    #"d53d658b5f7eac3f741389135662a2bf9f2475844141705a5c0514f81e47f9bf"
  let sreq_dt =
    RequestDatum {
      apr: 656,
      duration: 72,
      symbol: borrower_pid,
      borrower: borrower_nft,
      requested: 400,
      issued: 0,
      epo_rewards: 35945205,
      prepaid: 9,
      buffer: 6,
      fee: 500,
    }
  let bond_pkh = #"0916747413f64a22577b05b207c609d53fa1f110589bd61775770b5c"
  let bond_addr =
    credential.from_script(bond_pkh)
      |> credential.with_delegation_key(borrow_request_skh)
  let input_01 =
    build_input(
      #"23850612667a59e236ceeea412440b446fa697f2b988eb05e070aaa18c8cad0f",
      0,
      borrow_request_addr,
      value.from_lovelace(323506845) |> value.add(req_pid, borrower_nft, 1),
      InlineDatum(sreq_dt),
    )

  let input_02 =
    Input {
      output_reference: OutputReference(
        TransactionId(
          #"9e182879131766dafaa0fe44b77efc748779247cac68ae6ebc948b0465731e10",
        ),
        1,
      ),
      output: Output {
        address: owner_addr,
        value: value.from_lovelace(3416127),
        datum: NoDatum,
        reference_script: None,
      },
    }
  let input_03 =
    Input {
      output_reference: OutputReference(
        TransactionId(
          #"1d7e40357b586802a38243a77216ec6f8c5106ae928e1452f6706c41c9e67078",
        ),
        1,
      ),
      output: Output {
        address: owner_addr,
        value: value.from_lovelace(4675851207),
        datum: NoDatum,
        reference_script: None,
      },
    }
  let input_04 =
    Input {
      output_reference: OutputReference(
        TransactionId(
          #"23850612667a59e236ceeea412440b446fa697f2b988eb05e070aaa18c8cad0f",
        ),
        1,
      ),
      output: Output {
        address: owner_addr,
        value: value.from_lovelace(9147333849),
        datum: NoDatum,
        reference_script: None,
      },
    }
  let nft_pid = #"f0225dc689075f723faad666a16febada1d692f12eda5de2c2c7c7cc"
  let bond_pid = #"294967f6df83712494e176cf40b6d89690b0b0e3a286216710f1d7e7"
  let bond_name =
    #"79b18aded9e04c72f38e5fa8c4b31a0f3dc83d47f9ad5cdc2eed3f22f477247e"
  let output_01 =
    Output {
      address: fee_addr,
      value: value.from_lovelace(4043836),
      datum: NoDatum,
      reference_script: None,
    }
  let issue_qty = 100
  let output_02 =
    Output {
      address: bond_addr,
      value: value.from_lovelace(10076832873)
        |> value.add(nft_pid, bond_name, 1),
      datum: InlineDatum(
        BondDatum {
          epo_rewards: value.from_lovelace(8986301),
          duration: 72,
          bond_symbol: bond_pid,
          token_name: bond_name,
          bond_amount: issue_qty,
          buffer: 6,
          fee: 500,
          borrower: borrower_nft,
          start: 30409,
        },
      ),
      reference_script: None,
    }
  let output_03 =
    Output {
      address: borrow_request_addr,
      value: value.from_lovelace(242630136)
        |> value.add(req_pid, borrower_nft, 1),
      datum: InlineDatum(
        RequestDatum {
          apr: 656,
          duration: 72,
          symbol: borrower_pid,
          borrower: borrower_nft,
          requested: sreq_dt.requested,
          issued: sreq_dt.issued + issue_qty,
          epo_rewards: 26958904,
          prepaid: 9,
          buffer: 6,
          fee: 500,
        },
      ),
      reference_script: None,
    }
  let output_04 =
    Output {
      address: owner_addr,
      value: value.from_lovelace(3826431183),
      datum: NoDatum,
      reference_script: None,
    }
  let mint_tokens =
    value.from_asset(bond_pid, bond_name, issue_qty)
      |> value.add(nft_pid, bond_name, 1)
      |> value.to_minted_value()
  let tx_time =
    interval.between(
      slot_to_begin_posix_time(35979329, cfg.slot),
      slot_to_begin_posix_time(35979509, cfg.slot),
    )
  let tx =
    Transaction {
      inputs: [input_01, input_02, input_03, input_04],
      reference_inputs: [],
      outputs: [output_01, output_02, output_03, output_04],
      fee: value.zero(),
      mint: mint_tokens,
      certificates: [],
      withdrawals: dict.new(),
      validity_range: tx_time,
      extra_signatories: [],
      redeemers: dict.new(),
      datums: dict.new(),
      id: TransactionId {
        hash: #"0000000000000000000000000000000000000000000000000000000000000000",
      },
    }
  let ctx =
    ScriptContext { transaction: tx, purpose: Spend(input_01.output_reference) }

  bond_create.spending(cfg, ctx, sreq_dt, bond_pkh, nft_pid, bond_pid, req_pid)
}
