class_name HospitalManagementInsights
extends RefCounted

# Presentation only. Completion remains owned by CampaignManagementEvents.proof.
# No view field is attached to a model, command, save or earned event receipt.
static func event(d:Dictionary,catalog:ContentCatalog,event_id:String)->Dictionary:
	var result:Dictionary={"enabled":false,"ready":false,"resolved":false,"title":"可选经营方案","steps":[],"next_action":"经营方案将在实际病例进展后出现。","section":"cases","patient_id":"","staff_id":"","facility_kind":"","resource":"","case_id":""}
	if catalog==null or not d.get("campaign") is Dictionary:return result
	if not d.get("patients") is Dictionary or not d.get("work_orders") is Dictionary or not d.get("command_receipts") is Dictionary or not d.get("ledger_entries") is Array:return result
	if not catalog.levels.has(str(d.get("level_id",""))) or not CampaignManagementEvents.enabled(d):return result
	var selected:Dictionary={}
	for item:Dictionary in d.campaign.get("management_events",[]):
		if item.id==event_id:selected=item;break
	if selected.is_empty():return result
	var definition:Dictionary=CampaignManagementEvents._definition(d,catalog,event_id)
	if definition.is_empty():return result
	result.enabled=true
	result.title=CampaignManagementEvents.NAMES.get(selected.definition_id,"可选经营方案")
	result.case_id=definition.case_id
	var task:Dictionary=catalog.campaign.cases.get(definition.case_id,{})
	var case_name:String=str(task.get("title",definition.case_id))
	var unit_name:String=str(catalog.campaign.units.get(definition.unit_id,{}).get("name",definition.unit_id))
	if selected.definition_id=="staffing_peak":
		for step:Dictionary in task.get("steps",[]):
			if step.get("kind","")=="patient" and catalog.campaign.facilities.get(step.facility_kind,{}).get("unit_id","")==definition.unit_id:
				result.facility_kind=step.facility_kind;break
	var evidence:Dictionary=selected.proof if selected.status=="resolved" else CampaignManagementEvents.proof(d,catalog,selected,int(d.tick),int(d.command_sequence)+1)
	if selected.status=="resolved" or (selected.status=="accepted" and not evidence.is_empty()):
		result.resolved=selected.status=="resolved"
		result.ready=not result.resolved
		result.patient_id=str(evidence.get("patient_id",""))
		result.staff_id=str(evidence.get("staff_id",""))
		if selected.definition_id=="staffing_peak":
			var histories:Array=d.patients.get(result.patient_id,{}).get("step_history",[])
			var index:int=int(evidence.get("history_index",-1))
			if index>=0 and index<histories.size():result.facility_kind=str(histories[index].facility_kind)
		result.steps=_complete_steps(str(selected.definition_id),str(selected.choice))
		result.next_action="方案已核验完成，可继续经营或查看本阶段目标。" if result.resolved else "真实业务证据已齐全，请核验完成。"
		return result
	_add(result,"choice","已选择经营方案",selected.status=="accepted")
	if selected.status!="accepted":
		result.next_action="先选择一种经营方案。选择后再按步骤安排业务，不会自动修改经营设置。"
		return result
	var charges:Dictionary={}
	for entry:Dictionary in d.ledger_entries:
		charges[str(entry.category)+":"+str(entry.reference)]=entry
	match str(selected.definition_id):
		"fee_compact":_fee(result,d,catalog,definition,selected,charges,case_name)
		"procurement_crunch":_procurement(result,d,catalog,definition,selected,charges)
		"staffing_peak":_staffing(result,d,catalog,definition,selected,charges,unit_name)
		"clinical_handoff":_clinical(result,d,catalog,definition,selected,charges,case_name)
	return result

static func _add(result:Dictionary,id:String,label:String,done:bool)->void:
	result.steps.append({"id":id,"label":label,"done":done})

