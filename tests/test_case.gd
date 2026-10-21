class_name TestCase
extends RefCounted
## 테스트 파일의 바탕. test_ 로 시작하는 함수를 run_tests.gd 가 차례로 부른다.

var failures: Array[String] = []
var _current := ""


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures.append("%s: %s" % [_current, msg])


func check_near(a: float, b: float, msg: String, eps := 0.0001) -> void:
	check(absf(a - b) <= eps, "%s (%s != %s)" % [msg, a, b])
