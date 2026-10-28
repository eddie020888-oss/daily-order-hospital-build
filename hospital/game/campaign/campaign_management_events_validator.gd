class_name CampaignManagementEventsValidator
extends RefCounted

const COMMANDS: Array = ["choose_management_event","resolve_management_event"]
const EVENT_FIELDS: Dictionary = {"id":TYPE_STRING,"definition_id":TYPE_STRING,"threshold_case_id":TYPE_STRING,"created_tick":TYPE_INT,"status":TYPE_STRING,"revision":TYPE_INT,"choice":TYPE_STRING,"chosen_tick":TYPE_INT,"chosen_sequence":TYPE_INT,"resolved_tick":TYPE_INT,"resolved_sequence":TYPE_INT,"proof":TYPE_DICTIONARY}

static func _shape(value: Variant, fields: Dictionary) -> bool:
	if not value is Dictionary or value.size() != fields.size(): return false
	for key: String in fields:
		if not value.has(key) or typeof(value[key]) != fields[key]: return false
	return true

static func _rows(d: Dictionary) -> Array:
	var result: Array = []
	for receipt: Dictionary in d.command_receipts.values(): result.append(receipt.data)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.sequence) < int(b.sequence))
	return result

static func validate(d: Dictionary, catalog: ContentCatalog) -> String:
	var cp: Dictionary = d.campaign
	var opted_in: bool = cp.get("experience_version") is int and cp.experience_version == 1
	if not opted_in:
		if cp.has("management_events_version") or cp.has("management_events"): return "unexpected_management_schema_without_experience"
		for row: Dictionary in _rows(d):
			if row.command.type in COMMANDS: return "unexpected_legacy_management_receipt"
		return ""
	if not cp.get("management_events_version") is int or cp.management_events_version != 1 or not cp.get("management_events") is Array: return "missing_management_schema"
	if cp.management_events.size() > 2: return "invalid_management_count"
	for item: Variant in cp.management_events:
		if not _shape(item, EVENT_FIELDS): return "invalid_management_event_shape"
	var expected: Array = []
	var by_id: Dictionary = {}
	for definition: Dictionary in CampaignManagementEvents.plan(d, catalog):
		if not d.evidence.cases.has(definition.threshold_case_id): continue
		var tick: int = int(d.evidence.cases[definition.threshold_case_id].tick)
		if tick < 0 or tick > int(d.tick): return "invalid_management_milestone_clock"
		var event: Dictionary = CampaignManagementEvents.initial_event(definition, tick)
		expected.append(event)
		by_id[event.id] = event
	for row: Dictionary in _rows(d):
		var type: String = row.command.type
		if type not in COMMANDS: continue
		var p: Dictionary = row.command.payload
		var fields: Dictionary = {"event_id":TYPE_STRING,"expected_revision":TYPE_INT}
		if type == "choose_management_event": fields["choice"] = TYPE_STRING
		if not _shape(p, fields) or not by_id.has(p.event_id): return "invalid_management_receipt_payload"
		var event: Dictionary = by_id[p.event_id]
		if int(row.tick) < int(event.created_tick) or int(row.tick) > int(d.tick) or int(row.sequence) <= 0 or int(row.sequence) > int(d.command_sequence): return "invalid_management_receipt_clock"
		if int(p.expected_revision) != int(event.revision) or event.status == "resolved": return "invalid_management_receipt_revision"
		if row.get("event_id") != event.id: return "invalid_management_receipt_result"
		if type == "choose_management_event":
			var allowed: bool = false
			for choice: Dictionary in CampaignManagementEvents.choices(event.definition_id):
				if p.choice == choice.id: allowed = true
			if not allowed: return "invalid_management_receipt_choice"
			event.choice = p.choice
			event.status = "accepted"
			event.revision += 1
			event.chosen_tick = int(row.tick)
			event.chosen_sequence = int(row.sequence)
		else:
			if event.status != "accepted": return "unaccepted_management_resolution"
			var evidence: Dictionary = CampaignManagementEvents.proof(d, catalog, event, int(row.tick), int(row.sequence))
			if evidence.is_empty() or row.get("proof") != evidence: return "unearned_management_resolution"
			event.status = "resolved"
			event.revision += 1
			event.resolved_tick = int(row.tick)
			event.resolved_sequence = int(row.sequence)
			event.proof = evidence
		if not row.get("revision") is int or row.revision != event.revision or row.get("choice") != event.choice: return "invalid_management_receipt_result"
	if cp.management_events != expected: return "invalid_management_event_history"
	return ""
