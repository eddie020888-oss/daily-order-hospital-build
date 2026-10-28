class_name CommandBus
extends RefCounted

const TREATMENT_KINDS := ["echo", "motion", "sensory"]
const ROOM_COMMANDS := ["move_room", "remove_room", "close_room", "reopen_room", "upgrade_recovery", "set_room_mode"]
const STARTED_PHASES := ["treatment_service", "waiting_recovery", "moving_recovery", "recovering", "leaving", "abandoning", "completed", "abandoned"]

# Validate and stage the entire command on a private state. Rejected commands
# never consume IDs, receipts, funds or entity changes in the caller's state.
static func apply(state: ClinicState, catalog: ContentCatalog, command: Dictionary) -> Dictionary:
	if CampaignContent.is_campaign(state.data): return CampaignCommands.apply(state,catalog,command)
	if not command.get("id") is String or command.id.is_empty() or not command.get("type") is String or not command.get("payload") is Dictionary:
		return _reject("invalid_command")
	if state.data.command_receipts.has(command.id):
		return state.data.command_receipts[command.id].duplicate(true)
	if state.data.challenge.status != "running":
		return _reject("challenge_ended")
	var candidate := ClinicState.new()
	candidate.data = state.to_data()
	var result := _dispatch(candidate, catalog, command.type, command.payload, "command:" + command.id)
	if not result.ok:
		return result
	# Receipt bodies are saved model data too; reject unsupported extra values
	# without publishing the staged transaction. Depth also bounds cyclic input.
	if not _is_model_value(command):
		return _reject("invalid_command")
	if command.type in ["build_room", "move_room", "remove_room", "upgrade_recovery"]:
		candidate.data.map_revision = candidate.data.get("map_revision", 0) + 1
	candidate.data.command_sequence += 1
	result.data.tick = candidate.data.tick
	result.data.sequence = candidate.data.command_sequence
	result.data.command = command.duplicate(true)
	candidate.data.command_receipts[command.id] = result.duplicate(true)
	state.data = candidate.data
	return result.duplicate(true)

static func _dispatch(state: ClinicState, catalog: ContentCatalog, type: String, payload: Dictionary, event_id: String) -> Dictionary:
	if type in ROOM_COMMANDS:
		if not payload.get("room_id") is String:
			return _reject("invalid_payload")
		if not state.data.rooms.has(payload.room_id):
			return _reject("unknown_room")
	match type:
		"build_room": return _build(state, catalog, payload, event_id)
		"move_room": return _move(state, catalog, payload, event_id)
		"remove_room": return _remove(state, payload.room_id, event_id)
		"close_room":
			state.data.rooms[payload.room_id].status = "draining"
			return _ok({"room_id":payload.room_id})
		"reopen_room":
			state.data.rooms[payload.room_id].status = "open"
			return _ok({"room_id":payload.room_id})
		"upgrade_recovery": return _upgrade(state, catalog, payload.room_id, event_id)
		"hire_staff": return _hire(state, catalog, payload, event_id)
		"dismiss_staff": return _dismiss(state, payload)
		"assign_staff": return _assign(state, catalog, payload)
		"set_room_mode":
			if state.data.rooms[payload.room_id].kind not in TREATMENT_KINDS:
				return _reject("not_treatment_room")
			if not _valid_mode(payload.get("mode")):
				return _reject("invalid_mode")
			state.data.rooms[payload.room_id].mode = payload.mode
			return _ok({"room_id":payload.room_id})
		"set_auto_route":
			if not payload.get("enabled") is bool:
				return _reject("invalid_payload")
			state.data.auto_route = payload.enabled
			return _ok()
		"set_patient_mode": return _patient_mode(state, payload)
		"set_paused":
			if not payload.get("paused") is bool:
				return _reject("invalid_payload")
			state.data.paused = payload.paused
			return _ok()
		"set_speed":
			if not payload.get("speed") is int or payload.speed not in [1,2]:
				return _reject("invalid_speed")
			state.data.speed = payload.speed
			return _ok()
	return _reject("unknown_command")

