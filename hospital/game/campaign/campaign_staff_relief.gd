class_name CampaignStaffRelief
extends RefCounted

# Explicitly opted-in, paid employees only. Primary assignments never change.
const VERSION:int=1
const ACTIVE:Array=["walking","covering","draining","returning"]

static func configured(d:Dictionary)->bool:
	return CampaignPeople.autonomy_enabled(d) and d.campaign.get("staff_relief_version",0)==VERSION

static func enabled(d:Dictionary)->bool:
	return configured(d) and d.campaign.get("auto_staff_relief",false)==true

static func operations_configured(d:Dictionary)->bool:
	return configured(d) and d.campaign.get("staff_relief_operations_version",0)==1 and d.campaign.get("auto_staff_relief_operations") is bool

static func operations_enabled(d:Dictionary)->bool:
	return operations_configured(d) and enabled(d) and d.campaign.auto_staff_relief_operations==true

static func _operation_definition_allowed(definition:Dictionary)->bool:
	return definition.get("kind","") in ["operations","support"] and definition.get("handler","") not in ["intake","roster","training","research"]

static func _order_scope(catalog:ContentCatalog,order:Dictionary)->bool:
	var definition:Dictionary=catalog.campaign.facilities.get(order.get("facility_kind",""),{})
	return _operation_definition_allowed(definition) and order.get("handler","")==definition.get("handler","") and order.get("patient_id","")=="" and order.get("step_id","")=="" and not order.has("trainee_id") and not order.has("project_id")

static func order_eligible(d:Dictionary,catalog:ContentCatalog,order:Dictionary)->bool:
	return operations_enabled(d) and _order_scope(catalog,order) and order.get("status","") in ["queued","blocked"] and order.get("staff_ids",[]).is_empty() and order.get("staff_id","")=="" and int(order.get("started_tick",-1))<0

static func _has_pending_operation(d:Dictionary,catalog:ContentCatalog,fid:String)->bool:
	for order:Dictionary in d.get("work_orders",{}).values():
		if order.get("facility_id","")==fid and order_eligible(d,catalog,order):return true
	return false

static func busy(s:Dictionary)->bool:
	return s.get("relief_activity") is Dictionary and not s.relief_activity.is_empty()

# Roster indices are persistent handoff evidence until the reserve reaches EXIT.
# Keep this separate from busy(): originals may work again after the reserve leaves.
static func assignment_locked(d:Dictionary,s:Dictionary)->bool:
	if not configured(d):return false
	var fid:String=str(s.get("facility_id",""))
	if fid=="":return false
	for value:Variant in _events(d).values():
		if value is Dictionary and value.get("facility_id","")==fid and value.get("state","") in ACTIVE:return true
	return false

static func init_staff(d:Dictionary,s:Dictionary)->void:
	if configured(d):s.relief_activity={}

static func _events(d:Dictionary)->Dictionary:
	var value:Variant=d.get("campaign",{}).get("staff_relief_events",{})
	return value if value is Dictionary else {}

# A returning reserve no longer supplies the clinical crew, but still owns
# its claim interval. A new reservation starts only after the old one is done.
static func _slot_claimed(d:Dictionary,fid:String,slot:int)->bool:
	for value:Variant in _events(d).values():
		if value is Dictionary and value.get("facility_id","")==fid and value.get("slot_index",-1)==slot and value.get("state","") in ACTIVE:return true
	return false

static func _slot_event(d:Dictionary,fid:String,slot:int)->Dictionary:
	var result:Dictionary={}
	for value:Variant in _events(d).values():
		if not value is Dictionary:continue
		if value.get("facility_id","")!=fid or value.get("slot_index",-1)!=slot or value.get("state","") not in ["walking","covering","draining"] or int(value.get("left_tick",-1))>=0:continue
		if not result.is_empty():return {"invalid":true}
		result=value
	return result

static func slot_owner(d:Dictionary,fid:String,slot:int)->String:
	var f:Dictionary=d.get("facilities",{}).get(fid,{})
	if slot<0 or slot>=f.get("staff_ids",[]).size():return ""
	var event:Dictionary=_slot_event(d,fid,slot) if configured(d) else {}
	return str(event.get("relief_staff_id",f.staff_ids[slot])) if not event.get("invalid",false) else str(f.staff_ids[slot])

