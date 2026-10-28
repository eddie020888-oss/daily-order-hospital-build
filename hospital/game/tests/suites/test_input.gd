extends RefCounted

var session_script: GDScript
var touch_script: GDScript

func run(t: TestContext) -> void:
	var exists := FileAccess.file_exists("res://session/game_session.gd") and FileAccess.file_exists("res://input/touch_controller.gd")
	t.expect_true(exists,"Input: session and touch controller are operational")
	if not exists: return
	session_script = load("res://session/game_session.gd")
	touch_script = load("res://input/touch_controller.gd")
	test_second_finger_cancels_placement_before_release(t)
	test_ui_tap_does_not_pan_or_place_room(t)
	test_double_submit_and_cancel_never_double_charge(t)
	test_background_save_then_resume_stays_paused(t)
	test_frame_patterns_reach_equal_state_at_equal_tick(t)
	test_selected_patient_can_override_next_mode_but_not_active_treatment(t)
	test_pause_hint_discards_backlog_and_does_not_repeat(t)
	test_corrupt_commits_block_auto_new_game_and_backup_is_visible(t)
	test_pan_and_clamped_zoom_pick_actual_cell_centers(t)
	test_hud_controls_and_density_safe_area_contract(t)
	test_patient_information_hides_tolerance_until_diagnosis(t)
	test_mouse_reuses_pointer_ownership(t)
	load("res://tests/suites/test_input_review.gd").new().run(t)

func test_mouse_reuses_pointer_ownership(t: TestContext) -> void:
	var world:=HospitalWorld.new()
	Engine.get_main_loop().root.add_child(world)
	var c: RefCounted=touch_script.new(world)
	var before:=world.camera_rig.target
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new()
		event.button_index=MOUSE_BUTTON_LEFT
		event.pressed=pressed
		event.position=Vector2(600,330) if pressed else Vector2(660,350)
		c.feed(event)
		if pressed:
			var drag:=InputEventMouseMotion.new()
			drag.position=Vector2(660,350)
			c.feed(drag)
	t.expect_true(world.camera_rig.target!=before,"desktop pointer can pan actual camera")
	world.free()

