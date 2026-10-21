class_name Morale
extends RefCounted
## 사기 상태와 기습 충격 (기획서 '사기 상태와 기습 충격', 수치는 초안).

enum State { STEADY, SHAKEN, PANIC, ROUTED }

const SHAKEN_BELOW := 70.0
const PANIC_BELOW := 40.0
const ROUTED_BELOW := 15.0

## 경험별 충격 시간 (초 = 틱).
const SHOCK_TICKS := {"recruit": 30, "regular": 20, "elite": 10}
const SHOCK_MORALE_LOSS := {1: 15.0, 2: 25.0}

## 동요: 명중률 −25%, 반응 지연 +2초. 패닉: 사격 −75%.
const ACCURACY := {State.STEADY: 1.0, State.SHAKEN: 0.75, State.PANIC: 0.25, State.ROUTED: 0.0}
const EXTRA_REACTION := {State.STEADY: 0, State.SHAKEN: 2, State.PANIC: 4, State.ROUTED: 0}

## 피해로 깎이는 사기: 전체 병력을 잃으면 이만큼.
const LOSS_TO_MORALE := 60.0
## 제압 중일 때 틱마다 깎이는 사기.
const SUPPRESSED_DRAIN := 0.1
## 공격받지 않을 때 틱마다 회복하는 사기.
const RECOVERY_PER_TICK := 0.2
## 마지막으로 공격받은 뒤 이만큼 지나야 회복을 시작한다.
const QUIET_TICKS := 5

const SUPPRESSED_AT := 50.0
const PINNED_AT := 100.0
const SUPPRESSION_MAX := 150.0
const SUPPRESSION_DECAY := 0.5


## shock_level: 0 = 없음, 1 = 약한 충격(최소 동요), 2 = 강한 충격(최소 패닉).
static func state_for(morale: float, shock_level: int) -> State:
	var s := State.STEADY
	if morale < ROUTED_BELOW:
		s = State.ROUTED
	elif morale < PANIC_BELOW:
		s = State.PANIC
	elif morale < SHAKEN_BELOW:
		s = State.SHAKEN
	if shock_level >= 2 and s < State.PANIC:
		s = State.PANIC
	elif shock_level == 1 and s < State.SHAKEN:
		s = State.SHAKEN
	return s


static func shock_ticks(experience: String) -> int:
	return SHOCK_TICKS.get(experience, SHOCK_TICKS["regular"])
