extends Node2D
## 확인용 화면: 연습 스테이지를 위에서 내려다보며 한 턴씩 돌려 본다.
## 스페이스 = 실행기간 한 턴, R = 처음부터. 정식 화면과 입력은 다음 단계에서 만든다.

const STAGE := "res://data/stages/practice.json"
const TILE_PX := 20.0
const SYMBOL_PX := 20.0
## 플레이어 진영. 기호는 이 진영 기준으로 아군·적을 나눈다.
const PLAYER_SIDE := "player"
const TERRAIN_COLORS := {
	"open": Color(0.62, 0.68, 0.45),
	"road": Color(0.55, 0.5, 0.4),
	"forest": Color(0.25, 0.4, 0.22),
	"village": Color(0.6, 0.55, 0.5),
}
const SIDE_COLORS := {"player": Color(0.2, 0.4, 0.9), "ai": Color(0.85, 0.25, 0.2)}

var battle: Battle
var _status: Label


func _ready() -> void:
	_status = Label.new()
	_status.position = Vector2(8, 40 * TILE_PX + 8)
	add_child(_status)
	_reset()


func _reset() -> void:
	battle = StageLoader.load_file(STAGE)
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE:
				battle.run_turn()
				_refresh()
			KEY_R:
				_reset()


func _refresh() -> void:
	var alive := {}
	for u in battle.units:
		if u.is_alive():
			alive[u.side] = alive.get(u.side, 0) + 1
	var result := "" if battle.winner == "" else "  승리: %s" % battle.winner
	_status.text = "턴 %d / %d   공격측 부대 %d   방어측 부대 %d%s\n스페이스: 한 턴 실행   R: 처음부터" % [
		battle.turn, battle.turn_limit, alive.get("player", 0), alive.get("ai", 0), result]
	queue_redraw()


func _draw() -> void:
	var map := battle.map
	for y in map.height:
		for x in map.width:
			draw_rect(Rect2(x * TILE_PX, y * TILE_PX, TILE_PX, TILE_PX), TERRAIN_COLORS[map.terrain_at(Vector2i(x, y))])
	for line in battle.front_lines:
		var color: Color = SIDE_COLORS.get(line.side, Color.WHITE)
		_draw_polyline(line.points, color, 3.0)
		_draw_polyline(line.offensive, color.lightened(0.4), 2.0)
	for u in battle.units:
		if not u.is_alive():
			continue
		var color: Color = SIDE_COLORS.get(u.side, Color.WHITE)
		match u.state():
			Morale.State.SHAKEN:
				color = color.lightened(0.3)
			Morale.State.PANIC, Morale.State.ROUTED:
				color = color.lightened(0.6)
		var tile_color := color
		tile_color.a = 0.45
		for t in u.tiles():
			draw_rect(Rect2(t.x * TILE_PX + 1, t.y * TILE_PX + 1, TILE_PX - 2, TILE_PX - 2), tile_color)
		var c := (u.center + Vector2(0.5, 0.5)) * TILE_PX
		draw_line(c, c + u.facing * TILE_PX * 1.2, Color.BLACK, 2.0)
		UnitSymbol.draw(self, c, SYMBOL_PX, u.type.symbol_icon, u.type.symbol_echelon, u.side != PLAYER_SIDE, color)
	for s in battle.shells:
		draw_circle(((s["point"] as Vector2) + Vector2(0.5, 0.5)) * TILE_PX, 3.0, Color.YELLOW)


func _draw_polyline(points: PackedVector2Array, color: Color, width: float) -> void:
	if points.size() < 2:
		return
	var px := PackedVector2Array()
	for p in points:
		px.append((p + Vector2(0.5, 0.5)) * TILE_PX)
	draw_polyline(px, color, width)
