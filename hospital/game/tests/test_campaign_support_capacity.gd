extends SceneTree

const FormalPaths=preload("res://tests/support/formal_test_paths.gd")
const TASK:String="E:/CODEX/2026-10-28/医院逻辑与游戏性复审"
var test_paths:Variant
var crew_priority_observations:Dictionary={}

# Diagnostic only, outside the product. Real formal factory and public commands.
# No content, money, stock, patient, staff, route or simulation clock injection.
var output:String=""
var catalog:ContentCatalog
var serial:int=0
var passed:int=0
var failed:int=0
var checks:Array=[]
var snapshots:Dictionary={}

func _initialize()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=").replace("\\","/")
	var reservation:Dictionary={}
	if OS.get_name()=="Windows":
		var canonical:String=FormalPaths._canonical(output)
		var folder:String=canonical.get_base_dir()
		if canonical!="" and FormalPaths._descendant(canonical,TASK) and FormalPaths._descendant(folder,TASK) and canonical.get_extension()=="json" and not FileAccess.file_exists(canonical) and not DirAccess.dir_exists_absolute(canonical) and not FileAccess.file_exists(folder) and not DirAccess.dir_exists_absolute(folder) and FormalPaths._fresh_directory(folder):
			var paths:=FormalPaths.new()
			paths.output_path=canonical;paths.run_root=folder;paths.allowed_root=TASK
			reservation={"ok":true,"output":canonical,"paths":paths}
	else:reservation=FormalPaths.reserve(output,"parallel-support-capacity")
	if not reservation.get("ok",false):
		printerr("PARALLEL REFERRAL PATH ERROR: require fresh isolated report directory");quit(2);return
	test_paths=reservation.paths;output=str(reservation.output)
	_run.call_deferred()

func check(ok:bool,label:String,detail:Variant="")->bool:
	checks.append({"ok":ok,"check":label,"detail":detail})
	if ok:passed+=1
	else:failed+=1
	print(("PARALLEL REFERRAL PASS: " if ok else "PARALLEL REFERRAL FAIL: ")+label+" "+str(detail))
	return ok

func issue(sim:Simulation,type:String,payload:Dictionary={})->Dictionary:
	serial+=1
	var result:Dictionary=sim.submit({"id":"parallel_referral_%05d"%serial,"type":type,"payload":payload})
	check(bool(result.get("ok",false)),"public "+type,str(result.get("code","")))
	return result

func build(sim:Simulation,kind:String,origin:int)->String:
	var f:Dictionary=catalog.campaign.facilities[kind]
	var built:Dictionary=issue(sim,"build_department",{"unit_id":f.unit_id,"origin_cell":origin,"layout":FacilityLayout.default_layout(f.unit_id,kind,0)})
	if not built.get("ok",false):return ""
	var id:String=str(built.data.facility_ids[0])
	for role:String in f.roles:
		var hired:Dictionary=issue(sim,"hire",{"role":role})
		if not hired.get("ok",false):return ""
		if not issue(sim,"assign",{"staff_id":hired.data.staff_id,"facility_id":id}).get("ok",false):return ""
	return id

func _pending(d:Dictionary)->Array:
	var ids:Array=[]
	for id:String in d.campaign.live_patient_ids:
		if CampaignClinicalDecisions.preview(d,catalog,id).get("pending",false):ids.append(id)
	return ids

