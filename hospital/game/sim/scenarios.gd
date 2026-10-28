class_name Scenarios
extends RefCounted

const ROOM_KINDS := ["reception","diagnosis","echo","motion","sensory","recovery"]
const STANDARD := [["reception",121,0],["diagnosis",100,0],["echo",104,0],["motion",108,0],["sensory",112,0],["recovery",140,0]]
const LONGER_WALK := [["reception",25,0],["diagnosis",28,0],["echo",32,0],["motion",36,0],["sensory",40,0],["recovery",308,2]]

static func create_sim(catalog: ContentCatalog, scenario_id: String, strategy: String, layout_id: String) -> Simulation:
	if scenario_id not in ["level_01","benchmark_18","load_40"] or strategy not in ["fast","gentle","tolerance"] or layout_id not in ["standard","longer_walk"]:
		return null
	var state := ClinicState.create("level_01",catalog)
	state.data.scenario_id = scenario_id
	state.data.scenario_strategy = strategy
	state.data.scenario_layout = layout_id
	var sim := Simulation.new(catalog,state)
	if strategy == "tolerance":
		if not _command(sim,"route","set_auto_route",{"enabled":true}):
			return null
	if scenario_id == "level_01":
		return sim
	state.data.unlocked_room_kinds = ROOM_KINDS.duplicate()
	state.data.hint_flags.disabled = true
	state.data.scheduled_arrivals = []
	state.data.next_ids.patient = 1
	for row in STANDARD if layout_id == "standard" else LONGER_WALK:
		var result := sim.submit({"id":"setup_build_"+row[0],"type":"build_room","payload":{"kind":row[0],"origin_cell":row[1],"rotation":row[2]}})
		if not result.ok:
			return null
		var room_id: String = result.data.room_id
		if row[0] in ["echo","motion","sensory"] and strategy == "gentle":
			if not _command(sim,"mode_"+row[0],"set_room_mode",{"room_id":room_id,"mode":"gentle"}):
				return null
		if row[0] == "recovery":
			continue
		var hire := sim.submit({"id":"setup_hire_"+row[0],"type":"hire_staff","payload":{"role":catalog.rooms[row[0]].staff_role}})
		if not hire.ok or not _command(sim,"assign_"+row[0],"assign_staff",{"staff_id":hire.data.staff_id,"room_id":room_id}):
			return null
	if scenario_id == "benchmark_18":
		# Three disease cycles; each disease independently alternates high then low.
		for i in range(18):
			_append_arrival(state,200+100*i)
	else:
		for i in range(3):
			if not _command(sim,"load_hire_"+str(i),"hire_staff",{"role":"technician"}):
				return null
		replenish_load(state,catalog)
	if not _command(sim,"start","set_paused",{"paused":false}):
		return null
	return sim

static func _command(sim: Simulation, id: String, type: String, payload: Dictionary) -> bool:
	return sim.submit({"id":"setup_"+id,"type":type,"payload":payload}).ok

static func _append_arrival(state: ClinicState, tick: int) -> void:
	var index: int = state.data.next_ids.patient-1
	state.data.scheduled_arrivals.append({"id":"patient_%06d" % (index+1),"tick":tick,"disease_id":["echo","motion","sensory"][index%3],"tolerance":70 if (index/3)%2 == 0 else 30})
	state.data.next_ids.patient += 1

# Dedicated perf fixture only: replace actual exits using monotonically allocated
# IDs, retaining every original terminal record and complete arrival history.
static func replenish_load(state: ClinicState, catalog: ContentCatalog) -> void:
	var inside := 0
	for p in state.data.patients.values():
		if p.has("cell"):
			inside += 1
	for _i in range(40-inside):
		_append_arrival(state,state.data.tick)
	PatientFlow.admit_arrivals(state,catalog)
