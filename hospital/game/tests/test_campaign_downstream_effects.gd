extends SceneTree

var output := ""
var passed := 0
var failed := 0
var sequence := 0
var checks: Array=[]
var catalog: ContentCatalog
var flow: Script

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=").replace("\\","/")
	_run.call_deferred()

func check(ok: bool,label: String,detail: String="") -> void:
	checks.append({"ok":ok,"check":label,"detail":detail})
	if ok: passed+=1
	else: failed+=1
	print(("CAMPAIGN EFFECT PASS: " if ok else "CAMPAIGN EFFECT FAIL: ")+label+(": "+detail if detail!="" else ""))

func command(sim: Simulation,type: String,payload: Dictionary) -> Dictionary:
	sequence+=1
	var result: Dictionary=sim.submit({"id":"effect_%04d"%sequence,"type":type,"payload":payload})
	check(bool(result.get("ok",false)),"public "+type,str(result.get("code","")))
	return result

func build_staff(sim: Simulation,kind: String,origin: int) -> String:
	var definition: Dictionary=catalog.campaign.facilities[kind]
	var built: Dictionary=command(sim,"build_department",{"unit_id":definition.unit_id,"origin_cell":origin,"layout":FacilityLayout.default_layout(definition.unit_id,kind,0)})
	if not built.get("ok",false): return ""
	var id: String=built.data.facility_ids[0]
	for role: String in definition.roles:
		var hired: Dictionary=command(sim,"hire",{"role":role})
		if not hired.get("ok",false): return ""
		if not command(sim,"assign",{"staff_id":hired.data.staff_id,"facility_id":id}).get("ok",false): return ""
	return id

func run_job(sim: Simulation,kind: String) -> String:
	var ordered: Dictionary=command(sim,"run_operation",{"facility_kind":kind})
	if not ordered.get("ok",false): return ""
	command(sim,"set_paused",{"paused":false})
	var id: String=ordered.data.work_order_id
	for _n in range(1800):
		sim.advance_ticks(1)
		if sim.snapshot().work_orders[id].status=="done": break
	check(sim.snapshot().work_orders[id].status=="done","real staffed "+kind+" job completes")
	return id

func test_patience_effects() -> void:
	for kind: String in ["O20","O21","O07","O06"]:
		var state: ClinicState=CampaignState.create("career_01",catalog)
		var sim := Simulation.new(catalog,state)
		if build_staff(sim,kind,25)=="": continue
		var before: int=flow.patience_limit(state.data,catalog,{})
		if run_job(sim,kind)=="": continue
		var after: int=flow.patience_limit(state.data,catalog,{})
		check(after>before and after<=before+1200,"actual "+kind+" completion provides a bounded real waiting benefit","before=%d after=%d"%[before,after])
		var error: String=SnapshotValidator.validate(sim.snapshot(),catalog)
		check(error=="","real "+kind+" effect retains an earned save proof",error)

func test_privacy_route_effect() -> void:
	var state: ClinicState=CampaignState.create("career_01",catalog)
	var sim := Simulation.new(catalog,state)
	if build_staff(sim,"O31",25)=="": return
	var kind := "U26-E1"
	var definition: Dictionary=catalog.campaign.facilities[kind]
	var built: Dictionary=command(sim,"build_department",{"unit_id":definition.unit_id,"origin_cell":33,"layout":FacilityLayout.default_layout(definition.unit_id,kind,0)})
	if not built.get("ok",false): return
	var facility_id: String=built.data.facility_ids[0]
	var room_id: String=built.data.room_id
	var service_cell: int=state.data.facilities[facility_id].service_cells[0]
	# Read-only actor arguments inspect a real built backend room. They are
	# never injected into the hospital, used as screenshots or passed as saves.
	var observer := {"id":"inspection_patient","cell":216}
	var before: Dictionary=flow._work_positions(state.data,observer,217)
	check(not before.has(service_cell),"ordinary backend route has no invented privacy block")
	if run_job(sim,"O31")=="": return
	var after: Dictionary=flow._work_positions(state.data,observer,217)
	check(after.has(service_cell),"earned access-control job prevents patient transit through unrelated backend room")
	var target: Dictionary=flow._work_positions(state.data,observer,service_cell)
	check(not target.has(service_cell),"a patient's actual target backend service remains reachable")
	observer.cell=service_cell
	var leaving: Dictionary=flow._work_positions(state.data,observer,216)
	check(not leaving.has(service_cell) and not GridService.path_avoiding(state,service_cell,216,leaving).is_empty(),"patient already inside controlled room can walk out normally")
	var employee := {"id":"inspection_employee","role":"technician","cell":216}
	check(not flow._work_positions(state.data,employee,217).has(service_cell),"privacy control does not obstruct qualified staff circulation")
	check(state.data.rooms.has(room_id),"privacy only changes actor routing and keeps the actual room")

