extends RefCounted

# Transient UI coordinator. Only existing public hire/assign commands commit.
signal changed
signal action_finished(result:Dictionary)
var session:GameSession
var facility_id:String=""
var _owner:Simulation
var _generation:int=0
var _pending:Dictionary={}
var _working:bool=false
var _failure:Dictionary={}
var _recovery:Dictionary={}
var _cache_key:String=""
var _cache:Dictionary={}

func initialize(value:GameSession)->void:session=value

func open(id:String)->bool:
	close()
	if session==null or session.storage_blocked or session._background or not session.is_campaign():return false
	var d:Dictionary=session.presentation_snapshot()
	if not d.facilities.has(id) or d.challenge.status!="running":return false
	_owner=session.sim;facility_id=id
	if _recovery.get("owner")!=_owner:_recovery.clear()
	return true

func close()->void:
	_generation+=1;_pending.clear();facility_id="";_owner=null;_failure={};_cache_key=""

func _clone(d:Dictionary)->ClinicState:
	var state:=ClinicState.new();state.data=d.duplicate(true);return state

func _name(d:Dictionary,sid:String,role_name:String)->String:
	var display:String=str(d.staff[sid].get("display_name",""))
	return display if display!="" else role_name+" "+sid.trim_prefix("staff_")

func view(snapshot:Dictionary={},fresh:bool=false)->Dictionary:
	if session==null or _owner!=session.sim or session._background or facility_id=="":return {"active":false}
	var d:Dictionary=snapshot if not snapshot.is_empty() else session.presentation_snapshot()
	var key:String=JSON.stringify([d.command_sequence,int(d.tick)/10,facility_id,_working,_pending.is_empty(),session.storage_blocked,_failure,_recovery.get("staff_id","")])
	if not fresh and key==_cache_key:return _cache
	var f:Dictionary=d.facilities.get(facility_id,{})
	if f.is_empty():return {"active":false,"code":"unknown_facility"}
	var definition:Dictionary=session.catalog.campaign.facilities[f.kind]
	var missing:Array=definition.roles.duplicate()
	for sid:String in f.staff_ids:
		var employee:Dictionary=d.staff.get(sid,{})
		if employee.get("facility_id","")==facility_id and employee.get("role","") in missing:missing.erase(employee.role)
	var role:String=str(missing[0]) if not missing.is_empty() else ""
	var role_data:Dictionary=session.catalog.campaign.roles.get(role,{})
	var role_name:String=str(role_data.get("name",role))
	var result:Dictionary={"active":true,"facility_id":facility_id,"facility_name":definition.name,"role":role,"role_name":role_name,"missing_count":missing.count(role),"missing_roles":missing,"complete":missing.is_empty(),"candidates":[],"mode":"complete" if missing.is_empty() else "hire","hire_cost":int(role_data.get("hire_cost",0)),"daily_wage":0,"cash":d.cash,"busy":_working or not _pending.is_empty(),"can_fill":false,"failure":_failure.duplicate(true),"retained_staff_id":""}
	if role!="":result.daily_wage=CampaignPeople.staff_daily_wage(d,session.catalog,{"role":role,"wage_percent":100})
	if not _recovery.is_empty() and _recovery.get("owner")==_owner and _recovery.get("facility_id","")==facility_id:
		var retained:Dictionary=d.staff.get(_recovery.get("staff_id",""),{})
		if retained.is_empty() or retained.get("facility_id","")!="":_recovery.clear()
		else:result.retained_staff_id=retained.id
	var ids:Array=d.staff.keys();ids.sort()
	for sid:String in ids:
		var employee:Dictionary=d.staff[sid]
		if employee.get("facility_id","")!="" or employee.role!=role or int(employee.get("fatigue",0))>=95:continue
		var probe:Dictionary=CampaignCommands._assign(_clone(d),session.catalog,{"staff_id":sid,"facility_id":facility_id})
		if not probe.get("ok",false):continue
		result.candidates.append({"id":sid,"name":_name(d,sid,role_name),"daily_wage":CampaignPeople.staff_daily_wage(d,session.catalog,employee)})
	if result.retained_staff_id!="":
		result.mode="recovery"
		for item:Dictionary in result.candidates:
			if item.id==result.retained_staff_id:result.can_fill=true
		result.candidates=result.candidates.filter(func(item:Dictionary)->bool:return item.id==result.retained_staff_id)
	elif not result.candidates.is_empty():result.mode="existing";result.can_fill=true
	elif role!="":
		# Backend validation in a detached preview catches staff limit, cash and
		# exact assignment/path rules before a real recruitment is offered.
		var state:ClinicState=_clone(d)
		var hired:Dictionary=CampaignCommands._hire(state.data,session.catalog,{"role":role},"staffing-preview")
		var ready:Dictionary=hired
		if hired.get("ok",false):ready=CampaignCommands._assign(state,session.catalog,{"staff_id":hired.data.staff_id,"facility_id":facility_id})
		result.can_fill=ready.get("ok",false)
		result["unavailable"]=ready if not ready.get("ok",false) else {}
	result.can_fill=bool(result.can_fill) and not session.storage_blocked and d.challenge.status=="running" and not result.busy
	_cache_key=key;_cache=result
	return result

