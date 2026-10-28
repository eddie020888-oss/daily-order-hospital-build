class_name PatientFlow
extends RefCounted

const SERVICES := ["reception_service", "diagnosis_service", "treatment_service", "recovering", "general_exam_service", "pharmacy_service", "ward_service"]
const TERMINAL := ["completed", "abandoned"]
const QUEUES := ["reception_queue", "diagnosis_queue", "treatment_queue", "waiting_recovery", "general_exam_queue", "pharmacy_queue", "ward_queue"]

# These four entry points run once, in this order, for each fixed 100ms tick.
static func finish_services(state: ClinicState, catalog: ContentCatalog) -> void:
	var d := state.data
	# Remember the interval's starting phase: the final service tick is service,
	# while walking onto a service position is still a nonservice interval.
	for p in d.patients.values():
		if p.phase not in SERVICES and p.phase not in TERMINAL:
			p.wait_interval_tick = d.tick
			p.wait_interval_stage = p.stage if p.phase != "outside" else "outside"
	for slot_id in _ids(d.slots):
		var slot: Dictionary = d.slots[slot_id]
		if slot.phase != "serving":
			continue
		slot.remaining_ticks -= 1
		if slot.remaining_ticks == 0:
			_complete_service(state, catalog, slot)
	# A closed-to-new-arrivals room must still be recoverable when its only
	# pending work cannot reach a service position without crossing a worker.
	for id in _ids(d.patients):
		_release_unreachable_draining(state,d.patients[id])
	# Ordinary queues enter on the following tick; recovery handoffs compete
	# immediately, after every completion, in the same global FIFO order.
	# Sorting makes both room choice and queue order independent of dictionary order.
	var waiting: Array = d.patients.keys()
	waiting.sort_custom(func(a,b):
		var pa: Dictionary = d.patients[a]
		var pb: Dictionary = d.patients[b]
		return a < b if pa.get("queue_enter_tick",0) == pb.get("queue_enter_tick",0) else pa.get("queue_enter_tick",0) < pb.get("queue_enter_tick",0))
	for id in waiting:
		var p: Dictionary = d.patients[id]
		if p.phase in QUEUES and (p.queue_enter_tick < d.tick or p.stage=="recovery"):
			_schedule(state, catalog, p)
	_refresh_staff(state)

static func move_actors(state: ClinicState, catalog: ContentCatalog) -> void:
	var d := state.data
	for id in _ids(d.staff):
		var employee: Dictionary = d.staff[id]
		if not employee.has("cell"):
			employee.cell = GridService.EXIT_CELL + 1
		if employee.phase in ["serving", "blocked"]:
			continue
		var goal: int = employee.cell
		if employee.room_id != "" and d.rooms.has(employee.room_id):
			var room: Dictionary = d.rooms[employee.room_id]
			goal = _outside_goal(state,room,employee.cell) if room.status != "open" and not _has_work(state,employee.room_id) else room.staff_cells[0]
		elif employee.has("goal_cell"):
			goal = GridService.EXIT_CELL + 1
		var arrived := _walk(state, employee, goal)
		employee.phase = "idle" if arrived else "moving"
	for id in _ids(d.patients):
		var p: Dictionary = d.patients[id]
		if not p.has("cell") or p.phase in SERVICES or p.phase in TERMINAL:
			continue
		var goal: int = p.get("goal_cell",p.cell)
		if p.phase in ["leaving","abandoning"]:
			goal = GridService.EXIT_CELL
		elif p.get("slot_id","") != "":
			goal = d.slots[p.slot_id].cell
		var arrived := _walk(state,p,goal)
		if p.path.is_empty():
			p.wait_reason = "path_blocked"
		elif p.wait_reason == "path_blocked" and p.phase not in QUEUES:
			p.wait_reason = ""
		_release_departed_slots(state,p)
		if arrived and p.phase in ["leaving","abandoning"]:
			_exit(state,catalog,p)
		elif arrived and p.get("slot_id","") != "":
			_start_service(state,catalog,p)
	_refresh_staff(state)
	for id in _ids(d.rooms):
		var room: Dictionary = d.rooms[id]
		if room.status == "draining" and not _has_work(state,id) and not _actors_inside(state,room):
			room.status = "closed"

