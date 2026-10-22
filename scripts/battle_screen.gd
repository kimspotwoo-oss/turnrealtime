extends Node2D
## 집중전투 화면. 준비기간에 명령을 내리고, 실행기간을 지켜본다.
##
## 마우스: 왼쪽 클릭 = 선택·명령, 왼쪽 끌기 = 여러 부대 선택, 오른쪽 클릭 = 그리기 완료·모드 취소,
## 가운데 끌기 = 화면 이동, 휠 = 확대·축소.
## 키보드: 스페이스 = 실행, Enter = 그리기 완료, Esc = 취소, F1 = 전체 보기(시험용).

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
const STATE_NAMES := ["안정", "동요", "패닉", "패주"]
const STANCE_NAMES := ["공격", "후퇴", "저지", "무시"]
const FORMATION_NAMES := {"line": "횡대", "column": "종대", "wedge": "쐐기", "dispersed": "분산"}

enum Mode { SELECT, MOVE, RETREAT_POINT, FIRE_POINT, FIRE_PREDICT, DRAW_LINE, DRAW_OFFENSIVE, DRAW_RETREAT_LINE }

const MODE_HINTS := {
	Mode.SELECT: "부대를 누르거나 끌어서 고르세요.",
	Mode.MOVE: "이동할 곳을 누르세요.",
	Mode.RETREAT_POINT: "후퇴지를 누르세요.",
	Mode.FIRE_POINT: "포격할 지점을 누르세요.",
	Mode.FIRE_PREDICT: "예측 사격할 적 부대를 누르세요.",
	Mode.DRAW_LINE: "전선을 이루는 점들을 차례로 누르고, 오른쪽 클릭이나 Enter로 마치세요.",
	Mode.DRAW_OFFENSIVE: "공세선 점들을 누르고, 오른쪽 클릭이나 Enter로 마치세요.",
	Mode.DRAW_RETREAT_LINE: "후퇴선 점들을 누르고, 오른쪽 클릭이나 Enter로 마치세요.",
}

var battle: Battle
var selected: Array[BattleUnit] = []
var mode := Mode.SELECT
var draft := PackedVector2Array()
var running := false
var speed_index := 0
var show_all := false

var _tick_accum := 0.0
var _drag_start = null
var _panning := false
var _terrain_tex: ImageTexture
var _camera: Camera2D

var _top_label: Label
var _hint_label: Label
var _info_label: Label
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
	battle = StageLoader.load_file(path)
	selected.clear()
	_set_mode(Mode.SELECT)
	running = false
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
	battle.begin_turn()
	running = true
	_tick_accum = 0.0
	_refresh_ui()


func _process(delta: float) -> void:
	if not running:
		return
	_tick_accum += delta * SPEEDS[speed_index]
	while _tick_accum >= 1.0 and not battle.turn_over():
		battle.step()
		_tick_accum -= 1.0
	if battle.turn_over():
		battle.end_turn()
		running = false
		_prune_selection()
	_refresh_ui()
	queue_redraw()


func _prune_selection() -> void:
	selected = selected.filter(func(u): return u.is_alive())


# --- 입력 ---------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_on_mouse_button(event)
	elif event is InputEventMouseMotion:
		if _panning:
			_camera.position -= event.relative / _camera.zoom
		if _drag_start != null or not draft.is_empty():
			queue_redraw()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE:
				start_turn()
			KEY_ENTER, KEY_KP_ENTER:
				finish_draft()
			KEY_ESCAPE:
				_set_mode(Mode.SELECT)
			KEY_F1:
				show_all = not show_all
				queue_redraw()


func _on_mouse_button(event: InputEventMouseButton) -> void:
	match event.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			_camera.zoom = (_camera.zoom * 1.1).clamp(Vector2(0.4, 0.4), Vector2(3, 3))
		MOUSE_BUTTON_WHEEL_DOWN:
			_camera.zoom = (_camera.zoom / 1.1).clamp(Vector2(0.4, 0.4), Vector2(3, 3))
		MOUSE_BUTTON_MIDDLE:
			_panning = event.pressed
		MOUSE_BUTTON_RIGHT:
			if event.pressed:
				if draft.size() >= 2:
					finish_draft()
				else:
					_set_mode(Mode.SELECT)
		MOUSE_BUTTON_LEFT:
			var p := _mouse_tile()
			if event.pressed:
				if mode == Mode.SELECT:
					_drag_start = p
				else:
					click_at(p, event.shift_pressed)
			elif _drag_start != null:
				var start: Vector2 = _drag_start
				_drag_start = null
				if start.distance_to(p) < 0.6:
					click_at(p, event.shift_pressed)
				else:
					box_select(Rect2(start, Vector2.ZERO).expand(p), event.shift_pressed)


func _mouse_tile() -> Vector2:
	return get_global_mouse_position() / TILE_PX - Vector2(0.5, 0.5)


