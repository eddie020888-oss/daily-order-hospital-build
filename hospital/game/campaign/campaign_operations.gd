class_name CampaignOperations
extends RefCounted

static func readiness(d: Dictionary, catalog: ContentCatalog, facility_kind: String) -> Array:
	if not catalog.campaign.facilities.has(facility_kind): return ["unknown_facility"]
	if LongCampaign.is_long(d):
		var usable:=false
		for f:Dictionary in d.facilities.values():
			if f.kind!=facility_kind or not _long_operable(f,catalog):continue
			usable=true
			if _long_staffed(d,f,catalog):return []
		return ["missing_staff:"+facility_kind] if usable else ["missing_facility:"+facility_kind]
	var found:=false
	for f in d.facilities.values():
		if f.kind!=facility_kind or f.status!="open": continue
		found=true
		var roles: Array=catalog.campaign.facilities[facility_kind].roles.duplicate()
		for sid in f.staff_ids:
			if d.staff.has(sid) and d.staff[sid].role in roles: roles.erase(d.staff[sid].role)
		if roles.is_empty(): return []
	return ["missing_staff:"+facility_kind] if found else ["missing_facility:"+facility_kind]

static func _long_operable(f:Dictionary,catalog:ContentCatalog)->bool:
	# Engineers can perform a real paid field repair even when their own
	# workshop is damaged. Other facilities must be repaired before a new job.
	return f.status=="open" and (int(f.condition)>0 or catalog.campaign.facilities[f.kind].handler=="repair")

static func _long_staffed(d:Dictionary,f:Dictionary,catalog:ContentCatalog)->bool:
	var roles:Array=catalog.campaign.facilities[f.kind].roles.duplicate()
	for sid:String in f.staff_ids:
		if d.staff.has(sid) and d.staff[sid].role in roles:roles.erase(d.staff[sid].role)
	return roles.is_empty()

static func request(state: ClinicState, catalog: ContentCatalog, facility_kind: String, handler: String="", patient_id: String="") -> String:
	var d: Dictionary=state.data
	if not catalog.campaign.facilities.has(facility_kind): return ""
	var facility_id:=""
	var facility_ids:Array=d.facilities.keys()
	if LongCampaign.is_long(d):facility_ids.sort()
	for candidate_id:String in facility_ids:
		var f:Dictionary=d.facilities[candidate_id]
		if f.kind!=facility_kind or f.status!="open":continue
		if LongCampaign.is_long(d) and (not _long_operable(f,catalog) or not _long_staffed(d,f,catalog)):continue
		facility_id=f.id;break
	if facility_id=="": return ""
	var definition: Dictionary=catalog.campaign.facilities[facility_kind]
	var step: Dictionary={}
	if patient_id!="" and d.patients.has(patient_id):
		var patient: Dictionary=d.patients[patient_id]
		if patient.step_index<patient.steps.size(): step=patient.steps[patient.step_index]
	var id:="work_%04d"%d.next_ids.work_order
	d.next_ids.work_order+=1
	d.work_orders[id]={"id":id,"facility_id":facility_id,"facility_kind":facility_kind,"handler":handler if handler!="" else definition.handler,"patient_id":patient_id,"step_id":step.get("id",""),"staff_id":"","staff_ids":[],"status":"queued","work":0,"needed":step.get("duration_ticks",definition.duration_ticks),"cost":step.get("cost",definition.consumable_cost),"resource":step.get("resource",definition.get("input_resource","")),"quantity":step.get("quantity",definition.get("input_quantity",0)),"reason":"","created_tick":d.tick,"started_tick":-1,"completed_tick":-1,"output":definition.output.duplicate(true)}
	CampaignBusiness.quote(d,d.work_orders[id])
	if LongCampaign.is_long(d):
		d.campaign.active_order_ids.append(id)
		if d.work_orders[id].handler=="repair":
			# Lock the most damaged machine when requesting a manual job;
			# periodic wear must not repeatedly send the engineer to the first one.
			var target:=""
			var lowest:=101
			var machine_ids:Array=d.facilities.keys()
			machine_ids.sort()
			for machine_id:String in machine_ids:
				if int(d.facilities[machine_id].condition)<lowest:
					lowest=int(d.facilities[machine_id].condition)
					target=machine_id
			if target!="":d.work_orders[id]["target_facility_id"]=target
	return id

