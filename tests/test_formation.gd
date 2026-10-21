extends TestCase

var types := UnitType.load_all()


func test_line_is_perpendicular_to_facing() -> void:
	var tiles := Formation.world_tiles(Vector2(10, 10), Vector2.UP, Formation.local_offsets("line", 5))
	check(tiles.size() == 5, "5칸")
	for t in tiles:
		check(t.y == 10, "북쪽을 보면 가로로 선다")
	var east := Formation.world_tiles(Vector2(10, 10), Vector2.RIGHT, Formation.local_offsets("line", 5))
	for t in east:
		check(t.x == 10, "동쪽을 보면 세로로 선다")


func test_column_trails_behind() -> void:
	var tiles := Formation.world_tiles(Vector2(10, 10), Vector2.UP, Formation.local_offsets("column", 4))
	check(tiles == [Vector2i(10, 10), Vector2i(10, 11), Vector2i(10, 12), Vector2i(10, 13)], "선두 뒤로 줄선다: %s" % [tiles])


func test_wedge_and_dispersed() -> void:
	var wedge := Formation.local_offsets("wedge", 5)
	check(wedge[0] == Vector2i.ZERO, "쐐기 선두")
	check(wedge.size() == 5, "쐐기 5칸")
	var disp := Formation.world_tiles(Vector2(20, 20), Vector2.UP, Formation.local_offsets("dispersed", 4))
	check(disp.size() == 4, "분산 4칸, 겹치지 않음")


func test_tile_count_clamped_by_type() -> void:
	var u := BattleUnit.new("x", "a", types["infantry_platoon"], Vector2(10, 10))
	u.set_formation("line", 20)
	check(u.tile_count == 8, "보병 최대 8칸")
	u.set_formation("line", 1)
	check(u.tile_count == 2, "보병 최소 2칸")


func test_members_spread_over_tiles() -> void:
	var u := BattleUnit.new("x", "a", types["infantry_platoon"], Vector2(10, 10), Vector2.UP, "line", 6)
	var counts := {}
	var tiles := u.tiles()
	for i in u.elements.size():
		var t := u.element_tile(i, tiles)
		counts[t] = counts.get(t, 0) + 1
	check(counts.size() == 6, "6칸 모두 사람이 있다")
	for t in counts:
		check(counts[t] == 5, "30명이 6칸에 5명씩")
