use aiken/dict
use aiken/interval
use aiken/transaction.{
  Datum, InlineDatum, Input, NoDatum, Output, OutputReference, ScriptContext,
  Spend, Transaction, TransactionId,
}
use aiken/transaction/credential.{Address}
use aiken/transaction/value.{Value}
use bond_issue/types.{BondDatum, BondIssueConfig, PlatformConfig, RequestDatum}
use borrow_position/bond_nft
use borrow_position/bond_token
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

test succ_bond_create() {
  let fee_addr = credential.from_verification_key("fee_addr")
  let cfg =
    BondIssueConfig {
      slot: get_slot_config_network_preview(),
      epoch: get_epoch_config_preview(),
      basis: BasisPoints { base: 10_000, min: 1, max: 9_999 },
      platform: PlatformConfig {
        bond_face_value: 100_000_000,
        fee: 500,
        fee_addr,
        tx_ttl: 6 * 60,
        min_buffer: 6,
        prepaid_plus: 3,
        min_requested: 100,
        min_apr: 200,
        min_duration: 6,
        garbage_addr: credential.from_verification_key("garbage_addr"),
      },
    }
  let owner_addr = credential.from_verification_key("owner")
  let req_skh = #"4c0df7526072e3200e2796d3b900078625685cb1ebf3fcf4c29eba32"
  let req_stake = #"2b9f6ee3e1dd784ebba52ba98634ea52f1d78a3601ef20f0bf6b7e80"
  let req_addr =
    credential.from_script(req_skh)
      |> credential.with_delegation_key(req_stake)
  let req_pid = #"74b89307994e186eac325f7245fe1a9d9efa6bab0b786afed50eeec1"
  let borrower_pid = #"894677d0c96689ed3101394aa1dc35c1a6de99082e5b5cb229b69bd4"
  let borrower_nft =
    #"f4eb6725314d9c04be6c02d1e80d30f27dd2d438b5d935bd1402df603e55cb0e"
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
  let bond_skh = #"0c870a14186f553f2cc76884cf395286a39ed93550707181a365dcf8"
  let bond_addr =
    credential.from_script(bond_skh)
      |> credential.with_delegation_key(req_stake)
  let input_01 =
    build_input(
      #"2c7c0ba54d6bfa9ea2ed24789d960e92d75602f5956b7b404fa9c2377808d208",
      0,
      req_addr,
      value.from_lovelace(323506845) |> value.add(req_pid, borrower_nft, 1),
      InlineDatum(sreq_dt),
    )

  let input_02 =
    Input {
      output_reference: OutputReference(
        TransactionId(
          #"2c7c0ba54d6bfa9ea2ed24789d960e92d75602f5956b7b404fa9c2377808d208",
        ),
        2,
      ),
      output: Output {
        address: owner_addr,
        value: value.from_lovelace(18488827229),
        datum: NoDatum,
        reference_script: None,
      },
    }
  // let input_03 =
  //   Input {
  //     output_reference: OutputReference(
  //       TransactionId(
  //         #"1d7e40357b586802a38243a77216ec6f8c5106ae928e1452f6706c41c9e67078",
  //       ),
  //       1,
  //     ),
  //     output: Output {
  //       address: owner_addr,
  //       value: value.from_lovelace(4675851207),
  //       datum: NoDatum,
  //       reference_script: None,
  //     },
  //   }
  // let input_04 =
  //   Input {
  //     output_reference: OutputReference(
  //       TransactionId(
  //         #"23850612667a59e236ceeea412440b446fa697f2b988eb05e070aaa18c8cad0f",
  //       ),
  //       1,
  //     ),
  //     output: Output {
  //       address: owner_addr,
  //       value: value.from_lovelace(9147333849),
  //       datum: NoDatum,
  //       reference_script: None,
  //     },
  //   }
  let nft_pid = #"b08ea97cd6804da26cf4cd4a346340222244f6e9c63fc2af7e24bd45"
  let bond_pid = #"d4cb2133c49544f3f4aed61adf33d0aa70451bc0640e95381ef3356d"
  let bond_name =
    #"56a951688173fc7332fd488f0254e4a2e2a23374f2ee1004af51cc0da34306a6"
  let output_01 =
    Output {
      address: fee_addr,
      value: value.from_lovelace(969750),
      datum: NoDatum,
      reference_script: None,
    }
  let issue_qty = 5
  let output_02 =
    Output {
      address: bond_addr,
      value: value.from_lovelace(504290959)
        |> value.add(nft_pid, bond_name, 1),
      datum: InlineDatum(
        BondDatum {
          epo_rewards: value.from_lovelace(449315),
          duration: 72,
          bond_symbol: bond_pid,
          token_name: bond_name,
          bond_amount: issue_qty,
          buffer: 6,
          fee: 500,
          borrower: borrower_nft,
          start: 30589,
        },
      ),
      reference_script: None,
    }
  let output_03 =
    Output {
      address: req_addr,
      value: value.from_lovelace(319463010)
        |> value.add(req_pid, borrower_nft, 1),
      datum: InlineDatum(
        RequestDatum {
          apr: 656,
          duration: 72,
          symbol: borrower_pid,
          borrower: borrower_nft,
          requested: sreq_dt.requested,
          issued: sreq_dt.issued + issue_qty,
          epo_rewards: 35495890,
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
      value: value.from_lovelace(17985570093),
      datum: NoDatum,
      reference_script: None,
    }
  let mint_tokens =
    value.from_asset(bond_pid, bond_name, issue_qty)
      |> value.add(nft_pid, bond_name, 1)
      |> value.to_minted_value()
  let tx_time =
    interval.between(
      slot_to_begin_posix_time(36304324, cfg.slot),
      slot_to_begin_posix_time(36304684, cfg.slot),
    )
  let tx =
    Transaction {
      // inputs: [input_01, input_02, input_03, input_04],
      inputs: [input_01, input_02],
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

  and {
    bond_nft.minting(
      cfg,
      tx,
      req_skh,
      bond_skh,
      nft_pid,
      req_pid,
      input_01.output_reference,
    ),
    bond_token.minting_without_fee(
      cfg,
      tx,
      req_skh,
      bond_skh,
      nft_pid,
      bond_pid,
      input_01.output_reference,
    ),
    bond_create.spending(
      cfg,
      ctx,
      sreq_dt,
      bond_skh,
      nft_pid,
      bond_pid,
      req_pid,
    ),
  }
}