static func expire_patience(state: ClinicState, catalog: ContentCatalog) -> void:
	var d := state.data
	for id in _ids(d.patients):
		var p: Dictionary = d.patients[id]
		if p.get("wait_interval_tick",-1) == d.tick:
			p.wait_ticks += 1
			var stage: String = p.wait_interval_stage
			p.wait_by_stage[stage] = p.wait_by_stage.get(stage,0) + 1
			d.metrics.wait_ticks[stage] = d.metrics.wait_ticks.get(stage,0) + 1
		if p.phase in TERMINAL:
			if p.get("wait_interval_tick",-1) == d.tick:
				_record_total(state,p)
			continue
		if p.wait_ticks >= catalog.levels[d.level_id].patience_ticks and p.phase not in ["abandoning"] and p.phase not in SERVICES:
			p.abandon_tick = d.tick
			p.phase = "abandoning"
			p.stage = "exit"
			p.wait_reason = ""
			_clear_membership(state,p)
			if not p.has("cell"):
				# An outside patient already is beyond the exit; no phantom actor.
				_exit(state,catalog,p)
	_refresh_staff(state)

static func admit_arrivals(state: ClinicState, catalog: ContentCatalog) -> void:
	var d := state.data
	while d.arrival_cursor < d.scheduled_arrivals.size() and d.scheduled_arrivals[d.arrival_cursor].tick <= d.tick:
		var arrival: Dictionary = d.scheduled_arrivals[d.arrival_cursor]
		var p := {"id":arrival.id, "disease_id":arrival.disease_id, "tolerance":arrival.tolerance,
			"tolerance_revealed":false, "arrival_tick":arrival.tick, "admitted_tick":-1,
			"exit_tick":-1, "abandon_tick":-1, "phase":"outside", "stage":"reception",
			"wait_ticks":0, "wait_by_stage":{}, "wait_reason":"hospital_full",
			"room_id":"", "slot_id":"", "queue_enter_tick":arrival.tick,
			"treatment_started":false, "services_complete":false,
			"path":[], "path_index":0, "move_progress":0, "walked_cells":0}
		var care: Array=catalog.diseases[arrival.disease_id].get("care_steps",[])
		if not care.is_empty():
			p["care_steps"]=care.duplicate()
			p["care_cursor"]=0
			p["care_started_ticks"]={}
			p["care_completed_ticks"]={}
		d.patients[arrival.id] = p
		d.outside_queue.append(arrival.id)
		d.arrival_cursor += 1
	var inside := 0
	for p in d.patients.values():
		if p.has("cell"):
			inside += 1
	while inside < catalog.levels[d.level_id].max_patients and not d.outside_queue.is_empty():
		var id: String = d.outside_queue.pop_front()
		var p: Dictionary = d.patients[id]
		p.cell = GridService.EXIT_CELL
		p.admitted_tick = d.tick
		_enter_stage(state,p,"reception")
		# Outside time remains part of both arrival time and patience.
		inside += 1

static func _complete_service(state: ClinicState, catalog: ContentCatalog, slot: Dictionary) -> void:
	var p: Dictionary = state.data.patients[slot.patient_id]
	var room: Dictionary = state.data.rooms[slot.room_id]
	slot.phase = "blocked"
	p.slot_id = ""
	p.goal_cell = _outside_goal(state,room,p.cell)
	if p.stage in ClinicalPathways.CARE_STAGES:
		p.care_completed_ticks[p.stage]=state.data.tick
		p.care_cursor+=1
		if p.care_cursor<p.care_steps.size():
			_enter_stage(state,p,p.care_steps[p.care_cursor])
		else:
			p.services_complete=true
			p.phase="leaving"
			p.stage="exit"
		return
	match p.stage:
		"reception": _enter_stage(state,p,"diagnosis")
		"diagnosis":
			p.tolerance_revealed = true
			_enter_stage(state,p,p.care_steps[0] if p.has("care_steps") else "treatment")
		"treatment":
			if p.needs_recovery:
				# Stay on the device until a recovery position is reserved.
				p.goal_cell = p.cell
				_enter_stage(state,p,"recovery")
			else:
				p.services_complete = true
				p.phase = "leaving"
				p.stage = "exit"
		"recovery":
			p.services_complete = true
			p.phase = "leaving"
			p.stage = "exit"

