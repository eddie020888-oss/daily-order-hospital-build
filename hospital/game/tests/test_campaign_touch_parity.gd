extends SceneTree

const FormalPaths=preload("res://tests/support/formal_test_paths.gd")
var test_paths:Variant
## Focused RED/GREEN: real campaign controller, CameraRig and pointer classes.
## Events feed the controller boundary, not Main/GUI emulation or a physical phone.
var output:=""
var passed:=0
var failed:=0
var checks:Array=[]
var events:Array=[]
var metrics:Array=[]
var catalog:ContentCatalog
var world:HospitalWorld
var gui_rect:=Rect2(-10000,-10000,1,1)
var case_name:=""

func _initialize() -> void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=").replace("\\","/")
	var reservation:Dictionary=FormalPaths.reserve(output,"campaign-touch-parity")
	if not reservation.get("ok",false):
		printerr("FORMAL TEST PATH ERROR: "+str(reservation.get("code","unknown")));quit(2);return
	test_paths=reservation.paths;output=str(reservation.output)
	_run.call_deferred()

func check(ok:bool,label:String) -> bool:
	checks.append({"case":case_name,"ok":ok,"check":label})
	if ok:passed+=1
	else:failed+=1
	print(("TOUCH PARITY PASS: " if ok else "TOUCH PARITY FAIL: ")+case_name+": "+label)
	return ok

func _settle() -> void:
	for _i in range(3):await process_frame

func _point(at:Vector3) -> Vector2:
	return world.camera_rig.camera.unproject_position(at)

func _cell(cell:int) -> Vector2:
	return _point(HospitalWorld.cell_position(cell))

func _touch(c:CampaignBuildController,down:bool,point:Vector2,index:int=0) -> void:
	var e:=InputEventScreenTouch.new();e.index=index;e.pressed=down;e.position=point
	events.append({"case":case_name,"type":"ScreenTouch","index":index,"down":down,"position":[point.x,point.y]})
	c.feed(e)

func _drag(c:CampaignBuildController,point:Vector2,relative:Vector2) -> void:
	var e:=InputEventScreenDrag.new();e.index=0;e.position=point;e.relative=relative
	events.append({"case":case_name,"type":"ScreenDrag","index":0,"position":[point.x,point.y],"relative":[relative.x,relative.y]})
	c.feed(e)

func _tap(c:CampaignBuildController,point:Vector2) -> void:
	_touch(c,true,point);await process_frame;_touch(c,false,point);await _settle()

func _fixture(tag:String,step:int=0) -> Dictionary:
	case_name=tag;gui_rect=Rect2(-10000,-10000,1,1)
	var fixture_path:String=test_paths.fixture(tag)
	if fixture_path=="":
		printerr("FORMAL TEST PATH ERROR: fixture_create_failed");quit(2);return {}
	var session:=GameSession.new(catalog,fixture_path)
	if not check(session.start_level("long_01").get("ok",false),"normal public factory starts actual formal hospital"):return {}
	var before:Dictionary=session.sim.snapshot()
	var c:=CampaignBuildController.new()
	c.initialize(session,world,func(point:Vector2)->bool:return gui_rect.has_point(point))
	if not check(c.begin_build("U01-E1"),"actual U01-E1 starts an unpaid local draft"):return {}
	if step>=1:
		c.choose_cell(25);c.choose_cell(79)
		if not check(c.advance(),"manual API setup reaches doors with legal7x3 bounds"):return {}
	if step>=2:
		c.choose_wall("south",6)
		if not check(c.draft.step==1 and c.advance(),"programmatic door choice stays manual then explicitly advances"):return {}
	if step>=3:
		c.choose_cell(25)
		if not check(c.draft.step==2 and c.advance(),"programmatic device choice stays manual then explicitly advances"):return {}
	return {"session":session,"c":c,"before":before}

func _unpaid(f:Dictionary) -> void:
	check(f.session.sim.snapshot()==f.before,"draft gestures never change actual cash receipts rooms or facilities")
	f.c.cancel()

func _jitter(tag:String,before:Vector3,after:Vector3,want:Vector2i) -> void:
	var f:=_fixture(tag)
	if f.is_empty():return
	var c:CampaignBuildController=f.c
	var a:=_cell(54);var b:=_point(before);var d:=_point(after)
	_touch(c,true,a);_drag(c,b,b-a)
	var preview:Dictionary=c.view().proposal.duplicate(true)
	check(Vector2i(preview.layout.width,preview.layout.height)==want,"drag preview has the hand-derived intended dimensions")
	_touch(c,false,d);await _settle()
	var released:Dictionary=c.view().proposal
	metrics.append({"case":tag,"release_delta_pixels":b.distance_to(d),"preview":[preview.layout.width,preview.layout.height],"released":[released.layout.width,released.layout.height]})
	check(released==preview,"tiny border release preserves the exact visible preview")
	_unpaid(f)

