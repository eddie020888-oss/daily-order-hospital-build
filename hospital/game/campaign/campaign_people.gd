class_name CampaignPeople
extends RefCounted

# Optional additive behavior. Missing people_version is the exact legacy path.
const VERSION:int=1
const GROWTH_TICKS:int=100
const RELIEF:int=60
const COOLDOWN:int=300
const TIMEOUT:int=600
const NEEDS:Dictionary={
	"water":{"facility_kind":"O25","needed":20,"resource":"water","quantity":1,"cost":2},
	"food":{"facility_kind":"O26","needed":30,"resource":"food","quantity":1,"cost":4},
	"toilet":{"facility_kind":"O27","needed":40,"resource":"","quantity":0,"cost":1}
}

static func enabled(d:Dictionary)->bool:
	return d.get("schema_version",0)==3 and d.get("ruleset","")=="full-hospital-v2" and d.get("campaign",{}).get("people_version",0)==VERSION

static func autonomy_enabled(d:Dictionary)->bool:
	return enabled(d) and CampaignExperience.enabled(d)

static func staff_busy(s:Dictionary)->bool:
	return not s.get("rest_activity",{}).is_empty()

static func patience_penalty(d:Dictionary,p:Dictionary)->int:
	if not enabled(d):return 0
	# Patience can be inspected before the strict people save validator runs.
	# Invalid shapes remain its responsibility; this pure helper never casts them.
	var needs:Variant=p.get("needs",{})
	if not needs is Dictionary:return 0
	var total:int=0
	for key:String in NEEDS:
		var value:Variant=needs.get(key,0)
		if value is int:
			total+=maxi(0,clampi(value,0,100)-40)*10
	return mini(600,total)

static func rest_interval(d:Dictionary,s:Dictionary)->int:
	if not enabled(d):return 20
	var morale:Variant=s.get("morale",70)
	return 40 if morale is int and morale<40 else 20

static func init_campaign(d:Dictionary)->void:
	if d.get("schema_version",0)!=3 or d.get("ruleset","")!="full-hospital-v2":return
	d.campaign.people_version=VERSION
	d.campaign.people_reservations={}
	if autonomy_enabled(d):
		d.campaign.auto_patient_needs=true
		d.campaign.auto_staff_rest=true
		CampaignStaffRest.initialize(d)

static func init_patient(d:Dictionary,p:Dictionary)->void:
	if not enabled(d):return
	p.needs=initial_needs(str(p.id))
	p.need_history=[]
	p.need_activity={}

static func init_staff(d:Dictionary,s:Dictionary)->void:
	if not enabled(d):return
	s.people_hired_tick=int(d.tick)
	s.morale=70
	s.wage_percent=100
	s.wellbeing_history=[]
	s.salary_request={}
	if autonomy_enabled(d):s.rest_activity={}
	CampaignStaffRelief.init_staff(d,s)

static func initial_needs(id:String)->Dictionary:
	var number:int=int(id.get_slice("_",1))
	return {"water":30+number%7,"food":25+number%5,"toilet":20+number%3}

static func needs_at(p:Dictionary,at_tick:int)->Dictionary:
	var result:Dictionary=initial_needs(str(p.id))
	var previous:int=int(p.arrived_tick)
	for item:Variant in p.get("need_history",[]):
		if not item is Dictionary:continue
		var h:Dictionary=item
		var end:int=int(h.get("completed_tick",-1))
		if end<0 or end>at_tick:continue
		var growth:int=int((end-int(p.arrived_tick))/GROWTH_TICKS)-int((previous-int(p.arrived_tick))/GROWTH_TICKS)
		for key:String in NEEDS:result[key]=mini(100,int(result[key])+growth)
		var kind:String=str(h.get("need",""))
		if NEEDS.has(kind):result[kind]=maxi(0,int(result[kind])-RELIEF)
		previous=end
	var growth:int=int((at_tick-int(p.arrived_tick))/GROWTH_TICKS)-int((previous-int(p.arrived_tick))/GROWTH_TICKS)
	for key:String in NEEDS:result[key]=mini(100,int(result[key])+growth)
	return result