static func _complete_steps(kind:String,choice:String)->Array:
	var result:Dictionary={"steps":[]}
	_add(result,"choice","已选择经营方案",true)
	match kind:
		"fee_compact":
			_add(result,"price","目标患者已按所选收费入院",true)
			_add(result,"admission","已接收选择方案后的目标常规病例",true)
			_add(result,"outcome","目标患者已治愈并离院",true)
			_add(result,"income","实际诊疗收入已入账",true)
		"procurement_crunch":
			_add(result,"policy","新工单已锁定所选采购方式",true)
			_add(result,"purchase","目标补给已实际付费并完工",true)
			_add(result,"consumption","目标资源已在后续诊疗中实际使用",true)
		"staffing_peak":
			_add(result,"staff","已有匹配专科的受训员工" if choice=="trained_team" else "已有实际付费聘用的合格员工",true)
			_add(result,"care","合格员工已在选择方案后完成对应诊疗",true)
		"clinical_handoff":
			_add(result,"admission","已接收选择方案后的目标常规病例",true)
			if choice=="transfer":
				_add(result,"decision","已为该患者作出转诊决定",true)
				_add(result,"handoff","该患者的转诊交接已实际完成",true)
			_add(result,"outcome","患者已实际转诊离院，未取得本院治愈收入" if choice=="transfer" else "患者已在本院治愈并离院",true)
			if choice=="retain":_add(result,"income","实际诊疗收入已入账",true)
	return result.steps

static func _routine_candidates(d:Dictionary,_catalog:ContentCatalog,definition:Dictionary,chosen:Dictionary)->Array:
	var result:Array=[]
	for id:String in CampaignManagementEvents._patient_ids(d):
		var patient:Dictionary=d.patients[id]
		var admission:Dictionary=CampaignManagementEvents._new_routine(d,patient,definition,chosen,int(d.tick),int(d.command_sequence)+1)
		if not admission.is_empty():result.append({"patient":patient,"admission":admission})
	return result

static func _patient_name(patient:Dictionary)->String:
	return str(patient.get("name","这位患者"))

static func _active(patient:Dictionary)->bool:
	return patient.get("phase","") not in ["left","abandoned"]

static func _fee(result:Dictionary,d:Dictionary,catalog:ContentCatalog,definition:Dictionary,chosen:Dictionary,charges:Dictionary,case_name:String)->void:
	var percent:int=90 if chosen.choice=="community" else 120
	var candidate:Dictionary={}
	var best:int=-1
	for row:Dictionary in _routine_candidates(d,catalog,definition,chosen):
		if int(row.admission.quoted_price_percent)!=percent:continue
		var p:Dictionary=row.patient
		if not _active(p) and p.get("outcome","")!="completed":continue
		var rank:int=100000 if p.get("outcome","")=="completed" else p.step_history.size()
		if rank>best:candidate=p;best=rank
	var admitted:bool=not candidate.is_empty()
	var priced:bool=admitted or int(d.campaign.get("price_percent",100))==percent
	var cured:bool=admitted and candidate.phase=="left" and candidate.outcome=="completed" and int(candidate.completed_tick)<=int(d.tick)
	var expected:int=CampaignExperience.clinical_income(d,int(catalog.campaign.cases[definition.case_id].income),percent)
	var income:Dictionary=charges.get("income:income:"+str(candidate.get("id","")),{})
	var paid:bool=cured and not income.is_empty() and int(income.amount)==expected and int(income.tick)<=int(d.tick) and int(candidate.income)==expected
	_add(result,"price","目标患者按%d%%收费入院；现有患者报价不会追改"%percent,priced)
	_add(result,"admission","接收选择方案后的「%s」常规病例"%case_name,admitted)
	_add(result,"outcome","目标患者治愈并实际离院",cured)
	_add(result,"income","实际诊疗收入%d币已入账"%expected,paid)
	if not priced:
		result.section="finance";result.next_action="到财务页应用%d%%收费，再接收「%s」常规病例。"%[percent,case_name]
	elif not admitted:
		result.section="cases";result.next_action="接收新的「%s」常规病例。选择方案前的患者、签名病例或其他收费的旧报价不能代替这一步。"%case_name
	else:
		result.section="patients";result.patient_id=candidate.id
		result.next_action="%s已治愈离院，但尚未找到匹配的实际结算，请查看该患者。"%_patient_name(candidate) if cured else "查看%s的诊疗进度；实际治愈离院后再核验，之后调价不影响这位患者已锁定的报价。"%_patient_name(candidate)

