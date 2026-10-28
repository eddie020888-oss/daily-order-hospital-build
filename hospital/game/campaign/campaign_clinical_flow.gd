class_name CampaignClinicalFlow
extends RefCounted

# Clinical routes use stable step IDs. A repeated facility kind is a new
# service, not a cache hit. Operations owns support jobs and their staff.
const MOVE_TICKS := 4
const TERMINAL := ["left","abandoned"]

static func after_tick(state: ClinicState,catalog: ContentCatalog) -> void:
	var d: Dictionary=state.data
	if d.get("schema_version",0)==3 and d.get("ruleset","")=="full-hospital-v2":
		LongCampaignClinical.after_tick(state,catalog)
		return
	if d.get("paused",true) or d.challenge.status!="running": return
	for id: String in _ids(d.patients):
		var patient: Dictionary=d.patients[id]
		if patient.phase=="care_service": _advance_service(state,catalog,patient)
		elif patient.phase=="waiting_support": _advance_support(state,catalog,patient)
	_move_staff(state)
	for id: String in _ids(d.patients):
		var patient: Dictionary=d.patients[id]
		if patient.phase=="moving_care":
			var f: Dictionary=d.facilities.get(patient.facility_id,{})
			if not f.is_empty() and _walk(state,patient,int(f.service_cells[0])): _start_service(state,catalog,patient)
		elif patient.phase=="moving_exit":
			if _walk(state,patient,GridService.EXIT_CELL): _exit(state,catalog,patient)
		_release_departed(state,patient)
	for id: String in queue_order(d):
		_schedule(state,catalog,d.patients[id])
	for id: String in _ids(d.patients):
		var patient: Dictionary=d.patients[id]
		if patient.phase in ["care_queue","waiting_support"]:
			patient.wait_ticks+=1
			var limit: int=patience_limit(d,catalog,patient)
			if patient.wait_ticks>=limit and patient.phase=="care_queue": _abandon(state,patient)
	_update_case(state,catalog)

static func case_readiness(state: ClinicState,catalog: ContentCatalog,case_id: String) -> Array:
	if state.data.get("schema_version",0)==3 and state.data.get("ruleset","")=="full-hospital-v2": return LongCampaignClinical.instance_readiness(state,catalog,case_id)
	return _case_preparation_reasons(state,catalog,case_id,true)

static func _case_preparation_reasons(state: ClinicState,catalog: ContentCatalog,case_id: String,enforce_wave: bool) -> Array:
	var reasons: Array=[]
	var d: Dictionary=state.data
	if not catalog.campaign.cases.has(case_id): return ["unknown_case"]
	if enforce_wave and d.campaign.wave_active: reasons.append("wave_active")
	var c: Dictionary=catalog.campaign.cases[case_id]
	for step: Dictionary in c.steps:
		var found := false
		var staffed := false
		var reachable := false
		for f: Dictionary in d.facilities.values():
			if f.kind!=step.facility_kind or f.status!="open" or f.condition<=0: continue
			found=true
			var employees: Array=_qualified_staff(d,f,step.roles,false)
			if employees.size()!=step.roles.size(): continue
			staffed=true
			if step.kind=="support":
				reachable=not GridService.path(state,GridService.EXIT_CELL,int(f.maintenance_cell)).is_empty()
			else:
				var blockers: Dictionary=_work_positions(d,{},-1)
				# The existing service occupant may finish before the new visitor
				# arrives. Admission may queue for that target; _schedule/_walk still
				# enforce all real occupied work cells before a reservation/move.
				if not enforce_wave and not f.service_cells.is_empty(): blockers.erase(int(f.service_cells[0]))
				reachable=not f.service_cells.is_empty() and not GridService.path_avoiding(state,GridService.EXIT_CELL,int(f.service_cells[0]),blockers).is_empty()
			if reachable: break
		if not found: reasons.append("missing_facility:"+step.facility_kind)
		elif not staffed: reasons.append("missing_staff:"+step.id)
		elif not reachable: reasons.append("path_blocked:"+step.id)
	# Preparation is explicit: a queued patient is never used as an implicit
	# order to conjure missing batches. Existing stock must cover the whole wave;
	# operators can produce it and replace equipment before admitting the case.
	var count: int=int(c.get("patient_count",1))
	var required: Dictionary={}
	var cost := 0
	for step: Dictionary in c.steps:
		cost+=int(step.cost)*count
		var resource: String=str(step.get("resource",""))
		if resource!="": required[resource]=int(required.get(resource,0))+int(step.get("quantity",0))*count
	for resource: String in required:
		var available: int=int(d.resources.get(resource,0))
		if not enforce_wave:
			for id: String in _patient_ids(d):
				var p: Dictionary=d.patients[id]
				if p.get("reservation_resource","")==resource: available-=int(p.get("reservation_quantity",0))
		if available<int(required[resource]): reasons.append("missing_resource:"+resource)
	if _available_cash(d)<cost: reasons.append("insufficient_case_budget")
	return reasons