static func _yes(data:Dictionary={})->Dictionary:return {"ok":true,"code":"ok","data":data}
static func _no(code:String)->Dictionary:return {"ok":false,"code":code,"data":{}}

static func apply(state:ClinicState,catalog:ContentCatalog,type:String,p:Dictionary,reference:String)->Dictionary:
	if not enabled(state.data):return _no("people_model_disabled")
	match type:
		"request_patient_need":return _request_need(state,catalog,p,reference)
		"set_staff_wage":return _raise(state.data,catalog,p,reference)
		"set_people_autonomy":return set_autonomy(state,p)
		"request_staff_rest":return CampaignStaffRest.request(state,catalog,p,reference)
	return _no("unknown_people_command")

static func set_autonomy(state:ClinicState,payload:Dictionary)->Dictionary:
	if not autonomy_enabled(state.data):return _no("experience_not_enabled")
	if payload.size()!=2 or not payload.get("patient_needs") is bool or not payload.get("staff_rest") is bool:return _no("invalid_payload")
	state.data.campaign.auto_patient_needs=payload.patient_needs
	state.data.campaign.auto_staff_rest=payload.staff_rest
	return _yes({"patient_needs":payload.patient_needs,"staff_rest":payload.staff_rest})

static func maybe_auto_patient(state:ClinicState,catalog:ContentCatalog,p:Dictionary)->bool:
	var d:Dictionary=state.data
	if not autonomy_enabled(d) or not d.campaign.auto_patient_needs or int(d.tick)%20!=0:return false
	if p.phase!="care_queue" or p.slot_id!="" or p.support_order_id!="" or int(p.move_progress)!=0 or not p.need_activity.is_empty():return false
	var needs:Dictionary=needs_at(p,int(d.tick))
	var chosen:String=""
	var highest:int=39
	for key:String in NEEDS:
		if int(needs[key])>highest:highest=int(needs[key]);chosen=key
	if chosen=="":return false
	var reference:String="auto_need:"+str(p.id)+":"+str(p.need_history.size()+1)
	return bool(_request_need(state,catalog,{"patient_id":p.id,"need":chosen},reference,"auto",int(d.command_sequence)).ok)

static func _request_need(state:ClinicState,_catalog:ContentCatalog,payload:Dictionary,reference:String,source:String="manual",request_sequence:int=-1)->Dictionary:
	var d:Dictionary=state.data
	if not payload.get("patient_id") is String or not payload.get("need") is String:return _no("invalid_payload")
	if not d.patients.has(payload.patient_id) or not NEEDS.has(payload.need):return _no("invalid_personal_need")
	var p:Dictionary=d.patients[payload.patient_id]
	if p.phase!="care_queue" or p.slot_id!="" or p.support_order_id!="" or int(p.move_progress)!=0 or not p.need_activity.is_empty():return _no("patient_busy")
	# A completed examination can still be waiting for a genuine clinical
	# decision; the treatment plan is extended only after that decision.
	var pending_gate:bool=CampaignClinicalDecisions.enabled(d) and p.get("clinical_decision",{}).get("state","")=="pending"
	if int(p.step_index)>=p.steps.size() and not pending_gate:return _no("patient_finished_care")
	p.needs=needs_at(p,int(d.tick))
	if int(p.needs[payload.need])<20:return _no("need_not_due")
	var last:int=-COOLDOWN
	for h:Dictionary in p.need_history:
		if not autonomy_enabled(d) and int(h.step_index)==int(p.step_index):return _no("need_already_used_this_step")
		last=maxi(last,maxi(int(h.get("completed_tick",-1)),int(h.get("canceled_tick",-1))))
	if int(d.tick)-last<COOLDOWN:return _no("need_cooldown")
	var rule:Dictionary=NEEDS[payload.need]
	var chosen:String=""
	var goal:int=-1
	var distance:int=2147483647
	var ids:Array=d.facilities.keys();ids.sort()
	for fid:String in ids:
		var f:Dictionary=d.facilities[fid]
		if f.kind!=rule.facility_kind or f.status!="open" or int(f.condition)<=0 or f.service_cells.is_empty():continue
		if facility_busy(d,fid):continue
		var cell:int=int(f.service_cells[0])
		var physical:Dictionary=CampaignClinicalFlow._work_positions(d,p,cell)
		var path:Array=GridService.path_avoiding(state,int(p.cell),cell,physical)
		if path.is_empty():continue
		if path.size()<distance:chosen=fid;goal=cell;distance=path.size()
	if chosen=="":return _no("need_facility_unreachable:"+str(rule.facility_kind))
	var serial:int=p.need_history.size()+1
	var id:String="need:"+str(p.id)+":"+str(serial)
	var h:Dictionary={"id":id,"serial":serial,"need":payload.need,"facility_id":chosen,"facility_kind":rule.facility_kind,"target_cell":goal,"requested_tick":int(d.tick),"request_reference":reference,"request_cell":int(p.cell),"move_ticks":int(p.move_ticks),"step_index":int(p.step_index),"state":"walking","started_tick":-1,"completed_tick":-1,"departed_tick":-1,"canceled_tick":-1,"needed":int(rule.needed),"cost":int(rule.cost),"resource":str(rule.resource),"quantity":int(rule.quantity),"need_before":-1,"need_after":-1}
	if autonomy_enabled(d):
		h.source=source
		h.request_sequence=int(d.command_sequence)+1 if request_sequence<0 else request_sequence
	p.need_history.append(h)
	p.need_activity={"history_index":serial-1,"facility_id":chosen,"target_cell":goal,"state":"walking","processed_tick":-1}
	d.campaign.people_reservations[chosen+":0"]=p.id
	return _yes({"patient_id":p.id,"need":payload.need,"activity_id":id,"facility_id":chosen,"target_cell":goal,"request_cell":int(p.cell),"move_ticks":int(p.move_ticks)})

