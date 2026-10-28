class_name HospitalStaffingInsights
extends RefCounted

# Detached presentation only. Never edits staff, activity, appointments, paths,
# resources, scheduling or save fields. Availability here describes personnel;
# stock, facility condition and other clinical prerequisites remain separate.
const ROLE_NAMES:Dictionary={"doctor":"医师","nurse":"护士","technician":"医技师","receptionist":"接待员","pharmacist":"药师","engineer":"工程师","cleaner":"保洁员","logistics":"配送员"}
const RELIEF=preload("res://campaign/campaign_staff_relief.gd")

static func _dict(value:Variant)->Dictionary:
	return value if value is Dictionary else {}

static func _array(value:Variant)->Array:
	return value if value is Array else []

static func _number(row:Dictionary,key:String,fallback:int=-1)->int:
	return int(row[key]) if row.get(key) is int else fallback

static func _role_name(role:String)->String:
	return str(ROLE_NAMES.get(role,role))

static func _route_ticks(s:Dictionary,target:int)->int:
	# Only an already adopted path can support this moving-time estimate.
	# New blockers, rerouting and use/wait time are deliberately not predicted.
	var path:Array=_array(s.get("path",[]))
	var index:int=_number(s,"path_index")
	var cell:int=_number(s,"cell")
	var step_ticks:int=_number(s,"move_ticks")
	var progress:int=_number(s,"move_progress")
	if target<0 or path.is_empty() or index<0 or index>=path.size() or step_ticks<=0 or progress<0 or progress>=step_ticks:return -1
	if not path[-1] is int or int(path[-1])!=target or not path[index] is int or int(path[index])!=cell:return -1
	var edges:int=path.size()-index-1
	if edges==0:return 0 if cell==target and progress==0 else -1
	return maxi(0,edges*step_ticks-progress)

static func employee(d:Dictionary,sid:String)->Dictionary:
	var result:Dictionary={"staff_id":sid,"active":false,"state":"idle","label":"当前未在补给短休","elapsed_ticks":-1,"remaining_use_ticks":-1,"remaining_route_ticks":-1,"route_estimate_label":"当前路线尚未确定","estimate_scope":"只按当前已采用路径估计移动时间，不含等待、改道或未来返程；不是总返岗倒计时。"}
	var s:Dictionary=_dict(_dict(d.get("staff",{})).get(sid,{}))
	if s.is_empty():result.state="unknown";result.label="未找到该员工";return result
	var activity:Dictionary=_dict(s.get("rest_activity",{}))
	if activity.is_empty():return result
	var event_id:String=str(activity.get("event_id",""))
	var h:Dictionary=_dict(_dict(_dict(d.get("campaign",{})).get("staff_rest_events",{})).get(event_id,{}))
	if h.is_empty() or str(h.get("staff_id",""))!=sid:
		result.state="unknown";result.label="短休记录暂不可用";return result
	var state:String=str(h.get("state",""))
	if state not in ["walking","using","returning"]:
		result.state=state if state in ["done","canceled"] else "unknown"
		result.label="短休已取消，当前未离岗" if state=="canceled" else "本次短休已结束" if state=="done" else "短休阶段待确认"
		return result
	result.active=true;result.state=state
	var now:int=_number(d,"tick")
	var requested:int=_number(h,"requested_tick")
	var started:int=_number(h,"started_tick")
	var completed:int=_number(h,"completed_tick")
	var canceled:int=_number(h,"canceled_tick")
	var needed:int=_number(h,"needed")
	if requested>=0 and now>=requested:result.elapsed_ticks=now-requested
	var need:String=str(h.get("need",""))
	var purpose:String="饮水" if need=="water" else "便食" if need=="food" else "补给"
	if state=="walking":
		result.label="正在前往"+purpose+"补给点"
		result.remaining_route_ticks=_route_ticks(s,_number(h,"target_cell"))
	elif state=="using":
		result.label="正在"+purpose+"短休"
		if started>=0 and needed>=0 and now>=started:result.remaining_use_ticks=maxi(0,needed-(now-started))
		result.remaining_route_ticks=0
		result.route_estimate_label="当前正在补给，返程尚未开始"
	else:
		var canceled_before_use:bool=canceled>=0 and completed<0
		result.label="短休已取消，正在返岗" if canceled_before_use else "短休结束，正在返岗"
		if not canceled_before_use and started>=0 and completed>=started:result.remaining_use_ticks=0
		result.remaining_route_ticks=_route_ticks(s,_number(h,"return_cell"))
	if state in ["walking","returning"] and int(result.remaining_route_ticks)>=0:
		result.route_estimate_label="按当前路径还需约%.1f秒移动（不含等待或改道）。"%(float(result.remaining_route_ticks)/10.0)
	return result

