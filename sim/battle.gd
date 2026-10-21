class_name Battle
extends RefCounted
## 집중전투 한 판. 실행기간을 1초 틱으로 계산한다 (기획서 '실행기간의 처리 순서').
##
## 화면과 상관없는 순수 계산이라 테스트에서 그대로 돌릴 수 있다. 랜덤은 모두 rng 하나를
## 거치므로 같은 시드와 같은 명령이면 항상 같은 결과가 나온다.

## 발견 후 첫 사격까지 걸리는 시간 (틱).
const REACTION_MIN := 2
const REACTION_MAX := 3
## 공격 태세 부대가 멈춰 서는 거리 (교전 거리 대비). 보병은 끝까지 붙어 근접전에 들어간다.
const ATTACK_CLOSE_FRACTION := 0.3
const MOVING_ACCURACY := 0.5
## 제압돼 엎드린 보병은 맞을 확률이 절반.
const PRONE_ACCURACY := 0.5
## 포탄 폭발: 떨어진 칸 인원이 맞을 확률. 폭발 반경 안의 다른 칸은 BLAST_EDGE_FACTOR 배.
const BLAST_HIT_CHANCE := 0.15
const BLAST_EDGE_FACTOR := 0.3
## 아군이 이 거리 안에 있으면 자동 간접 사격을 하지 않는다 (칸).
const FRIENDLY_FIRE_MARGIN := 3
## 근접전: 근접 전투력 1 기준으로 인원 하나가 틱마다 상대 하나를 쓰러뜨릴 확률.
const MELEE_KILL_CHANCE := 0.03
## 근접 대전차 무기 하나가 틱마다 전차를 맞힐 확률.
const CLOSE_AT_CHANCE := 0.1
## 짧은 시간에 이만큼 잃으면 기습 충격.
const LOSS_SHOCK_FRACTION := 0.1
const LOSS_SHOCK_WINDOW := 5

var map: BattleMap
var units: Array[BattleUnit] = []
var rng := RandomNumberGenerator.new()
var tick := 0
var turn := 0
## 이번 실행기간에서 지난 틱 수.
var turn_tick := 0
var turn_seconds := 60
var turn_limit := 20
## 날아가는 포탄: {"land_tick": int, "point": Vector2, "weapon": WeaponType, "attacker": BattleUnit}
var shells: Array[Dictionary] = []
## 승리 조건: {"capture": {진영: [Rect2i, ...]}, "defender": 진영}
var victory := {}
var front_lines: Array[FrontLine] = []
## 준비기간마다 plan_turn() 을 부를 AI 들.
var ai_players: Array = []
var winner := ""

## 칸 → 그 칸을 차지한 부대들
var _occupancy := {}
## 부대 id → {보이는 적 id: true}
var _visible := {}
## 진영 → {진영 누군가 본 적 id: true}. 간접 사격은 이걸로 쏜다.
var _side_known := {}


func _init(p_map: BattleMap, seed_value := 0) -> void:
	map = p_map
	rng.seed = seed_value


func add_unit(u: BattleUnit) -> BattleUnit:
	units.append(u)
	_rebuild_occupancy()
	return u


func unit_by_id(id: String) -> BattleUnit:
	for u in units:
		if u.id == id:
			return u
	return null


func can_see(viewer: BattleUnit, target: BattleUnit) -> bool:
	return _visible.get(viewer.id, {}).has(target.id)


func side_knows(side: String, target: BattleUnit) -> bool:
	return _side_known.get(side, {}).has(target.id)


## 그 진영이 지금 아는 적. AI 는 이것만 보고 판단한다.
func known_enemies(side: String) -> Array[BattleUnit]:
	var out: Array[BattleUnit] = []
	for eid in _side_known.get(side, {}):
		var e := unit_by_id(eid)
		if e.is_alive():
			out.append(e)
	return out


func front_line(id: String) -> FrontLine:
	for line in front_lines:
		if line.id == id:
			return line
	return null


## 실행기간 한 턴. 승패가 나면 그 틱에서 멈춘다.
func run_turn() -> void:
	if winner != "":
		return
	begin_turn()
	while not turn_over():
		step()
	end_turn()