func _deliberate_and_move() -> void:
	var f:=_fixture("deliberate-crossing")
	if f.is_empty():return
	var c:CampaignBuildController=f.c
	var a:=_cell(54);var b:=_point(Vector3(10.49,0,5));var d:=_point(Vector3(10.8,0,5))
	_touch(c,true,a);_drag(c,b,b-a);_drag(c,d,d-b);_touch(c,false,d);await _settle()
	check(c.draft.layout.width==6 and c.draft.layout.height==4,"deliberate crossing still adds the requested column")
	_unpaid(f)
	f=_fixture("whole-room-move-jitter")
	if f.is_empty():return
	c=f.c;c.choose_cell(54);c.choose_cell(130)
	a=_cell(104);b=_point(Vector3(9.49,0,4));d=_point(Vector3(9.51,0,4))
	_touch(c,true,a);_drag(c,b,b-a)
	var preview:Dictionary=c.view().proposal.duplicate(true)
	check(preview.origin_cell==55 and preview.layout.width==5 and preview.layout.height==4,"interior drag moves the complete room exactly one column")
	_touch(c,false,d);await _settle()
	check(c.view().proposal==preview,"tiny move-release jitter does not move the whole room one extra column")
	_unpaid(f)

func _draw_abort() -> void:
	for mode:String in ["second_finger","gui_release"]:
		var f:=_fixture("draw-rollback-"+mode)
		if f.is_empty():continue
		var c:CampaignBuildController=f.c
		c.choose_cell(54);c.choose_cell(130)
		var before:Dictionary=c.view().proposal.duplicate(true)
		var a:=_cell(104);var b:=_cell(105)
		_touch(c,true,a);_drag(c,b,b-a)
		if mode=="second_finger":
			_touch(c,true,_cell(106),1);_touch(c,false,b);_touch(c,false,_cell(106),1)
		else:
			gui_rect=Rect2(b-Vector2(4,4),Vector2(8,8));_touch(c,false,b)
		await _settle()
		check(c.view().proposal==before,"interrupted whole-room move restores its complete initial local draft")
		_unpaid(f)

func _wall(c:CampaignBuildController,side:String="south",offset:int=6) -> Vector2:
	var p:=HospitalWorld.cell_position(c.draft.origin_cell)
	var w:int=c.draft.layout.width;var h:int=c.draft.layout.height
	match side:
		"south":p+=Vector3(offset,1.035,h-.5)
		"north":p+=Vector3(offset,1.035,-.5)
		"east":p+=Vector3(w-.5,1.035,offset)
		"west":p+=Vector3(-.5,1.035,offset)
	var screen:=_point(p)
	check(world.camera_rig.screen_to_wall(screen,c.draft.origin_cell,w,h)=={"side":side,"offset":offset},"actual wall ray hits the intended authored wall face")
	return screen

func _auto_next() -> void:
	var f:=_fixture("default-door-auto",1)
	if f.is_empty():return
	var c:CampaignBuildController=f.c
	var p:=_wall(c)
	_touch(c,true,p);await _settle()
	check(c.draft.step==1 and c.draft.layout.doors.is_empty(),"holding the world touch does not place or advance")
	_touch(c,false,p);await _settle()
	check(c.draft.layout.doors==[{"side":"south","offset":6}],"real released wall gesture places exactly the chosen door")
	check(c.draft.step==2,"valid default door release safely advances exactly to required equipment")
	_unpaid(f)
	f=_fixture("required-device-auto",2)
	if f.is_empty():return
	c=f.c;p=_cell(25)
	_touch(c,true,p);await _settle()
	check(c.draft.step==2 and c.draft.layout.facilities.is_empty(),"held equipment touch cannot complete a task")
	_touch(c,false,p);await _settle()
	check(c.draft.layout.facilities.size()==1,"real released floor gesture places exactly one required device")
	check(c.draft.step==3,"valid required-device release advances exactly to optional support")
	await _settle()
	check(c.active and c.draft.layout.facilities.size()==1,"idle frames never auto-purchase or duplicate equipment")
	_unpaid(f)