static func _relief_configured(d:Dictionary)->bool:
	return d.get("campaign") is Dictionary and RELIEF.configured(d)

static func relief(d:Dictionary,sid:String)->Dictionary:
	var result:Dictionary={"staff_id":sid,"registered":false,"active":false,"state":"unregistered","label":"未登记候补","facility_id":"","owner_staff_id":"","relief_staff_id":"","work_cell":-1}
	var s:Dictionary=_dict(_dict(d.get("staff",{})).get(sid,{}))
	if s.is_empty():result.state="unknown";result.label="未找到该员工";return result
	var home:String=str(s.get("facility_id",""))
	if home!="":result.label="主岗已保留。";result.facility_id=home;result.owner_staff_id=sid;result.state="primary"
	if not _relief_configured(d):return result
	var campaign:Dictionary=d.campaign
	result.registered=sid in _array(campaign.get("staff_relief_pool",[]))
	if result.registered:result.state="standby";result.label="已登记待命；仅在资格、路径和岗位均允许时安排替班。"
	var events:Dictionary=_dict(campaign.get("staff_relief_events",{}))
	var activity:Dictionary=_dict(s.get("relief_activity",{}))
	var h:Dictionary=_dict(events.get(str(activity.get("event_id","")),{}))
	if str(h.get("relief_staff_id",""))==sid and str(h.get("state","")) in ["walking","covering","draining","returning"]:
		result.active=true;result.state=str(h.state);result.facility_id=str(h.get("facility_id",""));result.owner_staff_id=str(h.get("owner_staff_id",""));result.relief_staff_id=sid;result.work_cell=_number(h,"work_cell")
		var labels:Dictionary={"walking":"正在前往替班岗位；到岗前尚未形成接诊能力。","covering":"正在替班，原员工的主岗仍保留。","draining":"正在交还岗位，先完成已有服务，再实际离开；暂停新预约。","returning":"替班结束，正在返回待命点。"}
		result.label=str(labels[result.state]);return result
	if not activity.is_empty():result.state="unknown";result.label="替班记录待确认，当前不能重新派岗。";return result
	for value:Variant in events.values():
		var event:Dictionary=_dict(value)
		if event.get("owner_staff_id","")!=sid or event.get("state","") not in ["walking","covering","draining"] or _number(event,"left_tick")>=0:continue
		result.active=true;result.state="primary_away";result.facility_id=str(event.get("facility_id",home));result.owner_staff_id=sid;result.relief_staff_id=str(event.get("relief_staff_id",""));result.work_cell=_number(event,"work_cell")
		var stage:String={"walking":"正在赴岗","covering":"正在替班","draining":"正在交还"}.get(str(event.state),"正在交接")
		result.label="主岗保留；候补%s%s，返岗仍需等待实际交接。"%[str(result.relief_staff_id).trim_prefix("staff_"),stage];return result
	return result

static func _unavailable(d:Dictionary,s:Dictionary,f:Dictionary,definition:Dictionary)->Dictionary:
	var sid:String=str(s.get("id",""))
	var role:String=str(s.get("role",""))
	var state:String="";var label:String=""
	var rest:Dictionary=employee(d,sid)
	if bool(rest.active):
		return {"staff_id":sid,"role":role,"state":str(rest.state),"label":str(rest.label),"elapsed_ticks":int(rest.elapsed_ticks),"remaining_use_ticks":int(rest.remaining_use_ticks),"remaining_route_ticks":int(rest.remaining_route_ticks)}
	if not _dict(s.get("rest_activity",{})).is_empty():state="unknown_rest";label="短休状态待确认，岗位仍保留"
	elif str(s.get("training_order_id",""))!="":state="training";label="正在培训或等待培训交接"
	elif str(s.get("patient_id",""))!="":state="service";label="已有诊疗预约或正在服务"
	elif str(s.get("work_order_id",""))!="":state="operation";label="正在处理后勤工单"
	else:
		var fatigue_limit:int=100 if str(definition.get("kind",""))=="patient" else 95
		if _number(s,"fatigue",0)>=fatigue_limit:state="fatigued";label="疲劳过高，暂不能开始工作"
		else:
			var ids:Array=_array(f.get("staff_ids",[]))
			var cells:Array=_array(f.get("staff_cells",[]))
			var place:int=ids.find(sid)
			var path:Array=_array(s.get("path",[]))
			var index:int=_number(s,"path_index",0)
			var moving:bool=_number(s,"move_progress",0)>0 or (not path.is_empty() and index>=0 and index<path.size()-1)
			if moving:state="moving";label="正在移动或前往岗位"
			elif place<0 or place>=cells.size() or not cells[place] is int:state="workplace_unknown";label="岗位位置待确认"
			elif _number(s,"cell")!=int(cells[place]):state="moving";label="尚未到达岗位，等待员工返岗"
	if state=="":return {}
	return {"staff_id":sid,"role":role,"state":state,"label":label}

