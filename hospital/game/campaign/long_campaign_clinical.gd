class_name LongCampaignClinical
extends RefCounted

# The clinical clock, paths, work reservations, stock debit and exit receipt are
# shared with v1. Only admission identity and batch completion policy differ.
const RULESET := "full-hospital-v2"
const TERMINAL := ["left","abandoned"]

static func instance_readiness(state: ClinicState,catalog: ContentCatalog,case_id: String) -> Array:
	var d: Dictionary=state.data
	if d.get("schema_version",0)!=3 or d.get("ruleset","")!=RULESET: return ["not_long_campaign"]
	if not catalog.campaign.cases.has(case_id) or case_id not in catalog.levels[d.level_id].case_ids: return ["unknown_case"]
	if case_id not in LongCampaign.unlocked_case_ids(d,catalog): return ["case_locked"]
	var reasons: Array=CampaignClinicalFlow._case_preparation_reasons(state,catalog,case_id,false)
	var count: int=int(catalog.campaign.cases[case_id].patient_count)
	var level: Dictionary=catalog.levels[d.level_id]
	var phase: Dictionary=level.phases[mini(3,int(d.campaign.phase_index))]
	var capacity: int=mini(int(level.max_patients),int(phase.max_live))
	if d.campaign.live_patient_ids.size()+count>capacity: reasons.append("patient_limit")
	return reasons

static func admit_instance(state: ClinicState,catalog: ContentCatalog,case_id: String,kind: String,source: String,sequence: int,schedule_index: int=-1) -> Dictionary:
	var d: Dictionary=state.data
	if d.get("schema_version",0)!=3 or d.get("ruleset","")!=RULESET: return _no("not_long_campaign")
	if kind not in ["signature","routine"] or source not in ["manual","auto"]: return _no("invalid_admission_source")
	if d.challenge.status!="running": return _no("challenge_ended")
	var cp: Dictionary=d.campaign
	if source=="manual":
		if sequence!=int(d.command_sequence)+1 or schedule_index!=-1: return _no("invalid_admission_sequence")
	elif kind!="routine" or sequence!=int(d.command_sequence) or schedule_index!=int(cp.intake_cursor) or not cp.intake_enabled: return _no("invalid_auto_admission_sequence")
	var level: Dictionary=catalog.levels[d.level_id]
	if kind=="signature":
		if cp.completed_cases.size()>=level.case_ids.size() or case_id!=level.case_ids[cp.completed_cases.size()]: return _no("not_next_case")
		for id: String in _active_instances(d):
			if cp.case_instances[id].kind=="signature": return _no("signature_active")
	elif case_id not in cp.completed_cases: return _no("routine_case_not_completed")
	var reasons: Array=instance_readiness(state,catalog,case_id)
	if not reasons.is_empty(): return _no(str(reasons[0]),{"reasons":reasons})
	var number: int=int(d.next_ids.case_instance)
	var instance_id: String="instance_%06d"%number
	var event_id: String="admission_%06d"%number
	var definition: Dictionary=catalog.campaign.cases[case_id]
	var patient_ids: Array=[]
	for _n in range(int(definition.patient_count)):
		var id: String="patient_%03d"%int(d.next_ids.patient)
		d.next_ids.patient+=1
		var patient: Dictionary=CampaignClinicalFlow._new_patient(d,definition,id,case_id)
		patient.case_instance_id=instance_id
		d.patients[id]=patient
		cp.live_patient_ids.append(id)
		patient_ids.append(id)
	d.next_ids.case_instance+=1
	cp.case_instances[instance_id]={"id":instance_id,"case_id":case_id,"kind":kind,"phase_index":int(cp.phase_index),"admitted_tick":int(d.tick),"patient_ids":patient_ids.duplicate(),"status":"active","completed_tick":-1,"admission_event_id":event_id}
	cp.admission_events[event_id]={"id":event_id,"source":source,"phase_index":int(cp.phase_index),"case_id":case_id,"instance_id":instance_id,"tick":int(d.tick),"command_sequence":sequence,"schedule_index":schedule_index,"quoted_price_percent":int(cp.price_percent),"patient_ids":patient_ids.duplicate()}
	if source=="auto": cp.intake_cursor+=1
	_refresh_wave(d)
	return {"ok":true,"code":"ok","data":{"instance_id":instance_id,"patient_ids":patient_ids,"case_id":case_id,"admission_event_id":event_id}}

