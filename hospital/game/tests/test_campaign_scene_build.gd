extends SceneTree

const FormalPaths=preload("res://tests/support/formal_test_paths.gd")
var test_paths:Variant

const MODULES:={"draft":"res://input/campaign_build_draft.gd","controller":"res://input/campaign_build_controller.gd","card":"res://ui/campaign_build_card.gd","editor":"res://ui/campaign_build_editor.gd"}
var passed:=0
var failed:=0
var checks:Array=[]
var output:=""
var catalog:ContentCatalog

func _initialize() -> void:
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):output=argument.trim_prefix("--output=")
	var reservation:Dictionary=FormalPaths.reserve(output,"campaign-scene-build")
	if not reservation.get("ok",false):
		printerr("FORMAL TEST PATH ERROR: "+str(reservation.get("code","unknown")));quit(2);return
	test_paths=reservation.paths;output=str(reservation.output)
	_run.call_deferred()

func check(ok:bool,copy:String) -> void:
	checks.append({"ok":ok,"check":copy})
	if ok:passed+=1
	else:failed+=1
	print(("SCENE BUILD PASS: " if ok else "SCENE BUILD FAIL: ")+copy)

func finish() -> void:
	if test_paths.write_report({"passed":passed,"failed":failed,"checks":checks,"scope":"Public campaign build_department/place_facility/edit_department via local scene draft; authoritative costs, IDs, occupied masks and cancellation. No phase/cash/unlock injection; not physical-device acceptance."},"  ")!=OK:
		printerr("FORMAL TEST PATH ERROR: report_write_failed");quit(2);return

	print("SCENE BUILD RESULT: passed=%d failed=%d"%[passed,failed])
	quit(1 if failed else 0)

func _session(suffix:String) -> GameSession:
	var fixture_path:String=test_paths.fixture(suffix)
	if fixture_path=="":
		printerr("FORMAL TEST PATH ERROR: fixture_create_failed");quit(2);return null
	var session:=GameSession.new(catalog,fixture_path)
	check(session.start_level("long_01").get("ok",false),"normal public factory opens the actual long hospital")
	return session

func _controller(session:GameSession) -> Variant:
	var controller:Variant=load(MODULES.controller).new()
	controller.initialize(session,null,Callable())
	return controller

