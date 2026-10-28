class_name LongCampaignValidator
extends RefCounted

const CLINIC_DRIVE:=preload("res://campaign/campaign_clinic_drive.gd")
const STAFF_RELIEF:=preload("res://campaign/campaign_staff_relief.gd")
const RELIEF_VALIDATOR:=preload("res://campaign/campaign_staff_relief_validator.gd")

const RULESET: String = "full-hospital-v2"
const GEOMETRY_RULESET: String = "full-hospital-v1"
const MAX_INTEGER: int = 9007199254740991
const INITIAL_RESOURCES: Dictionary = {"supplies":40,"sterile":8,"blood":4,"samples":0,"prepared":0,"waste":0,"water":20,"food":20,"spares":6}
const PATIENT_PHASES: Array = ["care_queue","moving_care","care_service","waiting_support","moving_exit","left","abandoned"]

# A separate authoritative schema; no state is projected into the v1 model.
static func validate(d: Dictionary, catalog: ContentCatalog) -> String:
	if catalog == null or not _model(d): return "invalid_long_model"
	if d.get("schema_version") != 3 or d.get("ruleset") != RULESET: return "incompatible_long_schema"
	if d.get("content_version") != catalog.content_version: return "incompatible_long_content"
	if not _fields(d,{"last_payroll_tick":TYPE_INT}): return "invalid_long_payroll_clock"
	if not _fields(d,{"level_id":TYPE_STRING,"tick":TYPE_INT,"paused":TYPE_BOOL,"speed":TYPE_INT,"cash":TYPE_INT,"next_ids":TYPE_DICTIONARY,"command_sequence":TYPE_INT,"map_revision":TYPE_INT,"rooms":TYPE_DICTIONARY,"staff":TYPE_DICTIONARY,"patients":TYPE_DICTIONARY,"facilities":TYPE_DICTIONARY,"slots":TYPE_DICTIONARY,"queues":TYPE_DICTIONARY,"work_orders":TYPE_DICTIONARY,"resources":TYPE_DICTIONARY,"evidence":TYPE_DICTIONARY,"campaign":TYPE_DICTIONARY,"ledger_entries":TYPE_ARRAY,"command_receipts":TYPE_DICTIONARY,"metrics":TYPE_DICTIONARY,"challenge":TYPE_DICTIONARY}): return "invalid_long_fields"
	if not catalog.levels.has(d.level_id) or catalog.levels[d.level_id].get("ruleset") != RULESET: return "unknown_long_level"
	var day_ticks: int=catalog.levels[d.level_id].day_ticks
	if d.last_payroll_tick!=int(d.tick/day_ticks)*day_ticks: return "invalid_long_payroll_clock"
	if d.tick < 0 or d.speed not in [1,2] or d.cash < 0 or d.command_sequence < 0 or d.map_revision < 0: return "invalid_long_clock"
	if d.has("appearance_seed") and (not d.appearance_seed is int or d.appearance_seed < 1 or d.appearance_seed > 2147483647): return "invalid_appearance_seed"
	if not _fields(d.next_ids,{"room":TYPE_INT,"staff":TYPE_INT,"patient":TYPE_INT,"facility":TYPE_INT,"work_order":TYPE_INT,"case_instance":TYPE_INT}): return "invalid_long_next_ids"
	for number: Variant in d.next_ids.values():
		if not number is int or number < 1: return "invalid_long_next_ids"
	var error: String = _campaign(d,catalog)
	if error != "": return error
	error = CampaignExperience.validate(d)
	if error != "": return error
	error = RELIEF_VALIDATOR.shape_error(d)
	if error != "":return error
	error = _entities(d,catalog)
	if error != "": return error
	error = _patients(d,catalog)
	if error != "": return error
	error = _instances(d,catalog)
	if error != "": return error
	error = _orders(d,catalog)
	if error != "": return error
	error = _training_and_order_index(d)
	if error != "": return error
	error = _ownership(d,catalog)
	if error != "": return error
	error = _finance(d,catalog)
	if error != "": return error
	error = _resources(d,catalog)
	if error != "": return error
	error = CampaignBusiness.validate(d,catalog)
	if error != "": return error
	error = CampaignPeopleValidator.validate(d,catalog)
	if error != "": return error
	error = CampaignClinicalDecisionsValidator.validate(d,catalog)
	if error != "": return error
	error = CampaignManagementEventsValidator.validate(d,catalog)
	if error != "": return error
	error = _progress(d,catalog)
	if error != "":return error
	error = RELIEF_VALIDATOR.validate(d,catalog)
	if error != "":return error
	return CLINIC_DRIVE.validate(d,catalog)

static func _core() -> Script:
	var path: String = "res://campaign/long_campaign.gd"
	return load(path) if ResourceLoader.exists(path) else null

static func _training_and_order_index(d: Dictionary) -> String:
	var pending: Array = []
	var trainees: Dictionary = {}
	for order: Dictionary in d.work_orders.values():
		if order.status == "done": continue
		pending.append(order.id)
		if order.has("trainee_id"):
			if trainees.has(order.trainee_id) or not d.staff.has(order.trainee_id): return "invalid_long_pending_training"
			trainees[order.trainee_id] = order.id
	var actual: Array = d.campaign.active_order_ids.duplicate()
	pending.sort_custom(func(a: String,b: String) -> bool: return int(a.trim_prefix("work_")) < int(b.trim_prefix("work_")))
	if pending != actual: return "invalid_long_active_order_index"
	for staff: Dictionary in d.staff.values():
		var training: Variant = staff.get("training_order_id","")
		if not training is String or training != trainees.get(staff.id,""): return "invalid_long_training_owner"
		if training != "" and (staff.patient_id != "" or (staff.work_order_id != "" and staff.work_order_id != training)): return "conflicting_long_training_owner"
		if training != "" and d.work_orders[training].status == "working":
			var facility: Dictionary = d.facilities[d.work_orders[training].facility_id]
			if staff.cell != facility.maintenance_cell or staff.move_progress != 0: return "invalid_long_training_arrival"
	return ""

