extends SceneTree

# The first test is an explicitly isolated clinical unit fixture. The second
# uses the actual clinical_02 arrivals, public commands, geometry and SaveStore.
var output := ""
var passed := 0
var failed := 0
var checks: Array = []
var traces: Array = []
var catalog: ContentCatalog
var helper: Script

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=").replace("\\","/")
	_run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks.append({"ok":ok,"check":label})
	if ok: passed+=1
	else: failed+=1
	print(("CARE PASS: " if ok else "CARE FAIL: ")+label)

func _care_events(state: Dictionary,id: String,stage: String) -> Array:
	return state.ledger_entries.filter(func(e: Dictionary) -> bool: return e.event_id=="care:"+id+":"+stage)

func _unit_patient(id: String,cell: int,slot: String) -> Dictionary:
	return {"id":id,"disease_id":"pillow_dependency","stage":"ward","phase":"moving_ward","cell":cell,"move_progress":0,"room_id":"ward_unit","slot_id":slot,"wait_reason":"","queue_enter_tick":900,
		"care_steps":["general_exam","ward"],"care_cursor":1,"care_started_ticks":{"general_exam":600},"care_completed_ticks":{"general_exam":760},"treatment_started":false,"services_complete":false}

func test_two_bed_nurse_unit() -> void:
	# This fixture is not a normal-play screenshot, save or valid full hospital.
	# It isolates _start_service and room-level occupation with two real slots.
	var state: ClinicState=ClinicState.create("level_01",catalog)
	state.data.tick=1000
	state.data.rooms={"ward_unit":{"kind":"ward","staff_id":"nurse_unit","staff_cells":[102]}}
	state.data.staff={"nurse_unit":{"role":"nurse","room_id":"ward_unit","phase":"idle","cell":102,"move_progress":0}}
	state.data.slots={"bed0":{"room_id":"ward_unit","cell":100,"patient_id":"unit1","phase":"reserved","remaining_ticks":0},"bed1":{"room_id":"ward_unit","cell":101,"patient_id":"unit2","phase":"reserved","remaining_ticks":0}}
	state.data.patients={"unit1":_unit_patient("unit1",100,"bed0"),"unit2":_unit_patient("unit2",101,"bed1")}
	PatientFlow._start_service(state,catalog,state.data.patients.unit1)
	PatientFlow._start_service(state,catalog,state.data.patients.unit2)
	check(state.data.slots.bed0.phase=="serving" and state.data.slots.bed1.phase=="serving","one room nurse starts both independently reserved beds")
	check(state.data.slots.bed0.remaining_ticks==300 and state.data.slots.bed1.remaining_ticks==300,"each bed starts its complete independent300tick service")
	check(_care_events(state.data,"unit1","ward").size()==1 and _care_events(state.data,"unit2","ward").size()==1 and state.data.metrics.treatment_cost==60,"two actual ward starts produce exactly two30cost events")
	check(state.data.patients.unit1.care_cursor==1 and state.data.patients.unit2.care_cursor==1,"starting service does not advance either route cursor")
	state.data.slots.bed0.phase="blocked"
	state.data.slots.bed0.remaining_ticks=0
	PatientFlow._refresh_staff(state)
	var first: String=state.data.staff.nurse_unit.phase
	var reverse := {"bed1":state.data.slots.bed1,"bed0":state.data.slots.bed0}
	state.data.slots=reverse
	PatientFlow._refresh_staff(state)
	check(first=="serving" and state.data.staff.nurse_unit.phase=="serving","mixed serving and blocked beds aggregate serving first independent of dictionary order")

func _command(sim: Simulation,id: String,kind: String,payload: Dictionary) -> Dictionary:
	var result: Dictionary=sim.submit({"id":id,"type":kind,"payload":payload})
	check(bool(result.get("ok",false)),"public "+kind+" "+id)
	return result

