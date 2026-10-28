class_name CampaignStaffRestValidator
extends RefCounted

static func _fields(value:Variant,shape:Dictionary)->bool:
	return CampaignPeopleValidator._fields(value,shape)

static func _distance(a:int,b:int)->int:
	return absi(a%GridService.WIDTH-b%GridService.WIDTH)+absi(int(a/GridService.WIDTH)-int(b/GridService.WIDTH))

# Local to a single validation. No indexes or counters enter saved state.
static func _bucket(index:Dictionary,sid:String)->Dictionary:
	if not index.staff.has(sid):index.staff[sid]={"fatigue":[],"morale":[],"care":[],"operations":[],"operation_ends":{},"rest_positions":{}}
	return index.staff[sid]

static func _event_less(a:Dictionary,b:Dictionary)->bool:
	if a.tick!=b.tick:return a.tick<b.tick
	if a.rank!=b.rank:return a.rank<b.rank
	if int(a.get("sequence",0))!=int(b.get("sequence",0)):return int(a.get("sequence",0))<int(b.get("sequence",0))
	return str(a.reference)<str(b.reference)

static func _stream(events:Array,initial:int)->Array:
	events.sort_custom(_event_less)
	var values:Array=[]
	var value:int=initial
	for e:Dictionary in events:
		value=clampi(value+int(e.delta),0,100)
		values.append(value)
	return values

static func _interval_index(events:Array)->Dictionary:
	events.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return int(a.start)<int(b.start))
	var starts:Array=[]
	var maximums:Array=[]
	var maximum:int=-1
	for e:Dictionary in events:
		starts.append(int(e.start));maximum=maxi(maximum,int(e.end));maximums.append(maximum)
	return {"starts":starts,"maximums":maximums}

