class_name CampaignManagementEvents
extends RefCounted

# Optional plans observe real business. They never mint rewards, authorize
# clinical care, change prices, or add a campaign graduation requirement.
const VERSION: int = 1
const PAIRS: Array = [
	["fee_compact","procurement_crunch"], ["clinical_handoff","staffing_peak"],
	["staffing_peak","fee_compact"], ["procurement_crunch","clinical_handoff"],
	["procurement_crunch","staffing_peak"], ["clinical_handoff","procurement_crunch"],
	["staffing_peak","clinical_handoff"], ["staffing_peak","procurement_crunch"],
	["fee_compact","procurement_crunch"], ["procurement_crunch","clinical_handoff"],
	["fee_compact","staffing_peak"], ["clinical_handoff","procurement_crunch"]]
const NAMES: Dictionary = {"fee_compact":"社区收费方案","procurement_crunch":"供给成本与时效","staffing_peak":"专科人员配置","clinical_handoff":"本院承接与临床转诊"}
const CHOICES: Dictionary = {
	"fee_compact":[{"id":"community","label":"社区价 90%","description":"以较低单价承接普通病例，实际收入和到诊频率使用现有收费规则。"},{"id":"premium","label":"专科价 120%","description":"提高单人收入，普通自动到诊也会按现有规则放慢。"}],
	"procurement_crunch":[{"id":"economy","label":"节省采购","description":"真实采购费用为标准的75%，原始工时的150%；完成后在临床使用产出资源。"},{"id":"express","label":"加急采购","description":"真实采购费用为标准的150%，原始工时的70%；已下单报价不会追改。"}],
	"staffing_peak":[{"id":"trained_team","label":"使用受训团队","description":"让匹配专科的已受训员工实际服务，使用已有训练工时折扣；不要求重新培训。"},{"id":"staffed_team","label":"使用已聘人员","description":"让真实付费聘用的合格员工派岗服务，承担既有聘用和工资成本；不要求额外增聘。"}],
	"clinical_handoff":[{"id":"retain","label":"本院诊疗","description":"正常完成已建立普通病例，承担诊疗耗材、人员与等待，并取得真实治愈收入。"},{"id":"transfer","label":"真实临床转诊","description":"在患者诊疗决策中转诊，经O05实际交接离院；没有本院治愈收入。"}]}

static func enabled(d: Dictionary) -> bool:
	return LongCampaign.is_long(d) and d.campaign.get("experience_version") is int and d.campaign.experience_version == 1 and d.campaign.get("management_events_version") is int and d.campaign.management_events_version == VERSION

static func initialize(d: Dictionary) -> void:
	# The factory owns experience opt-in. Calling this on a running legacy save
	# must not silently attach a new schema to it.
	if d.campaign.get("experience_version") != 1: return
	d.campaign.management_events_version = VERSION
	d.campaign.management_events = []

static func plan(d: Dictionary, catalog: ContentCatalog) -> Array:
	if not LongCampaign.is_long(d): return []
	var index: int = clampi(int(str(d.level_id).trim_prefix("long_")) - 1, 0, 11)
	var result: Array = []
	var level: Dictionary = catalog.levels[d.level_id]
	for n: int in range(2):
		var threshold: int = 2 if n == 0 else 6
		result.append({"id":"management_%02d" % (n + 1),"definition_id":PAIRS[index][n],"threshold_case_id":level.case_ids[threshold - 1],"case_id":level.case_ids[0],"unit_id":level.unit_ids[0]})
	return result

static func choices(definition_id: String) -> Array:
	return CHOICES.get(definition_id, []).duplicate(true)

static func initial_event(definition: Dictionary, tick: int) -> Dictionary:
	return {"id":definition.id,"definition_id":definition.definition_id,"threshold_case_id":definition.threshold_case_id,"created_tick":tick,"status":"open","revision":0,"choice":"","chosen_tick":-1,"chosen_sequence":0,"resolved_tick":-1,"resolved_sequence":0,"proof":{}}

