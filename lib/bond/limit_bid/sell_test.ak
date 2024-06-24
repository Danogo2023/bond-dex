// Bid Limit
use aiken/bytearray
use aiken/cbor
use aiken/dict
use aiken/interval.{entirely_between}
use aiken/string
use aiken/transaction.{
  DatumHash, InlineDatum, Input, NoDatum, Output, OutputReference, ScriptContext,
  ScriptPurpose, Spend, Transaction, TransactionId,
}
use aiken/transaction/credential.{
  Address, from_script, from_verification_key, with_delegation_key,
  with_delegation_script,
}
use aiken/transaction/value
use bond/common/fixture.{
  calc_escrow_full_info, gen_bid_limit_multi_datum, gen_input, gen_output,
  get_bond_id_1, get_bond_policy_id, get_buyer_address, get_buyer_address_hash,
  get_config_limit_mainnet, get_config_limit_preview, get_escrow_address,
  get_escrow_address_unexpect, get_escrow_datum, get_escrow_policy_id,
  get_exchange_address, get_input_escrow, get_not_bond_policy_id,
  get_not_escrow_policy_id, get_seller_address,
}
use bond/common/types.{
  BidLimitMulti, BondConfigLimit, DanogoBond, ExchangeConfigLimit, OptimBond,
}
use bond/common/utils.{get_price_of_bond}
use bond/limit_bid/types.{Sell} as dtypes
use bond/limit_bid/withdraw
use bond_issue/types.{BondDatum, RequestDatum} as bond_issue_types
use common/pvalue
use common/time.{slot_to_begin_posix_time}

const min_ada = 2_000_000

const bid_skh = "bid_1"

pub fn get_bid_sc_address() -> Address {
  from_script(bid_skh)
}

fn script_purpose_compare(a: ScriptPurpose, b: ScriptPurpose) {
  bytearray.compare(
    cbor.diagnostic(a) |> string.to_bytearray,
    cbor.diagnostic(b) |> string.to_bytearray,
  )
}

