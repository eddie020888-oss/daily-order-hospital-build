class_name HospitalOperatingInsights
extends RefCounted

# Read-only decision support. These estimates never reserve, purchase or advance time.
static func _enabled(d:Dictionary,catalog:ContentCatalog)->bool:
	return LongCampaign.is_long(d) and catalog.levels.has(str(d.get("level_id","")))

static func day_review(d:Dictionary,catalog:ContentCatalog,limit:int=7)->Dictionary:
	var result:Dictionary={"enabled":false,"rows":[],"latest_break":{},"history_breaks":[],"streak":0}
	if not _enabled(d,catalog):return result
	result.enabled=true
	var level:Dictionary=catalog.levels[d.level_id]
	var length:int=maxi(1,int(level.day_ticks))
	var current:int=clampi(int(d.campaign.get("phase_index",0)),0,3)
	var spans:Array=[]
	for receipt:Dictionary in d.campaign.get("phase_receipts",[]):
		spans.append({"index":int(receipt.index),"start":int(receipt.started_tick),"end":int(receipt.ended_tick)})
	if not d.campaign.get("course_complete",false):spans.append({"index":current,"start":int(d.campaign.get("phase_started_tick",0)),"end":int(d.tick)})
	var rows:Array=[]
	var streaks:Dictionary={}
	for day:Dictionary in d.campaign.get("day_records",[]):
		var start:int=int(day.get("start_tick",-1))
		var end:int=int(day.get("end_tick",-1))
		var full:bool=end<=int(d.tick) and end-start==length
		var owner:int=-1
		if full:
			for span:Dictionary in spans:
				if start>=int(span.start) and end<=int(span.end):owner=int(span.index);break
		var eligible:bool=owner>=0 and owner<level.phases.size()
		var phase:Dictionary=level.phases[owner] if eligible else {}
		var required:bool=eligible and int(phase.get("profitable_days",0))>0
		var active:bool=eligible and owner==current and not d.campaign.get("course_complete",false)
		var completed:int=int(day.get("completed",0))
		var total:int=completed+int(day.get("abandoned",0))
		var quality:int=int(completed*100/total) if total>0 else -1
		var missing:Array[String]=[]
		if required:
			if int(day.get("profit",0))<int(phase.min_daily_profit):missing.append("利润%d / %d币"%[int(day.get("profit",0)),int(phase.min_daily_profit)])
			if completed<int(phase.min_daily_cures):missing.append("治愈%d / %d人"%[completed,int(phase.min_daily_cures)])
			if total==0:missing.append("没有有效结案")
			elif quality<int(phase.cure_rate):missing.append("治愈率%d%% / %d%%"%[quality,int(phase.cure_rate)])
		var status:String="partial" if not full else "previous" if not eligible else "reference" if not required else "passed" if missing.is_empty() else "failed"
		var row:Dictionary={"index":int(day.get("index",0)),"profit":int(day.get("profit",0)),"completed":completed,"abandoned":int(day.get("abandoned",0)),"quality":quality,"eligible":eligible,"phase_index":owner,"historical":not active,"status":status,"missing":missing}
		rows.append(row)
		if not required:continue
		var streak:int=int(streaks.get(owner,0))
		if not missing.is_empty():
			if streak>0:
				var interruption:Dictionary={"index":row.index,"phase_index":owner,"previous_streak":streak,"missing":missing.duplicate()}
				result.history_breaks.append(interruption)
				if active:result.latest_break=interruption.duplicate(true)
			streaks[owner]=0
		else:streaks[owner]=streak+1
	result.streak=int(streaks.get(current,0)) if not d.campaign.get("course_complete",false) else 0
	result.history_breaks.reverse()
	result.history_breaks=result.history_breaks.slice(0,3)
	rows.reverse()
	result.rows=rows.slice(0,clampi(limit,1,14))
	return result

static func _reservations(d:Dictionary)->Dictionary:
	var result:Dictionary={"cash":0,"resources":{}}
	for id:String in d.get("campaign",{}).get("live_patient_ids",d.get("patients",{}).keys()):
		var patient:Dictionary=d.get("patients",{}).get(id,{})
		result.cash+=int(patient.get("reservation_cost",0))
		var key:String=str(patient.get("reservation_resource",""))
		if key!="":result.resources[key]=int(result.resources.get(key,0))+int(patient.get("reservation_quantity",0))
	return result