static func after_tick(state: ClinicState,catalog: ContentCatalog) -> void:
	var d: Dictionary=state.data
	if d.get("paused",true) or d.challenge.status!="running": return
	var ids: Array=d.campaign.live_patient_ids.duplicate()
	var touched: Dictionary={}
	var personal_busy:Dictionary={}
	for id: String in ids:
		var p: Dictionary=d.patients[id]
		touched[p.case_instance_id]=true
		if CampaignPeople.tick_patient(state,catalog,p):personal_busy[id]=true
		if p.phase=="care_service": CampaignClinicalFlow._advance_service(state,catalog,p)
		elif p.phase=="waiting_support": CampaignClinicalFlow._advance_support(state,catalog,p)
	if CampaignPeople.autonomy_enabled(d):CampaignStaffRest.tick_all(state,catalog)
	CampaignClinicalFlow._move_staff(state)
	for id: String in ids:
		var p: Dictionary=d.patients[id]
		if p.phase=="moving_care":
			var facility: Dictionary=d.facilities.get(p.facility_id,{})
			if not facility.is_empty() and CampaignClinicalFlow._walk(state,p,int(facility.service_cells[0])): CampaignClinicalFlow._start_service(state,catalog,p)
		elif p.phase=="moving_exit" and not personal_busy.has(id):
			if CampaignClinicalFlow._walk(state,p,GridService.EXIT_CELL):
				CampaignClinicalFlow._exit(state,catalog,p)
				if p.phase=="left" and p.outcome=="completed" and int(p.wait_ticks)<=1200: d.campaign.reputation=mini(100,int(d.campaign.reputation)+1)
				elif p.phase=="abandoned": d.campaign.reputation=maxi(0,int(d.campaign.reputation)-5)
		elif p.phase=="waiting_support" and not personal_busy.has(id):
			_queue_walk(state,p)
		CampaignClinicalFlow._release_departed(state,p)
		CampaignPeople.release_departed(d,p)
		_release_queue_marker(p)
	for id: String in CampaignClinicalFlow.queue_order(d):
		var patient:Dictionary=d.patients[id]
		if personal_busy.has(id):continue
		if CampaignPeople.maybe_auto_patient(state,catalog,patient):
			personal_busy[id]=true
			continue
		CampaignClinicalFlow._schedule(state,catalog,patient)
		if patient.phase in ["care_queue","waiting_support"]:
			_queue_walk(state,patient)
			# The old slot remains owned during the fractional edge, and is
			# released in the very tick the body actually leaves its cell.
			CampaignClinicalFlow._release_departed(state,patient)
		CampaignPeople.release_departed(d,patient)
		_release_queue_marker(patient)
	var live: Array=[]
	for id: String in ids:
		var p: Dictionary=d.patients[id]
		if p.phase in ["care_queue","waiting_support"]:
			p.wait_ticks+=1
			if p.phase=="care_queue" and p.wait_ticks>=CampaignClinicalFlow.patience_limit(d,catalog,p): CampaignClinicalFlow._abandon(state,p)
		_release_queue_marker(p)
		if p.phase not in TERMINAL: live.append(id)
	d.campaign.live_patient_ids=live
	for id: String in touched: _settle_instance(d,catalog,id)
	_refresh_wave(d)

