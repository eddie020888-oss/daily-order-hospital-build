class_name CampaignPeopleValidator
extends RefCounted

static func _fields(value:Variant,shape:Dictionary)->bool:
	if not value is Dictionary:return false
	for key:String in shape:
		if not value.has(key) or typeof(value[key])!=int(shape[key]):return false
	return true

static func _receipt(d:Dictionary,reference:String)->Dictionary:
	if not reference.begins_with("command:"):return {}
	var value:Variant=d.command_receipts.get(reference.trim_prefix("command:"),{})
	if not value is Dictionary or not value.get("ok",false) or not value.get("data") is Dictionary:return {}
	return value.data

static func validate(d:Dictionary,catalog:ContentCatalog)->String:
	var cp:Variant=d.get("campaign",{})
	if not cp is Dictionary or not cp.has("people_version"):return ""
	if not cp.people_version is int or cp.people_version!=1 or not CampaignPeople.enabled(d):return "invalid_people_version"
	if cp.has("experience_version"):
		if not cp.experience_version is int or cp.experience_version!=1 or not CampaignPeople.autonomy_enabled(d):return "invalid_people_experience_version"
		var policy_error:String=_autonomy_policy(d)
		if policy_error!="":return policy_error
	if not cp.get("people_reservations") is Dictionary:return "invalid_people_reservations"
	var reservations:Dictionary={}
	var requests:Dictionary={}
	var work_intervals:Dictionary=_patient_work_intervals(d) if CampaignPeople.autonomy_enabled(d) else {}
	for p:Variant in d.patients.values():
		if not p is Dictionary:return "invalid_people_patient"
		var error:String=_patient(d,catalog,p,reservations,requests,work_intervals.get(p.id,[]))
		if error!="":return error
	if not CampaignPeople.autonomy_enabled(d) and reservations!=cp.people_reservations:return "orphan_people_reservation"
	for receipt:Variant in d.command_receipts.values():
		if not receipt is Dictionary or not receipt.get("data") is Dictionary:continue
		var data:Dictionary=receipt.data
		var command:Variant=data.get("command",{})
		if command is Dictionary and command.get("type","")=="request_patient_need":
			if not command.get("id") is String or not requests.has("command:"+str(command.id)):return "orphan_people_request"
	for worker:Variant in d.staff.values():
		if not worker is Dictionary:return "invalid_people_staff"
		var error:String=_staff(d,catalog,worker)
		if error!="":return error
	if CampaignPeople.autonomy_enabled(d):return CampaignStaffRestValidator.validate(d,catalog)
	return ""

static func _autonomy_policy(d:Dictionary)->String:
	if not _fields(d.campaign,{"auto_patient_needs":TYPE_BOOL,"auto_staff_rest":TYPE_BOOL,"staff_rest_events":TYPE_DICTIONARY}):return "missing_autonomy_fields"
	var policy:Dictionary=autonomy_policy_at(d,int(d.command_sequence),int(d.tick),false)
	if not policy.get("valid",false):return "invalid_autonomy_policy_history"
	if policy.patient_needs!=d.campaign.auto_patient_needs or policy.staff_rest!=d.campaign.auto_staff_rest:return "forged_autonomy_policy"
	return ""

static func autonomy_policy_at(d:Dictionary,sequence:int,at_tick:int,automatic:bool=true)->Dictionary:
	if sequence<0 or sequence>int(d.command_sequence):return {"valid":false}
	var rows:Dictionary={}
	for receipt:Dictionary in d.command_receipts.values():rows[int(receipt.data.sequence)]=receipt.data
	var policy:Dictionary={"valid":true,"patient_needs":true,"staff_rest":true}
	for n:int in range(1,sequence+1):
		if not rows.has(n):return {"valid":false}
		var row:Dictionary=rows[n]
		if automatic and int(row.tick)>=at_tick:return {"valid":false}
		if row.command.type!="set_people_autonomy":continue
		var p:Dictionary=row.command.payload
		if p.size()!=2 or not p.get("patient_needs") is bool or not p.get("staff_rest") is bool or row.get("patient_needs")!=p.patient_needs or row.get("staff_rest")!=p.staff_rest:return {"valid":false}
		policy.patient_needs=p.patient_needs;policy.staff_rest=p.staff_rest
	if automatic and sequence<int(d.command_sequence) and (not rows.has(sequence+1) or int(rows[sequence+1].tick)<at_tick):return {"valid":false}
	return policy