static func _receipts(d: Dictionary, catalog: ContentCatalog) -> String:
	if d.command_receipts.size() != d.command_sequence: return "invalid_long_receipt_count"
	var sequence: Dictionary = {}
	var hires: Dictionary = {}
	var dismissed: Dictionary = {}
	var manual_events: Dictionary = {}
	var price: int = 100
	var intake: bool = false
	var phase: int = 0
	var continuing: bool = false
	var prices: Dictionary = {0:100}
	var intakes: Dictionary = {0:false}
	var phases: Dictionary = {0:0}
	var automations: Dictionary = {}
	for id: String in d.command_receipts:
		var receipt: Variant = d.command_receipts[id]
		if not receipt is Dictionary or not _fields(receipt,{"ok":TYPE_BOOL,"code":TYPE_STRING,"data":TYPE_DICTIONARY}) or not receipt.ok or receipt.code != "ok": return "invalid_long_receipt"
		var result: Dictionary = receipt.data
		if not _fields(result,{"tick":TYPE_INT,"sequence":TYPE_INT,"command":TYPE_DICTIONARY}) or result.tick < 0 or result.tick > d.tick or result.sequence < 1 or result.sequence > d.command_sequence or sequence.has(result.sequence): return "invalid_long_receipt_sequence"
		var command: Dictionary = result.command
		if not _fields(command,{"id":TYPE_STRING,"type":TYPE_STRING,"payload":TYPE_DICTIONARY}) or command.id != id or command.type not in ["set_paused","set_speed","build_department","edit_department","place_facility","remove_room","remove_facility","hire","hire_staff","assign","assign_staff","unassign","dismiss","dismiss_staff","accept_case","admit_routine","run_operation","request_audit","start_research","start_training","set_price","take_loan","repay_loan","resolve_event","close_facility","reopen_facility","advance_stage","set_intake","set_operation_auto","continue_hospital","set_procurement_policy","set_clinical_policy","clinical_decision","request_patient_need","set_staff_wage","set_people_autonomy","request_staff_rest","choose_management_event","resolve_management_event","set_clinic_drive","set_staff_relief","set_staff_relief_reserve","set_staff_relief_operations"]: return "invalid_long_receipt_command"
		sequence[result.sequence] = result
	var last_tick: int = 0
	for n: int in range(1,d.command_sequence+1):
		if not sequence.has(n) or sequence[n].tick < last_tick: return "invalid_long_receipt_order"
		var result: Dictionary = sequence[n]
		last_tick = result.tick
		var command: Dictionary = result.command
		var payload: Dictionary = command.payload
		match command.type:
			"hire","hire_staff":
				var sid: Variant = result.get("staff_id")
				var role: Variant = payload.get("role")
				if not sid is String or not _id(sid,"staff",d.next_ids.staff) or not role is String or not catalog.campaign.roles.has(role) or hires.has(sid): return "invalid_long_hire_history"
				hires[sid] = role
			"dismiss","dismiss_staff":
				var sid: Variant = payload.get("staff_id")
				if not sid is String or result.get("staff_id") != sid or not hires.has(sid) or dismissed.has(sid): return "invalid_long_dismiss_history"
				dismissed[sid] = true
			"set_price":
				if not payload.get("percent") is int or payload.percent < 75 or payload.percent > 150: return "invalid_long_price_history"
				price = payload.percent
			"set_intake":
				if not payload.get("enabled") is bool: return "invalid_long_intake_history"
				intake = payload.enabled
			"set_operation_auto":
				if not _fields(payload,{"facility_kind":TYPE_STRING,"enabled":TYPE_BOOL,"target":TYPE_INT}) or not catalog.campaign.facilities.has(payload.facility_kind): return "invalid_long_automation_history"
				var f: Dictionary = catalog.campaign.facilities[payload.facility_kind]
				var management: bool = f.output.is_empty() and f.handler in ["repair","floor_clean","toilet_clean","filter","tool_clean"]
				if payload.target < 1 or payload.target > (100 if management else 1000) or (f.output.is_empty() and not management): return "invalid_long_automation_history"
				automations[payload.facility_kind] = {"enabled":payload.enabled,"target":payload.target}
			"advance_stage":
				phase += 1
				if phase > 4 or result.get("phase_index") != phase or result.get("course_complete") != (phase == 4): return "invalid_long_stage_command"
				if phase == 4: intake = false
			"continue_hospital":
				if phase != 4 or result.get("continuing") != true: return "invalid_long_continue_command"
				continuing = true
			"accept_case","admit_routine":
				var eid: Variant = result.get("admission_event_id")
				if not eid is String or not d.campaign.admission_events.has(eid) or manual_events.has(eid): return "invalid_long_admission_receipt"
				var event: Dictionary = d.campaign.admission_events[eid]
				var instance: Dictionary = d.campaign.case_instances[event.instance_id]
				if event.source != "manual" or event.command_sequence != n or event.tick != result.tick or event.instance_id != result.get("instance_id") or event.patient_ids != result.get("patient_ids") or event.case_id != result.get("case_id") or event.case_id != payload.get("case_id") or instance.kind != ("signature" if command.type == "accept_case" else "routine"): return "invalid_long_admission_receipt"
				manual_events[eid] = true
		prices[n] = price
		intakes[n] = intake
		phases[n] = phase
	if price != d.campaign.price_percent or intake != d.campaign.intake_enabled or phase != d.campaign.phase_index or continuing != d.campaign.continuing or automations != d.campaign.automation: return "invalid_long_command_policy"
	for event: Dictionary in d.campaign.admission_events.values():
		if event.quoted_price_percent != prices[event.command_sequence] or event.phase_index != phases[event.command_sequence]: return "invalid_long_admission_price"
		if event.source == "manual":
			if not manual_events.has(event.id): return "missing_long_manual_admission_receipt"
		else:
			if not intakes[event.command_sequence]: return "unearned_long_automatic_admission"
			if event.command_sequence > 0 and sequence[event.command_sequence].tick >= event.tick: return "invalid_long_auto_admission_clock"
			if event.command_sequence < d.command_sequence and sequence[event.command_sequence+1].tick < event.tick: return "invalid_long_auto_admission_sequence"
		var quote: int = CampaignExperience.clinical_income(d,int(catalog.campaign.cases[event.case_id].income),int(event.quoted_price_percent))
		for pid: String in event.patient_ids:
			if d.patients[pid].income != quote: return "invalid_long_patient_quote"
	for sid: String in d.staff:
		if not hires.has(sid) or dismissed.has(sid) or d.staff[sid].role != hires[sid]: return "invalid_long_staff_history"
	for sid: String in hires:
		if not dismissed.has(sid) and not d.staff.has(sid): return "missing_long_hired_staff"
	if hires.size()+1 != d.next_ids.staff: return "invalid_long_staff_allocator"
	for patient: Dictionary in d.patients.values():
		for index: int in range(patient.step_history.size()):
			var history: Dictionary = patient.step_history[index]
			var roles: Array = patient.steps[index].roles
			if history.staff_ids.size() != roles.size(): return "invalid_long_history_staff_roles"
			for n: int in range(roles.size()):
				if hires.get(history.staff_ids[n],"") != roles[n]: return "invalid_long_history_staff_roles"
	for order: Dictionary in d.work_orders.values():
		var roles: Array = catalog.campaign.facilities[order.facility_kind].roles
		for n: int in range(order.staff_ids.size()):
			if hires.get(order.staff_ids[n],"") != roles[n]: return "invalid_long_order_staff_roles"
		if order.has("automation"):
			if order.automation != true: return "invalid_long_automatic_order"
			var policy: Dictionary = {}
			for n: int in range(1,d.command_sequence+1):
				var row: Dictionary = sequence[n]
				if row.tick >= order.created_tick: break
				if row.command.type == "set_operation_auto" and row.command.payload.facility_kind == order.facility_kind: policy = row.command.payload
			if not policy.get("enabled",false) or order.created_tick%20 != 0: return "unearned_long_automatic_order"
	return ""

static func _campaign(d: Dictionary, catalog: ContentCatalog) -> String:
	var c: Dictionary = d.campaign
	if not _fields(c,{"wave_index":TYPE_INT,"wave_active":TYPE_BOOL,"current_case_id":TYPE_STRING,"completed_cases":TYPE_ARRAY,"completed_waves":TYPE_ARRAY,"price_percent":TYPE_INT,"loan":TYPE_INT,"reputation":TYPE_INT,"research":TYPE_ARRAY,"training":TYPE_ARRAY,"events":TYPE_ARRAY,"audits":TYPE_DICTIONARY,"career":TYPE_DICTIONARY,"phase_index":TYPE_INT,"phase_started_tick":TYPE_INT,"phase_baseline":TYPE_DICTIONARY,"phase_receipts":TYPE_ARRAY,"case_instances":TYPE_DICTIONARY,"admission_events":TYPE_DICTIONARY,"intake_enabled":TYPE_BOOL,"intake_cursor":TYPE_INT,"next_arrival_tick":TYPE_INT,"intake_reason":TYPE_STRING,"live_patient_ids":TYPE_ARRAY,"automation":TYPE_DICTIONARY,"day_records":TYPE_ARRAY,"day_start_tick":TYPE_INT,"day_start_income":TYPE_INT,"day_start_expenses":TYPE_INT,"course_complete":TYPE_BOOL,"continuing":TYPE_BOOL,"next_event_tick":TYPE_INT,"event_serial":TYPE_INT}): return "invalid_long_campaign"
	var level: Dictionary = catalog.levels[d.level_id]
	if not _strings(c.completed_cases) or c.completed_cases != level.case_ids.slice(0,c.completed_cases.size()) or c.wave_index != c.completed_cases.size() or c.completed_waves != c.completed_cases: return "invalid_long_signature_order"
	if c.phase_index < 0 or c.phase_index > 4 or c.phase_started_tick < 0 or c.phase_started_tick > d.tick or c.intake_cursor < 0 or c.next_arrival_tick < 0 or c.event_serial < 0 or c.next_event_tick < 0: return "invalid_long_campaign_clock"
	if c.price_percent < 75 or c.price_percent > 150 or c.loan < 0 or c.loan > 20000 or c.reputation < 0 or c.reputation > 100: return "invalid_long_policy"
	if not _fields(c.phase_baseline,{"tick":TYPE_INT,"completed":TYPE_INT,"abandoned":TYPE_INT,"income":TYPE_INT,"expenses":TYPE_INT,"day_index":TYPE_INT}): return "invalid_long_phase_baseline"
	if not _strings(c.live_patient_ids) or not _strings(c.get("active_order_ids")): return "invalid_long_active_index"
	if not _fields(c,{"day_start_completed":TYPE_INT,"day_start_abandoned":TYPE_INT}): return "invalid_long_day_baseline"
	for group: String in ["facilities","cases","audits","events","diseases"]:
		if not d.evidence.get(group) is Dictionary: return "invalid_long_evidence"
	for key: String in INITIAL_RESOURCES:
		if not d.resources.get(key) is int or d.resources[key] < 0: return "invalid_long_resource"
	var allowed: Dictionary = INITIAL_RESOURCES.duplicate()
	for definition: Dictionary in catalog.campaign.facilities.values():
		for key: String in definition.get("output",{}): allowed[key] = 0
	for key: String in d.resources:
		if not allowed.has(key) or not d.resources[key] is int or d.resources[key] < 0: return "invalid_long_resource"
	var core: Script = _core()
	if core == null or not core.has_method("validate_career"): return "missing_long_career_validator"
	var error: String = core.validate_career(c.career,catalog)
	if error != "": return error
	if d.has("career_tracks"):
		if not d.career_tracks is Dictionary: return "invalid_career_tracks"
		if d.career_tracks.has(RULESET) and d.career_tracks[RULESET] != c.career: return "inconsistent_long_career_track"
	if not _fields(d.challenge,{"status":TYPE_STRING,"reason":TYPE_STRING,"ended_tick":TYPE_INT}): return "invalid_long_challenge"
	if d.challenge.status == "running":
		if d.challenge.reason != "" or d.challenge.ended_tick != -1: return "invalid_long_challenge"
	elif d.challenge.status in ["won","lost","finished"]:
		if not d.paused or d.challenge.ended_tick < 0 or d.challenge.ended_tick > d.tick or d.challenge.reason == "": return "invalid_long_challenge"
	else: return "invalid_long_challenge"
	if c.continuing and (not c.course_complete or d.challenge.status != "running"): return "invalid_long_continuation"
	if c.course_complete != (c.phase_index == 4): return "invalid_long_course_complete"
	return ""

