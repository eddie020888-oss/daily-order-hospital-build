extends SceneTree

# Public regression: a legal furnished bottleneck must stay unreserved, then
# close/reconfigure/reopen without waiting for patient abandonment. Every state
# comes from GameSession commands and normal time; no actor/snapshot is edited.
const ORIGIN := 49
const LAYOUT := {"width":3,"height":4,"footprint_version":2,"door":{"side":"east","offset":2},"equipment":{"x":0,"y":0,"rotation":0},"furniture":[{"kind":"plant","x":0,"y":3,"rotation":0},{"kind":"plant","x":1,"y":3,"rotation":0},{"kind":"plant","x":2,"y":3,"rotation":0}]}
var output := ""
var save_root := ""
var passed := 0
var failed := 0
var checks: Array=[]
var evidence: Dictionary={}
var catalog: ContentCatalog
var session: GameSession
var patient_id := ""
var doctor_id := ""
var room_id := ""
var replay: Simulation
var replay_matches := true
var abandonment_seen := false

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	for index in range(args.size()):
		var arg: String=args[index]
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=")
		elif arg=="--output" and index+1<args.size(): output=args[index+1]
		elif arg.begins_with("output="): output=arg.trim_prefix("output=")
	output=output.replace("\\","/")
	_run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks.append({"ok":ok,"check":label})
	if ok: passed+=1
	else: failed+=1
	print(("NARROW RECOVERY PASS: " if ok else "NARROW RECOVERY FAIL: ")+label)

func _issue(kind: String,payload: Dictionary) -> Dictionary:
	var result: Dictionary=session.issue(kind,payload)
	check(bool(result.get("ok",false)),"public "+kind)
	if replay!=null and result.get("ok",false):
		# Replay GameSession's exact accepted command and its real identifier.
		var command: Dictionary=result.data.command
		replay_matches=replay_matches and bool(replay.submit(command).get("ok",false)) and replay.snapshot()==session.sim.snapshot()
	return result

func _advance() -> bool:
	var before: Dictionary=session.sim.snapshot()
	if before.paused or before.challenge.status!="running": return false
	session.advance_wall_time(GameSession.STEP_USEC)
	if replay!=null:
		replay.advance_ticks(1)
		replay_matches=replay_matches and replay.snapshot()==session.sim.snapshot()
	var p: Dictionary=session.sim.snapshot().patients.get(patient_id,{})
	abandonment_seen=abandonment_seen or p.get("phase","") in ["abandoning","abandoned"]
	return true

func _save_load(label: String) -> bool:
	var snap: Dictionary=session.sim.snapshot()
	check(SnapshotValidator.validate(snap,catalog)=="",label+" full snapshot validates")
	var saved: Dictionary=session.save_now()
	check(bool(saved.get("ok",false)),label+" actually saves")
	var loaded: Dictionary=SaveStore.load(session.save_root,catalog)
	check(bool(loaded.get("ok",false)),label+" actually loads")
	if not loaded.get("ok",false): return false
	replay=Simulation.new(catalog,loaded.state)
	replay_matches=replay_matches and replay.snapshot()==snap
	return true

