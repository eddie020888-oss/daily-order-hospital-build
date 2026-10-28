class_name SnapshotValidator
extends RefCounted

const MAX_INTEGER := 9007199254740991
const STAGES := ["reception","diagnosis","treatment","recovery","exit","general_exam","pharmacy","ward"]
const PHASES := ["outside","reception_queue","moving_reception","reception_service","diagnosis_queue","moving_diagnosis","diagnosis_service","treatment_queue","moving_treatment","treatment_service","waiting_recovery","moving_recovery","recovering","leaving","abandoning","completed","abandoned","general_exam_queue","moving_general_exam","general_exam_service","pharmacy_queue","moving_pharmacy","pharmacy_service","ward_queue","moving_ward","ward_service"]
const CARE_STAGES := ["general_exam","pharmacy","ward"]
const CARE_FIELDS := ["care_steps","care_cursor","care_started_ticks","care_completed_ticks"]
const COMMANDS := ["build_room","move_room","remove_room","close_room","reopen_room","upgrade_recovery","hire_staff","dismiss_staff","assign_staff","set_room_mode","set_auto_route","set_patient_mode","set_paused","set_speed"]

# Strict model validation is separate from disk JSON normalization. In-memory
# float values are never coerced into authoritative integer state.
static func validate(d: Dictionary, catalog: ContentCatalog) -> String:
	if catalog == null or not _model(d): return "invalid_model_value"
	if d.get("ruleset","")=="full-hospital-v2" and d.get("schema_version",0)!=3: return "incompatible_campaign_schema"
	if d.get("ruleset","")=="full-hospital-v1" and d.get("schema_version",0)!=2: return "incompatible_campaign_schema"
	if d.has("career_tracks"):
		if not d.career_tracks is Dictionary: return "invalid_career_tracks"
		for ruleset: Variant in d.career_tracks:
			if ruleset not in ["full-hospital-v1","full-hospital-v2"]: return "invalid_career_track_ruleset"
			var track: Variant=d.career_tracks[ruleset]
			if not track is Dictionary: return "invalid_career_track"
			if ruleset=="full-hospital-v2" and track.get("ruleset","")!=ruleset: return "invalid_career_track_ruleset"
			if ruleset=="full-hospital-v1" and track.get("ruleset","full-hospital-v1")!=ruleset: return "invalid_career_track_ruleset"
			var track_error: String=CampaignProgress.validate(track,catalog)
			if track_error!="": return track_error
			if track.get("completed_levels",[]).is_empty(): return "empty_career_track"
		if d.get("campaign") is Dictionary and d.campaign.get("career") is Dictionary:
			var current_ruleset: String=str(d.get("ruleset",""))
			if d.career_tracks.has(current_ruleset) and d.career_tracks[current_ruleset]!=d.campaign.career: return "inconsistent_current_career_track"
		if d.get("schema_version",0)==1 and d.has("campaign_career") and d.career_tracks.has("full-hospital-v1") and d.career_tracks["full-hospital-v1"]!=d.campaign_career: return "inconsistent_current_career_track"
	if d.get("schema_version",0)==3: return LongCampaignValidator.validate(d,catalog)
	if d.get("schema_version",0)==2: return CampaignValidator.validate(d,catalog)
	if d.has("campaign_career"):
		var career_error:=CampaignProgress.validate(d.campaign_career,catalog)
		if career_error!="": return career_error
	if d.get("schema_version") != 1: return "incompatible_schema_version"
	if d.get("content_version") != catalog.content_version: return "incompatible_content_version"
	if d.has("appearance_seed") and (not d.appearance_seed is int or d.appearance_seed<=0 or d.appearance_seed>2147483647): return "invalid_appearance_seed"
	if not d.get("level_id") is String or not catalog.levels.has(d.level_id): return "unknown_level_id"
	var initial := ClinicState.create(d.level_id,catalog).data
	for key in initial:
		if not d.has(key) or typeof(d[key]) != typeof(initial[key]): return "invalid_field:" + key
	if d.tick < 0 or d.speed not in [1,2] or d.command_sequence < 0 or d.map_revision < 0 or d.negative_cash_ticks < 0 or d.negative_cash_ticks > d.tick: return "invalid_clock"
	if d.scenario_id not in ["level_01","clinical_02","benchmark_18","load_40"] or d.scenario_strategy not in ["fast","gentle","tolerance"] or d.scenario_layout not in ["standard","longer_walk"]: return "invalid_scenario"
	if d.tick > (18000 if d.scenario_id == "load_40" else catalog.levels[d.level_id].end_tick): return "invalid_clock_horizon"
	if not _fields(d.next_ids,{"room":TYPE_INT,"staff":TYPE_INT,"patient":TYPE_INT}): return "invalid_next_ids"
	for id in d.next_ids.values():
		if id < 1: return "invalid_next_ids"
	if not _unique_strings(d.unlocked_room_kinds): return "invalid_unlocks"
	for kind in d.unlocked_room_kinds:
		if not catalog.rooms.has(kind): return "unknown_room_kind"
	for key in d.hint_flags:
		if key == "pending":
			if d.hint_flags[key] not in ["unlock_motion","unlock_sensory"]: return "invalid_hint"
		elif key not in ["disabled","unlock_motion","unlock_sensory"] or not d.hint_flags[key] is bool: return "invalid_hint"
	var ch: Dictionary = d.challenge
	if not _fields(ch,{"status":TYPE_STRING,"reason":TYPE_STRING,"ended_tick":TYPE_INT}): return "invalid_challenge"
	if ch.status == "running":
		if ch.reason != "" or ch.ended_tick != -1: return "invalid_challenge"
	elif ch.status in ["won","lost","finished"]:
		if ch.reason not in ["bankruptcy","time_limit","all_departed","benchmark_horizon","load_horizon"] or ch.ended_tick != d.tick or not d.paused: return "invalid_challenge"
	else: return "invalid_challenge"
	if d.last_business_tick < -1 or d.last_business_tick > d.tick or d.last_payroll_tick < 0 or d.last_payroll_tick > d.tick or d.last_payroll_tick % catalog.levels[d.level_id].day_ticks != 0: return "invalid_business_clock"
	if d.tick > 0 and d.last_business_tick != d.tick: return "missing_business_tick"
	if d.last_payroll_tick != int(d.tick/catalog.levels[d.level_id].day_ticks)*catalog.levels[d.level_id].day_ticks: return "missing_payroll_boundary"
	var error := _entities(d,catalog)
	if error != "": return error
	error = _patients(d,catalog)
	if error != "": return error
	error = _ownership(d,catalog)
	if error != "": return error
	error = _receipts(d,catalog)
	if error != "": return error
	return _finance(d,catalog)