test succ_full() {
  let time_of_tx = 1681095094000
  let cfg = get_config_limit_mainnet()
  let owner_address = get_buyer_address()
  let seller_address = get_seller_address()
  let sc_in_datum_1 =
    gen_bid_limit_multi_datum(
      owner_address,
      390,
      480,
      5,
      500,
      [DanogoBond, OptimBond],
    )
  let bond_name_1 = get_bond_id_1()
  // get_escrow_datum(asset_name: AssetName, bond_amount: Int, epo_rewards: Int, duration: Int, start: Int)
  let escrow_bond_amount = 10000
  let escrow_epo_rewards = 753424657
  let escrow_duration = 72
  let escrow_datum =
    get_escrow_datum(
      bond_name_1,
      escrow_bond_amount,
      escrow_epo_rewards,
      escrow_duration,
      63,
    )
  // => epoch_start = 22190 epoch_end = 22244
  let escrow_lovelace =
    escrow_bond_amount * 100_000_000 + escrow_epo_rewards * escrow_duration
  let escrow_full_info =
    calc_escrow_full_info(
      cfg.platform,
      escrow_lovelace,
      escrow_datum,
      time_of_tx,
    )
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  //  
  let bond_sell_qty = 5
  let received_at_maturity = escrow_full_info.value_at_maturity * bond_sell_qty
  let received_with_yield = price_of_one_bond * bond_sell_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.seller_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.platform.basis.base
  //
  let owner_out_lovelace = min_ada
  let sc_address = get_bid_sc_address()
  let sc_in_lovelace =
    received_with_yield + exchange_fee_buyer + owner_out_lovelace
  let sc_in_1 =
    gen_input(sc_address, sc_in_lovelace, None, InlineDatum(sc_in_datum_1))
  let seller_in_lovelace = 1310316
  let asset_sell =
    value.from_asset(get_bond_policy_id(), bond_name_1, bond_sell_qty)
  let seller_in_1 =
    gen_input(seller_address, seller_in_lovelace, Some(asset_sell), NoDatum)
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_1,
      1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  //
  let exchange_address = get_exchange_address()
  let exchange_out_lovelace = exchange_fee_buyer + exchange_fee_seller
  let exchange_out_1 =
    gen_output(exchange_address, exchange_out_lovelace, None, NoDatum)
  let seller_out_lovelace =
    seller_in_lovelace + received_with_yield - exchange_fee_seller
  let seller_out_1 =
    gen_output(seller_address, seller_out_lovelace, None, NoDatum)
  let owner_out_1 =
    gen_output(owner_address, owner_out_lovelace, Some(asset_sell), NoDatum)
  let txn =
    fixture.tx(
      [sc_in_1, seller_in_1],
      [refer_in_1],
      [exchange_out_1, seller_out_1, owner_out_1],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  let seller_receive = received_with_yield - exchange_fee_seller
  let tx =
    Transaction {
      ..txn,
      redeemers: dict.insert(
        txn.redeemers,
        Spend(sc_in_1.output_reference),
        Sell {
          exchange_fee: exchange_out_lovelace,
          seller_receive,
          offers: [(get_bond_policy_id(), bond_name_1, bond_sell_qty)],
          cont_idx: None,
        },
        script_purpose_compare,
      ),
    }
  withdraw.constraint(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    bid_skh,
    [],
  )
}

test succ_partial() {
  let time_of_tx = 1681095094000
  let cfg = get_config_limit_mainnet()
  let owner_address = get_buyer_address()
  let seller_address = get_seller_address()
  let sc_in_datum_1 =
    gen_bid_limit_multi_datum(
      owner_address,
      390,
      480,
      5,
      500,
      [DanogoBond, OptimBond],
    )
  let bond_name_1 = get_bond_id_1()
  // get_escrow_datum(asset_name: AssetName, bond_amount: Int, epo_rewards: Int, duration: Int, start: Int)
  let escrow_bond_amount = 10000
  let escrow_epo_rewards = 753424657
  let escrow_duration = 72
  let escrow_datum =
    get_escrow_datum(
      bond_name_1,
      escrow_bond_amount,
      escrow_epo_rewards,
      escrow_duration,
      63,
    )
  // => epoch_start = 22190 epoch_end = 22244
  let escrow_lovelace =
    escrow_bond_amount * 100_000_000 + escrow_epo_rewards * escrow_duration
  let escrow_full_info =
    calc_escrow_full_info(
      cfg.platform,
      escrow_lovelace,
      escrow_datum,
      time_of_tx,
    )
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  //  
  let bond_sell_qty = 2
  let received_at_maturity = escrow_full_info.value_at_maturity * bond_sell_qty
  let received_with_yield = price_of_one_bond * bond_sell_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.seller_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.platform.basis.base
  //
  let owner_out_lovelace = min_ada
  let sc_address = get_bid_sc_address()
  let sc_in_lovelace = received_with_yield + exchange_fee_buyer + 10000000
  let sc_in_1 =
    gen_input(sc_address, sc_in_lovelace, None, InlineDatum(sc_in_datum_1))
  let seller_in_lovelace = min_ada
  let asset_sell =
    value.from_asset(get_bond_policy_id(), bond_name_1, bond_sell_qty)
  let seller_in_1 =
    gen_input(seller_address, seller_in_lovelace, Some(asset_sell), NoDatum)
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_1,
      1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  //
  let exchange_address = get_exchange_address()
  let exchange_out_lovelace = exchange_fee_buyer + exchange_fee_seller
  let exchange_out_1 =
    gen_output(exchange_address, exchange_out_lovelace, None, NoDatum)
  let seller_out_lovelace =
    seller_in_lovelace + received_with_yield - exchange_fee_seller
  let seller_out_1 =
    gen_output(seller_address, seller_out_lovelace, None, NoDatum)
  let owner_out_1 =
    gen_output(owner_address, owner_out_lovelace, Some(asset_sell), NoDatum)
  let sc_out_lovelace =
    sc_in_lovelace - received_with_yield - exchange_fee_buyer - owner_out_lovelace
  let sc_out_datum_1 =
    gen_bid_limit_multi_datum(
      owner_address,
      390,
      480,
      sc_in_datum_1.quantity - bond_sell_qty,
      500,
      [DanogoBond, OptimBond],
    )
  let sc_out_utxo =
    gen_output(sc_address, sc_out_lovelace, None, InlineDatum(sc_out_datum_1))
  let txn =
    fixture.tx(
      [sc_in_1, seller_in_1],
      [refer_in_1],
      [exchange_out_1, seller_out_1, owner_out_1, sc_out_utxo],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  let seller_receive = received_with_yield - exchange_fee_seller
  let tx =
    Transaction {
      ..txn,
      redeemers: dict.insert(
        txn.redeemers,
        Spend(sc_in_1.output_reference),
        Sell {
          exchange_fee: exchange_out_lovelace,
          seller_receive,
          offers: [(get_bond_policy_id(), bond_name_1, bond_sell_qty)],
          cont_idx: Some(3),
        },
        script_purpose_compare,
      ),
    }
  withdraw.constraint(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    bid_skh,
    [],
  )
}

test fail_input_epoch_1() fail {
  let time_of_tx = 1681095094000
  let cfg = get_config_limit_mainnet()
  let owner_address = get_buyer_address()
  let seller_address = get_seller_address()
  let sc_in_datum_1 =
    gen_bid_limit_multi_datum(
      owner_address,
      480,
      390,
      5,
      500,
      [DanogoBond, OptimBond],
    )
  let bond_name_1 = get_bond_id_1()
  // get_escrow_datum(asset_name: AssetName, bond_amount: Int, epo_rewards: Int, duration: Int, start: Int)
  let escrow_bond_amount = 10000
  let escrow_epo_rewards = 753424657
  let escrow_duration = 72
  let escrow_datum =
    get_escrow_datum(
      bond_name_1,
      escrow_bond_amount,
      escrow_epo_rewards,
      escrow_duration,
      63,
    )
  // => epoch_start = 22190 epoch_end = 22244
  let escrow_lovelace =
    escrow_bond_amount * 100_000_000 + escrow_epo_rewards * escrow_duration
  let escrow_full_info =
    calc_escrow_full_info(
      cfg.platform,
      escrow_lovelace,
      escrow_datum,
      time_of_tx,
    )
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  //  
  let bond_sell_qty = 5
  let received_at_maturity = escrow_full_info.value_at_maturity * bond_sell_qty
  let received_with_yield = price_of_one_bond * bond_sell_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.seller_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.platform.basis.base
  //
  let owner_out_lovelace = 1310316
  let sc_address = get_bid_sc_address()
  let sc_in_lovelace =
    received_with_yield + exchange_fee_buyer + owner_out_lovelace
  let sc_in_1 =
    gen_input(sc_address, sc_in_lovelace, None, InlineDatum(sc_in_datum_1))
  let seller_in_lovelace = 1310316
  let asset_sell =
    value.from_asset(get_bond_policy_id(), bond_name_1, bond_sell_qty)
  let seller_in_1 =
    gen_input(seller_address, seller_in_lovelace, Some(asset_sell), NoDatum)
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_1,
      1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  //
  let exchange_address = get_exchange_address()
  let exchange_out_lovelace = exchange_fee_buyer + exchange_fee_seller
  let exchange_out_1 =
    gen_output(exchange_address, exchange_out_lovelace, None, NoDatum)
  let seller_out_lovelace =
    seller_in_lovelace + received_with_yield - exchange_fee_seller
  let seller_out_1 =
    gen_output(seller_address, seller_out_lovelace, None, NoDatum)
  let owner_out_1 =
    gen_output(owner_address, owner_out_lovelace, Some(asset_sell), NoDatum)
  let sc_out_lovelace =
    sc_in_lovelace - received_with_yield - exchange_fee_buyer - owner_out_lovelace
  let sc_out_datum_1 =
    gen_bid_limit_multi_datum(
      owner_address,
      390,
      480,
      sc_in_datum_1.quantity - bond_sell_qty,
      500,
      [DanogoBond, OptimBond],
    )
  let sc_out_utxo =
    gen_output(sc_address, sc_out_lovelace, None, InlineDatum(sc_out_datum_1))
  let txn =
    fixture.tx(
      [sc_in_1, seller_in_1],
      [refer_in_1],
      [exchange_out_1, seller_out_1, owner_out_1, sc_out_utxo],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  let seller_receive = received_with_yield - exchange_fee_seller
  let tx =
    Transaction {
      ..txn,
      redeemers: dict.insert(
        txn.redeemers,
        Spend(sc_in_1.output_reference),
        Sell {
          exchange_fee: exchange_out_lovelace,
          seller_receive,
          offers: [(get_bond_policy_id(), bond_name_1, bond_sell_qty)],
          cont_idx: None,
        },
        script_purpose_compare,
      ),
    }
  withdraw.constraint(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    bid_skh,
    [],
  )
}

test fail_input_epoch_2() fail {
  let time_of_tx = 1681095094000
  let cfg = get_config_limit_mainnet()
  let owner_address = get_buyer_address()
  let seller_address = get_seller_address()
  let sc_in_datum_1 =
    gen_bid_limit_multi_datum(
      owner_address,
      464,
      480,
      5,
      500,
      [DanogoBond, OptimBond],
    )
  let bond_name_1 = get_bond_id_1()
  // get_escrow_datum(asset_name: AssetName, bond_amount: Int, epo_rewards: Int, duration: Int, start: Int)
  let escrow_bond_amount = 10000
  let escrow_epo_rewards = 753424657
  let escrow_duration = 72
  let escrow_datum =
    get_escrow_datum(
      bond_name_1,
      escrow_bond_amount,
      escrow_epo_rewards,
      escrow_duration,
      63,
    )
  // => epoch_start = 22190 epoch_end = 22244
  let escrow_lovelace =
    escrow_bond_amount * 100_000_000 + escrow_epo_rewards * escrow_duration
  let escrow_full_info =
    calc_escrow_full_info(
      cfg.platform,
      escrow_lovelace,
      escrow_datum,
      time_of_tx,
    )
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  //  
  let bond_sell_qty = 5
  let received_at_maturity = escrow_full_info.value_at_maturity * bond_sell_qty
  let received_with_yield = price_of_one_bond * bond_sell_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.seller_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.platform.basis.base
  //
  let owner_out_lovelace = 1310316
  let sc_address = get_bid_sc_address()
  let sc_in_lovelace =
    received_with_yield + exchange_fee_buyer + owner_out_lovelace
  let sc_in_1 =
    gen_input(sc_address, sc_in_lovelace, None, InlineDatum(sc_in_datum_1))
  let seller_in_lovelace = 1310316
  let asset_sell =
    value.from_asset(get_bond_policy_id(), bond_name_1, bond_sell_qty)
  let seller_in_1 =
    gen_input(seller_address, seller_in_lovelace, Some(asset_sell), NoDatum)
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_1,
      1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  //
  let exchange_address = get_exchange_address()
  let exchange_out_lovelace = exchange_fee_buyer + exchange_fee_seller
  let exchange_out_1 =
    gen_output(exchange_address, exchange_out_lovelace, None, NoDatum)
  let seller_out_lovelace =
    seller_in_lovelace + received_with_yield - exchange_fee_seller
  let seller_out_1 =
    gen_output(seller_address, seller_out_lovelace, None, NoDatum)
  let owner_out_1 =
    gen_output(owner_address, owner_out_lovelace, Some(asset_sell), NoDatum)
  let sc_out_lovelace =
    sc_in_lovelace - received_with_yield - exchange_fee_buyer - owner_out_lovelace
  let sc_out_datum_1 =
    gen_bid_limit_multi_datum(
      owner_address,
      390,
      480,
      sc_in_datum_1.quantity - bond_sell_qty,
      500,
      [DanogoBond, OptimBond],
    )
  let sc_out_utxo =
    gen_output(sc_address, sc_out_lovelace, None, InlineDatum(sc_out_datum_1))
  let txn =
    fixture.tx(
      [sc_in_1, seller_in_1],
      [refer_in_1],
      [exchange_out_1, seller_out_1, owner_out_1, sc_out_utxo],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  let seller_receive = received_with_yield - exchange_fee_seller
  let tx =
    Transaction {
      ..txn,
      redeemers: dict.insert(
        txn.redeemers,
        Spend(sc_in_1.output_reference),
        Sell {
          exchange_fee: exchange_out_lovelace,
          seller_receive,
          offers: [(get_bond_policy_id(), bond_name_1, bond_sell_qty)],
          cont_idx: None,
        },
        script_purpose_compare,
      ),
    }
  withdraw.constraint(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    bid_skh,
    [],
  )
}

test fail_input_epoch_3() fail {
  let time_of_tx = 1681095094000
  let cfg = get_config_limit_mainnet()
  let owner_address = get_buyer_address()
  let seller_address = get_seller_address()
  let sc_in_datum_1 =
    gen_bid_limit_multi_datum(
      owner_address,
      390,
      462,
      5,
      500,
      [DanogoBond, OptimBond],
    )
  let bond_name_1 = get_bond_id_1()
  // get_escrow_datum(asset_name: AssetName, bond_amount: Int, epo_rewards: Int, duration: Int, start: Int)
  let escrow_bond_amount = 10000
  let escrow_epo_rewards = 753424657
  let escrow_duration = 72
  let escrow_datum =
    get_escrow_datum(
      bond_name_1,
      escrow_bond_amount,
      escrow_epo_rewards,
      escrow_duration,
      63,
    )
  // => epoch_start = 22190 epoch_end = 22244
  let escrow_lovelace =
    escrow_bond_amount * 100_000_000 + escrow_epo_rewards * escrow_duration
  let escrow_full_info =
    calc_escrow_full_info(
      cfg.platform,
      escrow_lovelace,
      escrow_datum,
      time_of_tx,
    )
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  //  
  let bond_sell_qty = 5
  let received_at_maturity = escrow_full_info.value_at_maturity * bond_sell_qty
  let received_with_yield = price_of_one_bond * bond_sell_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.seller_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.platform.basis.base
  //
  let owner_out_lovelace = 1310316
  let sc_address = get_bid_sc_address()
  let sc_in_lovelace =
    received_with_yield + exchange_fee_buyer + owner_out_lovelace
  let sc_in_1 =
    gen_input(sc_address, sc_in_lovelace, None, InlineDatum(sc_in_datum_1))
  let seller_in_lovelace = 1310316
  let asset_sell =
    value.from_asset(get_bond_policy_id(), bond_name_1, bond_sell_qty)
  let seller_in_1 =
    gen_input(seller_address, seller_in_lovelace, Some(asset_sell), NoDatum)
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_1,
      1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  //
  let exchange_address = get_exchange_address()
  let exchange_out_lovelace = exchange_fee_buyer + exchange_fee_seller
  let exchange_out_1 =
    gen_output(exchange_address, exchange_out_lovelace, None, NoDatum)
  let seller_out_lovelace =
    seller_in_lovelace + received_with_yield - exchange_fee_seller
  let seller_out_1 =
    gen_output(seller_address, seller_out_lovelace, None, NoDatum)
  let owner_out_1 =
    gen_output(owner_address, owner_out_lovelace, Some(asset_sell), NoDatum)
  let sc_out_lovelace =
    sc_in_lovelace - received_with_yield - exchange_fee_buyer - owner_out_lovelace
  let sc_out_datum_1 =
    gen_bid_limit_multi_datum(
      owner_address,
      390,
      480,
      sc_in_datum_1.quantity - bond_sell_qty,
      500,
      [DanogoBond, OptimBond],
    )
  let sc_out_utxo =
    gen_output(sc_address, sc_out_lovelace, None, InlineDatum(sc_out_datum_1))
  let txn =
    fixture.tx(
      [sc_in_1, seller_in_1],
      [refer_in_1],
      [exchange_out_1, seller_out_1, owner_out_1, sc_out_utxo],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  let seller_receive = received_with_yield - exchange_fee_seller
  let tx =
    Transaction {
      ..txn,
      redeemers: dict.insert(
        txn.redeemers,
        Spend(sc_in_1.output_reference),
        Sell {
          exchange_fee: exchange_out_lovelace,
          seller_receive,
          offers: [(get_bond_policy_id(), bond_name_1, bond_sell_qty)],
          cont_idx: None,
        },
        script_purpose_compare,
      ),
    }
  withdraw.constraint(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    bid_skh,
    [],
  )
}

test fail_input_epoch_4() fail {
  let time_of_tx = 1681095094000 + 25920000000
  let cfg = get_config_limit_mainnet()
  let owner_address = get_buyer_address()
  let seller_address = get_seller_address()
  let sc_in_datum_1 =
    gen_bid_limit_multi_datum(
      owner_address,
      390,
      462,
      5,
      500,
      [DanogoBond, OptimBond],
    )
  let bond_name_1 = get_bond_id_1()
  // get_escrow_datum(asset_name: AssetName, bond_amount: Int, epo_rewards: Int, duration: Int, start: Int)
  let escrow_bond_amount = 10000
  let escrow_epo_rewards = 753424657
  let escrow_duration = 72
  let escrow_datum =
    get_escrow_datum(
      bond_name_1,
      escrow_bond_amount,
      escrow_epo_rewards,
      escrow_duration,
      63,
    )
  // => epoch_start = 22190 epoch_end = 22244
  let escrow_lovelace =
    escrow_bond_amount * 100_000_000 + escrow_epo_rewards * escrow_duration
  let escrow_full_info =
    calc_escrow_full_info(
      cfg.platform,
      escrow_lovelace,
      escrow_datum,
      time_of_tx,
    )
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  //  
  let bond_sell_qty = 5
  let received_at_maturity = escrow_full_info.value_at_maturity * bond_sell_qty
  let received_with_yield = price_of_one_bond * bond_sell_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.seller_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.platform.basis.base
  //
  let owner_out_lovelace = 1310316
  let sc_address = get_bid_sc_address()
  let sc_in_lovelace =
    received_with_yield + exchange_fee_buyer + owner_out_lovelace
  let sc_in_1 =
    gen_input(sc_address, sc_in_lovelace, None, InlineDatum(sc_in_datum_1))
  let seller_in_lovelace = 1310316
  let asset_sell =
    value.from_asset(get_bond_policy_id(), bond_name_1, bond_sell_qty)
  let seller_in_1 =
    gen_input(seller_address, seller_in_lovelace, Some(asset_sell), NoDatum)
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_1,
      1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  //
  let exchange_address = get_exchange_address()
  let exchange_out_lovelace = exchange_fee_buyer + exchange_fee_seller
  let exchange_out_1 =
    gen_output(exchange_address, exchange_out_lovelace, None, NoDatum)
  let seller_out_lovelace =
    seller_in_lovelace + received_with_yield - exchange_fee_seller
  let seller_out_1 =
    gen_output(seller_address, seller_out_lovelace, None, NoDatum)
  let owner_out_1 =
    gen_output(owner_address, owner_out_lovelace, Some(asset_sell), NoDatum)
  let sc_out_lovelace =
    sc_in_lovelace - received_with_yield - exchange_fee_buyer - owner_out_lovelace
  let sc_out_datum_1 =
    gen_bid_limit_multi_datum(
      owner_address,
      390,
      480,
      sc_in_datum_1.quantity - bond_sell_qty,
      500,
      [DanogoBond, OptimBond],
    )
  let sc_out_utxo =
    gen_output(sc_address, sc_out_lovelace, None, InlineDatum(sc_out_datum_1))
  let txn =
    fixture.tx(
      [sc_in_1, seller_in_1],
      [refer_in_1],
      [exchange_out_1, seller_out_1, owner_out_1, sc_out_utxo],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  let seller_receive = received_with_yield - exchange_fee_seller
  let tx =
    Transaction {
      ..txn,
      redeemers: dict.insert(
        txn.redeemers,
        Spend(sc_in_1.output_reference),
        Sell {
          exchange_fee: exchange_out_lovelace,
          seller_receive,
          offers: [(get_bond_policy_id(), bond_name_1, bond_sell_qty)],
          cont_idx: None,
        },
        script_purpose_compare,
      ),
    }
  withdraw.constraint(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    bid_skh,
    [],
  )
}

test fail_input_qty() fail {
  let time_of_tx = 1681095094000
  let cfg = get_config_limit_mainnet()
  let owner_address = get_buyer_address()
  let seller_address = get_seller_address()
  let sc_in_datum_1 =
    gen_bid_limit_multi_datum(
      owner_address,
      390,
      480,
      0,
      500,
      [DanogoBond, OptimBond],
    )
  let bond_name_1 = get_bond_id_1()
  // get_escrow_datum(asset_name: AssetName, bond_amount: Int, epo_rewards: Int, duration: Int, start: Int)
  let escrow_bond_amount = 10000
  let escrow_epo_rewards = 753424657
  let escrow_duration = 72
  let escrow_datum =
    get_escrow_datum(
      bond_name_1,
      escrow_bond_amount,
      escrow_epo_rewards,
      escrow_duration,
      63,
    )
  // => epoch_start = 22190 epoch_end = 22244
  let escrow_lovelace =
    escrow_bond_amount * 100_000_000 + escrow_epo_rewards * escrow_duration
  let escrow_full_info =
    calc_escrow_full_info(
      cfg.platform,
      escrow_lovelace,
      escrow_datum,
      time_of_tx,
    )
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  //  
  let bond_sell_qty = 5
  let received_at_maturity = escrow_full_info.value_at_maturity * bond_sell_qty
  let received_with_yield = price_of_one_bond * bond_sell_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.seller_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.platform.basis.base
  //
  let owner_out_lovelace = min_ada
  let sc_address = get_bid_sc_address()
  let sc_in_lovelace =
    received_with_yield + exchange_fee_buyer + owner_out_lovelace
  let sc_in_1 =
    gen_input(sc_address, sc_in_lovelace, None, InlineDatum(sc_in_datum_1))
  let seller_in_lovelace = 1310316
  let asset_sell =
    value.from_asset(get_bond_policy_id(), bond_name_1, bond_sell_qty)
  let seller_in_1 =
    gen_input(seller_address, seller_in_lovelace, Some(asset_sell), NoDatum)
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_1,
      1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  //
  let exchange_address = get_exchange_address()
  let exchange_out_lovelace = exchange_fee_buyer + exchange_fee_seller
  let exchange_out_1 =
    gen_output(exchange_address, exchange_out_lovelace, None, NoDatum)
  let seller_out_lovelace =
    seller_in_lovelace + received_with_yield - exchange_fee_seller
  let seller_out_1 =
    gen_output(seller_address, seller_out_lovelace, None, NoDatum)
  let owner_out_1 =
    gen_output(owner_address, owner_out_lovelace, Some(asset_sell), NoDatum)
  let sc_out_lovelace =
    sc_in_lovelace - received_with_yield - exchange_fee_buyer - owner_out_lovelace
  let sc_out_datum_1 =
    gen_bid_limit_multi_datum(
      owner_address,
      390,
      480,
      sc_in_datum_1.quantity - bond_sell_qty,
      500,
      [DanogoBond, OptimBond],
    )
  let sc_out_utxo =
    gen_output(sc_address, sc_out_lovelace, None, InlineDatum(sc_out_datum_1))
  let txn =
    fixture.tx(
      [sc_in_1, seller_in_1],
      [refer_in_1],
      [exchange_out_1, seller_out_1, owner_out_1, sc_out_utxo],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  let seller_receive = received_with_yield - exchange_fee_seller
  let tx =
    Transaction {
      ..txn,
      redeemers: dict.insert(
        txn.redeemers,
        Spend(sc_in_1.output_reference),
        Sell {
          exchange_fee: exchange_out_lovelace,
          seller_receive,
          offers: [(get_bond_policy_id(), bond_name_1, bond_sell_qty)],
          cont_idx: Some(3),
        },
        script_purpose_compare,
      ),
    }
  withdraw.constraint(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    bid_skh,
    [],
  )
}

test fail_output_qty() {
  let time_of_tx = 1681095094000
  let cfg = get_config_limit_mainnet()
  let owner_address = get_buyer_address()
  let seller_address = get_seller_address()
  let sc_in_datum_1 =
    gen_bid_limit_multi_datum(
      owner_address,
      390,
      480,
      5,
      500,
      [DanogoBond, OptimBond],
    )
  let bond_name_1 = get_bond_id_1()
  // get_escrow_datum(asset_name: AssetName, bond_amount: Int, epo_rewards: Int, duration: Int, start: Int)
  let escrow_bond_amount = 10000
  let escrow_epo_rewards = 753424657
  let escrow_duration = 72
  let escrow_datum =
    get_escrow_datum(
      bond_name_1,
      escrow_bond_amount,
      escrow_epo_rewards,
      escrow_duration,
      63,
    )
  // => epoch_start = 22190 epoch_end = 22244
  let escrow_lovelace =
    escrow_bond_amount * 100_000_000 + escrow_epo_rewards * escrow_duration
  let escrow_full_info =
    calc_escrow_full_info(
      cfg.platform,
      escrow_lovelace,
      escrow_datum,
      time_of_tx,
    )
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  //  
  let bond_sell_qty = 5
  let received_at_maturity = escrow_full_info.value_at_maturity * bond_sell_qty
  let received_with_yield = price_of_one_bond * bond_sell_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.seller_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.platform.basis.base
  //
  let owner_out_lovelace = min_ada
  let sc_address = get_bid_sc_address()
  let sc_in_lovelace =
    received_with_yield + exchange_fee_buyer + owner_out_lovelace
  let sc_in_1 =
    gen_input(sc_address, sc_in_lovelace, None, InlineDatum(sc_in_datum_1))
  let seller_in_lovelace = 1310316
  let asset_sell =
    value.from_asset(get_bond_policy_id(), bond_name_1, bond_sell_qty)
  let seller_in_1 =
    gen_input(seller_address, seller_in_lovelace, Some(asset_sell), NoDatum)
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_1,
      1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  //
  let exchange_address = get_exchange_address()
  let exchange_out_lovelace = exchange_fee_buyer + exchange_fee_seller
  let exchange_out_1 =
    gen_output(exchange_address, exchange_out_lovelace, None, NoDatum)
  let seller_out_lovelace =
    seller_in_lovelace + received_with_yield - exchange_fee_seller
  let seller_out_1 =
    gen_output(seller_address, seller_out_lovelace, None, NoDatum)
  let owner_out_1 =
    gen_output(owner_address, owner_out_lovelace, Some(asset_sell), NoDatum)
  let sc_out_lovelace =
    sc_in_lovelace - received_with_yield - exchange_fee_buyer - owner_out_lovelace
  let sc_out_datum_1 =
    gen_bid_limit_multi_datum(
      owner_address,
      390,
      480,
      4,
      500,
      [DanogoBond, OptimBond],
    )
  let sc_out_utxo =
    gen_output(sc_address, sc_out_lovelace, None, InlineDatum(sc_out_datum_1))
  let txn =
    fixture.tx(
      [sc_in_1, seller_in_1],
      [refer_in_1],
      [exchange_out_1, seller_out_1, owner_out_1, sc_out_utxo],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  let seller_receive = received_with_yield - exchange_fee_seller
  let tx =
    Transaction {
      ..txn,
      redeemers: dict.insert(
        txn.redeemers,
        Spend(sc_in_1.output_reference),
        Sell {
          exchange_fee: exchange_out_lovelace,
          seller_receive,
          offers: [(get_bond_policy_id(), bond_name_1, bond_sell_qty)],
          cont_idx: Some(3),
        },
        script_purpose_compare,
      ),
    }
  withdraw.constraint(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    bid_skh,
    [],
  )
}

test fail_validity_after_not_set() fail {
  let time_of_tx = 1681095094000
  let cfg = get_config_limit_mainnet()
  let owner_address = get_buyer_address()
  let seller_address = get_seller_address()
  let sc_in_datum_1 =
    gen_bid_limit_multi_datum(
      owner_address,
      390,
      480,
      5,
      500,
      [DanogoBond, OptimBond],
    )
  let bond_name_1 = get_bond_id_1()
  // get_escrow_datum(asset_name: AssetName, bond_amount: Int, epo_rewards: Int, duration: Int, start: Int)
  let escrow_bond_amount = 10000
  let escrow_epo_rewards = 753424657
  let escrow_duration = 72
  let escrow_datum =
    get_escrow_datum(
      bond_name_1,
      escrow_bond_amount,
      escrow_epo_rewards,
      escrow_duration,
      63,
    )
  // => epoch_start = 22190 epoch_end = 22244
  let escrow_lovelace =
    escrow_bond_amount * 100_000_000 + escrow_epo_rewards * escrow_duration
  let escrow_full_info =
    calc_escrow_full_info(
      cfg.platform,
      escrow_lovelace,
      escrow_datum,
      time_of_tx,
    )
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  //  
  let bond_sell_qty = 5
  let received_at_maturity = escrow_full_info.value_at_maturity * bond_sell_qty
  let received_with_yield = price_of_one_bond * bond_sell_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.seller_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.platform.basis.base
  //
  let owner_out_lovelace = 1310316
  let sc_address = get_bid_sc_address()
  let sc_in_lovelace =
    received_with_yield + exchange_fee_buyer + owner_out_lovelace
  let sc_in_1 =
    gen_input(sc_address, sc_in_lovelace, None, InlineDatum(sc_in_datum_1))
  let seller_in_lovelace = 1310316
  let asset_sell =
    value.from_asset(get_bond_policy_id(), bond_name_1, bond_sell_qty)
  let seller_in_1 =
    gen_input(seller_address, seller_in_lovelace, Some(asset_sell), NoDatum)
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_1,
      1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  //
  let exchange_address = get_exchange_address()
  let exchange_out_lovelace = exchange_fee_buyer + exchange_fee_seller
  let exchange_out_1 =
    gen_output(exchange_address, exchange_out_lovelace, None, NoDatum)
  let seller_out_lovelace =
    seller_in_lovelace + received_with_yield - exchange_fee_seller
  let seller_out_1 =
    gen_output(seller_address, seller_out_lovelace, None, NoDatum)
  let owner_out_1 =
    gen_output(owner_address, owner_out_lovelace, Some(asset_sell), NoDatum)
  let sc_out_lovelace =
    sc_in_lovelace - received_with_yield - exchange_fee_buyer - owner_out_lovelace
  let sc_out_datum_1 =
    gen_bid_limit_multi_datum(
      owner_address,
      390,
      480,
      sc_in_datum_1.quantity - bond_sell_qty,
      500,
      [DanogoBond, OptimBond],
    )
  let sc_out_utxo =
    gen_output(sc_address, sc_out_lovelace, None, InlineDatum(sc_out_datum_1))
  let txn =
    fixture.tx(
      [sc_in_1, seller_in_1],
      [refer_in_1],
      [exchange_out_1, seller_out_1, owner_out_1, sc_out_utxo],
      Some([get_buyer_address_hash()]),
      None,
      None,
      None,
    )
  let seller_receive = received_with_yield - exchange_fee_seller
  let tx =
    Transaction {
      ..txn,
      redeemers: dict.insert(
        txn.redeemers,
        Spend(sc_in_1.output_reference),
        Sell {
          exchange_fee: exchange_out_lovelace,
          seller_receive,
          offers: [(get_bond_policy_id(), bond_name_1, bond_sell_qty)],
          cont_idx: None,
        },
        script_purpose_compare,
      ),
    }
  withdraw.constraint(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    bid_skh,
    [],
  )
}

test fail_escrow_policy_id_unexpect() fail {
  let time_of_tx = 1681095094000
  let cfg = get_config_limit_mainnet()
  let owner_address = get_buyer_address()
  let seller_address = get_seller_address()
  let sc_in_datum_1 =
    gen_bid_limit_multi_datum(
      owner_address,
      390,
      480,
      5,
      500,
      [DanogoBond, OptimBond],
    )
  let bond_name_1 = get_bond_id_1()
  // get_escrow_datum(asset_name: AssetName, bond_amount: Int, epo_rewards: Int, duration: Int, start: Int)
  let escrow_bond_amount = 10000
  let escrow_epo_rewards = 753424657
  let escrow_duration = 72
  let escrow_datum =
    get_escrow_datum(
      bond_name_1,
      escrow_bond_amount,
      escrow_epo_rewards,
      escrow_duration,
      63,
    )
  // => epoch_start = 22190 epoch_end = 22244
  let escrow_lovelace =
    escrow_bond_amount * 100_000_000 + escrow_epo_rewards * escrow_duration
  let escrow_full_info =
    calc_escrow_full_info(
      cfg.platform,
      escrow_lovelace,
      escrow_datum,
      time_of_tx,
    )
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  //  
  let bond_sell_qty = 5
  let received_at_maturity = escrow_full_info.value_at_maturity * bond_sell_qty
  let received_with_yield = price_of_one_bond * bond_sell_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.seller_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.platform.basis.base
  //
  let owner_out_lovelace = 1310316
  let sc_address = get_bid_sc_address()
  let sc_in_lovelace =
    received_with_yield + exchange_fee_buyer + owner_out_lovelace
  let sc_in_1 =
    gen_input(sc_address, sc_in_lovelace, None, InlineDatum(sc_in_datum_1))
  let seller_in_lovelace = 1310316
  let asset_sell =
    value.from_asset(get_bond_policy_id(), bond_name_1, bond_sell_qty)
  let seller_in_1 =
    gen_input(seller_address, seller_in_lovelace, Some(asset_sell), NoDatum)
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_not_escrow_policy_id(),
      bond_name_1,
      1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  //
  let exchange_address = get_exchange_address()
  let exchange_out_lovelace = exchange_fee_buyer + exchange_fee_seller
  let exchange_out_1 =
    gen_output(exchange_address, exchange_out_lovelace, None, NoDatum)
  let seller_out_lovelace =
    seller_in_lovelace + received_with_yield - exchange_fee_seller
  let seller_out_1 =
    gen_output(seller_address, seller_out_lovelace, None, NoDatum)
  let owner_out_1 =
    gen_output(owner_address, owner_out_lovelace, Some(asset_sell), NoDatum)
  let sc_out_lovelace =
    sc_in_lovelace - received_with_yield - exchange_fee_buyer - owner_out_lovelace
  let sc_out_datum_1 =
    gen_bid_limit_multi_datum(
      owner_address,
      390,
      480,
      sc_in_datum_1.quantity - bond_sell_qty,
      500,
      [DanogoBond, OptimBond],
    )
  let sc_out_utxo =
    gen_output(sc_address, sc_out_lovelace, None, InlineDatum(sc_out_datum_1))
  let txn =
    fixture.tx(
      [sc_in_1, seller_in_1],
      [refer_in_1],
      [exchange_out_1, seller_out_1, owner_out_1, sc_out_utxo],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  let seller_receive = received_with_yield - exchange_fee_seller
  let tx =
    Transaction {
      ..txn,
      redeemers: dict.insert(
        txn.redeemers,
        Spend(sc_in_1.output_reference),
        Sell {
          exchange_fee: exchange_out_lovelace,
          seller_receive,
          offers: [(get_bond_policy_id(), bond_name_1, bond_sell_qty)],
          cont_idx: None,
        },
        script_purpose_compare,
      ),
    }
  withdraw.constraint(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    bid_skh,
    [],
  )
}

test fail_escrow_address_unexpect() fail {
  let time_of_tx = 1681095094000
  let cfg = get_config_limit_mainnet()
  let owner_address = get_buyer_address()
  let seller_address = get_seller_address()
  let sc_in_datum_1 =
    gen_bid_limit_multi_datum(
      owner_address,
      390,
      480,
      5,
      500,
      [DanogoBond, OptimBond],
    )
  let bond_name_1 = get_bond_id_1()
  // get_escrow_datum(asset_name: AssetName, bond_amount: Int, epo_rewards: Int, duration: Int, start: Int)
  let escrow_bond_amount = 10000
  let escrow_epo_rewards = 753424657
  let escrow_duration = 72
  let escrow_datum =
    get_escrow_datum(
      bond_name_1,
      escrow_bond_amount,
      escrow_epo_rewards,
      escrow_duration,
      63,
    )
  // => epoch_start = 22190 epoch_end = 22244
  let escrow_lovelace =
    escrow_bond_amount * 100_000_000 + escrow_epo_rewards * escrow_duration
  let escrow_full_info =
    calc_escrow_full_info(
      cfg.platform,
      escrow_lovelace,
      escrow_datum,
      time_of_tx,
    )
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  //  
  let bond_sell_qty = 5
  let received_at_maturity = escrow_full_info.value_at_maturity * bond_sell_qty
  let received_with_yield = price_of_one_bond * bond_sell_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.seller_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.platform.basis.base
  //
  let owner_out_lovelace = 1310316
  let sc_address = get_bid_sc_address()
  let sc_in_lovelace =
    received_with_yield + exchange_fee_buyer + owner_out_lovelace
  let sc_in_1 =
    gen_input(sc_address, sc_in_lovelace, None, InlineDatum(sc_in_datum_1))
  let seller_in_lovelace = 1310316
  let asset_sell =
    value.from_asset(get_bond_policy_id(), bond_name_1, bond_sell_qty)
  let seller_in_1 =
    gen_input(seller_address, seller_in_lovelace, Some(asset_sell), NoDatum)
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address_unexpect(),
      get_escrow_policy_id(),
      bond_name_1,
      1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  //
  let exchange_address = get_exchange_address()
  let exchange_out_lovelace = exchange_fee_buyer + exchange_fee_seller
  let exchange_out_1 =
    gen_output(exchange_address, exchange_out_lovelace, None, NoDatum)
  let seller_out_lovelace =
    seller_in_lovelace + received_with_yield - exchange_fee_seller
  let seller_out_1 =
    gen_output(seller_address, seller_out_lovelace, None, NoDatum)
  let owner_out_1 =
    gen_output(owner_address, owner_out_lovelace, Some(asset_sell), NoDatum)
  let sc_out_lovelace =
    sc_in_lovelace - received_with_yield - exchange_fee_buyer - owner_out_lovelace
  let sc_out_datum_1 =
    gen_bid_limit_multi_datum(
      owner_address,
      390,
      480,
      sc_in_datum_1.quantity - bond_sell_qty,
      500,
      [DanogoBond, OptimBond],
    )
  let sc_out_utxo =
    gen_output(sc_address, sc_out_lovelace, None, InlineDatum(sc_out_datum_1))
  let txn =
    fixture.tx(
      [sc_in_1, seller_in_1],
      [refer_in_1],
      [exchange_out_1, seller_out_1, owner_out_1, sc_out_utxo],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  let seller_receive = received_with_yield - exchange_fee_seller
  let tx =
    Transaction {
      ..txn,
      redeemers: dict.insert(
        txn.redeemers,
        Spend(sc_in_1.output_reference),
        Sell {
          exchange_fee: exchange_out_lovelace,
          seller_receive,
          offers: [(get_bond_policy_id(), bond_name_1, bond_sell_qty)],
          cont_idx: None,
        },
        script_purpose_compare,
      ),
    }
  withdraw.constraint(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    bid_skh,
    [],
  )
}

test fail_escrow_datum_not_found() fail {
  let time_of_tx = 1681095094000
  let cfg = get_config_limit_mainnet()
  let owner_address = get_buyer_address()
  let seller_address = get_seller_address()
  let sc_in_datum_1 =
    gen_bid_limit_multi_datum(
      owner_address,
      390,
      480,
      5,
      500,
      [DanogoBond, OptimBond],
    )
  let bond_name_1 = get_bond_id_1()
  // get_escrow_datum(asset_name: AssetName, bond_amount: Int, epo_rewards: Int, duration: Int, start: Int)
  let escrow_bond_amount = 10000
  let escrow_epo_rewards = 753424657
  let escrow_duration = 72
  let escrow_datum =
    get_escrow_datum(
      bond_name_1,
      escrow_bond_amount,
      escrow_epo_rewards,
      escrow_duration,
      63,
    )
  // => epoch_start = 22190 epoch_end = 22244
  let escrow_lovelace =
    escrow_bond_amount * 100_000_000 + escrow_epo_rewards * escrow_duration
  let escrow_full_info =
    calc_escrow_full_info(
      cfg.platform,
      escrow_lovelace,
      escrow_datum,
      time_of_tx,
    )
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  //  
  let bond_sell_qty = 5
  let received_at_maturity = escrow_full_info.value_at_maturity * bond_sell_qty
  let received_with_yield = price_of_one_bond * bond_sell_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.seller_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.platform.basis.base
  //
  let owner_out_lovelace = 1310316
  let sc_address = get_bid_sc_address()
  let sc_in_lovelace =
    received_with_yield + exchange_fee_buyer + owner_out_lovelace
  let sc_in_1 =
    gen_input(sc_address, sc_in_lovelace, None, InlineDatum(sc_in_datum_1))
  let seller_in_lovelace = 1310316
  let asset_sell =
    value.from_asset(get_bond_policy_id(), bond_name_1, bond_sell_qty)
  let seller_in_1 =
    gen_input(seller_address, seller_in_lovelace, Some(asset_sell), NoDatum)
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_1,
      1,
      escrow_lovelace,
      NoDatum,
    )
  //
  let exchange_address = get_exchange_address()
  let exchange_out_lovelace = exchange_fee_buyer + exchange_fee_seller
  let exchange_out_1 =
    gen_output(exchange_address, exchange_out_lovelace, None, NoDatum)
  let seller_out_lovelace =
    seller_in_lovelace + received_with_yield - exchange_fee_seller
  let seller_out_1 =
    gen_output(seller_address, seller_out_lovelace, None, NoDatum)
  let owner_out_1 =
    gen_output(owner_address, owner_out_lovelace, Some(asset_sell), NoDatum)
  let sc_out_lovelace =
    sc_in_lovelace - received_with_yield - exchange_fee_buyer - owner_out_lovelace
  let sc_out_datum_1 =
    gen_bid_limit_multi_datum(
      owner_address,
      390,
      480,
      sc_in_datum_1.quantity - bond_sell_qty,
      500,
      [DanogoBond, OptimBond],
    )
  let sc_out_utxo =
    gen_output(sc_address, sc_out_lovelace, None, InlineDatum(sc_out_datum_1))
  let txn =
    fixture.tx(
      [sc_in_1, seller_in_1],
      [refer_in_1],
      [exchange_out_1, seller_out_1, owner_out_1, sc_out_utxo],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  let seller_receive = received_with_yield - exchange_fee_seller
  let tx =
    Transaction {
      ..txn,
      redeemers: dict.insert(
        txn.redeemers,
        Spend(sc_in_1.output_reference),
        Sell {
          exchange_fee: exchange_out_lovelace,
          seller_receive,
          offers: [(get_bond_policy_id(), bond_name_1, bond_sell_qty)],
          cont_idx: None,
        },
        script_purpose_compare,
      ),
    }
  withdraw.constraint(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    bid_skh,
    [],
  )
}

test fail_escrow_datum_unexpect() fail {
  let time_of_tx = 1681095094000
  let cfg = get_config_limit_mainnet()
  let owner_address = get_buyer_address()
  let seller_address = get_seller_address()
  let sc_in_datum_1 =
    gen_bid_limit_multi_datum(
      owner_address,
      390,
      480,
      5,
      500,
      [DanogoBond, OptimBond],
    )
  let bond_name_1 = get_bond_id_1()
  // get_escrow_datum(asset_name: AssetName, bond_amount: Int, epo_rewards: Int, duration: Int, start: Int)
  let escrow_bond_amount = 10000
  let escrow_epo_rewards = 753424657
  let escrow_duration = 72
  let escrow_datum =
    get_escrow_datum(
      bond_name_1,
      escrow_bond_amount,
      escrow_epo_rewards,
      escrow_duration,
      63,
    )
  // => epoch_start = 22190 epoch_end = 22244
  let escrow_lovelace =
    escrow_bond_amount * 100_000_000 + escrow_epo_rewards * escrow_duration
  let escrow_full_info =
    calc_escrow_full_info(
      cfg.platform,
      escrow_lovelace,
      escrow_datum,
      time_of_tx,
    )
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  //  
  let bond_sell_qty = 5
  let received_at_maturity = escrow_full_info.value_at_maturity * bond_sell_qty
  let received_with_yield = price_of_one_bond * bond_sell_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.seller_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.platform.basis.base
  //
  let owner_out_lovelace = 1310316
  let sc_address = get_bid_sc_address()
  let sc_in_lovelace =
    received_with_yield + exchange_fee_buyer + owner_out_lovelace
  let sc_in_1 =
    gen_input(sc_address, sc_in_lovelace, None, InlineDatum(sc_in_datum_1))
  let seller_in_lovelace = 1310316
  let asset_sell =
    value.from_asset(get_bond_policy_id(), bond_name_1, bond_sell_qty)
  let seller_in_1 =
    gen_input(seller_address, seller_in_lovelace, Some(asset_sell), NoDatum)
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_1,
      1,
      escrow_lovelace,
      InlineDatum(sc_in_datum_1),
    )
  //
  let exchange_address = get_exchange_address()
  let exchange_out_lovelace = exchange_fee_buyer + exchange_fee_seller
  let exchange_out_1 =
    gen_output(exchange_address, exchange_out_lovelace, None, NoDatum)
  let seller_out_lovelace =
    seller_in_lovelace + received_with_yield - exchange_fee_seller
  let seller_out_1 =
    gen_output(seller_address, seller_out_lovelace, None, NoDatum)
  let owner_out_1 =
    gen_output(owner_address, owner_out_lovelace, Some(asset_sell), NoDatum)
  let sc_out_lovelace =
    sc_in_lovelace - received_with_yield - exchange_fee_buyer - owner_out_lovelace
  let sc_out_datum_1 =
    gen_bid_limit_multi_datum(
      owner_address,
      390,
      480,
      sc_in_datum_1.quantity - bond_sell_qty,
      500,
      [DanogoBond, OptimBond],
    )
  let sc_out_utxo =
    gen_output(sc_address, sc_out_lovelace, None, InlineDatum(sc_out_datum_1))
  let txn =
    fixture.tx(
      [sc_in_1, seller_in_1],
      [refer_in_1],
      [exchange_out_1, seller_out_1, owner_out_1, sc_out_utxo],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  let seller_receive = received_with_yield - exchange_fee_seller
  let tx =
    Transaction {
      ..txn,
      redeemers: dict.insert(
        txn.redeemers,
        Spend(sc_in_1.output_reference),
        Sell {
          exchange_fee: exchange_out_lovelace,
          seller_receive,
          offers: [(get_bond_policy_id(), bond_name_1, bond_sell_qty)],
          cont_idx: None,
        },
        script_purpose_compare,
      ),
    }
  withdraw.constraint(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    bid_skh,
    [],
  )
}

test succ_bond_policy_id_valid() {
  let time_of_tx = 1681095094000
  let cfg = get_config_limit_mainnet()
  let owner_address = get_buyer_address()
  let seller_address = get_seller_address()
  let sc_in_datum_1 =
    gen_bid_limit_multi_datum(
      owner_address,
      390,
      480,
      5,
      500,
      [DanogoBond, OptimBond],
    )
  let bond_name_1 = get_bond_id_1()
  // get_escrow_datum(asset_name: AssetName, bond_amount: Int, epo_rewards: Int, duration: Int, start: Int)
  let escrow_bond_amount = 10000
  let escrow_epo_rewards = 753424657
  let escrow_duration = 72
  let escrow_datum =
    get_escrow_datum(
      bond_name_1,
      escrow_bond_amount,
      escrow_epo_rewards,
      escrow_duration,
      63,
    )
  // => epoch_start = 22190 epoch_end = 22244
  let escrow_lovelace =
    escrow_bond_amount * 100_000_000 + escrow_epo_rewards * escrow_duration
  let escrow_full_info =
    calc_escrow_full_info(
      cfg.platform,
      escrow_lovelace,
      escrow_datum,
      time_of_tx,
    )
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  //  
  let bond_sell_qty = 5
  let received_at_maturity = escrow_full_info.value_at_maturity * bond_sell_qty
  let received_with_yield = price_of_one_bond * bond_sell_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.seller_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.platform.basis.base
  //
  let owner_out_lovelace = min_ada
  let sc_address = get_bid_sc_address()
  let sc_in_lovelace =
    received_with_yield + exchange_fee_buyer + owner_out_lovelace
  let sc_in_1 =
    gen_input(sc_address, sc_in_lovelace, None, InlineDatum(sc_in_datum_1))
  let seller_in_lovelace = 1310316
  let asset_sell =
    value.from_asset(get_bond_policy_id(), bond_name_1, bond_sell_qty)
  let seller_in_1 =
    gen_input(seller_address, seller_in_lovelace, Some(asset_sell), NoDatum)
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_1,
      1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  //
  let exchange_address = get_exchange_address()
  let exchange_out_lovelace = exchange_fee_buyer + exchange_fee_seller
  let exchange_out_1 =
    gen_output(exchange_address, exchange_out_lovelace, None, NoDatum)
  let seller_out_lovelace =
    seller_in_lovelace + received_with_yield - exchange_fee_seller
  let seller_out_1 =
    gen_output(seller_address, seller_out_lovelace, None, NoDatum)
  let owner_out_1 =
    gen_output(owner_address, owner_out_lovelace, Some(asset_sell), NoDatum)
  let txn =
    fixture.tx(
      [sc_in_1, seller_in_1],
      [refer_in_1],
      [exchange_out_1, seller_out_1, owner_out_1],
      // [exchange_out_1, seller_out_1, owner_out_1, sc_out_utxo],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  let seller_receive = received_with_yield - exchange_fee_seller
  let tx =
    Transaction {
      ..txn,
      redeemers: dict.insert(
        txn.redeemers,
        Spend(sc_in_1.output_reference),
        Sell {
          exchange_fee: exchange_out_lovelace,
          seller_receive,
          offers: [(get_bond_policy_id(), bond_name_1, bond_sell_qty)],
          cont_idx: None,
        },
        script_purpose_compare,
      ),
    }
  withdraw.constraint(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    bid_skh,
    [],
  )
}

test fail_bond_policy_id_invalid() fail {
  let time_of_tx = 1681095094000
  let cfg = get_config_limit_mainnet()
  let owner_address = get_buyer_address()
  let seller_address = get_seller_address()
  let sc_in_datum_1 =
    gen_bid_limit_multi_datum(
      owner_address,
      390,
      480,
      5,
      500,
      [DanogoBond, OptimBond],
    )
  let bond_name_1 = get_bond_id_1()
  // get_escrow_datum(asset_name: AssetName, bond_amount: Int, epo_rewards: Int, duration: Int, start: Int)
  let escrow_bond_amount = 10000
  let escrow_epo_rewards = 753424657
  let escrow_duration = 72
  let escrow_datum =
    get_escrow_datum(
      bond_name_1,
      escrow_bond_amount,
      escrow_epo_rewards,
      escrow_duration,
      63,
    )
  // => epoch_start = 22190 epoch_end = 22244
  let escrow_lovelace =
    escrow_bond_amount * 100_000_000 + escrow_epo_rewards * escrow_duration
  let escrow_full_info =
    calc_escrow_full_info(
      cfg.platform,
      escrow_lovelace,
      escrow_datum,
      time_of_tx,
    )
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  //  
  let bond_sell_qty = 4
  let received_at_maturity = escrow_full_info.value_at_maturity * bond_sell_qty
  let received_with_yield = price_of_one_bond * bond_sell_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.seller_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.platform.basis.base
  //
  let owner_out_lovelace = min_ada
  let sc_address = get_bid_sc_address()
  let sc_in_lovelace =
    received_with_yield + exchange_fee_buyer + owner_out_lovelace
  let sc_in_1 =
    gen_input(sc_address, sc_in_lovelace, None, InlineDatum(sc_in_datum_1))
  let seller_in_lovelace = 1310316
  let asset_sell =
    value.from_asset(get_not_bond_policy_id(), bond_name_1, bond_sell_qty)
  let seller_in_1 =
    gen_input(seller_address, seller_in_lovelace, Some(asset_sell), NoDatum)
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_1,
      1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  //
  let exchange_address = get_exchange_address()
  let exchange_out_lovelace = exchange_fee_buyer + exchange_fee_seller
  let exchange_out_1 =
    gen_output(exchange_address, exchange_out_lovelace, None, NoDatum)
  let seller_out_lovelace =
    seller_in_lovelace + received_with_yield - exchange_fee_seller
  let seller_out_1 =
    gen_output(seller_address, seller_out_lovelace, None, NoDatum)
  let owner_out_1 =
    gen_output(owner_address, owner_out_lovelace, Some(asset_sell), NoDatum)
  let sc_out_lovelace =
    sc_in_lovelace - received_with_yield - exchange_fee_buyer - owner_out_lovelace
  let sc_out_datum_1 =
    gen_bid_limit_multi_datum(
      owner_address,
      390,
      480,
      sc_in_datum_1.quantity - bond_sell_qty,
      500,
      [DanogoBond, OptimBond],
    )
  let sc_out_utxo =
    gen_output(sc_address, sc_out_lovelace, None, InlineDatum(sc_out_datum_1))
  let txn =
    fixture.tx(
      [sc_in_1, seller_in_1],
      [refer_in_1],
      [exchange_out_1, seller_out_1, owner_out_1, sc_out_utxo],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  let seller_receive = received_with_yield - exchange_fee_seller
  let tx =
    Transaction {
      ..txn,
      redeemers: dict.insert(
        txn.redeemers,
        Spend(sc_in_1.output_reference),
        Sell {
          exchange_fee: exchange_out_lovelace,
          seller_receive,
          offers: [(get_bond_policy_id(), bond_name_1, bond_sell_qty)],
          cont_idx: Some(3),
        },
        script_purpose_compare,
      ),
    }
  !withdraw.constraint(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    bid_skh,
    [],
  )
}

test fail_wrong_bond_types() fail {
  let time_of_tx = 1681095094000
  let cfg = get_config_limit_mainnet()
  let owner_address = get_buyer_address()
  let seller_address = get_seller_address()
  let sc_in_datum_1 =
    gen_bid_limit_multi_datum(owner_address, 390, 480, 5, 500, [DanogoBond])
  let bond_name_1 = get_bond_id_1()
  // get_escrow_datum(asset_name: AssetName, bond_amount: Int, epo_rewards: Int, duration: Int, start: Int)
  let escrow_bond_amount = 10000
  let escrow_epo_rewards = 753424657
  let escrow_duration = 72
  let escrow_datum =
    get_escrow_datum(
      bond_name_1,
      escrow_bond_amount,
      escrow_epo_rewards,
      escrow_duration,
      63,
    )
  // => epoch_start = 22190 epoch_end = 22244
  let escrow_lovelace =
    escrow_bond_amount * 100_000_000 + escrow_epo_rewards * escrow_duration
  let escrow_full_info =
    calc_escrow_full_info(
      cfg.platform,
      escrow_lovelace,
      escrow_datum,
      time_of_tx,
    )
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  //  
  let bond_sell_qty = 2
  let received_at_maturity = escrow_full_info.value_at_maturity * bond_sell_qty
  let received_with_yield = price_of_one_bond * bond_sell_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.seller_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.platform.basis.base
  //
  let owner_out_lovelace = min_ada
  let sc_address = get_bid_sc_address()
  let sc_in_lovelace = received_with_yield + exchange_fee_buyer + 10000000
  let sc_in_1 =
    gen_input(sc_address, sc_in_lovelace, None, InlineDatum(sc_in_datum_1))
  let seller_in_lovelace = min_ada
  let asset_sell =
    value.from_asset(get_bond_policy_id(), bond_name_1, bond_sell_qty)
  let seller_in_1 =
    gen_input(seller_address, seller_in_lovelace, Some(asset_sell), NoDatum)
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_1,
      1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  //
  let exchange_address = get_exchange_address()
  let exchange_out_lovelace = exchange_fee_buyer + exchange_fee_seller
  let exchange_out_1 =
    gen_output(exchange_address, exchange_out_lovelace, None, NoDatum)
  let seller_out_lovelace =
    seller_in_lovelace + received_with_yield - exchange_fee_seller
  let seller_out_1 =
    gen_output(seller_address, seller_out_lovelace, None, NoDatum)
  let owner_out_1 =
    gen_output(owner_address, owner_out_lovelace, Some(asset_sell), NoDatum)
  let sc_out_lovelace =
    sc_in_lovelace - received_with_yield - exchange_fee_buyer - owner_out_lovelace
  let sc_out_datum_1 =
    gen_bid_limit_multi_datum(
      owner_address,
      390,
      480,
      sc_in_datum_1.quantity - bond_sell_qty,
      500,
      [OptimBond, DanogoBond],
    )
  let sc_out_utxo =
    gen_output(sc_address, sc_out_lovelace, None, InlineDatum(sc_out_datum_1))
  let txn =
    fixture.tx(
      [sc_in_1, seller_in_1],
      [refer_in_1],
      [exchange_out_1, seller_out_1, owner_out_1, sc_out_utxo],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  let seller_receive = received_with_yield - exchange_fee_seller
  let tx =
    Transaction {
      ..txn,
      redeemers: dict.insert(
        txn.redeemers,
        Spend(sc_in_1.output_reference),
        Sell {
          exchange_fee: exchange_out_lovelace,
          seller_receive,
          offers: [(get_bond_policy_id(), bond_name_1, bond_sell_qty)],
          cont_idx: Some(3),
        },
        script_purpose_compare,
      ),
    }
  withdraw.constraint(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    bid_skh,
    [],
  )
}

test succ_spend_multiple_bids_different_owners() {
  let default_cfg = get_config_limit_preview()
  let cfg =
    BondConfigLimit {
      ..default_cfg,
      exchange: ExchangeConfigLimit {
        ..default_cfg.exchange,
        fee_addr: from_verification_key(
          #"ddf11f10f184795801208e292ea39d7c010aaaf42e75d9ca07e3f1f9",
        )
          |> with_delegation_key(
              #"0efaa13184b734b3188d9a1163aedd6ef9cfe5d8fc76920049f18a79",
            ),
      },
      escrow: default_cfg.escrow
        |> dict.insert(
            #"6c70c4e7de9a9173b330d26390f1223d7b6f9a30a44e525cd7d8c9f3",
            (
              #"6c70c4e7de9a9173b330d26390f1223d7b6f9a30a44e525cd7d8c9f3",
              DanogoBond,
            ),
            bytearray.compare,
          ),
    }
  let t = transaction.placeholder()
  let bid_out_ref =
    OutputReference(
      TransactionId(
        #"3767ab13fe42e26895de6ccb4392bee165c1f219b611a2a1b53c7509dd294bdb",
      ),
      0,
    )
  let tx =
    Transaction {
      ..t,
      inputs: [
        Input {
          output_reference: bid_out_ref,
          output: Output {
            value: value.from_lovelace(107_377_022),
            address: from_script(
              #"aa1a6ce68c5b672cddff867598db3a199233fbd24e70711c882c23ea",
            )
              |> with_delegation_key(
                  #"1eda16e062501fc351d3e4e53d9435283f83f7effddb9d29b6d696ab",
                ),
            datum: InlineDatum(
              BidLimitMulti {
                owner_vk: #"e53e7dcbec658da2c0f729f7e225ee81797e00f59496fc38cf67e14a",
                owner_sk: Some(
                  #"1eda16e062501fc351d3e4e53d9435283f83f7effddb9d29b6d696ab",
                ),
                from_epoch: 36062,
                to_epoch: 36126,
                quantity: 1,
                requested_yield: 533,
                bond_types: [DanogoBond, OptimBond],
              },
            ),
            reference_script: None,
          },
        },
        Input {
          output_reference: OutputReference(
            TransactionId(
              #"85548771a5861c5ff55eb880a38667fbe2f5d8dac03b63bce31d4fa9f6520e72",
            ),
            0,
          ),
          output: Output {
            value: value.from_lovelace(1_055_759_516),
            address: from_script(
              #"aa1a6ce68c5b672cddff867598db3a199233fbd24e70711c882c23ea",
            )
              |> with_delegation_key(
                  #"27cd6c01b37340fc2b3f9ce59bd825e4a0713d841d0294213bf1958e",
                ),
            datum: InlineDatum(
              BidLimitMulti {
                owner_vk: #"f05c5cf98d1aed3a20cf4f60260d6b96d10922a2c3f0356277aa9550",
                owner_sk: Some(
                  #"27cd6c01b37340fc2b3f9ce59bd825e4a0713d841d0294213bf1958e",
                ),
                from_epoch: 36079,
                to_epoch: 36126,
                quantity: 10,
                requested_yield: 500,
                bond_types: [DanogoBond, OptimBond],
              },
            ),
            reference_script: None,
          },
        },
        Input {
          output_reference: OutputReference(
            TransactionId(
              #"b2a9d3435f63711c48236916c95a35837487335a080a12e432319d6e6dd19813",
            ),
            5,
          ),
          output: Output {
            value: value.from_lovelace(5_000_000),
            address: from_verification_key(
              #"228209dba36a7c96b5e43b5497f9e2532e79e399e4bedf3c6ed58e21",
            )
              |> with_delegation_key(
                  #"2d16c16b47b3e94d97cddc225a6fb72db066a5b151a3f1e7a644b647",
                ),
            datum: NoDatum,
            reference_script: None,
          },
        },
        Input {
          output_reference: OutputReference(
            TransactionId(
              #"dc77a363caa41943887a82d34cbe7ec286a217ab6be49d7caec533d42ab73e7e",
            ),
            2,
          ),
          output: Output {
            value: value.from_lovelace(264_604_159),
            address: from_verification_key(
              #"228209dba36a7c96b5e43b5497f9e2532e79e399e4bedf3c6ed58e21",
            )
              |> with_delegation_key(
                  #"2d16c16b47b3e94d97cddc225a6fb72db066a5b151a3f1e7a644b647",
                ),
            datum: NoDatum,
            reference_script: None,
          },
        },
      ],
      mint: value.from_asset(
        #"1bcf5f5801a073b1ed979202065bd8433c132879fe51ab9b4006ba66",
        #"7d60450e77aee2c81c9c0945450afb526133825e6e13420793721d3df1954917",
        1,
      )
        |> value.add(
            #"1bcf5f5801a073b1ed979202065bd8433c132879fe51ab9b4006ba66",
            #"dc287c96cb4425252ce946cbf4df030a8d9823fded15bc86514ad99108223d7b",
            1,
          )
        |> value.add(
            #"1bcf5f5801a073b1ed979202065bd8433c132879fe51ab9b4006ba66",
            #"effba5f04b6a2decaac47011e123a444dcce40532ffa6b953f461c35a60fdf30",
            1,
          )
        |> value.add(
            #"5d412dd200a08f5ed73ef3f45b32c0c7605b36849a719336e094770b",
            #"7d60450e77aee2c81c9c0945450afb526133825e6e13420793721d3df1954917",
            1,
          )
        |> value.add(
            #"6c70c4e7de9a9173b330d26390f1223d7b6f9a30a44e525cd7d8c9f3",
            #"dc287c96cb4425252ce946cbf4df030a8d9823fded15bc86514ad99108223d7b",
            1,
          )
        |> value.add(
            #"6c70c4e7de9a9173b330d26390f1223d7b6f9a30a44e525cd7d8c9f3",
            #"effba5f04b6a2decaac47011e123a444dcce40532ffa6b953f461c35a60fdf30",
            1,
          )
        |> value.add(
            #"84e7fdfa7c0c5a5b25338435868a1413c2b8bf2315dcf9989991b9c4",
            #"dc287c96cb4425252ce946cbf4df030a8d9823fded15bc86514ad99108223d7b",
            10,
          )
        |> value.add(
            #"84e7fdfa7c0c5a5b25338435868a1413c2b8bf2315dcf9989991b9c4",
            #"effba5f04b6a2decaac47011e123a444dcce40532ffa6b953f461c35a60fdf30",
            1,
          )
        |> value.to_minted_value,
      outputs: [
        Output {
          address: from_script(
            #"6c70c4e7de9a9173b330d26390f1223d7b6f9a30a44e525cd7d8c9f3",
          )
            |> with_delegation_key(
                #"2d16c16b47b3e94d97cddc225a6fb72db066a5b151a3f1e7a644b647",
              ),
          value: value.from_lovelace(1010547944)
            |> value.add(
                #"6c70c4e7de9a9173b330d26390f1223d7b6f9a30a44e525cd7d8c9f3",
                #"dc287c96cb4425252ce946cbf4df030a8d9823fded15bc86514ad99108223d7b",
                1,
              ),
          datum: InlineDatum(
            BondDatum {
              epo_rewards: value.from_lovelace(958_904) |> pvalue.from_value,
              duration: 20,
              bond_symbol: #"84e7fdfa7c0c5a5b25338435868a1413c2b8bf2315dcf9989991b9c4",
              token_name: #"dc287c96cb4425252ce946cbf4df030a8d9823fded15bc86514ad99108223d7b",
              bond_amount: 10,
              buffer: 6,
              fee: 500,
              borrower: #"dc287c96cb4425252ce946cbf4df030a8d9823fded15bc86514ad99108223d7b",
              start: 35734,
            },
          ),
          reference_script: None,
        },
        Output {
          address: from_verification_key(
            #"f05c5cf98d1aed3a20cf4f60260d6b96d10922a2c3f0356277aa9550",
          )
            |> with_delegation_key(
                #"27cd6c01b37340fc2b3f9ce59bd825e4a0713d841d0294213bf1958e",
              ),
          value: value.from_lovelace(50_893_635)
            |> value.add(
                #"84e7fdfa7c0c5a5b25338435868a1413c2b8bf2315dcf9989991b9c4",
                #"dc287c96cb4425252ce946cbf4df030a8d9823fded15bc86514ad99108223d7b",
                10,
              ),
          datum: NoDatum,
          reference_script: None,
        },
        Output {
          address: from_verification_key(
            #"ddf11f10f184795801208e292ea39d7c010aaaf42e75d9ca07e3f1f9",
          )
            |> with_delegation_key(
                #"0efaa13184b734b3188d9a1163aedd6ef9cfe5d8fc76920049f18a79",
              ),
          value: value.from_lovelace(969_750),
          datum: NoDatum,
          reference_script: None,
        },
        Output {
          address: from_script(
            #"6c70c4e7de9a9173b330d26390f1223d7b6f9a30a44e525cd7d8c9f3",
          )
            |> with_delegation_key(
                #"2d16c16b47b3e94d97cddc225a6fb72db066a5b151a3f1e7a644b647",
              ),
          value: value.from_lovelace(101_054_790)
            |> value.add(
                #"6c70c4e7de9a9173b330d26390f1223d7b6f9a30a44e525cd7d8c9f3",
                #"effba5f04b6a2decaac47011e123a444dcce40532ffa6b953f461c35a60fdf30",
                1,
              ),
          datum: InlineDatum(
            BondDatum {
              epo_rewards: value.from_lovelace(95_890) |> pvalue.from_value,
              duration: 20,
              bond_symbol: #"84e7fdfa7c0c5a5b25338435868a1413c2b8bf2315dcf9989991b9c4",
              token_name: #"effba5f04b6a2decaac47011e123a444dcce40532ffa6b953f461c35a60fdf30",
              bond_amount: 1,
              buffer: 6,
              fee: 500,
              borrower: #"effba5f04b6a2decaac47011e123a444dcce40532ffa6b953f461c35a60fdf30",
              start: 35734,
            },
          ),
          reference_script: None,
        },
        Output {
          address: from_verification_key(
            #"e53e7dcbec658da2c0f729f7e225ee81797e00f59496fc38cf67e14a",
          )
            |> with_delegation_key(
                #"1eda16e062501fc351d3e4e53d9435283f83f7effddb9d29b6d696ab",
              ),
          value: value.from_lovelace(6977330)
            |> value.add(
                #"84e7fdfa7c0c5a5b25338435868a1413c2b8bf2315dcf9989991b9c4",
                #"effba5f04b6a2decaac47011e123a444dcce40532ffa6b953f461c35a60fdf30",
                1,
              ),
          datum: NoDatum,
          reference_script: None,
        },
        Output {
          address: from_verification_key(
            #"228209dba36a7c96b5e43b5497f9e2532e79e399e4bedf3c6ed58e21",
          )
            |> with_delegation_key(
                #"2d16c16b47b3e94d97cddc225a6fb72db066a5b151a3f1e7a644b647",
              ),
          value: value.from_lovelace(250634105)
            |> value.add(
                #"1bcf5f5801a073b1ed979202065bd8433c132879fe51ab9b4006ba66",
                #"7d60450e77aee2c81c9c0945450afb526133825e6e13420793721d3df1954917",
                1,
              )
            |> value.add(
                #"1bcf5f5801a073b1ed979202065bd8433c132879fe51ab9b4006ba66",
                #"dc287c96cb4425252ce946cbf4df030a8d9823fded15bc86514ad99108223d7b",
                1,
              )
            |> value.add(
                #"1bcf5f5801a073b1ed979202065bd8433c132879fe51ab9b4006ba66",
                #"effba5f04b6a2decaac47011e123a444dcce40532ffa6b953f461c35a60fdf30",
                1,
              ),
          datum: NoDatum,
          reference_script: None,
        },
        Output {
          address: from_script(
            #"5d412dd200a08f5ed73ef3f45b32c0c7605b36849a719336e094770b",
          )
            |> with_delegation_key(
                #"2d16c16b47b3e94d97cddc225a6fb72db066a5b151a3f1e7a644b647",
              ),
          value: value.from_lovelace(11493143)
            |> value.add(
                #"5d412dd200a08f5ed73ef3f45b32c0c7605b36849a719336e094770b",
                #"7d60450e77aee2c81c9c0945450afb526133825e6e13420793721d3df1954917",
                1,
              ),
          datum: InlineDatum(
            RequestDatum {
              apr: 700,
              duration: 20,
              symbol: #"1bcf5f5801a073b1ed979202065bd8433c132879fe51ab9b4006ba66",
              borrower: #"7d60450e77aee2c81c9c0945450afb526133825e6e13420793721d3df1954917",
              requested: 9,
              issued: 0,
              epo_rewards: 863013,
              prepaid: 11,
              buffer: 6,
              fee: 500,
            },
          ),
          reference_script: None,
        },
      ],
      redeemers: t.redeemers
        |> dict.insert(
            Spend(
              OutputReference(
                TransactionId(
                  #"85548771a5861c5ff55eb880a38667fbe2f5d8dac03b63bce31d4fa9f6520e72",
                ),
                0,
              ),
            ),
            Sell {
              exchange_fee: 269762,
              seller_receive: 1004596119,
              offers: [
                (
                  #"84e7fdfa7c0c5a5b25338435868a1413c2b8bf2315dcf9989991b9c4",
                  #"dc287c96cb4425252ce946cbf4df030a8d9823fded15bc86514ad99108223d7b",
                  10,
                ),
              ],
              cont_idx: None,
            },
            script_purpose_compare,
          )
        |> dict.insert(
            Spend(
              OutputReference(
                TransactionId(
                  #"3767ab13fe42e26895de6ccb4392bee165c1f219b611a2a1b53c7509dd294bdb",
                ),
                0,
              ),
            ),
            Sell {
              exchange_fee: 28730,
              seller_receive: 100370962,
              offers: [
                (
                  #"84e7fdfa7c0c5a5b25338435868a1413c2b8bf2315dcf9989991b9c4",
                  #"effba5f04b6a2decaac47011e123a444dcce40532ffa6b953f461c35a60fdf30",
                  1,
                ),
              ],
              cont_idx: None,
            },
            script_purpose_compare,
          ),
      validity_range: entirely_between(
        slot_to_begin_posix_time(45565039, cfg.platform.slot),
        slot_to_begin_posix_time(45565199, cfg.platform.slot),
      ),
    }

  withdraw.constraint(
    ScriptContext { transaction: tx, purpose: Spend(bid_out_ref) },
    cfg,
    #"aa1a6ce68c5b672cddff867598db3a199233fbd24e70711c882c23ea",
    [],
  )
}

test succ_when_sc_bid_stake_key_is_script() {
  let time_of_tx = 1681095094000
  let sc_bid_stake_key_hash = #"080201"
  let cfg = get_config_limit_mainnet()
  let owner_address =
    get_buyer_address() |> with_delegation_script(sc_bid_stake_key_hash)
  let seller_address =
    get_seller_address() |> with_delegation_script(sc_bid_stake_key_hash)
  let sc_in_datum_1 =
    gen_bid_limit_multi_datum(
      owner_address,
      390,
      480,
      5,
      500,
      [DanogoBond, OptimBond],
    )
  let bond_name_1 = get_bond_id_1()
  // get_escrow_datum(asset_name: AssetName, bond_amount: Int, epo_rewards: Int, duration: Int, start: Int)
  let escrow_bond_amount = 10000
  let escrow_epo_rewards = 753424657
  let escrow_duration = 72
  let escrow_datum =
    get_escrow_datum(
      bond_name_1,
      escrow_bond_amount,
      escrow_epo_rewards,
      escrow_duration,
      63,
    )
  // => epoch_start = 22190 epoch_end = 22244
  let escrow_lovelace =
    escrow_bond_amount * 100_000_000 + escrow_epo_rewards * escrow_duration
  let escrow_full_info =
    calc_escrow_full_info(
      cfg.platform,
      escrow_lovelace,
      escrow_datum,
      time_of_tx,
    )
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  //  
  let bond_sell_qty = 5
  let received_at_maturity = escrow_full_info.value_at_maturity * bond_sell_qty
  let received_with_yield = price_of_one_bond * bond_sell_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.seller_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.platform.basis.base
  //
  let owner_out_lovelace = min_ada
  let sc_address =
    get_bid_sc_address() |> with_delegation_script(sc_bid_stake_key_hash)
  let sc_in_lovelace =
    received_with_yield + exchange_fee_buyer + owner_out_lovelace
  let sc_in_1 =
    gen_input(sc_address, sc_in_lovelace, None, InlineDatum(sc_in_datum_1))
  let seller_in_lovelace = 1310316
  let asset_sell =
    value.from_asset(get_bond_policy_id(), bond_name_1, bond_sell_qty)
  let seller_in_1 =
    gen_input(seller_address, seller_in_lovelace, Some(asset_sell), NoDatum)
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_1,
      1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  //
  let exchange_address = get_exchange_address()
  let exchange_out_lovelace = exchange_fee_buyer + exchange_fee_seller
  let exchange_out_1 =
    gen_output(exchange_address, exchange_out_lovelace, None, NoDatum)
  let seller_out_lovelace =
    seller_in_lovelace + received_with_yield - exchange_fee_seller
  let seller_out_1 =
    gen_output(seller_address, seller_out_lovelace, None, NoDatum)
  let owner_out_1 =
    gen_output(owner_address, owner_out_lovelace, Some(asset_sell), NoDatum)
  let txn =
    fixture.tx(
      [sc_in_1, seller_in_1],
      [refer_in_1],
      [exchange_out_1, seller_out_1, owner_out_1],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  let seller_receive = received_with_yield - exchange_fee_seller
  let tx =
    Transaction {
      ..txn,
      redeemers: dict.insert(
        txn.redeemers,
        Spend(sc_in_1.output_reference),
        Sell {
          exchange_fee: exchange_out_lovelace,
          seller_receive,
          offers: [(get_bond_policy_id(), bond_name_1, bond_sell_qty)],
          cont_idx: None,
        },
        script_purpose_compare,
      ),
    }
  withdraw.constraint(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    bid_skh,
    [],
  )
}

test succ_when_sc_bid_stake_key_is_key() {
  let time_of_tx = 1681095094000
  let sc_bid_stake_key_hash = #"080201"
  let cfg = get_config_limit_mainnet()
  let owner_address =
    get_buyer_address() |> with_delegation_key(sc_bid_stake_key_hash)
  let seller_address =
    get_seller_address() |> with_delegation_key(sc_bid_stake_key_hash)
  let sc_in_datum_1 =
    gen_bid_limit_multi_datum(
      owner_address,
      390,
      480,
      5,
      500,
      [DanogoBond, OptimBond],
    )
  let bond_name_1 = get_bond_id_1()
  // get_escrow_datum(asset_name: AssetName, bond_amount: Int, epo_rewards: Int, duration: Int, start: Int)
  let escrow_bond_amount = 10000
  let escrow_epo_rewards = 753424657
  let escrow_duration = 72
  let escrow_datum =
    get_escrow_datum(
      bond_name_1,
      escrow_bond_amount,
      escrow_epo_rewards,
      escrow_duration,
      63,
    )
  // => epoch_start = 22190 epoch_end = 22244
  let escrow_lovelace =
    escrow_bond_amount * 100_000_000 + escrow_epo_rewards * escrow_duration
  let escrow_full_info =
    calc_escrow_full_info(
      cfg.platform,
      escrow_lovelace,
      escrow_datum,
      time_of_tx,
    )
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  //  
  let bond_sell_qty = 5
  let received_at_maturity = escrow_full_info.value_at_maturity * bond_sell_qty
  let received_with_yield = price_of_one_bond * bond_sell_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.seller_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.platform.basis.base
  //
  let owner_out_lovelace = min_ada
  let sc_address =
    get_bid_sc_address() |> with_delegation_key(sc_bid_stake_key_hash)
  let sc_in_lovelace =
    received_with_yield + exchange_fee_buyer + owner_out_lovelace
  let sc_in_1 =
    gen_input(sc_address, sc_in_lovelace, None, InlineDatum(sc_in_datum_1))
  let seller_in_lovelace = 1310316
  let asset_sell =
    value.from_asset(get_bond_policy_id(), bond_name_1, bond_sell_qty)
  let seller_in_1 =
    gen_input(seller_address, seller_in_lovelace, Some(asset_sell), NoDatum)
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_1,
      1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  //
  let exchange_address = get_exchange_address()
  let exchange_out_lovelace = exchange_fee_buyer + exchange_fee_seller
  let exchange_out_1 =
    gen_output(exchange_address, exchange_out_lovelace, None, NoDatum)
  let seller_out_lovelace =
    seller_in_lovelace + received_with_yield - exchange_fee_seller
  let seller_out_1 =
    gen_output(seller_address, seller_out_lovelace, None, NoDatum)
  let owner_out_1 =
    gen_output(owner_address, owner_out_lovelace, Some(asset_sell), NoDatum)
  let txn =
    fixture.tx(
      [sc_in_1, seller_in_1],
      [refer_in_1],
      [exchange_out_1, seller_out_1, owner_out_1],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  let seller_receive = received_with_yield - exchange_fee_seller
  let tx =
    Transaction {
      ..txn,
      redeemers: dict.insert(
        txn.redeemers,
        Spend(sc_in_1.output_reference),
        Sell {
          exchange_fee: exchange_out_lovelace,
          seller_receive,
          offers: [(get_bond_policy_id(), bond_name_1, bond_sell_qty)],
          cont_idx: None,
        },
        script_purpose_compare,
      ),
    }
  withdraw.constraint(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    bid_skh,
    [],
  )
}

test fail_when_buyer_stake_key_is_wrong() fail {
  let time_of_tx = 1681095094000
  let sc_bid_stake_key_hash = #"080201"
  let sc_bid_stake_key_hash_fake = #"080202"
  let cfg = get_config_limit_mainnet()
  let owner_address =
    get_buyer_address() |> with_delegation_key(sc_bid_stake_key_hash)
  let seller_address =
    get_seller_address() |> with_delegation_key(sc_bid_stake_key_hash)
  let sc_in_datum_1 =
    gen_bid_limit_multi_datum(
      owner_address,
      390,
      480,
      5,
      500,
      [DanogoBond, OptimBond],
    )
  let bond_name_1 = get_bond_id_1()
  // get_escrow_datum(asset_name: AssetName, bond_amount: Int, epo_rewards: Int, duration: Int, start: Int)
  let escrow_bond_amount = 10000
  let escrow_epo_rewards = 753424657
  let escrow_duration = 72
  let escrow_datum =
    get_escrow_datum(
      bond_name_1,
      escrow_bond_amount,
      escrow_epo_rewards,
      escrow_duration,
      63,
    )
  // => epoch_start = 22190 epoch_end = 22244
  let escrow_lovelace =
    escrow_bond_amount * 100_000_000 + escrow_epo_rewards * escrow_duration
  let escrow_full_info =
    calc_escrow_full_info(
      cfg.platform,
      escrow_lovelace,
      escrow_datum,
      time_of_tx,
    )
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  //  
  let bond_sell_qty = 5
  let received_at_maturity = escrow_full_info.value_at_maturity * bond_sell_qty
  let received_with_yield = price_of_one_bond * bond_sell_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.seller_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.platform.basis.base
  //
  let owner_out_lovelace = min_ada
  let sc_address =
    get_bid_sc_address() |> with_delegation_key(sc_bid_stake_key_hash)
  let sc_in_lovelace =
    received_with_yield + exchange_fee_buyer + owner_out_lovelace
  let sc_in_1 =
    gen_input(sc_address, sc_in_lovelace, None, InlineDatum(sc_in_datum_1))
  let seller_in_lovelace = 1310316
  let asset_sell =
    value.from_asset(get_bond_policy_id(), bond_name_1, bond_sell_qty)
  let seller_in_1 =
    gen_input(seller_address, seller_in_lovelace, Some(asset_sell), NoDatum)
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_1,
      1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  //
  let exchange_address = get_exchange_address()
  let exchange_out_lovelace = exchange_fee_buyer + exchange_fee_seller
  let exchange_out_1 =
    gen_output(exchange_address, exchange_out_lovelace, None, NoDatum)
  let seller_out_lovelace =
    seller_in_lovelace + received_with_yield - exchange_fee_seller
  let seller_out_1 =
    gen_output(seller_address, seller_out_lovelace, None, NoDatum)
  let owner_out_1 =
    gen_output(
      get_buyer_address() |> with_delegation_key(sc_bid_stake_key_hash_fake),
      owner_out_lovelace,
      Some(asset_sell),
      NoDatum,
    )
  let txn =
    fixture.tx(
      [sc_in_1, seller_in_1],
      [refer_in_1],
      [exchange_out_1, seller_out_1, owner_out_1],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  let seller_receive = received_with_yield - exchange_fee_seller
  let tx =
    Transaction {
      ..txn,
      redeemers: dict.insert(
        txn.redeemers,
        Spend(sc_in_1.output_reference),
        Sell {
          exchange_fee: exchange_out_lovelace,
          seller_receive,
          offers: [(get_bond_policy_id(), bond_name_1, bond_sell_qty)],
          cont_idx: None,
        },
        script_purpose_compare,
      ),
    }
  withdraw.constraint(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    bid_skh,
    [],
  )
}

test fail_unsafe_fee_datum() fail {
  let time_of_tx = 1681095094000
  let cfg = get_config_limit_mainnet()
  let owner_address = get_buyer_address()
  let seller_address = get_seller_address()
  let sc_in_datum_1 =
    gen_bid_limit_multi_datum(
      owner_address,
      390,
      480,
      5,
      500,
      [DanogoBond, OptimBond],
    )
  let bond_name_1 = get_bond_id_1()
  // get_escrow_datum(asset_name: AssetName, bond_amount: Int, epo_rewards: Int, duration: Int, start: Int)
  let escrow_bond_amount = 10000
  let escrow_epo_rewards = 753424657
  let escrow_duration = 72
  let escrow_datum =
    get_escrow_datum(
      bond_name_1,
      escrow_bond_amount,
      escrow_epo_rewards,
      escrow_duration,
      63,
    )
  // => epoch_start = 22190 epoch_end = 22244
  let escrow_lovelace =
    escrow_bond_amount * 100_000_000 + escrow_epo_rewards * escrow_duration
  let escrow_full_info =
    calc_escrow_full_info(
      cfg.platform,
      escrow_lovelace,
      escrow_datum,
      time_of_tx,
    )
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  //  
  let bond_sell_qty = 5
  let received_at_maturity = escrow_full_info.value_at_maturity * bond_sell_qty
  let received_with_yield = price_of_one_bond * bond_sell_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.seller_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.platform.basis.base
  //
  let owner_out_lovelace = min_ada
  let sc_address = get_bid_sc_address()
  let sc_in_lovelace =
    received_with_yield + exchange_fee_buyer + owner_out_lovelace
  let sc_in_1 =
    gen_input(sc_address, sc_in_lovelace, None, InlineDatum(sc_in_datum_1))
  let seller_in_lovelace = 1310316
  let asset_sell =
    value.from_asset(get_bond_policy_id(), bond_name_1, bond_sell_qty)
  let seller_in_1 =
    gen_input(seller_address, seller_in_lovelace, Some(asset_sell), NoDatum)
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_1,
      1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  //
  let exchange_address = get_exchange_address()
  let exchange_out_lovelace = exchange_fee_buyer + exchange_fee_seller
  let exchange_out_1 =
    gen_output(
      exchange_address,
      exchange_out_lovelace,
      None,
      DatumHash("arbitrary_digest"),
    )
  let seller_out_lovelace =
    seller_in_lovelace + received_with_yield - exchange_fee_seller
  let seller_out_1 =
    gen_output(seller_address, seller_out_lovelace, None, NoDatum)
  let owner_out_1 =
    gen_output(owner_address, owner_out_lovelace, Some(asset_sell), NoDatum)
  let txn =
    fixture.tx(
      [sc_in_1, seller_in_1],
      [refer_in_1],
      [exchange_out_1, seller_out_1, owner_out_1],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  let seller_receive = received_with_yield - exchange_fee_seller
  let tx =
    Transaction {
      ..txn,
      redeemers: dict.insert(
        txn.redeemers,
        Spend(sc_in_1.output_reference),
        Sell {
          exchange_fee: exchange_out_lovelace,
          seller_receive,
          offers: [(get_bond_policy_id(), bond_name_1, bond_sell_qty)],
          cont_idx: None,
        },
        script_purpose_compare,
      ),
    }
  withdraw.constraint(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    bid_skh,
    [],
  )
}

test fail_unsafe_payout_datum() fail {
  let time_of_tx = 1681095094000
  let cfg = get_config_limit_mainnet()
  let owner_address = get_buyer_address()
  let seller_address = get_seller_address()
  let sc_in_datum_1 =
    gen_bid_limit_multi_datum(
      owner_address,
      390,
      480,
      5,
      500,
      [DanogoBond, OptimBond],
    )
  let bond_name_1 = get_bond_id_1()
  // get_escrow_datum(asset_name: AssetName, bond_amount: Int, epo_rewards: Int, duration: Int, start: Int)
  let escrow_bond_amount = 10000
  let escrow_epo_rewards = 753424657
  let escrow_duration = 72
  let escrow_datum =
    get_escrow_datum(
      bond_name_1,
      escrow_bond_amount,
      escrow_epo_rewards,
      escrow_duration,
      63,
    )
  // => epoch_start = 22190 epoch_end = 22244
  let escrow_lovelace =
    escrow_bond_amount * 100_000_000 + escrow_epo_rewards * escrow_duration
  let escrow_full_info =
    calc_escrow_full_info(
      cfg.platform,
      escrow_lovelace,
      escrow_datum,
      time_of_tx,
    )
  let price_of_one_bond =
    get_price_of_bond(
      escrow_full_info.value_at_maturity,
      escrow_full_info.day_to_maturity,
      sc_in_datum_1.requested_yield,
      cfg.platform.basis.base,
    )
  //  
  let bond_sell_qty = 5
  let received_at_maturity = escrow_full_info.value_at_maturity * bond_sell_qty
  let received_with_yield = price_of_one_bond * bond_sell_qty
  let received_diff = received_at_maturity - received_with_yield
  let exchange_fee_seller =
    received_diff * cfg.exchange.seller_fee / cfg.platform.basis.base
  let exchange_fee_buyer =
    received_diff * cfg.exchange.buyer_fee / cfg.platform.basis.base
  //
  let owner_out_lovelace = min_ada
  let sc_address = get_bid_sc_address()
  let sc_in_lovelace =
    received_with_yield + exchange_fee_buyer + owner_out_lovelace
  let sc_in_1 =
    gen_input(sc_address, sc_in_lovelace, None, InlineDatum(sc_in_datum_1))
  let seller_in_lovelace = 1310316
  let asset_sell =
    value.from_asset(get_bond_policy_id(), bond_name_1, bond_sell_qty)
  let seller_in_1 =
    gen_input(seller_address, seller_in_lovelace, Some(asset_sell), NoDatum)
  let refer_in_1 =
    get_input_escrow(
      get_escrow_address(),
      get_escrow_policy_id(),
      bond_name_1,
      1,
      escrow_lovelace,
      InlineDatum(escrow_datum),
    )
  //
  let exchange_address = get_exchange_address()
  let exchange_out_lovelace = exchange_fee_buyer + exchange_fee_seller
  let exchange_out_1 =
    gen_output(exchange_address, exchange_out_lovelace, None, NoDatum)
  let seller_out_lovelace =
    seller_in_lovelace + received_with_yield - exchange_fee_seller
  let seller_out_1 =
    gen_output(seller_address, seller_out_lovelace, None, NoDatum)
  let owner_out_1 =
    gen_output(
      owner_address,
      owner_out_lovelace,
      Some(asset_sell),
      DatumHash("arbitrary_digest"),
    )
  let txn =
    fixture.tx(
      [sc_in_1, seller_in_1],
      [refer_in_1],
      [exchange_out_1, seller_out_1, owner_out_1],
      Some([get_buyer_address_hash()]),
      None,
      Some(time_of_tx),
      Some(time_of_tx + 3 * 60 * 1000),
    )
  let seller_receive = received_with_yield - exchange_fee_seller
  let tx =
    Transaction {
      ..txn,
      redeemers: dict.insert(
        txn.redeemers,
        Spend(sc_in_1.output_reference),
        Sell {
          exchange_fee: exchange_out_lovelace,
          seller_receive,
          offers: [(get_bond_policy_id(), bond_name_1, bond_sell_qty)],
          cont_idx: None,
        },
        script_purpose_compare,
      ),
    }
  withdraw.constraint(
    ScriptContext { transaction: tx, purpose: Spend(sc_in_1.output_reference) },
    cfg,
    bid_skh,
    [],
  )
}