func request_fill(mode:String,staff_id:String="")->void:
	if _working or not _pending.is_empty() or facility_id=="" or _owner!=session.sim:return
	var plan:Dictionary=view({},true)
	if not plan.get("active",false) or plan.get("complete",true) or not plan.get("can_fill",false):return
	if mode!=str(plan.mode):_failure={"ok":false,"code":"staffing_changed_review"};_cache_key="";changed.emit();return
	if mode in ["existing","recovery"]:
		var found:bool=false
		for item:Dictionary in plan.candidates:
			if item.id==staff_id:found=true
		if not found:return
	_pending={"generation":_generation,"owner":_owner,"facility_id":facility_id,"role":plan.role,"mode":mode,"staff_id":staff_id}
	_cache_key="";changed.emit()
	_flush.call_deferred(_generation)

func _flush(generation:int)->void:
	if generation!=_generation or _pending.is_empty():return
	var action:Dictionary=_pending.duplicate();_pending.clear()
	if action.owner!=session.sim or _owner!=session.sim or action.facility_id!=facility_id:return
	var plan:Dictionary=view({},true)
	if not plan.get("active",false) or plan.get("complete",true) or not plan.get("can_fill",false) or action.role!=plan.role or action.mode!=plan.mode:
		_failure={"ok":false,"code":"staffing_changed_review"};_cache_key="";changed.emit();return
	if action.mode in ["existing","recovery"]:
		var still_available:bool=false
		for candidate:Dictionary in plan.candidates:
			if candidate.id==action.staff_id:still_available=true
		if not still_available:
			_failure={"ok":false,"code":"staffing_changed_review"};_cache_key="";changed.emit();return
	_working=true;_failure={};_cache_key="";changed.emit()
	var result:Dictionary={}
	var sid:String=str(action.staff_id)
	if action.mode=="hire":
		result=session.issue("hire",{"role":str(action.role)})
		if result.get("ok",false):
			sid=str(result.data.staff_id)
			_recovery={"owner":action.owner,"facility_id":action.facility_id,"role":action.role,"staff_id":sid}
		else:_finish(result);return
	# A command_result callback may close the card, fill/remove the target, or
	# change hospitals between the two public commands. Never cross that owner.
	if generation!=_generation or action.owner!=session.sim or _owner!=session.sim:
		_working=false;_cache_key="";changed.emit();return
	result=session.issue("assign",{"staff_id":sid,"facility_id":str(action.facility_id)})
	if result.get("ok",false):_recovery.clear()
	else:result=result.duplicate(true);result.data["retained_staff_id"]=sid
	_finish(result)

func _finish(result:Dictionary)->void:
	_working=false
	_failure={} if result.get("ok",false) else result.duplicate(true)
	_cache_key="";changed.emit();action_finished.emit(result)