static func after_tick(state: ClinicState, catalog: ContentCatalog) -> void:
	var d: Dictionary = state.data
	if not enabled(d) or d.paused or d.challenge.status != "running": return
	for definition: Dictionary in plan(d, catalog):
		if not d.evidence.cases.has(definition.threshold_case_id): continue
		var found: bool = false
		for event: Dictionary in d.campaign.management_events:
			if event.id == definition.id: found = true; break
		if not found: d.campaign.management_events.append(initial_event(definition, int(d.evidence.cases[definition.threshold_case_id].tick)))

static func _yes(data: Dictionary) -> Dictionary: return {"ok":true,"code":"ok","data":data}
static func _no(code: String) -> Dictionary: return {"ok":false,"code":code,"data":{}}

static func apply(state: ClinicState, catalog: ContentCatalog, type: String, payload: Dictionary, _reference: String) -> Dictionary:
	var d: Dictionary = state.data
	if not enabled(d): return _no("legacy_management_rules")
	if type not in ["choose_management_event","resolve_management_event"]: return _no("unknown_management_command")
	var size: int = 3 if type == "choose_management_event" else 2
	if payload.size() != size or not payload.get("event_id") is String or not payload.get("expected_revision") is int: return _no("invalid_payload")
	if type == "choose_management_event" and not payload.get("choice") is String: return _no("invalid_payload")
	for event: Dictionary in d.campaign.management_events:
		if event.id != payload.event_id: continue
		if event.revision != payload.expected_revision: return _no("stale_management_event")
		if event.status == "resolved": return _no("management_event_already_resolved")
		if type == "choose_management_event":
			var allowed: bool = false
			for choice: Dictionary in choices(event.definition_id):
				if choice.id == payload.choice: allowed = true
			if not allowed: return _no("invalid_management_choice")
			event.choice = payload.choice
			event.status = "accepted"
			event.revision += 1
			event.chosen_tick = int(d.tick)
			event.chosen_sequence = int(d.command_sequence) + 1
			return _yes({"event_id":event.id,"choice":event.choice,"revision":event.revision})
		if event.status != "accepted": return _no("management_choice_required")
		var evidence: Dictionary = proof(d, catalog, event, int(d.tick), int(d.command_sequence) + 1)
		if evidence.is_empty(): return _no("management_evidence_required")
		event.status = "resolved"
		event.revision += 1
		event.resolved_tick = int(d.tick)
		event.resolved_sequence = int(d.command_sequence) + 1
		event.proof = evidence
		return _yes({"event_id":event.id,"choice":event.choice,"revision":event.revision,"proof":evidence.duplicate(true)})
	return _no("unknown_management_event")

static func _definition(d: Dictionary, catalog: ContentCatalog, id: String) -> Dictionary:
	for definition: Dictionary in plan(d, catalog):
		if definition.id == id: return definition
	return {}

static func _patient_ids(d: Dictionary) -> Array:
	var ids: Array = d.patients.keys()
	ids.sort_custom(func(a: String, b: String) -> bool:
		if int(d.patients[a].admitted_tick) != int(d.patients[b].admitted_tick): return int(d.patients[a].admitted_tick) < int(d.patients[b].admitted_tick)
		return int(a.trim_prefix("patient_")) < int(b.trim_prefix("patient_")))
	return ids

static func _new_routine(d: Dictionary, patient: Dictionary, definition: Dictionary, event: Dictionary, at_tick: int, at_sequence: int) -> Dictionary:
	if patient.case_id != definition.case_id or not d.campaign.case_instances.has(patient.case_instance_id): return {}
	var instance: Dictionary = d.campaign.case_instances[patient.case_instance_id]
	if instance.kind != "routine": return {}
	var admission: Dictionary = d.campaign.admission_events.get(instance.admission_event_id, {})
	if admission.is_empty() or int(admission.tick) > at_tick or int(admission.command_sequence) > at_sequence: return {}
	var after: bool = (int(admission.tick) > int(event.chosen_tick) and int(admission.command_sequence) >= int(event.chosen_sequence)) or (int(admission.tick) == int(event.chosen_tick) and int(admission.command_sequence) > int(event.chosen_sequence))
	return admission if after else {}

