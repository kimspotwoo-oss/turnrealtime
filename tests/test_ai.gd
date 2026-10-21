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


func test_ai_sends_reserve_to_danger() -> void:
	var s := _setup()
	var b: Battle = s["battle"]
	_settle_line(b)
	for i in 4:
		b.add_unit(BattleUnit.new("e%d" % i, "player", types["infantry_platoon"], Vector2(14 + i * 4, 28), Vector2(0, -1)))
	b.step()
	(s["ai"] as DefenseAI).plan_turn(b)
	var line: FrontLine = s["line"]
	check(line.reserves.size() == 1, "예비대 하나를 보낸다")
	check(line.units.has("res_inf"), "적 보병 쪽에는 가까운 보병 예비대가 간다")
	var sent := b.unit_by_id("res_inf")
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
