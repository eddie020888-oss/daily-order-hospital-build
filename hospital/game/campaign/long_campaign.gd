class_name LongCampaign
extends RefCounted

const CLINIC_DRIVE:=preload("res://campaign/campaign_clinic_drive.gd")

const RULESET:="full-hospital-v2"
const CLINICAL_RESEARCH_DISCOUNT_PERCENT:=10
const TRAINING_DISCOUNT_PERCENT:=10
const LOGISTICS_DISCOUNT_PERCENT:=15
const QUALITY_PATIENCE_BONUS_TICKS:=600

static func is_long(d:Dictionary)->bool:
	return d.get("schema_version",0)==3 and d.get("ruleset","")==RULESET

static func expenses(d:Dictionary)->int:
	var result:=0
	for amount:Variant in d.metrics.get("expenses",{}).values():result+=int(amount)
	return result

static func baseline(d:Dictionary)->Dictionary:
	return {"tick":d.tick,"completed":d.metrics.completed,"abandoned":d.metrics.abandoned,"income":d.metrics.income,"expenses":expenses(d),"day_index":d.campaign.day_records.size()}

static func phase(d:Dictionary,catalog:ContentCatalog)->Dictionary:
	return catalog.levels[d.level_id].phases[clampi(int(d.campaign.phase_index),0,3)]

static func unlocked_case_ids(d:Dictionary,catalog:ContentCatalog)->Array:
	return catalog.levels[d.level_id].case_ids.slice(0,int(phase(d,catalog).signature_cases))

static func facility_unlocked(d:Dictionary,catalog:ContentCatalog,kind:String)->bool:
	if not catalog.campaign.facilities.has(kind):return false
	var definition:Dictionary=catalog.campaign.facilities[kind]
	if not is_long(d) or int(d.campaign.phase_index)>=4:return true
	if definition.unit_id in ["OPS","operations",""] or definition.get("category","")=="运营设施" or not str(definition.unit_id).begins_with("U"):return true
	if int(str(definition.unit_id).trim_prefix("U"))>=25:return true
	for id:String in unlocked_case_ids(d,catalog):
		for step:Dictionary in catalog.campaign.cases[id].steps:
			if step.facility_kind==kind:return true
	return false

static func hospital_value(d:Dictionary,catalog:ContentCatalog)->int:
	var total:=0
	for room:Dictionary in d.rooms.values():
		total+=150+int(room.width)*int(room.height)*8
	for f:Dictionary in d.facilities.values():
		total+=int(catalog.campaign.facilities[f.kind].cost)
	return total

static func cure_rate(d:Dictionary)->int:
	var ended:int=int(d.metrics.completed)+int(d.metrics.abandoned)
	return int(int(d.metrics.completed)*100/ended) if ended>0 else 0

static func quality(d:Dictionary,catalog:ContentCatalog,at_tick:int=-1)->Dictionary:
	var end:int=int(d.tick) if at_tick<0 else at_tick
	var start:int=maxi(0,end-3*int(catalog.levels[d.level_id].day_ticks))
	var completed:=0
	var abandoned:=0
	for patient:Dictionary in d.patients.values():
		var terminal:int=int(patient.get("completed_tick",-1))
		if terminal<=start or terminal>end:continue
		if patient.phase=="left" and patient.outcome=="completed":completed+=1
		elif patient.phase=="abandoned":abandoned+=1
	var samples:int=completed+abandoned
	return {"rate":int(completed*100/samples) if samples>0 else 0,"completed":completed,"abandoned":abandoned,"samples":samples,"window_start_tick":start,"window_end_tick":end}

static func development_effects(d:Dictionary)->Dictionary:
	var research:Array=d.campaign.research
	return {"clinical_quality":{"patience_bonus_ticks":QUALITY_PATIENCE_BONUS_TICKS,"active":"clinical_quality" in research},"efficiency":{"clinical_discount_percent":CLINICAL_RESEARCH_DISCOUNT_PERCENT,"active":"efficiency" in research},"logistics":{"operation_discount_percent":LOGISTICS_DISCOUNT_PERCENT,"active":"logistics" in research},"training":{"clinical_discount_percent":TRAINING_DISCOUNT_PERCENT,"combined_clinical_discount_percent":100-int((100-CLINICAL_RESEARCH_DISCOUNT_PERCENT)*(100-TRAINING_DISCOUNT_PERCENT)/100)}}

