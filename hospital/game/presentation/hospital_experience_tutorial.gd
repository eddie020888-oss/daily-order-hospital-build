class_name HospitalExperienceTutorial
extends RefCounted

# The UI may navigate or dismiss this guide. Only validated model facts finish it.
const STEPS := ["clinical_policy", "clinical_decision", "personal_need", "staff_wage", "procurement", "event"]
var _visible := false
var _index := 0
var _baseline_sequence := 0
var _baseline_tick := 0
var _completed_needs: Dictionary = {}
var _completed_rests: Dictionary = {}
var _procurement_policy := ""
var _procurement_sequence := -1
var _snapshot: Dictionary = {}

func begin(snapshot: Dictionary, start_step: String = "clinical_policy") -> void:
	_snapshot = snapshot
	_visible = snapshot.get("ruleset", "") == "full-hospital-v2" and int(snapshot.get("campaign", {}).get("clinical_decisions_version", 0)) == 1
	_index = maxi(0, STEPS.find(start_step))
	_enter(snapshot)

func _enter(snapshot: Dictionary) -> void:
	_baseline_sequence = int(snapshot.get("command_sequence", 0))
	_baseline_tick = int(snapshot.get("tick", 0))
	_completed_needs.clear()
	_completed_rests.clear()
	for patient: Dictionary in snapshot.get("patients", {}).values():
		for entry: Dictionary in patient.get("need_history", []):
			if int(entry.get("completed_tick", -1)) >= 0: _completed_needs[str(patient.id) + ":" + str(entry.id)] = true
	for rest_id: String in snapshot.get("campaign", {}).get("staff_rest_events", {}):
		if int(snapshot.campaign.staff_rest_events[rest_id].get("completed_tick", -1)) >= 0: _completed_rests[rest_id] = true
	_procurement_policy = ""
	_procurement_sequence = -1

func close() -> void: _visible = false

func skip() -> void:
	_visible = false
	_index = STEPS.size()

func observe(snapshot: Dictionary, result: Dictionary = {}) -> void:
	_snapshot = snapshot
	if not _visible or _index >= STEPS.size(): return
	var receipt: Dictionary = _verified(snapshot, result)
	var kind: String = str(receipt.get("command", {}).get("type", ""))
	var payload: Dictionary = receipt.get("command", {}).get("payload", {})
	var done := false
	match STEPS[_index]:
		"clinical_policy": done = kind == "set_clinical_policy" and payload.get("policy", "") == "manual" and snapshot.get("campaign", {}).get("clinical_policy", "") == "manual"
		"clinical_decision":
			if kind == "clinical_decision":
				var patient: Dictionary = snapshot.get("patients", {}).get(payload.get("patient_id", ""), {})
				for entry: Dictionary in patient.get("clinical_decision", {}).get("receipts", []):
					if entry.get("command_id", "") == receipt.command.id and entry.get("source", "") == "manual" and entry.get("action", "") == payload.get("action", "") and int(entry.get("revision", -1)) == int(payload.get("expected_revision", -2)): done = true
		"personal_need":
			for patient: Dictionary in snapshot.get("patients", {}).values():
				for entry: Dictionary in patient.get("need_history", []):
					if int(entry.get("completed_tick", -1)) >= _baseline_tick and not _completed_needs.has(str(patient.id) + ":" + str(entry.id)): done = true
		"staff_wage":
			if int(snapshot.get("campaign", {}).get("experience_version", 0)) == 1:
				for rest_id: String in snapshot.get("campaign", {}).get("staff_rest_events", {}):
					var rest: Dictionary = snapshot.campaign.staff_rest_events[rest_id]
					if int(rest.get("completed_tick", -1)) >= _baseline_tick and not _completed_rests.has(rest_id): done = true
			if kind == "set_staff_wage":
				var employee: Dictionary = snapshot.get("staff", {}).get(payload.get("staff_id", ""), {})
				for entry: Dictionary in employee.get("wellbeing_history", []):
					if entry.get("kind", "") == "raise" and entry.get("reference", "") == "command:" + str(receipt.command.id) and int(employee.get("wage_percent", 0)) == int(payload.get("percent", -1)): done = true
		"procurement":
			if kind == "set_procurement_policy":
				_procurement_policy = str(payload.get("policy", ""))
				_procurement_sequence = int(receipt.sequence)
			if _procurement_sequence >= 0:
				for order: Dictionary in snapshot.get("work_orders", {}).values():
					var quote: Dictionary = order.get("procurement_quote", {})
					if order.get("status", "") == "done" and quote.get("policy", "") == _procurement_policy and int(quote.get("command_sequence", -1)) >= _procurement_sequence and int(order.get("created_tick", -1)) >= _baseline_tick: done = true
		"event":
			if kind == "resolve_event":
				for event: Dictionary in snapshot.get("campaign", {}).get("events", []):
					if event.get("id", "") == payload.get("event_id", "") and event.get("status", "") == "resolved" and int(event.get("resolved_tick", -1)) == int(receipt.tick):
						var order: Dictionary = snapshot.get("work_orders", {}).get(snapshot.get("evidence", {}).get("events", {}).get(event.id, ""), {})
						done = order.get("status", "") == "done" and int(order.get("started_tick", -1)) >= int(event.get("created_tick", 0))
	if done:
		_index += 1
		if _index >= STEPS.size(): _visible = false
		else: _enter(snapshot)

