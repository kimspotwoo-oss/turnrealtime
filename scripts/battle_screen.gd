extends Node2D
## 집중전투 화면. 준비기간에 명령을 내리고, 실행기간을 지켜본다.
##
## 마우스
##   왼쪽 클릭 = 선택 (Shift = 추가, 두 번 클릭 = 같은 종류 모두), 빈 땅에서 왼쪽 끌기 = 범위 선택,
##   아군 부대에서 왼쪽 끌기 = 경로 그리기 (적 위에서 놓으면 우선 사격).
##   오른쪽 클릭 = 이동 (Shift = 경유점, Ctrl = 후진), 적 위에서 오른쪽 클릭 = 우선 사격,
##   오른쪽 끌기 = 대형 배치 (선 길이 = 폭, 선에 수직 = 정면).
##   가운데 끌기 = 화면 이동, 휠 = 확대·축소.
## 터치
##   누르기 = 선택, 부대에서 끌기 = 경로, 빈 땅 끌기 = 화면 이동, 두 손가락 = 확대·축소.
##   이동·대형 배치·후진은 오른쪽 칸의 단추로.
## 키보드
##   스페이스 = 실행 / 일시정지, 1~4 = 태세, M 이동, R 후진, F 방향, G 대형 배치, S 정지,
##   Tab = 다음 부대, Ctrl+A = 모두, O = 모든 부대 명령 보기, V = 시야 범위 보기, Enter = 그리기 완료, Esc = 취소, F1 = 전체 보기(시험용).

const STAGE := "res://data/stages/practice.json"
const TILE_PX := 20.0
const SYMBOL_PX := 20.0
## 사격선을 보여 주는 시간 (틱).
const FIRE_LINE_TICKS := 4
const PLAYER_SIDE := "player"
## 실행기간 재생 속도 (게임 초 / 실제 초).
const SPEEDS := [10.0, 30.0, 120.0]
const SIDE_COLORS := {"player": Color(0.2, 0.4, 0.9), "ai": Color(0.85, 0.25, 0.2)}
const TERRAIN_COLORS := {
	"open": Color(0.62, 0.68, 0.45),
	"road": Color(0.55, 0.5, 0.4),
	"forest": Color(0.25, 0.4, 0.22),
	"village": Color(0.6, 0.55, 0.5),
}
const DIFFICULTY_NAMES := {"easy": "쉬움", "normal": "보통", "hard": "어려움"}
const STATE_NAMES := ["안정", "동요", "패닉", "패주"]
const STANCE_NAMES := ["공격", "후퇴", "저지", "무시"]
const FORMATION_NAMES := {"line": "횡대", "column": "종대", "wedge": "쐐기", "dispersed": "분산"}
const HOLD_REASONS := {
	"panic": "패닉에 빠져 움직이지 못함",
	"pace": "공세선에서 다른 부대를 기다리는 중",
	"pinned": "고착됨 (제압이 100 아래로 내려가야 움직임)",
	"melee": "근접전 중이라 앞으로 나가지 못함",
	"blocked": "다른 전차에 길이 막힘",
	"engaged": "교전 중이라 멈춤 (계속 가려면 태세를 '무시'로)",
}
## 보이지 않는 적에게 맞은 방향을 보여 주는 시간 (틱).
const UNSEEN_TICKS := 10
## 이보다 덜 움직이고 떼면 끌기가 아니라 클릭 (칸).
const CLICK_SLOP := 0.6
const DOUBLE_CLICK_MSEC := 350
## 경로를 그릴 때 점을 찍는 간격 (칸).
const PATH_SPACING := 1.0

enum Mode { SELECT, MOVE, REVERSE, FORMATION, FACE, RETREAT_POINT, FIRE_POINT, FIRE_PREDICT, DRAW_LINE, DRAW_OFFENSIVE, DRAW_RETREAT_LINE }

const MODE_HINTS := {
	Mode.SELECT: "오른쪽 클릭: 이동 (Shift 경유점)\n적에 오른쪽 클릭: 다가가서 공격\n오른쪽 끌기: 대형 배치\n부대에서 끌기: 경로 그리기",
	Mode.MOVE: "이동할 곳을 누르세요. Shift+클릭으로 경유점을 이어 찍을 수 있어요.",
	Mode.REVERSE: "후진할 곳을 누르세요. 지금 정면을 유지한 채 절반 속도로 물러납니다.",
	Mode.FORMATION: "세울 자리를 끌어서 그으세요.\n선 길이가 폭이고, 왼쪽에서 오른쪽으로 그으면 위쪽이 정면입니다.",
	Mode.FACE: "바라볼 곳을 누르세요. 이동 중이면 도착한 뒤에 그쪽을 봅니다.",
	Mode.RETREAT_POINT: "후퇴지를 누르세요.",
	Mode.FIRE_POINT: "포격할 지점을 누르세요. 전차와 대전차포는 시선이 닿는 지점만, 쏠 적이 없을 때 쏩니다.",
	Mode.FIRE_PREDICT: "예측 사격할 적 부대를 누르세요.",
	Mode.DRAW_LINE: "전선을 끌어서 한 번에 그으세요.\n또는 점들을 차례로 누르고 오른쪽 클릭이나 Enter로 마치세요.",
	Mode.DRAW_OFFENSIVE: "공세선을 끌어서 그으세요.\n또는 점들을 누르고 오른쪽 클릭이나 Enter로 마치세요.",
	Mode.DRAW_RETREAT_LINE: "후퇴선을 끌어서 그으세요.\n또는 점들을 누르고 오른쪽 클릭이나 Enter로 마치세요.",
}

var battle: Battle
var selected: Array[BattleUnit] = []
var mode := Mode.SELECT
var draft := PackedVector2Array()
var running := false
var speed_index := 0
var show_all := false
## 적 AI 난이도: easy, normal, hard.
var difficulty := "normal"
## 실행기간을 잠시 멈춤.
var paused := false
## 고른 부대의 시야 범위를 노란 테두리로 보여 준다.
var show_vision := true
## 고르지 않은 아군 부대의 명령도 흐리게 보여 준다.
var show_orders := false
## 켜면 누를 때마다 선택에 더하고, 터치에서도 끌어서 범위 선택.
var multi_select := false

var _tick_accum := 0.0
var _drag_start = null
var _panning := false
var _press_tile = null
## 대형 배치 선의 시작점 (오른쪽 끌기 또는 대형 배치 모드).
var _place_start = null
## 경로를 그리는 중인 부대와 지금까지의 점.
var _path_unit: BattleUnit = null
var _path := PackedVector2Array()
## 전선·공세선·후퇴선을 끌어서 긋는 중.
var _free_draw := false
## 전선 한 번 전진·후퇴 단추가 옮기는 거리 (칸).
const LINE_STEP := 5.0
## 전선을 눌러 고를 때 선에서 이만큼(칸) 안이면 누른 것으로 본다.
const LINE_PICK := 0.8
var _ctx_line: Control
var _ctx_line_label: Label
var _ctx_leave: Button
var _ctx_rejoin: Button
var _line_buttons: Array[Button] = []
var _touches := {}
var _touch_used := false
var _last_click_unit: BattleUnit = null
var _last_click_msec := 0
var _reach_key := ""
var _reach := {}
var _multi_button: Button
var _vision_button: Button
var _vision_key := ""
var _vision := {}
## 고른 부대 옆에 뜨는 명령 창.
var _ctx: PanelContainer
var _ctx_title: Label
var _ctx_strength: ProgressBar
var _ctx_strength_label: Label
var _ctx_morale: ProgressBar
var _ctx_morale_label: Label
var _ctx_note: Label
var _ctx_stances: Array[Button] = []
var _ctx_rows: Array[Control] = []
var _ctx_fire: Control
var _difficulty_button: Button
var _orders_button: Button
var _terrain_tex: ImageTexture
var _camera: Camera2D

var _top_label: Label
var _hint_label: Label
var _info_label: Label
var _report_label: Label
## 지난 턴 보고 (턴이 끝날 때 만든다).
var report := ""
## 턴을 시작할 때 아군이 알던 적.
var _known_at_start := {}
var _run_button: Button
var _speed_button: Button
var _groups := {}


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_camera = Camera2D.new()
	add_child(_camera)
	_build_ui()
	load_stage(STAGE)


func load_stage(path: String) -> void:
	battle = StageLoader.load_file(path, {}, -1, difficulty)
	if _difficulty_button != null:
		_difficulty_button.text = "난이도: %s" % DIFFICULTY_NAMES[difficulty]
	selected.clear()
	_set_mode(Mode.SELECT)
	running = false
	report = ""
	_terrain_tex = _make_terrain_texture(battle.map)
	# 오른쪽 명령 칸만큼 지도를 왼쪽으로 비켜 보여 준다.
	_camera.position = Vector2(battle.map.width, battle.map.height) * TILE_PX / 2.0 + Vector2(150, -20)
	_refresh_ui()
	queue_redraw()


