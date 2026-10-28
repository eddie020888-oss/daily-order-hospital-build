class_name TestContext
extends RefCounted

var failed: int = 0
var passed: int = 0

func expect_equal(actual: Variant, expected: Variant, label: String) -> void:
	_check(actual == expected, "%s: expected %s, got %s" % [label, str(expected), str(actual)])

func expect_true(value: bool, label: String) -> void:
	_check(value, label)

func expect_false(value: bool, label: String) -> void:
	_check(not value, label)

func expect_contains(text: String, part: String, label: String) -> void:
	_check(text.contains(part), label)

func _check(success: bool, label: String) -> void:
	if success:
		passed += 1
	else:
		failed += 1
		print("FAIL: " + label)
