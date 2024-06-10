use aiken/math
use bond/common/types.{AskLimit, AskMaking, BidLimitMulti, BidMaking}
use common/time.{BasisPoints, EpochTime}

pub fn yield_valid(basis: BasisPoints, v: Int) -> Bool {
  (math.clamp(v, basis.min, basis.max) == v)?
}

pub fn epoch_valid(epo_from: EpochTime, epo_to: EpochTime, out_qty: Int) -> Bool {
  and {
    (epo_from >= 0)?,
    (epo_to >= epo_from)?,
    (out_qty > 0)?,
  }
}

pub fn ask_limit_valid(left: AskLimit, right: AskLimit) -> Bool {
  and {
    (left.owner_vk == right.owner_vk)?,
    (left.owner_sk == right.owner_sk)?,
    (left.requested_yield == right.requested_yield)?,
  }
}

pub fn bid_limit_multi_valid(left: BidLimitMulti, right: BidLimitMulti) -> Bool {
  and {
    (left.owner_vk == right.owner_vk)?,
    (left.owner_sk == right.owner_sk)?,
    (left.from_epoch == right.from_epoch)?,
    (left.to_epoch == right.to_epoch)?,
    (left.requested_yield == right.requested_yield)?,
    (left.bond_types == right.bond_types)?,
  }
}

pub fn ask_making_valid(left: AskMaking, right: AskMaking) -> Bool {
  and {
    (left.owner_vk == right.owner_vk)?,
    (left.owner_sk == right.owner_sk)?,
    (left.requested_yield == right.requested_yield)?,
    (left.bid_sc == right.bid_sc)?,
    (left.margin == right.margin)?,
  }
}

pub fn bid_making_valid(left: BidMaking, right: BidMaking) -> Bool {
  and {
    (left.owner_vk == right.owner_vk)?,
    (left.owner_sk == right.owner_sk)?,
    (left.from_epoch == right.from_epoch)?,
    (left.to_epoch == right.to_epoch)?,
    (left.requested_yield == right.requested_yield)?,
    (left.ask_sc == right.ask_sc)?,
    (left.margin == right.margin)?,
  }
}
