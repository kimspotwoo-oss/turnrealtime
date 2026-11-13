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


func test_easy_difficulty_trims_enemy_and_adds_turns() -> void:
	var normal := StageLoader.load_file("res://data/stages/practice.json")
	var easy := StageLoader.load_file("res://data/stages/practice.json", {}, -1, "easy")
	check(normal.unit_by_id("a_tank2") != null and easy.unit_by_id("a_tank2") == null, "쉬움은 적 전차 한 소대가 없다")
	check(easy.turn_limit == normal.turn_limit + 5, "쉬움은 다섯 턴이 더 있다")
	check(easy.unit_by_id("a_inf1").experience == "recruit" and easy.unit_by_id("p_inf1").experience == "regular", "적만 신병")
	check(not easy.front_line("ai_main").reserves.has("a_tank2"), "없는 부대는 예비대 목록에도 없다")
	check(easy.ai_players[0].difficulty == "easy", "AI 난이도")