func _verified(snapshot: Dictionary, result: Dictionary) -> Dictionary:
	if not result.get("ok", false): return {}
	var data: Dictionary = result.get("data", {})
	var command: Dictionary = data.get("command", {})
	var id: String = str(command.get("id", ""))
	if id.is_empty() or int(data.get("sequence", 0)) <= _baseline_sequence or snapshot.get("command_receipts", {}).get(id, {}) != result: return {}
	return data

func current() -> Dictionary:
	if _index >= STEPS.size(): return {"visible": false, "id": "", "number": STEPS.size(), "total": STEPS.size()}
	var id: String = STEPS[_index]
	var copy: Array = {
		"clinical_policy": ["先试一次手动诊疗", "在病例页把诊疗策略设为手动，再应用。患者完成检查后会等待你的决定。", "应用手动策略后继续"],
		"clinical_decision": ["根据真实检查作决定", "等待真实检查完成，在患者页选择可用方案。复检会占用时间和耗材；审慎治疗与转诊有不同后果，转诊不计本院治愈。", "完成一次实际患者决定后继续"],
		"personal_need": ["让患者完成生活服务", "为有需要的排队患者安排饮水、用餐或如厕。患者要走到实际设施并完成服务，本人的需求才会恢复。", "实际服务完成后继续，安排成功尚未完成"],
		"staff_wage": ["看心情，再调整薪酬", "员工心情低会让闲置恢复更慢。可以为一位员工调整日薪；新标准从之后的工资日生效，不回改欠薪。", "成功应用一次员工加薪后继续"],
		"procurement": ["体验采购的费用与时间", "先在财务页查看已知支出后余量，再应用普通、节省或加急采购。后勤页可估算库存续航；安排新工单并让它完成，已有订单保留原报价。", "等待采用新报价的真实工单完成"],
		"event": ["完成工序，再复核事件", "出现营业事件后，先按要求完成真实工单，再在成长与审核页复核处理。尚无事件时可继续营业或稍后重开本课。", "真实事件复核成功后完成教学"]
	}[id]
	if id == "staff_wage" and int(_snapshot.get("campaign", {}).get("experience_version", 0)) == 1:
		copy = ["让员工完成真实短休", "在员工页查看岗位与短休概览，再为一位空闲员工安排饮水或便食短休。前往、使用和返岗分别显示，短休期间仍保留岗位。也可按经营需要选择加薪。", "完成一次真实短休，或自愿应用加薪后继续"]
	return {"visible": _visible, "id": id, "number": _index + 1, "total": STEPS.size(), "title": copy[0], "text": copy[1], "waiting": copy[2], "completion_scope": "真实命令与经营完成记录", "focus": _focus(id), "can_skip": true, "can_close": true}