func _exercise() -> void:
	var loaded: Dictionary=ContentCatalog.load_checked("res://content")
	check(bool(loaded.get("ok",false)),"real content loads")
	if not loaded.get("ok",false): return
	catalog=loaded.catalog
	check(FreeRoomLayout.validate("diagnosis",LAYOUT)=="","real legal narrow furniture layout")
	session=GameSession.new(catalog,save_root+"/session")
	patient_id=str(catalog.levels.level_01.arrivals[0].id)
	for row: Array in [["reception",128],["diagnosis",ORIGIN],["echo",112],["recovery",140]]:
		var payload: Dictionary={"kind":row[0],"origin_cell":row[1],"rotation":0}
		if row[0]=="diagnosis": payload.layout=LAYOUT.duplicate(true)
		var built: Dictionary=_issue("build_room",payload)
		if not built.get("ok",false): return
		if row[0]=="diagnosis": room_id=str(built.data.room_id)
		if row[0]=="recovery": continue
		var hired: Dictionary=_issue("hire_staff",{"role":catalog.rooms[row[0]].staff_role})
		if not hired.get("ok",false): return
		if row[0]=="diagnosis": doctor_id=str(hired.data.staff_id)
		if not _issue("assign_staff",{"staff_id":hired.data.staff_id,"room_id":built.data.room_id}).get("ok",false): return
	_issue("set_auto_route",{"enabled":true})
	_issue("set_paused",{"paused":false})
	var observed := false
	for _index in range(900):
		if not _advance(): break
		var snap: Dictionary=session.sim.snapshot()
		var p: Dictionary=snap.patients.get(patient_id,{})
		if p.get("wait_reason","")=="path_blocked" and p.get("phase","") in ["diagnosis_queue","moving_diagnosis"]:
			observed=true
			evidence.blocked_snapshot=snap
			break
	check(observed,"first real patient reaches bounded honest path-blocked wait")
	if not observed: return
	var blocked: Dictionary=session.sim.snapshot()
	var patient: Dictionary=blocked.patients[patient_id]
	var free: bool=patient.phase=="diagnosis_queue" and patient.slot_id==""
	for slot: Dictionary in blocked.slots.values():
		if slot.room_id==room_id: free=free and slot.phase=="free" and slot.patient_id==""
	check(free,"actor-unreachable work bottleneck is not reserved and diagnosis slot stays free")
	var entered_queue: int=patient.queue_enter_tick
	var wait_before: int=patient.wait_ticks
	var closed_at := -1
	var close_tick: int=blocked.tick
	if not _save_load("actual narrow blocked wait"): return
	if not _issue("close_room",{"room_id":room_id}).get("ok",false): return
	for _index in range(80):
		if not _advance(): break
		var snap: Dictionary=session.sim.snapshot()
		if snap.rooms[room_id].status=="closed":
			closed_at=int(snap.tick)
			evidence.closed_snapshot=snap
			break
	check(closed_at>=0 and closed_at-close_tick<=80,"public close drains inaccessible pending work within 80 ticks")
	check(not abandonment_seen,"public recovery never relies on patience/abandonment")
	check(replay_matches,"blocked-wait save resumes deterministically through actual close")
	evidence.close_elapsed_ticks=closed_at-close_tick if closed_at>=0 else -1
	if closed_at<0: return
	var closed: Dictionary=session.sim.snapshot()
	patient=closed.patients[patient_id]
	check(patient.phase=="diagnosis_queue" and patient.room_id=="" and patient.slot_id=="","closed unreachable pending patient returns to unassigned same-stage queue")
	check(patient.queue_enter_tick==entered_queue and patient.wait_ticks>=wait_before,"cancel retains original FIFO entry and accumulated wait")
	check(closed.queues[room_id].is_empty(),"closed room has no stale queue membership")
	if not _save_load("closed narrow room"): return
	if not _issue("assign_staff",{"staff_id":doctor_id,"room_id":""}).get("ok",false): return
	var repaired: Dictionary=LAYOUT.duplicate(true)
	repaired.furniture=[]
	if not _issue("move_room",{"room_id":room_id,"origin_cell":ORIGIN,"rotation":0,"layout":repaired}).get("ok",false): return
	if not _issue("assign_staff",{"staff_id":doctor_id,"room_id":room_id}).get("ok",false): return
	if not _issue("reopen_room",{"room_id":room_id}).get("ok",false): return
	var service_start := -1
	var service_end := -1
	var departed := false
	var completed := false
	var service_saved := false
	for _index in range(1500):
		if not _advance(): break
		var snap: Dictionary=session.sim.snapshot()
		patient=snap.patients[patient_id]
		if patient.phase=="diagnosis_service":
			if service_start<0: service_start=int(snap.tick)
			if not service_saved and int(snap.slots[patient.slot_id].remaining_ticks)<=40:
				service_saved=_save_load("real repaired-room Consult")
		elif service_start>=0 and service_end<0: service_end=int(snap.tick)
		if service_end>=0 and int(patient.get("move_progress",0))>0: departed=true
		if patient.phase=="completed":
			completed=true
			break
	check(service_start>=0 and service_end-service_start==int(catalog.rooms.diagnosis.service_ticks),"same first patient completes original full 80-tick Consult after public refit")
	check(departed and completed and not abandonment_seen,"same first patient genuinely walks out and completes the full visit")
	check(service_saved and replay_matches,"real save/load replays public refit, Consult and exit deterministically")
	check(SnapshotValidator.validate(session.sim.snapshot(),catalog)=="","final normal full snapshot validates")
	evidence.merge({"original_queue_enter_tick":entered_queue,"service_start":service_start,"service_end":service_end,"first_patient_completed":completed,"abandonment_seen":abandonment_seen,"deterministic_replay":replay_matches,"final_snapshot":session.sim.snapshot()})

func _run() -> void:
	if output=="" or not output.to_lower().begins_with("e:/codex/") or output.simplify_path()!=output or FileAccess.file_exists(output):
		push_error("Pass --output with a fresh absolute report path below E:/CODEX")
		quit(2)
		return
	save_root=output.get_base_dir().path_join(output.get_file().get_basename()+"-saves")
	if DirAccess.dir_exists_absolute(save_root) or FileAccess.file_exists(save_root) or DirAccess.make_dir_recursive_absolute(save_root)!=OK:
		push_error("The report save directory must be new and writable")
		quit(2)
		return
	_exercise()
	var file: FileAccess=FileAccess.open(output,FileAccess.WRITE)
	if file==null:
		push_error("Cannot write narrow recovery report")
		quit(2)
		return
	file.store_string(JSON.stringify({"passed":passed,"failed":failed,"checks":checks,"evidence":evidence,"scope":"Real level_01 GameSession first patient, public commands/time only. No mutated snapshots/actor phases, art, or product settings. Narrow path is blocked honestly; recovery must occur before patience expires and complete the same patient's visit."},"  "))
	print("NARROW RECOVERY RESULT: passed=%d failed=%d"%[passed,failed])
	quit(1 if failed>0 else 0)