func _run() -> void:
	var available:=true
	for key:String in MODULES:
		var exists:bool=FileAccess.file_exists(MODULES[key])
		check(exists,"native campaign scene-building module exists: "+key)
		available=available and exists
	if not available:finish();return
	var loaded:Dictionary=ContentCatalog.load_checked("res://content")
	check(loaded.get("ok",false),"real campaign catalog loads")
	if not loaded.get("ok",false):finish();return
	catalog=loaded.catalog
	var session:=_session("commands")
	if session==null:return
	var controller:Variant=_controller(session)
	var pristine:Dictionary=session.sim.snapshot()
	check(controller.begin_build("U01-E1"),"selected real diagnostic facility starts a local campaign draft")
	var initial:Dictionary=controller.view()
	check(controller.active and int(initial.step)==0 and initial.proposal.layout.facilities.is_empty(),"new hospital draft starts with no pre-placed machine")
	check(session.sim.snapshot()==pristine,"opening the draft does not spend or write a capital receipt")
	# A seven-by-three room leaves a second independent workstation and real
	# operating/maintenance aisles. Only real draft gestures and buttons apply it.
	controller.choose_cell(25);controller.choose_cell(79)
	check(controller.advance(),"drawn room bounds advance to real door placement")
	controller.choose_wall("south",6)
	controller.select_opening_tool("window");controller.choose_wall("north",6)
	controller.select_opening_tool("door")
	check(controller.advance(),"chosen real door and optional window advance to equipment")
	controller.choose_cell(25)
	check(controller.advance(),"legal device body and external work positions advance to optional support")
	var ready:Dictionary=controller.view()
	check(ready.preview.get("ok",false),"scene preview uses actual FacilityLayout geometry validation")
	check(session.sim.snapshot()==pristine,"bounds openings and equipment remain an unpaid local draft")
	var built:Dictionary=controller.confirm()
	check(built.get("ok",false),"final scene confirmation submits real build_department")
	if not built.get("ok",false):finish();return
	var after:Dictionary=session.sim.snapshot()
	check(after.rooms.size()==1 and after.facilities.size()==1 and int(pristine.cash)-int(after.cash)==int(built.data.cost),"one real room and machine charge the authoritative quote exactly once")
	var room_id:String=str(built.data.room_id)
	var first_id:String=str(after.rooms[room_id].layout.facilities[0].id)
	check(after.rooms[room_id].layout.doors==[{"side":"south","offset":6}] and after.rooms[room_id].layout.windows==[{"side":"north","offset":6}],"actual chosen doorway and window persist in the paid model")
	controller.confirm()
	check(session.sim.snapshot()==after,"repeated final confirmation cannot double-charge or duplicate the machine")
	check(controller.begin_install("U01-E1",room_id),"existing same-department room supports scene installation")
	controller.choose_cell(28)
	check(controller.advance(),"second independent device has a legal separate operation footprint")
	var installed:Dictionary=controller.confirm()
	check(installed.get("ok",false),"scene installation submits actual place_facility")
	if not installed.get("ok",false):finish();return
	after=session.sim.snapshot()
	var room:Dictionary=after.rooms[room_id]
	check(after.rooms.size()==1 and room.layout.facilities.size()==2 and after.facilities.size()==2,"two devices remain distinct instances inside one unchanged room")
	var second_id:String=str(room.layout.facilities[1].id)
	check(first_id!=second_id and after.facilities[first_id].service_cells!=after.facilities[second_id].service_cells and after.facilities[first_id].staff_cells!=after.facilities[second_id].staff_cells,"same-kind devices own distinct patient and staff positions")
	check(after.cash==int(pristine.cash)-int(built.data.cost)-int(catalog.campaign.facilities["U01-E1"].cost),"second installation charges only its real device cost")
	var before_edit:Dictionary=after
	check(controller.begin_edit(room_id),"existing department opens a local scene edit")
	check(controller.adjust_bounds(Vector2i(1,0)),"anchored existing room can grow through bounds controls")
	check(controller.advance() and controller.advance() and controller.advance(),"edit preserves real existing door and device instances across all stages")
	var edited:Dictionary=controller.confirm()
	check(edited.get("ok",false),"scene edit submits actual edit_department")
	if edited.get("ok",false):
		var now:Dictionary=session.sim.snapshot()
		check(now.rooms[room_id].layout.facilities[0].id==first_id and now.rooms[room_id].layout.facilities[1].id==second_id,"editing area preserves independent instance IDs")
		check(now.cash==int(before_edit.cash)-24,"three added floor cells use real expansion pricing")
		check(LongCampaignValidator.validate(now,catalog)=="","scene-created devices geometry and receipts pass the actual save validator")
	var before_cancel:Dictionary=session.sim.snapshot()
	check(controller.begin_build("U01-E1"),"a further local draft can start")
	controller.choose_cell(100);controller.choose_cell(175)
	controller.cancel()
	check(not controller.active and session.sim.snapshot()==before_cancel,"cancel discards the draft without cash or capital receipt changes")
	controller.begin_install("U01-E1",room_id)
	controller.choose_cell(25)
	var overlap:Dictionary=controller.view()
	check(not overlap.preview.get("ok",false),"second device on an existing body has an invalid real overlap preview")
	var rejected:Dictionary=controller.confirm()
	check(not rejected.get("ok",false) and session.sim.snapshot()==before_cancel,"illegal geometry cannot submit a paid command")
	controller.reset_input()
	check(not controller.active,"external reset removes all campaign construction pointer ownership")
	await _editor_contract(session)
	finish()

func _editor_contract(session:GameSession) -> void:
	root.size=Vector2i(932,430)
	var editor:Variant=load(MODULES.editor).new()
	root.add_child(editor)
	editor.initialize(session,null,Callable())
	editor.configure(Rect2(8,8,916,414))
	check(editor.begin_build("U01-E1"),"self-contained editor delegates the real scene start")
	for _i in range(3):await process_frame
	editor.present(session.sim.snapshot())
	var card:Control=editor.card
	check(card.is_visible_in_tree() and Rect2(Vector2.ZERO,Vector2(932,430)).encloses(card.get_global_rect()),"single-task construction card stays within phone landscape")
	check(editor.hits_gui(card.get_global_rect().get_center()) and not editor.hits_gui(Vector2.ONE),"editor blocks only its actual card and leaves world space available")
	var numeric_form:=false
	for control:Node in editor.find_children("*","SpinBox",true,false):numeric_form=true
	check(not numeric_form,"scene construction requires no x/y/quarter-turn forms")
	var before:Dictionary=session.sim.snapshot()
	editor.cancel()
	check(not editor.active and session.sim.snapshot()==before,"editor cancellation preserves the authoritative hospital")
	editor.free()
