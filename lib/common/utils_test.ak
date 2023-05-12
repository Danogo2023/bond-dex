use bond/fixture.{get_slot_config_network_test_1,
  get_slot_config_network_test_2}
use common/utils.{posix_time_to_enclosing_slot, slot_to_begin_posix_time}

test slot_to_begin_posix_time_1() {
  slot_to_begin_posix_time(380273, get_slot_config_network_test_1()) == 1667036273000
}

test slot_to_begin_posix_time_2() {
  slot_to_begin_posix_time(26682, get_slot_config_network_test_2()) == 1591592973000
}

test posix_time_to_enclosing_slot_1() {
  posix_time_to_enclosing_slot(1667036273000, get_slot_config_network_test_1()) == 380273
}

test posix_time_to_enclosing_slot_2() {
  posix_time_to_enclosing_slot(1591592973000, get_slot_config_network_test_2()) == 26682
}