static func _model(value: Variant, depth: int = 0) -> bool:
	if depth > 64: return false
	if value is int: return value >= -MAX_INTEGER and value <= MAX_INTEGER
	if value is String or value is bool: return true
	if value is Array:
		for child in value:
			if not _model(child,depth+1): return false
		return true
	if value is Dictionary:
		for key in value:
			# Dot assignment creates StringName dictionary keys in Godot. They
			# have the same JSON string identity; values remain strictly typed.
			if not (key is String or key is StringName) or str(key).is_empty() or not _model(value[key],depth+1): return false
		return true
	return false

static func _fields(d: Dictionary, fields: Dictionary) -> bool:
	for key in fields:
		if not d.has(key) or typeof(d[key]) != fields[key]: return false
	return true

static func _unique_strings(a: Array) -> bool:
	var seen := {}
	for id in a:
		if not id is String or id == "" or seen.has(id): return false
		seen[id] = true
	return true

static func _id(id: String, prefix: String, next: int) -> bool:
	var digits := id.trim_prefix(prefix+"_")
	for character in digits:
		if character not in "0123456789": return false
	return id.begins_with(prefix+"_") and digits.length() >= 3 and int(digits) > 0 and int(digits) < next

static func _cell(value: Variant) -> bool:
	return value is int and value >= 0 and value < GridService.WIDTH * GridService.HEIGHT

static func _actor(a: Dictionary) -> bool:
	if not _fields(a,{"phase":TYPE_STRING,"path":TYPE_ARRAY,"path_index":TYPE_INT,"move_progress":TYPE_INT}): return false
	if a.move_progress < 0 or a.move_progress > 3 or a.path_index < 0: return false
	for key in ["goal_cell","route_goal_cell","cell"]:
		if a.has(key) and not _cell(a[key]): return false
	for key in ["route_revision","walked_cells"]:
		if a.has(key) and (not a[key] is int or a[key] < (-1 if key == "route_revision" else 0)): return false
	if not a.has("cell"):
		return a.path.is_empty() and a.path_index == 0 and a.move_progress == 0
	if a.path.is_empty(): return a.path_index == 0 and a.move_progress == 0
	if a.path_index >= a.path.size() or a.path[a.path_index] != a.cell or (a.move_progress > 0 and a.path_index+1 >= a.path.size()): return false
	# This is the cached destination, not the desired goal, which may have
	# changed since the route was computed and legitimately await replanning.
	if not a.has("route_goal_cell") or a.path[-1] != a.route_goal_cell: return false
	for i in range(a.path.size()):
		if not _cell(a.path[i]): return false
		if i > 0:
			var delta: int = absi(a.path[i]-a.path[i-1])
			if delta != 24 and not (delta == 1 and int(a.path[i]/24) == int(a.path[i-1]/24)): return false
	return true

