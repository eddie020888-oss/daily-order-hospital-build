extends SceneTree

# Actual Main/HUD and a public-command formal patient fixture. This is an
# integration diagnostic, not a normal-player enjoyment or physical-phone test.
const Paths = preload("res://tests/support/gameplay_review_paths.gd")
const TASK: String = "E:/CODEX/2026-10-28/医院逻辑与游戏性复审"
var paths: Variant
var session: GameSession
var host: Variant
var catalog: ContentCatalog
var passed: int = 0
var failed: int = 0
var checks: Array = []
var observations: Dictionary = {}
var pointer: int = 0
var capture_requested: bool = false
var captures: Array = []

func _initialize() -> void:
	var output: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=").replace("\\", "/")
		elif arg == "--capture": capture_requested = true
	var reservation: Dictionary = Paths.reserve(output, "patient-card-geometry")
	if not reservation.get("ok", false):
		printerr("CARD GEOMETRY PATH ERROR: " + str(reservation.get("code", "unknown"))); quit(2); return
	paths = reservation.paths
	_run.call_deferred()

func check(ok: bool, label: String, detail: Variant = null) -> bool:
	checks.append({"ok": ok, "check": label, "detail": detail})
	if ok: passed += 1
	else: failed += 1
	print(("CARD GEOMETRY PASS: " if ok else "CARD GEOMETRY FAIL: ") + label)
	return ok

func issue(type: String, payload: Dictionary = {}) -> Dictionary:
	var result: Dictionary = session.issue(type, payload)
	check(result.get("ok", false), "public fixture command " + type, result.get("code", ""))
	return result

func build(kind: String, cell: int) -> bool:
	var definition: Dictionary = catalog.campaign.facilities[kind]
	var result: Dictionary = issue("build_department", {"unit_id": definition.unit_id, "origin_cell": cell, "layout": FacilityLayout.default_layout(definition.unit_id, kind, 0)})
	if not result.get("ok", false): return false
	var fid: String = str(result.data.facility_ids[0])
	for role: String in definition.roles:
		var hired: Dictionary = issue("hire", {"role": role})
		if not hired.get("ok", false): return false
		if not issue("assign", {"staff_id": hired.data.staff_id, "facility_id": fid}).get("ok", false): return false
	return true

func frames(count: int = 4) -> void:
	for _n: int in range(count): await process_frame

func tap(button: Button, scroll: ScrollContainer = null) -> bool:
	if button == null or not is_instance_valid(button) or not button.is_visible_in_tree() or button.disabled:
		check(false, "actual touch target is visible and enabled"); return false
	if scroll != null and scroll.is_ancestor_of(button):
		scroll.ensure_control_visible(button)
		await frames()
	var point: Vector2 = button.get_global_rect().get_center()
	if not check(Rect2(Vector2.ZERO, Vector2(root.size)).has_point(point), "touch target center stays in actual viewport", point): return false
	var down := InputEventScreenTouch.new()
	down.index = pointer; down.pressed = true; down.position = point
	Input.parse_input_event(down)
	await process_frame
	var up := InputEventScreenTouch.new()
	up.index = pointer; up.pressed = false; up.position = point
	Input.parse_input_event(up)
	await frames()
	pointer += 1
	return true

func policy_count(snapshot: Dictionary) -> int:
	var count: int = 0
	for receipt: Dictionary in snapshot.command_receipts.values():
		if receipt.data.command.type == "set_clinical_policy": count += 1
	return count

func capture(name: String) -> void:
	if not capture_requested or DisplayServer.get_name() == "headless": return
	await frames()
	await RenderingServer.frame_post_draw
	var destination: String = paths.run_root.path_join(name)
	if not check(not FileAccess.file_exists(destination), "native capture path is fresh"): return
	var frame: Image = root.get_texture().get_image()
	var error: Error = frame.save_png(destination)
	check(error == OK, "actual rendered viewport capture " + name, error)
	if error == OK: captures.append(destination)

func rect_data(value: Rect2) -> Array:
	return [value.position.x, value.position.y, value.size.x, value.size.y]