func _focus(id: String) -> Dictionary:
	match id:
		"clinical_policy": return {"section": "cases", "control": "set_clinical_policy"}
		"clinical_decision":
			for patient_id: String in _snapshot.get("patients", {}):
				var patient: Dictionary = _snapshot.patients[patient_id]
				if patient.get("clinical_decision", {}).get("state", "") == "pending":return {"section":"patients","control":"decision_"+patient_id+"_continue_exam","patient_id":patient_id,"preparation":"查看该患者的可用方案与尚缺条件；可选择复检、审慎治疗或转诊。"}
			return {"section":"cases","control":"accept_case","preparation":"先接收签名或常规病例，并让患者完成首诊检查；出现诊疗决定后，再到患者页处理。"}
		"personal_need":return _personal_focus()
		"staff_wage":
			if int(_snapshot.get("campaign", {}).get("experience_version", 0)) == 1:
				for employee: Dictionary in _snapshot.get("staff", {}).values():
					if employee.get("patient_id", "")!="" or employee.get("work_order_id", "")!="" or employee.get("training_order_id", "")!="" or not employee.get("rest_activity",{}).is_empty() or int(employee.get("move_progress",0))!=0 or employee.get("status","")!="idle":continue
					var last:int=-CampaignStaffRest.COOLDOWN
					for event:Dictionary in _snapshot.campaign.get("staff_rest_events",{}).values():
						if event.staff_id==employee.id:last=maxi(last,maxi(int(event.completed_tick),int(event.canceled_tick)))
					if int(_snapshot.tick)-last<CampaignStaffRest.COOLDOWN:continue
					for need:String in ["water","food"]:
						var kind:String=str(CampaignPeople.NEEDS[need].facility_kind)
						if _personal_station_available(need):return {"section":"staff","control":"rest_"+str(employee.id)+"_"+need,"staff_id":employee.id,"facility_kind":kind,"preparation":"让该员工实际走到补给点并完成短休；仅发出安排还不会恢复。"}
					return {"section":"facilities","control":"","facility_kind":"O25","preparation":"先建设可达的饮水或便食设施，并备好对应库存，才能安排真实补给短休。"}
				if _snapshot.get("staff",{}).is_empty():return {"section":"staff","control":"hire","preparation":"先招聘员工，再安排实际工作或补给短休。"}
				return {"section":"staff","control":"","preparation":"员工正在工作、培训、往返短休或冷却。等交接完成后再安排；也可继续营业，让自动短休完成本课。"}
			for employee: Dictionary in _snapshot.get("staff", {}).values():
				if int(employee.get("wage_percent", 150)) < 150: return {"section": "staff", "control": "raise_" + str(employee.id), "staff_id": employee.id}
			return {"section": "staff", "control": "hire" if _snapshot.get("staff",{}).is_empty() else "", "preparation":"先招聘员工，或查看已聘人员的心情与现有薪资；也可收起本课稍后再学。"}
		"procurement": return {"section": "finance" if _procurement_sequence < 0 else "operations", "control": "set_procurement_policy" if _procurement_sequence < 0 else "run_operation", "facility_kind": "O15"}
		"event":
			for event: Dictionary in _snapshot.get("campaign", {}).get("events", []):
				if event.get("status", "") != "resolved": return {"section": "growth", "control": "resolve_" + str(event.id), "event_id": event.id}
	return {"section": "growth", "control": "", "preparation":"尚未出现待处理事件。继续正常营业，事件出现后按要求完成工序并复核；也可收起本课稍后再学。"}

func _personal_station_available(need:String)->bool:
	var rule:Dictionary=CampaignPeople.NEEDS[need]
	if int(_snapshot.get("cash",0))<int(rule.cost):return false
	if str(rule.resource)!="" and int(_snapshot.get("resources",{}).get(rule.resource,0))<int(rule.quantity):return false
	for facility:Dictionary in _snapshot.get("facilities",{}).values():
		if facility.kind==rule.facility_kind and facility.status=="open" and int(facility.condition)>0 and not CampaignPeople.facility_busy(_snapshot,str(facility.id)):return true
	return false

func _personal_focus()->Dictionary:
	var active:bool=false
	var missing:String=""
	for patient:Dictionary in _snapshot.get("patients",{}).values():
		if patient.get("phase","") in ["left","abandoned"]:continue
		active=true
		if not patient.get("need_activity",{}).is_empty():return {"section":"patients","control":"","patient_id":patient.id,"preparation":"生活服务已经安排。保持营业，让患者实际到达并使用完毕；完成后教学才会继续。"}
		if patient.phase!="care_queue" or patient.get("slot_id","")!="" or patient.get("support_order_id","")!="" or int(patient.get("move_progress",0))!=0:continue
		var last:int=-CampaignPeople.COOLDOWN
		var used:bool=false
		for event:Dictionary in patient.get("need_history",[]):
			last=maxi(last,maxi(int(event.completed_tick),int(event.canceled_tick)))
			if int(event.step_index)==int(patient.step_index):used=true
		if int(_snapshot.tick)-last<CampaignPeople.COOLDOWN or (used and not CampaignExperience.enabled(_snapshot)):continue
		var needs:Array=["water","food","toilet"]
		needs.sort_custom(func(a:String,b:String)->bool:return int(patient.get("needs",{}).get(a,0))>int(patient.get("needs",{}).get(b,0)))
		for need:String in needs:
			if int(patient.get("needs",{}).get(need,0))<20:continue
			if _personal_station_available(need):return {"section":"patients","control":"need_"+str(patient.id)+"_"+need,"patient_id":patient.id}
			if missing=="":missing=str(CampaignPeople.NEEDS[need].facility_kind)
	if not active:return {"section":"cases","control":"accept_case","preparation":"先接收患者；患者排队且确有需要时，才能安排生活服务。"}
	if missing!="":return {"section":"facilities","control":"","facility_kind":missing,"preparation":"先准备开放且可用的饮水、便食或如厕设施，并备好水和餐食；设施正在使用时可等待交接。"}
	return {"section":"patients","control":"","preparation":"目前患者正在诊疗、行走或生活服务冷却中。继续营业，等到可安排时再操作。"}