static func _patient(d:Dictionary,catalog:ContentCatalog,p:Dictionary,reservations:Dictionary,requests:Dictionary,work_intervals:Array=[])->String:
	if not _fields(p,{"needs":TYPE_DICTIONARY,"need_history":TYPE_ARRAY,"need_activity":TYPE_DICTIONARY}):return "missing_people_patient_fields"
	if not _fields(p.needs,{"water":TYPE_INT,"food":TYPE_INT,"toilet":TYPE_INT}) or p.needs.size()!=3:return "invalid_people_needs"
	for value:Variant in p.needs.values():
		if value<0 or value>100:return "invalid_people_need_range"
	var prior:int=int(p.arrived_tick)
	var last_end:int=-CampaignPeople.COOLDOWN
	var used_steps:Dictionary={}
	var active_index:int=-1
	var shape:Dictionary={"id":TYPE_STRING,"serial":TYPE_INT,"need":TYPE_STRING,"facility_id":TYPE_STRING,"facility_kind":TYPE_STRING,"target_cell":TYPE_INT,"requested_tick":TYPE_INT,"request_reference":TYPE_STRING,"request_cell":TYPE_INT,"move_ticks":TYPE_INT,"step_index":TYPE_INT,"state":TYPE_STRING,"started_tick":TYPE_INT,"completed_tick":TYPE_INT,"departed_tick":TYPE_INT,"canceled_tick":TYPE_INT,"needed":TYPE_INT,"cost":TYPE_INT,"resource":TYPE_STRING,"quantity":TYPE_INT,"need_before":TYPE_INT,"need_after":TYPE_INT}
	for index:int in range(p.need_history.size()):
		var item:Variant=p.need_history[index]
		if not _fields(item,shape):return "invalid_people_history_shape"
		var h:Dictionary=item
		if not CampaignPeople.NEEDS.has(h.need):return "unknown_people_need"
		var rule:Dictionary=CampaignPeople.NEEDS[h.need]
		if h.id!="need:"+str(p.id)+":"+str(index+1) or h.serial!=index+1:return "invalid_people_history_identity"
		if h.facility_kind!=rule.facility_kind or h.needed!=rule.needed or h.cost!=rule.cost or h.resource!=rule.resource or h.quantity!=rule.quantity:return "invalid_people_service_definition"
		if not h.facility_id.begins_with("facility_") or int(h.facility_id.trim_prefix("facility_"))<1 or int(h.facility_id.trim_prefix("facility_"))>=int(d.next_ids.facility):return "invalid_people_facility_identity"
		if h.target_cell<0 or h.target_cell>=GridService.WIDTH*GridService.HEIGHT or h.request_cell<0 or h.request_cell>=GridService.WIDTH*GridService.HEIGHT or h.move_ticks!=4:return "invalid_people_target"
		if h.requested_tick<prior or h.requested_tick>d.tick or h.requested_tick-last_end<CampaignPeople.COOLDOWN:return "invalid_people_request_clock"
		if h.step_index<0 or h.step_index>int(p.step_index) or (not CampaignPeople.autonomy_enabled(d) and used_steps.has(h.step_index)):return "repeated_people_need_step"
		var completed_steps:int=0
		for clinical:Dictionary in p.step_history:
			if int(clinical.completed_tick)>=0 and int(clinical.completed_tick)<=int(h.requested_tick):completed_steps+=1
		if h.step_index!=completed_steps:return "invalid_people_clinical_cursor"
		used_steps[h.step_index]=true
		if CampaignPeople.autonomy_enabled(d) and not _fields(h,{"source":TYPE_STRING,"request_sequence":TYPE_INT}):return "missing_autonomy_need_source"
		if h.get("source","manual")=="auto":
			if not CampaignPeople.autonomy_enabled(d) or h.request_reference!="auto_need:"+str(p.id)+":"+str(h.serial) or int(h.requested_tick)%20!=0:return "invalid_auto_need_identity"
			var policy:Dictionary=autonomy_policy_at(d,int(h.request_sequence),int(h.requested_tick))
			if not policy.get("valid",false) or not policy.get("patient_needs",false):return "unearned_auto_need"
		else:
			if h.get("source","manual")!="manual":return "invalid_people_request_source"
			var receipt:Dictionary=_receipt(d,str(h.request_reference))
			var command:Variant=receipt.get("command",{})
			if not command is Dictionary or command.get("type","")!="request_patient_need" or not command.get("payload") is Dictionary:return "unanchored_people_request"
			if command.payload.get("patient_id")!=p.id or command.payload.get("need")!=h.need or receipt.get("tick")!=h.requested_tick or receipt.get("activity_id")!=h.id or receipt.get("facility_id")!=h.facility_id or receipt.get("target_cell")!=h.target_cell or receipt.get("request_cell")!=h.request_cell or receipt.get("move_ticks")!=h.move_ticks:return "invalid_people_request_receipt"
			if CampaignPeople.autonomy_enabled(d) and h.request_sequence!=receipt.get("sequence"):return "invalid_manual_need_sequence"
		if requests.has(h.request_reference):return "reused_people_request"
		requests[h.request_reference]=true
		if h.state not in ["walking","using","departing","done","canceled"]:return "invalid_people_activity_state"
		if h.started_tick< -1 or h.completed_tick< -1 or h.canceled_tick< -1 or h.departed_tick< -1:return "invalid_people_negative_clock"
		var prefix:Dictionary=p.duplicate()
		prefix.need_history=p.need_history.slice(0,index)
		var at_request:Dictionary=CampaignPeople.needs_at(prefix,int(h.requested_tick))
		if int(at_request[h.need])<20:return "people_need_was_not_due"
		if h.get("source","manual")=="auto":
			var chosen:String=""
			var highest:int=39
			for key:String in CampaignPeople.NEEDS:
				if int(at_request[key])>highest:chosen=key;highest=int(at_request[key])
			if chosen!=h.need:return "invalid_auto_need_priority"
		if h.started_tick>=0:
			var min_steps:int=absi(int(h.target_cell)%GridService.WIDTH-int(h.request_cell)%GridService.WIDTH)+absi(int(int(h.target_cell)/GridService.WIDTH)-int(int(h.request_cell)/GridService.WIDTH))
			if h.started_tick<h.requested_tick+min_steps*int(h.move_ticks) or h.started_tick>d.tick or h.canceled_tick!=-1:return "invalid_people_arrival_clock"
			var charges:int=0
			for entry:Dictionary in d.ledger_entries:
				if entry.reference==h.id:
					if entry.category!="operations" or entry.tick!=h.started_tick or entry.amount!=-int(h.cost):return "invalid_people_charge"
					charges+=1
			if charges!=1:return "missing_or_duplicate_people_charge"
		else:
			for entry:Dictionary in d.ledger_entries:
				if entry.reference==h.id:return "premature_people_charge"
		if h.completed_tick>=0:
			if h.started_tick<0 or h.completed_tick!=int(h.started_tick)+int(h.needed) or h.completed_tick>d.tick:return "invalid_people_service_clock"
			var before:Dictionary=CampaignPeople.needs_at(prefix,int(h.completed_tick))
			if h.need_before!=before[h.need] or h.need_after!=maxi(0,int(h.need_before)-CampaignPeople.RELIEF):return "forged_people_relief"
		elif h.need_before!=-1 or h.need_after!=-1:return "premature_people_relief"
		if h.canceled_tick>=0 and (h.started_tick!=-1 or h.canceled_tick<h.requested_tick or h.canceled_tick>d.tick):return "invalid_people_cancel_clock"
		if h.departed_tick>=0 and (h.departed_tick<maxi(int(h.completed_tick),int(h.canceled_tick)) or h.departed_tick>d.tick):return "invalid_people_departure_clock"
		if h.state=="walking" and (h.started_tick!=-1 or h.completed_tick!=-1 or h.canceled_tick!=-1 or h.departed_tick!=-1):return "invalid_people_walking_clock"
		if h.state=="using" and (h.started_tick<0 or h.completed_tick!=-1 or h.canceled_tick!=-1 or h.departed_tick!=-1 or int(d.tick)-int(h.started_tick)>=int(h.needed)):return "invalid_people_using_clock"
		if h.state=="departing" and (h.departed_tick!=-1 or (h.completed_tick<0 and h.canceled_tick<0)):return "invalid_people_departing_clock"
		if h.state=="done" and (h.completed_tick<0 or h.departed_tick<0):return "invalid_people_done_clock"
		if h.state=="canceled" and (h.canceled_tick<0 or h.departed_tick<0):return "invalid_people_canceled_state"
		if CampaignPeople.autonomy_enabled(d):
			if not _need_queue_possible(d,catalog,p,h):return "people_request_outside_care_queue"
			var work_conflict:String=_need_work_conflict(d,h,work_intervals)
			if work_conflict!="":return work_conflict
		if h.state in ["walking","using","departing"]:
			if active_index>=0 or index!=p.need_history.size()-1:return "multiple_people_activities"
			active_index=index
		last_end=maxi(int(h.completed_tick),int(h.canceled_tick))
		prior=maxi(int(h.requested_tick),maxi(last_end,int(h.departed_tick)))
	var end:int=int(p.completed_tick) if int(p.get("completed_tick",-1))>=0 else int(d.tick)
	if p.needs!=CampaignPeople.needs_at(p,end):return "forged_people_current_needs"
	if active_index<0:
		if not p.need_activity.is_empty():return "orphan_people_activity"
		return ""
	if not _fields(p.need_activity,{"history_index":TYPE_INT,"facility_id":TYPE_STRING,"target_cell":TYPE_INT,"state":TYPE_STRING,"processed_tick":TYPE_INT}):return "invalid_people_activity_shape"
	var h:Dictionary=p.need_history[active_index]
	var a:Dictionary=p.need_activity
	if a.history_index!=active_index or a.facility_id!=h.facility_id or a.target_cell!=h.target_cell or a.state!=h.state or a.processed_tick< -1 or a.processed_tick>d.tick:return "invalid_people_activity_pointer"
	if not d.facilities.has(h.facility_id):return "missing_people_active_facility"
	var f:Dictionary=d.facilities[h.facility_id]
	if f.kind!=h.facility_kind or f.service_cells.is_empty() or int(f.service_cells[0])!=h.target_cell:return "changed_people_active_target"
	if h.state in ["walking","using"] and p.slot_id!="":return "people_and_clinical_double_booking"
	if h.state=="using" and (p.cell!=h.target_cell or p.move_progress!=0):return "people_using_without_arrival"
	var key:String=str(h.facility_id)+":0"
	if reservations.has(key):return "double_people_target_owner"
	reservations[key]=p.id
	return ""