static func finance(d:Dictionary,catalog:ContentCatalog)->Dictionary:
	var result:Dictionary={"enabled":false,"reserved_cash":0,"available_cash":0,"queued_cost":0,"queued_support_cost":0,"payroll":0,"arrears":0,"interest":0,"safety_balance":0,"until_day_ticks":0}
	if not _enabled(d,catalog):return result
	result.enabled=true
	result.reserved_cash=int(_reservations(d).cash)
	result.available_cash=maxi(0,int(d.cash)-int(result.reserved_cash))
	for employee:Dictionary in d.get("staff",{}).values():
		if catalog.campaign.roles.has(str(employee.get("role",""))):result.payroll+=CampaignPeople.staff_daily_wage(d,catalog,employee)
	for order:Dictionary in d.get("work_orders",{}).values():
		if int(order.get("started_tick",-1))<0 and order.get("status","")!="done":
			result.queued_cost+=int(order.get("cost",0))
			if order.get("patient_id","")!="":result.queued_support_cost+=int(order.get("cost",0))
	result.arrears=int(d.campaign.get("unpaid_wages",0))
	var loan:int=int(d.campaign.get("loan",0))
	result.interest=maxi(1,int(loan/100)) if loan>0 else 0
	result.safety_balance=int(result.available_cash)-int(result.queued_cost)-int(result.payroll)-int(result.arrears)-int(result.interest)
	var length:int=maxi(1,int(catalog.levels[d.level_id].day_ticks))
	result.until_day_ticks=length-int(d.tick)%length
	return result

static func _consume(counts:Dictionary,item:Dictionary,start:int,end:int)->void:
	var at:int=int(item.get("started_tick",-1))
	var key:String=str(item.get("resource",""))
	if at>start and at<=end and key!="" and int(item.get("quantity",0))>0:counts[key]=int(counts.get(key,0))+int(item.quantity)

static func resources(d:Dictionary,catalog:ContentCatalog)->Dictionary:
	var result:Dictionary={}
	if not _enabled(d,catalog):return result
	var end:int=int(d.tick)
	var window:int=mini(end,maxi(1,int(catalog.levels[d.level_id].day_ticks)))
	var start:int=end-window
	var used:Dictionary={}
	var pending:Dictionary={}
	for patient:Dictionary in d.get("patients",{}).values():
		for item:Dictionary in patient.get("step_history",[]):
			if item.get("kind","")=="patient":_consume(used,item,start,end)
		for item:Dictionary in patient.get("need_history",[]):_consume(used,item,start,end)
	for item:Dictionary in d.campaign.get("staff_rest_events",{}).values():_consume(used,item,start,end)
	for order:Dictionary in d.get("work_orders",{}).values():
		_consume(used,order,start,end)
		if order.get("status","")!="done":
			for key:String in order.get("output",{}):pending[key]=int(pending.get(key,0))+int(order.output[key])
	var held:Dictionary=_reservations(d).resources
	for key:String in d.get("resources",{}):
		var stock:int=int(d.resources[key])
		var reserved:int=int(held.get(key,0))
		var available:int=maxi(0,stock-reserved)
		var consumed:int=int(used.get(key,0))
		result[key]={"stock":stock,"reserved":reserved,"available":available,"consumed":consumed,"sample_ticks":window,"pending_output":int(pending.get(key,0)),"runway_ticks":int(float(available)*window/consumed) if consumed>0 and window>0 else -1}
	return result

static func operation(d:Dictionary,catalog:ContentCatalog,kind:String)->Dictionary:
	if not _enabled(d,catalog) or not catalog.campaign.facilities.has(kind):return {}
	var definition:Dictionary=catalog.campaign.facilities[kind]
	var quote:Dictionary=CampaignBusiness.preview_terms(d,definition)
	var key:String=str(definition.get("input_resource",""))
	var held:Dictionary=_reservations(d).resources
	var input:int=maxi(0,int(d.resources.get(key,0))-int(held.get(key,0)))
	var free_cash:int=maxi(0,int(d.cash)-int(_reservations(d).cash))
	return {"cost":int(quote.cost),"duration_ticks":int(quote.duration_ticks),"input_resource":key,"input_quantity":int(definition.get("input_quantity",0)),"available_input":input,"missing_input":maxi(0,int(definition.get("input_quantity",0))-input),"output":definition.get("output",{}).duplicate(true),"cash_after":free_cash-int(quote.cost)}
