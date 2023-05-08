use aiken/list
use aiken/option
use aiken/transaction.{Transaction}
use aiken/transaction/credential.{Address}
use bond/types.{BizOutput, BizTxInfo, Config}
use bond/utils.{collect_biz_tx_info, must_be_signed_by}
use common/types.{PublicKeyHash} as common_types

fn check_update_listing_correct(
  biz_input_obj: BizOutput,
  biz_output_obj: Option<BizOutput>,
) -> Bool {
  when biz_output_obj is {
    None ->
      // trace @"biz_output_obj is None"
      False
    Some(biz_output) ->
      // trace @"biz_output_obj is Some"
      when biz_output.smart_contract.bond_outputs is {
        [_, ..] -> {
          // trace @"update listing"
          let miss_qty_or_owner =
            biz_input_obj.smart_contract.bond_qty + biz_input_obj.owner.bond_qty == biz_output.smart_contract.bond_qty + biz_output.owner.bond_qty
          biz_output.smart_contract.bond_datum_valid? && miss_qty_or_owner?
        }
        [] ->
          // trace @"cancel listing"
          (biz_output.owner.bond_qty == biz_input_obj.smart_contract.bond_qty + biz_input_obj.owner.bond_qty)?
      }
  }
}

fn update_listing_correct(
  conf: Config,
  tx: Transaction,
  owner: Address,
  smart_contract: Address,
  extra_signatories: List<PublicKeyHash>,
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
    )
  biz_tx_info_valid && check_update_listing_correct(
    biz_input_obj,
    biz_output_obj,
  )
}

pub fn update_listing(
  tx: Transaction,
  conf: Config,
  owner: Address,
  smart_contract: Address,
) -> Bool {
  let extra_signatories =
    list.at(tx.extra_signatories, 0)
      |> option.and_then(fn(a) { Some([a]) })
      |> option.or_else([])
  must_be_signed_by(extra_signatories, owner)? && update_listing_correct(
    conf,
    tx,
    owner,
    smart_contract,
    extra_signatories,
  )
}
