extends SceneTree

# Prepared formal hospital, real commands and deterministic public simulation
# ticks. This isolates information policy; it is not real-time player evidence.
const ReviewPaths=preload("res://tests/support/gameplay_review_paths.gd")
var test_paths:Variant
var output:String=""
var passed:int=0
var failed:int=0
var checks:Array=[]
var notes:Dictionary={}
var session:GameSession
var panel:CampaignHospitalPanel
var card:CampaignPatientCard

func _initialize()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=").replace("\\","/")
	var reservation:Dictionary=ReviewPaths.reserve(output,"player-information")
	if not reservation.get("ok",false):
		printerr("GAMEPLAY REVIEW PATH ERROR: "+str(reservation.get("code","unknown")));quit(2);return
	test_paths=reservation.paths;output=str(test_paths.output_path)
	_run.call_deferred()

func check(ok:bool,label:String,detail:Variant=null)->void:
	checks.append({"ok":ok,"check":label,"detail":detail})
	if ok:passed+=1
	else:failed+=1
	print(("PLAYER INFO PASS: " if ok else "PLAYER INFO FAIL: ")+label+(" "+str(detail) if detail!=null else ""))

func issue(kind:String,payload:Dictionary)->Dictionary:
	var result:Dictionary=session.issue(kind,payload)
	check(result.get("ok",false),"real fixture command "+kind,result.get("code",""))
	return result

func build(kind:String,cell:int=-1)->String:
	var definition:Dictionary=session.catalog.campaign.facilities[kind]
	var layout:Dictionary=FacilityLayout.default_layout(str(definition.unit_id),kind,0)
	var origin:int=cell
	if origin<0:
		for candidate:int in range(GridService.WIDTH*GridService.HEIGHT):
			var proposal:Dictionary={"id":"info_probe_preview","kind":"campaign_department","ruleset":CampaignContent.RULESET,"unit_id":definition.unit_id,"origin_cell":candidate,"rotation":0,"layout":layout,"width":layout.width,"height":layout.height,"status":"open"}
			if FacilityLayout.preview(session.sim._state,proposal).get("ok",false):origin=candidate;break
	if origin<0:check(false,"geometry can place "+kind);return ""
	var result:Dictionary=issue("build_department",{"unit_id":definition.unit_id,"origin_cell":origin,"layout":layout})
	if not result.get("ok",false):return ""
	var fid:String=str(result.data.facility_ids[0])
	for role:String in definition.roles:
		var hired:Dictionary=issue("hire",{"role":role})
		if not hired.get("ok",false):return ""
		if not issue("assign",{"staff_id":hired.data.staff_id,"facility_id":fid}).get("ok",false):return ""
	return fid

func text_of(node:Node)->String:
	var text:String=""
	if node is Label or node is Button:text+=str(node.text)+"\n"
	for child:Node in node.get_children():text+=text_of(child)
	return text

func _run()->void:
	root.size=Vector2i(932,430)
	var loaded:Dictionary=ContentCatalog.load_checked("res://content")
	check(loaded.get("ok",false),"real content loads")
	if not loaded.get("ok",false):finish();return
	var save_root:String=test_paths.fixture("hospital")
	if save_root=="":printerr("GAMEPLAY REVIEW PATH ERROR: fixture_create_failed");quit(2);return
	session=GameSession.new(loaded.catalog,save_root)
	if not issue_start():finish();return
	for row:Array in [["U04-E1",25],["O01",33],["O15",40],["O05",125]]:
		if build(str(row[0]),int(row[1]))=="":finish();return
	var delivery:Dictionary=issue("run_operation",{"facility_kind":"O15"})
	if not delivery.get("ok",false):finish();return
	issue("set_paused",{"paused":false})
	for _n:int in range(1200):
		if session.sim.snapshot().work_orders[delivery.data.work_order_id].status=="done":break
		session.sim.advance_ticks(1)
	check(session.sim.snapshot().work_orders[delivery.data.work_order_id].status=="done","real opening delivery completed")
	var admission:Dictionary=issue("admit_routine",{"case_id":"U04-C2"})
	if not admission.get("ok",false):finish();return
	var pid:String=str(admission.data.patient_ids[0])
	issue("set_paused",{"paused":true})
	var before:Dictionary=session.sim.snapshot()
	var confidence:int=int(CampaignClinicalDecisions.preview(before,session.catalog,pid).get("confidence",-1))
	var disease:String=str(session.catalog.campaign.diseases[before.patients[pid].disease_id].name)
	check(confidence<0,"real newly admitted patient has not completed first diagnosis",confidence)
	panel=CampaignHospitalPanel.new();root.add_child(panel);panel.initialize(session)
	panel.configure(Rect2(59,0,814,409));panel.show_section("patients")
	card=CampaignPatientCard.new();root.add_child(card);card.initialize(session)
	card.configure(Rect2(59,90,814,224))
	check(card.show_patient(pid),"actual patient card opens newly admitted patient")
	for _n:int in range(4):await process_frame
	check(not text_of(card).contains(disease),"patient card withholds disease before first diagnosis")
	check(not text_of(panel).contains(disease),"all-patients list also withholds disease before first diagnosis",{"disease":disease,"list_text":text_of(panel)})
	check(session.sim.snapshot()==before,"reading either UI leaves real clinical state unchanged")
	issue("set_paused",{"paused":false})
	for _n:int in range(1800):
		if CampaignClinicalDecisions.preview(session.sim.snapshot(),session.catalog,pid).get("pending",false):break
		session.sim.advance_ticks(1)
	issue("set_paused",{"paused":true})
	var examined:Dictionary=session.sim.snapshot()
	check(int(CampaignClinicalDecisions.preview(examined,session.catalog,pid).get("confidence",-1))>=0,"real first examination supplies diagnosis evidence")
	panel.show_section("patients");card.present(examined)
	check(text_of(panel).contains(disease),"patient list reveals suspected disease after real first examination")
	check(text_of(card).contains(disease),"patient card reveals the same evidence-backed suspected disease")
	check(session.sim.snapshot()==examined,"post-exam disclosure only reads the actual model")
	card.close();panel.hide()
	if build("U04-E2")=="":finish();return
	issue("set_paused",{"paused":false})
	for _n:int in range(3000):
		var snapshot:Dictionary=session.sim.snapshot()
		if snapshot.patients[pid].phase=="left":break
		var decision:Dictionary=CampaignClinicalDecisions.preview(snapshot,session.catalog,pid)
		if decision.get("pending",false):
			var action:String="continue_exam" if int(decision.confidence)<80 and int(decision.completed_exams)<1 else "cautious_treat"
			if decision.get("terms",{}).get(action,{}).get("missing",[]).is_empty():issue("clinical_decision",{"patient_id":pid,"action":action,"expected_revision":int(decision.revision)})
		session.sim.advance_ticks(1)
	var cured:Dictionary=session.sim.snapshot()
	check(cured.patients[pid].phase=="left" and cured.patients[pid].outcome=="completed","first real patient has completed diagnosis treatment and exit")
	check(cured.campaign.clinical_policy=="manual","player strategy was not silently changed after first cure")
	notes.first_cure_guide=CampaignOpeningGuide.current(cured,session.catalog)
	notes.first_cure_policy=cured.campaign.clinical_policy
	notes.patient_card_control_keys=card.controls.keys()
	notes.existing_strategy_entry="CampaignHospitalPanel cases page, _clinical_policy_controls; list and card entry observations recorded separately"
	notes.patient_list_has_policy_entry=panel.controls.has("clinical_policy_entry")
	notes.patient_card_has_policy_entry=card.controls.has("clinical_policy_entry")
	check(SnapshotValidator.validate(cured,session.catalog)=="","mechanical first-cure fixture remains strictly save-valid")
	_test_legacy_list()
	finish()