static func _entities(d: Dictionary, catalog: ContentCatalog) -> String:
	if d.staff.size() > catalog.levels[d.level_id].max_staff: return "staff_limit"
	for id in d.rooms:
		if not _id(id,"room",d.next_ids.room) or not d.rooms[id] is Dictionary: return "invalid_room_id"
		var r: Dictionary = d.rooms[id]
		if not _fields(r,{"kind":TYPE_STRING,"origin_cell":TYPE_INT,"rotation":TYPE_INT,"upgraded":TYPE_BOOL,"status":TYPE_STRING,"mode":TYPE_STRING,"staff_id":TYPE_STRING,"invested_cost":TYPE_INT}): return "invalid_room"
		if not catalog.rooms.has(r.kind): return "unknown_room_kind"
		if not _cell(r.origin_cell) or r.rotation not in [0,1,2,3] or (r.upgraded and r.kind != "recovery") or r.status not in ["open","draining","closed"] or r.mode not in ["fast","gentle"]: return "invalid_room"
		var cost: int = catalog.rooms[r.kind].cost + (catalog.rooms.recovery.upgrade_cost if r.upgraded else 0)
		if r.has("layout"):
			# Validate before geometry generation: a malformed optional layout must
			# never be indexed as an authoritative room definition.
			if r.rotation != 0: return "invalid_room_layout_rotation"
			var layout_error := FreeRoomLayout.validate_shape(r.layout)
			if layout_error != "": return "invalid_room_layout:"+layout_error
			layout_error = FreeRoomLayout.validate(r.kind,r.layout,r.upgraded)
			if layout_error != "": return "invalid_room_layout:"+layout_error
			cost = FreeRoomLayout.base_cost(r.kind,r.layout,catalog,r.upgraded)
		if r.invested_cost != cost: return "invalid_invested_cost"
		var geometry := GridService._room_geometry(r)
		for key in ["doorways","window_edges"]:
			if r.has(key)!=geometry.has(key): return "invalid_room_geometry"
		for key in geometry:
			if not r.has(key) or r[key] != geometry[key]: return "invalid_room_geometry"
		if not d.queues.get(id) is Array: return "missing_room_queue"
		if r.staff_id != "" and (not d.staff.has(r.staff_id) or not d.staff[r.staff_id] is Dictionary or d.staff[r.staff_id].get("room_id") != id): return "invalid_room_staff"
	for id in d.staff:
		if not _id(id,"staff",d.next_ids.staff) or not d.staff[id] is Dictionary: return "invalid_staff_id"
		var s: Dictionary = d.staff[id]
		if not _fields(s,{"role":TYPE_STRING,"room_id":TYPE_STRING}) or not _actor(s): return "invalid_staff"
		if not catalog.staff.has(s.role) or s.phase not in ["idle","moving","serving","blocked"]: return "invalid_staff"
		if s.room_id != "":
			if not d.rooms.has(s.room_id) or d.rooms[s.room_id].staff_id != id or catalog.rooms[d.rooms[s.room_id].kind].staff_role != s.role: return "invalid_staff_assignment"
		if not s.has("cell") and s.phase != "idle": return "invalid_staff_cell"
	# Use the same geometric legality check as live commands, after actor shapes
	# have been checked below; it protects active edges while permitting stale caches.
	return ""

