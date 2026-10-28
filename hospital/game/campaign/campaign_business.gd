class_name CampaignBusiness
extends RefCounted

# These profiles change actual supply quotes and event scheduling. They are
# immutable version-one rules, not decorations copied into a running save.
const ENVIRONMENTS:Array=[
	["社区开业",100,12000,[0,1,2,3]],
	["配送紧张",115,10800,[1,3,0,2]],
	["设备高负荷",105,10000,[0,0,1,2,3]],
	["卫生巡视",110,9600,[2,1,2,0,3]],
	["转诊枢纽",108,11400,[3,1,0,2]],
	["远郊供给",125,12000,[1,1,0,3,2]],
	["临床高峰",112,9000,[3,0,2,1]],
	["维护季",118,8400,[0,2,0,1,3]],
	["采购涨价",135,10800,[1,2,3,0]],
	["频繁巡视",120,7800,[2,3,1,0]],
	["区域中心",128,7200,[3,1,2,0,3]],
	["综合运营",130,6600,[0,1,3,2,1,0]]]
const POLICIES:Dictionary={"standard":{"cost":100,"duration":100},"economy":{"cost":75,"duration":150},"express":{"cost":150,"duration":70}}

static func enabled(d:Dictionary)->bool:
	return LongCampaign.is_long(d) and d.campaign.get("business_version",0)==1

static func initialize(d:Dictionary)->void:
	d.campaign.business_version=1
	d.campaign.procurement_policy="standard"
	d.campaign.next_event_tick=profile(d).event_interval

static func profile(d:Dictionary)->Dictionary:
	var n:int=clampi(int(str(d.level_id).trim_prefix("long_"))-1,0,11)
	var e:Array=ENVIRONMENTS[n]
	return {"name":e[0],"market_percent":e[1],"event_interval":e[2],"event_order":e[3].duplicate()}

static func event_interval(d:Dictionary,catalog:ContentCatalog)->int:
	return int(profile(d).event_interval) if enabled(d) else int(catalog.levels[d.level_id].event_interval_ticks)

static func event_id(d:Dictionary,catalog:ContentCatalog,index:int)->String:
	var pool:Array=catalog.levels[d.level_id].event_ids
	if not enabled(d):return str(pool[index%pool.size()])
	var order:Array=profile(d).event_order
	return str(pool[int(order[index%order.size()])%pool.size()])

static func apply(state:ClinicState,p:Dictionary)->Dictionary:
	if not enabled(state.data):return {"ok":false,"code":"business_not_enabled","data":{}}
	if not p.get("policy") is String or not POLICIES.has(p.policy):return {"ok":false,"code":"invalid_procurement_policy","data":{}}
	state.data.campaign.procurement_policy=p.policy
	return {"ok":true,"code":"ok","data":{"policy":p.policy}}

static func eligible(order:Dictionary)->bool:
	return order.patient_id=="" and not order.output.is_empty() and order.handler not in ["research","training"]

static func quote(d:Dictionary,order:Dictionary)->void:
	if not enabled(d) or not eligible(order):return
	var policy:String=d.campaign.procurement_policy
	var terms:Dictionary=POLICIES[policy]
	var market:int=int(profile(d).market_percent)
	var cost:int=ceili(float(int(order.cost)*market*int(terms.cost))/10000.0)
	var duration:int=maxi(1,ceili(float(int(order.needed)*int(terms.duration))/100.0))
	order.procurement_quote={"version":1,"policy":policy,"market_percent":market,"base_cost":int(order.cost),"base_duration":int(order.needed),"cost":cost,"duration":duration,"command_sequence":int(d.command_sequence)}
	order.cost=cost;order.needed=duration

static func preview_terms(d:Dictionary,definition:Dictionary)->Dictionary:
	var order:Dictionary={"patient_id":"","output":definition.get("output",{}),"handler":definition.get("handler",""),"cost":int(definition.consumable_cost),"needed":int(definition.duration_ticks)}
	quote(d,order)
	return {"cost":int(order.cost),"duration_ticks":int(order.needed)}