## 준비기간이 끝나고 실행기간을 시작한다. AI 는 여기서 이번 턴 명령을 정한다.
## 화면은 begin_turn → step 반복 → end_turn 으로 실행기간을 천천히 보여 줄 수 있다.
func begin_turn() -> void:
	turn += 1
	turn_tick = 0
	for ai in ai_players:
		ai.plan_turn(self)
	for u in units:
		u.turn_start_center = u.center


func turn_over() -> bool:
	return winner != "" or turn_tick >= turn_seconds


func end_turn() -> void:
	for u in units:
		u.velocity = (u.center - u.turn_start_center) / turn_seconds
	if winner == "" and turn >= turn_limit:
		winner = victory.get("defender", "")


func step() -> void:
	tick += 1
	turn_tick += 1
	# 1. 명령 도착: 1단계에는 통신 지연이 없어서 준비기간 명령이 그대로 유효하다.
	#    전선은 공세선 보조와 예비대 투입만 한다.
	for line in front_lines:
		line.update(self)
	_move()
	_rebuild_occupancy()
	_update_vision()
	_engage()
	var hits: Array[Dictionary] = []
	_fire(hits)
	_melee(hits)
	_impacts(hits)
	_apply(hits)
	_update_morale()
	_check_victory()


## 같은 시드·명령이면 같은 값이 나와야 하는 상태 요약 (리플레이·테스트용).
func state_hash() -> int:
	var parts: Array[String] = []
	for u in units:
		var hp := 0.0
		for e in u.elements:
			hp += e["hp"]
		parts.append("%s|%.4f,%.4f|%.2f|%.3f|%.3f" % [u.id, u.center.x, u.center.y, hp, u.morale, u.suppression])
	return ("%d;" % tick + ";".join(parts)).hash()


# --- 2. 이동 ---------------------------------------------------------------

func _move() -> void:
	for u in units:
		u.moved_this_tick = false
		if not u.is_alive():
			continue
		var st := u.state()
		var target = u.move_target
		var retreating := false
		if st == Morale.State.ROUTED:
			target = u.retreat_point
			retreating = true
		elif st == Morale.State.PANIC:
			target = null
		elif u.stance == BattleUnit.Stance.RETREAT and target == u.retreat_point:
			retreating = true
		if target == null or (u.pace_hold and not retreating):
			_settle(u)
			continue
		var to: Vector2 = target - u.center
		if to.length() < 0.01:
			if target == u.move_target:
				u.move_target = null
				if u.arrive_facing != null:
					u.facing = u.arrive_facing
			_settle(u)
			continue
		if u.is_pinned() and not retreating:
			_settle(u)
			continue
		# 근접전 중인 부대는 다른 적 칸으로 전진하지 못하고 물러나기만 한다.
		var melee_foe = _melee_enemy_center(u)
		if melee_foe != null and to.dot(_toward(u, melee_foe)) > 0.0:
			_settle(u)
			continue
		var speed := _speed(u) / 60.0
		if u.is_suppressed():
			speed *= 0.5
		var dir := to.normalized()
		var next_center := u.center + dir * minf(speed, to.length())
		if _vehicle_blocked(u, next_center, dir):
			_settle(u)
			continue
		u.center = next_center
		# 자리만 조금 고치는 짧은 이동에서는 방향을 돌리지 않는다.
		if to.length() > 1.0 or u.arrive_facing == null:
			u.facing = dir
		u.moved_this_tick = true
		if u.type.setup_ticks > 0:
			u.deployed = false
			u.setup_left = u.type.setup_ticks


## 적 쪽 방향. 중심이 겹치면 부대가 바라보는 쪽을 적 쪽으로 본다.
func _toward(u: BattleUnit, p: Vector2) -> Vector2:
	var d := p - u.center
	return u.facing if d.is_zero_approx() else d


## 멈춰 있는 포는 전개 시간이 지나면 다시 쏠 수 있다.
func _settle(u: BattleUnit) -> void:
	if not u.deployed:
		u.setup_left -= 1
		if u.setup_left <= 0:
			u.deployed = true


