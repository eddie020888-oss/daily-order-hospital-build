extends SceneTree

var failed:=0
var passed:=0
var catalog: ContentCatalog
var host: Node3D

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, copy: String) -> void:
	if ok: passed+=1
	else: failed+=1
	print(("ORIGINAL PASS: " if ok else "ORIGINAL FAIL: ")+copy)

func _host(suffix: String) -> Node3D:
	var view: Node3D=load("res://main.gd").new()
	view.session=GameSession.new(catalog,"E:/CODEX/2026-10-19/医院原稿落地/reports/structure-%d-%s" % [Time.get_ticks_usec(),suffix])
	root.add_child(view)
	view.set_process(false)
	view.hud.flow.controls.continue_game.pressed.emit()
	return view

func _run() -> void:
	root.size=Vector2i(1280,720)
	catalog=ContentCatalog.load_checked("res://content").catalog
	host=_host("placement")
	await _placement()
	await _assignment()
	_congestion_entry()
	await _operations()
	print("ORIGINAL RESULT: passed=%d failed=%d" % [passed,failed])
	host.free()
	host=null
	# The audio mixer releases stopped playback after the main thread destroys its nodes.
	await create_timer(0.24).timeout
	quit(1 if failed else 0)

func _placement() -> void:
	# Real four-step construction must keep unpaid quotes and pinned actions.
	var h:HospitalHud=host.hud
	var driver:Script=preload("res://tests/native_a2_interactions.gd")
	var proposal:Dictionary=driver.prepare_build(h,"recovery",121)
	check(not proposal.is_empty(),"A2 selection and explicit start complete the real recovery draft")
	var details:Variant=h.get("placement_details")
	check(details!=null,"S05 has a dedicated complete placement detail view")
	if details==null or proposal.is_empty():host.touch.cancel();return
	for _i in range(4):await process_frame
	check(details.values.cost.text=="600 币" and details.values.balance.text=="7400 币","placement details show real unpaid construction cost and resulting cash")
	check(host.session.sim.snapshot().cash==8000 and host.session.sim.snapshot().rooms.is_empty(),"placement projection cannot spend or build before explicit confirmation")
	check(h._preview_panel.position.x<640 and h._preview_panel.size.y>400 and not h._dock.visible and not h._top_frame.visible,"A2 free builder uses its full-height left sheet with separate visible tools")
	h.controls.build_back.pressed.emit()
	h.controls.rotate.pressed.emit()
	check(details.values.rotation.text=="90°","rotation updates actual equipment direction in the detail view")
	for _i in range(3):h.controls.rotate.pressed.emit()
	h.controls.confirm.pressed.emit()
	var action:Rect2=h.controls.confirm.get_global_rect()
	details.get_parent().scroll_vertical=1000
	for _i in range(4):await process_frame
	check(h.controls.confirm.get_global_rect().is_equal_approx(action),"construction confirmation remains fixed while its detail body scrolls")
	h.configure_display(Vector2(1920,1080),Vector2(1280,720),480,Rect2(0,0,1920,1080))
	for _i in range(4):await process_frame
	check(h.controls.confirm.get_global_rect().end.y<=720 and h.controls.cancel.get_global_rect().end.y<=720,"short landscape retains both construction footer actions")
	check(not h.controls.rotate.get_global_rect().intersects(h.controls.confirm.get_global_rect()),"short landscape rotation tool cannot cover the confirmation footer")
	check(h.hits_gui(h.controls.confirm.get_global_rect().get_center()),"placement footer owns its physical touch area")
	h.controls.reposition.pressed.emit()
	check(host.touch.placement.origin_cell==-1 and h.controls.confirm.disabled,"reposition returns to drawing bounds and requires a fresh legal rectangle")
	host.world.focus_cell(proposal.origin_cell)
	for _i in range(3):await process_frame
	var visible_point:Vector2=host.world.camera_rig.camera.unproject_position(HospitalWorld.cell_position(proposal.origin_cell))
	check(not h.hits_gui(visible_point),"short landscape offers a genuine buildable floor point outside the builder")
	for down in [true,false]:
		var floor_touch:=InputEventScreenTouch.new()
		floor_touch.index=0;floor_touch.pressed=down;floor_touch.position=visible_point
		Input.parse_input_event(floor_touch)
		await process_frame
	check(host.touch.placement.origin_cell==proposal.origin_cell and h.controls.confirm.disabled,"real floor touch selects the first corner without approving an undersized room")
	h.controls.cancel.pressed.emit()
	check(host.touch.placement.is_empty() and not h._preview_panel.visible and not h._placement_tools.visible and h._dock.visible and h._top_frame.visible,"cancel restores A2 HUD and clears both tools and authoritative draft")
	h.configure_display(Vector2(1280,720),Vector2(1280,720),160,Rect2(0,0,1280,720))
	check(not driver.prepare_build(h,"recovery",121).is_empty(),"second recovery draft reaches the explicit purchase action")
	h.controls.confirm.pressed.emit();h.controls.confirm.pressed.emit()
	check(host.session.sim.snapshot().cash==7400 and host.session.sim.snapshot().rooms.size()==1,"final double confirmation submits the real build and charge exactly once")
	check(not driver.prepare_build(h,"reception",100).is_empty(),"separate reception proposal is ready without purchasing")
	host.session.issue("hire_staff",{"role":"doctor"})
	check(details.values.balance.text=="6700 币","placement balance refreshes when another real command changes available cash")
	var finger:=InputEventScreenTouch.new()
	finger.index=0;finger.pressed=true;finger.position=Vector2(700,350)
	host.touch.feed(finger)
	h.controls.cancel.pressed.emit()
	h.controls.patients.pressed.emit()
	var target:Vector3=host.world.camera_rig.target
	var drag:=InputEventScreenDrag.new()
	drag.index=0;drag.position=Vector2(800,400)
	host.touch.feed(drag)
	check(host.touch.placement.is_empty() and not h._preview_panel.visible and host.world.camera_rig.target.is_equal_approx(target),"cancel then visible navigation revokes the old placement gesture and preview")

