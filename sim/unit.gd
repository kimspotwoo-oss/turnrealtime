class_name BattleUnit
extends RefCounted
## 전장의 소대 하나. 위치는 칸 단위 실수 좌표이고, 여러 칸을 차지한다.

## 반응 태세: 적과 교전에 들어가면 어떻게 하는지 (기획서 '반응 태세').
enum Stance { ATTACK, RETREAT, HOLD, IGNORE }

var id: String
var side: String
var type: UnitType
var experience := "regular"

var center: Vector2
var facing := Vector2.UP
var formation := "line"
var tile_count: int
var offsets: Array[Vector2i] = []

## 구성원 하나하나: {"kind": String, "hp": float, "max_hp": float, "shield": float}
var elements: Array[Dictionary] = []

var morale := 100.0
var suppression := 0.0
var shock_level := 0
var shock_ticks := 0
## 마지막으로 충격을 받은 틱. 같은 일로 충격이 거듭 걸리지 않게 한다.
var last_shock_tick := -1000
var last_attacked_tick := -1000
## 최근 손실 기록: [틱, 잃은 수]
var recent_losses: Array[Vector2i] = []

var stance := Stance.HOLD
## 이동 목표 (칸 좌표) 또는 null.
var move_target = null
## 이동 목표 다음에 차례로 갈 경유점.
var waypoints: Array[Vector2] = []
## 지금 따라가는 길 (map.find_path 결과)과 그 길의 끝.
var path := PackedVector2Array()
var path_goal = null
## 도착하면 바라볼 방향 (전선 자리처럼 정해진 경우) 또는 null. 가는 동안은 가는 쪽을 본다.
var arrive_facing = null
var retreat_point: Vector2
var moved_this_tick := false
## 플레이어가 따로 내린 명령. 전선 명령보다 우선한다.
var individual := false
## 공세선에서 앞서 나가 나머지를 기다리는 중. 전선이 틱마다 다시 정한다.
var pace_hold := false
## 교전 때문에 이번 틱에 갈 곳 (공격 태세는 적, 저지 태세는 제자리) 또는 null.
## 명령(move_target)은 그대로 두므로 교전이 끝나면 원래 명령을 이어 간다.
var engage_point = null
## 움직이지 못한 까닭 (화면 표시용): "", "panic", "pace", "pinned", "melee", "blocked", "engaged".
var hold_reason := ""
var deployed := true
var setup_left := 0

## 무기 id → 다음 사격까지 남은 틱.
var cooldowns := {}
## 보이는 적 id → 첫 사격까지 남은 반응 지연 틱.
var reaction := {}
## 간접 사격 명령: {} (자동), {"mode": "point", "point": Vector2}, {"mode": "predict", "target": String}
var fire_order := {}
## 마지막으로 쏜 목표 (화면 표시용): 부대 id, 간접 사격 지점, 쏜 틱.
var last_target := ""
var last_fire_point = null
var last_fire_tick := -1000
## 보이지 않는 적에게 맞았을 때 그 적이 있던 곳과 틱 (화면에는 방향만 보여 준다).
var unseen_from = null
var unseen_tick := -1000
## 이번 턴 기록 (턴 보고용). begin_turn 에서 비운다.
## {"state": 시작 사기 상태, "alive": 시작 병력, "lost": 잃은 수, "shelled": 가까이 떨어진 포탄 수,
##  "unseen": 보이지 않는 적에게 맞은 수, "shock": 충격 횟수}
var turn_log := {}

## 지난 턴의 초당 이동 (예측 사격용).
var velocity := Vector2.ZERO
var turn_start_center: Vector2


func _init(p_id: String, p_side: String, p_type: UnitType, p_center: Vector2, p_facing := Vector2.UP, p_formation := "", p_tiles := 0) -> void:
	id = p_id
	side = p_side
	type = p_type
	center = p_center
	facing = p_facing.normalized()
	retreat_point = p_center
	turn_start_center = p_center
	for group in type.elements:
		for i in group["count"]:
			elements.append({"kind": group["kind"], "hp": group["hp"], "max_hp": group["hp"], "shield": group["shield"]})
	for w in type.weapons:
		cooldowns[w.id] = 0
	set_formation(p_formation if p_formation != "" else "line", p_tiles if p_tiles > 0 else type.tiles_default)


func set_formation(kind: String, n: int) -> void:
	formation = kind
	tile_count = clampi(n, type.tiles_min, type.tiles_max)
	offsets = Formation.local_offsets(kind, tile_count)


func tiles() -> Array[Vector2i]:
	return Formation.world_tiles(center, facing, offsets)


func alive_count(kind := "") -> int:
	var n := 0
	for e in elements:
		if e["hp"] > 0.0 and (kind == "" or e["kind"] == kind):
			n += 1
	return n


func initial_count(kind := "") -> int:
	var n := 0
	for e in elements:
		if kind == "" or e["kind"] == kind:
			n += 1
	return n


func alive_indices(kind := "") -> Array[int]:
	var out: Array[int] = []
	for i in elements.size():
		var e := elements[i]
		if e["hp"] > 0.0 and (kind == "" or e["kind"] == kind):
			out.append(i)
	return out


## 싸울 수 있는 상태인지. 포만 남고 승무원이 없으면 싸우지 못한다.
func is_alive() -> bool:
	if type.is_vehicle():
		return alive_count("vehicle") > 0
	return alive_count("man") > 0


func state() -> Morale.State:
	return Morale.state_for(morale, shock_level if shock_ticks > 0 else 0)


func is_suppressed() -> bool:
	return suppression >= Morale.SUPPRESSED_AT


func is_pinned() -> bool:
	return suppression >= Morale.PINNED_AT


## 구성원이 서 있는 칸. 구성원은 차지한 칸에 차례로 고르게 나뉜다.
func element_tile(index: int, unit_tiles: Array[Vector2i]) -> Vector2i:
	return unit_tiles[index % unit_tiles.size()]


## 지금 쓸 수 있는 무기 수. 구성원이 줄면 같은 비율로 준다.
func weapon_count(w: WeaponType) -> int:
	var total := initial_count(w.scale)
	if total == 0:
		return 0
	var n := ceili(w.count * float(alive_count(w.scale)) / total)
	if w.scale == "gun" and alive_count("man") == 0:
		return 0
	return n


## 승무원이 절반 아래로 줄면 포의 사격 간격이 두 배가 된다.
func crew_slowdown(w: WeaponType) -> int:
	if w.scale == "gun" and alive_count("man") * 2 < initial_count("man"):
		return 2
	return 1


func nearest_tile_to(p: Vector2) -> Vector2i:
	var best := Vector2i.ZERO
	var best_d := INF
	for t in tiles():
		var d := Vector2(t).distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = t
	return best
