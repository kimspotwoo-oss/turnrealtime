class_name DefenseAI
extends RefCounted
## 방어하는 적 AI (기획서 '적 AI'). 매 턴 준비기간에 plan_turn() 이 불린다.
##
## 자기 진영이 본 적만 보고 판단하고, 플레이어와 같은 명령(전선, 예비대, 태세, 포격)만 쓴다.
## 판단 순서: 마지막 수단 → 목표 수비대 → 위험 구간에 예비대 → 조용한 구간에서 병력 옮기기 →
## 후방 경계 → 반격 → 박격포 진지 변환 → 박격포 표적 → 집중 사격.
##
## 난이도는 능력치를 속이지 않고 판단의 폭만 바꾼다.
##   easy:   세 턴에 한 번만 예비대를 보내고, 반격·후방 경계·진지 변환을 하지 않는다. 박격포는 두 턴에 한 번 쏜다.
##   normal: 목표마다 수비대를 남기고, 포격받은 박격포는 자리를 옮기고, 전차·대전차포가 적 전차 쪽을 본다.
##   hard:   normal 에 더해 조용한 구간의 부대를 위험한 구간으로 옮기고, 적 전차 하나에 화력을 모으고,
##           박격포로 대전차포·박격포를 먼저 노리고, 반격을 여러 번 한다.

## 위협 ÷ 아군 화력이 이 값을 넘으면 위험 구간.
const DANGER_RATIO := 1.5
## 공격해 온 적의 평균 사기가 이 아래면 반격을 노린다.
const COUNTER_MORALE := 70.0
const COUNTER_MIN_RESERVES := 2
## 이 거리(칸) 안의 적을 "공격해 온 적"으로 본다.
const ATTACKER_RANGE := 14.0
## 남은 턴이 이만큼 이하면 후퇴하지 않고 사수한다.
const LAST_STAND_TURNS := 5
## 사거리 밖이라도 이 배수 거리까지는 곧 닿을 위협으로 절반만큼 친다.
const THREAT_REACH := 1.5
## 박격포·대전차포에서 이 거리(칸) 안에 적이 오면 후방이 위협받는 것으로 본다.
const REAR_THREAT_RANGE := 10.0
## 목표에서 이 거리(칸) 안에 적이 오면 수비대가 막으러 들어간다.
const GUARD_RANGE := 8.0
## 포격받은 박격포가 옮겨 가는 거리(칸).
const RELOCATE_TILES := 5.0
## 이 거리(칸) 안에 아는 적이 없는 전선 자리는 조용한 구간으로 본다.
const QUIET_RANGE := 18.0
const DIFFICULTIES := ["easy", "normal", "hard"]

## 판단하는 동안만 잡아 둔다. Battle 이 AI 를 들고 있어서, 계속 들고 있으면 순환 참조가 된다.
var battle: Battle
var side: String
var line: FrontLine
## 지켜야 할 구역 (상대의 점령 목표).
var objectives: Array[Rect2i] = []
var personality := "careful"
var difficulty := "normal"

var _counterattacked := false
var _redrawn := false
var _last_counter_turn := -100
## 목표를 지키려고 남겨 둔 예비대 id.
var _guards: Array[String] = []


func _init(p_side: String, p_line: FrontLine, p_objectives: Array[Rect2i]) -> void:
	side = p_side
	line = p_line
	objectives = p_objectives


func plan_turn(p_battle: Battle) -> void:
	battle = p_battle
	if battle.winner == "" and line != null:
		var easy := difficulty == "easy"
		var hard := difficulty == "hard"
		_last_stand()
		if not easy:
			_guard_objectives()
		if not easy or battle.turn % 3 == 1:
			if not _reinforce_danger() and hard:
				_shift_from_quiet()
		if not easy:
			_guard_rear()
			_face_armor()
			_counterattack()
			_relocate_mortars()
		_assign_mortars()
		if hard:
			_focus_armor()
	battle = null