static func admit_case(state: ClinicState,catalog: ContentCatalog,case_id: String) -> Dictionary:
	if state.data.get("schema_version",0)==3 and state.data.get("ruleset","")=="full-hospital-v2": return LongCampaignClinical.admit_instance(state,catalog,case_id,"signature","manual",int(state.data.command_sequence)+1)
	var reasons: Array=case_readiness(state,catalog,case_id)
	if not reasons.is_empty(): return {"ok":false,"code":str(reasons[0]),"data":{"reasons":reasons}}
	var d: Dictionary=state.data
	var c: Dictionary=catalog.campaign.cases[case_id]
	var count: int=int(c.get("patient_count",1))
	var live := 0
	for patient: Dictionary in d.patients.values():
		if patient.phase not in TERMINAL: live+=1
	if live+count>int(catalog.levels[d.level_id].max_patients): return {"ok":false,"code":"patient_limit","data":{}}
	var ids: Array=[]
	for _n in range(count):
		var id := "patient_%03d"%int(d.next_ids.patient)
		d.next_ids.patient+=1
		d.patients[id]=_new_patient(d,c,id,case_id)
		ids.append(id)
	d.campaign.wave_active=true
	d.campaign.current_case_id=case_id
	return {"ok":true,"code":"ok","data":{"patient_ids":ids,"case_id":case_id}}

static func _new_patient(d: Dictionary,c: Dictionary,id: String,case_id: String) -> Dictionary:
	var patient:Dictionary={"id":id,"disease_id":c.disease_id,"case_id":case_id,"phase":"care_queue","stage":"care",
			"cell":GridService.EXIT_CELL,"path":[],"path_index":0,"move_progress":0,"move_ticks":MOVE_TICKS,
			"room_id":"","facility_id":"","slot_id":"","staff_id":"","staff_ids":[],"blocked_slot_id":"","support_order_id":"",
			"arrived_tick":d.tick,"arrival_tick":d.tick,"admitted_tick":d.tick,"queue_enter_tick":d.tick,"tolerance":70,"wait_reason":"","wait_ticks":0,
			"service_started_tick":-1,"service_work":0,"service_needed":0,"step_index":0,"steps":c.steps.duplicate(true),"step_history":[],
			"outcome":"","income":CampaignExperience.clinical_income(d,int(c.income),int(d.campaign.price_percent)),"completed_tick":-1,"walked_cells":0,
			"reservation_cost":0,"reservation_resource":"","reservation_quantity":0}
	CampaignClinicalDecisions.initialize_patient(d,c,patient)
	CampaignPeople.init_patient(d,patient)
	return patient

