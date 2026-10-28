extends SceneTree

# Regression for the real referral-ready opening followed by a newly built,
# unstaffed treatment device. No imported checkpoint or clinical-state edits.
const Paths=preload("res://tests/support/onboarding_test_paths.gd")
const Guide=preload("res://ui/campaign_opening_guide.gd")
const Opening=preload("res://campaign/campaign_opening_loop.gd")
const StaffingFlow=preload("res://ui/campaign_staffing_flow.gd")
var paths:Variant
var session:GameSession
var catalog:ContentCatalog
var passed:int=0
var failed:int=0
var checks:Array=[]
var notes:Dictionary={}

func _initialize()->void:
	var output:String=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	var reserved:Dictionary=Paths.reserve(output,"opening-treatment-staff-guide")
	if not reserved.get("ok",false):printerr("TREATMENT STAFF GUIDE PATH ERROR: "+str(reserved.get("code","unknown")));quit(2);return
	paths=reserved.paths
	_run.call_deferred()

func check(ok:bool,label:String,detail:Variant=null)->bool:
	checks.append({"ok":ok,"check":label,"detail":detail})
	if ok:passed+=1
	else:failed+=1
	print(("TREATMENT STAFF GUIDE PASS: " if ok else "TREATMENT STAFF GUIDE FAIL: ")+label)
	return ok

func issue(type:String,payload:Dictionary)->Dictionary:
	var result:Dictionary=session.issue(type,payload)
	check(result.get("ok",false),"public fixture command "+type,result)
	return result

func build(kind:String,origin:int,with_staff:bool=true)->String:
	var definition:Dictionary=catalog.campaign.facilities[kind]
	var result:Dictionary=issue("build_department",{"unit_id":definition.unit_id,"origin_cell":origin,"layout":FacilityLayout.default_layout(str(definition.unit_id),kind,0)})
	if not result.get("ok",false):return ""
	var fid:String=str(result.data.facility_ids[0])
	if with_staff:
		for role:String in definition.roles:
			var hired:Dictionary=issue("hire",{"role":role})
			if not hired.get("ok",false):return ""
			if not issue("assign",{"staff_id":hired.data.staff_id,"facility_id":fid}).get("ok",false):return ""
	return fid

func guide(label:String)->Dictionary:
	var before:Dictionary=session.sim.snapshot()
	var result:Dictionary=Guide.current(before,catalog)
	check(session.sim.snapshot()==before,label+" guide remains read-only")
	notes[label]=result
	return result

func expect_staff(label:String,fid:String,role:String,control:String)->void:
	var current:Dictionary=guide(label)
	var focus:Dictionary=current.get("focus",{})
	check(current.get("visible",false) and focus.get("action","")=="staff" and focus.get("facility_kind","")=="U04-E2" and focus.get("facility_id","")==fid and focus.get("role","")==role,label+" prioritizes the exact built treatment vacancy before generic resume/goals",current)
	check(focus.get("control","")==control,label+" names the real hire or existing-staff choice",focus)

