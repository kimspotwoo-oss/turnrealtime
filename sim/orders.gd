class_name Orders
extends RefCounted
## 준비기간에 내리는 명령. 화면(과 나중의 온라인 대전)은 이 함수들로만 명령을 바꾼다.

## 개별 이동. 전선에 속한 부대라도 개별 명령이 우선한다.
static func move(u: BattleUnit, target: Vector2) -> void:
	u.move_target = target
	u.waypoints.clear()
	u.arrive_facing = null
	u.reverse_move = false
	u.attack_move = false
	u.individual = true


## 후진: 지금 정면(전차는 두꺼운 정면 장갑)을 적 쪽에 둔 채 물러난다. 속도는 절반.
static func move_reverse(u: BattleUnit, target: Vector2) -> void:
	move(u, target)
	u.reverse_move = true


## 대형 배치: 고른 부대들을 a→b 선 위에 나란히 세운다. 선의 길이가 전체 폭이 되고,
## 정면은 선을 왼쪽에서 오른쪽으로 그었을 때 앞쪽(선에 수직)이다. waypoint 면 지금 명령 뒤에 잇는다.
static func place_on_segment(units: Array[BattleUnit], a: Vector2, b: Vector2, waypoint := false) -> void:
	if units.is_empty() or a.distance_to(b) < 0.01:
		return
	var along := (b - a).normalized()
	var front := along.rotated(-PI / 2.0)
	var sorted := units.duplicate()
	sorted.sort_custom(func(x, y): return (x.center - a).dot(along) < (y.center - a).dot(along))
	var width := roundi(a.distance_to(b) / sorted.size())
	for i in sorted.size():
		var u: BattleUnit = sorted[i]
		var pos := a.lerp(b, (i + 0.5) / sorted.size())
		if waypoint:
			add_waypoint(u, pos)
		else:
			move(u, pos)
		u.arrive_facing = front
		set_formation(u, u.formation, width)


## 공격 명령 (토탈워 방식): 가장 빠른 길로 다가가 최대 사거리에서 멈추고 이 적을 먼저 쏜다.
## 표적이 물러나면 다시 따라가고, 표적이 죽으면 명령이 끝난다.
static func attack(u: BattleUnit, target: BattleUnit) -> void:
	stop(u)
	u.focus_target = target.id
	u.attack_move = true
	u.attack_last_seen = target.center.round()


## 우선 사격: 이 적이 보이고 사거리 안이면 다른 표적보다 먼저 쏜다.
static func focus(u: BattleUnit, target: BattleUnit) -> void:
	u.focus_target = target.id


static func clear_focus(u: BattleUnit) -> void:
	u.focus_target = ""
	u.attack_move = false


## 경유점: 지금 이동 목표(와 앞선 경유점)를 지난 뒤 이어서 간다. 이동 명령이 없으면 그냥 이동.
static func add_waypoint(u: BattleUnit, p: Vector2) -> void:
	if u.move_target == null:
		move(u, p)
		return
	u.waypoints.append(p)
	u.arrive_facing = null
	u.individual = true


## 마지막 목적지 (경유점이 있으면 마지막 경유점).
static func final_destination(u: BattleUnit) -> Variant:
	if not u.waypoints.is_empty():
		return u.waypoints[u.waypoints.size() - 1]
	return u.move_target


static func stop(u: BattleUnit) -> void:
	u.move_target = null
	u.waypoints.clear()
	u.reverse_move = false
	u.focus_target = ""
	u.attack_move = false
	u.individual = true


## 바라볼 방향. 이동 중이면 도착한 뒤에 그쪽을 본다.
static func face(u: BattleUnit, p: Vector2) -> void:
	var dir := p - u.center
	if dir.is_zero_approx():
		return
	u.arrive_facing = dir.normalized()
	if u.move_target == null:
		u.facing = u.arrive_facing


static func set_retreat_point(u: BattleUnit, p: Vector2) -> void:
	u.retreat_point = p


static func set_formation(u: BattleUnit, kind: String, tiles := -1) -> void:
	u.set_formation(kind, u.tile_count if tiles < 0 else tiles)


## 태세. 한 전선의 부대를 모두 고른 경우에만 전선 태세도 바꾼다.
static func set_stance(b: Battle, units: Array[BattleUnit], stance: BattleUnit.Stance) -> void:
	for u in units:
		u.stance = stance
	var line := common_line(b, units)
	if line != null and line.units.size() == units.size():
		line.stance = stance


