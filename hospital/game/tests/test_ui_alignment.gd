extends SceneTree

var failed := 0
var passed := 0
var host: Node3D

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	if value: passed += 1
	else: failed += 1
	print(("ALIGN PASS: " if value else "ALIGN FAIL: ") + label)

func _run() -> void:
	root.size = Vector2i(1280,720)
	var catalog: ContentCatalog = ContentCatalog.load_checked("res://content").catalog
	host = load("res://main.gd").new()
	host.session = GameSession.new(catalog,"E:/CODEX/2026-10-19/医院原稿落地/reports/alignment-%d/save" % Time.get_ticks_usec())
	root.add_child(host)
	host.set_process(false)
	host.hud.flow.controls.continue_game.pressed.emit()
	for _i in range(4): await process_frame
	var h: HospitalHud = host.hud
	check(not h._left.visible and not h._right.visible,"operating home leaves both drawers closed")
	check(h._top.size.x < 700,"status cards leave center of header clear")
	check(h._bottom.size.x < 650,"four-item navigation is compact and centered")
	check(h.controls.has("finance") and h.controls.has("settings"),"finance and settings have real entry points")
	if h.controls.has("settings"):
		check(h.controls.settings.get_global_rect().end.x <= 1262,"settings stays inside the right safe margin")
	_world_gap_gestures(h)
	h.controls.build.pressed.emit()
	for _i in range(3): await process_frame
	check(h._left.visible and not h._right.visible,"construction opens a single drawer")
	var grids := h.palette.find_children("*","GridContainer",true,false)
	check(grids.size()>0 and grids[0].columns==3,"wide A2 construction directory presents three real facility cards")
	var before_selection:Dictionary=h.session.sim.snapshot()
	h.controls.build_reception.pressed.emit()
	check(h.palette.selected_kind=="reception" and host.touch.free_build==null and host.touch.placement.is_empty(),"selecting a facility does not begin construction")
	check(h.session.sim.snapshot()==before_selection,"facility selection cannot spend cash or mutate the simulation")
	h.controls.facility_next.pressed.emit()
	check(h.palette.page==1 and h.controls.build_motion.visible and h.controls.build_motion.disabled,"paging reveals the actual locked next facilities")
	h.controls.facility_previous.pressed.emit()
	check(h.palette.page==0 and h.controls.build_reception.visible,"previous page returns to the first real facility group")
	check(h.palette.find_children("*","TextureRect",true,false).size() >= 6,"facility cards use approved reference thumbnails")
	h.session.restart()
	h.configure_display(Vector2(2560,1440),Vector2(1280,720),480,Rect2(80,0,2400,1440))
	check(preload("res://tests/native_a2_interactions.gd").begin_build(h,"reception"),"selected card plus explicit start opens construction")
	for _i in range(3): await process_frame
	check(not h._notice_panel.visible,"beginning construction clears nonblocking restart notice")
	check(not h._notice_panel.visible or not h._notice_panel.get_global_rect().intersects(h._preview_panel.get_global_rect()),"notice cannot overlap placement actions")
	check(h.controls.confirm.get_global_rect().size.y >= 72,"actual scaled confirm target remains at least 48dp")
	host.touch.cancel()
	h.configure_display(Vector2(1280,720),Vector2(1280,720),160,Rect2(0,0,1280,720))
	h.controls.hire_receptionist.pressed.emit()
	check(host.session.sim.snapshot().cash == 7900,"redesigned recruitment still changes authoritative cash")
	h.select_entity("staff_001","staff")
	for _i in range(3): await process_frame
	check(h._right.visible and not h._left.visible,"employee selection has one readable detail drawer")
	if h.controls.has("close_detail"):
		check(h.controls.close_detail.size.x <= 56,"drawer close control keeps compact icon width")
	check(h.selection.find_children("*","TextureRect",true,false).size() > 0,"employee detail has approved portrait")
	if h.controls.has("finance"):
		h.controls.finance.pressed.emit()
		for _i in range(3): await process_frame
		check(h._settlement_panel.visible,"finance opens actual ledger")
	await _held_patient_filter(catalog)
	await _compact_layout(h)
	print("ALIGN RESULT: passed=%d failed=%d" % [passed,failed])
	host.free()
	await create_timer(0.12).timeout
	quit(1 if failed else 0)

