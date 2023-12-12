use aiken/list
use aiken/transaction.{OutputReference, Transaction}
use aiken/transaction/value.{PolicyId}
use bond_issue/types.{BondIssueConfig} as bond_issue_types
use borrow_position/utils_nft
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
    (list.length(list.difference(mint_nft.names, obond.names)) <= 0)?,
    // bond name in bond output must matching with bond name of request input
    (list.length(list.difference(ireq.names, obond.names)) <= 0)?,
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
  (list.length(list.difference(burning, burned)) <= 0)?
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
    (list.length(list.difference(nft_mint.names, obond_token.names)) <= 0)?,
    // bond name in bond output must matching with bond name of request input
    (list.length(list.difference(ireq_token.names, obond_token.names)) <= 0)?,
    // bond nft in output must matching with bond token minting
    (list.length(list.difference(nft_mint.names, bond_names)) <= 0)?,
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
    (list.length(list.difference(bond_burning.names, burned_nft)) <= 0)?,
  }
}
