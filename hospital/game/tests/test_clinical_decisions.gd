extends SceneTree

# Only public construction/admission/decisions create the positive fixtures.
# The module is dynamically loaded so a missing implementation is a RED, not a parse error.
var output: String=""
var passed: int=0
var failed: int=0
var checks: Array=[]
var serial: int=0
var catalog: ContentCatalog
var decisions: Script

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=").replace("\\","/")
	_run.call_deferred()

func check(ok: bool,label: String,detail: String="") -> void:
	checks.append({"ok":ok,"check":label,"detail":detail})
	if ok: passed+=1
	else: failed+=1
	print(("CLINICAL DECISIONS PASS " if ok else "CLINICAL DECISIONS FAIL ")+label+(": "+detail if detail!="" else ""))

func issue(sim: Simulation,type: String,payload: Dictionary={}) -> Dictionary:
	serial+=1
	var r: Dictionary=sim.submit({"id":"decisions_test_%06d"%serial,"type":type,"payload":payload})
	check(bool(r.get("ok",false)),"public "+type,str(r.get("code","")))
	return r

func build(sim: Simulation,kind: String,origin: int) -> String:
	var f: Dictionary=catalog.campaign.facilities[kind]
	var r: Dictionary=issue(sim,"build_department",{"unit_id":f.unit_id,"origin_cell":origin,"layout":FacilityLayout.default_layout(f.unit_id,kind,0)})
	if not r.get("ok",false): return ""
	var fid: String=r.data.facility_ids[0]
	for role: String in f.roles:
		var hire: Dictionary=issue(sim,"hire",{"role":role})
		if not hire.get("ok",false):return ""
		if not issue(sim,"assign",{"staff_id":hire.data.staff_id,"facility_id":fid}).get("ok",false):return ""
	return fid

func prepare(policy: String="manual",referral: bool=false) -> Dictionary:
	var state: ClinicState=ClinicState.create("long_01",catalog)
	if state==null:check(false,"real long_01 state");return {}
	var sim:=Simulation.new(catalog,state)
	check(int(state.data.campaign.get("clinical_decisions_version",0))==1,"new hospital opts into version 1")
	check(str(state.data.campaign.get("clinical_policy",""))=="balanced","new hospital defaults balanced")
	if not issue(sim,"set_clinical_policy",{"policy":policy}).get("ok",false):return {}
	if build(sim,"U01-E1",25)=="" or build(sim,"O01",33)=="" or build(sim,"O15",40)=="":return {}
	if referral and build(sim,"O05",121)=="":return {}
	var order: Dictionary=issue(sim,"run_operation",{"facility_kind":"O15"})
	if not order.get("ok",false):return {}
	issue(sim,"set_paused",{"paused":false})
	for _n: int in range(1200):
		sim.advance_ticks(1)
		if state.data.work_orders[order.data.work_order_id].status=="done":break
	check(state.data.work_orders[order.data.work_order_id].status=="done","real delivery work completes")
	return {"state":state,"sim":sim}

func preview(sim: Simulation,id: String) -> Dictionary:
	var result: Dictionary=decisions.call("preview",sim._state.data,catalog,id)
	return result

func drive(sim: Simulation,predicate: Callable,limit: int,label: String) -> bool:
	var error: String=""
	for _n: int in range(limit):
		if predicate.call(sim._state.data):break
		sim.advance_ticks(1)
		error=SnapshotValidator.validate(sim.snapshot(),catalog)
		if error!="":break
	check(error=="",label+" validates during actual ticks",error)
	var reached: bool=bool(predicate.call(sim._state.data))
	check(reached,label+" within bounded ticks")
	return reached

func accept_first(sim: Simulation) -> String:
	var r: Dictionary=issue(sim,"accept_case",{"case_id":"U01-C1"})
	if not r.get("ok",false):return ""
	return str(r.data.patient_ids[0])

func gate(sim: Simulation,id: String) -> bool:
	return drive(sim,func(_d: Dictionary)->bool:return bool(preview(sim,id).get("pending",false)),1800,"actual first examination reaches decision gate")

func reject_copy(d: Dictionary,label: String) -> void:
	var before: Dictionary=d.duplicate(true)
	var e: String=SnapshotValidator.validate(d,catalog)
	check(e!="" and d==before,label,e)