func run_probe()->void:
	var loaded:Dictionary=ContentCatalog.load_checked("res://content")
	check(bool(loaded.get("ok",false)),"real content loads",str(loaded.get("error","")))
	if not loaded.get("ok",false):return
	catalog=loaded.catalog
	var state:ClinicState=LongCampaignState.create_formal("long_01",catalog)
	check(state!=null,"real formal new hospital factory")
	if state==null:return
	var sim:=Simulation.new(catalog,state)
	for row:Array in [["U04-E1",25],["O01",33],["O15",40]]:
		if build(sim,str(row[0]),int(row[1]))=="":return
	var referral_a:String=build(sim,"O05",125)
	var referral_b:String=build(sim,"O05",129)
	if referral_a=="" or referral_b=="":return
	var delivery:Dictionary=issue(sim,"run_operation",{"facility_kind":"O15"})
	if not delivery.get("ok",false):return
	issue(sim,"set_paused",{"paused":false})
	for _n:int in range(1200):
		if state.data.work_orders[delivery.data.work_order_id].status=="done":break
		sim.advance_ticks(1)
	check(state.data.work_orders[delivery.data.work_order_id].status=="done","real delivery completed")
	issue(sim,"set_paused",{"paused":true})
	for _n:int in range(2):
		if not issue(sim,"admit_routine",{"case_id":"U04-C2"}).get("ok",false):return
	issue(sim,"set_paused",{"paused":false})
	var error:String=""
	for _n:int in range(1800):
		if _pending(state.data).size()==2:break
		sim.advance_ticks(1)
		error=SnapshotValidator.validate(sim.snapshot(),catalog)
		if error!="":break
	check(error=="","real two-patient admission and exam remains strict-valid",error)
	var ids:Array=_pending(state.data)
	check(ids.size()==2,"two real patients reach independent clinical decision")
	if ids.size()!=2:return
	issue(sim,"set_paused",{"paused":true})
	for id:String in ids:
		if not issue(sim,"clinical_decision",{"patient_id":id,"action":"refer","expected_revision":int(state.data.patients[id].clinical_decision.revision)}).get("ok",false):return
	issue(sim,"set_paused",{"paused":false})
	sim.advance_ticks(1)
	var allocations:Dictionary={}
	var order_ids:Array=[]
	for order:Dictionary in state.data.work_orders.values():
		if order.facility_kind=="O05":
			allocations[order.facility_id]=true
			order_ids.append(order.id)
	check(order_ids.size()==2,"two actual public decisions generate two real referral jobs")
	check(allocations.size()==2,"two staffed referral desks actually divide the two concurrent jobs",JSON.stringify(allocations.keys()))
	snapshots.allocated=sim.snapshot()
	var concurrent:bool=false
	for _n:int in range(500):
		sim.advance_ticks(1)
		var working:int=0
		for id:String in order_ids:
			if state.data.work_orders[id].status=="working":working+=1
		if working==2:concurrent=true
		if state.data.campaign.live_patient_ids.is_empty():break
	check(concurrent,"the purchased second desk adds real simultaneous referral capacity")
	check(state.data.metrics.referred==2 and state.data.metrics.income==0,"both physically depart as genuine referrals without cure income")
	check(SnapshotValidator.validate(sim.snapshot(),catalog)=="","final two-desk public hospital remains save-valid",SnapshotValidator.validate(sim.snapshot(),catalog))
	snapshots.final=sim.snapshot()

# Appended to the preserved public probe in the independently named v2 file.
# Allocator-only detached fixtures are explicitly synthetic; their modified
# flags are not represented as legal gameplay or accepted save snapshots.
func _allocation_fixture(source:Dictionary,expected:String,label:String,kind:String="O05")->Dictionary:
	var state:=ClinicState.new()
	state.data=source.duplicate(true)
	var old_orders:Dictionary=state.data.work_orders.duplicate(true)
	var cash:int=int(state.data.cash)
	var stock:Dictionary=state.data.resources.duplicate(true)
	var id:String=CampaignOperations.request(state,catalog,kind)
	var actual:String=str(state.data.work_orders[id].facility_id) if id!="" else ""
	check(actual==expected,"synthetic allocator: "+label,"actual="+actual+" expected="+expected)
	var preserved:bool=true
	for old_id:String in old_orders:
		if state.data.work_orders.get(old_id,{})!=old_orders[old_id]:preserved=false
	check(preserved and int(state.data.cash)==cash and state.data.resources==stock,"synthetic allocator: preserves existing jobs, cash and stock for "+label)
	return {"state":state,"order_id":id}

