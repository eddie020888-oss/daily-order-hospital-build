extends SceneTree

# All state in this test comes from the genuine career_01 factory, public
# commands and Simulation ticks. Mutated copies are negative save tests only.
var output := ""
var passed := 0
var failed := 0
var checks: Array=[]
var sequence := 0
var catalog: ContentCatalog

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=").replace("\\","/")
	_run.call_deferred()

func check(ok: bool,label: String,detail: String="") -> void:
	checks.append({"ok":ok,"check":label,"detail":detail})
	if ok: passed+=1
	else: failed+=1
	print(("CAMPAIGN PUBLIC PASS: " if ok else "CAMPAIGN PUBLIC FAIL: ")+label+(": "+detail if detail!="" else ""))

func command(sim: Simulation,type: String,payload: Dictionary) -> Dictionary:
	sequence+=1
	var result: Dictionary=sim.submit({"id":"clinical_public_%03d"%sequence,"type":type,"payload":payload})
	check(bool(result.get("ok",false)),"public "+type,str(result.get("code","")))
	return result

func reject_copy(snapshot: Dictionary,label: String) -> void:
	var before: Dictionary=snapshot.duplicate(true)
	var error: String=SnapshotValidator.validate(snapshot,catalog)
	check(error!="" and snapshot==before,label,error)

