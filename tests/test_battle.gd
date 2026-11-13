extends TestCase

var types := UnitType.load_all()


## 한 명짜리, 반드시 맞히는 시험용 병과.
func _duelist() -> UnitType:
	return UnitType.from_dict("duelist", {
		"elements": [{"kind": "man", "count": 1, "hp": 10}],
		"tiles": {"min": 1, "max": 1, "default": 1},
		"sight_m": 600,
		"speed_tiles_per_min": {"foot": 3},
		"weapons": [{"id": "gun", "count": 1, "damage": 100, "pen": [1, 1], "range_m": 400, "interval_s": 1, "accuracy": [1.0, 1.0]}],
	})


func _crowd(n: int) -> UnitType:
	return UnitType.from_dict("crowd", {
		"elements": [{"kind": "man", "count": n, "hp": 80}],
		"tiles": {"min": 1, "max": 1, "default": 1},
		"sight_m": 600,
		"speed_tiles_per_min": {"foot": 3},
		"weapons": [],
	})


func _battle() -> Battle:
	return Battle.new(BattleMap.new(40, 40), 42)


func test_simultaneous_fire_both_fall() -> void:
	var b := _battle()
	var a := b.add_unit(BattleUnit.new("a", "red", _duelist(), Vector2(10, 10), Vector2.DOWN))
	var c := b.add_unit(BattleUnit.new("c", "blue", _duelist(), Vector2(10, 15), Vector2.UP))
	b.step()
	a.reaction["c"] = 0
	c.reaction["a"] = 0
	b.step()
	check(not a.is_alive() and not c.is_alive(), "같은 틱에 서로 쏘면 둘 다 쓰러진다")


func test_reaction_delay_after_spotting() -> void:
	var b := _battle()
	var a := b.add_unit(BattleUnit.new("a", "red", _duelist(), Vector2(10, 10), Vector2.DOWN))
	var c := b.add_unit(BattleUnit.new("c", "blue", _duelist(), Vector2(10, 15), Vector2.UP))
	b.step()
	b.step()
	check(a.is_alive() and c.is_alive(), "발견하고 2초 안에는 쏘지 않는다")
	for i in 3:
		b.step()
	check(not a.is_alive() or not c.is_alive(), "반응 지연이 끝나면 쏜다")


func test_line_of_sight_blocked_by_forest() -> void:
	var b := _battle()
	b.map.fill_rect(Rect2i(0, 12, 40, 3), "forest")
	var a := b.add_unit(BattleUnit.new("a", "red", _duelist(), Vector2(10, 10), Vector2.DOWN))
	var c := b.add_unit(BattleUnit.new("c", "blue", _duelist(), Vector2(10, 17), Vector2.UP))
	b.step()
	check(not b.can_see(a, c) and not b.can_see(c, a), "숲 세 줄 너머는 안 보인다")


func test_no_direct_fire_into_melee_tile() -> void:
	var b := _battle()
	var inf: UnitType = types["infantry_platoon"]
	var red1 := b.add_unit(BattleUnit.new("red1", "red", inf, Vector2(10, 10), Vector2.UP, "line", 2))
	b.add_unit(BattleUnit.new("blue1", "blue", inf, Vector2(10, 10), Vector2.DOWN, "line", 2))
	var red2 := b.add_unit(BattleUnit.new("red2", "red", inf, Vector2(10, 16), Vector2.UP, "line", 2))
	for i in 6:
		b.step()
	check(b.in_melee(red1), "같은 칸이면 근접전")
	check(red2.cooldowns["rifle"] == 0, "밖의 부대는 근접전 칸에 직사하지 않는다")