# --- 실행기간 ---------------------------------------------------------------

func start_turn() -> void:
	if running or battle.winner != "":
		return
	_set_mode(Mode.SELECT)
	paused = false
	battle.begin_turn()
	_known_at_start.clear()
	for e in battle.known_enemies(PLAYER_SIDE):
		_known_at_start[e.id] = true
	running = true
	_tick_accum = 0.0
	_refresh_ui()


func _process(delta: float) -> void:
	if not running or paused:
		return
	_tick_accum += delta * SPEEDS[speed_index]
	while _tick_accum >= 1.0 and not battle.turn_over():
		battle.step()
		_tick_accum -= 1.0
	if battle.turn_over():
		battle.end_turn()
		running = false
		report = make_report()
		_prune_selection()
	_refresh_ui()
	queue_redraw()


## 난이도는 적 편성도 바꾸므로 전투를 처음부터 다시 연다. 그래서 첫 턴을 시작하기 전에만 바꿀 수 있다.
func set_difficulty(d: String) -> void:
	difficulty = d
	load_stage(STAGE)


func _cycle_difficulty() -> void:
	var all := DefenseAI.DIFFICULTIES
	set_difficulty(all[(all.find(difficulty) + 1) % all.size()])


func _prune_selection() -> void:
	selected = selected.filter(func(u): return u.is_alive())


# --- 입력 ---------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_on_touch(event)
	elif event is InputEventScreenDrag:
		_on_touch_drag(event)
	elif event is InputEventMouseButton:
		if _touches.size() < 2:
			_on_mouse_button(event)
	elif event is InputEventMouseMotion:
		if _touches.size() >= 2:
			return
		if _panning:
			_camera.position -= event.relative / _camera.zoom
			_refresh_ui()
		if _path_unit != null or _free_draw:
			var p := _tile_of(event.position)
			if _path.is_empty() or _path[_path.size() - 1].distance_to(p) >= PATH_SPACING:
				_path.append(p)
		queue_redraw()
	elif event is InputEventKey and event.pressed and not event.echo:
		_on_key(event)


func _on_key(event: InputEventKey) -> void:
	match event.keycode:
		KEY_SPACE:
			if running:
				toggle_pause()
			else:
				start_turn()
		KEY_ENTER, KEY_KP_ENTER:
			finish_draft()
		KEY_ESCAPE:
			if mode == Mode.SELECT and draft.is_empty():
				selected.clear()
			_set_mode(Mode.SELECT)
			_refresh_ui()
		KEY_F1:
			show_all = not show_all
		KEY_O:
			show_orders = not show_orders
		KEY_V:
			show_vision = not show_vision
			_refresh_ui()
		KEY_TAB:
			_select_next(-1 if event.shift_pressed else 1)
		KEY_A:
			if event.ctrl_pressed or event.meta_pressed:
				box_select(Rect2(-1, -1, battle.map.width + 2, battle.map.height + 2))
		KEY_1, KEY_2, KEY_3, KEY_4:
			if _can_order():
				Orders.set_stance(battle, _own_selected(), (event.keycode - KEY_1) as BattleUnit.Stance)
				_refresh_ui()
		KEY_M:
			if _can_order():
				_set_mode(Mode.MOVE)
		KEY_R:
			if _can_order():
				_set_mode(Mode.REVERSE)
		KEY_F:
			if _can_order():
				_set_mode(Mode.FACE)
		KEY_G:
			if _can_order():
				_set_mode(Mode.FORMATION)
		KEY_S:
			if _can_order():
				_each(func(u): Orders.stop(u))
	queue_redraw()


func _can_order() -> bool:
	return not running and battle.winner == "" and not _own_selected().is_empty()


func toggle_pause() -> void:
	if running:
		paused = not paused
		_refresh_ui()


## Tab: 다음 아군 부대를 고르고 화면을 그리로 옮긴다.
func _select_next(step: int) -> void:
	var own: Array[BattleUnit] = []
	for u in battle.units:
		if u.side == PLAYER_SIDE and u.is_alive():
			own.append(u)
	if own.is_empty():
		return
	var i := own.find(selected[0]) if selected.size() > 0 else -1
	var next: BattleUnit = own[posmod(i + step, own.size())]
	selected.clear()
	selected.append(next)
	_camera.position = _px(next.center) + Vector2(150, 0) / _camera.zoom
	_refresh_ui()


func _tile_of(screen_pos: Vector2) -> Vector2:
	return get_canvas_transform().affine_inverse() * screen_pos / TILE_PX - Vector2(0.5, 0.5)


func _zoom_by(factor: float) -> void:
	_camera.zoom = (_camera.zoom * factor).clamp(Vector2(0.4, 0.4), Vector2(3, 3))


# 터치: 한 손가락은 마우스 왼쪽 버튼처럼 오고 (빈 땅을 끌면 화면 이동), 두 손가락은 확대·축소와 화면 이동.
func _on_touch(event: InputEventScreenTouch) -> void:
	_touch_used = true
	if event.pressed:
		_touches[event.index] = event.position
		if _touches.size() >= 2:
			_cancel_drags()
	else:
		_touches.erase(event.index)


func _on_touch_drag(event: InputEventScreenDrag) -> void:
	if _touches.size() < 2 or not _touches.has(event.index):
		_touches[event.index] = event.position
		return
	var other: Vector2 = event.position
	for i in _touches:
		if i != event.index:
			other = _touches[i]
	var before: float = (_touches[event.index] as Vector2).distance_to(other)
	var after := event.position.distance_to(other)
	if before > 1.0 and after > 1.0:
		_zoom_by(after / before)
	_camera.position -= event.relative / _camera.zoom / 2.0
	_touches[event.index] = event.position
	queue_redraw()


func _cancel_drags() -> void:
	_drag_start = null
	_place_start = null
	_path_unit = null
	_path.clear()
	_panning = false
	_press_tile = null
	queue_redraw()


func _on_mouse_button(event: InputEventMouseButton) -> void:
	var p := _tile_of(event.position)
	match event.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			_zoom_by(1.1)
		MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_by(1.0 / 1.1)
		MOUSE_BUTTON_MIDDLE:
			_panning = event.pressed
		MOUSE_BUTTON_RIGHT:
			if event.pressed:
				if draft.size() >= 2:
					finish_draft()
				elif mode != Mode.SELECT:
					_set_mode(Mode.SELECT)
				elif _can_order():
					_place_start = p
			elif _place_start != null:
				var start: Vector2 = _place_start
				_place_start = null
				if start.distance_to(p) < CLICK_SLOP:
					command_at(p, event.shift_pressed, event.ctrl_pressed)
				else:
					place_formation(start, p, event.shift_pressed)
		MOUSE_BUTTON_LEFT:
			if event.pressed:
				_on_left_press(p, event)
			else:
				_on_left_release(p, event)
	queue_redraw()


func _on_left_press(p: Vector2, event: InputEventMouseButton) -> void:
	_press_tile = p
	if mode == Mode.FORMATION:
		_place_start = p
		return
	if mode in [Mode.DRAW_LINE, Mode.DRAW_OFFENSIVE, Mode.DRAW_RETREAT_LINE] and draft.is_empty():
		_free_draw = true
		_path.clear()
		return
	if mode != Mode.SELECT:
		return
	var u := unit_at(p)
	if u != null and u.side == PLAYER_SIDE and not running and battle.winner == "" and not multi_select:
		# 아군 부대에서 끌기 시작하면 경로 그리기.
		_path_unit = u
		_path.clear()
	elif _touch_used and not multi_select:
		_panning = true
	else:
		_drag_start = p


func _on_left_release(p: Vector2, event: InputEventMouseButton) -> void:
	if _press_tile == null:
		return
	var start: Vector2 = _press_tile
	_press_tile = null
	var add: bool = event.shift_pressed
	var short := start.distance_to(p) < CLICK_SLOP
	if mode == Mode.FORMATION:
		_place_start = null
		if not short:
			place_formation(start, p, add)
			_set_mode(Mode.SELECT)
		return
	if _free_draw:
		_free_draw = false
		var drawn := _path.duplicate()
		_path.clear()
		if not short:
			drawn.append(p)
			draft = PackedVector2Array([start])
			drawn.insert(0, start)
			draft.append_array(simplify_path(drawn, 0.7))
			finish_draft()
			return
	if mode != Mode.SELECT:
		click_at(p, add)
		return
	var path_unit := _path_unit
	var path := _path.duplicate()
	var was_panning := _panning
	_path_unit = null
	_path.clear()
	_drag_start = null
	_panning = false
	if short:
		var now := Time.get_ticks_msec()
		var u := unit_at(p)
		if u != null and u == _last_click_unit and now - _last_click_msec < DOUBLE_CLICK_MSEC:
			select_same_type(u)
		else:
			click_at(p, add or multi_select)
		_last_click_unit = u
		_last_click_msec = now
	elif path_unit != null:
		if not selected.has(path_unit):
			selected.clear()
			selected.append(path_unit)
		path.append(p)
		order_path(path, add)
	elif not was_panning:
		box_select(Rect2(start, Vector2.ZERO).expand(p), add or multi_select)