static func _build_index(d:Dictionary)->Dictionary:
	var index:Dictionary={"staff":{},"identities":{},"rows":{},"policies":{0:{"valid":true,"staff_rest":true}},"policy_ticks":{0:-1},"charges":{},"paid":{},"world_events":[],"request_geometry":{},"availability":{},"history_error":"","visits":{"patients":0,"clinical_rows":0,"orders":0,"rest_rows":0,"ledger_rows":0,"receipts":0,"day_rows":0}}
	for row:Dictionary in d.ledger_entries:
		index.visits.ledger_rows+=1
		if not index.charges.has(row.reference):index.charges[row.reference]=[]
		index.charges[row.reference].append(row)
		if row.category=="wages":index.paid[row.reference]=true
	for receipt:Dictionary in d.command_receipts.values():
		index.visits.receipts+=1
		var row:Dictionary=receipt.data
		index.rows[int(row.sequence)]=row
		index.world_events.append({"tick":int(row.tick),"phase":4,"sequence":int(row.sequence),"action":0,"type":"command","row":row})
		var command:Dictionary=row.command
		if command.type in ["hire","hire_staff"]:
			var sid:String=str(row.get("staff_id",""))
			if not index.identities.has(sid):index.identities[sid]={"hired":-1,"dismissed":-1}
			index.identities[sid].hired=int(row.tick)
			_bucket(index,sid)
		elif command.type in ["dismiss","dismiss_staff"]:
			var sid:String=str(command.payload.get("staff_id",""))
			if not index.identities.has(sid):index.identities[sid]={"hired":-1,"dismissed":-1}
			index.identities[sid].dismissed=int(row.tick)
		elif command.type=="set_staff_wage":
			_bucket(index,str(command.payload.get("staff_id",""))).morale.append({"tick":int(row.tick),"rank":4,"sequence":int(row.sequence),"reference":"command:"+str(command.id),"delta":8})
	var policy:Dictionary={"valid":true,"staff_rest":true}
	var maximum_tick:int=-1
	for n:int in range(1,int(d.command_sequence)+1):
		if not index.rows.has(n):policy.valid=false
		else:
			var row:Dictionary=index.rows[n]
			maximum_tick=maxi(maximum_tick,int(row.tick))
			if row.command.type=="set_people_autonomy":
				var p:Dictionary=row.command.payload
				if p.size()!=2 or not p.get("patient_needs") is bool or not p.get("staff_rest") is bool or row.get("patient_needs")!=p.get("patient_needs") or row.get("staff_rest")!=p.get("staff_rest"):policy.valid=false
				else:policy.staff_rest=p.staff_rest
		index.policies[n]=policy.duplicate()
		index.policy_ticks[n]=maximum_tick
	for p:Dictionary in d.patients.values():
		index.visits.patients+=1
		for care:Dictionary in p.step_history:
			index.visits.clinical_rows+=1
			if care.kind!="patient":continue
			var end:int=int(care.completed_tick) if int(care.completed_tick)>=0 else int(d.tick)+1
			for sid:String in care.staff_ids:
				var bucket:Dictionary=_bucket(index,sid)
				if end>int(care.started_tick):bucket.care.append({"start":int(care.started_tick),"end":end})
				if int(care.completed_tick)>=0:
					var reference:String="care:"+str(p.id)+":"+str(care.step_id)
					bucket.fatigue.append({"tick":int(care.completed_tick),"rank":0,"reference":reference,"delta":8})
					bucket.morale.append({"tick":int(care.completed_tick),"rank":0,"sequence":0,"reference":reference,"delta":-1})
			if int(care.completed_tick)>=0:index.world_events.append({"tick":int(care.completed_tick),"phase":0,"sequence":0,"action":0,"type":"wear","facility_id":str(care.facility_id)})
	for order:Dictionary in d.work_orders.values():
		index.visits.orders+=1
		if int(order.started_tick)>=0:
			var involved:Array=order.staff_ids.duplicate()
			if order.get("trainee_id","")!="" and order.trainee_id not in involved:involved.append(order.trainee_id)
			for sid:String in involved:
				var bucket:Dictionary=_bucket(index,sid)
				var end:int=int(order.completed_tick) if int(order.completed_tick)>=0 else int(d.tick)+1
				if end>int(order.started_tick):bucket.operations.append({"start":int(order.started_tick),"end":end})
				bucket.operation_ends[int(order.completed_tick)]=true
		if order.status!="done":continue
		for sid:String in order.staff_ids:
			var bucket:Dictionary=_bucket(index,sid)
			bucket.fatigue.append({"tick":int(order.completed_tick),"rank":2,"reference":str(order.id),"delta":8})
			bucket.morale.append({"tick":int(order.completed_tick),"rank":0,"sequence":0,"reference":"operation:"+str(order.id),"delta":-1})
			if order.handler=="roster":
				bucket.fatigue.append({"tick":int(order.completed_tick),"rank":3,"reference":str(order.id),"delta":-25})
				bucket.morale.append({"tick":int(order.completed_tick),"rank":1,"sequence":0,"reference":"roster:"+str(order.id),"delta":5})
		index.world_events.append({"tick":int(order.completed_tick),"phase":2,"sequence":int(str(order.id).trim_prefix("work_")),"action":0,"type":"operation","order":order})
	for h:Dictionary in d.campaign.staff_rest_events.values():
		index.visits.rest_rows+=1
		var bucket:Dictionary=_bucket(index,str(h.staff_id))
		if int(h.completed_tick)>=0:
			var rule:Dictionary=CampaignStaffRest.RULES[h.need]
			bucket.fatigue.append({"tick":int(h.completed_tick),"rank":1,"reference":str(h.id),"delta":-int(rule.fatigue_relief)})
			bucket.morale.append({"tick":int(h.completed_tick),"rank":2,"sequence":0,"reference":str(h.id),"delta":int(rule.morale_relief)})
		index.world_events.append({"tick":int(h.requested_tick),"phase":1 if h.source=="auto" else 4,"sequence":int(h.request_sequence) if h.source=="manual" else 0,"action":1,"type":"request","history":h})
	for day:Dictionary in d.campaign.day_records:
		index.visits.day_rows+=1
		for sid:String in index.identities:
			if int(day.end_tick)<=int(index.identities[sid].hired):continue
			var reference:String="payroll:"+str(day.end_tick)
			_bucket(index,sid).morale.append({"tick":int(day.end_tick),"rank":3,"sequence":0,"reference":reference,"delta":1 if index.paid.has(reference) else -8})
	for event:Variant in d.campaign.events:
		if event is Dictionary and event.get("definition_id","")=="breakdown" and event.get("created_tick") is int and event.get("target_facility_id") is String:
			index.world_events.append({"tick":int(event.created_tick),"phase":3,"sequence":0,"action":0,"type":"breakdown","facility_id":str(event.target_facility_id),"condition":20 if event.get("power_buffered",false) else 0})
	for sid:String in index.staff:
		var bucket:Dictionary=index.staff[sid]
		bucket.fatigue_values=_stream(bucket.fatigue,0)
		bucket.morale_values=_stream(bucket.morale,70)
		for n:int in range(bucket.fatigue.size()):
			if int(bucket.fatigue[n].rank)==1:bucket.rest_positions[bucket.fatigue[n].reference]=n
		bucket.care_index=_interval_index(bucket.care)
		bucket.operation_index=_interval_index(bucket.operations)
	_world_replay(index)
	return index