func _run()->void:
	var loaded:Dictionary=ContentCatalog.load_checked("res://content")
	if not check(loaded.get("ok",false),"actual production catalog loads"):finish();return
	catalog=loaded.catalog
	var folder:String=paths.fixture("treatment-guide-profile")
	if not check(folder!="","fresh isolated profile reserved"):finish();return
	session=GameSession.new(catalog,folder)
	check(int(session.sim.snapshot().campaign.get("opening_loop_version",0))==1,"unmodified default session uses formal opening policy")
	if build("U04-E1",25)=="" or build("O01",33)=="" or build("O15",40)=="" or build("O05",125)=="":finish();return
	var delivery:Dictionary=issue("run_operation",{"facility_kind":"O15"})
	if not delivery.get("ok",false):finish();return
	if not issue("set_paused",{"paused":false}).get("ok",false):finish();return
	var validation:String=""
	var waited:int=0
	while waited<1200 and session.sim.snapshot().work_orders[delivery.data.work_order_id].status!="done":
		session.sim.advance_ticks(1);waited+=1
		validation=SnapshotValidator.validate(session.sim.snapshot(),catalog)
		if validation!="":break
	check(validation=="","all genuine delivery ticks strictly validate",validation)
	if not check(session.sim.snapshot().work_orders[delivery.data.work_order_id].status=="done","real staffed delivery actually completes within bounded ticks",waited):finish();return
	if not issue("set_intake",{"enabled":true}).get("ok",false):finish();return
	var before_build:Dictionary=Opening.preview(session.sim.snapshot(),catalog)
	check(before_build.can_admit and before_build.referral_ready and not before_build.treatment_ready,"actual staffed referral permits intake without treatment; admission policy is unchanged",before_build)
	check(session.sim.snapshot().patients.is_empty(),"no patient or clinical decision is injected into staffing-priority fixture")
	var expansion:Dictionary=guide("before_optional_treatment")
	check(expansion.get("focus",{}).get("action","")=="build" and expansion.get("focus",{}).get("facility_kind","")=="U04-E2","real running guide already offers optional treatment expansion",expansion)
	if not issue("set_paused",{"paused":true}).get("ok",false):finish();return
	var fid:String=build("U04-E2",129,false)
	if fid=="":finish();return
	var role:String=str(catalog.campaign.facilities["U04-E2"].roles[0])
	check(role=="doctor" and session.sim.snapshot().facilities[fid].staff_ids.is_empty(),"real E2 treatment device has its catalog doctor vacancy",{"role":role,"facility_id":fid})
	var loop:Dictionary=Opening.preview(session.sim.snapshot(),catalog)
	check(loop.referral_ready and not loop.treatment_ready and loop.next_requirement.code=="","optional treatment vacancy does not rewrite referral-ready admission requirement",loop)
	expect_staff("paused_unstaffed_treatment",fid,role,"hire")
	if not issue("set_paused",{"paused":false}).get("ok",false):finish();return
	expect_staff("running_unstaffed_treatment",fid,role,"hire")
	if not issue("set_paused",{"paused":true}).get("ok",false):finish();return
	var flow=StaffingFlow.new();flow.initialize(session)
	if not check(flow.open(fid),"existing focused staffing route opens exact treatment facility"):finish();return
	var before_flow:Dictionary=session.sim.snapshot()
	var offered:Dictionary=flow.view({},true)
	check(offered.get("role","")==role and offered.get("mode","")=="hire" and offered.get("can_fill",false),"real StaffFlow proves this missing doctor can be hired and assigned through backend validation",offered)
	check(session.sim.snapshot()==before_flow,"staffing quote neither hires nor spends nor changes clinical state")
	var hired:Dictionary=issue("hire",{"role":role})
	if not hired.get("ok",false):flow.close();finish();return
	var sid:String=str(hired.data.staff_id)
	expect_staff("paused_existing_doctor",fid,role,"assign")
	var available:Dictionary=flow.view({},true)
	var has_candidate:bool=false
	for candidate:Dictionary in available.get("candidates",[]):
		if candidate.id==sid:has_candidate=true
	check(available.get("mode","")=="existing" and available.get("can_fill",false) and has_candidate,"real idle command-hired doctor is an eligible exact-route candidate",available)
	var before_assign:Dictionary=session.sim.snapshot()
	flow.request_fill("existing",sid)
	for _n:int in range(5):await process_frame
	var after:Dictionary=session.sim.snapshot()
	check(after.staff[sid].facility_id==fid and sid in after.facilities[fid].staff_ids,"focused flow assigns the actual already-hired doctor through public command")
	check(after.cash==before_assign.cash and after.staff.size()==before_assign.staff.size(),"existing-doctor flow neither recruits twice nor charges another hire")
	check(after.tick==before_assign.tick,"focused staffing does not skip real time while hospital is paused")
	check(flow.view({},true).get("complete",false),"focused flow closes the actual treatment vacancy after assignment")
	var complete:Dictionary=guide("staffed_treatment")
	check(not (complete.get("focus",{}).get("action","")=="staff" and complete.get("focus",{}).get("facility_id","")==fid),"filled treatment device no longer generates a stale staffing instruction",complete)
	check(SnapshotValidator.validate(after,catalog)=="","final public-command hospital remains strictly save-valid",SnapshotValidator.validate(after,catalog))
	flow.close();finish()

func finish()->void:
	if paths.write_report({"passed":passed,"failed":failed,"checks":checks,"notes":notes,"scope":"Unmodified formal GameSession and actual catalog; only public construction, hire, assign, delivery, pause and intake commands. Bounded ordinary Simulation ticks wait for the real delivery; no hospital/stock/patient/clock field edits or checkpoint import. Guide and actual StaffingFlow integration, not a rendered Main touch or human fun acceptance."})!=OK:printerr("TREATMENT STAFF GUIDE REPORT WRITE ERROR");quit(2);return
	print("TREATMENT STAFF GUIDE RESULT: passed=%d failed=%d"%[passed,failed]);quit(1 if failed else 0)