static func after_tick(state: ClinicState, catalog: ContentCatalog) -> void:
	var d: Dictionary=state.data
	var order_ids:Array=d.campaign.active_order_ids.duplicate() if LongCampaign.is_long(d) else d.work_orders.keys()
	for id in order_ids:
		var order: Dictionary=d.work_orders[id]
		if order.status=="done": continue
		if not d.facilities.has(order.facility_id): order.reason="missing_facility"; continue
		var f: Dictionary=d.facilities[order.facility_id]
		if f.status!="open": order.reason="facility_closed"; continue
		# A batch already paid for and started may finish safely on its original
		# clock. Queued/walking jobs wait without a second charge until repaired.
		if LongCampaign.is_long(d) and order.status!="working" and int(f.condition)<=0 and order.handler!="repair":
			order.reason="facility_broken";continue
		if order.status in ["queued","blocked"]:
			var workers:Array=_workers(d,f,catalog.campaign.facilities[f.kind].roles,CampaignStaffRelief.order_eligible(d,catalog,order))
			if workers.is_empty(): order.reason="missing_or_busy_staff"; continue
			var all_paths:={}
			for n in range(workers.size()):
				var worker: Dictionary=d.staff[workers[n]]
				var goal:int=CampaignStaffRelief.work_cell(d,str(f.id),str(worker.id))
				var path:=GridService.path_avoiding(state,worker.cell,goal,CampaignClinicalFlow._work_positions(d,worker,goal))
				if path.is_empty(): all_paths.clear(); break
				all_paths[worker.id]=path
			if all_paths.size()!=workers.size(): order.reason="unreachable_workplace"; continue
			order.staff_ids=workers
			order.staff_id=workers[0]
			order.status="walking"
			order.reason=""
			CampaignStaffRelief.record_order(d,order)
			for sid in workers:
				var worker: Dictionary=d.staff[sid]
				worker.work_order_id=id; worker.status="moving_work"; worker.path=all_paths[sid]; worker.path_index=0; worker.move_progress=0
		if order.status=="walking":
			var arrived:=true
			for sid in order.staff_ids:
				var goal:int=CampaignStaffRelief.work_cell(d,str(f.id),str(sid))
				if not CampaignClinicalFlow._walk(state,d.staff[sid],goal): arrived=false
			if LongCampaign.is_long(d) and order.has("trainee_id"):
				var trainee:Dictionary=d.staff[order.trainee_id]
				if not CampaignClinicalFlow._walk(state,trainee,int(f.maintenance_cell)):arrived=false
				trainee.status="idle" if trainee.cell==f.maintenance_cell and trainee.move_progress==0 else "walking"
			if not arrived: continue
			var free_cash: int=d.cash
			var free_resource: int=d.resources.get(order.resource,0)
			var patient_ids:Array=d.campaign.live_patient_ids if LongCampaign.is_long(d) else d.patients.keys()
			for patient_id:String in patient_ids:
				var patient:Dictionary=d.patients[patient_id]
				free_cash-=patient.get("reservation_cost",0)
				if patient.get("reservation_resource","")==order.resource: free_resource-=patient.get("reservation_quantity",0)
			if order.cost>free_cash or order.quantity>free_resource: order.reason="insufficient_resources"; continue
			var reference: String="care:"+order.patient_id+":"+order.step_id if order.patient_id!="" else "operation:"+id
			if not CampaignFinance.post(d,"treatment_cost" if order.patient_id!="" else "operations",-order.cost,reference): order.reason="insufficient_cash"; continue
			if order.quantity>0: d.resources[order.resource]-=order.quantity
			if LongCampaign.is_long(d) and order.patient_id=="" and order.handler not in ["research","training"]:
				order["planned_duration"]=int(order.needed)
				order["efficiency_source"]="research:logistics" if "logistics" in d.campaign.research else ""
				if order.efficiency_source!="":order.needed=maxi(1,ceili(float(order.planned_duration)*(100-LongCampaign.LOGISTICS_DISCOUNT_PERCENT)/100.0))
			order.status="working"; order.started_tick=d.tick; order.reason=""
			for sid in order.staff_ids: d.staff[sid].status="working"
		if order.status=="working" and order.started_tick<d.tick:
			order.work+=1
			if order.work<order.needed: continue
			_complete(d,catalog,order)
	_rest_and_payroll(d,catalog)
	if LongCampaign.is_long(d):
		LongCampaign.after_tick(state,catalog)
		return
	_trigger_events(d,catalog)
	CampaignProgress.record_win(d,catalog)
	if d.tick>=catalog.levels[d.level_id].end_tick and d.challenge.status=="running":
		d.challenge={"status":"lost","reason":"mission_timeout","ended_tick":d.tick}; d.paused=true

