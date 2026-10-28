extends SceneTree

const TASK_ROOT := "E:/CODEX/2026-10-22/医院经营深度与人物行为升级/"
const SOURCE := "E:/CODEX/2026-10-22/医院长线经营扩展/outputs/deep40-prestock-final-01/checkpoints/long_05-tick000186156.json"
const SOURCE_SHA := "3e06c64b7f493e00f85c61ac2e7373daab786bae80f0774a69cfe7267b44124a"
var output := ""
var checks: Array = []
var observations: Dictionary = {}
var failed := 0
var catalog: ContentCatalog
var serial := 0

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=").replace("\\", "/")
	_run.call_deferred()

func check(ok: bool, label: String, detail: Variant = null) -> bool:
	checks.append({"ok": ok, "check": label, "detail": detail})
	if not ok: failed += 1
	print(("ACTOR OUTCOME PASS: " if ok else "ACTOR OUTCOME FAIL: ") + label)
	return ok

func issue(sim: Simulation, type: String, payload: Dictionary) -> Dictionary:
	serial += 1
	return sim.submit({"id": "actor_feedback_" + str(serial), "type": type, "payload": payload})

func actor_view(actor: Dictionary, snapshot: Dictionary) -> ActorView:
	var view := ActorView.new()
	view.entity_id = str(actor.id)
	view.appearance_seed = int(snapshot.get("appearance_seed", 0))
	view.presentation_tick = int(snapshot.tick)
	view.presentation_paused = bool(snapshot.paused)
	view.presentation_speed = int(snapshot.speed)
	root.add_child(view)
	view.present(actor, false)
	return view

