extends SceneTree

const TestContext = preload("res://tests/test_context.gd")
const SETTINGS_ROOT := "E:/CODEX/2026-10-19/医院原稿落地/work/feedback/tests"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var t := TestContext.new()
	var service_script: Script = load("res://presentation/hospital_feedback.gd")
	t.expect_true(service_script != null, "feedback service script exists")
	if service_script != null:
		_test_preferences_restore_without_touching_save(service_script,t)
		_test_corrupt_preferences_use_defaults_and_preserve_bytes(service_script,t)
		_test_volume_bounds_and_audio_independence(service_script,t)
		_test_non_finite_volume_is_safe(service_script,t)
		_test_haptics_reports_platform_support(service_script,t)
		_test_write_failure_keeps_previous_preferences(service_script,t)
		_test_focus_lifecycle(service_script,t)
	print("TEST RESULT: failed=%d passed=%d" % [t.failed,t.passed])
	await process_frame
	await process_frame
	await create_timer(0.5).timeout
	quit(1 if t.failed > 0 else 0)

func _test_focus_lifecycle(script: Script,t: TestContext) -> void:
	var node := _service(script,_new_root("focus"))
	t.expect_true(node.has_method("set_application_active"),"feedback service exposes focus lifecycle")
	if not node.has_method("set_application_active"):
		node.free()
		return
	var music: AudioStreamPlayer = node.get_node("MusicPlayer")
	var effects: AudioStreamPlayer = node.get_node("SfxPlayer")
	var before: Dictionary = node.preferences()
	node.play_confirmed()
	t.expect_true(effects.playing,"pre-loss confirmation is playing")
	node.set_application_active(false)
	t.expect_false(music.playing,"paused music is not rendered as active playback")
	t.expect_true(music.stream_paused,"focus loss pauses actual music stream")
	t.expect_false(music.playing,"focus loss stops active music stream")
	t.expect_false(effects.playing,"focus loss stops current effect stream")
	node.play_rejected()
	t.expect_false(effects.playing,"inactive app blocks new sound effects")
	var haptic: Dictionary = node.request_haptic()
	t.expect_false(haptic.requested,"inactive app blocks vibration request")
	t.expect_equal(haptic.reason,"application_inactive","inactive vibration reports lifecycle reason")
	t.expect_false(haptic.requested,"inactive app blocks vibration request")
	t.expect_equal(node.preferences(),before,"focus loss does not alter user preferences")
	node.set_application_active(true)
	t.expect_true(music.playing,"focus return resumes music enabled by preference")
	t.expect_false(music.stream_paused,"focus return unpauses actual music stream")
	t.expect_true(music.playing,"focus return resumes music enabled by preference")
	t.expect_false(effects.playing,"focus return does not replay old effects")
	t.expect_equal(node.preferences(),before,"focus return preserves preferences")
	node.set_music_enabled(false)
	var muted_preferences: Dictionary = node.preferences()
	node.set_application_active(false)
	node.set_application_active(true)
	t.expect_false(music.playing,"focus return honors music disabled by preference")
	t.expect_equal(node.preferences(),muted_preferences,"resume does not rewrite settings")
	node.free()
func _new_root(name: String) -> String:
	var path := SETTINGS_ROOT.path_join(name + "_" + str(Time.get_ticks_usec()))
	DirAccess.make_dir_recursive_absolute(path)
	return path

func _service(script: Script, root: String) -> Node:
	var node: Node = script.new()
	get_root().add_child(node)
	node.configure(root)
	return node

func _test_preferences_restore_without_touching_save(script: Script,t: TestContext) -> void:
	var root := _new_root("restore")
	var main_path := root.path_join("main.json")
	var main_file := FileAccess.open(main_path,FileAccess.WRITE)
	main_file.store_string("keep game save")
	main_file.close()
	var node := _service(script,root)
	var pref: Dictionary = node.preferences()
	t.expect_true(pref.get("music_enabled",false),"music defaults enabled")
	t.expect_true((node.get_node("MusicPlayer") as AudioStreamPlayer).playing,"default music actually starts")
	t.expect_true(pref.get("haptics_enabled",false),"haptics default intent enabled")
	node.set_music_volume(0.23)
	node.set_sfx_volume(0.71)
	node.set_haptics_enabled(false)
	node.set_music_enabled(false)
	node.free()
	var loaded := _service(script,root)
	var restored: Dictionary = loaded.preferences()
	t.expect_false(restored.music_enabled,"music preference survives restart")
	t.expect_false(restored.haptics_enabled,"haptics preference survives restart")
	t.expect_true(is_equal_approx(restored.music_volume,0.23),"music volume survives restart")
	t.expect_true(is_equal_approx(restored.sfx_volume,0.71),"sfx volume survives restart")
	t.expect_equal(FileAccess.get_file_as_string(main_path),"keep game save","preferences are isolated from main save")
	loaded.free()