static func _instances(d: Dictionary, catalog: ContentCatalog) -> String:
	var cp: Dictionary = d.campaign
	var instances: Dictionary = cp.case_instances
	if instances.size() != d.next_ids.case_instance-1 or cp.admission_events.size() != instances.size(): return "invalid_long_instance_count"
	var patient_members: Dictionary = {}
	var completed_signatures: Array = []
	var all_signatures: Array = []
	var active_count: int = 0
	var active_signature: String = ""
	var auto_indices: Dictionary = {}
	var number: int = 1
	while number < d.next_ids.case_instance:
		var id: String = "instance_%06d"%number
		var event_id: String = "admission_%06d"%number
		if not instances.get(id) is Dictionary or not cp.admission_events.get(event_id) is Dictionary: return "invalid_long_instance_id"
		var instance: Dictionary = instances[id]
		var event: Dictionary = cp.admission_events[event_id]
		if not _fields(instance,{"id":TYPE_STRING,"case_id":TYPE_STRING,"kind":TYPE_STRING,"phase_index":TYPE_INT,"admitted_tick":TYPE_INT,"patient_ids":TYPE_ARRAY,"status":TYPE_STRING,"completed_tick":TYPE_INT,"admission_event_id":TYPE_STRING}): return "invalid_long_instance"
		if instance.id != id or instance.admission_event_id != event_id or not catalog.campaign.cases.has(instance.case_id) or instance.case_id not in catalog.levels[d.level_id].case_ids or instance.kind not in ["signature","routine"] or instance.status not in ["active","completed","failed"] or instance.phase_index < 0 or instance.phase_index > cp.phase_index or instance.admitted_tick < 0 or instance.admitted_tick > d.tick or not _strings(instance.patient_ids): return "invalid_long_instance"
		var definition: Dictionary = catalog.campaign.cases[instance.case_id]
		if instance.patient_ids.size() != definition.patient_count: return "invalid_long_instance_patients"
		var all_terminal: bool = true
		var all_success: bool = true
		var completed_tick: int = -1
		for pid: String in instance.patient_ids:
			if patient_members.has(pid) or not d.patients.has(pid): return "invalid_long_instance_membership"
			patient_members[pid] = id
			var p: Dictionary = d.patients[pid]
			if p.case_instance_id != id or p.case_id != instance.case_id or p.arrived_tick != instance.admitted_tick: return "invalid_long_instance_patient_identity"
			if p.phase not in ["left","abandoned"]: all_terminal = false
			if p.phase != "left" or p.outcome != "completed": all_success = false
			completed_tick = maxi(completed_tick,p.completed_tick)
		var expected_status: String = ("completed" if all_success else "failed") if all_terminal else "active"
		if instance.status != expected_status or instance.completed_tick != (completed_tick if all_terminal else -1): return "invalid_long_instance_status"
		if not all_terminal:
			active_count += 1
			if instance.kind == "signature":
				if active_signature != "": return "multiple_long_active_signatures"
				active_signature = instance.case_id
		if instance.kind == "signature":
			all_signatures.append(instance)
			if instance.status == "completed": completed_signatures.append(instance)
		if not _fields(event,{"id":TYPE_STRING,"source":TYPE_STRING,"phase_index":TYPE_INT,"case_id":TYPE_STRING,"instance_id":TYPE_STRING,"tick":TYPE_INT,"command_sequence":TYPE_INT,"schedule_index":TYPE_INT,"quoted_price_percent":TYPE_INT,"patient_ids":TYPE_ARRAY}): return "invalid_long_admission_event"
		if event.id != event_id or event.instance_id != id or event.case_id != instance.case_id or event.patient_ids != instance.patient_ids or event.phase_index != instance.phase_index or event.tick != instance.admitted_tick or event.source not in ["manual","auto"] or event.command_sequence < 0 or event.command_sequence > d.command_sequence or event.quoted_price_percent < 75 or event.quoted_price_percent > 150: return "invalid_long_admission_event"
		if event.source == "manual":
			if event.command_sequence < 1 or event.schedule_index != -1: return "invalid_long_manual_admission"
		else:
			if instance.kind != "routine" or event.schedule_index < 0 or event.schedule_index >= cp.intake_cursor or auto_indices.has(event.schedule_index): return "invalid_long_auto_admission"
			auto_indices[event.schedule_index] = true
		number += 1
	if patient_members.size() != d.patients.size() or auto_indices.size() != cp.intake_cursor: return "invalid_long_admission_membership"
	completed_signatures.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a.completed_tick < b.completed_tick or (a.completed_tick == b.completed_tick and a.id < b.id))
	var signatures: Array = []
	var cases: Dictionary = {}
	for instance: Dictionary in completed_signatures:
		if signatures.size() >= catalog.levels[d.level_id].case_ids.size() or instance.case_id != catalog.levels[d.level_id].case_ids[signatures.size()]: return "invalid_long_signature_completion_order"
		signatures.append(instance.case_id)
		cases[instance.case_id] = {"tick":instance.completed_tick,"patient_count":instance.patient_ids.size(),"instance_id":instance.id}
	if cp.completed_cases != signatures or d.evidence.cases != cases: return "invalid_long_signature_evidence"
	for instance: Dictionary in instances.values():
		var completed_before: Array = []
		for signature: Dictionary in completed_signatures:
			if signature.completed_tick <= instance.admitted_tick and signature.id != instance.id: completed_before.append(signature.case_id)
		var case_index: int = catalog.levels[d.level_id].case_ids.find(instance.case_id)
		var unlocked: int = int(catalog.levels[d.level_id].phases[mini(3,instance.phase_index)].signature_cases)
		if case_index < 0 or case_index >= unlocked: return "invalid_long_instance_unlock"
		if instance.kind == "signature":
			if instance.phase_index == 4 or completed_before.size() >= catalog.levels[d.level_id].case_ids.size() or instance.case_id != catalog.levels[d.level_id].case_ids[completed_before.size()]: return "invalid_long_signature_admission"
			for previous: Dictionary in all_signatures:
				if previous.id < instance.id and (previous.status == "active" or previous.completed_tick > instance.admitted_tick): return "overlapping_long_signatures"
		elif instance.case_id not in completed_before: return "unearned_long_routine_template"
	if cp.wave_active != (active_count > 0) or cp.current_case_id != active_signature: return "invalid_long_wave_state"
	return ""

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
		if not _layout_shape(record) or record.id != room_id or record.kind != "campaign_department" or record.ruleset != GEOMETRY_RULESET or not catalog.campaign.units.has(record.unit_id): return "invalid_campaign_room"
	var layout_script: Script
	if not d.rooms.is_empty():
		var path: String = "res://campaign/facility_layout.gd"
		if not ResourceLoader.exists(path): return "missing_campaign_layout_validator"
		layout_script = load(path)
	var facility_ids: Dictionary = {}
	for id: String in d.rooms:
		if not _id(id,"department",d.next_ids.room) or not d.rooms[id] is Dictionary: return "invalid_campaign_room_id"
		var room: Dictionary = d.rooms[id]
		if not _layout_shape(room) or room.id != id or room.kind != "campaign_department" or room.ruleset != GEOMETRY_RULESET or not catalog.campaign.units.has(room.unit_id) or room.status not in ["open","closed","draining"] or room.closed != (room.status == "closed"): return "invalid_campaign_room"
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
			if s.room_id != "" or (s.patient_id!="" and s.work_order_id!=""):return "invalid_campaign_unassigned_staff"
			if (s.patient_id!="" or s.work_order_id!="") and STAFF_RELIEF.active_facility(d,id)=="":return "invalid_campaign_unassigned_staff"
		elif not d.facilities.has(s.facility_id) or s.room_id != d.facilities[s.facility_id].room_id or not id in d.facilities[s.facility_id].staff_ids: return "invalid_campaign_staff_assignment"
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
			var research_factor: int = 100-LongCampaign.CLINICAL_RESEARCH_DISCOUNT_PERCENT
			var training_factor: int = 100-LongCampaign.TRAINING_DISCOUNT_PERCENT
			if h.efficiency_source.begins_with("research:efficiency+training:"):
				effective = maxi(1,int((step.duration_ticks*research_factor*training_factor+9999)/10000))
			else:
				var factor: int = research_factor if h.efficiency_source == "research:efficiency" else training_factor
				effective = maxi(1,int((step.duration_ticks*factor+99)/100))
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
		return _research_before(d,"efficiency",history.started_tick)
	elif source.begins_with("research:efficiency+training:"):
		var unit: String = catalog.campaign.facilities[history.facility_kind].unit_id
		if source != "research:efficiency+training:"+unit or not _research_before(d,"efficiency",history.started_tick): return false
		for sid: String in history.staff_ids:
			if _training_before(d,sid,unit,history.started_tick): return true
	elif source.begins_with("training:"):
		var sid: String = source.trim_prefix("training:")
		if sid not in history.staff_ids: return false
		var unit: String = catalog.campaign.facilities[history.facility_kind].unit_id
		return _training_before(d,sid,unit,history.started_tick)
	return false

