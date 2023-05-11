use aiken/list
use aiken/option
use aiken/transaction.{Transaction}
use aiken/transaction/credential.{Address}
use bond/types.{BizTxInfo, Config, DatumTypeBidding}
use bond/utils.{collect_biz_tx_info, get_price_of_bond, must_be_signed_by}
use common/types.{PublicKeyHash} as common_types

fn calc_deposit(
  conf: Config,
  bidding_quantity: Int,
  bidding_requested_yield: Int,
) -> Int {
  // let principal_lovelace = bidding_quantity * conf.bond.bond_face_value
  let lender_interest_one_bond_lovelace =
    conf.bond.bond_face_value + conf.bond.bond_face_value * conf.market.bidding_yield * conf.market.bidding_duration / conf.bond.epoch_config.year_to_epoch / conf.bond.basis_points_ref_unit
  let price_of_one_bond =
    get_price_of_bond(
      lender_interest_one_bond_lovelace,
      conf.market.bidding_maturity_day,
      bidding_requested_yield,
      conf.bond.basis_points_ref_unit,
    )
  let received_diff =
    ( lender_interest_one_bond_lovelace - price_of_one_bond ) * bidding_quantity
  let market_fee_buyer =
    received_diff * conf.market.buyer_fee / conf.bond.basis_points_ref_unit
  lender_interest_one_bond_lovelace + market_fee_buyer
}

fn update_is_correct(
  conf: Config,
  tx: Transaction,
  owner: Address,
  smart_contract: Address,
  extra_signatories: List<PublicKeyHash>,
  bidding_quantity: Int,
  bidding_requested_yield: Int,
) -> Bool {
  let BizTxInfo { valid: biz_tx_info_valid, biz_input_obj, biz_output_obj } =
    collect_biz_tx_info(
      conf,
      tx.inputs,
      tx.outputs,
      owner,
      smart_contract,
      extra_signatories,
      tx.datums,
      False,
      DatumTypeBidding,
    )
  biz_tx_info_valid && when biz_output_obj is {
    None ->
      // trace @"biz_output_obj is None"
      False
    Some(biz_output) ->
      // trace @"biz_output_obj is Some"
      biz_output.smart_contract.lovelace >= calc_deposit(
        conf,
        bidding_quantity,
        bidding_requested_yield,
      )
  }
}

pub fn update(
  tx: Transaction,
  conf: Config,
  owner: Address,
  smart_contract: Address,
  bidding_quantity: Int,
  bidding_requested_yield: Int,
) -> Bool {
  let extra_signatories =
    list.at(tx.extra_signatories, 0)
      |> option.and_then(fn(a) { Some([a]) })
      |> option.or_else([])
  must_be_signed_by(extra_signatories, owner)? && update_is_correct(
    conf,
    tx,
    owner,
    smart_contract,
    extra_signatories,
    bidding_quantity,
    bidding_requested_yield,
  )
}
