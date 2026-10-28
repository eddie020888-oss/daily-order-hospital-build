extends SceneTree

# Counts the real deep-copy boundary; all model and rendering methods still run.
class CountingSimulation:
	extends Simulation
	var snapshot_calls := 0
	func _init(content: ContentCatalog, state: ClinicState) -> void:
		super(content, state)
	func snapshot() -> Dictionary:
		snapshot_calls += 1
		return super.snapshot()

class CountingWorld:
	extends HospitalWorld
	var present_calls := 0
	var received_read_only := false
	func present(value: Dictionary) -> void:
		present_calls += 1
		received_read_only = value.is_read_only()
		super.present(value)

const TASK_ROOT := "E:/CODEX/2026-10-22/医院经营深度与人物行为升级/"
var output := ""
var source_save := ""
var source_sha := ""
var catalog: ContentCatalog
var checks: Array = []
var observations: Dictionary = {}
var games: Array[GameSession] = []
var failed := 0

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=").replace("\\", "/")
		elif arg.begins_with("--source-save="): source_save = arg.trim_prefix("--source-save=").replace("\\", "/")
	_run.call_deferred()

func check(ok: bool, label: String, detail: Variant = null) -> void:
	checks.append({"ok": ok, "check": label, "detail": detail})
	if not ok: failed += 1
	print(("PRESENTATION SNAPSHOT PASS: " if ok else "PRESENTATION SNAPSHOT FAIL: ") + label)

func make_game(sample: Dictionary, tag: String) -> GameSession:
	var decoded: Dictionary = ClinicState.from_data(sample, catalog)
	if not decoded.get("ok", false): return null
	var game := GameSession.new(catalog, output.get_basename() + "-" + tag + "-saves")
	game.sim = CountingSimulation.new(catalog, decoded.state)
	games.append(game)
	return game

func recursively_frozen(value: Variant) -> bool:
	if value is Dictionary:
		if not value.is_read_only(): return false
		for child: Variant in value.values():
			if not recursively_frozen(child): return false
	elif value is Array:
		if not value.is_read_only(): return false
		for child: Variant in value:
			if not recursively_frozen(child): return false
	return true

func test_snapshot_contract(sample: Dictionary) -> void:
	var game := make_game(sample, "contract")
	check(game != null, "actual source strictly creates the isolated contract session")
	if game == null: return
	var api: bool = game.has_method("presentation_snapshot") and game.has_method("presentation_revision")
	check(api, "session provides a read-only presentation snapshot and revision")
	if not api: return
	var meter: CountingSimulation = game.sim
	meter.snapshot_calls = 0
	var frame: Dictionary = game.call("presentation_snapshot")
	var first_revision: int = int(game.call("presentation_revision"))
	for _index: int in range(10):
		var repeated: Dictionary = game.call("presentation_snapshot")
		check(is_same(frame, repeated), "unchanged presentation shares the detached read-only frame " + str(_index))
	check(meter.snapshot_calls == 1, "cold repeated presentation makes exactly one real deep copy", meter.snapshot_calls)
	check(recursively_frozen(frame), "nested arrays and dictionaries are read-only, not just the root")
	var before: Dictionary = meter.snapshot()
	var ordinary: Dictionary = meter.snapshot()
	ordinary.cash += 999
	ordinary.command_receipts.clear()
	if not ordinary.rooms.is_empty():
		var room_id: String = str(ordinary.rooms.keys()[0])
		ordinary.rooms[room_id].cells.clear()
	check(meter.snapshot() == before and frame == before, "legacy mutable snapshot remains detached from both model and cached frame")
	var changed_speed: int = 2 if int(frame.speed) == 1 else 1
	var command: Dictionary = game.issue("set_speed", {"speed": changed_speed})
	var after_command: Dictionary = game.call("presentation_snapshot")
	check(command.ok and after_command.speed == changed_speed and int(game.call("presentation_revision")) > first_revision, "same-tick accepted command invalidates the frame")
	check(frame.speed != after_command.speed and not is_same(frame, after_command), "previous reader keeps its original immutable frame after a command")
	var prior_revision: int = int(game.call("presentation_revision"))
	game.sim.submit({"id": "presentation_direct_pause", "type": "set_paused", "payload": {"paused": false}})
	var direct: Dictionary = game.call("presentation_snapshot")
	check(not direct.paused and int(game.call("presentation_revision")) > prior_revision, "direct public Simulation command also invalidates session presentation")
	prior_revision = int(game.call("presentation_revision"))
	game.sim.advance_ticks(1)
	var advanced: Dictionary = game.call("presentation_snapshot")
	check(advanced.tick == direct.tick + 1 and int(game.call("presentation_revision")) > prior_revision, "real fixed tick invalidates the presentation frame")
	var same_clock_state: Dictionary = game.sim.snapshot()
	prior_revision = int(game.call("presentation_revision"))
	var decoded: Dictionary = ClinicState.from_data(same_clock_state, catalog)
	game.sim = CountingSimulation.new(catalog, decoded.state)
	var replacement: Dictionary = game.call("presentation_snapshot")
	check(replacement == same_clock_state and int(game.call("presentation_revision")) > prior_revision and not is_same(replacement, advanced), "new Simulation with identical clock/state cannot reuse the prior instance cache")
	var clock: Dictionary = game.sim.clock_state()
	clock.paused = not clock.paused
	check(game.sim.clock_state().paused == same_clock_state.paused, "scalar clock polling remains detached")

