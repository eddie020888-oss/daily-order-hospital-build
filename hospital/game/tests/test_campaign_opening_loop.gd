extends SceneTree

const FormalPaths=preload("res://tests/support/formal_test_paths.gd")
var test_paths:Variant

# These fixtures use the existing full-hospital-v2 public commands and clock.
# No inventory, patients, completion evidence, prices or balance are injected.
var output:String=""
var passed:int=0
var failed:int=0
var checks:Array=[]
var serial:int=0
var catalog:ContentCatalog
var opening:Script
var factory:Script

func _initialize()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=").replace("\\","/")
	var reservation:Dictionary=FormalPaths.reserve(output,"campaign-opening-loop")
	if not reservation.get("ok",false):
		printerr("FORMAL TEST PATH ERROR: "+str(reservation.get("code","unknown")));quit(2);return
	test_paths=reservation.paths;output=str(reservation.output)
	_run.call_deferred()

func check(ok:bool,label:String,detail:String="")->void:
	checks.append({"ok":ok,"check":label,"detail":detail})
	if ok:passed+=1
	else:failed+=1
	print(("OPENING LOOP PASS " if ok else "OPENING LOOP FAIL ")+label+(": "+detail if detail!="" else ""))

func _method(script:Script,name:String)->bool:
	for method:Dictionary in script.get_script_method_list():
		if str(method.name)==name:return true
	return false

func command(sim:Simulation,type:String,payload:Dictionary={})->Dictionary:
	serial+=1
	return {"id":"opening_public_%06d"%serial,"type":type,"payload":payload}

func issue(sim:Simulation,type:String,payload:Dictionary={})->Dictionary:
	var result:Dictionary=sim.submit(command(sim,type,payload))
	check(bool(result.get("ok",false)),"public "+type,str(result.get("code","")))
	return result

func reject(sim:Simulation,type:String,payload:Dictionary,label:String,expected_code:String="")->void:
	var before:Dictionary=sim.snapshot()
	var result:Dictionary=sim.submit(command(sim,type,payload))
	check(not result.get("ok",false) and sim.snapshot()==before and (expected_code=="" or result.get("code","")==expected_code),label,str(result.get("code","")))

func view(sim:Simulation)->Dictionary:
	var before:Dictionary=sim.snapshot()
	var result:Dictionary=opening.call("preview",sim._state.data,catalog)
	check(sim.snapshot()==before,"opening guide reader does not mutate hospital")
	return result

func build(sim:Simulation,kind:String,origin:int,staffed:bool=true)->String:
	var definition:Dictionary=catalog.campaign.facilities[kind]
	var result:Dictionary=issue(sim,"build_department",{"unit_id":definition.unit_id,"origin_cell":origin,"layout":FacilityLayout.default_layout(definition.unit_id,kind,0)})
	if not result.get("ok",false):return ""
	var id:String=str(result.data.facility_ids[0])
	if staffed:staff(sim,id)
	return id

func staff(sim:Simulation,id:String)->void:
	var definition:Dictionary=catalog.campaign.facilities[sim._state.data.facilities[id].kind]
	for role:String in definition.roles:
		var hired:Dictionary=issue(sim,"hire",{"role":role})
		if not hired.get("ok",false):return
		issue(sim,"assign",{"staff_id":hired.data.staff_id,"facility_id":id})

func live_error(d:Dictionary)->String:
	var actual:int=0
	for patient:Dictionary in d.patients.values():
		if patient.phase not in ["left","abandoned"]:actual+=1
	if actual>2:return "actual_live_patient_limit:"+str(actual)
	if actual!=d.campaign.live_patient_ids.size():return "actual_live_index_mismatch"
	return ""

func advance_checked(sim:Simulation,count:int,label:String)->bool:
	var error:String=""
	var max_live:int=0
	for _n:int in range(count):
		sim.advance_ticks(1)
		var current:Dictionary=sim.snapshot()
		error=SnapshotValidator.validate(current,catalog)
		if error=="":error=live_error(current)
		max_live=maxi(max_live,current.campaign.live_patient_ids.size())
		if error!="":break
	check(error=="",label+" every tick validates actual active patients and ownership",error)
	check(max_live<=2,label+" never exceeds two active patients","maximum_live="+str(max_live))
	return error==""

func drive(sim:Simulation,predicate:Callable,limit:int,label:String)->bool:
	var error:String=""
	for _n:int in range(limit):
		if predicate.call(sim._state.data):break
		sim.advance_ticks(1)
		var current:Dictionary=sim.snapshot()
		error=SnapshotValidator.validate(current,catalog)
		if error=="":error=live_error(current)
		if error!="":break
	check(error=="",label+" validates each real tick",error)
	var reached:bool=bool(predicate.call(sim._state.data))
	check(reached,label+" reached within bounded real ticks")
	return reached