func test_real_public_routes() -> void:
	if not catalog.levels.has("clinical_02"):
		check(false,"actual clinical_02 exists for normal scheduled arrivals")
		return
	var state: ClinicState=ClinicState.create("clinical_02",catalog)
	var sim := Simulation.new(catalog,state)
	check(state.data.cash==15000 and state.data.scheduled_arrivals.size()==60 and state.data.rooms.is_empty(),"genuine clinical_02 begins paused with15000 and60 actual scheduled arrivals")
	var serial := 0
	var room_ids: Dictionary={}
	for row: Array in [["reception",25],["diagnosis",28],["general_exam",32],["pharmacy",36],["ward",265]]:
		serial+=1
		var built: Dictionary=_command(sim,"care_build"+str(serial),"build_room",{"kind":row[0],"origin_cell":row[1],"rotation":0})
		if not built.get("ok",false): return
		var room_id: String=built.data.room_id
		room_ids[row[0]]=room_id
		var role: String=catalog.rooms[row[0]].staff_role
		var hired: Dictionary=_command(sim,"care_hire"+str(serial),"hire_staff",{"role":role})
		if not hired.get("ok",false): return
		if not _command(sim,"care_assign"+str(serial),"assign_staff",{"staff_id":hired.data.staff_id,"room_id":room_id}).get("ok",false): return
	_command(sim,"care_start","set_paused",{"paused":false})
	var targets := {"patient_002":"rhythm_hiccup","patient_004":"pillow_dependency","patient_006":"warmwind_sneeze"}
	var intervals: Dictionary={}
	var last: Dictionary={}
	var transfer_snapshot: Dictionary={}
	for _i in range(3600):
		var before: Dictionary=sim.snapshot()
		var transferring: Dictionary=before.patients.get("patient_006",{})
		if transfer_snapshot.is_empty() and transferring.get("phase","")=="moving_ward":
			var exam_slot: Dictionary=before.slots[room_ids.general_exam+":0"]
			var pharmacy_slot: Dictionary=before.slots[room_ids.pharmacy+":0"]
			if exam_slot.phase=="free" and pharmacy_slot.phase=="blocked" and pharmacy_slot.patient_id=="patient_006": transfer_snapshot=before
		for id: String in targets:
			var p: Dictionary=before.patients.get(id,{})
			if p.is_empty(): continue
			if p.phase in ["general_exam_service","pharmacy_service","ward_service"]:
				var key: String=id+":"+p.stage
				intervals[key]=int(intervals.get(key,0))+1
			var signature: String=JSON.stringify([p.phase,p.get("care_cursor",-1),p.get("care_started_ticks",{}),p.get("care_completed_ticks",{})])
			if last.get(id,"")!=signature:
				traces.append({"tick":before.tick,"patient_id":id,"patient":p})
				last[id]=signature
		sim.advance_ticks(1)
		var all_done := true
		for id: String in targets: all_done=all_done and sim.snapshot().patients.get(id,{}).get("phase","")=="completed"
		if all_done: break
	var final: Dictionary=sim.snapshot()
	for id: String in targets:
		var p: Dictionary=final.patients.get(id,{})
		check(p.get("disease_id","")==targets[id],id+" is the original scheduled new disease")
		var expected: Array=catalog.diseases[targets[id]].care_steps
		check(p.get("care_steps",[])==expected and p.get("care_cursor",-1)==expected.size() and p.get("phase","")=="completed" and p.get("services_complete",false),id+" completes its exact ordered care route and actually exits")
		var previous := 0
		for stage: String in expected:
			var started: int=p.get("care_started_ticks",{}).get(stage,-1)
			var ended: int=p.get("care_completed_ticks",{}).get(stage,-1)
			check(started>=previous and ended-started==int(catalog.rooms[stage].service_ticks),id+" "+stage+" starts after previous step and keeps its exact clinical duration")
			check(int(intervals.get(id+":"+stage,0))==int(catalog.rooms[stage].service_ticks),id+" "+stage+" uses actual service intervals, not reservation or walking time")
			var events: Array=_care_events(final,id,stage)
			check(events.size()==1 and events[0].tick==started and events[0].delta==-int(catalog.rooms[stage].get("consumable_cost",0)) and events[0].category=="treatment_cost",id+" "+stage+" records exactly one real start event including zero-cost exam")
			previous=ended
		check(not p.get("treatment_started",false),id+" does not invent an old equipment treatment latch")
	var old: Dictionary=final.patients.get("patient_001",{})
	check(not old.has("care_steps") and not old.has("care_cursor") and not old.has("care_started_ticks") and not old.has("care_completed_ticks"),"old disease receives no new route fields")
	check(SnapshotValidator.validate(final,catalog)=="","whole actual care hospital validates including other scheduled patients")
	var save_dir: String=output.get_basename()+"-save"
	var saved: Dictionary=SaveStore.save(final,save_dir)
	check(bool(saved.get("ok",false)),"actual full care state saves")
	var loaded: Dictionary=SaveStore.load(save_dir,catalog)
	check(bool(loaded.get("ok",false)),"actual full care state loads")
	if loaded.get("ok",false):
		check(loaded.state.to_data()==final,"actual loaded state preserves complete route/bed/ledger snapshot")
		var restored := Simulation.new(catalog,loaded.state)
		sim.advance_ticks(20); restored.advance_ticks(20)
		check(sim.snapshot()==restored.snapshot(),"care save replay remains exactly deterministic")
	var invalid: Dictionary=final.duplicate(true)
	invalid.patients.patient_002.care_steps=["unknown_care"]
	check(SnapshotValidator.validate(invalid,catalog)!="","unknown or substituted care route is rejected")
	invalid=final.duplicate(true)
	invalid.patients.patient_006.care_cursor=0
	check(SnapshotValidator.validate(invalid,catalog)!="","completed earnings with forged incomplete cursor are rejected")
	invalid=final.duplicate(true)
	for e: Dictionary in invalid.ledger_entries:
		if e.event_id=="care:patient_002:pharmacy":
			e.delta-=1; invalid.cash-=1; invalid.metrics.treatment_cost+=1; invalid.metrics.operating_profit-=1
			break
	check(SnapshotValidator.validate(invalid,catalog)!="","wrong per-step cost is rejected even when cash and operating totals reconcile")
	check(not transfer_snapshot.is_empty(),"real pharmacy-to-ward handoff provides a blocked-origin validation fixture")
	if not transfer_snapshot.is_empty():
		check(SnapshotValidator.validate(transfer_snapshot,catalog)=="","real blocked pharmacy handoff remains a valid save state")
		invalid=transfer_snapshot.duplicate(true)
		var p: Dictionary=invalid.patients.patient_006
		var previous_slot: Dictionary=invalid.slots[room_ids.pharmacy+":0"]
		previous_slot.phase="free"; previous_slot.patient_id=""; previous_slot.remaining_ticks=0
		var wrong_slot: Dictionary=invalid.slots[room_ids.general_exam+":0"]
		wrong_slot.phase="blocked"; wrong_slot.patient_id=p.id; wrong_slot.remaining_ticks=0
		p.cell=wrong_slot.cell; p.path=[]; p.path_index=0; p.move_progress=0
		invalid.staff[invalid.rooms[room_ids.pharmacy].staff_id].phase="idle"
		invalid.staff[invalid.rooms[room_ids.general_exam].staff_id].phase="blocked"
		check(SnapshotValidator.validate(invalid,catalog)=="invalid_care_blocked_slot","care handoff cannot hold an earlier exam instead of its immediately completed pharmacy")

