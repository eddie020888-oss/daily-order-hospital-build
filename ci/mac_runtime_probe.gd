extends SceneTree

func _initialize() -> void:
	var expected := OS.get_environment("HOSPITAL_CI_RUNTIME_ROOT").replace("\\", "/").simplify_path().trim_suffix("/")
	var runner := OS.get_environment("RUNNER_TEMP").replace("\\", "/").simplify_path().trim_suffix("/")
	var failed := 0
	if OS.get_name() != "macOS" or OS.get_environment("GITHUB_ACTIONS") != "true" or expected != runner.path_join("hospital-ios-build/runtime"):
		print("FAIL: Mac runtime probe requires the actual isolated CI environment")
		quit(1)
		return
	var paths := {"user":OS.get_user_data_dir(),"data":OS.get_data_dir(),"cache":OS.get_cache_dir(),"TEMP":OS.get_environment("TEMP"),"TMP":OS.get_environment("TMP")}
	print("MAC_RUNTIME_ENV: " + JSON.stringify({"HOME":OS.get_environment("HOME"),"expected_root":expected,"paths":paths}))
	for key: String in paths:
		if not str(paths[key]).replace("\\", "/").simplify_path().begins_with(expected+"/"):
			failed += 1
			print("FAIL: Mac " + key + " path escapes isolated runtime: " + str(paths[key]))
	print("MAC_RUNTIME_PROBE_RESULT: failed=%d" % failed)
	quit(1 if failed else 0)