func _speed(u: BattleUnit) -> float:
	var tile := Vector2i(u.center.round())
	var p := map.props(tile)
	if u.type.is_vehicle():
		if map.terrain_at(tile) == "road" and u.type.speed.has("road"):
			return float(u.type.speed["road"])
		return float(u.type.speed["vehicle"]) * p["move_vehicle"]
	return float(u.type.speed["foot"]) * p["move_foot"]


## 전차끼리는 같은 칸에 들어갈 수 없다.
func _vehicle_blocked(u: BattleUnit, next_center: Vector2, dir: Vector2) -> bool:
	if not u.type.is_vehicle():
		return false
	var next_tiles := Formation.world_tiles(next_center, dir, u.offsets)
	for o in units:
		if o == u or not o.type.is_vehicle() or not o.is_alive():
			continue
		for t in o.tiles():
			if next_tiles.has(t):
				return true
	return false


func _rebuild_occupancy() -> void:
	_occupancy.clear()
	for u in units:
		if not u.is_alive():
			continue
		for t in u.tiles():
			if not _occupancy.has(t):
				_occupancy[t] = []
			_occupancy[t].append(u)


func _melee_enemy_center(u: BattleUnit) -> Variant:
	for t in u.tiles():
		for o in _occupancy.get(t, []):
			if o.side != u.side:
				return o.center
	return null


func in_melee(u: BattleUnit) -> bool:
	return _melee_enemy_center(u) != null


# --- 3. 시야·발견 -----------------------------------------------------------

func _update_vision() -> void:
	_side_known.clear()
	for u in units:
		var seen := {}
		if u.is_alive():
			for e in units:
				if e.side != u.side and _sees(u, e):
					seen[e.id] = true
		var extra: int = Morale.EXTRA_REACTION[u.state()]
		for eid in seen:
			if u.reaction.has(eid):
				u.reaction[eid] = maxi(0, u.reaction[eid] - 1)
			else:
				u.reaction[eid] = rng.randi_range(REACTION_MIN, REACTION_MAX) + extra
		for eid in u.reaction.keys():
			if not seen.has(eid):
				u.reaction.erase(eid)
		_visible[u.id] = seen
		if not _side_known.has(u.side):
			_side_known[u.side] = {}
		_side_known[u.side].merge(seen)


func _sees(u: BattleUnit, e: BattleUnit) -> bool:
	if not e.is_alive():
		return false
	var e_tile := e.nearest_tile_to(u.center)
	var u_tile := u.nearest_tile_to(Vector2(e_tile))
	var d := Vector2(u_tile).distance_to(Vector2(e_tile))
	if d > u.type.sight_tiles * map.props(e_tile)["conceal"]:
		return false
	return not map.line_blocked(u_tile, e_tile)


## 두 부대에서 서로 가장 가까운 칸 사이의 거리 (칸).
func distance_between(a: BattleUnit, b: BattleUnit) -> float:
	var b_tile := b.nearest_tile_to(a.center)
	var a_tile := a.nearest_tile_to(Vector2(b_tile))
	return Vector2(a_tile).distance_to(Vector2(b_tile))


# --- 4. 교전 판정과 반응 태세 -------------------------------------------------

func _engage() -> void:
	for u in units:
		if not u.is_alive() or u.state() >= Morale.State.PANIC:
			continue
		var foe := _nearest_visible(u)
		if foe == null:
			continue
		var engage_range := _engage_range(u)
		var d := distance_between(u, foe)
		if d > engage_range:
			continue
		match u.stance:
			BattleUnit.Stance.ATTACK:
				# 공격: 적에게 바로 다가간다. 보병은 근접전까지 붙는다.
				var stop := 0.0 if _closes_to_melee(u) else engage_range * ATTACK_CLOSE_FRACTION
				u.move_target = foe.center if d > stop else null
			BattleUnit.Stance.RETREAT:
				u.move_target = u.retreat_point
			BattleUnit.Stance.HOLD:
				# 저지: 1단계에서는 그 자리에 멈춰 막는다. 적 진로 앞으로 나가는 건 나중에.
				u.move_target = null
			BattleUnit.Stance.IGNORE:
				pass


