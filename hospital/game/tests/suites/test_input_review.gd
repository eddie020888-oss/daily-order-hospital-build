extends RefCounted

func run(t: TestContext) -> void:
	test_prediction_uses_assigned_room_or_defers_unassigned(t)
	test_main_interruption_resets_pinch_and_canceled_touch(t)
	test_internal_ids_skip_loaded_receipts_without_remapping_external_ids(t)
	test_notice_targets_blocked_room_and_seats_and_expandable_flow(t)
	test_first_congestion_has_contextual_patient_target(t)
	test_held_flow_uses_latest_paused_patient_projection(t)

func _session() -> GameSession:
	var session:GameSession=GameSession.new(ContentCatalog.load_checked("res://content").catalog,ProjectSettings.globalize_path("res://../temp/tests/input-review-%d-%d" % [Time.get_ticks_usec(),randi()]))
	var legacy_start:Dictionary=session.start_level("level_01")
	assert(legacy_start.get("ok",false),"isolated legacy teaching fixture must initialize")
	session.dismiss_notice()
	return session

func _host(session: GameSession) -> Node3D:
	var host: Node3D=load("res://main.gd").new()
	host.session=session
	Engine.get_main_loop().root.add_child(host)
	host.set_process(false)
	host.hud.flow.controls.continue_game.pressed.emit()
	return host

func _finger(c: TouchController, index: int, down: bool, point: Vector2, canceled: bool=false) -> void:
	var e:=InputEventScreenTouch.new()
	e.index=index
	e.pressed=down
	e.position=point
	e.canceled=canceled
	c.feed(e)

func _text(node: Node) -> String:
	var result: String=node.text if node is Label else ""
	for child in node.get_children(): result+="\n"+_text(child)
	return result

func test_prediction_uses_assigned_room_or_defers_unassigned(t: TestContext) -> void:
	# Break caught: dictionary-first fast/closed room overrides the device actually assigned to this patient.
	var s:=_session()
	for row in [["reception",121],["diagnosis",100],["echo",104],["echo",108]]:
		s.issue("build_room",{"kind":row[0],"origin_cell":row[1],"rotation":0})
	for row in [["receptionist","room_001"],["doctor","room_002"],["technician","room_004"]]:
		var hired:=s.issue("hire_staff",{"role":row[0]})
		s.issue("assign_staff",{"staff_id":hired.data.staff_id,"room_id":row[1]})
	s.issue("set_room_mode",{"room_id":"room_004","mode":"gentle"})
	s.issue("close_room",{"room_id":"room_003"})
	s.issue("set_paused",{"paused":false})
	while not s.sim.snapshot().patients.get("patient_001",{}).get("tolerance_revealed",false): s.sim.advance_ticks(1)
	s.sim.advance_ticks(1)
	var snapshot:=s.sim.snapshot()
	var patient: Dictionary=snapshot.patients.patient_001
	t.expect_equal(patient.room_id,"room_004","actual flow assigned second gentle device")
	t.expect_equal(snapshot.rooms.room_003.status,"closed","first fast device is fully closed")
	var info:=SelectionPanel.patient_information(patient,snapshot,s.catalog)
	t.expect_true(info.contains("20秒") and info.contains("15币") and info.contains("无需恢复"),"assigned gentle low-tolerance prediction agrees with service")
	var slot_only:=patient.duplicate(true)
	slot_only.room_id=""
	t.expect_true(SelectionPanel.patient_information(slot_only,snapshot,s.catalog).contains("20秒"),"owned slot resolves actual gentle device")
	var unassigned:=patient.duplicate(true)
	unassigned.room_id=""
	unassigned.slot_id=""
	var pending:=SelectionPanel.patient_information(unassigned,snapshot,s.catalog)
	t.expect_false(pending.contains("12秒") or pending.contains("20秒"),"unassigned device default has no false exact forecast")
	while not s.sim.snapshot().patients.patient_001.treatment_started: s.sim.advance_ticks(1)
	t.expect_equal(s.sim.snapshot().patients.patient_001.service_mode,"gentle","real treatment uses predicted mode")