## 오른쪽 클릭 (또는 터치의 명령): 적이면 우선 사격, 땅이면 이동. add = 경유점으로 잇기, reverse = 후진.
func command_at(p: Vector2, add := false, reverse := false) -> void:
	if not _can_order():
		return
	var t := unit_at(p)
	if t != null and t.side != PLAYER_SIDE:
		for u in _own_selected():
			if _has_indirect(u):
				# 박격포는 다가가지 않고 그 자리에서 예측 사격한다.
				Orders.focus(u, t)
				Orders.fire_predicted(u, t)
			else:
				Orders.attack(u, t)
	else:
		_move_group(p, add, reverse)
	_refresh_ui()
	queue_redraw()


## 끌어서 대형 배치: a→b 선 위에 고른 부대를 나란히 세운다.
func place_formation(a: Vector2, b: Vector2, add := false) -> void:
	if not _can_order():
		return
	Orders.place_on_segment(_own_selected(), a, b, add)
	_refresh_ui()
	queue_redraw()


## 그린 경로대로 이동. 끝이 적 위면 그 적을 우선 사격한다.
func order_path(points: PackedVector2Array, add := false) -> void:
	if not _can_order() or points.is_empty():
		return
	var last := points[points.size() - 1]
	var t := unit_at(last)
	if t != null and t.side != PLAYER_SIDE:
		for u in _own_selected():
			Orders.focus(u, t)
		points.remove_at(points.size() - 1)
	if points.is_empty():
		return
	# simplify_path 는 첫 점을 뺀 나머지를 돌려주므로 첫 점을 한 번 더 넣는다.
	points.insert(0, points[0])
	var stops := simplify_path(points)
	for i in stops.size():
		_move_group(stops[i], add or i > 0)
	_refresh_ui()
	queue_redraw()


## 끌어 그린 점들에서 꺾이는 곳만 남긴다 (Douglas–Peucker). 첫 점은 출발점으로 보고 뺀다.
static func simplify_path(points: PackedVector2Array, tolerance := 1.0) -> PackedVector2Array:
	if points.size() < 2:
		return PackedVector2Array()
	var a := points[0]
	var b := points[points.size() - 1]
	var worst := 0
	var worst_d := 0.0
	for i in range(1, points.size() - 1):
		var d := (points[i] - Geometry2D.get_closest_point_to_segment(points[i], a, b)).length()
		if d > worst_d:
			worst_d = d
			worst = i
	if worst_d <= tolerance:
		return PackedVector2Array([b])
	var out := simplify_path(points.slice(0, worst + 1), tolerance)
	out.append_array(simplify_path(points.slice(worst, points.size()), tolerance))
	return out


## p 가까이를 지나는 아군 전선 (전선 자체나 공세선).
func line_at(p: Vector2) -> FrontLine:
	var best: FrontLine = null
	var best_d := LINE_PICK
	for line in battle.front_lines:
		if line.side != PLAYER_SIDE:
			continue
		for pts in [line.points, line.offensive]:
			for i in range(1, pts.size()):
				var d: float = Geometry2D.get_closest_point_to_segment(p, pts[i - 1], pts[i]).distance_to(p)
				if d < best_d:
					best_d = d
					best = line
	return best


## 전선을 누르면 그 전선에 선 부대를 모두 고른다.
func select_line(line: FrontLine, add := false) -> void:
	if not add:
		selected.clear()
	for id in line.units:
		var u := battle.unit_by_id(id)
		if u != null and u.is_alive() and not selected.has(u):
			selected.append(u)
	_refresh_ui()
	queue_redraw()


## 고른 부대가 모두 한 전선에 서 있으면 그 전선.
func selected_line() -> FrontLine:
	return Orders.common_line(battle, _own_selected())


func _line_order(f: Callable) -> void:
	var line := selected_line()
	if line != null and _can_order():
		f.call(line)
	_refresh_ui()
	queue_redraw()


func select_same_type(u: BattleUnit) -> void:
	selected.clear()
	for o in battle.units:
		if o.side == u.side and o.is_alive() and o.type == u.type and is_shown(o):
			selected.append(o)
	_refresh_ui()
	queue_redraw()


func _mouse_tile() -> Vector2:
	return get_global_mouse_position() / TILE_PX - Vector2(0.5, 0.5)


## 지도 한 점을 눌렀을 때. 지금 모드에 따라 고르거나 명령한다.
func click_at(p: Vector2, add := false) -> void:
	if running:
		return
	match mode:
		Mode.SELECT:
			var u := unit_at(p)
			if u == null:
				var picked := line_at(p)
				if picked != null:
					select_line(picked, add)
					return
			if not add:
				selected.clear()
			if u != null and not selected.has(u):
				selected.append(u)
			elif u != null and add:
				selected.erase(u)
		Mode.MOVE, Mode.REVERSE:
			var t := unit_at(p)
			if mode == Mode.MOVE and t != null and t.side != PLAYER_SIDE:
				command_at(p)
			else:
				_move_group(p, add, mode == Mode.REVERSE)
			if not add:
				_set_mode(Mode.SELECT)
		Mode.FORMATION:
			pass
		Mode.FACE:
			for u in _own_selected():
				Orders.face(u, p)
			_set_mode(Mode.SELECT)
		Mode.RETREAT_POINT:
			for u in _own_selected():
				Orders.set_retreat_point(u, p)
			_set_mode(Mode.SELECT)
		Mode.FIRE_POINT:
			for u in _own_selected():
				if _can_point_fire(u):
					Orders.fire_at_point(u, p)
			_set_mode(Mode.SELECT)
		Mode.FIRE_PREDICT:
			var t := unit_at(p)
			if t != null and t.side != PLAYER_SIDE:
				for u in _own_selected():
					if _has_indirect(u):
						Orders.fire_predicted(u, t)
				_set_mode(Mode.SELECT)
		Mode.DRAW_LINE, Mode.DRAW_OFFENSIVE, Mode.DRAW_RETREAT_LINE:
			draft.append(p)
	_refresh_ui()
	queue_redraw()


func box_select(rect: Rect2, add := false) -> void:
	if not add:
		selected.clear()
	for u in battle.units:
		if u.side == PLAYER_SIDE and u.is_alive() and rect.has_point(u.center) and not selected.has(u):
			selected.append(u)
	_refresh_ui()
	queue_redraw()


## 여럿을 함께 옮기면 지금의 배치 모양을 유지한 채 옮긴다.
## waypoint 이면 지금 명령의 마지막 목적지 다음에 이어 붙인다.
func _move_group(p: Vector2, waypoint := false, reverse := false) -> void:
	var units := _own_selected()
	if units.is_empty():
		return
	var starts := {}
	var c := Vector2.ZERO
	for u in units:
		var dest = Orders.final_destination(u) if waypoint else null
		starts[u] = dest if dest != null else u.center
		c += starts[u]
	c /= units.size()
	for u in units:
		var to: Vector2 = p + (starts[u] - c)
		if waypoint:
			Orders.add_waypoint(u, to)
		elif reverse:
			Orders.move_reverse(u, to)
		else:
			Orders.move(u, to)


func finish_draft() -> void:
	if draft.size() < 2:
		return
	var units := _own_selected()
	match mode:
		Mode.DRAW_LINE:
			Orders.draw_front_line(battle, PLAYER_SIDE, units, draft)
		Mode.DRAW_OFFENSIVE:
			var line := Orders.common_line(battle, units)
			if line != null:
				Orders.set_offensive(battle, line, draft)
		Mode.DRAW_RETREAT_LINE:
			var line := Orders.common_line(battle, units)
			if line != null:
				Orders.set_retreat_line(battle, line, draft)
	_set_mode(Mode.SELECT)
	_refresh_ui()
	queue_redraw()


func unit_at(p: Vector2) -> BattleUnit:
	var tile := Vector2i(p.round())
	var best: BattleUnit = null
	for u in battle.units:
		if not u.is_alive() or not is_shown(u):
			continue
		if u.tiles().has(tile) or u.center.distance_to(p) < 0.8:
			if best == null or u.side == PLAYER_SIDE:
				best = u
	return best


## 플레이어에게 보이는 부대: 아군과, 아군이 지금 아는 적.
func is_shown(u: BattleUnit) -> bool:
	return show_all or u.side == PLAYER_SIDE or battle.side_knows(PLAYER_SIDE, u)


