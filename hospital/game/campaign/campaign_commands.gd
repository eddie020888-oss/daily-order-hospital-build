class_name CampaignCommands
extends RefCounted

const CLINIC_DRIVE:=preload("res://campaign/campaign_clinic_drive.gd")
const STAFF_RELIEF:=preload("res://campaign/campaign_staff_relief.gd")

static func apply(state: ClinicState,catalog: ContentCatalog,command: Dictionary) -> Dictionary:
	if not command.get("id") is String or command.id=="" or not command.get("type") is String or not command.get("payload") is Dictionary or not CommandBus._is_model_value(command): return _no("invalid_command")
	if state.data.command_receipts.has(command.id): return state.data.command_receipts[command.id].duplicate(true)
	if state.data.challenge.status!="running" and command.type not in ["set_paused","set_speed"] and not (LongCampaign.is_long(state.data) and command.type=="continue_hospital"): return _no("challenge_ended")
	var staged:=ClinicState.new()
	staged.data=state.to_data()
	var result:=_dispatch(staged,catalog,command.type,command.payload,"command:"+command.id)
	if not result.ok: return result
	staged.data.command_sequence+=1
	result.data.tick=staged.data.tick; result.data.sequence=staged.data.command_sequence; result.data.command=command.duplicate(true)
	staged.data.command_receipts[command.id]=result.duplicate(true)
	CampaignProgress.sync_tracks(staged.data)
	state.data=staged.data
	return result.duplicate(true)