static func _procurement(result:Dictionary,d:Dictionary,catalog:ContentCatalog,definition:Dictionary,chosen:Dictionary,charges:Dictionary)->void:
	var target:Dictionary=CampaignManagementEvents.supply_target(catalog,definition)
	if target.is_empty():result.next_action="暂未找到该病例的补给来源，请返回病例页查看。";return
	result.facility_kind=target.facility_kind;result.resource=target.resource
	var facility_name:String=str(catalog.campaign.facilities[target.facility_kind].name)
	var job:Dictionary={}
	var done_job:Dictionary={}
	for id:String in d.work_orders:
		var order:Dictionary=d.work_orders[id]
		var quote:Dictionary=order.get("procurement_quote",{})
		if order.facility_kind!=target.facility_kind or order.patient_id!="" or quote.get("policy","")!=chosen.choice:continue
		if int(order.created_tick)<int(chosen.chosen_tick) or int(quote.get("command_sequence",-1))<int(chosen.chosen_sequence) or int(quote.get("command_sequence",-1))>=int(d.command_sequence)+1:continue
		if int(order.started_tick)>=0 and int(order.started_tick)<=int(chosen.chosen_tick):continue
		if job.is_empty():job=order
		var charge:Dictionary=charges.get("operations:operation:"+id,{})
		if order.status=="done" and int(order.completed_tick)<=int(d.tick) and int(order.started_tick)>int(chosen.chosen_tick) and int(order.output.get(target.resource,0))>0 and not charge.is_empty() and int(charge.amount)==-int(order.cost) and int(charge.tick)==int(order.started_tick):done_job=order;break
	var policy:bool=not job.is_empty() or str(d.campaign.get("procurement_policy","standard"))==str(chosen.choice)
	var purchased:bool=not done_job.is_empty()
	var consumer:Dictionary={}
	if purchased:
		for patient_id:String in CampaignManagementEvents._patient_ids(d):
			var patient:Dictionary=d.patients[patient_id]
			for history:Dictionary in patient.step_history:
				if history.resource==target.resource and int(history.quantity)>0 and int(history.started_tick)>int(done_job.completed_tick) and int(history.completed_tick)<0:consumer=patient;break
			if not consumer.is_empty():break
	_add(result,"policy","新工单使用所选采购方式；已有工单保留原报价",policy)
	_add(result,"purchase","「%s」完成选择方案后的真实付费补给"%facility_name,purchased)
	_add(result,"consumption","目标资源在之后的诊疗步骤中实际使用并完成该步骤",false)
	if not policy:
		result.section="finance";result.next_action="到财务页应用%s采购，再为「%s」安排新工单。"%["节省" if chosen.choice=="economy" else "加急",facility_name]
	elif not purchased:
		result.section="operations"
		result.next_action="「%s」已有所选报价的工单，等待其真实开工、付费和完成；无需重复下单或改回当前策略。"%facility_name if not job.is_empty() else "在后勤页为「%s」安排新的补给工单；方案选定前的旧批次不计。"%facility_name
	elif not consumer.is_empty():
		result.section="patients";result.patient_id=consumer.id;result.next_action="%s正在使用已补给的资源，等待该诊疗步骤实际完成后核验。"%_patient_name(consumer)
	else:
		result.section="cases";result.next_action="补给已完工，让后续诊疗实际使用目标资源。原在院患者也可以，不必额外收新患者或等完整疗程结束。"

static func _paid_employee(d:Dictionary,catalog:ContentCatalog,sid:String,roles:Array,charges:Dictionary,before_tick:int=-1)->bool:
	for receipt:Dictionary in d.command_receipts.values():
		var row:Dictionary=receipt.data
		if row.command.type not in ["hire","hire_staff"] or row.get("staff_id","")!=sid or int(row.sequence)>int(d.command_sequence)+1:continue
		if before_tick>=0 and int(row.tick)>=before_tick:continue
		var role:String=str(row.command.payload.get("role",""))
		if role not in roles or not catalog.campaign.roles.has(role):continue
		var charge:Dictionary=charges.get("hire:command:"+str(row.command.id),{})
		if not charge.is_empty() and int(charge.amount)==-int(catalog.campaign.roles[role].hire_cost):return true
	return false

static func _trained_employee(d:Dictionary,sid:String,unit:String,before_tick:int)->bool:
	for training:Dictionary in d.campaign.get("training",[]):
		if training.staff_id!=sid or training.unit_id!=unit or int(training.tick)>=before_tick:continue
		var order:Dictionary=d.work_orders.get(training.order_id,{})
		if not order.is_empty() and order.status=="done" and order.get("trainee_id","")==sid and order.get("unit_id","")==unit:return true
	return false

