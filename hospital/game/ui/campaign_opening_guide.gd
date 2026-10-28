class_name CampaignOpeningGuide
extends RefCounted

# Presentation-only: no tutorial receipts, model writes, inventory grants or
# second simulation. The clinical opening policy owns readiness and admission.
const OpeningLoop = preload("res://campaign/campaign_opening_loop.gd")
const RestInsights = preload("res://ui/hospital_operating_insights.gd")
const REST_WARNING_FATIGUE:int=48

static func current(snapshot:Dictionary,catalog:ContentCatalog) -> Dictionary:
	var opening:Dictionary=OpeningLoop.preview(snapshot,catalog)
	if not opening.get("enabled",false) or snapshot.get("challenge",{}).get("status","")!="running":return {"visible":false}
	var stage:Dictionary=LongCampaign.goals(snapshot,catalog)
	if stage.get("course_complete",false):return {"visible":false}
	var need:Dictionary=opening.get("next_requirement",{})
	var code:String=str(need.get("code",""))
	var kind:String=str(need.get("facility_kind",""))
	var role:String=str(need.get("role",""))
	var resource:String=str(need.get("resource",""))
	var name:String=str(catalog.campaign.facilities.get(kind,{}).get("name",kind))
	var role_name:String=str(catalog.campaign.roles.get(role,{}).get("name",role))
	var focus:Dictionary={"facility_kind":kind,"role":role,"resource":resource}
	# A real clinical decision outranks preparation. Fatigue guidance prepares
	# existing paid supply breaks; it never changes fatigue or schedules rest.
	if code=="clinical_pending":return _clinical_card(snapshot,catalog,stage,opening)
	if code not in ["build","hire","assign"]:
		var rest:Dictionary=_staff_rest_card(snapshot,catalog,stage)
		if not rest.is_empty():return rest
	if code in ["supply_operation","supply_in_progress"]:
		var input_card:Dictionary=_supply_input_card(snapshot,catalog,stage)
		if not input_card.is_empty():return input_card
	match code:
		"build":
			focus.action="build"
			var title:String="先建"+name if kind==str(opening.intake_kind) else "准备"+name
			return _card(snapshot,stage,"build:"+kind,title,"在医院空地划定房间、放门，再摆好这项设备；确认前只是预览，未完成不会扣款。","建设"+name,focus)
		"hire","assign":
			focus.action="staff"
			focus.control="hire" if code=="hire" else "assign"
			focus.facility_id=_facility_id(snapshot,kind)
			if code=="assign":focus.staff_id=_unassigned_staff(snapshot,role)
			return _card(snapshot,stage,code+":"+kind+":"+role,"为"+name+"安排"+role_name,"设备已建成。"+("先招聘对应岗位，再把员工派到这台设备，才能实际提供服务。" if code=="hire" else "已有对应员工尚未派到岗位；选择员工和这台设备后确认派岗。"),"招聘"+role_name if code=="hire" else "安排岗位",focus)
		"supply_operation":
			focus.action="operation"
			focus.control="run_operation"
			return _card(snapshot,stage,"supply:order","安排一次真实配送","供给设施和人员已准备好，但首诊所需物资尚未送达。安排配送后还要营业等待工单实际完成。","安排配送",focus)
		"supply_in_progress":
			if bool(snapshot.get("paused",true)):
				return _card(snapshot,stage,"supply:resume","让配送继续进行","配送工单已在进行，不必重复建设或下单。当前医院暂停，继续营业后人员才能运输并完成。","继续营业",{"action":"resume"})
			focus.action="operation"
			return _card(snapshot,stage,"supply:working","等待物资实际送达","配送工单已在进行；等待人员完成运输，库存才会增加。可以查看工单与当前等待原因。","查看配送进度",focus)
		"open_intake":
			return _card(snapshot,stage,"intake:open","开启这座医院的接诊","接待、首诊、供给与可用后续出口已经准备好。开启后最多接收%d位开业患者；暂停时不会推进。"%int(opening.get("live_limit",2)),"开启接诊",{"action":"open_intake","control":"set_intake"})
		"clinical_pending":
			return _clinical_card(snapshot,catalog,stage,opening)
		"waiting_treatment":
			var reason:String=str(need.get("reason",""))
			if reason=="insufficient_case_budget" or reason.begins_with("missing_cash") or reason.begins_with("insufficient_cash"):
				return _card(snapshot,stage,"cash:readiness","先补足接诊预算","当前现金尚不足以支付实际检查与后续出口。先查看支出、收费与贷款，再决定如何补足，不会自动借款或接收患者。","查看医院财务",{"action":"goals","section":"finance","control":"take_loan"})
			if reason=="facility_unavailable":
				var id:String=_facility_id(snapshot,kind)
				return _card(snapshot,stage,"capacity:"+kind,"检查"+name+"的可用状态","这项已建设施当前不可用。先查看关停、设备完好度和人员到岗；不需要重复建同一项。","查看设备状态",{"action":"goals","section":"rooms","facility_id":id,"control":"close_"+id})
			if bool(snapshot.get("paused",true)):
				return _card(snapshot,stage,"patients:resume","继续医院实际运转","当前诊疗或后勤仍待推进。医院暂停，诊疗、转诊与离院都不会推进；继续后可查看具体等待原因。","继续营业",{"action":"resume"})
			return _card(snapshot,stage,"patients:waiting","先处理在院患者","当前开业客流%d / %d人。查看正在等待的检查、治疗或转诊；完成实际离院后才释放接诊名额。"%[int(opening.get("live_count",0)),int(opening.get("live_limit",2))],"查看在院患者",{"action":"patients","reason":str(need.get("reason",""))})
	# A working referral route permits admission before optional therapy. Once
	# that device is built, do not mistake its vacant role for completed setup.
	if not bool(opening.get("treatment_ready",false)):
		var therapy_state:=ClinicState.new();therapy_state.data=snapshot
		var therapy_steps:Array=catalog.campaign.cases[str(opening.template_case_id)].steps.slice(2)
		var therapy_reasons:Array=CampaignClinicalFlow._case_preparation_reasons(therapy_state,catalog,str(opening.template_case_id),false,therapy_steps)
		if _only_staff_missing(therapy_reasons):
			var therapy_focus:Dictionary=_staffing_focus(snapshot,catalog,str(opening.treatment_kind))
			if not therapy_focus.is_empty():
				var therapy_role_name:String=str(catalog.campaign.roles[therapy_focus.role].name)
				return _card(snapshot,stage,"staff:"+str(therapy_focus.facility_id),"配齐本院治疗岗位","设备已经建成，仍缺"+therapy_role_name+"。查看已有员工和招聘费用，确认后才会招聘或派岗；诊疗方案仍由你决定。","安排诊疗岗位",therapy_focus)
	if bool(snapshot.get("paused",true)):
		return _card(snapshot,stage,"hospital:resume","继续医院的真实运转","当前准备已完成。继续营业后接待、首诊、配送和患者离院才会推进；暂停期间不会消耗经营时间。","继续营业",{"action":"resume"})
	if not bool(opening.get("treatment_ready",false)) and _facility_id(snapshot,str(opening.treatment_kind))=="":
		var therapy:String=str(opening.treatment_kind)
		var therapy_name:String=str(catalog.campaign.facilities.get(therapy,{}).get("name",therapy))
		return _card(snapshot,stage,"expand:"+therapy,"补齐本院后续治疗","首诊已可运行，当前可通过真实转诊出口处理。增建"+therapy_name+"并配齐岗位与供给，才能在本院完成相应治疗。","建设"+therapy_name,{"action":"build","facility_kind":therapy})
	if bool(stage.get("can_advance",false)):
		return _card(snapshot,stage,"stage:ready","本阶段目标已满足","实际经营指标已达到本阶段要求。你可以查看目标并手动提交考核，仍在同一座医院继续发展。","查看阶段考核",{"action":"goals","control":"advance_stage"})
	for goal:Dictionary in stage.get("goals",[]):
		if not bool(goal.get("passed",false)):
			return _card(snapshot,stage,"stage:"+str(goal.get("id","")),"当前阶段 · "+str(goal.get("label","")),"实际进度 %d / %d。查看当前目标及尚缺条件；增加科室、接诊或改善经营都保留在这座医院中。"%[int(goal.get("current",0)),int(goal.get("target",0))],"查看阶段目标",{"action":"goals","control":"prepare_case" if goal.get("id","")=="signature_cases" else ""})
	return {"visible":false}

