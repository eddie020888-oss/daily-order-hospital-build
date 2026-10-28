class_name CampaignStaffRest
extends RefCounted

# Self service supply breaks use the existing O25/O26 public service cells.
# The employee retains their job; this is never a fabricated rest room.
const COOLDOWN:int=120
const TIMEOUT:int=600
const RULES:Dictionary={
	"water":{"facility_kind":"O25","needed":60,"cost":2,"resource":"water","quantity":1,"fatigue_relief":32,"morale_relief":8},
	"food":{"facility_kind":"O26","needed":90,"cost":4,"resource":"food","quantity":1,"fatigue_relief":40,"morale_relief":10}
}

static func initialize(d:Dictionary)->void:
	if CampaignPeople.autonomy_enabled(d):d.campaign.staff_rest_events={}

static func busy(s:Dictionary)->bool:
	return not s.get("rest_activity",{}).is_empty()

static func room_busy(d:Dictionary,room_id:String)->bool:
	if not CampaignPeople.autonomy_enabled(d):return false
	for s:Dictionary in d.staff.values():
		if not busy(s):continue
		var h:Dictionary=d.campaign.staff_rest_events.get(s.rest_activity.get("event_id",""),{})
		if s.room_id==room_id or d.facilities.get(h.get("facility_id",""),{}).get("room_id","")==room_id:return true
	return false

static func request(state:ClinicState,catalog:ContentCatalog,payload:Dictionary,reference:String)->Dictionary:
	if not CampaignPeople.autonomy_enabled(state.data):return CampaignPeople._no("experience_not_enabled")
	if payload.size()!=2 or not payload.get("staff_id") is String or not payload.get("need") is String:return CampaignPeople._no("invalid_payload")
	return _request(state,catalog,str(payload.staff_id),str(payload.need),"manual",reference,int(state.data.command_sequence)+1)

static func _request(state:ClinicState,_catalog:ContentCatalog,sid:String,need:String,source:String,reference:String,sequence:int)->Dictionary:
	var d:Dictionary=state.data
	if not d.staff.has(sid) or not RULES.has(need):return CampaignPeople._no("invalid_staff_rest")
	var s:Dictionary=d.staff[sid]
	if busy(s) or CampaignStaffRelief.busy(s) or s.patient_id!="" or s.work_order_id!="" or s.get("training_order_id","")!="" or int(s.move_progress)!=0:return CampaignPeople._no("staff_busy")
	if source=="auto" and int(s.fatigue)<64 and int(s.morale)>=45:return CampaignPeople._no("staff_rest_not_due")
	var serial:int=1
	var last:int=-COOLDOWN
	for h:Dictionary in d.campaign.staff_rest_events.values():
		if h.staff_id!=sid:continue
		serial+=1
		last=maxi(last,maxi(int(h.completed_tick),int(h.canceled_tick)))
	if int(d.tick)-last<COOLDOWN:return CampaignPeople._no("staff_rest_cooldown")
	var rule:Dictionary=RULES[need]
	if CampaignClinicalFlow._available_cash(d)<int(rule.cost) or not CampaignClinicalFlow._stock_ready(d,{"resource":rule.resource,"quantity":rule.quantity}):return CampaignPeople._no("staff_rest_missing_resources")
	var chosen:String=""
	var goal:int=-1
	var distance:int=2147483647
	var ids:Array=d.facilities.keys();ids.sort()
	for fid:String in ids:
		var f:Dictionary=d.facilities[fid]
		if f.kind!=rule.facility_kind or f.status!="open" or int(f.condition)<=0 or f.service_cells.is_empty() or CampaignPeople.facility_busy(d,fid):continue
		var cell:int=int(f.service_cells[0])
		var path:Array=GridService.path_avoiding(state,int(s.cell),cell,CampaignClinicalFlow._work_positions(d,s,cell))
		if path.is_empty():continue
		if path.size()<distance:chosen=fid;goal=cell;distance=path.size()
	if chosen=="":return CampaignPeople._no("staff_rest_facility_unreachable")
	var home:Dictionary=d.facilities.get(s.facility_id,{})
	var return_cell:int=GridService.EXIT_CELL
	if not home.is_empty():
		var place:int=home.staff_ids.find(sid)
		if place<0 or place>=home.staff_cells.size():return CampaignPeople._no("staff_rest_invalid_workplace")
		return_cell=int(home.staff_cells[place])
	var id:String="rest:"+sid+":"+str(serial)
	var h:Dictionary={"id":id,"staff_id":sid,"serial":serial,"need":need,"source":source,"request_reference":reference if source=="manual" else "auto_rest:"+sid+":"+str(serial),"request_sequence":sequence,"requested_tick":int(d.tick),"request_cell":int(s.cell),"move_ticks":int(s.move_ticks),"facility_id":chosen,"facility_kind":str(rule.facility_kind),"target_cell":goal,"workplace_id":str(s.facility_id),"return_cell":return_cell,"state":"walking","started_tick":-1,"completed_tick":-1,"canceled_tick":-1,"departed_tick":-1,"returned_tick":-1,"needed":int(rule.needed),"cost":int(rule.cost),"resource":str(rule.resource),"quantity":int(rule.quantity),"fatigue_before":-1,"fatigue_after":-1,"request_fatigue":int(s.fatigue),"request_morale":int(s.morale)}
	d.campaign.staff_rest_events[id]=h
	s.rest_activity={"event_id":id,"processed_tick":-1}
	s.status="walking";s.phase="walking"
	d.campaign.people_reservations[chosen+":0"]=sid
	return CampaignPeople._yes({"staff_id":sid,"need":need,"event_id":id,"facility_id":chosen,"target_cell":goal,"request_cell":int(s.cell),"return_cell":return_cell})

