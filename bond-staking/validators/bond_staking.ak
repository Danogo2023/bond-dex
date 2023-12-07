use aiken/transaction.{Mint, ScriptContext}
use bond_staking/request
use bond_staking/types.{RequestAction, RequestConfig, RequestCreate}

validator(cfg: RequestConfig) {
  fn request_mint(ac: RequestAction, ctx: ScriptContext) -> Bool {
    when ctx.purpose is {
      Mint(p) ->
        when ac is {
          RequestCreate { sk } -> request.minting(p, ctx.transaction, cfg, sk)
          _ -> fail @"invalid action"
        }
      _ -> fail @"only supports mint"
    }
  }
}
