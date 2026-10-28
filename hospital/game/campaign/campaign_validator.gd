class_name CampaignValidator
extends RefCounted

const RULESET: String = "full-hospital-v1"
const MAX_INTEGER: int = 9007199254740991
const INITIAL_RESOURCES: Dictionary = {"supplies":40,"sterile":8,"blood":4,"samples":0,"prepared":0,"waste":0,"water":20,"food":20,"spares":6}
const PATIENT_PHASES: Array = ["care_queue","moving_care","care_service","waiting_support","moving_exit","left","abandoned"]

# The campaign is a separate model. No legacy snapshot is normalized or
# upgraded by this validator, and validation never repairs the caller's data.
static func validate(d: Dictionary, catalog: ContentCatalog) -> String:
	if catalog == null or not _model(d): return "invalid_campaign_model"
	if d.get("schema_version") != 2: return "incompatible_campaign_schema"
	if d.get("ruleset") != RULESET or d.get("content_version") != catalog.content_version: return "incompatible_campaign_content"
	if not _fields(d, {"level_id":TYPE_STRING,"tick":TYPE_INT,"paused":TYPE_BOOL,"speed":TYPE_INT,"cash":TYPE_INT,"next_ids":TYPE_DICTIONARY,"command_sequence":TYPE_INT,"map_revision":TYPE_INT,"rooms":TYPE_DICTIONARY,"staff":TYPE_DICTIONARY,"patients":TYPE_DICTIONARY,"facilities":TYPE_DICTIONARY,"slots":TYPE_DICTIONARY,"queues":TYPE_DICTIONARY,"work_orders":TYPE_DICTIONARY,"resources":TYPE_DICTIONARY,"evidence":TYPE_DICTIONARY,"campaign":TYPE_DICTIONARY,"ledger_entries":TYPE_ARRAY,"command_receipts":TYPE_DICTIONARY,"metrics":TYPE_DICTIONARY,"challenge":TYPE_DICTIONARY}): return "invalid_campaign_fields"
	if not catalog.campaign.get("levels",{}).has(d.level_id) or not catalog.levels.has(d.level_id): return "unknown_campaign_level"
	var level: Dictionary = catalog.levels[d.level_id]
	if level.get("ruleset") != RULESET: return "invalid_campaign_level"
	if d.tick < 0 or d.tick > level.end_tick or d.speed not in [1,2] or d.cash < 0 or d.command_sequence < 0 or d.map_revision < 0: return "invalid_campaign_clock"
	if d.has("appearance_seed") and (not d.appearance_seed is int or d.appearance_seed < 1 or d.appearance_seed > 2147483647): return "invalid_appearance_seed"
	if not _fields(d.next_ids,{"room":TYPE_INT,"staff":TYPE_INT,"patient":TYPE_INT,"facility":TYPE_INT,"work_order":TYPE_INT}): return "invalid_campaign_next_ids"
	for number: Variant in d.next_ids.values():
		if not number is int or number < 1: return "invalid_campaign_next_ids"
	var error: String = _campaign(d,catalog)
	if error != "": return error
	error = _entities(d,catalog)
	if error != "": return error
	error = _patients(d,catalog)
	if error != "": return error
	error = _orders(d,catalog)
	if error != "": return error
	error = _ownership(d,catalog)
	if error != "": return error
	error = _finance(d,catalog)
	if error != "": return error
	return _resources_and_evidence(d,catalog)

static func _model(value: Variant, depth: int = 0) -> bool:
	if depth > 64: return false
	if value is int: return value >= -MAX_INTEGER and value <= MAX_INTEGER
	if value is String or value is bool: return true
	if value is Array:
		for child: Variant in value:
			if not _model(child,depth+1): return false
		return true
	if value is Dictionary:
		for key: Variant in value:
			if not (key is String or key is StringName) or str(key) == "" or not _model(value[key],depth+1): return false
		return true
	return false

static func _fields(d: Dictionary, wanted: Dictionary) -> bool:
	for key: String in wanted:
		if not d.has(key) or typeof(d[key]) != wanted[key]: return false
	return true

static func _strings(value: Variant, unique: bool = true) -> bool:
	if not value is Array: return false
	var seen: Dictionary = {}
	for item: Variant in value:
		if not item is String or item == "" or (unique and seen.has(item)): return false
		seen[item] = true
	return true

static func _cell(value: Variant) -> bool:
	return value is int and value >= 0 and value < GridService.WIDTH*GridService.HEIGHT

static func _id(value: String, prefix: String, next: int) -> bool:
	if not value.begins_with(prefix+"_"): return false
	var digits: String = value.trim_prefix(prefix+"_")
	if digits.length() < 3: return false
	for character: String in digits:
		if character not in "0123456789": return false
	return int(digits) > 0 and int(digits) < next

static func _campaign(d: Dictionary, catalog: ContentCatalog) -> String:
	var c: Dictionary = d.campaign
	var level: Dictionary = catalog.levels[d.level_id]
	if not _fields(c,{"wave_index":TYPE_INT,"wave_active":TYPE_BOOL,"current_case_id":TYPE_STRING,"completed_cases":TYPE_ARRAY,"completed_waves":TYPE_ARRAY,"price_percent":TYPE_INT,"loan":TYPE_INT,"reputation":TYPE_INT,"research":TYPE_ARRAY,"training":TYPE_ARRAY,"events":TYPE_ARRAY,"audits":TYPE_DICTIONARY,"career":TYPE_DICTIONARY}): return "invalid_campaign_progress"
	if not _strings(c.completed_cases) or c.completed_cases.size() > level.case_ids.size() or c.completed_cases != level.case_ids.slice(0,c.completed_cases.size()): return "invalid_campaign_case_order"
	if c.wave_index < 0 or c.wave_index > level.case_ids.size() or c.price_percent < 75 or c.price_percent > 150 or c.loan < 0 or c.reputation < 0 or c.reputation > 100: return "invalid_campaign_policy"
	if c.current_case_id != "" and (not catalog.campaign.cases.has(c.current_case_id) or not c.current_case_id in level.case_ids): return "invalid_campaign_current_case"
	if c.wave_active and (c.completed_cases.size() >= level.case_ids.size() or c.current_case_id != level.case_ids[c.completed_cases.size()]): return "invalid_campaign_active_wave"
	var error: String = CampaignProgress.validate(c.career,catalog)
	if error != "": return error
	if c.career.completed_levels.size() < level.order-1: return "missing_campaign_prerequisite"
	if not _fields(d.challenge,{"status":TYPE_STRING,"reason":TYPE_STRING,"ended_tick":TYPE_INT}): return "invalid_campaign_challenge"
	if d.challenge.status == "running":
		if d.challenge.reason != "" or d.challenge.ended_tick != -1: return "invalid_campaign_challenge"
	elif d.challenge.status in ["won","lost","finished"]:
		if not d.paused or d.challenge.ended_tick != d.tick or d.challenge.reason == "": return "invalid_campaign_challenge"
		if d.challenge.status == "won" and not c.career.receipts.has(d.level_id): return "missing_campaign_win_receipt"
	else: return "invalid_campaign_challenge"
	for group: String in ["facilities","cases","audits","events","diseases"]:
		if not d.evidence.get(group) is Dictionary: return "invalid_campaign_evidence"
		var reference: Dictionary = catalog.campaign.get(group,{})
		for key: Variant in d.evidence[group]:
			if not reference.has(key): return "invalid_campaign_evidence"
			if group in ["facilities","diseases"] and (not d.evidence[group][key] is int or d.evidence[group][key] < 0): return "invalid_campaign_evidence"
	for key: Variant in INITIAL_RESOURCES:
		if not d.resources.get(key) is int or d.resources[key] < 0: return "invalid_campaign_resource"
	var allowed: Dictionary = INITIAL_RESOURCES.duplicate()
	for definition: Dictionary in catalog.campaign.facilities.values():
		for key: String in definition.get("output",{}): allowed[key] = 0
	for key: Variant in d.resources:
		if not allowed.has(key) or not d.resources[key] is int or d.resources[key] < 0: return "invalid_campaign_resource"
	return ""

