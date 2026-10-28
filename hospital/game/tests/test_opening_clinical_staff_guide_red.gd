extends SceneTree

# Independent pending-patient regression. Fixture setup uses real public
# commands; the existing patient/footer/staffing route uses actual Main touch.
const Paths=preload("res://tests/support/onboarding_test_paths.gd")
const Guide=preload("res://ui/campaign_opening_guide.gd")
var paths:Variant
var session:GameSession
var catalog:ContentCatalog
var host:Variant
var pointer:int=0
var passed:int=0
var failed:int=0
var checks:Array=[]
var notes:Dictionary={}

func _initialize()->void:
	var output:String=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	var reserved:Dictionary=Paths.reserve(output,"opening-clinical-staff-guide")
	if not reserved.get("ok",false):printerr("CLINICAL STAFF GUIDE PATH ERROR: "+str(reserved.get("code","unknown")));quit(2);return
	paths=reserved.paths
	_run.call_deferred()

func check(ok:bool,label:String,detail:Variant=null)->bool:
	checks.append({"ok":ok,"check":label,"detail":detail})
	if ok:passed+=1
	else:failed+=1
	print(("CLINICAL STAFF GUIDE PASS: " if ok else "CLINICAL STAFF GUIDE FAIL: ")+label)
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

func frames(count:int=5)->void:
	for _n:int in range(count):await process_frame

func tap(button:Button)->void:
	if not check(button!=null and button.is_visible_in_tree() and not button.disabled,"actual UI touch target is visible and enabled"):return
	var point:Vector2=button.get_global_rect().get_center()
	check(Rect2(Vector2.ZERO,Vector2(root.size)).has_point(point),"actual touch center stays inside phone-sized viewport",point)
	var down:=InputEventScreenTouch.new();down.index=pointer;down.pressed=true;down.position=point
	Input.parse_input_event(down);await process_frame
	var up:=InputEventScreenTouch.new();up.index=pointer;up.pressed=false;up.position=point
	Input.parse_input_event(up);pointer+=1;await frames()

func current(label:String)->Dictionary:
	var before:Dictionary=session.sim.snapshot()
	var result:Dictionary=Guide.current(before,catalog)
	check(session.sim.snapshot()==before,label+" guide does not mutate real patient or hospital")
	notes[label]=result
	return result

