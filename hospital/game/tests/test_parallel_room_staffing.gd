extends SceneTree
# Regression uses only real public GameSession commands, arrivals and SaveStore.
var output := ""
var passed := 0
var failed := 0
var checks: Array=[]
var commands: Array=[]
var traces: Array=[]
var checkpoints: Dictionary={}
var catalog: ContentCatalog
var session: GameSession
var case_id := ""
var old := ""
var staffed := ""
var first_diagnosis_room := ""
var diagnosis_intervals := 0
func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=").replace("\\","/")
	_run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks.append({"ok":ok,"case":case_id,"check":label})
	if ok: passed+=1
	else: failed+=1
	print(("PARALLEL STAFF PASS: " if ok else "PARALLEL STAFF FAIL: ")+case_id+" / "+label)
func issue(kind: String,payload: Dictionary) -> Dictionary:
	var before: Dictionary=session.sim.snapshot()
	var result: Dictionary=session.issue(kind,payload)
	commands.append({"case":case_id,"tick":before.tick,"kind":kind,"payload":payload,"result":result,"unchanged_if_rejected":session.sim.snapshot()==before if not result.get("ok",false) else null})
	return result
func snapshot() -> Dictionary:
	return session.sim.snapshot()
func first() -> Dictionary:
	return snapshot().patients.get("patient_001",{})
func advance(ticks: int) -> void:
	for _i in range(ticks):
		if first().get("phase","")=="diagnosis_service": diagnosis_intervals+=1
		session.advance_wall_time(GameSession.STEP_USEC)
		var snap: Dictionary=snapshot()
		var p: Dictionary=snap.patients.get("patient_001",{})
		if first_diagnosis_room=="" and p.get("stage","")=="diagnosis" and p.get("room_id","")!="": first_diagnosis_room=p.room_id
		var slots: Dictionary={}
		for id: String in snap.slots: slots[id]=snap.slots[id]
		traces.append({"case":case_id,"tick":snap.tick,"patient":p,"old_queue":snap.queues.get(old,[]),"staffed_queue":snap.queues.get(staffed,[]),"slots":slots})
func hire_for(room_id: String) -> bool:
	var role: String=catalog.rooms[snapshot().rooms[room_id].kind].staff_role
	var hired: Dictionary=issue("hire_staff",{"role":role})
	check(bool(hired.get("ok",false)),"public hire "+role)
	if not hired.get("ok",false): return false
	var assigned: Dictionary=issue("assign_staff",{"staff_id":hired.data.staff_id,"room_id":room_id})
	check(bool(assigned.get("ok",false)),"public assignment to "+room_id)
	return bool(assigned.get("ok",false))
func setup(tag: String,ready: bool) -> bool:
	case_id=tag; old=""; staffed=""; first_diagnosis_room=""; diagnosis_intervals=0
	session=GameSession.new(catalog,output.get_basename()+"-saves/"+tag)
	check(snapshot().cash==8000 and snapshot().rooms.is_empty(),"genuine empty 8000-budget new game")
	for row: Array in [["diagnosis",100,false],["diagnosis",108,ready],["reception",121,true],["echo",104,true],["recovery",140,false]]:
		var result: Dictionary=issue("build_room",{"kind":row[0],"origin_cell":row[1],"rotation":0})
		check(bool(result.get("ok",false)),"public build "+str(row[0])+" "+str(row[1]))
		if not result.get("ok",false): return false
		var id: String=result.data.room_id
		if old=="": old=id
		elif staffed=="": staffed=id
		if row[2] and not hire_for(id): return false
	check(old<staffed and snapshot().rooms[old].staff_id=="","first open diagnosis is the lower-ID unstaffed room")
	checkpoints[tag+"_setup"]=snapshot()
	return bool(issue("set_paused",{"paused":false}).get("ok",false))
func wait_for_unstaffed_queue() -> bool:
	for _i in range(800):
		advance(1)
		var p: Dictionary=first()
		if p.get("phase","")=="diagnosis_queue" and p.get("room_id","")==old and p.get("wait_reason","")=="missing_staff": return true
	return false
func save_load(tag: String) -> void:
	var before: Dictionary=snapshot()
	check(SnapshotValidator.validate(before,catalog)=="",tag+" complete real state validates")
	check(bool(session.save_now().get("ok",false)),tag+" actually saves")
	var loaded: Dictionary=SaveStore.load(session.save_root,catalog)
	check(bool(loaded.get("ok",false)),tag+" SaveStore actually loads")
	if not loaded.get("ok",false): return
	check(loaded.state.to_data()==before,tag+" raw loaded snapshot equals the actual saved state")
	session.open_saved()
	var after: Dictionary=snapshot()
	var same := true
	for key: String in before:
		if key not in ["paused","command_receipts","command_sequence"] and before[key]!=after[key]: same=false
	check(not session.storage_blocked and after.paused and same,tag+" public reopen preserves clinical ownership, waits, money and identity; paused")
	check(bool(issue("set_paused",{"paused":false}).get("ok",false)),tag+" publicly resumes after reopen")
	checkpoints[case_id+"_"+tag]=snapshot()
