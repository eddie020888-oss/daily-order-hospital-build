extends RefCounted

var sequence := 0
var catalog: ContentCatalog

func run(t: TestContext) -> void:
	catalog = ContentCatalog.load_checked("res://content").catalog
	test_three_diseases_complete_and_charge_once_after_exit(t)
	test_low_tolerance_fast_holds_device_until_recovery_available(t)
	test_patience_includes_walk_and_recovery_wait_but_not_service(t)
	test_closing_drains_old_queue_and_allows_replacement_staff(t)
	test_busy_room_or_departing_actor_cannot_be_removed(t)
	test_missing_room_staff_or_path_recovers_without_ghost_slots(t)
	test_41st_arrival_waits_outside_with_original_arrival_time(t)
	test_modes_latch_and_map_changes_replan_staff(t)
	test_service_durations_and_exit_fee_boundary(t)
	test_fifo_busy_wait_and_mode_precedence(t)
	test_outside_patient_promotes_without_resetting_wait(t)
	test_unrelated_map_edit_retains_route_and_progress(t)

func _send(sim: Simulation, type: String, payload: Dictionary) -> Dictionary:
	sequence += 1
	return sim.submit({"id":"clinic_%d" % sequence, "type":type, "payload":payload})

func _arrival(id: String, disease: String = "echo", tolerance: int = 70, tick: int = 1) -> Dictionary:
	return {"id":id, "disease_id":disease, "tolerance":tolerance, "tick":tick}

func _fixture(arrivals: Array, kinds: Array = ["reception", "diagnosis", "echo", "motion", "sensory", "recovery"], staffed: bool = true) -> Dictionary:
	var state := ClinicState.create("level_01", catalog)
	# Clinical unit fixtures (including staff-only empty arrivals) run independently
	# of player early settlement and story unlock pauses.
	state.data.scenario_id = "benchmark_18"
	state.data.unlocked_room_kinds = ["reception", "diagnosis", "echo", "motion", "sensory", "recovery"]
	state.data.scheduled_arrivals = arrivals.duplicate(true)
	var sim := Simulation.new(catalog, state)
	for row in [["reception",121],["diagnosis",100],["echo",104],["motion",108],["sensory",112],["recovery",140]]:
		if row[0] not in kinds:
			continue
		var result := _send(sim, "build_room", {"kind":row[0],"origin_cell":row[1],"rotation":0})
		if staffed and row[0] != "recovery":
			var hire := _send(sim,"hire_staff",{"role":catalog.rooms[row[0]].staff_role})
			_send(sim,"assign_staff",{"staff_id":hire.data.staff_id,"room_id":result.data.room_id})
	_send(sim,"set_paused",{"paused":false})
	return {"state":state,"sim":sim}

func _room(f: Dictionary, kind: String) -> String:
	for id in f.state.data.rooms:
		if f.state.data.rooms[id].kind == kind:
			return id
	return ""

func _until(f: Dictionary, id: String, phase: String, limit: int = 2500) -> bool:
	for tick in range(limit):
		if f.state.data.patients.get(id, {}).get("phase", "") == phase:
			return true
		f.sim.advance_ticks(1)
	return false

func _invariants(t: TestContext, f: Dictionary) -> void:
	var d: Dictionary = f.state.data
	var delta := 0
	for e in d.ledger_entries:
		delta += e.delta
	t.expect_equal(d.cash, 8000 + delta, "money conservation")
	var owners := {}
	for slot in d.slots.values():
		t.expect_true(slot.phase == "free" or d.patients.has(slot.patient_id), "occupied slot has real patient")
		t.expect_equal(slot.patient_id == "",slot.phase == "free","free phase and empty patient agree")
		if slot.phase in ["reserved","serving"]:
			t.expect_false(owners.has(slot.patient_id), "one active reservation per patient")
			owners[slot.patient_id] = true
	var outside := 0
	var inside := 0
	var completed := 0
	var abandoned := 0
	for p in d.patients.values():
		match p.phase:
			"outside": outside += 1
			"completed": completed += 1
			"abandoned": abandoned += 1
			_: inside += 1
	t.expect_equal(d.scheduled_arrivals.size() - d.arrival_cursor + outside + inside + completed + abandoned, d.scheduled_arrivals.size(), "patients conserved across exclusive locations")
	t.expect_equal(d.outside_queue.size(), outside, "outside membership authoritative")
	t.expect_equal(d.metrics.completed,completed,"completed count only actual terminal exits")
	t.expect_equal(d.metrics.abandoned,abandoned,"abandoned count only actual terminal exits")
	t.expect_true(inside <= 40,"inside capacity never exceeds40")
	var queued := {}
	for queue in d.queues.values():
		for id in queue:
			t.expect_true(d.patients.has(id),"queued patient exists")
			t.expect_false(queued.has(id),"patient in at most one queue")
			t.expect_false(owners.has(id),"queue membership excludes reserved service")
			queued[id] = true