static func _income(d: Dictionary, patient: Dictionary, at_tick: int) -> Dictionary:
	for entry: Dictionary in d.ledger_entries:
		if entry.category == "income" and entry.reference == "income:" + str(patient.id) and int(entry.tick) <= at_tick: return entry
	return {}

static func _fee(d: Dictionary, catalog: ContentCatalog, definition: Dictionary, event: Dictionary, at_tick: int, at_sequence: int) -> Dictionary:
	var percent: int = 90 if event.choice == "community" else 120
	var amount: int = CampaignExperience.clinical_income(d, int(catalog.campaign.cases[definition.case_id].income), percent)
	for id: String in _patient_ids(d):
		var patient: Dictionary = d.patients[id]
		var admission: Dictionary = _new_routine(d, patient, definition, event, at_tick, at_sequence)
		if admission.is_empty() or int(admission.quoted_price_percent) != percent: continue
		if patient.phase != "left" or patient.outcome != "completed" or int(patient.completed_tick) > at_tick: continue
		var income: Dictionary = _income(d, patient, at_tick)
		if income.is_empty() or int(income.amount) != amount or int(patient.income) != amount: continue
		return {"patient_id":id,"admission_event_id":admission.id,"price_percent":percent,"income_reference":income.reference,"income":amount,"completed_tick":int(patient.completed_tick)}
	return {}

static func supply_target(catalog: ContentCatalog, definition: Dictionary) -> Dictionary:
	for step: Dictionary in catalog.campaign.cases[definition.case_id].steps:
		if int(step.get("quantity", 0)) <= 0: continue
		var resource: String = str(step.resource)
		var kinds: Array = catalog.campaign.facilities.keys(); kinds.sort()
		for kind: String in kinds:
			var facility: Dictionary = catalog.campaign.facilities[kind]
			if facility.get("kind", "") != "patient" and int(facility.get("output", {}).get(resource, 0)) > 0: return {"facility_kind":kind,"resource":resource}
	return {}

static func _procurement(d: Dictionary, catalog: ContentCatalog, definition: Dictionary, event: Dictionary, at_tick: int, at_sequence: int) -> Dictionary:
	var target: Dictionary = supply_target(catalog, definition)
	if target.is_empty(): return {}
	var ids: Array = d.work_orders.keys()
	ids.sort_custom(func(a: String, b: String) -> bool:
		if int(d.work_orders[a].created_tick) != int(d.work_orders[b].created_tick): return int(d.work_orders[a].created_tick) < int(d.work_orders[b].created_tick)
		return int(a.trim_prefix("work_")) < int(b.trim_prefix("work_")))
	for id: String in ids:
		var order: Dictionary = d.work_orders[id]
		var quote: Dictionary = order.get("procurement_quote", {})
		if order.facility_kind != target.facility_kind or order.patient_id != "" or order.status != "done" or quote.get("policy", "") != event.choice: continue
		if int(order.created_tick) < int(event.chosen_tick) or int(order.started_tick) <= int(event.chosen_tick) or int(order.completed_tick) > at_tick: continue
		if int(quote.get("command_sequence", -1)) < int(event.chosen_sequence) or int(quote.get("command_sequence", -1)) >= at_sequence: continue
		var paid: bool = false
		for entry: Dictionary in d.ledger_entries:
			if entry.category == "operations" and entry.reference == "operation:" + id and int(entry.tick) == int(order.started_tick) and int(entry.amount) == -int(order.cost): paid = true; break
		if not paid or int(order.output.get(target.resource, 0)) <= 0: continue
		for patient_id: String in _patient_ids(d):
			var patient: Dictionary = d.patients[patient_id]
			for n: int in range(patient.step_history.size()):
				var history: Dictionary = patient.step_history[n]
				if history.resource != target.resource or int(history.quantity) <= 0 or int(history.started_tick) <= int(order.completed_tick) or int(history.completed_tick) < 0 or int(history.completed_tick) > at_tick: continue
				return {"work_order_id":id,"policy":event.choice,"cost":int(order.cost),"duration_ticks":int(quote.duration),"resource":target.resource,"patient_id":patient_id,"history_index":n,"step_id":history.step_id,"consumed_quantity":int(history.quantity)}
	return {}