static func _dispatch(state: ClinicState,catalog: ContentCatalog,type: String,p: Dictionary,reference: String) -> Dictionary:
	var d: Dictionary=state.data
	if not _payload_shape(type,p): return _no("invalid_payload")
	if type=="set_clinic_drive":return CLINIC_DRIVE.apply(state,catalog,p)
	if type in ["set_staff_relief","set_staff_relief_reserve","set_staff_relief_operations"]:return STAFF_RELIEF.apply(state,catalog,type,p,reference)
	if type in ["request_patient_need","set_staff_wage","set_people_autonomy","request_staff_rest"]:return CampaignPeople.apply(state,catalog,type,p,reference)
	if type in ["choose_management_event","resolve_management_event"]:return CampaignManagementEvents.apply(state,catalog,type,p,reference)
	if type=="set_procurement_policy":return CampaignBusiness.apply(state,p)
	if type=="set_clinical_policy":return CampaignClinicalDecisions.set_policy(state,catalog,p,reference)
	if type=="clinical_decision":return CampaignClinicalDecisions.apply(state,catalog,p,reference)
	if LongCampaign.is_long(d) and type in ["accept_case","admit_routine","set_intake","advance_stage","set_operation_auto","continue_hospital"]:
		return LongCampaign.apply(state,catalog,type,p,reference)
	match type:
		"set_paused":
			if not p.get("paused") is bool: return _no("invalid_payload")
			d.paused=p.paused; return _yes()
		"set_speed":
			if p.get("speed",0) not in [1,2]: return _no("invalid_speed")
			d.speed=p.speed; return _yes()
		"build_department": return _build(state,catalog,p,reference)
		"edit_department": return _edit(state,catalog,p,reference)
		"place_facility":
			if not d.rooms.has(p.get("room_id","")): return _no("unknown_room")
			var layout: Dictionary=d.rooms[p.room_id].layout.duplicate(true)
			layout.facilities.append({"id":"","kind":p.get("kind",""),"x":p.get("x",0),"y":p.get("y",0),"rotation":p.get("rotation",0)})
			return _edit(state,catalog,{"room_id":p.room_id,"layout":layout},reference)
		"remove_room": return _remove_room(state,p.get("room_id",""),reference)
		"remove_facility": return _remove_facility(state,catalog,p.get("facility_id",""),reference)
		"hire","hire_staff": return _hire(d,catalog,p,reference)
		"assign","assign_staff": return _assign(state,catalog,p)
		"unassign":
			if not d.staff.has(p.get("staff_id","")): return _no("unknown_staff")
			if STAFF_RELIEF.assignment_locked(d,d.staff[p.staff_id]):return _no("staff_relief_assignment_locked")
			if _staff_busy(d.staff[p.staff_id]): return _no("staff_busy")
			_detach_staff(state,p.staff_id); return _yes({"staff_id":p.staff_id})
		"dismiss","dismiss_staff":
			if not d.staff.has(p.get("staff_id","")): return _no("unknown_staff")
			if STAFF_RELIEF.assignment_locked(d,d.staff[p.staff_id]):return _no("staff_relief_assignment_locked")
			if _staff_busy(d.staff[p.staff_id]): return _no("staff_busy")
			if p.staff_id in d.campaign.get("staff_relief_pool",[]):return _no("staff_relief_registered")
			_detach_staff(state,p.staff_id); d.staff.erase(p.staff_id); return _yes({"staff_id":p.staff_id})
		"accept_case":
			var ids: Array=catalog.levels[d.level_id].case_ids
			if d.campaign.wave_index>=ids.size() or p.get("case_id","")!=ids[d.campaign.wave_index]: return _no("not_next_case")
			return CampaignClinicalFlow.admit_case(state,catalog,p.case_id)
		"run_operation":
			var kind: String=p.get("facility_kind","")
			if catalog.campaign.facilities.get(kind,{}).get("kind","")=="patient": return _no("patient_service_required")
			var missing:=CampaignOperations.readiness(d,catalog,kind)
			if not missing.is_empty(): return _no("operation_not_ready",{"missing":missing})
			for order in d.work_orders.values():
				if order.facility_kind==kind and order.status!="done": return _no("operation_pending")
			var id:=CampaignOperations.request(state,catalog,kind)
			return _yes({"work_order_id":id}) if id!="" else _no("missing_facility")
		"request_audit":
			var aid: String=p.get("audit_id","")
			var missing:=CampaignOperations.audit_missing(d,catalog,aid)
			if not missing.is_empty(): return _no("audit_requirements",{"missing":missing})
			d.campaign.audits[aid]={"passed":true,"tick":d.tick,"facility_evidence":d.evidence.facilities.duplicate(true)}
			d.evidence.audits[aid]=d.tick
			CampaignProgress.record_win(d,catalog)
			return _yes({"audit_id":aid})
		"start_research": return _research(state,catalog,p,reference)
		"start_training": return _training(state,catalog,p,reference)
		"set_price":
			if not p.get("percent") is int or p.percent<75 or p.percent>150: return _no("invalid_price")
			d.campaign.price_percent=p.percent; return _yes()
		"take_loan":
			var amount: int=p.get("amount",0)
			if amount<1000 or amount>10000 or d.campaign.loan+amount>20000: return _no("loan_limit")
			CampaignFinance.post(d,"loan",amount,reference); d.campaign.loan+=amount; return _yes()
		"repay_loan":
			var amount: int=p.get("amount",0)
			if amount<1 or amount>d.campaign.loan: return _no("invalid_repayment")
			if not CampaignFinance.post(d,"repay",-amount,reference): return _no("insufficient_cash")
			d.campaign.loan-=amount; return _yes()
		"resolve_event": return _resolve_event(d,p)
		"close_facility","reopen_facility":
			if not d.facilities.has(p.get("facility_id","")): return _no("unknown_facility")
			var f: Dictionary=d.facilities[p.facility_id]
			if f.get("busy_patient_id","")!="" or CampaignPeople.facility_busy(d,f.id) or STAFF_RELIEF.room_busy(d,f.room_id): return _no("facility_busy")
			for order in d.work_orders.values():
				if order.facility_id==f.id and order.status in ["walking","working"]: return _no("facility_busy")
			f.status="closed" if type=="close_facility" else "open"; return _yes({"facility_id":f.id})
	return _no("unknown_command")

static func _build(state: ClinicState,catalog: ContentCatalog,p: Dictionary,reference: String) -> Dictionary:
	var d: Dictionary=state.data
	if not catalog.campaign.units.has(p.get("unit_id","")) or not p.get("origin_cell") is int or not p.get("layout") is Dictionary: return _no("invalid_department")
	var layout: Dictionary=p.layout.duplicate(true)
	var error:=_layout_ids(d,catalog,layout,{})
	if error!="": return _no(error)
	var id:="department_%03d"%d.next_ids.room
	var proposal:={"id":id,"kind":"campaign_department","ruleset":CampaignContent.RULESET,"unit_id":p.unit_id,"origin_cell":p.origin_cell,"rotation":0,"width":layout.get("width",0),"height":layout.get("height",0),"layout":layout,"status":"open","closed":false,"staff_id":"","upgraded":false,"mode":"fast"}
	var preview:=FacilityLayout.preview(state,proposal)
	if not preview.ok: return preview
	var room: Dictionary=preview.data.room
	for cell in catalog.levels[d.level_id].get("build_restrictions",{}).get("reserved_cells",[]):
		if cell in room.cells: return _no("reserved_plot",{"cell":cell})
	var cost: int=150+layout.width*layout.height*8
	for item in layout.facilities: cost+=catalog.campaign.facilities[item.kind].cost
	if not CampaignFinance.post(d,"build",-cost,reference): return _no("insufficient_cash",{"cost":cost})
	room.id=id; room["capital_cost"]=cost
	d.rooms[id]=room; d.next_ids.room+=1
	_install(d,room,catalog,{})
	d.map_revision+=1
	return _yes({"room_id":id,"cost":cost,"facility_ids":_room_facilities(room)})