func _run() -> void:
	if not output.begins_with("E:/CODEX/2026-10-21/医院诊疗护理扩展/") or output.simplify_path()!=output or FileAccess.file_exists(output) or DirAccess.dir_exists_absolute(output.get_basename()+"-save"):
		printerr("Require fresh --output JSON inside the clinical task")
		quit(2); return
	var result: Dictionary=ContentCatalog.load_checked("res://content")
	check(bool(result.get("ok",false)),"actual production catalog loads")
	if result.get("ok",false):
		catalog=result.catalog
		var content_ready: bool=catalog.rooms.has("ward") and catalog.diseases.has("warmwind_sneeze") and catalog.staff.has("nurse")
		check(content_ready,"actual expanded nurse/room/disease content is available")
		var helper_ready: bool=FileAccess.file_exists("res://sim/clinical_pathways.gd")
		check(helper_ready,"read-only ClinicalPathways interface exists")
		if content_ready: test_two_bed_nurse_unit()
		var runtime_ready: bool=PatientFlow.SERVICES.has("ward_service")
		check(runtime_ready,"care services are recognized before advancing normal play")
		# Avoid an old-runtime modes lookup error; missing feature itself is RED.
		if content_ready and helper_ready and runtime_ready: test_real_public_routes()
	var file: FileAccess=FileAccess.open(output,FileAccess.WRITE)
	if file==null: quit(2); return
	file.store_string(JSON.stringify({"passed":passed,"failed":failed,"checks":checks,"route_trace":traces,"scope":"Explicit isolated two-bed clinical unit fixture plus actual clinical_02 public construction/assignment and original scheduled patients002/004/006; no fabricated normal-play phases. Full real SaveStore and negative validation copies.","patient_flow_sha256":FileAccess.get_sha256("res://sim/patient_flow.gd"),"validator_sha256":FileAccess.get_sha256("res://storage/snapshot_validator.gd")},"  "))
	print("CARE RESULT: passed=%d failed=%d"%[passed,failed])
	quit(1 if failed else 0)