static func _build(state: ClinicState, catalog: ContentCatalog, payload: Dictionary, event_id: String) -> Dictionary:
	if not payload.get("kind") is String or not catalog.rooms.has(payload.kind):
		return _reject("unknown_kind")
	if payload.kind not in state.data.unlocked_room_kinds:
		return _reject("room_locked")
	if payload.has("upgraded") or payload.has("room_id"):
		return _reject("invalid_payload")
	var cost: int = catalog.rooms[payload.kind].cost
	if payload.has("layout"):
		var layout_error := FreeRoomLayout.validate(payload.kind,payload.layout)
		if layout_error != "":
			return _reject(layout_error)
		cost = FreeRoomLayout.base_cost(payload.kind,payload.layout,catalog)
	if state.data.cash < cost:
		return _reject("insufficient_cash")
	var preview := GridService.preview(state, payload)
	if not preview.ok:
		return preview
	var id := "room_%03d" % state.data.next_ids.room
	var room: Dictionary = preview.data.room
	room.merge({"status":"open", "mode":"gentle" if state.data.get("scenario_strategy","fast") == "gentle" else "fast", "staff_id":"", "invested_cost":cost})
	state.data.rooms[id] = room
	state.data.queues[id] = []
	_sync_slots(state, id)
	if not Ledger.post(state, event_id, "capital_build", -cost, state.data.tick):
		return _reject("ledger_conflict")
	state.data.next_ids.room += 1
	return _ok({"room_id":id})

static func _move(state: ClinicState, catalog: ContentCatalog, payload: Dictionary, event_id: String) -> Dictionary:
	var room: Dictionary = state.data.rooms[payload.room_id]
	if payload.has("kind") or payload.has("upgraded"):
		return _reject("invalid_payload")
	var permission := _can_relocate(state, payload.room_id)
	if not permission.ok:
		return permission
	var proposal := {"room_id":payload.room_id, "kind":room.kind, "origin_cell":payload.get("origin_cell"), "rotation":payload.get("rotation"), "upgraded":room.upgraded}
	if payload.has("layout"):
		proposal.layout = payload.layout
	elif room.has("layout"):
		proposal.layout = room.layout
	var preview := GridService.preview(state, proposal)
	if not preview.ok:
		return preview
	if payload.has("layout"):
		var new_cost := FreeRoomLayout.base_cost(room.kind,payload.layout,catalog,room.upgraded)
		var difference: int = new_cost - room.invested_cost
		if difference > 0 and difference > state.data.cash:
			return _reject("insufficient_cash")
		if difference != 0:
			var category := "capital_build" if difference > 0 else "capital_refund"
			var delta: int = -difference if difference > 0 else (-difference * 3 / 4)
			if not Ledger.post(state,event_id,category,delta,state.data.tick):
				return _reject("ledger_conflict")
		room.invested_cost = new_cost
	for key in ["doorways","window_edges"]:
		if not preview.data.room.has(key): room.erase(key)
	room.merge(preview.data.room, true)
	_sync_slots(state, payload.room_id)
	return _ok({"room_id":payload.room_id})

static func _remove(state: ClinicState, id: String, event_id: String) -> Dictionary:
	var permission := _can_relocate(state, id)
	if not permission.ok:
		return permission
	var room: Dictionary = state.data.rooms[id]
	var refund: int = room.invested_cost * 3 / 4
	for employee in state.data.staff.values():
		if employee.get("room_id", "") == id:
			employee.room_id = ""
	state.data.rooms.erase(id)
	state.data.queues.erase(id)
	for slot_id in state.data.slots.keys():
		if state.data.slots[slot_id].room_id == id:
			state.data.slots.erase(slot_id)
	if not Ledger.post(state, event_id, "capital_refund", refund, state.data.tick):
		return _reject("ledger_conflict")
	return _ok({"room_id":id, "refund":refund})

