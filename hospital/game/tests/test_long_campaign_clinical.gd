extends SceneTree

# Real long_01/public commands only. No authored plans, inventory, patients,
# phases, clocks or balance are injected. Corrupt copies are negative saves.
var output := ""
var passed := 0
var failed := 0
var checks: Array=[]
var sequence := 0
var catalog: ContentCatalog

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=").replace("\\","/")
	_run.call_deferred()

func check(ok: bool,label: String,detail: String="") -> void:
	checks.append({"ok":ok,"check":label,"detail":detail})
	if ok: passed+=1
	else: failed+=1
	print(("LONG CLINICAL PASS: " if ok else "LONG CLINICAL FAIL: ")+label+(": "+detail if detail!="" else ""))

func issue(sim: Simulation,type: String,payload: Dictionary) -> Dictionary:
	sequence+=1
	var result: Dictionary=sim.submit({"id":"long_public_%05d"%sequence,"type":type,"payload":payload})
	check(bool(result.get("ok",false)),"public "+type,str(result.get("code","")))
	return result

func build(sim: Simulation,kind: String,origin: int) -> String:
	var definition: Dictionary=catalog.campaign.facilities[kind]
	var result: Dictionary=issue(sim,"build_department",{"unit_id":definition.unit_id,"origin_cell":origin,"layout":FacilityLayout.default_layout(definition.unit_id,kind,0)})
	if not result.get("ok",false): return ""
	var facility_id: String=result.data.facility_ids[0]
	for role: String in definition.roles:
		var hired: Dictionary=issue(sim,"hire",{"role":role})
		if not hired.get("ok",false): return ""
		if not issue(sim,"assign",{"staff_id":hired.data.staff_id,"facility_id":facility_id}).get("ok",false): return ""
	return facility_id

func prepare() -> Dictionary:
	var state: ClinicState=ClinicState.create("long_01",catalog)
	check(state!=null,"real long_01 factory")
	if state==null: return {}
	var sim:=Simulation.new(catalog,state)
	var clinical_id: String=build(sim,"U01-E1",25)
	if clinical_id=="" or build(sim,"O01",33)=="" or build(sim,"O15",40)=="": return {}
	var delivery: Dictionary=issue(sim,"run_operation",{"facility_kind":"O15"})
	if not delivery.get("ok",false): return {}
	issue(sim,"set_paused",{"paused":false})
	for _n in range(1200):
		sim.advance_ticks(1)
		if state.data.work_orders[delivery.data.work_order_id].status=="done": break
	check(state.data.work_orders[delivery.data.work_order_id].status=="done" and int(state.data.resources.get("delivered",0))>=3,"real assigned logistics worker physically delivers stock")
	return {"state":state,"sim":sim,"clinical_id":clinical_id}

func drive(sim: Simulation,predicate: Callable,limit: int,label: String) -> bool:
	var error := ""
	for _n in range(limit):
		if predicate.call(sim.snapshot()): break
		sim.advance_ticks(1)
		error=SnapshotValidator.validate(sim.snapshot(),catalog)
		if error!="": break
	check(error=="",label+" strict validation during every real tick",error)
	var reached: bool=bool(predicate.call(sim.snapshot()))
	check(reached,label+" reached within bounded real ticks")
	return reached

func reject_copy(snapshot: Dictionary,label: String) -> void:
	var before: Dictionary=snapshot.duplicate(true)
	var error: String=SnapshotValidator.validate(snapshot,catalog)
	check(error!="" and before==snapshot,label,error)

