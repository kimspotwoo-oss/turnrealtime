extends TestCase

var types := UnitType.load_all()


func _battle() -> Battle:
	var b := Battle.new(BattleMap.new(60, 40), 9)
	for i in 3:
		b.add_unit(BattleUnit.new("p%d" % i, "player", types["infantry_platoon"], Vector2(10 + i * 15, 33)))
	b.add_unit(BattleUnit.new("e", "ai", types["infantry_platoon"], Vector2(30, 5)))
	return b


func _units(b: Battle, ids: Array) -> Array[BattleUnit]:
	var out: Array[BattleUnit] = []
	for id in ids:
		out.append(b.unit_by_id(id))
	return out


func test_draw_front_line_orders_units_along_line() -> void:
	var b := _battle()
	# 선을 오른쪽에서 왼쪽으로 그어도 각 부대는 가까운 자리로 간다.
	var line := Orders.draw_front_line(b, "player", _units(b, ["p0", "p1", "p2"]), PackedVector2Array([Vector2(50, 28), Vector2(5, 28)]))
	check(line.units == ["p2", "p1", "p0"], "선 방향 순서대로: %s" % [line.units])
	check(b.unit_by_id("p0").facing.is_equal_approx(Vector2(0, -1)), "아군 반대쪽(적 쪽)을 바라본다")
	check(b.front_lines.has(line), "전투에 등록된다")


func test_redrawing_moves_units_out_of_old_line() -> void:
	var b := _battle()
	var first := Orders.draw_front_line(b, "player", _units(b, ["p0", "p1"]), PackedVector2Array([Vector2(5, 28), Vector2(50, 28)]))
	var second := Orders.draw_front_line(b, "player", _units(b, ["p0", "p1"]), PackedVector2Array([Vector2(5, 25), Vector2(50, 25)]))
	check(not b.front_lines.has(first), "빈 전선은 지운다")
	check(second.units.size() == 2, "새 전선으로 옮긴다")
	check(second.id != first.id or b.front_lines.size() == 1, "전선 id 가 겹치지 않는다")


func test_individual_move_and_stance_on_line() -> void:
	var b := _battle()
	var units := _units(b, ["p0", "p1"])
	var line := Orders.draw_front_line(b, "player", units, PackedVector2Array([Vector2(5, 28), Vector2(50, 28)]))
	Orders.set_stance(b, units, BattleUnit.Stance.ATTACK)
	check(line.stance == BattleUnit.Stance.ATTACK, "전선 전체를 고르면 전선 태세가 바뀐다")
	Orders.move(units[0], Vector2(3, 3))
	check(units[0].individual and units[0].move_target == Vector2(3, 3), "개별 이동")
	Orders.set_offensive(b, line, PackedVector2Array([Vector2(5, 15), Vector2(50, 15)]))
	check(units[0].move_target == Vector2(3, 3), "개별 명령은 공세선이 덮어쓰지 않는다")
	check((units[1].move_target as Vector2).y == 15.0, "나머지는 공세선으로 간다")


func test_reserves_and_fire_orders() -> void:
	var b := _battle()
	var line := Orders.draw_front_line(b, "player", _units(b, ["p0", "p1"]), PackedVector2Array([Vector2(5, 28), Vector2(50, 28)]))
	Orders.add_reserves(b, line, _units(b, ["p2"]))
	check(line.reserves == ["p2"], "예비대로")
	check(Orders.line_of(b, "p2") == line, "예비대도 그 전선 소속")
	var m := b.add_unit(BattleUnit.new("m", "player", types["mortar_platoon"], Vector2(30, 38)))
	Orders.fire_predicted(m, b.unit_by_id("e"))
	check(m.fire_order == {"mode": "predict", "target": "e"}, "예측 사격 명령")
	Orders.clear_fire(m)
	check(m.fire_order.is_empty(), "사격 해제")


func test_turn_can_be_stepped_by_screen() -> void:
	var b := StageLoader.load_file("res://data/stages/practice.json")
	var c := StageLoader.load_file("res://data/stages/practice.json")
	b.run_turn()
	c.begin_turn()
	while not c.turn_over():
		c.step()
	c.end_turn()
	check(b.state_hash() == c.state_hash(), "화면처럼 틱을 나눠 돌려도 결과가 같다")