static func _enter_stage(state: ClinicState, p: Dictionary, stage: String) -> void:
	p.stage = stage
	p.phase = "waiting_recovery" if stage == "recovery" else stage + "_queue"
	p.queue_enter_tick = state.data.tick
	p.room_id = ""
	p.wait_reason = ""

static func _schedule(state: ClinicState, catalog: ContentCatalog, p: Dictionary) -> void:
	var d := state.data
	var kind: String = ClinicalPathways.current_room_kind(p,catalog)
	if kind=="recovery":
		_schedule_recovery(state,p)
		return
	# Only new care departments release unreserved queues when closed to arrivals.
	# Keep queue age, previous blocked devices and the legacy draining contract.
	if p.stage in ClinicalPathways.CARE_STAGES and p.phase in QUEUES and p.slot_id=="" and p.room_id!="":
		if d.rooms[p.room_id].status in ["draining","closed"]:
			d.queues[p.room_id].erase(p.id)
			p.room_id=""
	var candidates: Array = []
	var staffed: Array = []
	for id in _ids(d.rooms):
		var candidate: Dictionary = d.rooms[id]
		if candidate.kind != kind or candidate.status != "open": continue
		candidates.append(id)
		var employee: Dictionary = d.staff.get(candidate.staff_id,{})
		if employee.get("room_id","") == id and employee.get("role","") == catalog.rooms[kind].staff_role:
			staffed.append(id)
	# Prefer assigned matching staff, even if they are still walking to work.
	# Only an unreserved open-room queue may transfer; draining work and all
	# prior blocked devices keep their existing ownership and clinical clocks.
	if p.room_id != "" and p.phase in QUEUES and p.slot_id == "" and not staffed.is_empty():
		if d.rooms[p.room_id].status == "open" and p.room_id not in staffed:
			d.queues[p.room_id].erase(p.id)
			p.room_id = ""
	if p.room_id == "":
		if not staffed.is_empty(): candidates = staffed
		if candidates.is_empty():
			p.wait_reason = "missing_room"
			return
		candidates.sort_custom(func(a,b): return a < b if d.queues[a].size() == d.queues[b].size() else d.queues[a].size() < d.queues[b].size())
		p.room_id = candidates[0]
		d.queues[p.room_id].append(p.id)
	var room: Dictionary = d.rooms[p.room_id]
	var queue: Array = d.queues[p.room_id]
	queue.sort_custom(func(a,b): return a < b if d.patients[a].queue_enter_tick == d.patients[b].queue_enter_tick else d.patients[a].queue_enter_tick < d.patients[b].queue_enter_tick)
	if kind != "recovery" and (room.staff_id == "" or not d.staff.has(room.staff_id)):
		p.wait_reason = "missing_staff"
		return
	if kind in ["pharmacy","ward"]:
		var nurse: Dictionary=d.staff[room.staff_id]
		if nurse.get("cell",-1)!=room.staff_cells[0] or nurse.get("move_progress",0)!=0:
			p.wait_reason="missing_staff"
			return
	var available := ""
	var had_free := false
	for slot_id in _ids(d.slots):
		var slot: Dictionary = d.slots[slot_id]
		if slot.room_id == p.room_id and slot.phase == "free":
			had_free = true
			if GridService.path_avoiding(state,p.cell,slot.cell,_work_positions(state,p,slot.cell)).is_empty(): continue
			available = slot_id
			break
	if available == "" or queue[0] != p.id:
		p.wait_reason = "path_blocked" if had_free and queue[0] == p.id else ("recovery_full" if kind == "recovery" else "equipment_busy")
		return
	var slot: Dictionary = d.slots[available]
	queue.erase(p.id)
	slot.patient_id = p.id
	slot.phase = "reserved"
	p.slot_id = available
	p.phase = "moving_" + p.stage
	p.wait_reason = ""

