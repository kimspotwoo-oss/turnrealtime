extends TestCase

var types := UnitType.load_all()


func _setup() -> Dictionary:
	var b := Battle.new(BattleMap.new(60, 40), 5)
	var line := FrontLine.new("ai_main", "ai", PackedVector2Array([Vector2(8, 18), Vector2(52, 18)]), Vector2(0, 1))
	for i in 2:
		var u := b.add_unit(BattleUnit.new("d%d" % i, "ai", types["infantry_platoon"], Vector2(19 + i * 22, 18), Vector2(0, 1)))
		line.units.append(u.id)
	b.add_unit(BattleUnit.new("res_inf", "ai", types["infantry_platoon"], Vector2(20, 8), Vector2(0, 1)))
	b.add_unit(BattleUnit.new("res_tank", "ai", types["medium_tank_platoon"], Vector2(40, 6), Vector2(0, 1)))
	line.reserves.assign(["res_inf", "res_tank"])
	line.apply(b)
	b.front_lines.append(line)
	var ai := DefenseAI.new("ai", line, [Rect2i(16, 6, 8, 6)])
	b.ai_players.append(ai)
	return {"battle": b, "line": line, "ai": ai}


func _settle_line(b: Battle) -> void:
	for i in 60:
		b.step()


func test_ai_ignores_enemies_it_has_not_seen() -> void:
	var s := _setup()
	var b: Battle = s["battle"]
	b.map.fill_rect(Rect2i(0, 22, 60, 4), "forest")
	_settle_line(b)
	for i in 3:
		b.add_unit(BattleUnit.new("e%d" % i, "player", types["infantry_platoon"], Vector2(18 + i * 4, 30), Vector2(0, -1)))
	b.step()
	(s["ai"] as DefenseAI).plan_turn(b)
	check((s["line"] as FrontLine).reserves.size() == 2, "숲 너머 안 보이는 적에는 반응하지 않는다")


## 목표 수비대로 묶이지 않는 보병 예비대를 하나 더 둔다.
func _add_spare(s: Dictionary) -> void:
	(s["battle"] as Battle).add_unit(BattleUnit.new("res_inf2", "ai", types["infantry_platoon"], Vector2(28, 12), Vector2(0, 1)))
	(s["line"] as FrontLine).reserves.append("res_inf2")


func test_ai_sends_reserve_to_danger() -> void:
	var s := _setup()
	var b: Battle = s["battle"]
	_add_spare(s)
	_settle_line(b)
	for i in 4:
		b.add_unit(BattleUnit.new("e%d" % i, "player", types["infantry_platoon"], Vector2(14 + i * 4, 28), Vector2(0, -1)))
	b.step()
	(s["ai"] as DefenseAI).plan_turn(b)
	var line: FrontLine = s["line"]
	check(line.reserves.size() == 2, "예비대 하나를 보낸다")
	check(line.units.has("res_inf2"), "적 보병 쪽에는 보병 예비대가 간다")
	check(line.reserves.has("res_inf"), "목표 옆 보병은 수비대로 남는다")
	var sent := b.unit_by_id("res_inf2")
	check(sent.move_target is Vector2 and sent.move_target.x < 30.0, "위험한 왼쪽 구간으로 간다")


func test_ai_prefers_tanks_against_tanks() -> void:
	var s := _setup()
	var b: Battle = s["battle"]
	_settle_line(b)
	for i in 3:
		b.add_unit(BattleUnit.new("t%d" % i, "player", types["medium_tank_platoon"], Vector2(14 + i * 5, 30), Vector2(0, -1)))
	b.step()
	(s["ai"] as DefenseAI).plan_turn(b)
	check((s["line"] as FrontLine).units.has("res_tank"), "적 전차가 보이면 전차 예비대를 먼저 보낸다")


func test_ai_counterattacks_shaken_attackers() -> void:
	var s := _setup()
	var b: Battle = s["battle"]
	_add_spare(s)
	_settle_line(b)
	var e := b.add_unit(BattleUnit.new("e", "player", types["infantry_platoon"], Vector2(30, 26), Vector2(0, -1)))
	b.step()
	e.morale = 30.0
	var ai: DefenseAI = s["ai"]
	ai.plan_turn(b)
	var r := b.unit_by_id("res_tank")
	check(r.stance == BattleUnit.Stance.ATTACK and r.individual, "흔들리는 적에게 예비대로 반격한다")