static func tick_all(state:ClinicState,catalog:ContentCatalog)->void:
	var d:Dictionary=state.data
	if not CampaignPeople.autonomy_enabled(d):return
	var ids:Array=d.staff.keys();ids.sort()
	for sid:String in ids:
		if busy(d.staff[sid]):_tick(state,d.staff[sid])
	# Existing work finishes before this phase. Each replacement walks once,
	# then ordinary staff movement skips its active, durable handoff pointer.
	CampaignStaffRelief.tick(state,catalog)
	if not d.campaign.auto_staff_rest:return
	for sid:String in ids:
		var s:Dictionary=d.staff[sid]
		if busy(s) or CampaignStaffRelief.busy(s) or s.patient_id!="" or s.work_order_id!="" or s.get("training_order_id","")!="" or int(s.move_progress)!=0:continue
		if int(s.fatigue)<64 and int(s.morale)>=45:continue
		for need:String in RULES:
			if _request(state,catalog,sid,need,"auto","",int(d.command_sequence)).ok:break
	CampaignStaffRelief.claim_pending(state,catalog)

static func _tick(state:ClinicState,s:Dictionary)->void:
	var d:Dictionary=state.data
	var a:Dictionary=s.rest_activity
	if int(a.processed_tick)==int(d.tick):return
	a.processed_tick=int(d.tick)
	var h:Dictionary=d.campaign.staff_rest_events[a.event_id]
	if h.state=="walking":
		var f:Dictionary=d.facilities.get(h.facility_id,{})
		if f.is_empty() or f.status!="open" or int(f.condition)<=0 or int(d.tick)-int(h.requested_tick)>TIMEOUT:
			h.canceled_tick=int(d.tick);h.state="returning"
			return
		else:
			s.status="walking";s.phase="walking"
			if not CampaignClinicalFlow._walk(state,s,int(h.target_cell)):return
			if CampaignClinicalFlow._available_cash(d)<int(h.cost) or not CampaignClinicalFlow._stock_ready(d,{"resource":h.resource,"quantity":h.quantity}):return
			if not CampaignFinance.post(d,"operations",-int(h.cost),str(h.id)):return
			d.resources[h.resource]-=int(h.quantity)
			h.started_tick=int(d.tick);h.state="using"
			s.status="resting";s.phase="resting"
			return
	if h.state=="using":
		s.status="resting";s.phase="resting"
		if int(d.tick)-int(h.started_tick)<int(h.needed):return
		var rule:Dictionary=RULES[h.need]
		h.fatigue_before=int(s.fatigue);h.fatigue_after=maxi(0,int(s.fatigue)-int(rule.fatigue_relief))
		s.fatigue=h.fatigue_after
		h.completed_tick=int(d.tick);h.state="returning"
		CampaignPeople.on_staff_rest_completed(d,str(s.id),str(h.id),int(rule.morale_relief))
		s.status="walking";s.phase="walking"
		return
	if h.state=="returning":
		s.status="walking";s.phase="walking"
		# Retain the original return cell and shared supply reservation. Waiting
		# at the actual supply point avoids a head-on swap in a narrow doorway.
		if CampaignStaffRelief.hold_return(d,str(s.id)):return
		var arrived:bool=CampaignClinicalFlow._walk(state,s,int(h.return_cell))
		var route:Array=s.path
		var index:int=int(s.path_index)
		var entering:bool=int(s.move_progress)>0 and index+1<route.size() and int(route[index+1])==int(h.target_cell)
		if h.departed_tick<0 and int(s.cell)!=int(h.target_cell) and not entering:
			h.departed_tick=int(d.tick)
			if d.campaign.people_reservations.get(str(h.facility_id)+":0","")==s.id:d.campaign.people_reservations.erase(str(h.facility_id)+":0")
		if arrived:
			h.returned_tick=int(d.tick);h.state="done" if int(h.completed_tick)>=0 else "canceled"
			s.rest_activity={};s.status="idle";s.phase="idle"