# Called in global queue-entry-tick / patient-ID order. Existing reservations
# never enter here; a draining room remains eligible only for its own old queue.
static func _schedule_recovery(state: ClinicState, p: Dictionary) -> void:
	var d:=state.data
	var eligible: Array=[]
	var had_free:=false
	for room_id in _ids(d.rooms):
		var room: Dictionary=d.rooms[room_id]
		if room.kind!="recovery": continue
		if room.status!="open" and not (room.status=="draining" and p.room_id==room_id): continue
		eligible.append(room_id)
		for sid in _ids(d.slots):
			var slot: Dictionary=d.slots[sid]
			if slot.room_id!=room_id or slot.phase!="free" or slot.patient_id!="": continue
			had_free=true
			if GridService.path_avoiding(state,p.cell,slot.cell,_work_positions(state,p,slot.cell)).is_empty(): continue
			for queue in d.queues.values(): queue.erase(p.id)
			p.room_id=room_id
			p.slot_id=sid
			p.phase="moving_recovery"
			p.wait_reason=""
			slot.patient_id=p.id
			slot.phase="reserved"
			return
	if eligible.is_empty():
		p.wait_reason="missing_room"
		return
	if p.room_id=="":
		p.room_id=eligible[0]
		d.queues[p.room_id].append(p.id)
	p.wait_reason="path_blocked" if had_free else "recovery_full"

# Closing preserves reachable old work. Only an unreachable unstarted queue
# or reservation is detached; completed-but-occupied devices remain owned until
# the patient actually walks off them through _release_departed_slots.
static func _release_unreachable_draining(state: ClinicState, p: Dictionary) -> void:
	if p.phase not in QUEUES and not p.phase.begins_with("moving_"): return
	if p.room_id == "" or p.move_progress > 0: return
	var room: Dictionary = state.data.rooms[p.room_id]
	if room.status != "draining": return
	var goals: Array = room.service_cells
	if p.slot_id != "":
		var slot: Dictionary = state.data.slots[p.slot_id]
		if slot.phase != "reserved" or slot.remaining_ticks != 0: return
		goals = [slot.cell]
	elif p.phase not in QUEUES:
		return
	for goal in goals:
		if not GridService.path_avoiding(state,p.cell,goal,_work_positions(state,p,goal)).is_empty(): return
	var exit_room: Dictionary = {}
	for id in _ids(state.data.slots):
		var previous: Dictionary = state.data.slots[id]
		if previous.phase == "blocked" and previous.patient_id == p.id:
			exit_room = state.data.rooms[previous.room_id]
			break
	if exit_room.is_empty():
		for id in _ids(state.data.rooms):
			if p.cell in state.data.rooms[id].cells:
				exit_room = state.data.rooms[id]
				break
	p.goal_cell = p.cell if exit_room.is_empty() else _outside_goal(state,exit_room,p.cell)
	state.data.queues[p.room_id].erase(p.id)
	if p.slot_id != "": _free(state.data.slots[p.slot_id])
	p.slot_id = ""
	p.room_id = ""
	p.phase = "waiting_recovery" if p.stage == "recovery" else p.stage + "_queue"
	p.wait_reason = "missing_room"