static func _upgrade(state: ClinicState, catalog: ContentCatalog, id: String, event_id: String) -> Dictionary:
	var room: Dictionary = state.data.rooms[id]
	if room.kind != "recovery":
		return _reject("not_recovery_room")
	if room.upgraded:
		return _reject("already_upgraded")
	var cost: int = catalog.rooms.recovery.upgrade_cost
	if state.data.cash < cost:
		return _reject("insufficient_cash")
	var proposal := {"room_id":id, "kind":room.kind, "origin_cell":room.origin_cell, "rotation":room.rotation, "upgraded":true}
	if room.has("layout"):
		proposal.layout = room.layout
	var preview := GridService.preview(state, proposal)
	if not preview.ok:
		return preview
	room.merge(preview.data.room, true)
	room.invested_cost += cost
	_sync_slots(state, id)
	if not Ledger.post(state, event_id, "capital_upgrade", -cost, state.data.tick):
		return _reject("ledger_conflict")
	return _ok({"room_id":id})

static func _hire(state: ClinicState, catalog: ContentCatalog, payload: Dictionary, event_id: String) -> Dictionary:
	if not payload.get("role") is String or not catalog.staff.has(payload.role):
		return _reject("unknown_role")
	if state.data.staff.size() >= catalog.levels[state.data.level_id].max_staff:
		return _reject("staff_limit")
	var cost: int = catalog.staff[payload.role].hire_cost
	if state.data.cash < cost:
		return _reject("insufficient_cash")
	var id := "staff_%03d" % state.data.next_ids.staff
	state.data.staff[id] = {"role":payload.role, "room_id":"", "phase":"idle", "path":[], "path_index":0, "move_progress":0}
	if not Ledger.post(state, event_id, "capital_hire", -cost, state.data.tick):
		return _reject("ledger_conflict")
	state.data.next_ids.staff += 1
	return _ok({"staff_id":id})

# Only a safely withdrawn idle worker can leave. Recruitment cost and the
# monotonic next ID stay in history; repeated command IDs use normal receipts.
static func _dismiss(state: ClinicState, payload: Dictionary) -> Dictionary:
	if not payload.get("staff_id") is String: return _reject("invalid_payload")
	if not state.data.staff.has(payload.staff_id): return _reject("unknown_staff")
	var employee: Dictionary = state.data.staff[payload.staff_id]
	if employee.room_id != "": return _reject("staff_assigned", {"staff_id":payload.staff_id,"room_id":employee.room_id})
	if employee.phase != "idle" or employee.move_progress != 0 or employee.path_index + 1 < employee.path.size():
		return _reject("staff_moving", {"staff_id":payload.staff_id})
	var role: String = employee.role
	state.data.staff.erase(payload.staff_id)
	return _ok({"staff_id":payload.staff_id,"role":role})

static func _assign(state: ClinicState, catalog: ContentCatalog, payload: Dictionary) -> Dictionary:
	if not payload.get("staff_id") is String or not payload.get("room_id") is String:
		return _reject("invalid_payload")
	if not state.data.staff.has(payload.staff_id):
		return _reject("unknown_staff")
	var employee: Dictionary = state.data.staff[payload.staff_id]
	var target: String = payload.room_id
	if target != "":
		if not state.data.rooms.has(target):
			return _reject("unknown_room")
		var room: Dictionary = state.data.rooms[target]
		if catalog.rooms[room.kind].staff_role != employee.role:
			return _reject("role_mismatch")
		if room.staff_id != "" and room.staff_id != payload.staff_id:
			return _reject("room_staffed")
	if employee.room_id == target:
		return _ok({"staff_id":payload.staff_id, "room_id":target})
	if employee.phase in ["serving", "blocked"]:
		return _reject("staff_busy", {"remaining_ticks":_remaining_ticks(state, employee.room_id)})
	if employee.room_id != "" and state.data.rooms.has(employee.room_id):
		var previous: Dictionary = state.data.rooms[employee.room_id]
		if _has_work(state, employee.room_id):
			return _reject("staff_busy", {"remaining_ticks":_remaining_ticks(state, employee.room_id)})
		previous.staff_id = ""
	employee.room_id = target
	if target != "":
		state.data.rooms[target].staff_id = payload.staff_id
	return _ok({"staff_id":payload.staff_id, "room_id":target})