static func _layout_shape(room: Dictionary) -> bool:
	if not _fields(room,{"id":TYPE_STRING,"kind":TYPE_STRING,"ruleset":TYPE_STRING,"unit_id":TYPE_STRING,"origin_cell":TYPE_INT,"rotation":TYPE_INT,"width":TYPE_INT,"height":TYPE_INT,"layout":TYPE_DICTIONARY,"status":TYPE_STRING,"closed":TYPE_BOOL}): return false
	var layout: Dictionary = room.layout
	if not _fields(layout,{"width":TYPE_INT,"height":TYPE_INT,"doors":TYPE_ARRAY,"windows":TYPE_ARRAY,"facilities":TYPE_ARRAY}): return false
	if layout.width < 3 or layout.height < 3 or layout.width > GridService.WIDTH-2 or layout.height > GridService.HEIGHT-2 or room.width != layout.width or room.height != layout.height: return false
	if room.rotation != 0 or not _cell(room.origin_cell): return false
	for list: String in ["doors","windows"]:
		for opening: Variant in layout[list]:
			if not opening is Dictionary or not _fields(opening,{"side":TYPE_STRING,"offset":TYPE_INT}): return false
			if opening.side not in ["north","east","south","west"]: return false
			var extent: int = layout.width if opening.side in ["north","south"] else layout.height
			if opening.offset < 0 or opening.offset >= extent: return false
	for item: Variant in layout.facilities:
		if not item is Dictionary or not _fields(item,{"id":TYPE_STRING,"kind":TYPE_STRING,"x":TYPE_INT,"y":TYPE_INT,"rotation":TYPE_INT}): return false
		if item.x < 0 or item.y < 0 or item.rotation not in [0,1,2,3]: return false
	return not layout.doors.is_empty()

static func _actor(actor: Dictionary, navigation: Dictionary) -> bool:
	if not _fields(actor,{"cell":TYPE_INT,"path":TYPE_ARRAY,"path_index":TYPE_INT,"move_progress":TYPE_INT,"move_ticks":TYPE_INT}): return false
	if not _cell(actor.cell) or not GridService._walkable(navigation,actor.cell) or actor.move_ticks != 4 or actor.move_progress < 0 or actor.move_progress >= 4 or actor.path_index < 0: return false
	if actor.path.is_empty(): return actor.path_index == 0 and actor.move_progress == 0
	if actor.path_index >= actor.path.size() or actor.path[actor.path_index] != actor.cell or (actor.move_progress > 0 and actor.path_index+1 >= actor.path.size()): return false
	for n: int in range(actor.path.size()):
		if not _cell(actor.path[n]): return false
		if n > 0:
			var from_cell: int = actor.path[n-1]
			var to_cell: int = actor.path[n]
			if absi(from_cell%GridService.WIDTH-to_cell%GridService.WIDTH)+absi(int(from_cell/GridService.WIDTH)-int(to_cell/GridService.WIDTH)) != 1: return false
	if actor.move_progress > 0 and not GridService._can_step(navigation,actor.cell,actor.path[actor.path_index+1]): return false
	return true

static func _entities(d: Dictionary, catalog: ContentCatalog) -> String:
	if d.staff.size() > catalog.levels[d.level_id].max_staff: return "campaign_staff_limit"
	# Cross-room geometry helpers inspect their peers. Reject every malformed
	# record before passing any room collection to those helpers.
	for room_id: String in d.rooms:
		if not _id(room_id,"department",d.next_ids.room) or not d.rooms[room_id] is Dictionary: return "invalid_campaign_room_id"
		var record: Dictionary = d.rooms[room_id]
		if not _layout_shape(record) or record.id != room_id or record.kind != "campaign_department" or record.ruleset != RULESET or not catalog.campaign.units.has(record.unit_id): return "invalid_campaign_room"
	var layout_script: Script
	if not d.rooms.is_empty():
		var path: String = "res://campaign/facility_layout.gd"
		if not ResourceLoader.exists(path): return "missing_campaign_layout_validator"
		layout_script = load(path)
	var facility_ids: Dictionary = {}
	for id: String in d.rooms:
		if not _id(id,"department",d.next_ids.room) or not d.rooms[id] is Dictionary: return "invalid_campaign_room_id"
		var room: Dictionary = d.rooms[id]
		if not _layout_shape(room) or room.id != id or room.kind != "campaign_department" or room.ruleset != RULESET or not catalog.campaign.units.has(room.unit_id) or room.status not in ["open","closed","draining"] or room.closed != (room.status == "closed"): return "invalid_campaign_room"
		var others: Dictionary = d.rooms.duplicate()
		others.erase(id)
		var geometry_error: String = layout_script.validate(room,others)
		if geometry_error != "": return "invalid_campaign_layout:"+geometry_error
		var geometry: Dictionary = layout_script.geometry(room)
		for key: String in geometry:
			if not room.has(key) or room[key] != geometry[key]: return "invalid_campaign_room_geometry"
		if not d.queues.get(id) is Array: return "missing_campaign_room_queue"
		for item: Dictionary in room.layout.facilities:
			if facility_ids.has(item.id) or not d.facilities.has(item.id): return "invalid_campaign_layout_facility"
			facility_ids[item.id] = true
			var facility: Variant = d.facilities[item.id]
			if not facility is Dictionary or facility.get("room_id") != id or facility.get("kind") != item.kind or facility.get("x") != item.x or facility.get("y") != item.y or facility.get("rotation") != item.rotation: return "invalid_campaign_facility_layout_link"
	if facility_ids.size() != d.facilities.size(): return "orphan_campaign_facility"
	for id: String in d.facilities:
		if not _id(id,"facility",d.next_ids.facility) or not d.facilities[id] is Dictionary: return "invalid_campaign_facility_id"
		var f: Dictionary = d.facilities[id]
		if not _fields(f,{"id":TYPE_STRING,"kind":TYPE_STRING,"room_id":TYPE_STRING,"x":TYPE_INT,"y":TYPE_INT,"rotation":TYPE_INT,"status":TYPE_STRING,"condition":TYPE_INT,"uses":TYPE_INT,"staff_ids":TYPE_ARRAY,"busy_patient_id":TYPE_STRING,"service_cells":TYPE_ARRAY,"staff_cells":TYPE_ARRAY,"maintenance_cell":TYPE_INT}): return "invalid_campaign_facility"
		if f.id != id or not catalog.campaign.facilities.has(f.kind) or not d.rooms.has(f.room_id) or f.status not in ["open","closed","broken"] or f.condition < 0 or f.condition > 100 or f.uses < 0 or not _strings(f.staff_ids): return "invalid_campaign_facility"
		var item: Dictionary = {"id":id,"kind":f.kind,"x":f.x,"y":f.y,"rotation":f.rotation}
		var geometry: Dictionary = layout_script.facility_geometry(d.rooms[f.room_id],item)
		for key: String in ["service_cells","staff_cells","maintenance_cell"]:
			if not geometry.has(key) or f[key] != geometry[key]: return "invalid_campaign_facility_geometry"
		if f.busy_patient_id != "" and not d.patients.has(f.busy_patient_id): return "invalid_campaign_facility_patient"
	var navigation: Dictionary = GridService._navigation(d.rooms)
	for id: String in d.staff:
		if not _id(id,"staff",d.next_ids.staff) or not d.staff[id] is Dictionary: return "invalid_campaign_staff_id"
		var s: Dictionary = d.staff[id]
		if not _fields(s,{"id":TYPE_STRING,"role":TYPE_STRING,"room_id":TYPE_STRING,"facility_id":TYPE_STRING,"status":TYPE_STRING,"fatigue":TYPE_INT,"skills":TYPE_ARRAY,"work_order_id":TYPE_STRING,"patient_id":TYPE_STRING}) or not _actor(s,navigation): return "invalid_campaign_staff"
		if s.id != id or not catalog.campaign.roles.has(s.role) or s.status not in ["idle","moving","moving_work","walking","serving","blocked","working","resting"] or s.fatigue < 0 or s.fatigue > 100 or not _strings(s.skills): return "invalid_campaign_staff"
		if s.facility_id == "":
			if s.room_id != "" or s.patient_id != "" or s.work_order_id != "": return "invalid_campaign_unassigned_staff"
		elif not d.facilities.has(s.facility_id) or s.room_id != d.facilities[s.facility_id].room_id or not id in d.facilities[s.facility_id].staff_ids: return "invalid_campaign_staff_assignment"
	return ""