func run_case() -> void:
	var state: ClinicState=CampaignState.create("career_01",catalog)
	var sim := Simulation.new(catalog,state)
	var layout: Dictionary=FacilityLayout.default_layout("U01","U01-E1",0)
	var built: Dictionary=command(sim,"build_department",{"unit_id":"U01","origin_cell":25,"layout":layout})
	if not built.get("ok",false): return
	var facility_id: String=str(built.data.facility_ids[0])
	var hired: Dictionary=command(sim,"hire",{"role":"doctor"})
	if not hired.get("ok",false): return
	if not command(sim,"assign",{"staff_id":hired.data.staff_id,"facility_id":facility_id}).get("ok",false): return
	# The authored route now starts at a real staffed reception. Clinical
	# supplies must be physically delivered by the background logistics worker.
	for row: Array in [["O01",33],["O15",40]]:
		var kind: String=str(row[0])
		var definition: Dictionary=catalog.campaign.facilities[kind]
		var extra: Dictionary=command(sim,"build_department",{"unit_id":definition.unit_id,"origin_cell":int(row[1]),"layout":FacilityLayout.default_layout(definition.unit_id,kind,0)})
		if not extra.get("ok",false): return
		for role: String in definition.roles:
			var worker: Dictionary=command(sim,"hire",{"role":role})
			if not worker.get("ok",false): return
			if not command(sim,"assign",{"staff_id":worker.data.staff_id,"facility_id":extra.data.facility_ids[0]}).get("ok",false): return
	var delivery: Dictionary=command(sim,"run_operation",{"facility_kind":"O15"})
	if not delivery.get("ok",false): return
	command(sim,"set_paused",{"paused":false})
	for _n in range(900):
		sim.advance_ticks(1)
		if sim.snapshot().work_orders[delivery.data.work_order_id].status=="done": break
	check(sim.snapshot().work_orders[delivery.data.work_order_id].status=="done","actual logistics worker produces delivered clinical stock before admission")
	command(sim,"set_paused",{"paused":true})
	check(CampaignClinicalFlow.case_readiness(state,catalog,"U01-C1").is_empty(),"genuine first case is reachable and staffed before acceptance")
	if not command(sim,"accept_case",{"case_id":"U01-C1"}).get("ok",false): return
	command(sim,"set_paused",{"paused":false})
	var moving: Dictionary={}
	var active: Dictionary={}
	var validation_error := ""
	for _n in range(1400):
		sim.advance_ticks(1)
		var snapshot: Dictionary=sim.snapshot()
		validation_error=SnapshotValidator.validate(snapshot,catalog)
		if validation_error!="": break
		var p: Dictionary=snapshot.patients.patient_001
		if moving.is_empty() and p.phase=="moving_care" and p.move_progress==1: moving=snapshot
		if active.is_empty() and p.phase=="care_service" and p.steps[p.step_index].facility_kind=="U01-E1" and p.service_work==10: active=snapshot
		if p.phase=="left": break
	check(validation_error=="","every actual admission/walk/service/handoff/exit tick passes strict validation",validation_error)
	check(not moving.is_empty(),"real quarter-edge reservation snapshot captured")
	check(not active.is_empty(),"real service clock and ledger snapshot captured")
	var final: Dictionary=sim.snapshot()
	check(final.patients.patient_001.phase=="left" and final.metrics.completed==1 and final.campaign.completed_cases==["U01-C1"],"same first patient physically exits and earns one genuine case completion")
	check(SnapshotValidator.validate(final,catalog)=="","fully completed genuine case remains save-valid",SnapshotValidator.validate(final,catalog))
	for row: Array in [["moving",moving],["active",active],["finished",final]]:
		if row[1].is_empty(): continue
		var directory: String=output.get_basename()+"-save-"+str(row[0])
		var saved: Dictionary=SaveStore.save(row[1],directory)
		check(bool(saved.get("ok",false)),"actual disk save "+str(row[0]),str(saved.get("error","")))
		var loaded: Dictionary=SaveStore.load(directory,catalog)
		check(bool(loaded.get("ok",false)),"actual disk load "+str(row[0]),str(loaded.get("error","")))
		if not loaded.get("ok",false): continue
		check(loaded.state.to_data()==row[1],"exact snapshot roundtrip "+str(row[0]))
		if row[0]=="active":
			var initial: Dictionary=ClinicState.from_data(row[1],catalog)
			if not initial.ok: continue
			var a := Simulation.new(catalog,initial.state)
			var b := Simulation.new(catalog,loaded.state)
			a.advance_ticks(900); b.advance_ticks(900)
			check(a.snapshot()==b.snapshot() and a.snapshot().patients.patient_001.phase=="left","saved active service replays deterministically through physical departure")
	if active.is_empty(): return
	var altered: Dictionary=active.duplicate(true)
	altered.patients.patient_001.service_work+=1
	reject_copy(altered,"forged remaining service clock rejects without mutation")
	altered=active.duplicate(true)
	altered.patients.patient_001.step_history[0].started_tick-=1
	reject_copy(altered,"forged history start cannot shortcut full authored service")
	altered=active.duplicate(true)
	altered.staff[hired.data.staff_id].patient_id=""
	reject_copy(altered,"one-sided staff release rejects during actual service")
	altered=active.duplicate(true)
	altered.slots[facility_id+":0"].phase="free"
	altered.slots[facility_id+":0"].patient_id=""
	reject_copy(altered,"one-sided facility slot release rejects during actual service")
	altered=active.duplicate(true)
	altered.resources.supplies+=1
	reject_copy(altered,"unearned replacement of consumed stock rejects")

func _run() -> void:
	if not output.begins_with("E:/CODEX/") or output.simplify_path()!=output or FileAccess.file_exists(output):
		printerr("Require fresh --output=E:/CODEX/...json"); quit(2); return
	for suffix: String in ["moving","active","finished"]:
		if DirAccess.dir_exists_absolute(output.get_basename()+"-save-"+suffix): quit(2); return
	var loaded: Dictionary=ContentCatalog.load_checked("res://content")
	check(bool(loaded.get("ok",false)),"actual full content loads",str(loaded.get("error","")))
	if loaded.get("ok",false): catalog=loaded.catalog; run_case()
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	var file := FileAccess.open(output,FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed":passed,"failed":failed,"checks":checks,"scope":"Actual career01 case U01-C1 via public build/hire/assign/accept and Simulation; three actual disk SaveStore roundtrips; strict corrupted-copy rejection. No teleports, free money or fabricated normal-play phases."},"  "))
	print("CAMPAIGN PUBLIC RESULT: passed=%d failed=%d"%[passed,failed])
	quit(1 if failed else 0)