func _nearest_visible(u: BattleUnit) -> BattleUnit:
	var best: BattleUnit = null
	var best_d := INF
	for eid in _visible.get(u.id, {}):
		var e := unit_by_id(eid)
		var d := distance_between(u, e)
		if d < best_d:
			best_d = d
			best = e
	return best


## 교전 거리: 직사 무기 중 가장 긴 사거리. 직사 무기가 없으면 시야.
func _engage_range(u: BattleUnit) -> float:
	var r := 0.0
	for w in u.type.weapons:
		if not w.indirect and not w.close_at:
			r = maxf(r, w.range_tiles)
	return r if r > 0.0 else u.type.sight_tiles


func _closes_to_melee(u: BattleUnit) -> bool:
	return not u.type.is_vehicle() and u.type.melee_power >= 1.0


# --- 5. 사격 ---------------------------------------------------------------

func _fire(hits: Array[Dictionary]) -> void:
	for u in units:
		if not u.is_alive() or u.state() == Morale.State.ROUTED:
			continue
		var melee := in_melee(u)
		for w in u.type.weapons:
			if u.cooldowns[w.id] > 0:
				u.cooldowns[w.id] -= 1
				continue
			if u.type.setup_ticks > 0 and not u.deployed:
				continue
			var n := u.weapon_count(w)
			if n == 0:
				continue
			var fired := false
			if w.indirect:
				fired = _fire_indirect(u, w, n)
			elif not melee:
				# 근접전 중인 병력은 밖으로 쏘지 못한다.
				fired = _fire_direct(u, w, n, hits)
			if fired:
				var interval := w.interval_ticks * u.crew_slowdown(w)
				if u.is_suppressed():
					interval *= 2
				u.cooldowns[w.id] = interval


func _fire_direct(u: BattleUnit, w: WeaponType, n: int, hits: Array[Dictionary]) -> bool:
	var target := _pick_direct_target(u, w)
	if target == null:
		return false
	var d := distance_between(u, target)
	var acc: float = w.accuracy_at(d) * Morale.ACCURACY[u.state()]
	if u.moved_this_tick:
		acc *= MOVING_ACCURACY
	var unseen := not can_see(target, u)
	var target_tiles := target.tiles()
	hits.append(_hit(target, -1, 0.0, w.suppression * n, u, unseen))
	u.last_target = target.id
	u.last_fire_point = null
	u.last_fire_tick = tick
	for i in n:
		var idx := _pick_element(target, w)
		if idx < 0:
			break
		var e := target.elements[idx]
		match e["kind"]:
			"man":
				var chance: float = acc * map.props(target.element_tile(idx, target_tiles))["cover"]
				if target.is_suppressed():
					chance *= PRONE_ACCURACY
				if rng.randf() < chance:
					hits.append(_hit(target, idx, w.damage, 0.0, u, false))
			"vehicle":
				if rng.randf() < acc:
					var side := Combat.hit_side(target.center, target.facing, u.center)
					var res := Combat.armored_hit(rng, w.damage, w.pen_at(d), Combat.armor_for(target.type, side))
					hits.append(_hit(target, idx, res["damage"], 0.0, u, false))
			"gun":
				if rng.randf() < acc:
					var shield: float = e["shield"] if Combat.hit_side(target.center, target.facing, u.center) == "front" else 0.0
					var res := Combat.armored_hit(rng, w.damage, w.pen_at(d), shield)
					hits.append(_hit(target, idx, res["damage"], 0.0, u, false))
	return true


func _pick_direct_target(u: BattleUnit, w: WeaponType) -> BattleUnit:
	var best: BattleUnit = null
	var best_score := INF
	for eid in _visible.get(u.id, {}):
		if u.reaction.get(eid, 1) > 0:
			continue
		var e := unit_by_id(eid)
		if not e.is_alive() or in_melee(e):
			# 근접전 칸으로는 직사하지 않는다 (아군 오사 위험).
			continue
		var d := distance_between(u, e)
		if d > w.range_tiles:
			continue
		var armored := e.type.is_vehicle()
		if w.is_small_arms() and armored:
			continue
		if w.close_at and not armored:
			continue
		var score := d
		if armored and not w.is_small_arms():
			score -= 1000.0
		if score < best_score:
			best_score = score
			best = e
	return best