static func _patients(d: Dictionary, catalog: ContentCatalog) -> String:
	if d.arrival_cursor < 0 or d.arrival_cursor > d.scheduled_arrivals.size() or d.patients.size() != d.arrival_cursor or d.next_ids.patient != d.scheduled_arrivals.size()+1: return "invalid_arrival_cursor"
	var arrivals := {}
	var last_tick := -1
	for i in range(d.scheduled_arrivals.size()):
		var a: Variant = d.scheduled_arrivals[i]
		if not a is Dictionary or not _fields(a,{"id":TYPE_STRING,"tick":TYPE_INT,"disease_id":TYPE_STRING,"tolerance":TYPE_INT}): return "invalid_arrival"
		if not _id(a.id,"patient",d.next_ids.patient) or arrivals.has(a.id) or not catalog.diseases.has(a.disease_id) or a.tolerance not in [30,70] or a.tick < last_tick: return "invalid_arrival"
		last_tick = a.tick
		arrivals[a.id] = a
		if (i < d.arrival_cursor) != d.patients.has(a.id) or (i < d.arrival_cursor and a.tick > d.tick): return "invalid_arrival_membership"
		if i >= d.arrival_cursor and a.tick <= d.tick: return "unconsumed_due_arrival"
	var inside := 0
	for id in d.patients:
		if not d.patients[id] is Dictionary: return "invalid_patient"
		var p: Dictionary = d.patients[id]
		if not _fields(p,{"id":TYPE_STRING,"disease_id":TYPE_STRING,"tolerance":TYPE_INT,"tolerance_revealed":TYPE_BOOL,"arrival_tick":TYPE_INT,"admitted_tick":TYPE_INT,"exit_tick":TYPE_INT,"abandon_tick":TYPE_INT,"stage":TYPE_STRING,"wait_ticks":TYPE_INT,"wait_by_stage":TYPE_DICTIONARY,"wait_reason":TYPE_STRING,"room_id":TYPE_STRING,"slot_id":TYPE_STRING,"queue_enter_tick":TYPE_INT,"treatment_started":TYPE_BOOL,"services_complete":TYPE_BOOL,"walked_cells":TYPE_INT}) or not _actor(p): return "invalid_patient"
		if p.id != id or not arrivals.has(id) or p.disease_id != arrivals[id].disease_id or p.tolerance != arrivals[id].tolerance or p.arrival_tick != arrivals[id].tick: return "invalid_patient_identity"
		var is_care: bool = _is_care(p,catalog)
		var allowed_stages: Array = ["reception","diagnosis","exit"] if is_care else ["reception","diagnosis","treatment","recovery","exit"]
		if is_care: allowed_stages.append_array(catalog.diseases[p.disease_id].care_steps)
		if p.phase not in PHASES or p.stage not in allowed_stages or p.wait_ticks < 0 or p.wait_ticks > d.tick-p.arrival_tick or p.walked_cells < 0 or p.queue_enter_tick < p.arrival_tick or p.queue_enter_tick > d.tick: return "invalid_patient_progress"
		if p.phase in PatientFlow.SERVICES:
			var service_stage: String = "recovery" if p.phase == "recovering" else p.phase.trim_suffix("_service")
			if p.stage != service_stage: return "invalid_service_stage"
		if p.wait_reason not in ["","hospital_full","path_blocked","missing_room","missing_staff","equipment_busy","recovery_full"]: return "invalid_wait_reason"
		for key in ["admitted_tick","exit_tick","abandon_tick"]:
			if p[key] < -1 or p[key] > d.tick or (p[key] >= 0 and p[key] < p.arrival_tick): return "invalid_patient_time"
		if p.has("wait_interval_tick") and (not p.wait_interval_tick is int or p.wait_interval_tick < p.arrival_tick or p.wait_interval_tick > d.tick or p.get("wait_interval_stage") not in allowed_stages+["outside"]): return "invalid_wait_interval"
		var sum := 0
		for stage in p.wait_by_stage:
			if stage not in allowed_stages+["outside"] or not p.wait_by_stage[stage] is int or p.wait_by_stage[stage] < 0: return "invalid_wait_totals"
			sum += p.wait_by_stage[stage]
		if sum != p.wait_ticks: return "invalid_wait_totals"
		if is_care:
			var care_error: String = _care_progress(p,d,catalog)
			if care_error != "": return care_error
		else:
			for field: String in CARE_FIELDS:
				if p.has(field): return "unexpected_care_fields"
			if p.has("mode_override") and p.mode_override not in ["fast","gentle"]: return "invalid_mode_override"
			if p.treatment_started:
				if not _fields(p,{"service_mode":TYPE_STRING,"treatment_start_tick":TYPE_INT,"needs_recovery":TYPE_BOOL}) or p.service_mode not in ["fast","gentle"] or p.treatment_start_tick < p.arrival_tick or p.treatment_start_tick > d.tick: return "invalid_treatment_latch"
				if p.needs_recovery != (catalog.diseases[p.disease_id].modes[p.service_mode].stimulus > p.tolerance): return "invalid_recovery_latch"
			elif p.phase in ["treatment_service","waiting_recovery","moving_recovery","recovering","leaving","completed"]: return "missing_treatment_latch"
		if p.phase in ["leaving","completed"] and not p.services_complete: return "missing_completed_services"
		if p.phase in ["abandoning","abandoned"] and p.abandon_tick < 0: return "missing_abandonment_time"
		if p.phase == "recovering" and not p.has("recovery_start_tick"): return "missing_recovery_start"
		if p.phase.begins_with("moving_") and p.phase != "moving_"+p.stage: return "invalid_moving_stage"
		if p.phase in PatientFlow.QUEUES and p.phase != ("waiting_recovery" if p.stage == "recovery" else p.stage+"_queue"): return "invalid_queue_stage"
		if p.has("recovery_start_tick") and (not p.recovery_start_tick is int or p.recovery_start_tick < p.get("treatment_start_tick",0) or p.recovery_start_tick > d.tick): return "invalid_recovery_time"
		if p.phase in ["outside","completed","abandoned"]:
			if p.has("cell") or p.slot_id != "" or p.room_id != "": return "invalid_absent_patient"
			if (p.phase == "outside") != (p.exit_tick == -1): return "invalid_exit_time"
		else:
			if not p.has("cell") or p.admitted_tick < 0 or p.exit_tick != -1: return "invalid_inside_patient"
			inside += 1
		if p.room_id != "" and not d.rooms.has(p.room_id): return "unknown_patient_room"
	if inside > catalog.levels[d.level_id].max_patients: return "patient_capacity"
	var state := ClinicState.new()
	state.data = d
	for id in d.rooms:
		var proposal: Dictionary = d.rooms[id].duplicate(true)
		proposal.room_id = id
		if not GridService.preview(state,proposal).ok: return "invalid_map_or_actor_edge"
	var navigation := GridService._navigation(d.rooms)
	for actors in [d.patients,d.staff]:
		for a in actors.values():
			if a.has("cell") and GridService.path(state,a.cell,a.cell).is_empty(): return "invalid_actor_cell"
			if a.get("route_revision",0) > d.map_revision: return "invalid_route_revision"
			if a.move_progress > 0 and not GridService._can_step(navigation,a.cell,a.path[a.path_index+1]): return "invalid_in_flight_edge"
			# _walk trusts a current cache. Every remaining cell/edge must be
			# usable; stale future geometry remains valid until the next replan.
			if a.get("route_revision",-1) == d.map_revision:
				for i in range(a.path_index,a.path.size()):
					if not GridService._walkable(navigation,a.path[i]): return "invalid_cached_route_cell"
					if i+1 < a.path.size() and not GridService._can_step(navigation,a.path[i],a.path[i+1]): return "invalid_cached_route_edge"
	return ""

static func _is_care(p: Dictionary, catalog: ContentCatalog) -> bool:
	return catalog.diseases[p.disease_id].has("care_steps")

