extends TestCase

var types := UnitType.load_all()


func _weapon(type_id: String, weapon_id: String) -> WeaponType:
	for w in (types[type_id] as UnitType).weapons:
		if w.id == weapon_id:
			return w
	return null


func test_penetration_chance_is_pen_over_armor() -> void:
	check_near(Combat.penetration_chance(120, 300), 0.4, "T-34 vs 티거 전면")
	check_near(Combat.penetration_chance(210, 160), 1.0, "최대 1")
	check_near(Combat.penetration_chance(1, 0), 1.0, "장갑 없음")


func test_ricochet_does_ten_percent() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	for i in 20:
		var res := Combat.armored_hit(rng, 160, 0, 160)
		check(not res["penetrated"], "관통력 0은 관통 못 함")
		check_near(res["damage"], 16.0, "도탄 피해 10%")


func test_penetration_falls_with_distance() -> void:
	var gun := _weapon("medium_tank_platoon", "main_gun")
	check_near(gun.pen_at(0), 120, "근거리")
	check_near(gun.pen_at(gun.range_tiles), 80, "최대 사거리")
	check_near(gun.pen_at(gun.range_tiles / 2), 100, "중간")
	check_near(gun.pen_at(gun.range_tiles * 3), 80, "사거리 밖은 최솟값")


func test_hit_side() -> void:
	var p := Vector2.ZERO
	check(Combat.hit_side(p, Vector2.UP, Vector2(0, -10)) == "front", "정면")
	check(Combat.hit_side(p, Vector2.UP, Vector2(0, 10)) == "rear", "후면")
	check(Combat.hit_side(p, Vector2.UP, Vector2(10, 0)) == "side", "측면")
	var tank: UnitType = types["medium_tank_platoon"]
	check_near(Combat.armor_for(tank, "side"), 117.5, "측면 장갑은 전·후면 평균")


func test_scatter_extent_matches_design_table() -> void:
	var mortar := _weapon("mortar_platoon", "mortar")
	var ext := Combat.scatter_extent(40.0, mortar)  # 1km
	check_near(ext.x * BattleMap.TILE_METERS, 30.0, "1km 앞뒤 ±30m", 0.01)
	check_near(ext.y * BattleMap.TILE_METERS, 34.92, "1km 좌우 ±35m", 0.05)
	var far := Combat.scatter_extent(96.0, mortar)
	check_near(far.x * BattleMap.TILE_METERS, 50.0, "앞뒤 최대 50m", 0.01)


func test_scatter_points_stay_in_fan_and_lean_long() -> void:
	var mortar := _weapon("mortar_platoon", "mortar")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var origin := Vector2(0, 0)
	var aim := Vector2(0, -40)
	var ext := Combat.scatter_extent(40.0, mortar)
	var sum_along := 0.0
	for i in 2000:
		var p := Combat.scatter_point(rng, origin, aim, mortar)
		var along := -(p.y - aim.y)
		check(absf(p.x - aim.x) <= ext.y + 0.0001, "좌우 범위 안")
		check(along >= -ext.x * (1.0 - Combat.SCATTER_OVERSHOOT) - 0.0001 and along <= ext.x * (1.0 + Combat.SCATTER_OVERSHOOT) + 0.0001, "앞뒤 범위 안")
		sum_along += along
	check(sum_along / 2000 > 0.0, "평균적으로 목표보다 넘어간다")


func test_small_arms_flag() -> void:
	check(_weapon("infantry_platoon", "rifle").is_small_arms(), "소총은 소화기")
	check(not _weapon("medium_tank_platoon", "main_gun").is_small_arms(), "주포는 소화기 아님")
	check(not _weapon("mortar_platoon", "mortar").is_small_arms(), "박격포는 간접 사격")
