extends SceneTree

# Actual Main + raw ScreenTouch/ScreenDrag. No view() call after release may
# refresh away stale UI; inspect the actual existing button and public model.
const OnboardingPaths=preload("res://tests/support/onboarding_test_paths.gd")
const SAFE:=Rect2(59,0,814,409)
var paths:Variant
var host:Variant
var passed:int=0
var failed:int=0
var checks:Array=[]
var notes:Dictionary={}

func _initialize()->void:
	var requested:String=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):requested=arg.trim_prefix("--output=")
	var reservation:Dictionary=OnboardingPaths.reserve(requested,"onboarding-recommendation-after-draw")
	if not reservation.get("ok",false):printerr("DRAW RECOMMEND PATH ERROR");quit(2);return
	paths=reservation.paths
	_run.call_deferred()

func check(ok:bool,label:String,detail:Variant=null)->bool:
	checks.append({"ok":ok,"check":label,"detail":detail})
	if ok:passed+=1
	else:failed+=1
	print(("DRAW RECOMMEND PASS: " if ok else "DRAW RECOMMEND FAIL: ")+label)
	return ok

func frames(count:int=5)->void:
	for _i:int in range(count):await process_frame

func finger(pressed:bool,point:Vector2)->void:
	var e:=InputEventScreenTouch.new();e.index=0;e.pressed=pressed;e.position=point;Input.parse_input_event(e)

func _run()->void:
	root.size=Vector2i(932,430)
	var loaded:Dictionary=ContentCatalog.load_checked("res://content")
	if not check(loaded.get("ok",false),"real content loads"):await finish();return
	host=load("res://main.gd").new();host.session=GameSession.new(loaded.catalog,paths.fixture("manual-draw"))
	root.add_child(host);await frames()
	host.hud.configure_display(Vector2(932,430),Vector2(932,430),160,SAFE)
	host.hud.flow.close();host.session.dismiss_notice()
	if not check(host.hud.begin_campaign_build("build","U04-E1"),"actual Main starts user-drawn clinic"):await finish();return
	await frames()
	var editor:CampaignBuildEditor=host.hud.campaign_build
	var card:CampaignBuildCard=editor.card
	if not check(card.controls.has("recommend_layout"),"actual optional layout action exists"):await finish();return
	var pair:Array=[]
	for y:int in range(1,14):
		for x:int in range(1,20):
			if y<=9 and y+3>=8:continue
			var first:int=y*24+x;var last:int=(y+3)*24+x+3
			var a:Vector2=host.world.camera_rig.camera.unproject_position(HospitalWorld.cell_position(first))
			var b:Vector2=host.world.camera_rig.camera.unproject_position(HospitalWorld.cell_position(last))
			if not SAFE.grow(-4).has_point(a) or not SAFE.grow(-4).has_point(b) or host.hud.hits_gui(a) or host.hud.hits_gui(b):continue
			if host.world.camera_rig.screen_to_cell(a)!=first or host.world.camera_rig.screen_to_cell(b)!=last:continue
			pair=[a,b];break
		if pair.size()==2:break
	if not check(pair.size()==2,"two real exposed cell centers support a legal4x4 room"):await finish();return
	var before:Dictionary=host.session.sim.snapshot()
	finger(true,pair[0]);await process_frame
	var moved:=InputEventScreenDrag.new();moved.index=0;moved.position=pair[1];moved.relative=Vector2(pair[1])-Vector2(pair[0]);Input.parse_input_event(moved)
	await process_frame
	finger(false,pair[1]);await frames()
	check(editor.controller.draft.step==0 and editor.controller.draft.layout.width==4 and editor.controller.draft.layout.height==4,"actual drag/release leaves user's completed4x4 selection")
	check(editor.controller._fingers.is_empty(),"real drawing pointer has fully released")
	notes={"recommend_size_disabled":card.controls.recommend_size.disabled,"recommend_layout_disabled":card.controls.recommend_layout.disabled,"draft":editor.controller.draft.capture_state()}
	check(not card.controls.recommend_layout.disabled,"recommend layout is immediately usable after normal drawing release",notes)
	check(host.session.sim.snapshot()==before,"normal drawing and idle UI do not spend or modify hospital")
	await finish()

func finish()->void:
	if host!=null:host.free();host=null
	await create_timer(.24).timeout
	paths.write_report({"passed":passed,"failed":failed,"checks":checks,"notes":notes,"scope":"Actual Main, valid exposed floor rays and Input.parse_input_event draw/release. No private model commands or clock advancement; not physical-phone/human-fun acceptance."})
	print("DRAW RECOMMEND RESULT: passed=%d failed=%d"%[passed,failed]);quit(1 if failed else 0)