func test_melee_unit_can_only_retreat() -> void:
	var b := _battle()
	var inf: UnitType = types["infantry_platoon"]
	var red := b.add_unit(BattleUnit.new("red", "red", inf, Vector2(10, 10), Vector2.UP, "line", 2))
	b.add_unit(BattleUnit.new("blue", "blue", inf, Vector2(10, 10), Vector2.DOWN, "line", 2))
	# 저지 태세는 교전 중 제자리를 지키므로, 이동 규칙만 보려고 무시 태세로 둔다.
	red.stance = BattleUnit.Stance.IGNORE
	b.step()
	red.move_target = Vector2(10, 0)
	var before := red.center
	b.step()
	check(red.center == before, "적 칸 쪽으로는 전진하지 못한다")
	red.move_target = Vector2(10, 30)
	b.step()
	check(red.center.y > before.y, "뒤로는 물러난다")


func test_tank_with_unarmed_infantry_causes_shock() -> void:
	var b := _battle()
	var rifles := UnitType.from_dict("rifles", {
		"elements": [{"kind": "man", "count": 10, "hp": 80}],
		"tiles": {"min": 1, "max": 1, "default": 1},
		"sight_m": 600,
		"speed_tiles_per_min": {"foot": 3},
		"weapons": [{"id": "rifle", "count": 10, "damage": 16, "pen": [1, 1], "range_m": 300, "interval_s": 4, "accuracy": [0.15, 0.05]}],
	})
	var inf := b.add_unit(BattleUnit.new("inf", "red", rifles, Vector2(10, 10), Vector2.UP))
	var tank := b.add_unit(BattleUnit.new("tank", "blue", types["medium_tank_platoon"], Vector2(10, 10), Vector2.DOWN, "line", 3))
	b.step()
	check(inf.state() >= Morale.State.PANIC, "대전차 무기가 없으면 강한 충격")
	var hp := 0.0
	for e in tank.elements:
		hp += e["hp"]
	check(hp == 1000.0 * 3, "소총은 전차에 피해를 주지 못한다")


func test_small_arms_do_not_shoot_tanks() -> void:
	var b := _battle()
	var inf := b.add_unit(BattleUnit.new("inf", "red", types["infantry_platoon"], Vector2(10, 10), Vector2.DOWN, "line", 4))
	b.add_unit(BattleUnit.new("tank", "blue", types["medium_tank_platoon"], Vector2(10, 18), Vector2.LEFT, "line", 3))
	for i in 10:
		b.step()
	check(inf.cooldowns["rifle"] == 0 and inf.cooldowns["lmg"] == 0, "소총·경기관총은 전차를 쏘지 않는다")


func test_artillery_hits_both_sides_on_melee_tile() -> void:
	var b := _battle()
	var red := b.add_unit(BattleUnit.new("red", "red", _crowd(40), Vector2(20, 20)))
	var blue := b.add_unit(BattleUnit.new("blue", "blue", _crowd(40), Vector2(20, 20)))
	var mortar_type: UnitType = types["mortar_platoon"]
	b.shells.append({"land_tick": 1, "point": Vector2(20, 20), "weapon": mortar_type.weapons[0], "attacker": null})
	b.step()
	check(red.alive_count() < 40 and blue.alive_count() < 40, "포격은 근접전 칸의 양쪽을 모두 친다")


func test_dense_formation_suffers_more_from_shells() -> void:
	var mortar: WeaponType = (types["mortar_platoon"] as UnitType).weapons[0]
	var dense_losses := 0
	var spread_losses := 0
	for s in 20:
		var b := Battle.new(BattleMap.new(40, 40), s)
		var dense := b.add_unit(BattleUnit.new("dense", "red", types["infantry_platoon"], Vector2(10, 20), Vector2.UP, "line", 2))
		var spread := b.add_unit(BattleUnit.new("spread", "red", types["infantry_platoon"], Vector2(30, 20), Vector2.UP, "line", 8))
		b.shells.append({"land_tick": 1, "point": Vector2(10, 20), "weapon": mortar, "attacker": null})
		b.shells.append({"land_tick": 1, "point": Vector2(30, 20), "weapon": mortar, "attacker": null})
		b.step()
		dense_losses += 30 - dense.alive_count()
		spread_losses += 30 - spread.alive_count()
	check(dense_losses > spread_losses, "좁게 모이면 포격에 더 당한다 (%d vs %d)" % [dense_losses, spread_losses])