static func patient_busy(p:Dictionary)->bool:
	return p.get("need_activity",{}).get("state","") in ["walking","using"]

static func _cancel(d:Dictionary,p:Dictionary,h:Dictionary,reason:String)->void:
	h.canceled_tick=int(d.tick);h.state="departing"
	p.need_activity.state="departing"
	p.wait_reason=reason

static func tick_patient(state:ClinicState,_catalog:ContentCatalog,p:Dictionary)->bool:
	var d:Dictionary=state.data
	if not enabled(d):return false
	var end:int=int(p.completed_tick) if int(p.get("completed_tick",-1))>=0 else int(d.tick)
	p.needs=needs_at(p,end)
	if p.need_activity.is_empty():return false
	var a:Dictionary=p.need_activity
	if int(a.get("processed_tick",-1))==int(d.tick):return patient_busy(p)
	a.processed_tick=int(d.tick)
	var h:Dictionary=p.need_history[int(a.history_index)]
	if a.state=="departing":return false
	if a.state=="walking":
		var f:Dictionary=d.facilities.get(a.facility_id,{})
		if p.phase!="care_queue" or f.is_empty() or f.status!="open" or int(f.condition)<=0 or int(d.tick)-int(h.requested_tick)>TIMEOUT:
			_cancel(d,p,h,"personal_need_canceled");return false
		if not CampaignClinicalFlow._walk(state,p,int(a.target_cell)):return true
		if autonomy_enabled(d):
			if CampaignClinicalFlow._available_cash(d)<int(h.cost):p.wait_reason="need_insufficient_cash";return true
			if h.resource!="" and not CampaignClinicalFlow._stock_ready(d,{"resource":h.resource,"quantity":h.quantity}):p.wait_reason="need_missing_resource:"+str(h.resource);return true
		if h.resource!="" and int(d.resources.get(h.resource,0))<int(h.quantity):p.wait_reason="need_missing_resource:"+str(h.resource);return true
		if not CampaignFinance.post(d,"operations",-int(h.cost),str(h.id)):p.wait_reason="need_insufficient_cash";return true
		if h.resource!="":d.resources[h.resource]-=int(h.quantity)
		h.started_tick=int(d.tick);h.state="using";a.state="using";p.wait_reason="personal_need_using"
		return true
	if a.state=="using":
		if int(d.tick)-int(h.started_tick)<int(h.needed):return true
		# Only now does this patient's need recover. Paid use safely finishes
		# its latched clock even if the machine breaks after service started.
		h.need_before=int(p.needs[h.need]);h.need_after=maxi(0,int(h.need_before)-RELIEF)
		h.completed_tick=int(d.tick);h.state="departing";a.state="departing"
		p.needs=needs_at(p,end);p.wait_reason=""
		return false
	return false

