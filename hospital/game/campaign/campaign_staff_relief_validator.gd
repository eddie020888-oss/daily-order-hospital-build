class_name CampaignStaffReliefValidator
extends RefCounted

const COMMANDS:Array=["set_staff_relief","set_staff_relief_reserve","set_staff_relief_operations"]
const EVENT_SHAPE:Dictionary={"id":TYPE_STRING,"serial":TYPE_INT,"source":TYPE_STRING,"request_sequence":TYPE_INT,"facility_id":TYPE_STRING,"facility_kind":TYPE_STRING,"room_id":TYPE_STRING,"unit_id":TYPE_STRING,"owner_staff_id":TYPE_STRING,"relief_staff_id":TYPE_STRING,"slot_index":TYPE_INT,"work_cell":TYPE_INT,"rest_event_id":TYPE_STRING,"claim_tick":TYPE_INT,"claim_cell":TYPE_INT,"required_skill":TYPE_STRING,"arrived_tick":TYPE_INT,"release_requested_tick":TYPE_INT,"release_reason":TYPE_STRING,"left_tick":TYPE_INT,"finished_tick":TYPE_INT,"state":TYPE_STRING,"reservations":TYPE_ARRAY}

static func _fields(value:Variant,shape:Dictionary,exact:bool=false)->bool:
	if not value is Dictionary:return false
	if exact and value.size()!=shape.size():return false
	for key:String in shape:
		if not value.has(key) or typeof(value[key])!=int(shape[key]):return false
	return true

# Safe before ownership helpers: no receipt/history projection or casts yet.
static func shape_error(d:Dictionary)->String:
	var cp:Variant=d.get("campaign",{})
	if not cp is Dictionary:return "invalid_relief_campaign"
	if not cp.has("staff_relief_version"):
		for key:String in ["auto_staff_relief","staff_relief_pool","staff_relief_events","staff_relief_operations_version","auto_staff_relief_operations"]:
			if cp.has(key):return "orphan_staff_relief_fields"
		for value:Variant in d.get("staff",{}).values():
			if value is Dictionary and value.has("relief_activity"):return "orphan_staff_relief_activity"
		return ""
	if not CampaignPeople.autonomy_enabled(d) or not _fields(cp,{"staff_relief_version":TYPE_INT,"auto_staff_relief":TYPE_BOOL,"staff_relief_pool":TYPE_ARRAY,"staff_relief_events":TYPE_DICTIONARY}) or cp.staff_relief_version!=1:return "invalid_staff_relief_version"
	if cp.has("staff_relief_operations_version") or cp.has("auto_staff_relief_operations"):
		if not _fields(cp,{"staff_relief_operations_version":TYPE_INT,"auto_staff_relief_operations":TYPE_BOOL}) or cp.staff_relief_operations_version!=1:return "invalid_staff_relief_operations_version"
	var seen:Dictionary={}
	for sid:Variant in cp.staff_relief_pool:
		if not sid is String or seen.has(sid):return "invalid_staff_relief_pool"
		seen[sid]=true
	for key:Variant in cp.staff_relief_events:
		if not key is String or not _fields(cp.staff_relief_events[key],EVENT_SHAPE,true):return "invalid_staff_relief_event_shape"
		var h:Dictionary=cp.staff_relief_events[key]
		if h.id!=key or h.state not in ["walking","covering","draining","returning","done"]:return "invalid_staff_relief_event_identity"
		for row:Variant in h.reservations:
			if not _fields(row,{"patient_id":TYPE_STRING,"step_id":TYPE_STRING,"reserved_tick":TYPE_INT},true) and not _fields(row,{"work_order_id":TYPE_STRING,"reserved_tick":TYPE_INT},true):return "invalid_staff_relief_reservation_shape"
	for value:Variant in d.get("staff",{}).values():
		if not value is Dictionary or not value.get("relief_activity") is Dictionary:return "missing_staff_relief_activity"
		if not value.relief_activity.is_empty() and not _fields(value.relief_activity,{"event_id":TYPE_STRING},true):return "invalid_staff_relief_activity"
	return ""

