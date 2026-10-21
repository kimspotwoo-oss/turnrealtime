class_name Orders
extends RefCounted
## 준비기간에 내리는 명령. 화면(과 나중의 온라인 대전)은 이 함수들로만 명령을 바꾼다.

## 개별 이동. 전선에 속한 부대라도 개별 명령이 우선한다.
static func move(u: BattleUnit, target: Vector2) -> void:
	u.move_target = target
	u.arrive_facing = null
	u.individual = true


static func stop(u: BattleUnit) -> void:
	u.move_target = null
	u.individual = true


static func set_retreat_point(u: BattleUnit, p: Vector2) -> void:
	u.retreat_point = p


static func set_formation(u: BattleUnit, kind: String, tiles := -1) -> void:
	u.set_formation(kind, u.tile_count if tiles < 0 else tiles)


## 태세. 고른 부대가 모두 한 전선의 부대면 전선 태세도 바꾼다.
static func set_stance(b: Battle, units: Array[BattleUnit], stance: BattleUnit.Stance) -> void:
	for u in units:
		u.stance = stance
	var line := common_line(b, units)
	if line != null:
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