func prepare(referral:bool=false,therapy:bool=false)->Dictionary:
	var state:ClinicState=factory.call("create_formal","long_01",catalog)
	check(state!=null,"formal hospital factory returns existing state model")
	if state==null:return {}
	var sim:=Simulation.new(catalog,state)
	if build(sim,"U04-E1",25)=="" or build(sim,"O01",33)=="":return {}
	var logistics:String=build(sim,"O15",40)
	if logistics=="":return {}
	var before_stock:Dictionary=view(sim)
	check(str(before_stock.next_requirement.get("code",""))=="supply_operation","built assigned supply desk requests work rather than another desk")
	var delivery:Dictionary=issue(sim,"run_operation",{"facility_kind":"O15"})
	if not delivery.get("ok",false):return {}
	check(str(view(sim).next_requirement.get("code",""))=="supply_in_progress","real active delivery is visible as in progress")
	issue(sim,"set_paused",{"paused":false})
	if not drive(sim,func(d:Dictionary)->bool:return d.work_orders[delivery.data.work_order_id].status=="done",1200,"assigned logistics staff really produces delivered stock"):return {}
	if referral and build(sim,"O05",125)=="":return {}
	if therapy and build(sim,"U04-E2",129)=="":return {}
	return {"state":state,"sim":sim}

func factory_and_compatibility()->void:
	var legacy:ClinicState=LongCampaignState.create("long_01",catalog)
	check(not legacy.data.campaign.has("opening_loop_version") and legacy.data.campaign.clinical_policy=="balanced","existing factory retains old admission and automatic clinical policy")
	var legacy_sim:=Simulation.new(catalog,legacy)
	check(not bool(view(legacy_sim).get("enabled",true)),"old save without optional field stays on old rules")
	reject(legacy_sim,"admit_routine",{"case_id":"U04-C2"},"old hospital cannot admit unearned outside-level opening template")
	for level_id:String in ["long_01","long_12"]:
		var state:ClinicState=factory.call("create_formal",level_id,catalog)
		if state==null:check(false,"formal "+level_id+" factory");continue
		var old:ClinicState=LongCampaignState.create(level_id,catalog)
		check(state.data.schema_version==3 and state.data.ruleset=="full-hospital-v2" and state.data.level_id==level_id,"formal "+level_id+" shares the same version2 simulation")
		check(state.data.cash==old.data.cash and state.data.resources==old.data.resources and state.data.rooms.is_empty() and state.data.staff.is_empty(),"formal "+level_id+" does not give money inventory rooms or workers")
		check(state.data.campaign.completed_cases.is_empty() and state.data.metrics.completed==0 and state.data.metrics.income==0,"formal "+level_id+" grants no cures signatures or receipts")
		check(SnapshotValidator.validate(state.to_data(),catalog)=="","formal "+level_id+" initial state strictly validates",SnapshotValidator.validate(state.to_data(),catalog))
		var sim:=Simulation.new(catalog,state)
		var status:Dictionary=view(sim)
		check(status.enabled and status.template_case_id=="U04-C2" and status.primary_kind=="U04-E1" and status.treatment_kind=="U04-E2","opening reader identifies separate real examination and treatment")
		check(not status.can_admit and status.next_requirement.code=="build" and status.next_requirement.facility_kind=="O01","empty hospital first needs real reception rather than imaginary arrivals")
		check(LongCampaign.facility_unlocked(state.data,catalog,"U04-E1") and LongCampaign.facility_unlocked(state.data,catalog,"U04-E2") and LongCampaign.facility_unlocked(state.data,catalog,"O05"),"new opening permits all real first-loop capabilities")
		check(not LongCampaign.facility_unlocked(state.data,catalog,"U04-E3") if level_id=="long_01" else true,"opening does not unlock unrelated respiratory equipment")
		var long_script:Script=load("res://campaign/long_campaign.gd")
		check(long_script.call("routine_case_ids",state.data,catalog)==["U04-C2"],"opening template is selectable before any signature completion")
		var malformed:Dictionary=state.to_data()
		malformed.campaign.opening_loop_version=99
		check(SnapshotValidator.validate(malformed,catalog)!="","unknown opening version is rejected instead of silently downgraded")