static func _patients(d: Dictionary, catalog: ContentCatalog) -> String:
	var navigation: Dictionary = GridService._navigation(d.rooms)
	var by_case: Dictionary = {}
	var live: int = 0
	var completed: int = 0
	var abandoned: int = 0
	for id: String in d.patients:
		if not _id(id,"patient",d.next_ids.patient) or not d.patients[id] is Dictionary: return "invalid_campaign_patient_id"
		var p: Dictionary = d.patients[id]
		if not _fields(p,{"id":TYPE_STRING,"disease_id":TYPE_STRING,"case_id":TYPE_STRING,"phase":TYPE_STRING,"stage":TYPE_STRING,"room_id":TYPE_STRING,"facility_id":TYPE_STRING,"slot_id":TYPE_STRING,"staff_id":TYPE_STRING,"staff_ids":TYPE_ARRAY,"blocked_slot_id":TYPE_STRING,"support_order_id":TYPE_STRING,"arrived_tick":TYPE_INT,"tolerance":TYPE_INT,"wait_reason":TYPE_STRING,"wait_ticks":TYPE_INT,"service_started_tick":TYPE_INT,"service_work":TYPE_INT,"service_needed":TYPE_INT,"step_index":TYPE_INT,"steps":TYPE_ARRAY,"step_history":TYPE_ARRAY,"outcome":TYPE_STRING,"income":TYPE_INT,"completed_tick":TYPE_INT,"reservation_cost":TYPE_INT,"reservation_resource":TYPE_STRING,"reservation_quantity":TYPE_INT}) or not _actor(p,navigation): return "invalid_campaign_patient"
		if p.id != id or not catalog.campaign.cases.has(p.case_id) or p.phase not in PATIENT_PHASES or not _strings(p.staff_ids): return "invalid_campaign_patient"
		var definition: Dictionary = catalog.campaign.cases[p.case_id]
		if p.disease_id != definition.disease_id or p.steps != definition.steps or p.step_index < 0 or p.step_index > p.steps.size() or p.arrived_tick < 0 or p.arrived_tick > d.tick or p.wait_ticks < 0 or p.wait_ticks > d.tick-p.arrived_tick+1 or p.tolerance != 70: return "invalid_campaign_patient_identity"
		var valid_income: bool = false
		for price: int in range(75,151):
			if p.income == int(int(definition.income)*price/100): valid_income = true; break
		if not valid_income: return "invalid_campaign_patient_income"
		if not p.case_id in catalog.levels[d.level_id].case_ids: return "invalid_campaign_patient_case"
		if not by_case.has(p.case_id): by_case[p.case_id] = []
		by_case[p.case_id].append(p)
		if p.phase in ["left","abandoned"]:
			if p.cell != GridService.EXIT_CELL or p.completed_tick < p.arrived_tick or p.completed_tick > d.tick or not p.path.is_empty() or p.move_progress != 0: return "invalid_campaign_patient_departure"
			if p.phase == "left":
				if p.step_index != p.steps.size() or p.outcome != "completed": return "invalid_campaign_completed_patient"
				completed += 1
			else:
				if p.outcome != "abandoned": return "invalid_campaign_abandoned_patient"
				abandoned += 1
		else:
			live += 1
			if p.completed_tick != -1 or p.outcome not in ["","abandoned"]: return "invalid_campaign_active_patient"
		if p.stage != ("exit" if p.phase in ["moving_exit","left","abandoned"] else "care"): return "invalid_campaign_patient_stage"
		if p.phase == "moving_exit" and p.step_index < p.steps.size() and p.outcome != "abandoned": return "invalid_campaign_early_exit"
		if p.phase in ["care_queue","moving_care","care_service","waiting_support"] and p.step_index >= p.steps.size(): return "invalid_campaign_step_cursor"
		var error: String = _history(p,d,catalog)
		if error != "": return error
		if p.phase == "moving_care":
			var step: Dictionary = p.steps[p.step_index]
			if step.kind != "patient" or p.reservation_cost != step.cost or p.reservation_resource != step.get("resource","") or p.reservation_quantity != step.get("quantity",0) or p.service_started_tick != -1 or p.service_work != 0 or p.service_needed != step.duration_ticks: return "invalid_campaign_clinical_reservation"
		elif p.reservation_cost != 0 or p.reservation_resource != "" or p.reservation_quantity != 0: return "unexpected_campaign_reservation"
		if p.phase == "care_service":
			var step: Dictionary = p.steps[p.step_index]
			var duration: int = p.step_history[-1].get("effective_duration",step.duration_ticks)
			if step.kind != "patient" or p.service_needed != duration or p.service_started_tick < p.arrived_tick or p.service_started_tick > d.tick or p.service_work != d.tick-p.service_started_tick or p.service_work >= p.service_needed: return "invalid_campaign_service_clock"
		elif p.phase != "moving_care" and (p.service_started_tick != -1 or p.service_work != 0 or p.service_needed != 0): return "unexpected_campaign_service_clock"
		if p.phase == "waiting_support":
			if p.steps[p.step_index].kind != "support" or p.support_order_id == "" or not d.work_orders.has(p.support_order_id): return "invalid_campaign_support_reference"
		elif p.support_order_id != "": return "unexpected_campaign_support_order"
		if p.phase not in ["moving_care","care_service"] and (p.room_id != "" or p.facility_id != "" or p.slot_id != "" or p.staff_id != "" or not p.staff_ids.is_empty()): return "unexpected_campaign_patient_ownership"
	if live > catalog.levels[d.level_id].max_patients or d.patients.size() != d.next_ids.patient-1: return "invalid_campaign_patient_count"
	if not _fields(d.metrics,{"completed":TYPE_INT,"abandoned":TYPE_INT,"income":TYPE_INT,"operating_profit":TYPE_INT,"expenses":TYPE_DICTIONARY,"patient_totals":TYPE_DICTIONARY}) or d.metrics.completed != completed or d.metrics.abandoned != abandoned: return "invalid_campaign_patient_metrics"
	for case_id: String in d.campaign.completed_cases:
		if not by_case.has(case_id) or by_case[case_id].size() != catalog.campaign.cases[case_id].patient_count: return "invalid_campaign_completed_case"
		for patient: Dictionary in by_case[case_id]:
			if patient.phase != "left": return "invalid_campaign_completed_case"
	for case_id: String in by_case:
		if by_case[case_id].size() != catalog.campaign.cases[case_id].patient_count: return "invalid_campaign_case_patient_count"
		if case_id not in d.campaign.completed_cases:
			var next: int = d.campaign.completed_cases.size()
			if next >= catalog.levels[d.level_id].case_ids.size() or case_id != catalog.levels[d.level_id].case_ids[next]: return "invalid_campaign_admission_order"
			if d.challenge.status == "running" and (not d.campaign.wave_active or d.campaign.current_case_id != case_id): return "missing_campaign_active_wave"
	if d.campaign.wave_active and not by_case.has(d.campaign.current_case_id): return "empty_campaign_active_wave"
	if d.campaign.wave_index != d.campaign.completed_cases.size(): return "invalid_campaign_wave_index"
	if d.campaign.completed_waves != d.campaign.completed_cases: return "invalid_campaign_completed_waves"
	return ""