# This branch is selected by trusted content, never by patient-supplied flags.
# Abandonment preserves completed-prefix history and cost. It cannot interrupt
# a service: public patience processing excludes all active service phases.
static func _care_progress(p: Dictionary, d: Dictionary, catalog: ContentCatalog) -> String:
	if not _fields(p,{"care_steps":TYPE_ARRAY,"care_cursor":TYPE_INT,"care_started_ticks":TYPE_DICTIONARY,"care_completed_ticks":TYPE_DICTIONARY}): return "invalid_care_fields"
	var steps: Array = catalog.diseases[p.disease_id].care_steps
	if p.care_steps != steps or p.care_cursor < 0 or p.care_cursor > steps.size(): return "invalid_care_cursor"
	if p.treatment_started: return "invalid_care_treatment_latch"
	for field: String in ["mode_override","service_mode","treatment_start_tick","needs_recovery","recovery_start_tick"]:
		if p.has(field): return "invalid_care_treatment_latch"
	var started: Dictionary = p.care_started_ticks
	var completed: Dictionary = p.care_completed_ticks
	var aborting: bool = p.phase in ["abandoning","abandoned"]
	var latest: int = p.exit_tick if p.exit_tick >= 0 else d.tick
	if aborting and p.abandon_tick >= 0: latest = mini(latest,p.abandon_tick)
	for stage in started:
		if stage not in steps or not started[stage] is int or started[stage] < p.arrival_tick or started[stage] > latest: return "invalid_care_start"
	for stage in completed:
		if stage not in steps or not completed[stage] is int or not started.has(stage) or completed[stage] > latest: return "invalid_care_completion"
		if completed[stage] != started[stage]+catalog.rooms[stage].service_ticks: return "invalid_care_duration"
	var previous_completed: int = p.arrival_tick
	for index in range(steps.size()):
		var stage: String = steps[index]
		if index < p.care_cursor:
			if not started.has(stage) or not completed.has(stage): return "missing_care_prefix"
		else:
			if completed.has(stage) or (index > p.care_cursor and started.has(stage)): return "invalid_care_prefix"
			if aborting and started.has(stage): return "invalid_care_abort_start"
		if started.has(stage) and started[stage] < previous_completed: return "invalid_care_order"
		if completed.has(stage): previous_completed = completed[stage]
	if p.services_complete != (p.care_cursor == steps.size()): return "invalid_care_complete_flag"
	if (not started.is_empty() or p.stage in CARE_STAGES or p.care_cursor > 0) and not p.tolerance_revealed: return "missing_care_diagnosis"
	if aborting:
		if p.stage != "exit": return "invalid_care_exit"
	elif p.phase in ["leaving","completed"]:
		if p.stage != "exit" or p.care_cursor != steps.size(): return "invalid_care_exit"
	elif p.phase == "outside" or p.stage in ["reception","diagnosis"]:
		if p.care_cursor != 0 or not started.is_empty() or not completed.is_empty(): return "premature_care_progress"
		if p.phase == "outside" and p.stage != "reception": return "invalid_care_stage"
	else:
		if p.care_cursor >= steps.size() or p.stage != steps[p.care_cursor]: return "invalid_care_stage"
		if p.phase not in [p.stage+"_queue","moving_"+p.stage,p.stage+"_service"]: return "invalid_care_phase"
		if started.has(p.stage) != (p.phase == p.stage+"_service"): return "invalid_care_active_start"
	return ""

static func _ownership(d: Dictionary, catalog: ContentCatalog) -> String:
	var queued := {}
	for room_id in d.queues:
		if not d.rooms.has(room_id) or not d.queues[room_id] is Array or not _unique_strings(d.queues[room_id]): return "invalid_queue"
		var last_tick := -1
		var last_id := ""
		for id in d.queues[room_id]:
			if not d.patients.has(id) or queued.has(id): return "invalid_queue_patient"
			var p: Dictionary = d.patients[id]
			if p.room_id != room_id or p.slot_id != "" or p.phase not in PatientFlow.QUEUES: return "invalid_queue_owner"
			var kind: String = catalog.diseases[p.disease_id].room_kind if p.stage == "treatment" else p.stage
			if d.rooms[room_id].kind != kind: return "invalid_queue_kind"
			if p.queue_enter_tick < last_tick or (p.queue_enter_tick == last_tick and id < last_id): return "invalid_queue_order"
			last_tick = p.queue_enter_tick
			last_id = id
			queued[id] = room_id
	var active := {}
	var blocked := {}
	var expected_slots := {}
	for room_id in d.rooms:
		for index in range(d.rooms[room_id].service_cells.size()): expected_slots[room_id+":"+str(index)] = d.rooms[room_id].service_cells[index]
	if expected_slots.size() != d.slots.size(): return "invalid_slot_count"
	for id in d.slots:
		if not expected_slots.has(id) or not d.slots[id] is Dictionary: return "invalid_slot_id"
		var s: Dictionary = d.slots[id]
		if not _fields(s,{"room_id":TYPE_STRING,"cell":TYPE_INT,"patient_id":TYPE_STRING,"phase":TYPE_STRING,"remaining_ticks":TYPE_INT}): return "invalid_slot"
		if not d.rooms.has(s.room_id) or not id.begins_with(s.room_id+":") or s.cell != expected_slots[id] or s.phase not in ["free","reserved","serving","blocked"] or s.remaining_ticks < 0: return "invalid_slot"
		if s.phase == "free":
			if s.patient_id != "" or s.remaining_ticks != 0: return "invalid_free_slot"
			continue
		if not d.patients.has(s.patient_id): return "unknown_slot_patient"
		var p: Dictionary = d.patients[s.patient_id]
		if s.phase == "blocked":
			if blocked.has(p.id) or p.get("cell",-1) != s.cell or s.remaining_ticks != 0: return "invalid_blocked_slot"
			var blocked_kind: String = d.rooms[s.room_id].kind
			if blocked_kind in CARE_STAGES and (not _is_care(p,catalog) or not p.care_completed_ticks.has(blocked_kind) or p.care_cursor<=0 or p.care_steps[p.care_cursor-1]!=blocked_kind): return "invalid_care_blocked_slot"
			blocked[p.id] = id
		else:
			if active.has(p.id) or queued.has(p.id) or p.slot_id != id or p.room_id != s.room_id: return "invalid_active_slot_owner"
			active[p.id] = id
			var expected_kind: String = catalog.diseases[p.disease_id].room_kind if p.stage == "treatment" else p.stage
			if d.rooms[s.room_id].kind != expected_kind: return "invalid_service_kind"
			if expected_kind in CARE_STAGES and d.rooms[s.room_id].staff_id == "": return "missing_service_staff"
			if s.phase == "reserved":
				if p.phase != "moving_"+p.stage or s.remaining_ticks != 0: return "invalid_reserved_slot"
			else:
				var max_ticks: int = catalog.diseases[p.disease_id].modes[p.service_mode].duration_ticks if p.stage == "treatment" else catalog.rooms[expected_kind].service_ticks
				if p.phase != ("recovering" if p.stage == "recovery" else p.stage+"_service") or p.cell != s.cell or p.move_progress != 0 or s.remaining_ticks <= 0 or s.remaining_ticks > max_ticks: return "invalid_serving_slot"
				if expected_kind in CARE_STAGES and s.remaining_ticks != max_ticks-(d.tick-p.care_started_ticks[expected_kind]): return "invalid_care_remaining_ticks"
				if expected_kind != "recovery" and d.rooms[s.room_id].staff_id == "": return "missing_service_staff"
	if not _unique_strings(d.outside_queue): return "invalid_outside_queue"
	for id in d.outside_queue:
		if not d.patients.has(id) or d.patients[id].phase != "outside": return "invalid_outside_owner"
	for id in d.patients:
		var p: Dictionary = d.patients[id]
		if (p.phase == "outside") != (id in d.outside_queue): return "missing_outside_membership"
		if (p.slot_id != "") != active.has(id): return "missing_active_membership"
		if p.slot_id == "" and (p.phase.begins_with("moving_") or p.phase in PatientFlow.SERVICES): return "missing_service_reservation"
		if p.phase in PatientFlow.QUEUES and p.room_id != "" and not queued.has(id): return "missing_queue_membership"
	for employee in d.staff.values():
		var occupation := ""
		var committed: int = 0
		for s in d.slots.values():
			if s.room_id == employee.room_id and s.phase in ["serving","blocked"]:
				committed += 1
				if s.phase == "serving" or occupation == "": occupation = s.phase
		if committed > 1 and (employee.room_id == "" or d.rooms[employee.room_id].kind != "ward"): return "invalid_staff_parallel_service"
		if occupation != "" and employee.phase != occupation: return "invalid_staff_occupation"
		if occupation == "" and employee.phase in ["serving","blocked"]: return "invalid_staff_occupation"
		if occupation == "serving" and employee.get("cell",-1) != d.rooms[employee.room_id].staff_cells[0]: return "invalid_service_staff_cell"
	for room_id in d.rooms:
		if d.rooms[room_id].status != "closed": continue
		if not d.queues[room_id].is_empty(): return "closed_room_occupied"
		for s in d.slots.values():
			if s.room_id == room_id and s.phase != "free": return "closed_room_occupied"
		for actors in [d.patients,d.staff]:
			for a in actors.values():
				if a.has("cell") and (a.cell in d.rooms[room_id].cells or (a.move_progress > 0 and a.path[a.path_index+1] in d.rooms[room_id].cells)): return "closed_room_occupied"
	return ""

