class_name UnitType
extends RefCounted
## 병과 하나의 수치. data/unit_types.json 에서 읽는다.

var id: String
var name: String
## 구성원 묶음 목록: {"kind": "man" | "vehicle" | "gun", "count": int, "hp": float, "shield": float}
var elements: Array[Dictionary] = []
var armor_front: float
var armor_rear: float
var tiles_min: int
var tiles_max: int
var tiles_default: int
var sight_tiles: float
## 칸/분 단위 속도. "foot" 또는 "vehicle", 차량은 "road" 도 가질 수 있다.
var speed: Dictionary
var setup_ticks: int
var melee_power: float
var weapons: Array[WeaponType] = []


static func from_dict(id: String, d: Dictionary) -> UnitType:
	var t := UnitType.new()
	t.id = id
	t.name = d.get("name", id)
	for e in d["elements"]:
		t.elements.append({
			"kind": e["kind"],
			"count": int(e["count"]),
			"hp": float(e["hp"]),
			"shield": float(e.get("shield", 0)),
		})
	var armor: Dictionary = d.get("armor", {})
	t.armor_front = float(armor.get("front", 0))
	t.armor_rear = float(armor.get("rear", 0))
	var tiles: Dictionary = d["tiles"]
	t.tiles_min = int(tiles["min"])
	t.tiles_max = int(tiles["max"])
	t.tiles_default = int(tiles["default"])
	t.sight_tiles = float(d["sight_m"]) / BattleMap.TILE_METERS
	t.speed = d["speed_tiles_per_min"]
	t.setup_ticks = int(d.get("setup_seconds", 0))
	t.melee_power = float(d.get("melee_power", 1.0))
	for w in d.get("weapons", []):
		t.weapons.append(WeaponType.from_dict(w))
	return t


static func load_all(path := "res://data/unit_types.json") -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	var data: Dictionary = JSON.parse_string(text)
	var out := {}
	for id in data:
		out[id] = UnitType.from_dict(id, data[id])
	return out


func is_vehicle() -> bool:
	return speed.has("vehicle")


## 측면 장갑은 전면과 후면의 평균이다.
func armor_side() -> float:
	return (armor_front + armor_rear) / 2.0