static func _assigned_roles(d:Dictionary,f:Dictionary,roles:Array)->Dictionary:
	var used:Array=[];var selected:Array=[];var missing:Array=[]
	var staff:Dictionary=_dict(d.get("staff",{}))
	for role_value:Variant in roles:
		var role:String=str(role_value)
		var chosen:String=""
		for id_value:Variant in _array(f.get("staff_ids",[])):
			var sid:String=str(id_value)
			if sid in used:continue
			var s:Dictionary=_dict(staff.get(sid,{}))
			if str(s.get("role",""))!=role or str(s.get("facility_id",""))!=str(f.get("id","")):continue
			chosen=sid;break
		if chosen=="":missing.append(role)
		else:used.append(chosen);selected.append({"staff_id":chosen,"role":role})
	return {"selected":selected,"missing":missing}

static func _staffed_peer(d:Dictionary,definition:Dictionary,f:Dictionary)->bool:
	# A deliberately unstaffed O25/O26 can still be a self-service point.
	# When a separate producer already has its crew, do not call that extra
	# self-service point an urgent staffing gap in the overview.
	var roles:Array=_array(definition.get("roles",[]))
	for value:Variant in _dict(d.get("facilities",{})).values():
		var other:Dictionary=_dict(value)
		if other.get("id","")==f.get("id","") or other.get("kind","")!=f.get("kind","") or other.get("status","")!="open" or _number(other,"condition",0)<=0:continue
		if _assigned_roles(d,other,roles).missing.is_empty():return true
	return false

static func _effective_assignment(d:Dictionary,f:Dictionary,roles:Array)->Dictionary:
	var primary:Dictionary=_assigned_roles(d,f,roles)
	var selected:Array=[];var used:Array=[];var rows:Array=[]
	var ids:Array=_array(f.get("staff_ids",[])).duplicate()
	var configured:bool=_relief_configured(d)
	for member:Dictionary in primary.selected:
		var owner:String=str(member.staff_id)
		var sid:String=owner
		var slot:int=ids.find(owner)
		if configured and slot>=0 and slot<_array(f.get("staff_cells",[])).size() and f.staff_cells[slot] is int:
			var actual:String=RELIEF.slot_owner(d,str(f.id),slot)
			if actual!=owner and actual not in used and RELIEF.active_facility(d,actual)==str(f.id) and RELIEF.owns(d,actual,str(f.id)) and RELIEF.work_cell(d,str(f.id),actual)==int(f.staff_cells[slot]):
				var worker:Dictionary=_dict(d.get("staff",{}).get(actual,{}))
				if worker.get("role","")==member.role:
					sid=actual;ids[slot]=actual
					var status:Dictionary=relief(d,actual)
					rows.append({"owner_staff_id":owner,"staff_id":actual,"state":status.state,"label":status.label,"slot_index":slot})
		used.append(sid);selected.append({"staff_id":sid,"role":member.role})
	var visual:Dictionary=f
	if not rows.is_empty():visual=f.duplicate(false);visual.staff_ids=ids
	return {"selected":selected,"missing":primary.missing,"visual_facility":visual,"relief_rows":rows}

