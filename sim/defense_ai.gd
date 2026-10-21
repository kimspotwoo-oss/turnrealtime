class_name DefenseAI
extends RefCounted
## 방어하는 적 AI (기획서 '적 AI'). 매 턴 준비기간에 plan_turn() 이 불린다.
##
## 자기 진영이 본 적만 보고 판단하고, 플레이어와 같은 명령(전선, 예비대, 태세, 포격)만 쓴다.
## 1단계 판단 순서: 마지막 수단 → 위험 구간에 예비대 → 반격 → 박격포 표적.

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

## 판단하는 동안만 잡아 둔다. Battle 이 AI 를 들고 있어서, 계속 들고 있으면 순환 참조가 된다.
var battle: Battle
var side: String
var line: FrontLine
## 지켜야 할 구역 (상대의 점령 목표).
var objectives: Array[Rect2i] = []
var personality := "careful"

var _counterattacked := false
var _redrawn := false


func _init(p_side: String, p_line: FrontLine, p_objectives: Array[Rect2i]) -> void:
	side = p_side
	line = p_line
	objectives = p_objectives


func plan_turn(p_battle: Battle) -> void:
	battle = p_battle
	if battle.winner == "" and line != null:
		_last_stand()
		_reinforce_danger()
		_counterattack()
		_assign_mortars()
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
func _reinforce_danger() -> void:
	var worst_f := -1.0
	var worst_p := Vector2.ZERO
	var worst := DANGER_RATIO
	for uid in line.units:
		var f := line.slot_of(uid)
		if f < 0.0:
			continue
		var p := FrontLine.point_at(line.points, f)
		var ratio := danger_at(p)
		if ratio > worst:
			worst = ratio
			worst_f = f
			worst_p = p
	if worst_f < 0.0:
		return
	var tanks_near := false
	for e in battle.known_enemies(side):
		if e.type.is_vehicle() and e.center.distance_to(worst_p) <= ATTACKER_RANGE:
			tanks_near = true
	var r := line.nearest_reserve(battle, worst_p, tanks_near)
	if r == null:
		return
	line.reserves.erase(r.id)
	line.units.append(r.id)
	line.send_to_slot(r, worst_f, worst_p)


## 공격해 온 적이 흔들리고 온전한 예비대가 둘 이상이면 짧게 반격한다.
func _counterattack() -> void:
	if _counterattacked or personality == "hold":
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
		if r != null and r.is_alive() and r.state() == Morale.State.STEADY:
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
			var y := float(rect.end.y) if line.enemy_dir.y > 0.0 else float(rect.position.y - 1)
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


func _enemy_in(rect: Rect2i) -> bool:
	for u in battle.units:
		if u.side != side and u.is_alive():
			for t in u.tiles():
				if rect.has_point(t):
					return true
	return false


## 박격포: 아는 적 보병 중 가장 큰 무리를 노린다. 움직이는 중이면 예측 사격.
func _assign_mortars() -> void:
	for u in battle.units:
		if u.side != side or not u.is_alive():
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
				if best == null or e.alive_count("man") > best.alive_count("man"):
					best = e
			if best == null:
				u.fire_order = {}
			elif best.velocity.length() > 0.01:
				u.fire_order = {"mode": "predict", "target": best.id}
			else:
				u.fire_order = {"mode": "point", "point": best.center}
