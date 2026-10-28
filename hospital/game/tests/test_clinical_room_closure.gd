extends SceneTree

# Genuine clinical_02 patient002 and public room/employee commands only.
var output := ""
var catalog: ContentCatalog
var session: GameSession
var passed := 0
var failed := 0
var checks: Array=[]
var commands: Array=[]
var traces: Array=[]
var checkpoints: Dictionary={}
var old_room := ""
var new_room := ""
var last_trace := ""
var service_intervals := 0

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=").replace("\\","/")
	_run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks.append({"ok":ok,"check":label})
	if ok: passed+=1
	else: failed+=1
	print(("CARE CLOSE PASS: " if ok else "CARE CLOSE FAIL: ")+label)

func issue(kind: String,payload: Dictionary) -> Dictionary:
	var before: Dictionary=session.sim.snapshot()
	var result: Dictionary=session.issue(kind,payload)
	commands.append({"tick":before.tick,"kind":kind,"payload":payload,"result":result,"unchanged_on_rejection":before==session.sim.snapshot() if not result.get("ok",false) else null})
	check(bool(result.get("ok",false)),"public "+kind)
	return result

func patient() -> Dictionary:
	return session.sim.snapshot().patients.get("patient_002",{})

func advance_one() -> void:
	if patient().get("phase","")=="pharmacy_service": service_intervals+=1
	session.advance_wall_time(GameSession.STEP_USEC)
	var snapshot: Dictionary=session.sim.snapshot()
	var p: Dictionary=patient()
	var key: String=JSON.stringify([p.get("phase",""),p.get("room_id",""),p.get("slot_id",""),p.get("wait_reason","")])
	if key!=last_trace:
		traces.append({"tick":snapshot.tick,"patient":p,"old_queue":snapshot.queues.get(old_room,[]),"new_queue":snapshot.queues.get(new_room,[]),"old_status":snapshot.rooms.get(old_room,{}).get("status","")})
		last_trace=key

func checkpoint(label: String) -> void:
	var before: Dictionary=session.sim.snapshot()
	check(SnapshotValidator.validate(before,catalog)=="",label+" complete model validates")
	var saved: Dictionary=session.save_now()
	check(bool(saved.get("ok",false)),label+" actual GameSession save")
	var loaded: Dictionary=SaveStore.load(session.save_root,catalog)
	check(bool(loaded.get("ok",false)),label+" actual disk load")
	if not loaded.get("ok",false): return
	check(loaded.state.to_data()==before,label+" full disk snapshot equals saved state")
	session.open_saved()
	var after: Dictionary=session.sim.snapshot()
	var same := true
	for key: String in before:
		if key not in ["paused","command_receipts","command_sequence"] and before[key]!=after[key]: same=false
	check(not session.storage_blocked and after.paused and same and SnapshotValidator.validate(after,catalog)=="",label+" public reopen preserves all clinical, money and cosmetic state")
	checkpoints[label]=session.sim.snapshot()
	issue("set_paused",{"paused":false})

func build(kind: String,origin: int,staffed: bool) -> String:
	var built: Dictionary=issue("build_room",{"kind":kind,"origin_cell":origin,"rotation":0})
	if not built.get("ok",false): return ""
	var id: String=built.data.room_id
	if staffed:
		var hired: Dictionary=issue("hire_staff",{"role":catalog.rooms[kind].staff_role})
		if not hired.get("ok",false): return ""
		if not issue("assign_staff",{"staff_id":hired.data.staff_id,"room_id":id}).get("ok",false): return ""
	return id

