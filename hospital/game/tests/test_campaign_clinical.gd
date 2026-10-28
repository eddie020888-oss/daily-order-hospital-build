extends SceneTree

# Isolated, explicit clinical unit fixtures exercise the real campaign runtime.
# Public construction/all-catalog playthroughs belong to the independent suite.
var passed := 0
var failed := 0
var output := ""
var checks: Array = []
var state_script: Script
var flow: Script
var operations: Script
var catalog: ContentCatalog
var level_id := ""
var fixture_kind := ""
var fixture_disease := ""

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=").replace("\\","/")
	_run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks.append({"ok":ok,"check":label})
	if ok: passed+=1
	else: failed+=1
	print(("CAMPAIGN CLINICAL PASS: " if ok else "CAMPAIGN CLINICAL FAIL: ")+label)

func _tick(state: ClinicState,count: int=1) -> void:
	for _n in range(count):
		if state.data.paused: continue
		state.data.tick+=1
		flow.after_tick(state,catalog)
		if not state.data.paused: operations.after_tick(state,catalog)

func _fixture(two_roles: bool=false) -> ClinicState:
	var state: ClinicState=state_script.create(level_id,catalog)
	state.data.paused=false
	var roles: Array=["doctor","nurse"] if two_roles else ["doctor"]
	var steps: Array=[]
	for id: String in ["first","repeat"]:
		steps.append({"id":id,"kind":"patient","facility_kind":fixture_kind,"duration_ticks":7,"cost":11,"roles":roles.duplicate(),"resource":"supplies","quantity":2})
	catalog.campaign.cases["clinical_unit"]={"id":"clinical_unit","unit_id":"U01","disease_id":fixture_disease,"patient_count":1,"steps":steps,"income":120}
	# No rendered room is fabricated: this intentionally isolates navigation on
	# the real open 24x18 map and arrival/resource/occupation semantics.
	state.data.facilities={"unit_facility":{"id":"unit_facility","kind":fixture_kind,"room_id":"","x":0,"y":0,"rotation":0,"status":"open","condition":100,"uses":0,"staff_ids":["staff_001","staff_002"] if two_roles else ["staff_001"],"busy_patient_id":"","service_cells":[221],"staff_cells":[197,198],"maintenance_cell":222}}
	state.data.slots={"unit_facility:0":{"id":"unit_facility:0","facility_id":"unit_facility","room_id":"","index":0,"cell":221,"patient_id":"","phase":"free"}}
	state.data.staff={"staff_001":_staff("staff_001","doctor",217)}
	if two_roles: state.data.staff.staff_002=_staff("staff_002","nurse",218)
	state.data.next_ids.staff=3
	return state

func _staff(id: String,role: String,cell: int) -> Dictionary:
	return {"id":id,"role":role,"room_id":"","facility_id":"unit_facility","cell":cell,"path":[],"path_index":0,"move_progress":0,"move_ticks":4,"status":"idle","phase":"idle","fatigue":0,"skills":[],"work_order_id":"","patient_id":"","appearance_id":""}

func _start(state: ClinicState) -> Dictionary:
	var result: Dictionary=flow.admit_case(state,catalog,"clinical_unit")
	check(bool(result.get("ok",false)),"explicit unit case admits through actual campaign admission")
	return state.data.patients.values()[0] if not state.data.patients.is_empty() else {}

func test_create() -> void:
	var state: ClinicState=state_script.create(level_id,catalog)
	check(state!=null and state.data.schema_version==2 and state.data.ruleset=="full-hospital-v1","factory creates isolated schema2 ruleset")
	check(state.data.cash==catalog.levels[level_id].initial_cash and state.data.rooms.is_empty() and state.data.patients.is_empty(),"fresh campaign preserves authored budget without free construction or patients")
	check(state.data.resources=={"supplies":40,"sterile":8,"blood":4,"samples":0,"prepared":0,"waste":0,"water":20,"food":20,"spares":6},"initial bounded logistics stock is explicit")
	check(state.data.campaign.current_case_id=="" and not state.data.campaign.wave_active and state.data.next_ids.facility==1 and state.data.next_ids.work_order==1,"fresh wave and all identifier sequences are ready")
	var original: Dictionary=state.to_data()
	original.resources.supplies=0
	check(state.data.resources.supplies==40,"snapshots are independent copies")
	check(state_script.create("not_a_campaign_level",catalog)==null,"unknown campaign factory level is rejected")