static func _fatigue_query(index:Dictionary,sid:String,at_tick:int,exclude_rest:String="")->int:
	if not index.staff.has(sid):return 0
	var bucket:Dictionary=index.staff[sid]
	var events:Array=bucket.fatigue
	var low:int=0
	var high:int=events.size()
	while low<high:
		var middle:int=int((low+high)/2)
		if int(events[middle].tick)<=at_tick:low=middle+1
		else:high=middle
	if low==0:return 0
	if exclude_rest=="" or not bucket.rest_positions.has(exclude_rest) or int(bucket.rest_positions[exclude_rest])>=low:return int(bucket.fatigue_values[low-1])
	var position:int=int(bucket.rest_positions[exclude_rest])
	var value:int=int(bucket.fatigue_values[position-1]) if position>0 else 0
	# Completion queries exclude this rest but retain every later same-tick
	# event. This also preserves the frozen validator's malformed-input result.
	for n:int in range(position+1,low):value=clampi(value+int(events[n].delta),0,100)
	return value

static func _morale_query(index:Dictionary,h:Dictionary)->int:
	if not index.staff.has(h.staff_id):return 70
	var bucket:Dictionary=index.staff[h.staff_id]
	var events:Array=bucket.morale
	var rank:int=2 if h.source=="auto" else 4
	var low:int=0
	var high:int=events.size()
	while low<high:
		var middle:int=int((low+high)/2)
		var e:Dictionary=events[middle]
		var before:bool=int(e.tick)<int(h.requested_tick) or (int(e.tick)==int(h.requested_tick) and (int(e.rank)<rank or (int(e.rank)==rank and int(e.get("sequence",0))<=int(h.request_sequence))))
		if before:low=middle+1
		else:high=middle
	return int(bucket.morale_values[low-1]) if low>0 else 70

static func _policy_query(index:Dictionary,sequence:int,at_tick:int,maximum:int)->Dictionary:
	if sequence<0 or sequence>maximum or not index.policies.has(sequence):return {"valid":false}
	var policy:Dictionary=index.policies[sequence]
	if not policy.valid or int(index.policy_ticks[sequence])>=at_tick:return {"valid":false}
	if sequence<maximum and (not index.rows.has(sequence+1) or int(index.rows[sequence+1].tick)<at_tick):return {"valid":false}
	return policy

static func _interval_overlap(intervals:Dictionary,start:int,end:int)->bool:
	var low:int=0
	var high:int=intervals.starts.size()
	while low<high:
		var middle:int=int((low+high)/2)
		if int(intervals.starts[middle])<end:low=middle+1
		else:high=middle
	return low>0 and int(intervals.maximums[low-1])>start

static func _work_overlap_index(index:Dictionary,h:Dictionary,tick:int)->String:
	if not index.staff.has(h.staff_id):return ""
	var bucket:Dictionary=index.staff[h.staff_id]
	var end:int=int(h.returned_tick) if int(h.returned_tick)>=0 else tick+1
	if _interval_overlap(bucket.care_index,int(h.requested_tick),end):return "staff_rest_overlaps_care"
	if bucket.operation_ends.has(int(h.requested_tick)) or _interval_overlap(bucket.operation_index,int(h.requested_tick),end):return "staff_rest_overlaps_operation"
	return ""

static func _availability(index:Dictionary,fid:String,tick:int,available:bool)->void:
	if not index.availability.has(fid):index.availability[fid]=[]
	var rows:Array=index.availability[fid]
	if not rows.is_empty() and int(rows[-1].tick)==tick:rows[-1].available=available
	elif rows.is_empty() or bool(rows[-1].available)!=available:rows.append({"tick":tick,"available":available})

