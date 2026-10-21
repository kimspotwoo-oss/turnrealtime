class_name StageLoader
extends RefCounted
## 스테이지 파일(JSON)을 읽어 Battle 을 만든다. 스테이지는 코드가 아니라 데이터다.

const STANCES := {
	"attack": BattleUnit.Stance.ATTACK,
	"retreat": BattleUnit.Stance.RETREAT,
	"hold": BattleUnit.Stance.HOLD,
	"ignore": BattleUnit.Stance.IGNORE,
}


static func load_file(path: String, unit_types := {}, seed_override := -1) -> Battle:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert(data != null, "스테이지 파일을 읽지 못함: %s" % path)
	return build(data, unit_types if not unit_types.is_empty() else UnitType.load_all(), seed_override)


static func build(data: Dictionary, unit_types: Dictionary, seed_override := -1) -> Battle:
	var m: Dictionary = data["map"]
	var map := BattleMap.new(int(m["width"]), int(m["height"]), m.get("base", "open"))
	for area in m.get("areas", []):
		map.fill_rect(_rect(area["rect"]), area["terrain"])
	var battle := Battle.new(map, int(data.get("seed", 0)) if seed_override < 0 else seed_override)
	battle.turn_seconds = int(data.get("turn_seconds", 60))
	battle.turn_limit = int(data.get("turn_limit", 20))
	for d in data["units"]:
		var type: UnitType = unit_types[d["type"]]
		var u := BattleUnit.new(d["id"], d["side"], type, _vec(d["pos"]), _vec(d.get("facing", [0, -1])), d.get("formation", ""), int(d.get("tiles", 0)))
		u.stance = STANCES[d.get("stance", "hold")]
		u.experience = d.get("experience", "regular")
		if d.has("retreat"):
			u.retreat_point = _vec(d["retreat"])
		if d.has("move"):
			u.move_target = _vec(d["move"])
		battle.add_unit(u)
	var v: Dictionary = data.get("victory", {})
	var capture := {}
	for side in v.get("capture", {}):
		var rects: Array[Rect2i] = []
		for r in v["capture"][side]:
			rects.append(_rect(r))
		capture[side] = rects
	battle.victory = {"capture": capture, "defender": v.get("defender", "")}
	for d in data.get("front_lines", []):
		var line := FrontLine.new(d["id"], d["side"], _points(d["points"]), _vec(d.get("enemy_dir", [0, -1])))
		line.units.assign(d.get("units", []))
		line.reserves.assign(d.get("reserves", []))
		line.stance = STANCES[d.get("stance", "hold")]
		line.offensive = _points(d.get("offensive", []))
		line.retreat = _points(d.get("retreat", []))
		line.apply(battle)
		battle.front_lines.append(line)
	for d in data.get("ai", []):
		match d.get("type", "defense"):
			"defense":
				var objectives: Array[Rect2i] = []
				for side in capture:
					if side != d["side"]:
						objectives.append_array(capture[side])
				var ai := DefenseAI.new(d["side"], battle.front_line(d["front_line"]), objectives)
				ai.personality = d.get("personality", "careful")
				battle.ai_players.append(ai)
	return battle


static func _points(a: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in a:
		out.append(_vec(p))
	return out


static func _vec(a: Array) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))


static func _rect(a: Array) -> Rect2i:
	return Rect2i(int(a[0]), int(a[1]), int(a[2]), int(a[3]))