static func work_cell(d:Dictionary,fid:String,sid:String)->int:
	var f:Dictionary=d.get("facilities",{}).get(fid,{})
	var place:int=f.get("staff_ids",[]).find(sid)
	if place>=0 and place<f.get("staff_cells",[]).size():return int(f.staff_cells[place])
	if configured(d):
		for event:Dictionary in _events(d).values():
			if event.get("relief_staff_id","")!=sid or event.get("facility_id","")!=fid or event.get("state","") not in ["walking","covering","draining"] or int(event.get("left_tick",-1))>=0:continue
			var index:int=int(event.get("slot_index",-1))
			if index>=0 and index<f.get("staff_cells",[]).size() and int(event.get("work_cell",-1))==int(f.staff_cells[index]):return int(f.staff_cells[index])
	return -1

static func owns(d:Dictionary,sid:String,fid:String)->bool:
	if not configured(d):return false
	var s:Dictionary=d.get("staff",{}).get(sid,{})
	var h:Dictionary=_events(d).get(s.get("relief_activity",{}).get("event_id",""),{})
	return h.get("relief_staff_id","")==sid and h.get("facility_id","")==fid and h.get("state","") in ["covering","draining"] and int(h.get("arrived_tick",-1))>=0 and int(h.get("left_tick",-1))<0 and work_cell(d,fid,sid)>=0

static func active_facility(d:Dictionary,sid:String)->String:
	if not configured(d):return ""
	var s:Dictionary=d.get("staff",{}).get(sid,{})
	var h:Dictionary=_events(d).get(s.get("relief_activity",{}).get("event_id",""),{})
	var fid:String=str(h.get("facility_id",""))
	return fid if owns(d,sid,fid) else ""

static func owns_at(d:Dictionary,sid:String,fid:String,at_tick:int)->bool:
	for h:Dictionary in _events(d).values():
		if h.get("relief_staff_id","")!=sid or h.get("facility_id","")!=fid:continue
		if int(h.get("arrived_tick",-1))>=0 and at_tick>=int(h.arrived_tick) and (int(h.get("left_tick",-1))<0 or at_tick<int(h.left_tick)):return true
	return false

static func effective_crew(d:Dictionary,catalog:ContentCatalog,fid:String,available:bool=false)->Array:
	var f:Dictionary=d.get("facilities",{}).get(fid,{})
	if f.is_empty() or catalog==null:return []
	var roles:Array=catalog.campaign.facilities.get(f.get("kind",""),{}).get("roles",[])
	return resolve_crew(d,f,roles,available,95 if catalog.campaign.facilities.get(f.get("kind",""),{}).get("kind","")!="patient" else 100)

static func resolve_crew(d:Dictionary,f:Dictionary,roles:Array,available:bool=false,fatigue_limit:int=100)->Array:
	var fid:String=str(f.get("id",""))
	var result:Array=[]
	for role:String in roles:
		var found:String=""
		for slot:int in range(f.get("staff_ids",[]).size()):
			var primary:String=str(f.staff_ids[slot])
			var home:Dictionary=d.get("staff",{}).get(primary,{})
			if home.get("role","")!=role or home.get("facility_id","")!=fid:continue
			var h:Dictionary=_slot_event(d,fid,slot) if configured(d) else {}
			if h.get("invalid",false):return []
			var sid:String=str(h.relief_staff_id) if h.get("state","") in ["covering","draining"] and int(h.get("arrived_tick",-1))>=0 else primary
			if sid in result:continue
			var s:Dictionary=d.get("staff",{}).get(sid,{})
			if s.is_empty() or s.get("role","")!=role or s.get("training_order_id","")!="":continue
			if available:
				if h.get("state","")=="draining":return []
				if not s.get("rest_activity",{}).is_empty() or s.get("patient_id","")!="" or s.get("work_order_id","")!="" or int(s.get("fatigue",0))>=fatigue_limit:continue
				if sid!=primary:
					if not owns(d,sid,fid) or int(s.get("cell",-1))!=int(h.work_cell) or int(s.get("move_progress",0))!=0 or int(s.get("fatigue",0))>=64 or int(s.get("morale",70))<45:continue
				elif busy(s):continue
			found=sid;break
		if found=="":return []
		result.append(found)
	return result

