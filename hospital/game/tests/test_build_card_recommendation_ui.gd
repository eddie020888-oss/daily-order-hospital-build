extends SceneTree
const OnboardingPaths=preload("res://tests/support/onboarding_test_paths.gd")
var paths:Variant
var host:Variant
var output:String=""
var passed:int=0
var failed:int=0
var checks:Array=[]
func _initialize()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	var reservation:Dictionary=OnboardingPaths.reserve(output,"onboarding-build-card-recommendation-ui")
	if not reservation.get("ok",false):printerr("RECOMMEND UI PATH ERROR");quit(2);return
	paths=reservation.paths
	_run.call_deferred()
func check(ok:bool,label:String)->void:
	checks.append({"ok":ok,"check":label})
	if ok:passed+=1
	else:failed+=1
func frames()->void:
	for _i:int in range(5):await process_frame
func tap(button:Button)->void:
	var point:Vector2=button.get_global_rect().get_center()
	var e:=InputEventScreenTouch.new();e.index=0;e.pressed=true;e.position=point;Input.parse_input_event(e)
	await process_frame
	e=InputEventScreenTouch.new();e.index=0;e.pressed=false;e.position=point;Input.parse_input_event(e)
	await frames()
func _run()->void:
	root.size=Vector2i(932,430)
	var loaded:Dictionary=ContentCatalog.load_checked("res://content")
	host=load("res://main.gd").new()
	host.session=GameSession.new(loaded.catalog,paths.fixture("recommendation-ui-profile"))
	root.add_child(host);await frames()
	host.hud.configure_display(Vector2(932,430),Vector2(932,430),160,Rect2(59,0,814,409))
	host.hud.flow.close();host.session.dismiss_notice()
	check(host.hud.begin_campaign_build("build","U04-E1"),"actual opening construction starts")
	await frames()
	var card:CampaignBuildCard=host.hud.campaign_build.card
	check(card.controls.has("recommend_size"),"actual card exposes optional recommended size")
	check(card.controls.has("recommend_layout"),"actual card exposes optional valid layout")
	if card.controls.has("recommend_size") and card.controls.has("recommend_layout"):
		var before:Dictionary=host.session.sim.snapshot()
		var button:Button=card.controls.recommend_size
		check(button.is_visible_in_tree() and card.get_global_rect().encloses(button.get_global_rect()) and card._scroll.get_global_rect().encloses(button.get_global_rect()) and button.size.y>=48,"whole size action is visible in actual initial phone card")
		await tap(button)
		check(int(host.hud.campaign_build.controller.view().proposal.layout.width)==4,"size touch creates real metadata based4x4 proposal")
		await tap(card.controls.recommend_layout)
		check(host.hud.campaign_build.controller.view().step==3 and host.hud.campaign_build.controller.view().can_confirm,"layout touch reaches valid review through actual Main")
		check(host.session.sim.snapshot()==before,"both recommendation touches preserve full hospital and money")
	host.free();await create_timer(.24).timeout
	if paths.write_report({"passed":passed,"failed":failed,"checks":checks})!=OK:printerr("RECOMMEND UI WRITE ERROR");quit(2);return
	print("RECOMMEND UI RESULT: passed=%d failed=%d"%[passed,failed]);quit(1 if failed else 0)
