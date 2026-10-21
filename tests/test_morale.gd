extends TestCase


func test_states_by_morale() -> void:
	check(Morale.state_for(100, 0) == Morale.State.STEADY, "100 안정")
	check(Morale.state_for(70, 0) == Morale.State.STEADY, "70 안정")
	check(Morale.state_for(69.9, 0) == Morale.State.SHAKEN, "70 미만 동요")
	check(Morale.state_for(39.9, 0) == Morale.State.PANIC, "40 미만 패닉")
	check(Morale.state_for(14.9, 0) == Morale.State.ROUTED, "15 미만 패주")


func test_shock_sets_minimum_state() -> void:
	check(Morale.state_for(100, 1) == Morale.State.SHAKEN, "약한 충격은 최소 동요")
	check(Morale.state_for(100, 2) == Morale.State.PANIC, "강한 충격은 최소 패닉")
	check(Morale.state_for(10, 1) == Morale.State.ROUTED, "충격이 패주를 가볍게 하지 않음")


func test_shock_time_by_experience() -> void:
	check(Morale.shock_ticks("recruit") == 30, "신병 30초")
	check(Morale.shock_ticks("regular") == 20, "일반 20초")
	check(Morale.shock_ticks("elite") == 10, "정예 10초")