func allocation_boundaries()->void:
	if not snapshots.has("final"):return
	var source:Dictionary=snapshots.final
	var desks:Array=[]
	for fid:String in source.facilities:
		if source.facilities[fid].kind=="O05":desks.append(fid)
	desks.sort()
	check(desks.size()==2,"boundary source really contains two public-built referral desks")
	if desks.size()!=2:return
	var a:String=str(desks[0])
	var b:String=str(desks[1])
	_allocation_fixture(source,a,"empty queues use stable first ID")
	var reversed:Dictionary=source.duplicate(true)
	var keys:Array=reversed.facilities.keys();keys.reverse()
	var reordered:Dictionary={}
	for fid:String in keys:reordered[fid]=reversed.facilities[fid]
	reversed.facilities=reordered
	_allocation_fixture(reversed,a,"dictionary insertion order cannot alter long-campaign tie")
	for mode:String in ["closed","broken","unassigned"]:
		var d:Dictionary=source.duplicate(true)
		if mode=="closed":d.facilities[a].status="closed"
		elif mode=="broken":d.facilities[a].condition=0
		else:d.facilities[a].staff_ids=[]
		_allocation_fixture(d,b,"skip first desk when "+mode)
	var none:Dictionary=source.duplicate(true)
	none.facilities[a].status="closed";none.facilities[b].status="closed"
	_allocation_fixture(none,"","all desks closed gives no phantom capacity")
	none=source.duplicate(true)
	none.facilities[a].staff_ids=[];none.facilities[b].staff_ids=[]
	_allocation_fixture(none,"","all desks unassigned gives no phantom staff")
	var tired:Dictionary=source.duplicate(true)
	for sid:String in tired.facilities[a].staff_ids:tired.staff[sid].fatigue=100
	_allocation_fixture(tired,b,"equal queue load prefers truly available second crew")
	for sid:String in tired.facilities[b].staff_ids:tired.staff[sid].fatigue=100
	var busy_result:Dictionary=_allocation_fixture(tired,a,"all crews busy may queue deterministically without borrowing staff")
	if busy_result.order_id!="":
		var order:Dictionary=busy_result.state.data.work_orders[busy_result.order_id]
		check(order.status=="queued" and order.staff_ids.is_empty() and order.started_tick<0,"synthetic allocator: queued all-busy request claims no worker and starts no paid clock")
	var reserved:Dictionary=source.duplicate(true)
	reserved.facilities[a].busy_patient_id="synthetic_direct_reservation"
	_allocation_fixture(reserved,b,"real direct-patient ownership contributes candidate load")
	for status:String in ["queued","blocked","walking","working"]:
		var first:Dictionary=_allocation_fixture(source,a,"prepare preserved first job for "+status)
		if first.order_id=="":continue
		var d:Dictionary=first.state.to_data()
		d.work_orders[first.order_id].status=status
		_allocation_fixture(d,b,"unfinished "+status+" job contributes load; old allocation is not moved")
	var first:Dictionary=_allocation_fixture(source,a,"prepare done-history test")
	if first.order_id!="":
		var d:Dictionary=first.state.to_data()
		d.work_orders[first.order_id].status="done"
		d.campaign.active_order_ids.erase(first.order_id)
		_allocation_fixture(d,a,"completed historical jobs are not pending load")
	var legacy:Dictionary=source.duplicate(true)
	legacy.schema_version=2;legacy.ruleset="full-hospital-v1"
	legacy.facilities[a].condition=0;legacy.facilities[a].staff_ids=[]
	_allocation_fixture(legacy,a,"legacy v1 preserves original first-open-instance behavior")
	var repair:Dictionary=source.duplicate(true)
	repair.facilities[a].kind="O11";repair.facilities[a].condition=0
	repair.facilities[b].status="closed"
	for sid:String in repair.facilities[a].staff_ids:repair.staff[sid].role="engineer"
	_allocation_fixture(repair,a,"damaged engineer workshop retains paid field-repair eligibility","O11")
	var read_state:=ClinicState.new()
	read_state.data=source.duplicate(true)
	var candidate:Dictionary={"facility_kind":"O05","handler":str(catalog.campaign.facilities.O05.handler),"patient_id":"","step_id":"","status":"queued"}
	var before:Dictionary=read_state.to_data()
	var eligible:bool=CampaignStaffRelief.order_eligible(read_state.data,catalog,candidate)
	var crew:Array=CampaignOperations._workers(read_state.data,read_state.data.facilities[a],catalog.campaign.facilities.O05.roles,eligible)
	check(not crew.is_empty() and read_state.to_data()==before,"real baseline availability query is read-only")