func test_real_walk_and_repeated_steps() -> void:
	var state: ClinicState=_fixture()
	var patient: Dictionary=_start(state)
	if patient.is_empty(): return
	var original_cash: int=state.data.cash
	_tick(state)
	check(patient.cell==216 and patient.move_progress<=1 and patient.step_history.is_empty() and state.data.resources.supplies==40,"admission cannot teleport or charge before real arrival")
	var income_before_exit := false
	for _n in range(500):
		_tick(state)
		if patient.phase=="care_service":
			check(patient.cell==221 and state.data.staff.staff_001.cell==197 and state.data.staff.staff_001.move_progress==0,"service only starts with real patient and required staff on distinct work cells")
		if patient.phase!="left" and int(state.data.metrics.completed)>0: income_before_exit=true
		if patient.phase=="left": break
	check(patient.phase=="left" and patient.cell==216 and patient.move_progress==0,"complete route physically walks out before terminal success")
	check(patient.step_index==2 and patient.step_history.size()==2 and patient.step_history[0].step_id=="first" and patient.step_history[1].step_id=="repeat","same facility kind has independent stable step identities")
	if patient.step_history.size()==2:
		for entry: Dictionary in patient.step_history:
			check(entry.completed_tick-entry.started_tick==7,"each repeated service retains its full seven tick duration")
	check(not income_before_exit and state.data.metrics.completed==1 and state.data.resources.supplies==36,"only one exit reward and exactly two stock consumptions")
	check(state.data.cash==original_cash-22+120,"two charges and one exact case income reconcile")
	var terminal: Dictionary=state.to_data()
	_tick(state,20)
	check(state.data.cash==terminal.cash and state.data.ledger_entries==terminal.ledger_entries and state.data.metrics.completed==1,"terminal ticks cannot repeat charges or income")
	check(state.data.facilities.unit_facility.busy_patient_id=="" and state.data.slots["unit_facility:0"].phase=="free" and state.data.staff.staff_001.patient_id=="","physical departure releases facility slot and staff ownership")

func test_atomic_staff_and_stock() -> void:
	var state: ClinicState=_fixture(true)
	# The second employee exists and is qualified, but belongs to an actual
	# background job. A patient may not partially reserve the other employee.
	state.data.staff.staff_002.work_order_id="unit_job"
	var patient: Dictionary=_start(state)
	if patient.is_empty(): return
	_tick(state,35)
	check(patient.phase=="care_queue" and state.data.facilities.unit_facility.busy_patient_id=="" and state.data.staff.staff_001.patient_id=="" and state.data.resources.supplies==40,"busy second role causes no partial patient staff facility or stock reservation")
	state.data.staff.staff_002.work_order_id=""
	state.data.resources.supplies=1
	_tick(state,20)
	check(patient.step_history.is_empty() and state.data.staff.staff_001.patient_id=="" and state.data.staff.staff_002.patient_id=="" and state.data.facilities.unit_facility.busy_patient_id=="","insufficient stock atomically rejects all role reservations")
	state.data.resources.supplies=40
	for _n in range(200):
		_tick(state)
		if patient.phase=="care_service": break
	check(patient.phase=="care_service" and patient.staff_ids.size()==2 and state.data.staff.staff_001.patient_id==patient.id and state.data.staff.staff_002.patient_id==patient.id,"all distinct required roles reserve together and recover without resetting patient")

