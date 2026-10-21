class_name UnitSymbol
extends RefCounted
## NATO 부대 기호(APP-6) 그리기. 아군은 직사각형 틀, 적은 마름모 틀이다.
## 틀 안 기호가 병과(보병 X, 전차 타원, 대전차 ∧, 박격포 원과 화살표)를,
## 틀 위 점이 규모(분대 1개, 반 2개, 소대 3개, 중대는 막대)를 나타낸다.

const ECHELON_DOTS := {"squad": 1, "section": 2, "platoon": 3}


static func draw(ci: CanvasItem, center: Vector2, h: float, icon: String, echelon: String, hostile: bool, fill: Color, line := Color.BLACK, width := 1.5) -> void:
	var inner: Rect2
	var top: float
	if hostile:
		var r := h * 0.75
		var pts := PackedVector2Array([center + Vector2(0, -r), center + Vector2(r, 0), center + Vector2(0, r), center + Vector2(-r, 0)])
		ci.draw_colored_polygon(pts, fill)
		pts.append(pts[0])
		ci.draw_polyline(pts, line, width)
		inner = Rect2(center - Vector2(r, r) * 0.5, Vector2(r, r))
		top = center.y - r
	else:
		var size := Vector2(h * 1.5, h)
		inner = Rect2(center - size / 2.0, size)
		ci.draw_rect(inner, fill)
		ci.draw_rect(inner, line, false, width)
		top = inner.position.y
	_draw_icon(ci, inner, icon, line, width)
	_draw_echelon(ci, Vector2(center.x, top - h * 0.2), h, echelon, line)


static func _draw_icon(ci: CanvasItem, r: Rect2, icon: String, color: Color, width: float) -> void:
	var tl := r.position
	var br := r.end
	var tr := Vector2(br.x, tl.y)
	var bl := Vector2(tl.x, br.y)
	var c := r.get_center()
	match icon:
		"infantry":
			ci.draw_line(tl, br, color, width)
			ci.draw_line(tr, bl, color, width)
		"armor":
			_draw_ellipse(ci, c, Vector2(r.size.x * 0.32, r.size.y * 0.24), color, width)
		"anti_tank":
			var peak := Vector2(c.x, tl.y)
			ci.draw_line(bl, peak, color, width)
			ci.draw_line(peak, br, color, width)
		"mortar":
			var base := Vector2(c.x, br.y - r.size.y * 0.2)
			ci.draw_arc(base, r.size.y * 0.12, 0.0, TAU, 12, color, width)
			var tip := Vector2(c.x, tl.y + r.size.y * 0.15)
			ci.draw_line(base - Vector2(0, r.size.y * 0.12), tip, color, width)
			var head := r.size.y * 0.15
			ci.draw_line(tip, tip + Vector2(-head, head), color, width)
			ci.draw_line(tip, tip + Vector2(head, head), color, width)


static func _draw_ellipse(ci: CanvasItem, c: Vector2, radius: Vector2, color: Color, width: float) -> void:
	var pts := PackedVector2Array()
	for i in 25:
		var a := TAU * i / 24.0
		pts.append(c + Vector2(cos(a) * radius.x, sin(a) * radius.y))
	ci.draw_polyline(pts, color, width)


static func _draw_echelon(ci: CanvasItem, bottom_center: Vector2, h: float, echelon: String, color: Color) -> void:
	if echelon == "company":
		ci.draw_line(bottom_center, bottom_center - Vector2(0, h * 0.3), color, maxf(1.0, h * 0.08))
		return
	var n: int = ECHELON_DOTS.get(echelon, 0)
	var gap := h * 0.22
	for i in n:
		ci.draw_circle(bottom_center + Vector2((i - (n - 1) / 2.0) * gap, -h * 0.05), h * 0.07, color)
