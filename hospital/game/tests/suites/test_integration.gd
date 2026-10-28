extends RefCounted

var catalog: ContentCatalog
var commands: Array
var output: String
var serial := 0

func run(t: TestContext) -> void:
	catalog=ContentCatalog.load_checked("res://content").catalog
	var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/replay_commands.json"))
	commands=_integers(fixture.commands)
	output=ProjectSettings.globalize_path("res://../reports/implementation/integration-%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(output)
	t.expect_equal(fixture.version,catalog.content_version,"replay uses current content")
	test_complete_challenge_from_commands_with_save_mid_congestion(t)
	test_close_reassign_reopen_upgrade_and_finish_without_orphans(t)
	test_replay_at_30_and_60_render_calls_keeps_same_tick_snapshot(t)
	print("INTEGRATION EVIDENCE: "+output)

func _session() -> GameSession:
	return GameSession.new(catalog,output.path_join("unused-session-save"))

func _commands_at(session: GameSession, tick: int, t: TestContext) -> void:
	for row in commands:
		if row.tick!=tick: continue
		var command: Dictionary=row.duplicate(true)
		command.erase("tick")
		var result:=session.submit(command)
		t.expect_true(result.ok,"replayed explicit command "+command.id+" at "+str(tick)+": "+result.code)

func _send(session: GameSession, type: String, payload: Dictionary, t: TestContext) -> Dictionary:
	serial+=1
	var result:=session.submit({"id":"integration_%d" % serial,"type":type,"payload":payload})
	t.expect_true(result.ok,type+": "+result.code)
	return result

func _conservation(snapshot: Dictionary, t: TestContext) -> Dictionary:
	var state:=ClinicState.new()
	state.data=snapshot
	var result:=Metrics.summary(state)
	var total:=0
	for category in ["not_arrived","outside","in_hospital","completed","abandoned"]: total+=int(result.dispositions[category])
	t.expect_equal(total,snapshot.scheduled_arrivals.size(),"all dispositions conserved")
	t.expect_equal(result.patients.size(),snapshot.scheduled_arrivals.size(),"each scheduled patient has one disposition")
	return result

func _no_orphans(snapshot: Dictionary, t: TestContext) -> void:
	var orphan_reservations:=0
	for slot in snapshot.slots.values():
		if slot.patient_id!="" and (not snapshot.patients.has(slot.patient_id) or snapshot.patients[slot.patient_id].phase in ["completed","abandoned"]): orphan_reservations+=1
	for queue in snapshot.queues.values():
		for id in queue:
			if not snapshot.patients.has(id) or snapshot.patients[id].phase in ["completed","abandoned"]: orphan_reservations+=1
	t.expect_equal(orphan_reservations,0,"no ghost slots after closing and upgrading")
	for id in snapshot.staff:
		var room_id: String=snapshot.staff[id].room_id
		if room_id!="": t.expect_equal(snapshot.rooms[room_id].staff_id,id,"staff-room assignment reciprocal")

func test_complete_challenge_from_commands_with_save_mid_congestion(t: TestContext) -> void:
	var continuous:=_session()
	t.expect_true(continuous.start_level("level_01").get("ok",false),"legacy replay explicitly selects teaching level01")
	var reloaded: GameSession
	var save_tick:=-1
	_commands_at(continuous,0,t)
	t.expect_equal(continuous.sim.snapshot().rooms.size(),4,"duplicate explicit build replay charges once")
	for _step in range(9000):
		continuous.advance_wall_time(GameSession.STEP_USEC)
		var snapshot:=continuous.sim.snapshot()
		if reloaded!=null:
			reloaded.advance_wall_time(GameSession.STEP_USEC)
			_commands_at(reloaded,snapshot.tick,t)
		_commands_at(continuous,snapshot.tick,t)
		if reloaded==null:
			for patient in snapshot.patients.values():
				if patient.get("wait_reason","") in ["equipment_busy","recovery_full"]:
					save_tick=snapshot.tick
					var root:=output.path_join("congested-save")
					var saved:=SaveStore.save(continuous.sim.snapshot(),root)
					t.expect_true(saved.ok,"real congested snapshot saves: "+saved.error)
					var loaded:=SaveStore.load(root,catalog)
					t.expect_true(loaded.ok,"real congested snapshot reloads: "+loaded.error)
					if not loaded.ok: return
					reloaded=_session()
					reloaded.sim=Simulation.new(catalog,loaded.state)
					t.expect_equal(reloaded.sim.snapshot(),continuous.sim.snapshot(),"full snapshot exact immediately after reload")
					break
		if snapshot.challenge.status!="running": break
	t.expect_true(save_tick>0,"save actually occurs during clinical congestion")
	if reloaded==null: return
	t.expect_equal(reloaded.sim.snapshot(),continuous.sim.snapshot(),"full replay equivalence at same tick")
	var final:=continuous.sim.snapshot()
	t.expect_equal(final.challenge.status,"won","real level01 command replay wins without setup cheats")
	var summary:=_conservation(final,t)
	_no_orphans(final,t)
	_write("challenge-replay.json",{"save_tick":save_tick,"same_full_snapshot":reloaded.sim.snapshot()==final,"summary":summary,"snapshot":final})

func test_close_reassign_reopen_upgrade_and_finish_without_orphans(t: TestContext) -> void:
	var session:=_session()
	session.sim=Scenarios.create_sim(catalog,"benchmark_18","fast","standard")
	var found:=false
	for i in range(2000):
		session.advance_wall_time(GameSession.STEP_USEC)
		if session.sim.snapshot().staff.staff_003.phase=="serving":
			found=true
			break
	t.expect_true(found,"close starts during actual echo service")
	_send(session,"close_room",{"room_id":"room_003"},t)
	var before:=session.sim.snapshot()
	var rejected:=session.submit({"id":"integration_busy_reassign","type":"assign_staff","payload":{"staff_id":"staff_003","room_id":""}})
	t.expect_equal(rejected.code,"staff_busy","occupied employee cannot be reassigned")
	t.expect_equal(session.sim.snapshot(),before,"rejected reassignment is atomic")
	for i in range(3000):
		if session.sim.snapshot().rooms.room_003.status=="closed": break
		session.advance_wall_time(GameSession.STEP_USEC)
	t.expect_equal(session.sim.snapshot().rooms.room_003.status,"closed","close drains actual reservations and departure actors")
	_send(session,"assign_staff",{"staff_id":"staff_003","room_id":""},t)
	var hired:=_send(session,"hire_staff",{"role":"technician"},t)
	_send(session,"assign_staff",{"staff_id":hired.data.staff_id,"room_id":"room_003"},t)
	_send(session,"reopen_room",{"room_id":"room_003"},t)
	_send(session,"upgrade_recovery",{"room_id":"room_006"},t)
	t.expect_equal(session.sim.snapshot().rooms.room_006.service_cells.size(),2,"real recovery upgrade adds second seat")
	_no_orphans(session.sim.snapshot(),t)
	var root:=output.path_join("operations-save")
	var saved:=SaveStore.save(session.sim.snapshot(),root)
	t.expect_true(saved.ok,"post-reassignment upgrade saves: "+saved.error)
	var loaded:=SaveStore.load(root,catalog)
	t.expect_true(loaded.ok,"post-reassignment upgrade reloads: "+loaded.error)
	if not loaded.ok: return
	var restored:=Simulation.new(catalog,loaded.state)
	var remaining:=9000-int(session.sim.snapshot().tick)
	session.sim.advance_ticks(remaining)
	restored.advance_ticks(remaining)
	t.expect_equal(session.sim.snapshot(),restored.snapshot(),"operations full saved/continuous final snapshots equal")
	var final:=session.sim.snapshot()
	t.expect_equal(final.tick,9000,"operations run complete fixed horizon")
	_no_orphans(final,t)
	var summary:=_conservation(final,t)
	t.expect_equal(summary.dispositions.in_hospital+summary.dispositions.outside,0,"operations finish with nobody stranded")
	_write("operations-replay.json",{"same_full_snapshot":session.sim.snapshot()==restored.snapshot(),"summary":summary,"snapshot":final})

func test_replay_at_30_and_60_render_calls_keeps_same_tick_snapshot(t: TestContext) -> void:
	var results: Array=[]
	var call_counts: Array=[]
	var initial: Dictionary={}
	for fps in [30,60]:
		var session:=_session()
		t.expect_true(session.start_level("level_01").get("ok",false),"legacy pacing replay explicitly selects teaching level01")
		# Both render schedules replay one exact initial game, including its
		# cosmetic seed; preserve the full-snapshot equality assertion below.
		if initial.is_empty():initial=session.sim.snapshot()
		else:session.sim=Simulation.new(session.catalog,ClinicState.from_data(initial,session.catalog).state)
		_commands_at(session,0,t)
		var calls:=0
		var second:=0
		var previous_usec:=0
		# One integer second per fps calls: no 33333/16666 truncation drift.
		while session.sim.snapshot().challenge.status=="running" and second<901:
			for call in range(fps):
				var elapsed_usec:=second*1000000+int((call+1)*1000000/fps)
				session.advance_wall_time(elapsed_usec-previous_usec)
				previous_usec=elapsed_usec
				calls+=1
				var snapshot:=session.sim.snapshot()
				_commands_at(session,snapshot.tick,t)
				if snapshot.challenge.status!="running": break
			second+=1
		results.append(session.sim.snapshot())
		call_counts.append(calls)
	t.expect_equal(results[0],results[1],"render pacing does not change simulation")
	t.expect_true(call_counts[1]>call_counts[0],"60fps path actually uses more session render calls")
	t.expect_equal(results[0].challenge.status,"won","both rendering-call patterns finish real challenge")
	_write("render-pacing-replay.json",{"calls_30":call_counts[0],"calls_60":call_counts[1],"same_full_snapshot":results[0]==results[1],"snapshot":results[0]})

func _integers(value: Variant) -> Variant:
	if value is float: return int(value)
	if value is Array:
		var array: Array=[]
		for item in value: array.append(_integers(item))
		return array
	if value is Dictionary:
		var dict: Dictionary={}
		for key in value: dict[key]=_integers(value[key])
		return dict
	return value

func _write(name: String, data: Dictionary) -> void:
	var file:=FileAccess.open(output.path_join(name),FileAccess.WRITE)
	file.store_string(JSON.stringify(data,"  "))
	file.close()
