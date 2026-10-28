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
	var reservation: Dictionary = Paths.reserve(output, "clinical-policy-apply")
	if not reservation.get("ok", false):
		printerr("POLICY APPLY PATH ERROR: " + str(reservation.get("code", "unknown"))); quit(2); return
	paths = reservation.paths
	_run.call_deferred()

func check(ok: bool, label: String, detail: Variant = null) -> bool:
	checks.append({"ok": ok, "check": label, "detail": detail})
	if ok: passed += 1
	else: failed += 1
	print(("POLICY APPLY PASS: " if ok else "POLICY APPLY FAIL: ") + label)
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

func drive_until(predicate: Callable, limit: int, label: String) -> bool:
	for _n: int in range(limit):
		if predicate.call(session.sim.snapshot()): break
		session.sim.advance_ticks(1)
	var current: Dictionary = session.sim.snapshot()
	check(SnapshotValidator.validate(current, catalog) == "", label + " strict real state", SnapshotValidator.validate(current, catalog))
	return check(bool(predicate.call(current)), label + " reached in bounded fixed steps")

func choose_policy(panel: CampaignHospitalPanel, wanted: String) -> bool:
	var option: OptionButton = panel.controls.get("clinical_policy")
	if not check(option != null, "existing real policy OptionButton is present"): return false
	var index: int = -1
	for n: int in range(option.item_count):
		if str(option.get_item_metadata(n)) == wanted: index = n; break
	if not check(index >= 0, "existing real policy choice contains " + wanted): return false
	# Selection invokes the real OptionButton callback. Navigation and apply use
	# actual ScreenTouch. This is not claimed as physical menu-touch validation.
	option.select(index)
	option.item_selected.emit(index)
	await frames()
	return true

func all_decisions_from(patient: Dictionary, expected_source: String) -> bool:
	var rows: Array = patient.clinical_decision.receipts
	if rows.is_empty(): return false
	for row: Dictionary in rows:
		if row.source != expected_source: return false
	return true

