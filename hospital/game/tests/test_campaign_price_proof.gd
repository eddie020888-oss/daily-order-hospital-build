extends SceneTree

# The normal-play baseline is an actual public-case SaveStore file. Only a
# deep copy is corrupted; the file and all clinical history remain intact.
var output: String = ""
var source_save: String = ""
var passed: int = 0
var failed: int = 0
var checks: Array = []
var catalog: ContentCatalog
var source_sha256: String = ""
var command_sequence: int = 0
var mutation: Dictionary = {}

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=").replace("\\", "/")
		if argument.begins_with("--source-save="): source_save = argument.trim_prefix("--source-save=").replace("\\", "/")
	_run.call_deferred()

func check(ok: bool, label: String, detail: String = "") -> void:
	checks.append({"ok":ok,"check":label,"detail":detail})
	if ok: passed += 1
	else: failed += 1
	print(("CAMPAIGN PRICE PASS: " if ok else "CAMPAIGN PRICE FAIL: ") + label + (": " + detail if detail != "" else ""))

func finish() -> void:
	if source_sha256 != "": check(FileAccess.get_sha256(source_save) == source_sha256, "original public save bytes remain unchanged")
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	var file: FileAccess = FileAccess.open(output,FileAccess.WRITE)
	if file == null: quit(2); return
	file.store_string(JSON.stringify({"passed":passed,"failed":failed,"checks":checks,"source_save":source_save,"source_sha256":source_sha256,"mutation":mutation,"scope":"Real public finished-case save, balanced corrupted copy only, and independently paid public admission at a changed price. No clinical-state injection or production writes."},"  "))
	print("CAMPAIGN PRICE RESULT: passed=%d failed=%d" % [passed,failed])
	quit(1 if failed > 0 else 0)

func submit(sim: Simulation, type: String, payload: Dictionary) -> Dictionary:
	command_sequence += 1
	var result: Dictionary = sim.submit({"id":"price_proof_%03d" % command_sequence,"type":type,"payload":payload})
	check(result.get("ok",false), "public " + type, str(result.get("code","")))
	return result

func prepare_facility(sim: Simulation, kind: String, origin: int) -> bool:
	var definition: Dictionary = catalog.campaign.facilities[kind]
	var unit: String = definition.unit_id
	var built: Dictionary = submit(sim,"build_department",{"unit_id":unit,"origin_cell":origin,"layout":FacilityLayout.default_layout(unit,kind,0)})
	if not built.get("ok",false): return false
	for role: String in definition.roles:
		var hired: Dictionary = submit(sim,"hire",{"role":role})
		if not hired.get("ok",false): return false
		if not submit(sim,"assign",{"staff_id":hired.data.staff_id,"facility_id":built.data.facility_ids[0]}).get("ok",false): return false
	return true

func actual_new_price_admission() -> void:
	var state: ClinicState = CampaignState.create("career_01",catalog)
	var sim: Simulation = Simulation.new(catalog,state)
	if not prepare_facility(sim,"O01",25): return
	if not prepare_facility(sim,"U01-E1",30): return
	if not prepare_facility(sim,"O15",35): return
	var delivery: Dictionary = submit(sim,"run_operation",{"facility_kind":"O15"})
	if not delivery.get("ok",false): return
	if not submit(sim,"set_paused",{"paused":false}).get("ok",false): return
	var order_id: String = delivery.data.work_order_id
	for _n: int in range(2000):
		sim.advance_ticks(1)
		if sim.snapshot().work_orders[order_id].status == "done": break
	var prepared: Dictionary = sim.snapshot()
	var delivered: bool = prepared.work_orders[order_id].status == "done" and prepared.resources.get("delivered",0) > 0
	check(delivered, "real paid O15 work order supplies the future patient's delivery stock")
	if not delivered: return
	check(CampaignValidator.validate(prepared,catalog) == "", "actual intake and delivery preparation is save-valid", CampaignValidator.validate(prepared,catalog))
	if not submit(sim,"set_paused",{"paused":true}).get("ok",false): return
	if not submit(sim,"set_price",{"percent":101}).get("ok",false): return
	if not submit(sim,"accept_case",{"case_id":"U01-C1"}).get("ok",false): return
	var admitted: Dictionary = sim.snapshot()
	var expected: int = int(int(catalog.campaign.cases["U01-C1"].income)*101/100)
	check(admitted.patients.patient_001.income == expected, "real admission latches the public 101 percent price")
	check(CampaignValidator.validate(admitted,catalog) == "", "genuine priced admission is save-valid", CampaignValidator.validate(admitted,catalog))
	if not submit(sim,"set_price",{"percent":115}).get("ok",false): return
	var repriced: Dictionary = sim.snapshot()
	check(repriced.tick == admitted.tick and repriced.patients.patient_001.income == expected and repriced.campaign.price_percent == 115, "later same-tick price command preserves the admitted patient's quote")
	check(CampaignValidator.validate(repriced,catalog) == "", "receipt sequence distinguishes before-admission and after-admission prices", CampaignValidator.validate(repriced,catalog))