static func _timeline(d:Dictionary)->Dictionary:
	var rows:Array=[]
	for receipt:Variant in d.get("command_receipts",{}).values():
		if not _fields(receipt,{"data":TYPE_DICTIONARY}) or not _fields(receipt.data,{"command":TYPE_DICTIONARY,"sequence":TYPE_INT,"tick":TYPE_INT}):return {"error":"invalid_relief_receipt"}
		rows.append(receipt.data)
	rows.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return int(a.sequence)<int(b.sequence))
	var pool:Array=[];var enabled:bool=false;var initialized:bool=false
	var operations_initialized:bool=false;var operations_enabled:bool=false;var operations_first_tick:int=-1
	var policies:Array=[];var homes:Dictionary={};var roles:Dictionary={};var current_home:Dictionary={};var dismissed:Dictionary={}
	var latest_tick:int=-1;var first_tick:int=-1
	var world:Dictionary={"rooms":{},"facilities":{},"workers":{},"next_facility":1}
	var world_index:Dictionary={"availability":{},"history_error":""}
	for row:Dictionary in rows:
		var command:Dictionary=row.command
		if not _fields(command,{"type":TYPE_STRING,"payload":TYPE_DICTIONARY}):return {"error":"invalid_relief_command"}
		var p:Dictionary=command.payload
		latest_tick=int(row.tick)
		match str(command.type):
			"hire","hire_staff":
				var sid:String=str(row.get("staff_id",""))
				roles[sid]=str(p.get("role",""));current_home[sid]="";homes[sid]=[{"tick":int(row.tick),"sequence":int(row.sequence),"facility_id":""}]
			"assign","assign_staff","unassign","dismiss","dismiss_staff":
				var sid:String=str(p.get("staff_id",""))
				if not homes.has(sid):return {"error":"unhired_relief_assignment"}
				if sid in pool and command.type in ["assign","assign_staff","dismiss","dismiss_staff"]:return {"error":"relief_pool_member_reassigned"}
				var home:String=str(p.get("facility_id","")) if command.type in ["assign","assign_staff"] else ""
				current_home[sid]=home;homes[sid].append({"tick":int(row.tick),"sequence":int(row.sequence),"facility_id":home})
				if command.type in ["dismiss","dismiss_staff"]:dismissed[sid]=int(row.tick)
			"set_staff_relief":
				if not _fields(p,{"enabled":TYPE_BOOL},true) or row.get("enabled")!=p.enabled or row.get("version")!=1:return {"error":"invalid_relief_policy_receipt"}
				if not initialized:first_tick=int(row.tick)
				initialized=true;enabled=p.enabled
				policies.append({"tick":int(row.tick),"sequence":int(row.sequence),"enabled":enabled,"pool":pool.duplicate(),"operations_enabled":operations_enabled})
			"set_staff_relief_operations":
				if not initialized or not _fields(p,{"enabled":TYPE_BOOL},true) or row.get("enabled")!=p.enabled or row.get("version")!=1:return {"error":"invalid_relief_operations_policy_receipt"}
				if not operations_initialized:operations_first_tick=int(row.tick)
				operations_initialized=true;operations_enabled=p.enabled
				policies.append({"tick":int(row.tick),"sequence":int(row.sequence),"enabled":enabled,"pool":pool.duplicate(),"operations_enabled":operations_enabled})
			"set_staff_relief_reserve":
				if not initialized or not _fields(p,{"staff_id":TYPE_STRING,"enabled":TYPE_BOOL},true) or row.get("staff_id")!=p.staff_id or row.get("enabled")!=p.enabled or not roles.has(p.staff_id) or dismissed.has(p.staff_id) or current_home.get(p.staff_id,"")!="":return {"error":"invalid_relief_pool_receipt"}
				if p.enabled and p.staff_id not in pool:pool.append(p.staff_id);pool.sort()
				elif not p.enabled:pool.erase(p.staff_id)
				policies.append({"tick":int(row.tick),"sequence":int(row.sequence),"enabled":enabled,"pool":pool.duplicate(),"operations_enabled":operations_enabled})
		CampaignStaffRestValidator._world_command(world,world_index,row)
		if world_index.history_error!="":return {"error":str(world_index.history_error)}
		for sid:String in world.workers:
			var actual_home:String=str(world.workers[sid].facility_id)
			if current_home.get(sid,"")!=actual_home:
				current_home[sid]=actual_home
				homes[sid].append({"tick":int(row.tick),"sequence":int(row.sequence),"facility_id":actual_home})
	return {"error":"","initialized":initialized,"enabled":enabled,"pool":pool,"policies":policies,"homes":homes,"roles":roles,"dismissed":dismissed,"first_tick":first_tick,"latest_tick":latest_tick,"rows":rows,"operations_initialized":operations_initialized,"operations_enabled":operations_enabled,"operations_first_tick":operations_first_tick}

