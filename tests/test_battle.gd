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
	check(hp == 640.0 * 3, "소총은 전차에 피해를 주지 못한다")


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