static func _layout_ids(d: Dictionary,catalog: ContentCatalog,layout: Dictionary,preserved: Dictionary) -> String:
	if not layout.get("facilities") is Array: return "invalid_facilities"
	for item in layout.facilities:
		if not item is Dictionary or not catalog.campaign.facilities.has(item.get("kind","")): return "unknown_facility"
		if LongCampaign.is_long(d) and not LongCampaign.facility_unlocked(d,catalog,item.kind):return "facility_stage_locked"
		if not item.get("x") is int or not item.get("y") is int or not item.get("rotation") is int: return "invalid_facility_position"
		if preserved.has(item.get("id","")) and preserved[item.id].kind!=item.kind: return "facility_kind_change_requires_purchase"
		if item.get("id","")=="" or not preserved.has(item.id):
			item.id="facility_%04d"%d.next_ids.facility; d.next_ids.facility+=1
	return ""

static func _install(d: Dictionary,room: Dictionary,catalog: ContentCatalog,preserved: Dictionary) -> void:
	for item in room.layout.facilities:
		var geo:=FacilityLayout.facility_geometry(room,item)
		var f: Dictionary=preserved.get(item.id,{"id":item.id,"kind":item.kind,"status":"open","condition":100,"uses":0,"staff_ids":[],"busy_patient_id":""}).duplicate(true)
		f.room_id=room.id; f.x=item.x; f.y=item.y; f.rotation=item.rotation
		for key in ["service_cells","staff_cells","maintenance_cell","equipment_cells"]: f[key]=geo[key]
		d.facilities[item.id]=f
		for index in range(f.service_cells.size()):
			var sid: String=item.id+":"+str(index)
			d.slots[sid]={"id":sid,"room_id":room.id,"facility_id":item.id,"index":index,"cell":f.service_cells[index],"patient_id":"","phase":"free","remaining_ticks":0}
	if not d.queues.has(room.id): d.queues[room.id]=[]

static func _edit(state: ClinicState,catalog: ContentCatalog,p: Dictionary,reference: String) -> Dictionary:
	var d: Dictionary=state.data
	if not d.rooms.has(p.get("room_id","")) or not p.get("layout") is Dictionary: return _no("unknown_room")
	var old: Dictionary=d.rooms[p.room_id]
	if _room_busy(d,old.id): return _no("room_busy")
	var preserved:={}
	for fid in _room_facilities(old): preserved[fid]=d.facilities[fid].duplicate(true)
	var layout: Dictionary=p.layout.duplicate(true)
	var error:=_layout_ids(d,catalog,layout,preserved)
	if error!="": return _no(error)
	var proposal: Dictionary=old.duplicate(true)
	proposal.layout=layout; proposal.width=layout.get("width",0); proposal.height=layout.get("height",0); proposal.room_id=old.id
	var preview:=FacilityLayout.preview(state,proposal)
	if not preview.ok: return preview
	var cost: int=maxi(0,(layout.width*layout.height-old.width*old.height)*8)
	for item in layout.facilities:
		if not preserved.has(item.id): cost+=catalog.campaign.facilities[item.kind].cost
	if cost>0 and not CampaignFinance.post(d,"build",-cost,reference): return _no("insufficient_cash",{"cost":cost})
	var retained:={}
	for item in layout.facilities: retained[item.id]=true
	for fid in preserved:
		if not retained.has(fid) and not preserved[fid].staff_ids.is_empty(): return _no("unassign_staff_first")
	_clear_facilities(d,old)
	var room: Dictionary=preview.data.room
	room.id=old.id; room.capital_cost=old.capital_cost+cost
	d.rooms[old.id]=room
	_install(d,room,catalog,preserved)
	d.map_revision+=1
	return _yes({"room_id":old.id,"cost":cost})