static func _training_before(d: Dictionary, sid: String, unit: String, tick: int) -> bool:
	for record: Variant in d.campaign.training:
		# Clinical starts before Operations can complete training at this tick.
		if record is Dictionary and record.get("staff_id") == sid and record.get("unit_id") == unit and record.get("tick") is int and record.tick < tick: return true
	return false

static func _research_before(d: Dictionary, project: String, tick: int, operation_number: int = -1) -> bool:
	if project not in d.campaign.research: return false
	for order: Variant in d.work_orders.values():
		if not order is Dictionary or order.get("project_id","") != project or order.get("status") != "done" or not order.get("completed_tick") is int: continue
		if order.completed_tick < tick: return true
		# Operations processes numeric creation order. A research completion may
		# affect a later work order in that same tick, never an earlier one.
		if operation_number >= 0 and order.completed_tick == tick and order.get("id") is String and int(order.id.trim_prefix("work_")) < operation_number: return true
	return false


static func _orders(d: Dictionary, catalog: ContentCatalog) -> String:
	for id: String in d.work_orders:
		if not _id(id,"work",d.next_ids.work_order) or not d.work_orders[id] is Dictionary: return "invalid_campaign_work_order_id"
		var o: Dictionary = d.work_orders[id]
		if not _fields(o,{"id":TYPE_STRING,"facility_id":TYPE_STRING,"facility_kind":TYPE_STRING,"handler":TYPE_STRING,"patient_id":TYPE_STRING,"step_id":TYPE_STRING,"staff_id":TYPE_STRING,"staff_ids":TYPE_ARRAY,"status":TYPE_STRING,"work":TYPE_INT,"needed":TYPE_INT,"cost":TYPE_INT,"resource":TYPE_STRING,"quantity":TYPE_INT,"reason":TYPE_STRING,"created_tick":TYPE_INT,"started_tick":TYPE_INT,"completed_tick":TYPE_INT,"output":TYPE_DICTIONARY}): return "invalid_campaign_work_order"
		if o.id != id or not catalog.campaign.facilities.has(o.facility_kind) or not _id(o.facility_id,"facility",d.next_ids.facility) or o.status not in ["queued","walking","working","done","blocked"] or not _strings(o.staff_ids) or o.created_tick < 0 or o.created_tick > d.tick or o.needed < 1 or o.cost < 0 or o.quantity < 0: return "invalid_campaign_work_order"
		var definition: Dictionary = catalog.campaign.facilities[o.facility_kind]
		var planned: int = definition.duration_ticks
		if o.output != definition.output: return "invalid_campaign_order_output"
		if d.facilities.has(o.facility_id) and d.facilities[o.facility_id].kind != o.facility_kind: return "invalid_campaign_order_facility"
		if o.status != "done" and not d.facilities.has(o.facility_id): return "orphan_campaign_active_order"
		if o.patient_id != "":
			if not d.patients.has(o.patient_id): return "invalid_campaign_order_patient"
			var p: Dictionary = d.patients[o.patient_id]
			var step: Dictionary = {}
			for candidate: Dictionary in p.steps:
				if candidate.id == o.step_id: step = candidate; break
			if step.is_empty() or step.kind != "support" or o.facility_kind != step.facility_kind or o.cost != step.cost or o.resource != step.get("resource","") or o.quantity != step.get("quantity",0): return "invalid_campaign_support_order_step"
			planned = step.duration_ticks
		else:
			if o.has("project_id"):
				if not o.project_id is String or not catalog.campaign.projects.has(o.project_id) or o.facility_kind != "O10" or o.handler != "research": return "invalid_campaign_research_order"
				planned = catalog.campaign.projects[o.project_id].duration_ticks
			if o.has("trainee_id") or o.has("unit_id"):
				if not _fields(o,{"trainee_id":TYPE_STRING,"unit_id":TYPE_STRING}) or not _id(o.trainee_id,"staff",d.next_ids.staff) or not catalog.campaign.units.has(o.unit_id) or o.facility_kind != "O09" or o.handler != "training": return "invalid_campaign_training_order"
				planned = 240
			if o.step_id != "" or o.cost != CampaignBusiness.operation_cost(d,o,definition.consumable_cost) or o.resource != definition.get("input_resource","") or o.quantity != definition.get("input_quantity",0): return "invalid_campaign_operation_definition"
		planned = CampaignBusiness.planned_duration(d,o,planned)
		var effective: int = planned
		var declared_plan: Variant = o.get("planned_duration",planned)
		var source: Variant = o.get("efficiency_source","")
		if not declared_plan is int or declared_plan != planned or not source is String: return "invalid_long_order_growth_shape"
		if o.status in ["queued","blocked","walking"]:
			if o.has("planned_duration") or o.has("efficiency_source"): return "premature_long_order_growth"
		elif source != "":
			if o.patient_id != "" or o.handler in ["research","training"] or source != "research:logistics" or not _research_before(d,"logistics",o.started_tick,int(o.id.trim_prefix("work_"))): return "unearned_long_order_efficiency"
			var factor: int = 100-LongCampaign.LOGISTICS_DISCOUNT_PERCENT
			effective = maxi(1,int((planned*factor+99)/100))
		if o.needed != effective: return "invalid_long_order_effective_duration"
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
				if not d.staff.has(sid) or d.staff[sid].patient_id != p.id or (d.staff[sid].facility_id != f.id and not STAFF_RELIEF.owns(d,sid,f.id)) or d.staff[sid].role != step.roles[n] or d.staff[sid].work_order_id != "": return "invalid_campaign_patient_staff"
				if p.phase == "care_service":
					var goal:int=STAFF_RELIEF.work_cell(d,f.id,sid)
					if goal < 0 or d.staff[sid].cell != goal or d.staff[sid].move_progress != 0 or d.staff[sid].status != "serving": return "invalid_campaign_service_staff_position"
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
			if order.status not in ["walking","working"] or not s.id in order.staff_ids or (order.facility_id != s.facility_id and not STAFF_RELIEF.owns(d,s.id,order.facility_id)) or s.patient_id != "": return "invalid_campaign_staff_order_owner"
	for order: Dictionary in d.work_orders.values():
		if order.status not in ["walking","working"]: continue
		var f: Dictionary = d.facilities[order.facility_id]
		var roles: Array = catalog.campaign.facilities[f.kind].roles
		for n: int in range(order.staff_ids.size()):
			var sid: String = order.staff_ids[n]
			if not d.staff.has(sid) or d.staff[sid].work_order_id != order.id or (d.staff[sid].facility_id != f.id and not STAFF_RELIEF.owns(d,sid,f.id)) or d.staff[sid].role != roles[n]: return "invalid_campaign_order_staff_owner"
			if order.status == "working":
				var goal:int=STAFF_RELIEF.work_cell(d,f.id,sid)
				if goal<0 or d.staff[sid].cell!=goal or d.staff[sid].move_progress!=0:return "invalid_campaign_order_staff_position"
	for room_id: String in d.queues:
		if not d.rooms.has(room_id) or not _strings(d.queues[room_id]): return "invalid_campaign_queue"
		for pid: String in d.queues[room_id]:
			if not d.patients.has(pid) or d.patients[pid].room_id != room_id: return "invalid_campaign_queue_member"
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