static func _history(p: Dictionary, d: Dictionary, catalog: ContentCatalog) -> String:
	if p.step_history.size() < p.step_index or p.step_history.size() > p.step_index+1: return "invalid_campaign_history_cursor"
	var previous_end: int = p.arrived_tick
	for index: int in range(p.step_history.size()):
		var h: Variant = p.step_history[index]
		if not h is Dictionary or not _fields(h,{"step_id":TYPE_STRING,"kind":TYPE_STRING,"facility_kind":TYPE_STRING,"facility_id":TYPE_STRING,"staff_ids":TYPE_ARRAY,"started_tick":TYPE_INT,"completed_tick":TYPE_INT,"cost":TYPE_INT,"resource":TYPE_STRING,"quantity":TYPE_INT,"work_order_id":TYPE_STRING,"planned_duration":TYPE_INT,"effective_duration":TYPE_INT,"efficiency_source":TYPE_STRING}): return "invalid_campaign_step_history"
		var step: Dictionary = p.steps[index]
		if h.step_id != step.id or h.kind != step.kind or h.facility_kind != step.facility_kind or h.cost != step.cost or h.resource != step.get("resource","") or h.quantity != step.get("quantity",0) or not _strings(h.staff_ids) or h.staff_ids.is_empty() or not _id(h.facility_id,"facility",d.next_ids.facility): return "invalid_campaign_history_identity"
		if h.get("planned_duration",step.duration_ticks) != step.duration_ticks: return "invalid_campaign_planned_duration"
		var effective: int = step.duration_ticks
		if h.get("efficiency_source","") != "":
			if step.kind != "patient" or not _efficiency_proven(h,d,catalog): return "unearned_campaign_efficiency"
			effective = int(ceil(float(step.duration_ticks)*0.9))
		if h.get("effective_duration",step.duration_ticks) != effective: return "invalid_campaign_effective_duration"
		if h.started_tick < previous_end or h.started_tick > d.tick: return "invalid_campaign_history_order"
		for sid: String in h.staff_ids:
			if not _id(sid,"staff",d.next_ids.staff): return "invalid_campaign_history_staff"
		if d.facilities.has(h.facility_id) and d.facilities[h.facility_id].kind != step.facility_kind: return "invalid_campaign_history_facility"
		if index < p.step_index:
			if h.completed_tick != h.started_tick+effective or h.completed_tick > d.tick: return "invalid_campaign_history_duration"
			previous_end = h.completed_tick
		elif h.completed_tick != -1: return "invalid_campaign_active_history"
		if step.kind == "patient":
			if h.work_order_id != "" or h.staff_ids.size() != step.roles.size(): return "invalid_campaign_clinical_history"
			if index == p.step_index and (p.phase != "care_service" or h.started_tick != p.service_started_tick or h.facility_id != p.facility_id or h.staff_ids != p.staff_ids): return "invalid_campaign_active_history"
		else:
			if h.work_order_id == "" or not d.work_orders.has(h.work_order_id): return "invalid_campaign_support_history"
			var order: Variant = d.work_orders[h.work_order_id]
			if not order is Dictionary or order.get("patient_id") != p.id or order.get("step_id") != step.id or order.get("facility_id") != h.facility_id or order.get("started_tick") != h.started_tick or order.get("staff_ids") != h.staff_ids: return "invalid_campaign_support_history"
			if index < p.step_index and (order.get("status") != "done" or order.get("completed_tick") != h.completed_tick): return "invalid_campaign_support_completion"
			if index == p.step_index and p.phase != "waiting_support": return "invalid_campaign_support_active_history"
	if p.phase == "care_service" and p.step_history.size() != p.step_index+1: return "missing_campaign_service_history"
	if p.phase not in ["care_service","waiting_support"] and p.step_history.size() != p.step_index: return "unexpected_campaign_active_history"
	return ""

static func _efficiency_proven(history: Dictionary, d: Dictionary, catalog: ContentCatalog) -> bool:
	var source: String = history.efficiency_source
	if source == "research:efficiency":
		if "efficiency" not in d.campaign.research: return false
		for order: Variant in d.work_orders.values():
			if order is Dictionary and order.get("project_id","") == "efficiency" and order.get("status") == "done" and order.get("completed_tick") is int and order.completed_tick <= history.started_tick: return true
	elif source.begins_with("training:"):
		var sid: String = source.trim_prefix("training:")
		if sid not in history.staff_ids: return false
		var unit: String = catalog.campaign.facilities[history.facility_kind].unit_id
		for record: Variant in d.campaign.training:
			if record is Dictionary and record.get("staff_id") == sid and record.get("unit_id") == unit and record.get("tick") is int and record.tick <= history.started_tick: return true
	return false

static func _orders(d: Dictionary, catalog: ContentCatalog) -> String:
	for id: String in d.work_orders:
		if not _id(id,"work",d.next_ids.work_order) or not d.work_orders[id] is Dictionary: return "invalid_campaign_work_order_id"
		var o: Dictionary = d.work_orders[id]
		if not _fields(o,{"id":TYPE_STRING,"facility_id":TYPE_STRING,"facility_kind":TYPE_STRING,"handler":TYPE_STRING,"patient_id":TYPE_STRING,"step_id":TYPE_STRING,"staff_id":TYPE_STRING,"staff_ids":TYPE_ARRAY,"status":TYPE_STRING,"work":TYPE_INT,"needed":TYPE_INT,"cost":TYPE_INT,"resource":TYPE_STRING,"quantity":TYPE_INT,"reason":TYPE_STRING,"created_tick":TYPE_INT,"started_tick":TYPE_INT,"completed_tick":TYPE_INT,"output":TYPE_DICTIONARY}): return "invalid_campaign_work_order"
		if o.id != id or not catalog.campaign.facilities.has(o.facility_kind) or not _id(o.facility_id,"facility",d.next_ids.facility) or o.status not in ["queued","walking","working","done","blocked"] or not _strings(o.staff_ids) or o.created_tick < 0 or o.created_tick > d.tick or o.needed < 1 or o.cost < 0 or o.quantity < 0: return "invalid_campaign_work_order"
		var definition: Dictionary = catalog.campaign.facilities[o.facility_kind]
		if o.output != definition.output: return "invalid_campaign_order_output"
		if d.facilities.has(o.facility_id) and d.facilities[o.facility_id].kind != o.facility_kind: return "invalid_campaign_order_facility"
		if o.status != "done" and not d.facilities.has(o.facility_id): return "orphan_campaign_active_order"
		if o.patient_id != "":
			if not d.patients.has(o.patient_id): return "invalid_campaign_order_patient"
			var p: Dictionary = d.patients[o.patient_id]
			var step: Dictionary = {}
			for candidate: Dictionary in p.steps:
				if candidate.id == o.step_id: step = candidate; break
			if step.is_empty() or step.kind != "support" or o.facility_kind != step.facility_kind or o.needed != step.duration_ticks or o.cost != step.cost or o.resource != step.get("resource","") or o.quantity != step.get("quantity",0): return "invalid_campaign_support_order_step"
		else:
			var needed: int = definition.duration_ticks
			if o.has("project_id"):
				if not o.project_id is String or not catalog.campaign.projects.has(o.project_id) or o.facility_kind != "O10" or o.handler != "research": return "invalid_campaign_research_order"
				needed = catalog.campaign.projects[o.project_id].duration_ticks
			if o.has("trainee_id") or o.has("unit_id"):
				if not _fields(o,{"trainee_id":TYPE_STRING,"unit_id":TYPE_STRING}) or not _id(o.trainee_id,"staff",d.next_ids.staff) or not catalog.campaign.units.has(o.unit_id) or o.facility_kind != "O09" or o.handler != "training": return "invalid_campaign_training_order"
				needed = 240
			if o.step_id != "" or o.needed != needed or o.cost != definition.consumable_cost or o.resource != definition.get("input_resource","") or o.quantity != definition.get("input_quantity",0): return "invalid_campaign_operation_definition"
		if o.handler != definition.handler: return "invalid_campaign_order_handler"
		if o.status in ["queued","blocked"]:
			if o.work != 0 or o.started_tick != -1 or o.completed_tick != -1 or o.staff_id != "" or not o.staff_ids.is_empty(): return "invalid_campaign_queued_order"
		else:
			if o.staff_ids.is_empty() or o.staff_id != o.staff_ids[0] or o.staff_ids.size() != definition.roles.size(): return "invalid_campaign_order_staff"
			if o.status == "walking":
				if o.work != 0 or o.started_tick != -1 or o.completed_tick != -1: return "invalid_campaign_walking_order"
			elif o.started_tick < o.created_tick or o.started_tick > d.tick: return "invalid_campaign_order_start"
			elif o.status == "working":
				if o.completed_tick != -1 or o.work != d.tick-o.started_tick or o.work >= o.needed: return "invalid_campaign_order_clock"
			elif o.completed_tick != o.started_tick+o.needed or o.completed_tick > d.tick or o.work != o.needed: return "invalid_campaign_order_duration"
			for sid: String in o.staff_ids:
				if not _id(sid,"staff",d.next_ids.staff): return "invalid_campaign_order_staff"
	return ""

