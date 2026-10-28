extends SceneTree

# Run only against HospitalBeta.pck from a fresh, source-free CI working folder.
# No gameplay commands or default user-save paths are used by this probe.
const PACK_NAME := "HospitalBeta.pck"
const EXPECTED_CAST := {"doctor":60,"technician":8,"receptionist":8,"patient":48}
const TEXTURE_SAMPLE_LIMIT := 16

var failed := 0
var passed := 0
var host: Node3D
var _finishing := false
var _save_root := ""

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, label: String) -> bool:
	if ok: passed += 1
	else: failed += 1
	print(("HOSPITAL_PACKED_PASS: " if ok else "HOSPITAL_PACKED_FAIL: ") + label)
	return ok

func _clean(path: String) -> String:
	return path.replace("\\", "/").simplify_path().trim_suffix("/")

func _pack_argument() -> String:
	var args := OS.get_cmdline_args()
	for index: int in range(args.size()):
		if args[index] == "--main-pack" and index + 1 < args.size(): return args[index + 1]
		if args[index].begins_with("--main-pack="): return args[index].trim_prefix("--main-pack=")
	return ""

func _preflight() -> bool:
	var runner_temp := _clean(OS.get_environment("RUNNER_TEMP"))
	if not _check(runner_temp.is_absolute_path(), "runner temporary root is explicit and absolute"): return false
	var scratch := runner_temp.path_join("hospital-ios-build")
	var empty_root := scratch.path_join("packed-smoke-empty")
	_save_root = scratch.path_join("packed-smoke-save")
	var directory := DirAccess.open(".")
	if not _check(directory != null and _clean(directory.get_current_dir()) == empty_root, "process cwd is the isolated packed-smoke-empty directory"): return false
	if not _check(DirAccess.get_files_at(empty_root).is_empty() and DirAccess.get_directories_at(empty_root).is_empty(), "working directory contains no loose source files or folders"): return false
	# The actual red/green isolated PCK invocation globalizes res:// to empty.
	# A source-project resource root here would invalidate this smoke's evidence.
	if not _check(ProjectSettings.globalize_path("res://").is_empty(), "resource root comes from the main pack, with no source project root"): return false
	var pack_path := _clean(_pack_argument())
	if not _check(pack_path.is_absolute_path() and pack_path.begins_with(scratch + "/") and pack_path.get_file() == PACK_NAME, "explicit main-pack selects the exported hospital pack inside this job"): return false
	var pack := FileAccess.open(pack_path, FileAccess.READ)
	if not _check(pack != null, "exported hospital pack is readable"): return false
	var magic := pack.get_buffer(4).get_string_from_ascii()
	pack.close()
	if not _check(magic == "GDPC", "main-pack has a real Godot PCK header"): return false
	if not _check(not DirAccess.dir_exists_absolute(_save_root) and not FileAccess.file_exists(_save_root), "injected smoke save path is fresh"): return false
	return _check(DisplayServer.get_name() == "headless", "probe uses headless execution without rendering waits")

func _watchdog() -> void:
	await create_timer(90.0).timeout
	if not _finishing:
		_check(false, "probe exceeded its 90-second process-frame deadline")
		await _finish()

func _run() -> void:
	if not _preflight():
		await _finish()
		return
	_watchdog.call_deferred()
	var catalog_script: GDScript = load("res://sim/content_catalog.gd")
	if not _check(catalog_script != null, "actual packed ContentCatalog script loads"):
		await _finish()
		return
	var checked: Dictionary = catalog_script.load_checked("res://content")
	if not _check(bool(checked.get("ok", false)), "actual packed business catalog validates"):
		# The error is a controlled production error code, never source JSON.
		var code := str(checked.get("error", "unknown"))
		if code.length() < 100 and code.replace(":", "").replace("_", "").replace("-", "").is_valid_identifier():
			print("HOSPITAL_PACKED_FAIL: catalog code " + code)
		await _finish()
		return
	var catalog: Variant = checked.catalog
	if not _check(catalog.campaign.facilities.size() == 128 and catalog.campaign.cases.size() == 96 and catalog.levels.size() == 26, "packed catalog retains 128 facilities, 96 cases and all 26 levels"):
		await _finish()
		return
	_check_equipment(catalog)
	_check_cast()
	if failed == 0:
		await _check_main(catalog)
	await _finish()