static func facility(d:Dictionary,catalog:ContentCatalog,fid:String)->Dictionary:
	var result:Dictionary={"facility_id":fid,"assigned_complete":false,"available_complete":false,"missing_roles":[],"unavailable":[],"required_count":0,"assigned_count":0,"available_count":0,"needs_attention":true,"summary":"未找到该设备的岗位信息","primary_staff_ids":[],"effective_staff_ids":[],"relief_count":0,"relief_rows":[]}
	var f:Dictionary=_dict(_dict(d.get("facilities",{})).get(fid,{}))
	if f.is_empty() or catalog==null:return result
	var kind:String=str(f.get("kind",""))
	var definition:Dictionary=_dict(catalog.campaign.facilities.get(kind,{}))
	if definition.is_empty():return result
	var roles:Array=_array(definition.get("roles",[]))
	var assignment:Dictionary=_effective_assignment(d,f,roles)
	var selected:Array=assignment.selected
	var missing:Array=assignment.missing
	var unavailable:Array=[]
	var staff:Dictionary=_dict(d.get("staff",{}))
	for member:Dictionary in selected:
		var s:Dictionary=_dict(staff.get(str(member.staff_id),{}))
		var reason:Dictionary=_unavailable(d,s,assignment.visual_facility,definition)
		var status:Dictionary=relief(d,str(member.staff_id))
		if status.active and status.owner_staff_id!=member.staff_id and status.facility_id==fid:
			if status.state=="draining":reason={"staff_id":member.staff_id,"role":member.role,"state":"handoff","label":"替班交还中，已有服务结束前不接新预约"}
			elif _number(s,"fatigue",0)>=64 or _number(s,"morale",70)<45:reason={"staff_id":member.staff_id,"role":member.role,"state":"relief_rest_due","label":"候补需要恢复，等待交还岗位"}
		if not reason.is_empty():unavailable.append(reason)
		result.effective_staff_ids.append(member.staff_id)
	result.primary_staff_ids=_array(f.get("staff_ids",[])).duplicate()
	result.relief_rows=assignment.relief_rows;result.relief_count=assignment.relief_rows.size()
	result.required_count=roles.size();result.assigned_count=selected.size();result.available_count=selected.size()-unavailable.size()
	result.assigned_complete=missing.is_empty();result.available_complete=missing.is_empty() and unavailable.is_empty()
	result.missing_roles=missing;result.unavailable=unavailable
	result.needs_attention=not bool(result.assigned_complete) or not bool(result.available_complete)
	var name:String=str(definition.get("name",kind))
	var self_service:bool=kind in ["O25","O26"]
	if self_service and selected.is_empty() and _staffed_peer(d,definition,f):
		result.needs_attention=false
		result.summary=name+"：此处可自助补给，补货生产由另一台已派岗设备承担。"
	elif not missing.is_empty():
		var counts:Dictionary={}
		for role:String in missing:counts[role]=int(counts.get(role,0))+1
		var labels:Array[String]=[]
		for role:String in counts:labels.append(_role_name(role)+str(counts[role])+"人")
		result.summary=name+"："+("自助补给不需派岗；补货生产" if self_service else "")+"尚缺"+"、".join(labels)+"。"
	elif unavailable.is_empty():result.summary=name+"：人员已派齐且均已到岗（%d/%d）。"%[int(result.assigned_count),int(result.required_count)]
	else:
		var details:Array[String]=[]
		for reason:Dictionary in unavailable:details.append(_role_name(str(reason.role))+" "+str(reason.staff_id).trim_prefix("staff_")+"："+str(reason.label))
		result.summary=name+"：已派齐，当前人员到岗可用%d/%d；"%[int(result.available_count),int(result.required_count)]+"；".join(details)+"。"
	for row:Dictionary in result.relief_rows:
		result.summary+=" 主岗%s保留；候补%s%s。"%[str(row.owner_staff_id).trim_prefix("staff_"),str(row.staff_id).trim_prefix("staff_"),{"covering":"正在替班","draining":"正在交还","walking":"正在赴岗"}.get(str(row.state),"正在交接")]
	return result

static func overview(d:Dictionary,catalog:ContentCatalog)->Dictionary:
	var resting:int=0
	var reserves:int=0;var covering:int=0
	for id_value:Variant in _dict(d.get("staff",{})):
		if bool(employee(d,str(id_value)).active):resting+=1
		var status:Dictionary=relief(d,str(id_value))
		if status.registered:reserves+=1
		if status.active and status.owner_staff_id!=str(id_value):covering+=1
	var summaries:Array[String]=[]
	var ids:Array=_dict(d.get("facilities",{})).keys();ids.sort()
	for id_value:Variant in ids:
		var view:Dictionary=facility(d,catalog,str(id_value))
		if not bool(view.get("needs_attention",true)) and int(view.get("relief_count",0))==0:continue
		summaries.append(str(view.summary))
		if summaries.size()>=6:break
	return {"resting_count":resting,"reserve_count":reserves,"relief_active_count":covering,"facility_summaries":summaries,"scope":"仅当前快照的人员与岗位状态；不改变任何派岗或休息安排。"}
