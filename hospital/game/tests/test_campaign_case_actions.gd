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
	var reservation: Dictionary = Paths.reserve(output, "case-actions-layout")
	if not reservation.get("ok", false):
		printerr("CASE ACTIONS PATH ERROR: " + str(reservation.get("code", "unknown"))); quit(2); return
	paths = reservation.paths
	_run.call_deferred()

func check(ok: bool, label: String, detail: Variant = null) -> bool:
	checks.append({"ok": ok, "check": label, "detail": detail})
	if ok: passed += 1
	else: failed += 1
	print(("CASE ACTIONS PASS: " if ok else "CASE ACTIONS FAIL: ") + label)
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

func case_actions_in_tree(panel: CampaignHospitalPanel) -> Array:
	var actions: Array = []
	for node: Node in panel.find_children("*", "Button", true, false):
		if node is Button and node.get_meta("case_action", false): actions.append(node)
	return actions

func audit_case_layout(tag: String, compact: bool, safe: Rect2) -> void:
	var panel: CampaignHospitalPanel = host.hud.campaign_panel
	await frames(6)
	check(panel.visible and panel.section == "cases", tag + " is the actual visible cases page")
	check(panel.is_full_page() == compact, tag + " uses actual viewport compact classification")
	check(panel.footer.visible == (not compact), tag + " fixed footer visibility matches display mode")
	var clip: Rect2 = panel.scroll.get_global_rect()
	check(clip.size.y >= 48, tag + " scroll retains room for a complete48-high touch target", rect_data(clip))
	var keys: Array[String] = ["set_intake", "advance_stage", "show_patients"]
	var actions: Array = case_actions_in_tree(panel)
	check(actions.size() == 3, tag + " actual tree contains exactly three case-action buttons", actions.size())
	var identities: Dictionary = {}
	var rows: Dictionary = {}
	for key: String in keys:
		if not check(panel.controls.has(key), tag + " exposes necessary " + key): continue
		var button: Button = panel.controls[key]
		identities[button.get_instance_id()] = true
		check(button.get_meta("case_action", false) and button in actions, tag + " registered action is the actual tree button " + key)
		check(button.get_parent() == (panel.body if compact else panel.footer), tag + " action parent is scroll body on phone or footer on desktop " + key)
		if compact:
			panel.scroll.ensure_control_visible(button)
			await frames()
		var area: Rect2 = button.get_global_rect()
		rows[key] = {"rect": rect_data(area), "parent": str(button.get_parent().get_path()), "disabled": button.disabled}
		check(button.is_visible_in_tree() and area.size.y >= 48, tag + " action remains visible with full touch height " + key)
		check(safe.encloses(area), tag + " whole necessary action stays in exact display safe rect " + key, rect_data(area))
		if compact:
			check(panel.scroll.get_global_rect().encloses(area), tag + " whole action is inside actual scroll clip after reveal " + key, {"button": rect_data(area), "clip": rect_data(panel.scroll.get_global_rect())})
		else:
			check(panel.footer.get_global_rect().encloses(area), tag + " whole action fits fixed desktop footer " + key)
	check(identities.size() == 3, tag + " all necessary controls are distinct instances without duplicates")
	observations[tag] = {"actions": rows, "tree_action_count": actions.size(), "scroll": rect_data(panel.scroll.get_global_rect()), "footer_visible": panel.footer.visible}

func phone_list_roundtrip(tag: String) -> void:
	var panel: CampaignHospitalPanel = host.hud.campaign_panel
	if not check(panel.controls.has("show_patients"), tag + " actual list-navigation action exists"): return
	await tap(panel.controls.show_patients, panel.scroll)
	check(panel.visible and panel.section == "patients", tag + " real ScreenTouch reaches patients without a business command")
	check(case_actions_in_tree(panel).is_empty(), tag + " patients page contains no leftover case-action buttons")
	if not check(panel.controls.has("section_cases"), tag + " permanent cases tab still exists"): return
	await tap(panel.controls.section_cases)
	check(panel.visible and panel.section == "cases", tag + " real ScreenTouch returns to cases page")
	await frames()

func _run() -> void:
	root.size = Vector2i(932, 430)
	var phone: Rect2 = Rect2(59, 0, 814, 409)
	var desktop: Rect2 = Rect2(0, 0, 1280, 720)
	var loaded: Dictionary = ContentCatalog.load_checked("res://content")
	if not check(loaded.get("ok", false), "real content loads"): await finish(); return
	catalog = loaded.catalog
	var save_root: String = paths.fixture("case-actions-layout")
	if not check(save_root != "", "isolated public-session save directory"): await finish(); return
	session = GameSession.new(catalog, save_root)
	if not check(session.start_level("long_01").get("ok", false), "new formal hospital starts by public session"): await finish(); return
	host = load("res://main.gd").new()
	host.session = session
	root.add_child(host)
	await frames()
	host.hud.configure_display(Vector2(932, 430), Vector2(932, 430), 160, phone)
	host.hud.flow.close(); session.dismiss_notice()
	var before: Dictionary = session.sim.snapshot()
	host.hud._show_campaign("cases")
	await audit_case_layout("phone_initial", true, phone)
	await capture("01-phone-case-actions.png")
	await phone_list_roundtrip("phone_first_roundtrip")
	await audit_case_layout("phone_after_roundtrip", true, phone)
	# Resize the still-open actual page; no show_section here can hide a stale
	# reparenting defect by rebuilding the controls before the audit.
	root.size = Vector2i(1280, 720)
	await frames()
	host.hud.configure_display(Vector2(1280, 720), Vector2(1280, 720), 160, desktop)
	await audit_case_layout("desktop_reparent", false, desktop)
	root.size = Vector2i(932, 430)
	await frames()
	host.hud.configure_display(Vector2(932, 430), Vector2(932, 430), 160, phone)
	await audit_case_layout("phone_reparent_back", true, phone)
	await phone_list_roundtrip("phone_final_roundtrip")
	await audit_case_layout("phone_final", true, phone)
	await capture("02-phone-case-actions-after-resizes.png")
	# Main opens the real newly saved profile and records its legitimate pause.
	# Layout must preserve that baseline, rather than pretend it never happened.
	var baseline_pause_only: bool = not before.command_receipts.is_empty()
	for receipt: Dictionary in before.command_receipts.values():
		var command: Dictionary = receipt.data.command
		baseline_pause_only = baseline_pause_only and command.type == "set_paused" and command.payload.get("paused", false) == true
	check(baseline_pause_only, "normal saved-profile startup has only legitimate pause receipts before layout")
	check(session.sim.snapshot() == before, "layout reparent and actual navigation add no commands or model changes to the real baseline")
	check(SnapshotValidator.validate(session.sim.snapshot(), catalog) == "", "final formal hospital strictly validates")
	await finish()

func finish() -> void:
	if host != null: host.free(); host = null
	await create_timer(0.24).timeout
	if paths.write_report({"passed": passed, "failed": failed, "checks": checks, "observations": observations, "captures": captures, "scope": "Actual Main/HUD pure GUI layout probe. Real new formal session, paused empty hospital; no clinical fixture, no business commands, no physical iPhone or human-fun acceptance. Phone case-actions full rectangles within actual scroll/safe bounds, real list/tab touch roundtrips, phone-desktop-phone reparent on still-open page."}) != OK:
		printerr("CASE ACTIONS PATH ERROR: report write failed"); quit(2); return
	print("CASE ACTIONS RESULT: passed=%d failed=%d" % [passed, failed])
	quit(1 if failed > 0 else 0)