static func candidate_reason(d:Dictionary,catalog:ContentCatalog,sid:String,fid:String,owner:String)->String:
	if not enabled(d):return "staff_relief_disabled"
	if sid not in d.campaign.get("staff_relief_pool",[]):return "not_in_relief_pool"
	var s:Dictionary=d.get("staff",{}).get(sid,{})
	var home:Dictionary=d.get("staff",{}).get(owner,{})
	var f:Dictionary=d.get("facilities",{}).get(fid,{})
	if s.is_empty() or home.is_empty() or f.is_empty() or sid==owner:return "unknown_relief_employee"
	var definition:Dictionary=catalog.campaign.facilities.get(f.get("kind",""),{})
	if definition.get("kind","")!="patient" and (not operations_enabled(d) or not _operation_definition_allowed(definition)):return "relief_facility_unavailable"
	if f.get("status","")!="open" or (int(f.get("condition",0))<=0 and definition.get("handler","")!="repair"):return "relief_facility_unavailable"
	if home.get("facility_id","")!=fid or owner not in f.get("staff_ids",[]):return "invalid_relief_primary"
	if home.get("patient_id","")!="" or home.get("work_order_id","")!="" or home.get("training_order_id","")!="":return "primary_busy"
	if s.get("facility_id","")!="" or s.get("role","")!=home.get("role",""):return "relief_role_or_home_mismatch"
	if s.get("patient_id","")!="" or s.get("work_order_id","")!="" or s.get("training_order_id","")!="" or not s.get("rest_activity",{}).is_empty() or busy(s) or int(s.get("move_progress",0))!=0:return "relief_staff_busy"
	if int(s.get("fatigue",0))>=64 or int(s.get("morale",70))<45:return "relief_rest_due"
	var unit:String=str(definition.get("unit_id",""))
	if unit in home.get("skills",[]) and unit not in s.get("skills",[]):return "missing_relief_skill"
	return ""

static func preview(state:ClinicState,catalog:ContentCatalog,fid:String,owner:String)->Dictionary:
	var d:Dictionary=state.data
	var f:Dictionary=d.facilities.get(fid,{})
	var slot:int=f.get("staff_ids",[]).find(owner)
	if slot<0 or slot>=f.get("staff_cells",[]).size():return {"ok":false,"code":"invalid_relief_primary"}
	var goal:int=int(f.staff_cells[slot])
	var candidates:Array=d.campaign.get("staff_relief_pool",[]).duplicate();candidates.sort()
	var best:Dictionary={"ok":false,"code":"no_available_relief"}
	for sid:String in candidates:
		if candidate_reason(d,catalog,sid,fid,owner)!="":continue
		var s:Dictionary=d.staff[sid]
		var blocked:Dictionary=CampaignClinicalFlow._work_positions(d,s,goal)
		# A planned destination may still contain the departing primary. Actual
		# movement below keeps that body/edge blocked until it really vacates.
		blocked.erase(goal)
		var path:Array=GridService.path_avoiding(state,int(s.cell),goal,blocked)
		if path.is_empty():continue
		if not best.ok or path.size()<best.path.size():best={"ok":true,"code":"ok","staff_id":sid,"slot_index":slot,"work_cell":goal,"path":path}
	return best

