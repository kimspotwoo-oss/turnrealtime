# turnrealtime

동시 실행형 턴제 전략게임. 모든 부대가 준비기간에 받은 명령에 따라 실행기간 동안 동시에 움직인다.

- 엔진: Godot 4.3
- 기획서: [동시 실행형 턴제 전략게임 기획서](https://claude.ai/artifact/DoueKpfjDjGDbMTPyE4fTB)

## 구조

- `sim/`: 화면과 상관없는 전투 계산. 칸 맵, 1초 틱, 이동, 시야, 사격, 관통·도탄, 흩어짐, 근접전, 제압·사기, 승리 조건.
- `sim/front_line.gd`: 전선 기능 (전선 긋기, 공세선, 후퇴선, 전선 태세, 예비대).
- `sim/defense_ai.gd`: 방어 AI. 자기 진영이 본 적만 보고, 플레이어와 같은 명령만 쓴다.
- `data/unit_types.json`: 1단계 병과 수치 (기획서 '1단계 병과 수치 초안').
- `data/stages/`: 스테이지 파일. 스테이지는 코드가 아니라 데이터다.
- `scenes/main.tscn`: 확인용 화면. 스페이스로 한 턴씩 실행, R로 처음부터. 부대는 NATO 부대 기호(`scripts/unit_symbol.gd`)로 그린다.
- `assets/fonts/`: 한글 글꼴 Pretendard (SIL Open Font License 1.1, `OFL-Pretendard.txt`).
- `tests/`: 헤드리스 테스트.

## 실행

Godot 4.3에서 프로젝트를 열고 실행(F5)하면 연습 스테이지 확인 화면이 뜬다.

테스트:

```sh
godot --headless --import
godot --headless -s tests/run_tests.gd
```
