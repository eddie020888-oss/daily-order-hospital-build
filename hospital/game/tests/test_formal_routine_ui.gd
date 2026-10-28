extends SceneTree

const FormalPaths=preload("res://tests/support/formal_test_paths.gd")
var test_paths:Variant

var output := ""
var passed := 0
var failed := 0
var checks: Array=[]

func _initialize()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=").replace("\\","/")
	var reservation:Dictionary=FormalPaths.reserve(output,"formal-routine-ui")
	if not reservation.get("ok",false):
		printerr("FORMAL TEST PATH ERROR: "+str(reservation.get("code","unknown")));quit(2);return
	test_paths=reservation.paths;output=str(reservation.output)
	_run.call_deferred()

func check(ok:bool,label:String)->void:
	checks.append({"ok":ok,"check":label})
	if ok:passed+=1
	else:failed+=1;print("ROUTINE UI FAIL: "+label)

func _run()->void:
	var catalog:ContentCatalog=ContentCatalog.load_checked("res://content").catalog
	var fixture_path:String=test_paths.fixture("hospital")
	if fixture_path=="":
		printerr("FORMAL TEST PATH ERROR: fixture_create_failed");quit(2);return
	var session:=GameSession.new(catalog,fixture_path)
	var panel:=CampaignHospitalPanel.new()
	root.add_child(panel);panel.initialize(session);panel.show_section("cases")
	for _n in range(2):await process_frame
	var before:Dictionary=session.sim.snapshot()
	check(CampaignOpeningLoop.enabled(before),"fixture uses normal new formal hospital")
	check(panel.controls.has("routine_case") and panel.controls.has("admit_routine"),"normal cases UI offers the real opening routine before earned signatures")
	if panel.controls.has("routine_case"):
		var choice:OptionButton=panel.controls.routine_case
		var found:=false
		for n:int in range(choice.item_count):
			if str(choice.get_item_metadata(n))==CampaignOpeningLoop.TEMPLATE_CASE_ID:found=true
		check(found,"UI choices use the same versioned source as manual and automatic admission")
		check(str(choice.get_item_metadata(choice.selected))==CampaignOpeningLoop.TEMPLATE_CASE_ID,"first routine selection is the actual separate diagnostic and therapy case")
		check(panel.controls.admit_routine.disabled,"empty hospital truthfully disables admission for real missing preparation")
	check(not panel.controls.has("clinic_drive_start") or panel.controls.clinic_drive_start.disabled,"unearned opening template cannot bypass its two-patient limit through clinic drive")
	check(session.sim.snapshot()==before,"displaying routine choices never creates people or earned progress")
	panel.free()
	var old_fixture_path:String=test_paths.fixture("legacy-hospital")
	if old_fixture_path=="":
		printerr("FORMAL TEST PATH ERROR: fixture_create_failed");quit(2);return
	var old:=GameSession.new(catalog,old_fixture_path)
	old.restart(ClinicState.create("long_01",catalog))
	var legacy:=CampaignHospitalPanel.new();root.add_child(legacy);legacy.initialize(old);legacy.show_section("cases")
	check(not legacy.controls.has("routine_case"),"old hospital keeps its earned-template UI requirement")
	legacy.free()
	if test_paths.write_report({"passed":passed,"failed":failed,"checks":checks},"  ")!=OK:
		printerr("FORMAL TEST PATH ERROR: report_write_failed");quit(2);return

	print("ROUTINE UI RESULT: passed=%d failed=%d"%[passed,failed])
	quit(1 if failed>0 else 0)