func pre_staffed_case() -> void:
	if not setup("pre_staffed",true): return
	advance(800)
	check(snapshot().tick==800 and first_diagnosis_room==staffed,"first patient initially chooses the available staffed diagnosis")
	check(bool(first().get("tolerance_revealed",false)),"first patient completes actual diagnosis by tick 800")
	check(diagnosis_intervals==catalog.rooms.diagnosis.service_ticks,"diagnosis keeps its complete original service duration")
	save_load("after_diagnosis")
func only_unstaffed_case() -> void:
	if not setup("only_unstaffed",false): return
	check(wait_for_unstaffed_queue(),"first patient actually queues when both rooms are unstaffed")
	var before: Dictionary=first()
	advance(80)
	var p: Dictionary=first()
	check(p.get("room_id","")==old and p.get("slot_id","")=="" and p.get("phase","")=="diagnosis_queue" and p.get("wait_reason","")=="missing_staff","only unstaffed choices retain the patient in the existing queue")
	check(p.queue_enter_tick==before.queue_enter_tick and p.wait_ticks==before.wait_ticks+80,"no staff does not drop or reset queue age or cumulative waiting")
	check(snapshot().queues[old].count("patient_001")==1 and snapshot().queues[staffed].is_empty(),"patient remains in exactly one unstaffed queue")
	save_load("still_waiting")
func late_staffed_case() -> void:
	if not setup("late_staffed",false): return
	check(wait_for_unstaffed_queue(),"first patient genuinely waits before another room is staffed")
	save_load("before_staffing")
	var before: Dictionary=snapshot()
	var p: Dictionary=before.patients["patient_001"]
	var blocked := ""
	for id: String in before.slots:
		if before.slots[id].patient_id=="patient_001" and before.slots[id].phase=="blocked": blocked=id
	check(blocked!="","late-staffing fixture genuinely still owns the blocked previous reception slot")
	if not hire_for(staffed): return
	advance(1)
	var moved: Dictionary=first()
	check(moved.room_id==staffed and "patient_001" not in snapshot().queues[old],"unreserved patient transfers to the newly staffed open same-kind room")
	check(moved.queue_enter_tick==p.queue_enter_tick and moved.wait_ticks==p.wait_ticks+1,"transfer preserves original queue time and accumulated waiting")
	if blocked!="" and moved.cell==p.cell:
		check(snapshot().slots[blocked].phase=="blocked" and snapshot().slots[blocked].patient_id=="patient_001","queue transfer keeps previous blocked-slot ownership until actual departure")
	check(moved.slot_id!="" and snapshot().slots[moved.slot_id].phase=="reserved","ordinary scheduler reserves the new service slot instead of skipping service")
	save_load("after_transfer")
	advance(800)
	check(bool(first().get("tolerance_revealed",false)),"newly staffed room really completes the first patient's diagnosis")
	check(diagnosis_intervals==catalog.rooms.diagnosis.service_ticks,"transferred diagnosis retains full original clinical duration")
	save_load("after_diagnosis")
func draining_case() -> void:
	if not setup("draining_preserved",false): return
	check(wait_for_unstaffed_queue(),"draining fixture begins with an actual unstaffed old queue")
	var queued: Dictionary=first()
	check(bool(issue("close_room",{"room_id":old}).get("ok",false)),"publicly close old queued room")
	if not hire_for(staffed): return
	advance(100)
	var held: Dictionary=first()
	check(snapshot().rooms[old].status=="draining" and held.room_id==old and held.slot_id=="" and "patient_001" in snapshot().queues[old],"staffing another room does not steal the draining room's existing queue")
	check(held.queue_enter_tick==queued.queue_enter_tick and held.wait_ticks==queued.wait_ticks+100,"draining queue keeps its original age and waiting")
	save_load("held_draining")
	if not hire_for(old): return
	advance(600)
	check(bool(first().get("tolerance_revealed",false)),"staffing the draining original room still completes its preserved old work")
	save_load("after_drain_service")
func _run() -> void:
	var base := "E:/CODEX/2026-10-21/医院全人物接入与经营压测/"
	if output=="" or not output.begins_with(base) or output.simplify_path()!=output or FileAccess.file_exists(output) or DirAccess.dir_exists_absolute(output.get_basename()+"-saves"):
		push_error("Require fresh --output JSON below this task")
		quit(2); return
	var loaded: Dictionary=ContentCatalog.load_checked("res://content")
	check(bool(loaded.get("ok",false)),"production catalog loads")
	if loaded.get("ok",false):
		catalog=loaded.catalog
		pre_staffed_case(); only_unstaffed_case(); late_staffed_case(); draining_case()
	var file: FileAccess=FileAccess.open(output,FileAccess.WRITE)
	if file==null: quit(2); return
	file.store_string(JSON.stringify({"passed":passed,"failed":failed,"checks":checks,"commands":commands,"trace":traces,"checkpoints":checkpoints,"patient_flow_sha256":FileAccess.get_sha256("res://sim/patient_flow.gd"),"scope":"Four real public new-game fixtures: pre-staffed, only-unstaffed, late-staffed unreserved queue with prior blocked reception ownership, and preserved draining queue. Real save/load/reopen; original arrivals, budget, clinical times, normal hints; no state/phase injection or restart."},"  "))
	print("PARALLEL STAFF RESULT: passed=%d failed=%d"%[passed,failed])
	quit(1 if failed>0 else 0)