func test_main_interruption_resets_pinch_and_canceled_touch(t: TestContext) -> void:
	# Break caught: missing release events leave finger1 alive across background/foreground.
	var root: Window=Engine.get_main_loop().root
	var previous_size:=root.size
	root.size=Vector2i(1280,720)
	var s:=_session()
	var host:=_host(s)
	_finger(host.touch,0,true,Vector2(450,330))
	_finger(host.touch,1,true,Vector2(550,330))
	host.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	host.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	t.expect_true(preload("res://tests/native_a2_interactions.gd").begin_build(host.hud,"reception"),"explicit start opens the selected reception draft")
	host.world.focus_cell(121)
	var point: Vector2=host.world.camera_rig.camera.unproject_position(HospitalWorld.cell_position(121))
	t.expect_false(host.hud.hits_gui(point),"post-resume test floor is outside GUI")
	_finger(host.touch,0,true,point)
	_finger(host.touch,0,false,point)
	t.expect_equal(host.touch.placement.get("origin_cell",-1),121,"single finger places after interrupted pinch")
	# The normal palette now starts four-step free construction. Complete the
	# interrupted gesture fixture through its real size, door and device stages.
	host.touch.choose_cell(171)
	host.touch.advance_build_step()
	host.touch.choose_cell(170)
	host.touch.advance_build_step()
	host.touch.choose_cell(121)
	host.touch.advance_build_step()
	host.touch.confirm()
	t.expect_equal(s.sim.snapshot().rooms.size(),1,"post-resume placement really executes")
	t.expect_true(s.sim.snapshot().paused,"gesture reset never resumes simulation")
	var canceled:=TouchController.new(host.world)
	canceled.begin_placement("echo")
	_finger(canceled,0,true,point)
	_finger(canceled,0,false,point,true)
	t.expect_equal(canceled.placement.get("origin_cell",-1),-1,"canceled ScreenTouch never becomes a tap")
	host.free()
	root.size=previous_size

func test_internal_ids_skip_loaded_receipts_without_remapping_external_ids(t: TestContext) -> void:
	# Break caught: a restarted process repeats the next ticks-prefix ID and replays an unrelated receipt.
	var standalone:=TouchController.new()
	var unsafe_commands: Array=[]
	standalone.command_requested.connect(func(command: Dictionary) -> void: unsafe_commands.append(command))
	standalone.begin_placement("reception")
	standalone.choose_cell(121)
	standalone.confirm()
	t.expect_equal(unsafe_commands.size(),0,"placement without receipt-aware ID provider cannot dispatch unsafe command")
	var s:=_session()
	s._prefix="forced_collision"
	var external:={"id":"forced_collision_1","type":"hire_staff","payload":{"role":"receptionist"}}
	s.submit(external)
	s.issue("build_room",{"kind":"echo","origin_cell":104,"rotation":0})
	t.expect_equal(s.sim.snapshot().rooms.size(),1,"session skips next candidate already committed")
	var cash: int=s.sim.snapshot().cash
	var replay:=s.submit(external)
	t.expect_equal(replay.data.command.id,"forced_collision_1","explicit external ID is not remapped")
	t.expect_equal(s.sim.snapshot().cash,cash,"external replay stays idempotent")
	var saved:=_session()
	saved.submit({"id":"loaded_collision_1","type":"hire_staff","payload":{"role":"receptionist"}})
	saved.issue("set_paused",{"paused":false})
	saved.save_now()
	var loaded:=GameSession.new(saved.catalog,saved.save_root)
	loaded._prefix="loaded_collision"
	loaded.open_saved()
	t.expect_true(loaded.sim.snapshot().paused,"loaded receipt collision cannot defeat forced pause")
	t.expect_true(loaded.has_method("reserve_command_id"),"touch shares receipt-aware ID reservation")
	if loaded.has_method("reserve_command_id"):
		loaded._prefix="loaded_collision"
		loaded._serial=0
		var c: TouchController=load("res://input/touch_controller.gd").new(null,Callable(),Callable(loaded,"reserve_command_id"))
		c.command_requested.connect(loaded.submit)
		c.begin_placement("reception")
		c.choose_cell(121)
		c.confirm()
		c.confirm()
		t.expect_equal(loaded.sim.snapshot().rooms.size(),1,"touch skips loaded receipt and executes one new build")
		t.expect_equal(loaded.sim.snapshot().cash,7500,"touch repeated confirm charges once after load")