static func _ownership(d: Dictionary, catalog: ContentCatalog) -> String:
	for id: String in d.slots:
		if not d.slots[id] is Dictionary: return "invalid_campaign_slot"
		var slot: Dictionary = d.slots[id]
		if not _fields(slot,{"id":TYPE_STRING,"room_id":TYPE_STRING,"facility_id":TYPE_STRING,"index":TYPE_INT,"cell":TYPE_INT,"patient_id":TYPE_STRING,"phase":TYPE_STRING}) or not d.facilities.has(slot.facility_id): return "invalid_campaign_slot"
		var f: Dictionary = d.facilities[slot.facility_id]
		if slot.id != id or id != slot.facility_id+":"+str(slot.index) or slot.room_id != f.room_id or slot.index < 0 or slot.index >= f.service_cells.size() or slot.cell != f.service_cells[slot.index] or slot.phase not in ["free","reserved","serving","blocked"]: return "invalid_campaign_slot_geometry"
		if slot.phase == "free":
			if slot.patient_id != "": return "invalid_campaign_free_slot"
		else:
			if not d.patients.has(slot.patient_id) or f.busy_patient_id != slot.patient_id: return "invalid_campaign_slot_patient"
			var p: Dictionary = d.patients[slot.patient_id]
			if slot.phase == "blocked":
				if p.blocked_slot_id != id or p.cell != slot.cell: return "invalid_campaign_blocked_slot"
				# Support work advances a clinical cursor while the patient remains
				# physically at the last completed patient-facing station.
				var last_patient_facility: String = ""
				for n: int in range(p.step_index-1,-1,-1):
					if p.step_history[n].kind == "patient":
						last_patient_facility = p.step_history[n].facility_id
						break
				if last_patient_facility != f.id: return "invalid_campaign_blocked_origin"
			else:
				if p.slot_id != id or p.facility_id != f.id or p.room_id != f.room_id or p.phase != ("care_service" if slot.phase == "serving" else "moving_care"): return "invalid_campaign_active_slot"
	for id: String in d.facilities:
		var f: Dictionary = d.facilities[id]
		var roles: Array = catalog.campaign.facilities[f.kind].roles.duplicate()
		if f.staff_ids.size() > f.staff_cells.size(): return "invalid_campaign_facility_staff_count"
		for sid: String in f.staff_ids:
			if not d.staff.has(sid) or d.staff[sid].facility_id != id or d.staff[sid].room_id != f.room_id or not d.staff[sid].role in roles: return "invalid_campaign_facility_staff"
			roles.erase(d.staff[sid].role)
		for index: int in range(f.service_cells.size()):
			if not d.slots.has(id+":"+str(index)): return "missing_campaign_facility_slot"
		if f.busy_patient_id != "":
			var p: Dictionary = d.patients[f.busy_patient_id]
			if p.facility_id != id and (p.blocked_slot_id == "" or not d.slots.has(p.blocked_slot_id) or d.slots[p.blocked_slot_id].facility_id != id): return "orphan_campaign_facility_reservation"
	for p: Dictionary in d.patients.values():
		if p.blocked_slot_id != "" and (not d.slots.has(p.blocked_slot_id) or d.slots[p.blocked_slot_id].phase != "blocked" or d.slots[p.blocked_slot_id].patient_id != p.id): return "invalid_campaign_blocked_reference"
		if p.phase in ["moving_care","care_service"]:
			if not d.facilities.has(p.facility_id) or not d.slots.has(p.slot_id): return "orphan_campaign_patient_reservation"
			var f: Dictionary = d.facilities[p.facility_id]
			var slot: Dictionary = d.slots[p.slot_id]
			var phase: String = "serving" if p.phase == "care_service" else "reserved"
			if slot.phase != phase or slot.patient_id != p.id or slot.facility_id != f.id or slot.room_id != p.room_id: return "invalid_campaign_patient_slot_owner"
			var step: Dictionary = p.steps[p.step_index]
			if f.kind != step.facility_kind or f.busy_patient_id != p.id or p.staff_ids.size() != step.roles.size() or p.staff_id != p.staff_ids[0]: return "invalid_campaign_patient_reservation"
			for n: int in range(p.staff_ids.size()):
				var sid: String = p.staff_ids[n]
				if not d.staff.has(sid) or d.staff[sid].patient_id != p.id or d.staff[sid].facility_id != f.id or d.staff[sid].role != step.roles[n] or d.staff[sid].work_order_id != "": return "invalid_campaign_patient_staff"
				if p.phase == "care_service":
					var place: int = f.staff_ids.find(sid)
					if place < 0 or d.staff[sid].cell != f.staff_cells[place] or d.staff[sid].move_progress != 0 or d.staff[sid].status != "serving": return "invalid_campaign_service_staff_position"
			if p.phase == "care_service" and (p.cell != d.slots[p.slot_id].cell or p.move_progress != 0): return "invalid_campaign_service_patient_position"
		if p.phase == "waiting_support":
			var order: Dictionary = d.work_orders[p.support_order_id]
			if order.patient_id != p.id or order.step_id != p.steps[p.step_index].id: return "invalid_campaign_support_owner"
			if order.started_tick >= 0 and p.step_history.size() == p.step_index and order.started_tick != d.tick: return "missing_campaign_support_start_history"
	for s: Dictionary in d.staff.values():
		if s.patient_id != "":
			if not d.patients.has(s.patient_id): return "orphan_campaign_staff_patient"
			var p: Dictionary = d.patients[s.patient_id]
			if p.phase not in ["moving_care","care_service"] or not s.id in p.staff_ids or s.work_order_id != "": return "invalid_campaign_staff_patient_owner"
		if s.work_order_id != "":
			if not d.work_orders.has(s.work_order_id): return "orphan_campaign_staff_order"
			var order: Dictionary = d.work_orders[s.work_order_id]
			if order.status not in ["walking","working"] or not s.id in order.staff_ids or order.facility_id != s.facility_id or s.patient_id != "": return "invalid_campaign_staff_order_owner"
	for order: Dictionary in d.work_orders.values():
		if order.status not in ["walking","working"]: continue
		var f: Dictionary = d.facilities[order.facility_id]
		var roles: Array = catalog.campaign.facilities[f.kind].roles
		for n: int in range(order.staff_ids.size()):
			var sid: String = order.staff_ids[n]
			if not d.staff.has(sid) or d.staff[sid].work_order_id != order.id or d.staff[sid].facility_id != f.id or d.staff[sid].role != roles[n]: return "invalid_campaign_order_staff_owner"
			if order.status == "working":
				var place: int = f.staff_ids.find(sid)
				if place < 0 or d.staff[sid].cell != f.staff_cells[place] or d.staff[sid].move_progress != 0: return "invalid_campaign_order_staff_position"
	for room_id: String in d.queues:
		if not d.rooms.has(room_id) or not _strings(d.queues[room_id]): return "invalid_campaign_queue"
		for pid: String in d.queues[room_id]:
			if not d.patients.has(pid) or d.patients[pid].room_id != room_id: return "invalid_campaign_queue_member"
	return ""