static func _supply_input_card(d:Dictionary,catalog:ContentCatalog,stage:Dictionary)->Dictionary:
	var existing:bool=false
	for order:Dictionary in d.work_orders.values():
		if str(order.facility_kind)!=str(OpeningLoop.SUPPLY_KIND) or order.status in ["done","failed","cancelled"]:continue
		existing=true
		# Working has already paid and consumed its input. Walking/queued
		# records alone cannot promise output when input or funds are missing.
		if order.status=="working":continue
		if not CampaignClinicalFlow._stock_ready(d,order):return _supply_resource_card(d,catalog,stage,str(order.resource),int(order.quantity))
		if CampaignClinicalFlow._available_cash(d)<int(order.cost):return _card(d,stage,"supply:cash","准备配送费用","已有配送单尚未开工，可用资金不足；查看财务，不会重复下单或自动借款。","查看财务",{"action":"goals","section":"finance"})
	if existing:return {}
	var estimate:Dictionary=RestInsights.operation(d,catalog,str(OpeningLoop.SUPPLY_KIND))
	if int(estimate.get("missing_input",0))>0:return _supply_resource_card(d,catalog,stage,str(estimate.input_resource),int(estimate.input_quantity))
	if int(estimate.get("cash_after",0))<0:return _card(d,stage,"supply:cash","准备配送费用","安排真实配送仍需可用资金，先查看财务。","查看财务",{"action":"goals","section":"finance"})
	return {}