# --- 영향력 ---------------------------------------------------------------

## 부대 하나가 1초에 낼 수 있는 예상 피해 (대략값).
static func firepower(u: BattleUnit) -> float:
	var total := 0.0
	for w in u.type.weapons:
		if w.close_at:
			continue
		var acc := 0.3 if w.indirect else w.acc_near
		total += u.weapon_count(w) * w.damage * acc / w.interval_ticks
	return total * Morale.ACCURACY[u.state()]


static func max_range(u: BattleUnit) -> float:
	var r := 0.0
	for w in u.type.weapons:
		r = maxf(r, w.range_tiles)
	return r


## 한 지점에 닿는 화력의 합. 사거리 밖 THREAT_REACH 배까지는 절반으로 친다.
static func influence(p: Vector2, units: Array[BattleUnit], reach := 1.0) -> float:
	var total := 0.0
	for u in units:
		var d := Vector2(u.nearest_tile_to(p)).distance_to(p)
		var r := max_range(u)
		if d <= r:
			total += firepower(u)
		elif d <= r * reach:
			total += firepower(u) * 0.5
	return total


## 전선을 지키는 아군 (예비대는 투입할지 정하는 대상이라 빼고 센다).
func _own_units() -> Array[BattleUnit]:
	var out: Array[BattleUnit] = []
	for u in battle.units:
		if u.side == side and u.is_alive() and u.state() != Morale.State.ROUTED and not line.reserves.has(u.id):
			out.append(u)
	return out


## 전선 각 자리의 위협 비율. 아군 화력이 없으면 매우 큰 값.
func danger_at(p: Vector2) -> float:
	var threat := influence(p, battle.known_enemies(side), THREAT_REACH)
	if threat == 0.0:
		return 0.0
	var own := influence(p, _own_units())
	return INF if own == 0.0 else threat / own


# --- 판단 ---------------------------------------------------------------

## 위협이 가장 큰 전선 자리에 가까운 예비대를 보낸다. 적 전차가 보이면 전차를 먼저 보낸다.
## 보냈으면 true. 위험한 곳이 없어도 true (더 할 일이 없다는 뜻).
func _reinforce_danger() -> bool:
	var worst := _worst_slot()
	if worst.is_empty():
		return true
	var worst_p: Vector2 = worst["point"]
	var tanks_near := false
	for e in battle.known_enemies(side):
		if e.type.is_vehicle() and e.center.distance_to(worst_p) <= ATTACKER_RANGE:
			tanks_near = true
	var r := _free_reserve(worst_p, tanks_near)
	if r == null:
		return false
	line.reserves.erase(r.id)
	line.units.append(r.id)
	line.send_to_slot(r, worst["slot"], worst_p)
	return true


## 위협 비율이 가장 큰 전선 자리. 위험한 곳이 없으면 빈 사전.
func _worst_slot() -> Dictionary:
	var out := {}
	var worst := DANGER_RATIO
	for uid in line.units:
		var f := line.slot_of(uid)
		if f < 0.0:
			continue
		var p := FrontLine.point_at(line.points, f)
		var ratio := danger_at(p)
		if ratio > worst:
			worst = ratio
			out = {"slot": f, "point": p, "unit": uid}
	return out


## 수비대로 묶이지 않은 예비대 중 가장 가까운 부대.
func _free_reserve(p: Vector2, prefer_vehicle := false) -> BattleUnit:
	var held: Array[String] = []
	for id in _guards:
		if line.reserves.has(id):
			held.append(id)
			line.reserves.erase(id)
	var r := line.nearest_reserve(battle, p, prefer_vehicle)
	line.reserves.append_array(held)
	return r