func _test_corrupt_preferences_use_defaults_and_preserve_bytes(script: Script,t: TestContext) -> void:
	var root := _new_root("corrupt")
	var path := root.path_join("preferences.jsonl")
	var original := "{ definitely broken config"
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(original)
	file.close()
	var node := _service(script,root)
	t.expect_true(node.preferences().music_enabled,"corrupt config falls back to safe music default")
	t.expect_true(node.preferences().haptics_enabled,"corrupt config falls back to haptics default")
	t.expect_equal(FileAccess.get_file_as_string(path),original,"corrupt preferences retained unchanged on load")
	node.free()

func _test_volume_bounds_and_audio_independence(script: Script,t: TestContext) -> void:
	var root := _new_root("audio")
	var node := _service(script,root)
	node.set_music_volume(4.0)
	node.set_sfx_volume(-2.0)
	var prefs: Dictionary = node.preferences()
	t.expect_equal((node.get_node("MusicPlayer") as AudioStreamPlayer).volume_db,0.0,"music volume reaches music player only")
	t.expect_equal(prefs.music_volume,1.0,"music volume clamps high")
	t.expect_equal(prefs.sfx_volume,0.0,"sfx volume clamps low")
	node.set_music_enabled(false)
	node.play_confirmed()
	var music: AudioStreamPlayer = node.get_node("MusicPlayer")
	var effects: AudioStreamPlayer = node.get_node("SfxPlayer")
	t.expect_true(effects.stream.resource_path.ends_with("ui_confirm.wav"),"confirm uses its own audible cue")
	t.expect_false(music.playing,"music toggle stops actual looping player")
	t.expect_true(effects.playing,"sfx plays while music is disabled")
	t.expect_true(effects.volume_db < -70.0,"sfx volume is applied independently")
	node.set_music_enabled(true)
	t.expect_true(music.playing,"re-enabled music actually loops")
	t.expect_true(music.stream is AudioStreamWAV and music.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD,"music stream loops")
	node.play_rejected()
	t.expect_true(effects.stream.resource_path.ends_with("ui_reject.wav"),"reject uses a distinct audible cue")
	t.expect_true(effects.playing,"reject feedback has a real player")
	node.free()

func _test_non_finite_volume_is_safe(script: Script,t: TestContext) -> void:
	var node := _service(script,_new_root("nan_volume"))
	var result: Dictionary = node.set_music_volume(NAN)
	t.expect_true(result.ok,"non-finite volume safely persists")
	t.expect_true(is_finite(float(node.preferences().music_volume)),"non-finite volume never enters preferences")
	t.expect_true(node.preferences().music_volume >= 0.0 and node.preferences().music_volume <= 1.0,"non-finite volume remains in range")
	node.free()

func _test_haptics_reports_platform_support(script: Script,t: TestContext) -> void:
	var node := _service(script,_new_root("haptics"))
	node.set_haptics_enabled(true)
	if not (OS.has_feature("android") or OS.has_feature("ios")):
		var outcome: Dictionary = node.request_haptic()
		t.expect_false(outcome.supported,"desktop reports hardware haptics unavailable")
		t.expect_false(outcome.requested,"desktop does not claim vibration occurred")
	node.free()

func _test_write_failure_keeps_previous_preferences(script: Script,t: TestContext) -> void:
	var root := _new_root("write-failure")
	var prefs_path := root.path_join("preferences.jsonl")
	DirAccess.make_dir_absolute(prefs_path)
	var node := _service(script,root)
	var before: Dictionary = node.preferences()
	var result: Dictionary = node.set_music_enabled(false)
	t.expect_false(result.ok,"persistence failure is surfaced")
	t.expect_equal(node.preferences(),before,"failed persistence rolls back live preference")
	t.expect_true(DirAccess.dir_exists_absolute(prefs_path),"failed write preserves pre-existing path")
	node.free()