static func fire_at_point(u: BattleUnit, p: Vector2) -> void:
	u.fire_order = {"mode": "point", "point": p}


static func fire_predicted(u: BattleUnit, target: BattleUnit) -> void:
	u.fire_order = {"mode": "predict", "target": target.id}


static func clear_fire(u: BattleUnit) -> void:
	u.fire_order = {}


## 부대가 속한 전선 (전선 부대 또는 예비대). 없으면 null.
static func line_of(b: Battle, unit_id: String) -> FrontLine:
	for line in b.front_lines:
		if line.units.has(unit_id) or line.reserves.has(unit_id):
			return line
	return null


static func common_line(b: Battle, units: Array[BattleUnit]) -> FrontLine:
	if units.is_empty():
		return null
	var line := line_of(b, units[0].id)
	if line == null:
		return null
	for u in units:
		if not line.units.has(u.id):
			return null
	return line


## 전선 긋기: 고른 부대들을 새 전선으로 묶는다. 부대는 선 위의 가까운 순서대로 선다.
static func draw_front_line(b: Battle, side: String, units: Array[BattleUnit], points: PackedVector2Array) -> FrontLine:
	if units.is_empty() or points.size() < 2:
		return null
	var ids: Array[String] = []
	for u in units:
		ids.append(u.id)
	_detach(b, ids)
	var sorted := units.duplicate()
	sorted.sort_custom(func(a, c): return _param_on(points, a.center) < _param_on(points, c.center))
	var line := FrontLine.new(_new_line_id(b, side), side, points, _enemy_dir(b, side, points))
	line.stance = units[0].stance
	for u in sorted:
		u.individual = false
		line.units.append(u.id)
	line.apply(b)
	b.front_lines.append(line)
	return line


static func set_offensive(b: Battle, line: FrontLine, points: PackedVector2Array) -> void:
	line.offensive = points
	line.apply(b)


static func set_retreat_line(b: Battle, line: FrontLine, points: PackedVector2Array) -> void:
	line.retreat = points
	line.apply(b)


## 예비대로 돌린다. 예비대는 제자리에서 기다리다 전선에 구멍이 나면 메운다.
static func add_reserves(b: Battle, line: FrontLine, units: Array[BattleUnit]) -> void:
	var ids: Array[String] = []
	for u in units:
		ids.append(u.id)
	_detach(b, ids)
	for u in units:
		line.reserves.append(u.id)
		u.individual = false
		u.move_target = null


## 다른 전선에서 빼고, 빈 전선은 지운다.
static func _detach(b: Battle, ids: Array[String]) -> void:
	for line in b.front_lines.duplicate():
		for id in ids:
			line.units.erase(id)
			line.reserves.erase(id)
		if line.units.is_empty() and line.reserves.is_empty():
			b.front_lines.erase(line)


static func _new_line_id(b: Battle, side: String) -> String:
	var n := 1
	while b.front_line("%s_line_%d" % [side, n]) != null:
		n += 1
	return "%s_line_%d" % [side, n]


## 적 쪽: 아는 적이 있으면 그 무게중심 쪽, 없으면 아군 무게중심 반대쪽.
static func _enemy_dir(b: Battle, side: String, points: PackedVector2Array) -> Vector2:
	var mid := FrontLine.point_at(points, 0.5)
	var d := (points[points.size() - 1] - points[0]).normalized()
	var n := Vector2(-d.y, d.x)
	var enemies := b.known_enemies(side)
	var side_sign := 1.0
	if not enemies.is_empty():
		var c := Vector2.ZERO
		for e in enemies:
			c += e.center
		side_sign = 1.0 if (c / enemies.size() - mid).dot(n) >= 0.0 else -1.0
	else:
		var c := Vector2.ZERO
		var count := 0
		for u in b.units:
			if u.side == side:
				c += u.center
				count += 1
		if count > 0:
			side_sign = -1.0 if (c / count - mid).dot(n) >= 0.0 else 1.0
	return n * side_sign


## 꺾은선에서 p 에 가장 가까운 지점의 길이 비율.
static func _param_on(points: PackedVector2Array, p: Vector2) -> float:
	var best := 0.0
	var best_d := INF
	for i in 65:
		var f := i / 64.0
		var d := FrontLine.point_at(points, f).distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = f
	return best
