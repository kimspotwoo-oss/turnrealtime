class_name Formation
extends RefCounted
## 소대가 차지하는 칸 모양. 오프셋은 소대 기준 좌표(x = 오른쪽, y = 앞쪽)로 만든다.

const KINDS := ["line", "column", "wedge", "dispersed"]

## 분산 대형의 대가. 사람 사이가 벌어지면 포탄 한 발에 덜 다치는 대신, 분대장이 소리와 손짓으로
## 부하를 다 챙기지 못한다: 걸음이 느려지고, 적을 보고 반응하기까지 더 걸리고,
## 흩어진 병사들이 서로 기대지 못해 사기가 더디게 돌아온다.
const DISPERSED_SPEED := 0.75
const DISPERSED_EXTRA_REACTION := 1
const DISPERSED_RECOVERY := 0.5


static func local_offsets(kind: String, n: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	match kind:
		"line":
			for i in n:
				out.append(Vector2i(i - (n - 1) / 2, 0))
		"column":
			for i in n:
				out.append(Vector2i(0, -i))
		"wedge":
			out.append(Vector2i.ZERO)
			for i in range(1, n):
				var row := (i + 1) / 2
				out.append(Vector2i(-row if i % 2 == 1 else row, -row))
		"dispersed":
			for i in n:
				out.append(Vector2i((i - (n - 1) / 2) * 2, -(i % 2)))
		_:
			assert(false, "모르는 대형: %s" % kind)
	return out


## 기준 좌표의 오프셋을 맵 칸으로 바꾼다. 대각선 방향에서 겹치는 칸은 하나로 친다.
static func world_tiles(center: Vector2, facing: Vector2, offsets: Array[Vector2i]) -> Array[Vector2i]:
	var fwd := facing.normalized()
	var right := Vector2(-fwd.y, fwd.x)
	var out: Array[Vector2i] = []
	for o in offsets:
		var t := Vector2i((center + right * o.x + fwd * o.y).round())
		if not out.has(t):
			out.append(t)
	return out