static func _patients(d: Dictionary, catalog: ContentCatalog) -> String:
	var navigation: Dictionary = GridService._navigation(d.rooms)
	var live: int = 0
	var completed: int = 0
	var abandoned: int = 0
	var queue_cells:Dictionary={}
	var queue_excluded:Dictionary=FacilityLayout.queue_excluded_cells(d.rooms)
	for id: String in d.patients:
		if not _id(id,"patient",d.next_ids.patient) or not d.patients[id] is Dictionary: return "invalid_campaign_patient_id"
		var p: Dictionary = d.patients[id]
		if not _fields(p,{"id":TYPE_STRING,"disease_id":TYPE_STRING,"case_id":TYPE_STRING,"case_instance_id":TYPE_STRING,"phase":TYPE_STRING,"stage":TYPE_STRING,"room_id":TYPE_STRING,"facility_id":TYPE_STRING,"slot_id":TYPE_STRING,"staff_id":TYPE_STRING,"staff_ids":TYPE_ARRAY,"blocked_slot_id":TYPE_STRING,"support_order_id":TYPE_STRING,"arrived_tick":TYPE_INT,"tolerance":TYPE_INT,"wait_reason":TYPE_STRING,"wait_ticks":TYPE_INT,"service_started_tick":TYPE_INT,"service_work":TYPE_INT,"service_needed":TYPE_INT,"step_index":TYPE_INT,"steps":TYPE_ARRAY,"step_history":TYPE_ARRAY,"outcome":TYPE_STRING,"income":TYPE_INT,"completed_tick":TYPE_INT,"reservation_cost":TYPE_INT,"reservation_resource":TYPE_STRING,"reservation_quantity":TYPE_INT}) or not _actor(p,navigation): return "invalid_campaign_patient"
		if p.id != id or not catalog.campaign.cases.has(p.case_id) or p.phase not in PATIENT_PHASES or not _strings(p.staff_ids): return "invalid_campaign_patient"
		if p.has("queue_cell"):
			if not p.queue_cell is int or not _cell(p.queue_cell) or not GridService._walkable(navigation,p.queue_cell) or queue_excluded.has(p.queue_cell) or queue_cells.has(p.queue_cell):return "invalid_long_queue_position"
			queue_cells[p.queue_cell]=id
			if p.phase in ["care_queue","waiting_support"]:
				var personal:Dictionary=p.get("need_activity",{}) if p.get("need_activity",{}) is Dictionary else {}
				var personal_goal:bool=CampaignPeople.enabled(d) and personal.get("state","")=="walking" and p.get("goal_cell",-1)==personal.get("target_cell",-2)
				if p.get("goal_cell",-1)!=p.queue_cell and not personal_goal:return "invalid_long_queue_goal"
			elif p.phase in ["moving_care","moving_exit"]:
				var entering:bool=p.move_progress>0 and p.path_index+1<p.path.size() and p.path[p.path_index+1]==p.queue_cell
				if p.cell!=p.queue_cell and not entering:return "orphan_long_queue_position"
			else:return "unexpected_long_queue_position"
		var definition: Dictionary = catalog.campaign.cases[p.case_id]
		if p.disease_id != definition.disease_id or p.steps != (CampaignClinicalDecisions.effective_steps(d,catalog,p) if CampaignClinicalDecisions.enabled(d) else definition.steps) or p.step_index < 0 or p.step_index > p.steps.size() or p.arrived_tick < 0 or p.arrived_tick > d.tick or p.wait_ticks < 0 or p.wait_ticks > d.tick-p.arrived_tick+1 or p.tolerance != 70: return "invalid_campaign_patient_identity"
		var valid_income: bool = false
		for price: int in range(75,151):
			if p.income == CampaignExperience.clinical_income(d,int(definition.income),price): valid_income = true; break
		if not valid_income: return "invalid_campaign_patient_income"
		if not p.case_id in catalog.levels[d.level_id].case_ids: return "invalid_campaign_patient_case"
		if p.phase in ["left","abandoned"]:
			if p.cell != GridService.EXIT_CELL or p.completed_tick < p.arrived_tick or p.completed_tick > d.tick or not p.path.is_empty() or p.move_progress != 0: return "invalid_campaign_patient_departure"
			if p.phase == "left":
				if p.outcome == "referred" and CampaignClinicalDecisions.enabled(d):pass
				elif p.step_index != p.steps.size() or p.outcome != "completed": return "invalid_campaign_completed_patient"
				else:completed += 1
			else:
				if p.outcome != "abandoned": return "invalid_campaign_abandoned_patient"
				abandoned += 1
		else:
			live += 1
			if p.completed_tick != -1 or p.outcome not in (["","abandoned","referred"] if CampaignClinicalDecisions.enabled(d) else ["","abandoned"]): return "invalid_campaign_active_patient"
		if p.stage != ("exit" if p.phase in ["moving_exit","left","abandoned"] else "care"): return "invalid_campaign_patient_stage"
		if p.phase == "moving_exit" and p.step_index < p.steps.size() and p.outcome != "abandoned" and not (CampaignClinicalDecisions.enabled(d) and p.outcome=="referred"): return "invalid_campaign_early_exit"
		if p.phase in ["care_queue","moving_care","care_service","waiting_support"] and p.step_index >= p.steps.size() and not (CampaignClinicalDecisions.enabled(d) and p.phase=="care_queue" and p.get("clinical_decision") is Dictionary and p.clinical_decision.get("state","")=="pending"): return "invalid_campaign_step_cursor"
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
	if live > catalog.levels[d.level_id].max_patients or d.patients.size() != d.next_ids.patient-1: return "invalid_long_patient_count"
	if not _fields(d.metrics,{"completed":TYPE_INT,"abandoned":TYPE_INT,"income":TYPE_INT,"operating_profit":TYPE_INT,"expenses":TYPE_DICTIONARY,"patient_totals":TYPE_DICTIONARY}) or d.metrics.completed != completed or d.metrics.abandoned != abandoned: return "invalid_long_patient_metrics"
	var expected_live: Array = []
	var reputation_events: Array = []
	for patient: Dictionary in d.patients.values():
		if patient.phase not in ["left","abandoned"]: expected_live.append(patient.id)
		else:
			reputation_events.append({"tick":patient.completed_tick,"id":int(patient.id.trim_prefix("patient_")),"delta":-5 if patient.phase == "abandoned" else (1 if patient.outcome=="completed" and patient.wait_ticks <= 1200 else 0)})
	var actual_live: Array = d.campaign.live_patient_ids.duplicate()
	expected_live.sort_custom(func(a: String,b: String) -> bool: return int(a.trim_prefix("patient_")) < int(b.trim_prefix("patient_")))
	if actual_live != expected_live: return "invalid_long_live_index"
	reputation_events.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a.tick < b.tick or (a.tick == b.tick and a.id < b.id))
	var reputation: int = 50
	for event: Dictionary in reputation_events: reputation = clampi(reputation+event.delta,0,100)
	if d.campaign.reputation != reputation: return "invalid_long_reputation"
	return ""

static func _finance(d: Dictionary, catalog: ContentCatalog) -> String:
	var receipt_error: String = _receipts(d,catalog)
	if receipt_error != "": return receipt_error
	var expected: Dictionary = {}
	for p: Dictionary in d.patients.values():
		for h: Dictionary in p.step_history:
			if h.kind == "patient": expected["treatment_cost|care:"+p.id+":"+h.step_id] = {"tick":h.started_tick,"amount":-h.cost}
		if p.phase == "left" and p.outcome=="completed": expected["income|income:"+p.id] = {"tick":p.completed_tick,"amount":p.income}
	for order: Dictionary in d.work_orders.values():
		if order.started_tick < 0: continue
		var reference: String = "care:"+order.patient_id+":"+order.step_id if order.patient_id != "" else "operation:"+order.id
		var category: String = "treatment_cost" if order.patient_id != "" else "operations"
		expected[category+"|"+reference] = {"tick":order.started_tick,"amount":-order.cost}
	expected.merge(CampaignPeople.finance_expected(d),true)
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
			var matched: bool = false
			for proof: Variant in d.campaign.phase_receipts:
				if proof is Dictionary and proof.get("index") is int and entry.reference == "phase:"+d.level_id+":"+str(proof.index) and proof.get("ended_tick") == entry.tick and proof.get("reward") == entry.amount: matched = true; break
			if not matched: return "invalid_long_phase_grant"
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

static func _resources(d: Dictionary, catalog: ContentCatalog) -> String:
	var resources: Dictionary = INITIAL_RESOURCES.duplicate(true)
	var facilities: Dictionary = {}
	var diseases: Dictionary = {}
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
		if p.phase == "left" and p.outcome=="completed": diseases[p.disease_id] = diseases.get(p.disease_id,0)+1
	var operation_sequence: int = 0
	for order: Dictionary in d.work_orders.values():
		operation_sequence = int(order.id.trim_prefix("work_"))
		if order.started_tick >= 0: events.append({"tick":order.started_tick,"phase":2,"sequence":operation_sequence,"action":0,"resource":order.resource,"delta":-order.quantity,"output":{},"handler":""})
		if order.status == "done":
			events.append({"tick":order.completed_tick,"phase":2,"sequence":operation_sequence,"action":1,"resource":"","delta":0,"output":order.output,"handler":order.handler})
			facilities[order.facility_kind] = facilities.get(order.facility_kind,0)+1
			uses[order.facility_id] = uses.get(order.facility_id,0)+1
	for personal:Dictionary in CampaignPeople.resource_events(d):
		events.append({"tick":personal.tick,"phase":1,"sequence":0,"action":0,"resource":personal.resource,"delta":-int(personal.quantity),"output":{},"handler":""})
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
	var reserved_cash: int = 0
	var reserved_resources: Dictionary = {}
	for p: Dictionary in d.patients.values():
		reserved_cash += p.reservation_cost
		if p.reservation_resource != "": reserved_resources[p.reservation_resource] = reserved_resources.get(p.reservation_resource,0)+p.reservation_quantity
	if reserved_cash > d.cash: return "overbooked_campaign_cash"
	for key: String in reserved_resources:
		if reserved_resources[key] > d.resources.get(key,0): return "overbooked_campaign_stock"
	return ""