static func _staffing(result:Dictionary,d:Dictionary,catalog:ContentCatalog,definition:Dictionary,chosen:Dictionary,charges:Dictionary,unit_name:String)->void:
	var qualified:bool=false
	var target_kind:String=str(result.facility_kind)
	for sid:String in d.get("staff",{}):
		var worker:Dictionary=d.staff[sid]
		var facility:Dictionary=d.get("facilities",{}).get(worker.get("facility_id",""),{})
		if facility.is_empty():continue
		var spec:Dictionary=catalog.campaign.facilities.get(facility.kind,{})
		if spec.get("unit_id","")!=definition.unit_id or worker.role not in spec.get("roles",[]):continue
		var matches:bool=_paid_employee(d,catalog,sid,spec.roles,charges) if chosen.choice=="staffed_team" else (definition.unit_id in worker.get("skills",[]) and _trained_employee(d,sid,definition.unit_id,int(d.tick)+1))
		if not matches:continue
		if not qualified or str(facility.kind)==target_kind:
			qualified=true;result.staff_id=sid;result.facility_kind=facility.kind
		if str(facility.kind)==target_kind:break
	var patient:Dictionary={}
	for pid:String in CampaignManagementEvents._patient_ids(d):
		var p:Dictionary=d.patients[pid]
		for history:Dictionary in p.step_history:
			if history.kind!="patient" or int(history.started_tick)<=int(chosen.chosen_tick) or int(history.completed_tick)>=0:continue
			var spec:Dictionary=catalog.campaign.facilities.get(history.facility_kind,{})
			if spec.get("unit_id","")!=definition.unit_id:continue
			for sid:String in history.staff_ids:
				var matches:bool=_paid_employee(d,catalog,sid,spec.roles,charges,int(history.started_tick)) if chosen.choice=="staffed_team" else (str(history.get("efficiency_source","")) in ["training:"+sid,"research:efficiency+training:"+str(definition.unit_id)] and _trained_employee(d,sid,definition.unit_id,int(history.started_tick)))
				if matches:qualified=true;patient=p;result.staff_id=sid;result.facility_kind=history.facility_kind;break
			if not patient.is_empty():break
		if not patient.is_empty():break
	_add(result,"staff","「%s」已有匹配的受训在岗员工"%unit_name if chosen.choice=="trained_team" else "「%s」已有实际付费聘用的合格在岗员工"%unit_name,qualified)
	_add(result,"care","合格员工在选择方案后实际完成该专科诊疗步骤",false)
	if not qualified:
		result.section="staff";result.next_action="查找并派岗「%s」已受训员工；若尚无匹配人员，可到成长与审核培训，已有合格课程不必重做。"%unit_name if chosen.choice=="trained_team" else "为「%s」派岗已付费聘用的合格员工。已有员工可以使用，不要求额外增聘。"%unit_name
	elif not patient.is_empty():
		result.section="patients";result.patient_id=patient.id;result.next_action="合格员工正在服务%s，等待该专科步骤实际完成后核验；原在院患者也可以。"%_patient_name(patient)
	else:
		result.section="cases";result.next_action="合格员工已在岗，让「%s」正常接诊并完成一个选择方案后的实际步骤；原在院患者也可以，无须重聘或重训。"%unit_name

static func _refer_decided(patient:Dictionary,chosen:Dictionary,at_tick:int,at_sequence:int)->bool:
	for row:Dictionary in patient.get("clinical_decision",{}).get("receipts",[]):
		if row.action=="refer" and int(row.tick)>=int(chosen.chosen_tick) and int(row.tick)<=at_tick and int(row.sequence)<=at_sequence:return true
	return false

static func _referral_rank(patient:Dictionary,chosen:Dictionary,at_tick:int,at_sequence:int)->int:
	var state:String=str(patient.get("clinical_decision",{}).get("state",""))
	if state in ["authorized","settled"] and patient.get("outcome","")!="referred":return -1
	if _refer_decided(patient,chosen,at_tick,at_sequence):return 3
	if not _active(patient):return -1
	if state=="pending" and patient.get("phase","")=="care_queue":return 2
	if state in ["not_ready","examining"]:return 1
	return -1