static func _schedule(state: ClinicState,catalog: ContentCatalog,p: Dictionary) -> void:
	var d: Dictionary=state.data
	if CampaignClinicalDecisions.before_schedule(state,catalog,p):return
	if p.step_index>=p.steps.size():
		p.phase="moving_exit"; p.stage="exit"; p.wait_reason=""; return
	var step: Dictionary=p.steps[p.step_index]
	if step.kind=="support":
		var order_id: String=CampaignOperations.request(state,catalog,step.facility_kind,catalog.campaign.facilities[step.facility_kind].handler,p.id)
		if order_id=="": p.wait_reason="support_unavailable:"+step.facility_kind; return
		p.support_order_id=order_id; p.phase="waiting_support"; p.wait_reason="support_queued"; return
	var reason: String="missing_facility:"+str(step.facility_kind)
	for id: String in _ids(d.facilities):
		var f: Dictionary=d.facilities[id]
		if f.kind!=step.facility_kind or f.status!="open" or f.condition<=0: continue
		if f.busy_patient_id!="" and f.busy_patient_id!=p.id: reason="facility_busy"; continue
		var employees: Array=_qualified_staff(d,f,step.roles,true)
		if employees.size()!=step.roles.size(): reason="missing_staff"; continue
		if not _stock_ready(d,step,p.id): reason="missing_resource:"+str(step.get("resource","")); continue
		if _available_cash(d,p.id)<int(step.cost): reason="insufficient_cash"; continue
		if f.service_cells.is_empty() or f.staff_cells.size()<employees.size(): reason="invalid_work_positions"; continue
		var goal: int=int(f.service_cells[0])
		if GridService.path_avoiding(state,int(p.cell),goal,_work_positions(d,p,goal)).is_empty(): reason="path_blocked"; continue
		var staff_routes := true
		for n in range(employees.size()):
			var employee: Dictionary=d.staff[employees[n]]
			var employee_goal: int=CampaignStaffRelief.work_cell(d,f.id,str(employees[n]))
			if GridService.path_avoiding(state,int(employee.cell),employee_goal,_work_positions(d,employee,employee_goal)).is_empty(): staff_routes=false
		if not staff_routes: reason="staff_path_blocked"; continue
		# No mutation above this point: all roles, geometry, money and stock pass.
		var slot_id: String=f.id+":0"
		if not d.slots.has(slot_id): d.slots[slot_id]={"id":slot_id,"room_id":f.room_id,"facility_id":f.id,"index":0,"cell":goal,"patient_id":"","phase":"free"}
		var slot: Dictionary=d.slots[slot_id]
		if slot.patient_id!="" and slot.patient_id!=p.id: reason="facility_busy"; continue
		if p.blocked_slot_id==slot_id: p.blocked_slot_id=""
		slot.patient_id=p.id; slot.phase="reserved"
		f.busy_patient_id=p.id
		p.facility_id=f.id; p.room_id=f.room_id; p.slot_id=slot_id; p.staff_ids=employees; p.staff_id=str(employees[0]) if not employees.is_empty() else ""
		p.reservation_cost=int(step.cost); p.reservation_resource=str(step.get("resource","")); p.reservation_quantity=int(step.get("quantity",0))
		p.phase="moving_care"; p.wait_reason=""; p.service_work=0; p.service_needed=int(step.duration_ticks); p.service_started_tick=-1
		for employee_id: String in employees:
			d.staff[employee_id].patient_id=p.id
		CampaignStaffRelief.record_reservation(d,p)
		return
	p.wait_reason=reason