# Only the experience branch adds historical busy proofs. Build the patient
# support index once: queued jobs already own the patient before any history
# row exists, and Operations completes after the Clinical handoff this tick.
static func _patient_work_intervals(d:Dictionary)->Dictionary:
	var result:Dictionary={}
	for p:Dictionary in d.patients.values():
		var rows:Array=[]
		for care:Dictionary in p.step_history:
			if care.kind!="patient":continue
			var end:int=int(care.completed_tick) if int(care.completed_tick)>=0 else int(d.tick)+1
			# _schedule runs after the movement/start loop. Even a zero-distance
			# service must have held its actual reservation in the preceding tick.
			# Earlier reservation starts were never recorded; do not invent them.
			rows.append({"from_tick":int(care.started_tick)-1,"to_tick":end,"kind":"clinical"})
		result[p.id]=rows
	for order:Dictionary in d.work_orders.values():
		if order.patient_id=="" or not result.has(order.patient_id):continue
		var end:int=int(order.completed_tick)+1 if int(order.completed_tick)>=0 else int(d.tick)+1
		result[order.patient_id].append({"from_tick":int(order.created_tick),"to_tick":end,"kind":"support"})
	# Current reservation ownership is real evidence even before service starts.
	# Its unrecorded historical beginning cannot be reconstructed from phase/body.
	for slot:Dictionary in d.slots.values():
		if slot.phase not in ["reserved","serving"] or not result.has(slot.patient_id):continue
		result[slot.patient_id].append({"from_tick":int(d.tick),"to_tick":int(d.tick)+1,"kind":"clinical"})
	return result