static func _world_install(world:Dictionary,index:Dictionary,room_id:String,layout:Dictionary,tick:int)->void:
	var room:Dictionary=world.rooms[room_id]
	var preserved:Dictionary={}
	for fid:String in world.facilities.keys():
		if world.facilities[fid].room_id==room_id:preserved[fid]=world.facilities[fid];world.facilities.erase(fid)
	var retained:Dictionary={}
	for item:Variant in layout.get("facilities",[]):
		if not item is Dictionary or not item.get("kind") is String or not item.get("x") is int or not item.get("y") is int or not item.get("rotation") is int:
			index.history_error="invalid_staff_rest_layout_history";return
		if not preserved.has(item.get("id","")):
			item.id="facility_%04d"%int(world.next_facility);world.next_facility+=1
		var fid:String=str(item.id)
		var f:Dictionary=preserved.get(fid,{"kind":str(item.kind),"room_id":room_id,"condition":100,"status":"open","staff_ids":[]})
		var geometry:Dictionary=FacilityLayout.facility_geometry(room,item)
		if geometry.is_empty():index.history_error="invalid_staff_rest_layout_history";return
		f.service_cells=geometry.service_cells;f.staff_cells=geometry.staff_cells
		world.facilities[fid]=f;retained[fid]=true
		_availability(index,fid,tick+1,f.status=="open" and int(f.condition)>0)
	for fid:String in preserved:
		if retained.has(fid):continue
		_availability(index,fid,tick+1,false)
		for worker:Dictionary in world.workers.values():
			if worker.facility_id==fid:worker.facility_id=""
	room.layout=layout

static func _world_detach(world:Dictionary,sid:String)->void:
	if not world.workers.has(sid):return
	var worker:Dictionary=world.workers[sid]
	if world.facilities.has(worker.facility_id):world.facilities[worker.facility_id].staff_ids.erase(sid)
	worker.facility_id=""

static func _world_command(world:Dictionary,index:Dictionary,row:Dictionary)->void:
	var command:Dictionary=row.command
	var p:Dictionary=command.payload
	var tick:int=int(row.tick)
	match command.type:
		"build_department","edit_department","place_facility":
			var room_id:String=str(row.get("room_id",p.get("room_id","")))
			if command.type=="build_department":
				if not p.get("origin_cell") is int:index.history_error="invalid_staff_rest_layout_history";return
				world.rooms[room_id]={"id":room_id,"origin_cell":int(p.origin_cell),"layout":{}}
			if not world.rooms.has(room_id):index.history_error="invalid_staff_rest_layout_history";return
			var layout:Dictionary={}
			if command.type=="place_facility":
				layout=world.rooms[room_id].layout.duplicate(true)
				layout.facilities.append({"id":"","kind":p.get("kind",""),"x":p.get("x",0),"y":p.get("y",0),"rotation":p.get("rotation",0)})
			else:
				if not p.get("layout") is Dictionary:index.history_error="invalid_staff_rest_layout_history";return
				layout=p.layout.duplicate(true)
			_world_install(world,index,room_id,layout,tick)
		"remove_facility":
			var fid:String=str(p.get("facility_id",""))
			if not world.facilities.has(fid):index.history_error="invalid_staff_rest_layout_history";return
			var room_id:String=str(world.facilities[fid].room_id)
			var layout:Dictionary=world.rooms[room_id].layout.duplicate(true)
			for item:Dictionary in layout.facilities.duplicate():
				if item.id==fid:layout.facilities.erase(item)
			_world_install(world,index,room_id,layout,tick)
		"remove_room":
			var room_id:String=str(p.get("room_id",""))
			for fid:String in world.facilities.keys():
				if world.facilities[fid].room_id!=room_id:continue
				world.facilities.erase(fid);_availability(index,fid,tick+1,false)
				for worker:Dictionary in world.workers.values():
					if worker.facility_id==fid:worker.facility_id=""
			world.rooms.erase(room_id)
		"hire","hire_staff":world.workers[str(row.get("staff_id",""))]={"facility_id":""}
		"assign","assign_staff":
			var sid:String=str(p.get("staff_id",""))
			var fid:String=str(p.get("facility_id",""))
			_world_detach(world,sid)
			if not world.workers.has(sid) or not world.facilities.has(fid):index.history_error="invalid_staff_rest_assignment_history";return
			world.workers[sid].facility_id=fid
			world.facilities[fid].staff_ids.append(sid)
		"unassign":_world_detach(world,str(p.get("staff_id","")))
		"dismiss","dismiss_staff":
			_world_detach(world,str(p.get("staff_id","")));world.workers.erase(str(p.get("staff_id","")))
		"close_facility","reopen_facility":
			var fid:String=str(p.get("facility_id",""))
			if world.facilities.has(fid):
				world.facilities[fid].status="closed" if command.type=="close_facility" else "open"
				_availability(index,fid,tick+1,world.facilities[fid].status=="open" and int(world.facilities[fid].condition)>0)