static func _room_facilities(room: Dictionary) -> Array:
	var ids: Array=[]
	for item in room.layout.facilities: ids.append(item.id)
	return ids

static func _clear_facilities(d: Dictionary,room: Dictionary) -> void:
	for fid in _room_facilities(room):
		d.facilities.erase(fid)
		for sid in d.slots.keys():
			if d.slots[sid].facility_id==fid: d.slots.erase(sid)

static func _room_busy(d: Dictionary,room_id: String) -> bool:
	if STAFF_RELIEF.room_busy(d,room_id):return true
	if CampaignPeople.autonomy_enabled(d) and CampaignStaffRest.room_busy(d,room_id):return true
	for f in d.facilities.values():
		if f.room_id==room_id and (f.get("busy_patient_id","")!="" or CampaignPeople.facility_busy(d,f.id)): return true
	for slot in d.slots.values():
		if slot.room_id==room_id and slot.phase!="free": return true
	for order in d.work_orders.values():
		if order.status!="done" and d.facilities.has(order.facility_id) and d.facilities[order.facility_id].room_id==room_id: return true
	return false

static func _remove_room(state: ClinicState,room_id: String,reference: String) -> Dictionary:
	var d: Dictionary=state.data
	if not d.rooms.has(room_id): return _no("unknown_room")
	if _room_busy(d,room_id): return _no("room_busy")
	var room: Dictionary=d.rooms[room_id]
	for actor in d.staff.values():
		if actor.room_id==room_id and _staff_busy(actor): return _no("staff_busy")
	for actor in d.staff.values():
		if actor.room_id==room_id: _detach_staff(state,actor.id)
	_clear_facilities(d,room); d.rooms.erase(room_id); d.queues.erase(room_id)
	CampaignFinance.post(d,"sale",int(room.capital_cost*0.7),reference)
	d.map_revision+=1
	return _yes({"room_id":room_id})

static func _remove_facility(state: ClinicState,catalog: ContentCatalog,id: String,reference: String) -> Dictionary:
	var d: Dictionary=state.data
	if not d.facilities.has(id): return _no("unknown_facility")
	var f: Dictionary=d.facilities[id]
	if _room_busy(d,f.room_id): return _no("room_busy")
	for sid in f.staff_ids.duplicate(): _detach_staff(state,sid)
	var room: Dictionary=d.rooms[f.room_id]
	var layout: Dictionary=room.layout.duplicate(true)
	for item in layout.facilities.duplicate():
		if item.id==id: layout.facilities.erase(item)
	var result:=_edit(state,catalog,{"room_id":room.id,"layout":layout},reference+":edit")
	if not result.ok: return result
	var refund: int=int(catalog.campaign.facilities[f.kind].cost*0.7)
	CampaignFinance.post(d,"sale",refund,reference); d.rooms[room.id].capital_cost=maxi(0,d.rooms[room.id].capital_cost-catalog.campaign.facilities[f.kind].cost)
	return _yes({"facility_id":id,"refund":refund})

static func _hire(d: Dictionary,catalog: ContentCatalog,p: Dictionary,reference: String) -> Dictionary:
	var role: String=p.get("role","")
	if not catalog.campaign.roles.has(role): return _no("unknown_role")
	if d.staff.size()>=catalog.levels[d.level_id].max_staff: return _no("staff_limit")
	if not CampaignFinance.post(d,"hire",-catalog.campaign.roles[role].hire_cost,reference): return _no("insufficient_cash")
	var id:="staff_%03d"%d.next_ids.staff
	d.next_ids.staff+=1
	d.staff[id]={"id":id,"role":role,"room_id":"","facility_id":"","cell":GridService.EXIT_CELL,"path":[],"path_index":0,"move_progress":0,"move_ticks":4,"status":"idle","fatigue":0,"skills":[],"work_order_id":"","patient_id":"","appearance_id":id}
	if LongCampaign.is_long(d):d.staff[id]["training_order_id"]=""
	CampaignPeople.init_staff(d,d.staff[id])
	return _yes({"staff_id":id})

static func _staff_busy(staff: Dictionary) -> bool:
	return STAFF_RELIEF.busy(staff) or CampaignPeople.staff_busy(staff) or staff.get("patient_id","")!="" or staff.get("work_order_id","")!="" or staff.get("training_order_id","")!="" or staff.get("move_progress",0)>0