func _assignment() -> void:
	# Break caught: assignment choices are merged into details or include wrong-role rooms.
	var view:=_host("assignment")
	view.session.issue("build_room",{"kind":"reception","origin_cell":121,"rotation":0})
	view.session.issue("build_room",{"kind":"diagnosis","origin_cell":100,"rotation":0})
	view.session.issue("hire_staff",{"role":"doctor"})
	var h: HospitalHud=view.hud
	h.select_entity("staff_001","staff")
	check(h.selection.controls.has("choose_assignment"),"S11 has an explicit entry from employee details")
	if not h.selection.controls.has("choose_assignment"): view.free(); return
	h.selection.controls.choose_assignment.pressed.emit()
	check(h._right_title.text=="派往岗位" and h.selection.controls.has("assign_room_002") and not h.selection.controls.has("assign_room_001"),"independent assignment view contains only real profession-matching room cards")
	h.selection.controls.assign_room_002.pressed.emit()
	check(view.session.sim.snapshot().staff.staff_001.room_id=="room_002","room card sends the real employee assignment command")
	h.selection.controls.back.pressed.emit()
	check(h.selection.selected_id=="staff_001" and h.selection.controls.has("choose_assignment"),"assignment returns to the same employee details")
	view.session.sim=Scenarios.create_sim(catalog,"benchmark_18","fast","standard")
	view.session.sim.advance_ticks(418)
	h.select_entity("staff_003","staff")
	h.selection.controls.choose_assignment.pressed.emit()
	var before: Dictionary=view.session.sim.snapshot()
	check(h.selection.controls.unassign.disabled and h.selection.controls.assign_room_003.disabled,"busy assignment disables withdrawal and matching destination cards before any rejected command")
	check(h.selection.controls.assign_room_003.tooltip_text.contains("剩余") or h.selection.controls.assign_room_003.tooltip_text.contains("交接"),"disabled assignment exposes its actual remaining service or handoff reason")
	for _i in range(3): await process_frame
	var button: Button=h.selection.controls.unassign
	for down in [true,false]:
		var event:=InputEventScreenTouch.new()
		event.index=0; event.pressed=down; event.position=button.get_global_rect().get_center()
		Input.parse_input_event(event)
		await process_frame
	check(view.session.sim.snapshot()==before,"real touch on disabled withdrawal cannot alter the started service")
	view.free()