func test_three_diseases_complete_and_charge_once_after_exit(t: TestContext) -> void:
	# Catches missing clinical stages, early/double income and wrong disease costs.
	var f := _fixture([_arrival("p1","echo"),_arrival("p2","motion"),_arrival("p3","sensory")])
	f.sim.advance_ticks(1700)
	t.expect_equal(f.state.data.metrics.completed, 3, "three diseases actually exit")
	t.expect_equal(f.state.data.metrics.income, 680, "all three literal fees once")
	t.expect_equal(f.state.data.metrics.treatment_cost, 135, "fast consumables 25+45+65")
	t.expect_equal(f.state.data.metrics.recovery_cost, 0, "high tolerance needs no recovery")
	for id in ["p1","p2","p3"]:
		var p: Dictionary = f.state.data.patients.get(id,{})
		t.expect_equal(p.get("phase"), "completed", "terminal after actual exit " + id)
		t.expect_false(p.has("cell"), "departed actor omits cell")
		var fees: Array = f.state.data.ledger_entries.filter(func(e): return e.event_id == "income:" + id)
		t.expect_equal(fees.size(), 1, "one fee after exit " + id)
	f.sim.advance_ticks(40)
	t.expect_equal(f.state.data.metrics.income, 680, "terminal patients never charged again")
	_invariants(t,f)

func test_low_tolerance_fast_holds_device_until_recovery_available(t: TestContext) -> void:
	# Catches releasing treatment/technician while recovery is absent or full.
	var f := _fixture([_arrival("p", "echo", 30)], ["reception","diagnosis","echo"])
	t.expect_true(_until(f,"p","waiting_recovery"), "low tolerance reaches recovery wait")
	if not f.state.data.patients.has("p"):
		return
	var room := _room(f,"echo")
	var slot: Dictionary = f.state.data.slots[room+":0"]
	t.expect_equal(slot.phase,"blocked","device held until patient walks off it")
	t.expect_equal(f.state.data.staff[f.state.data.rooms[room].staff_id].phase,"blocked","technician held")
	f.sim.advance_ticks(10)
	t.expect_equal(slot.phase,"blocked","device remains occupied throughout recovery wait")
	t.expect_equal(f.state.data.staff[f.state.data.rooms[room].staff_id].phase,"blocked","technician remains blocked throughout recovery wait")
	t.expect_equal(f.state.data.patients.get("p",{}).get("wait_reason"),"missing_room","missing recovery reason visible")
	_send(f.sim,"close_room",{"room_id":room})
	t.expect_false(_send(f.sim,"remove_room",{"room_id":room}).ok,"cannot remove busy treatment room")
	t.expect_false(_send(f.sim,"assign_staff",{"staff_id":f.state.data.rooms[room].staff_id,"room_id":""}).ok,"blocked technician cannot transfer")
	t.expect_true(_send(f.sim,"build_room",{"kind":"recovery","origin_cell":140,"rotation":0}).ok,"add recovery")
	t.expect_true(_until(f,"p","moving_recovery"), "recovery reserved before movement")
	t.expect_equal(f.state.data.metrics.recovery_cost,0,"reservation does not charge recovery consumables")
	t.expect_equal(f.state.data.staff[f.state.data.rooms[room].staff_id].phase,"blocked","technician held during first quarter of departure")
	f.sim.advance_ticks(2)
	t.expect_equal(f.state.data.staff[f.state.data.rooms[room].staff_id].phase,"blocked","technician held until whole cell departed")
	t.expect_true(_until(f,"p","recovering"), "new recovery unblocks patient")
	t.expect_equal(f.state.data.slots[room+":0"].phase,"free","device released after departure")
	t.expect_equal(f.state.data.metrics.income,0,"not charged on treatment/recovery start")
	t.expect_equal(f.state.data.metrics.recovery_cost,10,"recovery charged on actual arrival")
	t.expect_true(_until(f,"p","completed"), "recovery completes then actual exit")
	_invariants(t,f)

