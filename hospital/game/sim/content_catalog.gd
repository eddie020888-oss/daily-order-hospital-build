class_name ContentCatalog
extends RefCounted

var rooms: Dictionary = {}
var diseases: Dictionary = {}
var staff: Dictionary = {}
var levels: Dictionary = {}
var content_version: String = "0.1.0"
var campaign: Dictionary = {}

static func load_checked(root: String) -> Dictionary:
	var catalog := ContentCatalog.new()
	var documents := {}
	for name in ["rooms", "diseases", "staff", "level_01", "clinical_02"]:
		var path := root.path_join(name + ".json")
		if not FileAccess.file_exists(path):
			return _failure("missing_file:" + name)
		var json := JSON.new()
		if json.parse(FileAccess.get_file_as_string(path)) != OK:
			return _failure("invalid_json:" + name)
		if not json.data is Dictionary:
			return _failure("invalid_document:" + name)
		var normalized := _normalize(json.data)
		if not normalized.ok:
			return _failure(normalized.error + ":" + name)
		documents[name] = normalized.value
		if documents[name].get("version") != catalog.content_version:
			return _failure("unsupported_content_version:" + name)
	for name in ["rooms", "diseases", "staff"]:
		var document: Dictionary = documents[name]
		if not document.get("items") is Array:
			return _failure("missing_field:" + name + ".items")
		var index := {}
		for item in document.items:
			if not item is Dictionary or not item.get("id") is String or item.id.is_empty():
				return _failure("invalid_id:" + name)
			if index.has(item.id):
				return _failure("duplicate_id:" + name)
			index[item.id] = item
		catalog.set(name, index)
	for name in ["level_01", "clinical_02"]:
		var error := catalog._validate(documents[name])
		if not error.is_empty():
			return _failure(error)
		if documents[name].id != name:
			return _failure("invalid_level_id:"+name)
		catalog.levels[name] = documents[name]
	var campaign_error:=CampaignContent.load_into(catalog,root)
	if campaign_error!="": return _failure(campaign_error)
	return {"ok": true, "catalog": catalog, "error": ""}

static func _failure(error: String) -> Dictionary:
	return {"ok": false, "catalog": null, "error": error}

static func _normalize(value: Variant) -> Dictionary:
	# Godot JSON numbers are floats: reject fractions before converting, never truncate money.
	if value is float:
		if not is_finite(value) or value != floor(value) or abs(value) > 9007199254740991:
			return {"ok": false, "error": "invalid_integer"}
		return {"ok": true, "value": int(value)}
	if value is Array or value is Dictionary:
		var result: Variant = [] if value is Array else {}
		for key in range(value.size()) if value is Array else value.keys():
			var child := _normalize(value[key])
			if not child.ok:
				return child
			if value is Array:
				result.append(child.value)
			else:
				result[key] = child.value
		return {"ok": true, "value": result}
	return {"ok": true, "value": value}

