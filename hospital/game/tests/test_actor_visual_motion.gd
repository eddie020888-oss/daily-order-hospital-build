extends SceneTree

const HELPER_PATH := "res://presentation/actor_visual_motion.gd"
var passed := 0
var failed := 0

func _initialize() -> void: _run.call_deferred()

func check(value: bool, label: String) -> void:
	if value: passed += 1
	else: failed += 1
	print(("VISUAL MOTION PASS: " if value else "VISUAL MOTION FAIL: ") + label)

func _run() -> void:
	check(ResourceLoader.exists(HELPER_PATH), "presentation-only motion helper exists")
	if not ResourceLoader.exists(HELPER_PATH):
		finish()
		return
	var script: Script = load(HELPER_PATH)
	check(script != null and script.can_instantiate(), "motion helper compiles independently")
	if script == null or not script.can_instantiate():
		finish()
		return
	var motion: Variant = script.new()
	motion.present(Vector3(2, .05, 3), 10, false, 1)
	check(motion.offset().is_zero_approx() and not motion.is_moving(), "first snapshot aligns without inventing travel")
	motion.present(Vector3(2.25, .05, 3), 11, false, 1)
	check(motion.offset().is_equal_approx(Vector3(-.25, 0, 0)) and motion.is_moving(), "new tick begins at the previous authoritative position")
	check(motion.advance(.05).is_equal_approx(Vector3(-.125, 0, 0)), "1x motion reaches half of a quarter-edge in 50 ms")
	motion.present(Vector3(2.25, .05, 3), 11, false, 1)
	check(motion.offset().is_equal_approx(Vector3(-.125, 0, 0)), "same-tick command presentation does not restart interpolation")
	check(motion.advance(.05).is_zero_approx() and not motion.is_moving(), "1x motion finishes at the authoritative endpoint in 100 ms")
	check(motion.advance(5).is_zero_approx(), "completed motion never predicts past the authoritative endpoint")
	motion.present(Vector3(2.25, .05, 3.25), 12, false, 1)
	var turn: Vector3 = motion.advance(.05)
	check(turn.is_equal_approx(Vector3(0, 0, -.125)), "a corner follows its new quarter-edge without diagonal wall cutting")
	motion.advance(.05)
	motion.present(Vector3(2.25, .05, 3.5), 13, false, 2)
	check(motion.advance(.025).is_equal_approx(Vector3(0, 0, -.125)), "2x motion reaches its midpoint in 25 ms")
	check(motion.advance(.025).is_zero_approx(), "2x motion finishes in 50 ms")
	motion.present(Vector3(2.5, .05, 3.5), 14, false, 1)
	motion.advance(.025)
	motion.present(Vector3(2.5, .05, 3.5), 14, true, 1)
	check(motion.offset().is_zero_approx() and not motion.is_moving(), "same-tick pause change immediately aligns to the authoritative position")
	check(motion.advance(2).is_zero_approx(), "paused motion cannot drift on wall-clock time")
	motion.present(Vector3(2.5, .05, 3.5), 14, false, 1)
	check(motion.offset().is_zero_approx(), "same-tick resume preserves the aligned position")
	motion.present(Vector3(2.75, .05, 3.5), 15, false, 1)
	check(motion.is_moving(), "single-tick movement resumes normally")
	motion.present(Vector3(3, .05, 3.5), 17, false, 1)
	check(motion.offset().is_zero_approx() and not motion.is_moving(), "missing multiple ticks align instead of sweeping through unknown routes")
	motion.present(Vector3(3.25, .05, 3.5), 5, false, 1)
	check(motion.offset().is_zero_approx(), "time rollback or save reload aligns immediately")
	motion.present(Vector3(5, .05, 3.5), 6, false, 1)
	check(motion.offset().is_zero_approx() and not motion.is_moving(), "teleport farther than .36 metres never creates a long slide")
	motion.present(Vector3(5.25, .9, 3.5), 7, false, 1)
	check(motion.advance(.05).is_equal_approx(Vector3(-.125, 0, 0)), "floor height changes do not introduce vertical interpolation")
	motion.advance(.05)
	motion.present(Vector3(5.5, .9, 3.5), 8, false, 1)
	motion.advance(.025)
	var before_speed: Vector3 = motion.offset()
	motion.present(Vector3(5.5, .9, 3.5), 8, false, 2)
	check(motion.offset().is_equal_approx(before_speed), "same-tick speed command preserves the displayed position")
	check(motion.advance(.0375).is_zero_approx(), "changed speed applies only to the remaining segment time")
	motion.present(Vector3(5.75, .9, 3.5), 9, false, 1)
	var before_delta: Vector3 = motion.offset()
	check(motion.advance(-1).is_equal_approx(before_delta), "negative frame delta cannot reverse motion")
	motion.advance(10)
	check(motion.offset().is_zero_approx() and not motion.is_moving(), "large render delta clamps at the endpoint")
	finish()

func finish() -> void:
	print("VISUAL MOTION RESULT: passed=%d failed=%d" % [passed, failed])
	quit(1 if failed else 0)