static func profit_days(d:Dictionary,p:Dictionary)->int:
	var count:=0
	for n in range(d.campaign.day_records.size()-1,-1,-1):
		var day:Dictionary=d.campaign.day_records[n]
		if day.start_tick<int(d.campaign.phase_started_tick) or day.profit<int(p.min_daily_profit) or day.completed<int(p.min_daily_cures):break
		var total:int=int(day.completed)+int(day.abandoned)
		if total==0 or int(int(day.completed)*100/total)<int(p.cure_rate):break
		count+=1
	return count

static func _trained(d:Dictionary,catalog:ContentCatalog)->int:
	return int(_trained_team(d,catalog).staff)

static func _trained_team(d:Dictionary,catalog:ContentCatalog)->Dictionary:
	var result:=0
	var units:Dictionary={}
	for employee:Dictionary in d.staff.values():
		if not d.facilities.has(employee.get("facility_id","")):continue
		var kind:String=d.facilities[employee.facility_id].kind
		if not catalog.campaign.facilities.has(kind):continue
		var unit:String=catalog.campaign.facilities[kind].unit_id
		if unit not in catalog.levels[d.level_id].unit_ids or unit not in employee.get("skills",[]):continue
		result+=1;units[unit]=true
	return {"staff":result,"units":units.size()}

static func _roles(d:Dictionary)->int:
	var found:Dictionary={}
	for employee:Dictionary in d.staff.values():
		if d.facilities.has(employee.get("facility_id","")):found[employee.role]=true
	return found.size()

static func _goal(rows:Array,id:String,label:String,current:int,target:int)->void:
	rows.append({"id":id,"label":label,"current":current,"target":target,"passed":current>=target})

static func goals(d:Dictionary,catalog:ContentCatalog)->Dictionary:
	var cp:Dictionary=d.campaign
	var p:Dictionary=phase(d,catalog)
	var rows:Array=[]
	var complete:bool=bool(cp.get("course_complete",false))
	var recent:Dictionary=quality(d,catalog)
	var team:Dictionary=_trained_team(d,catalog)
	var signature_id:=""
	var ids:Array=catalog.levels[d.level_id].case_ids
	if cp.completed_cases.size()<int(p.signature_cases):signature_id=str(ids[cp.completed_cases.size()])
	if not complete:
		_goal(rows,"new_cures","本阶段新增治愈离院",int(d.metrics.completed)-int(cp.phase_baseline.completed),p.new_cures)
		_goal(rows,"signature_cases","签名病例任务",cp.completed_cases.size(),p.signature_cases)
		_goal(rows,"hospital_value","当前医院价值",hospital_value(d,catalog),p.hospital_value)
		_goal(rows,"cash","现金安全线",d.cash,p.cash)
		_goal(rows,"reputation","医院声誉",cp.reputation,p.reputation)
		_goal(rows,"cure_rate","最近三个经营日治愈率（%）",recent.rate,p.cure_rate)
		_goal(rows,"quality_samples","近期有效结案数",recent.samples,p.quality_samples)
		_goal(rows,"profitable_days","连续达标经营日（利润、病例、质量）",profit_days(d,p),p.profitable_days)
		_goal(rows,"research","已完成真实研究",cp.research.size(),p.research)
		_goal(rows,"trained_staff","已派岗的匹配专科受训员工",team.staff,p.trained_staff)
		_goal(rows,"trained_units","受训在岗专科覆盖",team.units,p.trained_units)
		_goal(rows,"hygiene","当前医院卫生",int(cp.get("hygiene",100)),p.hygiene)
		_goal(rows,"roles","已派岗的岗位种类",_roles(d),p.roles)
		if cp.phase_index==3:
			var operations:=0
			for id:String in catalog.levels[d.level_id].operation_ids:
				if d.evidence.facilities.get(id,0)>0:operations+=1
			var audits:=0
			for id:String in catalog.levels[d.level_id].audit_ids:
				if cp.audits.get(id,{}).get("passed",false) and cp.audits[id].tick>=cp.phase_started_tick:audits+=1
			var resolved:=0
			for event:Dictionary in cp.events:
				if event.status=="resolved":resolved+=1
			_goal(rows,"operations","指定运营设施实际使用",operations,catalog.levels[d.level_id].operation_ids.size())
			_goal(rows,"audits","本阶段综合审核",audits,catalog.levels[d.level_id].audit_ids.size())
			_goal(rows,"events","营业事件实际闭环",resolved,maxi(1,cp.events.size()))
			_goal(rows,"debt","贷款已清偿",1 if cp.loan==0 else 0,1)
			_goal(rows,"empty_hospital","停止普通接诊且在院患者已完成",1 if not cp.intake_enabled and cp.live_patient_ids.is_empty() else 0,1)
	var ready:bool=not complete
	for row:Dictionary in rows:
		if not row.passed:ready=false
	return {"phase_index":cp.phase_index,"phase_name":"综合考核已通过" if complete else p.name,"goals":rows,"can_advance":ready,"course_complete":complete,"continuing":cp.get("continuing",false),"signature_case_id":signature_id,"unlocked_case_ids":unlocked_case_ids(d,catalog),"intake_enabled":cp.intake_enabled,"next_arrival_tick":cp.next_arrival_tick,"intake_reason":cp.intake_reason,"live_count":cp.live_patient_ids.size(),"cure_rate":recent.rate,"quality":recent,"lifetime_cure_rate":cure_rate(d),"lifetime_samples":int(d.metrics.completed)+int(d.metrics.abandoned),"trained_units":team.units,"hospital_value":hospital_value(d,catalog)}

