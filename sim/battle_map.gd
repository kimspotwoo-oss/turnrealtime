class_name BattleMap
extends RefCounted
## 집중전투 맵. 한 칸은 25m 정사각형이다.

const TILE_METERS := 25.0

## cover: 칸 안 병력이 맞을 확률 배수. conceal: 칸 안 부대가 발견되는 거리 배수.
## move_foot / move_vehicle: 이동 속도 배수. blocks_los: 시야를 가리는지.
const TERRAIN := {
	"open": {"cover": 1.0, "conceal": 1.0, "move_foot": 1.0, "move_vehicle": 1.0, "blocks_los": false},
	"road": {"cover": 1.0, "conceal": 1.0, "move_foot": 1.0, "move_vehicle": 1.0, "blocks_los": false},
	"forest": {"cover": 0.5, "conceal": 0.5, "move_foot": 0.7, "move_vehicle": 0.3, "blocks_los": true},
	"village": {"cover": 0.5, "conceal": 0.6, "move_foot": 0.8, "move_vehicle": 0.6, "blocks_los": true},
}

## 시야선이 이만큼의 가리는 칸(양 끝 칸 제외)을 지나면 막힌다.
const LOS_BLOCK_TILES := 2

var width: int
var height: int
var _terrain: Array[String] = []
## 길 찾기 격자. 걷는 부대용과 차량용(길 속도 배수별)을 처음 쓸 때 만든다.
var _grids := {}


func _init(w: int, h: int, base := "open") -> void:
	width = w
	height = h
	_terrain.resize(w * h)
	_terrain.fill(base)


func in_bounds(tile: Vector2i) -> bool:
	return tile.x >= 0 and tile.y >= 0 and tile.x < width and tile.y < height


func terrain_at(tile: Vector2i) -> String:
	if not in_bounds(tile):
		return "open"
	return _terrain[tile.y * width + tile.x]


func props(tile: Vector2i) -> Dictionary:
	return TERRAIN[terrain_at(tile)]


func set_terrain(tile: Vector2i, terrain: String) -> void:
	assert(TERRAIN.has(terrain), "모르는 지형: %s" % terrain)
	if in_bounds(tile):
		_terrain[tile.y * width + tile.x] = terrain
		_grids.clear()


func fill_rect(rect: Rect2i, terrain: String) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			set_terrain(Vector2i(x, y), terrain)
	_grids.clear()


## 한 칸을 지나는 데 드는 시간 배수 (개활지 = 1). road_factor 는 차량이 길에서 몇 배 빠른지.
func move_cost(tile: Vector2i, vehicle: bool, road_factor := 1.0) -> float:
	var p := props(tile)
	if vehicle:
		if terrain_at(tile) == "road" and road_factor > 1.0:
			return 1.0 / road_factor
		return 1.0 / p["move_vehicle"]
	return 1.0 / p["move_foot"]


## 지형 비용으로 가장 빨리 가는 길. 돌아서 가는 점들만 남기고, 마지막 점은 to 이다.
## 같은 비용 이하의 칸만 지나는 구간은 곧게 펴서 계단 모양으로 걷지 않게 한다.
func find_path(from: Vector2, to: Vector2, vehicle: bool, road_factor := 1.0) -> PackedVector2Array:
	var a := _clamp_tile(Vector2i(from.round()))
	var b := _clamp_tile(Vector2i(to.round()))
	if a == b:
		return PackedVector2Array([to])
	var cells := _grid(vehicle, road_factor).get_id_path(a, b)
	if cells.size() < 2:
		return PackedVector2Array([to])
	var pts: Array[Vector2] = [from]
	for i in range(1, cells.size() - 1):
		pts.append(Vector2(cells[i]))
	pts.append(to)
	var out := PackedVector2Array()
	var i := 0
	while i < pts.size() - 1:
		var j := pts.size() - 1
		while j > i + 1 and not _straight_ok(pts, i, j, vehicle, road_factor):
			j -= 1
		out.append(pts[j])
		i = j
	return out


## pts[i] 에서 pts[j] 로 곧장 가도 그 사이 길보다 느린 칸을 지나지 않는지.
func _straight_ok(pts: Array[Vector2], i: int, j: int, vehicle: bool, road_factor: float) -> bool:
	var worst := 0.0
	for k in range(i, j + 1):
		worst = maxf(worst, move_cost(Vector2i(pts[k].round()), vehicle, road_factor))
	var steps := ceili(pts[i].distance_to(pts[j]) * 2.0)
	for s in range(1, steps):
		var t := Vector2i(pts[i].lerp(pts[j], float(s) / steps).round())
		if move_cost(t, vehicle, road_factor) > worst + 0.001:
			return false
	return true


func _clamp_tile(t: Vector2i) -> Vector2i:
	return Vector2i(clampi(t.x, 0, width - 1), clampi(t.y, 0, height - 1))


func _grid(vehicle: bool, road_factor: float) -> AStarGrid2D:
	var key := "%s:%.2f" % [vehicle, road_factor]
	if _grids.has(key):
		return _grids[key]
	var g := AStarGrid2D.new()
	g.region = Rect2i(0, 0, width, height)
	g.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	g.default_compute_heuristic = AStarGrid2D.HEURISTIC_EUCLIDEAN
	g.default_estimate_heuristic = AStarGrid2D.HEURISTIC_EUCLIDEAN
	g.update()
	var cheapest := INF
	for y in height:
		for x in width:
			cheapest = minf(cheapest, move_cost(Vector2i(x, y), vehicle, road_factor))
	for y in height:
		for x in width:
			# 휴리스틱이 비용을 넘지 않게 가장 싼 칸을 1로 맞춘다.
			g.set_point_weight_scale(Vector2i(x, y), move_cost(Vector2i(x, y), vehicle, road_factor) / cheapest)
	_grids[key] = g
	return g


## 두 칸 사이 시야가 숲·마을에 막히는지. 양 끝 칸은 세지 않아서
## 숲 가장자리에 있는 부대는 밖을 볼 수 있다.
func line_blocked(a: Vector2i, b: Vector2i) -> bool:
	var steps := maxi(absi(b.x - a.x), absi(b.y - a.y)) * 2
	var seen := {}
	var blocking := 0
	for i in range(1, steps):
		var tile := Vector2i(Vector2(a).lerp(Vector2(b), float(i) / steps).round())
		if tile == a or tile == b or seen.has(tile):
			continue
		seen[tile] = true
		if props(tile)["blocks_los"]:
			blocking += 1
			if blocking >= LOS_BLOCK_TILES:
				return true
	return false