static func _finance(d: Dictionary, catalog: ContentCatalog) -> String:
	var m: Dictionary = d.metrics
	if not _fields(m,{"completed":TYPE_INT,"abandoned":TYPE_INT,"operating_profit":TYPE_INT,"income":TYPE_INT,"treatment_cost":TYPE_INT,"recovery_cost":TYPE_INT,"wages":TYPE_INT,"fixed_cost":TYPE_INT,"wait_ticks":TYPE_DICTIONARY,"patient_totals":TYPE_DICTIONARY}): return "invalid_metrics"
	var capital := _capital_history(d,catalog)
	if not capital.ok: return capital.error
	var expected_care: Dictionary = _care_events(d,catalog)
	var balance: int = catalog.levels[d.level_id].initial_cash
	var totals := {"income":0,"treatment_cost":0,"recovery_cost":0,"wages":0,"fixed_cost":0,"operating_profit":0}
	var events := {}
	var last_tick := -1
	for e in d.ledger_entries:
		if not e is Dictionary or not _fields(e,{"event_id":TYPE_STRING,"category":TYPE_STRING,"delta":TYPE_INT,"tick":TYPE_INT}): return "invalid_ledger"
		if e.event_id == "" or events.has(e.event_id) or e.category not in Ledger.OPERATING+Ledger.CAPITAL or e.tick < last_tick or e.tick > d.tick: return "invalid_ledger_event"
		if (e.category in ["income","capital_refund"] and e.delta < 0) or (e.category not in ["income","capital_refund"] and e.delta > 0): return "invalid_ledger_sign"
		if e.category in Ledger.CAPITAL:
			if not capital.events.has(e.event_id): return "invalid_capital_event"
			var expected: Dictionary = capital.events[e.event_id]
			if expected.category != e.category or expected.tick != e.tick: return "invalid_capital_category"
			if e.delta != expected.delta: return "invalid_capital_amount"
		elif e.category in ["wages","fixed_cost"]:
			if e.tick <= 0 or e.tick % catalog.levels[d.level_id].day_ticks != 0 or e.event_id != e.category+":"+str(e.tick) or e.tick > d.last_payroll_tick: return "invalid_payroll_event"
		else:
			if e.event_id.begins_with("care:"):
				if not expected_care.has(e.event_id): return "invalid_care_event"
				var care: Dictionary = expected_care[e.event_id]
				if e.category != "treatment_cost" or e.tick != care.tick or e.delta != care.delta: return "invalid_care_event"
			else:
				var prefix: String = {"income":"income:","treatment_cost":"treatment:","recovery_cost":"recovery:"}[e.category]
				if not e.event_id.begins_with(prefix) or not d.patients.has(e.event_id.trim_prefix(prefix)): return "invalid_patient_event"
		events[e.event_id] = e
		last_tick = e.tick
		balance += e.delta
		if absi(balance) > MAX_INTEGER: return "invalid_balance_range"
		if e.category in Ledger.OPERATING:
			totals[e.category] += e.delta if e.category == "income" else -e.delta
			totals.operating_profit += e.delta
	for event_id in capital.events:
		if not events.has(event_id): return "missing_capital_event"
	for event_id in expected_care:
		if not events.has(event_id): return "missing_care_event"
	if balance != d.cash: return "cash_not_conserved"
	for key in totals:
		if totals[key] != m[key]: return "ledger_metrics_mismatch:"+key
	for tick in range(catalog.levels[d.level_id].day_ticks,d.last_payroll_tick+1,catalog.levels[d.level_id].day_ticks):
		if not events.has("wages:"+str(tick)) or not events.has("fixed_cost:"+str(tick)): return "missing_payroll_event"
	var completed := 0
	var abandoned := 0
	var waits := {}
	var terminal := {}
	for p in d.patients.values():
		for stage in p.wait_by_stage: waits[stage] = waits.get(stage,0)+p.wait_by_stage[stage]
		if p.phase == "completed": completed += 1
		if p.phase == "abandoned": abandoned += 1
		if p.phase in PatientFlow.TERMINAL:
			terminal[p.id] = {"arrival_tick":p.arrival_tick,"admitted_tick":p.admitted_tick,"exit_tick":p.exit_tick,"phase":p.phase,"wait_ticks":p.wait_ticks,"wait_by_stage":p.wait_by_stage,"walked_cells":p.walked_cells,"total_ticks":p.exit_tick-p.arrival_tick}
		for record in [["treatment:","treatment_started","treatment_cost"],["recovery:","recovery_start_tick","recovery_cost"],["income:","phase","income"]]:
			var should_exist: bool = p.treatment_started if record[0] == "treatment:" else (p.has("recovery_start_tick") if record[0] == "recovery:" else p.phase == "completed")
			if events.has(record[0]+p.id) != should_exist: return "missing_or_unearned_patient_money"
			if should_exist:
				var entry: Dictionary = events[record[0]+p.id]
				var delta: int = -catalog.diseases[p.disease_id].modes[p.service_mode].cost if record[0] == "treatment:" else (-catalog.rooms.recovery.consumable_cost if record[0] == "recovery:" else catalog.diseases[p.disease_id].income)
				if entry.category != record[2] or entry.delta != delta: return "invalid_patient_money"
	if completed != m.completed or abandoned != m.abandoned or waits != m.wait_ticks or terminal != m.patient_totals: return "invalid_clinical_metrics"
	return ""