func test_hud_controls_and_density_safe_area_contract(t: TestContext) -> void:
	var exists:=FileAccess.file_exists("res://ui/hospital_hud.gd")
	t.expect_true(exists,"HUD: playable controls exist")
	if not exists: return
	var script: GDScript=load("res://ui/hospital_hud.gd")
	# Break caught: treating physical pixels as viewport coordinates makes targets too small and GUI misses.
	var layout: Dictionary=script.layout_metrics(Vector2(2560,1440),Vector2(1280,720),480,Rect2(80,0,2400,1440))
	t.expect_equal(layout.target,72.0,"48dp at density3/output scale2 has72 viewport pixels")
	t.expect_equal(layout.safe,Rect2(40,0,1200,720),"physical safe area converted to input coordinates")
	var s:=_session()
	var c:=_controller(s)
	# _controller starts a placement for low-level touch tests. Ordinary A2
	# HUD ownership must be sampled after that unrelated draft is cancelled.
	c.cancel()
	var hud: Control=script.new()
	Engine.get_main_loop().root.add_child(hud)
	hud.initialize(s,c,null)
	# Inject a high-density, scaled-output device and exercise GUI ownership in that coordinate space.
	t.expect_true(hud.has_method("configure_display"),"HUD adapts physical density and safe area together")
	if not hud.has_method("configure_display"):
		hud.free()
		return
	hud.configure_display(Vector2(2560,1440),Vector2(1280,720),480,Rect2(80,0,2400,1440))
	t.expect_true(hud.controls.speed2.custom_minimum_size.x*hud.scale.x>=72 and hud.controls.speed2.custom_minimum_size.y*hud.scale.y>=72,"primary target meets48dp in both dimensions")
	t.expect_true(hud._dock.is_visible_in_tree() and hud._top_frame.is_visible_in_tree(),"ordinary HUD ownership fixture shows both real A2 frames")
	var console_point:Vector2=hud._dock.get_global_rect().get_center()
	t.expect_true(hud.hits_gui(console_point),"scaled safe-area GUI rect uses viewport input coordinates")
	var duty_point:Vector2=hud._top_frame.get_global_rect().get_center()
	var duty_hit:bool=hud.hits_gui(duty_point)
	if not duty_hit:
		print("A2 INPUT GEOMETRY: "+JSON.stringify({"top_rect":str(hud._top_frame.get_global_rect()),"point":str(duty_point),"visible":hud._top_frame.visible,"in_tree":hud._top_frame.is_visible_in_tree(),"top_rect_contains":hud._top_frame.get_global_rect().has_point(duty_point),"dock_rect":str(hud._dock.get_global_rect()),"dock_visible":hud._dock.visible,"preview_visible":hud._preview_panel.visible,"catalog":hud._construction_catalog_open(),"safe":str(hud._safe),"scale":str(hud.scale),"flow_page":hud.flow.page,"flow_visible":hud.flow.visible}))
	t.expect_true(duty_hit,"separate A2 top duty frame owns its viewport input rectangle")
	var world_gap:Vector2=Vector2(hud._safe.get_center().x,(hud._top_frame.position.y+hud._top_frame.size.y+hud._dock.position.y)*0.5)*hud.scale
	t.expect_true(not hud.hits_gui(world_gap),"empty center between A2 frames remains available to world gestures")
	var scaled_touch: RefCounted=touch_script.new(null,hud.hits_gui)
	scaled_touch.begin_placement("reception")
	scaled_touch.choose_cell(121)
	scaled_touch.feed(_touch(0,true,console_point))
	scaled_touch.feed(_touch(0,false,console_point))
	t.expect_equal(scaled_touch.placement.origin_cell,121,"scaled GUI input cannot choose floor")
	hud.controls.speed2.pressed.emit()
	t.expect_equal(s.sim.snapshot().speed,2,"speed button submits command")
	hud.controls.hire_receptionist.pressed.emit()
	t.expect_equal(s.sim.snapshot().staff.size(),1,"hire button changes actual clinic")
	t.expect_equal(s.sim.snapshot().cash,7900,"hire has real fee")
	hud.controls.patients.pressed.emit()
	hud.selection.controls.hospital_flow.pressed.emit()
	hud.operations.controls.stage_recovery.pressed.emit()
	hud.operations.controls.auto_route.pressed.emit()
	t.expect_true(s.sim.snapshot().auto_route,"routing control submits command")
	s.sim=Scenarios.create_sim(s.catalog,"benchmark_18","fast","standard")
	s.sim.advance_ticks(201)
	while not s.sim.snapshot().patients.patient_000001.tolerance_revealed: s.sim.advance_ticks(1)
	s.issue("set_paused",{"paused":true})
	s.changed.connect(hud.present)
	hud.select_entity("patient_000001","patients")
	hud.selection.controls.treatment_preview.pressed.emit()
	hud.selection.controls.gentle.pressed.emit()
	hud.selection.controls.apply_mode.pressed.emit()
	hud.selection.controls.back.pressed.emit()
	t.expect_equal(hud.selection.find_child("Value_预计刺激",true,false).text,"20","paused explicit apply immediately refreshes actual stimulus prediction")
	hud.free()

func test_patient_information_hides_tolerance_until_diagnosis(t: TestContext) -> void:
	if not FileAccess.file_exists("res://ui/selection_panel.gd"): return
	var script: GDScript=load("res://ui/selection_panel.gd")
	var catalog: ContentCatalog=ContentCatalog.load_checked("res://content").catalog
	var sim:=Scenarios.create_sim(catalog,"benchmark_18","fast","standard")
	sim.advance_ticks(201)
	var p: Dictionary=sim.snapshot().patients.patient_000001
	var before: String=script.patient_information(p,sim.snapshot(),catalog)
	t.expect_false(before.contains("耐受 70"),"hidden tolerance cannot leak before diagnosis")
	while not sim.snapshot().patients.patient_000001.tolerance_revealed: sim.advance_ticks(1)
	sim.advance_ticks(1)
	var after: String=script.patient_information(sim.snapshot().patients.patient_000001,sim.snapshot(),catalog)
	t.expect_true(after.contains("耐受 70"),"diagnosis reveals tolerance")
	t.expect_true(after.contains("12秒") and after.contains("25币") and after.contains("无需恢复"),"actual fast prediction exposed before treatment")

