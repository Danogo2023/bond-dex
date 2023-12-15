use aiken/bytearray
use aiken/dict
use aiken/list
use aiken/option
use aiken/string
use aiken/transaction.{InlineDatum, Output, OutputReference, Transaction}
use aiken/transaction/credential.{ScriptCredential}
use aiken/transaction/value.{PolicyId, Value}
use bond_issue/types.{BondDatum, BondIssueConfig, RequestDatum}
use borrow_position/types.{
  AssetNames, BondData, BorrowRequestData, BurnToken, MintName, PolicyMint,
  TokenDict,
} as borrow_position_types
use borrow_position/utils_nft
use common/hash_inputs.{hash_sorted_salt}
use common/types.{ScriptKeyHash} as common_types
use common/util.{find_while}

pub fn get_borrow_request_input(
  tx: Transaction,
  out_ref: OutputReference,
  req_sk: ScriptKeyHash,
) -> (MintName, BorrowRequestData) {
  let req_credential = ScriptCredential(req_sk)
  let out_ref_input =
    list.find(tx.inputs, fn(i) { i.output_reference == out_ref })
  list.foldr(
    tx.inputs,
    (MintName { count: 0, names: [] }, dict.new()),
    fn(o, z) {
      if o.output.address.payment_credential == req_credential {
        let (mint, data) = z
        expect ireq_dt: RequestDatum =
          when o.output.datum is {
            InlineDatum(d) -> d
            _ ->
              fail @"borrow_position/utils_token.get_borrow_request_input: only supports InlineDatum for request"
          }
        (
          MintName {
            count: mint.count + 1,
            names: [
              hash_sorted_salt(out_ref_input, ireq_dt.borrower),
              ..mint.names
            ],
          },
          dict.insert_with(
            data,
            ireq_dt.borrower,
            (ireq_dt, o.output),
            fn(k, _, _) {
              let log =
                @"borrow_position/utils_token.get_borrow_request_input: only 1 borrow request input is allowed for 1 borrow nft (ireq_dt.borrower="
                  |> string.concat(string.from_bytearray(k))
                  |> string.concat(@")")
              fail log
            },
            bytearray.compare,
          ),
        )
      } else {
        z
      }
    },
  )
}

pub fn get_bond_output(
  cfg: BondIssueConfig,
  tx: Transaction,
  nft_pid: PolicyId,
  bond_sk: ScriptKeyHash,
) -> (MintName, BondData, Option<Output>) {
  let bond_credential = ScriptCredential(bond_sk)
  list.foldr(
    tx.outputs,
    (MintName { count: 0, names: [] }, dict.new(), None),
    fn(o, z) {
      let (mint, data, ofee) = z
      if o.address.payment_credential == bond_credential {
        expect obond_dt: BondDatum =
          when o.datum is {
            InlineDatum(d) -> d
            _ ->
              fail @"borrow_position/utils_token.get_bond_output: only supports InlineDatum for bond"
          }
        let nft_qty = value.quantity_of(o.value, nft_pid, obond_dt.token_name)
        if (nft_qty == 1)? {
          (
            MintName {
              count: mint.count + nft_qty,
              names: [obond_dt.token_name, ..mint.names],
            },
            dict.insert_with(
              data,
              obond_dt.borrower,
              (obond_dt, o),
              fn(k, _, _) {
                let log =
                  @"borrow_position/utils_token.get_bond_output: only 1 nft mining is allowed (obond_dt.borrower="
                    |> string.concat(string.from_bytearray(k))
                    |> string.concat(@")")
                fail log
              },
              bytearray.compare,
            ),
            ofee,
          )
        } else {
          let log =
            @"borrow_position/utils_token.get_bond_output: each bond utxo must contains 1 bond nft ("
              |> string.concat(string.from_bytearray(nft_pid))
              |> string.concat(@".")
              |> string.concat(string.from_bytearray(obond_dt.token_name))
              |> string.concat(@"=")
              |> string.concat(string.from_int(nft_qty))
              |> string.concat(@")")
          fail log
        }
      } else if o.address == cfg.platform.address {
        if ofee == None {
          (mint, data, Some(o))
        } else {
          fail @"borrow_position/utils_token.get_bond_output: only 1 platform fee output is allowed"
        }
      } else {
        z
      }
    },
  )
}

pub fn get_policy_mint(
  mint: Value,
  nft_pid: PolicyId,
  bond_pid: PolicyId,
) -> PolicyMint {
  find_while(
    dict.to_list(value.to_dict(mint)),
    PolicyMint { nfts: dict.new(), bonds: dict.new() },
    fn(i, z) {
      let (k, v) = i
      let r =
        if k == nft_pid {
          PolicyMint { ..z, nfts: v }
        } else if k == bond_pid {
          PolicyMint { ..z, bonds: v }
        } else {
          z
        }
      (!dict.is_empty(r.nfts) && !dict.is_empty(r.bonds), r)
    },
  )
}