static func release_departed(d:Dictionary,p:Dictionary)->void:
	if not enabled(d) or p.get("need_activity",{}).is_empty():return
	var a:Dictionary=p.need_activity
	if a.get("state","")!="departing":return
	var cell:int=int(a.target_cell)
	var route:Array=p.get("path",[])
	var index:int=int(p.get("path_index",0))
	var entering:bool=int(p.get("move_progress",0))>0 and index+1<route.size() and int(route[index+1])==cell
	if int(p.cell)==cell or entering:return
	var h:Dictionary=p.need_history[int(a.history_index)]
	h.departed_tick=int(d.tick);h.state="done" if int(h.completed_tick)>=0 else "canceled"
	var key:String=str(a.facility_id)+":0"
	if d.campaign.people_reservations.get(key,"")==p.id:d.campaign.people_reservations.erase(key)
	p.need_activity={}

static func blockers(d:Dictionary,actor_id:String,_goal:int=-1)->Dictionary:
	var result:Dictionary={}
	if not enabled(d):return result
	for owner:Variant in d.campaign.people_reservations.values():
		if not owner is String or owner==actor_id or not d.patients.has(owner):continue
		var a:Dictionary=d.patients[owner].get("need_activity",{})
		if not a.is_empty():result[int(a.target_cell)]=true
	if autonomy_enabled(d):result.merge(CampaignStaffRest.blockers(d,actor_id),true)
	return result

static func facility_busy(d:Dictionary,facility_id:String)->bool:
	return enabled(d) and d.campaign.get("people_reservations",{}).has(facility_id+":0")

static func _project_staff(events:Array,id:String)->Dictionary:
	var morale:int=70
	var percent:int=100
	var request:Dictionary={}
	for index:int in range(events.size()):
		var e:Dictionary=events[index]
		morale=clampi(morale+int(e.delta),0,100)
		if e.kind=="raise":
			percent=int(e.percent)
			if request.get("status","")=="pending" and percent>=int(request.proposed_percent):
				request.status="accepted";request.resolved_tick=e.tick;request.resolution_reference=e.reference
		if e.kind!="raise" and morale<40 and percent<150 and request.get("status","")!="pending":
			request={"id":"raise:"+id+":"+str(index+1),"status":"pending","requested_tick":e.tick,"proposed_percent":percent+10,"source_reference":e.reference,"resolved_tick":-1,"resolution_reference":""}
	return {"morale":morale,"percent":percent,"request":request}

static func _staff_event(d:Dictionary,sid:String,kind:String,reference:String,delta:int,percent:int=0)->void:
	if not enabled(d) or not d.staff.has(sid):return
	var s:Dictionary=d.staff[sid]
	for prior:Dictionary in s.wellbeing_history:
		if prior.kind==kind and prior.reference==reference:return
	var e:Dictionary={"kind":kind,"reference":reference,"tick":int(d.tick),"delta":delta,"percent":percent,"sequence":int(d.command_sequence)+1 if kind=="raise" else 0}
	s.wellbeing_history.append(e)
	var projected:Dictionary=_project_staff(s.wellbeing_history,sid)
	s.morale=projected.morale;s.wage_percent=projected.percent;s.salary_request=projected.request

static func _raise(d:Dictionary,catalog:ContentCatalog,payload:Dictionary,reference:String)->Dictionary:
	if not payload.get("staff_id") is String or not payload.get("percent") is int:return _no("invalid_payload")
	if not d.staff.has(payload.staff_id):return _no("unknown_staff")
	var s:Dictionary=d.staff[payload.staff_id]
	var percent:int=int(payload.percent)
	if percent not in [110,120,130,140,150] or percent<=int(s.wage_percent):return _no("invalid_wage_raise")
	_staff_event(d,str(s.id),"raise",reference,8,percent)
	return _yes({"staff_id":s.id,"percent":percent,"daily_wage":staff_daily_wage(d,catalog,s)})