static func _supply_resource_card(d:Dictionary,catalog:ContentCatalog,stage:Dictionary,resource:String,required:int)->Dictionary:
	# Same authored output-source relationship as the resource help page.
	var held:Dictionary=RestInsights._reservations(d).resources
	var available:int=maxi(0,int(d.resources.get(resource,0))-int(held.get(resource,0)))
	var prefix:String="配送需%s%d份，当前可用%d份，还缺%d份。"%[str(CampaignHospitalPanel.RESOURCE_NAMES.get(resource,resource)),required,available,maxi(0,required-available)]
	for definition:Dictionary in catalog.campaign.facilities.values():
		if definition.get("kind","patient")=="patient" or int(definition.get("output",{}).get(resource,0))<=0:continue
		return _rest_operation_card(d,catalog,stage,str(definition.id),resource,prefix)
	return _card(d,stage,"supply:source","准备配送上游物资",prefix+"先查看实际物资来源，不能空等配送产生库存。","查看物资来源",{"action":"goals","section":"resource","resource":resource})

static func _staff_rest_card(d:Dictionary,catalog:ContentCatalog,stage:Dictionary)->Dictionary:
	if not CampaignPeople.autonomy_enabled(d):return {}
	var tired:Array=[]
	for s:Dictionary in d.staff.values():
		var home:Dictionary=d.facilities.get(s.get("facility_id",""),{})
		if home.is_empty() or s.id not in home.staff_ids or int(s.get("fatigue",0))<REST_WARNING_FATIGUE or CampaignStaffRest.busy(s):continue
		tired.append(s)
	if tired.is_empty():return {}
	tired.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return int(a.fatigue)>int(b.fatigue) if a.fatigue!=b.fatigue else str(a.id)<str(b.id))
	var worker:Dictionary=tired[0]
	var worker_name:String=str(worker.get("display_name","")).strip_edges()
	if worker_name=="":worker_name=str(catalog.campaign.roles.get(str(worker.get("role","")),{}).get("name","员工"))
	var prefix:String="%s疲劳%d。"%[worker_name,int(worker.fatigue)]
	var existing:Array=[]
	var empty:Dictionary={}
	var blocked:Dictionary={}
	var state:=ClinicState.new();state.data=d
	var ids:Array=d.facilities.keys();ids.sort()
	for need:String in CampaignStaffRest.RULES:
		var rule:Dictionary=CampaignStaffRest.RULES[need]
		for id:String in ids:
			var f:Dictionary=d.facilities[id]
			if f.kind!=rule.facility_kind:continue
			existing.append(f)
			if f.status!="open" or int(f.condition)<=0 or f.service_cells.is_empty():continue
			if not CampaignClinicalFlow._stock_ready(d,rule):
				if empty.is_empty():empty={"kind":str(f.kind),"resource":str(rule.resource)}
				continue
			if CampaignClinicalFlow._available_cash(d)<int(rule.cost):
				return _card(d,stage,"staff-rest:cash","准备员工短休费用",prefix+"补给短休仍需真实费用和物资；先查看财务，不会自动借款。","查看财务",{"action":"goals","section":"finance"})
			# Existing self-service stock needs no production employee. A shared
			# supply point already in use is temporary occupancy, not a new build.
			if CampaignPeople.facility_busy(d,id):return {}
			var target:int=int(f.service_cells[0])
			if not GridService.path_avoiding(state,int(worker.cell),target,CampaignClinicalFlow._work_positions(d,worker,target)).is_empty():
				if not bool(d.campaign.get("auto_staff_rest",false)):
					return _card(d,stage,"staff-rest:manual","查看员工补给短休",prefix+"已有可用补给点。当前自动短休关闭，可在员工页安排真实短休；仍须付费、使用并返岗。","查看员工",{"action":"goals","section":"staff","staff_id":str(worker.id),"control":"rest_"+str(worker.id)+"_"+need})
				return {}
			blocked=f
	if not empty.is_empty():return _rest_operation_card(d,catalog,stage,str(empty.kind),str(empty.resource),prefix)
	if not blocked.is_empty():
		return _card(d,stage,"staff-rest:path","检查补给点通道",prefix+"已有补给设施，但当前路径不可达；检查房门和通道，不必重复建设。","查看科室",{"action":"goals","section":"rooms","facility_id":str(blocked.id),"control":"edit_"+str(blocked.room_id)})
	for f:Dictionary in existing:
		if f.status!="open":return _card(d,stage,"staff-rest:closed","重新开放补给设施",prefix+"现有补给点已关停，先查看并重新开放。","查看设备状态",{"action":"goals","section":"rooms","facility_id":str(f.id),"control":"close_"+str(f.id)})
		if int(f.condition)<=0:return _rest_operation_card(d,catalog,stage,"O11","",prefix+"补给设备已损坏，先准备真实维修。")
	return _card(d,stage,"staff-rest:build","准备员工饮水短休",prefix+"先建饮水补给机。员工达到短休条件后会实际前往、支付费用和用水，再返回原岗位；不会空等恢复。","建设饮水补给机",{"action":"build","facility_kind":"O25","staff_id":str(worker.id)})

