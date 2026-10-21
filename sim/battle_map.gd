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


func fill_rect(rect: Rect2i, terrain: String) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			set_terrain(Vector2i(x, y), terrain)


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
