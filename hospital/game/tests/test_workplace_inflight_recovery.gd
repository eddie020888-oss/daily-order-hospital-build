extends SceneTree

# Domain regression for old saves/caches, not an art/capture fixture. Obtain a
# complete real live snapshot, then install a geometrically legal OLD route.
# The changed route/quarter models the prior release's saved state explicitly.
const LAYOUT := {"width":6,"height":5,"footprint_version":2,"door":{"side":"south","offset":2},"doors":[{"side":"south","offset":2},{"side":"east","offset":2}],"windows":[{"side":"north","offset":4},{"side":"west","offset":1},{"side":"east","offset":0},{"side":"south","offset":4}],"equipment":{"x":1,"y":0,"rotation":0},"furniture":[]}
var passed := 0
var failed := 0
var output := ""
var save_root := ""
var catalog: ContentCatalog
var rows: Array=[]

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
	print(("INFLIGHT PASS: " if ok else "INFLIGHT FAIL: ")+label)

func _fixture() -> Dictionary:
	var session := GameSession.new(catalog,save_root+"/fixture")
	var doctor := ""
	var diagnosis := ""
	for row: Array in [["reception",128],["diagnosis",49],["echo",112],["recovery",140]]:
		var payload: Dictionary={"kind":row[0],"origin_cell":row[1],"rotation":0}
		if row[0]=="diagnosis": payload.layout=LAYOUT.duplicate(true)
		var built: Dictionary=session.issue("build_room",payload)
		check(bool(built.get("ok",false)),"real fixture builds "+str(row[0]))
		if not built.get("ok",false): return {}
		if row[0]=="diagnosis": diagnosis=str(built.data.room_id)
		if row[0]=="recovery": continue
		var hired: Dictionary=session.issue("hire_staff",{"role":catalog.rooms[row[0]].staff_role})
		check(bool(hired.get("ok",false)),"real fixture hires "+str(row[0]))
		if not hired.get("ok",false): return {}
		if row[0]=="diagnosis": doctor=str(hired.data.staff_id)
		check(bool(session.issue("assign_staff",{"staff_id":hired.data.staff_id,"room_id":built.data.room_id}).get("ok",false)),"real fixture assigns "+str(row[0]))
	check(bool(session.issue("set_auto_route",{"enabled":true}).get("ok",false)),"normal auto route")
	check(bool(session.issue("close_room",{"room_id":diagnosis}).get("ok",false)),"normal temporary closure")
	check(bool(session.issue("set_paused",{"paused":false}).get("ok",false)),"normal clinic starts")
	var patient: String=str(catalog.levels.level_01.arrivals[0].id)
	var ready := false
	for _tick in range(1400):
		var snap: Dictionary=session.sim.snapshot()
		var p: Dictionary=snap.patients.get(patient,{})
		var d: Dictionary=snap.staff.get(doctor,{})
		if snap.rooms[diagnosis].status=="closed" and d.get("phase","")=="idle" and p.get("phase","")=="diagnosis_queue" and p.get("wait_reason","")=="missing_room" and _route_done(d) and _route_done(p):
			ready=true
			break
		if snap.paused or snap.challenge.status!="running": break
		session.advance_wall_time(GameSession.STEP_USEC)
	check(ready,"real closed-room waiting fixture")
	if not ready: return {}
	check(bool(session.issue("reopen_room",{"room_id":diagnosis}).get("ok",false)),"normal reopen")
	for _tick in range(1400):
		session.advance_wall_time(GameSession.STEP_USEC)
		var snap: Dictionary=session.sim.snapshot()
		var p: Dictionary=snap.patients.get(patient,{})
		var d: Dictionary=snap.staff.get(doctor,{})
		if p.get("phase","")=="moving_diagnosis" and d.get("cell",-1)==99 and d.get("move_progress",0)==0:
			return {"snapshot":snap,"doctor":doctor,"patient":patient}
		if snap.paused or snap.challenge.status!="running": break
	return {}

func _route_done(actor: Dictionary) -> bool:
	return actor.has("cell") and int(actor.get("move_progress",0))==0 and int(actor.get("path_index",0))+1>=actor.get("path",[]).size()