func _validate(level: Dictionary) -> String:
	for definition in [[rooms, ["reception", "diagnosis", "echo", "motion", "sensory", "recovery", "general_exam", "pharmacy", "ward"]], [staff, ["receptionist", "doctor", "technician", "nurse"]], [diseases, ["echo", "motion", "sensory", "rhythm_hiccup", "pillow_dependency", "warmwind_sneeze"]]]:
		if definition[0].size() != definition[1].size():
			return "invalid_content_ids"
		for id in definition[1]:
			if not definition[0].has(id):
				return "unknown_content_id:" + id
	for room in rooms.values():
		var error := _fields(room, {"name": TYPE_STRING, "width": TYPE_INT, "height": TYPE_INT, "cost": TYPE_INT, "staff_role": TYPE_STRING, "service_ticks": TYPE_INT, "capacity": TYPE_INT})
		if not error.is_empty():
			return error
		if room.width < 1 or room.height < 1 or room.capacity < 1:
			return "invalid_room_dimensions"
		if room.staff_role != "" and not staff.has(room.staff_role):
			return "unknown_staff_role:" + room.staff_role
		if room.id != "recovery" and room.staff_role == "":
			return "unknown_staff_role:empty"
		if room.id in ["general_exam","pharmacy","ward"]:
			error = _fields(room,{"consumable_cost":TYPE_INT})
			if error != "": return error
			if room.service_ticks < 1: return "invalid_duration"
			if room.capacity != (2 if room.id == "ward" else 1): return "invalid_clinical_capacity"
			if room.staff_role != ("doctor" if room.id == "general_exam" else "nurse"): return "invalid_clinical_role"
	var recovery_error := _fields(rooms.recovery, {"upgrade_cost": TYPE_INT, "upgraded_capacity": TYPE_INT, "consumable_cost": TYPE_INT})
	if not recovery_error.is_empty():
		return recovery_error
	for role in staff.values():
		var error := _fields(role, {"name": TYPE_STRING, "hire_cost": TYPE_INT, "daily_wage": TYPE_INT})
		if not error.is_empty():
			return error
	for disease in diseases.values():
		var error := _fields(disease, {"name": TYPE_STRING, "room_kind": TYPE_STRING, "income": TYPE_INT, "modes": TYPE_DICTIONARY})
		if not error.is_empty():
			return error
		if not rooms.has(disease.room_kind):
			return "unknown_room_kind:" + disease.room_kind
		if disease.has("care_steps"):
			var expected: Array = {"rhythm_hiccup":["pharmacy"],"pillow_dependency":["general_exam","ward"],"warmwind_sneeze":["general_exam","pharmacy","ward"]}.get(disease.id,[])
			if expected.is_empty() or not disease.care_steps is Array or disease.care_steps != expected or disease.room_kind != expected[0] or not disease.modes.is_empty():
				return "invalid_care_steps"
			continue
		if disease.id not in ["echo","motion","sensory"]: return "missing_field:care_steps"
		for mode in ["fast", "gentle"]:
			if not disease.modes.get(mode) is Dictionary:
				return "missing_field:modes." + mode
			error = _fields(disease.modes[mode], {"duration_ticks": TYPE_INT, "cost": TYPE_INT, "stimulus": TYPE_INT})
			if not error.is_empty():
				return error
			if disease.modes[mode].duration_ticks < 1:
				return "invalid_duration"
	var level_error := _fields(level, {"id": TYPE_STRING, "initial_cash": TYPE_INT, "fixed_daily_cost": TYPE_INT, "day_ticks": TYPE_INT, "end_tick": TYPE_INT, "patience_ticks": TYPE_INT, "negative_cash_limit_ticks": TYPE_INT, "max_staff": TYPE_INT, "max_patients": TYPE_INT, "initial_unlocked_room_kinds": TYPE_ARRAY, "unlocks": TYPE_ARRAY, "arrivals": TYPE_ARRAY})
	if not level_error.is_empty():
		return level_error
	if level.id not in ["level_01","clinical_02"] or level.day_ticks < 1 or level.end_tick < 1 or level.patience_ticks < 1 or level.negative_cash_limit_ticks < 1 or level.max_staff < 1 or level.max_patients < 1:
		return "invalid_level"
	if level.has("goal"):
		if not level.goal is Dictionary or _fields(level.goal,{"completed_min":TYPE_INT,"cash_min":TYPE_INT,"require_all_departed":TYPE_BOOL}) != "": return "invalid_goal"
		for key in level.goal:
			if key not in ["completed_min","cash_min","require_all_departed","abandoned_max","operating_profit_min"]: return "invalid_goal"
			if key in ["abandoned_max","operating_profit_min"] and (not level.goal[key] is int or level.goal[key] < 0): return "invalid_goal"
		if level.goal.completed_min > level.arrivals.size(): return "invalid_goal"
	for kind in level.initial_unlocked_room_kinds:
		if not kind is String or not rooms.has(kind):
			return "unknown_room_kind"
	for unlock in level.unlocks:
		if not unlock is Dictionary:
			return "invalid_unlock"
		var error := _fields(unlock, {"tick": TYPE_INT, "room_kind": TYPE_STRING})
		if not error.is_empty():
			return error
		if not rooms.has(unlock.room_kind):
			return "unknown_room_kind"
	var patient_ids := {}
	var previous_tick := -1
	for arrival in level.arrivals:
		if not arrival is Dictionary:
			return "invalid_arrival"
		var error := _fields(arrival, {"id": TYPE_STRING, "tick": TYPE_INT, "disease_id": TYPE_STRING, "tolerance": TYPE_INT})
		if not error.is_empty():
			return error
		if arrival.id.is_empty() or patient_ids.has(arrival.id):
			return "duplicate_patient_id"
		if not diseases.has(arrival.disease_id):
			return "unknown_disease_id"
		if arrival.tolerance not in [30, 70] or arrival.tick < previous_tick or arrival.tick > level.end_tick:
			return "invalid_arrival"
		patient_ids[arrival.id] = true
		previous_tick = arrival.tick
	return ""

static func _fields(item: Dictionary, required: Dictionary) -> String:
	for field in required:
		if not item.has(field):
			return "missing_field:" + field
		if typeof(item[field]) != required[field]:
			return "invalid_field_type:" + field
		if item[field] is int and item[field] < 0:
			return "invalid_integer:" + field
	return ""
