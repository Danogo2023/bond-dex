use aiken/dict
use aiken/list
use aiken/math
use aiken/transaction.{Input, Output, Transaction}
use aiken/transaction/credential.{ScriptCredential, VerificationKeyCredential}
use aiken/transaction/value.{AssetName, PolicyId}
use bond_issue/types.{BondIssueConfig, RequestDatum} as bond_issue_types

pub fn get_burn_token_names(tx: Transaction, pid: PolicyId) -> List<AssetName> {
  dict.foldl(
    value.from_minted_value(tx.mint) |> value.tokens(pid),
    [],
    fn(n, q, z) {
      if (q < 0)? {
        [n, ..z]
      } else {
        fail
      }
    },
  )
}

pub fn get_burn_nft_names(tx: Transaction, pid: PolicyId) -> List<AssetName> {
  dict.foldl(
    value.from_minted_value(tx.mint) |> value.tokens(pid),
    [],
    fn(n, q, z) {
      if (q == -1)? {
        [n, ..z]
      } else {
        fail
      }
    },
  )
}

pub fn get_input_by_nft_names(
  tx: Transaction,
  nft_names: List<AssetName>,
  nft_pid: PolicyId,
) -> List<Input> {
  list.filter(
    tx.inputs,
    fn(i) {
      when i.output.address.payment_credential is {
        VerificationKeyCredential(_) -> False
        ScriptCredential(_) -> True
      } && //
      when
        list.find(
          nft_names,
          fn(n) { value.quantity_of(i.output.value, nft_pid, n) == 1 },
        )
      is {
        Some(_) -> True
        _ -> False
      }
    },
  )
}

pub fn get_output_by_nft_names(
  tx: Transaction,
  nft_names: List<AssetName>,
  nft_pid: PolicyId,
) -> List<Output> {
  list.filter(
    tx.outputs,
    fn(o) {
      when
        list.find(
          nft_names,
          fn(n) { value.quantity_of(o.value, nft_pid, n) > 0 },
        )
      is {
        Some(_) -> True
        _ -> False
      }
    },
  )
}

pub fn check_output_request_base(
  cfg: BondIssueConfig,
  o: Output,
  oreq_dt: RequestDatum,
) -> Bool {
  and {
    (oreq_dt.apr >= cfg.platform.min_apr)?,
    (oreq_dt.duration >= cfg.platform.min_duration)?,
    (oreq_dt.requested >= cfg.platform.min_requested)?,
    (oreq_dt.buffer >= cfg.platform.min_buffer)?,
    (oreq_dt.prepaid >= math.min(
      oreq_dt.buffer + cfg.platform.prepaid_plus,
      oreq_dt.duration,
    ))?,
    (oreq_dt.prepaid <= oreq_dt.duration)?,
    (oreq_dt.fee >= cfg.platform.fee)?,
    
    (oreq_dt.epo_rewards >= ( oreq_dt.requested - oreq_dt.issued ) * cfg.platform.bond_face_value * oreq_dt.apr / cfg.basis.base / cfg.epoch.year_to_epoch)?,
    (value.lovelace_of(o.value) >= oreq_dt.epo_rewards * oreq_dt.prepaid)?,
  }
}