func _pointer_guards() -> void:
	for mode:String in ["two_fingers","gui_start","gui_end"]:
		var f:=_fixture("no-auto-"+mode,2)
		if f.is_empty():continue
		var c:CampaignBuildController=f.c
		var p:=_cell(25);var blocked:=p+Vector2(45,0)
		var before:Dictionary=c.view().proposal.duplicate(true)
		if mode=="two_fingers":
			_touch(c,true,p);_touch(c,true,_cell(28),1);_touch(c,false,p);_touch(c,false,_cell(28),1)
		elif mode=="gui_start":
			gui_rect=Rect2(blocked-Vector2(4,4),Vector2(8,8))
			_touch(c,true,blocked);_touch(c,false,p)
		else:
			gui_rect=Rect2(blocked-Vector2(4,4),Vector2(8,8))
			_touch(c,true,p);_touch(c,false,blocked)
		await _settle()
		check(c.draft.step==2 and c.view().proposal==before,"two-finger or GUI-owned gesture never places equipment or auto-advances")
		_unpaid(f)

func _stale_guards() -> void:
	for mode:String in ["cancel_new","back_before_callback","new_held_touch"]:
		var f:=_fixture("queued-auto-"+mode,2)
		if f.is_empty():continue
		var c:CampaignBuildController=f.c;var p:=_cell(25)
		_touch(c,true,p);_touch(c,false,p)
		match mode:
			"cancel_new":c.cancel();c.begin_build("U01-E1")
			"back_before_callback":c.back()
			"new_held_touch":_touch(c,true,p)
		await _settle()
		if mode=="cancel_new":
			check(c.draft.step==0 and c.draft.layout.facilities.is_empty(),"old completion cannot advance a replacement draft with a different receipt")
		elif mode=="back_before_callback":
			check(c.draft.step==1,"back invalidates queued completion rather than skipping back out of opening edit")
		else:
			check(c.draft.step==2,"a new held world finger prevents an older deferred auto-next")
			_touch(c,false,p);await _settle()
			check(c.draft.step==3,"latest released valid gesture may then safely finish the task")
		_unpaid(f)

func _opening_edit_guards() -> void:
	var f:=_fixture("return-to-opening-edit",3)
	if f.is_empty():return
	var c:CampaignBuildController=f.c
	c.back();c.back()
	check(c.draft.step==1,"explicit back returns to editing existing openings")
	await _tap(c,_wall(c,"south",5))
	check(c.draft.step==1 and c.draft.layout.doors.size()==2,"returning to door edit permits another entrance without auto-exiting")
	c.select_opening_tool("window")
	# The north6 midpoint is occluded by the nearer east wall from (18,18,18).
	# south4 is visible and distinct from the existing south5/south6 door edges.
	await _tap(c,_wall(c,"south",4))
	check(c.draft.step==1 and c.draft.layout.windows==[{"side":"south","offset":4}],"optional window editing stays manual")
	check(c.advance() and c.draft.step==2,"explicit completion remains available after multiple-opening edits")
	_unpaid(f)

func _run() -> void:
	var loaded:Dictionary=ContentCatalog.load_checked("res://content")
	case_name="setup"
	if not check(loaded.get("ok",false),"actual campaign content loads"):finish();return
	catalog=loaded.catalog;root.size=Vector2i(1280,720)
	world=HospitalWorld.new();root.add_child(world);await process_frame
	await _jitter("column-release",Vector3(10.49,0,5),Vector3(10.51,0,5),Vector2i(5,4))
	await _jitter("row-release",Vector3(10,0,5.49),Vector3(10,0,5.51),Vector2i(5,4))
	await _jitter("diagonal-release",Vector3(10.49,0,5.49),Vector3(10.51,0,5.51),Vector2i(5,4))
	await _deliberate_and_move();await _draw_abort();await _auto_next()
	await _pointer_guards();await _stale_guards();await _opening_edit_guards()
	world.free();finish()

func finish() -> void:
	if test_paths.write_report({"passed":passed,"failed":failed,"checks":checks,"events":events,"metrics":metrics,
		"controller_sha256":FileAccess.get_sha256("res://input/campaign_build_controller.gd"),
		"scope":"Real campaign public factory and controller, actual CameraRig, ScreenTouch/Drag fed at controller boundary; independent hand-derived dimensions. No production/model writes or injected paid state; not Main GUI-emulation ordering, physical-phone or art acceptance.",
		"physical_device_measured":false},"  ")!=OK:
		printerr("FORMAL TEST PATH ERROR: report_write_failed");quit(2);return

	print("TOUCH PARITY RESULT: passed=%d failed=%d"%[passed,failed]);quit(1 if failed else 0)
