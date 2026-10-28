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
	var reservation:Dictionary=FormalPaths.reserve(output,"campaign-scene-edit-regressions")
	if not reservation.get("ok",false):
		printerr("FORMAL TEST PATH ERROR: "+str(reservation.get("code","unknown")));quit(2);return
	test_paths=reservation.paths;output=str(reservation.output)
	_run.call_deferred()

func check(ok:bool,copy:String) -> bool:
	checks.append({"ok":ok,"check":copy})
	if ok:passed+=1
	else:failed+=1
	print(("SCENE EDIT PASS: " if ok else "SCENE EDIT FAIL: ")+copy)
	return ok

func _fixture(height:int,tag:String,window:bool=false) -> Dictionary:
	var fixture_path:String=test_paths.fixture(tag)
	if fixture_path=="":
		printerr("FORMAL TEST PATH ERROR: fixture_create_failed");quit(2);return {}
	var session:=GameSession.new(catalog,fixture_path)
	if not check(session.start_level("long_01").get("ok",false),tag+" opens a real formal hospital"):return {}
	var layout:Dictionary={"width":7,"height":height,"doors":[{"side":"south","offset":6}],"windows":[{"side":"north","offset":6}] if window else [],"facilities":[{"id":"","kind":"U01-E1","x":0,"y":0,"rotation":0}]}
	var built:Dictionary=session.issue("build_department",{"unit_id":"U01","origin_cell":25,"layout":layout})
	if not check(built.get("ok",false),tag+" pays for a genuine seven-wide department"):return {}
	var room_id:String=str(built.data.room_id)
	var controller:=CampaignBuildController.new();controller.initialize(session,null,Callable())
	return {"session":session,"controller":controller,"room_id":room_id,"first_id":str(session.sim.snapshot().rooms[room_id].layout.facilities[0].id)}

func _install_intent() -> void:
	var f:Dictionary=_fixture(3,"seven-by-three-intent")
	if f.is_empty():return
	var c:CampaignBuildController=f.controller
	var before:Dictionary=f.session.sim.snapshot()
	check(c.begin_install("U01-E1",f.room_id),"seven-by-three install enters its local required-device task")
	c.choose_cell(28)
	if not check(c.advance(),"second device is legal before moving the old instance"):c.cancel();return
	c.select_facility(0);c.choose_cell(50)
	check(c.draft.command().type=="edit_department","any move of a preserved instance selects edit_department instead of dropping the move")
	# At three rows, the stronger occupied-work-position rule may reject the
	# final arrangement. Command intent must still preserve the local change.
	var view:Dictionary=c.view()
	if not view.preview.get("ok",false):
		check(not c.confirm().get("ok",false) and f.session.sim.snapshot()==before,"invalid three-row work aisles cannot charge or silently substitute old geometry")
	c.cancel()
	check(f.session.sim.snapshot()==before,"cancelling an install/move keeps real devices receipts and funds unchanged")

func _install_and_move() -> void:
	# Four rows give the moved doctor/patient positions a genuine bypass;
	# this isolates command/preview divergence from a geometrically bad room.
	var f:Dictionary=_fixture(4,"install-plus-existing-move")
	if f.is_empty():return
	var c:CampaignBuildController=f.controller
	var before:Dictionary=f.session.sim.snapshot()
	check(c.begin_install("U01-E1",f.room_id),"larger real room starts scene installation")
	c.choose_cell(28)
	if not check(c.advance(),"new independent device reaches optional support"):c.cancel();return
	c.select_facility(0);c.choose_cell(50)
	var preview:Dictionary=c.view().preview
	if not check(preview.get("ok",false),"moved old device and added new one have valid actual occupied-work paths"):
		print("SCENE EDIT PREVIEW: "+JSON.stringify(preview));c.cancel();return
	var planned:Dictionary=preview.data.room.facility_geometries[f.first_id]
	check(planned.equipment_cells[0]==50,"visible validated preview places preserved old body at cell50")
	check(f.session.sim.snapshot()==before,"preview and all scene edits have no capital side effects")
	var result:Dictionary=c.confirm()
	if not check(result.get("ok",false),"valid install-plus-move confirms through a real public command"):c.cancel();return
	var after:Dictionary=f.session.sim.snapshot()
	check(result.data.command.type=="edit_department","paid install-plus-move dispatches a complete edit_department payload")
	check(after.facilities[f.first_id].equipment_cells[0]==50,"paid existing device matches its cell50 preview rather than reverting to cell25")
	check(after.rooms[f.room_id].layout.facilities[0].id==f.first_id and after.rooms[f.room_id].layout.facilities.size()==2,"full edit preserves first ID and adds exactly one independent instance")
	check(int(before.cash)-int(after.cash)==int(catalog.campaign.facilities["U01-E1"].cost),"moving an old device while adding one charges only the new machine")
	check(LongCampaignValidator.validate(after,catalog)=="","combined public edit retains complete valid capital evidence")
	c.confirm()
	check(f.session.sim.snapshot()==after,"repeated combined confirmation cannot duplicate charge or instance")

func _shrink_openings() -> void:
	var f:Dictionary=_fixture(3,"shrink-openings",true)
	if f.is_empty():return
	var c:CampaignBuildController=f.controller
	var before:Dictionary=f.session.sim.snapshot()
	check(c.begin_edit(f.room_id),"real existing doors and windows enter the scene edit")
	var draft_before:Dictionary=c.draft.capture_state()
	var shrunk:bool=c.adjust_bounds(Vector2i(-1,0))
	if not shrunk:
		check(c.draft.capture_state()==draft_before,"crop protection retains the complete prior room instead of deleting its edge openings")
		check(c.advance() and c.advance() and c.advance(),"a refused crop leaves the original valid draft usable")
	else:
		check(c.advance(),"accepted width change reaches the opening correction task")
		check(not c.confirm().get("ok",false) and f.session.sim.snapshot()==before,"invalid edge openings cannot be paid while awaiting correction")
		c.select_opening_tool("move");c.choose_wall("south",6)
		check(not c.draft.selected_opening.is_empty(),"an accepted crop keeps the old out-of-bounds door selectable for correction")
		c.choose_wall("south",5)
		c.choose_wall("north",6)
		check(not c.draft.selected_opening.is_empty() and str(c.draft.selected_opening.get("group",""))=="windows","an accepted crop keeps its old edge window selectable too")
		c.choose_wall("north",5)
		check(c.advance(),"both moved openings restore a real valid route to the equipment task")
		c.back();c.back()
		check(c.adjust_bounds(Vector2i(1,0)),"back and restore width remains available before any purchase")
		check(c.advance() and c.advance() and c.advance(),"restoring the original size recovers a confirmable local draft")
	c.cancel()
	check(not c.active and f.session.sim.snapshot()==before,"cancel after either crop policy leaves authoritative layout IDs openings and money exact")

func _run() -> void:
	catalog=ContentCatalog.load_checked("res://content").catalog
	_install_intent();_install_and_move();_shrink_openings()
	if test_paths.write_report({"passed":passed,"failed":failed,"checks":checks,"scope":"Focused real-command regression for install preview/commit identity and recoverable crop handling; no model injection or physical-device claim."},"  ")!=OK:
		printerr("FORMAL TEST PATH ERROR: report_write_failed");quit(2);return

	print("SCENE EDIT RESULT: passed=%d failed=%d"%[passed,failed])
	quit(1 if failed else 0)