static func _yes(data:Dictionary={})->Dictionary:return {"ok":true,"code":"ok","data":data}
static func _no(code:String,data:Dictionary={})->Dictionary:return {"ok":false,"code":code,"data":data}

static func apply(state:ClinicState,catalog:ContentCatalog,type:String,p:Dictionary,reference:String)->Dictionary:
	var d:Dictionary=state.data
	var cp:Dictionary=d.campaign
	match type:
		"set_intake":
			if not p.get("enabled") is bool:return _no("invalid_payload")
			cp.intake_enabled=p.enabled
			cp.intake_reason="" if p.enabled else "intake_paused"
			if p.enabled:cp.next_arrival_tick=maxi(d.tick,cp.next_arrival_tick)
			return _yes({"enabled":p.enabled})
		"accept_case","admit_routine":
			if not p.get("case_id") is String:return _no("invalid_payload")
			var id:String=p.case_id
			if not id in unlocked_case_ids(d,catalog):return _no("case_stage_locked")
			if type=="accept_case":
				if id!=goals(d,catalog).signature_case_id:return _no("not_next_case")
			else:
				if id not in cp.completed_cases:return _no("routine_case_not_established")
			return LongCampaignClinical.admit_instance(state,catalog,id,"signature" if type=="accept_case" else "routine","manual",d.command_sequence+1)
		"advance_stage":return _advance(state,catalog)
		"set_operation_auto":
			if not p.get("facility_kind") is String or not p.get("enabled") is bool or not p.get("target") is int:return _no("invalid_payload")
			if p.target<1 or p.target>1000:return _no("invalid_automation_target")
			if not catalog.campaign.facilities.has(p.facility_kind):return _no("unknown_facility")
			var f:Dictionary=catalog.campaign.facilities[p.facility_kind]
			if f.output.is_empty() and f.handler not in ["repair","floor_clean","toilet_clean","filter","tool_clean"]:return _no("automation_not_supported")
			if f.output.is_empty() and f.handler in ["repair","floor_clean","toilet_clean","filter","tool_clean"] and p.target>100:return _no("invalid_automation_target")
			cp.automation[p.facility_kind]={"enabled":p.enabled,"target":p.target}
			return _yes({"facility_kind":p.facility_kind,"enabled":p.enabled,"target":p.target})
		"continue_hospital":
			if not cp.course_complete or not cp.career.receipts.has(d.level_id):return _no("course_not_complete")
			if cp.continuing:return _yes({"continuing":true})
			cp.continuing=true
			d.challenge={"status":"running","reason":"","ended_tick":-1}
			d.paused=true
			return _yes({"continuing":true})
	return _no("unknown_long_command")