func _run()->void:
	root.size=Vector2i(932,430)
	var loaded:Dictionary=ContentCatalog.load_checked("res://content")
	if not check(loaded.get("ok",false),"actual production content loads"):await finish();return
	catalog=loaded.catalog
	var folder:String=paths.fixture("pending-treatment-profile")
	if not check(folder!="","fresh isolated pending-patient profile reserved"):await finish();return
	session=GameSession.new(catalog,folder)
	if not check(int(session.sim.snapshot().campaign.get("opening_loop_version",0))==1,"unmodified default factory uses formal opening policy"):await finish();return
	if build("U04-E1",25)=="" or build("O01",33)=="" or build("O15",40)=="" or build("O05",125)=="":await finish();return
	var delivery:Dictionary=issue("run_operation",{"facility_kind":"O15"})
	if not delivery.get("ok",false):await finish();return
	if not issue("set_paused",{"paused":false}).get("ok",false):await finish();return
	var validation:String=""
	var waited:int=0
	while waited<1200 and session.sim.snapshot().work_orders[delivery.data.work_order_id].status!="done":
		session.sim.advance_ticks(1);waited+=1
		validation=SnapshotValidator.validate(session.sim.snapshot(),catalog)
		if validation!="":break
	check(validation=="","real delivery ticks remain strictly save-valid",validation)
	if not check(session.sim.snapshot().work_orders[delivery.data.work_order_id].status=="done","real staffed delivery completes before admission",waited):await finish();return
	var admitted:Dictionary=issue("admit_routine",{"case_id":"U04-C2"})
	if not admitted.get("ok",false):await finish();return
	var pid:String=str(admitted.data.patient_ids[0])
	var fid:String=build("U04-E2",129,false)
	if fid=="":await finish();return
	var role:String=str(catalog.campaign.facilities["U04-E2"].roles[0])
	waited=0
	while waited<1800 and not CampaignClinicalDecisions.preview(session.sim.snapshot(),catalog,pid).get("pending",false):
		session.sim.advance_ticks(1);waited+=1
		validation=SnapshotValidator.validate(session.sim.snapshot(),catalog)
		if validation!="":break
	check(validation=="","every real first-exam tick strictly validates",validation)
	if not issue("set_paused",{"paused":true}).get("ok",false):await finish();return
	var before:Dictionary=session.sim.snapshot()
	var decision:Dictionary=CampaignClinicalDecisions.preview(before,catalog,pid)
	if not check(decision.get("pending",false),"real completed first examination creates a pending clinical decision",decision):await finish();return
	check(decision.get("terms",{}).get("cautious_treat",{}).get("missing",[]).has("missing_staff:U04-E2"),"real cautious-treatment terms explicitly identify the built E2 vacancy",decision)
	check(decision.get("terms",{}).get("refer",{}).get("missing",[]).is_empty(),"real referral alternative remains available without changing clinical policy",decision)
	var guide:Dictionary=current("pending_missing_doctor")
	var focus:Dictionary=guide.get("focus",{})
	check(guide.get("id","")=="clinical:"+pid and focus.get("patient_id","")==pid and int(focus.get("expected_revision",-1))==int(decision.revision),"staff repair stays inside the exact pending patient's clinical context and revision",guide)
	check(str(guide.get("text","")).contains(str(int(decision.confidence))),"clinical repair keeps the actual confidence evidence in its text",guide)
	check(focus.get("action","")=="staff" and focus.get("facility_kind","")=="U04-E2" and focus.get("facility_id","")==fid and focus.get("role","")==role and guide.get("button","")=="安排诊疗岗位","clinical guide directly exposes the exact real treatment staffing repair",guide)
	check(session.sim.snapshot()==before,"clinical repair guidance neither chooses an option nor hires automatically")
	if not issue("close_facility",{"facility_id":fid}).get("ok",false):await finish();return
	var closed_decision:Dictionary=CampaignClinicalDecisions.preview(session.sim.snapshot(),catalog,pid)
	check(closed_decision.get("terms",{}).get("cautious_treat",{}).get("missing",[]).has("missing_facility:U04-E2"),"genuinely closed device reports facility availability rather than a staffing promise")
	var closed:Dictionary=current("closed_treatment_pending")
	check(closed.get("id","")=="clinical:"+pid and closed.get("focus",{}).get("action","")!="staff","closed device does not trigger the open-device staffing shortcut",closed)
	if not issue("reopen_facility",{"facility_id":fid}).get("ok",false):await finish();return
	# The paused, command-saved hospital is now attached to the actual Main.
	# Main's normal open_saved/GUI routing is used; the save is not patched.
	host=load("res://main.gd").new();host.session=session;root.add_child(host)
	await frames()
	host.hud.configure_display(Vector2(932,430),Vector2(932,430),160,Rect2(59,0,814,409))
	host.hud.flow.close();session.dismiss_notice();host.hud.present();await frames()
	before=session.sim.snapshot()
	check(before.paused and CampaignClinicalDecisions.preview(before,catalog,pid).get("pending",false),"actual Main keeps the real pending fixture paused and undecided")
	await tap(host.hud.opening_card.action_button)
	check(host.hud.staffing_card.visible and host.hud.staffing_card.facility_id==fid,"actual clinical guide button opens the compact exact-device staffing route")
	check(session.sim.snapshot()==before,"actual guide navigation alone does not hire spend or decide treatment")
	# Existing alternative path: patient page has always had its own preparation
	# footer. Verify it explicitly instead of calling the omission no-path.
	check(host.hud.show_campaign_patient(pid),"actual patient inspector can still open the pending patient")
	await frames()
	var patient_card:CampaignPatientCard=host.hud.patient_card
	var preparation:Dictionary=patient_card.preparation_focus
	check(patient_card.controls.prepare_treatment.is_visible_in_tree() and not patient_card.controls.prepare_treatment.disabled and preparation.get("action","")=="staff" and preparation.get("facility_id","")==fid and preparation.get("patient_id","")==pid,"original PatientCard footer already identifies the exact pending staffing repair",preparation)
	before=session.sim.snapshot()
	await tap(patient_card.controls.prepare_treatment)
	check(not patient_card.visible and host.hud.staffing_card.visible and host.hud.staffing_card.facility_id==fid,"original PatientCard raw touch routes through actual HUD into compact staffing")
	check(session.sim.snapshot()==before,"original patient-footer navigation does not hire spend or choose a clinical option")
	var staff_card:Variant=host.hud.staffing_card
	var quote:Dictionary=staff_card._view
	check(quote.get("role","")==role and quote.get("mode","")=="hire" and quote.get("can_fill",false),"real StaffFlow clone validation proves the pending patient's missing role can be filled",quote)
	var cost:int=int(catalog.campaign.roles[role].hire_cost)
	await tap(staff_card.controls.hire_assign)
	var after:Dictionary=session.sim.snapshot()
	check(after.staff.size()==before.staff.size()+1 and after.cash==before.cash-cost and after.facilities[fid].staff_ids.size()==1,"one actual compact-card touch hires and assigns one catalog doctor for one real fee")
	var after_decision:Dictionary=CampaignClinicalDecisions.preview(after,catalog,pid)
	check(after_decision.get("pending",false) and int(after_decision.revision)==int(decision.revision) and after.patients[pid].clinical_decision.receipts==before.patients[pid].clinical_decision.receipts,"repair leaves all clinical choices and revision to the player")
	check(not after_decision.get("terms",{}).get("cautious_treat",{}).get("missing",[]).has("missing_staff:U04-E2"),"actual doctor assignment removes the real cautious-treatment staffing blocker")
	check(after.tick==before.tick,"paused UI preparation never skips clinical or business time")
	var repaired:Dictionary=current("pending_after_staff_repair")
	check(repaired.get("id","")=="clinical:"+pid and repaired.get("focus",{}).get("action","")=="clinical","completed repair returns guidance to the patient's original explicit clinical decision",repaired)
	check(SnapshotValidator.validate(after,catalog)=="","final actual public-command hospital remains strictly valid",SnapshotValidator.validate(after,catalog))
	await finish()

func finish()->void:
	if host!=null:host.free();host=null
	await create_timer(.24).timeout
	if paths.write_report({"passed":passed,"failed":failed,"checks":checks,"notes":notes,"scope":"Real formal GameSession/public construction, staff, delivery, admission and pause commands; bounded ordinary ticks earn the first clinical decision. Actual Main raw ScreenTouch verifies both guide navigation and the pre-existing PatientCard preparation footer into compact StaffingCard. No checkpoint import, clinical/fund/stock/time field edits, automatic clinical decision or physical-phone/human-fun claim."})!=OK:printerr("CLINICAL STAFF GUIDE REPORT WRITE ERROR");quit(2);return
	print("CLINICAL STAFF GUIDE RESULT: passed=%d failed=%d"%[passed,failed]);quit(1 if failed else 0)