static func _detach_staff(state: ClinicState,id: String) -> void:
	var d: Dictionary=state.data
	var worker: Dictionary=d.staff[id]
	if d.facilities.has(worker.facility_id): d.facilities[worker.facility_id].staff_ids.erase(id)
	worker.facility_id=""; worker.room_id=""; worker.status="idle"
	worker.path=GridService.path(state,worker.cell,GridService.EXIT_CELL); worker.path_index=0; worker.move_progress=0

static func _assign(state: ClinicState,catalog: ContentCatalog,p: Dictionary) -> Dictionary:
	var d: Dictionary=state.data
	if not d.staff.has(p.get("staff_id","")): return _no("unknown_staff")
	if not d.facilities.has(p.get("facility_id","")): return _no("unknown_facility")
	var worker: Dictionary=d.staff[p.staff_id]
	var f: Dictionary=d.facilities[p.facility_id]
	if STAFF_RELIEF.assignment_locked(d,worker):return _no("staff_relief_assignment_locked")
	if _staff_busy(worker): return _no("staff_busy")
	if worker.id in d.campaign.get("staff_relief_pool",[]):return _no("staff_relief_registered")
	if worker.role not in catalog.campaign.facilities[f.kind].roles: return _no("wrong_role")
	var count:=0
	for sid in f.staff_ids:
		if sid!=worker.id and d.staff[sid].role==worker.role: count+=1
	if count>=catalog.campaign.facilities[f.kind].roles.count(worker.role): return _no("role_filled")
	var path:=GridService.path(state,worker.cell,f.staff_cells[mini(f.staff_ids.size(),f.staff_cells.size()-1)])
	if path.is_empty(): return _no("unreachable_workplace")
	_detach_staff(state,worker.id)
	worker.room_id=f.room_id; worker.facility_id=f.id; worker.path=path; worker.path_index=0; worker.move_progress=0
	if worker.id not in f.staff_ids: f.staff_ids.append(worker.id)
	return _yes({"staff_id":worker.id,"facility_id":f.id})

static func _research(state: ClinicState,catalog: ContentCatalog,p: Dictionary,reference: String) -> Dictionary:
	var d: Dictionary=state.data
	var id: String=p.get("project_id","")
	if not catalog.campaign.projects.has(id): return _no("unknown_project")
	if id in d.campaign.research: return _no("research_completed")
	for order in d.work_orders.values():
		if order.get("project_id","")==id and order.status!="done": return _no("research_pending")
	var project: Dictionary=catalog.campaign.projects[id]
	if not CampaignOperations.readiness(d,catalog,"O10").is_empty(): return _no("research_workplace_required")
	if not CampaignFinance.post(d,"research",-project.cost,reference): return _no("insufficient_cash")
	var order_id:=CampaignOperations.request(state,catalog,"O10","research")
	d.work_orders[order_id]["project_id"]=id; d.work_orders[order_id].needed=project.duration_ticks
	return _yes({"work_order_id":order_id})

static func _training(state: ClinicState,catalog: ContentCatalog,p: Dictionary,reference: String) -> Dictionary:
	var d: Dictionary=state.data
	if not d.staff.has(p.get("staff_id","")) or not catalog.campaign.units.has(p.get("unit_id","")): return _no("invalid_training")
	var worker: Dictionary=d.staff[p.staff_id]
	if _staff_busy(worker) or p.unit_id in worker.skills: return _no("staff_busy_or_trained")
	for order in d.work_orders.values():
		if order.status!="done" and order.get("trainee_id","")==worker.id: return _no("training_pending")
	if not CampaignOperations.readiness(d,catalog,"O09").is_empty(): return _no("teaching_workplace_required")
	if LongCampaign.is_long(d) and d.facilities.get(worker.facility_id,{}).get("kind","")=="O09":return _no("trainee_requires_separate_teacher")
	if not CampaignFinance.post(d,"training",-180,reference): return _no("insufficient_cash")
	var order_id:=CampaignOperations.request(state,catalog,"O09","training")
	d.work_orders[order_id]["trainee_id"]=worker.id; d.work_orders[order_id]["unit_id"]=p.unit_id; d.work_orders[order_id].needed=240
	if LongCampaign.is_long(d):worker["training_order_id"]=order_id
	return _yes({"work_order_id":order_id})