static func _release_queue_marker(patient:Dictionary) -> void:
	if not patient.has("queue_cell"):return
	if patient.phase in ["care_queue","waiting_support"] and (patient.get("need_activity",{}).is_empty() or int(patient.get("goal_cell",-1))==int(patient.queue_cell)):return
	var cell:int=int(patient.queue_cell)
	var route:Array=patient.get("path",[])
	var index:int=int(patient.get("path_index",0))
	var entering:bool=int(patient.get("move_progress",0))>0 and index+1<route.size() and int(route[index+1])==cell
	if int(patient.cell)!=cell and not entering:patient.erase("queue_cell")

static func _queue_walk(state:ClinicState,patient:Dictionary) -> void:
	if patient.get("blocked_slot_id","")=="" and not patient.has("queue_cell") and patient.get("need_activity",{}).get("state","")!="departing":return
	var d:Dictionary=state.data
	var settled:bool=patient.has("queue_cell") and int(patient.cell)==int(patient.queue_cell) and int(patient.move_progress)==0 and patient.path.is_empty()
	# A parked body needs no per-tick geometry or flood. Periodic review also
	# lets genuine saves made by an earlier candidate vacate unsafe old spots.
	if settled and int(d.tick)%100!=0:return
	var extra:Dictionary={}
	for collection:String in ["patients","staff"]:
		var ids:Array=d.campaign.live_patient_ids if collection=="patients" else d.staff.keys()
		for id:String in ids:
			if id==patient.id:continue
			var actor:Dictionary=d[collection][id]
			extra[int(actor.cell)]=true
			var route:Array=actor.get("path",[])
			var index:int=int(actor.get("path_index",0))
			if int(actor.get("move_progress",0))>0 and index+1<route.size():extra[int(route[index+1])]=true
			if actor.has("queue_cell"):extra[int(actor.queue_cell)]=true
	extra.erase(int(patient.cell))
	if patient.has("queue_cell") and not settled:
		CampaignClinicalFlow._walk(state,patient,int(patient.queue_cell),extra)
		return
	var excluded:Dictionary=FacilityLayout.queue_excluded_cells(d.rooms)
	var goal:int=int(patient.get("queue_cell",-1))
	var access:Dictionary=_queue_access_model(d,str(patient.id))
	var individual_access:Dictionary=_queue_access_model(d,str(patient.id),false)
	# Non-work floors can still be the only entrance to a station. Retain a
	# parked destination only when the complete future waiting mask is safe.
	if settled and _queue_access_result(access,goal).all_accessible:return
	var blockers:Dictionary=CampaignClinicalFlow._work_positions(d,patient,goal)
	blockers.merge(extra,true)
	var navigation:Dictionary=GridService._navigation(d.rooms)
	for cell:int in blockers:navigation.blocked[cell]=true
	var reachable:Dictionary=GridService._flood(navigation,int(patient.cell))
	goal=-1
	# Flood order is fixed north/east/south/west. Adding a waiting destination
	# must preserve every previously accessible station/door approach. For old
	# broken sets, move even an individually redundant blocker to another floor.
	for cell:int in reachable:
		if cell==int(patient.cell) or excluded.has(cell) or extra.has(cell):continue
		# Old multiple bad points can conceal each other's damage. A new
		# point must also be safe on its own, not just preserve a broken mask.
		if _queue_access_result(individual_access,cell).all_accessible and _queue_access_result(access,cell).preserved:goal=cell;break
	if goal<0:return
	CampaignClinicalFlow._walk(state,patient,goal,extra)
	# A changed destination while mid-edge first finishes/retreats that edge.
	# Commit its reservation only when the common walker has adopted the goal;
	# until then the old marker and physical route remain a valid saved state.
	if int(patient.get("goal_cell",-1))==goal:patient.queue_cell=goal

