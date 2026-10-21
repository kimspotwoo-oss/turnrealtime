extends SceneTree
## 헤드리스 테스트 실행: godot --headless -s tests/run_tests.gd

const SUITES := [
	"res://tests/test_combat.gd",
	"res://tests/test_morale.gd",
	"res://tests/test_formation.gd",
	"res://tests/test_battle.gd",
	"res://tests/test_front_line.gd",
	"res://tests/test_ai.gd",
	"res://tests/test_stage.gd",
]


func _init() -> void:
	var total := 0
	var failed: Array[String] = []
	for path in SUITES:
		var suite: TestCase = load(path).new()
		for m in suite.get_method_list():
			var name: String = m["name"]
			if not name.begins_with("test_"):
				continue
			total += 1
			suite._current = "%s::%s" % [path.get_file(), name]
			var before := suite.failures.size()
			suite.call(name)
			print("%s %s" % ["ok  " if suite.failures.size() == before else "FAIL", suite._current])
		failed.append_array(suite.failures)
	for f in failed:
		printerr(f)
	print("%d tests, %d failures" % [total, failed.size()])
	quit(1 if failed.size() > 0 else 0)
