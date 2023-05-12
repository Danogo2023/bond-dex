use aiken/dict.{Dict}
use aiken/transaction.{Output, OutputReference}
use aiken/transaction/credential.{Address, StakeCredential}
use aiken/transaction/value.{AssetName, Value}
use common/types.{SlotConfigNetwork}

pub type EpochConfig {
  // 1 year = 365 days / 5 days per epoch = 73 epoch. default: 73
  year_to_epoch: Int,
  // default: 1_647_899_091_000
  epoch_boundary: Int,
  // default: epoch 327+1
  epoch_boundary_as_epoch: Int,
  // Each Cardano epoch consists of a number of slots, where each slot lasts for one second
  // A Cardano epoch currently includes 432,000 slots (5 days)
  // mainnet: 432_000_000
  // preview: 1_800_000
  epoch_length: Int,
  // base is 5 days = 432_000_000
  epoch_length_base: Int,
}

pub type BondConfig {
  bond_policy_id: ByteArray,
  escrow_policy_id: ByteArray,
  // basis_points reference value, default: 10_000
  basis_points_ref_unit: Int,
  // range basis_points min = 1, max = 9_999
  basis_points_min: Int,
  basis_points_max: Int,
  one_ada_2_lovelace: Int,
  // 1 bond = 100 ADA = 100_000_000 lovelace. default: 100 ADA = 100_000_000 lovelace
  bond_face_value: Int,
  epoch_config: EpochConfig,
}

pub type MarketConfig {
  address: Address,
  // value in range 0001 -> 9999 default: 1% per yield == 100
  buyer_fee: Int,
  // value in range 0001 -> 9999 default: 1% per yield == 100
  seller_fee: Int,
  // yield for bidding caculate deposit to smart contract. value in range 0001 -> 9999 default: 1% per yield == 100
  bidding_yield: Int,
  bidding_duration: Int,
  bidding_maturity_day: Int,
  bidding_validity_time: Int,
}

pub type Config {
  bond: BondConfig,
  market: MarketConfig,
  slot_config_network: SlotConfigNetwork,
}

pub type EscrowDatum {
  // PValue 'Sorted 'NoGuarantees: monthly lovelace value gain promised
  epo_rewards: Value,
  // PEpochTime: duration of the loan in epochs
  duration: Int,
  // PCurrencySymbol
  bond_symbol: ByteArray,
  // PTokenName: token name of both Uniqueness and Ownership NFTs
  token_name: ByteArray,
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

pub type BondWriterDatum {
  epo_rewards: Value,
  duration: Int,
  bond_symbol: ByteArray,
  token_name: ByteArray,
  bond_amount: Int,
  buffer: Int,
  otmFee: Int,
  stake_key: StakeCredential,
  permissioned: Option<List<ByteArray>>,
}

pub type EscrowInfoResult<a, b> {
  OK(a)
  Error(b)
}

pub type EscrowInfo {
  received_at_maturity_one_bond: Int,
  day_to_maturity: Int,
}

pub type BizOutputInfo {
  addresses: List<Address>,
  bond_datum_valid: Bool,
  bond_outputs: List<Output>,
  bond_assets: Dict<AssetName, Int>,
  bond_qty: Int,
  lovelace: Int,
  other_outputs: List<Output>,
}

pub type BizOutput {
  valid: Bool,
  unique_bonds: Dict<AssetName, Int>,
  smart_contract: BizOutputInfo,
  owner: BizOutputInfo,
  market: BizOutputInfo,
  other: BizOutputInfo,
}

pub type BizTxInfo {
  valid: Bool,
  biz_input_obj: BizOutput,
  biz_output_obj: Option<BizOutput>,
}

pub type DatumType {
  DatumTypePayment
  DatumTypeListing
  DatumTypeBidding
}

pub type PaymentDatum {
  output_reference: OutputReference,
}

pub type ListingDatum {
  owner_payment_key: ByteArray,
  owner_stake_key: Option<ByteArray>,
  requested_yield: Int,
}

pub type BiddingDatum {
  owner_payment_key: ByteArray,
  owner_stake_key: Option<ByteArray>,
  from_epoch: Int,
  to_epoch: Int,
  quantity: Int,
  requested_yield: Int,
}

pub type TradeAction {
  Update
  Buy
  Sell
}