func admission_and_exit()->void:
	var setup:Dictionary=prepare()
	if setup.is_empty():return
	var sim:Simulation=setup.sim
	reject(sim,"admit_routine",{"case_id":"U04-C2"},"first examination alone cannot admit without treatment or a working referral outlet","missing_facility:O05")
	var referral_id:String=build(sim,"O05",125,false)
	if referral_id=="":return
	reject(sim,"admit_routine",{"case_id":"U04-C2"},"unstaffed referral desk is not an exit capability","missing_staff:U04-C2:decision:referral")
	staff(sim,referral_id)
	var ready:Dictionary=view(sim)
	check(ready.can_admit and ready.primary_ready and ready.referral_ready and not ready.treatment_ready,"working referral permits bounded admission while treatment is still absent")
	check(ready.next_requirement.code=="open_intake","ready hospital asks to open intake without building full case route")
	var request:Dictionary=command(sim,"admit_routine",{"case_id":"U04-C2"})
	var first:Dictionary=sim.submit(request)
	check(bool(first.get("ok",false)),"unearned opening template admits as a real routine instance",str(first.get("code","")))
	if not first.get("ok",false):return
	var after:Dictionary=sim.snapshot()
	check(sim.submit(request)==first and sim.snapshot()==after,"same admission command never duplicates a patient")
	var second:Dictionary=issue(sim,"admit_routine",{"case_id":"U04-C2"})
	if not second.get("ok",false):return
	reject(sim,"admit_routine",{"case_id":"U04-C2"},"two live opening patients cap new arrivals without completing fake signatures")
	var d:Dictionary=sim.snapshot()
	check(d.campaign.completed_cases.is_empty() and int(d.metrics.completed)==0 and int(d.metrics.income)==0,"admitting genuine patients does not award case completion or income")
	var first_id:String=str(first.data.patient_ids[0])
	var second_id:String=str(second.data.patient_ids[0])
	if not drive(sim,func(data:Dictionary)->bool:return bool(CampaignClinicalDecisions.preview(data,catalog,first_id).get("pending",false)),1800,"first completed pulmonary examination reaches a visible clinical decision"):return
	d=sim.snapshot()
	var hcount:int=d.patients[first_id].step_history.size()
	if not advance_checked(sim,30,"visible first decision wait"):return
	d=sim.snapshot()
	check(CampaignClinicalDecisions.preview(d,catalog,first_id).pending and d.patients[first_id].step_history.size()==hcount and int(d.metrics.income)==0,"manual first decision remains visible and cannot silently complete treatment")
	var v:Dictionary=CampaignClinicalDecisions.preview(d,catalog,first_id)
	reject(sim,"clinical_decision",{"patient_id":first_id,"action":"cautious_treat","expected_revision":v.revision},"missing true therapy cannot be replaced by another first-exam cure")
	var before_save:Dictionary=sim.snapshot()
	var fixture_path:String=test_paths.fixture("decision-save")
	if fixture_path=="":
		printerr("FORMAL TEST PATH ERROR: fixture_create_failed");quit(2);return
	var save_path:String=fixture_path
	var saved:Dictionary=SaveStore.save(before_save,save_path)
	var loaded:Dictionary=SaveStore.load(save_path,catalog)
	check(saved.get("ok",false) and loaded.get("ok",false),"actual opening decision disk save/load succeeds",str(loaded.get("error","")))
	if loaded.get("ok",false):check(loaded.state.to_data()==before_save,"decision pending and all money history survive exact disk roundtrip")
	var corrupt:Dictionary=before_save.duplicate(true)
	corrupt.campaign.erase("opening_loop_version")
	check(SnapshotValidator.validate(corrupt,catalog)!="","erasing version cannot launder an unearned opening admission into an old save")
	corrupt=before_save.duplicate(true)
	corrupt.campaign.completed_cases=["U04-C2"]
	check(SnapshotValidator.validate(corrupt,catalog)!="","opening case cannot forge ordered signature progress")
	issue(sim,"clinical_decision",{"patient_id":first_id,"action":"continue_exam","expected_revision":v.revision})
	if not drive(sim,func(data:Dictionary)->bool:return CampaignClinicalDecisions.preview(data,catalog,first_id).pending,1400,"additional examination is a new actual service"):return
	if build(sim,"U04-E2",129)=="":return
	d=sim.snapshot()
	v=CampaignClinicalDecisions.preview(d,catalog,first_id)
	var treatment:Dictionary=issue(sim,"clinical_decision",{"patient_id":first_id,"action":"cautious_treat","expected_revision":v.revision})
	if not treatment.get("ok",false):return
	if not drive(sim,func(data:Dictionary)->bool:return CampaignClinicalDecisions.preview(data,catalog,second_id).pending,1400,"second real patient can reach its own clinical decision"):return
	d=sim.snapshot()
	v=CampaignClinicalDecisions.preview(d,catalog,second_id)
	issue(sim,"clinical_decision",{"patient_id":second_id,"action":"refer","expected_revision":v.revision})
	if not drive(sim,func(data:Dictionary)->bool:return data.campaign.live_patient_ids.is_empty(),2600,"one actual treatment and one referral release all patients and work slots"):return
	d=sim.snapshot()
	var therapy:Dictionary={}
	for h:Dictionary in d.patients[first_id].step_history:
		if h.step_id=="U04-C2:step2":therapy=h
	check(not therapy.is_empty() and therapy.facility_kind=="U04-E2" and int(therapy.completed_tick)>=int(therapy.started_tick)+int(therapy.duration_ticks if therapy.has("duration_ticks") else therapy.planned_duration),"cure contains the authored distinct physical nebulizer treatment")
	check(d.patients[first_id].outcome=="completed" and d.patients[second_id].outcome=="referred","treatment and referral have different real terminal outcomes")
	check(int(d.metrics.completed)==1 and int(d.metrics.get("referred",0))==1 and int(d.metrics.abandoned)==0,"one cure plus one referral never counts as two cures")
	check(int(d.metrics.income)==240 and d.campaign.completed_cases.is_empty(),"only actual cure earns quoted 35-percent fee and opening routines do not unlock signatures",str(d.metrics.income))
	var handover:bool=false
	for order:Dictionary in d.work_orders.values():
		if order.facility_kind=="O05" and order.patient_id==second_id and order.status=="done":handover=true
	check(handover,"referral has an actual assigned patient-linked completed handover")
	for id:String in [first_id,second_id]:
		check(d.patients[id].blocked_slot_id=="" and d.patients[id].facility_id=="" and d.patients[id].cell==GridService.EXIT_CELL,"departed "+id+" does not retain the last examination station")
	check(SnapshotValidator.validate(sim.snapshot(),catalog)=="","all final admission service stock finance and departure evidence validates",SnapshotValidator.validate(sim.snapshot(),catalog))