func test_patience_includes_walk_and_recovery_wait_but_not_service(t: TestContext) -> void:
	# Catches decrementing patience during services, missing walking or blocked wait.
	var f := _fixture([_arrival("p","echo",30)], ["reception","diagnosis","echo"])
	t.expect_true(_until(f,"p","reception_service"),"walk reaches reception")
	if not f.state.data.patients.has("p"):
		return
	var p: Dictionary = f.state.data.patients.p
	t.expect_true(p.wait_ticks > 0,"walking consumes patience")
	var before: int = p.wait_ticks
	f.sim.advance_ticks(20)
	t.expect_equal(p.wait_ticks,before,"actual reception consumes no patience")
	t.expect_true(_until(f,"p","waiting_recovery"),"wait after treatment")
	before = p.wait_ticks
	f.sim.advance_ticks(10)
	t.expect_equal(p.wait_ticks,before+10,"blocked recovery adds nonservice wait")
	f.sim.advance_ticks(1800-p.wait_ticks)
	t.expect_equal(p.phase,"abandoning","patience1800 creates abandonment intention before actual exit")
	t.expect_equal(f.state.data.metrics.abandoned,0,"in-hospital abandonment not terminal yet")
	t.expect_true(p.has("cell"),"abandoning actor remains on map")
	for slot in f.state.data.slots.values():
		t.expect_equal(slot.phase,"free","abandonment releases device and reservations first")
	t.expect_true(_until(f,"p","abandoned"),"abandoning actor follows actual exit path")
	t.expect_equal(p.phase,"abandoned","expired patient really walks out")
	t.expect_equal(f.state.data.metrics.income,0,"abandonment never earns fee")
	t.expect_equal(f.state.data.metrics.treatment_cost,25,"incurred consumables retained")
	_invariants(t,f)

func test_closing_drains_old_queue_and_allows_replacement_staff(t: TestContext) -> void:
	# Catches close dropping old queues or preventing compatible replacement staff.
	var f := _fixture([_arrival("p"),_arrival("new","echo",70,10)],["reception"],false)
	f.sim.advance_ticks(5)
	var room := _room(f,"reception")
	t.expect_equal(f.state.data.queues[room],["p"],"patient admitted to existing queue before closing")
	_send(f.sim,"close_room",{"room_id":room})
	var h := _send(f.sim,"hire_staff",{"role":"receptionist"})
	t.expect_true(_send(f.sim,"assign_staff",{"staff_id":h.data.staff_id,"room_id":room}).ok,"replacement accepted during drain")
	t.expect_true(_until(f,"p","diagnosis_queue"),"old queue completes while draining")
	t.expect_equal(f.state.data.patients.new.phase,"reception_queue","later arrival still waits for open reception")
	t.expect_equal(f.state.data.patients.new.wait_reason,"missing_room","draining room refuses new assignment")
	f.sim.advance_ticks(60)
	t.expect_equal(f.state.data.rooms[room].status,"closed","drained room closes after staff walks outside")
	t.expect_false(f.state.data.staff[h.data.staff_id].get("cell",-1) in f.state.data.rooms[room].cells,"staff outside footprint")
	t.expect_true(_send(f.sim,"remove_room",{"room_id":room}).ok,"drained room removable")
	t.expect_equal(f.state.data.staff[h.data.staff_id].room_id,"","removal retains unassigned staff")
	_invariants(t,f)