## 목표마다 가까운 보병 예비대 하나를 수비대로 남긴다. 적이 목표 가까이 오면 그쪽 가장자리로 들어가 막는다.
## 전차 한 소대가 빈 마을에 들어와 점령하는 것을 막기 위해서다.
func _guard_objectives() -> void:
	_guards = _guards.filter(func(id): return line.reserves.has(id) and battle.unit_by_id(id).is_alive())
	var enemies := battle.known_enemies(side)
	for rect in objectives:
		var center := Vector2(rect.position) + Vector2(rect.size) / 2.0
		var guard: BattleUnit = null
		for id in _guards:
			var g := battle.unit_by_id(id)
			if Rect2(rect).grow(3.0).has_point(g.center) and (guard == null or g.center.distance_to(center) < guard.center.distance_to(center)):
				guard = g
		if guard == null:
			var best := INF
			for rid in line.reserves:
				var r := battle.unit_by_id(rid)
				if r == null or not r.is_alive() or r.type.is_vehicle() or _guards.has(rid) or r.state() >= Morale.State.PANIC:
					continue
				var d := r.center.distance_to(center)
				if d < best:
					best = d
					guard = r
			if guard == null:
				continue
			_guards.append(guard.id)
		var near: BattleUnit = null
		for e in enemies:
			if e.state() == Morale.State.ROUTED:
				continue
			if Rect2(rect).grow(GUARD_RANGE).has_point(e.center) and (near == null or e.center.distance_to(center) < near.center.distance_to(center)):
				near = e
		if near == null:
			continue
		# 구역 안에서 적에 가장 가까운 자리.
		var spot := Vector2(clampf(near.center.x, rect.position.x, rect.end.x - 1), clampf(near.center.y, rect.position.y, rect.end.y - 1))
		_guards.erase(guard.id)
		line.reserves.erase(guard.id)
		guard.individual = true
		guard.stance = BattleUnit.Stance.ATTACK
		guard.move_target = spot
		guard.waypoints.clear()


## hard: 예비대가 없을 때, 근처에 적이 없는 전선 부대 하나를 가장 위험한 자리로 옮긴다.
func _shift_from_quiet() -> void:
	var worst := _worst_slot()
	if worst.is_empty():
		return
	var worst_p: Vector2 = worst["point"]
	var enemies := battle.known_enemies(side)
	var pick: BattleUnit = null
	for uid in line.units:
		var u := battle.unit_by_id(uid)
		if u == null or not u.is_alive() or u.individual or u.state() != Morale.State.STEADY or uid == worst["unit"]:
			continue
		if u.move_target != null:
			continue
		var quiet := true
		for e in enemies:
			if e.center.distance_to(u.center) <= QUIET_RANGE:
				quiet = false
		if quiet and (pick == null or u.center.distance_to(worst_p) < pick.center.distance_to(worst_p)):
			pick = u
	if pick != null:
		line.send_to_slot(pick, worst["slot"], worst_p)


## 서 있는 전차는 아는 적 전차 중 가장 가까운 쪽으로 정면(두꺼운 장갑)을 돌린다.
func _face_armor() -> void:
	var enemies := battle.known_enemies(side)
	for u in battle.units:
		if u.side != side or not u.is_alive() or not u.type.is_vehicle() or u.move_target != null:
			continue
		var tank: BattleUnit = null
		for e in enemies:
			if e.type.is_vehicle() and (tank == null or e.center.distance_to(u.center) < tank.center.distance_to(u.center)):
				tank = e
		if tank != null:
			u.facing = (tank.center - u.center).normalized()


## hard: 포를 가진 부대들이 같은 적 전차(목표에 가장 가까운 것)를 먼저 쏜다.
func _focus_armor() -> void:
	var target: BattleUnit = null
	var best := INF
	for e in battle.known_enemies(side):
		if not e.type.is_vehicle():
			continue
		for rect in objectives:
			var d := e.center.distance_to(Vector2(rect.position) + Vector2(rect.size) / 2.0)
			if d < best:
				best = d
				target = e
	for u in battle.units:
		if u.side == side and u.is_alive() and _can_kill_armor(u):
			u.focus_target = target.id if target != null else ""


