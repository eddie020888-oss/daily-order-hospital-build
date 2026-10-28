class_name HospitalExperienceEvents
extends RefCounted

# Stable fact IDs, not rendered frames, own one-shot presentation cues.
const MAX_CUES := 2
const COOLDOWN_TICKS := 20
var _initialized := false
var _epoch: Variant = null
var _tick := 0
var _sequence := 0
var _fact_since := -1
var _seen: Dictionary = {}
var _last_played: Dictionary = {}

func reset(snapshot: Dictionary, epoch: Variant) -> void:
	_initialized = true
	_epoch = epoch
	_tick = int(snapshot.get("tick", 0))
	_sequence = int(snapshot.get("command_sequence", 0))
	_seen.clear()
	_last_played.clear()
	_fact_since = -1
	for fact: Dictionary in _facts(snapshot): _seen[fact.occurrence_id] = true
	_fact_since = _tick

func poll(snapshot: Dictionary, epoch: Variant, active: bool = true) -> Array:
	var tick: int = int(snapshot.get("tick", 0))
	if not _initialized or _epoch != epoch or tick < _tick:
		reset(snapshot, epoch)
		return []
	var sequence: int = int(snapshot.get("command_sequence", 0))
	if tick == _tick and sequence == _sequence: return []
	_fact_since = _tick
	_tick = tick
	_sequence = sequence
	var fresh: Array = []
	for fact: Dictionary in _facts(snapshot):
		var key: String = str(fact.occurrence_id)
		if _seen.has(key): continue
		_seen[key] = true
		if active: fresh.append(fact)
	fresh.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ap: int = 0 if str(a.kind).begins_with("event_") or str(a.kind).begins_with("management_") else 1
		var bp: int = 0 if str(b.kind).begins_with("event_") or str(b.kind).begins_with("management_") else 1
		return ap < bp if ap != bp else str(a.occurrence_id) < str(b.occurrence_id))
	var result: Array = []
	for fact: Dictionary in fresh:
		var family: String = str(fact.kind) + ":" + str(fact.category)
		if result.size() >= MAX_CUES or tick - int(_last_played.get(family, -COOLDOWN_TICKS)) < COOLDOWN_TICKS: continue
		_last_played[family] = tick
		result.append(fact)
	return result

func _fact(kind: String, category: String, id: String, tick: int, facility: String = "", definition: String = "") -> Dictionary:
	return {"kind": kind, "category": category, "occurrence_id": kind + ":" + id, "tick": tick, "facility_id": facility, "definition_id": definition}

func _facts(snapshot: Dictionary) -> Array:
	var result: Array = []
	for patient: Dictionary in snapshot.get("patients", {}).values():
		if int(patient.get("completed_tick", -1)) >= 0 and int(patient.completed_tick) < _fact_since: continue
		for entry: Dictionary in patient.get("step_history", []):
			# Support work has its own real order cue; do not double-play it here.
			if entry.get("kind", "") == "support": continue
			if int(entry.get("started_tick", -1)) < _fact_since and int(entry.get("completed_tick", -1)) < _fact_since: continue
			var id: String = str(patient.get("id", "")) + ":" + str(entry.get("step_id", "")) + ":" + str(entry.get("started_tick", -1))
			if int(entry.get("started_tick", -1)) >= 0: result.append(_fact("clinical_start", "clinical", id, int(entry.started_tick), str(entry.get("facility_id", ""))))
			if int(entry.get("completed_tick", -1)) >= 0: result.append(_fact("clinical_complete", "clinical", id, int(entry.completed_tick), str(entry.get("facility_id", ""))))
		for entry: Dictionary in patient.get("need_history", []):
			if int(entry.get("started_tick", -1)) < _fact_since and int(entry.get("completed_tick", -1)) < _fact_since: continue
			var id: String = str(patient.get("id", "")) + ":" + str(entry.get("id", ""))
			if int(entry.get("started_tick", -1)) >= 0: result.append(_fact("personal_start", "personal", id, int(entry.started_tick), str(entry.get("facility_id", ""))))
			if int(entry.get("completed_tick", -1)) >= 0: result.append(_fact("personal_complete", "personal", id, int(entry.completed_tick), str(entry.get("facility_id", ""))))
	for order: Dictionary in snapshot.get("work_orders", {}).values():
		if int(order.get("started_tick", -1)) < _fact_since and int(order.get("completed_tick", -1)) < _fact_since: continue
		var category: String = _handler_category(str(order.get("handler", "")))
		var id: String = str(order.get("id", "")) + ":" + str(order.get("started_tick", -1))
		if int(order.get("started_tick", -1)) >= 0: result.append(_fact("operation_start", category, id, int(order.started_tick), str(order.get("facility_id", ""))))
		if int(order.get("completed_tick", -1)) >= 0 and order.get("status", "") == "done": result.append(_fact("operation_complete", category, id, int(order.completed_tick), str(order.get("facility_id", ""))))
	for event: Dictionary in snapshot.get("campaign", {}).get("events", []):
		if int(event.get("created_tick", -1)) < _fact_since and int(event.get("resolved_tick", -1)) < _fact_since: continue
		var id: String = str(event.get("id", ""))
		var definition: String = str(event.get("definition_id", id))
		if int(event.get("created_tick", -1)) >= 0: result.append(_fact("event_open", "event", id, int(event.created_tick), str(event.get("target_facility_id", "")), definition))
		if event.get("status", "") == "resolved" and int(event.get("resolved_tick", -1)) >= 0: result.append(_fact("event_resolved", "event", id, int(event.resolved_tick), str(event.get("target_facility_id", "")), definition))
	for rest_id: String in snapshot.get("campaign", {}).get("staff_rest_events", {}):
		var rest: Dictionary = snapshot.campaign.staff_rest_events[rest_id]
		if int(rest.get("started_tick", -1)) < _fact_since and int(rest.get("completed_tick", -1)) < _fact_since: continue
		var id: String = rest_id + ":" + str(rest.get("staff_id", ""))
		if int(rest.get("started_tick", -1)) >= 0: result.append(_fact("staff_rest_start", "personal", id, int(rest.started_tick), str(rest.get("facility_id", ""))))
		if int(rest.get("completed_tick", -1)) >= 0: result.append(_fact("staff_rest_complete", "personal", id, int(rest.completed_tick), str(rest.get("facility_id", ""))))
	_management_facts(snapshot, result)
	return result

func _handler_category(handler: String) -> String:
	if handler in ["laboratory", "pathology", "blood", "sterilize", "clinical"]: return "support"
	return FacilityInteraction.classify({"kind": "operations", "handler": handler})

func _management_facts(snapshot: Dictionary, result: Array) -> void:
	for event: Dictionary in snapshot.get("campaign", {}).get("management_events", []):
		if int(event.get("created_tick", -1)) < _fact_since and int(event.get("chosen_tick", -1)) < _fact_since and int(event.get("resolved_tick", -1)) < _fact_since: continue
		var id: String = str(event.get("id", ""))
		var definition: String = str(event.get("definition_id", ""))
		if int(event.get("created_tick", -1)) >= 0: result.append(_fact("management_open", "event", id, int(event.created_tick), "", definition))
		if int(event.get("chosen_tick", -1)) >= 0: result.append(_fact("management_accepted", "event", id + ":" + str(event.get("chosen_sequence", 0)), int(event.chosen_tick), "", definition))
		if event.get("status", "") == "resolved" and int(event.get("resolved_tick", -1)) >= 0: result.append(_fact("management_resolved", "event", id, int(event.resolved_tick), "", definition))