static func _hire(d: Dictionary, catalog: ContentCatalog, sid: String, history: Dictionary, at_sequence: int) -> Dictionary:
	for receipt: Dictionary in d.command_receipts.values():
		var row: Dictionary = receipt.data
		# Clinical scheduling runs before commands stamped with that tick. A
		# same-tick later hire cannot retroactively staff an already started step.
		if row.command.type not in ["hire", "hire_staff"] or row.get("staff_id", "") != sid or int(row.sequence) > at_sequence or int(row.tick) >= int(history.started_tick): continue
		var role: String = str(row.command.payload.get("role", ""))
		if role not in catalog.campaign.facilities[history.facility_kind].roles: continue
		for entry: Dictionary in d.ledger_entries:
			if entry.category == "hire" and entry.reference == "command:" + str(row.command.id) and int(entry.amount) == -int(catalog.campaign.roles[role].hire_cost): return {"command_id":row.command.id,"hire_cost":-int(entry.amount)}
	return {}

static func _staffing(d: Dictionary, catalog: ContentCatalog, definition: Dictionary, event: Dictionary, at_tick: int, at_sequence: int) -> Dictionary:
	for patient_id: String in _patient_ids(d):
		var patient: Dictionary = d.patients[patient_id]
		for n: int in range(patient.step_history.size()):
			var history: Dictionary = patient.step_history[n]
			if history.kind != "patient" or int(history.started_tick) <= int(event.chosen_tick) or int(history.completed_tick) < 0 or int(history.completed_tick) > at_tick: continue
			if catalog.campaign.facilities[history.facility_kind].unit_id != definition.unit_id: continue
			for sid: String in history.staff_ids:
				if event.choice == "staffed_team":
					var hire: Dictionary = _hire(d, catalog, sid, history, at_sequence)
					if not hire.is_empty(): return {"patient_id":patient_id,"history_index":n,"step_id":history.step_id,"staff_id":sid,"unit_id":definition.unit_id,"hire_command_id":hire.command_id,"hire_cost":hire.hire_cost}
				else:
					var source: String = str(history.get("efficiency_source", ""))
					if source != "training:" + sid and source != "research:efficiency+training:" + str(definition.unit_id): continue
					for training: Dictionary in d.campaign.training:
						if training.staff_id != sid or training.unit_id != definition.unit_id or int(training.tick) >= int(history.started_tick): continue
						var order: Dictionary = d.work_orders.get(training.order_id, {})
						if order.is_empty() or order.status != "done" or order.get("trainee_id", "") != sid or order.get("unit_id", "") != definition.unit_id: continue
						return {"patient_id":patient_id,"history_index":n,"step_id":history.step_id,"staff_id":sid,"unit_id":definition.unit_id,"training_order_id":order.id,"planned_duration":int(history.planned_duration),"effective_duration":int(history.effective_duration),"efficiency_source":source}
	return {}

