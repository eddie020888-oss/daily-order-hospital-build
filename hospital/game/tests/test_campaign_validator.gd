extends SceneTree

var passed: int = 0
var failed: int = 0
var checks: Array = []
var output: String = ""
var validator: Script
var catalog: ContentCatalog

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			output = argument.trim_prefix("--output=").replace("\\", "/")
	_run.call_deferred()

func _check(ok: bool, label: String, detail: String = "") -> void:
	checks.append({"ok": ok, "check": label, "detail": detail})
	if ok:
		passed += 1
	else:
		failed += 1
	print(("CAMPAIGN VALIDATOR PASS: " if ok else "CAMPAIGN VALIDATOR FAIL: ") + label + (" [" + detail + "]" if detail != "" else ""))

func _finish() -> void:
	var file: FileAccess = FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		quit(2)
		return
	file.store_string(JSON.stringify({"passed": passed, "failed": failed, "checks": checks, "scope": "Real CampaignState/catalog baseline and strict corruption checks. Tests never mutate production saves or run a simulation engine separately."}, "  "))
	print("CAMPAIGN VALIDATOR RESULT: passed=%d failed=%d" % [passed, failed])
	quit(1 if failed > 0 else 0)

func _valid(snapshot: Dictionary, label: String) -> void:
	var before: Dictionary = snapshot.duplicate(true)
	var error: String = validator.validate(snapshot, catalog)
	_check(error == "", label, error)
	_check(snapshot == before, label + " is read only")

func _reject(snapshot: Dictionary, label: String) -> void:
	var before: Dictionary = snapshot.duplicate(true)
	var error: String = validator.validate(snapshot, catalog)
	_check(error != "", label, error)
	_check(snapshot == before, label + " rejects without repair")

func _run() -> void:
	var task: String = "E:/CODEX/2026-10-22/医院全设施病例任务贯通/"
	if output == "" or not output.begins_with(task) or "/../" in output or FileAccess.file_exists(output):
		push_error("Require a fresh --output under the current E:/CODEX task")
		quit(2)
		return
	var loaded: Dictionary = ContentCatalog.load_checked("res://content")
	_check(loaded.get("ok", false), "actual content catalog loads", loaded.get("error", ""))
	if not loaded.get("ok", false):
		_finish()
		return
	catalog = loaded.catalog
	var path: String = "res://campaign/campaign_validator.gd"
	_check(FileAccess.file_exists(path), "schema2 has an independent strict validator")
	if not FileAccess.file_exists(path):
		_finish()
		return
	validator = load(path)
	_check(validator != null and validator.has_method("validate"), "validator exposes validate(snapshot,catalog)")
	var state_path: String = "res://campaign/campaign_state.gd"
	_check(FileAccess.file_exists(state_path), "real campaign factory exists")
	if validator == null or not validator.has_method("validate") or not FileAccess.file_exists(state_path):
		_finish()
		return
	var state_factory: Script = load(state_path)
	var state: ClinicState = state_factory.create("career_01", catalog)
	_check(state != null and state.data.get("schema_version") == 2, "factory produces genuine schema2 career_01")
	if state == null or state.data.get("schema_version") != 2:
		_finish()
		return
	var base: Dictionary = state.to_data()
	_valid(base, "empty genuine career state is valid")
	var parsed: Variant = JSON.parse_string(JSON.stringify(base))
	var normalized: Dictionary = ContentCatalog._normalize(parsed)
	_check(normalized.get("ok", false) and normalized.value == base, "JSON normalization preserves all authoritative integers")
	if normalized.get("ok", false):
		_valid(normalized.value, "genuine JSON round trip remains valid")
	var changed: Dictionary = base.duplicate(true)
	changed.schema_version = 1
	_reject(changed, "schema1 is not silently interpreted as campaign")
	changed = base.duplicate(true)
	changed.ruleset = "full-hospital-v0"
	_reject(changed, "unknown campaign ruleset rejects")
	changed = base.duplicate(true)
	changed.level_id = "level_01"
	_reject(changed, "legacy level cannot acquire schema2 semantics")
	changed = base.duplicate(true)
	changed.cash += 1
	_reject(changed, "unledgered cash creation rejects")
	changed = base.duplicate(true)
	changed.resources.supplies = -1
	_reject(changed, "negative resource stock rejects")
	changed = base.duplicate(true)
	changed.resources.supplies = 40.0
	_reject(changed, "in-memory fractional type is not silently coerced")
	changed = base.duplicate(true)
	changed.resources.erase("sterile")
	_reject(changed, "missing authoritative resource rejects")
	changed = base.duplicate(true)
	changed.next_ids.facility = 0
	_reject(changed, "nonpositive facility allocator rejects")
	changed = base.duplicate(true)
	changed.campaign.price_percent = 151
	_reject(changed, "price outside public command bounds rejects")
	changed = base.duplicate(true)
	changed.campaign.loan = 1000
	_reject(changed, "unledgered debt rejects")
	changed = base.duplicate(true)
	changed.campaign.completed_cases.append(catalog.levels.career_01.case_ids[0])
	_reject(changed, "case completion without real patients and evidence rejects")
	changed = base.duplicate(true)
	changed.campaign.career.completed_levels.append("career_01")
	_reject(changed, "career progress without matching receipt rejects")
	for effect: Array in [["comfort",100],["ventilation",100],["assistance_ready",true],["privacy_ready",true],["power_ready",true],["fire_ready",true],["educated",1],["archived_evidence_tick",0],["queue_priority_until",600],["operation_counts",{"fire":1}]]:
		changed = base.duplicate(true)
		changed.campaign[effect[0]] = effect[1]
		_reject(changed, "unearned operation effect " + str(effect[0]) + " rejects without a completed job")
	changed = base.duplicate(true)
	changed.facilities["facility_001"] = {"id": "facility_001", "kind": "missing", "room_id": "room_001"}
	changed.next_ids.facility = 2
	_reject(changed, "orphan malformed facility rejects before geometry dereference")
	changed = base.duplicate(true)
	changed.patients["patient_001"] = {"id": "patient_001", "case_id": "missing", "steps": []}
	changed.next_ids.patient = 2
	_reject(changed, "malformed patient rejects before clinical history dereference")
	changed = base.duplicate(true)
	changed.work_orders["work_order_001"] = {"id": "work_order_001", "status": "working", "facility_id": "missing"}
	changed.next_ids.work_order = 2
	_reject(changed, "orphan work order rejects before ownership dereference")
	changed = base.duplicate(true)
	changed.ledger_entries.append({"tick": 0, "category": "income", "amount": 1, "reference": "income:patient_999", "cash_after": changed.cash + 1})
	changed.cash += 1
	changed.metrics.income += 1
	changed.metrics.operating_profit += 1
	_reject(changed, "balanced forged patient income still rejects")
	changed = base.duplicate(true)
	changed.ledger_entries.append({"tick": 0, "category": "loan", "amount": 1000, "reference": "loan:fixture", "cash_after": changed.cash + 1000})
	changed.cash += 1000
	changed.campaign.loan = 1000
	changed.ledger_entries.append(changed.ledger_entries[-1].duplicate(true))
	changed.cash += 1000
	changed.campaign.loan += 1000
	changed.ledger_entries[-1].cash_after = changed.cash
	_reject(changed, "duplicate finance category/reference cannot mint money")
	_finish()
