use aiken/list
use aiken/transaction.{Input, OutputReference, Transaction}
use aiken/transaction/credential.{Address}
use aiken/transaction/value.{PolicyId}
use bond_issue/types.{BondDatum, BondIssueConfig} as bond_issue_types
use borrow_position/utils_nft
use borrow_position/utils_spend
use borrow_position/utils_token
use common/types.{ScriptKeyHash} as common_types

pub fn minting_nft(
  tx: Transaction,
  out_ref: OutputReference,
  req_sk: ScriptKeyHash,
  bond_sk: ScriptKeyHash,
  nft_pid: PolicyId,
) -> Bool {
  let ireq = utils_nft.get_borrow_request_input(tx, out_ref, req_sk)
  let obond = utils_nft.get_bond_output(tx, nft_pid, bond_sk)
  let mint_value = value.from_minted_value(tx.mint)
  let mint_nft = utils_nft.get_mint(mint_value, nft_pid)
  and {
    // must found bond output
    (obond.count > 0)?,
    // must found mint nft
    (mint_nft.count > 0)?,
    (obond.count == mint_nft.count)?,
    // request input count must equal bond output count
    (ireq.count > 0)?,
    (obond.count == ireq.count)?,
    // bond nft in output must matching with bond nft minting
    (list.at(list.difference(mint_nft.names, obond.names), 0) == None)?,
    // bond name in bond output must matching with bond name of request input
    (list.at(list.difference(ireq.names, obond.names), 0) == None)?,
  }
}

pub fn burning_nft(
  tx: Transaction,
  nft_pid: PolicyId,
  bond_pid: PolicyId,
) -> Bool {
  let mint_value = value.from_minted_value(tx.mint)
  let burning = utils_nft.get_name_burn(mint_value, nft_pid)
  //
  let input = utils_nft.get_name_inputs(tx, nft_pid, bond_pid)
  //
  let output = utils_nft.get_name_outputs(tx, nft_pid, bond_pid)
  //
  let maintain = list.difference(input, output)
  //
  let burned = list.difference(input, maintain)
  //
  // nft burned of output must matching with bond nft burning
  (list.at(list.difference(burning, burned), 0) == None)?
}

pub fn minting_token(
  cfg: BondIssueConfig,
  tx: Transaction,
  out_ref: OutputReference,
  req_sk: ScriptKeyHash,
  bond_sk: ScriptKeyHash,
  nft_pid: PolicyId,
  bond_pid: PolicyId,
) -> Bool {
  let (ireq_token, ireq_data) =
    utils_token.get_borrow_request_input(tx, out_ref, req_sk)
  let (obond_token, obond_data, obond_fee) =
    utils_token.get_bond_output(cfg, tx, nft_pid, bond_sk)
  let mint_value = value.from_minted_value(tx.mint)
  let (nft_mint, _, bond_assets, bond_names) =
    utils_token.get_mint(mint_value, nft_pid, bond_pid)
  and {
    // must found bond output
    (obond_token.count > 0)?,
    // must found mint nft
    (nft_mint.count > 0)?,
    (obond_token.count == nft_mint.count)?,
    // request input count must equal bond output count
    (ireq_token.count > 0)?,
    (obond_token.count == ireq_token.count)?,
    // bond nft in output must matching with bond nft minting
    (list.at(list.difference(nft_mint.names, obond_token.names), 0) == None)?,
    // bond name in bond output must matching with bond name of request input
    (list.at(list.difference(ireq_token.names, obond_token.names), 0) == None)?,
    // bond nft in output must matching with bond token minting
    (list.at(list.difference(nft_mint.names, bond_names), 0) == None)?,
    // not found platform fee output
    (obond_fee != None)?,
    // must pay the correct fees to the platform
    utils_token.fee_valid(cfg, ireq_data, obond_data, bond_assets, obond_fee),
  }
}

pub fn burning_token(
  tx: Transaction,
  nft_pid: PolicyId,
  bond_pid: PolicyId,
) -> Bool {
  let mint_value = value.from_minted_value(tx.mint)
  let bond_burning = utils_token.get_burn(mint_value, bond_pid)
  //
  let input_nft = utils_nft.get_name_inputs(tx, nft_pid, bond_pid)
  //
  let output_nft = utils_nft.get_name_outputs(tx, nft_pid, bond_pid)
  //
  let maintain_nft = list.difference(input_nft, output_nft)
  //
  let burned_nft = list.difference(input_nft, maintain_nft)
  and {
    (bond_burning.count > 0)?,
    (list.at(list.difference(bond_burning.names, burned_nft), 0) == None)?,
  }
}

pub fn spending_pay_interest(
  cfg: BondIssueConfig,
  tx: Transaction,
  sbond_addr: Address,
) -> Bool {
  // let ibond_lovelace = value.lovelace_of(sbond.output.value)
  let (ibond_count, ibond_keys, ibond_utxos) =
    utils_spend.get_bond_inputs(tx, sbond_addr)
  let (obond_count, obond_keys, obond_utxos, ofee) =
    utils_spend.get_bond_outputs(cfg, tx, sbond_addr)

  and {
    (ofee != None)?,
    (ibond_count > 0)?,
    (obond_count > 0)?,
    (ibond_count == obond_count)?,
    (list.at(list.difference(ibond_keys, obond_keys), 0) == None)?,
    utils_spend.fee_pay_interest_valid(cfg, ibond_utxos, obond_utxos, ofee),
  }
}

pub fn spending_change_stake_key(
  tx: Transaction,
  sbond: Input,
  sbond_addr: Address,
  sbond_dt: BondDatum,
  req_pid: PolicyId,
) -> Bool {
  when
    list.find(
      tx.inputs,
      fn(i) {
        value.quantity_of(i.output.value, req_pid, sbond_dt.borrower) == 1
      },
    )
  is {
    Some(_) ->
      utils_spend.change_stake_key_valid(tx, sbond.output, sbond_addr, sbond_dt)
    _ ->
      fail @"borrow_position/constraint.spending_change_stake_key: not found borrower nft of bond utxo"
  }
}

pub fn spending_redeem(
  cfg: BondIssueConfig,
  tx: Transaction,
  sbond: Input,
  sbond_addr: Address,
  sbond_dt: BondDatum,
  nft_pid: PolicyId,
) -> Bool {
  and {
    utils_spend.bond_violate(cfg, tx, sbond.output, sbond_dt),
    utils_spend.redeem_valid(tx, sbond.output, sbond_addr, sbond_dt, nft_pid),
  }
}
