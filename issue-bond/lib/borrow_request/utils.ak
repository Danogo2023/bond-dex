use aiken/list
use aiken/transaction.{Input, OutputReference, ScriptContext, Spend}
use common/util.{find_while}

pub fn get_input_out_ref(
  inputs: List<Input>,
  out_ref: OutputReference,
) -> OutputReference {
  expect Some(sreq) = list.find(inputs, fn(i) { i.output_reference == out_ref })
  sreq.output_reference
}

pub fn get_out_ref(
  ctx: ScriptContext,
  out_ref: OutputReference,
) -> (Input, Option<Input>) {
  expect Spend(sout_ref) = ctx.purpose
  expect (Some(spending_input), out_ref_input) =
    find_while(
      ctx.transaction.inputs,
      (None, None),
      fn(i, z) {
        let r =
          if i.output_reference == sout_ref {
            (Some(i), z.2nd)
          } else if i.output_reference == out_ref {
            (z.1st, Some(i))
          } else {
            z
          }
        (r.1st != None && r.2nd != None, r)
      },
    )
  (spending_input, out_ref_input)
}
