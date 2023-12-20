use aiken/dict
use aiken/list
use aiken/math
use aiken/transaction.{InlineDatum, OutputReference, Transaction}
use aiken/transaction/credential.{Address, ScriptCredential}
use aiken/transaction/value.{PolicyId}
use bond_issue/types.{BondDatum, BondIssueConfig, RequestDatum}
use common/hash_out_refs.{hash_out_ref_salt}
use common/types.{ScriptKeyHash} as common_types

pub fn burning(tx: Transaction, nft_pid: PolicyId) -> Bool {
  let burn_names =
    dict.foldl(
      value.from_minted_value(tx.mint) |> value.tokens(nft_pid),
      [],
      fn(n, q, z) {
        if (q == -1)? {
          [n, ..z]
        } else {
          fail
        }
      },
    )
  (list.length(burn_names) == 1)?
}

pub fn minting(
  cfg: BondIssueConfig,
  tx: Transaction,
  req_skh: ScriptKeyHash,
  bond_skh: ScriptKeyHash,
  nft_pid: PolicyId,
  req_pid: PolicyId,
  out_ref: OutputReference,
) -> Bool {
  let req_pk = ScriptCredential(req_skh)
  when
    list.foldl(
      tx.inputs,
      (#"", None),
      fn(i, z) {
        if and {
          i.output_reference == out_ref,
          i.output.address.payment_credential == req_pk,
        } {
          expect sreq_dt: RequestDatum =
            when i.output.datum is {
              InlineDatum(d) -> d
              _ -> fail @"only supports InlineDatum for borrow request"
            }
          if and {
            (sreq_dt.apr >= cfg.platform.min_apr)?,
            (sreq_dt.duration >= cfg.platform.min_duration)?,
            (sreq_dt.requested >= cfg.platform.min_requested)?,
            (sreq_dt.buffer >= cfg.platform.min_buffer)?,
            (sreq_dt.prepaid >= math.min(
              sreq_dt.buffer + cfg.platform.prepaid_plus,
              sreq_dt.duration,
            ))?,
            (sreq_dt.prepaid <= sreq_dt.duration)?,
            (sreq_dt.fee >= cfg.platform.fee)?,
            (sreq_dt.requested >= sreq_dt.issued)?,
            (sreq_dt.epo_rewards >= ( sreq_dt.requested - sreq_dt.issued ) * cfg.platform.bond_face_value * sreq_dt.apr / cfg.basis.base / cfg.epoch.year_to_epoch)?,
            (value.quantity_of(i.output.value, req_pid, sreq_dt.borrower) == 1)?,
          } {
            (sreq_dt.borrower, Some(i))
          } else {
            z
          }
        } else {
          z
        }
      },
    )
  is {
    (borrower, Some(i)) -> {
      let bond_name = hash_out_ref_salt(out_ref, borrower)
      let mint_qty =
        value.quantity_of(value.from_minted_value(tx.mint), nft_pid, bond_name)
      let bond_addr =
        Address {
          payment_credential: ScriptCredential(bond_skh),
          stake_credential: i.output.address.stake_credential,
        }
      and {
        (mint_qty == 1)?,
        when
          list.filter(
            tx.outputs,
            fn(o) {
              if o.address == bond_addr {
                expect obond_dt: BondDatum =
                  when o.datum is {
                    InlineDatum(d) -> d
                    _ ->
                      fail @"borrow_position/bond_nft.minting: only supports InlineDatum for bond"
                  }
                and {
                  (obond_dt.borrower == borrower)?,
                  (value.quantity_of(o.value, nft_pid, bond_name) == 1)?,
                }
              } else {
                False
              }
            },
          )
        is {
          [_o] -> True
          _ -> fail @"not found borrow request output"
        },
      }
    }
    _ -> fail @"not found borrow request input"
  }
}