static func _home_at(timeline:Dictionary,sid:String,tick:int)->String:
	var answer:String=""
	for row:Dictionary in timeline.homes.get(sid,[]):
		if int(row.tick)>=tick:break
		answer=str(row.facility_id)
	return answer

static func _policy_at(timeline:Dictionary,sequence:int,tick:int)->Dictionary:
	var result:Dictionary={"enabled":false,"pool":[],"operations_enabled":false}
	for row:Dictionary in timeline.policies:
		if int(row.sequence)>sequence:break
		if int(row.tick)>=tick:return {"enabled":false,"pool":[],"operations_enabled":false}
		result=row
	return result

static func _sequence_at(timeline:Dictionary,tick:int)->int:
	var result:int=0
	for row:Dictionary in timeline.rows:
		if int(row.tick)>=tick:break
		result=int(row.sequence)
	return result

static func _release_cause(_d:Dictionary,timeline:Dictionary,index:Dictionary,h:Dictionary,rest:Dictionary,is_operation:bool=false)->bool:
	var at:int=int(h.release_requested_tick)
	if at<0:return false
	var end:int=maxi(int(rest.completed_tick),int(rest.canceled_tick))
	if end>=0 and end<=at:return true
	for row:Dictionary in timeline.rows:
		if int(row.tick)>at:break
		if (row.command.type=="set_staff_relief" or (is_operation and row.command.type=="set_staff_relief_operations")) and row.command.payload.get("enabled",true)==false and int(row.tick)>=int(h.claim_tick):return true
	if CampaignStaffRestValidator._fatigue_query(index,h.relief_staff_id,at)>=64:return true
	if CampaignStaffRestValidator._morale_query(index,{"staff_id":h.relief_staff_id,"source":"auto","requested_tick":at,"request_sequence":_sequence_at(timeline,at)})<45:return true
	var available:bool=true
	for row:Dictionary in index.availability.get(h.facility_id,[]):
		if int(row.tick)>at:break
		available=bool(row.available)
	return not available

static func _trained(d:Dictionary,sid:String,unit:String,tick:int)->bool:
	for row:Dictionary in d.campaign.training:
		if row.staff_id==sid and row.unit_id==unit and int(row.tick)<=tick:return true
	return false

static func _distance(a:int,b:int)->int:
	return absi(a%GridService.WIDTH-b%GridService.WIDTH)+absi(int(a/GridService.WIDTH)-int(b/GridService.WIDTH))

static func _ends(h:Dictionary,now:int)->int:return int(h.finished_tick) if int(h.finished_tick)>=0 else now+1

