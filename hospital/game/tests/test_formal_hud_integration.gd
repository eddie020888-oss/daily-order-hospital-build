extends SceneTree

const FormalPaths=preload("res://tests/support/formal_test_paths.gd")
var test_paths:Variant

# Integration exercises the real main input owner, HUD, world and command model.
# The prepared state is a test fixture, not evidence of a normal player playthrough.
var output := ""
var passed := 0
var failed := 0
var checks: Array = []

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=").replace("\\","/")
	var reservation:Dictionary=FormalPaths.reserve(output,"formal-hud-integration")
	if not reservation.get("ok",false):
		printerr("FORMAL TEST PATH ERROR: "+str(reservation.get("code","unknown")));quit(2);return
	test_paths=reservation.paths;output=str(reservation.output)
	_run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks.append({"ok":ok,"check":label})
	if ok:passed+=1
	else:failed+=1;print("FORMAL HUD FAIL: "+label)

func _touch(index: int,pressed: bool,point: Vector2) -> InputEventScreenTouch:
	var event:=InputEventScreenTouch.new()
	event.index=index;event.pressed=pressed;event.position=point
	return event

func _run() -> void:
	root.size=Vector2i(932,430)
	var loaded:Dictionary=ContentCatalog.load_checked("res://content")
	check(loaded.get("ok",false),"real content loads")
	if not loaded.get("ok",false):finish();return
	var host=load("res://main.gd").new()
	var fixture_path:String=test_paths.fixture("hospital")
	if fixture_path=="":
		printerr("FORMAL TEST PATH ERROR: fixture_create_failed");quit(2);return
	host.session=GameSession.new(loaded.catalog,fixture_path)
	check(host.session.start_level("long_01").get("ok",false),"real new hospital starts through public session")
	root.add_child(host)
	for _n in range(4):await process_frame
	host.hud.configure_display(Vector2(932,430),Vector2(932,430),160,Rect2(59,0,814,409))
	host.hud.flow.close();host.session.dismiss_notice()
	check(host.hud.has_method("begin_campaign_build"),"HUD exposes real scene construction instead of coordinate forms")
	if not host.hud.has_method("begin_campaign_build"):
		host.free();finish();return
	var before:Dictionary=host.session.sim.snapshot()
	check(host.hud.call("begin_campaign_build","build","O01",""),"normal HUD opens reception scene draft")
	var editor=host.hud.get("campaign_build")
	check(editor!=null and editor.active,"editor owns active draft")
	check(not host.hud.campaign_panel.visible and not host.hud.flow.visible,"catalog and modal are closed for scene interaction")
	if editor==null:host.free();finish();return
	for _n in range(3):await process_frame
	check(editor.card.get_global_rect().position.x>=59 and editor.card.get_global_rect().end.x<=873,"short landscape construction card respects safe horizontal area")
	host._input(_touch(0,true,Vector2(720,205)))
	check(host.touch.get("_fingers").is_empty(),"legacy controller cannot share construction touch ownership")
	host._input(_touch(1,true,Vector2(800,235)))
	host._input(_touch(0,false,Vector2(720,205)))
	host._input(_touch(1,false,Vector2(800,235)))
	var after:Dictionary=host.session.sim.snapshot()
	check(after.cash==before.cash and after.rooms==before.rooms and after.facilities==before.facilities,"multitouch preview never changes hospital capital")
	editor.cancel()
	check(not editor.active,"cancel releases scene draft ownership")
	check(host.world.get("_campaign_preview")==null,"cancel clears visual ghost")
	check(host.hud.call("begin_campaign_build","build","U04-E1",""),"guide's actual first diagnosis device is reachable")
	host.hud._flow_action("menu")
	check(not editor.active,"opening system menu cancels the foremost construction draft")
	check(host.session.sim.snapshot().cash==before.cash,"modal cancellation cannot charge for preview")
	host.hud.flow.close()
	check(host.hud.call("begin_campaign_build","build","O01",""),"construction can reopen after modal")
	host._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(not editor.active and host.touch.get("_fingers").is_empty(),"focus loss cancels new draft and clears legacy pointer state")
	host._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	check(host.session.sim.snapshot().paused,"focus restoration preserves paused hospital")
	check(SnapshotValidator.validate(host.session.sim.snapshot(),loaded.catalog)=="","real hospital remains strictly save-valid after interrupted input")
	var first_employee:Dictionary=host.session.issue("hire",{"role":"doctor"})
	var second_employee:Dictionary=host.session.issue("hire",{"role":"doctor"})
	check(first_employee.get("ok",false) and second_employee.get("ok",false),"two real employees can be distinguished in the scene selection fixture")
	if second_employee.get("ok",false):
		host.hud.select_entity(str(second_employee.data.staff_id),"staff")
		var choice:OptionButton=host.hud.campaign_panel.controls.get("assign_staff")
		check(choice!=null and str(choice.get_item_metadata(choice.selected))==str(second_employee.data.staff_id),"selecting the second scene employee shows that employee rather than the first roster entry")
		var prior:Dictionary=host.session.sim.snapshot()
		host.hud._campaign_opening_action({"action":"goals","section":"staff","staff_id":str(first_employee.data.staff_id),"control":"rest_"+str(first_employee.data.staff_id)+"_water"})
		choice=host.hud.campaign_panel.controls.get("assign_staff")
		check(choice!=null and str(choice.get_item_metadata(choice.selected))==str(first_employee.data.staff_id),"manual staff-rest navigation selects its actual employee after a different employee was inspected")
		check(host.session.sim.snapshot()==prior,"manual staff-rest navigation cannot hire charge rest or mutate the hospital")
	check(host.hud.has_method("show_campaign_patient"),"HUD opens a contextual live patient inspector instead of the full list")
	if host.hud.has_method("show_campaign_patient"):
		var intact:Dictionary=host.session.sim.snapshot()
		check(not host.hud.call("show_campaign_patient","missing_patient"),"stale actor selection cannot open an invented patient")
		check(host.session.sim.snapshot()==intact,"stale patient selection never creates a clinical decision or expense")
	host.free()
	host=null
	# Let the audio mixer consume queued stop/free commands before engine shutdown.
	await create_timer(0.24).timeout
	finish()

func finish() -> void:
	if test_paths.write_report({"passed":passed,"failed":failed,"checks":checks,"source":"Native main/HUD integration with real model; automated fixture, not human or iPhone playthrough"},"  ")!=OK:
		printerr("FORMAL TEST PATH ERROR: report_write_failed");quit(2);return

	print("FORMAL HUD RESULT: passed=%d failed=%d"%[passed,failed])
	quit(1 if failed>0 else 0)