static func _receipt_rows(d: Dictionary) -> Array:
	var rows: Array = []
	for receipt: Dictionary in d.command_receipts.values(): rows.append(receipt.data)
	rows.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a.sequence < b.sequence)
	return rows

static func _terminal_totals(d: Dictionary, tick: int) -> Dictionary:
	var ended: Array = []
	var result: Dictionary = {"completed":0,"abandoned":0,"reputation":50}
	for patient: Dictionary in d.patients.values():
		if patient.phase in ["left","abandoned"] and patient.completed_tick <= tick: ended.append(patient)
	ended.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:
		return a.completed_tick < b.completed_tick or (a.completed_tick == b.completed_tick and int(a.id.trim_prefix("patient_")) < int(b.id.trim_prefix("patient_"))))
	for patient: Dictionary in ended:
		if patient.phase == "left" and patient.outcome=="completed":
			result.completed += 1
			if patient.wait_ticks <= 1200: result.reputation = mini(100,result.reputation+1)
		elif patient.phase=="abandoned":
			result.abandoned += 1
			result.reputation = maxi(0,result.reputation-5)
	return result

static func _operating_entry(entry: Dictionary) -> bool:
	return entry.category not in ["build","hire","sale","loan","repay","grant","income"]

static func _ledger_prefix(d: Dictionary, stop: int) -> Dictionary:
	var value: Dictionary = {"income":0,"expenses":0,"debt":0}
	for index: int in range(stop):
		var entry: Dictionary = d.ledger_entries[index]
		if entry.category == "income": value.income += entry.amount
		elif _operating_entry(entry): value.expenses -= entry.amount
		elif entry.category == "loan": value.debt += entry.amount
		elif entry.category == "repay": value.debt += entry.amount
	return value

static func _payroll(d: Dictionary, catalog: ContentCatalog) -> Dictionary:
	var rows: Array = _receipt_rows(d)
	var employees: Dictionary = {}
	var percentages:Dictionary={}
	var paid: Dictionary = {}
	for entry: Dictionary in d.ledger_entries:
		if entry.category == "wages": paid[entry.tick] = entry.amount
	var owed: int = 0
	var owed_by_tick: Dictionary = {}
	var row_index: int = 0
	var length: int = catalog.levels[d.level_id].day_ticks
	# _days first bounds the count by the actual persisted records. A corrupt
	# giant tick cannot turn validation into an unbounded calendar loop.
	for index: int in range(d.campaign.day_records.size()):
		var boundary: int = (index+1)*length
		while row_index < rows.size() and rows[row_index].tick < boundary:
			var row: Dictionary = rows[row_index]
			var command: Dictionary = row.command
			if command.type in ["hire","hire_staff"]: employees[row.staff_id] = command.payload.role
			elif command.type in ["dismiss","dismiss_staff"]: employees.erase(command.payload.staff_id);percentages.erase(command.payload.staff_id)
			elif command.type=="set_staff_wage" and CampaignPeople.enabled(d):percentages[command.payload.staff_id]=int(command.payload.percent)
			row_index += 1
		# Commands stamped at the boundary happen after its actual payroll.
		var due: int = owed
		for sid:String in employees:
			due += CampaignExperience.daily_wage(d,int(catalog.campaign.roles[employees[sid]].daily_wage),int(percentages.get(sid,100)))
		if paid.has(boundary):
			if paid[boundary] != -due: return {"error":"invalid_long_payroll_amount"}
			owed = 0
		else: owed = due
		owed_by_tick[boundary] = owed
	var current_owed: Variant = d.campaign.get("unpaid_wages",0)
	if not current_owed is int or current_owed < 0 or current_owed != owed: return {"error":"invalid_long_unpaid_wages"}
	return {"error":"","owed_by_tick":owed_by_tick}

static func _day_totals(d: Dictionary, end: int, owed: int) -> Dictionary:
	# Tick processing closes the day before public commands at that tick.
	# Accrued salary remains an expense until paid, without counting its later
	# cash settlement twice. Stage receipts still use _ledger_prefix cash totals.
	var totals: Dictionary = {"income":0,"expenses":owed}
	for entry: Dictionary in d.ledger_entries:
		if entry.tick > end or (entry.tick == end and entry.reference.begins_with("command:")): continue
		if entry.category == "income": totals.income += entry.amount
		elif _operating_entry(entry): totals.expenses -= entry.amount
	return totals

static func _days(d: Dictionary, catalog: ContentCatalog) -> String:
	var cp: Dictionary = d.campaign
	var length: int = catalog.levels[d.level_id].day_ticks
	if int(d.tick/length) != cp.day_records.size(): return "invalid_long_day_count"
	var payroll: Dictionary = _payroll(d,catalog)
	if payroll.error != "": return payroll.error
	var previous: Dictionary = {"tick":0,"income":0,"expenses":0,"completed":0,"abandoned":0}
	for index: int in range(cp.day_records.size()):
		var day: Variant = cp.day_records[index]
		if not day is Dictionary or not _fields(day,{"index":TYPE_INT,"start_tick":TYPE_INT,"end_tick":TYPE_INT,"income":TYPE_INT,"expenses":TYPE_INT,"profit":TYPE_INT,"completed":TYPE_INT,"abandoned":TYPE_INT}): return "invalid_long_day_shape"
		if day.index != index+1 or day.start_tick != previous.tick or day.end_tick != previous.tick+length or day.end_tick > d.tick: return "invalid_long_day_clock"
		var money: Dictionary = _day_totals(d,day.end_tick,payroll.owed_by_tick.get(day.end_tick,0))
		var terminal: Dictionary = _terminal_totals(d,day.end_tick)
		if day.income != money.income-previous.income or day.expenses != money.expenses-previous.expenses or day.profit != day.income-day.expenses or day.completed != terminal.completed-previous.completed or day.abandoned != terminal.abandoned-previous.abandoned: return "invalid_long_day_evidence"
		previous = {"tick":day.end_tick,"income":money.income,"expenses":money.expenses,"completed":terminal.completed,"abandoned":terminal.abandoned}
	if cp.day_start_tick != previous.tick or cp.day_start_income != previous.income or cp.day_start_expenses != previous.expenses or cp.day_start_completed != previous.completed or cp.day_start_abandoned != previous.abandoned or d.tick-previous.tick >= length: return "invalid_long_day_baseline"
	return ""

static func _growth_proofs(d: Dictionary, catalog: ContentCatalog) -> String:
	var projects: Array = []
	var records: Dictionary = {}
	var skills: Dictionary = {}
	for order: Dictionary in d.work_orders.values():
		if order.status != "done": continue
		if order.has("project_id"):
			if projects.has(order.project_id): return "duplicate_long_research"
			projects.append(order.project_id)
		if order.has("trainee_id"):
			records[order.id] = {"staff_id":order.trainee_id,"unit_id":order.unit_id,"order_id":order.id,"tick":order.completed_tick}
			if not skills.has(order.trainee_id): skills[order.trainee_id] = []
			if not order.unit_id in skills[order.trainee_id]: skills[order.trainee_id].append(order.unit_id)
	var actual_projects: Array = d.campaign.research.duplicate()
	projects.sort(); actual_projects.sort()
	if projects != actual_projects: return "invalid_long_research_evidence"
	var actual_records: Dictionary = {}
	for record: Variant in d.campaign.training:
		if not record is Dictionary or not _fields(record,{"staff_id":TYPE_STRING,"unit_id":TYPE_STRING,"order_id":TYPE_STRING,"tick":TYPE_INT}) or actual_records.has(record.order_id): return "invalid_long_training_evidence"
		actual_records[record.order_id] = record
	if records != actual_records: return "invalid_long_training_evidence"
	for employee: Dictionary in d.staff.values():
		var expected: Array = skills.get(employee.id,[]).duplicate()
		var actual: Array = employee.skills.duplicate()
		expected.sort(); actual.sort()
		if expected != actual: return "invalid_long_staff_skills"
	return ""

