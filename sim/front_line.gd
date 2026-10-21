class_name FrontLine
extends RefCounted
## 전선: 여러 부대를 하나의 선으로 묶어 한 번에 명령한다 (기획서 '전선 기능').
##
## 1단계에는 통신 지연이 없으므로 전선 명령은 준비기간에 apply() 로 한 번 내리고,
## 실행기간에는 update() 가 보조만 한다: 공세선에서 앞서 나간 부대를 기다리게 하고,
## 무너진 자리를 예비대로 메운다.

var id: String
var side: String
## 전선 (칸 좌표 꺾은선).
var points: PackedVector2Array
## 적이 있는 쪽. 각 구간에서 이쪽을 향한 법선이 부대의 정면이 된다.
var enemy_dir: Vector2
## 전선에 선 부대 id. 순서대로 선을 따라 고르게 나눠 선다.
var units: Array[String] = []
## 전선 뒤에 대기하는 부대 id. 전선에 구멍이 나면 메운다.
var reserves: Array[String] = []
var stance := BattleUnit.Stance.HOLD
## 공세선: 비어 있지 않으면 전선 전체가 나란히 이 선까지 전진한다.
var offensive: PackedVector2Array
## 후퇴선: 후퇴 태세나 패주 때 물러날 선.
var retreat: PackedVector2Array

## 공세선에서 이만큼(진행 비율) 앞서면 나머지를 기다린다.
const PACE_SLACK := 0.08

## 부대 id → {"slot": float, "start": Vector2, "target": Vector2}
var _slots := {}


func _init(p_id: String, p_side: String, p_points: PackedVector2Array, p_enemy_dir: Vector2) -> void:
	id = p_id
	side = p_side
	points = p_points
	enemy_dir = p_enemy_dir.normalized()


## 준비기간의 전선 명령. 개별 명령을 받은 부대는 건드리지 않는다.
func apply(battle: Battle) -> void:
	_slots.clear()
	var n := units.size()
	if n == 0:
		return
	var width := polyline_length(points) / n
	for i in n:
		var u := battle.unit_by_id(units[i])
		if u == null:
			continue
		var f := (i + 0.5) / n
		var pos := point_at(points, f)
		var target := pos if offensive.is_empty() else point_at(offensive, f)
		_slots[u.id] = {"slot": f, "start": u.center, "target": target}
		if u.individual:
			continue
		u.facing = facing_at(points if offensive.is_empty() else offensive, f)
		u.arrive_facing = u.facing
		u.set_formation("line", roundi(width))
		u.stance = stance
		u.move_target = target
		if not retreat.is_empty():
			u.retreat_point = point_at(retreat, f)


## 실행기간 매 틱: 공세선 보조와 예비대 투입.
func update(battle: Battle) -> void:
	_fill_gaps(battle)
	_keep_pace(battle)


func slot_of(unit_id: String) -> float:
	return _slots.get(unit_id, {}).get("slot", -1.0)


## 무너진(패닉·패주·전멸) 부대 자리에 가장 가까운 예비대를 보낸다.
func _fill_gaps(battle: Battle) -> void:
	for i in units.size():
		var u := battle.unit_by_id(units[i])
		if u != null and u.is_alive() and u.state() < Morale.State.PANIC:
			continue
		var slot: Dictionary = _slots.get(units[i], {})
		if slot.is_empty():
			continue
		var r := nearest_reserve(battle, slot["target"])
		if r == null:
			continue
		reserves.erase(r.id)
		_slots.erase(units[i])
		units[i] = r.id
		send_to_slot(r, slot["slot"], slot["target"])


func nearest_reserve(battle: Battle, p: Vector2, prefer_vehicle := false) -> BattleUnit:
	var best: BattleUnit = null
	var best_score := INF
	for rid in reserves:
		var r := battle.unit_by_id(rid)
		if r == null or not r.is_alive() or r.state() >= Morale.State.PANIC:
			continue
		var score := r.center.distance_to(p)
		if prefer_vehicle and r.type.is_vehicle():
			score -= 1000.0
		if score < best_score:
			best_score = score
			best = r
	return best


## 예비대 하나를 전선의 한 자리로 보낸다.
func send_to_slot(r: BattleUnit, f: float, target: Vector2) -> void:
	_slots[r.id] = {"slot": f, "start": r.center, "target": target}
	r.individual = false
	r.facing = facing_at(points, f)
	r.arrive_facing = r.facing
	r.stance = stance
	r.move_target = target
	if not retreat.is_empty():
		r.retreat_point = point_at(retreat, f)


## 공세선: 앞서 나간 부대는 뒤처진 부대를 기다려 나란히 전진한다.
## 적과 교전 중인 부대는 기다리지 않는다.
func _keep_pace(battle: Battle) -> void:
	if offensive.is_empty():
		return
	var progress := {}
	var slowest := INF
	for uid in units:
		var u := battle.unit_by_id(uid)
		if u == null or not u.is_alive() or u.individual or not _slots.has(uid):
			continue
		var s: Dictionary = _slots[uid]
		var total: float = (s["start"] as Vector2).distance_to(s["target"])
		var p := 1.0 if total < 0.01 else 1.0 - u.center.distance_to(s["target"]) / total
		progress[uid] = p
		if u.state() < Morale.State.PANIC:
			slowest = minf(slowest, p)
	for uid in progress:
		var u := battle.unit_by_id(uid)
		u.pace_hold = u.reaction.is_empty() and progress[uid] > slowest + PACE_SLACK
	if slowest >= 0.99:
		# 모두 도착하면 공세선이 새 전선이 된다.
		points = offensive
		offensive = PackedVector2Array()
		for uid in progress:
			battle.unit_by_id(uid).pace_hold = false


# --- 꺾은선 도우미 -----------------------------------------------------------

static func polyline_length(line: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(1, line.size()):
		total += line[i - 1].distance_to(line[i])
	return total


## 꺾은선에서 길이 비율 f(0~1) 지점.
static func point_at(line: PackedVector2Array, f: float) -> Vector2:
	if line.size() == 1:
		return line[0]
	var want := polyline_length(line) * clampf(f, 0.0, 1.0)
	for i in range(1, line.size()):
		var seg := line[i - 1].distance_to(line[i])
		if want <= seg or i == line.size() - 1:
			return line[i - 1].lerp(line[i], 0.0 if seg == 0.0 else minf(1.0, want / seg))
		want -= seg
	return line[line.size() - 1]


## 길이 비율 f 지점 구간의 법선 중 적 쪽을 향한 것.
func facing_at(line: PackedVector2Array, f: float) -> Vector2:
	if line.size() < 2:
		return enemy_dir
	var a := point_at(line, maxf(0.0, f - 0.01))
	var b := point_at(line, minf(1.0, f + 0.01))
	var d := (b - a).normalized()
	var n := Vector2(-d.y, d.x)
	return n if n.dot(enemy_dir) >= 0.0 else -n