## 지난 턴에 포격을 받았거나 사람을 잃은 박격포는 옆으로 자리를 옮긴다 (대포병 사격 피하기).
func _relocate_mortars() -> void:
	for u in battle.units:
		if u.side != side or not u.is_alive() or not _has_indirect(u) or u.move_target != null:
			continue
		if int(u.turn_log.get("shelled", 0)) == 0 and int(u.turn_log.get("lost", 0)) == 0:
			continue
		# 지도 가운데 쪽으로, 다른 아군과 겹치지 않는 자리.
		var dir := 1.0 if u.center.x < battle.map.width / 2.0 else -1.0
		for sign in [dir, -dir]:
			var to := u.center + Vector2(sign * RELOCATE_TILES, 0)
			if not battle.map.in_bounds(Vector2i(to.round())):
				continue
			if battle.friendly_near(side, to, 1.5):
				to += Vector2(sign * 2.0, 0)
			var was_individual := u.individual
			Orders.move(u, to)
			u.individual = was_individual
			u.fire_order = {}
			break


## 멀리서 전차를 잡을 수 있는 직사 무기가 있는가.
static func _can_kill_armor(u: BattleUnit) -> bool:
	for w in u.type.weapons:
		if not w.indirect and not w.close_at and w.pen_near >= 50.0:
			return true
	return false


static func _has_indirect(u: BattleUnit) -> bool:
	for w in u.type.weapons:
		if w.indirect:
			return true
	return false


## 대전차포는 아는 적 전차 중 가장 가까운 쪽으로 포를 돌린다. 포 진지 가까이 적이 오면
## 예비대 하나를 보내 쫓아낸다.
func _guard_rear() -> void:
	var enemies := battle.known_enemies(side)
	for u in battle.units:
		if u.side != side or not u.is_alive() or u.type.setup_ticks == 0:
			continue
		var tank: BattleUnit = null
		var near: BattleUnit = null
		for e in enemies:
			if e.state() == Morale.State.ROUTED:
				continue
			var d := e.center.distance_to(u.center)
			if e.type.is_vehicle() and (tank == null or d < tank.center.distance_to(u.center)):
				tank = e
			if d <= REAR_THREAT_RANGE and (near == null or d < near.center.distance_to(u.center)):
				near = e
		if tank != null and _has_direct_gun(u):
			u.facing = (tank.center - u.center).normalized()
		if near == null:
			continue
		var r := _free_reserve(near.center, near.type.is_vehicle())
		if r == null:
			continue
		line.reserves.erase(r.id)
		r.individual = true
		r.stance = BattleUnit.Stance.ATTACK
		r.move_target = near.center


static func _has_direct_gun(u: BattleUnit) -> bool:
	for w in u.type.weapons:
		if w.scale == "gun" and not w.indirect:
			return true
	return false


## 공격해 온 적이 흔들리고 온전한 예비대가 둘 이상이면 짧게 반격한다.
func _counterattack() -> void:
	if personality == "hold":
		return
	# hard 는 네 턴마다 다시 반격할 수 있다.
	if _counterattacked and (difficulty != "hard" or battle.turn - _last_counter_turn < 4):
		return
	var attackers: Array[BattleUnit] = []
	var morale_sum := 0.0
	for e in battle.known_enemies(side):
		if _near_line_or_objective(e.center):
			attackers.append(e)
			morale_sum += e.morale
	if attackers.is_empty() or morale_sum / attackers.size() >= COUNTER_MORALE:
		return
	var ready: Array[BattleUnit] = []
	for rid in line.reserves:
		var r := battle.unit_by_id(rid)
		if r != null and r.is_alive() and r.state() == Morale.State.STEADY and not _guards.has(rid):
			ready.append(r)
	if ready.size() < COUNTER_MIN_RESERVES:
		return
	ready.sort_custom(func(a, b): return a.type.is_vehicle() and not b.type.is_vehicle())
	for r in ready.slice(0, 2):
		var target := attackers[0]
		for e in attackers:
			if e.center.distance_to(r.center) < target.center.distance_to(r.center):
				target = e
		line.reserves.erase(r.id)
		r.individual = true
		r.stance = BattleUnit.Stance.ATTACK
		r.move_target = target.center
	_counterattacked = true
	_last_counter_turn = battle.turn