static func _queue_access_model(d:Dictionary,patient_id:String,include_queues:bool=true) -> Dictionary:
	var original:Dictionary=GridService._navigation(d.rooms)
	var masked:Dictionary=original.duplicate(true)
	var targets:Dictionary={}
	for facility:Dictionary in d.facilities.values():
		for key:String in ["service_cells","staff_cells"]:
			for cell:int in facility[key]:
				masked.blocked[cell]=true
				targets[cell]=true
		targets[int(facility.maintenance_cell)]=true
	for room:Dictionary in d.rooms.values():
		for doorway:Dictionary in room.doorways:
			targets[int(doorway.door_cell)]=true
			targets[int(doorway.door_outside_cell)]=true
	if include_queues:
		for id:String in d.campaign.live_patient_ids:
			if id!=patient_id and d.patients[id].has("queue_cell"):masked.blocked[int(d.patients[id].queue_cell)]=true
	# The patient being relocated is absent from this future mask. Keeping its
	# old body/goal here would hide exactly the entrance it currently blocks.
	var reachable:Dictionary=GridService._flood(masked,GridService.EXIT_CELL)
	var baseline:Dictionary={}
	for cell:int in targets:
		if _queue_has_approach(original,reachable,cell):baseline[cell]=true
	return {"original":original,"masked":masked,"targets":targets,"baseline":baseline}

static func _queue_has_approach(navigation:Dictionary,reachable:Dictionary,cell:int) -> bool:
	if reachable.has(cell):return true
	for neighbor:int in [cell-GridService.WIDTH,cell+1,cell+GridService.WIDTH,cell-1]:
		if reachable.has(neighbor) and GridService._can_step(navigation,neighbor,cell):return true
	return false

static func _queue_access_result(model:Dictionary,goal:int) -> Dictionary:
	var masked:Dictionary=model.masked.duplicate(true)
	masked.blocked[goal]=true
	var reachable:Dictionary=GridService._flood(masked,GridService.EXIT_CELL)
	var preserved:bool=true
	var all_accessible:bool=true
	for cell:int in model.targets:
		if _queue_has_approach(model.original,reachable,cell):continue
		all_accessible=false
		if model.baseline.has(cell):preserved=false
	return {"preserved":preserved,"all_accessible":all_accessible}

static func _settle_instance(d: Dictionary,catalog: ContentCatalog,id: String) -> void:
	var instance: Dictionary=d.campaign.case_instances[id]
	if instance.status!="active": return
	var success:=true
	var completed_tick: int=-1
	for patient_id: String in instance.patient_ids:
		var p: Dictionary=d.patients[patient_id]
		if p.phase not in TERMINAL: return
		if p.phase!="left" or p.outcome!="completed": success=false
		completed_tick=maxi(completed_tick,int(p.completed_tick))
	instance.status="completed" if success else "failed"
	instance.completed_tick=completed_tick
	# A failed signature may be retried. Routine visits never append/overwrite
	# the ordered one-time signature proof, and neither result pauses the game.
	if instance.kind=="signature" and success:
		var cp: Dictionary=d.campaign
		var case_id: String=instance.case_id
		var cases: Array=catalog.levels[d.level_id].case_ids
		if cp.completed_cases.size()<cases.size() and cases[cp.completed_cases.size()]==case_id:
			cp.completed_cases.append(case_id); cp.completed_waves.append(case_id)
			cp.wave_index=cp.completed_cases.size()
			d.evidence.cases[case_id]={"tick":completed_tick,"patient_count":instance.patient_ids.size(),"instance_id":id}

static func _active_instances(d: Dictionary) -> Array:
	var result: Array=[]
	for patient_id: String in d.campaign.live_patient_ids:
		var id: String=d.patients[patient_id].case_instance_id
		if not result.has(id): result.append(id)
	return result

static func _refresh_wave(d: Dictionary) -> void:
	var active: Array=_active_instances(d)
	d.campaign.wave_active=not active.is_empty()
	d.campaign.current_case_id=""
	for id: String in active:
		var instance: Dictionary=d.campaign.case_instances[id]
		if instance.kind=="signature": d.campaign.current_case_id=instance.case_id; break

static func _no(code: String,data: Dictionary={}) -> Dictionary:
	return {"ok":false,"code":code,"data":data}