static func _need_work_conflict(d:Dictionary,h:Dictionary,intervals:Array)->String:
	var requested:int=int(h.requested_tick)
	var end:int=maxi(int(h.completed_tick),int(h.canceled_tick))
	if end<0:end=int(d.tick)+1
	for row:Dictionary in intervals:
		# The request itself must be idle, even for a malformed zero-length
		# cancellation. After the request, only walking/using stays exclusive.
		# tick_patient ends those phases before this tick can schedule new work;
		# departing may therefore legitimately overlap later clinical work.
		if (requested>=int(row.from_tick) and requested<int(row.to_tick)) or (requested<int(row.to_tick) and int(row.from_tick)<end):
			return "people_and_support_history_overlap" if row.kind=="support" else "people_and_clinical_history_overlap"
	return ""

static func _need_queue_possible(d:Dictionary,catalog:ContentCatalog,p:Dictionary,h:Dictionary)->bool:
	var requested:int=int(h.requested_tick)
	if int(p.completed_tick)>=0 and int(p.completed_tick)<=requested:return false
	if int(h.step_index)<p.steps.size():return true
	# A finished examination may genuinely wait for a clinical decision even
	# when no next step exists yet. Prove that gate from its historical step,
	# not the patient's present clinical_decision.state or physical position.
	if not CampaignClinicalDecisions.enabled(d) or int(h.step_index)<1:return false
	var last:Dictionary=p.step_history[int(h.step_index)-1]
	var definition:Dictionary=catalog.campaign.cases[p.case_id]
	var anchor:int=CampaignClinicalDecisions.anchor_index(definition)
	if (anchor<0 or last.step_id!=definition.steps[anchor].id) and ":decision:exam:" not in str(last.step_id):return false
	if not p.get("clinical_decision") is Dictionary or not p.clinical_decision.get("receipts") is Array:return false
	for value:Variant in p.clinical_decision.receipts:
		if not _fields(value,{"history_count":TYPE_INT,"tick":TYPE_INT,"sequence":TYPE_INT,"source":TYPE_STRING}):return false
		var receipt:Dictionary=value
		if int(receipt.history_count)!=int(h.step_index):continue
		if int(receipt.tick)<requested or (int(receipt.tick)==requested and receipt.source=="manual" and int(receipt.sequence)<int(h.request_sequence)):return false
	return true