func public_order_safety()->void:
	if not snapshots.has("final"):return
	var restored:Dictionary=ClinicState.from_data(snapshots.final,catalog)
	check(bool(restored.get("ok",false)),"real public final baseline restores strictly before operation safety checks",str(restored.get("error","")))
	if not restored.get("ok",false):return
	var sim:=Simulation.new(catalog,restored.state)
	issue(sim,"set_paused",{"paused":true})
	var before_orders:Dictionary=sim.snapshot().work_orders.duplicate(true)
	serial+=1
	var command:Dictionary={"id":"parallel_referral_%05d"%serial,"type":"run_operation","payload":{"facility_kind":"O05"}}
	var accepted:Dictionary=sim.submit(command)
	check(bool(accepted.get("ok",false)),"real public manual operation still accepts when all prior orders are done",str(accepted.get("code","")))
	if not accepted.get("ok",false):return
	var before:Dictionary=sim.snapshot()
	check(sim.submit(command)==accepted and sim.snapshot()==before,"real repeated command ID returns identical receipt without duplicate order or fee")
	serial+=1
	var duplicate:Dictionary=sim.submit({"id":"parallel_referral_%05d"%serial,"type":"run_operation","payload":{"facility_kind":"O05"}})
	check(not duplicate.get("ok",false) and duplicate.get("code","")=="operation_pending" and sim.snapshot()==before,"real second manual operation remains kind-deduplicated despite two machines")
	var order_id:String=str(accepted.data.work_order_id)
	issue(sim,"set_paused",{"paused":false})
	for _n:int in range(600):
		if sim._state.data.work_orders[order_id].status=="done":break
		sim.advance_ticks(1)
	var d:Dictionary=sim.snapshot()
	check(d.work_orders[order_id].status=="done","real manual order physically works to completion")
	var fee_rows:Array=[]
	for row:Dictionary in d.ledger_entries:
		if row.reference=="operation:"+order_id and row.category=="operations":fee_rows.append(row)
	check(fee_rows.size()==1 and int(fee_rows[0].amount)==-int(d.work_orders[order_id].cost),"real manual order charges exactly its one genuine operations fee")
	var preserved:bool=true
	for id:String in before_orders:
		if d.work_orders.get(id,{})!=before_orders[id]:preserved=false
	check(preserved,"real new job does not move or rewrite any historical public order")
	check(d.metrics.referred==2 and d.metrics.income==0 and SnapshotValidator.validate(d,catalog)=="","real safety continuation preserves referral totals, zero cure income and strict save validity",SnapshotValidator.validate(d,catalog))
	var save_dir:String=output.get_basename()+"-save"
	var saved:Dictionary=SaveStore.save(d,save_dir)
	check(bool(saved.get("ok",false)),"real multi-desk state writes an actual isolated disk save",str(saved.get("error","")))
	var loaded:Dictionary=SaveStore.load(save_dir,catalog)
	check(bool(loaded.get("ok",false)) and loaded.state.to_data()==d,"real multi-desk costs and completed job allocations survive exact disk roundtrip",str(loaded.get("error","")))
	snapshots.public_safety_final=d