static func _finance(d: Dictionary, catalog: ContentCatalog) -> String:
	var receipt_error: String = _receipts(d,catalog)
	if receipt_error != "": return receipt_error
	var expected: Dictionary = {}
	for p: Dictionary in d.patients.values():
		for h: Dictionary in p.step_history:
			if h.kind == "patient": expected["treatment_cost|care:"+p.id+":"+h.step_id] = {"tick":h.started_tick,"amount":-h.cost}
		if p.phase == "left": expected["income|income:"+p.id] = {"tick":p.completed_tick,"amount":p.income}
	for order: Dictionary in d.work_orders.values():
		if order.started_tick < 0: continue
		var reference: String = "care:"+order.patient_id+":"+order.step_id if order.patient_id != "" else "operation:"+order.id
		var category: String = "treatment_cost" if order.patient_id != "" else "operations"
		expected[category+"|"+reference] = {"tick":order.started_tick,"amount":-order.cost}
	var cash: int = catalog.levels[d.level_id].initial_cash
	var loan: int = 0
	var income: int = 0
	var expenses: Dictionary = {}
	var seen: Dictionary = {}
	var last_tick: int = 0
	for entry: Variant in d.ledger_entries:
		if not entry is Dictionary or not _fields(entry,{"tick":TYPE_INT,"category":TYPE_STRING,"amount":TYPE_INT,"reference":TYPE_STRING,"cash_after":TYPE_INT}): return "invalid_campaign_ledger"
		if entry.tick < last_tick or entry.tick > d.tick or entry.reference == "" or entry.category not in ["income","build","hire","sale","loan","repay","grant","treatment_cost","operations","research","training","wages","interest"]: return "invalid_campaign_ledger"
		last_tick = entry.tick
		var key: String = entry.category+"|"+entry.reference
		if seen.has(key): return "duplicate_campaign_finance_reference"
		seen[key] = true
		cash += entry.amount
		if cash < 0 or entry.cash_after != cash: return "invalid_campaign_cash_chain"
		if entry.category in ["income","sale","loan","grant"]:
			if entry.amount < 0: return "invalid_campaign_credit"
		elif entry.amount > 0: return "invalid_campaign_expense"
		if entry.category in ["income","treatment_cost","operations"]:
			if not expected.has(key) or expected[key].tick != entry.tick or expected[key].amount != entry.amount: return "invalid_campaign_service_finance"
			expected.erase(key)
		elif entry.category == "grant":
			if entry.reference != "mission:"+d.level_id or d.challenge.status != "won" or entry.amount != catalog.levels[d.level_id].mission_grant: return "invalid_campaign_mission_grant"
		elif entry.category in ["wages","interest"]:
			if entry.tick < 1 or entry.tick%catalog.levels[d.level_id].day_ticks != 0 or entry.reference != ("payroll:" if entry.category == "wages" else "interest:")+str(entry.tick): return "invalid_campaign_periodic_finance"
			if entry.category == "interest" and (loan <= 0 or entry.amount != -maxi(1,int(loan/100))): return "invalid_campaign_interest"
		else:
			var error: String = _command_finance(entry,d,catalog)
			if error != "": return error
		if entry.category == "loan": loan += entry.amount
		elif entry.category == "repay":
			loan += entry.amount
			if loan < 0: return "invalid_campaign_repayment"
		if entry.category == "income": income += entry.amount
		elif entry.category not in ["build","hire","sale","loan","repay","grant"]: expenses[entry.category] = expenses.get(entry.category,0)-entry.amount
	if not expected.is_empty(): return "missing_campaign_service_finance"
	if cash != d.cash or loan != d.campaign.loan or loan > 20000 or d.metrics.income != income or d.metrics.expenses != expenses: return "invalid_campaign_financial_totals"
	var profit: int = income
	for amount: int in expenses.values(): profit -= amount
	if d.metrics.operating_profit != profit: return "invalid_campaign_operating_profit"
	for category: String in ["treatment_cost","recovery_cost","wages","fixed_cost"]:
		if not d.metrics.get(category) is int or d.metrics[category] != expenses.get(category,0): return "invalid_campaign_expense_metric"
	for receipt: Dictionary in d.command_receipts.values():
		var result: Dictionary = receipt.data
		var command: Dictionary = result.command
		var category: String = ""
		match command.type:
			"hire","hire_staff": category = "hire"
			"build_department": category = "build"
			"edit_department","place_facility":
				if result.get("cost",0) > 0: category = "build"
			"remove_room","remove_facility": category = "sale"
			"take_loan": category = "loan"
			"repay_loan": category = "repay"
			"start_research": category = "research"
			"start_training": category = "training"
		if category != "" and not seen.has(category+"|command:"+command.id): return "missing_campaign_command_finance"
	return ""

static func _resources_and_evidence(d: Dictionary, catalog: ContentCatalog) -> String:
	var resources: Dictionary = INITIAL_RESOURCES.duplicate(true)
	var facilities: Dictionary = {}
	var diseases: Dictionary = {}
	var cases: Dictionary = {}
	var uses: Dictionary = {}
	var events: Array = []
	for p: Dictionary in d.patients.values():
		for h: Dictionary in p.step_history:
			if h.kind != "patient": continue
			events.append({"tick":h.started_tick,"phase":1,"sequence":0,"action":0,"resource":h.resource,"delta":-h.quantity,"output":{},"handler":""})
			if h.completed_tick >= 0:
				events.append({"tick":h.completed_tick,"phase":0,"sequence":0,"action":0,"resource":"waste","delta":1,"output":{},"handler":""})
				facilities[h.facility_kind] = facilities.get(h.facility_kind,0)+1
				uses[h.facility_id] = uses.get(h.facility_id,0)+1
		if p.phase == "left": diseases[p.disease_id] = diseases.get(p.disease_id,0)+1
	var operation_sequence: int = 0
	for order: Dictionary in d.work_orders.values():
		operation_sequence += 1
		if order.started_tick >= 0: events.append({"tick":order.started_tick,"phase":2,"sequence":operation_sequence,"action":0,"resource":order.resource,"delta":-order.quantity,"output":{},"handler":""})
		if order.status == "done":
			events.append({"tick":order.completed_tick,"phase":2,"sequence":operation_sequence,"action":1,"resource":"","delta":0,"output":order.output,"handler":order.handler})
			facilities[order.facility_kind] = facilities.get(order.facility_kind,0)+1
			uses[order.facility_id] = uses.get(order.facility_id,0)+1
	# Match Simulation: completed clinical steps produce waste before new
	# clinical starts; Operations then processes actual work-order insertion
	# order. An upstream completion can supply a later start in the same tick.
	events.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:
		if a.tick != b.tick: return a.tick < b.tick
		if a.phase != b.phase: return a.phase < b.phase
		if a.sequence != b.sequence: return a.sequence < b.sequence
		return a.action < b.action)
	for event: Dictionary in events:
		if event.resource != "":
			resources[event.resource] = resources.get(event.resource,0)+event.delta
			if resources[event.resource] < 0: return "invalid_campaign_resource_history"
		for key: String in event.output: resources[key] = maxi(0,resources.get(key,0)+event.output[key])
	for key: String in d.resources:
		if d.resources[key] != resources.get(key,0): return "invalid_campaign_resource_conservation"
	for key: String in resources:
		if resources[key] != d.resources.get(key,0): return "invalid_campaign_resource_conservation"
	if facilities != d.evidence.facilities or diseases != d.evidence.diseases: return "invalid_campaign_completed_evidence"
	for id: String in d.facilities:
		if d.facilities[id].uses != uses.get(id,0): return "invalid_campaign_facility_uses"
	for case_id: String in d.campaign.completed_cases:
		var tick: int = 0
		for p: Dictionary in d.patients.values():
			if p.case_id == case_id: tick = maxi(tick,p.completed_tick)
		cases[case_id] = {"tick":tick,"patient_count":catalog.campaign.cases[case_id].patient_count}
	if cases != d.evidence.cases: return "invalid_campaign_case_evidence"
	var reserved_cash: int = 0
	var reserved_resources: Dictionary = {}
	for p: Dictionary in d.patients.values():
		reserved_cash += p.reservation_cost
		if p.reservation_resource != "": reserved_resources[p.reservation_resource] = reserved_resources.get(p.reservation_resource,0)+p.reservation_quantity
	if reserved_cash > d.cash: return "overbooked_campaign_cash"
	for key: String in reserved_resources:
		if reserved_resources[key] > d.resources.get(key,0): return "overbooked_campaign_stock"
	return _growth(d,catalog)