func test_predicted_fire_leads_moving_target() -> void:
	var b := _battle()
	var mortar := b.add_unit(BattleUnit.new("m", "red", types["mortar_platoon"], Vector2(20, 38)))
	var target := b.add_unit(BattleUnit.new("t", "blue", types["infantry_platoon"], Vector2(20, 10)))
	target.velocity = Vector2(0.05, 0)
	var w: WeaponType = mortar.type.weapons[0]
	var aim := b.predict_aim(mortar, w, target)
	var flight := 28.0 / w.shell_speed_tiles
	check_near(aim.x, 20 + 0.05 * flight, "이동 방향으로 앞서 쏜다")


func test_guns_must_deploy_after_moving() -> void:
	var b := _battle()
	var at := b.add_unit(BattleUnit.new("at", "red", types["at_gun"], Vector2(10, 10)))
	at.move_target = Vector2(10, 9.9)
	for i in 70:
		b.step()
		if i == 30:
			check(not at.deployed, "움직인 포는 바로 쏘지 못한다")
	check(at.deployed, "멈추고 1분 뒤 다시 전개")


func test_capture_victory() -> void:
	var b := _battle()
	b.victory = {"capture": {"red": [Rect2i(5, 5, 4, 4)]}, "defender": "blue"}
	b.add_unit(BattleUnit.new("red", "red", _crowd(5), Vector2(6, 6)))
	b.add_unit(BattleUnit.new("blue", "blue", _crowd(5), Vector2(30, 30)))
	b.step()
	check(b.winner == "red", "적이 없는 구역에 들어가면 점령")


func test_defender_wins_at_turn_limit() -> void:
	var b := _battle()
	b.turn_limit = 1
	b.victory = {"capture": {"red": [Rect2i(5, 5, 4, 4)]}, "defender": "blue"}
	b.add_unit(BattleUnit.new("red", "red", _crowd(5), Vector2(30, 30)))
	b.add_unit(BattleUnit.new("blue", "blue", _crowd(5), Vector2(6, 6)))
	b.run_turn()
	check(b.winner == "blue", "제한 턴까지 버티면 방어측 승리")


func test_same_seed_same_result() -> void:
	var h1 := _run_practice(1943, 3)
	var h2 := _run_practice(1943, 3)
	var h3 := _run_practice(7, 3)
	check(h1 == h2, "같은 시드와 명령이면 결과가 같다")
	check(h1 != h3, "시드가 다르면 결과가 달라진다")


func _run_practice(seed_value: int, turns: int) -> int:
	var b := StageLoader.load_file("res://data/stages/practice.json", types, seed_value)
	for i in turns:
		b.run_turn()
	return b.state_hash()


func test_shooter_remembers_target() -> void:
	var b := _battle()
	var a := b.add_unit(BattleUnit.new("a", "red", _duelist(), Vector2(10, 10), Vector2.DOWN))
	b.add_unit(BattleUnit.new("c", "blue", _crowd(5), Vector2(10, 15), Vector2.UP))
	b.step()
	a.reaction["c"] = 0
	b.step()
	check(a.last_target == "c" and a.last_fire_tick >= 0, "화면에 그릴 사격 목표를 기억한다")


func test_at_gun_moves_at_infantry_speed() -> void:
	check(types["at_gun"].speed["foot"] == types["infantry_platoon"].speed["foot"], "대전차포는 보병과 같은 속도")