static func _workers(d: Dictionary, f: Dictionary, roles: Array,allow_relief:bool=false) -> Array:
	if allow_relief:return CampaignStaffRelief.resolve_crew(d,f,roles,true,95)
	var result: Array=[]
	for role in roles:
		var found:=""
		for sid in f.staff_ids:
			if sid in result or not d.staff.has(sid): continue
			var worker: Dictionary=d.staff[sid]
			if CampaignPeople.staff_busy(worker) or CampaignStaffRelief.busy(worker):continue
			if worker.role!=role or worker.get("patient_id","")!="" or worker.get("work_order_id","")!="" or worker.get("fatigue",0)>=95: continue
			if worker.get("training_order_id","")!="":continue
			found=sid; break
		if found=="": return []
		result.append(found)
	return result

static func _move(actor: Dictionary) -> bool:
	if actor.path.is_empty() or actor.path_index>=actor.path.size()-1:
		actor.move_progress=0; return true
	actor.move_progress+=1
	if actor.move_progress>=actor.get("move_ticks",4):
		actor.move_progress=0; actor.path_index+=1; actor.cell=actor.path[actor.path_index]
	return actor.path_index>=actor.path.size()-1

static func _complete(d: Dictionary, catalog: ContentCatalog, order: Dictionary) -> void:
	order.status="done"; order.completed_tick=d.tick; order.reason=""
	if LongCampaign.is_long(d):d.campaign.active_order_ids.erase(order.id)
	var f: Dictionary=d.facilities[order.facility_id]
	f.uses+=1
	f.condition=maxi(0,f.condition-2)
	d.evidence.facilities[f.kind]=d.evidence.facilities.get(f.kind,0)+1
	for key in order.output:
		d.resources[key]=maxi(0,d.resources.get(key,0)+order.output[key])
	for sid in order.staff_ids:
		var worker: Dictionary=d.staff[sid]
		worker.work_order_id=""; worker.status="idle"; worker.fatigue=mini(100,worker.get("fatigue",0)+8)
		CampaignPeople.on_staff_work_completed(d,sid,"operation:"+str(order.id))
	var cp: Dictionary=d.campaign
	var handler: String=order.handler
	if not cp.has("operation_counts"): cp.operation_counts={}
	cp.operation_counts[handler]=cp.operation_counts.get(handler,0)+1
	match handler:
		"repair":
			var target: String=order.get("target_facility_id","")
			if target!="" and d.facilities.has(target): d.facilities[target].condition=100
			else:
				var machine_ids:Array=d.facilities.keys()
				if CampaignExperience.enabled(d):machine_ids.sort()
				for machine_id:String in machine_ids:
					var machine:Dictionary=d.facilities[machine_id]
					if machine.condition<100: machine.condition=100; break
		"floor_clean","toilet_clean","filter","tool_clean": cp["hygiene"]=100
		"temperature": cp["comfort"]=100
		"ventilation": cp["ventilation"]=100
		"ups","power": cp["power_ready"]=true
		"fire": cp["fire_ready"]=true
		"privacy": cp["privacy_ready"]=true
		"identity":
			for patient in d.patients.values(): patient["identity_checked"]=true
		"ticket":
			for patient in d.patients.values(): patient["ticket"]=patient.id
		"call","referral":
			cp["queue_priority_until"]=d.tick+600
			var chosen: Dictionary={}
			for patient in d.patients.values():
				if patient.phase!="care_queue": continue
				if chosen.is_empty() or patient.wait_ticks>chosen.wait_ticks or (patient.wait_ticks==chosen.wait_ticks and patient.id<chosen.id): chosen=patient
			if not chosen.is_empty(): chosen["called_until"]=d.tick+600
		"education": cp["educated"]=cp.get("educated",0)+1
		"accessibility": cp["assistance_ready"]=true
		"roster":
			if CampaignPeople.enabled(d):
				for sid:String in order.staff_ids:d.staff[sid].fatigue=maxi(0,int(d.staff[sid].fatigue)-25)
				CampaignPeople.on_roster_completed(d,order)
			else:
				for worker in d.staff.values(): worker.fatigue=maxi(0,worker.get("fatigue",0)-25)
		"toilet","food","water":
			if not CampaignPeople.enabled(d):
				for patient in d.patients.values(): patient["comfort_bonus"]=mini(600,patient.get("comfort_bonus",0)+100)
		"archive": cp["archived_evidence_tick"]=d.tick
		"research":
			var project_id: String=order.get("project_id","")
			if project_id!="" and project_id not in cp.research: cp.research.append(project_id)
		"training":
			var sid: String=order.get("trainee_id","")
			if d.staff.has(sid):
				if d.staff[sid].get("training_order_id","")==order.id:d.staff[sid]["training_order_id"]=""
				var skill: String=order.get("unit_id","")
				if skill not in d.staff[sid].skills: d.staff[sid].skills.append(skill)
				cp.training.append({"staff_id":sid,"unit_id":skill,"order_id":order.id,"tick":d.tick})