func _operations() -> void:
	# Break caught: global five-stage counts are replaced by one patient's cumulative waiting table.
	var view:=_host("operations")
	view.session.sim=Scenarios.create_sim(catalog,"benchmark_18","fast","standard")
	view.session.sim.advance_ticks(200)
	var h: HospitalHud=view.hud
	h.controls.patients.pressed.emit()
	check(h.selection.controls.has("hospital_flow"),"S15 has a global flow entry from the patient list")
	if not h.selection.controls.has("hospital_flow"): view.free(); return
	h.selection.controls.hospital_flow.pressed.emit()
	var operations: Variant=h.get("operations")
	check(operations!=null and operations.view=="flow","patient list opens a separate hospital flow overview")
	if operations==null: view.free(); return
	var before: Dictionary=view.session.sim.snapshot()
	var first_counts:Dictionary={}
	for stage in HospitalOperationsPanel.STAGES:first_counts[stage[0]]=0
	first_counts.reception=1
	if operations.summary.stage_counts!=first_counts:print("ORIGINAL FIRST FLOW STATE: "+JSON.stringify(_flow_state(before,operations.summary,first_counts)))
	check(operations.summary.stage_counts==first_counts,"global overview projects the first actual arrival into one mutually exclusive stage across all eight supported stages")
	check(view.session.sim.snapshot()==before,"global projection cannot mutate patient or accounting authority")
	for _i in range(4): await process_frame
	_check_flow_containment(operations,"normal")
	operations.controls.stage_diagnosis.pressed.emit()
	check(not h.selection.controls.has("patient_000001"),"diagnosis stage card excludes an actual reception patient")
	h.selection.controls.hospital_flow.pressed.emit()
	operations.controls.stage_reception.pressed.emit()
	check(h.selection.controls.has("patient_000001"),"reception stage card includes the actual reception patient")
	check(h.selection._patient_stage=="reception" and not SelectionPanel.patient_information(before.patients.patient_000001,before,catalog).contains("耐受 70"),"stage drilldown preserves the undisclosed tolerance boundary")
	h.selection.controls.hospital_flow.pressed.emit()
	operations.controls.patients.pressed.emit()
	h.select_entity("patient_000001","patients")
	h.selection.controls.flow.pressed.emit()
	check(h.selection.selected_id=="patient_000001" and h.selection.controls.has("back"),"the individual patient's waiting flow remains independently reachable")
	var found:=false
	for _i in range(2500):
		view.session.sim.advance_ticks(1)
		for patient in view.session.sim.snapshot().patients.values():
			if patient.phase=="waiting_recovery" and patient.wait_reason=="recovery_full": found=true; break
		if found: break
	check(found,"real clinical fixture reaches recovery handoff congestion")
	view.session.advance_wall_time(1)
	h.controls.locate.pressed.emit()
	check(operations.view=="congestion" and h._operations_title.text=="恢复区拥堵","contextual congestion notice opens the independent original S20 view")
	check(operations.summary.blocked_devices==1 and operations.summary.seats.total==1 and operations.summary.seats.occupied==1,"congestion headline uses the single actual held device and occupied recovery seat")
	for _i in range(4): await process_frame
	check(operations._labels.seats.size.x>=180 and operations._labels.seats.size.y<=70,"S20 recovery capacity tag retains a readable allocated width and bounded wrapping")
	h.controls.patients.pressed.emit()
	h.selection.controls.hospital_flow.pressed.emit()
	operations.get_parent().scroll_vertical=250
	operations.controls.stage_recovery.pressed.emit()
	for _i in range(4): await process_frame
	check(operations.get_parent().scroll_vertical==0,"switching a scrolled global flow to congestion resets the new page to its headline")
	before=view.session.sim.snapshot()
	operations.controls.auto_route.pressed.emit()
	check(view.session.sim.snapshot().auto_route and view.session.sim.snapshot().cash==before.cash,"congestion routing improvement submits the real setting without charging")
	operations.controls.recovery.pressed.emit()
	check(h.selection.selected_id=="room_006" and h.selection.controls.has("upgrade"),"view recovery reaches the actual congested room's real upgrade action")
	h.selection.controls.upgrade.pressed.emit()
	check(view.session.sim.snapshot().rooms.room_006.upgraded and view.session.sim.snapshot().cash==before.cash-400,"recovery improvement performs the actual paid second-seat upgrade")
	h.controls.patients.pressed.emit()
	h.selection.controls.hospital_flow.pressed.emit()
	for _i in range(3): await process_frame
	h.configure_display(Vector2(1920,1080),Vector2(1280,720),480,Rect2(0,0,1920,1080))
	for _i in range(4): await process_frame
	check(operations.controls.recovery.get_global_rect().end.y<=720 and operations.controls.patients.get_global_rect().end.y<=720,"short landscape global overview keeps its fixed action footer reachable")
	_check_flow_containment(operations,"short")
	check(h.controls.patients.is_visible_in_tree() and h.controls.close_operations.is_visible_in_tree() and not h._operations_drawer.get_global_rect().intersects(h._dock.get_global_rect()),"short operations drawer preserves A2 navigation and its separate visible close entry")
	await _tap_ui(h.controls.close_operations)
	check(h.controls.patients.is_visible_in_tree(),"closing the short drawer restores the actual patient navigation")
	await _tap_ui(h.controls.patients)
	await _tap_ui(h.selection.controls.hospital_flow)
	check(h._operations_drawer.visible and operations.view=="flow","short landscape global flow is reachable through visible close navigation and list actions")
	view.session.sim.advance_ticks(9000)
	h.controls.patients.pressed.emit()
	h.selection.controls.hospital_flow.pressed.emit()
	var finished_counts:Dictionary={}
	for stage in HospitalOperationsPanel.STAGES:finished_counts[stage[0]]=0
	if operations.summary.stage_counts!=finished_counts:print("ORIGINAL FINISHED FLOW STATE: "+JSON.stringify(_flow_state(view.session.sim.snapshot(),operations.summary,finished_counts)))
	check(operations.summary.stage_counts==finished_counts,"completed and abandoned patients are absent from every supported live flow stage")
	view.free()

