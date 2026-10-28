class_name HospitalPlaytestInsights
extends RefCounted

# Read-only operating observations. No human wall-clock or enjoyment inference.
static func review(d:Dictionary,catalog:ContentCatalog)->Dictionary:
	var result:Dictionary={"enabled":false,"samples":0,"completed":0,"abandoned":0,"referred":0,"average_wait_ticks":0,"operating_commands":0,"since_command_ticks":-1,"day_cures":0,"day_profit":0,"full_days":0,"queues":[],"window_ticks":0,"phase_elapsed_ticks":0}
	if d.get("schema_version",0)!=3 or d.get("ruleset","")!="full-hospital-v2" or not catalog.levels.has(d.get("level_id","")):return result
	result.enabled=true
	var now:int=int(d.get("tick",0))
	var day:int=int(catalog.levels[d.level_id].day_ticks)
	var start:int=maxi(0,now-3*day)
	result.window_ticks=now-start
	result.phase_elapsed_ticks=maxi(0,now-int(d.campaign.get("phase_started_tick",0)))
	var total_wait:int=0
	for patient:Dictionary in d.get("patients",{}).values():
		var ended:int=int(patient.get("completed_tick",-1))
		if ended<=start or ended>now:continue
		if patient.get("phase","")=="left" and patient.get("outcome","")=="completed":result.completed+=1
		elif patient.get("phase","")=="left" and patient.get("outcome","")=="referred":result.referred+=1
		elif patient.get("phase","")=="abandoned":result.abandoned+=1
		else:continue
		result.samples+=1;total_wait+=int(patient.get("wait_ticks",0))
	if result.samples>0:result.average_wait_ticks=int(total_wait/result.samples)
	var latest:int=-1
	for receipt:Dictionary in d.get("command_receipts",{}).values():
		var row:Dictionary=receipt.get("data",{})
		var kind:String=str(row.get("command",{}).get("type",""))
		if kind in ["","set_paused","set_speed","continue_hospital"] or int(row.get("tick",-1))<int(d.campaign.get("phase_started_tick",0)):continue
		result.operating_commands+=1;latest=maxi(latest,int(row.tick))
	if latest>=0:result.since_command_ticks=maxi(0,now-latest)
	var days:Array=d.campaign.get("day_records",[])
	for record:Dictionary in days.slice(maxi(0,days.size()-3)):
		result.full_days+=1;result.day_cures+=int(record.get("completed",0));result.day_profit+=int(record.get("profit",0))
	var grouped:Dictionary={}
	for id:String in d.campaign.get("live_patient_ids",[]):
		var patient:Dictionary=d.get("patients",{}).get(id,{})
		if patient.get("phase","") not in ["care_queue","waiting_support"]:continue
		var reason:String=str(patient.get("wait_reason",""))
		if reason=="":reason="clinical_queue"
		if not grouped.has(reason):grouped[reason]={"reason":reason,"count":0,"patient_id":id}
		grouped[reason].count+=1
	result.queues=grouped.values()
	result.queues.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return int(a.count)>int(b.count) if a.count!=b.count else str(a.reason)<str(b.reason))
	return result
