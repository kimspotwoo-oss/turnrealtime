extends TestCase

var types := UnitType.load_all()


func _battle_with_line(n: int, offensive := PackedVector2Array()) -> Battle:
	var b := Battle.new(BattleMap.new(60, 40), 3)
	var line := FrontLine.new("main", "red", PackedVector2Array([Vector2(8, 18), Vector2(52, 18)]), Vector2(0, 1))
	for i in n:
		var u := b.add_unit(BattleUnit.new("u%d" % i, "red", types["infantry_platoon"], Vector2(10 + i * 10, 10)))
		line.units.append(u.id)
	line.offensive = offensive
	b.front_lines.append(line)
	line.apply(b)
	return b


func test_units_spread_evenly_along_line() -> void:
	var b := _battle_with_line(4)
	var xs := [13.5, 24.5, 35.5, 46.5]
	for i in 4:
		var u := b.unit_by_id("u%d" % i)
		check_near((u.move_target as Vector2).x, xs[i], "u%d 자리" % i)
		check_near((u.move_target as Vector2).y, 18.0, "u%d 전선 위" % i)
		check(u.facing.is_equal_approx(Vector2(0, 1)), "적 쪽을 바라본다")
		check(u.formation == "line", "횡대")
		check(u.tile_count == 8, "넓은 전선은 최대 폭으로 선다")


func test_line_stance_and_individual_order() -> void:
	var b := Battle.new(BattleMap.new(60, 40), 3)
	var line := FrontLine.new("main", "red", PackedVector2Array([Vector2(8, 18), Vector2(52, 18)]), Vector2(0, 1))
	var a := b.add_unit(BattleUnit.new("a", "red", types["infantry_platoon"], Vector2(10, 10)))
	var c := b.add_unit(BattleUnit.new("c", "red", types["infantry_platoon"], Vector2(30, 10)))
	c.individual = true
	c.move_target = Vector2(1, 1)
	line.units.assign(["a", "c"])
	line.stance = BattleUnit.Stance.ATTACK
	line.apply(b)
	check(a.stance == BattleUnit.Stance.ATTACK, "전선 태세를 따른다")
	check(c.move_target == Vector2(1, 1), "개별 명령이 전선 명령보다 우선한다")


func test_polyline_point_at() -> void:
	var line := PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10)])
	check(FrontLine.point_at(line, 0.5).is_equal_approx(Vector2(10, 0)), "꺾인 점")
	check(FrontLine.point_at(line, 0.75).is_equal_approx(Vector2(10, 5)), "두 번째 구간")
	check_near(FrontLine.polyline_length(line), 20.0, "길이")


func test_offensive_keeps_pace() -> void:
	var b := _battle_with_line(2, PackedVector2Array([Vector2(8, 30), Vector2(52, 30)]))
	var line := b.front_lines[0]
	var ahead := b.unit_by_id("u0")
	var behind := b.unit_by_id("u1")
	# 한 부대만 미리 많이 나가 있게 만든다.
	ahead.center = Vector2(19, 26)
	line.apply(b)
	behind.center = Vector2(30, 5)
	line._slots["u1"]["start"] = behind.center
	line._slots["u0"]["start"] = Vector2(19, 5)
	var before := ahead.center
	b.step()
	check(ahead.center == before, "앞선 부대는 기다린다")
	check(behind.center != Vector2(30, 5), "뒤처진 부대는 전진한다")


func test_reserve_fills_broken_slot() -> void:
	var b := _battle_with_line(2)
	var line := b.front_lines[0]
	var r := b.add_unit(BattleUnit.new("r", "red", types["infantry_platoon"], Vector2(20, 5)))
	line.reserves.append("r")
	var broken := b.unit_by_id("u0")
	broken.morale = 10.0
	var slot_target: Vector2 = broken.move_target
	b.step()
	check(line.units.has("r") and not line.units.has("u0"), "예비대가 무너진 부대 자리에 들어간다")
	check(r.move_target == slot_target, "예비대가 그 자리로 간다")
	check(not line.reserves.has("r") and line.reserves.has("u0"), "예비대 목록에서 빠지고, 무너진 부대가 예비대로 돌아간다")
	check(broken.move_target == null, "무너진 부대는 옛 자리로 혼자 가지 않는다")


func test_units_face_enemy_after_small_adjustment() -> void:
	var b := _battle_with_line(1)
	var u := b.unit_by_id("u0")
	u.center = Vector2(29.5, 18)
	b.front_lines[0].apply(b)
	for i in 30:
		b.step()
	check(u.facing.is_equal_approx(Vector2(0, 1)), "자리를 옆으로 조금 고쳐도 적 쪽을 본다: %s" % u.facing)
	check(u.tiles()[0].y == u.tiles()[1].y, "횡대는 가로로 선다")


func test_pace_hold_clears_after_individual_order() -> void:
	var b := _battle_with_line(2, PackedVector2Array([Vector2(8, 30), Vector2(52, 30)]))
	var u0 := b.unit_by_id("u0")
	var u1 := b.unit_by_id("u1")
	u1.morale = 100.0
	u1.suppression = Morale.PINNED_AT + 40.0
	for i in 3:
		b.step()
	check(not u0.pace_hold, "고착된 부대는 기다려 주지 않는다")
	u1.suppression = 0.0
	u1.center = Vector2(30, 10)
	u0.pace_hold = true
	Orders.move(u0, Vector2(10, 5))
	b.step()
	check(not u0.pace_hold, "개별 명령을 받으면 공세선 대기가 풀린다")


func test_broken_line_does_not_jump_to_offensive() -> void:
	var b := _battle_with_line(2, PackedVector2Array([Vector2(8, 30), Vector2(52, 30)]))
	for u in b.units:
		u.morale = 30.0
	b.step()
	var line := b.front_line("main")
	check(not line.offensive.is_empty(), "모두 무너져도 공세선을 새 전선으로 삼지 않는다")
	check_near(line.points[0].y, 18.0, "전선은 제자리")


func test_advance_line_moves_units_and_reserves_follow() -> void:
	var b: Battle = StageLoader.load_file("res://data/stages/practice.json")
	var line := b.front_line("player_main")
	Orders.cancel_advance(b, line)
	var tank := b.unit_by_id("p_tank1")
	Orders.add_reserves(b, line, [tank] as Array[BattleUnit])
	var start := tank.center
	Orders.advance_line(b, line, 5.0)
	check_near(line.offensive[0].y, line.points[0].y - 5.0, "적 쪽으로 다섯 칸")
	check(tank.move_target is Vector2 and is_equal_approx((tank.move_target as Vector2).y, start.y - 5.0), "예비대도 같은 만큼 따라간다")
	Orders.cancel_advance(b, line)
	check(line.offensive.is_empty() and tank.move_target == null, "전진을 취소하면 예비대도 선다")


func test_leave_and_rejoin_line() -> void:
	var b: Battle = StageLoader.load_file("res://data/stages/practice.json")
	var line := b.front_line("player_main")
	var u := b.unit_by_id("p_inf2")
	Orders.move(u, Vector2(30, 30))
	Orders.rejoin_line(b, [u] as Array[BattleUnit])
	check(not u.individual and not (u.move_target as Vector2).is_equal_approx(Vector2(30, 30)), "복귀하면 전선 자리로 간다")
	Orders.leave_line(b, [u] as Array[BattleUnit])
	check(not line.units.has("p_inf2") and u.move_target == null, "빼면 전선 목록에서 빠지고 그 자리에 선다")
	check(line.units.size() == 5, "남은 부대가 전선을 다시 나눠 선다")