func _world_gap_gestures(h:HospitalHud) -> void:
	var gap:=Vector2(h._top_frame.get_global_rect().get_center().x,(h._top_frame.get_global_rect().end.y+h._dock.get_global_rect().position.y)*0.5)
	check(not h.hits_gui(gap),"the visible gap between A2 HUD frames accepts world input")
	var target:Vector3=host.world.camera_rig.target
	var zoom:float=host.world.camera_rig.zoom_size
	var touch_event:=InputEventScreenTouch.new()
	touch_event.index=0;touch_event.pressed=true;touch_event.position=gap
	host.touch.feed(touch_event)
	var drag:=InputEventScreenDrag.new()
	drag.index=0;drag.position=gap+Vector2(36,12)
	host.touch.feed(drag)
	touch_event.pressed=false;touch_event.position=drag.position
	host.touch.feed(touch_event)
	check(not host.world.camera_rig.target.is_equal_approx(target),"a single-finger drag in the actual HUD gap pans the hospital")
	for index in range(2):
		touch_event=InputEventScreenTouch.new()
		touch_event.index=index;touch_event.pressed=true;touch_event.position=gap+Vector2(-40 if index==0 else 40,0)
		host.touch.feed(touch_event)
	drag.index=1;drag.position=gap+Vector2(80,0)
	host.touch.feed(drag)
	for index in range(2):
		touch_event=InputEventScreenTouch.new()
		touch_event.index=index;touch_event.pressed=false;touch_event.position=gap+Vector2(-40 if index==0 else 80,0)
		host.touch.feed(touch_event)
	check(not is_equal_approx(host.world.camera_rig.zoom_size,zoom),"a two-finger gesture in the actual HUD gap zooms the hospital")
	host.world.camera_rig.target=target
	host.world.camera_rig.set_zoom(zoom)

func _held_patient_filter(catalog: ContentCatalog) -> void:
	var sim:=Scenarios.create_sim(catalog,"benchmark_18","fast","standard")
	sim.advance_ticks(600)
	var panel:=SelectionPanel.new()
	root.add_child(panel)
	panel.show_list("patients")
	panel.present(sim.snapshot(),catalog)
	var held: Button=panel.controls.filter_completed
	held.toggle_mode=true
	held.set_pressed_no_signal(true)
	sim.advance_ticks(400)
	panel.present(sim.snapshot(),catalog)
	held.pressed.emit()
	held.set_pressed_no_signal(false)
	held.button_up.emit()
	for _i in range(3): await process_frame
	check(panel._pending_snapshot.is_empty(),"paused filter release flushes the latest pending projection")
	check(panel.controls.has("patient_000001"),"completed filter shows actual completed patients after release")
	panel.free()