static func _clinical(d: Dictionary, catalog: ContentCatalog, definition: Dictionary, event: Dictionary, at_tick: int, at_sequence: int) -> Dictionary:
	for id: String in _patient_ids(d):
		var patient: Dictionary = d.patients[id]
		var admission: Dictionary = _new_routine(d, patient, definition, event, at_tick, at_sequence)
		if admission.is_empty() or patient.phase != "left" or int(patient.completed_tick) > at_tick: continue
		var income: Dictionary = _income(d, patient, at_tick)
		if event.choice == "retain":
			if patient.outcome == "completed" and not income.is_empty(): return {"patient_id":id,"admission_event_id":admission.id,"outcome":"completed","income_reference":income.reference,"income":int(income.amount)}
			continue
		if patient.outcome != "referred" or not income.is_empty(): continue
		var decision: Dictionary = patient.get("clinical_decision", {})
		var order: Dictionary = d.work_orders.get(decision.get("referral_order_id", ""), {})
		if order.is_empty() or order.status != "done" or order.patient_id != id or order.facility_kind != "O05" or int(order.completed_tick) > at_tick: continue
		for row: Dictionary in decision.get("receipts", []):
			if row.action != "refer" or int(row.tick) < int(event.chosen_tick) or int(row.tick) > at_tick or int(row.sequence) > at_sequence: continue
			for n: int in range(patient.step_history.size()):
				var history: Dictionary = patient.step_history[n]
				if history.work_order_id == order.id and int(history.completed_tick) == int(order.completed_tick): return {"patient_id":id,"admission_event_id":admission.id,"outcome":"referred","decision_id":row.id,"referral_order_id":order.id,"history_index":n,"income":0}
	return {}

static func proof(d: Dictionary, catalog: ContentCatalog, event: Dictionary, at_tick: int, at_sequence: int) -> Dictionary:
	if event.choice == "": return {}
	var definition: Dictionary = _definition(d, catalog, event.id)
	if definition.is_empty(): return {}
	match event.definition_id:
		"fee_compact": return _fee(d, catalog, definition, event, at_tick, at_sequence)
		"procurement_crunch": return _procurement(d, catalog, definition, event, at_tick, at_sequence)
		"staffing_peak": return _staffing(d, catalog, definition, event, at_tick, at_sequence)
		"clinical_handoff": return _clinical(d, catalog, definition, event, at_tick, at_sequence)
	return {}

static func _next(event: Dictionary, ready: bool) -> String:
	if event.status == "resolved": return "方案已由真实经营证据完成；可继续经营或推进原主线。"
	if ready: return "已有真实业务证据，可点击核验完成；没有额外奖励或通关门槛。"
	if event.status == "open": return "可选：先选择一种方案；不影响本院毕业，也不会自动修改经营设置。"
	match event.definition_id:
		"fee_compact": return "通过收费设置调整为%s%%；随后正常接诊目标已建立病例并完成治愈。" % ("90" if event.choice == "community" else "120")
		"procurement_crunch": return "通过采购策略选择%s，完成真实补给，并在之后的日常诊疗使用产出资源。" % ("节省" if event.choice == "economy" else "加急")
		"staffing_peak": return "让本关首个专科的%s员工实际完成诊疗；已有成果可以使用，无需重复培训或额外聘用。" % ("已受训" if event.choice == "trained_team" else "已付费聘用合格")
		"clinical_handoff": return "正常接诊目标已建立普通病例；%s。" % ("在本院完成治愈" if event.choice == "retain" else "在患者临床决策中选择转诊并完成O05交接")
	return "继续正常经营，可随时回来查看。"

static func view(d: Dictionary, catalog: ContentCatalog) -> Dictionary:
	var result: Dictionary = {"enabled":enabled(d),"optional":true,"events":[]}
	if not result.enabled: return result
	for event: Dictionary in d.campaign.management_events:
		var evidence: Dictionary = event.proof.duplicate(true) if event.status == "resolved" else proof(d, catalog, event, int(d.tick), int(d.command_sequence) + 1)
		var ready: bool = event.status == "accepted" and not evidence.is_empty()
		result.events.append({"id":event.id,"definition_id":event.definition_id,"name":NAMES[event.definition_id],"status":event.status,"revision":event.revision,"choice":event.choice,"choices":choices(event.definition_id),"progress":{"ready":ready,"current":1 if event.status == "resolved" or ready else 0,"target":1},"next_action":_next(event, ready),"proof":evidence,"optional":true,"created_tick":event.created_tick})
	return result
