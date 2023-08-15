use bond/fixture.{get_epoch_config_mainnet, get_epoch_config_preview}
use bond/utils.{
  get_day_to_maturity, get_milliseconds_of_day, get_price_of_bond,
  posix_time_to_relative_epoch, relative_epoch_to_posix_time_end,
  relative_epoch_to_posix_time_start,
}

test get_day_to_maturity_1() {
  let epoch_config = get_epoch_config_preview()
  let tx_time: Int = 1682576167903
  let end_epoch: Int = 19593
  // let maturity_time: Int = relative_epoch_to_posix_time_end(end_epoch, epoch_config)
  // let diff_time = maturity_time - tx_time
  // let time_of_day = get_milliseconds_of_day(epoch_config)
  // let maturity_day = diff_time / time_of_day
  // ( maturity_time - tx_time ) % time_of_day == 283097
  // ( maturity_time - tx_time ) / time_of_day == 4
  // when diff_time % time_of_day is {
  //   0 -> maturity_day
  //   _ -> maturity_day + 1
  // } == 5
  get_day_to_maturity(tx_time, end_epoch, epoch_config) == 0
}

test get_day_to_maturity_5() {
  let epoch_config = get_epoch_config_preview()
  let tx_time: Int = 1682576167903 - ( 360000 - 283097 )
  let end_epoch: Int = 19593
  // let maturity_time: Int = relative_epoch_to_posix_time_end(end_epoch, epoch_config)
  // let time_of_day = get_milliseconds_of_day(epoch_config)
  // ( maturity_time - tx_time ) % time_of_day == 0
  // ( maturity_time - tx_time ) / time_of_day == 5
  get_day_to_maturity(tx_time, end_epoch, epoch_config) == 0
}

test get_day_to_maturity_6() {
  let epoch_config = get_epoch_config_preview()
  let tx_time: Int = 1682576167903 + 283097
  let end_epoch: Int = 19593
  // let maturity_time: Int = relative_epoch_to_posix_time_end(end_epoch, epoch_config)
  // let time_of_day = get_milliseconds_of_day(epoch_config)
  // ( maturity_time - tx_time ) % time_of_day == 0
  // ( maturity_time - tx_time ) / time_of_day == 4
  get_day_to_maturity(tx_time, end_epoch, epoch_config) == 0
}

test get_day_to_maturity_2() {
  get_day_to_maturity(1682577892000, 19593, get_epoch_config_preview()) == 0
}

test get_day_to_maturity_4() {
  get_day_to_maturity(1682576167903, 19593, get_epoch_config_preview()) == 0
}

test relative_epoch_to_posix_time_start_4() {
  relative_epoch_to_posix_time_start(19593 + 1, get_epoch_config_preview()) == 1682577891000
}

test relative_epoch_to_posix_time_start_5() {
  relative_epoch_to_posix_time_end(19593, get_epoch_config_preview()) == 1682577891000
}

test get_day_to_maturity_3() {
  get_day_to_maturity(
    relative_epoch_to_posix_time_start(390, get_epoch_config_mainnet()),
    462,
    get_epoch_config_mainnet(),
  ) == 360
}

test get_epoch_length_rate_1() {
  get_milliseconds_of_day(get_epoch_config_preview()) == 360000
}

test get_epoch_length_rate_2() {
  get_milliseconds_of_day(get_epoch_config_mainnet()) == 86400000
}

test posix_time_to_relative_epoch_preview() {
  posix_time_to_relative_epoch(1687343990000, get_epoch_config_preview()) == 22241
  // posix_time_to_relative_epoch(1680670422833, get_epoch_config_preview()) == 18534
}

test posix_time_to_relative_epoch_mainnet() {
  posix_time_to_relative_epoch(1680670422833, get_epoch_config_mainnet()) == 403
}

test relative_epoch_to_posix_time_start_preview() {
  relative_epoch_to_posix_time_start(18534, get_epoch_config_preview()) == 1680669891000
}

test relative_epoch_to_posix_time_start_mainnet() {
  relative_epoch_to_posix_time_start(403, get_epoch_config_mainnet()) == 1680299091000
}

test relative_epoch_to_posix_time_start_3() {
  relative_epoch_to_posix_time_start(462, get_epoch_config_mainnet()) == 1705787091000
}

test relative_epoch_to_posix_time_end_1() {
  relative_epoch_to_posix_time_end(18534, get_epoch_config_preview()) == 1680671691000
}

test relative_epoch_to_posix_time_end_2() {
  relative_epoch_to_posix_time_end(403, get_epoch_config_mainnet()) == 1680731091000
}

test get_price_of_bond_1() {
  get_price_of_bond(104660000, 85, 550, 10000) == 103336445
}

test get_price_of_bond_2() {
  get_price_of_bond(313980000, 85, 550, 10000) == 310009335
}
