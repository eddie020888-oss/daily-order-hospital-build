extends SceneTree

# Regression: normal public GameSession flow, four legal v2 work orientations.
# Catches routing through a stationary worker; also requires service and exit.
# No assets, actor visibility, patient phases or simulation snapshots are edited.
const LAYOUT := {"width":6,"height":5,"footprint_version":2,"door":{"side":"south","offset":2},"doors":[{"side":"south","offset":2},{"side":"east","offset":2}],"windows":[{"side":"north","offset":4},{"side":"west","offset":1},{"side":"east","offset":0},{"side":"south","offset":4}],"equipment":{"x":1,"y":0,"rotation":0},"furniture":[]}
var passed := 0
var failed := 0
var output := ""
var save_root := ""
var records: Array=[]
var catalog: ContentCatalog

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	for index in range(args.size()):
		var arg: String=args[index]
		if arg.begins_with("--output="):
			output=arg.trim_prefix("--output=")
		elif arg=="--output" and index+1<args.size():
			output=args[index+1]
		elif arg.begins_with("output="):
			output=arg.trim_prefix("output=")
	output=output.replace("\\","/")
	_run.call_deferred()

func check(ok: bool,label: String) -> void:
	if ok: passed+=1
	else: failed+=1
	print(("WORKPLACE PASS: " if ok else "WORKPLACE FAIL: ")+label)

func _issue(session: GameSession,kind: String,payload: Dictionary) -> Dictionary:
	var result: Dictionary=session.issue(kind,payload)
	check(bool(result.get("ok",false)),"normal command "+kind)
	return result

func _position(actor: Dictionary) -> Vector2:
	var cell: int=int(actor.cell)
	var result := Vector2(cell%24,cell/24)
	var path: Array=actor.get("path",[])
	var index: int=int(actor.get("path_index",0))
	if int(actor.get("move_progress",0))>0 and index+1<path.size():
		var next: int=int(path[index+1])
		result=result.lerp(Vector2(next%24,next/24),float(actor.move_progress)/4.0)
	return result

func _route_done(actor: Dictionary) -> bool:
	return actor.has("cell") and int(actor.get("move_progress",0))==0 and int(actor.get("path_index",0))+1>=actor.get("path",[]).size()

