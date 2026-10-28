extends SceneTree

# External integration probe. Uses normal formal factory and real controller.
# Recommendation must remain a draft until the original explicit confirmation.
const Paths=preload("res://tests/support/onboarding_test_paths.gd")
var paths:Variant
var catalog:ContentCatalog
var passed:int=0
var failed:int=0
var checks:Array=[]

func _initialize()->void:
	var output:String=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	var reservation:Dictionary=Paths.reserve(output,"layout-recommendation")
	if not reservation.get("ok",false):
		printerr("RECOMMENDATION PATH ERROR");quit(2);return
	paths=reservation.paths
	_run.call_deferred()

func check(ok:bool,label:String,detail:Variant=null)->bool:
	checks.append({"ok":ok,"check":label,"detail":detail})
	if ok:passed+=1
	else:failed+=1
	print(("RECOMMENDATION PASS: " if ok else "RECOMMENDATION FAIL: ")+label)
	return ok

func new_session(tag:String)->GameSession:
	var folder:String=paths.fixture(tag)
	if folder=="":return null
	var session:=GameSession.new(catalog,folder)
	if not check(session.start_level("long_01").get("ok",false),"normal formal public hospital starts"):return null
	return session

func _run()->void:
	var loaded:Dictionary=ContentCatalog.load_checked("res://content")
	if not check(loaded.get("ok",false),"real catalog loads"):finish();return
	catalog=loaded.catalog
	var session:GameSession=new_session("first-exam")
	if session==null:finish();return
	var controller:Variant=CampaignBuildController.new()
	controller.initialize(session)
	check(controller.begin_build("U04-E1"),"actual first examination begins a normal empty draft")
	var before:Dictionary=session.sim.snapshot()
	check(controller.has_method("recommended_dimensions"),"controller exposes metadata-derived recommended dimensions")
	check(controller.has_method("apply_recommended_size"),"controller offers explicit recommended-size draft action")
	check(controller.has_method("apply_recommended_layout"),"controller offers explicit valid recommended-layout draft action")
	if not controller.has_method("recommended_dimensions") or not controller.has_method("apply_recommended_size") or not controller.has_method("apply_recommended_layout"):
		finish();return
	var dimensions:Dictionary=controller.call("recommended_dimensions")
	var canonical:Dictionary=FacilityLayout.default_layout("U04","U04-E1",0)
	check(int(dimensions.get("width",0))==int(canonical.width) and int(dimensions.get("height",0))==int(canonical.height),"suggested first-exam size matches real body and access geometry",dimensions)
	check(bool(controller.call("apply_recommended_size")),"blank draft can receive a recommended movable room size")
	check(controller.draft.origin_cell>=0 and controller.draft.bounds_error(before)=="","recommended room is on actual legal unoccupied hospital floor")
	check(controller.draft.layout.facilities.is_empty() and controller.draft.layout.doors.is_empty(),"size action does not silently install devices or doors")
	check(session.sim.snapshot()==before,"recommended size cannot purchase or change any hospital truth")
	var room_origin:int=int(controller.draft.origin_cell)
	var room_width:int=int(controller.draft.layout.width)
	var room_height:int=int(controller.draft.layout.height)
	check(bool(controller.call("apply_recommended_layout")),"recommend fills this real room with a usable first-exam plan")
	var view:Dictionary=controller.view()
	check(view.preview.get("ok",false),"full recommendation passes actual placement and occupied access validation",view.preview)
	check(int(view.step)==3 and view.get("can_confirm",false),"recommendation reaches final review, not a purchase")
	check(int(view.proposal.origin_cell)==room_origin and int(view.proposal.layout.width)==room_width and int(view.proposal.layout.height)==room_height,"layout recommendation never moves or enlarges selected room")
	check(view.proposal.layout.facilities.size()==1 and view.proposal.layout.facilities[0].kind=="U04-E1" and not view.proposal.layout.doors.is_empty(),"only requested real device and valid entrance are proposed")
	check(session.sim.snapshot()==before,"layout recommendation cannot issue receipts or spend resources")
	var exact_quote:int=int(view.quote)
	var result:Dictionary=controller.confirm()
	check(result.get("ok",false),"original explicit confirm purchases the real recommended room",result)
	var after:Dictionary=session.sim.snapshot()
	check(int(before.cash)-int(after.cash)==exact_quote and after.rooms.size()==1 and after.facilities.size()==1,"normal authoritative quote is charged once for one room and device")
	check(SnapshotValidator.validate(after,catalog)=="","purchased recommendation remains a strict legal save")
	var second:GameSession=new_session("custom-room")
	if second==null:finish();return
	controller=CampaignBuildController.new();controller.initialize(second);controller.begin_build("U04-E1")
	controller.draft.set_bounds(25,100)
	controller.draft.layout.doors=[{"side":"south","offset":3}]
	controller.draft.layout.windows=[{"side":"north","offset":1}]
	var doors:Array=controller.draft.layout.doors.duplicate(true)
	var windows:Array=controller.draft.layout.windows.duplicate(true)
	var custom_before:Dictionary=second.sim.snapshot()
	check(bool(controller.call("apply_recommended_layout")),"recommendation works inside an already drawn room with player openings")
	check(controller.draft.layout.doors==doors and controller.draft.layout.windows==windows,"player door and window choices are preserved exactly")
	check(controller.draft.origin_cell==25 and controller.draft.layout.width==4 and controller.draft.layout.height==4,"player room size and position are preserved exactly")
	check(second.sim.snapshot()==custom_before,"custom recommendation remains presentation-only")
	var captured:Dictionary=controller.draft.capture_state()
	check(not bool(controller.call("apply_recommended_layout")) and controller.draft.capture_state()==captured,"repeat recommendation cannot overwrite an existing device")
	controller.cancel();controller.begin_build("U04-E1");controller.draft.set_bounds(25,75)
	var small_before:Dictionary=controller.draft.capture_state()
	check(not bool(controller.call("apply_recommended_layout")),"too-small room is explained rather than silently enlarged")
	check(controller.draft.capture_state()==small_before,"failed recommendation preserves all small-room content and position")
	controller.cancel()
	check(not bool(controller.call("apply_recommended_size")) and not bool(controller.call("apply_recommended_layout")),"no stale recommendation can mutate a closed build")
	finish()

func finish()->void:
	if paths.write_report({"passed":passed,"failed":failed,"checks":checks,"scope":"Real formal session/controller, metadata sizes, validated draft layout, original paid confirm and exact player-opening preservation. No normal-player timing or phone acceptance."})!=OK:
		printerr("RECOMMENDATION REPORT ERROR");quit(2);return
	print("RECOMMENDATION RESULT: passed=%d failed=%d"%[passed,failed])
	quit(1 if failed else 0)