static func _world_replay(index:Dictionary)->void:
	index.world_events.sort_custom(func(a:Dictionary,b:Dictionary)->bool:
		if a.tick!=b.tick:return a.tick<b.tick
		if a.phase!=b.phase:return a.phase<b.phase
		if a.sequence!=b.sequence:return a.sequence<b.sequence
		return a.action<b.action)
	var world:Dictionary={"rooms":{},"facilities":{},"workers":{},"next_facility":1}
	for event:Dictionary in index.world_events:
		if event.type=="command":_world_command(world,index,event.row)
		elif event.type=="request":
			var h:Dictionary=event.history
			var f:Dictionary=world.facilities.get(h.facility_id,{})
			var home_id:String=str(world.workers.get(h.staff_id,{}).get("facility_id",""))
			var home:Dictionary=world.facilities.get(home_id,{})
			var return_cell:int=GridService.EXIT_CELL
			var relief_slot:int=-1
			if not home.is_empty():
				var place:int=home.staff_ids.find(h.staff_id)
				relief_slot=place
				return_cell=int(home.staff_cells[place]) if place>=0 and place<home.staff_cells.size() else -1
			index.request_geometry[h.id]={"exists":not f.is_empty(),"kind":str(f.get("kind","")),"target_cell":int(f.service_cells[0]) if not f.get("service_cells",[]).is_empty() else -1,"available":not f.is_empty() and f.status=="open" and int(f.condition)>0,"workplace_id":home_id,"return_cell":return_cell,"slot_index":relief_slot,"home_kind":str(home.get("kind","")),"home_room_id":str(home.get("room_id",""))}
		elif event.type in ["wear","operation","breakdown"]:
			var fid:String=str(event.get("facility_id",event.get("order",{}).get("facility_id","")))
			if world.facilities.has(fid):
				var f:Dictionary=world.facilities[fid]
				f.condition=int(event.condition) if event.type=="breakdown" else maxi(0,int(f.condition)-2)
				_availability(index,fid,int(event.tick)+(0 if int(event.phase)==0 else 1),f.status=="open" and int(f.condition)>0)
			if event.type=="operation" and event.order.handler=="repair":
				var target:String=str(event.order.get("target_facility_id",""))
				if not world.facilities.has(target):
					target=""
					var machine_ids:Array=world.facilities.keys()
					machine_ids.sort()
					for machine_id:String in machine_ids:
						if int(world.facilities[machine_id].condition)<100:target=machine_id;break
				if target!="":
					world.facilities[target].condition=100
					_availability(index,target,int(event.tick)+1,world.facilities[target].status=="open")
		if index.history_error!="":return
	# Collapse same-tick/redundant updates and prepare binary-searchable false ticks.
	for fid:String in index.availability:
		var clean:Array=[]
		var false_ticks:Array=[]
		for row:Dictionary in index.availability[fid]:
			if not clean.is_empty() and bool(clean[-1].available)==bool(row.available):continue
			clean.append(row)
			if not row.available:false_ticks.append(int(row.tick))
		index.availability[fid]={"rows":clean,"false_ticks":false_ticks}

static func _expected_cancel(index:Dictionary,h:Dictionary)->int:
	var first_tick:int=int(h.requested_tick)+1
	var deadline:int=int(h.requested_tick)+CampaignStaffRest.TIMEOUT+1
	if not index.availability.has(h.facility_id):return first_tick
	var changes:Dictionary=index.availability[h.facility_id]
	var rows:Array=changes.rows
	var low:int=0
	var high:int=rows.size()
	while low<high:
		var middle:int=int((low+high)/2)
		if int(rows[middle].tick)<=first_tick:low=middle+1
		else:high=middle
	if low==0 or not bool(rows[low-1].available):return first_tick
	var unavailable:Array=changes.false_ticks
	low=0;high=unavailable.size()
	while low<high:
		var middle:int=int((low+high)/2)
		if int(unavailable[middle])<=first_tick:low=middle+1
		else:high=middle
	return mini(deadline,int(unavailable[low])) if low<unavailable.size() else deadline


