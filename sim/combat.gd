class_name Combat
extends RefCounted
## 관통·도탄, 장갑 방향, 장거리 사격의 흩어짐 계산.

## 관통하지 못해도 들어가는 피해 비율 (기획서 '관통과 도탄', 초안 10%).
const RICOCHET_FRACTION := 0.1
## 흩어짐 중심이 목표보다 사거리 방향으로 밀려나는 정도 (앞뒤 흩어짐 대비).
const SCATTER_OVERSHOOT := 0.2
const SCATTER_UNOBSERVED := 1.5
const SCATTER_MOVING := 2.0
## 정면으로 치는 각도 범위 (중심에서 좌우 45도).
const FRONT_COS := 0.7071


## 관통 확률 = 관통력 ÷ 맞은 방향 장갑 (최대 1).
static func penetration_chance(pen: float, armor: float) -> float:
	if armor <= 0.0:
		return 1.0
	return minf(1.0, pen / armor)


## 장갑 목표 한 번 명중의 피해. 관통하면 전부, 도탄이면 10%.
static func armored_hit(rng: RandomNumberGenerator, damage: float, pen: float, armor: float) -> Dictionary:
	var penetrated := rng.randf() < penetration_chance(pen, armor)
	return {"damage": damage if penetrated else damage * RICOCHET_FRACTION, "penetrated": penetrated}


## 공격자가 목표의 어느 쪽을 치는지: "front", "side", "rear".
static func hit_side(target_pos: Vector2, target_facing: Vector2, attacker_pos: Vector2) -> String:
	var to_attacker := attacker_pos - target_pos
	if to_attacker.is_zero_approx():
		return "side"
	var c := target_facing.normalized().dot(to_attacker.normalized())
	if c >= FRONT_COS:
		return "front"
	if c <= -FRONT_COS:
		return "rear"
	return "side"


static func armor_for(type: UnitType, side: String) -> float:
	match side:
		"front":
			return type.armor_front
		"rear":
			return type.armor_rear
	return type.armor_side()


## 흩어짐 범위의 앞뒤 반폭과 좌우 반폭 (칸 단위).
static func scatter_extent(dist: float, w: WeaponType, multiplier := 1.0) -> Vector2:
	var along := minf(dist * w.scatter_ratio, w.scatter_max_tiles) * multiplier
	var lateral := dist * tan(deg_to_rad(w.scatter_angle_deg / 2.0)) * multiplier
	return Vector2(along, lateral)


## 포탄이 떨어질 지점. 사거리 방향으로 길쭉한 범위 안에서 균등하게 고르고,
## 중심은 목표보다 살짝 뒤라 넘어가는 탄이 많다.
static func scatter_point(rng: RandomNumberGenerator, origin: Vector2, aim: Vector2, w: WeaponType, multiplier := 1.0) -> Vector2:
	var dir := aim - origin
	var dist := dir.length()
	if dist == 0.0:
		return aim
	dir /= dist
	var perp := Vector2(-dir.y, dir.x)
	var ext := scatter_extent(dist, w, multiplier)
	var along := rng.randf_range(-ext.x, ext.x) + ext.x * SCATTER_OVERSHOOT
	var lateral := rng.randf_range(-ext.y, ext.y)
	return aim + dir * along + perp * lateral