func _session() -> RefCounted:
	return session_script.new(ContentCatalog.load_checked("res://content").catalog,ProjectSettings.globalize_path("res://../temp/tests/input-%d-%d" % [Time.get_ticks_usec(),randi()]))

func _touch(index: int, pressed: bool, point: Vector2) -> InputEventScreenTouch:
	var event := InputEventScreenTouch.new()
	event.index=index
	event.pressed=pressed
	event.position=point
	return event

func _controller(s: RefCounted, hit: Callable = Callable()) -> RefCounted:
	var c: RefCounted = touch_script.new(null,hit,s.reserve_command_id)
	c.command_requested.connect(s.submit)
	c.begin_placement("reception")
	c.choose_cell(121)
	return c

func test_second_finger_cancels_placement_before_release(t: TestContext) -> void:
	# A second finger must take gesture ownership before the first can place anything.
	var s := _session()
	var c := _controller(s)
	c.feed(_touch(0,true,Vector2(450,300)))
	c.feed(_touch(1,true,Vector2(550,300)))
	c.feed(_touch(0,false,Vector2(450,300)))
	c.feed(_touch(1,false,Vector2(550,300)))
	c.confirm()
	t.expect_equal(s.sim.snapshot().cash,8000,"pinch cancels placement")
	t.expect_equal(s.sim.snapshot().rooms.size(),0,"no unintended room")

func test_ui_tap_does_not_pan_or_place_room(t: TestContext) -> void:
	var s := _session()
	var c := _controller(s,func(_p: Vector2) -> bool: return true)
	c.feed(_touch(0,true,Vector2(20,20)))
	c.feed(_touch(0,false,Vector2(20,20)))
	t.expect_equal(c.placement.origin_cell,121,"GUI cannot change preview")
	t.expect_equal(s.sim.snapshot().cash,8000,"GUI cannot build")

func test_double_submit_and_cancel_never_double_charge(t: TestContext) -> void:
	var s := _session()
	var c := _controller(s)
	var emitted: Array=[]
	c.command_requested.connect(func(command: Dictionary) -> void: emitted.append(command))
	c.confirm()
	s.submit(emitted[0])
	s.submit(emitted[0])
	c.confirm()
	c.cancel()
	t.expect_equal(s.sim.snapshot().cash,7600,"confirmed build charges once")
	t.expect_equal(s.sim.snapshot().rooms.size(),1,"duplicate confirm no extra room")
	c.begin_placement("reception")
	c.choose_cell(145)
	c.cancel()
	c.confirm()
	t.expect_equal(s.sim.snapshot().cash,7600,"cancel no fee")
	t.expect_equal(s.sim.snapshot().tick,0,"paused build time stays zero")

func test_background_save_then_resume_stays_paused(t: TestContext) -> void:
	var s := _session()
	s.issue("set_paused",{"paused":false})
	s.advance_wall_time(350000)
	s.handle_focus_lost()
	var saved := SaveStore.load(s.save_root,s.catalog)
	t.expect_true(saved.ok and saved.state.data.paused,"background pauses before storage")
	s.advance_wall_time(900000000)
	s.handle_focus_gained()
	t.expect_true(s.sim.snapshot().paused,"return stays paused")
	t.expect_equal(s.sim.snapshot().tick,3,"no offline catchup")