static func _rest_and_payroll(d: Dictionary,catalog: ContentCatalog) -> void:
	if not CampaignPeople.autonomy_enabled(d) and d.tick%20==0:
		for worker in d.staff.values():
			if worker.get("patient_id","")=="" and worker.get("work_order_id","")=="" and (not CampaignPeople.enabled(d) or worker.get("training_order_id","")=="") and int(d.tick)%CampaignPeople.rest_interval(d,worker)==0: worker.fatigue=maxi(0,worker.get("fatigue",0)-1)
	if d.tick%300==0:
		d.campaign.hygiene=maxi(0,d.campaign.get("hygiene",100)-1)
	if d.tick-d.last_payroll_tick>=catalog.levels[d.level_id].day_ticks:
		var wages:=0
		for worker in d.staff.values(): wages+=CampaignPeople.staff_daily_wage(d,catalog,worker)
		if LongCampaign.is_long(d):wages+=int(d.campaign.get("unpaid_wages",0))
		var payroll_paid:bool=CampaignFinance.post(d,"wages",-wages,"payroll:"+str(d.tick))
		if not payroll_paid:
			d.campaign["unpaid_wages"]=wages
		else: d.campaign["unpaid_wages"]=0
		CampaignPeople.on_payroll(d,catalog,payroll_paid)
		d.last_payroll_tick=d.tick
		if d.campaign.loan>0: CampaignFinance.post(d,"interest",-maxi(1,d.campaign.loan/100),"interest:"+str(d.tick))