## 한 발이 노리는 구성원. 대전차 무기는 차량·포를, 소화기는 사람을 먼저 노린다.
func _pick_element(target: BattleUnit, w: WeaponType) -> int:
	var order := ["man", "gun", "vehicle"] if w.is_small_arms() else ["vehicle", "gun", "man"]
	for kind in order:
		var alive := target.alive_indices(kind)
		if not alive.is_empty():
			return alive[rng.randi_range(0, alive.size() - 1)]
	return -1


func _fire_indirect(u: BattleUnit, w: WeaponType, n: int) -> bool:
	var aim = null
	var aimed: BattleUnit = null
	var observed := true
	match u.fire_order.get("mode", ""):
		"point":
			aim = u.fire_order["point"]
			observed = _known_enemy_near(u.side, aim, w.blast_tiles + 2)
		"predict":
			var t := unit_by_id(u.fire_order["target"])
			if t != null and t.is_alive() and side_knows(u.side, t):
				aim = predict_aim(u, w, t)
		_:
			aimed = _auto_indirect_target(u, w)
			if aimed != null:
				aim = aimed.center
	if aim == null:
		return false
	var dist := u.center.distance_to(aim)
	if dist < w.min_range_tiles or dist > w.range_tiles:
		return false
	var mult := 1.0 if observed else Combat.SCATTER_UNOBSERVED
	if u.moved_this_tick:
		mult *= Combat.SCATTER_MOVING
	for i in n:
		var p := Combat.scatter_point(rng, u.center, aim, w, mult)
		var flight := maxi(1, ceili(u.center.distance_to(p) / w.shell_speed_tiles))
		shells.append({"land_tick": tick + flight, "point": p, "weapon": w, "attacker": u})
	u.last_target = u.fire_order.get("target", "") if u.fire_order.get("mode", "") == "predict" else (aimed.id if aimed != null else "")
	u.last_fire_point = aim
	u.last_fire_tick = tick
	return true


## 예측 사격: 목표의 지난 턴 속도와 방향으로 포탄이 닿을 때의 위치를 노린다.
func predict_aim(u: BattleUnit, w: WeaponType, t: BattleUnit) -> Vector2:
	var flight := u.center.distance_to(t.center) / w.shell_speed_tiles
	return t.center + t.velocity * flight


func _auto_indirect_target(u: BattleUnit, w: WeaponType) -> BattleUnit:
	var best: BattleUnit = null
	var best_d := INF
	for eid in _side_known.get(u.side, {}):
		var e := unit_by_id(eid)
		if not e.is_alive() or in_melee(e):
			continue
		var d := u.center.distance_to(e.center)
		if d < w.min_range_tiles or d > w.range_tiles:
			continue
		if friendly_near(u.side, e.center, w.blast_tiles + FRIENDLY_FIRE_MARGIN):
			continue
		if d < best_d:
			best_d = d
			best = e
	return best


func friendly_near(side: String, p: Vector2, radius: float) -> bool:
	for o in units:
		if o.side == side and o.is_alive() and Vector2(o.nearest_tile_to(p)).distance_to(p) <= radius:
			return true
	return false


func _known_enemy_near(side: String, p: Vector2, radius: float) -> bool:
	for eid in _side_known.get(side, {}):
		var e := unit_by_id(eid)
		if e.is_alive() and Vector2(e.nearest_tile_to(p)).distance_to(p) <= radius:
			return true
	return false


# --- 근접전 ---------------------------------------------------------------

func _melee(hits: Array[Dictionary]) -> void:
	for tile in _occupancy:
		var occ: Array = _occupancy[tile]
		for a in occ:
			for b in occ:
				if a.side != b.side:
					_melee_attack(a, b, tile, hits)


