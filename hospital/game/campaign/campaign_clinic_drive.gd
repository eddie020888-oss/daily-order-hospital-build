class_name CampaignClinicDrive
extends RefCounted

# Optional demand, never extra cures or a faster treatment/simulation clock.
# The normal command/admission histories are the sole persisted evidence.
const BATCHES:Array=[4,8,12]
const INTERVAL_PERCENT:int=70

static func enabled(d:Dictionary)->bool:
	return d.get("schema_version",0)==3 and d.get("ruleset","")=="full-hospital-v2"

static func _latest(d:Dictionary)->Dictionary:
	var latest:Dictionary={}
	for receipt:Dictionary in d.get("command_receipts",{}).values():
		var row:Dictionary=receipt.get("data",{})
		if row.get("command",{}).get("type","")=="set_clinic_drive" and int(row.get("sequence",0))>int(latest.get("sequence",0)):latest=row
	return latest

static func view(d:Dictionary,catalog:ContentCatalog)->Dictionary:
	var result:Dictionary={"status":"none","enabled":false,"case_id":"","target_batches":0,"admitted":0,"completed":0,"failed":0,"patients":0,"patient_ids":[],"instance_ids":[],"sequence":0,"phase_index":-1}
	if not enabled(d):return result
	var row:Dictionary=_latest(d)
	if row.is_empty():return result
	var payload:Dictionary=row.command.payload
	result.sequence=int(row.sequence)
	if not payload.get("enabled",false):result.status="canceled";return result
	result.case_id=str(payload.get("case_id",""));result.target_batches=int(payload.get("batches",0))
	result.phase_index=int(row.get("phase_index",-1))
	var events:Array=[]
	for event:Dictionary in d.campaign.get("admission_events",{}).values():
		if event.get("source","")!="auto" or event.get("case_id","")!=result.case_id:continue
		if int(event.get("command_sequence",0))<int(row.sequence) or int(event.get("schedule_index",-1))<int(row.get("start_cursor",0)) or int(event.get("phase_index",-1))!=result.phase_index:continue
		events.append(event)
	events.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return int(a.schedule_index)<int(b.schedule_index))
	for event:Dictionary in events.slice(0,result.target_batches):
		var instance:Dictionary=d.campaign.case_instances.get(event.instance_id,{})
		result.admitted+=1;result.instance_ids.append(event.instance_id)
		result.patient_ids.append_array(event.patient_ids);result.patients+=event.patient_ids.size()
		if instance.get("status","")=="completed":result.completed+=1
		elif instance.get("status","")=="failed":result.failed+=1
	if int(d.campaign.get("phase_index",0))!=result.phase_index:result.status="stage_ended"
	elif result.completed+result.failed>=result.target_batches:result.status="completed"
	elif result.admitted>=result.target_batches:result.status="finishing"
	elif not d.campaign.get("intake_enabled",false):result.status="paused"
	else:result.status="admitting";result.enabled=true
	return result

static func preferred_cases(d:Dictionary,catalog:ContentCatalog)->Array:
	var current:Dictionary=view(d,catalog)
	return [current.case_id] if current.enabled else []

static func interval_percent(d:Dictionary,catalog:ContentCatalog)->int:
	return INTERVAL_PERCENT if view(d,catalog).enabled else 100

static func apply(state:ClinicState,catalog:ContentCatalog,p:Dictionary)->Dictionary:
	var d:Dictionary=state.data
	if not enabled(d):return _no("not_long_campaign")
	if not p.get("enabled") is bool or not p.get("case_id") is String or not p.get("batches") is int:return _no("invalid_payload")
	if not p.enabled:
		if p.case_id!="" or p.batches!=0:return _no("invalid_clinic_drive")
		return _yes({"enabled":false,"case_id":"","batches":0,"phase_index":int(d.campaign.phase_index),"start_cursor":int(d.campaign.intake_cursor)})
	if p.batches not in BATCHES:return _no("invalid_clinic_drive")
	var level:Dictionary=catalog.levels[d.level_id]
	var phase:Dictionary=level.phases[mini(3,int(d.campaign.phase_index))]
	if p.case_id not in level.case_ids.slice(0,int(phase.signature_cases)) or p.case_id not in d.campaign.completed_cases:return _no("routine_case_not_established")
	if not d.campaign.intake_enabled:return _no("intake_disabled")
	if view(d,catalog).status in ["admitting","paused","finishing"]:return _no("clinic_drive_active")
	var missing:Array=LongCampaignClinical.instance_readiness(state,catalog,p.case_id)
	if not missing.is_empty():return _no(str(missing[0]),{"missing":missing})
	return _yes({"enabled":true,"case_id":p.case_id,"batches":p.batches,"phase_index":int(d.campaign.phase_index),"start_cursor":int(d.campaign.intake_cursor)})

