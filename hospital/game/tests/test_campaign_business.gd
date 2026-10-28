extends SceneTree

var output:String=""
var passed:int=0
var failed:int=0
var checks:Array=[]
var serial:int=0
var catalog:ContentCatalog
var business:Script

func _initialize()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	_run.call_deferred()

func check(ok:bool,label:String,detail:String="")->void:
	checks.append({"ok":ok,"check":label,"detail":detail})
	if ok:passed+=1
	else:failed+=1
	print(("BUSINESS PASS " if ok else "BUSINESS FAIL ")+label+" "+detail)

func issue(sim:Simulation,type:String,payload:Dictionary={})->Dictionary:
	serial+=1
	return sim.submit({"id":"business_%04d"%serial,"type":type,"payload":payload})

func _run()->void:
	var loaded_catalog:Dictionary=ContentCatalog.load_checked("res://content")
	check(loaded_catalog.get("ok",false),"catalog loads")
	if not loaded_catalog.get("ok",false):quit(1);return
	catalog=loaded_catalog.catalog
	var state:ClinicState=ClinicState.create("long_01",catalog)
	var sim:=Simulation.new(catalog,state)
	check(state.data.campaign.get("business_version",0)==1,"new hospital has business extension")
	check(issue(sim,"set_procurement_policy",{"policy":"economy"}).get("ok",false),"public economy policy")
	var path:String="res://campaign/campaign_business.gd"
	if ResourceLoader.exists(path):business=load(path)
	check(business!=null,"business module exists")
	if business!=null:
		var signatures:Dictionary={}
		for n:int in range(1,13):
			var d:Dictionary=ClinicState.create("long_%02d"%n,catalog).data
			var profile:Dictionary=business.call("profile",d)
			signatures[JSON.stringify([profile.market_percent,profile.event_interval,profile.event_order])]=true
		check(signatures.size()==12,"twelve actual economic/event environments")
		var build:Dictionary=issue(sim,"build_department",{"unit_id":"operations","origin_cell":25,"layout":FacilityLayout.default_layout("operations","O15",0)})
		check(build.get("ok",false),"real delivery facility",str(build.get("code")))
		if build.get("ok",false):
			var hire:Dictionary=issue(sim,"hire",{"role":"logistics"})
			check(hire.get("ok",false),"real employee")
			if hire.get("ok",false):check(issue(sim,"assign",{"staff_id":hire.data.staff_id,"facility_id":build.data.facility_ids[0]}).get("ok",false),"assign real delivery employee")
			var requested:Dictionary=issue(sim,"run_operation",{"facility_kind":"O15"})
			check(requested.get("ok",false),"create real economy delivery order")
			if requested.get("ok",false):
				var order:Dictionary=state.data.work_orders[requested.data.work_order_id]
				var cost:int=int(catalog.campaign.facilities.O15.consumable_cost)
				var duration:int=int(catalog.campaign.facilities.O15.duration_ticks)
				check(order.cost==ceili(cost*0.75) and order.needed==ceili(duration*1.5),"economy pays less and takes longer")
				var quoted:Dictionary=order.duplicate(true)
				check(issue(sim,"set_procurement_policy",{"policy":"express"}).get("ok",false),"public express policy")
				check(state.data.work_orders[order.id]==quoted,"changing policy never rewrites queued quote")
				var rewritten:Dictionary=sim.snapshot()
				var forged:Dictionary=rewritten.work_orders[order.id]
				forged.procurement_quote.policy="express"
				forged.procurement_quote.command_sequence=rewritten.command_sequence
				forged.procurement_quote.cost=ceili(cost*1.5)
				forged.procurement_quote.duration=ceili(duration*0.7)
				forged.cost=forged.procurement_quote.cost
				forged.needed=forged.procurement_quote.duration
				check(SnapshotValidator.validate(rewritten,catalog)!="","later policy cannot rewrite a real pending order quote")
				issue(sim,"set_paused",{"paused":false})
				for _n:int in range(1500):
					sim.advance_ticks(1)
					if state.data.work_orders[order.id].status=="done":break
				order=state.data.work_orders[order.id]
				check(order.status=="done" and int(state.data.resources.get("delivered",0))==int(catalog.campaign.facilities.O15.output.delivered),"employee walks and finishes paid delivery")
				check(SnapshotValidator.validate(sim.snapshot(),catalog)=="","actual quoted order validates",SnapshotValidator.validate(sim.snapshot(),catalog))
				var corrupt:Dictionary=sim.snapshot();corrupt.work_orders[order.id].cost+=1
				check(SnapshotValidator.validate(corrupt,catalog)!="","forged quote rejected")
				var loaded:Dictionary=ClinicState.from_data(sim.snapshot(),catalog)
				check(loaded.get("ok",false),"business state strictly reloads",str(loaded.get("error","")))
				if loaded.get("ok",false):
					var mirror:=Simulation.new(catalog,loaded.state)
					for _n:int in range(100):sim.advance_ticks(1);mirror.advance_ticks(1)
					check(sim.snapshot()==mirror.snapshot(),"post-load future matches")
				check(issue(sim,"set_procurement_policy",{"policy":"economy"}).get("ok",false),"economy before automatic order")
				check(issue(sim,"set_operation_auto",{"facility_kind":"O15","enabled":true,"target":20}).get("ok",false),"enable real supply threshold")
				var automatic_id:String=""
				for _n:int in range(50):
					sim.advance_ticks(1)
					for candidate:Dictionary in state.data.work_orders.values():
						if candidate.get("automation",false):automatic_id=candidate.id;break
					if automatic_id!="":break
				check(automatic_id!="","real threshold creates an automatic order")
				if automatic_id!="":
					var original_auto:Dictionary=state.data.work_orders[automatic_id].duplicate(true)
					check(issue(sim,"set_procurement_policy",{"policy":"express"}).get("ok",false),"same-tick later policy switch")
					check(state.data.work_orders[automatic_id]==original_auto,"same-tick policy keeps earlier automatic quote")
					check(SnapshotValidator.validate(sim.snapshot(),catalog)=="","automatic quote anchors before same-tick command",SnapshotValidator.validate(sim.snapshot(),catalog))
					var auto_loaded:Dictionary=ClinicState.from_data(sim.snapshot(),catalog)
					check(auto_loaded.get("ok",false),"automatic quoted order strictly reloads")
		var legacy:Dictionary=ClinicState.create("long_01",catalog).data
		legacy.campaign.erase("business_version");legacy.campaign.erase("procurement_policy")
		check(not business.call("enabled",legacy),"missing extension retains legacy")
		check(business.call("event_interval",legacy,catalog)==catalog.levels.long_01.event_interval_ticks,"legacy event cadence preserved")
	if output!="":
		DirAccess.make_dir_recursive_absolute(output.get_base_dir())
		var f:=FileAccess.open(output,FileAccess.WRITE);f.store_string(JSON.stringify({"passed":passed,"failed":failed,"checks":checks},"\t"))
	print("BUSINESS RESULT passed=%d failed=%d"%[passed,failed]);quit(1 if failed>0 else 0)
