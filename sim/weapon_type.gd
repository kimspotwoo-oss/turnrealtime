class_name WeaponType
extends RefCounted
## 무기 하나의 수치. data/unit_types.json 의 "weapons" 항목에서 읽는다.

var id: String
var name: String
## 무기 수가 어떤 구성원 수에 비례해 줄어드는지 ("man", "vehicle", "gun").
var scale: String
var count: int
var damage: float
var pen_near: float
var pen_far: float
var range_tiles: float
var min_range_tiles: float
var interval_ticks: int
var acc_near: float
var acc_far: float
var suppression: float
var indirect: bool
var close_at: bool
var blast_tiles: int
var shell_speed_tiles: float
var scatter_ratio: float
var scatter_max_tiles: float
var scatter_angle_deg: float


static func from_dict(d: Dictionary) -> WeaponType:
	var w := WeaponType.new()
	w.id = d["id"]
	w.name = d.get("name", w.id)
	w.scale = d.get("scale", "man")
	w.count = int(d.get("count", 1))
	w.damage = float(d["damage"])
	var pen: Array = d.get("pen", [0, 0])
	w.pen_near = float(pen[0])
	w.pen_far = float(pen[1])
	w.range_tiles = float(d["range_m"]) / BattleMap.TILE_METERS
	w.min_range_tiles = float(d.get("min_range_m", 0)) / BattleMap.TILE_METERS
	w.interval_ticks = int(d.get("interval_s", 1))
	var acc: Array = d.get("accuracy", [1.0, 1.0])
	w.acc_near = float(acc[0])
	w.acc_far = float(acc[1])
	w.suppression = float(d.get("suppression", 0.0))
	w.indirect = bool(d.get("indirect", false))
	w.close_at = bool(d.get("close_at", false))
	w.blast_tiles = int(d.get("blast_tiles", 0))
	w.shell_speed_tiles = float(d.get("shell_speed_mps", 0)) / BattleMap.TILE_METERS
	var sc: Dictionary = d.get("scatter", {})
	w.scatter_ratio = float(sc.get("ratio", 0.0))
	w.scatter_max_tiles = float(sc.get("max_m", 0.0)) / BattleMap.TILE_METERS
	w.scatter_angle_deg = float(sc.get("angle_deg", 0.0))
	return w


## 거리 비율(0 = 바로 앞, 1 = 최대 사거리)에 따른 관통력.
func pen_at(dist_tiles: float) -> float:
	return lerpf(pen_near, pen_far, clampf(dist_tiles / range_tiles, 0.0, 1.0))


func accuracy_at(dist_tiles: float) -> float:
	return lerpf(acc_near, acc_far, clampf(dist_tiles / range_tiles, 0.0, 1.0))


## 소화기처럼 관통력이 너무 낮아 장갑 목표에는 쏘지 않는 무기인지.
func is_small_arms() -> bool:
	return pen_near < 10.0 and not indirect