func manual_checks() -> void:
	var setup: Dictionary=prepare()
	if setup.is_empty():return
	var sim: Simulation=setup.sim
	var id: String=accept_first(sim)
	if id=="":return
	var prior: Dictionary=sim.snapshot()
	var early: Dictionary=sim.submit({"id":"decisions_early","type":"clinical_decision","payload":{"patient_id":id,"action":"cautious_treat","expected_revision":0}})
	check(not early.get("ok",false) and sim.snapshot()==prior,"no decision or score before real first examination")
	if not gate(sim,id):return
	var view: Dictionary=preview(sim,id)
	check(int(view.get("confidence",-1))==77 and int(view.get("safe_threshold",-1))==80,"published untrained C1 confidence is 77/80")
	var hcount: int=sim._state.data.patients[id].step_history.size()
	sim.advance_ticks(40)
	check(bool(preview(sim,id).get("pending",false)) and sim._state.data.patients[id].step_history.size()==hcount,"manual policy waits without inventing service progress")
	serial+=1
	var cmd: Dictionary={"id":"decisions_test_%06d"%serial,"type":"clinical_decision","payload":{"patient_id":id,"action":"continue_exam","expected_revision":int(view.get("revision",0))}}
	var chosen: Dictionary=sim.submit(cmd)
	check(bool(chosen.get("ok",false)),"manual continue examination accepted",str(chosen.get("code","")))
	if not chosen.get("ok",false):return
	var after: Dictionary=sim.snapshot()
	check(sim.submit(cmd)==chosen and sim.snapshot()==after,"retry same decision command is exactly idempotent")
	var stale: Dictionary=sim.submit({"id":"decisions_stale","type":"clinical_decision","payload":cmd.payload})
	check(not stale.get("ok",false) and sim.snapshot()==after,"stale revision different command rejects without mutation")
	if not gate(sim,id):return
	view=preview(sim,id)
	check(int(view.get("confidence",-1))==95 and int(view.get("completed_exams",-1))==1,"real repeat examination raises confidence by 18")
	check(sim._state.data.patients[id].step_history.size()==hcount+1,"extra examination has real distinct completed service history")
	var active: Dictionary=sim.snapshot()
	var savepath: String=output.get_basename()+"-manual-save"
	var saved: Dictionary=SaveStore.save(active,savepath)
	var loaded: Dictionary=SaveStore.load(savepath,catalog)
	check(saved.get("ok",false) and loaded.get("ok",false),"real decision gate disk save/load")
	if loaded.get("ok",false):
		check(loaded.state.to_data()==active,"decision gate full snapshot roundtrip exact")
		var replay:=Simulation.new(catalog,loaded.state)
		serial+=1
		var treat: Dictionary={"id":"decisions_test_%06d"%serial,"type":"clinical_decision","payload":{"patient_id":id,"action":"cautious_treat","expected_revision":int(view.get("revision",-1))}}
		var left: Dictionary=sim.submit(treat)
		var right: Dictionary=replay.submit(treat)
		check(left.get("ok",false) and left==right,"same public treatment decision after load")
		for _n: int in range(1800):
			if sim._state.data.patients[id].phase=="left":break
			sim.advance_ticks(1);replay.advance_ticks(1)
		check(sim.snapshot()==replay.snapshot() and sim._state.data.patients[id].outcome=="completed","saved decision resumes deterministic actual treatment and exit")
	check(sim._state.data.metrics.completed==1 and sim._state.data.campaign.completed_cases==["U01-C1"],"only actual treatment completes signature")
	var corrupted: Dictionary=active.duplicate(true)
	corrupted.patients[id].clinical_decision.treatment_confidence=100
	reject_copy(corrupted,"forged clinical score rejects")
	corrupted=active.duplicate(true)
	corrupted.patients[id].steps[-1].cost=0
	reject_copy(corrupted,"forged inserted exam plan rejects")
	check(SnapshotValidator.validate(sim.snapshot(),catalog)=="","final manual history and finance valid",SnapshotValidator.validate(sim.snapshot(),catalog))

func cautious_low_confidence() -> void:
	var setup: Dictionary=prepare()
	if setup.is_empty():return
	var sim: Simulation=setup.sim
	var id: String=accept_first(sim)
	if id=="" or not gate(sim,id):return
	var v: Dictionary=preview(sim,id)
	if not issue(sim,"clinical_decision",{"patient_id":id,"action":"cautious_treat","expected_revision":v.revision}).get("ok",false):return
	if not drive(sim,func(d: Dictionary)->bool:return d.patients[id].phase=="left",2200,"low-confidence cautious actual treatment and remedial care"):return
	var p: Dictionary=sim._state.data.patients[id]
	var remedy: Dictionary={}
	for h: Dictionary in p.step_history:
		if ":decision:remedy" in str(h.step_id):remedy=h
	check(not remedy.is_empty(),"confidence deficit creates a real remedial visit")
	if not remedy.is_empty():
		check(int(remedy.planned_duration)==20 and int(remedy.cost)==17 and remedy.completed_tick>=remedy.started_tick+20,"deficit 3 costs exactly 17 and 20 authored ticks before efficiency")
	check(p.step_history.size()==4 and int(sim._state.data.metrics.completed)==1,"short C1 needs diagnosis, treatment and remedy rather than instant cure button")
	check(SnapshotValidator.validate(sim.snapshot(),catalog)=="","low-confidence ledger and stock proof strict",SnapshotValidator.validate(sim.snapshot(),catalog))