func _case(base: Dictionary,quarter: int) -> void:
	var state := ClinicState.new()
	state.data=base.snapshot.duplicate(true)
	var actor: Dictionary=state.data.patients[base.patient]
	# Exact legacy cache from the proven collision: old static geometry has
	# always allowed 100 -> 99 (doctor) -> 98 (patient service target).
	var original_revision: int=state.data.map_revision
	actor.cell=100
	actor.path=[100,99,98]
	actor.path_index=0
	actor.move_progress=quarter
	actor.route_goal_cell=98
	actor.route_revision=original_revision
	actor.goal_cell=98
	check(SnapshotValidator.validate(state.to_data(),catalog)=="","legacy quarter is a legal full snapshot q"+str(quarter))
	var root_path: String=save_root+"/q"+str(quarter)
	check(bool(SaveStore.save(state.to_data(),root_path).get("ok",false)),"legacy full snapshot actually saves q"+str(quarter))
	var loaded: Dictionary=SaveStore.load(root_path,catalog)
	check(bool(loaded.get("ok",false)),"legacy full snapshot actually loads q"+str(quarter))
	if not loaded.get("ok",false): return
	var sim := Simulation.new(catalog,loaded.state)
	sim.advance_ticks(1)
	var first: Dictionary=sim.snapshot()
	var p: Dictionary=first.patients[base.patient]
	if quarter>0:
		check(p.cell==100 and p.move_progress==quarter-1,"blocked old edge backs out exactly one quarter, without teleport/forward collision q"+str(quarter))
	else:
		check(p.cell==100 and 99 not in p.path,"boundary old cache replans despite same map revision")
	check(first.map_revision==original_revision,"occupancy replan does not fabricate a map edit q"+str(quarter))
	check(SnapshotValidator.validate(first,catalog)=="","first recovery state remains a legal full snapshot q"+str(quarter))
	check(bool(SaveStore.save(first,root_path+"-after-first").get("ok",false)),"mid-recovery state saves q"+str(quarter))
	var second_load: Dictionary=SaveStore.load(root_path+"-after-first",catalog)
	check(bool(second_load.get("ok",false)),"mid-recovery state loads q"+str(quarter))
	if not second_load.get("ok",false): return
	var replay := Simulation.new(catalog,second_load.state)
	var deterministic := replay.snapshot()==sim.snapshot()
	var arrived := false
	var trace: Array=[]
	for _tick in range(80):
		sim.advance_ticks(1)
		replay.advance_ticks(1)
		var snap: Dictionary=sim.snapshot()
		deterministic=deterministic and replay.snapshot()==snap
		p=snap.patients[base.patient]
		trace.append({"tick":snap.tick,"cell":p.cell,"quarter":p.move_progress,"path":p.path.duplicate(),"phase":p.phase})
		if p.phase=="diagnosis_service":
			arrived=true
			break
	check(arrived,"saved old inflight recovers to actual Consult within bounded time q"+str(quarter))
	check(deterministic,"mid-recovery load resumes exactly q"+str(quarter))
	check(SnapshotValidator.validate(sim.snapshot(),catalog)=="","final recovery snapshot validates q"+str(quarter))
	rows.append({"quarter":quarter,"first_recovery_patient":first.patients[base.patient],"reached_real_service":arrived,"deterministic_replay":deterministic,"trace":trace})

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
		var base: Dictionary=_fixture()
		check(not base.is_empty(),"true normal first patient owns diagnosis reservation while doctor is at work; legacy cell/cache are explicit unit-fixture data")
		if not base.is_empty():
			for quarter in range(4): _case(base,quarter)
	var file: FileAccess=FileAccess.open(output,FileAccess.WRITE)
	if file==null:
		push_error("Cannot write regression report: "+output)
		quit(2)
		return
	file.store_string(JSON.stringify({"passed":passed,"failed":failed,"cases":rows,"scope":"Complete real GameSession snapshot with an explicitly installed old-release route/quarter as a domain regression fixture. SaveStore reads/writes and Simulation recovery are real. This is not an art or gameplay capture."},"  "))
	print("INFLIGHT RESULT: passed=%d failed=%d"%[passed,failed])
	quit(1 if failed>0 else 0)
