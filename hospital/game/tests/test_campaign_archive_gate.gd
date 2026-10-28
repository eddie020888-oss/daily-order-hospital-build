extends SceneTree

var output := ""
var source_save := ""
var rejected_fixture := ""
var passed := 0
var failed := 0
var sequence := 0
var checks: Array=[]
var early_snapshot: Dictionary={}
var catalog: ContentCatalog

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=").replace("\\","/")
		if arg.begins_with("--source-save="): source_save=arg.trim_prefix("--source-save=").replace("\\","/")
		if arg.begins_with("--rejected-fixture="): rejected_fixture=arg.trim_prefix("--rejected-fixture=").replace("\\","/")
	_run.call_deferred()

func check(ok: bool,label: String,detail: String="") -> void:
	checks.append({"ok":ok,"check":label,"detail":detail})
	if ok: passed+=1
	else: failed+=1
	print(("ARCHIVE GATE PASS: " if ok else "ARCHIVE GATE FAIL: ")+label+(": "+detail if detail!="" else ""))

func command(sim: Simulation,type: String,payload: Dictionary,required: bool=true) -> Dictionary:
	sequence+=1
	var result: Dictionary=sim.submit({"id":"archive_gate_%04d"%sequence,"type":type,"payload":payload})
	if required: check(bool(result.get("ok",false)),"public "+type,str(result.get("code","")))
	return result

func run_probe(state: ClinicState) -> void:
	var sim := Simulation.new(catalog,state)
	check(state.data.campaign.completed_cases==["U01-C1"] and state.data.challenge.status=="running","actual saved first case is complete while seven authored cases remain")
	for row: Array in [["O31",241],["O32",248]]:
		var kind: String=str(row[0])
		var definition: Dictionary=catalog.campaign.facilities[kind]
		var built: Dictionary=command(sim,"build_department",{"unit_id":definition.unit_id,"origin_cell":int(row[1]),"layout":FacilityLayout.default_layout(definition.unit_id,kind,0)})
		if not built.get("ok",false): return
		for role: String in definition.roles:
			var hired: Dictionary=command(sim,"hire",{"role":role})
			if not hired.get("ok",false): return
			if not command(sim,"assign",{"staff_id":hired.data.staff_id,"facility_id":built.data.facility_ids[0]}).get("ok",false): return
		var order: Dictionary=command(sim,"run_operation",{"facility_kind":kind})
		if not order.get("ok",false): return
		command(sim,"set_paused",{"paused":false})
		for _n in range(2000):
			sim.advance_ticks(1)
			if sim.snapshot().work_orders[order.data.work_order_id].status=="done": break
		check(sim.snapshot().work_orders[order.data.work_order_id].status=="done","actual staffed "+kind+" prerequisite completes")
	command(sim,"set_paused",{"paused":true})
	var before: Dictionary=sim.snapshot()
	check(SnapshotValidator.validate(before,catalog)=="","genuine first-case privacy and archive preparation is save-valid",SnapshotValidator.validate(before,catalog))
	var result: Dictionary=command(sim,"request_audit",{"audit_id":"A13"},false)
	check(not result.get("ok",false) and sim.snapshot()==before,"archive audit cannot pass before the final case and preserve a stale approval",str(result.get("code","")))
	if result.get("ok",false):
		early_snapshot=sim.snapshot()
		check(SnapshotValidator.validate(early_snapshot,catalog)!="","strict save validation rejects an actual incorrectly accepted early archive approval")
	else:
		check(SnapshotValidator.validate(sim.snapshot(),catalog)=="","refusing an early audit leaves the real game playable")
	if rejected_fixture!="":
		var report: Variant=JSON.parse_string(FileAccess.get_file_as_string(rejected_fixture))
		var normalized: Dictionary=ContentCatalog._normalize(report.get("accepted_early_snapshot",{}) if report is Dictionary else {})
		var actual: Dictionary=normalized.get("value",{})
		check(normalized.get("ok",false) and not actual.is_empty(),"previous genuine RED snapshot is retained as an invalid-save regression")
		if not actual.is_empty(): check(SnapshotValidator.validate(actual,catalog)!="","old actual early-audit snapshot cannot load after the fix")

func _run() -> void:
	if not output.begins_with("E:/CODEX/") or output.simplify_path()!=output or FileAccess.file_exists(output) or not source_save.begins_with("E:/CODEX/") or not FileAccess.file_exists(source_save): quit(2); return
	var source_sha: String=FileAccess.get_sha256(source_save)
	var loaded: Dictionary=ContentCatalog.load_checked("res://content")
	check(bool(loaded.get("ok",false)),"actual campaign content loads",str(loaded.get("error","")))
	if loaded.get("ok",false):
		catalog=loaded.catalog
		var source: Dictionary=SaveStore.load(source_save.get_base_dir(),catalog)
		check(bool(source.get("ok",false)),"real completed first-case save loads",str(source.get("error","")))
		if source.get("ok",false): run_probe(source.state)
	check(FileAccess.get_sha256(source_save)==source_sha,"original public gameplay save is unchanged")
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	var file := FileAccess.open(output,FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed":passed,"failed":failed,"checks":checks,"source_save":source_save,"source_sha256":source_sha,"accepted_early_snapshot":early_snapshot,"scope":"Actual public first-case save plus paid O31 privacy and O32 archive construction, staff, jobs and audit request. No cash/phase/stock injection; any incorrectly accepted RED snapshot is preserved as a later invalid-load fixture."},"  "))
	print("ARCHIVE GATE RESULT: passed=%d failed=%d"%[passed,failed])
	quit(1 if failed else 0)