static func _care_events(d: Dictionary, catalog: ContentCatalog) -> Dictionary:
	var events: Dictionary = {}
	for p: Dictionary in d.patients.values():
		if not _is_care(p,catalog): continue
		for stage: String in p.care_started_ticks:
			var event_id: String = "care:"+p.id+":"+stage
			events[event_id] = {"tick":p.care_started_ticks[stage],"delta":-catalog.rooms[stage].consumable_cost}
	return events

# Room edit prices depend on the preceding layout, including rooms that have
# since been removed. Rebuild that price history from ordered command receipts;
# neither a claimed refund nor the current room alone proves the ledger delta.
static func _capital_history(d: Dictionary, catalog: ContentCatalog) -> Dictionary:
	var ordered: Array = d.command_receipts.values()
	ordered.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a.data.sequence < b.data.sequence)
	var rooms := {}
	var used_ids := {}
	var events := {}
	for receipt: Dictionary in ordered:
		var command: Dictionary = receipt.data.command
		var payload: Dictionary = command.payload
		var event_id: String = "command:"+command.id
		var category := ""
		var delta := 0
		if command.type == "build_room":
			if not receipt.data.get("room_id") is String or not _id(receipt.data.room_id,"room",d.next_ids.room) or used_ids.has(receipt.data.room_id): return {"ok":false,"error":"invalid_build_history"}
			var cost: int = catalog.rooms[payload.kind].cost
			if payload.has("layout"): cost = FreeRoomLayout.base_cost(payload.kind,payload.layout,catalog)
			rooms[receipt.data.room_id] = {"kind":payload.kind,"upgraded":false,"cost":cost}
			used_ids[receipt.data.room_id] = true
			category = "capital_build"
			delta = -cost
		elif command.type == "hire_staff":
			category = "capital_hire"
			delta = -catalog.staff[payload.role].hire_cost
		elif command.type in ["move_room","upgrade_recovery","remove_room"]:
			if not payload.get("room_id") is String or not rooms.has(payload.room_id) or receipt.data.get("room_id") != payload.room_id: return {"ok":false,"error":"invalid_room_price_history"}
			var room: Dictionary = rooms[payload.room_id]
			if command.type == "move_room" and payload.has("layout"):
				var layout_error := FreeRoomLayout.validate(room.kind,payload.layout,room.upgraded)
				if layout_error != "": return {"ok":false,"error":"invalid_receipt_layout:"+layout_error}
				var cost: int = FreeRoomLayout.base_cost(room.kind,payload.layout,catalog,room.upgraded)
				var difference: int = cost-room.cost
				if difference > 0:
					category = "capital_build"
					delta = -difference
				elif difference < 0:
					category = "capital_refund"
					delta = int(-difference*3/4)
				room.cost = cost
			elif command.type == "upgrade_recovery":
				if room.kind != "recovery" or room.upgraded: return {"ok":false,"error":"invalid_upgrade_history"}
				room.upgraded = true
				room.cost += catalog.rooms.recovery.upgrade_cost
				category = "capital_upgrade"
				delta = -catalog.rooms.recovery.upgrade_cost
			elif command.type == "remove_room":
				category = "capital_refund"
				delta = int(room.cost*3/4)
				if not receipt.data.get("refund") is int or receipt.data.refund != delta: return {"ok":false,"error":"invalid_refund_receipt"}
				rooms.erase(payload.room_id)
		if category != "": events[event_id] = {"category":category,"delta":delta,"tick":receipt.data.tick}
	if rooms.size() != d.rooms.size(): return {"ok":false,"error":"invalid_room_price_history"}
	for id in rooms:
		if not d.rooms.has(id) or d.rooms[id].kind != rooms[id].kind or d.rooms[id].upgraded != rooms[id].upgraded or d.rooms[id].invested_cost != rooms[id].cost: return {"ok":false,"error":"invalid_room_price_history"}
	return {"ok":true,"error":"","events":events}