static func validate(d:Dictionary,_catalog:ContentCatalog)->String:
	if not CampaignPeople.autonomy_enabled(d):return ""
	var records:Variant=d.campaign.get("staff_rest_events")
	if not records is Dictionary:return "invalid_staff_rest_events"
	var shape:Dictionary={"id":TYPE_STRING,"staff_id":TYPE_STRING,"serial":TYPE_INT,"need":TYPE_STRING,"source":TYPE_STRING,"request_reference":TYPE_STRING,"request_sequence":TYPE_INT,"requested_tick":TYPE_INT,"request_cell":TYPE_INT,"move_ticks":TYPE_INT,"facility_id":TYPE_STRING,"facility_kind":TYPE_STRING,"target_cell":TYPE_INT,"workplace_id":TYPE_STRING,"return_cell":TYPE_INT,"state":TYPE_STRING,"started_tick":TYPE_INT,"completed_tick":TYPE_INT,"canceled_tick":TYPE_INT,"departed_tick":TYPE_INT,"returned_tick":TYPE_INT,"needed":TYPE_INT,"cost":TYPE_INT,"resource":TYPE_STRING,"quantity":TYPE_INT,"fatigue_before":TYPE_INT,"fatigue_after":TYPE_INT,"request_fatigue":TYPE_INT,"request_morale":TYPE_INT}
	var by_staff:Dictionary={}
	var reservations:Dictionary={}
	var active:Dictionary={}
	var requests:Dictionary={}
	for p:Dictionary in d.patients.values():
		if p.need_activity.is_empty():continue
		reservations[str(p.need_activity.facility_id)+":0"]=p.id
	# First prove all shapes before any fatigue projection visits other records.
	for key:Variant in records:
		if not key is String or not _fields(records[key],shape):return "invalid_staff_rest_shape"
		var h:Dictionary=records[key]
		if key!=h.id or not CampaignStaffRest.RULES.has(h.need):return "invalid_staff_rest_identity"
		if not by_staff.has(h.staff_id):by_staff[h.staff_id]=[]
		by_staff[h.staff_id].append(h)
	var evidence:Dictionary=_build_index(d)
	if evidence.history_error!="":return str(evidence.history_error)
	for sid:String in by_staff:
		var identity:Dictionary=evidence.identities.get(sid,{"hired":-1,"dismissed":-1})
		if int(identity.hired)<0:return "unhired_staff_rest_owner"
		var rows:Array=by_staff[sid]
		rows.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return a.serial<b.serial)
		var prior_return:int=int(identity.hired)
		var last_end:int=-CampaignStaffRest.COOLDOWN
		for index:int in range(rows.size()):
			var h:Dictionary=rows[index]
			var rule:Dictionary=CampaignStaffRest.RULES[h.need]
			if h.serial!=index+1 or h.id!="rest:"+sid+":"+str(index+1):return "invalid_staff_rest_serial"
			if h.facility_kind!=rule.facility_kind or h.needed!=rule.needed or h.cost!=rule.cost or h.resource!=rule.resource or h.quantity!=rule.quantity:return "forged_staff_rest_definition"
			if not LongCampaignValidator._id(h.facility_id,"facility",int(d.next_ids.facility)) or (h.workplace_id!="" and not LongCampaignValidator._id(h.workplace_id,"facility",int(d.next_ids.facility))):return "invalid_staff_rest_facility_identity"
			if not LongCampaignValidator._cell(h.target_cell) or not LongCampaignValidator._cell(h.request_cell) or not LongCampaignValidator._cell(h.return_cell) or h.move_ticks!=4:return "invalid_staff_rest_target"
			if h.requested_tick<prior_return or h.requested_tick>d.tick or int(h.requested_tick)-last_end<CampaignStaffRest.COOLDOWN:return "invalid_staff_rest_request_clock"
			if h.state not in ["walking","using","returning","done","canceled"] or h.started_tick< -1 or h.completed_tick< -1 or h.canceled_tick< -1 or h.departed_tick< -1 or h.returned_tick< -1:return "invalid_staff_rest_clock"
			if h.source=="auto":
				var policy:Dictionary=_policy_query(evidence,int(h.request_sequence),int(h.requested_tick),int(d.command_sequence))
				if not policy.get("valid",false) or not policy.get("staff_rest",false) or h.request_reference!="auto_rest:"+sid+":"+str(h.serial):return "unearned_automatic_staff_rest"
			else:
				if h.source!="manual":return "invalid_staff_rest_source"
				var receipt:Dictionary=CampaignPeopleValidator._receipt(d,str(h.request_reference))
				var command:Dictionary=receipt.get("command",{})
				if command.get("type","")!="request_staff_rest" or command.get("payload",{}).get("staff_id","")!=sid or command.get("payload",{}).get("need","")!=h.need:return "unanchored_manual_staff_rest"
				if receipt.get("tick")!=h.requested_tick or receipt.get("sequence")!=h.request_sequence or receipt.get("event_id")!=h.id or receipt.get("facility_id")!=h.facility_id or receipt.get("target_cell")!=h.target_cell or receipt.get("request_cell")!=h.request_cell or receipt.get("return_cell")!=h.return_cell:return "invalid_manual_staff_rest_receipt"
				if requests.has(h.request_reference):return "reused_manual_staff_rest_receipt"
				requests[h.request_reference]=true
			if h.started_tick>=0:
				if h.started_tick<int(h.requested_tick)+_distance(int(h.request_cell),int(h.target_cell))*4 or h.started_tick>d.tick or h.canceled_tick!=-1:return "staff_rest_without_real_arrival"
				var count:int=0
				for entry:Dictionary in evidence.charges.get(h.id,[]):
					if entry.reference!=h.id:continue
					if entry.tick!=h.started_tick or entry.category!="operations" or entry.amount!=-int(h.cost):return "invalid_staff_rest_charge"
					count+=1
				if count!=1:return "missing_staff_rest_charge"
			else:
				for entry:Dictionary in evidence.charges.get(h.id,[]):
					if entry.reference==h.id:return "premature_staff_rest_charge"
			if h.completed_tick>=0:
				if h.started_tick<0 or h.completed_tick!=int(h.started_tick)+int(h.needed) or h.completed_tick>d.tick:return "invalid_staff_rest_service_clock"
				var before:int=_fatigue_query(evidence,sid,int(h.completed_tick),str(h.id))
				if h.fatigue_before!=before or h.fatigue_after!=maxi(0,before-int(rule.fatigue_relief)):return "forged_staff_rest_relief"
			elif h.fatigue_before!=-1 or h.fatigue_after!=-1:return "premature_staff_rest_relief"
			if h.canceled_tick>=0 and (h.started_tick!=-1 or h.canceled_tick<h.requested_tick or h.canceled_tick>d.tick):return "invalid_staff_rest_cancel_clock"
			var end:int=maxi(int(h.completed_tick),int(h.canceled_tick))
			if h.departed_tick>=0 and (end<0 or h.departed_tick<end or h.departed_tick>d.tick):return "invalid_staff_rest_departure_clock"
			if h.returned_tick>=0 and (h.departed_tick<0 or h.returned_tick<h.departed_tick or h.returned_tick>d.tick or h.returned_tick<end+_distance(int(h.target_cell),int(h.return_cell))*4 and h.completed_tick>=0):return "invalid_staff_rest_return_clock"
			if h.state=="walking" and (h.started_tick!=-1 or end!=-1 or h.departed_tick!=-1 or h.returned_tick!=-1):return "invalid_staff_rest_walking_state"
			if h.state=="using" and (h.started_tick<0 or end!=-1 or h.departed_tick!=-1 or h.returned_tick!=-1 or int(d.tick)-int(h.started_tick)>=int(h.needed)):return "invalid_staff_rest_using_state"
			if h.state=="returning" and (end<0 or h.returned_tick!=-1):return "invalid_staff_rest_returning_state"
			if h.state=="done" and (h.completed_tick<0 or h.returned_tick<0):return "invalid_staff_rest_done_state"
			if h.state=="canceled" and (h.canceled_tick<0 or h.returned_tick<0):return "invalid_staff_rest_canceled_state"
			var overlap_error:String=_work_overlap_index(evidence,h,int(d.tick))
			if overlap_error!="":return overlap_error
			if h.request_fatigue!=_fatigue_query(evidence,sid,int(h.requested_tick)):return "forged_staff_rest_request_fatigue"
			if h.source=="auto" and h.request_fatigue<64 and h.request_morale>=45:return "automatic_staff_rest_not_due"
			if h.request_morale<0 or h.request_morale>100:return "invalid_staff_rest_request_morale"
			if h.request_morale!=_morale_query(evidence,h):return "forged_staff_rest_request_morale"
			if identity.dismissed>=0 and (h.returned_tick<0 or h.returned_tick>identity.dismissed):return "staff_rest_after_dismissal"
			if h.state in ["walking","using","returning"]:
				if active.has(sid) or index!=rows.size()-1 or not d.staff.has(sid):return "orphan_or_multiple_staff_rest"
				active[sid]=h.id
				var live_error:String=_active(d,h,reservations)
				if live_error!="":return live_error
			prior_return=int(h.returned_tick) if int(h.returned_tick)>=0 else int(d.tick)+1
			last_end=end
	for s:Dictionary in d.staff.values():
		if not s.get("rest_activity") is Dictionary:return "missing_staff_rest_activity"
		if not active.has(s.id):
			if not s.rest_activity.is_empty():return "orphan_staff_rest_pointer"
		elif s.rest_activity.get("event_id","")!=active[s.id]:return "mismatched_staff_rest_pointer"
		if int(s.fatigue)!=_fatigue_query(evidence,str(s.id),int(d.tick)):return "forged_experience_staff_fatigue"
	if reservations!=d.campaign.people_reservations:return "orphan_shared_people_reservation"
	for receipt:Dictionary in d.command_receipts.values():
		if receipt.data.command.type=="request_staff_rest" and not requests.has("command:"+str(receipt.data.command.id)):return "orphan_manual_staff_rest_command"
	return _history_proof(evidence,records,int(d.tick))