static func _advance(state:ClinicState,catalog:ContentCatalog)->Dictionary:
	var d:Dictionary=state.data
	var cp:Dictionary=d.campaign
	var status:Dictionary=goals(d,catalog)
	if cp.course_complete:return _no("course_already_complete")
	if not status.can_advance:
		var missing:Array=[]
		for row:Dictionary in status.goals:
			if not row.passed:missing.append(row.id)
		return _no("phase_requirements",{"missing":missing})
	var index:int=cp.phase_index
	var p:Dictionary=phase(d,catalog)
	var b:Dictionary=cp.phase_baseline
	var values:Dictionary={}
	for row:Dictionary in status.goals:values[row.id]=row.current
	var receipt:Dictionary={"id":"phase_%d"%(index+1),"index":index,"started_tick":cp.phase_started_tick,"ended_tick":d.tick,"baseline":b.duplicate(true),"completed_delta":int(d.metrics.completed)-int(b.completed),"abandoned_delta":int(d.metrics.abandoned)-int(b.abandoned),"income_delta":int(d.metrics.income)-int(b.income),"expenses_delta":expenses(d)-int(b.expenses),"hospital_value":status.hospital_value,"cure_rate":cure_rate(d),"reputation":cp.reputation,"cash":d.cash,"profit_days":profit_days(d,p),"signature_cases":cp.completed_cases.duplicate(),"goal_values":values,"reward":p.reward}
	if not CampaignFinance.post(d,"grant",p.reward,"phase:"+d.level_id+":"+str(index)):return _no("phase_reward_failed")
	cp.phase_receipts.append(receipt)
	cp.phase_index+=1
	cp.phase_started_tick=d.tick
	cp.phase_baseline=baseline(d)
	if cp.phase_index==4:
		cp.course_complete=true
		cp.intake_enabled=false
		var career:Dictionary=cp.career
		if not career.receipts.has(d.level_id) and career.completed_levels.size()!=int(catalog.levels[d.level_id].order)-1:return _no("career_order")
		var win:Dictionary={"ruleset":RULESET,"level_id":d.level_id,"order":catalog.levels[d.level_id].order,"phase_receipts":cp.phase_receipts.duplicate(true),"completed_cases":cp.completed_cases.duplicate(),"audit_ids":catalog.levels[d.level_id].audit_ids.duplicate(),"tick":d.tick,"treated":d.metrics.completed,"cure_rate":cure_rate(d),"hospital_value":hospital_value(d,catalog),"income":d.metrics.income,"expenses":expenses(d)}
		win.seal=CampaignProgress._seal(win)
		if not career.receipts.has(d.level_id):
			career.completed_levels.append(d.level_id)
			career.receipts[d.level_id]=win
		d.challenge={"status":"won","reason":"long_hospital_objectives_complete","ended_tick":d.tick}
		d.paused=true
	return _yes({"phase_index":cp.phase_index,"course_complete":cp.course_complete})

static func after_tick(state:ClinicState,catalog:ContentCatalog)->void:
	var d:Dictionary=state.data
	if d.challenge.status!="running" or d.paused:return
	_record_day(d,catalog)
	if d.tick%20==0:_auto_operations(state,catalog)
	_events(d,catalog)
	CampaignManagementEvents.after_tick(state,catalog)
	if d.campaign.intake_enabled and d.tick>=d.campaign.next_arrival_tick:_auto_intake(state,catalog)