func _run() -> void:
	root.size = Vector2i(932, 430)
	var loaded: Dictionary = ContentCatalog.load_checked("res://content")
	if not check(loaded.get("ok", false), "real content loads"): await finish(); return
	catalog = loaded.catalog
	var save_root: String = paths.fixture("policy-apply")
	if not check(save_root != "", "isolated formal save directory"): await finish(); return
	session = GameSession.new(catalog, save_root)
	if not check(session.start_level("long_01").get("ok", false), "formal hospital starts through public session"): await finish(); return
	host = load("res://main.gd").new()
	host.session = session
	root.add_child(host)
	await frames()
	host.hud.configure_display(Vector2(932, 430), Vector2(932, 430), 160, Rect2(59, 0, 814, 409))
	host.hud.flow.close(); session.dismiss_notice()
	check(session.sim.snapshot().campaign.clinical_policy == "manual" and policy_count(session.sim.snapshot()) == 0, "first teaching starts manual without silent policy command")
	for row: Array in [["U04-E1", 25], ["O01", 33], ["O15", 40], ["U04-E2", 129]]:
		if not build(str(row[0]), int(row[1])): await finish(); return
	var delivery: Dictionary = issue("run_operation", {"facility_kind": "O15"})
	if not delivery.get("ok", false): await finish(); return
	issue("set_paused", {"paused": false})
	if not drive_until(func(d: Dictionary) -> bool: return d.work_orders[delivery.data.work_order_id].status == "done", 1200, "actual first delivery"): await finish(); return
	var first_admission: Dictionary = issue("admit_routine", {"case_id": "U04-C2"})
	if not first_admission.get("ok", false): await finish(); return
	var first_id: String = str(first_admission.data.patient_ids[0])
	for action: String in ["continue_exam", "cautious_treat"]:
		if not drive_until(func(d: Dictionary) -> bool: return CampaignClinicalDecisions.preview(d, catalog, first_id).get("pending", false), 1800, "first patient manual " + action): await finish(); return
		var decision: Dictionary = CampaignClinicalDecisions.preview(session.sim.snapshot(), catalog, first_id)
		if not issue("clinical_decision", {"patient_id": first_id, "action": action, "expected_revision": int(decision.revision)}).get("ok", false): await finish(); return
	if not drive_until(func(d: Dictionary) -> bool: return d.patients[first_id].phase == "left", 1800, "teaching patient genuinely treated and exited"): await finish(); return
	issue("set_paused", {"paused": true})
	var taught: Dictionary = session.sim.snapshot()
	check(taught.campaign.clinical_policy == "manual" and policy_count(taught) == 0 and all_decisions_from(taught.patients[first_id], "manual"), "first teaching finishes with only explicit manual decisions and no delegation")
	check(taught.metrics.completed == 1 and taught.metrics.income == 240 and int(taught.resources.get("delivered", 0)) == 3, "first actual cure consumes three delivered and earns exact quoted fee")
	var second_admission: Dictionary = issue("admit_routine", {"case_id": "U04-C2"})
	if not second_admission.get("ok", false): await finish(); return
	var second_id: String = str(second_admission.data.patient_ids[0])
	issue("set_paused", {"paused": false})
	if not drive_until(func(d: Dictionary) -> bool: return CampaignClinicalDecisions.preview(d, catalog, second_id).get("pending", false), 1800, "subsequent actual patient reaches unapproved decision"): await finish(); return
	issue("set_paused", {"paused": true})
	var before_navigation: Dictionary = session.sim.snapshot()
	check(host.hud.show_campaign_patient(second_id), "actual HUD opens subsequent patient card")
	await frames()
	var card: CampaignPatientCard = host.hud.patient_card
	if not check(card.controls.has("clinical_policy"), "patient card has actual delegation entry"): await finish(); return
	await tap(card.controls.clinical_policy)
	var panel: CampaignHospitalPanel = host.hud.campaign_panel
	if not check(not card.visible and panel.visible and panel.section == "cases" and panel.controls.has("clinical_policy"), "real card touch navigates into existing cases policy form"): await finish(); return
	check(session.sim.snapshot() == before_navigation, "navigation cannot apply delegation or authorize current care")
	await capture("01-delegation-settings.png")
	var chose_balanced: bool = await choose_policy(panel, "balanced")
	if not chose_balanced: await finish(); return
	check(session.sim.snapshot() == before_navigation, "choosing balanced is only an unapplied UI draft")
	if not check(panel.controls.has("set_clinical_policy"), "real explicit apply button exists"): await finish(); return
	await tap(panel.controls.set_clinical_policy, panel.scroll)
	var applied: Dictionary = session.sim.snapshot()
	if not check(applied.campaign.clinical_policy == "balanced" and policy_count(applied) == 1 and applied.command_sequence == before_navigation.command_sequence + 1, "one explicit apply touch submits exactly one public set_clinical_policy"): await finish(); return
	var policy_receipt: Dictionary = {}
	for receipt: Dictionary in applied.command_receipts.values():
		if receipt.data.command.type == "set_clinical_policy": policy_receipt = receipt.data
	check(policy_receipt.get("command", {}).get("payload", {}).get("policy", "") == "balanced", "unique public command contains the selected balanced policy")
	check(applied.tick == before_navigation.tick and applied.paused and applied.cash == before_navigation.cash and applied.resources == before_navigation.resources and applied.patients == before_navigation.patients, "applying while paused cannot spend clinical stock fee or settle a patient")
	var manual_commands: int = 0
	for receipt: Dictionary in applied.command_receipts.values():
		if receipt.data.command.type == "clinical_decision": manual_commands += 1
	issue("set_paused", {"paused": false})
	if not drive_until(func(d: Dictionary) -> bool: return d.patients[second_id].phase == "left", 2600, "delegated subsequent patient genuinely examines treats and exits"): await finish(); return
	issue("set_paused", {"paused": true})
	var cured: Dictionary = session.sim.snapshot()
	var patient: Dictionary = cured.patients[second_id]
	check(patient.outcome == "completed" and all_decisions_from(patient, "policy") and patient.clinical_decision.receipts.size() == 2, "subsequent diagnosis decisions are actual source=policy receipts")
	var after_manual_commands: int = 0
	for receipt: Dictionary in cured.command_receipts.values():
		if receipt.data.command.type == "clinical_decision": after_manual_commands += 1
	check(after_manual_commands == manual_commands, "delegation requires no hidden or scripted per-patient public decision commands")
	var clinical_cost: int = 0
	var delivered: int = 0
	var real_timing: bool = true
	var matching_debits: bool = true
	for history: Dictionary in patient.step_history:
		clinical_cost += int(history.cost)
		if history.resource == "delivered": delivered += int(history.quantity)
		if int(history.started_tick) < 0 or int(history.completed_tick) - int(history.started_tick) < int(history.effective_duration): real_timing = false
		var found: bool = false
		for ledger: Dictionary in cured.ledger_entries:
			if ledger.category == "treatment_cost" and ledger.reference == "care:" + second_id + ":" + str(history.step_id) and int(ledger.amount) == -int(history.cost) and int(ledger.tick) == int(history.started_tick): found = true; break
		if not found: matching_debits = false
	check(real_timing and patient.step_history.size() == 4, "automatic patient contains real completed registration exam repeat and therapy durations")
	check(clinical_cost == 42 and matching_debits, "all automatic services contain exact real paid clinical ledger debits")
	check(delivered == 3 and int(taught.resources.delivered) - int(cured.resources.delivered) == 3, "automatic patient consumes exactly three actually delivered supplies")
	var income_count: int = 0
	for entry: Dictionary in cured.ledger_entries:
		if entry.category == "income" and entry.reference == "income:" + second_id and int(entry.amount) == 240 and int(entry.tick) == int(patient.completed_tick): income_count += 1
	check(income_count == 1 and cured.metrics.completed == 2 and cured.metrics.income == 480 and cured.campaign.completed_cases.is_empty(), "actual exit pays exactly once without inventing signature progress")
	if capture_requested and DisplayServer.get_name() != "headless":
		host.hud.show_campaign_patient(second_id)
		await capture("02-automatic-patient-completed.png")
	host.hud._show_campaign("patients")
	await frames()
	panel = host.hud.campaign_panel
	if not check(panel.controls.has("clinical_policy_entry"), "patient list retains real delegation/settings navigation"): await finish(); return
	var before_list: Dictionary = session.sim.snapshot()
	await tap(panel.controls.clinical_policy_entry, panel.scroll)
	if not check(panel.visible and panel.section == "cases" and panel.controls.has("clinical_policy"), "actual patient-list touch reaches same policy form"): await finish(); return
	check(session.sim.snapshot() == before_list, "list navigation does not change balanced model policy")
	var chose_manual: bool = await choose_policy(panel, "manual")
	if not chose_manual: await finish(); return
	check(session.sim.snapshot() == before_list, "choosing manual remains a draft until applied")
	await tap(panel.controls.set_clinical_policy, panel.scroll)
	var manual_again: Dictionary = session.sim.snapshot()
	check(manual_again.campaign.clinical_policy == "manual" and policy_count(manual_again) == 2 and manual_again.command_sequence == before_list.command_sequence + 1, "player can explicitly restore manual with one further public command")
	var more_stock: Dictionary = issue("run_operation", {"facility_kind": "O15"})
	if not more_stock.get("ok", false): await finish(); return
	issue("set_paused", {"paused": false})
	if not drive_until(func(d: Dictionary) -> bool: return d.work_orders[more_stock.data.work_order_id].status == "done", 1200, "paid second delivery replenishes stock normally"): await finish(); return
	var third_admission: Dictionary = issue("admit_routine", {"case_id": "U04-C2"})
	if not third_admission.get("ok", false): await finish(); return
	var third_id: String = str(third_admission.data.patient_ids[0])
	if not drive_until(func(d: Dictionary) -> bool: return CampaignClinicalDecisions.preview(d, catalog, third_id).get("pending", false), 1800, "restored manual strategy genuinely holds next patient's decision"): await finish(); return
	var pending: Dictionary = session.sim.snapshot()
	session.sim.advance_ticks(30)
	var still_manual: Dictionary = session.sim.snapshot()
	check(still_manual.tick == pending.tick + 30 and CampaignClinicalDecisions.preview(still_manual, catalog, third_id).get("pending", false) and still_manual.patients[third_id].clinical_decision.receipts.is_empty() and still_manual.metrics.completed == 2, "real further ticks cannot silently re-enable policy treatment after manual restoration")
	issue("set_paused", {"paused": true})
	if capture_requested and DisplayServer.get_name() != "headless":
		host.hud.show_campaign_patient(third_id)
		await capture("03-manual-restored.png")
	observations = {"first_manual_patient": first_id, "second_policy_patient": second_id, "third_manual_pending_patient": third_id, "policy_commands": policy_count(session.sim.snapshot()), "actual_main_process_enabled": host.is_processing(), "automatic_patient_cost": clinical_cost, "automatic_patient_delivered": delivered, "automatic_patient_income": 240}
	check(SnapshotValidator.validate(session.sim.snapshot(), catalog) == "", "final mixed manual-policy-manual hospital strictly validates", SnapshotValidator.validate(session.sim.snapshot(), catalog))
	await finish()

func finish() -> void:
	if host != null: host.free(); host = null
	await create_timer(0.24).timeout
	if paths.write_report({"passed": passed, "failed": failed, "checks": checks, "observations": observations, "captures": captures, "scope": "Actual Main/HUD; paid public-command formal hospital fixture and actual ScreenTouch navigation. Model paused for navigation and explicit policy application; clinical care advances through actual fixed simulation steps. OptionButton choice uses its real item_selected callback; navigation and apply use ScreenTouch. Not human enjoyment, full campaign, real-time economy or physical iPhone acceptance."}) != OK:
		printerr("POLICY APPLY PATH ERROR: report write failed"); quit(2); return
	print("POLICY APPLY RESULT: passed=%d failed=%d" % [passed, failed])
	quit(1 if failed > 0 else 0)
