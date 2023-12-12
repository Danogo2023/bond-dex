use aiken/dict
use aiken/list
use aiken/transaction.{InlineDatum, Output, OutputReference, Transaction}
use aiken/transaction/credential.{ScriptCredential}
use aiken/transaction/value.{PolicyId, Value}
use bond_issue/types.{BondDatum, RequestDatum} as bond_issue_types
use borrow_position/types.{AssetNames, MintName, TokenDict}
use common/hash_inputs.{hash_sorted_salt}
use common/types.{ScriptKeyHash} as common_types
use common/util.{find_while}

pub fn get_borrow_request_input(
  tx: Transaction,
  out_ref: OutputReference,
  req_sk: ScriptKeyHash,
) -> MintName {
  let req_credential = ScriptCredential(req_sk)
  let out_ref_input =
    list.find(tx.inputs, fn(i) { i.output_reference == out_ref })
  list.foldr(
    tx.inputs,
    MintName { count: 0, names: [] },
    fn(o, z) {
      if o.output.address.payment_credential == req_credential {
        expect ireq_dt: RequestDatum =
          when o.output.datum is {
            InlineDatum(d) -> d
            _ -> fail @"only supports InlineDatum for request"
          }
        MintName {
          count: z.count + 1,
          names: [hash_sorted_salt(out_ref_input, ireq_dt.borrower), ..z.names],
        }
      } else {
        z
      }
    },
  )
}

pub fn get_bond_output(
  tx: Transaction,
  nft_pid: PolicyId,
  bond_sk: ScriptKeyHash,
) -> MintName {
  let bond_credential = ScriptCredential(bond_sk)
  list.foldr(
    tx.outputs,
    MintName { count: 0, names: [] },
    fn(o, z) {
      if o.address.payment_credential == bond_credential {
        expect obond_dt: BondDatum =
          when o.datum is {
            InlineDatum(d) -> d
            _ -> fail @"only supports InlineDatum for bond"
          }
        let nft_qty = value.quantity_of(o.value, nft_pid, obond_dt.token_name)
        if (nft_qty == 1)? {
          MintName {
            count: z.count + nft_qty,
            names: [obond_dt.token_name, ..z.names],
          }
        } else {
          fail @"each bond utxo must contains 1 bond nft"
        }
      } else {
        z
      }
    },
  )
}

pub fn get_policy_mint(mint: Value, pid: PolicyId) -> TokenDict {
  find_while(
    dict.to_list(value.to_dict(mint)),
    dict.new(),
    fn(i, z) {
      let (k, v) = i
      let r =
        if k == pid {
          v
        } else {
          z
        }
      (!dict.is_empty(r), r)
    },
  )
}

pub fn get_mint(mint: Value, nft_pid: PolicyId) -> MintName {
  dict.foldr(
    get_policy_mint(mint, nft_pid),
    MintName { count: 0, names: [] },
    fn(k, v, z) {
      if (v == 1)? {
        MintName { count: z.count + v, names: [k, ..z.names] }
      } else {
        fail @"only 1 bond nft can be minting"
      }
    },
  )
}

pub fn get_name_burn(mint: Value, nft_pid: PolicyId) -> AssetNames {
  dict.foldr(
    get_policy_mint(mint, nft_pid),
    [],
    fn(k, v, z) {
      if v < 0 {
        if v == -1 {
          [k, ..z]
        } else {
          fail @"only 1 bond nft can be burn"
        }
      } else {
        z
      }
    },
  )
}

pub fn get_name_inputs(
  tx: Transaction,
  nft_pid: PolicyId,
  bond_pid: PolicyId,
) -> AssetNames {
  list.foldr(
    tx.inputs,
    [],
    fn(i, z) { get_name(i.output, nft_pid, bond_pid, z) },
  )
}

pub fn get_name_outputs(
  tx: Transaction,
  nft_pid: PolicyId,
  bond_pid: PolicyId,
) -> AssetNames {
  list.foldr(tx.outputs, [], fn(o, z) { get_name(o, nft_pid, bond_pid, z) })
}

fn get_name(
  o: Output,
  nft_pid: PolicyId,
  bond_pid: PolicyId,
  z: AssetNames,
) -> AssetNames {
  let nft_assets = dict.to_list(value.tokens(o.value, nft_pid))
  let count = list.length(nft_assets)
  if count == 1 {
    expect obond_dt: BondDatum =
      when o.datum is {
        InlineDatum(d) -> d
        _ -> fail @"only supports InlineDatum for bond"
      }
    if obond_dt.bond_symbol == bond_pid {
      expect Some((nft_name, _)) = list.head(nft_assets)
      if nft_name == obond_dt.token_name {
        [nft_name, ..z]
      } else {
        fail @"unmatching token_name"
      }
    } else {
      fail @"unmatching bond_symbol"
    }
  } else if count > 1 {
    fail @"each bond utxo can only contain 1 nft"
  } else {
    z
  }
}