static func _record_day(d:Dictionary,catalog:ContentCatalog)->void:
	var cp:Dictionary=d.campaign
	var length:int=catalog.levels[d.level_id].day_ticks
	if d.tick-cp.day_start_tick<length:return
	var income:int=int(d.metrics.income)-int(cp.day_start_income)
	# Unpaid salary is still an operating cost. Paying arrears reduces the
	# liability again so the same salary cannot be counted as a second expense.
	var accrued_expenses:int=expenses(d)+int(cp.get("unpaid_wages",0))
	var cost:int=accrued_expenses-int(cp.day_start_expenses)
	cp.day_records.append({"index":cp.day_records.size()+1,"start_tick":cp.day_start_tick,"end_tick":d.tick,"income":income,"expenses":cost,"profit":income-cost,"completed":int(d.metrics.completed)-int(cp.day_start_completed),"abandoned":int(d.metrics.abandoned)-int(cp.day_start_abandoned)})
	cp.day_start_tick=d.tick;cp.day_start_income=d.metrics.income;cp.day_start_expenses=accrued_expenses
	cp.day_start_completed=d.metrics.completed;cp.day_start_abandoned=d.metrics.abandoned

static func _auto_intake(state:ClinicState,catalog:ContentCatalog)->void:
	var d:Dictionary=state.data
	var cp:Dictionary=d.campaign
	var choices:Array=[]
	for id:String in unlocked_case_ids(d,catalog):
		if id in cp.completed_cases:choices.append(id)
	var drive:Dictionary=CLINIC_DRIVE.view(d,catalog)
	if drive.enabled:choices=[drive.case_id]
	if choices.is_empty():cp.intake_reason="routine_case_not_established";cp.next_arrival_tick=d.tick+100;return
	var start:int=cp.intake_cursor%choices.size()
	var reasons:Array=[]
	for n in range(choices.size()):
		var id:String=choices[(start+n)%choices.size()]
		reasons=LongCampaignClinical.instance_readiness(state,catalog,id)
		if not reasons.is_empty():continue
		var result:Dictionary=LongCampaignClinical.admit_instance(state,catalog,id,"routine","auto",d.command_sequence,cp.intake_cursor)
		if not result.ok:reasons=[result.code];continue
		# The clinical factory alone advances the successful schedule cursor.
		cp.intake_reason=""
		var multiplier:int=clampi(100+(int(cp.price_percent)-100)*2-(int(cp.reputation)-50)/2,65,180)
		cp.next_arrival_tick=d.tick+maxi(80,int(int(phase(d,catalog).arrival_interval_ticks)*multiplier*(CLINIC_DRIVE.INTERVAL_PERCENT if drive.enabled else 100)/10000))
		return
	cp.intake_reason=str(reasons[0]) if not reasons.is_empty() else "intake_waiting"
	cp.next_arrival_tick=d.tick+100

static func _auto_operations(state:ClinicState,catalog:ContentCatalog)->void:
	var d:Dictionary=state.data
	# JSON saves sort dictionary keys. Stable scheduling must not depend on
	# which order the player enabled policies before the save.
	var policy_kinds:Array=d.campaign.automation.keys()
	policy_kinds.sort()
	for kind:String in policy_kinds:
		var policy:Dictionary=d.campaign.automation[kind]
		if not policy.enabled:continue
		var pending:=false
		for oid:String in d.campaign.active_order_ids:
			if d.work_orders[oid].facility_kind==kind:pending=true;break
		if pending or not CampaignOperations.readiness(d,catalog,kind).is_empty():continue
		var f:Dictionary=catalog.campaign.facilities[kind]
		var needed:=false
		var target_id:=""
		if not f.output.is_empty():
			for key:String in f.output:
				if int(f.output[key])>0 and int(d.resources.get(key,0))<int(policy.target):needed=true
		elif f.handler=="repair":
			var worst:int=int(policy.target)
			var machine_ids:Array=d.facilities.keys()
			machine_ids.sort()
			for machine_id:String in machine_ids:
				var machine:Dictionary=d.facilities[machine_id]
				if machine.condition<worst:worst=machine.condition;target_id=machine.id
			needed=target_id!=""
		elif f.handler in ["floor_clean","toilet_clean","filter","tool_clean"]:needed=int(d.campaign.get("hygiene",100))<int(policy.target)
		if not needed:continue
		if int(f.get("input_quantity",0))>int(d.resources.get(f.get("input_resource",""),0)):continue
		if int(CampaignBusiness.preview_terms(d,f).cost)>CampaignClinicalFlow._available_cash(d):continue
		var id:String=CampaignOperations.request(state,catalog,kind)
		if id!="":
			d.work_orders[id]["automation"]=true
			if target_id!="":d.work_orders[id]["target_facility_id"]=target_id