func _own_selected() -> Array[BattleUnit]:
	var out: Array[BattleUnit] = []
	for u in selected:
		if u.side == PLAYER_SIDE and u.is_alive():
			out.append(u)
	return out


## 지점 사격을 할 수 있는가: 곡사 무기이거나 고폭탄이 있는 직사포.
static func _can_point_fire(u: BattleUnit) -> bool:
	for w in u.type.weapons:
		if w.indirect or w.area != null:
			return true
	return false


static func _has_indirect(u: BattleUnit) -> bool:
	for w in u.type.weapons:
		if w.indirect:
			return true
	return false


func _set_mode(m: Mode) -> void:
	mode = m
	draft = PackedVector2Array()
	if _hint_label != null:
		_hint_label.text = MODE_HINTS[m]
	queue_redraw()


# --- 화면 ---------------------------------------------------------------

func _make_terrain_texture(map: BattleMap) -> ImageTexture:
	var img := Image.create(map.width, map.height, false, Image.FORMAT_RGBA8)
	for y in map.height:
		for x in map.width:
			img.set_pixel(x, y, TERRAIN_COLORS[map.terrain_at(Vector2i(x, y))])
	return ImageTexture.create_from_image(img)


func _px(p: Vector2) -> Vector2:
	return (p + Vector2(0.5, 0.5)) * TILE_PX


func _draw() -> void:
	if battle == null:
		return
	draw_texture_rect(_terrain_tex, Rect2(Vector2.ZERO, Vector2(battle.map.width, battle.map.height) * TILE_PX), false)
	_draw_objectives()
	for line in battle.front_lines:
		if line.side != PLAYER_SIDE and not show_all:
			continue
		var color: Color = SIDE_COLORS.get(line.side, Color.WHITE)
		if not _line_in_use(line):
			# 부대가 모두 개별 명령으로 떠난 전선은 흐리게.
			color.a = 0.3
		var picked := line.side == PLAYER_SIDE and line == selected_line()
		if picked:
			_draw_line_points(line.points, Color.WHITE, 7.0)
		_draw_line_points(line.points, color, 3.0)
		_draw_line_points(line.offensive, color.lightened(0.4), 3.0 if picked else 2.0, true)
		_draw_line_points(line.retreat, color.darkened(0.3), 2.0, true)
		if line.side == PLAYER_SIDE:
			_draw_line_info(line, color, picked)
	if not running:
		_draw_reach()
	for u in battle.units:
		if u.is_alive() and is_shown(u):
			_draw_unit(u)
	for u in battle.units:
		if u.is_alive() and is_shown(u):
			_draw_fire(u)
	for u in battle.units:
		if u.is_alive() and u.side == PLAYER_SIDE:
			_draw_unseen(u)
	if show_vision:
		_draw_vision()
	# 여럿을 고르면 원이 겹쳐 읽을 수 없으므로 하나를 골랐을 때만 그린다.
	if selected.size() == 1 and selected[0].is_alive() and is_shown(selected[0]):
		_draw_ranges(selected[0])
	if show_orders:
		for u in battle.units:
			if u.is_alive() and u.side == PLAYER_SIDE and not selected.has(u):
				_draw_orders_faint(u)
	for u in _own_selected():
		_draw_orders(u)
	_draw_drags()
	for s in battle.shells:
		draw_circle(_px(s["point"]), 3.0, Color.YELLOW)
	if not draft.is_empty():
		var pts := draft.duplicate()
		pts.append(_mouse_tile())
		_draw_line_points(pts, Color.WHITE, 2.0)
	if _drag_start != null:
		var r := Rect2(_px(_drag_start), Vector2.ZERO).expand(_px(_mouse_tile()))
		draw_rect(r, Color(1, 1, 1, 0.8), false, 1.5)
	if _ctx != null:
		_refresh_context()


func _draw_unit(u: BattleUnit) -> void:
	var color: Color = SIDE_COLORS.get(u.side, Color.WHITE)
	match u.state():
		Morale.State.SHAKEN:
			color = color.lightened(0.3)
		Morale.State.PANIC, Morale.State.ROUTED:
			color = color.lightened(0.6)
	var tile_color := color
	tile_color.a = 0.45
	var sel := selected.has(u)
	for t in u.tiles():
		var r := Rect2(t.x * TILE_PX + 1, t.y * TILE_PX + 1, TILE_PX - 2, TILE_PX - 2)
		draw_rect(r, tile_color)
		if sel:
			draw_rect(r, Color.WHITE, false, 1.5)
	var c := _px(u.center)
	draw_line(c, c + u.facing * TILE_PX * 1.2, Color.BLACK, 2.0)
	UnitSymbol.draw(self, c, SYMBOL_PX, u.type.symbol_icon, u.type.symbol_echelon, u.side != PLAYER_SIDE, color, Color.WHITE if sel else Color.BLACK)
	_draw_strength(u, c)
	if u.side == PLAYER_SIDE or show_all:
		if u.hold_reason == "pinned":
			_draw_label(c + Vector2(SYMBOL_PX * 0.7, -SYMBOL_PX * 0.2), "고착", Color(1.0, 0.3, 0.2))
		elif u.is_suppressed():
			_draw_label(c + Vector2(SYMBOL_PX * 0.7, -SYMBOL_PX * 0.2), "제압", Color(1.0, 0.85, 0.2))
	if u.state() != Morale.State.STEADY:
		var badge := Color(1.0, 0.85, 0.2) if u.state() == Morale.State.SHAKEN else Color(1.0, 0.3, 0.2)
		_draw_label(c + Vector2(-SYMBOL_PX * 0.6, SYMBOL_PX * 1.45), STATE_NAMES[u.state()], badge)