static func blockers(d:Dictionary,actor_id:String)->Dictionary:
	var result:Dictionary={}
	for s:Variant in d.get("staff",{}).values():
		if not s is Dictionary or s.get("id","")==actor_id or not s.get("rest_activity") is Dictionary or s.rest_activity.is_empty():continue
		var h:Variant=d.campaign.get("staff_rest_events",{}).get(s.rest_activity.get("event_id",""),{})
		if not h is Dictionary:continue
		if h.get("departed_tick",-1)<0 and h.get("target_cell") is int:result[h.target_cell]=true
		if s.get("cell") is int:result[s.cell]=true
		var route:Variant=s.get("path",[])
		var index:Variant=s.get("path_index",0)
		if route is Array and index is int and int(s.get("move_progress",0))>0 and index+1<route.size():result[route[index+1]]=true
	return result

static func finance_expected(d:Dictionary)->Dictionary:
	var result:Dictionary={}
	var records:Variant=d.get("campaign",{}).get("staff_rest_events",{})
	if not records is Dictionary:return result
	for h:Variant in records.values():
		if h is Dictionary and h.get("started_tick") is int and h.started_tick>=0 and h.get("id") is String and h.get("cost") is int:result["operations|"+str(h.id)]={"tick":h.started_tick,"amount":-int(h.cost)}
	return result

static func resource_events(d:Dictionary)->Array:
	var result:Array=[]
	var records:Variant=d.get("campaign",{}).get("staff_rest_events",{})
	if not records is Dictionary:return result
	for h:Variant in records.values():
		if not h is Dictionary or not h.get("started_tick") is int or h.started_tick<0 or not h.get("resource") is String or not h.get("quantity") is int or not h.get("id") is String:continue
		result.append({"tick":h.started_tick,"resource":h.resource,"quantity":h.quantity,"reference":h.id,"ledger_index":-1})
	return result

# All new-hospital fatigue is derived from real completed work and breaks.
# This helper is deliberately pure and does not trust an event's before/after.
static func fatigue_at(d:Dictionary,sid:String,at_tick:int,exclude_rest:String="")->int:
	var events:Array=[]
	for p:Dictionary in d.patients.values():
		for h:Dictionary in p.step_history:
			if h.kind=="patient" and int(h.completed_tick)>=0 and int(h.completed_tick)<=at_tick and sid in h.staff_ids:events.append({"tick":int(h.completed_tick),"rank":0,"reference":"care:"+str(p.id)+":"+str(h.step_id),"delta":8})
	for order:Dictionary in d.work_orders.values():
		if order.status!="done" or int(order.completed_tick)>at_tick or sid not in order.staff_ids:continue
		events.append({"tick":int(order.completed_tick),"rank":2,"reference":str(order.id),"delta":8})
		if order.handler=="roster":events.append({"tick":int(order.completed_tick),"rank":3,"reference":str(order.id),"delta":-25})
	var records:Variant=d.campaign.get("staff_rest_events",{})
	if records is Dictionary:
		for h:Variant in records.values():
			if not h is Dictionary or h.get("staff_id","")!=sid or h.get("id","")==exclude_rest or not h.get("completed_tick") is int or h.completed_tick<0 or h.completed_tick>at_tick or not RULES.has(h.get("need","")):continue
			events.append({"tick":int(h.completed_tick),"rank":1,"reference":str(h.get("id","")),"delta":-int(RULES[h.need].fatigue_relief)})
	events.sort_custom(func(a:Dictionary,b:Dictionary)->bool:
		if a.tick!=b.tick:return a.tick<b.tick
		if a.rank!=b.rank:return a.rank<b.rank
		return str(a.reference)<str(b.reference))
	var fatigue:int=0
	for e:Dictionary in events:fatigue=clampi(fatigue+int(e.delta),0,100)
	return fatigue