func _test_legacy_list()->void:
	card.free();card=null
	panel.free();panel=null
	var catalog:ContentCatalog=session.catalog
	var legacy_root:String=test_paths.fixture("legacy")
	if legacy_root=="":printerr("GAMEPLAY REVIEW PATH ERROR: legacy_fixture_create_failed");quit(2);return
	session=GameSession.new(catalog,legacy_root)
	check(session.start_level("career_01").get("ok",false),"legacy career factory remains available")
	for row:Array in [["U01-E1",25],["O01",33],["O15",40]]:
		if build(str(row[0]),int(row[1]))=="":return
	var delivery:Dictionary=issue("run_operation",{"facility_kind":"O15"})
	if not delivery.get("ok",false):return
	issue("set_paused",{"paused":false})
	for _n:int in range(1200):
		if session.sim.snapshot().work_orders[delivery.data.work_order_id].status=="done":break
		session.sim.advance_ticks(1)
	issue("set_paused",{"paused":true})
	var admission:Dictionary=issue("accept_case",{"case_id":"U01-C1"})
	if not admission.get("ok",false):return
	var snapshot:Dictionary=session.sim.snapshot()
	check(not CampaignClinicalDecisions.enabled(snapshot),"real legacy hospital has no new diagnosis-information policy")
	var ids:Array=snapshot.patients.keys()
	if ids.is_empty():check(false,"legacy public admission made actual patient");return
	var disease:String=str(catalog.campaign.diseases[snapshot.patients[ids[0]].disease_id].name)
	panel=CampaignHospitalPanel.new();root.add_child(panel);panel.initialize(session)
	panel.configure(Rect2(59,0,814,409));panel.show_section("patients")
	check(text_of(panel).contains(disease),"legacy patient list retains its original known-disease label")
	check(not panel.controls.has("clinical_policy_entry"),"legacy patient list has no unsupported new-policy entry")
	check(session.sim.snapshot()==snapshot,"legacy list rendering does not opt in or rewrite its hospital")
	check(SnapshotValidator.validate(snapshot,catalog)=="","real legacy fixture remains strictly save-valid")

func issue_start()->bool:
	var started:Dictionary=session.start_level("long_01")
	check(started.get("ok",false),"formal factory via public start")
	return bool(started.get("ok",false))

func finish()->void:
	if card!=null:card.free();card=null
	if panel!=null:panel.free();panel=null
	if test_paths.write_report({"passed":passed,"failed":failed,"checks":checks,"notes":notes,"scope":"Prepared real formal hospital, public commands and public deterministic ticks; UI information audit, not human/phone play or elapsed-time acceptance."},"  ")!=OK:
		printerr("GAMEPLAY REVIEW PATH ERROR: report_write_failed");quit(2);return
	print("PLAYER INFO RESULT: passed=%d failed=%d"%[passed,failed])
	quit(1 if failed>0 else 0)