pub fn get_mint(
  mint: Value,
  nft_pid: PolicyId,
  bond_pid: PolicyId,
) -> (MintName, TokenDict, TokenDict, AssetNames) {
  let policy_mint = get_policy_mint(mint, nft_pid, bond_pid)
  (
    dict.foldr(
      policy_mint.nfts,
      MintName { count: 0, names: [] },
      fn(k, v, z) {
        if (v == 1)? {
          MintName { count: z.count + v, names: [k, ..z.names] }
        } else {
          let log =
            @"borrow_position/utils_token.get_mint: only 1 bond nft can be mined ("
              |> string.concat(string.from_bytearray(k))
              |> string.concat(@"=")
              |> string.concat(string.from_int(v))
              |> string.concat(@")")
          fail log
        }
      },
    ),
    policy_mint.nfts,
    policy_mint.bonds,
    dict.foldr(policy_mint.bonds, [], fn(k, _, z) { [k, ..z] }),
  )
}

pub fn fee_valid(
  cfg: BondIssueConfig,
  req_data: BorrowRequestData,
  bond_data: BondData,
  bond_mint: TokenDict,
  fee: Option<Output>,
) -> Bool {
  expect Some(fee_output) = fee
  let total_fee =
    dict.foldr(
      bond_data,
      0,
      fn(k, v, z) {
        let (obond_dt, obond) = v
        when dict.get(req_data, k) is {
          Some((ireq_dt, ireq)) -> {
            let mint_bond_amount =
              option.or_else(dict.get(bond_mint, obond_dt.token_name), 0)
            if (mint_bond_amount == obond_dt.bond_amount)? {
              if
              (obond.address.stake_credential == ireq.address.stake_credential)?{
              
                z + value.lovelace_of(obond_dt.epo_rewards) * ireq_dt.prepaid * ireq_dt.fee / cfg.basis.base
              } else {
                fail @"borrow_position/utils_token.fee_valid: stake key of bond output not matching with stake key of borrow request input"
              }
            } else {
              let log =
                @"borrow_position/utils_token.fee_valid: bond token mint amount invalid ("
                  |> string.concat(string.from_int(mint_bond_amount))
                  |> string.concat(@"==")
                  |> string.concat(string.from_int(obond_dt.bond_amount))
                  |> string.concat(@")")
              fail log
            }
          }
          _ ->
            fail @"borrow_position/utils_token.fee_valid: not found borrow request input valid"
        }
      },
    )

  (value.lovelace_of(fee_output.value) >= total_fee)?
}

pub fn get_burn(mint: Value, pid: PolicyId) -> BurnToken {
  dict.foldr(
    utils_nft.get_policy_mint(mint, pid),
    BurnToken { count: 0, names: [], assets: [] },
    fn(k, v, z) {
      if v < 0 {
        BurnToken {
          count: z.count - v,
          names: [k, ..z.names],
          assets: [(k, v), ..z.assets],
        }
      } else {
        z
      }
    },
  )
}

pub fn get_inputs(tx: Transaction, pid: PolicyId) -> BurnToken {
  list.foldr(
    tx.inputs,
    BurnToken { count: 0, names: [], assets: [] },
    fn(i, z) { get_output(i.output, pid, z) },
  )
}

pub fn get_outputs(tx: Transaction, pid: PolicyId) -> BurnToken {
  list.foldr(
    tx.outputs,
    BurnToken { count: 0, names: [], assets: [] },
    fn(o, z) { get_output(o, pid, z) },
  )
}

fn get_output(o: Output, pid: PolicyId, z: BurnToken) -> BurnToken {
  list.foldr(
    dict.to_list(value.tokens(o.value, pid)),
    z,
    fn(a, c) {
      let (k, v) = a
      BurnToken {
        count: c.count + v,
        names: [k, ..c.names],
        assets: [(k, v), ..c.assets],
      }
    },
  )
}

pub fn get_name_burn(mint: Value, pid: PolicyId) -> AssetNames {
  dict.foldr(
    utils_nft.get_policy_mint(mint, pid),
    [],
    fn(k, v, z) {
      if v < 0 {
        [k, ..z]
      } else {
        z
      }
    },
  )
}

pub fn count_burn(mint: Value, pid: PolicyId) -> Int {
  dict.foldr(
    utils_nft.get_policy_mint(mint, pid),
    0,
    fn(_, v, z) {
      if v < 0 {
        z - v
      } else {
        z
      }
    },
  )
}

pub fn count_input(tx: Transaction, pid: PolicyId) -> Int {
  list.foldr(tx.inputs, 0, fn(i, z) { count(i.output, pid, z) })
}

pub fn count_output(tx: Transaction, pid: PolicyId) -> Int {
  list.foldr(tx.outputs, 0, fn(o, z) { count(o, pid, z) })
}

fn count(o: Output, pid: PolicyId, z: Int) -> Int {
  list.foldr(
    dict.to_list(value.tokens(o.value, pid)),
    z,
    fn(a, c) {
      let (_, v) = a
      c + v
    },
  )
}
