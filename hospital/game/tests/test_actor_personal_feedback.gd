extends SceneTree

const TASK_ROOT := "E:/CODEX/2026-10-22/医院经营深度与人物行为升级/"
const SOURCE := TASK_ROOT + "reports/people-GREEN-01-need-mid-save/main.json"
const SOURCE_SHA := "bb3e5fbf89b29e9074e1beedc1750104c77ab6f49ff48e11c20e64c037419813"
var output := ""
var checks: Array = []
var observations: Array = []
var failed := 0

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=").replace("\\", "/")
	_run.call_deferred()

func check(ok: bool, label: String, detail: Variant = null) -> bool:
	checks.append({"ok": ok, "check": label, "detail": detail})
	if not ok: failed += 1
	print(("ACTOR PERSONAL PASS: " if ok else "ACTOR PERSONAL FAIL: ") + label)
	return ok

func show_actual(sim: Simulation, id: String, label: String, walking: bool) -> void:
	var snapshot: Dictionary = sim.snapshot()
	var actor: Dictionary = snapshot.patients[id]
	var view := ActorView.new()
	view.entity_id = id
	view.appearance_seed = int(snapshot.get("appearance_seed", 0))
	view.presentation_tick = int(snapshot.tick)
	view.presentation_paused = bool(snapshot.paused)
	view.presentation_speed = int(snapshot.speed)
	root.add_child(view)
	view.present(actor, false)
	var detail := {"tick": snapshot.tick, "patient_id": id, "phase": actor.phase, "cell": actor.cell, "move_progress": actor.move_progress, "path": actor.path, "path_index": actor.path_index, "has_queue_cell": actor.has("queue_cell"), "need_activity": actor.need_activity, "rig_state": view._rig_state, "route_active": view._route_active}
	observations.append(detail)
	check(view._route_active == walking and (view._rig_state == "Walk") == walking, label, detail)
	check(not view.cure_feedback.visible, "personal activity cannot display a cure result")
	check(sim.snapshot() == snapshot, "presenting actual personal activity leaves clinical state unchanged")
	view.free()

func _run() -> void:
	if not output.begins_with(TASK_ROOT) or output.simplify_path() != output or FileAccess.file_exists(output):
		printerr("Require a fresh absolute T2 output"); quit(2); return
	if not check(FileAccess.get_sha256(SOURCE) == SOURCE_SHA, "source is the immutable actual public personal-trip save"): finish(); return
	var catalog_result: Dictionary = ContentCatalog.load_checked("res://content")
	if not check(catalog_result.get("ok", false), "real current catalog loads"): finish(); return
	var loaded: Dictionary = SaveStore.load(SOURCE.get_base_dir(), catalog_result.catalog)
	if not check(loaded.get("ok", false) and not loaded.get("used_backup", true), "actual personal-trip save strictly loads without fallback", loaded.get("error", "")): finish(); return
	var sim := Simulation.new(catalog_result.catalog, loaded.state)
	var id := "patient_001"
	var initial: Dictionary = sim.snapshot().patients.get(id, {})
	if not check(initial.get("phase", "") == "care_queue" and initial.get("need_activity", {}).get("state", "") == "walking" and not initial.has("queue_cell") and int(initial.get("move_progress", 0)) > 0, "source contains genuine personal walking without a queue marker"): finish(); return
	show_actual(sim, id, "actual personal half-edge retains Walk", true)
	var found := false
	for _index: int in range(8):
		sim.advance_ticks(1)
		var p: Dictionary = sim._state.data.patients[id]
		if p.get("need_activity", {}).get("state", "") == "walking" and int(p.move_progress) == 0 and int(p.path_index) + 1 < p.path.size(): found = true; break
	if check(found, "real ticks reach a personal-trip grid boundary with another route edge"):
		check(SnapshotValidator.validate(sim.snapshot(), catalog_result.catalog) == "", "actual personal grid-boundary state strictly validates")
		show_actual(sim, id, "actual personal grid boundary retains Walk", true)
		var evidence := FileAccess.open(output.get_basename() + "-grid-actual.json", FileAccess.WRITE)
		if evidence != null: evidence.store_string(JSON.stringify(sim.snapshot(), "  ")); evidence.close()
	var using := false
	for _index: int in range(400):
		sim.advance_ticks(1)
		if sim._state.data.patients[id].get("need_activity", {}).get("state", "") == "using": using = true; break
	if check(using, "same patient actually arrives and starts paid personal use"):
		show_actual(sim, id, "stationary personal use does not play Walk", false)
	finish()

func finish() -> void:
	check(FileAccess.get_sha256(SOURCE) == SOURCE_SHA, "actual personal-trip source bytes remain unchanged")
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null: quit(2); return
	file.store_string(JSON.stringify({"passed": checks.size() - failed, "failed": failed, "checks": checks, "observations": observations, "source": SOURCE, "source_sha256": SOURCE_SHA, "scope": "Strictly read actual public personal-trip save; advance genuine ticks to half-edge, grid boundary and paid use. Presentation only, without model injection."}, "  "))
	file.close()
	print("ACTOR PERSONAL RESULT: passed=%d failed=%d" % [checks.size() - failed, failed])
	quit(1 if failed else 0)
