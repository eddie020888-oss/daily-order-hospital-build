extends SceneTree

# Catches dropped level-restriction forwarding and a search that aborts at the
# first reserved candidate. Both levels are explicitly authored factory fixtures,
# not claims of player progression. A cash=0 dictionary below is detached and
# labelled synthetic; it is never installed into the live session or saved.
const Paths=preload("res://tests/support/onboarding_test_paths.gd")
const Suggest=preload("res://input/campaign_build_recommendation.gd")
var paths:Variant
var passed:int=0
var failed:int=0
var checks:Array=[]
var observations:Dictionary={}

func _initialize()->void:
	var requested:String=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):requested=arg.trim_prefix("--output=")
	var reservation:Dictionary=Paths.reserve(requested,"recommendation-reserved-boundaries")
	if not reservation.get("ok",false):
		printerr("RESERVED BOUNDARY PATH ERROR");quit(2);return
	paths=reservation.paths
	_run.call_deferred()

func check(ok:bool,label:String,detail:Variant=null)->bool:
	checks.append({"ok":ok,"check":label,"detail":detail})
	if ok:passed+=1
	else:failed+=1
	print(("RESERVED BOUNDARY PASS: " if ok else "RESERVED BOUNDARY FAIL: ")+label)
	return ok

func detached_build(snapshot:Dictionary,catalog:ContentCatalog,proposal:Dictionary,id:String)->Dictionary:
	var state:=ClinicState.new();state.data=snapshot.duplicate(true)
	var result:Dictionary=CampaignCommands.apply(state,catalog,{"id":id,"type":"build_department","payload":proposal.duplicate(true)})
	return {"result":result,"after":state.to_data()}