func _compact_layout(h: HospitalHud) -> void:
	h._close_drawers()
	h.configure_display(Vector2(1920,1080),Vector2(1280,720),480,Rect2(0,0,1920,1080))
	h.present()
	for _i in range(3): await process_frame
	check(not h._top.get_global_rect().intersects(h._actions.get_global_rect()),"640dp landscape header keeps status and actions separate")
	print("ALIGN HEADER: "+JSON.stringify({"status":str(h._top.get_global_rect()),"minimum":str(h._top.get_combined_minimum_size()),"actions":str(h._actions.get_global_rect()),"status_copy":[h._stats.text,h._completed.text,h._clock.text]}))
	h.session.notice="保存完成，可以继续建设。"
	h.present()
	h.controls.build.pressed.emit()
	for _i in range(3): await process_frame
	check(not h._notice_panel.visible,"opening catalog resolves nonblocking notice ownership")
	var scroll: ScrollContainer=h.palette.get_parent()
	print("ALIGN DRAWER: "+str(h._left.size)+" body="+str(scroll.size)+" header="+str(h.controls.close_build.size))
	check(scroll.size.y>=h.selection.minimum_touch_target*2,"short landscape drawer retains at least two touch rows of scrollable content")
	check(not h._dock.visible and not h._top_frame.visible and not h._bottom.visible and h.controls.close_build.is_visible_in_tree(),"construction takes the short-screen HUD space and retains its visible close action")
	h.controls.close_build.pressed.emit()
	check(h._bottom.visible,"closing short landscape drawer restores navigation")
	h.controls.build.pressed.emit()
	for _i in range(3): await process_frame
	var limit:=scroll.get_global_rect().end.x
	if scroll.get_v_scroll_bar().is_visible_in_tree(): limit-=scroll.get_v_scroll_bar().size.x*h.scale.x
	check(h.controls.build_diagnosis.get_global_rect().end.x<=limit+.1,"compact catalog keeps right card clear of its scrollbar")
	check(preload("res://tests/native_a2_interactions.gd").begin_build(h,"reception"),"compact catalog explicit start enters placement")
	h.session.notice="新的通知等待查看。"
	h.present()
	h.touch.choose_cell(121)
	for _i in range(3): await process_frame
	check(not (h._preview_panel.visible and h._notice_panel.visible and h._preview_panel.get_global_rect().intersects(h._notice_panel.get_global_rect())),"floor update cannot restore placement over an incoming notice")
	h.session.dismiss_notice()
	h.touch.cancel()
	h.configure_display(Vector2(1440,810),Vector2(1280,720),480,Rect2(0,0,1440,810))
	for _i in range(3): await process_frame
	check(h.controls.speed_toggle.visible and not h.controls.speed1.visible and not h.controls.speed2.visible,"paused resize updates narrow speed controls without a simulation refresh")
	h._close_drawers()
	h.controls.settings.pressed.emit()
	h.flow.controls.pause_help.pressed.emit()
	check(h._utility.visible and h._bottom.visible and Rect2(Vector2.ZERO,Vector2(1280,720)).encloses(h.controls.close_settings.get_global_rect()),"short settings has a reachable close action while preserving the console")
	h.controls.close_settings.pressed.emit()
	check(not h._utility.visible and h._bottom.visible,"closing short settings immediately restores navigation")
	h.session.notice="新设施解锁，可以建设。"
	h.session.notice_target={"group":"build"}
	h.present()
	h.controls.locate.pressed.emit()
	var immediate:Dictionary=_catalog_geometry(h)
	if not immediate.reachable:print("ALIGN UNLOCK IMMEDIATE: "+JSON.stringify(immediate))
	# The notice route opens and widens a previously hidden Container. Its
	# children receive their new rectangles on the deferred sort, before draw.
	# All other drawer geometry checks above already settle after navigation.
	for _i in range(3):await process_frame
	var settled:Dictionary=_catalog_geometry(h)
	if not settled.reachable:print("ALIGN UNLOCK SETTLED: "+JSON.stringify(settled))
	check(settled.reachable,"unlock catalog uses A2 construction space with a reachable close target")
	h.palette.get_parent().scroll_vertical=120
	h._show_recruitment()
	for _i in range(3): await process_frame
	check(h.palette.get_parent().scroll_vertical==0,"recruitment starts at its own first card after browsing facilities")

func _catalog_geometry(h:HospitalHud) -> Dictionary:
	var close:Button=h.controls.close_build
	var close_rect:Rect2=close.get_global_rect()
	var left_rect:Rect2=h._left.get_global_rect()
	var screen:Rect2=Rect2(Vector2.ZERO,Vector2(root.size))
	var hit:bool=h.hits_gui(close_rect.get_center())
	var reachable:bool=h._left.is_visible_in_tree() and not h._bottom.is_visible_in_tree() and not h._top_frame.is_visible_in_tree() and close.is_visible_in_tree() and left_rect.encloses(close_rect) and screen.encloses(close_rect) and hit
	return {"reachable":reachable,"left_visible":h._left.visible,"left_in_tree":h._left.is_visible_in_tree(),"left_rect":str(left_rect),"left_minimum":str(h._left.get_combined_minimum_size()),"close_visible":close.visible,"close_in_tree":close.is_visible_in_tree(),"close_rect":str(close_rect),"close_in_left":left_rect.encloses(close_rect),"close_in_screen":screen.encloses(close_rect),"hit_close":hit,"bottom_visible":h._bottom.visible,"top_frame_visible":h._top_frame.visible,"preview_visible":h._preview_panel.visible,"notice_visible":h._notice_panel.visible,"notice":h.session.notice,"notice_target":h.session.notice_target,"flow_page":h.flow.page,"flow_visible":h.flow.visible,"safe":str(h._safe),"scale":str(h.scale)}