static func _start_service(state: ClinicState,catalog: ContentCatalog,p: Dictionary) -> void:
	var d: Dictionary=state.data
	var f: Dictionary=d.facilities[p.facility_id]
	for n in range(p.staff_ids.size()):
		var employee: Dictionary=d.staff[p.staff_ids[n]]
		var employee_goal: int=CampaignStaffRelief.work_cell(d,f.id,str(p.staff_ids[n]))
		if int(employee.cell)!=employee_goal or int(employee.move_progress)!=0 or employee.get("work_order_id","")!="": return
	var step: Dictionary=p.steps[p.step_index]
	if not _stock_ready(d,step,p.id) or d.cash<int(step.cost): p.wait_reason="reserved_resources_unavailable"; return
	if not CampaignFinance.post(d,"treatment_cost",-int(step.cost),"care:"+p.id+":"+step.id): return
	var resource: String=str(step.get("resource",""))
	if resource!="": d.resources[resource]-=int(step.get("quantity",0))
	p.reservation_cost=0; p.reservation_resource=""; p.reservation_quantity=0
	p.phase="care_service"; p.service_started_tick=d.tick; p.service_work=0; p.wait_reason=""
	var terms: Dictionary=service_terms(d,catalog,step,p.staff_ids)
	p.service_needed=terms.effective_duration
	d.slots[p.slot_id].phase="serving"
	p.step_history.append(_history(step,f.id,p.staff_ids,d.tick,""))
	p.step_history[-1].merge(terms,true)
	CampaignClinicalDecisions.service_started(d,catalog,p)
	for id: String in p.staff_ids:
		d.staff[id].status="serving"; d.staff[id].phase="serving"

static func _advance_service(state: ClinicState,catalog: ContentCatalog,p: Dictionary) -> void:
	var d: Dictionary=state.data
	p.service_work+=1
	if p.service_work<p.service_needed: return
	var f: Dictionary=d.facilities[p.facility_id]
	p.step_history[-1].completed_tick=d.tick
	d.resources.waste=int(d.resources.get("waste",0))+1
	f.uses+=1
	d.evidence.facilities[f.kind]=int(d.evidence.facilities.get(f.kind,0))+1
	for id: String in p.staff_ids:
		var employee: Dictionary=d.staff[id]
		employee.patient_id=""; employee.status="idle"; employee.phase="idle"; employee.fatigue=mini(100,int(employee.get("fatigue",0))+8)
		CampaignPeople.on_staff_work_completed(d,id,"care:"+p.id+":"+str(p.step_history[-1].step_id))
	f.condition=maxi(0,int(f.condition)-2)
	p.blocked_slot_id=p.slot_id
	d.slots[p.slot_id].phase="blocked"
	_clear_active(p)
	p.step_index+=1
	p.phase="care_queue"
	if p.step_index>=p.steps.size(): p.phase="moving_exit"; p.stage="exit"
	CampaignClinicalDecisions.after_service(d,catalog,p)

static func _advance_support(state: ClinicState,catalog: ContentCatalog,p: Dictionary) -> void:
	var d: Dictionary=state.data
	var order: Dictionary=d.work_orders.get(p.support_order_id,{})
	if order.is_empty(): p.wait_reason="support_missing"; return
	var step: Dictionary=p.steps[p.step_index]
	var started: int=int(order.get("started_tick",-1))
	if started>=0 and p.step_history.size()==p.step_index:
		p.step_history.append(_history(step,order.facility_id,order.staff_ids,started,order.id))
	if order.status!="done": p.wait_reason=str(order.get("reason","support_queued")); return
	if p.step_history.size()==p.step_index:
		p.step_history.append(_history(step,order.facility_id,order.staff_ids,int(order.completed_tick)-int(order.needed),order.id))
	p.step_history[-1].completed_tick=order.completed_tick
	p.step_index+=1; p.support_order_id=""; p.wait_reason=""; p.phase="care_queue"
	if p.step_index>=p.steps.size(): p.phase="moving_exit"; p.stage="exit"
	CampaignClinicalDecisions.after_service(d,catalog,p)

static func _history(step: Dictionary,facility_id: String,staff_ids: Array,tick: int,order_id: String) -> Dictionary:
	return {"step_id":step.id,"kind":step.kind,"facility_kind":step.facility_kind,"facility_id":facility_id,"staff_ids":staff_ids.duplicate(),"started_tick":tick,"completed_tick":-1,"cost":int(step.cost),"resource":str(step.get("resource","")),"quantity":int(step.get("quantity",0)),"work_order_id":order_id,"planned_duration":int(step.duration_ticks),"effective_duration":int(step.duration_ticks),"efficiency_source":""}