func _run() -> void:
	if not output.begins_with(TASK_ROOT) or FileAccess.file_exists(output) or DirAccess.dir_exists_absolute(output.get_basename() + "-source"):
		push_error("Fresh T2 output and isolated source directory required"); quit(2); return
	if not check(FileAccess.get_sha256(SOURCE) == SOURCE_SHA, "queue source is the immutable actual full-run checkpoint"): finish(); return
	var loaded: Dictionary = ContentCatalog.load_checked("res://content")
	if not check(loaded.get("ok", false), "real current catalog loads"): finish(); return
	catalog = loaded.catalog
	var source_root: String = output.get_basename() + "-source"
	DirAccess.make_dir_recursive_absolute(source_root)
	var file := FileAccess.open(source_root.path_join("main.json"), FileAccess.WRITE)
	if file == null: check(false, "isolated source file opens"); finish(); return
	file.store_buffer(FileAccess.get_file_as_bytes(SOURCE)); file.close()
	var disk: Dictionary = SaveStore.load(source_root, catalog)
	if not check(disk.get("ok", false) and not disk.get("used_backup", true), "actual queue source strictly loads without fallback", disk.get("error", "")): finish(); return
	var sim := Simulation.new(catalog, disk.state)
	var original: Dictionary = sim.snapshot()
	var queue: Dictionary = original.patients.get("patient_232", {})
	if not check(queue.get("phase", "") == "care_queue" and queue.get("move_progress", -1) == 0 and queue.get("path_index", 0) + 1 < queue.get("path", []).size() and queue.get("queue_cell", -1) == 195, "actual queued body is at cell194 with one real route edge remaining"): finish(); return
	var view := actor_view(queue, original)
	observations.queue = {"tick": original.tick, "patient_id": queue.id, "cell": queue.cell, "path": queue.path, "path_index": queue.path_index, "move_progress": queue.move_progress, "rig_state": view._rig_state}
	check(view._route_active and view._rig_state == "Walk", "queue movement at an exact cell boundary keeps the walk presentation", observations.queue)
	check(not view.cure_feedback.visible, "waiting at a device is not a treatment result")
	view.free()
	var cured_id := ""
	for id: String in original.patients:
		if original.patients[id].phase == "left": cured_id = id; break
	if check(cured_id != "", "actual source retains a genuinely cured patient"):
		view = actor_view(original.patients[cured_id], original)
		check(view.cure_feedback.visible, "a genuine completed cure retains its existing success motif")
		view.free()
	check(sim.snapshot() == original, "showing queue and treatment outcome does not change clinical state")
	if not check(issue(sim, "set_intake", {"enabled": false}).get("ok", false), "public intake shutdown stops new patients"): finish(); return
	var patient_kinds: Dictionary = {}
	for id: String in original.campaign.live_patient_ids:
		for step: Dictionary in original.patients[id].steps:
			if step.kind == "patient": patient_kinds[step.facility_kind] = true
	var closed: Array = []
	var ids: Array = original.facilities.keys(); ids.sort()
	for id: String in ids:
		var facility: Dictionary = original.facilities[id]
		if not patient_kinds.has(facility.kind) or facility.get("busy_patient_id", "") != "": continue
		var active := false
		for order: Dictionary in original.work_orders.values():
			if order.facility_id == id and order.status in ["walking", "working"]: active = true; break
		if not active:
			var result: Dictionary = issue(sim, "close_facility", {"facility_id": id})
			if result.get("ok", false): closed.append(id)
	if not check(not closed.is_empty(), "normal commands close genuinely idle required clinical devices", closed): finish(); return
	if not check(issue(sim, "set_paused", {"paused": false}).get("ok", false), "public command resumes the real patience clock"): finish(); return
	var abandoned_id := ""
	var before_tick: int = int(sim.clock_state().tick)
	for _index: int in range(12000):
		sim.advance_ticks(1)
		# Observation only: avoid thousands of history copies while searching.
		# Model records never go to a renderer; the found state is snapshotted below.
		for id: String in sim._state.data.campaign.live_patient_ids:
			var patient: Dictionary = sim._state.data.patients[id]
			if patient.phase == "moving_exit" and patient.outcome == "abandoned": abandoned_id = id; break
		if abandoned_id != "" or sim.clock_state().paused: break
	if check(abandoned_id != "", "public device closure reaches a real patience abandonment before exit"):
		var abandoned_snapshot: Dictionary = sim.snapshot()
		var patient: Dictionary = abandoned_snapshot.patients[abandoned_id]
		view = actor_view(patient, abandoned_snapshot)
		observations.abandonment = {"started_tick": before_tick, "tick": abandoned_snapshot.tick, "patient_id": abandoned_id, "phase": patient.phase, "stage": patient.stage, "outcome": patient.outcome, "step_index": patient.step_index, "step_count": patient.steps.size(), "closed_facilities": closed, "cure_feedback_visible": view.cure_feedback.visible}
		check(not view.cure_feedback.visible, "actual abandoned exit never displays the green cure result", observations.abandonment)
		check(sim.snapshot() == abandoned_snapshot, "abandonment presentation cannot alter outcome, walking or accounts")
		view.free()
		var evidence := FileAccess.open(output.get_basename() + "-abandoned-actual.json", FileAccess.WRITE)
		if evidence != null: evidence.store_string(JSON.stringify(abandoned_snapshot, "  ")); evidence.close()
	finish()

func finish() -> void:
	check(FileAccess.get_sha256(SOURCE) == SOURCE_SHA, "original full-run checkpoint remains byte-for-byte unchanged")
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null: quit(2); return
	file.store_string(JSON.stringify({"passed": checks.size() - failed, "failed": failed, "checks": checks, "observations": observations, "source": SOURCE, "source_sha256": SOURCE_SHA, "scope": "Actual strict checkpoint, public intake/close/resume commands and real patience ticks. Existing actor art and presentation only; no patient/status/money/time injection and no engine performance claim."}, "  "))
	file.close()
	print("ACTOR OUTCOME RESULT: passed=%d failed=%d" % [checks.size() - failed, failed])
	quit(1 if failed else 0)