func _near_line_or_objective(p: Vector2) -> bool:
	for rect in objectives:
		if Rect2(rect).grow(ATTACKER_RANGE).has_point(p):
			return true
	for i in range(1, line.points.size()):
		if Geometry2D.get_closest_point_to_segment(p, line.points[i - 1], line.points[i]).distance_to(p) <= ATTACKER_RANGE:
			return true
	return false


## 목표 하나를 잃으면 남은 목표 앞에 전선을 다시 긋고, 막판에는 후퇴하지 않는다.
func _last_stand() -> void:
	if not _redrawn:
		var held: Array[Rect2i] = []
		var lost := false
		for rect in objectives:
			if battle.holds(side, rect):
				held.append(rect)
			elif _enemy_in(rect):
				lost = true
		if lost and held.size() > 0:
			var rect := held[0]
			# 구역 안 가장자리 줄에 선다. 구역 밖에 서면 점령을 막지 못한다.
			var y := float(rect.end.y - 1) if line.enemy_dir.y > 0.0 else float(rect.position.y)
			line.points = PackedVector2Array([Vector2(rect.position.x - 1, y), Vector2(rect.end.x, y)])
			line.offensive = PackedVector2Array()
			line.retreat = PackedVector2Array()
			line.apply(battle)
			_redrawn = true
	if battle.turn_limit - battle.turn <= LAST_STAND_TURNS:
		line.stance = BattleUnit.Stance.HOLD
		for uid in line.units:
			var u := battle.unit_by_id(uid)
			if u != null and not u.individual:
				u.stance = BattleUnit.Stance.HOLD
				u.retreat_point = u.center


func _mortar_value(e: BattleUnit) -> float:
	var v := float(e.alive_count("man"))
	if difficulty == "hard" and e.type.setup_ticks > 0:
		v += 100.0
	return v


func _enemy_in(rect: Rect2i) -> bool:
	for u in battle.units:
		if u.side != side and u.is_alive():
			for t in u.tiles():
				if rect.has_point(t):
					return true
	return false


## 박격포: 아는 적 보병 중 가장 큰 무리를 노린다. 움직이는 중이면 예측 사격.
## easy 는 두 턴에 한 번만 쏘고, hard 는 대전차포·박격포를 먼저 노린다.
func _assign_mortars() -> void:
	for u in battle.units:
		if u.side != side or not u.is_alive():
			continue
		if u.move_target != null:
			continue
		if difficulty == "easy" and battle.turn % 2 == 0:
			if _has_indirect(u):
				u.fire_order = {}
			continue
		for w in u.type.weapons:
			if not w.indirect:
				continue
			var best: BattleUnit = null
			for e in battle.known_enemies(side):
				if e.type.is_vehicle() or battle.in_melee(e):
					continue
				if battle.friendly_near(side, e.center, w.blast_tiles + Battle.FRIENDLY_FIRE_MARGIN):
					continue
				var d := u.center.distance_to(e.center)
				if d < w.min_range_tiles or d > w.range_tiles:
					continue
				if best == null or _mortar_value(e) > _mortar_value(best):
					best = e
			if best == null:
				u.fire_order = {}
			elif best.velocity.length() > 0.01:
				u.fire_order = {"mode": "predict", "target": best.id}
			else:
				u.fire_order = {"mode": "point", "point": best.center}