# Preview and start use the same rule. The immutable case plan and the exact
# qualified growth source are kept beside the latched effective clock.
static func service_terms(d: Dictionary,catalog: ContentCatalog,step: Dictionary,staff_ids: Array) -> Dictionary:
	if LongCampaign.is_long(d):
		var planned_v3: int=int(step.duration_ticks)
		# Patient support jobs retain their authored clock; only direct patient
		# service receives the two independently earned clinical discounts.
		if step.get("kind","")!="patient":
			return {"planned_duration":planned_v3,"effective_duration":planned_v3,"efficiency_source":""}
		var unit_v3: String=str(catalog.campaign.facilities[step.facility_kind].unit_id)
		var trained_staff: String=""
		for candidate_id: String in staff_ids:
			if d.staff.has(candidate_id) and unit_v3 in d.staff[candidate_id].get("skills",[]):
				trained_staff=candidate_id
				break
		var researched: bool="efficiency" in d.campaign.research
		var numerator: int=1
		var denominator: int=1
		if researched:
			numerator*=100-LongCampaign.CLINICAL_RESEARCH_DISCOUNT_PERCENT
			denominator*=100
		if trained_staff!="":
			numerator*=100-LongCampaign.TRAINING_DISCOUNT_PERCENT
			denominator*=100
		var source_v3: String=""
		if researched and trained_staff!="": source_v3="research:efficiency+training:"+unit_v3
		elif researched: source_v3="research:efficiency"
		elif trained_staff!="": source_v3="training:"+trained_staff
		# Round once after multiplying both factors; keep the original plan.
		var effective: int=maxi(1,ceili(float(planned_v3*numerator)/float(denominator)))
		return {"planned_duration":planned_v3,"effective_duration":effective,"efficiency_source":source_v3}
	var source := ""
	if "efficiency" in d.campaign.research: source="research:efficiency"
	else:
		var unit_id: String=str(catalog.campaign.facilities[step.facility_kind].unit_id)
		for id: String in staff_ids:
			if d.staff.has(id) and unit_id in d.staff[id].get("skills",[]): source="training:"+id; break
	var planned: int=int(step.duration_ticks)
	return {"planned_duration":planned,"effective_duration":maxi(1,int(ceil(float(planned)*.9))) if source!="" else planned,"efficiency_source":source}

static func patience_limit(d: Dictionary,catalog: ContentCatalog,p: Dictionary) -> int:
	var base: int=int(catalog.levels[d.level_id].patience_ticks)
	var percent: int=int(d.campaign.price_percent)
	var limit: int=int(base*100/maxi(100,percent))
	if "clinical_quality" in d.campaign.research: limit+=600
	limit+=clampi(int(p.get("comfort_bonus",0)),0,600)
	# Completed services provide small, bounded benefits. Their provenance is
	# verified against actual completed work orders when the game is loaded.
	limit+=clampi(int(d.campaign.get("comfort",0)),0,100)
	limit+=clampi(int(d.campaign.get("ventilation",0)),0,100)
	if bool(d.campaign.get("assistance_ready",false)): limit+=150
	limit+=mini(4,maxi(0,int(d.campaign.get("educated",0))))*50
	if int(d.campaign.get("hygiene",100))<70: limit-=300
	limit-=CampaignPeople.patience_penalty(d,p)
	return maxi(100,limit)

static func queue_order(d: Dictionary) -> Array:
	var result: Array=[]
	for id: String in _patient_ids(d):
		if d.patients[id].phase=="care_queue": result.append(id)
	result.sort_custom(func(a: String,b: String) -> bool:
		var first: Dictionary=d.patients[a]
		var second: Dictionary=d.patients[b]
		var called_a: int=int(first.get("called_until",0))
		var called_b: int=int(second.get("called_until",0))
		if called_a<=int(d.tick): called_a=0
		if called_b<=int(d.tick): called_b=0
		if called_a!=called_b: return called_a>called_b
		var entered_a: int=int(first.get("queue_enter_tick",first.get("arrived_tick",0)))
		var entered_b: int=int(second.get("queue_enter_tick",second.get("arrived_tick",0)))
		if entered_a!=entered_b: return entered_a<entered_b
		return a<b)
	return result