static func apply(state:ClinicState,catalog:ContentCatalog,type:String,p:Dictionary,_reference:String)->Dictionary:
	var d:Dictionary=state.data
	if not CampaignPeople.autonomy_enabled(d):return CampaignPeople._no("experience_not_enabled")
	if type=="set_staff_relief_operations":
		if p.size()!=1 or not p.get("enabled") is bool:return CampaignPeople._no("invalid_payload")
		if not configured(d):return CampaignPeople._no("staff_relief_disabled")
		d.campaign.staff_relief_operations_version=1;d.campaign.auto_staff_relief_operations=p.enabled
		if not p.enabled:
			for h:Dictionary in _events(d).values():
				if h.state in ["walking","covering"] and catalog.campaign.facilities[h.facility_kind].kind!="patient":_drain(h,int(d.tick),"operation_policy_disabled")
		return CampaignPeople._yes({"enabled":p.enabled,"version":1})
	if type=="set_staff_relief":
		if p.size()!=1 or not p.get("enabled") is bool:return CampaignPeople._no("invalid_payload")
		if not configured(d):
			d.campaign.staff_relief_version=VERSION;d.campaign.staff_relief_pool=[];d.campaign.staff_relief_events={};d.campaign.auto_staff_relief=false
			for s:Dictionary in d.staff.values():s.relief_activity={}
		d.campaign.auto_staff_relief=p.enabled
		if not p.enabled:
			for h:Dictionary in _events(d).values():
				if h.state in ["walking","covering"]:_drain(h,int(d.tick),"policy_disabled")
		return CampaignPeople._yes({"enabled":p.enabled,"version":VERSION})
	if type!="set_staff_relief_reserve" or p.size()!=2 or not p.get("staff_id") is String or not p.get("enabled") is bool:return CampaignPeople._no("invalid_payload")
	if not configured(d):return CampaignPeople._no("staff_relief_disabled")
	var s:Dictionary=d.staff.get(p.staff_id,{})
	if s.is_empty():return CampaignPeople._no("unknown_staff")
	if s.facility_id!="" or s.patient_id!="" or s.work_order_id!="" or s.get("training_order_id","")!="" or not s.get("rest_activity",{}).is_empty() or busy(s) or int(s.move_progress)!=0:return CampaignPeople._no("staff_busy")
	if p.enabled and p.staff_id not in d.campaign.staff_relief_pool:d.campaign.staff_relief_pool.append(p.staff_id);d.campaign.staff_relief_pool.sort()
	elif not p.enabled:d.campaign.staff_relief_pool.erase(p.staff_id)
	return CampaignPeople._yes({"staff_id":p.staff_id,"enabled":p.enabled})

static func _drain(h:Dictionary,tick:int,reason:String)->void:
	if int(h.get("release_requested_tick",-1))<0:h.release_requested_tick=tick;h.release_reason=reason
	h.state="draining"

static func _entering(s:Dictionary,cell:int)->bool:
	var path:Array=s.get("path",[])
	var index:int=int(s.get("path_index",0))
	return int(s.get("move_progress",0))>0 and index+1<path.size() and int(path[index+1])==cell

static func hold_return(d:Dictionary,sid:String)->bool:
	if not configured(d):return false
	for h:Dictionary in _events(d).values():
		if h.owner_staff_id==sid and h.state in ["walking","covering","draining"] and int(h.left_tick)<0:return true
	return false

static func room_busy(d:Dictionary,room_id:String)->bool:
	for h:Dictionary in _events(d).values():
		if h.get("room_id","")==room_id and h.get("state","") in ACTIVE:return true
	return false

static func blocks(d:Dictionary,actor_id:String)->Dictionary:
	var result:Dictionary={}
	if not configured(d):return result
	for s:Dictionary in d.get("staff",{}).values():
		if s.id==actor_id or not busy(s):continue
		if int(s.cell)!=GridService.EXIT_CELL:result[int(s.cell)]=true
		var path:Array=s.path;var index:int=int(s.path_index)
		if int(s.move_progress)>0 and index+1<path.size():result[int(path[index+1])]=true
	return result