func _run()->void:
	var loaded:Dictionary=ContentCatalog.load_checked("res://content")
	if not check(loaded.get("ok",false),"real catalog loads"):finish();return
	var catalog:ContentCatalog=loaded.catalog
	var fresh:ClinicState=LongCampaignState.create_formal("long_02",catalog)
	if not check(fresh!=null,"actual formal long02 map fixture creates"):finish();return
	var session:=GameSession.new(catalog,paths.fixture("reserved-boundaries-long02"))
	session.restart(fresh)
	var before:Dictionary=session.sim.snapshot()
	var reserved:Array=session.level_data().get("build_restrictions",{}).get("reserved_cells",[])
	if not check(31 in reserved,"actual restriction includes literal reserved cell31",reserved):finish();return
	check(SnapshotValidator.validate(before,catalog)=="","unchanged actual level2 factory is strict legal")
	var selected:Dictionary=Suggest.room(before,"U04-E1",29,29,reserved)
	check(not selected.get("ok",false) and selected.get("code","")=="reserved_plot","selected origin29 refuses reserved cell31 rather than moving",selected)
	var offered:Dictionary=Suggest.room(before,"U04-E1",-1,29,reserved)
	if not check(offered.get("ok",false),"no selected origin skips reserved preferred room and finds a legal full plan",offered):finish();return
	var geometry:Dictionary=FacilityLayout.preview(before,offered.proposal)
	check(geometry.get("ok",false) and 31 not in geometry.get("data",{}).get("room",{}).get("cells",[]),"independent real preview excludes reserved cell31 from returned footprint",geometry)
	var built:Dictionary=detached_build(before,catalog,offered.proposal,"reserved-search-authority")
	check(built.result.get("ok",false),"authoritative paid build accepts allowed search result in detached authored level2",built.result)
	check(SnapshotValidator.validate(built.after,catalog)=="","detached accepted candidate leaves a strict legal built snapshot")
	check(session.sim.snapshot()==before,"search and detached paid contrast leave real level2 model untouched")
	var c:Variant=CampaignBuildController.new();c.initialize(session)
	if not check(c.begin_build("U04-E1"),"real level2 controller opens normal unpositioned draft"):finish();return
	check(c.draft.origin_cell<0,"explicit size action starts without a selected room origin")
	if not check(c.apply_recommended_size(),"normal controller no-origin size action finds permitted ground"):finish();return
	var suggested_origin:int=c.draft.origin_cell
	check(c.draft.layout.doors.is_empty() and c.draft.layout.windows.is_empty() and c.draft.layout.facilities.is_empty(),"size action produces empty movable bounds without free equipment or openings")
	if not check(c.apply_recommended_layout(),"same allowed bounds accept explicit complete-layout recommendation"):finish();return
	var current:Dictionary=FacilityLayout.preview(before,c.draft.proposal())
	check(current.get("ok",false) and 31 not in current.get("data",{}).get("room",{}).get("cells",[]),"controller complete layout respects current level restriction and real routes",current)
	check(c.draft.origin_cell==suggested_origin and c.draft.step==3,"layout keeps chosen ghost position and stops at explicit construction review")
	check(session.sim.snapshot()==before,"both controller recommendations remain unpaid draft operations")
	var unaffordable:Dictionary=before.duplicate(true);unaffordable.cash=0
	var empty:Dictionary=offered.proposal.layout.duplicate(true);empty.facilities=[]
	var low_cash:Dictionary=Suggest.furnish(unaffordable,"U04-E1",int(offered.proposal.origin_cell),empty,Suggest.MAX_PREVIEWS,reserved)
	if check(low_cash.get("ok",false),"detached synthetic cash0 still permits legal layout preview",low_cash):
		var refusal:Dictionary=detached_build(unaffordable,catalog,low_cash.proposal,"cashless-preview-only")
		check(not refusal.result.get("ok",false) and refusal.result.get("code","")=="insufficient_cash","actual build keeps original cash requirement after preview",refusal.result)
		check(refusal.after==unaffordable,"unaffordable detached build cannot create room or command receipt")
	check(session.sim.snapshot()==before,"synthetic affordability contrast cannot alter live hospital")
	c.cancel()
	var open_fresh:ClinicState=LongCampaignState.create_formal("long_01",catalog)
	if not check(open_fresh!=null,"actual unrestricted long01 fixture creates"):finish();return
	var unrestricted:=GameSession.new(catalog,paths.fixture("reserved-boundaries-long01"));unrestricted.restart(open_fresh)
	var open_before:Dictionary=unrestricted.sim.snapshot()
	check(unrestricted.level_data().get("build_restrictions",{}).get("reserved_cells",[]).is_empty(),"actual level1 has an empty reserved list")
	var legacy:Dictionary=Suggest.room(open_before,"U04-E1",29)
	if check(legacy.get("ok",false),"legacy room signature remains valid with omitted restrictions",legacy):
		check(int(legacy.proposal.origin_cell)==29,"unrestricted caller retains selected origin29")
		var no_devices:Dictionary=legacy.proposal.layout.duplicate(true);no_devices.facilities=[]
		var legacy_layout:Dictionary=Suggest.furnish(open_before,"U04-E1",29,no_devices)
		check(legacy_layout.get("ok",false),"legacy furnish signature remains valid with omitted restrictions",legacy_layout)
		var old_build:Dictionary=detached_build(open_before,catalog,legacy.proposal,"unrestricted-legacy-authority")
		check(old_build.result.get("ok",false),"actual build accepts formerly reserved coordinates on unrestricted level1",old_build.result)
	check(unrestricted.sim.snapshot()==open_before and session.sim.snapshot()==before,"all helpers and detached comparisons leave both real fixture sessions intact")
	observations={"reserved_cells":reserved,"selected_rejection":selected,"searched_origin":offered.proposal.origin_cell,"controller_origin":suggested_origin,"legacy_ok":legacy.get("ok",false)}
	finish()

func finish()->void:
	if paths.write_report({"passed":passed,"failed":failed,"checks":checks,"observations":observations,"scope":"Real authored LongCampaignState.create_formal fixtures long02 and long01, real Controller and public detached CampaignCommands acceptance. Synthetic cash0 dictionary is explicitly detached and never a live or saved game state. No claim of earned progression, full campaign or physical-phone acceptance."})!=OK:
		printerr("RESERVED BOUNDARY REPORT ERROR");quit(2);return
	print("RESERVED BOUNDARY RESULT: passed=%d failed=%d"%[passed,failed]);quit(1 if failed else 0)