func test_busy_room_or_departing_actor_cannot_be_removed(t: TestContext) -> void:
	# Catches premature free slots and removing a room while actors leave its footprint.
	var f := _fixture([_arrival("p")])
	t.expect_true(_until(f,"p","reception_service"),"service begins")
	var room := _room(f,"reception")
	_send(f.sim,"close_room",{"room_id":room})
	t.expect_false(_send(f.sim,"remove_room",{"room_id":room}).ok,"serving prevents removal")
	t.expect_true(_until(f,"p","moving_diagnosis"),"completed reception starts real walk")
	t.expect_false(_send(f.sim,"remove_room",{"room_id":room}).ok,"departing actor prevents removal")
	f.sim.advance_ticks(100)
	t.expect_true(_send(f.sim,"remove_room",{"room_id":room}).ok,"after footprint clears remove succeeds")
	_invariants(t,f)

func test_missing_room_staff_or_path_recovers_without_ghost_slots(t: TestContext) -> void:
	# Catches sticky missing room/staff/path waits and equipment/recovery reason conflation.
	var f := _fixture([_arrival("p")],[])
	f.sim.advance_ticks(2)
	t.expect_equal(f.state.data.patients.get("p",{}).get("wait_reason"),"missing_room","missing room")
	var b := _send(f.sim,"build_room",{"kind":"reception","origin_cell":121,"rotation":0})
	f.sim.advance_ticks(1)
	t.expect_equal(f.state.data.patients.get("p",{}).get("wait_reason"),"missing_staff","missing employee")
	if not f.state.data.patients.has("p"):
		return
	var h := _send(f.sim,"hire_staff",{"role":"receptionist"})
	_send(f.sim,"assign_staff",{"staff_id":h.data.staff_id,"room_id":b.data.room_id})
	# Explicit damaged-map fixture, not an outcome: rotation makes the old service cell equipment.
	f.state.data.patients.p.cell = 121
	f.state.data.patients.p.path = []
	f.state.data.patients.p.erase("goal_cell")
	f.sim.advance_ticks(1)
	t.expect_equal(f.state.data.patients.p.wait_reason,"path_blocked","unreachable route explicit")
	f.state.data.patients.p.cell = 217
	f.state.data.patients.p.path = []
	f.state.data.patients.p.erase("goal_cell")
	t.expect_true(_until(f,"p","reception_service"),"restored route resumes reserved target")
	f.sim.advance_ticks(50)
	t.expect_equal(f.state.data.patients.p.phase,"diagnosis_queue","missing next room waits normally")
	_invariants(t,f)
	var busy := _fixture([_arrival("a","echo",30),_arrival("b","echo",30)], ["reception","diagnosis","echo","recovery"])
	t.expect_true(_until(busy,"a","recovering"),"first recovery occupies seat")
	t.expect_true(_until(busy,"b","waiting_recovery"),"second reaches full recovery")
	t.expect_equal(busy.state.data.patients.b.wait_reason,"recovery_full","full recovery reason")
	t.expect_equal(busy.state.data.slots[_room(busy,"echo")+":0"].phase,"blocked","full recovery holds treatment device")
	t.expect_true(_until(busy,"b","completed"),"full recovery resumes automatically")
	_invariants(t,busy)

func test_41st_arrival_waits_outside_with_original_arrival_time(t: TestContext) -> void:
	# Catches overflow dropping IDs, resetting arrival time or skipping outside patience.
	var arrivals: Array = []
	for i in range(41):
		arrivals.append(_arrival("p%02d" % i))
	var f := _fixture(arrivals,[])
	f.sim.advance_ticks(11)
	t.expect_equal(f.state.data.arrival_cursor,41,"all arrivals tracked")
	t.expect_equal(f.state.data.outside_queue,["p40"],"41st patient stays outside")
	var p: Dictionary = f.state.data.patients.get("p40",{})
	t.expect_equal(p.get("arrival_tick"),1,"original arrival preserved")
	t.expect_equal(p.get("wait_ticks"),10,"outside patience accumulated")
	t.expect_false(p.has("cell"),"outside patient is not an on-map actor")
	f.sim.advance_ticks(1900)
	t.expect_equal(f.state.data.metrics.abandoned,41,"inside and outside abandon without disappearing")
	_invariants(t,f)