static func _rest_operation_card(d:Dictionary,catalog:ContentCatalog,stage:Dictionary,kind:String,resource:String,prefix:String)->Dictionary:
	var name:String=str(catalog.campaign.facilities[kind].name)
	for order:Dictionary in d.work_orders.values():
		if order.status in ["done","failed","cancelled"]:continue
		if (resource!="" and int(order.get("output",{}).get(resource,0))>0) or (resource=="" and str(order.facility_kind)==kind):
			if order.status!="working":
				if not CampaignClinicalFlow._stock_ready(d,order):return _supply_resource_card(d,catalog,stage,str(order.resource),int(order.quantity))
				if CampaignClinicalFlow._available_cash(d)<int(order.cost):return _card(d,stage,"staff-rest:order-cash","准备工单实际费用",prefix+"已有工单尚未开工，可用资金不足；先查看财务，不会重复下单或自动借款。","查看财务",{"action":"goals","section":"finance"})
			if d.paused:return _card(d,stage,"staff-rest:resume","让补给准备继续",prefix+"已有真实工单在进行；继续营业等待完成，不必重复下单。","继续营业",{"action":"resume"})
			return _card(d,stage,"staff-rest:working","等待补给准备完成",prefix+"已有真实工单在进行；查看进度，完成后才会增加库存或修复设备。","查看工单",{"action":"operation","facility_kind":kind,"resource":resource})
	var need:Dictionary=OpeningLoop._facility_requirement(d,catalog,kind)
	# The existing operation rules allow a staffed, open repair workshop to
	# perform paid field repair even when that workshop itself is damaged.
	var repair_workshop:String=""
	if kind=="O11":
		var operation_reasons:Array=CampaignOperations.readiness(d,catalog,kind)
		if operation_reasons.is_empty():need={"code":""}
		elif operation_reasons.has("missing_staff:"+kind):
			var ids:Array=d.facilities.keys();ids.sort()
			for id:String in ids:
				if d.facilities[id].kind==kind and CampaignOperations._long_operable(d.facilities[id],catalog):repair_workshop=id;break
			if repair_workshop!="":
				var role:String=str(catalog.campaign.facilities[kind].roles[0])
				need={"code":"assign" if _unassigned_staff(d,role)!="" else "hire","role":role}
	var focus:Dictionary={"facility_kind":kind,"resource":resource}
	match str(need.code):
		"build":
			focus.action="build"
			return _card(d,stage,"staff-rest:source-build","准备"+name,prefix+"这项真实补给来源尚未建设。","建设"+name,focus)
		"hire","assign":
			focus.action="staff";focus.role=str(need.role);focus.control=str(need.code);focus.facility_id=_facility_id(d,kind)
			if repair_workshop!="":focus.facility_id=repair_workshop
			if need.code=="assign":focus.staff_id=_unassigned_staff(d,str(need.role))
			return _card(d,stage,"staff-rest:source-staff","配齐补给生产岗位",prefix+"补给库存不足；生产新物资需要"+str(catalog.campaign.roles[need.role].name)+"到岗，有库存的自助短休本身不需要另配人。","安排补给岗位",focus)
		"waiting_treatment":
			focus.action="goals";focus.section="rooms";focus.facility_id=_facility_id(d,kind);focus.control="close_"+str(focus.facility_id)
			return _card(d,stage,"staff-rest:source-closed","检查补给来源状态",prefix+"已有来源当前不可用，先查看开放和完好状态，不重复建设。","查看设备状态",focus)
	var estimate:Dictionary=RestInsights.operation(d,catalog,kind)
	if int(estimate.get("missing_input",0))>0:
		focus.action="goals";focus.section="resource";focus.resource=str(estimate.get("input_resource",""))
		return _card(d,stage,"staff-rest:input","准备补给生产原料",prefix+"当前生产仍缺真实原料，先查看来源。","查看物资来源",focus)
	if int(estimate.get("cash_after",0))<0:
		return _card(d,stage,"staff-rest:production-cash","准备补给生产费用",prefix+"安排生产仍需真实费用，先查看财务。","查看财务",{"action":"goals","section":"finance"})
	focus.action="operation";focus.control="run_operation"
	return _card(d,stage,"staff-rest:produce","安排真实补给工单",prefix+"设备和岗位已准备好；安排工单后，实际生产完成才增加库存或恢复完好度。","安排"+name,focus)

