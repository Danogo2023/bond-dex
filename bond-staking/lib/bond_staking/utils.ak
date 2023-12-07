use aiken/dict
use aiken/math
use aiken/option
use aiken/transaction.{Transaction}
use aiken/transaction/value.{AssetName, PolicyId}
use bond_staking/types.{RequestConfig, RequestDatum}

pub fn request_output_valid(
  deposit: Int,
  dt: RequestDatum,
  cfg: RequestConfig,
) -> Bool {
  and {
    (dt.apr >= cfg.platform.min_apr)?,
    (dt.duration >= cfg.platform.min_duration)?,
    (dt.requested >= cfg.platform.min_requested)?,
    (dt.buffer >= cfg.platform.min_buffer)?,
    (dt.prepaid >= math.min(dt.buffer + cfg.platform.prepaid_plus, dt.duration))?,
    (dt.prepaid <= dt.duration)?,
    (dt.fee >= cfg.platform.fee)?,
    (dt.epo_rewards >= ( dt.requested - dt.issued ) * cfg.platform.bond_face_value * dt.apr / cfg.epoch.year_to_epoch / cfg.basis_points.base)?,
    (deposit >= dt.prepaid * dt.epo_rewards)?,
  }
}

pub fn mint_only_one(tx: Transaction, pid: PolicyId, tn: AssetName) -> Bool {
  let mint_assets = value.from_minted_value(tx.mint) |> value.tokens(pid)
  and {
    (dict.size(mint_assets) == 1)?,
    (option.or_else(dict.get(mint_assets, tn), 0) == 1)?,
  }
}