func automatic_bounded_arrivals()->void:
	var setup:Dictionary=prepare(true,false)
	if setup.is_empty():return
	var sim:Simulation=setup.sim
	issue(sim,"set_intake",{"enabled":true})
	if not drive(sim,func(data:Dictionary)->bool:return data.campaign.live_patient_ids.size()==2,2400,"ordinary automatic intake starts without a completed authored wave"):return
	var d:Dictionary=sim.snapshot()
	var events:int=d.campaign.admission_events.size()
	if not advance_checked(sim,700,"continued ordinary automatic intake"):return
	d=sim.snapshot()
	check(d.campaign.live_patient_ids.size()==2 and d.campaign.admission_events.size()==events,"automatic arrivals respect the same two-live-patient cap while decisions wait")
	check(d.campaign.completed_cases.is_empty() and int(d.metrics.completed)==0 and int(d.metrics.income)==0,"ordinary automatic intake invents no cures signatures or revenue")
	for event:Dictionary in d.campaign.admission_events.values():check(event.source=="auto" and event.case_id=="U04-C2","auto arrival preserves real admission source template and cursor evidence")
	check(SnapshotValidator.validate(sim.snapshot(),catalog)=="","automatic opening admissions pass strict historical validation",SnapshotValidator.validate(sim.snapshot(),catalog))

func _run()->void:
	var loaded:Dictionary=ContentCatalog.load_checked("res://content")
	check(bool(loaded.get("ok",false)),"real content loads",str(loaded.get("error","")))
	if loaded.get("ok",false):
		catalog=loaded.catalog
		factory=load("res://campaign/long_campaign_state.gd")
		var factory_ready:bool=_method(factory,"create_formal")
		var reader_ready:bool=ResourceLoader.exists("res://campaign/campaign_opening_loop.gd")
		check(factory_ready,"new formal factory API exists")
		check(reader_ready,"read-only opening capability reader exists")
		var long_script:Script=load("res://campaign/long_campaign.gd")
		var routine_ready:bool=_method(long_script,"routine_case_ids")
		check(routine_ready,"manual automatic and UI routine choices share one source")
		if factory_ready and reader_ready and routine_ready:
			opening=load("res://campaign/campaign_opening_loop.gd")
			factory_and_compatibility()
			admission_and_exit()
			automatic_bounded_arrivals()
	if test_paths.write_report({"ok":failed==0,"passed":passed,"failed":failed,"coverage":"real public-command formal v2 admission, delivered stock, decision, distinct therapy, referral, bounded intake and disk evidence; no renderer or physical-device claim","checks":checks},"\t")!=OK:
		printerr("FORMAL TEST PATH ERROR: report_write_failed");quit(2);return

	print("OPENING LOOP RESULT passed="+str(passed)+" failed="+str(failed))
	quit(0 if failed==0 else 1)