static func tick(state:ClinicState,catalog:ContentCatalog)->void:
	var d:Dictionary=state.data
	if not configured(d):return
	var ids:Array=_events(d).keys();ids.sort()
	for id:String in ids:
		var h:Dictionary=_events(d)[id]
		if h.state not in ACTIVE:continue
		var s:Dictionary=d.staff[h.relief_staff_id]
		var rest:Dictionary=d.campaign.staff_rest_events.get(h.rest_event_id,{})
		var f:Dictionary=d.facilities.get(h.facility_id,{})
		if h.state in ["walking","covering"]:
			var definition:Dictionary=catalog.campaign.facilities.get(h.facility_kind,{})
			if not enabled(d) or (definition.get("kind","")!="patient" and not operations_enabled(d)) or rest.get("state","") not in ["walking","using"] or f.get("status","")!="open" or (int(f.get("condition",0))<=0 and definition.get("handler","")!="repair") or int(s.fatigue)>=64 or int(s.morale)<45:_drain(h,int(d.tick),"return_or_unavailable")
		if h.state=="walking":
			s.status="walking";s.phase="walking"
			if CampaignClinicalFlow._walk(state,s,int(h.work_cell)):
				h.arrived_tick=int(d.tick);h.state="covering";s.status="idle";s.phase="idle"
		elif h.state=="draining":
			if s.patient_id!="" or s.work_order_id!="" or s.get("training_order_id","")!="":continue
			s.status="walking";s.phase="walking"
			var arrived:bool=CampaignClinicalFlow._walk(state,s,GridService.EXIT_CELL)
			if int(s.cell)!=int(h.work_cell) and not _entering(s,int(h.work_cell)):
				h.left_tick=int(d.tick);h.state="returning"
			if arrived:h.finished_tick=int(d.tick);h.state="done";s.relief_activity={};s.status="idle";s.phase="idle"
		elif h.state=="returning":
			s.status="walking";s.phase="walking"
			if CampaignClinicalFlow._walk(state,s,GridService.EXIT_CELL):h.finished_tick=int(d.tick);h.state="done";s.relief_activity={};s.status="idle";s.phase="idle"
	claim_pending(state,catalog)

static func claim_pending(state:ClinicState,catalog:ContentCatalog)->void:
	var d:Dictionary=state.data
	if not enabled(d):return
	var fids:Array=d.facilities.keys();fids.sort()
	for fid:String in fids:
		var f:Dictionary=d.facilities[fid]
		if catalog.campaign.facilities[f.kind].kind!="patient" and not _has_pending_operation(d,catalog,fid):continue
		for slot:int in range(f.staff_ids.size()):
			if _slot_claimed(d,fid,slot):continue
			var owner:String=str(f.staff_ids[slot])
			var s:Dictionary=d.staff[owner]
			var rid:String=str(s.get("rest_activity",{}).get("event_id",""))
			var rest:Dictionary=d.campaign.staff_rest_events.get(rid,{})
			if rest.get("state","") not in ["walking","using"]:continue
			var plan:Dictionary=preview(state,catalog,fid,owner)
			if not plan.ok:continue
			var reserve:String=str(plan.staff_id)
			var serial:int=1
			for old:Dictionary in _events(d).values():
				if old.relief_staff_id==reserve:serial+=1
			var id:String="relief:"+reserve+":"+str(serial)
			var unit:String=str(catalog.campaign.facilities[f.kind].unit_id)
			var h:Dictionary={"id":id,"serial":serial,"source":"auto","request_sequence":int(d.command_sequence),"facility_id":fid,"facility_kind":f.kind,"room_id":f.room_id,"unit_id":unit,"owner_staff_id":owner,"relief_staff_id":reserve,"slot_index":slot,"work_cell":int(plan.work_cell),"rest_event_id":rid,"claim_tick":int(d.tick),"claim_cell":int(d.staff[reserve].cell),"required_skill":unit if unit in s.skills else "","arrived_tick":-1,"release_requested_tick":-1,"release_reason":"","left_tick":-1,"finished_tick":-1,"state":"walking","reservations":[]}
			d.campaign.staff_relief_events[id]=h
			d.staff[reserve].relief_activity={"event_id":id}
			d.staff[reserve].path=[];d.staff[reserve].path_index=0;d.staff[reserve].move_progress=0;d.staff[reserve].status="walking";d.staff[reserve].phase="walking"

static func record_reservation(d:Dictionary,p:Dictionary)->void:
	if not configured(d):return
	for sid:String in p.staff_ids:
		if not owns(d,sid,str(p.facility_id)):continue
		var h:Dictionary=_events(d)[d.staff[sid].relief_activity.event_id]
		h.reservations.append({"patient_id":p.id,"step_id":p.steps[p.step_index].id,"reserved_tick":int(d.tick)})


static func record_order(d:Dictionary,order:Dictionary)->void:
	if not operations_configured(d) or order.get("status","")!="walking" or int(order.get("started_tick",-1))>=0:return
	for sid:String in order.staff_ids:
		if not owns(d,sid,str(order.facility_id)):continue
		var h:Dictionary=_events(d)[d.staff[sid].relief_activity.event_id]
		h.reservations.append({"work_order_id":order.id,"reserved_tick":int(d.tick)})
