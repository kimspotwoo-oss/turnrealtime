extends TestCase


func test_practice_stage_loads() -> void:
	var b := StageLoader.load_file("res://data/stages/practice.json")
	check(b.map.width == 60 and b.map.height == 40, "60×40칸")
	check(b.turn_limit == 25, "25턴 제한")
	var per_side := {}
	for u in b.units:
		per_side[u.side] = per_side.get(u.side, 0) + 1
	check(per_side.get("player", 0) == 12 and per_side.get("ai", 0) == 12, "양측 12개 부대: %s" % [per_side])
	check(b.map.terrain_at(Vector2i(18, 8)) == "village", "마을 칸")
	check(b.map.terrain_at(Vector2i(10, 17)) == "forest", "숲 칸")
	check(b.victory["capture"]["player"].size() == 2, "두 마을 점령 조건")


func test_practice_stage_runs_to_the_end() -> void:
	var b := StageLoader.load_file("res://data/stages/practice.json")
	var guard := 0
	while b.winner == "" and guard < 30:
		b.run_turn()
		guard += 1
	check(b.winner != "", "제한 턴 안에 승패가 난다")
	print("    연습 스테이지 결과: %s 승, %d턴 %d틱" % [b.winner, b.turn, b.tick])