func _melee_attack(a: BattleUnit, b: BattleUnit, tile: Vector2i, hits: Array[Dictionary]) -> void:
	var a_tiles := a.tiles()
	var b_tiles := b.tiles()
	var attackers := _indices_on_tile(a, a_tiles, tile, "vehicle" if a.type.is_vehicle() else "man")
	if attackers.is_empty():
		return
	if b.type.is_vehicle():
		# 전차와 칸을 공유한 보병은 근접 대전차 무기가 있을 때만 측·후면을 칠 수 있다.
		var at_count := 0
		for w in a.type.weapons:
			if w.close_at:
				at_count += a.weapon_count(w)
				for i in mini(at_count, attackers.size()):
					if rng.randf() < CLOSE_AT_CHANCE:
						var targets := _indices_on_tile(b, b_tiles, tile, "vehicle")
						if targets.is_empty():
							break
						var idx: int = targets[rng.randi_range(0, targets.size() - 1)]
						var res := Combat.armored_hit(rng, w.damage, w.pen_near, b.type.armor_side())
						hits.append(_hit(b, idx, res["damage"], 0.0, a, false))
		if at_count == 0:
			hits.append(_hit(a, -1, 0.0, 0.0, null, false, 2))
		return
	var defenders := _indices_on_tile(b, b_tiles, tile, "man")
	if defenders.is_empty():
		return
	var chance: float = MELEE_KILL_CHANCE * a.type.melee_power * Morale.ACCURACY[a.state()]
	for i in attackers.size():
		if rng.randf() < chance:
			var idx: int = defenders[rng.randi_range(0, defenders.size() - 1)]
			hits.append(_hit(b, idx, b.elements[idx]["max_hp"], 0.0, a, false))


func _indices_on_tile(u: BattleUnit, unit_tiles: Array[Vector2i], tile: Vector2i, kind: String) -> Array[int]:
	var out: Array[int] = []
	for i in u.alive_indices(kind):
		if u.element_tile(i, unit_tiles) == tile:
			out.append(i)
	return out


# --- 6. 착탄 ---------------------------------------------------------------

func _impacts(hits: Array[Dictionary]) -> void:
	var landed: Array[Dictionary] = []
	for s in shells:
		if s["land_tick"] <= tick:
			landed.append(s)
	for s in landed:
		shells.erase(s)
		_explode(s, hits)


## 폭발은 피아를 가리지 않는다. 같은 인원이 적은 칸에 몰려 있을수록 많이 당한다.
func _explode(s: Dictionary, hits: Array[Dictionary]) -> void:
	var w: WeaponType = s["weapon"]
	var land := Vector2i((s["point"] as Vector2).round())
	for u in units:
		if not u.is_alive():
			continue
		var unit_tiles := u.tiles()
		var nearest := 1 << 30
		for t in unit_tiles:
			nearest = mini(nearest, _cheb(t, land))
		if nearest > w.blast_tiles + 2:
			continue
		var supp := w.suppression if nearest <= w.blast_tiles else w.suppression * 0.5
		hits.append(_hit(u, -1, 0.0, supp, s["attacker"], false, 1 if nearest <= 1 else 0))
		for i in u.alive_indices():
			var et := u.element_tile(i, unit_tiles)
			var dist := Vector2(et).distance_to(Vector2(land))
			if dist > w.blast_tiles:
				continue
			var factor := 1.0 if et == land else BLAST_EDGE_FACTOR
			var e := u.elements[i]
			if e["kind"] == "man":
				var chance: float = BLAST_HIT_CHANCE * factor * map.props(et)["cover"]
				if u.is_suppressed():
					chance *= PRONE_ACCURACY
				if rng.randf() < chance:
					hits.append(_hit(u, i, w.damage, 0.0, s["attacker"], false))
			elif rng.randf() < 0.5 * factor:
				var armor := u.type.armor_side() if e["kind"] == "vehicle" else 0.0
				var res := Combat.armored_hit(rng, w.damage, w.pen_near, armor)
				hits.append(_hit(u, i, res["damage"], 0.0, s["attacker"], false))