func _normal_case(rotation: int) -> void:
	var session := GameSession.new(catalog,save_root+"/r"+str(rotation))
	var doctor_id := ""
	var room_id := ""
	var patient_id: String=str(catalog.levels.level_01.arrivals[0].id)
	for row: Array in [["reception",128],["diagnosis",49],["echo",112],["recovery",140]]:
		var payload: Dictionary={"kind":row[0],"origin_cell":row[1],"rotation":0}
		if row[0]=="diagnosis":
			payload["layout"]=LAYOUT.duplicate(true)
			payload.layout.equipment.rotation=rotation
		var built: Dictionary=_issue(session,"build_room",payload)
		if not built.get("ok",false): return
		if row[0]=="diagnosis": room_id=str(built.data.room_id)
		if row[0]=="recovery": continue
		var hired: Dictionary=_issue(session,"hire_staff",{"role":catalog.rooms[row[0]].staff_role})
		if not hired.get("ok",false): return
		if row[0]=="diagnosis": doctor_id=str(hired.data.staff_id)
		_issue(session,"assign_staff",{"staff_id":hired.data.staff_id,"room_id":built.data.room_id})
	_issue(session,"set_auto_route",{"enabled":true})
	_issue(session,"close_room",{"room_id":room_id})
	_issue(session,"set_paused",{"paused":false})
	var ready := false
	for _tick in range(1800):
		var snap: Dictionary=session.sim.snapshot()
		var d: Dictionary=snap.staff.get(doctor_id,{})
		var p: Dictionary=snap.patients.get(patient_id,{})
		if snap.rooms[room_id].status=="closed" and d.get("phase","")=="idle" and p.get("phase","")=="diagnosis_queue" and p.get("wait_reason","")=="missing_room" and _route_done(d) and _route_done(p):
			ready=true
			break
		if snap.paused or snap.challenge.status!="running": break
		session.advance_wall_time(GameSession.STEP_USEC)
	check(ready,"real waiting pair established r"+str(rotation))
	if not ready: return
	_issue(session,"reopen_room",{"room_id":room_id})
	var min_distance := INF
	var unsafe: Array=[]
	var service_start := -1
	var service_end := -1
	var departed := false
	var complete := false
	var saved := false
	var restored: Simulation
	var replay_matches := true
	for _tick in range(1800):
		session.advance_wall_time(GameSession.STEP_USEC)
		if restored!=null:
			restored.advance_ticks(1)
			replay_matches=replay_matches and restored.snapshot()==session.sim.snapshot()
		var snap: Dictionary=session.sim.snapshot()
		var d: Dictionary=snap.staff[doctor_id]
		var p: Dictionary=snap.patients.get(patient_id,{})
		var work_cell: int=int(snap.rooms[room_id].staff_cells[0])
		if d.get("cell",-1)==work_cell and int(d.get("move_progress",0))==0 and p.has("cell"):
			var distance: float=_position(d).distance_to(_position(p))
			min_distance=minf(min_distance,distance)
			if distance<.55:
				unsafe.append({"tick":snap.tick,"distance":distance,"doctor":d.duplicate(true),"patient":p.duplicate(true)})
		if p.get("phase","")=="diagnosis_service":
			if service_start<0: service_start=int(snap.tick)
			if not saved and int(snap.slots[p.slot_id].remaining_ticks)<=40:
				check(SnapshotValidator.validate(snap,catalog)=="","real active consultation snapshot validates r"+str(rotation))
				check(bool(session.save_now().get("ok",false)),"real consultation saves r"+str(rotation))
				var loaded: Dictionary=SaveStore.load(session.save_root,catalog)
				check(bool(loaded.get("ok",false)),"real consultation save loads r"+str(rotation))
				if loaded.get("ok",false): restored=Simulation.new(catalog,loaded.state)
				saved=true
		elif service_start>=0 and service_end<0:
			service_end=int(snap.tick)
		if service_end>=0 and p.has("cell") and int(p.get("move_progress",0))>0: departed=true
		if p.get("phase","")=="completed":
			complete=true
			break
		if snap.paused or snap.challenge.status!="running": break
	check(unsafe.is_empty(),"patient never crosses stationary doctor work position on entry/departure r"+str(rotation)+" minimum="+str(min_distance))
	check(service_start>=0 and service_end-service_start==int(catalog.rooms.diagnosis.service_ticks),"normal Consult remains complete and exactly original duration r"+str(rotation))
	check(departed and complete,"first patient actually walks out and completes visit; no permanent wait r"+str(rotation))
	check(saved and restored!=null and replay_matches,"loaded in-service state resumes deterministically through real exit r"+str(rotation))
	check(SnapshotValidator.validate(session.sim.snapshot(),catalog)=="","final full session snapshot validates r"+str(rotation))
	records.append({"rotation":rotation,"minimum_stationary_doctor_patient_horizontal_distance":min_distance,"unsafe_samples":unsafe,"service_start":service_start,"service_end":service_end,"first_patient_completed":complete,"saved_replay_matches":replay_matches,"final_snapshot":session.sim.snapshot()})

func _run() -> void:
	# Each run owns a fresh report and sibling save directory. No machine- or
	# task-specific folder is embedded in this persistent regression test.
	if output=="" or not output.to_lower().begins_with("e:/codex/") or output.simplify_path()!=output or FileAccess.file_exists(output):
		push_error("Pass --output with a fresh absolute report path below E:/CODEX")
		quit(2)
		return
	save_root=output.get_base_dir().path_join(output.get_file().get_basename()+"-saves")
	if DirAccess.dir_exists_absolute(save_root) or FileAccess.file_exists(save_root) or DirAccess.make_dir_recursive_absolute(save_root)!=OK:
		push_error("The report save directory must be new and writable: "+save_root)
		quit(2)
		return
	var loaded: Dictionary=ContentCatalog.load_checked("res://content")
	check(bool(loaded.get("ok",false)),"real catalog loads")
	if loaded.get("ok",false):
		catalog=loaded.catalog
		for rotation in range(4): _normal_case(rotation)
	var file: FileAccess=FileAccess.open(output,FileAccess.WRITE)
	if file==null:
		push_error("Cannot write regression report: "+output)
		quit(2)
		return
	file.store_string(JSON.stringify({"passed":passed,"failed":failed,"cases":records,"scope":"True normal public GameSession flow. .55m is a regression warning threshold for the proven zero-distance crossing, not a character collision-radius or pixel nonpenetration proof. No presentation/asset changes or forged patient phase."},"  "))
	print("WORKPLACE ROUTE RESULT: passed=%d failed=%d"%[passed,failed])
	quit(1 if failed>0 else 0)