func _crew_priority_fixture(source:Dictionary,a:String,b:String,mode:String)->void:
	var state:=ClinicState.new()
	state.data=source.duplicate(true)
	var d:Dictionary=state.data
	var first_order:String=""
	var second_order:String=""
	for oid:String in d.campaign.active_order_ids:
		var order:Dictionary=d.work_orders[oid]
		if order.facility_id==a:first_order=oid
		elif order.facility_id==b:second_order=oid
	if not check(first_order!="" and second_order!="","synthetic "+mode+": actual source has one queued job on each real desk"):return
	# Remove A's pending load in this synthetic fixture while preserving its
	# original identity/desk. No output, cost, worker or real tick is produced.
	d.work_orders[first_order].status="done"
	d.campaign.active_order_ids.erase(first_order)
	for sid:String in d.facilities[a].staff_ids:
		d.staff[sid].fatigue=95
		d.staff[sid].work_order_id=""
		d.staff[sid].patient_id=""
		d.staff[sid].training_order_id=""
		d.staff[sid].rest_activity={}
		d.staff[sid].relief_activity={}
	var second:Dictionary=d.work_orders[second_order]
	second.status=mode
	if mode=="working":
		second.staff_ids=d.facilities[b].staff_ids.duplicate()
		second.staff_id=str(second.staff_ids[0])
		second.started_tick=int(d.tick)-1
		second.work=int(second.needed)-1
		for sid:String in second.staff_ids:
			d.staff[sid].fatigue=0
			d.staff[sid].work_order_id=second_order
			d.staff[sid].status="working"
	else:
		second.staff_ids=[];second.staff_id=""
		for sid:String in d.facilities[b].staff_ids:
			d.staff[sid].fatigue=0
			d.staff[sid].work_order_id=""
			d.staff[sid].patient_id=""
			d.staff[sid].training_order_id=""
			d.staff[sid].rest_activity={}
	var before_orders:Dictionary=d.work_orders.duplicate(true)
	var cash:int=int(d.cash)
	var resources:Dictionary=d.resources.duplicate(true)
	var ledger:Array=d.ledger_entries.duplicate(true)
	var metrics:Dictionary=d.metrics.duplicate(true)
	var id:String=CampaignOperations.request(state,catalog,"O05")
	if not check(id!="","synthetic "+mode+": existing real staffed desks still accept a queued request"):return
	var created:Dictionary=d.work_orders[id]
	check(created.facility_id==b,"synthetic "+mode+": zero-load exhausted crew cannot outrank viable busy second crew",{"actual":created.facility_id,"expected":b})
	var preserved:bool=true
	for oid:String in before_orders:
		if d.work_orders.get(oid,{})!=before_orders[oid]:preserved=false
	check(preserved,"synthetic "+mode+": allocator never rewrites any existing job or its facility")
	check(d.cash==cash and d.resources==resources and d.ledger_entries==ledger and d.metrics==metrics,"synthetic "+mode+": allocating a queue creates no charge, free output, cure or referral")
	check(created.status=="queued" and created.staff_ids.is_empty() and created.staff_id=="" and created.started_tick<0,"synthetic "+mode+": future crew receives no early claim or free started clock")
	crew_priority_observations[mode]={"expected_facility":b,"actual_facility":created.facility_id,"first_fatigue":95,"second_order_state":mode,"existing_second_order_id":second_order,"new_order_id":id}

func _crew_priority_boundaries()->void:
	if not check(snapshots.get("allocated") is Dictionary,"crew priority uses this run's real public allocated snapshot"):return
	var source:Dictionary=snapshots.allocated
	if not check(SnapshotValidator.validate(source,catalog)=="","unmodified current-run crew-priority source is strict-valid",SnapshotValidator.validate(source,catalog)):return
	var desks:Array=[]
	for fid:String in source.facilities:
		if source.facilities[fid].kind=="O05":desks.append(fid)
	desks.sort()
	if check(desks.size()==2,"crew-priority source has this run's two actual desks"):
		_crew_priority_fixture(source,str(desks[0]),str(desks[1]),"queued")
		_crew_priority_fixture(source,str(desks[0]),str(desks[1]),"working")

func _run()->void:
	if test_paths==null or FileAccess.file_exists(output) or DirAccess.dir_exists_absolute(output.get_basename()+"-save"):quit(2);return
	run_probe()
	_crew_priority_boundaries()
	allocation_boundaries()
	public_order_safety()
	var report:Dictionary={"passed":passed,"failed":failed,"checks":checks,"snapshots":snapshots,"crew_priority_observations":crew_priority_observations,"scope":"External diagnostic v3. Public referral baseline and operation safety continuation use genuine formal long01 factory, commands, real ticks and disk roundtrip. All allocator synthetic fixtures use detached copies of this same run's actual snapshots; they are not legal save states or normal gameplay. Crew-priority fixtures do not load a local evidence dependency. FormalPaths enforces a fresh task-local Windows directory or existing strict isolated Mac CI runtime. No physical-phone or full-game-fun acceptance."}
	if test_paths.write_report(report)!=OK:
		printerr("PARALLEL REFERRAL PATH ERROR: report write failed");quit(2);return
	print("PARALLEL REFERRAL RESULT: passed=%d failed=%d"%[passed,failed])
	quit(1 if failed else 0)