## 글자 뒤에 검은 테두리를 둘러 지형 위에서도 읽히게 한다.
func _draw_label(p: Vector2, text: String, color: Color, size := 13) -> void:
	var font := ThemeDB.fallback_font
	draw_string_outline(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, Color(0, 0, 0, 0.8))
	draw_string(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


## 점령 목표 구역. 플레이어가 점령해야 하면 흰 테두리, 지켜야 하면 파란 테두리.
func _draw_objectives() -> void:
	var capture: Dictionary = battle.victory.get("capture", {})
	for side in capture:
		var color := Color.WHITE if side == PLAYER_SIDE else SIDE_COLORS[PLAYER_SIDE]
		for rect in capture[side]:
			var r := Rect2(Vector2(rect.position) * TILE_PX, Vector2(rect.size) * TILE_PX)
			var held := battle.holds(side, rect)
			draw_rect(r, Color(color, 0.9), false, 3.0 if held else 2.0)
			_draw_label(r.position + Vector2(4, 16), "점령 목표%s" % (" (점령함)" if held else ""), color)


func _line_in_use(line: FrontLine) -> bool:
	for uid in line.units:
		var u := battle.unit_by_id(uid)
		if u != null and u.is_alive() and not u.individual:
			return true
	return not line.reserves.is_empty()


## 보이지 않는 적에게 맞으면 그 방향으로 짧은 빨간 점선과 "?" 를 그린다. 거리는 알려 주지 않는다.
func _draw_unseen(u: BattleUnit) -> void:
	var age := battle.tick - u.unseen_tick
	if u.unseen_from == null or age > UNSEEN_TICKS:
		return
	var dir: Vector2 = (u.unseen_from - u.center).normalized()
	var color := Color(1.0, 0.2, 0.2, 1.0 - float(age) / (UNSEEN_TICKS + 1))
	var from := _px(u.center) + dir * TILE_PX * 1.5
	var to := from + dir * TILE_PX * 4.0
	draw_dashed_line(from, to, color, 2.5, 6.0)
	_draw_label(to + Vector2(-4, 5), "?", color, 18)


## 고른 아군의 명령: 찾은 길을 따라 이동 목표와 경유점까지 점선, 후퇴지, 포격 지점.
## 기호 아래의 전력 막대. 전차·포는 한 대(문)에 한 칸, 보병은 남은 비율만큼 채운다.
## 초록(2/3 넘게) → 노랑 → 빨강(1/3 아래). 아군은 남은 수도 숫자로 적는다.
func _draw_strength(u: BattleUnit, c: Vector2) -> void:
	var kind := strength_kind(u)
	var alive := u.alive_count(kind)
	var total := maxi(u.initial_count(kind), 1)
	var frac := float(alive) / total
	var color := Color(0.25, 0.85, 0.3) if frac > 0.66 else (Color(1.0, 0.8, 0.2) if frac > 0.33 else Color(1.0, 0.3, 0.2))
	var w := SYMBOL_PX * 1.5
	var h := 5.0
	var o := c + Vector2(-w / 2.0, SYMBOL_PX * 0.62)
	draw_rect(Rect2(o - Vector2(1, 1), Vector2(w + 2, h + 2)), Color(0, 0, 0, 0.85))
	if total <= 6:
		var pip := w / total
		for i in total:
			if i < alive:
				draw_rect(Rect2(o + Vector2(i * pip + 0.5, 0), Vector2(pip - 1.0, h)), color)
	else:
		draw_rect(Rect2(o, Vector2(w * frac, h)), color)
	if u.side == PLAYER_SIDE or show_all:
		_draw_label(o + Vector2(w + 3, h + 3), str(alive), Color.WHITE, 11)


## 전력으로 세는 것: 전차 부대는 전차, 나머지는 사람.
static func strength_kind(u: BattleUnit) -> String:
	return "vehicle" if u.type.is_vehicle() else "man"


## 부대 하나만 골랐을 때 그 부대가 지금 볼 수 있는 칸들의 테두리 (노랑).
## 숲·마을 칸은 더 가까워야 보이고, 숲·마을 너머는 가려진다.
func _draw_vision() -> void:
	if selected.size() != 1 or not selected[0].is_alive() or not is_shown(selected[0]):
		return
	var u := selected[0]
	var key := "%s %s" % [u.id, u.center.round()]
	if key != _vision_key:
		_vision_key = key
		_vision = battle.visible_tiles(u)
	var color := Color(1.0, 0.9, 0.3, 0.8)
	var top := Vector2i(0, battle.map.height)
	for t in _vision:
		var o := Vector2(t) * TILE_PX
		if not _vision.has(t + Vector2i.UP):
			draw_line(o, o + Vector2(TILE_PX, 0), color, 1.5)
		if not _vision.has(t + Vector2i.DOWN):
			draw_line(o + Vector2(0, TILE_PX), o + Vector2(TILE_PX, TILE_PX), color, 1.5)
		if not _vision.has(t + Vector2i.LEFT):
			draw_line(o, o + Vector2(0, TILE_PX), color, 1.5)
		if not _vision.has(t + Vector2i.RIGHT):
			draw_line(o + Vector2(TILE_PX, 0), o + Vector2(TILE_PX, TILE_PX), color, 1.5)
		if t.x == roundi(u.center.x) and t.y < top.y:
			top = t
	if not _vision.is_empty():
		_draw_label(Vector2(top) * TILE_PX + Vector2(-34, 16), "시야 %dm" % roundi(u.type.sight_tiles * BattleMap.TILE_METERS), color, 13)


## 전선 이름표와, 공세선이 있으면 전선에서 공세선으로 가는 화살표.
func _draw_line_info(line: FrontLine, color: Color, picked: bool) -> void:
	if line.points.size() < 2:
		return
	var text := "전선 · %s · %d부대" % [STANCE_NAMES[line.stance], line.units.size()]
	if not line.reserves.is_empty():
		text += " · 예비 %d" % line.reserves.size()
	if not line.offensive.is_empty():
		text += " · 전진 중"
	# 부대 기호와 전력 막대를 가리지 않게 선 아래에 적는다.
	var at := _px(line.points[0]) + Vector2(-6, 36)
	_draw_label(at, text, Color.WHITE if picked else color.lightened(0.6), 13)
	if line.offensive.is_empty():
		return
	var arrow := Color(1, 1, 1, 0.8 if picked else 0.45)
	for f in [0.1, 0.5, 0.9]:
		var a := _px(FrontLine.point_at(line.points, f))
		var b := _px(FrontLine.point_at(line.offensive, f))
		if a.distance_to(b) < 12.0:
			continue
		var dir := (b - a).normalized()
		draw_line(a, b, arrow, 2.0)
		draw_line(b, b - dir.rotated(0.5) * 9.0, arrow, 2.0)
		draw_line(b, b - dir.rotated(-0.5) * 9.0, arrow, 2.0)


## 고르지 않은 부대의 이동 명령을 흐리게 (곧은 선으로만).
func _draw_orders_faint(u: BattleUnit) -> void:
	if u.move_target == null:
		return
	var color := Color(1, 1, 1, 0.45)
	var from := u.center
	var stops: Array[Vector2] = [u.move_target]
	stops.append_array(u.waypoints)
	for stop in stops:
		draw_dashed_line(_px(from), _px(stop), color, 1.0, 4.0)
		from = stop
	draw_circle(_px(from), 2.5, color)


## 부대 하나만 골랐을 때, 이번 턴에 닿을 수 있는 범위. 사거리 원과 헷갈리지 않게 옅게 칠한다.
func _draw_reach() -> void:
	var own := _own_selected()
	if own.size() != 1 or selected.size() != 1:
		return
	var u := own[0]
	var reverse := mode == Mode.REVERSE or u.reverse_move
	var key := "%s %s %s %d" % [u.id, u.center.round(), reverse, battle.turn]
	if key != _reach_key:
		_reach_key = key
		var base: float = u.type.speed["vehicle"] if u.type.is_vehicle() else u.type.speed["foot"]
		var budget := base * battle.turn_seconds / 60.0 * (Battle.REVERSE_SPEED if reverse else 1.0)
		_reach = battle.map.reachable(u.center, budget, u.type.is_vehicle(), Battle.road_factor(u))
	var color := Color(1, 1, 1, 0.7)
	var top := Vector2i(0, battle.map.height)
	for t in _reach:
		var o := Vector2(t) * TILE_PX
		draw_rect(Rect2(o, Vector2(TILE_PX, TILE_PX)), Color(1, 1, 1, 0.22))
		if t.y < top.y:
			top = t
		if not _reach.has(t + Vector2i.UP):
			draw_line(o, o + Vector2(TILE_PX, 0), color, 1.5)
		if not _reach.has(t + Vector2i.DOWN):
			draw_line(o + Vector2(0, TILE_PX), o + Vector2(TILE_PX, TILE_PX), color, 1.5)
		if not _reach.has(t + Vector2i.LEFT):
			draw_line(o, o + Vector2(0, TILE_PX), color, 1.5)
		if not _reach.has(t + Vector2i.RIGHT):
			draw_line(o + Vector2(TILE_PX, 0), o + Vector2(TILE_PX, TILE_PX), color, 1.5)
	if not _reach.is_empty():
		_draw_label(Vector2(top) * TILE_PX + Vector2(-30, -6), "이번 턴 이동 범위", Color.WHITE)


## 끌고 있는 것의 미리 보기: 대형 배치 선과 그리는 경로.
func _draw_drags() -> void:
	var m := _mouse_tile()
	if _place_start != null and (_place_start as Vector2).distance_to(m) >= CLICK_SLOP:
		var a: Vector2 = _place_start
		var n := _own_selected().size()
		var front := (m - a).normalized().rotated(-PI / 2.0)
		draw_line(_px(a), _px(m), Color.WHITE, 2.0)
		for i in n:
			var slot := a.lerp(m, (i + 0.5) / n)
			draw_circle(_px(slot), 4.0, Color.WHITE)
			draw_line(_px(slot), _px(slot + front * 1.5), Color.WHITE, 2.0)
		_draw_label(_px(m) + Vector2(8, -8), "폭 %d칸" % roundi(a.distance_to(m) / maxi(n, 1)), Color.WHITE)
	if _free_draw and _press_tile != null and not _path.is_empty():
		var free := PackedVector2Array([_press_tile])
		free.append_array(_path)
		free.append(m)
		_draw_line_points(free, Color.WHITE, 2.0)
	if _path_unit != null and not _path.is_empty():
		var pts := PackedVector2Array([_path_unit.center])
		pts.append_array(_path)
		pts.append(m)
		_draw_line_points(pts, Color.WHITE, 2.0)


func _draw_orders(u: BattleUnit) -> void:
	var focus := battle.unit_by_id(u.focus_target) if u.focus_target != "" else null
	if focus != null and focus.is_alive() and is_shown(focus):
		var fc := _px(focus.center)
		draw_dashed_line(_px(u.center), fc, Color(1.0, 0.25, 0.2), 1.5, 5.0)
		draw_arc(fc, TILE_PX * 0.9, 0.0, TAU, 20, Color(1.0, 0.25, 0.2), 2.0)
		draw_line(fc - Vector2(TILE_PX * 1.2, 0), fc + Vector2(TILE_PX * 1.2, 0), Color(1.0, 0.25, 0.2), 1.5)
		draw_line(fc - Vector2(0, TILE_PX * 1.2), fc + Vector2(0, TILE_PX * 1.2), Color(1.0, 0.25, 0.2), 1.5)
	if u.move_target != null:
		var stops: Array[Vector2] = [u.move_target]
		stops.append_array(u.waypoints)
		var from := u.center
		for stop in stops:
			var pts := PackedVector2Array([from])
			pts.append_array(battle.map.find_path(from, stop, u.type.is_vehicle(), Battle.road_factor(u)))
			for i in range(1, pts.size()):
				draw_dashed_line(_px(pts[i - 1]), _px(pts[i]), Color.WHITE, 1.5, 6.0)
			draw_circle(_px(stop), 3.0, Color.WHITE)
			from = stop
	var rp := _px(u.retreat_point)
	draw_line(rp - Vector2(4, 4), rp + Vector2(4, 4), Color.ORANGE, 2.0)
	draw_line(rp - Vector2(4, -4), rp + Vector2(4, -4), Color.ORANGE, 2.0)
	match u.fire_order.get("mode", ""):
		"point":
			draw_arc(_px(u.fire_order["point"]), TILE_PX * 1.5, 0.0, TAU, 24, Color.ORANGE_RED, 2.0)
		"predict":
			var t := battle.unit_by_id(u.fire_order["target"])
			if t != null and t.is_alive():
				draw_arc(_px(t.center), TILE_PX * 1.5, 0.0, TAU, 24, Color.ORANGE_RED, 2.0)
				draw_dashed_line(_px(t.center), _px(t.center + t.velocity * 20.0), Color.ORANGE_RED, 1.5, 4.0)


## 고른 부대의 무기별 사거리 원. 같은 사거리는 한 번만, 칸 하나 남짓한 근접 무기는 뺀다.
func _draw_ranges(u: BattleUnit) -> void:
	var color: Color = SIDE_COLORS.get(u.side, Color.WHITE).darkened(0.1)
	var drawn := {}
	# 글자는 원 위에서 지도 가운데 쪽에 둔다 (원이 지도 밖으로 나가도 읽히게).
	var inward := (Vector2(battle.map.width, battle.map.height) / 2.0 - u.center).normalized()
	if inward.is_zero_approx():
		inward = Vector2.UP
	for w in u.type.weapons:
		if w.range_tiles < 2.0 or drawn.has(w.range_tiles):
			continue
		drawn[w.range_tiles] = true
		var r := (w.range_tiles + 0.5) * TILE_PX
		draw_arc(_px(u.center), r, 0.0, TAU, 96, color, 2.0)
		var at := _px(u.center) + inward * minf(r, _inside_distance(u.center, inward) * TILE_PX)
		_draw_label(at + Vector2(-30, 0), "%s %dm" % [w.name, roundi(w.range_tiles * BattleMap.TILE_METERS)], color.lightened(0.5), 15)
		if w.min_range_tiles > 0.0:
			draw_arc(_px(u.center), w.min_range_tiles * TILE_PX, 0.0, TAU, 48, color.darkened(0.3), 1.0)


## p 에서 dir 쪽으로 지도 끝까지의 거리 (칸).
func _inside_distance(p: Vector2, dir: Vector2) -> float:
	var best := INF
	if dir.x > 0.001:
		best = minf(best, (battle.map.width - 2 - p.x) / dir.x)
	elif dir.x < -0.001:
		best = minf(best, (1 - p.x) / dir.x)
	if dir.y > 0.001:
		best = minf(best, (battle.map.height - 2 - p.y) / dir.y)
	elif dir.y < -0.001:
		best = minf(best, (1 - p.y) / dir.y)
	return maxf(0.0, best)


## 최근에 쏜 사격을 쏜 부대에서 목표로 선을 긋는다. 오래될수록 흐려진다.
## 아군 사격은 노란색, 적 사격은 주황색이다.
func _draw_fire(u: BattleUnit) -> void:
	var age := battle.tick - u.last_fire_tick
	if age > FIRE_LINE_TICKS:
		return
	var color := Color(1.0, 0.9, 0.2) if u.side == PLAYER_SIDE else Color(1.0, 0.45, 0.1)
	color.a = 1.0 - float(age) / (FIRE_LINE_TICKS + 1)
	var to = null
	var t := battle.unit_by_id(u.last_target)
	if t != null and t.is_alive() and is_shown(t):
		to = _px(t.center)
	elif u.last_fire_point != null:
		to = _px(u.last_fire_point)
	if to == null:
		return
	var from := _px(u.center)
	draw_line(from, to, color, 2.0)
	var dir: Vector2 = (to - from).normalized()
	draw_line(to, to - dir.rotated(0.4) * 9.0, color, 2.0)
	draw_line(to, to - dir.rotated(-0.4) * 9.0, color, 2.0)


func _draw_line_points(points: PackedVector2Array, color: Color, width: float, dashed := false) -> void:
	for i in range(1, points.size()):
		if dashed:
			draw_dashed_line(_px(points[i - 1]), _px(points[i]), color, width, 8.0)
		else:
			draw_line(_px(points[i - 1]), _px(points[i]), color, width)


# --- 버튼과 정보 ----------------------------------------------------------

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var top := HBoxContainer.new()
	top.position = Vector2(8, 8)
	top.add_theme_constant_override("separation", 8)
	layer.add_child(top)
	_run_button = _button(top, "실행 ▶", func(): toggle_pause() if running else start_turn())
	_speed_button = _button(top, "속도 ×1", _cycle_speed)
	_button(top, "처음부터", func(): load_stage(STAGE))
	_difficulty_button = _button(top, "난이도: %s" % DIFFICULTY_NAMES[difficulty], _cycle_difficulty)
	_multi_button = _button(top, "여러 개 선택", func(): multi_select = not multi_select; _refresh_ui())
	_multi_button.toggle_mode = true
	_orders_button = _button(top, "명령 모두 보기", func(): show_orders = not show_orders; _refresh_ui(); queue_redraw())
	_orders_button.toggle_mode = true
	_vision_button = _button(top, "시야 보기", func(): show_vision = not show_vision; _refresh_ui(); queue_redraw())
	_vision_button.toggle_mode = true
	_build_context(layer)
	_top_label = Label.new()
	top.add_child(_top_label)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	panel.offset_left = -300
	layer.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	_hint_label = Label.new()
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_hint_label)
	_info_label = Label.new()
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_info_label)
	_report_label = Label.new()
	_report_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_report_label.add_theme_font_size_override("font_size", 13)
	# 보고가 길어도 아래 단추가 화면 밖으로 밀리지 않게 한다.
	_report_label.max_lines_visible = 8
	_report_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(_report_label)

	var stance := _group(box, "stance", "태세")
	for i in STANCE_NAMES.size():
		_button(stance, STANCE_NAMES[i], func(): Orders.set_stance(battle, _own_selected(), i as BattleUnit.Stance); _refresh_ui())
	var formation := _group(box, "formation", "대형")
	for kind in FORMATION_NAMES:
		_button(formation, FORMATION_NAMES[kind], func(): _each(func(u): Orders.set_formation(u, kind)))
	var width := _group(box, "width", "폭")
	_button(width, "좁게 −", func(): _each(func(u): Orders.set_formation(u, u.formation, u.tile_count - 1)))
	_button(width, "넓게 +", func(): _each(func(u): Orders.set_formation(u, u.formation, u.tile_count + 1)))
	var order := _group(box, "order", "명령")
	_button(order, "이동", func(): _set_mode(Mode.MOVE))
	_button(order, "후진", func(): _set_mode(Mode.REVERSE))
	_button(order, "대형 배치", func(): _set_mode(Mode.FORMATION))
	_button(order, "정지", func(): _each(func(u): Orders.stop(u)))
	var order2 := _group(box, "order2", "")
	_button(order2, "방향", func(): _set_mode(Mode.FACE))
	_button(order2, "후퇴지", func(): _set_mode(Mode.RETREAT_POINT))
	_button(order2, "우선 사격 해제", func(): _each(func(u): Orders.clear_focus(u)))
	var fire := _group(box, "fire", "포격")
	_button(fire, "지점", func(): _set_mode(Mode.FIRE_POINT))
	_button(fire, "예측", func(): _set_mode(Mode.FIRE_PREDICT))
	_button(fire, "해제", func(): _each(func(u): Orders.clear_fire(u)))
	var line := _group(box, "line", "전선")
	_button(line, "전선 긋기", func(): _set_mode(Mode.DRAW_LINE))
	_button(line, "공세선", func(): _set_mode(Mode.DRAW_OFFENSIVE))
	_button(line, "후퇴선", func(): _set_mode(Mode.DRAW_RETREAT_LINE))
	var line2 := _group(box, "line2", "")
	_line_buttons.append(_button(line2, "전진 +5", func(): _line_order(func(l): Orders.advance_line(battle, l, LINE_STEP))))
	_line_buttons.append(_button(line2, "후퇴 −5", func(): _line_order(func(l): Orders.advance_line(battle, l, -LINE_STEP))))
	_line_buttons.append(_button(line2, "전진 취소", func(): _line_order(func(l): Orders.cancel_advance(battle, l))))
	var line3 := _group(box, "line3", "")
	_button(line3, "예비대로", _to_reserve)
	_button(line3, "전선에서 빼기", func(): Orders.leave_line(battle, _own_selected()); _refresh_ui(); queue_redraw())
	_button(line3, "전선 복귀", func(): Orders.rejoin_line(battle, _own_selected()); _refresh_ui(); queue_redraw())
	line2 = _group(box, "line4", "")
	_button(line2, "완료", finish_draft)
	_button(line2, "취소", func(): _set_mode(Mode.SELECT))


