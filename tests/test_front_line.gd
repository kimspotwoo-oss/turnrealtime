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
	check(line.reserves.is_empty(), "예비대 목록에서 빠진다")
