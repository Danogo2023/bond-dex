use aiken/bytearray
use aiken/dict.{Dict}
use aiken/transaction.{OutputReference}
use aiken/transaction/credential.{Address}
use aiken/transaction/value.{AssetName, PolicyId}
use common/pvalue.{PValue} as common_value
use common/time.{BasisPoints, EpochConfig, SlotConfig}
use common/types.{AssetUnit, PublicKeyHash, ScriptKeyHash}

pub type ExchangeConfigLimit {
  fee_addr: Address,
  // value in range 0001 -> 9999 default: 1% per yield == 100
  buyer_fee: Int,
  // value in range 0001 -> 9999 default: 1% per yield == 100
  seller_fee: Int,
  // Khoảng thời gian giao dịch sell hợp lệ, giá trị tính theo slot
  tx_buy_ttl: Option<Int>,
}

pub type ExchangeConfigMaking {
  fee_addr: Address,
  // value in range 0001 -> 9999 default: 1% per yield == 100
  maker_fee: Int,
  // value in range 0001 -> 9999 default: 1% per yield == 100
  taker_fee: Int,
  // Time frame for valid transaction, value represent slot
  tx_buy_ttl: Option<Int>,
}

pub type BondType {
  DanogoBond
  OptimBond
}

// Dict<escrow_skh, (escrow_nft_pid, escrow_type)>
// { escrow_skh: ScriptKeyHash, escrow_nft_pid: PolicyId, escrow_type: BondType }
pub type EscrowConfigRaw =
  List<(ScriptKeyHash, (PolicyId, BondType))>

pub type EscrowConfig =
  Dict<ScriptKeyHash, (PolicyId, BondType)>

pub type EscrowRef =
  Dict<AssetUnit, EscrowInfo>

pub type PlatformConfig {
  slot: SlotConfig,
  epoch: EpochConfig,
  basis: BasisPoints,
  one_ada_2_lovelace: Int,
  // 1 bond = 100 ADA = 100_000_000 lovelace. default: 100 ADA = 100_000_000 lovelace
  bond_face_value: Int,
  min_ada: Int,
}

pub type BondConfigLimit {
  platform: PlatformConfig,
  escrow: EscrowConfig,
  exchange: ExchangeConfigLimit,
}

pub type BondConfigLimitRaw {
  platform: PlatformConfig,
  escrow: EscrowConfigRaw,
  exchange: ExchangeConfigLimit,
}

pub fn bond_config_limit_from_raw(self: BondConfigLimitRaw) {
  BondConfigLimit {
    platform: self.platform,
    exchange: self.exchange,
    escrow: dict.from_ascending_list(self.escrow, bytearray.compare),
  }
}

pub type BondConfigMaking {
  platform: PlatformConfig,
  escrow: EscrowConfig,
  exchange: ExchangeConfigMaking,
}

pub type BondConfigMakingRaw {
  platform: PlatformConfig,
  escrow: EscrowConfigRaw,
  exchange: ExchangeConfigMaking,
}

pub fn bond_config_making_from_raw(self: BondConfigMakingRaw) {
  BondConfigMaking {
    platform: self.platform,
    exchange: self.exchange,
    escrow: dict.from_ascending_list(self.escrow, bytearray.compare),
  }
}

pub type EscrowDatum {
  // PValue 'Sorted 'NoGuarantees: monthly lovelace value gain promised
  epo_rewards: PValue,
  // PEpochTime: duration of the loan in epochs
  duration: Int,
  // PCurrencySymbol
  bond_symbol: PolicyId,
  // PTokenName: token name of both Uniqueness and Ownership NFTs
  token_name: AssetName,
  // PInteger
  bond_amount: Int,
  // PEpochTime: number of epochs paid in advance
  buffer: Int,
  // PBasisPoints: Optim fee
  otm_fee: Int,
  // PPubKeyHash: used in staking the funds back to them
  og_lender: ByteArray,
  // PEpochTime
  start: Int,
}

pub type EscrowInfo {
  bond_symbol: PolicyId,
  token_name: AssetName,
  bond_amount: Int,
  start_epoch: Int,
  end_epoch: Int,
  value_at_maturity: Int,
  day_to_maturity: Int,
}

pub type PaymentDatum {
  output_reference: OutputReference,
}

pub type AskLimit {
  owner_vk: PublicKeyHash,
  owner_sk: Option<PublicKeyHash>,
  requested_yield: Int,
}

pub type EpochType {
  Absolute
  RelativeToCurrentEpoch
}

pub type BidLimitMulti {
  owner_vk: PublicKeyHash,
  owner_sk: Option<PublicKeyHash>,
  from_epoch: Int,
  to_epoch: Int,
  quantity: Int,
  requested_yield: Int,
  bond_types: List<BondType>,
}

pub type AskMaking {
  owner_vk: PublicKeyHash,
  owner_sk: Option<PublicKeyHash>,
  requested_yield: Int,
  bid_sc: ScriptKeyHash,
  margin: Int,
}

pub type BidMaking {
  owner_vk: PublicKeyHash,
  owner_sk: Option<PublicKeyHash>,
  from_epoch: Int,
  to_epoch: Int,
  quantity: Int,
  requested_yield: Int,
  ask_sc: ScriptKeyHash,
  margin: Int,
}

pub type TradeAction {
  Update
  Buy
  Sell
  Upgrade
  GarbageCollector
}

pub type AddressId =
  ByteArray