static func validate(d:Dictionary,catalog:ContentCatalog)->String:
	var shape:String=shape_error(d)
	if shape!="":return shape
	if not d.campaign.has("staff_relief_version"):
		for receipt:Dictionary in d.command_receipts.values():
			if receipt.data.command.type in COMMANDS:return "orphan_staff_relief_command"
		return ""
	var timeline:Dictionary=_timeline(d)
	if timeline.error!="":return str(timeline.error)
	if not timeline.initialized or timeline.enabled!=d.campaign.auto_staff_relief or timeline.pool!=d.campaign.staff_relief_pool:return "forged_staff_relief_policy"
	if timeline.operations_initialized!=d.campaign.has("staff_relief_operations_version"):return "forged_relief_operations_configuration"
	if timeline.operations_initialized and timeline.operations_enabled!=d.campaign.auto_staff_relief_operations:return "forged_relief_operations_policy"
	for sid:String in d.campaign.staff_relief_pool:
		if not d.staff.has(sid) or d.staff[sid].facility_id!="":return "invalid_current_relief_pool_member"
	var records:Dictionary=d.campaign.staff_relief_events
	# All original People/Rest validation must have completed before this full
	# proof. Its existing indexed historical geometry includes the primary slot.
	var rest_index:Dictionary=CampaignStaffRestValidator._build_index(d) if not records.is_empty() else {"history_error":"","request_geometry":{}}
	if rest_index.get("history_error","")!="":return str(rest_index.history_error)
	var active:Dictionary={};var by_reserve:Dictionary={};var claimed:Dictionary={}
	var cares:Dictionary={};var orders:Dictionary={};var breaks:Dictionary={}
	for p:Dictionary in d.patients.values():
		for care:Dictionary in p.step_history:
			if care.kind!="patient":continue
			for sid:String in care.staff_ids:
				if not cares.has(sid):cares[sid]=[]
				cares[sid].append({"patient":p,"care":care})
	for order:Dictionary in d.work_orders.values():
		var involved:Array=order.staff_ids.duplicate()
		if order.get("trainee_id","")!="" and order.trainee_id not in involved:involved.append(order.trainee_id)
		for sid:String in involved:
			if not orders.has(sid):orders[sid]=[]
			orders[sid].append(order)
	for rest:Dictionary in d.campaign.staff_rest_events.values():
		if not breaks.has(rest.staff_id):breaks[rest.staff_id]=[]
		breaks[rest.staff_id].append(rest)
	for h:Dictionary in records.values():
		if h.source!="auto" or h.serial<1 or h.id!="relief:"+h.relief_staff_id+":"+str(h.serial) or h.owner_staff_id==h.relief_staff_id:return "invalid_relief_identity"
		if not timeline.roles.has(h.relief_staff_id) or not timeline.roles.has(h.owner_staff_id) or timeline.roles[h.relief_staff_id]!=timeline.roles[h.owner_staff_id]:return "invalid_relief_role"
		if h.claim_tick<0 or h.claim_tick>d.tick or h.request_sequence!=_sequence_at(timeline,int(h.claim_tick)) or not LongCampaignValidator._cell(h.claim_cell) or not LongCampaignValidator._cell(h.work_cell):return "invalid_relief_claim_clock"
		var policy:Dictionary=_policy_at(timeline,int(h.request_sequence),int(h.claim_tick))
		if not policy.enabled or h.relief_staff_id not in policy.pool or _home_at(timeline,h.relief_staff_id,int(h.claim_tick))!="":return "unearned_relief_claim"
		if CampaignStaffRestValidator._fatigue_query(rest_index,h.relief_staff_id,int(h.claim_tick))>=64:return "relief_claim_when_fatigued"
		if CampaignStaffRestValidator._morale_query(rest_index,{"staff_id":h.relief_staff_id,"source":"auto","requested_tick":h.claim_tick,"request_sequence":h.request_sequence})<45:return "relief_claim_when_morale_low"
		var rest:Dictionary=d.campaign.staff_rest_events.get(h.rest_event_id,{})
		if rest.is_empty() or rest.staff_id!=h.owner_staff_id or rest.workplace_id!=h.facility_id or int(rest.return_cell)!=int(h.work_cell) or int(rest.requested_tick)>int(h.claim_tick):return "unanchored_relief_primary_break"
		var end:int=maxi(int(rest.completed_tick),int(rest.canceled_tick))
		if end>=0 and h.claim_tick>=end:return "relief_claim_after_break_finished"
		var geometry:Dictionary=rest_index.request_geometry.get(h.rest_event_id,{})
		if geometry.get("workplace_id","")!=h.facility_id or geometry.get("home_kind","")!=h.facility_kind or geometry.get("home_room_id","")!=h.room_id or geometry.get("slot_index",-1)!=h.slot_index or int(geometry.get("return_cell",-1))!=h.work_cell:return "forged_relief_historical_workplace"
		var definition:Dictionary=catalog.campaign.facilities.get(h.facility_kind,{})
		var is_operation:bool=definition.get("kind","")!="patient"
		if (is_operation and (not CampaignStaffRelief._operation_definition_allowed(definition) or not policy.get("operations_enabled",false))) or definition.get("unit_id","")!=h.unit_id or str(timeline.roles[h.relief_staff_id]) not in definition.get("roles",[]):return "invalid_relief_facility_kind"
		if is_operation:
			var pending_at_claim:bool=false
			for order:Dictionary in d.work_orders.values():
				if order.facility_id==h.facility_id and CampaignStaffRelief._order_scope(catalog,order) and order.created_tick<h.claim_tick and (order.started_tick<0 or order.started_tick>=h.claim_tick) and (order.completed_tick<0 or order.completed_tick>=h.claim_tick):pending_at_claim=true;break
			if not pending_at_claim:return "unanchored_relief_pending_operation"
		var skill:String=h.unit_id if _trained(d,h.owner_staff_id,h.unit_id,int(h.claim_tick)) else ""
		if h.required_skill!=skill or (skill!="" and not _trained(d,h.relief_staff_id,skill,int(h.claim_tick))):return "unqualified_relief_specialist"
		for key:String in ["arrived_tick","release_requested_tick","left_tick","finished_tick"]:
			if int(h[key])< -1 or int(h[key])>int(d.tick):return "invalid_relief_event_clock"
		if h.arrived_tick>=0 and h.arrived_tick<h.claim_tick+_distance(h.claim_cell,h.work_cell)*4:return "relief_without_real_arrival"
		if h.release_requested_tick>=0 and h.release_requested_tick<h.claim_tick:return "premature_relief_release"
		if h.release_requested_tick>=0 and not _release_cause(d,timeline,rest_index,h,rest,is_operation):return "unproven_relief_release_cause"
		if h.left_tick>=0 and (h.release_requested_tick<0 or h.left_tick<h.release_requested_tick or (h.arrived_tick>=0 and h.left_tick<h.arrived_tick)):return "invalid_relief_departure_clock"
		if h.finished_tick>=0 and (h.left_tick<0 or h.finished_tick<h.left_tick or h.finished_tick<h.claim_tick+_distance(h.claim_cell,GridService.EXIT_CELL)*4):return "invalid_relief_return_clock"
		if h.finished_tick>=0 and h.arrived_tick>=0 and h.finished_tick<h.left_tick+maxi(0,_distance(h.work_cell,GridService.EXIT_CELL)-1)*4:return "relief_return_without_real_travel"
		if h.state=="walking" and (h.arrived_tick!=-1 or h.release_requested_tick!=-1 or h.left_tick!=-1 or h.finished_tick!=-1):return "invalid_relief_walking_state"
		if h.state=="covering" and (h.arrived_tick<0 or h.release_requested_tick!=-1 or h.left_tick!=-1 or h.finished_tick!=-1):return "invalid_relief_covering_state"
		if h.state=="draining" and (h.release_requested_tick<0 or h.left_tick!=-1 or h.finished_tick!=-1):return "invalid_relief_draining_state"
		if h.state=="returning" and (h.left_tick<0 or h.finished_tick!=-1):return "invalid_relief_returning_state"
		if h.state=="done" and h.finished_tick<0:return "invalid_relief_done_state"
		if timeline.dismissed.has(h.relief_staff_id) and (h.finished_tick<0 or h.finished_tick>int(timeline.dismissed[h.relief_staff_id])):return "relief_after_dismissal"
		if not by_reserve.has(h.relief_staff_id):by_reserve[h.relief_staff_id]=[]
		by_reserve[h.relief_staff_id].append(h)
		for other:Dictionary in records.values():
			if other.id==h.id or int(other.claim_tick)<int(h.claim_tick):continue
			if int(other.claim_tick)>=_ends(h,int(d.tick)):continue
			if other.relief_staff_id==h.relief_staff_id or (other.facility_id==h.facility_id and (other.owner_staff_id==h.owner_staff_id or other.work_cell==h.work_cell)):return "overlapping_relief_claims"
		var references:Dictionary={}
		for row:Dictionary in h.reservations:
			if row.has("work_order_id"):
				var order:Dictionary=d.work_orders.get(row.work_order_id,{})
				var order_key:String="order|"+str(row.work_order_id)
				if not is_operation or references.has(order_key) or claimed.has(order_key+"|"+h.relief_staff_id) or h.arrived_tick<0 or row.reserved_tick<h.arrived_tick or (h.release_requested_tick>=0 and row.reserved_tick>h.release_requested_tick) or (h.left_tick>=0 and row.reserved_tick>=h.left_tick):return "invalid_relief_operation_reservation"
				if order.is_empty() or not CampaignStaffRelief._order_scope(catalog,order) or order.facility_id!=h.facility_id or h.relief_staff_id not in order.staff_ids or order.created_tick>row.reserved_tick or order.status not in ["walking","working","done"] or (order.started_tick>=0 and order.started_tick<row.reserved_tick) or (h.left_tick>=0 and (order.completed_tick<0 or order.completed_tick>=h.left_tick)):return "invalid_relief_operation_proof"
				references[order_key]=row;claimed[order_key+"|"+h.relief_staff_id]=h
				continue
			if is_operation:return "operation_relief_has_clinical_reservation"
			var key:String=row.patient_id+"|"+row.step_id
			if references.has(key) or claimed.has(key+"|"+h.relief_staff_id) or row.reserved_tick<h.arrived_tick or h.arrived_tick<0 or (h.release_requested_tick>=0 and row.reserved_tick>h.release_requested_tick) or (h.left_tick>=0 and row.reserved_tick>=h.left_tick):return "invalid_relief_clinical_reservation"
			references[key]=row;claimed[key+"|"+h.relief_staff_id]=h
			var p:Dictionary=d.patients.get(row.patient_id,{})
			if p.is_empty():return "missing_relief_patient"
			var found:bool=false
			for care:Dictionary in p.step_history:
				if care.step_id!=row.step_id:continue
				if care.kind!="patient" or care.facility_id!=h.facility_id or h.relief_staff_id not in care.staff_ids or care.started_tick<row.reserved_tick or (h.left_tick>=0 and (care.completed_tick<0 or care.completed_tick>=h.left_tick)):return "invalid_relief_care_proof"
				found=true;break
			if not found and not (p.phase=="moving_care" and p.facility_id==h.facility_id and h.relief_staff_id in p.staff_ids and p.steps[p.step_index].id==row.step_id):return "orphan_relief_clinical_reservation"
		for row:Dictionary in cares.get(h.relief_staff_id,[]):
			var p:Dictionary=row.patient;var care:Dictionary=row.care
			var care_end:int=int(care.completed_tick) if int(care.completed_tick)>=0 else int(d.tick)+1
			if care_end<=h.claim_tick or care.started_tick>=_ends(h,int(d.tick)):continue
			if care.facility_id!=h.facility_id or care.started_tick<h.arrived_tick or not references.has(p.id+"|"+str(care.step_id)):return "double_booked_relief_clinical"
		for order:Dictionary in orders.get(h.relief_staff_id,[]):
			var begin:int=int(order.created_tick) if order.get("trainee_id","")==h.relief_staff_id else int(order.started_tick)
			var finish:int=int(order.completed_tick) if int(order.completed_tick)>=0 else int(d.tick)+1
			if begin>=0 and finish>=h.claim_tick and begin<_ends(h,int(d.tick)):
				if not is_operation or order.facility_id!=h.facility_id or order.get("trainee_id","")==h.relief_staff_id or not references.has("order|"+str(order.id)):return "double_booked_relief_operation_or_training"
			elif order.status=="walking" and h.relief_staff_id in order.staff_ids:
				if not is_operation or order.facility_id!=h.facility_id or not references.has("order|"+str(order.id)):return "unreserved_relief_walking_order"
		for other:Dictionary in breaks.get(h.relief_staff_id,[]):
			var finish:int=int(other.returned_tick) if int(other.returned_tick)>=0 else int(d.tick)+1
			if finish>h.claim_tick and other.requested_tick<_ends(h,int(d.tick)):return "double_booked_relief_break"
		if h.state in CampaignStaffRelief.ACTIVE:
			if active.has(h.relief_staff_id) or not d.staff.has(h.relief_staff_id):return "orphan_active_relief"
			active[h.relief_staff_id]=h.id
			var s:Dictionary=d.staff[h.relief_staff_id]
			if s.facility_id!="" or s.room_id!="" or s.get("training_order_id","")!="" or not s.rest_activity.is_empty():return "double_booked_active_relief"
			if s.work_order_id!="" and (not is_operation or not references.has("order|"+str(s.work_order_id)) or h.state not in ["covering","draining"]):return "unproven_active_relief_order"
			if is_operation and s.patient_id!="":return "operation_relief_has_patient"
			if h.state in ["walking","returning"] and s.patient_id!="":return "moving_relief_has_patient"
			var f:Dictionary=d.facilities.get(h.facility_id,{})
			if f.is_empty() or h.slot_index<0 or h.slot_index>=f.staff_ids.size() or f.staff_ids[h.slot_index]!=h.owner_staff_id or f.staff_cells[h.slot_index]!=h.work_cell:return "changed_active_relief_workplace"
			if h.state=="covering" and (s.cell!=h.work_cell or s.move_progress!=0):return "active_relief_not_at_post"
			if h.state in ["returning"] and (s.cell==h.work_cell or CampaignStaffRelief._entering(s,h.work_cell)):return "premature_relief_work_cell_release"
	for sid:String in by_reserve:
		var events:Array=by_reserve[sid];events.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return int(a.serial)<int(b.serial))
		for index:int in range(events.size()):
			if events[index].serial!=index+1:return "invalid_relief_serial"
	for sid:String in d.staff:
		var expected:Dictionary={"event_id":active[sid]} if active.has(sid) else {}
		if d.staff[sid].relief_activity!=expected:return "orphan_relief_activity"
	# New ordinary work must either retain its public primary assignment at
	# start or name one of the already proven coverage reservations above.
	for p:Dictionary in d.patients.values():
		for care:Dictionary in p.step_history:
			if care.kind!="patient" or care.started_tick<=int(timeline.first_tick):continue
			for sid:String in care.staff_ids:
				if _home_at(timeline,sid,int(care.started_tick))==care.facility_id:continue
				if not claimed.has(p.id+"|"+str(care.step_id)+"|"+sid):return "unproven_relief_clinical_owner"
	if timeline.operations_initialized:
		for order:Dictionary in d.work_orders.values():
			if order.started_tick<=int(timeline.operations_first_tick):continue
			for sid:String in order.staff_ids:
				if _home_at(timeline,sid,int(order.started_tick))==order.facility_id:continue
				if not claimed.has("order|"+str(order.id)+"|"+sid):return "unproven_relief_operation_owner"
	return ""
