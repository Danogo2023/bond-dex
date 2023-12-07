use aiken/list
use aiken/transaction.{InlineDatum, Output, Transaction}
use aiken/transaction/credential.{ScriptCredential}
use aiken/transaction/value.{PolicyId}
use bond_staking/types.{RequestConfig, RequestDatum}
use bond_staking/utils.{mint_only_one, request_output_valid}
use common/hash_inputs.{hash_head}
use common/types.{ScriptKeyHash} as common_types

pub fn minting(
  pid: PolicyId,
  tx: Transaction,
  cfg: RequestConfig,
  sk: ScriptKeyHash,
) -> Bool {
  when
    list.foldr(
      tx.outputs,
      None,
      fn(o, c) {
        if o.address.payment_credential == ScriptCredential(sk) {
          if c == None {
            Some((o.datum, o))
          } else {
            fail @"only 1 request output is allowed"
          }
        } else {
          c
        }
      },
    )
  is {
    Some((data, output)) ->
      when data is {
        InlineDatum(dt) -> {
          expect d: RequestDatum = dt
          and {
            (output.address.stake_credential != None)?,
            (d.issued == 0)?,
            (d.symbol == pid)?,
            request_output_valid(value.lovelace_of(output.value), d, cfg),
            (d.borrower == hash_head(tx.inputs))?,
            mint_only_one(tx, pid, d.borrower),
          }
        }
        _ -> fail @"only supports InlineDatum"
      }
    _ -> fail @"only 1 request output is allowed"
  }
}