static func _clinical_card(snapshot:Dictionary,catalog:ContentCatalog,stage:Dictionary,opening:Dictionary) -> Dictionary:
	var pending:Array=opening.get("clinical_pending_patient_ids",[]).duplicate()
	pending.sort()
	if pending.is_empty():return {"visible":false}
	var patient_id:String=str(pending[0])
	var decision:Dictionary=CampaignClinicalDecisions.preview(snapshot,catalog,patient_id)
	var treatment_missing:Array=decision.get("terms",{}).get("cautious_treat",{}).get("missing",[])
	if decision.get("pending",false) and _only_staff_missing(treatment_missing):
		for reason:String in treatment_missing:
			var repair_focus:Dictionary=_staffing_focus(snapshot,catalog,reason.trim_prefix("missing_staff:"))
			if repair_focus.is_empty():continue
			repair_focus.patient_id=patient_id;repair_focus.expected_revision=int(decision.get("revision",0))
			var repair_role_name:String=str(catalog.campaign.roles[repair_focus.role].name)
			return _card(snapshot,stage,"clinical:"+patient_id,"先补齐这位患者的治疗岗位","当前把握度%d / 100，治疗设备尚缺%s。查看费用并确认后才招聘或派岗；治疗、复检与转诊仍由你决定。"%[int(decision.get("confidence",0)),repair_role_name],"安排诊疗岗位",repair_focus)
	var control:String=""
	for action:String in decision.get("options",[]):
		var terms:Dictionary=decision.get("terms",{}).get(action,{})
		if not terms.get("missing",[]).is_empty():continue
		if action=="continue_exam" and int(decision.get("completed_exams",0))>=int(decision.get("max_exams",0)):continue
		control="decision_"+patient_id+"_"+action
		break
	return _card(snapshot,stage,"clinical:"+patient_id,"根据首诊结果作决定","患者已完成真实检查，当前把握度%d / 100。查看继续检查、审慎治疗与转诊各自的时间、费用和缺项，再由你决定。"%int(decision.get("confidence",0)),"查看患者决定",{"action":"clinical","patient_id":patient_id,"control":control,"expected_revision":int(decision.get("revision",0))})