func repeated_visits() -> void:
	var setup: Dictionary=prepare()
	if setup.is_empty(): return
	var state: ClinicState=setup.state
	var sim: Simulation=setup.sim
	var first: Dictionary=issue(sim,"accept_case",{"case_id":"U01-C1"})
	if not first.get("ok",false): return
	if not drive(sim,func(d: Dictionary)->bool: return d.patients.patient_001.phase=="left",1500,"first signature physical departure"): return
	check(not state.data.paused and state.data.challenge.status=="running" and state.data.campaign.completed_cases==["U01-C1"],"signature completion leaves hospital running and records one template")
	var first_instance: String=first.data.instance_id
	check(state.data.campaign.case_instances[first_instance].status=="completed" and state.data.campaign.live_patient_ids.is_empty(),"first instance completes and active index releases it")
	sequence+=1
	var command: Dictionary={"id":"long_public_%05d"%sequence,"type":"admit_routine","payload":{"case_id":"U01-C1"}}
	var second: Dictionary=sim.submit(command)
	check(bool(second.get("ok",false)),"same template admits as genuine second instance",str(second.get("code","")))
	if not second.get("ok",false): return
	var before: Dictionary=state.to_data()
	check(sim.submit(command)==second and state.to_data()==before,"retry same public command returns same instance without duplicate admission")
	issue(sim,"set_price",{"percent":115})
	var third: Dictionary=issue(sim,"admit_routine",{"case_id":"U01-C1"})
	if not third.get("ok",false): return
	var second_id: String=second.data.patient_ids[0]
	var third_id: String=third.data.patient_ids[0]
	check(second.data.instance_id!=third.data.instance_id and second_id!=third_id and state.data.campaign.case_instances.size()==3,"overlapping repeated template has unique instances and permanent patient IDs")
	var event2: Dictionary=state.data.campaign.admission_events[state.data.campaign.case_instances[second.data.instance_id].admission_event_id]
	var event3: Dictionary=state.data.campaign.admission_events[state.data.campaign.case_instances[third.data.instance_id].admission_event_id]
	check(event2.tick==event3.tick and event2.quoted_price_percent==100 and event3.quoted_price_percent==115 and event2.command_sequence<event3.command_sequence,"same-tick public price change locks different actual admission quotes")
	check(state.data.patients[second_id].income==int(catalog.campaign.cases["U01-C1"].income) and state.data.patients[third_id].income==int(int(catalog.campaign.cases["U01-C1"].income)*115/100),"each new patient retains exact quoted case income")
	if not drive(sim,func(d: Dictionary)->bool: return d.patients[second_id].phase=="care_service" and d.patients[second_id].service_work==5,1000,"second visit actual mid-service"): return
	var active: Dictionary=state.to_data()
	var save_dir: String=output.get_basename()+"-active-save"
	var saved: Dictionary=SaveStore.save(active,save_dir)
	check(bool(saved.get("ok",false)),"actual disk save while repeated visits overlap",str(saved.get("error","")))
	var loaded: Dictionary=SaveStore.load(save_dir,catalog)
	check(bool(loaded.get("ok",false)),"actual disk load repeated active visits",str(loaded.get("error","")))
	if loaded.get("ok",false):
		check(loaded.state.to_data()==active,"full active snapshot exact disk roundtrip")
		var replay:=Simulation.new(catalog,loaded.state)
		for _n in range(1800):
			if state.data.campaign.live_patient_ids.is_empty(): break
			sim.advance_ticks(1); replay.advance_ticks(1)
		check(replay.snapshot()==state.to_data() and state.data.campaign.live_patient_ids.is_empty(),"loaded overlapping visits deterministically replay through all real exits")
	check(state.data.metrics.completed==3 and state.data.metrics.abandoned==0 and state.data.campaign.completed_cases==["U01-C1"] and not state.data.paused,"three physical cures keep one signature proof and continuous running")
	check(SnapshotValidator.validate(state.to_data(),catalog)=="","completed repeated histories, stock and ledger remain strictly valid",SnapshotValidator.validate(state.to_data(),catalog))
	var altered: Dictionary=active.duplicate(true)
	altered.patients[second_id].case_instance_id=third.data.instance_id
	reject_copy(altered,"patient cannot steal another instance identity")
	altered=active.duplicate(true); altered.campaign.live_patient_ids.erase(second_id)
	reject_copy(altered,"removing active patient from live index rejects")
	altered=active.duplicate(true); altered.campaign.admission_events[event3.id].quoted_price_percent=100
	reject_copy(altered,"same-tick admission price cannot be rewritten")
	altered=active.duplicate(true); altered.campaign.case_instances[third.data.instance_id].patient_ids=[second_id]
	reject_copy(altered,"duplicate instance patient ownership rejects")
	altered=active.duplicate(true); altered.patients[second_id].service_work+=1
	reject_copy(altered,"new ruleset still rejects forged service clock")
	altered=active.duplicate(true); altered.resources.delivered+=1
	reject_copy(altered,"new ruleset still rejects conjured delivered stock")

func recover_after_abandonment() -> void:
	var setup: Dictionary=prepare()
	if setup.is_empty(): return
	var state: ClinicState=setup.state
	var sim: Simulation=setup.sim
	var accepted: Dictionary=issue(sim,"accept_case",{"case_id":"U01-C1"})
	if not accepted.get("ok",false): return
	if not issue(sim,"close_facility",{"facility_id":setup.clinical_id}).get("ok",false): return
	if not drive(sim,func(d: Dictionary)->bool: return d.patients.patient_001.phase=="abandoned",3200,"real closed-clinic patience loss and physical exit"): return
	check(state.data.challenge.status=="running" and not state.data.paused and state.data.metrics.abandoned==1 and state.data.metrics.income==0,"one genuine abandonment records loss without global instant defeat or income")
	check(state.data.campaign.case_instances[accepted.data.instance_id].status=="failed" and state.data.campaign.completed_cases.is_empty(),"failed signature instance remains history and is retryable")
	check(state.data.campaign.reputation==45,"actual abandoned departure costs exactly five reputation")
	if not issue(sim,"reopen_facility",{"facility_id":setup.clinical_id}).get("ok",false): return
	var retry: Dictionary=issue(sim,"accept_case",{"case_id":"U01-C1"})
	if not retry.get("ok",false): return
	var patient_id: String=retry.data.patient_ids[0]
	drive(sim,func(d: Dictionary)->bool: return d.patients[patient_id].phase=="left",1600,"same hospital publicly reopens and completes retried signature")
	check(state.data.metrics.completed==1 and state.data.metrics.abandoned==1 and state.data.challenge.status=="running" and state.data.campaign.completed_cases==["U01-C1"],"successful retry advances signature once while preserving prior loss")
	check(SnapshotValidator.validate(state.to_data(),catalog)=="","recoverable failed-instance history and unique actual income stay valid",SnapshotValidator.validate(state.to_data(),catalog))

func _run() -> void:
	if not output.begins_with("E:/CODEX/") or output.simplify_path()!=output or FileAccess.file_exists(output) or DirAccess.dir_exists_absolute(output.get_basename()+"-active-save"):
		printerr("Require fresh E:/CODEX output and save directory"); quit(2); return
	var loaded: Dictionary=ContentCatalog.load_checked("res://content")
	check(bool(loaded.get("ok",false)),"real catalog loads",str(loaded.get("error","")))
	if loaded.get("ok",false): catalog=loaded.catalog; repeated_visits(); recover_after_abandonment()
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	var file:=FileAccess.open(output,FileAccess.WRITE)
	if file==null: quit(2); return
	file.store_string(JSON.stringify({"ok":failed==0,"passed":passed,"failed":failed,"coverage":"genuine public long_01 construction, staff, production, repeated instances, mid-service disk replay and closed-clinic recovery; corrupted copies are negative saves only","checks":checks},"\t")); file.close()
	print("LONG CLINICAL RESULT passed="+str(passed)+" failed="+str(failed))
	quit(0 if failed==0 else 1)
