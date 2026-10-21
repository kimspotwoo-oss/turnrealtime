class_name Formation
extends RefCounted
## 소대가 차지하는 칸 모양. 오프셋은 소대 기준 좌표(x = 오른쪽, y = 앞쪽)로 만든다.

const KINDS := ["line", "column", "wedge", "dispersed"]


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
