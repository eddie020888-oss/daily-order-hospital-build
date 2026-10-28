extends SceneTree

const FormalPaths=preload("res://tests/support/formal_test_paths.gd")
const NEW_ROOT:String="E:/CODEX/2026-10-28/建设视角拖动修复"
const SAFE:=Rect2(59,0,814,409)
var paths:Variant
var host:Variant
var output:String=""
var passed:int=0
var failed:int=0
var checks:Array=[]
var captures:Array=[]
var diagnostics:Array=[]

func _initialize()->void:
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):output=argument.trim_prefix("--output=")
	var reserved:Dictionary=_reserve(output)
	if not reserved.get("ok",false):
		printerr("NAVIGATION PATH ERROR: "+str(reserved.get("code","unknown")));quit(2);return
	paths=reserved.paths
	_run.call_deferred()

# This narrowly permits only this task's fresh report directory on Windows.
# The existing helper and its Mac CI gate remain unchanged.
func _reserve(requested:String)->Dictionary:
	if OS.get_name()!="Windows":return FormalPaths.reserve(requested,"campaign-build-navigation")
	var report:String=FormalPaths._canonical(requested)
	if report=="" or not FormalPaths._descendant(report,NEW_ROOT) or report.get_extension()!="json":return {"ok":false,"code":"report_path_rejected"}
	var folder:String=report.get_base_dir()
	if not FormalPaths._descendant(folder,NEW_ROOT) or FileAccess.file_exists(report) or DirAccess.dir_exists_absolute(report) or FileAccess.file_exists(folder) or DirAccess.dir_exists_absolute(folder):return {"ok":false,"code":"report_directory_not_fresh"}
	if not FormalPaths._no_links(folder) or not FormalPaths._fresh_directory(folder) or not FormalPaths._no_links(folder):return {"ok":false,"code":"fresh_directory_or_link_rejected"}
	var reserved:=FormalPaths.new()
	reserved.output_path=report;reserved.run_root=folder;reserved.allowed_root=NEW_ROOT
	return {"ok":true,"paths":reserved}

func check(ok:bool,label:String)->void:
	checks.append({"ok":ok,"check":label})
	if ok:passed+=1
	else:failed+=1
	print(("BUILD NAV PASS: " if ok else "BUILD NAV FAIL: ")+label)

func settle(count:int=4)->void:
	for _i in range(count):await process_frame

func finger(index:int,pressed:bool,point:Vector2)->void:
	var event:=InputEventScreenTouch.new()
	event.index=index;event.pressed=pressed;event.position=point
	Input.parse_input_event(event)

func drag(index:int,from:Vector2,to:Vector2)->void:
	var event:=InputEventScreenDrag.new()
	event.index=index;event.position=to;event.relative=to-from
	Input.parse_input_event(event)

func tap(button:Button)->void:
	var point:Vector2=button.get_global_rect().get_center()
	finger(0,true,point);await process_frame
	finger(0,false,point);await settle()

func _world(point:Vector2)->bool:
	return SAFE.grow(-3).has_point(point) and not host.hud.hits_gui(point) and host.world.camera_rig.screen_to_cell(point)>=0

func _pair()->Array:
	# Real exposed rays, not a fixed coordinate hidden behind the current card.
	for y:int in range(115,290,20):
		for x:int in range(480,730,20):
			var a:=Vector2(x,y)
			var b:=a+Vector2(90,40)
			if _world(a) and _world(b) and _world(a+Vector2(18,8)) and _world(b+Vector2(58,8)):return [a,b]
	return []

func _draw_pair()->Array:
	var candidates:Array=[]
	for y:int in range(100,320,12):
		for x:int in range(450,850,12):
			var point:=Vector2(x,y)
			if _world(point):candidates.append(point)
	for a:Vector2 in candidates:
		var first:int=host.world.camera_rig.screen_to_cell(a)
		for b:Vector2 in candidates:
			var last:int=host.world.camera_rig.screen_to_cell(b)
			var first_row:int=int(first/24);var last_row:int=int(last/24)
			var same_build_band:bool=(first_row>=1 and first_row<=7 and last_row>=1 and last_row<=7) or (first_row>=10 and first_row<=16 and last_row>=10 and last_row<=16)
			if same_build_band and absi(first%24-last%24)>=2 and absi(first_row-last_row)>=2 and a.distance_to(b)>35:return [a,b]
	return []