static func _events(d:Dictionary,catalog:ContentCatalog)->void:
	var cp:Dictionary=d.campaign
	if d.tick<cp.next_event_tick:return
	for event:Dictionary in cp.events:
		if event.status!="resolved":return
	var definition_id:String=CampaignBusiness.event_id(d,catalog,int(cp.event_serial))
	var event:Dictionary=catalog.campaign.events[definition_id].duplicate(true)
	cp.event_serial+=1
	event["definition_id"]=definition_id
	event.id="event_%04d"%int(cp.event_serial)
	event.status="open";event.created_tick=d.tick;event.resolved_tick=-1
	if definition_id=="breakdown":
		event["power_buffered"]=cp.get("power_ready",false)
		var facility_ids:Array=d.facilities.keys()
		facility_ids.sort()
		for facility_id:String in facility_ids:
			var f:Dictionary=d.facilities[facility_id]
			if f.busy_patient_id=="":
				f.condition=20 if cp.get("power_ready",false) else 0
				event["target_facility_id"]=f.id
				break
	cp.events.append(event)
	cp.next_event_tick=d.tick+CampaignBusiness.event_interval(d,catalog)

static func validate_career(career:Variant,catalog:ContentCatalog)->String:
	if not career is Dictionary or career.get("ruleset","")!=RULESET or not career.get("completed_levels") is Array or not career.get("receipts") is Dictionary:return "invalid_long_career"
	if career.completed_levels.size()!=career.receipts.size() or career.completed_levels.size()>12:return "invalid_long_career_counts"
	for n in range(career.completed_levels.size()):
		var id:String="long_%02d"%(n+1)
		if career.completed_levels[n]!=id or not career.receipts.has(id) or not catalog.levels.has(id):return "invalid_long_career_order"
		var receipt:Variant=career.receipts[id]
		if not receipt is Dictionary or receipt.get("ruleset","")!=RULESET or receipt.get("level_id","")!=id or receipt.get("order",0)!=n+1 or receipt.get("seal","")!=CampaignProgress._seal(receipt):return "invalid_long_career_receipt"
		var level:Dictionary=catalog.levels[id]
		if receipt.get("completed_cases",[])!=level.case_ids or receipt.get("audit_ids",[])!=level.audit_ids or not receipt.get("phase_receipts") is Array or receipt.phase_receipts.size()!=4:return "invalid_long_career_objectives"
		if not receipt.get("treated") is int or receipt.treated<level.treated_target or not receipt.get("cure_rate") is int or receipt.cure_rate<0 or receipt.cure_rate>100:return "invalid_long_career_quality"
		if not receipt.phase_receipts[3] is Dictionary:return "invalid_long_career_recent_quality"
		var final_values:Variant=receipt.phase_receipts[3].get("goal_values",{})
		if not final_values is Dictionary:return "invalid_long_career_recent_quality"
		if int(final_values.get("cure_rate",-1))<int(level.phases[3].cure_rate) or int(final_values.get("quality_samples",-1))<int(level.phases[3].quality_samples):return "invalid_long_career_recent_quality"
		for index in range(4):
			var proof:Variant=receipt.phase_receipts[index]
			if not proof is Dictionary or proof.get("index",-1)!=index or proof.get("completed_delta",-1)<level.phases[index].new_cures or proof.get("signature_cases",[]).size()<level.phases[index].signature_cases:return "invalid_long_career_phase"
	return ""
