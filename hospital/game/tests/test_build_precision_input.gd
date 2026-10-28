extends SceneTree

func _initialize() -> void:_run.call_deferred()

func _run() -> void:
	var t:=TestContext.new()
	load("res://tests/suites/test_build_precision.gd").new().run(t)
	print("BUILD PRECISION INPUT RESULT: passed=%d failed=%d"%[t.passed,t.failed])
	quit(1 if t.failed else 0)