static func _layout_history(d: Dictionary, catalog: ContentCatalog) -> Dictionary:
	# Replay only successful public capital and assignment commands. Clinical
	# clocks remain authoritative in the actual patient/order histories.
	var rooms: Dictionary = {}
	var facilities: Dictionary = {}
	var workers: Dictionary = {}
	var phases: Array = []
	var next_facility: int = 1
	var intake: bool = false
	for result: Dictionary in _receipt_rows(d):
		var command: Dictionary = result.command
		var p: Dictionary = command.payload
		match command.type:
			"build_department","edit_department","place_facility":
				var room_id: String = result.get("room_id",p.get("room_id",""))
				var layout: Dictionary
				if command.type == "place_facility":
					if not rooms.has(room_id): return {"error":"invalid_long_layout_receipt"}
					layout = rooms[room_id].duplicate(true)
					layout.facilities.append({"id":"","kind":p.get("kind","")})
				else:
					if not p.get("layout") is Dictionary or not _fields(p.layout,{"width":TYPE_INT,"height":TYPE_INT,"facilities":TYPE_ARRAY}): return {"error":"invalid_long_layout_receipt"}
					layout = p.layout.duplicate(true)
				var preserved: Dictionary = {}
				if rooms.has(room_id):
					for item: Dictionary in rooms[room_id].facilities: preserved[item.id] = item
				for item: Variant in layout.facilities:
					if not item is Dictionary or not catalog.campaign.facilities.has(item.get("kind","")): return {"error":"invalid_long_layout_receipt"}
					if not preserved.has(item.get("id","")):
						item.id = "facility_%04d"%next_facility
						next_facility += 1
				var retained: Dictionary = {}
				for item: Dictionary in layout.facilities: retained[item.id] = true
				for id: String in preserved:
					if not retained.has(id):
						facilities.erase(id)
						for employee: Dictionary in workers.values():
							if employee.facility_id == id: employee.facility_id = ""
				rooms[room_id] = layout
				for item: Dictionary in layout.facilities: facilities[item.id] = {"kind":item.kind,"room_id":room_id}
			"remove_room":
				var id: String = p.get("room_id","")
				if not rooms.has(id): return {"error":"invalid_long_remove_history"}
				for item: Dictionary in rooms[id].facilities:
					facilities.erase(item.id)
					for employee: Dictionary in workers.values():
						if employee.facility_id == item.id: employee.facility_id = ""
				rooms.erase(id)
			"remove_facility":
				var id: String = p.get("facility_id","")
				if not facilities.has(id): return {"error":"invalid_long_remove_history"}
				var room_id: String = facilities[id].room_id
				for item: Dictionary in rooms[room_id].facilities.duplicate():
					if item.id == id: rooms[room_id].facilities.erase(item)
				facilities.erase(id)
				for employee: Dictionary in workers.values():
					if employee.facility_id == id: employee.facility_id = ""
			"hire","hire_staff": workers[result.staff_id] = {"role":p.role,"facility_id":""}
			"assign","assign_staff":
				if not workers.has(p.get("staff_id","")) or not facilities.has(p.get("facility_id","")): return {"error":"invalid_long_assignment_history"}
				workers[p.staff_id].facility_id = p.facility_id
			"unassign":
				if not workers.has(p.get("staff_id","")): return {"error":"invalid_long_assignment_history"}
				workers[p.staff_id].facility_id = ""
			"dismiss","dismiss_staff": workers.erase(p.get("staff_id",""))
			"set_intake": intake = p.enabled
			"advance_stage":
				var value: int = 0
				for room: Dictionary in rooms.values(): value += 150+room.width*room.height*8
				for facility: Dictionary in facilities.values(): value += catalog.campaign.facilities[facility.kind].cost
				var roles: Dictionary = {}
				var trained: int = 0
				var trained_units: Dictionary = {}
				for id: String in workers:
					if not facilities.has(workers[id].facility_id): continue
					roles[workers[id].role] = true
					var definition: Dictionary = catalog.campaign.facilities[facilities[workers[id].facility_id].kind]
					if definition.unit_id not in catalog.levels[d.level_id].unit_ids: continue
					for record: Dictionary in d.campaign.training:
						if record.staff_id == id and record.tick <= result.tick and record.unit_id == definition.unit_id:
							trained += 1
							trained_units[definition.unit_id] = true
							break
				phases.append({"value":value,"roles":roles.size(),"trained":trained,"trained_units":trained_units.size(),"intake":intake,"sequence":result.sequence,"tick":result.tick})
				if result.phase_index == 4: intake = false
	return {"error":"","phases":phases}

static func _audit_effects(id: String, tick: int, d: Dictionary, catalog: ContentCatalog) -> String:
	if id == "A01":
		var fire: bool = false
		for order: Dictionary in d.work_orders.values():
			if order.status == "done" and order.handler == "fire" and order.completed_tick <= tick: fire = true
		if not fire: return "missing_long_audit_fire"
	if id in ["A13","A16"]:
		var latest: int = 0
		for case_id: String in catalog.levels[d.level_id].case_ids:
			if not d.evidence.cases.has(case_id) or d.evidence.cases[case_id].tick > tick: return "missing_long_audit_case"
			latest = maxi(latest,d.evidence.cases[case_id].tick)
		for patient: Dictionary in d.patients.values():
			if patient.completed_tick >= 0 and patient.completed_tick <= tick: latest = maxi(latest,patient.completed_tick)
		var archived: bool = false
		for order: Dictionary in d.work_orders.values():
			if order.status == "done" and order.handler == "archive" and order.completed_tick >= latest and order.completed_tick <= tick: archived = true
		if not archived: return "missing_long_audit_archive"
	return ""

static func _events_and_audits(d: Dictionary, catalog: ContentCatalog) -> String:
	var cp: Dictionary = d.campaign
	var rows: Array = _receipt_rows(d)
	var audit_receipts: Dictionary = {}
	var resolution_receipts: Dictionary = {}
	for row: Dictionary in rows:
		if row.command.type == "resolve_event":
			var id: Variant = row.command.payload.get("event_id")
			if not id is String or id == "" or row.get("event_id") != id: return "invalid_long_event_resolution_receipt"
			# A later successful command for an already resolved event leaves
			# its original resolved_tick intact. Anchor the first success only.
			if not resolution_receipts.has(id): resolution_receipts[id] = row.tick
		if row.command.type == "request_audit":
			var id: Variant = row.command.payload.get("audit_id")
			if not id is String or not catalog.campaign.audits.has(id) or row.get("audit_id") != id: return "invalid_long_audit_receipt"
			var error: String = _audit_effects(id,row.tick,d,catalog)
			if error != "": return error
			audit_receipts[id] = row.tick
	if audit_receipts.size() != cp.audits.size() or audit_receipts != d.evidence.audits: return "invalid_long_audit_evidence"
	for id: String in cp.audits:
		var audit: Variant = cp.audits[id]
		if not audit is Dictionary or not _fields(audit,{"passed":TYPE_BOOL,"tick":TYPE_INT,"facility_evidence":TYPE_DICTIONARY}) or not audit.passed or audit.tick != audit_receipts.get(id,-1): return "invalid_long_audit"
		var expected: Dictionary = _facility_evidence_at(d,audit.tick)
		if audit.facility_evidence != expected: return "invalid_long_audit_facility_evidence"
	var previous_created: int = 0
	var previous_resolved: int = 0
	var unresolved: bool = false
	var resolved_count: int = 0
	var event_ids: Dictionary = {}
	var interval: int = CampaignBusiness.event_interval(d,catalog)
	for index: int in range(cp.events.size()):
		var event: Variant = cp.events[index]
		if not event is Dictionary or not _fields(event,{"id":TYPE_STRING,"definition_id":TYPE_STRING,"status":TYPE_STRING,"created_tick":TYPE_INT,"resolved_tick":TYPE_INT}): return "invalid_long_event"
		var definition_id: String = CampaignBusiness.event_id(d,catalog,index)
		if event.id != "event_%04d"%(index+1) or event.definition_id != definition_id or unresolved: return "invalid_long_event_sequence"
		event_ids[event.id] = true
		var definition: Dictionary = catalog.campaign.events[definition_id]
		for key: String in definition:
			if key != "id" and event.get(key) != definition[key]: return "invalid_long_event_definition"
		if event.created_tick != maxi(interval if index == 0 else previous_created+interval,previous_resolved+1) or event.created_tick > d.tick: return "invalid_long_event_clock"
		if definition_id == "breakdown":
			var power: bool = false
			for order: Dictionary in d.work_orders.values():
				if order.status == "done" and order.handler in ["power","ups"] and order.completed_tick <= event.created_tick: power = true
			if event.get("power_buffered") != power: return "invalid_long_event_power"
		if event.status == "open":
			if event.resolved_tick != -1 or d.evidence.events.has(event.id) or resolution_receipts.has(event.id): return "invalid_long_open_event"
			unresolved = true
		elif event.status == "resolved":
			if resolution_receipts.get(event.id,-1) != event.resolved_tick: return "missing_long_event_resolution_receipt"
			var oid: Variant = d.evidence.events.get(event.id)
			if not oid is String or not d.work_orders.has(oid): return "missing_long_event_order"
			var order: Dictionary = d.work_orders[oid]
			if order.status != "done" or order.handler != event.required_handler or order.started_tick < event.created_tick or event.resolved_tick < order.completed_tick or event.resolved_tick > d.tick: return "invalid_long_event_resolution"
			previous_resolved = event.resolved_tick
			resolved_count += 1
		else: return "invalid_long_event_status"
		previous_created = event.created_tick
	for id: String in resolution_receipts:
		if not event_ids.has(id): return "orphan_long_event_resolution_receipt"
	if d.evidence.events.size() != resolved_count or cp.event_serial != cp.events.size() or cp.next_event_tick != (interval if cp.events.is_empty() else previous_created+interval): return "invalid_long_event_index"
	return ""