static func _start_service(state: ClinicState, catalog: ContentCatalog, p: Dictionary) -> void:
	var d := state.data
	var slot: Dictionary = d.slots[p.slot_id]
	var room: Dictionary = d.rooms[slot.room_id]
	if room.kind != "recovery":
		if room.staff_id == "" or not d.staff.has(room.staff_id):
			p.wait_reason = "missing_staff"
			return
		var employee: Dictionary = d.staff[room.staff_id]
		var parallel_care: bool=room.kind=="ward" and employee.role=="nurse"
		if employee.get("cell",-1) != room.staff_cells[0] or employee.get("move_progress",0) != 0 or (employee.phase in ["serving","blocked"] and not parallel_care):
			p.wait_reason = "missing_staff"
			return
		employee.phase = "serving"
	p.wait_reason = ""
	slot.phase = "serving"
	slot.remaining_ticks = catalog.rooms[room.kind].service_ticks
	p.phase = p.stage + "_service"
	if p.stage in ClinicalPathways.CARE_STAGES:
		p.care_started_ticks[p.stage]=d.tick
		Ledger.post(state,"care:"+p.id+":"+p.stage,"treatment_cost",-int(catalog.rooms[room.kind].get("consumable_cost",0)),d.tick)
	elif p.stage == "treatment":
		var disease: Dictionary = catalog.diseases[p.disease_id]
		var mode: String = p.get("mode_override", "")
		if mode == "":
			mode = ("gentle" if disease.modes.fast.stimulus > p.tolerance else "fast") if d.auto_route else room.mode
		var rule: Dictionary = disease.modes[mode]
		p.treatment_started = true
		p.service_mode = mode
		p.treatment_start_tick = d.tick
		p.needs_recovery = rule.stimulus > p.tolerance
		slot.remaining_ticks = rule.duration_ticks
		Ledger.post(state,"treatment:"+p.id,"treatment_cost",-rule.cost,d.tick)
	elif p.stage == "recovery":
		p.phase = "recovering"
		p.recovery_start_tick = d.tick
		Ledger.post(state,"recovery:"+p.id,"recovery_cost",-catalog.rooms.recovery.consumable_cost,d.tick)

# Cached routes change only on goal/map changes. Finish an already traversed
# quarter-edge before replanning; map transactions protect that exact edge.
static func _outside_goal(state: ClinicState, room: Dictionary, from_cell: int) -> int:
	var doorways: Array = room.get("doorways",[])
	if doorways.size()<2:
		return room.door_outside_cell
	var goal: int = room.door_outside_cell
	var best := 2147483647
	for doorway in doorways:
		var route := GridService.path(state,from_cell,doorway.door_outside_cell)
		if not route.is_empty() and route.size()<best:
			best = route.size()
			goal = doorway.door_outside_cell
	return goal

static func _walk(state: ClinicState, actor: Dictionary, goal: int) -> bool:
	var work_positions := _work_positions(state,actor,goal)
	# An old save/cache can already be on an edge towards a reserved work
	# position. Back out one quarter per tick, then replan at the original cell;
	# never snap forward through a worker or freeze on that edge indefinitely.
	var old_index: int=actor.get("path_index",0)
	if actor.move_progress>0 and old_index+1<actor.path.size() and work_positions.has(actor.path[old_index+1]):
		actor.move_progress-=1
		return false
	var revision: int = state.data.get("map_revision",0)
	if actor.get("route_goal_cell",-1) == goal and actor.get("route_revision",-1) != revision and _route_usable(state,actor):
		actor.route_revision = revision
	var changed: bool = actor.get("route_goal_cell",-1) != goal or actor.get("route_revision",-1) != revision
	# Assignments/arrivals do not alter map_revision. At a cell boundary, old
	# routes must also respect newly reserved work positions, including loads.
	if actor.move_progress==0:
		for index in range(old_index+1,actor.path.size()):
			if work_positions.has(actor.path[index]):
				changed=true
				break
	if changed and actor.move_progress > 0:
		actor.move_progress += 1
		if actor.move_progress == 4:
			actor.path_index += 1
			actor.cell = actor.path[actor.path_index]
			actor.walked_cells = actor.get("walked_cells",0) + 1
			actor.move_progress = 0
			actor.path = []
			actor.path_index = 0
			actor.route_revision = -1
		return false
	if changed or actor.path.is_empty():
		actor.goal_cell = goal
		actor.route_goal_cell = goal
		actor.route_revision = revision
		actor.path = GridService.path_avoiding(state,actor.cell,goal,work_positions)
		actor.path_index = 0
		actor.move_progress = 0
	if actor.path.is_empty():
		return false
	if actor.cell == goal:
		return true
	actor.move_progress += 1
	if actor.move_progress == 4:
		actor.path_index += 1
		actor.cell = actor.path[actor.path_index]
		actor.walked_cells = actor.get("walked_cells",0) + 1
		actor.move_progress = 0
	return actor.cell == goal