# --- 부대 옆 명령 창 ---------------------------------------------------------
# 고른 부대 바로 옆에 상태(전력·사기)와 자주 쓰는 명령을 띄운다. 오른쪽 칸은 그대로 둔다.

func _build_context(layer: CanvasLayer) -> void:
	_ctx = PanelContainer.new()
	_ctx.visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.11, 0.13, 0.96)
	style.border_color = Color(1, 1, 1, 0.5)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(7)
	_ctx.add_theme_stylebox_override("panel", style)
	layer.add_child(_ctx)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	_ctx.add_child(box)
	_ctx_title = Label.new()
	_ctx_title.add_theme_font_size_override("font_size", 14)
	box.add_child(_ctx_title)
	var bars := GridContainer.new()
	bars.columns = 3
	bars.add_theme_constant_override("h_separation", 6)
	box.add_child(bars)
	_ctx_strength = _ctx_bar(bars, "전력")
	_ctx_strength_label = _ctx_small(bars)
	_ctx_morale = _ctx_bar(bars, "사기")
	_ctx_morale_label = _ctx_small(bars)
	_ctx_note = Label.new()
	_ctx_note.add_theme_font_size_override("font_size", 12)
	_ctx_note.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	box.add_child(_ctx_note)
	var stance := HBoxContainer.new()
	box.add_child(stance)
	for i in STANCE_NAMES.size():
		var sb := _ctx_button(stance, STANCE_NAMES[i], func(): Orders.set_stance(battle, _own_selected(), i as BattleUnit.Stance); _refresh_ui())
		sb.toggle_mode = true
		_ctx_stances.append(sb)
	var order := HBoxContainer.new()
	box.add_child(order)
	_ctx_button(order, "이동", func(): _set_mode(Mode.MOVE))
	_ctx_button(order, "후진", func(): _set_mode(Mode.REVERSE))
	_ctx_button(order, "방향", func(): _set_mode(Mode.FACE))
	_ctx_button(order, "정지", func(): _each(func(u): Orders.stop(u)))
	var order2 := HBoxContainer.new()
	box.add_child(order2)
	_ctx_button(order2, "대형 배치", func(): _set_mode(Mode.FORMATION))
	_ctx_button(order2, "후퇴지", func(): _set_mode(Mode.RETREAT_POINT))
	_ctx_button(order2, "예비대로", _to_reserve)
	var fire := HBoxContainer.new()
	box.add_child(fire)
	_ctx_button(fire, "포격 지점", func(): _set_mode(Mode.FIRE_POINT))
	_ctx_button(fire, "예측", func(): _set_mode(Mode.FIRE_PREDICT))
	_ctx_button(fire, "해제", func(): _each(func(u): Orders.clear_fire(u)))
	_ctx_fire = fire
	var lbox := VBoxContainer.new()
	lbox.add_theme_constant_override("separation", 3)
	box.add_child(lbox)
	_ctx_line_label = Label.new()
	_ctx_line_label.add_theme_font_size_override("font_size", 12)
	_ctx_line_label.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
	lbox.add_child(_ctx_line_label)
	var lrow := HBoxContainer.new()
	lbox.add_child(lrow)
	_line_buttons.append(_ctx_button(lrow, "전진 +5", func(): _line_order(func(l): Orders.advance_line(battle, l, LINE_STEP))))
	_line_buttons.append(_ctx_button(lrow, "후퇴 −5", func(): _line_order(func(l): Orders.advance_line(battle, l, -LINE_STEP))))
	_line_buttons.append(_ctx_button(lrow, "공세선", func(): _set_mode(Mode.DRAW_OFFENSIVE)))
	_line_buttons.append(_ctx_button(lrow, "취소", func(): _line_order(func(l): Orders.cancel_advance(battle, l))))
	var lrow2 := HBoxContainer.new()
	lbox.add_child(lrow2)
	_ctx_button(lrow2, "전선 긋기", func(): _set_mode(Mode.DRAW_LINE))
	_ctx_leave = _ctx_button(lrow2, "전선에서 빼기", func(): Orders.leave_line(battle, _own_selected()); _refresh_ui(); queue_redraw())
	_ctx_rejoin = _ctx_button(lrow2, "복귀", func(): Orders.rejoin_line(battle, _own_selected()); _refresh_ui(); queue_redraw())
	_ctx_line = lbox
	_ctx_rows = [stance, order, order2, fire, lbox]