static func _cheb(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


# --- 7. 피해 일괄 적용 -------------------------------------------------------

func _hit(target: BattleUnit, element: int, damage: float, suppression: float, attacker: BattleUnit, unseen: bool, shock := 0) -> Dictionary:
	return {"target": target, "element": element, "damage": damage, "suppression": suppression, "attacker": attacker, "unseen": unseen, "shock": shock}


## 이번 틱의 사격을 모두 계산한 뒤 한꺼번에 적용한다. 그래서 서로 동시에 쓰러질 수 있다.
func _apply(hits: Array[Dictionary]) -> void:
	var losses := {}
	for h in hits:
		var t: BattleUnit = h["target"]
		var idx: int = h["element"]
		if idx >= 0:
			var e := t.elements[idx]
			if e["hp"] > 0.0:
				e["hp"] = maxf(0.0, e["hp"] - h["damage"])
				if e["hp"] == 0.0:
					losses[t] = losses.get(t, 0) + 1
		t.suppression = minf(Morale.SUPPRESSION_MAX, t.suppression + h["suppression"])
		if h["attacker"] != null:
			t.last_attacked_tick = tick
		if h["unseen"]:
			_shock(t, 1)
		if h["shock"] > 0:
			_shock(t, h["shock"])
	for t in losses:
		t.morale = maxf(0.0, t.morale - Morale.LOSS_TO_MORALE * float(losses[t]) / t.initial_count())
		t.recent_losses.append(Vector2i(tick, losses[t]))


func _shock(u: BattleUnit, level: int) -> void:
	if u.shock_ticks > 0 and u.shock_level >= level:
		return
	u.morale = maxf(0.0, u.morale - Morale.SHOCK_MORALE_LOSS[level])
	u.shock_level = maxi(u.shock_level if u.shock_ticks > 0 else 0, level)
	u.shock_ticks = Morale.shock_ticks(u.experience)


# --- 8. 제압·사기 -----------------------------------------------------------

func _update_morale() -> void:
	for u in units:
		if not u.is_alive():
			continue
		u.suppression = maxf(0.0, u.suppression - Morale.SUPPRESSION_DECAY)
		var recent := 0
		var kept: Array[Vector2i] = []
		for r in u.recent_losses:
			if tick - r.x < LOSS_SHOCK_WINDOW:
				kept.append(r)
				recent += r.y
		u.recent_losses = kept
		if recent >= ceili(u.initial_count() * LOSS_SHOCK_FRACTION):
			_shock(u, 1)
			u.recent_losses.clear()
		if u.is_suppressed():
			u.morale -= Morale.SUPPRESSED_DRAIN
		if u.shock_ticks > 0:
			u.shock_ticks -= 1
		elif tick - u.last_attacked_tick > Morale.QUIET_TICKS:
			u.morale = minf(_morale_cap(u), u.morale + Morale.RECOVERY_PER_TICK)
		u.morale = clampf(u.morale, 0.0, 100.0)


## 잃은 병력만큼은 회복되지 않는다.
func _morale_cap(u: BattleUnit) -> float:
	var lost := 1.0 - float(u.alive_count()) / u.initial_count()
	return 100.0 - Morale.LOSS_TO_MORALE * lost


# --- 9. 승리 조건 -----------------------------------------------------------

func _check_victory() -> void:
	var fighting := {}
	for u in units:
		var ok: bool = u.is_alive() and u.state() != Morale.State.ROUTED
		fighting[u.side] = fighting.get(u.side, false) or ok
	var standing: Array = fighting.keys().filter(func(s): return fighting[s])
	if fighting.size() > 1 and standing.size() == 1:
		winner = standing[0]
		return
	var capture: Dictionary = victory.get("capture", {})
	for side in capture:
		var all_held := true
		for rect in capture[side]:
			if not holds(side, rect):
				all_held = false
				break
		if all_held:
			winner = side
			return


## 그 진영의 싸울 수 있는 부대가 구역 안에 있고, 적은 없으면 점령.
func holds(side: String, rect: Rect2i) -> bool:
	var mine := false
	for u in units:
		if not u.is_alive() or u.state() == Morale.State.ROUTED:
			continue
		for t in u.tiles():
			if rect.has_point(t):
				if u.side == side:
					mine = true
				else:
					return false
				break
	return mine