func test_called_queue() -> void:
	var state: ClinicState=CampaignState.create("career_01",catalog)
	var sim := Simulation.new(catalog,state)
	var reception := ""
	for row: Array in [["O01",25],["U01-E1",30],["O15",35],["O03",40]]:
		var id: String=build_staff(sim,str(row[0]),int(row[1]))
		if id=="": return
		if row[0]=="O01": reception=id
	if run_job(sim,"O15")=="": return
	command(sim,"set_paused",{"paused":true})
	if not command(sim,"accept_case",{"case_id":"U01-C1"}).get("ok",false): return
	# Legal public closure before any reservation keeps this actual first
	# patient queued while the separately staffed calling screen performs work.
	command(sim,"close_facility",{"facility_id":reception})
	if run_job(sim,"O03")=="": return
	var actual: Dictionary=sim.snapshot().patients.patient_001
	check(actual.phase=="care_queue" and int(actual.get("called_until",0))>int(state.data.tick),"actual queued patient receives priority only from a finished calling job")
	var ready: bool=flow.has_method("queue_order")
	check(ready,"scheduler exposes and uses deterministic called-priority/FIFO ordering")
	if ready:
		# Explicit pure-order unit: the real called patient's record is copied;
		# an older comparison row is synthetic and never enters Simulation.
		var ordered: Dictionary=state.to_data()
		var older: Dictionary=actual.duplicate(true)
		older.id="patient_000"; older.queue_enter_tick=maxi(0,int(actual.queue_enter_tick)-1); older.called_until=0
		ordered.patients={"patient_001":actual.duplicate(true),"patient_000":older}
		check(flow.queue_order(ordered)[0]=="patient_001","an earned active call takes priority over an older uncalled row")
		ordered.patients.patient_001.called_until=0
		check(flow.queue_order(ordered)[0]=="patient_000","equal call status keeps original FIFO instead of actor ID order")
	command(sim,"reopen_facility",{"facility_id":reception})
	sim.advance_ticks(1800)
	check(sim.snapshot().patients.patient_001.phase=="left","same real first patient resumes service and exits without route or phase edits")
	check(SnapshotValidator.validate(sim.snapshot(),catalog)=="","actual call and resumed patient remain strictly save-valid",SnapshotValidator.validate(sim.snapshot(),catalog))

func _run() -> void:
	if not output.begins_with("E:/CODEX/") or output.simplify_path()!=output or FileAccess.file_exists(output): quit(2); return
	var loaded: Dictionary=ContentCatalog.load_checked("res://content")
	check(bool(loaded.get("ok",false)),"actual campaign content loads",str(loaded.get("error","")))
	if loaded.get("ok",false):
		catalog=loaded.catalog; flow=load("res://campaign/campaign_clinical_flow.gd")
		test_patience_effects(); test_privacy_route_effect(); test_called_queue()
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	var file := FileAccess.open(output,FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed":passed,"failed":failed,"checks":checks,"scope":"Actual public staffed operation jobs and genuine first patient waiting under a public reception closure; backend path inspection uses read-only actor arguments on real room geometry. Two-row ordering is an explicitly synthetic pure-rule comparison, never normal gameplay, a save or a screenshot."},"  "))
	print("CAMPAIGN EFFECT RESULT: passed=%d failed=%d"%[passed,failed])
	quit(1 if failed else 0)