static func _active(d:Dictionary,h:Dictionary,reservations:Dictionary)->String:
	var s:Dictionary=d.staff[h.staff_id]
	if not _fields(s.get("rest_activity"),{"event_id":TYPE_STRING,"processed_tick":TYPE_INT}):return "invalid_staff_rest_activity"
	if s.rest_activity.event_id!=h.id or s.rest_activity.processed_tick< -1 or s.rest_activity.processed_tick>d.tick:return "invalid_staff_rest_activity_pointer"
	if s.patient_id!="" or s.work_order_id!="" or s.get("training_order_id","")!="":return "double_booked_staff_rest"
	if s.facility_id!=h.workplace_id:return "changed_staff_rest_workplace"
	if h.workplace_id!="":
		var home:Dictionary=d.facilities.get(h.workplace_id,{})
		if home.is_empty():return "missing_staff_rest_workplace"
		var place:int=home.staff_ids.find(s.id)
		if place<0 or place>=home.staff_cells.size() or int(home.staff_cells[place])!=int(h.return_cell):return "changed_staff_rest_return_cell"
	elif h.return_cell!=GridService.EXIT_CELL:return "invalid_unassigned_staff_rest_return"
	var f:Dictionary=d.facilities.get(h.facility_id,{})
	if f.is_empty() or f.kind!=h.facility_kind or f.service_cells.is_empty() or int(f.service_cells[0])!=int(h.target_cell):return "changed_staff_rest_target"
	if h.state=="using" and (int(s.cell)!=int(h.target_cell) or int(s.move_progress)!=0 or s.status!="resting"):return "staff_rest_use_without_position"
	var route:Array=s.path
	var entering:bool=int(s.move_progress)>0 and int(s.path_index)+1<route.size() and int(route[int(s.path_index)+1])==int(h.target_cell)
	if h.departed_tick>=0 and (int(s.cell)==int(h.target_cell) or entering):return "premature_staff_rest_target_release"
	if h.departed_tick<0:
		var key:String=str(h.facility_id)+":0"
		if reservations.has(key):return "double_people_supply_target"
		reservations[key]=s.id
	return ""

static func _history_proof(index:Dictionary,records:Dictionary,tick:int)->String:
	for h:Dictionary in records.values():
		var geometry:Dictionary=index.request_geometry.get(h.id,{})
		if geometry.is_empty() or not geometry.get("exists",false) or not geometry.get("available",false):return "unproven_staff_rest_historical_facility"
		if geometry.kind!=h.facility_kind or int(geometry.target_cell)!=int(h.target_cell):return "forged_staff_rest_historical_target"
		if geometry.workplace_id!=h.workplace_id or int(geometry.return_cell)!=int(h.return_cell):return "forged_staff_rest_historical_workplace"
		var cancellation:int=_expected_cancel(index,h)
		if int(h.canceled_tick)>=0 and int(h.canceled_tick)!=cancellation:return "unproven_staff_rest_cancellation"
		if int(h.started_tick)>=cancellation and int(h.started_tick)>=0:return "staff_rest_started_after_cancellation_due"
		if h.state=="walking" and cancellation<=tick:return "overdue_staff_rest_cancellation"
	return ""