func test_notice_targets_blocked_room_and_seats_and_expandable_flow(t: TestContext) -> void:
	var s:=_session()
	s.sim=Scenarios.create_sim(s.catalog,"benchmark_18","fast","standard")
	s.sim.advance_ticks(418)
	var host:=_host(s)
	s.issue("close_room",{"room_id":"room_003"})
	var rejected:=s.issue("remove_room",{"room_id":"room_003"})
	t.expect_equal(rejected.code,"room_busy","fixture refuses busy treatment-room demolition")
	host.hud.controls.locate.pressed.emit()
	t.expect_equal(host.hud.selection.selected_group,"rooms","busy-room notice does not navigate to unrelated patient")
	t.expect_equal(host.hud.selection.selected_id,"room_003","busy-room notice selects exact rejected room")
	host.free()
	var recovery:=_session()
	recovery.sim=Scenarios.create_sim(recovery.catalog,"benchmark_18","fast","standard")
	recovery.issue("upgrade_recovery",{"room_id":"room_006"})
	var found:=false
	for _i in range(5000):
		recovery.sim.advance_ticks(1)
		var slots: Dictionary=recovery.sim.snapshot().slots
		var phases: Array=[]
		for slot in slots.values():
			if slot.room_id=="room_006": phases.append(slot.phase)
		if "serving" in phases and "reserved" in phases:
			found=true
			break
	t.expect_true(found,"real recovery has one occupied and one reserved seat")
	var view:=_host(recovery)
	view.hud.select_entity("room_006","rooms")
	var copy:=_text(view.hud.selection)
	t.expect_true(copy.contains("占用 1") and copy.contains("预留 1") and copy.contains("共 2"),"recovery detail shows occupied reserved and total")
	var main_copy:=_text(view.hud._hint)
	t.expect_true(main_copy.replace(" ","").contains("占用1") and main_copy.replace(" ","").contains("预留1"),"current recovery occupancy is visible in main HUD")
	var before:=recovery.sim.snapshot()
	var fixture:=before.duplicate(true)
	var id: String=fixture.patients.keys()[0]
	fixture.patients[id].phase="treatment_queue"
	fixture.patients[id].wait_reason="equipment_busy"
	fixture.patients[id].wait_by_stage={"reception":20,"diagnosis":90,"treatment":250}
	view.hud.configure_display(Vector2(2560,1440),Vector2(1280,720),480,Rect2(0,0,2560,1440))
	view.hud.selection.select(id,"patients")
	view.hud.selection.present(fixture,recovery.catalog)
	t.expect_true(view.hud.selection.controls.has("flow"),"patient congestion flow can expand")
	if view.hud.selection.controls.has("flow"):
		view.hud.selection.controls.flow.pressed.emit()
		t.expect_true(view.hud.selection.controls.back.custom_minimum_size.y*view.hud.scale.y>=72,"flow return control preserves physical touch target")
		var expanded:=_text(view.hud.selection)
		t.expect_true(expanded.contains("最长累计等待：治疗 25秒") and expanded.contains("设备正在服务"),"expanded flow shows patient longest stage and current cause")
		view.hud.selection.controls.back.pressed.emit()
		t.expect_false(_text(view.hud.selection).contains("最长累计等待"),"return from flow preserves patient detail")
	t.expect_equal(recovery.sim.snapshot(),before,"operational projections never modify authority")
	view.free()

func test_first_congestion_has_contextual_patient_target(t: TestContext) -> void:
	var s:=_session()
	s.sim=Scenarios.create_sim(s.catalog,"benchmark_18","fast","standard")
	for _i in range(2000):
		s.advance_wall_time(100000)
		if not s.notice.is_empty(): break
	t.expect_true(s.notice.contains("拥堵"),"first real congestion offers patient flow")
	var target: Variant=s.get("notice_target")
	t.expect_true(target is Dictionary and not target.is_empty(),"congestion notice preserves its room/patient target")

func test_held_flow_uses_latest_paused_patient_projection(t: TestContext) -> void:
	# Break caught: a render-time flow closure replaces the newer pending clinical snapshot on release.
	var s:=_session()
	s.sim=Scenarios.create_sim(s.catalog,"benchmark_18","fast","standard")
	s.sim.advance_ticks(350)
	var panel:=SelectionPanel.new()
	panel.minimum_touch_target=72
	panel.select("patient_000001","patients")
	panel.present(s.sim.snapshot(),s.catalog)
	var held: Button=panel.controls.flow
	# Latch the press flag synchronously; the native companion verifies actual ScreenTouch ordering.
	held.toggle_mode=true
	held.set_pressed_no_signal(true)
	t.expect_true(held.button_pressed,"synchronous held flow fixture owns press")
	s.sim.advance_ticks(70)
	s.issue("set_paused",{"paused":true})
	var latest:=s.sim.snapshot()
	t.expect_equal(latest.patients.patient_000001.phase,"treatment_service","held flow fixture progresses into active treatment")
	panel.present(latest,s.catalog)
	held.pressed.emit()
	held.set_pressed_no_signal(false)
	panel._flush_pending()
	var copy:=_text(panel)
	t.expect_true(copy.contains("治疗中") and panel.find_child("Value_刺激耐受",true,false).text=="70","held flow reveals latest phase and diagnosed tolerance after paused release")
	t.expect_true(copy.contains("最长累计等待：治疗 3.9秒"),"held flow retains latest longest waiting stage")
	t.expect_true(panel.controls.back.custom_minimum_size.y>=72,"held flow return retains density touch target")
	panel.controls.back.pressed.emit()
	panel.controls.treatment_preview.pressed.emit()
	t.expect_true(panel.controls.apply_mode.disabled,"held flow cannot reenable apply after treatment starts")
	t.expect_equal(s.sim.snapshot(),latest,"held flow projection leaves paused authority unchanged")
	panel.free()