func test_sidestep_keeps_front_and_hold_keeps_order() -> void:
	var b := _battle()
	var a := b.add_unit(BattleUnit.new("a", "red", types["infantry_platoon"], Vector2(10, 10), Vector2.DOWN))
	a.move_target = Vector2(20, 10)
	a.arrive_facing = Vector2.DOWN
	b.step()
	check(a.facing.is_equal_approx(Vector2.DOWN), "전선 자리를 옆으로 옮길 때는 정면을 유지한다")
	b.add_unit(BattleUnit.new("c", "blue", _crowd(5), Vector2(11, 15), Vector2.UP))
	for i in 3:
		b.step()
	check(a.move_target != null, "저지 태세 교전은 명령을 지우지 않는다")
	check(a.hold_reason == "engaged", "멈춘 까닭을 남긴다")


func test_attack_does_not_chase_routed_enemy() -> void:
	var b := _battle()
	var a := b.add_unit(BattleUnit.new("a", "red", _crowd(5), Vector2(10, 10), Vector2.DOWN))
	a.stance = BattleUnit.Stance.ATTACK
	a.move_target = Vector2(30, 10)
	var c := b.add_unit(BattleUnit.new("c", "blue", _crowd(5), Vector2(10, 16), Vector2.UP))
	c.morale = 5.0
	for i in 5:
		b.step()
	check(a.center.x > 10.0, "패주하는 적은 쫓지 않고 명령대로 간다")


func test_adjacent_tanks_do_not_deadlock() -> void:
	var b := _battle()
	var tank: UnitType = types["medium_tank_platoon"]
	var a := b.add_unit(BattleUnit.new("a", "red", tank, Vector2(10, 20), Vector2.UP, "line", 3))
	var c := b.add_unit(BattleUnit.new("c", "red", tank, Vector2(13, 20), Vector2.UP, "line", 3))
	a.move_target = Vector2(10, 5)
	c.move_target = Vector2(13, 5)
	for i in 30:
		b.step()
	check(a.center.y < 18.0 and c.center.y < 18.0, "붙어 선 전차 소대가 서로 막지 않는다")


func test_routed_infantry_does_not_hold_tank() -> void:
	var b := _battle()
	var t := b.add_unit(BattleUnit.new("t", "red", types["medium_tank_platoon"], Vector2(10, 10), Vector2.UP, "line", 3))
	var inf := b.add_unit(BattleUnit.new("i", "blue", types["infantry_platoon"], Vector2(10, 10), Vector2.DOWN, "line", 3))
	inf.morale = 5.0
	b.step()
	check(not b.in_melee(t), "전차는 근접전에 묶이지 않는다")
	t.move_target = Vector2(10, 2)
	var y := t.center.y
	b.step()
	check(t.center.y < y, "보병 사이를 지나 전진한다")


func test_mortar_does_not_pin_tanks_or_shock_repeatedly() -> void:
	var b := _battle()
	var t := b.add_unit(BattleUnit.new("t", "red", types["medium_tank_platoon"], Vector2(10, 10), Vector2.UP, "line", 3))
	var inf := b.add_unit(BattleUnit.new("i", "red", _crowd(30), Vector2(20, 10), Vector2.UP))
	var m := b.add_unit(BattleUnit.new("m", "blue", types["mortar_platoon"], Vector2(15, 39), Vector2.UP))
	var w: WeaponType = m.type.weapons[0]
	for i in 60:
		b.shells.append({"land_tick": b.tick + 1, "point": t.center, "weapon": w, "attacker": m})
		b.shells.append({"land_tick": b.tick + 1, "point": inf.center, "weapon": w, "attacker": m})
		b.step()
	check(t.suppression == 0.0 and t.shock_ticks == 0, "포탄은 전차를 제압하지 않는다")
	check(inf.morale > 40.0 or inf.alive_count() < 25, "사상자 없이 포격만으로 패닉에 빠지지 않는다")