static func _only_staff_missing(reasons:Array) -> bool:
	if reasons.is_empty():return false
	for reason:Variant in reasons:
		if not str(reason).begins_with("missing_staff:"):return false
	return true

static func _staffing_focus(snapshot:Dictionary,catalog:ContentCatalog,kind:String) -> Dictionary:
	if not catalog.campaign.facilities.has(kind):return {}
	var facility_ids:Array=snapshot.facilities.keys();facility_ids.sort()
	var staff_ids:Array=snapshot.staff.keys();staff_ids.sort()
	for id:String in facility_ids:
		var facility:Dictionary=snapshot.facilities[id]
		if facility.kind!=kind or facility.status!="open" or int(facility.condition)<=0:continue
		var room:Dictionary=snapshot.rooms.get(facility.room_id,{})
		if room.is_empty() or room.get("status","open")!="open" or room.get("closed",false):continue
		# Match the focused staffing card's real owned vacancies, including
		# repeated catalog roles. Training/closure is not a missing new hire.
		var missing:Array=catalog.campaign.facilities[kind].roles.duplicate()
		for sid:String in facility.staff_ids:
			var employee:Dictionary=snapshot.staff.get(sid,{})
			if employee.get("facility_id","")==id and employee.get("role","") in missing:missing.erase(employee.role)
		if missing.is_empty():continue
		var role:String=str(missing[0])
		var focus:Dictionary={"action":"staff","facility_kind":kind,"facility_id":id,"role":role,"control":"hire"}
		for sid:String in staff_ids:
			var employee:Dictionary=snapshot.staff[sid]
			if employee.role!=role or employee.get("facility_id","")!="" or int(employee.get("fatigue",0))>=95:continue
			var assignment_state:=ClinicState.new();assignment_state.data=snapshot.duplicate(true)
			if CampaignCommands._assign(assignment_state,catalog,{"staff_id":sid,"facility_id":id}).get("ok",false):
				focus.control="assign";focus.staff_id=sid;return focus
		# Reuse backend rules on a detached quote, never recruit for navigation.
		var hire_state:=ClinicState.new();hire_state.data=snapshot.duplicate(true)
		var hired:Dictionary=CampaignCommands._hire(hire_state.data,catalog,{"role":role},"opening-guide-preview")
		if hired.get("ok",false) and CampaignCommands._assign(hire_state,catalog,{"staff_id":hired.data.staff_id,"facility_id":id}).get("ok",false):return focus
	return {}

static func _facility_id(snapshot:Dictionary,kind:String) -> String:
	var ids:Array=snapshot.get("facilities",{}).keys()
	ids.sort()
	var first:String=""
	for id:String in ids:
		var facility:Dictionary=snapshot.facilities[id]
		if str(facility.get("kind",""))!=kind:continue
		if first=="":first=id
		if facility.get("status","")=="open" and int(facility.get("condition",0))>0:return id
	return first

static func _unassigned_staff(snapshot:Dictionary,role:String) -> String:
	var ids:Array=snapshot.get("staff",{}).keys()
	ids.sort()
	for id:String in ids:
		var worker:Dictionary=snapshot.staff[id]
		if worker.get("role","")==role and worker.get("facility_id","")=="":return id
	return ""

static func _card(snapshot:Dictionary,stage:Dictionary,id:String,title:String,text:String,button:String,focus:Dictionary) -> Dictionary:
	return {"visible":true,"id":id,"title":title,"text":text,"button":button,"focus":focus,"phase_name":str(stage.get("phase_name","")),"phase_index":int(stage.get("phase_index",0)),"source_level_id":str(snapshot.get("level_id","")),"source_sequence":int(snapshot.get("command_sequence",0))}