static func _hire_tick(d:Dictionary,sid:String)->int:
	for value:Variant in d.command_receipts.values():
		if not value is Dictionary or not value.get("data") is Dictionary:continue
		var data:Dictionary=value.data
		var command:Variant=data.get("command",{})
		if command is Dictionary and command.get("type","") in ["hire","hire_staff"] and data.get("staff_id")==sid:return int(data.get("tick",-1))
	return -1

static func _staff(d:Dictionary,_catalog:ContentCatalog,s:Dictionary)->String:
	if not _fields(s,{"people_hired_tick":TYPE_INT,"morale":TYPE_INT,"wage_percent":TYPE_INT,"wellbeing_history":TYPE_ARRAY,"salary_request":TYPE_DICTIONARY}):return "missing_people_staff_fields"
	var hired:int=_hire_tick(d,str(s.id))
	if hired<0 or s.people_hired_tick!=hired:return "invalid_people_hire_clock"
	var expected:Array=[]
	for p:Dictionary in d.patients.values():
		for h:Dictionary in p.step_history:
			if h.kind=="patient" and int(h.completed_tick)>=0 and s.id in h.staff_ids:expected.append(_event("work","care:"+str(p.id)+":"+str(h.step_id),int(h.completed_tick),-1))
	for order:Dictionary in d.work_orders.values():
		if order.status!="done" or s.id not in order.staff_ids:continue
		expected.append(_event("work","operation:"+str(order.id),int(order.completed_tick),-1))
		if order.handler=="roster":expected.append(_event("roster","roster:"+str(order.id),int(order.completed_tick),5))
	for day:Variant in d.campaign.day_records:
		if not day is Dictionary or not day.get("end_tick") is int:return "invalid_people_payroll_day"
		var boundary:int=int(day.end_tick)
		if boundary<=hired:continue
		var paid:bool=false
		for entry:Dictionary in d.ledger_entries:
			if entry.category=="wages" and entry.reference=="payroll:"+str(boundary):paid=true;break
		expected.append(_event("payroll","payroll:"+str(boundary),boundary,1 if paid else -8))
	if CampaignPeople.autonomy_enabled(d):
		for h:Variant in d.campaign.staff_rest_events.values():
			if h is Dictionary and h.get("staff_id","")==s.id and h.get("completed_tick") is int and h.completed_tick>=0 and CampaignStaffRest.RULES.has(h.get("need","")):
				expected.append(_event("rest",str(h.get("id","")),int(h.completed_tick),int(CampaignStaffRest.RULES[h.need].morale_relief)))
	for value:Variant in d.command_receipts.values():
		if not value is Dictionary or not value.get("data") is Dictionary:continue
		var data:Dictionary=value.data
		var command:Variant=data.get("command",{})
		if not command is Dictionary or command.get("type","")!="set_staff_wage" or not command.get("payload") is Dictionary or command.payload.get("staff_id")!=s.id:continue
		if not command.payload.get("percent") is int or data.get("percent")!=command.payload.percent:return "invalid_people_wage_receipt"
		var event:Dictionary=_event("raise","command:"+str(command.id),int(data.tick),8)
		event.percent=int(command.payload.percent);event.sequence=int(data.sequence);expected.append(event)
	expected.sort_custom(func(a:Dictionary,b:Dictionary)->bool:
		if a.tick!=b.tick:return a.tick<b.tick
		var rank:Dictionary={"work":0,"roster":1,"rest":2,"payroll":3,"raise":4}
		if rank[a.kind]!=rank[b.kind]:return rank[a.kind]<rank[b.kind]
		if a.sequence!=b.sequence:return a.sequence<b.sequence
		return str(a.reference)<str(b.reference))
	if expected!=s.wellbeing_history:return "invalid_people_staff_event_proof"
	var percent:int=100
	for e:Dictionary in expected:
		if e.tick<hired or e.tick>d.tick:return "invalid_people_staff_event_clock"
		if e.kind=="raise":
			if e.percent not in [110,120,130,140,150] or int(e.percent)<=percent:return "invalid_people_wage_history"
			percent=int(e.percent)
	var projected:Dictionary=CampaignPeople._project_staff(expected,str(s.id))
	if s.morale!=projected.morale or s.wage_percent!=projected.percent or s.salary_request!=projected.request:return "forged_people_staff_wellbeing"
	return ""

static func _event(kind:String,reference:String,tick:int,delta:int)->Dictionary:
	return {"kind":kind,"reference":reference,"tick":tick,"delta":delta,"percent":0,"sequence":0}