static func _receipts(d: Dictionary, catalog: ContentCatalog) -> String:
	if d.command_receipts.size() != d.command_sequence: return "invalid_campaign_receipt_count"
	var sequence: Dictionary = {}
	var hires: Dictionary = {}
	var dismissed: Dictionary = {}
	var admissions: Dictionary = {}
	var price_percent: int = 100
	for id: String in d.command_receipts:
		var receipt: Variant = d.command_receipts[id]
		if not receipt is Dictionary or not _fields(receipt,{"ok":TYPE_BOOL,"code":TYPE_STRING,"data":TYPE_DICTIONARY}) or not receipt.ok or receipt.code != "ok": return "invalid_campaign_receipt"
		var result: Dictionary = receipt.data
		if not _fields(result,{"tick":TYPE_INT,"sequence":TYPE_INT,"command":TYPE_DICTIONARY}) or result.tick < 0 or result.tick > d.tick or result.sequence < 1 or result.sequence > d.command_sequence or sequence.has(result.sequence): return "invalid_campaign_receipt_sequence"
		var command: Dictionary = result.command
		if not _fields(command,{"id":TYPE_STRING,"type":TYPE_STRING,"payload":TYPE_DICTIONARY}) or command.id != id or command.type not in ["set_paused","set_speed","build_department","edit_department","place_facility","remove_room","remove_facility","hire","hire_staff","assign","assign_staff","unassign","dismiss","dismiss_staff","accept_case","run_operation","request_audit","start_research","start_training","set_price","take_loan","repay_loan","resolve_event","close_facility","reopen_facility"]: return "invalid_campaign_receipt_command"
		sequence[result.sequence] = result
	var last_tick: int = 0
	for n: int in range(1,d.command_sequence+1):
		if not sequence.has(n) or sequence[n].tick < last_tick: return "invalid_campaign_receipt_order"
		var result: Dictionary = sequence[n]
		last_tick = result.tick
		var command: Dictionary = result.command
		if command.type in ["hire","hire_staff"]:
			var sid: Variant = result.get("staff_id")
			var role: Variant = command.payload.get("role")
			if not sid is String or not _id(sid,"staff",d.next_ids.staff) or not role is String or not catalog.campaign.roles.has(role) or hires.has(sid): return "invalid_campaign_hire_history"
			hires[sid] = role
		elif command.type in ["dismiss","dismiss_staff"]:
			var sid: Variant = command.payload.get("staff_id")
			if not sid is String or result.get("staff_id") != sid or not hires.has(sid) or dismissed.has(sid): return "invalid_campaign_dismiss_history"
			dismissed[sid] = true
		elif command.type == "set_price":
			var price: Variant = command.payload.get("percent")
			if not price is int or price < 75 or price > 150: return "invalid_campaign_price_history"
			price_percent = price
		elif command.type == "accept_case":
			var case_id: Variant = command.payload.get("case_id")
			if not case_id is String or not catalog.campaign.cases.has(case_id) or result.get("case_id") != case_id or not _strings(result.get("patient_ids")): return "invalid_campaign_admission_receipt"
			var definition: Dictionary = catalog.campaign.cases[case_id]
			if result.patient_ids.size() != definition.patient_count: return "invalid_campaign_admission_receipt"
			var quote: int = int(int(definition.income)*price_percent/100)
			for pid: String in result.patient_ids:
				if admissions.has(pid) or not d.patients.has(pid): return "invalid_campaign_admission_receipt"
				var patient: Dictionary = d.patients[pid]
				if patient.case_id != case_id or patient.arrived_tick != result.tick or patient.income != quote: return "invalid_campaign_admission_quote"
				admissions[pid] = true
	# Commands sharing a tick still have an authoritative sequence. A later
	# price change affects future admissions, never an existing patient's quote.
	if admissions.size() != d.patients.size() or d.campaign.price_percent != price_percent: return "invalid_campaign_price_history"
	for sid: String in d.staff:
		if not hires.has(sid) or dismissed.has(sid) or d.staff[sid].role != hires[sid]: return "invalid_campaign_staff_history"
	for sid: String in hires:
		if not dismissed.has(sid) and not d.staff.has(sid): return "missing_campaign_hired_staff"
	if hires.size()+1 != d.next_ids.staff: return "invalid_campaign_staff_allocator"
	for p: Dictionary in d.patients.values():
		for index: int in range(p.step_history.size()):
			var h: Dictionary = p.step_history[index]
			var step: Dictionary = p.steps[index]
			if h.staff_ids.size() != step.roles.size(): return "invalid_campaign_history_staff_roles"
			for n: int in range(h.staff_ids.size()):
				if hires.get(h.staff_ids[n],"") != step.roles[n]: return "invalid_campaign_history_staff_roles"
	for order: Dictionary in d.work_orders.values():
		var roles: Array = catalog.campaign.facilities[order.facility_kind].roles
		for n: int in range(order.staff_ids.size()):
			if hires.get(order.staff_ids[n],"") != roles[n]: return "invalid_campaign_history_order_staff"
	return ""

static func _command_finance(entry: Dictionary, d: Dictionary, catalog: ContentCatalog) -> String:
	if not entry.reference.begins_with("command:"): return "invalid_campaign_command_finance"
	var id: String = entry.reference.trim_prefix("command:")
	if not d.command_receipts.has(id): return "missing_campaign_finance_receipt"
	var result: Dictionary = d.command_receipts[id].data
	var command: Dictionary = result.command
	var payload: Dictionary = command.payload
	if entry.tick != result.tick: return "invalid_campaign_command_finance_tick"
	match command.type:
		"hire","hire_staff":
			if entry.category != "hire" or not catalog.campaign.roles.has(payload.get("role","")) or entry.amount != -catalog.campaign.roles[payload.role].hire_cost: return "invalid_campaign_hire_finance"
		"build_department","edit_department","place_facility":
			if entry.category != "build" or not result.get("cost") is int or entry.amount != -result.cost: return "invalid_campaign_build_finance"
			if command.type == "build_department":
				if not payload.get("layout") is Dictionary or not _fields(payload.layout,{"width":TYPE_INT,"height":TYPE_INT,"facilities":TYPE_ARRAY}): return "invalid_campaign_build_receipt"
				var cost: int = 150+payload.layout.width*payload.layout.height*8
				for item: Variant in payload.layout.facilities:
					if not item is Dictionary or not catalog.campaign.facilities.has(item.get("kind","")): return "invalid_campaign_build_receipt"
					cost += catalog.campaign.facilities[item.kind].cost
				if result.cost != cost: return "invalid_campaign_build_cost"
		"remove_room","remove_facility":
			if entry.category != "sale" or entry.amount < 0: return "invalid_campaign_sale_finance"
			if command.type == "remove_facility" and entry.amount != result.get("refund",-1): return "invalid_campaign_sale_finance"
		"take_loan":
			if entry.category != "loan" or not payload.get("amount") is int or payload.amount < 1000 or payload.amount > 10000 or entry.amount != payload.amount: return "invalid_campaign_loan_finance"
		"repay_loan":
			if entry.category != "repay" or not payload.get("amount") is int or payload.amount < 1 or entry.amount != -payload.amount: return "invalid_campaign_repayment_finance"
		"start_research":
			if entry.category != "research" or not catalog.campaign.projects.has(payload.get("project_id","")) or entry.amount != -catalog.campaign.projects[payload.project_id].cost: return "invalid_campaign_research_finance"
		"start_training":
			if entry.category != "training" or entry.amount != -180: return "invalid_campaign_training_finance"
		_: return "unexpected_campaign_command_finance"
	return ""