func _check_flow_containment(operations:HospitalOperationsPanel,layout:String) -> void:
	var inside:=true
	var count_width:=true
	var stage_visibility:=true
	check(operations.is_visible_in_tree(),"S15 "+layout+" containment checks the actual visible flow page")
	for stage in HospitalOperationsPanel.STAGES:
		var card:Button=operations.controls["stage_"+stage[0]]
		var clinical:bool=stage[0] in SelectionPanel.CARE_STAGES
		var expected_visible:bool=not clinical or operations._snapshot.level_id=="clinical_02"
		stage_visibility=stage_visibility and card.visible==expected_visible
		# The three clinical-only cards have no drawn rectangle in level01.
		# They are asserted hidden above, rather than treated as overflowing UI.
		if not card.is_visible_in_tree():continue
		var row:HBoxContainer=card.get_child(0)
		var badge:Control=row.get_child(0)
		var count:Control=row.get_child(2)
		var card_rect:Rect2=card.get_global_rect()
		var contains:bool=card_rect.encloses(badge.get_global_rect()) and card_rect.encloses(count.get_global_rect())
		if not contains:
			print("ORIGINAL FLOW CARD GEOMETRY: "+JSON.stringify({"layout":layout,"stage":stage[0],"visible":card.visible,"in_tree":card.is_visible_in_tree(),"card_rect":str(card_rect),"card_minimum":str(card.get_combined_minimum_size()),"row_rect":str(row.get_global_rect()),"row_minimum":str(row.get_combined_minimum_size()),"badge_rect":str(badge.get_global_rect()),"count_rect":str(count.get_global_rect()),"count_minimum":str(count.get_combined_minimum_size()),"body_rect":str(operations.get_global_rect()),"scroll_rect":str(operations.get_parent().get_global_rect()),"level_id":operations._snapshot.level_id}))
		inside=inside and contains
		count_width=count_width and count.size.x>=24
	check(stage_visibility,"S15 "+layout+" clinical-only stages are visible only in their supported level")
	check(inside,"S15 "+layout+" visible stage badges and count columns stay inside their own card rectangles")
	check(count_width,"S15 "+layout+" visible count columns reserve readable width for both number and unit")

func _flow_state(snapshot:Dictionary,summary:Dictionary,expected:Dictionary) -> Dictionary:
	var patients:Dictionary={}
	for id in snapshot.patients:
		var patient:Dictionary=snapshot.patients[id]
		patients[id]={"phase":patient.phase,"stage":patient.stage,"outcome":patient.get("outcome",""),"cell":patient.get("cell",-1)}
	return {"tick":snapshot.tick,"level_id":snapshot.level_id,"challenge":snapshot.challenge,"paused":snapshot.paused,"expected_counts":expected,"actual_counts":summary.stage_counts,"dispositions":summary.dispositions,"patients":patients}

func _tap_ui(button: Button) -> void:
	for _i in range(3): await process_frame
	for down in [true,false]:
		var event:=InputEventScreenTouch.new()
		event.index=0; event.pressed=down; event.position=button.get_global_rect().get_center()
		Input.parse_input_event(event)
		await process_frame
	for _i in range(3): await process_frame

func _congestion_entry() -> void:
	# Break caught: a recovery bottleneck notice opens an unrelated single-patient table.
	var view:=_host("congestion-entry")
	view.session.sim=Scenarios.create_sim(catalog,"benchmark_18","fast","standard")
	var found:=false
	for _i in range(2500):
		view.session.sim.advance_ticks(1)
		for patient in view.session.sim.snapshot().patients.values():
			if patient.phase=="waiting_recovery" and patient.wait_reason=="recovery_full": found=true; break
		if found: break
	check(found,"S20 fixture reaches a real recovery-full handoff")
	view.session.advance_wall_time(1)
	view.hud.controls.locate.pressed.emit()
	var page: Variant=view.hud.get("operations")
	check(page!=null and page.view=="congestion","S20 recovery notice opens its own actionable recovery congestion page")
	view.free()