func test_firing_reveals_shooter_to_target() -> void:
	var b := _battle()
	b.map.fill_rect(Rect2i(0, 18, 40, 3), "forest")
	var gun := b.add_unit(BattleUnit.new("g", "red", types["at_gun"], Vector2(10, 19), Vector2.DOWN))
	var tank := b.add_unit(BattleUnit.new("t", "blue", types["medium_tank_platoon"], Vector2(10, 30), Vector2.UP, "line", 3))
	b.step()
	check(not b.can_see(tank, gun), "숲 속 대전차포는 처음에는 안 보인다")
	gun.last_target = "t"
	gun.last_fire_tick = b.tick
	b.step()
	check(b.can_see(tank, gun), "쏘면 맞은 쪽에 위치가 드러난다")


func test_tank_drives_around_forest() -> void:
	var b := _battle()
	b.map.fill_rect(Rect2i(5, 15, 10, 3), "forest")
	var t := b.add_unit(BattleUnit.new("t", "red", types["medium_tank_platoon"], Vector2(10, 25), Vector2.UP, "line", 3))
	t.move_target = Vector2(10, 8)
	var max_x := 0.0
	for i in 200:
		b.step()
		max_x = maxf(max_x, t.center.x)
	check(t.move_target == null, "목표에 닿는다")
	check(max_x > 14.0, "숲을 뚫지 않고 돌아간다")


func test_waypoints_are_followed_in_order() -> void:
	var b := _battle()
	var u := b.add_unit(BattleUnit.new("u", "red", _crowd(5), Vector2(5, 5)))
	Orders.move(u, Vector2(5, 8))
	Orders.add_waypoint(u, Vector2(8, 8))
	check(Orders.final_destination(u) == Vector2(8, 8), "마지막 목적지는 마지막 경유점")
	var passed_corner := false
	for i in 200:
		b.step()
		if u.center.distance_to(Vector2(5, 8)) < 0.3:
			passed_corner = true
	check(passed_corner, "첫 목표를 지난다")
	check(u.center.distance_to(Vector2(8, 8)) < 0.01 and u.move_target == null, "경유점까지 간다")


func test_enemy_next_to_objective_contests_capture() -> void:
	var b := _battle()
	var rect := Rect2i(10, 10, 4, 4)
	b.add_unit(BattleUnit.new("a", "red", _crowd(5), Vector2(11, 11)))
	check(b.holds("red", rect), "구역 안에 아군만 있으면 점령")
	var e := b.add_unit(BattleUnit.new("e", "blue", _crowd(5), Vector2(11, 15)))
	check(not b.holds("red", rect), "구역 바로 밖의 적도 점령을 막는다")
	e.morale = 5.0
	check(b.holds("red", rect), "패주한 적은 막지 못한다")


func test_tanks_pass_head_on() -> void:
	var b := _battle()
	var tank: UnitType = types["medium_tank_platoon"]
	var a := b.add_unit(BattleUnit.new("a", "red", tank, Vector2(10, 30), Vector2.UP, "line", 3))
	var c := b.add_unit(BattleUnit.new("c", "red", tank, Vector2(10, 10), Vector2.DOWN, "line", 3))
	a.move_target = Vector2(10, 5)
	c.move_target = Vector2(10, 35)
	for i in 240:
		b.step()
	check(a.move_target == null and c.move_target == null, "마주 오는 전차 소대가 비켜 지나간다")


func test_gun_fire_needs_crew() -> void:
	var m := BattleUnit.new("m", "red", types["mortar_platoon"], Vector2(10, 10))
	var w: WeaponType = m.type.weapons[0]
	check(m.weapon_count(w) == 3, "온전하면 세 문")
	for i in m.elements.size():
		if m.elements[i]["kind"] == "man" and i < m.elements.size() - 2:
			m.elements[i]["hp"] = 0.0
	check(m.weapon_count(w) == 1, "사수 둘이면 한 문만 쏜다")