## 지도 한 점을 눌렀을 때. 지금 모드에 따라 고르거나 명령한다.
func click_at(p: Vector2, add := false) -> void:
	if running:
		return
	match mode:
		Mode.SELECT:
			var u := unit_at(p)
			if not add:
				selected.clear()
			if u != null and not selected.has(u):
				selected.append(u)
		Mode.MOVE:
			_move_group(p)
			_set_mode(Mode.SELECT)
		Mode.RETREAT_POINT:
			for u in _own_selected():
				Orders.set_retreat_point(u, p)
			_set_mode(Mode.SELECT)
		Mode.FIRE_POINT:
			for u in _own_selected():
				if _has_indirect(u):
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
func _move_group(p: Vector2) -> void:
	var units := _own_selected()
	if units.is_empty():
		return
	var c := Vector2.ZERO
	for u in units:
		c += u.center
	c /= units.size()
	for u in units:
		Orders.move(u, p + (u.center - c))


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
	for line in battle.front_lines:
		if line.side != PLAYER_SIDE and not show_all:
			continue
		var color: Color = SIDE_COLORS.get(line.side, Color.WHITE)
		_draw_line_points(line.points, color, 3.0)
		_draw_line_points(line.offensive, color.lightened(0.4), 2.0, true)
		_draw_line_points(line.retreat, color.darkened(0.3), 2.0, true)
	for u in battle.units:
		if u.is_alive() and is_shown(u):
			_draw_unit(u)
	for u in battle.units:
		if u.is_alive() and is_shown(u):
			_draw_fire(u)
	for u in selected:
		if u.is_alive() and is_shown(u):
			_draw_ranges(u)
	for u in _own_selected():
		_draw_orders(u)
	for s in battle.shells:
		draw_circle(_px(s["point"]), 3.0, Color.YELLOW)
	if not draft.is_empty():
		var pts := draft.duplicate()
		pts.append(_mouse_tile())
		_draw_line_points(pts, Color.WHITE, 2.0)
	if _drag_start != null:
		var r := Rect2(_px(_drag_start), Vector2.ZERO).expand(_px(_mouse_tile()))
		draw_rect(r, Color(1, 1, 1, 0.8), false, 1.5)


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


func _draw_orders(u: BattleUnit) -> void:
	if u.move_target != null:
		draw_dashed_line(_px(u.center), _px(u.move_target), Color.WHITE, 1.5, 6.0)
		draw_circle(_px(u.move_target), 3.0, Color.WHITE)
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


## 최근에 쏜 사격을 쏜 부대에서 목표로 선을 긋는다. 오래될수록 흐려진다.
## 아군 사격은 노란색, 적 사격은 주황색이다.
## 고른 부대의 무기별 사거리 원. 같은 사거리는 한 번만, 칸 하나 남짓한 근접 무기는 뺀다.
func _draw_ranges(u: BattleUnit) -> void:
	var color: Color = SIDE_COLORS.get(u.side, Color.WHITE).darkened(0.1)
	var font := ThemeDB.fallback_font
	var drawn := {}
	for w in u.type.weapons:
		if w.range_tiles < 2.0 or drawn.has(w.range_tiles):
			continue
		drawn[w.range_tiles] = true
		var r := (w.range_tiles + 0.5) * TILE_PX
		draw_arc(_px(u.center), r, 0.0, TAU, 96, color, 2.0)
		draw_string(font, _px(u.center) + Vector2(4, -r - 4), "%s %dm" % [w.name, roundi(w.range_tiles * BattleMap.TILE_METERS)], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, color)
		if w.min_range_tiles > 0.0:
			draw_arc(_px(u.center), w.min_range_tiles * TILE_PX, 0.0, TAU, 48, color.darkened(0.3), 1.0)


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
	_run_button = _button(top, "실행 ▶", start_turn)
	_speed_button = _button(top, "속도 ×1", _cycle_speed)
	_button(top, "처음부터", func(): load_stage(STAGE))
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
	_button(order, "정지", func(): _each(func(u): Orders.stop(u)))
	_button(order, "후퇴지", func(): _set_mode(Mode.RETREAT_POINT))
	var fire := _group(box, "fire", "포격")
	_button(fire, "지점", func(): _set_mode(Mode.FIRE_POINT))
	_button(fire, "예측", func(): _set_mode(Mode.FIRE_PREDICT))
	_button(fire, "해제", func(): _each(func(u): Orders.clear_fire(u)))
	var line := _group(box, "line", "전선")
	_button(line, "전선 긋기", func(): _set_mode(Mode.DRAW_LINE))
	_button(line, "공세선", func(): _set_mode(Mode.DRAW_OFFENSIVE))
	_button(line, "후퇴선", func(): _set_mode(Mode.DRAW_RETREAT_LINE))
	var line2 := _group(box, "line2", "")
	_button(line2, "예비대로", _to_reserve)
	_button(line2, "완료", finish_draft)
	_button(line2, "취소", func(): _set_mode(Mode.SELECT))


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
	var result := ""
	if battle.winner != "":
		result = "   승리!" if battle.winner == PLAYER_SIDE else "   패배"
	_top_label.text = "턴 %d / %d   %s%s" % [battle.turn + (0 if running else 1), battle.turn_limit, phase, result]
	_run_button.disabled = running or battle.winner != ""
	var own := _own_selected()
	var can_order := not running and battle.winner == "" and not own.is_empty()
	for key in _groups:
		for child in _groups[key].get_children():
			if child is Button:
				child.disabled = not can_order
	if can_order and not own.any(func(u): return _has_indirect(u)):
		for child in _groups["fire"].get_children():
			if child is Button:
				child.disabled = true
	_info_label.text = _describe_selection()


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
	return "\n".join(lines)
