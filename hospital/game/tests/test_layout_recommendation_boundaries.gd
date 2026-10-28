extends SceneTree

const Paths=preload("res://tests/support/onboarding_test_paths.gd")
const Suggest=preload("res://input/campaign_build_recommendation.gd")
var paths:Variant
var catalog:ContentCatalog
var passed:int=0
var failed:int=0
var checks:Array=[]
var observations:Dictionary={}

func _initialize()->void:
	var output:String=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	var reservation:Dictionary=Paths.reserve(output,"layout-recommendation-boundaries")
	if not reservation.get("ok",false):
		printerr("RECOMMENDATION BOUNDARY PATH ERROR");quit(2);return
	paths=reservation.paths
	_run.call_deferred()

func check(ok:bool,label:String,detail:Variant=null)->bool:
	checks.append({"ok":ok,"check":label,"detail":detail})
	if ok:passed+=1
	else:failed+=1
	print(("RECOMMENDATION BOUNDARY PASS: " if ok else "RECOMMENDATION BOUNDARY FAIL: ")+label)
	return ok

func control(session:GameSession)->Variant:
	var c:Variant=CampaignBuildController.new();c.initialize(session)
	check(c.begin_build("U04-E1"),"normal selected first-exam draft opens")
	return c

func unchanged(session:GameSession,before:Dictionary,label:String)->void:
	check(session.sim.snapshot()==before,label)