func test_ai_mortar_uses_predicted_fire_on_moving_target() -> void:
	var s := _setup()
	var b: Battle = s["battle"]
	var m := b.add_unit(BattleUnit.new("m", "ai", types["mortar_platoon"], Vector2(30, 2), Vector2(0, 1)))
	_settle_line(b)
	var e := b.add_unit(BattleUnit.new("e", "player", types["infantry_platoon"], Vector2(30, 28), Vector2(0, -1)))
	e.velocity = Vector2(0, -0.05)
	b.step()
	(s["ai"] as DefenseAI).plan_turn(b)
	check(m.fire_order.get("mode", "") == "predict" and m.fire_order.get("target", "") == "e", "움직이는 적에게 예측 사격: %s" % [m.fire_order])


func test_ai_holds_in_last_turns() -> void:
	var s := _setup()
	var b: Battle = s["battle"]
	b.turn_limit = 10
	b.turn = 6
	(s["ai"] as DefenseAI).plan_turn(b)
	var u := b.unit_by_id("d0")
	check(u.stance == BattleUnit.Stance.HOLD and u.retreat_point == u.center, "막판에는 후퇴하지 않고 사수한다")


func test_ai_guards_guns_in_rear() -> void:
	var s := _setup()
	var b: Battle = s["battle"]
	var at := b.add_unit(BattleUnit.new("at", "ai", types["at_gun"], Vector2(30, 4), Vector2(0, 1)))
	_settle_line(b)
	var raider := b.add_unit(BattleUnit.new("raider", "player", types["medium_tank_platoon"], Vector2(36, 4), Vector2.LEFT, "line", 3))
	b.step()
	b.begin_turn()
	var tank := b.unit_by_id("res_tank")
	check(tank.move_target != null and (tank.move_target as Vector2).distance_to(raider.center) < 1.0, "포 진지에 온 적에게 예비대를 보낸다")
	check(at.facing.dot(Vector2.RIGHT) > 0.9, "대전차포는 적 전차 쪽으로 돈다")


func test_guard_enters_objective_when_enemy_comes_near() -> void:
	var s := _setup()
	var b: Battle = s["battle"]
	_settle_line(b)
	b.add_unit(BattleUnit.new("t", "player", types["medium_tank_platoon"], Vector2(28, 9), Vector2(-1, 0)))
	b.step()
	(s["ai"] as DefenseAI).plan_turn(b)
	var g := b.unit_by_id("res_inf")
	check(g.individual and g.move_target is Vector2 and Rect2(16, 6, 8, 6).has_point(g.move_target), "수비대가 목표 안에서 적 쪽 자리로 간다: %s" % [g.move_target])


func test_shelled_mortar_relocates_except_on_easy() -> void:
	for diff in ["normal", "easy"]:
		var s := _setup()
		var b: Battle = s["battle"]
		(s["ai"] as DefenseAI).difficulty = diff
		var m := b.add_unit(BattleUnit.new("m", "ai", types["mortar_platoon"], Vector2(30, 2), Vector2(0, 1)))
		b.begin_turn()
		m.turn_log["shelled"] = 3
		(s["ai"] as DefenseAI).plan_turn(b)
		check((m.move_target != null) == (diff == "normal"), "%s: 포격받은 박격포 진지 변환" % diff)


func test_hard_shifts_quiet_unit_and_focuses_tank() -> void:
	var s := _setup()
	var b: Battle = s["battle"]
	var ai: DefenseAI = s["ai"]
	ai.difficulty = "hard"
	(s["line"] as FrontLine).reserves.clear()
	_settle_line(b)
	for i in 5:
		b.add_unit(BattleUnit.new("e%d" % i, "player", types["infantry_platoon"], Vector2(8 + i * 3, 24), Vector2(0, -1)))
	b.add_unit(BattleUnit.new("pt", "player", types["medium_tank_platoon"], Vector2(20, 27), Vector2(0, -1)))
	b.step()
	ai.plan_turn(b)
	var d1 := b.unit_by_id("d1")
	check(d1.move_target is Vector2 and d1.move_target.x < 30.0, "조용한 오른쪽 부대가 위험한 왼쪽으로 옮긴다: %s" % [d1.move_target])
	check(b.unit_by_id("res_tank").focus_target == "pt", "전차가 적 전차에 화력을 모은다")
