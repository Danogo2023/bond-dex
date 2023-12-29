use aiken/bytearray
use aiken/cbor
use aiken/dict
use aiken/list
use aiken/math
use aiken/transaction.{Input, Output, Spend, Transaction}
use aiken/transaction/credential.{ScriptCredential, VerificationKeyCredential}
use aiken/transaction/value.{AssetName, PolicyId, Value}
use bond_issue/types.{BondIssueConfig, RequestDatum} as bond_issue_types
use common/util.{data_valid}
use issue_bond/types.{
  BondChangeStakeKey, BondCreate, BondIssueAction, BondPayInterest, BondRedeem,
  ForceRedeem, GarbageCollector, RedeemFee, RequestCreate, RequestUpdate,
} as issue_bond_types

fn get_garbage_collector_value(tx: Transaction) -> (Int, Value) {
  let garbage_out_refs =
    dict.foldr(
      tx.redeemers,
      [],
      fn(k, v, z) {
        when k is {
          Spend(r) -> {
            expect ac: BondIssueAction = v
            when ac is {
              GarbageCollector ->
                [r, ..z]
              RequestCreate { .. } -> fail @"RequestCreate found"
              RequestUpdate { .. } -> fail @"RequestUpdate found"
              BondCreate { .. } -> fail @"BondCreate found"
              BondRedeem { .. } -> fail @"BondRedeem found"
              BondPayInterest { .. } -> fail @"BondPayInterest found"
              BondChangeStakeKey { .. } -> fail @"BondChangeStakeKey found"
              RedeemFee { .. } -> fail @"RedeemFee found"
              ForceRedeem { .. } -> fail @"ForceRedeem found"
            }
          }
          _ -> z
        }
      },
    )
  list.foldr(
    tx.inputs,
    (0, value.zero()),
    fn(i, z) {
      if list.has(garbage_out_refs, i.output_reference) {
        (
          z.1st + value.lovelace_of(i.output.value),
          value.merge(z.2nd, value.without_lovelace(i.output.value)),
        )
      } else {
        z
      }
    },
  )
}

pub fn garbage_collector_request(
  d: Data,
  tx: Transaction,
  cfg: BondIssueConfig,
) -> Bool {
  let dt = cbor.diagnostic(d)
  let request_valid =
    if dt == @"121([])" {
      False
    } else {
      data_valid(
        bytearray.from_string(dt),
        "121([_ ",
        [", ", ", h'", "', h'", "', ", ", ", ", ", ", ", ", ", ", "],
        "])",
      )
    }
  if request_valid {
    fail @"its datum valid"
  } else {
    when
      list.find(tx.outputs, fn(o) { o.address == cfg.platform.garbage_addr })
    is {
      Some(o) -> {
        let (val, assets) = get_garbage_collector_value(tx)
        and {
          (value.lovelace_of(o.value) >= val)?,
          (value.without_lovelace(o.value) == assets)?,
        }
      }
      _ -> fail @"not found garbage address output"
    }
  }
}

pub fn garbage_collector_position(
  d: Data,
  tx: Transaction,
  cfg: BondIssueConfig,
) -> Bool {
  let dt = cbor.diagnostic(d)
  let bond_valid =
    if dt == @"121([])" {
      False
    } else {
      data_valid(
        bytearray.from_string(dt),
        "121([_ {_ h'': {_ h'': ",
        [
          " }, h'", "': {_ h'", "': ", " } }, ", ", h'", "', h'", "', ", ", ",
          ", ", ", h'", "', ",
        ],
        "])",
      )
    }
  if bond_valid {
    fail @"its datum valid"
  } else {
    when
      list.find(tx.outputs, fn(o) { o.address == cfg.platform.garbage_addr })
    is {
      Some(o) -> {
        let (val, assets) = get_garbage_collector_value(tx)
        and {
          (value.lovelace_of(o.value) >= val)?,
          (value.without_lovelace(o.value) == assets)?,
        }
      }
      _ -> fail @"not found garbage address output"
    }
  }
}

pub fn get_burn_token_names(tx: Transaction, pid: PolicyId) -> List<AssetName> {
  dict.foldr(
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
  dict.foldr(
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