func _ctx_bar(parent: Control, title: String) -> ProgressBar:
	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", 12)
	parent.add_child(label)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(110, 10)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.max_value = 1.0
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0, 0, 0, 0.7)
	bar.add_theme_stylebox_override("background", back)
	bar.add_theme_stylebox_override("fill", StyleBoxFlat.new())
	parent.add_child(bar)
	return bar


func _ctx_small(parent: Control) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 12)
	parent.add_child(label)
	return label


func _ctx_button(parent: Control, text: String, action: Callable) -> Button:
	var b := _button(parent, text, action)
	b.custom_minimum_size = Vector2(0, 30)
	b.add_theme_font_size_override("font_size", 13)
	return b


static func _level_color(frac: float) -> Color:
	return Color(0.25, 0.85, 0.3) if frac > 0.66 else (Color(1.0, 0.8, 0.2) if frac > 0.33 else Color(1.0, 0.3, 0.2))


func _refresh_context() -> void:
	var units: Array[BattleUnit] = []
	for u in selected:
		if u.is_alive() and is_shown(u):
			units.append(u)
	# 지점을 찍는 중이거나 끄는 중에는 지도를 가리지 않게 숨긴다.
	_ctx.visible = not units.is_empty() and mode == Mode.SELECT and _path_unit == null and _place_start == null and _drag_start == null
	if not _ctx.visible:
		return
	var own := _own_selected()
	var alive := 0
	var total := 0
	var morale := 0.0
	for u in units:
		alive += u.alive_count(strength_kind(u))
		total += u.initial_count(strength_kind(u))
		morale += u.morale
	morale /= units.size()
	var first := units[0]
	_ctx_title.text = first.type.name if units.size() == 1 else "부대 %d개" % units.size()
	if first.side != PLAYER_SIDE:
		_ctx_title.text += " (적)"
	var frac := float(alive) / maxi(total, 1)
	_ctx_strength.value = frac
	(_ctx_strength.get_theme_stylebox("fill") as StyleBoxFlat).bg_color = _level_color(frac)
	_ctx_strength_label.text = "%d / %d" % [alive, total]
	var known := own.size() == units.size() or show_all
	_ctx_morale.value = morale / 100.0 if known else 0.0
	(_ctx_morale.get_theme_stylebox("fill") as StyleBoxFlat).bg_color = _level_color(morale / 100.0)
	_ctx_morale_label.text = ("%d %s" % [morale, STATE_NAMES[first.state()] if units.size() == 1 else ""]) if known else "모름"
	var notes: Array[String] = []
	if units.size() == 1 and known:
		if first.hold_reason == "pinned":
			notes.append("고착")
		elif first.is_suppressed():
			notes.append("제압됨")
		if HOLD_REASONS.has(first.hold_reason) and first.hold_reason != "pinned":
			notes.append(HOLD_REASONS[first.hold_reason].split(" (")[0])
		if first.type.setup_ticks > 0 and not first.deployed:
			notes.append("전개 중 %d초" % first.setup_left)
		if first.attack_move:
			notes.append("공격 명령: 사거리까지 접근")
	_ctx_note.text = ", ".join(notes)
	_ctx_note.visible = not notes.is_empty()
	var can_order := _can_order()
	for row in _ctx_rows:
		row.visible = can_order
	_ctx_fire.visible = can_order and own.any(func(u): return _can_point_fire(u))
	if can_order:
		var line := selected_line()
		var in_line := own.any(func(u): return Orders.line_of(battle, u.id) != null)
		_ctx_line_label.text = "전선 전체 명령" if line != null else ("전선 소속 (개별 선택)" if in_line else "전선 없음")
		for b in _line_buttons:
			b.disabled = line == null
		_ctx_leave.disabled = not in_line
		_ctx_rejoin.disabled = not own.any(func(u): return u.individual and Orders.line_of(battle, u.id) != null)
	if can_order:
		for i in _ctx_stances.size():
			_ctx_stances[i].set_pressed_no_signal(own.all(func(u): return u.stance == i))
	_ctx.reset_size()
	_place_context(units)