static func _qualified_staff(d: Dictionary,f: Dictionary,roles: Array,available: bool) -> Array:
	if CampaignStaffRelief.configured(d):
		# Content roles supplied by the caller remain authoritative. The module
		# resolves only versioned primary/temporary ownership, never free staff.
		return CampaignStaffRelief.resolve_crew(d,f,roles,available)
	var result: Array=[]
	for role: String in roles:
		var chosen := ""
		for id: String in f.staff_ids:
			if result.has(id) or not d.staff.has(id): continue
			var employee: Dictionary=d.staff[id]
			if employee.role!=role or employee.facility_id!=f.id: continue
			if d.get("schema_version",0)==3 and employee.get("training_order_id","")!="": continue
			if available and (CampaignPeople.staff_busy(employee) or employee.get("work_order_id","")!="" or employee.get("patient_id","")!="" or int(employee.get("fatigue",0))>=100): continue
			chosen=id; break
		if chosen=="": return []
		result.append(chosen)
	return result

static func _stock_ready(d: Dictionary,step: Dictionary,except_id: String="") -> bool:
	var resource: String=str(step.get("resource",""))
	if resource=="": return int(step.get("quantity",0))==0
	if not d.resources.has(resource): return false
	var available: int=int(d.resources[resource])
	for id: String in _patient_ids(d):
		var patient: Dictionary=d.patients[id]
		if patient.id!=except_id and patient.get("reservation_resource","")==resource: available-=int(patient.get("reservation_quantity",0))
	return available>=int(step.get("quantity",0))

static func _available_cash(d: Dictionary,except_id: String="") -> int:
	var available: int=int(d.cash)
	for id: String in _patient_ids(d):
		var patient: Dictionary=d.patients[id]
		if patient.id!=except_id: available-=int(patient.get("reservation_cost",0))
	return available

static func _move_staff(state: ClinicState) -> void:
	var d: Dictionary=state.data
	for id: String in _ids(d.staff):
		var employee: Dictionary=d.staff[id]
		if CampaignStaffRelief.busy(employee):continue
		if CampaignPeople.staff_busy(employee):continue
		if d.get("schema_version",0)==3 and employee.get("training_order_id","")!="": continue
		if employee.get("work_order_id","")!="" or employee.get("status","")=="serving": continue
		var f: Dictionary=d.facilities.get(employee.get("facility_id",""),{})
		if f.is_empty():
			var left: bool=_walk(state,employee,GridService.EXIT_CELL)
			employee.phase="idle" if left else "moving_exit"
			employee.status="idle" if left else "walking"
			continue
		var index: int=f.staff_ids.find(id)
		# Work cells follow the facility's assigned employee order, including
		# repeated roles; commands retain that stable order during a reservation.
		if index<0 or index>=f.staff_cells.size(): continue
		var arrived: bool=_walk(state,employee,int(f.staff_cells[index]))
		employee.phase="idle" if arrived else "moving_to_work"
		employee.status="idle" if arrived else "walking"