func _check_equipment(catalog: Variant) -> void:
	var kinds: Array = catalog.campaign.facilities.keys()
	kinds.sort()
	var view_count := 0
	var mapped_count := 0
	var sample_count := 0
	var raw_probe := ""
	var sample_stride := maxi(1, int(ceil(float(kinds.size()) / float(TEXTURE_SAMPLE_LIMIT))))
	for index: int in range(kinds.size()):
		var facility: Dictionary = catalog.campaign.facilities[kinds[index]]
		for view: Dictionary in facility.views:
			view_count += 1
			var path: String = view.path
			if raw_probe.is_empty(): raw_probe = path
			if ResourceLoader.exists(path, "Texture2D"): mapped_count += 1
		if index % sample_stride != 0 or sample_count >= TEXTURE_SAMPLE_LIMIT: continue
		# Ignore the resource cache and release each sample immediately; the
		# smoke does not retain all 512 source textures on the standard Mac.
		var sample: Resource = ResourceLoader.load(str(facility.views[0].path), "Texture2D", ResourceLoader.CACHE_MODE_IGNORE)
		_check(sample is Texture2D and sample.get_width() > 0 and sample.get_height() > 0, "representative packed equipment texture decodes with nonzero dimensions")
		sample = null
		sample_count += 1
	_check(view_count == 512 and mapped_count == 512, "all 512 mapped equipment views exist in the actual pack")
	_check(sample_count == TEXTURE_SAMPLE_LIMIT, "16 distributed equipment samples were loaded without retention")
	_check(not raw_probe.is_empty() and not FileAccess.file_exists(raw_probe), "original imported PNG is absent, proving no loose-source fallback")

func _check_cast() -> void:
	var cast: GDScript = load("res://presentation/unified_character_cast.gd")
	var roster: GDScript = load("res://presentation/character_roster.gd")
	if not _check(cast != null and roster != null, "actual packed unified cast and roster scripts load"): return
	var complete_count := 0
	for family: String in EXPECTED_CAST:
		for ordinal: int in range(1, int(EXPECTED_CAST[family]) + 1):
			var canonical := "%s-%02d" % [family, ordinal]
			if not cast.id_available(canonical): continue
			var model: String = cast.model_path(canonical)
			var portrait: String = cast.portrait_path(canonical)
			if model.is_empty() or portrait.is_empty(): continue
			if roster.model_path(canonical) != model or roster.portrait_path(canonical) != portrait: continue
			if ResourceLoader.exists(model, "PackedScene") and ResourceLoader.exists(portrait, "Texture2D"):
				complete_count += 1
		# One actual model and portrait per existing art family. Every identity
		# above is checked through the production registry and resource remaps.
		var sample_id := family + "-01"
		var sample_model: Resource = ResourceLoader.load(cast.model_path(sample_id), "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
		var sample_portrait: Resource = ResourceLoader.load(cast.portrait_path(sample_id), "Texture2D", ResourceLoader.CACHE_MODE_IGNORE)
		_check(sample_model is PackedScene and sample_portrait is Texture2D, "representative character family model and portrait load")
		if sample_model is PackedScene:
			var instance: Node = sample_model.instantiate()
			_check(instance is Node3D, "representative packed character scene instantiates")
			instance.free()
		sample_model = null
		sample_portrait = null
	_check(complete_count == 124, "all 124 production identities retain mapped models and portraits")

func _check_main(catalog: Variant) -> void:
	var main_script: GDScript = load("res://main.gd")
	var session_script: GDScript = load("res://session/game_session.gd")
	if not _check(main_script != null and session_script != null, "actual packed Main and GameSession scripts load"): return
	var injected: Variant = session_script.new(catalog, _save_root)
	host = main_script.new()
	host.session = injected
	host.set_process(false)
	root.add_child(host)
	host.set_process(false)
	# No frame_post_draw in a headless probe and no wall-time/simulation advance.
	await process_frame
	await process_frame
	if not _check(host.session == injected and host.session.save_root == _save_root, "real Main uses only the injected isolated session/save path"): return
	var snapshot: Dictionary = host.session.sim.snapshot()
	_check(int(snapshot.tick) == 0 and bool(snapshot.paused) and snapshot.rooms.is_empty() and snapshot.staff.is_empty() and snapshot.patients.is_empty(), "real packed Main starts paused at tick zero without gameplay commands")
	if not _check(host.hud != null and host.world != null, "real packed Main creates its actual HUD and hospital world"): return
	_check(host.hud.flow != null and host.hud.flow.page == "launch" and host.hud.flow.is_visible_in_tree(), "real packed hospital launch menu is active")
	_check(host.hud.flow.controls.has("continue_game") and host.hud.flow.controls.continue_game.is_visible_in_tree(), "real launch menu contains its visible continue action")

func _finish() -> void:
	if _finishing: return
	_finishing = true
	if host != null:
		host.free()
		host = null
		await process_frame
	print("HOSPITAL_PACKED_RESULT: failed=%d passed=%d" % [failed, passed])
	quit(1 if failed > 0 else 0)