func test_notification_contract() -> void:
	# A tempting change that suppresses legacy subtick signals must fail here.
	for level_id: String in ["level_01", "career_01", "long_01"]:
		var game := make_game(ClinicState.create(level_id, catalog).to_data(), level_id)
		var trace: Array = []
		game.command_result.connect(func(result: Dictionary) -> void: trace.append("result:" + str(result.code)))
		game.changed.connect(func() -> void:
			trace.append("changed")
			if game.has_method("presentation_snapshot"): game.call("presentation_snapshot")
		)
		game.issue("set_paused", {"paused": false})
		check(trace == ["result:ok", "changed"], level_id + " command_result still precedes changed")
		trace.clear()
		game.advance_wall_time(1)
		check(trace == ([] if level_id == "long_01" else ["changed"]), level_id + " original subtick notification order remains")
		trace.clear()
		game.issue("not_a_command")
		check(trace == ["result:unknown_command", "changed"], level_id + " rejected command still sends result then feedback change")
		trace.clear()
		game.notice = "缓存不应阻止同tick提示更新"
		game.dismiss_notice()
		check(trace == ["changed"] and game.notice == "", level_id + " same-tick notice change remains observable")

func test_actual_main(sample: Dictionary) -> void:
	var game := make_game(sample, "main")
	if game == null: check(false, "actual Main source creates session"); return
	var host: Node3D = load("res://main.gd").new()
	host.session = game
	root.add_child(host)
	host.set_process(false)
	for _index: int in range(3): await process_frame
	host.hud.flow.close()
	var old_world: HospitalWorld = host.world
	var world := CountingWorld.new()
	host.add_child(world)
	host.world = world
	host.touch.world = world
	host.hud.world = world
	host.hud.campaign_panel.world = world
	old_world.free()
	# New real Simulation identity makes this a cold frame without fake progress.
	var decoded: Dictionary = ClinicState.from_data(game.sim.snapshot(), catalog)
	game.sim = CountingSimulation.new(catalog, decoded.state)
	var meter: CountingSimulation = game.sim
	for _index: int in range(10): host._present()
	observations.actual_main = {"snapshot_calls": meter.snapshot_calls, "world_present_calls": world.present_calls, "present_requests": 10, "source_patients": sample.patients.size()}
	check(meter.snapshot_calls == 1, "ten real Main/HUD presents share one cold snapshot", observations.actual_main)
	check(world.present_calls == 1, "unchanged Main does not rerender the real World", world.present_calls)
	check(world.received_read_only, "real World receives the read-only detached snapshot")
	var copies_before: int = meter.snapshot_calls
	game.notice = "只更新提示，不复制或重绘模型"
	game.changed.emit()
	check(host.hud._notice_panel.visible and host.hud._notice.text == game.notice, "HUD displays a newly arriving same-tick notice without a model change")
	game.dismiss_notice()
	check(meter.snapshot_calls == copies_before and world.present_calls == 1, "same-tick notice signal does not clone or rerender World")
	check(not host.hud._notice_panel.visible, "HUD still processes same-tick dismissed notices")
	host.free()

func _run() -> void:
	if not output.begins_with(TASK_ROOT) or FileAccess.file_exists(output):
		push_error("Fresh T2 --output required"); quit(2); return
	for tag: String in ["contract", "level_01", "career_01", "long_01", "main"]:
		if DirAccess.dir_exists_absolute(output.get_basename() + "-" + tag + "-saves"):
			push_error("Fresh isolated save roots required"); quit(2); return
	var loaded: Dictionary = ContentCatalog.load_checked("res://content")
	check(loaded.get("ok", false), "real catalog loads")
	if not loaded.get("ok", false): finish(); return
	catalog = loaded.catalog
	var sample: Dictionary = ClinicState.create("long_01", catalog).to_data()
	if source_save != "":
		if not source_save.begins_with("E:/CODEX/") or source_save.get_file() != "main.json" or not FileAccess.file_exists(source_save):
			push_error("Existing E:/CODEX main source required"); quit(2); return
		source_sha = FileAccess.get_sha256(source_save)
		var disk: Dictionary = SaveStore.load(source_save.get_base_dir(), catalog)
		check(disk.get("ok", false) and not disk.get("used_backup", true), "optional actual source strictly loads without fallback")
		if not disk.get("ok", false): finish(); return
		sample = disk.state.to_data()
	test_snapshot_contract(sample)
	test_notification_contract()
	await test_actual_main(sample)
	finish.call_deferred()

func finish() -> void:
	for game: GameSession in games:
		for signal_name: String in ["changed", "command_result"]:
			for link: Dictionary in game.get_signal_connection_list(signal_name): game.disconnect(signal_name, link.callable)
	games.clear()
	if source_save != "": check(FileAccess.get_sha256(source_save) == source_sha, "optional original source remains byte-for-byte unchanged")
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null: quit(2); return
	file.store_string(JSON.stringify({"passed": checks.size() - failed, "failed": failed, "checks": checks, "observations": observations, "source_save": source_save, "source_sha256": source_sha, "scope": "Real catalog, strict saved source or real factories, public commands and fixed ticks. Actual Main/HUD/World with counting subclasses that run their real implementations. No fabricated clinical progress, no performance/FPS claim."}, "  "))
	file.close()
	print("PRESENTATION SNAPSHOT RESULT: passed=%d failed=%d" % [checks.size() - failed, failed])
	quit(1 if failed else 0)