func test_frame_patterns_reach_equal_state_at_equal_tick(t: TestContext) -> void:
	var a := _session()
	var b := _session()
	# Replay the same initial game, including its new cosmetic seed. Two new
	# games intentionally draw different appearances, independent of pacing.
	b.sim=Simulation.new(b.catalog,ClinicState.from_data(a.sim.snapshot(),b.catalog).state)
	for s in [a,b]:
		s.issue("set_speed",{"speed":2})
		s.issue("set_paused",{"paused":false})
	for _i in range(100): a.advance_wall_time(10000)
	for _i in range(4): b.advance_wall_time(250000)
	t.expect_equal(a.sim.snapshot().tick,20,"2x executes 20 fixed ticks per second")
	var aa: Dictionary=a.sim.snapshot()
	var bb: Dictionary=b.sim.snapshot()
	aa.erase("command_receipts")
	bb.erase("command_receipts")
	t.expect_equal(aa,bb,"equal elapsed time has equal clinical state")

func test_selected_patient_can_override_next_mode_but_not_active_treatment(t: TestContext) -> void:
	var s := _session()
	s.sim=Scenarios.create_sim(s.catalog,"benchmark_18","fast","standard")
	while s.sim.snapshot().tick<350: s.sim.advance_ticks(1)
	var accepted: Dictionary=s.issue("set_patient_mode",{"patient_id":"patient_000001","mode":"gentle"})
	t.expect_true(accepted.ok,"pre-treatment individual override accepted")
	while not s.sim.snapshot().patients.patient_000001.treatment_started: s.sim.advance_ticks(1)
	var rejected: Dictionary=s.issue("set_patient_mode",{"patient_id":"patient_000001","mode":"fast"})
	t.expect_false(rejected.ok,"active treatment cannot be rewritten")

func test_pause_hint_discards_backlog_and_does_not_repeat(t: TestContext) -> void:
	var s := _session()
	s.issue("set_paused",{"paused":false})
	s.advance_wall_time(300000000)
	t.expect_equal(s.sim.snapshot().tick,2400,"hint stops in middle of frame")
	t.expect_true(s.notice.contains("动作"),"unlock shown once")
	s.dismiss_notice()
	s.issue("set_paused",{"paused":false})
	s.advance_wall_time(100000)
	t.expect_equal(s.sim.snapshot().tick,2401,"hint drops unexecuted frame backlog")
	t.expect_equal(s.notice,"","retained pending not redisplayed")

func test_corrupt_commits_block_auto_new_game_and_backup_is_visible(t: TestContext) -> void:
	var s := _session()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(s.save_root))
	for name in ["main.json","previous.json"]:
		var file:=FileAccess.open(s.save_root.path_join(name),FileAccess.WRITE)
		file.store_string("broken evidence")
		file.close()
	s.open_saved()
	t.expect_true(s.storage_blocked,"two damaged commits block automatic overwrite")
	t.expect_false(s.save_now().ok,"cannot overwrite damaged committed files")
	t.expect_equal(FileAccess.get_file_as_string(s.save_root.path_join("main.json")),"broken evidence","damaged bytes preserved")
	var b:=_session()
	b.save_now()
	b.issue("build_room",{"kind":"reception","origin_cell":121,"rotation":0})
	b.save_now()
	var f:=FileAccess.open(b.save_root.path_join("main.json"),FileAccess.WRITE)
	f.store_string("bad")
	f.close()
	b.open_saved()
	t.expect_true(b.notice.contains("备用"),"successful backup diagnostic visible")
	t.expect_true(b.sim.snapshot().paused,"loaded sessions force pause")

func test_pan_and_clamped_zoom_pick_actual_cell_centers(t: TestContext) -> void:
	var world:=HospitalWorld.new()
	Engine.get_main_loop().root.add_child(world)
	world.camera_rig.pan(Vector3(2,0,1))
	for value in [0.1,200.0]:
		world.camera_rig.set_zoom(value)
		var screen:=world.camera_rig.camera.unproject_position(Vector3(12,0,9))
		t.expect_equal(world.camera_rig.screen_to_cell(screen),228,"actual center pick after pan and clamped zoom")
	world.free()