func test_modes_latch_and_map_changes_replan_staff(t: TestContext) -> void:
	# Catches rewriting active treatment, ignoring overrides, and old employee destinations after relocation.
	var f := _fixture([_arrival("p","echo",30)])
	_send(f.sim,"set_auto_route",{"enabled":true})
	t.expect_true(_until(f,"p","treatment_queue"),"diagnosis exposes tolerance before treatment queue")
	t.expect_true(_send(f.sim,"set_patient_mode",{"patient_id":"p","mode":"fast"}).ok,"override accepted before start")
	t.expect_true(_until(f,"p","treatment_service"),"treatment starts")
	var room := _room(f,"echo")
	_send(f.sim,"set_room_mode",{"room_id":room,"mode":"gentle"})
	t.expect_equal(f.state.data.patients.get("p",{}).get("service_mode"),"fast","patient override beats auto route and latches")
	t.expect_equal(f.state.data.slots[room+":0"].remaining_ticks,120,"fast timing unaffected")
	t.expect_false(_send(f.sim,"set_patient_mode",{"patient_id":"p","mode":"gentle"}).ok,"active patient override rejected")
	_invariants(t,f)
	var moved := _fixture([], ["echo"])
	room = _room(moved,"echo")
	moved.sim.advance_ticks(2)
	_send(moved.sim,"close_room",{"room_id":room})
	t.expect_true(_send(moved.sim,"move_room",{"room_id":room,"origin_cell":54,"rotation":0}).ok,"empty room moved during staff walk")
	_send(moved.sim,"reopen_room",{"room_id":room})
	moved.sim.advance_ticks(2)
	t.expect_equal(moved.state.data.staff.staff_001.path_index,0,"pending route replan has normalized empty path index")
	moved.sim.advance_ticks(150)
	t.expect_equal(moved.state.data.staff.staff_001.get("cell",-1),80,"employee reaches new staff cell, not cached old goal")
	var revision: int = moved.state.data.get("map_revision",-1)
	_send(moved.sim,"build_room",{"kind":"echo","origin_cell":54,"rotation":0})
	t.expect_equal(moved.state.data.get("map_revision",-1),revision,"rejected spatial command keeps map revision")
	_invariants(t,moved)

func test_service_durations_and_exit_fee_boundary(t: TestContext) -> void:
	# Catches off-by-one service decrement, counting service as wait, and charging before exit.
	var f := _fixture([_arrival("p","echo",30)])
	for row in [["reception_service","reception",40],["diagnosis_service","diagnosis",80],["treatment_service","echo",120],["recovering","recovery",400]]:
		t.expect_true(_until(f,"p",row[0]),"reaches " + row[0])
		var p: Dictionary = f.state.data.patients.get("p",{})
		if p.is_empty():
			return
		var slot: Dictionary = f.state.data.slots[_room(f,row[1])+":0"]
		t.expect_equal(slot.remaining_ticks,row[2],"full duration on service start")
		var wait_before: int = p.wait_ticks
		f.sim.advance_ticks(row[2]-1)
		t.expect_equal(slot.remaining_ticks,1,"service lasts full specified tick count")
		t.expect_equal(p.phase,row[0],"still serving before final tick")
		t.expect_equal(p.wait_ticks,wait_before,"service excluded from nonservice wait")
		f.sim.advance_ticks(1)
		t.expect_false(p.phase == row[0],"final service tick transitions")
		t.expect_equal(p.wait_ticks,wait_before,"final service tick excluded from wait")
	t.expect_equal(f.state.data.patients.p.phase,"leaving","all necessary services then real exit walk")
	t.expect_equal(f.state.data.metrics.income,0,"no fee during exit walk")
	t.expect_true(_until(f,"p","completed"),"actual exit")
	var p: Dictionary = f.state.data.patients.p
	t.expect_equal(p.exit_tick-p.arrival_tick,p.wait_ticks+640,"all elapsed intervals accounted as wait or 40+80+120+400 service")
	t.expect_equal(f.state.data.metrics.patient_totals.p.wait_ticks,p.wait_ticks,"terminal summary includes last exit walking tick")
	t.expect_equal(f.state.data.metrics.operating_profit,115,"150 fee minus25 treatment minus10 recovery, no double financial metric")
	_invariants(t,f)