static func _growth(d: Dictionary, catalog: ContentCatalog) -> String:
	var effect_error: String = _effects(d)
	if effect_error != "": return effect_error
	if not _strings(d.campaign.research): return "invalid_campaign_research"
	for project: String in d.campaign.research:
		if not catalog.campaign.projects.has(project): return "invalid_campaign_research"
		var found: bool = false
		for order: Dictionary in d.work_orders.values():
			if order.get("project_id","") == project and order.status == "done": found = true
		if not found: return "unearned_campaign_research"
	for record: Variant in d.campaign.training:
		if not record is Dictionary or not _fields(record,{"staff_id":TYPE_STRING,"unit_id":TYPE_STRING,"order_id":TYPE_STRING,"tick":TYPE_INT}) or not d.work_orders.has(record.order_id): return "invalid_campaign_training"
		var order: Dictionary = d.work_orders[record.order_id]
		if order.status != "done" or order.get("trainee_id") != record.staff_id or order.get("unit_id") != record.unit_id or record.tick != order.completed_tick: return "unearned_campaign_training"
	for id: String in d.campaign.audits:
		var audit: Variant = d.campaign.audits[id]
		if not catalog.campaign.audits.has(id) or not audit is Dictionary or not _fields(audit,{"passed":TYPE_BOOL,"tick":TYPE_INT,"facility_evidence":TYPE_DICTIONARY}) or not audit.passed or audit.tick < 0 or audit.tick > d.tick or d.evidence.audits.get(id,-1) != audit.tick: return "invalid_campaign_audit"
		var proof_error: String = _audit_effects(id,audit,d,catalog)
		if proof_error != "": return proof_error
		for key: Variant in audit.facility_evidence:
			if not catalog.campaign.facilities.has(key) or not audit.facility_evidence[key] is int or audit.facility_evidence[key] < 0 or audit.facility_evidence[key] > d.evidence.facilities.get(key,0): return "invalid_campaign_audit_evidence"
	if d.campaign.audits.size() != d.evidence.audits.size(): return "invalid_campaign_audit_evidence"
	var seen: Dictionary = {}
	for event: Variant in d.campaign.events:
		if not event is Dictionary or not _fields(event,{"id":TYPE_STRING,"status":TYPE_STRING,"created_tick":TYPE_INT,"resolved_tick":TYPE_INT}) or not catalog.campaign.events.has(event.id) or seen.has(event.id) or not event.id in catalog.levels[d.level_id].event_ids: return "invalid_campaign_event"
		seen[event.id] = true
		var definition: Dictionary = catalog.campaign.events[event.id]
		for key: String in definition:
			if event.get(key) != definition[key]: return "invalid_campaign_event_definition"
		if event.created_tick < 0 or event.created_tick > d.tick or event.status not in ["open","resolved"]: return "invalid_campaign_event_clock"
		if event.status == "open":
			if event.resolved_tick != -1 or d.evidence.events.has(event.id): return "invalid_campaign_open_event"
		else:
			var order_id: Variant = d.evidence.events.get(event.id)
			if not order_id is String or not d.work_orders.has(order_id): return "missing_campaign_event_work"
			var order: Dictionary = d.work_orders[order_id]
			if order.status != "done" or order.handler != event.required_handler or order.started_tick < event.created_tick or event.resolved_tick < order.completed_tick or event.resolved_tick > d.tick: return "invalid_campaign_event_resolution"
	for id: String in d.evidence.events:
		if not seen.has(id): return "orphan_campaign_event_evidence"
	if d.challenge.status == "won":
		var level: Dictionary = catalog.levels[d.level_id]
		if d.campaign.completed_cases != level.case_ids or d.metrics.abandoned > 0: return "unearned_campaign_win"
		for id: String in level.operation_ids:
			if d.evidence.facilities.get(id,0) < 1: return "unearned_campaign_win"
		for id: String in level.audit_ids:
			if not d.campaign.audits.has(id): return "unearned_campaign_win"
		for event: Dictionary in d.campaign.events:
			if event.status != "resolved": return "unearned_campaign_win"
	return ""

static func _effects(d: Dictionary) -> String:
	var counts: Dictionary = {}
	var call_ticks: Dictionary = {}
	var last_call: int = -1
	var last_archive: int = -1
	for order: Dictionary in d.work_orders.values():
		if order.status != "done": continue
		counts[order.handler] = counts.get(order.handler,0)+1
		if order.handler in ["call","referral"]:
			call_ticks[order.completed_tick] = true
			last_call = maxi(last_call,order.completed_tick)
		if order.handler == "archive": last_archive = maxi(last_archive,order.completed_tick)
	var cp: Dictionary = d.campaign
	if cp.has("operation_counts") and not cp.operation_counts is Dictionary: return "invalid_campaign_operation_counts"
	if cp.get("operation_counts",{}) != counts: return "invalid_campaign_operation_counts"
	var flags: Dictionary = {
		"assistance_ready":counts.get("accessibility",0)>0,
		"privacy_ready":counts.get("privacy",0)>0,
		"fire_ready":counts.get("fire",0)>0,
		"power_ready":counts.get("ups",0)+counts.get("power",0)>0
	}
	for key: String in flags:
		if cp.has(key) and not cp[key] is bool: return "invalid_campaign_effect_flag"
		if cp.get(key,false) != flags[key]: return "unearned_campaign_effect_flag:"+key
	for spec: Array in [["comfort","temperature"],["ventilation","ventilation"]]:
		var key: String = spec[0]
		var expected: int = 100 if counts.get(spec[1],0)>0 else 0
		if cp.has(key) and not cp[key] is int: return "invalid_campaign_environment_effect"
		if cp.get(key,0) != expected: return "unearned_campaign_environment_effect:"+key
	if cp.has("educated") and not cp.educated is int: return "invalid_campaign_education_effect"
	if cp.get("educated",0) != counts.get("education",0): return "unearned_campaign_education_effect"
	if cp.has("archived_evidence_tick") and not cp.archived_evidence_tick is int: return "invalid_campaign_archive_effect"
	if cp.get("archived_evidence_tick",-1) != last_archive: return "unearned_campaign_archive_effect"
	if cp.has("queue_priority_until"):
		if not cp.queue_priority_until is int or cp.queue_priority_until != (last_call+600 if last_call >= 0 else 0): return "unearned_campaign_call_effect"
	for patient: Dictionary in d.patients.values():
		if not patient.has("called_until"): continue
		if not patient.called_until is int or patient.called_until < 0: return "invalid_campaign_patient_call"
		if patient.called_until == 0: continue
		var called_tick: int = patient.called_until-600
		if not call_ticks.has(called_tick) or patient.arrived_tick > called_tick: return "unearned_campaign_patient_call"
	return ""

static func _audit_effects(id: String, audit: Dictionary, d: Dictionary, catalog: ContentCatalog) -> String:
	if id == "A01":
		var fire_before_audit: bool = false
		for order: Dictionary in d.work_orders.values():
			if order.status == "done" and order.handler == "fire" and order.completed_tick <= audit.tick: fire_before_audit = true; break
		if not fire_before_audit: return "missing_campaign_audit_fire_proof"
	elif id in ["A13","A16"]:
		# Archive approval covers every authored case in this level. A later
		# archive job cannot make an early, incomplete approval legitimate.
		var last_case_tick: int = 0
		for case_id: String in catalog.levels[d.level_id].case_ids:
			if not d.evidence.cases.has(case_id) or d.evidence.cases[case_id].tick > audit.tick: return "missing_campaign_audit_case_proof"
			last_case_tick = maxi(last_case_tick,d.evidence.cases[case_id].tick)
		var archived_before_audit: bool = false
		for order: Dictionary in d.work_orders.values():
			if order.status == "done" and order.handler == "archive" and order.completed_tick >= last_case_tick and order.completed_tick <= audit.tick: archived_before_audit = true; break
		if not archived_before_audit: return "missing_campaign_audit_archive_proof"
	return ""