## 고른 부대들의 오른쪽 아래에 둔다. 화면 밖이나 오른쪽 칸 위로 나가면 반대쪽으로 넘긴다.
func _place_context(units: Array[BattleUnit]) -> void:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var to_screen := get_canvas_transform()
	for u in units:
		for t in u.tiles():
			var p: Vector2 = to_screen * _px(Vector2(t))
			lo = lo.min(p)
			hi = hi.max(p)
	var view := get_viewport_rect().size - Vector2(300, 0)
	var size := _ctx.size
	var low := Vector2(4, 50)
	var high := (view - size).max(low)
	# 네 귀퉁이 가운데 다른 부대를 가장 덜 가리는 자리를 고른다 (같으면 오른쪽 아래 먼저).
	var gap := 28.0
	var spots := [
		Vector2(hi.x + gap, hi.y + gap), Vector2(hi.x + gap, lo.y - gap - size.y),
		Vector2(lo.x - gap - size.x, hi.y + gap), Vector2(lo.x - gap - size.x, lo.y - gap - size.y),
	]
	var best := low
	var best_cost := INF
	for i in spots.size():
		var pos: Vector2 = (spots[i] as Vector2).clamp(low, high)
		var rect := Rect2(pos, size).grow(12)
		var cost := i * 0.1 + pos.distance_to(spots[i]) * 0.02
		for o in battle.units:
			if o.is_alive() and is_shown(o) and rect.has_point(to_screen * _px(o.center)):
				cost += 3.0 if units.has(o) else 1.0
		if cost < best_cost:
			best_cost = cost
			best = pos
	_ctx.position = best


func _group(parent: Control, key: String, title: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = title
	label.custom_minimum_size = Vector2(36, 0)
	row.add_child(label)
	parent.add_child(row)
	_groups[key] = row
	return row


func _button(parent: Control, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 36)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(action)
	parent.add_child(b)
	return b


func _each(f: Callable) -> void:
	for u in _own_selected():
		f.call(u)
	_refresh_ui()
	queue_redraw()


func _cycle_speed() -> void:
	speed_index = (speed_index + 1) % SPEEDS.size()
	_speed_button.text = "속도 ×%d" % [SPEEDS[speed_index] / SPEEDS[0]]


## 고른 부대를 예비대로: 고른 부대가 아닌 첫 아군 전선에 붙인다.
func _to_reserve() -> void:
	var units := _own_selected()
	for line in battle.front_lines:
		if line.side != PLAYER_SIDE:
			continue
		var other := line.units.filter(func(id): return not units.any(func(u): return u.id == id))
		if not other.is_empty():
			Orders.add_reserves(battle, line, units)
			break
	_refresh_ui()
	queue_redraw()


func _refresh_ui() -> void:
	if _top_label == null:
		return
	var phase := "실행기간 %d/%d초" % [battle.turn_tick, battle.turn_seconds] if running else "준비기간"
	if running and paused:
		phase += " (멈춤)"
	var result := ""
	if battle.winner != "":
		result = "   승리!" if battle.winner == PLAYER_SIDE else "   패배"
	var shown_turn := battle.turn if running or battle.winner != "" else battle.turn + 1
	_top_label.text = "턴 %d / %d   %s%s   %s" % [mini(shown_turn, battle.turn_limit), battle.turn_limit, phase, result, _goal_text()]
	_run_button.disabled = battle.winner != ""
	_difficulty_button.disabled = running or (battle.turn > 0 and battle.winner == "")
	_run_button.text = ("계속 ▶" if paused else "일시정지 ⏸") if running else "실행 ▶"
	_multi_button.set_pressed_no_signal(multi_select)
	_orders_button.set_pressed_no_signal(show_orders)
	_vision_button.set_pressed_no_signal(show_vision)
	_refresh_context()
	var own := _own_selected()
	var can_order := not running and battle.winner == "" and not own.is_empty()
	for key in _groups:
		for child in _groups[key].get_children():
			if child is Button:
				child.disabled = not can_order
	if can_order and not own.any(func(u): return _can_point_fire(u)):
		for child in _groups["fire"].get_children():
			if child is Button:
				child.disabled = true
	_info_label.text = _describe_selection()
	_report_label.text = report
	_report_label.visible = not running and report != ""


func _goal_text() -> String:
	var capture: Dictionary = battle.victory.get("capture", {})
	if capture.has(PLAYER_SIDE):
		return "목표: %d턴 안에 점령 목표 %d곳을 모두 점령" % [battle.turn_limit, capture[PLAYER_SIDE].size()]
	if battle.victory.get("defender", "") == PLAYER_SIDE:
		return "목표: %d턴까지 버티기" % battle.turn_limit
	return ""


## 턴 보고: 아군 부대마다 이번 턴에 잃은 병력, 사기 변화와 그 까닭, 새로 발견한 적.
func make_report() -> String:
	var lines: Array[String] = ["— 턴 %d 보고 —" % battle.turn]
	for u in battle.units:
		if u.side != PLAYER_SIDE or u.turn_log.is_empty() or u.turn_log.get("alive", 0) == 0:
			continue
		var parts: Array[String] = []
		var lost: int = u.turn_log.get("lost", 0)
		if not u.is_alive():
			parts.append("전멸")
		elif lost > 0:
			parts.append("%d명 잃음" % lost if not u.type.is_vehicle() else "%d 잃음" % lost)
		var before: int = u.turn_log.get("state", 0)
		if u.is_alive() and u.state() != before:
			parts.append("%s → %s" % [STATE_NAMES[before], STATE_NAMES[u.state()]])
		var causes: Array[String] = []
		if u.turn_log.get("shelled", 0) > 0:
			causes.append("포격 %d발" % u.turn_log["shelled"])
		if u.turn_log.get("unseen", 0) > 0:
			causes.append("보이지 않는 적의 사격")
		if u.turn_log.get("shock", 0) > 0:
			causes.append("기습 충격")
		var by: Dictionary = u.turn_log.get("by", {})
		for who in by:
			causes.append("%s에게 %d" % [who, by[who]])
		if parts.is_empty() and causes.is_empty():
			continue
		var text := "%s: %s" % [u.id, ", ".join(parts) if not parts.is_empty() else "피해 없음"]
		if not causes.is_empty():
			text += " (%s)" % ", ".join(causes)
		lines.append(text)
	var found := 0
	for e in battle.known_enemies(PLAYER_SIDE):
		if not _known_at_start.has(e.id):
			found += 1
	if found > 0:
		lines.append("새로 발견한 적 %d부대" % found)
	if lines.size() == 1:
		lines.append("큰 변화 없음")
	return "\n".join(lines)


func _describe_selection() -> String:
	if selected.is_empty():
		return "고른 부대 없음"
	if selected.size() > 1:
		var line := Orders.common_line(battle, selected)
		return "부대 %d개%s" % [selected.size(), "  (같은 전선)" if line != null else ""]
	var u := selected[0]
	var lines: Array[String] = ["%s  %s" % [u.type.name, u.id]]
	var kinds := "vehicle" if u.type.is_vehicle() else "man"
	lines.append("병력 %d / %d" % [u.alive_count(kinds), u.initial_count(kinds)])
	var ranges: Array[String] = []
	for w in u.type.weapons:
		ranges.append("%s %dm" % [w.name, roundi(w.range_tiles * BattleMap.TILE_METERS)])
	lines.append("사거리: " + ", ".join(ranges))
	if u.side != PLAYER_SIDE:
		return "\n".join(lines)
	lines.append("사기 %d (%s)   제압 %d" % [u.morale, STATE_NAMES[u.state()], u.suppression])
	lines.append("태세 %s   대형 %s %d칸" % [STANCE_NAMES[u.stance], FORMATION_NAMES.get(u.formation, u.formation), u.tile_count])
	var line := Orders.line_of(battle, u.id)
	if line != null:
		lines.append("%s %s%s" % [line.id, "예비대" if line.reserves.has(u.id) else "전선", " (개별 명령)" if u.individual else ""])
	var t := battle.unit_by_id(u.last_target)
	if t != null and battle.tick - u.last_fire_tick <= 10:
		lines.append("사격 대상: %s %s" % [t.type.name, t.id])
	elif u.last_fire_point != null and battle.tick - u.last_fire_tick <= 10:
		lines.append("사격 대상: 지점 포격")
	if u.type.setup_ticks > 0 and not u.deployed:
		lines.append("전개 중 %d초" % u.setup_left)
	if HOLD_REASONS.has(u.hold_reason):
		lines.append("멈춤: " + HOLD_REASONS[u.hold_reason])
	if battle.tick - u.unseen_tick <= UNSEEN_TICKS:
		lines.append("보이지 않는 적에게 공격받는 중 (빨간 ? 방향)")
	return "\n".join(lines)