static func _clinical(result:Dictionary,d:Dictionary,catalog:ContentCatalog,definition:Dictionary,chosen:Dictionary,charges:Dictionary,case_name:String)->void:
	var candidate:Dictionary={}
	var best:int=-1
	var irreversible:bool=false
	for row:Dictionary in _routine_candidates(d,catalog,definition,chosen):
		var p:Dictionary=row.patient
		var rank:int=-1
		if chosen.choice=="transfer":
			rank=_referral_rank(p,chosen,int(d.tick),int(d.command_sequence)+1)
			if str(p.get("clinical_decision",{}).get("state","")) in ["authorized","settled"] and p.get("outcome","")!="referred":irreversible=true
			if rank<0:continue
		else:
			if not _active(p) and p.outcome!="completed":continue
			rank=100000 if not _active(p) else p.step_history.size()
		if rank>best:candidate=p;best=rank
	var admitted:bool=not candidate.is_empty()
	_add(result,"admission","接收选择方案后的「%s」常规病例"%case_name,admitted)
	if chosen.choice=="retain":
		var cured:bool=admitted and candidate.phase=="left" and candidate.outcome=="completed" and int(candidate.completed_tick)<=int(d.tick)
		var income:Dictionary=charges.get("income:income:"+str(candidate.get("id","")),{})
		_add(result,"outcome","目标患者在本院治愈并实际离院",cured)
		_add(result,"income","实际诊疗收入已入账",cured and not income.is_empty())
		result.section="patients" if admitted else "cases"
		result.patient_id=str(candidate.get("id",""))
		result.next_action="接收新的「%s」常规病例，再让其在本院完成诊疗。"%case_name if not admitted else "查看%s的诊疗与离院结算；真实治愈收入入账后再核验。"%_patient_name(candidate)
		return
	var decided:bool=false
	var handed:bool=false
	if admitted:
		var decision:Dictionary=candidate.get("clinical_decision",{})
		decided=_refer_decided(candidate,chosen,int(d.tick),int(d.command_sequence)+1)
		var order:Dictionary=d.work_orders.get(decision.get("referral_order_id",""),{})
		if decided and not order.is_empty() and order.status=="done" and order.patient_id==candidate.id and order.facility_kind=="O05" and int(order.completed_tick)<=int(d.tick):
			for h:Dictionary in candidate.step_history:
				if h.work_order_id==order.id and int(h.completed_tick)==int(order.completed_tick):handed=true;break
	var departed:bool=admitted and candidate.phase=="left" and candidate.outcome=="referred" and int(candidate.completed_tick)<=int(d.tick) and not charges.has("income:income:"+str(candidate.get("id","")))
	_add(result,"decision","在该患者的诊疗决定中选择真实转诊",decided)
	_add(result,"handoff","该患者的O05转诊交接实际完成",handed)
	_add(result,"outcome","患者实际转诊离院，未取得本院治愈收入",departed)
	result.facility_kind="O05"
	if not admitted:
		result.section="cases"
		result.next_action="已有患者已选择本院治疗，不能再追改为转诊。先在病例页设为手动诊疗，再接收新的「%s」常规病例；手动等候仍占用耐心。"%case_name if irreversible else "接收新的「%s」常规病例。若要亲自选择转诊，先在病例页设为手动诊疗，首诊后到患者页决定；手动等候仍占用耐心。"%case_name
	else:
		result.section="patients";result.patient_id=candidate.id
		if not decided and d.campaign.get("clinical_policy","balanced")!="manual":
			result.section="cases";result.next_action="先在病例页将诊疗策略设为手动，再查看%s的首诊与转诊决定；自动策略会自行继续诊疗，手动等候仍占用耐心。"%_patient_name(candidate)
		elif not decided:result.next_action="查看%s的诊疗决定，在首诊完成后选择转诊；单独运行普通转诊工单不能代替该患者的交接。"%_patient_name(candidate)
		elif not handed:result.next_action="%s已选择转诊，等待该患者的O05交接完成；可检查对应设施、人员与耗材。"%_patient_name(candidate)
		else:result.next_action="转诊交接已完成，等待%s实际离院；本次不取得本院治愈收入。"%_patient_name(candidate)
