class_name FacilityInteraction
extends RefCounted

# Presentation consumes detached facts. It never reserves a cell or moves a person.
static var _definitions: Dictionary = {}

static func classify(definition: Dictionary) -> String:
	if definition.get("kind", "") == "patient": return "clinical"
	if definition.get("kind", "") == "support": return "support"
	match str(definition.get("handler", "")):
		"spares", "stock", "delivery", "sterile_transport", "waste_transport", "sample_transport": return "logistics"
		"repair", "tool_clean", "toilet_clean", "floor_clean", "filter", "waste_sort": return "maintenance"
		"intake", "ticket", "call", "identity", "referral", "education", "accessibility", "roster", "training", "research", "archive", "privacy": return "admin"
		"temperature", "ventilation", "ups", "power", "fire": return "environment"
		"water", "food", "toilet": return "personal"
	return ""

static func context(snapshot: Dictionary, id: String, is_staff: bool, definitions: Dictionary = {}) -> Dictionary:
	var actor: Dictionary = snapshot.get("staff" if is_staff else "patients", {}).get(id, {})
	if actor.is_empty() or int(actor.get("move_progress", 0)) != 0: return {}
	if definitions.is_empty():
		if _definitions.is_empty():
			var loaded: Dictionary = ContentCatalog.load_checked("res://content")
			if loaded.get("ok", false): _definitions = loaded.catalog.campaign.facilities
		definitions = _definitions
	if is_staff:
		var rest: Dictionary = _rest(snapshot, actor, definitions)
		if not rest.is_empty(): return rest
		var order: Dictionary = snapshot.get("work_orders", {}).get(str(actor.get("work_order_id", "")), {})
		if order.get("status", "") == "working" and id in order.get("staff_ids", []):
			var facility: Dictionary = snapshot.get("facilities", {}).get(order.get("facility_id", ""), {})
			if _at_workplace(actor, facility):
				return _result(actor, facility, definitions, "work_order", str(order.id) + ":" + str(order.started_tick), _ratio(order.get("work", 0), order.get("needed", 0)))
	else:
		var activity: Dictionary = actor.get("need_activity", {})
		if activity.get("state", "") == "using":
			var history: Array = actor.get("need_history", [])
			var index: int = int(activity.get("history_index", -1))
			if index >= 0 and index < history.size():
				var entry: Dictionary = history[index]
				if entry.get("state", "") == "using" and int(entry.get("started_tick", -1)) >= 0 and int(entry.get("completed_tick", -1)) < 0 and entry.get("facility_id", "") == activity.get("facility_id", "") and int(entry.get("target_cell", -1)) == int(actor.get("cell", -2)):
					var facility: Dictionary = snapshot.get("facilities", {}).get(activity.get("facility_id", ""), {})
					var result: Dictionary = _result(actor, facility, definitions, "personal", str(entry.id), _ratio(int(snapshot.tick) - int(entry.started_tick), entry.get("needed", 0)))
					if not result.is_empty():
						result.category = "personal"
						result.label = {"water": "饮水", "food": "用餐", "toilet": "如厕"}.get(entry.get("need", ""), "生活服务")
						result.clip = "Idle" if entry.get("need", "") == "toilet" else "Examine"
					return result
	var patient: Dictionary = snapshot.get("patients", {}).get(actor.get("patient_id", ""), {}) if is_staff else actor
	if patient.get("phase", "") != "care_service" or int(patient.get("service_started_tick", -1)) < 0: return {}
	var slot: Dictionary = snapshot.get("slots", {}).get(patient.get("slot_id", ""), {})
	if slot.get("patient_id", "") != patient.get("id", "") or slot.get("phase", "") != "serving": return {}
	var facility: Dictionary = snapshot.get("facilities", {}).get(patient.get("facility_id", ""), {})
	if is_staff:
		if not id in patient.get("staff_ids", []) or not _at_workplace(actor, facility): return {}
	elif int(actor.get("cell", -1)) != int(slot.get("cell", -2)): return {}
	var steps: Array = patient.get("steps", [])
	var step_index: int = int(patient.get("step_index", -1))
	if step_index < 0 or step_index >= steps.size(): return {}
	return _result(actor, facility, definitions, "clinical", str(patient.id) + ":" + str(steps[step_index].id) + ":" + str(patient.service_started_tick), _ratio(patient.get("service_work", 0), patient.get("service_needed", 0)))

static func _at_workplace(actor: Dictionary, facility: Dictionary) -> bool:
	var employees: Array = facility.get("staff_ids", [])
	var cells: Array = facility.get("staff_cells", [])
	var index: int = employees.find(str(actor.get("id", "")))
	return index >= 0 and not cells.is_empty() and int(actor.get("cell", -1)) == int(cells[index % cells.size()]) and actor.get("facility_id", "") == facility.get("id", "")

static func _ratio(work: Variant, needed: Variant) -> float:
	var denominator: float = float(needed)
	return clampf(float(work) / denominator, 0.0, 1.0) if denominator > 0.0 else 0.0

static func _result(actor: Dictionary, facility: Dictionary, definitions: Dictionary, source: String, occurrence: String, progress: float) -> Dictionary:
	var definition: Dictionary = definitions.get(facility.get("kind", ""), {})
	var category: String = classify(definition)
	if category.is_empty() or facility.is_empty(): return {}
	var at: Vector3 = HospitalWorld.cell_position(int(actor.get("cell", 0)))
	var target := Vector3.ZERO
	var cells: Array = facility.get("equipment_cells", [])
	for cell: int in cells: target += HospitalWorld.cell_position(cell)
	if cells.is_empty(): target = at + Vector3.FORWARD
	else: target /= cells.size()
	var direction: Vector3 = target - at
	return {"active": true, "category": category, "label": str(definition.get("name", "工作中")), "facility_id": str(facility.id), "progress": progress, "occurrence_id": occurrence, "source": source, "clip": "Examine", "heading": atan2(direction.x, direction.z)}

static func _rest(snapshot: Dictionary, actor: Dictionary, definitions_value: Dictionary) -> Dictionary:
	var activity: Dictionary = actor.get("rest_activity", {})
	var event: Dictionary = snapshot.get("campaign", {}).get("staff_rest_events", {}).get(activity.get("event_id", ""), {})
	if event.get("state", "") != "using" or event.get("staff_id", "") != actor.get("id", "") or int(event.get("started_tick", -1)) < 0 or int(event.get("completed_tick", -1)) >= 0 or int(actor.get("cell", -1)) != int(event.get("target_cell", -2)): return {}
	var facility: Dictionary = snapshot.get("facilities", {}).get(event.get("facility_id", ""), {})
	var result: Dictionary = _result(actor, facility, definitions_value, "staff_rest", str(event.get("id", activity.get("event_id", ""))), _ratio(int(snapshot.get("tick", 0)) - int(event.started_tick), event.get("needed", 0)))
	if not result.is_empty():
		result.category = "personal"
		result.label = "饮水短休" if event.get("need", "") == "water" else "便食短休"
		result.clip = "Idle"
	return result