func _run() -> void:
	root.size = Vector2i(932, 430)
	var safe: Rect2 = Rect2(59, 0, 814, 409)
	var viewport_bounds: Rect2 = Rect2(Vector2.ZERO, Vector2(root.size))
	var loaded: Dictionary = ContentCatalog.load_checked("res://content")
	if not check(loaded.get("ok", false), "real content loads"): await finish(); return
	catalog = loaded.catalog
	var save_root: String = paths.fixture("card-geometry")
	if not check(save_root != "", "isolated formal save directory"): await finish(); return
	session = GameSession.new(catalog, save_root)
	if not check(session.start_level("long_01").get("ok", false), "formal hospital starts through public session"): await finish(); return
	host = load("res://main.gd").new()
	host.session = session
	root.add_child(host)
	await frames()
	host.hud.configure_display(Vector2(932, 430), Vector2(932, 430), 160, safe)
	host.hud.flow.close(); session.dismiss_notice()
	# A staffed O05 is the real admission outlet; authored U04-E2 is absent,
	# so a pending real patient must expose Prepare Therapy alongside both
	# navigation actions. No detached display dictionary manufactures this state.
	for row: Array in [["U04-E1", 25], ["O01", 33], ["O15", 40], ["O05", 125]]:
		if not build(str(row[0]), int(row[1])): await finish(); return
	var delivery: Dictionary = issue("run_operation", {"facility_kind": "O15"})
	if not delivery.get("ok", false): await finish(); return
	issue("set_paused", {"paused": false})
	for _n: int in range(1200):
		if session.sim.snapshot().work_orders[delivery.data.work_order_id].status == "done": break
		session.sim.advance_ticks(1)
	if not check(session.sim.snapshot().work_orders[delivery.data.work_order_id].status == "done", "real paid delivery prepares actual stock"): await finish(); return
	var admission: Dictionary = issue("admit_routine", {"case_id": "U04-C2"})
	if not admission.get("ok", false): await finish(); return
	var pid: String = str(admission.data.patient_ids[0])
	for _n: int in range(1800):
		if CampaignClinicalDecisions.preview(session.sim.snapshot(), catalog, pid).get("pending", false): break
		session.sim.advance_ticks(1)
	issue("set_paused", {"paused": true})
	var before: Dictionary = session.sim.snapshot()
	if not check(CampaignClinicalDecisions.preview(before, catalog, pid).get("pending", false), "actual first examination reaches a manual decision"): await finish(); return
	check(host.hud.show_campaign_patient(pid), "actual Main HUD opens the real patient card")
	await frames(8)
	var card: CampaignPatientCard = host.hud.patient_card
	var card_bounds: Rect2 = card.get_global_rect()
	var content_bounds: Rect2 = host.hud._campaign_build_bounds()
	check(safe.encloses(card_bounds), "whole patient card stays inside exact phone safe rect", rect_data(card_bounds))
	check(viewport_bounds.encloses(card_bounds), "whole patient card stays inside viewport")
	check(content_bounds.encloses(card_bounds), "whole card avoids actual header and dock content exclusion", {"card": rect_data(card_bounds), "content": rect_data(content_bounds)})
	var keys: Array[String] = ["prepare_treatment", "all_patients", "clinical_policy"]
	var rectangles: Array[Rect2] = []
	var geometry: Dictionary = {}
	for key: String in keys:
		if not check(card.controls.has(key), "actual footer has " + key): continue
		var button: Button = card.controls[key]
		if not check(button.is_visible_in_tree(), key + " is actually visible"): continue
		var bounds: Rect2 = button.get_global_rect()
		rectangles.append(bounds)
		geometry[key] = {"rect": rect_data(bounds), "label": button.text, "disabled": button.disabled, "minimum_size": [button.get_combined_minimum_size().x, button.get_combined_minimum_size().y]}
		check(not button.disabled, key + " is a real enabled action")
		check(bounds.size.y >= 48 and bounds.size.x >= 48, key + " full hit target is at least48 in both dimensions", rect_data(bounds))
		check(card_bounds.encloses(bounds), key + " entire target fits inside Card rather than center only", rect_data(bounds))
		check(safe.encloses(bounds), key + " entire target fits inside exact phone safe rect", rect_data(bounds))
		check(viewport_bounds.encloses(bounds), key + " entire target fits inside viewport", rect_data(bounds))
	check(rectangles.size() == 3, "all three footer actions are measured in the same real frame")
	for first: int in range(rectangles.size()):
		for second: int in range(first + 1, rectangles.size()):
			check(not rectangles[first].intersects(rectangles[second]), "visible footer targets do not overlap " + str(first) + ":" + str(second), {"first": rect_data(rectangles[first]), "second": rect_data(rectangles[second])})
	var scroll: ScrollContainer = card.get("_scroll")
	if check(scroll != null, "only body has actual local scroll"):
		scroll.scroll_vertical = 999
		await frames()
		for key: String in keys:
			if not geometry.has(key): continue
			var button: Button = card.controls[key]
			var original: Array = geometry[key].rect
			var expected: Rect2 = Rect2(float(original[0]), float(original[1]), float(original[2]), float(original[3]))
			check(button.get_global_rect().is_equal_approx(expected) and button.is_visible_in_tree(), key + " stays fixed and visible when body scrolls")
	check(session.sim.snapshot() == before, "geometry layout and body scroll cannot alter strategy patient stock cash or tick")
	check(SnapshotValidator.validate(before, catalog) == "", "actual geometry fixture remains strictly save valid", SnapshotValidator.validate(before, catalog))
	observations = {"viewport": rect_data(viewport_bounds), "safe": rect_data(safe), "card": rect_data(card_bounds), "actual_content_bounds": rect_data(content_bounds), "buttons": geometry, "patient_id": pid, "clinical_policy": before.campaign.clinical_policy, "first_patient_has_no_authorizations": before.patients[pid].clinical_decision.receipts.is_empty(), "actual_main_process_enabled": host.is_processing()}
	await capture("01-patient-card-three-actions.png")
	await finish()

func finish() -> void:
	if host != null: host.free(); host = null
	await create_timer(0.24).timeout
	if paths.write_report({"passed": passed, "failed": failed, "checks": checks, "observations": observations, "captures": captures, "scope": "Actual Main at932x430 and safeRect59,0,814,409. Real public-command formal patient fixture missing authored therapy with staffed referral outlet; all three actual Card footer buttons simultaneously visible. Full rectangles measured, no center-only geometry assertion. Model paused for layout comparison; no human enjoyment, full-campaign, real-time balance or physical iPhone acceptance."}) != OK:
		printerr("CARD GEOMETRY PATH ERROR: report write failed"); quit(2); return
	print("CARD GEOMETRY RESULT: passed=%d failed=%d" % [passed, failed])
	quit(1 if failed > 0 else 0)