func _capture(name:String)->void:
	if DisplayServer.get_name()=="headless" or captures.size()>=3:return
	await RenderingServer.frame_post_draw
	var file:String=paths.run_root.path_join(name+".png")
	if FileAccess.file_exists(file) or not FormalPaths._no_links(file):
		check(false,"capture must be a fresh file without links");return
	var error:Error=root.get_texture().get_image().save_png(file)
	check(error==OK,"actual viewport capture saved: "+name)
	if error==OK:captures.append(file)

func _run()->void:
	root.size=Vector2i(932,430)
	var loaded:Dictionary=ContentCatalog.load_checked("res://content")
	check(loaded.get("ok",false),"fixture: actual campaign catalog loads")
	if not loaded.get("ok",false):await finish();return
	var fixture:String=paths.fixture("isolated-hospital")
	if fixture=="":printerr("NAVIGATION PATH ERROR: fixture_create_failed");quit(2);return
	host=load("res://main.gd").new()
	host.session=GameSession.new(loaded.catalog,fixture)
	check(host.session.start_level("long_01").get("ok",false),"fixture: public factory opens isolated real hospital")
	root.add_child(host)
	host.feedback.set_application_active(false)
	await settle()
	host.hud.configure_display(Vector2(932,430),Vector2(932,430),160,SAFE)
	host.hud.flow.close();host.session.dismiss_notice()
	check(host.hud.begin_campaign_build("build","O01",""),"fixture: real HUD opens a stage-zero reception draft")
	await settle(6)
	var editor:Variant=host.hud.campaign_build
	var controller:Variant=editor.controller
	var camera:CameraRig=host.world.camera_rig
	var pair:Array=_pair()
	check(pair.size()==2,"fixture: two actual exposed floor rays avoid GUI and safe-area edges")
	if pair.size()!=2:await finish();return
	await _capture("01-initial")
	var snapshot:Dictionary=host.session.sim.snapshot()
	check(bool(snapshot.get("paused",false)),"fixture: actual new-hospital construction pauses simulation while Main._process remains active")
	var draft:Dictionary=controller.draft.capture_state()
	var target:Vector3=camera.target
	var zoom:float=camera.zoom_size
	var a:Vector2=pair[0];var b:Vector2=pair[1];var move:=Vector2(18,8)
	finger(0,true,a);finger(1,true,b)
	drag(0,a,a+move);drag(1,b,b+move)
	finger(0,false,a+move);finger(1,false,b+move)
	await settle()
	check(camera.target.distance_to(target)>0.05 and is_equal_approx(camera.zoom_size,zoom),"stage0 actual Main touch: same-distance two-finger translation pans without changing zoom")
	check(controller.draft.capture_state()==draft and controller.draft.step==0 and host.session.sim.snapshot()==snapshot and host.touch.get("_fingers").is_empty(),"two-finger release preserves complete draft and model without legacy ownership or confirmation")
	await _capture("02-two-finger-pan")
	# Independent pinch: a genuine spread still zooms while keeping the model read-only.
	pair=_pair()
	if pair.size()==2:
		a=pair[0];b=pair[1];zoom=camera.zoom_size
		finger(0,true,a);finger(1,true,b);drag(1,b,b+Vector2(40,0))
		finger(0,false,a);finger(1,false,b+Vector2(40,0));await settle()
		check(camera.zoom_size<zoom and controller.draft.capture_state()==draft and host.session.sim.snapshot()==snapshot,"two-finger spread still pinches without placing or buying")
	else:check(false,"fixture: exposed pinch rays remain available after pan")
	# Missing new APIs produce assertion RED, never a static call/parse failure.
	var api:bool=controller.has_method("set_navigation_mode") and controller.view().has("navigation_mode")
	var button:Variant=editor.card.controls.get("pan_view")
	check(api and button is Button,"stage0 exposes navigation-mode API, view state and real footer pan_view button")
	if not api or not button is Button:await finish();return
	check(not bool(controller.view().navigation_mode) and button.visible and button.get_global_rect().size.x>=48 and button.get_global_rect().size.y>=48 and SAFE.encloses(button.get_global_rect()),"stage0 defaults to drawing with a reachable safe-area 48-unit view toggle")
	await tap(button)
	pair=_pair()
	if pair.size()!=2:check(false,"fixture: exposed navigation rays remain available");await finish();return
	a=pair[0];b=pair[1];target=camera.target;zoom=camera.zoom_size;draft=controller.draft.capture_state()
	finger(0,true,a);drag(0,a,b);finger(0,false,b);await settle()
	check(bool(controller.view().navigation_mode) and camera.target.distance_to(target)>0.05 and is_equal_approx(camera.zoom_size,zoom) and controller.draft.capture_state()==draft and host.session.sim.snapshot()==snapshot,"real view-toggle touch enables single-finger pan while preserving the entire draft and hospital")
	await _capture("03-single-finger-navigation")
	await tap(button)
	pair=_draw_pair()
	if pair.size()!=2:check(false,"fixture: two exposed real cells span a drawable room");await finish();return
	a=pair[0];b=pair[1];target=camera.target
	finger(0,true,a);drag(0,a,b);finger(0,false,b);await settle()
	check(not bool(controller.view().navigation_mode) and int(controller.draft.layout.width)>=3 and int(controller.draft.layout.height)>=3 and camera.target.is_equal_approx(target) and host.session.sim.snapshot()==snapshot,"real toggle back restores single-finger room drawing without moving camera or charging capital")
	# Begin another unfinished stroke, then add a second finger: original bounds return.
	draft=controller.draft.capture_state();pair=_pair()
	if pair.size()==2:
		a=pair[0];b=pair[1]
		var rollback_probe:Dictionary={"name":"unfinished-stroke-rollback","point_a":str(a),"point_b":str(b),"stroke_end":str(a+Vector2(36,16)),"cell_a":camera.screen_to_cell(a),"cell_stroke_end":camera.screen_to_cell(a+Vector2(36,16)),"before":draft.duplicate(true),"target":str(camera.target),"zoom":camera.zoom_size}
		finger(0,true,a);drag(0,a,a+Vector2(36,16))
		await process_frame # Hold the same finger through one dispatch frame before observing.
		var stroke_changed:bool=controller.draft.capture_state()!=draft
		rollback_probe["stroke_changed"]=stroke_changed
		rollback_probe["after_stroke"]=controller.draft.capture_state().duplicate(true)
		rollback_probe["after_stroke_draw_move"]=controller.get("_draw_move")
		rollback_probe["after_stroke_draw_first"]=controller.get("_draw_first")
		rollback_probe["after_stroke_draw_last"]=controller.get("_draw_last")
		rollback_probe["after_stroke_draw_backup"]=controller.get("_draw_backup").duplicate(true)
		rollback_probe["after_stroke_bounds_issue"]=str(controller.draft.bounds_issue)
		rollback_probe["after_stroke_fingers"]=controller.get("_fingers").duplicate(true)
		rollback_probe["after_stroke_blocked"]=controller.get("_blocked").duplicate(true)
		rollback_probe["after_stroke_gesture_generation"]=controller.get("_gesture_generation").duplicate(true)
		rollback_probe["after_stroke_dragged"]=controller.get("_dragged")
		finger(1,true,b)
		await process_frame # Observe rollback while both source contacts are still held.
		rollback_probe["after_second_finger"]=controller.draft.capture_state().duplicate(true)
		rollback_probe["after_second_finger_equals_before"]=controller.draft.capture_state()==draft
		rollback_probe["after_second_finger_count"]=controller.get("_fingers").size()
		rollback_probe["after_second_finger_draw_move"]=controller.get("_draw_move")
		rollback_probe["after_second_finger_draw_first"]=controller.get("_draw_first")
		rollback_probe["after_second_finger_draw_backup"]=controller.get("_draw_backup").duplicate(true)
		check(controller.get("_fingers").size()==2 and controller.draft.capture_state()==draft and host.session.sim.snapshot()==snapshot,"second finger restores the original draft while both real contacts remain held")
		finger(1,false,b);await process_frame
		target=camera.target;zoom=camera.zoom_size
		drag(0,a+Vector2(36,16),a+Vector2(54,24));await process_frame
		check(controller.get("_fingers").size()==1 and controller.draft.capture_state()==draft and camera.target.is_equal_approx(target) and is_equal_approx(camera.zoom_size,zoom) and host.session.sim.snapshot()==snapshot,"remaining finger after multitouch cannot take over single-finger drawing or camera navigation")
		finger(0,false,a+Vector2(54,24));await settle()
		rollback_probe["after_release"]=controller.draft.capture_state().duplicate(true)
		rollback_probe["after_release_equals_before"]=controller.draft.capture_state()==draft
		rollback_probe["after_release_step"]=controller.draft.step
		rollback_probe["after_release_model_unchanged"]=host.session.sim.snapshot()==snapshot
		rollback_probe["after_release_draw_move"]=controller.get("_draw_move")
		rollback_probe["after_release_draw_first"]=controller.get("_draw_first")
		rollback_probe["after_release_draw_backup"]=controller.get("_draw_backup").duplicate(true)
		diagnostics.append(rollback_probe)
		print("BUILD NAV DIAGNOSTIC: "+JSON.stringify(rollback_probe))
		check(stroke_changed and controller.draft.capture_state()==draft and controller.draft.step==0 and host.session.sim.snapshot()==snapshot,"second finger rolls back an actually changed unfinished size stroke; ending the gesture cannot place or confirm")
	else:check(false,"fixture: rollback rays remain available")
	# A non-action title on the card starts the first finger, so both contacts are GUI-owned.
	var gui:Vector2=editor.card.get_global_rect().position+Vector2(22,16)
	pair=_pair()
	if pair.size()==2:
		a=pair[0];b=pair[1];target=camera.target;zoom=camera.zoom_size
		finger(0,true,gui);finger(1,true,a)
		drag(0,gui,b);drag(1,a,a+Vector2(36,16))
		finger(0,false,b);finger(1,false,a+Vector2(36,16));await settle()
		check(camera.target.is_equal_approx(target) and is_equal_approx(camera.zoom_size,zoom) and controller.draft.capture_state()==draft and host.session.sim.snapshot()==snapshot,"GUI-started contacts cannot leak into camera navigation, room placement or confirmation")
	else:check(false,"fixture: GUI blocking rays remain available")
	# Fixture API requests a mode change during an already held real stroke.
	# Further source events from that old contact must have no new owner.
	pair=_pair()
	if pair.size()==2:
		a=pair[0];b=pair[1]
		finger(0,true,a);drag(0,a,a+Vector2(18,8));await process_frame
		controller.call("set_navigation_mode",true)
		var after_mode:Dictionary=controller.draft.capture_state().duplicate(true)
		target=camera.target;zoom=camera.zoom_size
		drag(0,a+Vector2(18,8),b);finger(0,false,b);await settle()
		check(controller.draft.capture_state()==after_mode and camera.target.is_equal_approx(target) and is_equal_approx(camera.zoom_size,zoom) and host.session.sim.snapshot()==snapshot,"mode change discards the old held contact so its later drag and release cannot mutate draft or camera")
		controller.call("set_navigation_mode",false)
	else:check(false,"fixture: held-contact mode-change rays remain available")
	# Camera-only fixture reaches the real rig clamp; no model fields are changed.
	var prior_zoom:float=camera.zoom_size
	camera.set_zoom(1000)
	zoom=camera.zoom_size;target=camera.target;draft=controller.draft.capture_state()
	pair=_pair()
	if pair.size()==2:
		a=pair[0];b=pair[1]
		finger(0,true,a);finger(1,true,b)
		drag(0,a,a+move);drag(1,b,b+move)
		finger(0,false,a+move);finger(1,false,b+move);await settle()
		check(camera.target.distance_to(target)>0.05 and is_equal_approx(camera.zoom_size,zoom) and controller.draft.capture_state()==draft and host.session.sim.snapshot()==snapshot,"same-distance two-finger pan at the actual rig zoom limit cannot accumulate clamp drift")
	else:check(false,"fixture: exposed floor rays exist at actual rig zoom limit")
	camera.set_zoom(prior_zoom)
	# Public API only prepares the next stage; behavior above used real touches.
	controller.call("set_navigation_mode",true)
	var advanced:bool=controller.advance()
	await settle()
	controller.call("set_navigation_mode",true)
	check(advanced and controller.draft.step==1 and not bool(controller.view().navigation_mode) and not button.visible and host.session.sim.snapshot()==snapshot,"fixture stage transition: navigation toggle is confined to size stage and adds no fixed row later")
	await finish()

func finish()->void:
	if host!=null:
		host.free();host=null
	await create_timer(0.24).timeout
	var report:Dictionary={"passed":passed,"failed":failed,"checks":checks,"captures":captures,"diagnostics":diagnostics,"source":"Real Main/HUD and isolated GameSession; setup/API calls are fixtures; gestures and buttons use ScreenTouch/ScreenDrag through Input.parse_input_event. Desktop viewport evidence is not phone-device acceptance."}
	if paths.write_report(report)!=OK:printerr("NAVIGATION PATH ERROR: report_write_failed");quit(2);return
	print("BUILD NAV RESULT: passed=%d failed=%d"%[passed,failed])
	quit(1 if failed else 0)