static func validate(d:Dictionary,catalog:ContentCatalog)->String:
	if not enabled(d):return ""
	var rows:Array=[]
	if not d.get("command_receipts",{}) is Dictionary:return "invalid_clinic_drive_history"
	for receipt:Variant in d.get("command_receipts",{}).values():
		if not receipt is Dictionary or not receipt.get("data") is Dictionary or not receipt.data.get("command") is Dictionary or not receipt.data.command.get("payload") is Dictionary:return "invalid_clinic_drive_history"
		rows.append(receipt.data)
	rows.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return int(a.get("sequence",0))<int(b.get("sequence",0)))
	var phase:int=0
	var intake:bool=false
	var previous:Dictionary={}
	for row:Dictionary in rows:
		var command:Dictionary=row.get("command",{})
		var p:Dictionary=command.get("payload",{})
		if command.get("type","")=="set_intake":intake=bool(p.get("enabled",false))
		elif command.get("type","")=="advance_stage":phase+=1;intake=false if phase==4 else intake
		elif command.get("type","")=="set_clinic_drive":
			if not p.get("enabled") is bool or not p.get("case_id") is String or not p.get("batches") is int:return "invalid_clinic_drive_history"
			if row.get("enabled")!=p.enabled or row.get("case_id")!=p.case_id or row.get("batches")!=p.batches or row.get("phase_index")!=phase or not row.get("start_cursor") is int:return "invalid_clinic_drive_history"
			var cursor:int=0
			for event:Dictionary in d.campaign.admission_events.values():
				if event.source=="auto" and int(event.command_sequence)<int(row.sequence):cursor+=1
			if int(row.start_cursor)!=cursor:return "invalid_clinic_drive_cursor"
			if not p.enabled:
				if p.case_id!="" or p.batches!=0:return "invalid_clinic_drive_history"
				previous={}
				continue
			if not intake or p.batches not in BATCHES:return "invalid_clinic_drive_history"
			if not previous.is_empty() and int(previous.phase_index)==phase and not _settled_before(d,previous,row):return "overlapping_clinic_drive_history"
			var definition:Dictionary=catalog.levels[d.level_id]
			if p.case_id not in definition.case_ids.slice(0,int(definition.phases[mini(3,phase)].signature_cases)):return "invalid_clinic_drive_case"
			var earned:bool=false
			for instance:Dictionary in d.campaign.case_instances.values():
				if instance.kind=="signature" and instance.case_id==p.case_id and instance.status=="completed" and int(instance.completed_tick)<=int(row.tick):earned=true;break
			if not earned:return "unearned_clinic_drive_case"
			previous=row
	return ""

static func _settled_before(d:Dictionary,previous:Dictionary,next:Dictionary)->bool:
	var events:Array=[]
	for event:Dictionary in d.campaign.admission_events.values():
		if event.source!="auto" or event.case_id!=previous.case_id or int(event.phase_index)!=int(previous.phase_index):continue
		if int(event.command_sequence)<int(previous.sequence) or int(event.command_sequence)>=int(next.sequence) or int(event.schedule_index)<int(previous.start_cursor) or int(event.tick)>int(next.tick):continue
		events.append(event)
	events.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return int(a.schedule_index)<int(b.schedule_index))
	var target:int=int(previous.batches)
	if events.size()<target:return false
	for event:Dictionary in events.slice(0,target):
		var instance:Dictionary=d.campaign.case_instances[event.instance_id]
		if int(instance.completed_tick)<0 or int(instance.completed_tick)>int(next.tick):return false
	return true

static func _yes(data:Dictionary)->Dictionary:return {"ok":true,"code":"ok","data":data}
static func _no(code:String,data:Dictionary={})->Dictionary:return {"ok":false,"code":code,"data":data}