func test_support_waits_for_actual_work() -> void:
	var kind := ""
	for id: String in catalog.campaign.facilities:
		if catalog.campaign.facilities[id].kind=="support": kind=id; break
	check(kind!="","authored background support facility exists")
	if kind=="": return
	var state: ClinicState=_fixture()
	var definition: Dictionary=catalog.campaign.facilities[kind]
	catalog.campaign.cases.clinical_unit.steps=[{"id":"support_first","kind":"support","facility_kind":kind,"duration_ticks":9,"cost":13,"roles":definition.roles.duplicate(),"resource":"supplies","quantity":1}]
	state.data.facilities.unit_facility.kind=kind
	state.data.staff={}
	state.data.facilities.unit_facility.staff_ids=[]
	for n in range(definition.roles.size()):
		var id := "staff_%03d"%(n+1)
		state.data.staff[id]=_staff(id,str(definition.roles[n]),217+n)
		state.data.facilities.unit_facility.staff_ids.append(id)
	var patient: Dictionary=_start(state)
	if patient.is_empty(): return
	var original_cash: int=state.data.cash
	_tick(state)
	check(patient.phase=="waiting_support" and state.data.work_orders.size()==1 and patient.step_history.is_empty() and state.data.cash==original_cash,"support requests one real job and waits without pretending queued work has started")
	for _n in range(250):
		_tick(state)
		if patient.phase=="left": break
	var order: Dictionary=state.data.work_orders.values()[0]
	check(order.status=="done" and order.completed_tick-order.started_tick==9 and patient.step_index==1 and patient.phase=="left","background work walks workers and completes nine real ticks before patient leaves")
	check(patient.step_history.size()==1 and patient.step_history[0].work_order_id==order.id and patient.step_history[0].completed_tick==order.completed_tick,"support history cites its actual completed work order")
	check(state.data.cash==original_cash-13+120 and state.data.resources.supplies==39,"support charges and consumes once through Operations only")
	check(state.data.evidence.facilities.get(kind,0)==1,"support facility evidence is not double counted by clinical flow")

func _run() -> void:
	if not output.begins_with("E:/CODEX/") or output.simplify_path()!=output or FileAccess.file_exists(output):
		printerr("Require a fresh --output=E:/CODEX/...json"); quit(2); return
	var loaded: Dictionary=ContentCatalog.load_checked("res://content")
	check(bool(loaded.get("ok",false)),"real content catalog loads")
	var ready := true
	for path: String in ["res://campaign/campaign_state.gd","res://campaign/campaign_clinical_flow.gd","res://campaign/campaign_finance.gd","res://campaign/campaign_operations.gd"]:
		var exists: bool=FileAccess.file_exists(path)
		check(exists,"runtime exists "+path)
		ready=ready and exists
	if loaded.get("ok",false) and ready:
		catalog=loaded.catalog
		state_script=load("res://campaign/campaign_state.gd")
		flow=load("res://campaign/campaign_clinical_flow.gd")
		operations=load("res://campaign/campaign_operations.gd")
		for id: String in catalog.levels:
			if catalog.levels[id].get("ruleset","")=="full-hospital-v1": level_id=id; break
		for id: String in catalog.campaign.facilities:
			if catalog.campaign.facilities[id].kind=="patient": fixture_kind=id; break
		if not catalog.campaign.diseases.is_empty(): fixture_disease=str(catalog.campaign.diseases.keys()[0])
		check(level_id!="" and fixture_kind!="" and fixture_disease!="","actual campaign level facility and disease catalogs exist")
		if level_id!="" and fixture_kind!="" and fixture_disease!="":
			test_create(); test_real_walk_and_repeated_steps(); test_atomic_staff_and_stock(); test_support_waits_for_actual_work()
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	var file := FileAccess.open(output,FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed":passed,"failed":failed,"checks":checks,"scope":"Explicit isolated state/real-path clinical unit fixtures; no screenshots or claim of normal-play construction. Independent public campaign tests cover authored full geometry and all cases."},"  "))
	print("CAMPAIGN CLINICAL RESULT: passed=%d failed=%d"%[passed,failed])
	quit(1 if failed else 0)