func _run() -> void:
	var task: String = "E:/CODEX/2026-10-22/医院全设施病例任务贯通/"
	if not output.begins_with(task) or output.simplify_path() != output or FileAccess.file_exists(output) or not source_save.begins_with(task) or source_save.simplify_path() != source_save or not FileAccess.file_exists(source_save):
		printerr("Require --source-save=<actual task save> and fresh --output=<task report>"); quit(2); return
	source_sha256 = FileAccess.get_sha256(source_save)
	var loaded: Dictionary = ContentCatalog.load_checked("res://content")
	check(loaded.get("ok",false), "actual campaign catalog loads", loaded.get("error",""))
	if not loaded.get("ok",false): finish(); return
	catalog = loaded.catalog
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(source_save))
	if not parsed is Dictionary: check(false,"actual source save is a JSON object"); finish(); return
	var normalized: Dictionary = ContentCatalog._normalize(parsed)
	check(normalized.get("ok",false), "actual source normalizes integer JSON losslessly")
	if not normalized.get("ok",false): finish(); return
	var base: Dictionary = normalized.value
	var original: Dictionary = base.duplicate(true)
	var error: String = CampaignValidator.validate(base,catalog)
	check(error == "" and base == original, "original real finished-case save passes without repair", error)
	if error != "": finish(); return
	var target: String = "patient_001"
	var ready: bool = base.patients.has(target) and base.patients[target].phase == "left" and base.patients[target].case_id == "U01-C1" and base.campaign.price_percent == 100 and base.challenge.status == "running"
	for receipt: Dictionary in base.command_receipts.values():
		if receipt.data.command.type == "set_price": ready = false
	check(ready, "source genuinely completed first case at the unchanged default 100 percent price")
	if not ready: finish(); return
	var no_call_job: bool = true
	for order: Dictionary in base.work_orders.values():
		if order.status == "done" and order.handler in ["call","referral"]: no_call_job = false
	check(no_call_job, "actual first-case source has no completed queue-call job")
	if no_call_job:
		var fake_call: Dictionary = base.duplicate(true)
		fake_call.patients[target].called_until = base.tick+600
		var before_call_check: Dictionary = fake_call.duplicate(true)
		var call_error: String = CampaignValidator.validate(fake_call,catalog)
		check(call_error != "" and fake_call == before_call_check, "actual patient cannot acquire called_until without a completed call/referral job", call_error)
	var altered: Dictionary = base.duplicate(true)
	var old_income: int = altered.patients[target].income
	var forged_income: int = int(int(catalog.campaign.cases["U01-C1"].income)*101/100)
	var delta: int = forged_income-old_income
	var income_index: int = -1
	for n: int in range(altered.ledger_entries.size()):
		if altered.ledger_entries[n].category == "income" and altered.ledger_entries[n].reference == "income:"+target:
			income_index = n
			break
	check(delta > 0 and income_index >= 0, "real income row permits a precisely balanced one-percent forgery")
	if delta <= 0 or income_index < 0: finish(); return
	altered.patients[target].income = forged_income
	altered.ledger_entries[income_index].amount += delta
	for n: int in range(income_index,altered.ledger_entries.size()): altered.ledger_entries[n].cash_after += delta
	altered.cash += delta
	altered.metrics.income += delta
	altered.metrics.operating_profit += delta
	var clinical: Dictionary = altered.patients[target].duplicate(true)
	clinical.income = old_income
	check(clinical == base.patients[target] and altered.command_receipts == base.command_receipts and altered.resources == base.resources and altered.campaign == base.campaign, "forgery preserves clinical timing/history, stock, all receipts, and actual price policy")
	mutation = {"patient_id":target,"old_income":old_income,"forged_income":forged_income,"delta":delta,"fictional_price_percent":101,"ledger_index":income_index}
	var before_reject: Dictionary = altered.duplicate(true)
	error = CampaignValidator.validate(altered,catalog)
	check(error != "", "balanced extra revenue without a prior public price command rejects", error)
	check(altered == before_reject, "rejecting forged income never repairs the caller's model")
	var restored: Dictionary = ClinicState.from_data(altered,catalog)
	check(not restored.get("ok",false), "normal saved-state entry point rejects the same fabricated quote", restored.get("error",""))
	actual_new_price_admission()
	finish()