static func _resolve_event(d: Dictionary,p: Dictionary) -> Dictionary:
	for event in d.campaign.events:
		if event.id!=p.get("event_id",""): continue
		if event.status=="resolved": return _yes({"event_id":event.id})
		if LongCampaign.is_long(d) and event.get("definition_id","")=="breakdown" and d.facilities.has(event.get("target_facility_id","")) and d.facilities[event.target_facility_id].condition<30:return _no("event_repair_target_required",{"facility_kind":event.facility_kind})
		for order in d.work_orders.values():
			if order.handler==event.required_handler and order.status=="done" and order.started_tick>=event.created_tick:
				event.status="resolved"; event.resolved_tick=d.tick; d.evidence.events[event.id]=order.id
				return _yes({"event_id":event.id})
		return _no("event_work_required",{"facility_kind":event.facility_kind})
	return _no("unknown_event")

static func _yes(data: Dictionary={}) -> Dictionary: return {"ok":true,"code":"ok","data":data}
static func _no(code: String,data: Dictionary={}) -> Dictionary: return {"ok":false,"code":code,"data":data}

static func _payload_shape(type: String,p: Dictionary) -> bool:
	var shapes:={
		"set_paused":{"paused":TYPE_BOOL},"set_speed":{"speed":TYPE_INT},
		"build_department":{"unit_id":TYPE_STRING,"origin_cell":TYPE_INT,"layout":TYPE_DICTIONARY},"edit_department":{"room_id":TYPE_STRING,"layout":TYPE_DICTIONARY},
		"place_facility":{"room_id":TYPE_STRING,"kind":TYPE_STRING,"x":TYPE_INT,"y":TYPE_INT,"rotation":TYPE_INT},
		"remove_room":{"room_id":TYPE_STRING},"remove_facility":{"facility_id":TYPE_STRING},
		"hire":{"role":TYPE_STRING},"hire_staff":{"role":TYPE_STRING},"assign":{"staff_id":TYPE_STRING,"facility_id":TYPE_STRING},"assign_staff":{"staff_id":TYPE_STRING,"facility_id":TYPE_STRING},
		"unassign":{"staff_id":TYPE_STRING},"dismiss":{"staff_id":TYPE_STRING},"dismiss_staff":{"staff_id":TYPE_STRING},
		"accept_case":{"case_id":TYPE_STRING},"run_operation":{"facility_kind":TYPE_STRING},"request_audit":{"audit_id":TYPE_STRING},
		"start_research":{"project_id":TYPE_STRING},"start_training":{"staff_id":TYPE_STRING,"unit_id":TYPE_STRING},
		"set_price":{"percent":TYPE_INT},"take_loan":{"amount":TYPE_INT},"repay_loan":{"amount":TYPE_INT},"resolve_event":{"event_id":TYPE_STRING},
		"close_facility":{"facility_id":TYPE_STRING},"reopen_facility":{"facility_id":TYPE_STRING}}
	shapes.merge({"set_intake":{"enabled":TYPE_BOOL},"admit_routine":{"case_id":TYPE_STRING},"set_operation_auto":{"facility_kind":TYPE_STRING,"enabled":TYPE_BOOL,"target":TYPE_INT}})
	shapes["set_clinic_drive"]={"enabled":TYPE_BOOL,"case_id":TYPE_STRING,"batches":TYPE_INT}
	shapes["set_staff_relief"]={"enabled":TYPE_BOOL}
	shapes["set_staff_relief_operations"]={"enabled":TYPE_BOOL}
	shapes["set_staff_relief_reserve"]={"staff_id":TYPE_STRING,"enabled":TYPE_BOOL}
	shapes.merge({"request_patient_need":{"patient_id":TYPE_STRING,"need":TYPE_STRING},"set_staff_wage":{"staff_id":TYPE_STRING,"percent":TYPE_INT}})
	shapes.merge({"set_people_autonomy":{"patient_needs":TYPE_BOOL,"staff_rest":TYPE_BOOL},"request_staff_rest":{"staff_id":TYPE_STRING,"need":TYPE_STRING}})
	shapes.merge({"choose_management_event":{"event_id":TYPE_STRING,"choice":TYPE_STRING,"expected_revision":TYPE_INT},"resolve_management_event":{"event_id":TYPE_STRING,"expected_revision":TYPE_INT}})
	shapes.merge({"set_procurement_policy":{"policy":TYPE_STRING},"set_clinical_policy":{"policy":TYPE_STRING},"clinical_decision":{"patient_id":TYPE_STRING,"action":TYPE_STRING,"expected_revision":TYPE_INT}})
	for key in shapes.get(type,{}):
		if not p.has(key) or typeof(p[key])!=shapes[type][key]: return false
	return true