func test_focus_target_is_shot_first() -> void:
	var b := _battle()
	var a := b.add_unit(BattleUnit.new("a", "red", _duelist(), Vector2(10, 10), Vector2.DOWN))
	b.add_unit(BattleUnit.new("near", "blue", _crowd(5), Vector2(10, 13), Vector2.UP))
	var far := b.add_unit(BattleUnit.new("far", "blue", _crowd(5), Vector2(10, 20), Vector2.UP))
	Orders.focus(a, far)
	for i in 6:
		b.step()
	check(a.last_target == "far", "가까운 적보다 우선 사격 목표를 먼저 쏜다")


func test_reachable_respects_terrain() -> void:
	var map := BattleMap.new(40, 40)
	map.fill_rect(Rect2i(0, 12, 40, 6), "forest")
	var reach := map.reachable(Vector2(20, 20), 6.0, true)
	check(reach.has(Vector2i(26, 20)) and not reach.has(Vector2i(27, 20)), "개활지는 이동량만큼")
	check(reach.has(Vector2i(20, 17)) and not reach.has(Vector2i(20, 16)), "숲은 전차가 느리게 들어간다")


func test_firing_unit_in_forest_is_exposed() -> void:
	var b := _battle()
	b.map.fill_rect(Rect2i(0, 8, 40, 4), "forest")
	var hidden := b.add_unit(BattleUnit.new("h", "blue", _duelist(), Vector2(10, 11), Vector2.DOWN))
	var watcher := b.add_unit(BattleUnit.new("w", "red", _crowd(5), Vector2(12, 30), Vector2.UP))
	b.add_unit(BattleUnit.new("bait", "red", _crowd(5), Vector2(10, 14), Vector2.UP))
	b.step()
	check(not b.can_see(watcher, hidden), "숲 속에 가만히 있는 적은 멀리서 안 보인다")
	for i in 8:
		b.step()
	check(hidden.last_target == "bait", "숲 속 부대가 가까운 적을 쏜다")
	check(b.can_see(watcher, hidden), "쏘고 나면 표적이 아닌 부대에게도 보인다")


func test_visible_tiles_respect_concealment_and_los() -> void:
	var b := _battle()
	b.map.fill_rect(Rect2i(0, 10, 40, 4), "forest")
	var u := b.add_unit(BattleUnit.new("u", "red", _crowd(5), Vector2(20, 20), Vector2.UP))
	var seen := b.visible_tiles(u)
	check(seen.has(Vector2i(20, 15)), "개활지는 보인다")
	check(not seen.has(Vector2i(20, 6)), "숲 너머는 안 보인다")


func test_tank_point_fire_shells_a_spot_in_sight() -> void:
	var types := UnitType.load_all()
	var b := _battle()
	var tank := b.add_unit(BattleUnit.new("t", "red", types["medium_tank_platoon"], Vector2(20, 30), Vector2.UP))
	var hidden := b.add_unit(BattleUnit.new("h", "blue", _crowd(20), Vector2(20, 8), Vector2.DOWN))
	b.map.fill_rect(Rect2i(15, 6, 10, 3), "forest")
	Orders.fire_at_point(tank, Vector2(20, 8))
	for i in 40:
		b.step()
	check(not b.side_knows("red", hidden), "숲 속 적은 여전히 보이지 않는다")
	check(tank.last_fire_point != null and hidden.turn_log.get("shelled", 0) > 0, "전차가 지점에 고폭탄을 쏜다")
	check(hidden.suppression > 0.0 or hidden.alive_count() < 20, "맞은 쪽이 제압되거나 피해를 입는다")
	var behind := b.add_unit(BattleUnit.new("t2", "red", types["medium_tank_platoon"], Vector2(20, 36), Vector2.UP))
	b.map.fill_rect(Rect2i(10, 32, 20, 3), "forest")
	Orders.fire_at_point(behind, Vector2(20, 8))
	for i in 20:
		b.step()
	check(behind.last_fire_point == null, "숲에 가려 시선이 닿지 않으면 쏘지 못한다")
