extends SceneTree

# Explicit level-2 factory fixture for map-restriction integration. This does
# not claim that a player has progressed through or unlocked level 2. All
# recommendation actions use the real Controller; the paid-command contrast
# executes only against a detached snapshot and never purchases a room.
const Paths=preload("res://tests/support/onboarding_test_paths.gd")
var paths:Variant
var passed:int=0
var failed:int=0
var checks:Array=[]
var observations:Dictionary={}

func _initialize()->void:
	var requested:String=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):requested=arg.trim_prefix("--output=")
	var reservation:Dictionary=Paths.reserve(requested,"recommendation-reserved-plot")
	if not reservation.get("ok",false):
		printerr("RESERVED RECOMMENDATION PATH ERROR");quit(2);return
	paths=reservation.paths
	_run.call_deferred()

func check(ok:bool,label:String,detail:Variant=null)->bool:
	checks.append({"ok":ok,"check":label,"detail":detail})
	if ok:passed+=1
	else:failed+=1
	print(("RESERVED RECOMMENDATION PASS: " if ok else "RESERVED RECOMMENDATION FAIL: ")+label)
	return ok

func _run()->void:
	var loaded:Dictionary=ContentCatalog.load_checked("res://content")
	if not check(loaded.get("ok",false),"real catalog loads"):finish();return
	var catalog:ContentCatalog=loaded.catalog
	var fresh:ClinicState=LongCampaignState.create_formal("long_02",catalog)
	if not check(fresh!=null,"actual formal long_02 factory creates map-constraint fixture"):finish();return
	var session:=GameSession.new(catalog,paths.fixture("long02-reserved-plot"))
	session.restart(fresh)
	var before:Dictionary=session.sim.snapshot()
	var reserved:Array=session.level_data().get("build_restrictions",{}).get("reserved_cells",[])
	check(before.level_id=="long_02" and 31 in reserved,"fixture uses actual current-level catalog restriction cell31",reserved)
	check(SnapshotValidator.validate(before,catalog)=="","unmodified formal factory is a strict legal state")
	var canonical:Dictionary=FacilityLayout.default_layout("U04","U04-E1",0)
	var proposal:Dictionary={"unit_id":"U04","origin_cell":29,"rotation":0,"layout":canonical}
	var geometry:Dictionary=FacilityLayout.preview(before,proposal)
	if not check(geometry.get("ok",false),"selected4x4 room is geometrically valid before level-specific restriction",geometry):finish();return
	check(31 in geometry.data.room.cells,"real room footprint covers reserved cell31",geometry.data.room.cells)
	var quote:int=150+int(canonical.width)*int(canonical.height)*8+int(catalog.campaign.facilities["U04-E1"].cost)
	check(int(before.cash)>=quote,"real authored initial cash suffices; rejection is not insufficient money",{"cash":before.cash,"quote":quote})
	var detached:=ClinicState.new();detached.data=before.duplicate(true)
	var command:Dictionary={"id":"reserved-recommendation-control","type":"build_department","payload":proposal.duplicate(true)}
	var authoritative:Dictionary=CampaignCommands.apply(detached,catalog,command)
	check(not authoritative.get("ok",false) and authoritative.get("code","")=="reserved_plot","detached authoritative build rejects exactly the actual reserved plot",authoritative)
	check(detached.to_data()==before and session.sim.snapshot()==before,"rejected control cannot create receipts or change real resources")
	var c:Variant=CampaignBuildController.new();c.initialize(session)
	if not check(c.begin_build("U04-E1"),"actual controller permits a normal first-exam draft in formal level2"):finish();return
	if not check(c.has_method("apply_recommended_size") and c.has_method("apply_recommended_layout"),"controller exposes both explicit recommendation actions"):finish();return
	c.draft.set_bounds(29,104)
	check(c.draft.origin_cell==29 and c.draft.layout.width==4 and c.draft.layout.height==4 and c.draft.bounds_error(before)=="","player selected legal4x4 geometry including reserved ground")
	var original:Dictionary=c.draft.capture_state()
	var original_step:int=c.draft.step
	var size_ok:bool=c.call("apply_recommended_size")
	check(not size_ok,"recommended size refuses current selected room on reserved plot")
	check(c.draft.capture_state()==original and c.draft.step==original_step,"rejected size preserves player origin, dimensions, openings, selection and step")
	check(c.draft.bounds_issue!="","reserved-size rejection explains why recommendation cannot apply")
	check(session.sim.snapshot()==before,"reserved-size action never changes model or pays")
	c.cancel();c.begin_build("U04-E1");c.draft.set_bounds(29,104)
	original=c.draft.capture_state();original_step=c.draft.step
	var layout_ok:bool=c.call("apply_recommended_layout")
	check(not layout_ok,"recommended layout refuses current room on actual reserved plot")
	check(c.draft.capture_state()==original and c.draft.step==original_step,"rejected layout retains exact draft and cannot jump to final review")
	check(c.draft.bounds_issue!="","reserved-layout rejection explains why recommendation cannot apply")
	check(session.sim.snapshot()==before,"reserved-layout action leaves model, finances and receipts unchanged")
	observations={"reserved_cells":reserved,"origin":29,"geometry":geometry,"authoritative_rejection":authoritative,"size_returned":size_ok,"layout_returned":layout_ok}
	finish()

func finish()->void:
	if paths.write_report({"passed":passed,"failed":failed,"checks":checks,"observations":observations,"scope":"Explicit actual LongCampaignState.create_formal long_02 fixture, genuine reserved31 and authored sufficient cash; detached public-command contrast, real Controller no-charge draft actions. Does not claim player career progression, phone acceptance or full campaign completion."})!=OK:
		printerr("RESERVED RECOMMENDATION REPORT ERROR");quit(2);return
	print("RESERVED RECOMMENDATION RESULT: passed=%d failed=%d"%[passed,failed]);quit(1 if failed else 0)