func referral_checks() -> void:
	var setup: Dictionary=prepare("manual",true)
	if setup.is_empty():return
	var sim: Simulation=setup.sim
	var id: String=accept_first(sim)
	if id=="" or not gate(sim,id):return
	var v: Dictionary=preview(sim,id)
	if not issue(sim,"clinical_decision",{"patient_id":id,"action":"refer","expected_revision":v.revision}).get("ok",false):return
	if not drive(sim,func(d: Dictionary)->bool:return d.patients[id].phase=="left",2200,"real O05 referral handover and physical exit"):return
	var p: Dictionary=sim._state.data.patients[id]
	var handover: bool=false
	for order: Dictionary in sim._state.data.work_orders.values():
		if order.facility_kind=="O05" and order.patient_id==id and order.status=="done":handover=true
	check(handover and p.outcome=="referred" and p.cell==GridService.EXIT_CELL,"referral has patient-linked completed work and physical departure")
	check(int(sim._state.data.metrics.completed)==0 and int(sim._state.data.metrics.abandoned)==0 and int(sim._state.data.metrics.get("referred",0))==1,"referral is neither cure nor abandonment")
	check(sim._state.data.campaign.completed_cases.is_empty() and int(sim._state.data.metrics.income)==0,"referral neither earns full fee nor signature proof")
	check(SnapshotValidator.validate(sim.snapshot(),catalog)=="","referral terminal history validates",SnapshotValidator.validate(sim.snapshot(),catalog))

func automatic_policy() -> void:
	var setup: Dictionary=prepare("balanced")
	if setup.is_empty():return
	var sim: Simulation=setup.sim
	var id: String=accept_first(sim)
	if id=="":return
	if not drive(sim,func(d: Dictionary)->bool:return d.patients[id].phase=="left",2600,"balanced public policy actually examines treats and exits unattended"):return
	check(int(preview(sim,id).get("completed_exams",-1))==1 and sim._state.data.patients[id].step_history.size()==4,"balanced low confidence does one real extra examination then treatment")
	check(SnapshotValidator.validate(sim.snapshot(),catalog)=="","automatic decisions replay/history valid",SnapshotValidator.validate(sim.snapshot(),catalog))

func _run() -> void:
	if not output.begins_with("E:/CODEX/") or output.simplify_path()!=output or FileAccess.file_exists(output) or DirAccess.dir_exists_absolute(output.get_basename()+"-manual-save"):
		printerr("Require fresh E:/CODEX report and save directory");quit(2);return
	var loaded: Dictionary=ContentCatalog.load_checked("res://content")
	check(bool(loaded.get("ok",false)),"real catalog loads",str(loaded.get("error","")))
	if loaded.get("ok",false):
		catalog=loaded.catalog
		var fresh: ClinicState=ClinicState.create("long_01",catalog)
		check(fresh!=null and int(fresh.data.campaign.get("clinical_decisions_version",0))==1,"fresh long hospital uses versioned clinical decisions")
		if fresh!=null:
			var sim:=Simulation.new(catalog,fresh)
			var policy: Dictionary=sim.submit({"id":"decisions_policy_probe","type":"set_clinical_policy","payload":{"policy":"manual"}})
			check(bool(policy.get("ok",false)),"public manual clinical policy exists",str(policy.get("code","")))
		var exists: bool=ResourceLoader.exists("res://campaign/campaign_clinical_decisions.gd")
		check(exists,"clinical decisions module exists")
		if exists:
			decisions=load("res://campaign/campaign_clinical_decisions.gd")
			if decisions!=null:manual_checks();cautious_low_confidence();referral_checks();automatic_policy()
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	var file:=FileAccess.open(output,FileAccess.WRITE)
	if file==null:quit(2);return
	file.store_string(JSON.stringify({"ok":failed==0,"passed":passed,"failed":failed,"checks":checks,"scope":"real public short-case clinical decisions; no authored patient/state injection; corrupt copies only negative validation"},"\t"));file.close()
	print("CLINICAL DECISIONS RESULT passed="+str(passed)+" failed="+str(failed))
	quit(0 if failed==0 else 1)