func _run()->void:
	var loaded:Dictionary=ContentCatalog.load_checked("res://content")
	if not check(loaded.get("ok",false),"real catalog loads"):finish();return
	catalog=loaded.catalog
	var session:=GameSession.new(catalog,paths.fixture("boundaries"))
	if not check(session.start_level("long_01").get("ok",false),"real public formal hospital"):finish();return
	var pristine:Dictionary=session.sim.snapshot()
	var failures:Array=[]
	var seen:int=0
	for kind:String in catalog.campaign.facilities:
		var size:Dictionary=Suggest.dimensions(kind)
		var local:Dictionary=size.duplicate(true)
		if size.is_empty():failures.append({"kind":kind,"reason":"missing_dimensions"});continue
		local.width=999
		if int(Suggest.dimensions(kind).width)==999:failures.append({"kind":kind,"reason":"mutable_metadata_cache"})
		var layout:Dictionary={"width":int(size.width),"height":int(size.height),"doors":[],"windows":[],"facilities":[]}
		var value:Dictionary=Suggest.furnish(pristine,kind,25,layout)
		if not value.get("ok",false):failures.append({"kind":kind,"reason":value.get("code","")})
		elif not FacilityLayout.preview(pristine,value.proposal).get("ok",false):failures.append({"kind":kind,"reason":"invalid_full_plan"})
		seen+=1
	check(seen==catalog.campaign.facilities.size(),"every actual catalog facility supplies a recommended footprint",seen)
	check(failures.is_empty(),"all catalog templates return independently validated complete layouts and isolated metadata copies",failures)
	unchanged(session,pristine,"all catalog recommendations do not unlock build or change hospital state")
	observations.catalog_templates=seen
	var c:Variant=control(session)
	c.draft.set_bounds(356,406)
	var record:Dictionary=c.draft.capture_state()
	check(not c.apply_recommended_size(),"recommended-size action refuses to shift an edge-selected room elsewhere")
	check(c.draft.capture_state()==record and c.draft.bounds_issue!="","edge rejection retains selected room and explains it")
	c.cancel();c=control(session);c.draft.set_bounds(169,219)
	record=c.draft.capture_state()
	check(not c.apply_recommended_size(),"recommended size cannot replace a corridor selection with an unrelated location")
	check(c.draft.capture_state()==record and c.draft.bounds_issue!="","corridor rejection preserves exact proposed bounds")
	c.cancel();c=control(session);c.draft.set_bounds(25,100)
	c.draft.layout.doors=[{"side":"south","offset":3},{"side":"east","offset":3}]
	c.draft.layout.windows=[{"side":"north","offset":1}]
	record=c.draft.capture_state()
	check(not c.apply_recommended_size() and c.draft.capture_state()==record,"recommended-size action cannot erase previously chosen multiple openings")
	var custom_doors:Array=c.draft.layout.doors.duplicate(true)
	var custom_windows:Array=c.draft.layout.windows.duplicate(true)
	check(c.apply_recommended_layout(),"multiple player entrances remain compatible with recommended device placement")
	check(c.draft.layout.doors==custom_doors and c.draft.layout.windows==custom_windows,"all player doors and windows are preserved exactly")
	check(c.view().preview.get("ok",false),"multi-entrance recommendation keeps actual occupied workplace routes")
	c.cancel();c=control(session);c.draft.set_bounds(25,100)
	c.draft.layout.windows=[{"side":"south","offset":3}]
	custom_windows=c.draft.layout.windows.duplicate(true)
	check(c.apply_recommended_layout(),"existing window at canonical door leads to another legal entrance")
	check(c.draft.layout.windows==custom_windows and c.draft.layout.doors[0] not in custom_windows,"window is never silently converted into a door")
	c.cancel();c=control(session)
	c.initialize(session,null,func(_point:Vector2)->bool:return false)
	var down:=InputEventScreenTouch.new();down.index=0;down.pressed=true;down.position=Vector2(500,200)
	c.feed(down)
	record=c.draft.capture_state()
	check(not c.apply_recommended_size() and c.draft.capture_state()==record,"mechanical held world pointer cannot trigger recommendation through a second action")
	c.cancel();c=control(session)
	check(c.apply_recommended_size() and c.apply_recommended_layout(),"one normal draft still reaches explicit final review")
	var quote:int=int(c.view().quote)
	var result:Dictionary=c.confirm()
	check(result.get("ok",false),"normal public confirmation commits suggested room once")
	var bought:Dictionary=session.sim.snapshot()
	check(int(pristine.cash)-int(bought.cash)==quote,"normal quoted cost is paid exactly once")
	check(not c.confirm().get("ok",false) and session.sim.snapshot()==bought,"second confirmation cannot purchase again")
	var rid:String=str(bought.rooms.keys()[0])
	check(c.begin_edit(rid),"normal edit mode opens purchased room")
	record=c.draft.capture_state()
	check(not c.apply_recommended_size() and not c.apply_recommended_layout() and c.draft.capture_state()==record,"edit recommendations cannot overwrite an owned room")
	c.cancel()
	check(c.begin_install("U04-E2",rid),"normal same-unit installation remains available")
	record=c.draft.capture_state()
	check(not c.apply_recommended_size() and not c.apply_recommended_layout() and c.draft.capture_state()==record,"install recommendations cannot overwrite existing apparatus")
	c.cancel();c=control(session)
	check(session.start_level("long_01").get("ok",false),"normal public session can replace hospital")
	var replacement:Dictionary=session.sim.snapshot()
	check(not c.apply_recommended_size() and not c.apply_recommended_layout(),"old controller cannot recommend into a replacement hospital")
	unchanged(session,replacement,"stale recommendation leaves replacement hospital untouched")
	check(SnapshotValidator.validate(replacement,catalog)=="","final new hospital still strictly validates")
	finish()

func finish()->void:
	if paths.write_report({"passed":passed,"failed":failed,"checks":checks,"observations":observations,"scope":"Public new/edit/install/session replacement, actual paid confirmation and all metadata-only geometry templates. World-pointer check is a mechanical controller fixture. No player-time, phone or full case acceptance."})!=OK:
		printerr("RECOMMENDATION BOUNDARY REPORT ERROR");quit(2);return
	print("RECOMMENDATION BOUNDARY RESULT: passed=%d failed=%d"%[passed,failed])
	quit(1 if failed else 0)