static func _work_positions(d: Dictionary,actor: Dictionary,goal: int) -> Dictionary:
	var blocked := CampaignPeople.blockers(d,str(actor.get("id","")),goal)
	for cell:int in CampaignStaffRelief.blocks(d,str(actor.get("id",""))):
		if cell!=int(actor.get("cell",-1)):blocked[cell]=true
	for f: Dictionary in d.facilities.values():
		for n in range(mini(f.staff_ids.size(),f.staff_cells.size())):
			var id: String=CampaignStaffRelief.slot_owner(d,str(f.id),n)
			if not d.staff.has(id): continue
			var cell: int=int(f.staff_cells[n])
			if cell==int(actor.get("cell",-1)) or (id==actor.get("id","") and cell==goal): continue
			blocked[cell]=true
	for slot: Dictionary in d.slots.values():
		if slot.phase=="free" or slot.patient_id==actor.get("id",""): continue
		var cell: int=int(slot.cell)
		if cell!=int(actor.get("cell",-1)): blocked[cell]=true
	# v3 patients can wait away from their completed station. Every walker,
	# including staff and operation workers, respects that real waiting body,
	# its current edge and its reserved destination. v1 has no such markers.
	if d.get("schema_version",0)==3 and d.get("ruleset","")=="full-hospital-v2":
		for id:String in d.campaign.live_patient_ids:
			var patient:Dictionary=d.patients[id]
			if id==actor.get("id","") or not patient.has("queue_cell"):continue
			var occupied:Array=[int(patient.cell),int(patient.queue_cell)]
			var route:Array=patient.get("path",[])
			var index:int=int(patient.get("path_index",0))
			if int(patient.get("move_progress",0))>0 and index+1<route.size():occupied.append(int(route[index+1]))
			for cell:int in occupied:
				if cell!=int(actor.get("cell",-1)):blocked[cell]=true
	if bool(d.campaign.get("privacy_ready",false)) and not actor.has("role"):
		for room: Dictionary in d.rooms.values():
			if room.unit_id not in ["U26","U27","U31","U32"]: continue
			# Never trap a patient who was already inside. A genuine target
			# service room also stays accessible; unrelated transit is barred.
			if int(actor.get("cell",-1)) in room.cells or goal in room.service_cells: continue
			for cell: int in room.cells: blocked[cell]=true
	return blocked

static func _walk(state: ClinicState,actor: Dictionary,goal: int,extra_blocked:Dictionary={}) -> bool:
	# Long idle at a validated cell needs no navigation rebuild.
	if state.data.get("schema_version",0)==3 and state.data.get("ruleset","")=="full-hospital-v2" and int(actor.get("cell",-1))==goal and int(actor.get("move_progress",0))==0 and actor.get("path",[]).is_empty():
		actor.path=[]; actor.path_index=0; actor.move_progress=0
		actor.goal_cell=goal; actor.route_revision=state.data.map_revision
		return true
	var blockers: Dictionary=_work_positions(state.data,actor,goal)
	for cell:int in extra_blocked:
		if cell!=int(actor.get("cell",-1)):blockers[cell]=true
	var route: Array=actor.get("path",[])
	var index: int=int(actor.get("path_index",0))
	var progress: int=int(actor.get("move_progress",0))
	var changed: bool=int(actor.get("goal_cell",-1))!=goal or int(actor.get("route_revision",-1))!=int(state.data.map_revision)
	if not changed:
		for n in range(index+1,route.size()):
			if blockers.has(route[n]): changed=true; break
	# A newly occupied work cell cannot be crossed to escape a cached edge.
	# Retreat by a quarter before replanning, preserving physical continuity.
	if progress>0 and index+1<route.size() and blockers.has(route[index+1]):
		actor.move_progress=progress-1
		if actor.move_progress==0: actor.path=[]; actor.path_index=0; actor.route_revision=-1
		return false
	if changed and progress>0 and index+1<route.size():
		actor.move_progress=progress+1
		if actor.move_progress>=MOVE_TICKS:
			actor.cell=route[index+1]; actor.move_progress=0; actor.path=[]; actor.path_index=0; actor.route_revision=-1
			actor.walked_cells=int(actor.get("walked_cells",0))+1
		return false
	if changed or route.is_empty():
		route=GridService.path_avoiding(state,int(actor.cell),goal,blockers)
		actor.path=route; actor.path_index=0; actor.move_progress=0; actor.goal_cell=goal; actor.route_revision=state.data.map_revision
		index=0
	if route.is_empty(): return false
	if int(actor.cell)==goal: actor.path=[]; actor.path_index=0; actor.move_progress=0; return true
	if index+1>=route.size(): actor.path=[]; actor.route_revision=-1; return false
	actor.move_progress+=1
	if actor.move_progress>=MOVE_TICKS:
		actor.path_index+=1; actor.cell=route[actor.path_index]; actor.move_progress=0
		actor.walked_cells=int(actor.get("walked_cells",0))+1
	if int(actor.cell)==goal:
		actor.path=[]; actor.path_index=0; return true
	return false