static func _facility_evidence_at(d: Dictionary, tick: int) -> Dictionary:
	var found: Dictionary = {}
	for patient: Dictionary in d.patients.values():
		for history: Dictionary in patient.step_history:
			if history.kind == "patient" and history.completed_tick >= 0 and history.completed_tick <= tick: found[history.facility_kind] = found.get(history.facility_kind,0)+1
	for order: Dictionary in d.work_orders.values():
		if order.status == "done" and order.completed_tick <= tick: found[order.facility_kind] = found.get(order.facility_kind,0)+1
	return found

static func _quality_at(d: Dictionary, catalog: ContentCatalog, tick: int) -> Dictionary:
	var start: int = maxi(0,tick-3*int(catalog.levels[d.level_id].day_ticks))
	var completed: int = 0
	var abandoned: int = 0
	for patient: Dictionary in d.patients.values():
		if patient.completed_tick <= start or patient.completed_tick > tick: continue
		if patient.phase == "left" and patient.outcome=="completed": completed += 1
		elif patient.phase == "abandoned": abandoned += 1
	var samples: int = completed+abandoned
	return {"rate":int(completed*100/samples) if samples>0 else 0,"samples":samples}

static func _hygiene_at(d: Dictionary, tick: int) -> int:
	var last_clean: int = -1
	for order: Dictionary in d.work_orders.values():
		if order.status == "done" and order.handler in ["floor_clean","toilet_clean","filter","tool_clean"] and order.completed_tick <= tick: last_clean = maxi(last_clean,order.completed_tick)
	var decays: int = int(tick/300)
	if last_clean >= 0: decays -= int((last_clean-1)/300)
	return maxi(0,100-decays)

static func _progress(d: Dictionary, catalog: ContentCatalog) -> String:
	var error: String = _effects(d)
	if error != "": return error
	error = _growth_proofs(d,catalog)
	if error != "": return error
	error = _events_and_audits(d,catalog)
	if error != "": return error
	error = _days(d,catalog)
	if error != "": return error
	var cp: Dictionary = d.campaign
	var level: Dictionary = catalog.levels[d.level_id]
	if not cp.get("hygiene",100) is int or cp.get("hygiene",100) != _hygiene_at(d,d.tick): return "invalid_long_hygiene_history"
	var historical: Dictionary = _layout_history(d,catalog)
	if historical.error != "": return historical.error
	if historical.phases.size() != cp.phase_index or cp.phase_receipts.size() != cp.phase_index: return "invalid_long_phase_count"
	var baseline: Dictionary = {"tick":0,"completed":0,"abandoned":0,"income":0,"expenses":0,"day_index":0}
	for index: int in range(cp.phase_receipts.size()):
		var proof: Variant = cp.phase_receipts[index]
		if not proof is Dictionary or not _fields(proof,{"id":TYPE_STRING,"index":TYPE_INT,"started_tick":TYPE_INT,"ended_tick":TYPE_INT,"baseline":TYPE_DICTIONARY,"completed_delta":TYPE_INT,"abandoned_delta":TYPE_INT,"income_delta":TYPE_INT,"expenses_delta":TYPE_INT,"hospital_value":TYPE_INT,"cure_rate":TYPE_INT,"reputation":TYPE_INT,"cash":TYPE_INT,"profit_days":TYPE_INT,"signature_cases":TYPE_ARRAY,"goal_values":TYPE_DICTIONARY,"reward":TYPE_INT}): return "invalid_long_phase_shape"
		var stage: Dictionary = level.phases[index]
		var history: Dictionary = historical.phases[index]
		if proof.id != "phase_%d"%(index+1) or proof.index != index or proof.started_tick != baseline.tick or proof.baseline != baseline or proof.ended_tick != history.tick or proof.ended_tick < proof.started_tick or proof.ended_tick > d.tick or proof.reward != stage.reward: return "invalid_long_phase_identity"
		var grant_index: int = -1
		for n: int in range(d.ledger_entries.size()):
			var entry: Dictionary = d.ledger_entries[n]
			if entry.category == "grant" and entry.reference == "phase:"+d.level_id+":"+str(index): grant_index = n
		if grant_index < 0: return "missing_long_phase_grant"
		var grant: Dictionary = d.ledger_entries[grant_index]
		var money: Dictionary = _ledger_prefix(d,grant_index)
		var terminal: Dictionary = _terminal_totals(d,proof.ended_tick)
		var rate: int = int(terminal.completed*100/(terminal.completed+terminal.abandoned)) if terminal.completed+terminal.abandoned > 0 else 0
		if grant.tick != proof.ended_tick or grant.amount != stage.reward or proof.cash != grant.cash_after-grant.amount or proof.completed_delta != terminal.completed-baseline.completed or proof.abandoned_delta != terminal.abandoned-baseline.abandoned or proof.income_delta != money.income-baseline.income or proof.expenses_delta != money.expenses-baseline.expenses or proof.cure_rate != rate or proof.reputation != terminal.reputation or proof.hospital_value != history.value: return "invalid_long_phase_metrics"
		var signature: Array = []
		for case_id: String in level.case_ids:
			if d.evidence.cases.has(case_id) and d.evidence.cases[case_id].tick <= proof.ended_tick: signature.append(case_id)
		if proof.signature_cases != signature: return "invalid_long_phase_signatures"
		var days: int = 0
		var day_index: int = 0
		for day: Dictionary in cp.day_records:
			if day.end_tick <= proof.ended_tick: day_index += 1
		for n: int in range(day_index-1,-1,-1):
			var day: Dictionary = cp.day_records[n]
			if day.start_tick < proof.started_tick or day.profit < stage.min_daily_profit or day.completed < stage.min_daily_cures: break
			var day_samples: int = day.completed+day.abandoned
			if day_samples == 0 or int(day.completed*100/day_samples) < stage.cure_rate: break
			days += 1
		if proof.profit_days != days: return "invalid_long_phase_profit_days"
		var research: int = 0
		for order: Dictionary in d.work_orders.values():
			if order.has("project_id") and order.status == "done" and order.completed_tick <= proof.ended_tick: research += 1
		var quality: Dictionary = _quality_at(d,catalog,proof.ended_tick)
		var values: Dictionary = {"new_cures":proof.completed_delta,"signature_cases":signature.size(),"hospital_value":history.value,"cash":proof.cash,"reputation":terminal.reputation,"cure_rate":quality.rate,"quality_samples":quality.samples,"profitable_days":days,"research":research,"trained_staff":history.trained,"trained_units":history.trained_units,"hygiene":_hygiene_at(d,proof.ended_tick),"roles":history.roles}
		var targets: Dictionary = {}
		for key: String in values: targets[key] = stage[key]
		if index == 3:
			var evidence: Dictionary = _facility_evidence_at(d,proof.ended_tick)
			var operations: int = 0
			for kind: String in level.operation_ids:
				if evidence.get(kind,0) > 0: operations += 1
			var audits: Dictionary = {}
			for row: Dictionary in _receipt_rows(d):
				if row.sequence >= history.sequence: break
				if row.command.type == "request_audit" and row.tick >= proof.started_tick and row.command.payload.audit_id in level.audit_ids: audits[row.command.payload.audit_id] = true
			var event_count: int = 0
			var resolved: int = 0
			for event: Dictionary in cp.events:
				if event.created_tick <= proof.ended_tick:
					event_count += 1
					if event.resolved_tick >= 0 and event.resolved_tick <= proof.ended_tick: resolved += 1
			var live: int = 0
			for event: Dictionary in cp.admission_events.values():
				if event.command_sequence >= history.sequence: continue
				for pid: String in event.patient_ids:
					if d.patients[pid].completed_tick < 0 or d.patients[pid].completed_tick > proof.ended_tick: live += 1
			values.merge({"operations":operations,"audits":audits.size(),"events":resolved,"debt":1 if money.debt == 0 else 0,"empty_hospital":1 if not history.intake and live == 0 else 0})
			targets.merge({"operations":level.operation_ids.size(),"audits":level.audit_ids.size(),"events":maxi(1,event_count),"debt":1,"empty_hospital":1})
		if proof.goal_values != values: return "invalid_long_phase_goal_values"
		for key: String in values:
			if values[key] < targets[key]: return "unearned_long_phase:"+key
		baseline = {"tick":proof.ended_tick,"completed":terminal.completed,"abandoned":terminal.abandoned,"income":money.income,"expenses":money.expenses,"day_index":day_index}
	if cp.phase_baseline != baseline or cp.phase_started_tick != baseline.tick: return "invalid_long_current_phase_baseline"
	if cp.course_complete:
		if not cp.career.receipts.has(d.level_id) or cp.completed_cases != level.case_ids: return "unearned_long_course"
		# Replaying an already certified level retains its prior career receipt.
		# This hospital is proven by its own four grants and phase histories.
		if not cp.continuing and (d.challenge.status != "won" or d.challenge.reason != "long_hospital_objectives_complete" or d.challenge.ended_tick != cp.phase_receipts[3].ended_tick): return "invalid_long_course_outcome"
	elif d.challenge.status != "running": return "invalid_long_premature_outcome"
	return ""