static func _patient_mode(state: ClinicState, payload: Dictionary) -> Dictionary:
	if not payload.get("patient_id") is String:
		return _reject("invalid_payload")
	if not state.data.patients.has(payload.patient_id):
		return _reject("unknown_patient")
	if not _valid_mode(payload.get("mode")):
		return _reject("invalid_mode")
	var patient: Dictionary = state.data.patients[payload.patient_id]
	if patient.has("care_steps"):
		return _reject("not_treatment_room")
	if patient.get("treatment_started", false) or patient.get("phase", "") in STARTED_PHASES:
		return _reject("treatment_started")
	patient.mode_override = payload.mode
	return _ok({"patient_id":payload.patient_id})

static func _valid_mode(value: Variant) -> bool:
	return value is String and value in ["fast", "gentle"]

static func _is_model_value(value: Variant, depth: int = 0) -> bool:
	if depth > 32:
		return false
	if value is Dictionary:
		for key in value:
			if (not key is String and not key is StringName) or not _is_model_value(value[key], depth + 1):
				return false
		return true
	if value is Array:
		for item in value:
			if not _is_model_value(item, depth + 1):
				return false
		return true
	return value is String or value is int or value is bool

static func _can_relocate(state: ClinicState, id: String) -> Dictionary:
	if state.data.rooms[id].status == "open":
		return _reject("room_open")
	if _has_work(state, id) or _has_actor_inside(state, id):
		return _reject("room_busy", {"room_id":id})
	return _ok()

static func _has_work(state: ClinicState, id: String) -> bool:
	if not state.data.queues.get(id, []).is_empty():
		return true
	for slot in state.data.slots.values():
		if slot.room_id == id and (slot.patient_id != "" or slot.phase != "free"):
			return true
	return false

static func _has_actor_inside(state: ClinicState, id: String) -> bool:
	var cells: Array = state.data.rooms[id].cells
	for collection in ["patients", "staff"]:
		for actor in state.data[collection].values():
			if not actor.has("cell"):
				continue
			if actor.cell in cells:
				return true
			var route: Array = actor.get("path", [])
			var index: int = actor.get("path_index", 0)
			if actor.get("move_progress", 0) > 0 and index >= 0 and index + 1 < route.size() and route[index + 1] in cells:
				return true
	return false

static func _remaining_ticks(state: ClinicState, id: String) -> int:
	var remaining := 0
	for slot in state.data.slots.values():
		if slot.room_id == id:
			remaining = maxi(remaining, slot.remaining_ticks)
	return remaining

# Existing slot progress/reservations survive geometry replacement and upgrade.
static func _sync_slots(state: ClinicState, id: String) -> void:
	var room: Dictionary = state.data.rooms[id]
	for index in range(room.service_cells.size()):
		var slot_id := id + ":" + str(index)
		if not state.data.slots.has(slot_id):
			state.data.slots[slot_id] = {"room_id":id, "cell":room.service_cells[index], "patient_id":"", "phase":"free", "remaining_ticks":0}
		state.data.slots[slot_id].cell = room.service_cells[index]

static func _ok(data: Dictionary = {}) -> Dictionary:
	return {"ok":true, "code":"ok", "data":data}

static func _reject(code: String, data: Dictionary = {}) -> Dictionary:
	return {"ok":false, "code":code, "data":data}
