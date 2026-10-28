extends SceneTree

const SUITES = {"FinalFix":"res://tests/suites/test_final_fix.gd", "Bootstrap": "res://tests/suites/test_bootstrap.gd", "Map": "res://tests/suites/test_map.gd", "Commands": "res://tests/suites/test_commands.gd", "Clinic": "res://tests/suites/test_clinic.gd", "Challenge":"res://tests/suites/test_challenge.gd", "Save":"res://tests/suites/test_save.gd", "Presentation":"res://tests/suites/test_presentation.gd", "Input":"res://tests/suites/test_input.gd", "Integration":"res://tests/suites/test_integration.gd", "BuildPrecision":"res://tests/suites/test_build_precision.gd"}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var suite := "All"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("suite="):
			suite = argument.trim_prefix("suite=")
	if suite != "All" and not SUITES.has(suite):
		print("SUITE ERROR: unknown suite " + suite)
		quit(1)
		return
	var t := TestContext.new()
	print("RUNTIME PATHS: " + JSON.stringify({
		"user": OS.get_user_data_dir(), "data": OS.get_data_dir(),
		"cache": OS.get_cache_dir(), "temp": OS.get_environment("TEMP"),
		"tmp": OS.get_environment("TMP")
	}))
	var allowed_root := "E:/CODEX"
	if OS.get_name() == "macOS":
		var runner_temp := OS.get_environment("RUNNER_TEMP").replace("\\", "/").simplify_path().trim_suffix("/")
		var isolated_root := OS.get_environment("HOSPITAL_CI_RUNTIME_ROOT").replace("\\", "/").simplify_path().trim_suffix("/")
		var isolated_ci := OS.get_environment("GITHUB_ACTIONS") == "true" and runner_temp.is_absolute_path() and isolated_root == runner_temp.path_join("hospital-ios-build/runtime")
		t.expect_true(isolated_ci,"Mac regression runtime is isolated inside this private CI job")
		if isolated_ci: allowed_root = isolated_root
	for path in [OS.get_user_data_dir(), OS.get_data_dir(), OS.get_cache_dir(), OS.get_environment("TEMP"), OS.get_environment("TMP")]:
		t.expect_true(path.replace("\\", "/").simplify_path().begins_with(allowed_root+"/"), "runtime path stays inside required storage root: " + path)
	for name in SUITES:
		if suite == "All" or suite == name:
			load(SUITES[name]).new().run(t)
	# Fixtures release their audio players synchronously; the mixer drains later.
	await create_timer(0.24).timeout
	print("TEST RESULT: failed=%d passed=%d" % [t.failed, t.passed])
	quit(1 if t.failed > 0 else 0)