func test_fifo_busy_wait_and_mode_precedence(t: TestContext) -> void:
	# Catches unstable same-tick queue order, sticky busy waits, and choosing room defaults over auto routing.
	var f := _fixture([_arrival("b"),_arrival("a")])
	t.expect_true(_until(f,"a","reception_service"),"same arrival tick sorts stable ID before admission insertion order")
	t.expect_equal(f.state.data.patients.b.wait_reason,"equipment_busy","busy device distinct reason")
	t.expect_true(_until(f,"b","completed"),"equipment busy queue recovers")
	t.expect_true(f.state.data.patients.a.exit_tick < f.state.data.patients.b.exit_tick,"FIFO maintained through real services")
	_invariants(t,f)
	for row in [[30,true,"fast","gentle",15],[70,true,"gentle","fast",25],[70,false,"gentle","gentle",15]]:
		var routed := _fixture([_arrival("p","echo",row[0])])
		_send(routed.sim,"set_auto_route",{"enabled":row[1]})
		_send(routed.sim,"set_room_mode",{"room_id":_room(routed,"echo"),"mode":row[2]})
		t.expect_true(_until(routed,"p","treatment_service"),"routed service starts")
		t.expect_equal(routed.state.data.patients.p.service_mode,row[3],"auto route then room default precedence")
		_send(routed.sim,"set_room_mode",{"room_id":_room(routed,"echo"),"mode":"fast" if row[3] == "gentle" else "gentle"})
		t.expect_true(_until(routed,"p","completed"),"routed service exits")
		t.expect_equal(routed.state.data.metrics.treatment_cost,row[4],"latched consumable cost")
		t.expect_equal(routed.state.data.metrics.recovery_cost,0,"gentle low or fast high avoid recovery")
		_invariants(t,routed)

func test_outside_patient_promotes_without_resetting_wait(t: TestContext) -> void:
	# Catches resetting patience or arrival timestamp when an inside actor exits and frees capacity.
	var arrivals: Array = []
	for index in range(41):
		arrivals.append(_arrival("p%02d" % index))
	var f := _fixture(arrivals)
	f.sim.advance_ticks(2)
	t.expect_equal(f.state.data.patients.p40.phase,"outside","capacity remains40 during real treatment")
	t.expect_true(_until(f,"p40","reception_queue"),"outside patient enters after real exit frees capacity")
	var p: Dictionary = f.state.data.patients.get("p40",{})
	if p.is_empty():
		return
	t.expect_equal(p.arrival_tick,1,"promotion preserves scheduled arrival")
	t.expect_true(p.admitted_tick > 300,"waited for an actual full visit")
	t.expect_equal(p.wait_ticks,p.admitted_tick-1,"outside wait not reset on promotion")
	t.expect_equal(p.wait_by_stage.outside,p.admitted_tick-1,"outside wait remains available for fair metrics")
	t.expect_equal(f.state.data.outside_queue,[],"promoted patient removed from outside queue")
	_invariants(t,f)

func test_unrelated_map_edit_retains_route_and_progress(t: TestContext) -> void:
	# Catches invalidating every actor's route after an unrelated spatial command.
	var f := _fixture([], ["echo"])
	f.sim.advance_ticks(2)
	var employee: Dictionary = f.state.data.staff.staff_001
	var route: Array = employee.path.duplicate()
	t.expect_equal(employee.move_progress,2,"two ticks advance half a cell")
	t.expect_true(_send(f.sim,"build_room",{"kind":"recovery","origin_cell":140,"rotation":0}).ok,"unrelated room build succeeds")
	f.sim.advance_ticks(2)
	# CommandBus commits a copy, so read the authoritative actor again.
	employee = f.state.data.staff.staff_001
	t.expect_equal(employee.path,route,"still-valid route retained after map revision")
	t.expect_equal(employee.cell,193,"four ticks still move exactly one cell")
	t.expect_equal(employee.move_progress,0,"no movement progress lost on unrelated edit")
	_invariants(t,f)