# Reserve assigned work positions even while their worker is approaching.
# Only that worker may target its own position; any legacy occupant may leave.
# Actors in shared entrances/corridors are not turned into permanent map walls.
static func _work_positions(state: ClinicState, actor: Dictionary, goal: int) -> Dictionary:
	var positions := {}
	for id in state.data.rooms:
		var room: Dictionary=state.data.rooms[id]
		if room.get("staff_id","")=="" or not state.data.staff.has(room.staff_id): continue
		for cell in room.staff_cells:
			if int(cell)==int(actor.cell): continue
			if int(cell)==goal and actor.has("role") and actor.get("room_id","")==id: continue
			positions[cell]=true
	return positions

# A map revision triggers a cheap remaining-edge check, not a new BFS for
# unaffected actors. Command previews already protect the edge in flight.
static func _route_usable(state: ClinicState, actor: Dictionary) -> bool:
	if actor.path.is_empty():
		return false
	var cells := {}
	var edges := {}
	for i in range(actor.path_index,actor.path.size()):
		cells[actor.path[i]] = true
		if i + 1 < actor.path.size():
			var a: int = actor.path[i]
			var b: int = actor.path[i+1]
			edges[str(mini(a,b))+":"+str(maxi(a,b))] = true
	for room in state.data.rooms.values():
		for cell in room.equipment_cells + room.get("furniture_cells",[]):
			if cells.has(cell):
				return false
		for edge in room.wall_edges:
			if edges.has(str(edge[0])+":"+str(edge[1])):
				return false
	return true

static func _release_departed_slots(state: ClinicState, p: Dictionary) -> void:
	for slot in state.data.slots.values():
		if slot.patient_id == p.id and slot.phase == "blocked" and p.cell != slot.cell:
			_free(slot)

static func _clear_membership(state: ClinicState, p: Dictionary) -> void:
	for queue in state.data.queues.values():
		queue.erase(p.id)
	state.data.outside_queue.erase(p.id)
	for slot in state.data.slots.values():
		if slot.patient_id == p.id:
			_free(slot)
	p.slot_id = ""
	p.room_id = ""

static func _free(slot: Dictionary) -> void:
	slot.patient_id = ""
	slot.phase = "free"
	slot.remaining_ticks = 0

static func _exit(state: ClinicState, catalog: ContentCatalog, p: Dictionary) -> void:
	var abandoned: bool = p.abandon_tick >= 0
	p.phase = "abandoned" if abandoned else "completed"
	p.exit_tick = state.data.tick
	p.erase("cell")
	p.path = []
	p.path_index = 0
	p.move_progress = 0
	_clear_membership(state,p)
	if abandoned:
		state.data.metrics.abandoned += 1
	elif p.services_complete:
		Ledger.post(state,"income:"+p.id,"income",catalog.diseases[p.disease_id].income,state.data.tick)
		state.data.metrics.completed += 1
	_record_total(state,p)

static func _record_total(state: ClinicState, p: Dictionary) -> void:
	state.data.metrics.patient_totals[p.id] = {"arrival_tick":p.arrival_tick,"admitted_tick":p.admitted_tick,
		"exit_tick":p.exit_tick,"phase":p.phase,"wait_ticks":p.wait_ticks,
		"wait_by_stage":p.wait_by_stage.duplicate(true),"walked_cells":p.walked_cells,
		"total_ticks":p.exit_tick-p.arrival_tick}

static func _refresh_staff(state: ClinicState) -> void:
	for employee in state.data.staff.values():
		if employee.phase in ["serving","blocked"]:
			employee.phase = "idle"
		var occupation: String=ClinicalPathways.staff_occupation(state.data.slots,employee.room_id)
		if occupation!="": employee.phase=occupation

static func _has_work(state: ClinicState, id: String) -> bool:
	if not state.data.queues[id].is_empty():
		return true
	for slot in state.data.slots.values():
		if slot.room_id == id and slot.phase != "free":
			return true
	return false

static func _actors_inside(state: ClinicState, room: Dictionary) -> bool:
	for actors in [state.data.patients,state.data.staff]:
		for actor in actors.values():
			if actor.has("cell"):
				if actor.cell in room.cells:
					return true
				if actor.move_progress > 0 and actor.path[actor.path_index+1] in room.cells:
					return true
	return false

static func _ids(records: Dictionary) -> Array:
	var ids := records.keys()
	ids.sort()
	return ids