static func staff_daily_wage(d:Dictionary,catalog:ContentCatalog,s:Dictionary)->int:
	var base:int=int(catalog.campaign.roles[s.role].daily_wage)
	return CampaignExperience.daily_wage(d,base,int(s.get("wage_percent",100)) if enabled(d) else 100)

static func on_staff_rest_completed(d:Dictionary,staff_id:String,reference:String,delta:int)->void:
	_staff_event(d,staff_id,"rest",reference,delta)

static func on_staff_work_completed(d:Dictionary,staff_id:String,reference:String)->void:
	_staff_event(d,staff_id,"work",reference,-1)

static func on_roster_completed(d:Dictionary,order:Dictionary)->void:
	if not enabled(d):return
	for sid:String in order.get("staff_ids",[]):
		on_staff_work_completed(d,sid,"operation:"+str(order.id))
		_staff_event(d,sid,"roster","roster:"+str(order.id),5)

static func on_payroll(d:Dictionary,_catalog:ContentCatalog,paid:bool)->void:
	if not enabled(d):return
	var ids:Array=d.staff.keys();ids.sort()
	for sid:String in ids:_staff_event(d,sid,"payroll","payroll:"+str(d.tick),1 if paid else -8)

static func finance_expected(d:Dictionary)->Dictionary:
	var result:Dictionary={}
	if not enabled(d):return result
	# This helper is called before the strict people validator. Malformed
	# history must reach its rejection instead of causing a typed-loop error.
	for patient:Variant in d.get("patients",{}).values():
		if not patient is Dictionary or not patient.get("need_history") is Array:continue
		for item:Variant in patient.need_history:
			if not item is Dictionary:continue
			if not item.get("started_tick") is int or not item.get("id") is String or not item.get("cost") is int:continue
			if item.started_tick>=0:result["operations|"+item.id]={"tick":item.started_tick,"amount":-item.cost}
	if autonomy_enabled(d):result.merge(CampaignStaffRest.finance_expected(d),true)
	return result

static func resource_events(d:Dictionary)->Array:
	var result:Array=[]
	if not enabled(d):return result
	for patient:Variant in d.get("patients",{}).values():
		if not patient is Dictionary or not patient.get("need_history") is Array:continue
		for item:Variant in patient.need_history:
			if not item is Dictionary:continue
			if not item.get("started_tick") is int or not item.get("resource") is String or not item.get("quantity") is int or not item.get("id") is String:continue
			if item.started_tick<0 or item.resource=="":continue
			var ledger_index:int=-1
			for index:int in range(d.ledger_entries.size()):
				var entry:Variant=d.ledger_entries[index]
				if entry is Dictionary and entry.get("reference")==item.id:ledger_index=index;break
			result.append({"tick":item.started_tick,"resource":item.resource,"quantity":item.quantity,"reference":item.id,"ledger_index":ledger_index})
	if autonomy_enabled(d):result.append_array(CampaignStaffRest.resource_events(d))
	return result

static func info_patient(d:Dictionary,p:Dictionary)->Dictionary:
	if not enabled(d):return {"enabled":false}
	var end:int=int(p.completed_tick) if int(p.get("completed_tick",-1))>=0 else int(d.tick)
	return {"enabled":true,"needs":needs_at(p,end),"activity":p.need_activity.duplicate(true),"history_count":p.need_history.size(),"manual_request":true,"auto_enabled":autonomy_enabled(d) and bool(d.campaign.get("auto_patient_needs",false))}

static func info_staff(d:Dictionary,s:Dictionary)->Dictionary:
	if not enabled(d):return {"enabled":false}
	var result:Dictionary={"enabled":true,"morale":s.morale,"wage_percent":s.wage_percent,"salary_request":s.salary_request.duplicate(true),"rest_scope":"Existing idle fatigue recovery and actual participating roster worker only; no fabricated rest-room travel."}
	if autonomy_enabled(d):
		result.auto_enabled=bool(d.campaign.auto_staff_rest)
		result.rest_activity=s.get("rest_activity",{}).duplicate(true)
		result.active_rest=d.campaign.staff_rest_events.get(s.get("rest_activity",{}).get("event_id",""),{}).duplicate(true)
		result.rest_scope="Actual paid water or food supply break, then physical return to the retained workplace."
	return result