static func _release_departed(state: ClinicState,p: Dictionary) -> void:
	var id: String=p.get("blocked_slot_id","")
	if id=="" or not state.data.slots.has(id): return
	var slot: Dictionary=state.data.slots[id]
	if int(p.cell)==int(slot.cell): return
	_free_slot(state.data,slot)
	p.blocked_slot_id=""

static func _free_slot(d: Dictionary,slot: Dictionary) -> void:
	var f: Dictionary=d.facilities.get(slot.facility_id,{})
	if not f.is_empty() and f.busy_patient_id==slot.patient_id: f.busy_patient_id=""
	slot.patient_id=""; slot.phase="free"

static func _clear_active(p: Dictionary) -> void:
	p.room_id=""; p.facility_id=""; p.slot_id=""; p.staff_id=""; p.staff_ids=[]
	p.reservation_cost=0; p.reservation_resource=""; p.reservation_quantity=0
	p.service_started_tick=-1; p.service_work=0; p.service_needed=0

static func _abandon(_state: ClinicState,p: Dictionary) -> void:
	p.outcome="abandoned"; p.phase="moving_exit"; p.stage="exit"; p.wait_reason="patience_exhausted"

static func _exit(state: ClinicState,_catalog: ContentCatalog,p: Dictionary) -> void:
	var d: Dictionary=state.data
	if CampaignClinicalDecisions.finish_exit(state,_catalog,p):return
	if p.phase in TERMINAL: return
	var successful: bool=p.step_index==p.steps.size() and p.outcome!="abandoned"
	if successful:
		if not CampaignFinance.post(d,"income",int(p.income),"income:"+p.id): return
		p.phase="left"; p.outcome="completed"; d.metrics.completed+=1
		d.evidence.diseases[p.disease_id]=int(d.evidence.diseases.get(p.disease_id,0))+1
	else:
		p.phase="abandoned"; p.outcome="abandoned"; d.metrics.abandoned+=1
	p.completed_tick=d.tick; p.path=[]; p.path_index=0; p.move_progress=0
	if p.blocked_slot_id!="" and d.slots.has(p.blocked_slot_id): _free_slot(d,d.slots[p.blocked_slot_id])
	p.blocked_slot_id=""; _clear_active(p)
	d.metrics.patient_totals[p.id]={"arrival_tick":p.arrived_tick,"exit_tick":d.tick,"phase":p.phase,"wait_ticks":p.wait_ticks,"total_ticks":d.tick-p.arrived_tick}

static func _update_case(state: ClinicState,catalog: ContentCatalog) -> void:
	var d: Dictionary=state.data
	if not d.campaign.wave_active: return
	var case_id: String=d.campaign.current_case_id
	var all_terminal := true
	var all_success := true
	var count := 0
	for patient: Dictionary in d.patients.values():
		if patient.case_id!=case_id: continue
		count+=1
		if patient.phase not in TERMINAL: all_terminal=false
		if patient.phase!="left": all_success=false
	if not all_terminal or count==0: return
	d.campaign.wave_active=false; d.campaign.current_case_id=""
	if all_success: CampaignOperations.complete_case(d,catalog,case_id)
	else:
		d.challenge={"status":"lost","reason":"case_abandoned:"+case_id,"ended_tick":d.tick}; d.paused=true

static func _ids(records: Dictionary) -> Array:
	var ids: Array=records.keys(); ids.sort(); return ids

static func _patient_ids(d: Dictionary) -> Array:
	if d.get("schema_version",0)==3 and d.get("ruleset","")=="full-hospital-v2": return d.campaign.live_patient_ids
	return d.patients.keys()