static func _receipts(d: Dictionary, catalog: ContentCatalog) -> String:
	if d.command_receipts.size() != d.command_sequence: return "invalid_receipt_count"
	var sequences := {}
	for id in d.command_receipts:
		var r: Variant = d.command_receipts[id]
		if not r is Dictionary or not _fields(r,{"ok":TYPE_BOOL,"code":TYPE_STRING,"data":TYPE_DICTIONARY}) or not r.ok or r.code != "ok": return "invalid_receipt"
		if not _fields(r.data,{"tick":TYPE_INT,"sequence":TYPE_INT,"command":TYPE_DICTIONARY}): return "invalid_receipt_data"
		if r.data.tick < 0 or r.data.tick > d.tick or r.data.sequence < 1 or r.data.sequence > d.command_sequence or sequences.has(r.data.sequence): return "invalid_receipt_sequence"
		sequences[r.data.sequence] = true
		var c: Dictionary = r.data.command
		if not _fields(c,{"id":TYPE_STRING,"type":TYPE_STRING,"payload":TYPE_DICTIONARY}) or c.id != id or c.type not in COMMANDS: return "invalid_receipt_command"
		var p: Dictionary = c.payload
		if c.type == "build_room" and (not p.get("kind") is String or not catalog.rooms.has(p.kind)): return "unknown_receipt_room"
		if c.type in ["build_room","move_room"] and p.has("layout"):
			if not p.get("rotation") is int or p.rotation != 0: return "invalid_receipt_layout_rotation"
			var layout_error := FreeRoomLayout.validate_shape(p.layout)
			if layout_error != "": return "invalid_receipt_layout:"+layout_error
			if c.type == "build_room":
				layout_error = FreeRoomLayout.validate(p.kind,p.layout)
				if layout_error != "": return "invalid_receipt_layout:"+layout_error
		if c.type == "hire_staff" and (not p.get("role") is String or not catalog.staff.has(p.role)): return "unknown_receipt_staff"
		if c.type == "dismiss_staff":
			if not _fields(p,{"staff_id":TYPE_STRING}) or not _id(p.staff_id,"staff",d.next_ids.staff): return "invalid_dismiss_receipt"
			if not _fields(r.data,{"staff_id":TYPE_STRING,"role":TYPE_STRING}) or r.data.staff_id != p.staff_id or not catalog.staff.has(r.data.role): return "invalid_dismiss_receipt"
		if c.type in ["set_room_mode","set_patient_mode"] and p.get("mode") not in ["fast","gentle"]: return "invalid_receipt_mode"
		if c.type == "set_speed" and p.get("speed") not in [1,2]: return "invalid_receipt_speed"
		if c.type == "set_paused" and not p.get("paused") is bool: return "invalid_receipt_pause"
		if c.type == "set_auto_route" and not p.get("enabled") is bool: return "invalid_receipt_route"
	return _dismissal_history(d)

# Old snapshots need not reconstruct staff history. A new dismissal must prove
# its own preceding hire, keep that capital cost, and never leave or reuse its ID.
static func _dismissal_history(d: Dictionary) -> String:
	var targets := {}
	for receipt: Dictionary in d.command_receipts.values():
		if receipt.data.command.type == "dismiss_staff": targets[receipt.data.staff_id] = true
	if targets.is_empty(): return ""
	var ordered: Array = d.command_receipts.values()
	ordered.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a.data.sequence < b.data.sequence)
	var hired := {}
	var dismissed := {}
	for receipt: Dictionary in ordered:
		var command: Dictionary = receipt.data.command
		if command.type == "hire_staff" and targets.has(receipt.data.get("staff_id","")):
			var staff_id: String = receipt.data.staff_id
			if hired.has(staff_id): return "invalid_dismiss_staff_history"
			hired[staff_id] = command.payload.role
		elif command.type == "dismiss_staff":
			var staff_id: String = receipt.data.staff_id
			if not hired.has(staff_id) or dismissed.has(staff_id) or receipt.data.role != hired[staff_id]: return "invalid_dismiss_staff_history"
			dismissed[staff_id] = true
	for staff_id in dismissed:
		if d.staff.has(staff_id): return "active_dismissed_staff"
	return ""
