use bond/fixture.{get_epoch_config_test_1, get_epoch_config_test_2}
use bond/utils.{
  get_day_to_maturity, get_milliseconds_of_day, get_price_of_bond,
  posix_time_to_relative_epoch, relative_epoch_to_posix_time_end,
  relative_epoch_to_posix_time_start,
}

test get_day_to_maturity_test_1() {
  let epoch_config =
    get_epoch_config_test_1()
  let tx_time: Int =
    1682576167903
  let end_epoch: Int =
    19593
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
  get_day_to_maturity(tx_time, end_epoch, epoch_config) == 5
}

test get_day_to_maturity_test_5() {
  let epoch_config =
    get_epoch_config_test_1()
  let tx_time: Int =
    1682576167903 - ( 360000 - 283097 )
  let end_epoch: Int =
    19593
  // let maturity_time: Int = relative_epoch_to_posix_time_end(end_epoch, epoch_config)
  // let time_of_day = get_milliseconds_of_day(epoch_config)
  // ( maturity_time - tx_time ) % time_of_day == 0
  // ( maturity_time - tx_time ) / time_of_day == 5
  get_day_to_maturity(tx_time, end_epoch, epoch_config) == 5
}

test get_day_to_maturity_test_6() {
  let epoch_config =
    get_epoch_config_test_1()
  let tx_time: Int =
    1682576167903 + 283097
  let end_epoch: Int =
    19593
  // let maturity_time: Int = relative_epoch_to_posix_time_end(end_epoch, epoch_config)
  // let time_of_day = get_milliseconds_of_day(epoch_config)
  // ( maturity_time - tx_time ) % time_of_day == 0
  // ( maturity_time - tx_time ) / time_of_day == 4
  get_day_to_maturity(tx_time, end_epoch, epoch_config) == 4
}

test get_day_to_maturity_test_2() {
  get_day_to_maturity(1682577892000, 19593, get_epoch_config_test_1()) == 0
}

test get_day_to_maturity_test_4() {
  get_day_to_maturity(1682576167903, 19593, get_epoch_config_test_1()) == 5
}

test relative_epoch_to_posix_time_start_test_4() {
  relative_epoch_to_posix_time_start(19593 + 1, get_epoch_config_test_1()) == 1682577891000
}

test relative_epoch_to_posix_time_start_test_5() {
  relative_epoch_to_posix_time_end(19593, get_epoch_config_test_1()) == 1682577891000
}

test get_day_to_maturity_test_3() {
  get_day_to_maturity(
    relative_epoch_to_posix_time_start(390, get_epoch_config_test_2()),
    462,
    get_epoch_config_test_2(),
  ) == 365
}

test get_epoch_length_rate_test_1() {
  get_milliseconds_of_day(get_epoch_config_test_1()) == 360000
}

test get_epoch_length_rate_test_2() {
  get_milliseconds_of_day(get_epoch_config_test_2()) == 86400000
}

test posix_time_to_relative_epoch_test_1() {
  posix_time_to_relative_epoch(1680670422833, get_epoch_config_test_1()) == 18534
}

test posix_time_to_relative_epoch_test_2() {
  posix_time_to_relative_epoch(1680670422833, get_epoch_config_test_2()) == 403
}

test relative_epoch_to_posix_time_start_test_1() {
  relative_epoch_to_posix_time_start(18534, get_epoch_config_test_1()) == 1680669891000
}

test relative_epoch_to_posix_time_start_test_2() {
  relative_epoch_to_posix_time_start(403, get_epoch_config_test_2()) == 1680299091000
}

test relative_epoch_to_posix_time_start_test_3() {
  relative_epoch_to_posix_time_start(462, get_epoch_config_test_2()) == 1705787091000
}

test relative_epoch_to_posix_time_end_test_1() {
  relative_epoch_to_posix_time_end(18534, get_epoch_config_test_1()) == 1680671691000
}

test relative_epoch_to_posix_time_end_test_2() {
  relative_epoch_to_posix_time_end(403, get_epoch_config_test_2()) == 1680731091000
}

test get_price_of_bond_test_1() {
  get_price_of_bond(104660000, 85, 550, 10000) == 103336445
}

test get_price_of_bond_test_2() {
  get_price_of_bond(313980000, 85, 550, 10000) == 310009335
}

test get_price_of_bond_test1() {
  // 1285479.4520547944
  552 * 10000 * 85 / 365 == 1285479
}

test get_price_of_bond_test2() {
  // 1283150.6849315069
  551 * 10000 * 85 / 365 == 1283150
}

test get_price_of_bond_test3() {
  // 2328.7671232876714
  1 * 10000 * 85 / 365 == 2328
}

test get_price_of_bond_test4() {
  // 4657.534246575343
  2 * 10000 * 85 / 365 == 4657
}

test get_price_of_bond_test5() {
  // 23285342.465753425
  9999 * 10000 * 85 / 365 == 23285342
}

test get_price_of_bond_test6() {
  // 128082.19178082192
  55 * 10000 * 85 / 365 == 128082
}

test get_price_of_bond_test7() {
  // 101280821.91780822
  10000 * 10000 + 550 * 10000 * 85 / 365 == 101280821
}

test get_price_of_bond_test8() {
  // 103336445.11037287
  104660000 * ( 10000 * 10000 ) / (
    ( 10000 * 10000 + 550 * 10000 * 85 / 365 ) * 10 / 10
  ) == 103336445
}
