extends SceneTree

const FormalPaths=preload("res://tests/support/formal_test_paths.gd")
var test_paths:Variant

var output:=""
var passed:=0
var failed:=0
var checks:Array=[]
var catalog:ContentCatalog

func _initialize() -> void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	var reservation:Dictionary=FormalPaths.reserve(output,"campaign-confirm-release")
	if not reservation.get("ok",false):
		printerr("FORMAL TEST PATH ERROR: "+str(reservation.get("code","unknown")));quit(2);return
	test_paths=reservation.paths;output=str(reservation.output)
	_run.call_deferred()

func check(ok:bool,copy:String) -> bool:
	checks.append({"ok":ok,"check":copy})
	if ok:passed+=1
	else:failed+=1
	print(("CONFIRM RELEASE PASS: " if ok else "CONFIRM RELEASE FAIL: ")+copy)
	return ok

func _ready_controller(tag:String) -> Dictionary:
	var fixture_path:String=test_paths.fixture(tag)
	if fixture_path=="":
		printerr("FORMAL TEST PATH ERROR: fixture_create_failed");quit(2);return {}
	var session:=GameSession.new(catalog,fixture_path)
	if not check(session.start_level("long_01").get("ok",false),tag+" has a real isolated formal hospital"):return {}
	var c:=CampaignBuildController.new();c.initialize(session,null,func(point:Vector2)->bool:return point.x<100)
	c.begin_build("U01-E1");c.choose_cell(25);c.choose_cell(75);c.advance();c.choose_wall("south",2);c.advance();c.choose_cell(25);c.advance()
	if not check(c.view().get("can_confirm",false),tag+" reaches a genuine unpaid valid final draft"):return {}
	return {"session":session,"controller":c,"before":session.sim.snapshot()}

func _finger(c:CampaignBuildController,index:int,down:bool,point:Vector2=Vector2(50,50)) -> void:
	var event:=InputEventScreenTouch.new();event.index=index;event.pressed=down;event.position=point;c.feed(event)

func _settle() -> void:
	for _i in range(3):await process_frame

func _run() -> void:
	catalog=ContentCatalog.load_checked("res://content").catalog
	var probe:=CampaignBuildController.new()
	if not check(probe.has_method("request_confirm"),"controller provides a receipt-bound GUI confirmation request which waits for release"):finish();return
	var f:Dictionary=_ready_controller("normal-release")
	if f.is_empty():finish();return
	var c:CampaignBuildController=f.controller
	_finger(c,0,true)
	check(not c.confirm().get("ok",false) and f.session.sim.snapshot()==f.before,"direct confirmation retains the held-pointer safety gate")
	check(c.call("request_confirm"),"GUI pressed before ScreenTouch-up queues an explicit confirmation intent")
	await _settle()
	check(c.active and f.session.sim.snapshot()==f.before,"queued intent cannot spend while its finger is still held")
	check(not c.call("request_confirm"),"duplicate GUI signals cannot queue a second purchase")
	_finger(c,0,false)
	await _settle()
	var after:Dictionary=f.session.sim.snapshot()
	check(not c.active and after.rooms.size()==1 and after.facilities.size()==1 and after.cash<f.before.cash,"release commits exactly one real room and device")
	c.call("request_confirm");c.confirm();await _settle()
	check(f.session.sim.snapshot()==after,"post-success repeated GUI/direct confirmation preserves one receipt and one charge")
	for action:String in ["second_finger","release_outside","back","cancel_and_new"]:
		f=_ready_controller(action)
		if f.is_empty():continue
		c=f.controller
		_finger(c,0,true);check(c.call("request_confirm"),action+" creates a valid pending GUI intent")
		match action:
			"second_finger":_finger(c,1,true);_finger(c,1,false);_finger(c,0,false)
			"release_outside":_finger(c,0,false,Vector2(500,50))
			"back":c.back();_finger(c,0,false)
			"cancel_and_new":c.cancel();c.begin_build("U01-E1");_finger(c,0,false)
		await _settle()
		check(c.active and f.session.sim.snapshot()==f.before,action+" invalidates the queued purchase and leaves real money and receipts untouched")
		if action=="cancel_and_new":check(c.draft.step==0 and c.draft.layout.facilities.is_empty(),"an old deferred callback cannot purchase a replacement draft with a new receipt")
		c.cancel()
	f=_ready_controller("world-owned-touch")
	if not f.is_empty():
		c=f.controller;_finger(c,0,true,Vector2(500,50))
		check(not c.call("request_confirm"),"a world-owned finger cannot borrow a GUI confirmation intent")
		_finger(c,0,false,Vector2(500,50));await _settle()
		check(f.session.sim.snapshot()==f.before,"world release never turns a rejected request into a paid command")
		c.cancel()
	finish()

func finish() -> void:
	if test_paths.write_report({"passed":passed,"failed":failed,"checks":checks,"scope":"Reordered GUI/ScreenTouch-release regression with real commands, held-finger, multi-touch, outside, back/cancel/new-receipt guards. Native event ordering is separately recorded by observer evidence."},"  ")!=OK:
		printerr("FORMAL TEST PATH ERROR: report_write_failed");quit(2);return

	print("CONFIRM RELEASE RESULT: passed=%d failed=%d"%[passed,failed]);quit(1 if failed else 0)