static func planned_duration(d:Dictionary,order:Dictionary,original:int)->int:
	var q:Variant=order.get("procurement_quote",{})
	return int(q.duration) if enabled(d) and q is Dictionary and q.get("duration") is int else original

static func operation_cost(d:Dictionary,order:Dictionary,original:int)->int:
	var q:Variant=order.get("procurement_quote",{})
	return int(q.cost) if enabled(d) and q is Dictionary and q.get("cost") is int else original

static func validate(d:Dictionary,catalog:ContentCatalog)->String:
	if not d.campaign.has("business_version"):return ""
	if d.campaign.business_version!=1 or not d.campaign.get("procurement_policy") is String or not POLICIES.has(d.campaign.procurement_policy):return "invalid_business_policy"
	var rows:Array=[]
	for receipt:Dictionary in d.command_receipts.values():rows.append(receipt.data)
	rows.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return a.sequence<b.sequence)
	var policies:Dictionary={0:"standard"}
	var creators:Dictionary={}
	var current:String="standard"
	for row:Dictionary in rows:
		if row.command.type=="run_operation":
			creators[str(row.get("work_order_id",""))]={"sequence":int(row.sequence),"tick":int(row.tick),"kind":str(row.command.payload.get("facility_kind",""))}
		if row.command.type=="set_procurement_policy":
			var p:Variant=row.command.payload.get("policy")
			if not p is String or not POLICIES.has(p) or row.get("policy")!=p:return "invalid_business_policy_receipt"
			current=p
		policies[row.sequence]=current
	if current!=d.campaign.procurement_policy:return "invalid_business_policy_history"
	for order:Dictionary in d.work_orders.values():
		if not eligible(order):
			if order.has("procurement_quote"):return "unexpected_procurement_quote"
			continue
		var q:Variant=order.get("procurement_quote")
		if not q is Dictionary:return "missing_procurement_quote"
		for key:String in ["version","market_percent","base_cost","base_duration","cost","duration","command_sequence"]:
			if not q.get(key) is int:return "invalid_procurement_quote"
		if q.version!=1 or not q.get("policy") is String or not POLICIES.has(q.policy) or q.command_sequence<0 or q.command_sequence>d.command_sequence or policies.get(q.command_sequence)!=q.policy:return "invalid_procurement_quote_policy"
		# Public creation is anchored to its actual result; automatic orders are
		# created inside a tick before any command stamped with that tick.
		if creators.has(order.id):
			var creator:Dictionary=creators[order.id]
			if q.command_sequence!=int(creator.sequence)-1 or order.created_tick!=creator.tick or order.facility_kind!=creator.kind:return "unanchored_procurement_quote"
		else:
			if order.get("automation",false)!=true:return "missing_procurement_creator"
			var left:int=0
			var right:int=rows.size()
			while left<right:
				var middle:int=int((left+right)/2)
				if int(rows[middle].tick)<int(order.created_tick):left=middle+1
				else:right=middle
			var prior_sequence:int=int(rows[left-1].sequence) if left>0 else 0
			if q.command_sequence!=prior_sequence:return "unanchored_automatic_procurement_quote"
		var def:Dictionary=catalog.campaign.facilities.get(order.facility_kind,{})
		if def.is_empty() or q.base_cost!=def.consumable_cost or q.base_duration!=def.duration_ticks or q.market_percent!=profile(d).market_percent:return "invalid_procurement_quote_basis"
		var terms:Dictionary=POLICIES[q.policy]
		if q.cost!=ceili(float(q.base_cost*q.market_percent*int(terms.cost))/10000.0) or q.duration!=maxi(1,ceili(float(q.base_duration*int(terms.duration))/100.0)) or order.cost!=q.cost:return "invalid_procurement_quote_amount"
	return ""