func run_case() -> void:
	var loaded: Dictionary=ContentCatalog.load_checked("res://content")
	check(bool(loaded.get("ok",false)),"actual expanded catalog loads")
	if not loaded.get("ok",false): return
	catalog=loaded.catalog
	session=GameSession.new(catalog,output.get_basename()+"-save")
	var selected: Dictionary=session.start_level("clinical_02")
	check(bool(selected.get("ok",false)),"public selection starts clinical_02")
	check(session.sim.snapshot().cash==15000 and session.sim.snapshot().scheduled_arrivals.size()==60,"original budget and60 scheduled arrivals are unchanged")
	old_room=build("pharmacy",32,false)
	if old_room=="" or build("reception",25,true)=="" or build("diagnosis",28,true)=="": return
	issue("set_paused",{"paused":false})
	var queued := false
	for _i in range(1000):
		advance_one()
		var p: Dictionary=patient()
		if p.get("phase","")=="pharmacy_queue" and p.get("room_id","")==old_room and p.get("slot_id","")=="" and p.get("wait_reason","")=="missing_staff":
			queued=true
			break
	check(queued,"original patient002 genuinely queues at the unstaffed old pharmacy")
	if not queued: return
	checkpoint("before_close")
	var before: Dictionary=session.sim.snapshot()
	var original: Dictionary=patient()
	var previous_blocked := ""
	for id: String in before.slots:
		if before.slots[id].phase=="blocked" and before.slots[id].patient_id=="patient_002": previous_blocked=id
	issue("close_room",{"room_id":old_room})
	new_room=build("pharmacy",36,true)
	if new_room=="": return
	advance_one()
	var moved: Dictionary=patient()
	check(moved.room_id==new_room and "patient_002" not in session.sim.snapshot().queues[old_room],"unreserved care patient leaves draining old queue and selects new open pharmacy")
	check(moved.queue_enter_tick==original.queue_enter_tick and moved.wait_ticks==original.wait_ticks+1,"care requeue preserves original FIFO age and cumulative waiting")
	if previous_blocked!="" and moved.cell==original.cell:
		check(session.sim.snapshot().slots[previous_blocked].phase=="blocked" and session.sim.snapshot().slots[previous_blocked].patient_id=="patient_002","requeue does not release the previous real diagnosis occupation")
	checkpoint("after_close_and_requeue")
	var old_closed := false
	for _i in range(800):
		advance_one()
		old_closed=old_closed or session.sim.snapshot().rooms[old_room].status=="closed"
		if patient().phase=="completed": break
	var final: Dictionary=session.sim.snapshot()
	var p: Dictionary=patient()
	check(old_closed and final.queues[old_room].is_empty(),"old unstaffed pharmacy actually drains and closes without waiting for abandonment")
	check(p.phase=="completed" and p.abandon_tick==-1 and p.care_cursor==1 and p.care_completed_ticks.has("pharmacy"),"same actual patient completes pharmacy and exits without restart or abandonment")
	check(service_intervals==int(catalog.rooms.pharmacy.service_ticks),"closed-room transfer preserves the complete120tick pharmacy service")
	var events: Array=final.ledger_entries.filter(func(e: Dictionary) -> bool: return e.event_id=="care:patient_002:pharmacy")
	check(events.size()==1 and events[0].delta==-15 and events[0].tick==p.care_started_ticks.get("pharmacy",-1),"same patient is charged once at actual new-pharmacy service start")
	checkpoint("completed_patient")

func _run() -> void:
	if not output.begins_with("E:/CODEX/2026-10-21/医院诊疗护理扩展/") or output.simplify_path()!=output or FileAccess.file_exists(output) or DirAccess.dir_exists_absolute(output.get_basename()+"-save"): quit(2); return
	run_case()
	var file: FileAccess=FileAccess.open(output,FileAccess.WRITE)
	if file==null: quit(2); return
	file.store_string(JSON.stringify({"passed":passed,"failed":failed,"checks":checks,"commands":commands,"trace":traces,"checkpoints":checkpoints,"scope":"Real public clinical_02 original patient002, unstaffed pharmacy queue, public close/build/hire/assign, actual clinical completion and disk save/reopen. No injected phase/patient/budget or restart recovery.","patient_flow_sha256":FileAccess.get_sha256("res://sim/patient_flow.gd")},"  "))
	print("CARE CLOSE RESULT: passed=%d failed=%d"%[passed,failed])
	quit(1 if failed else 0)