static func _trigger_events(d: Dictionary,catalog: ContentCatalog) -> void:
	if d.campaign.completed_cases.size()<4 or not d.campaign.events.is_empty(): return
	for event_id in catalog.levels[d.level_id].event_ids:
		var event: Dictionary=catalog.campaign.events[event_id].duplicate(true)
		event.status="open"; event.created_tick=d.tick; event.resolved_tick=-1
		if event_id=="breakdown":
			event["power_buffered"]=d.campaign.get("power_ready",false)
			for f in d.facilities.values():
					if f.get("busy_patient_id","")=="": f.condition=20 if d.campaign.get("power_ready",false) else 0; event["target_facility_id"]=f.id; break
		d.campaign.events.append(event)

static func complete_case(d: Dictionary,catalog: ContentCatalog,case_id: String) -> void:
	if case_id in d.campaign.completed_cases: return
	var found:=0
	for p in d.patients.values():
		if p.case_id!=case_id: continue
		found+=1
		if p.phase!="left" or p.outcome!="completed": return
	if found!=catalog.campaign.cases[case_id].patient_count: return
	d.campaign.completed_cases.append(case_id)
	d.campaign.completed_waves.append(case_id)
	d.campaign.wave_index=d.campaign.completed_cases.size()
	d.campaign.wave_active=false; d.campaign.current_case_id=""
	d.evidence.cases[case_id]={"tick":d.tick,"patient_count":found}
	d.campaign.reputation=mini(100,d.campaign.reputation+2)
	d.paused=true

static func audit_missing(d: Dictionary,catalog: ContentCatalog,audit_id: String) -> Array:
	if not catalog.campaign.audits.has(audit_id): return ["unknown_audit"]
	var req: Array=catalog.campaign.audits[audit_id].requirements
	var missing: Array=[]
	if audit_id=="A01" and not d.campaign.get("fire_ready",false): missing.append("fire_system_check_required")
	if audit_id in ["A13","A16"]:
		if d.campaign.completed_cases!=catalog.levels[d.level_id].case_ids: missing.append("all_cases_before_archive_audit_required")
		var latest_case_tick: int=-1
		for proof in d.evidence.cases.values(): latest_case_tick=maxi(latest_case_tick,proof.tick)
		if LongCampaign.is_long(d):
			for patient:Dictionary in d.patients.values():latest_case_tick=maxi(latest_case_tick,int(patient.get("completed_tick",-1)))
		if d.campaign.get("archived_evidence_tick",-1)<latest_case_tick or d.campaign.get("archived_evidence_tick",-1)<0: missing.append("archive_after_care_required")
	match req[0]:
		"facility":
			if d.evidence.facilities.get(req[1],0)<1: missing.append("facility_work_required:"+req[1])
		"clinical","completed_case":
			if d.campaign.completed_cases.is_empty(): missing.append("completed_case_required")
		"doctor","nurse":
			var found:=false
			for worker in d.staff.values():
				if worker.role==req[0] and worker.facility_id!="": found=true
			if not found: missing.append("assigned_role_required:"+req[0])
		"sterile","sterile_evidence":
			var found:=false
			for kind in ["U32-E1","U32-E2","U32-E3"]:
				if d.evidence.facilities.get(kind,0)>0: found=true
			if not found: missing.append("sterilization_batch_required")
		"support":
			var found:=false
			for kind in d.evidence.facilities:
				if catalog.campaign.facilities[kind].kind=="support": found=true
			if not found: missing.append("completed_support_order_required")
		"blood":
			if d.evidence.facilities.get("U31-E1",0)+d.evidence.facilities.get("U31-E2",0)+d.evidence.facilities.get("U31-E3",0)<1: missing.append("verified_blood_batch_required")
		"condition":
			for f in d.facilities.values():
				if f.condition<30: missing.append("maintenance_required:"+f.id)
		"hygiene":
			if d.campaign.get("hygiene",100)<70: missing.append("cleaning_required")
		"roster":
			if d.campaign.get("operation_counts",{}).get("roster",0)<1: missing.append("roster_handoff_required")
		"ledger":
			if d.metrics.income<=0: missing.append("earned_income_required")
	return missing
