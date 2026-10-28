extends SceneTree

var passed:=0
var failed:=0
var host: Node3D

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, copy: String) -> void:
	if ok: passed+=1
	else: failed+=1
	print(("LISTS PASS: " if ok else "LISTS FAIL: ")+copy)

func _labels(node: Node) -> Array[String]:
	var result: Array[String]=[]
	for label in node.find_children("*","Label",true,false): result.append(label.text)
	return result

func _run() -> void:
	root.size=Vector2i(1280,720)
	var catalog: ContentCatalog=ContentCatalog.load_checked("res://content").catalog
	# A different real content value detects a UI that copied the reference wage.
	catalog.staff.doctor.daily_wage=73
	host=load("res://main.gd").new()
	host.session=GameSession.new(catalog,"E:/CODEX/2026-10-19/医院原稿落地/reports/lists-%d/save" % Time.get_ticks_usec())
	root.add_child(host)
	host.set_process(false)
	host.hud.flow.controls.continue_game.pressed.emit()
	host.session.sim=Scenarios.create_sim(catalog,"benchmark_18","fast","standard")
	var h: HospitalHud=host.hud
	var panel: SelectionPanel=h.selection
	h.controls.staff.pressed.emit()
	for _i in range(4): await process_frame
	check(panel.action_footer.is_ancestor_of(panel.controls.recruit),"S08 recruitment remains in a fixed footer outside the scrolling employee list")
	check(panel.controls.has("recruit_header"),"S08 also offers the original inline recruitment entry beside its live count")
	if panel.controls.has("recruit_header"):
		var count: Node=panel.find_child("ListCount",true,false)
		check(count!=null and count.text=="在职 5 / 8 人" and absf(count.get_global_rect().get_center().y-panel.controls.recruit_header.get_global_rect().get_center().y)<10,"employee count and header recruitment occupy one row")
	var staff_labels:=_labels(panel.controls.staff_002)
	check("医生" in staff_labels and staff_labels.any(func(copy: String) -> bool: return copy.contains("每日 73 币")),"employee card exposes its profession tag and the wage from current content")
	var footer_rect: Rect2=panel.controls.recruit.get_global_rect()
	panel.get_parent().scroll_vertical=1000
	for _i in range(3): await process_frame
	check(panel.controls.recruit.get_global_rect().is_equal_approx(footer_rect),"scrolling employees cannot move the recruitment action")
	var before: Dictionary=host.session.sim.snapshot()
	panel.controls.recruit.pressed.emit()
	check(host.session.sim.snapshot()==before and h._left.visible,"recruitment opens the actual catalog without hiring or charging")
	panel.show_list("rooms")
	panel.present(before,catalog)
	check(panel.has_signal("build_catalog_requested") and panel.controls.has("new_build"),"S06 has a dedicated construction-catalog entry")
	if panel.has_signal("build_catalog_requested") and panel.controls.has("new_build"):
		var requests: Array[bool]=[]
		panel.connect("build_catalog_requested",func() -> void: requests.append(true))
		panel.controls.new_build.pressed.emit()
		check(requests.size()==1 and host.session.sim.snapshot()==before,"S06 construction entry requests the catalog without placing or charging a room")
	var room_labels:=_labels(panel.controls.room_003)
	check(room_labels.any(func(copy: String) -> bool: return copy.contains("声环梳理台")),"room cards identify the actual device separately from their room title")
	panel.select("room_003","rooms")
	var titles: Array[String]=[]
	panel.page_changed.connect(func(title: String) -> void: titles.append(title))
	panel.present(before,catalog)
	check(not titles.is_empty() and titles.back()=="声环治疗室","S07 emits the specific room title for the drawer header")
	var texts:=_labels(panel)
	check("声环梳理台" in texts and "当前运行" in texts and "岗位" in texts and "设备状态" in texts,"room details retain device identity and a separate live-running section")
	check(panel.controls.move.disabled and panel.controls.remove.disabled and not panel.controls.move.tooltip_text.is_empty(),"open-room editing is disabled with its actual required next step")
	panel.controls.status.pressed.emit()
	panel.present(host.session.sim.snapshot(),catalog)
	check(not panel.controls.move.disabled and not panel.controls.remove.disabled,"an empty closed room can still reach the real move and refund commands")
	var cash_before: int=host.session.sim.snapshot().cash
	panel.controls.remove.pressed.emit()
	check(not host.session.sim.snapshot().rooms.has("room_003") and host.session.sim.snapshot().cash==cash_before+750,"room demolition retains the authoritative 75 percent refund")
	host.session.sim=Scenarios.create_sim(catalog,"benchmark_18","fast","standard")
	host.session.sim.advance_ticks(1042)
	panel.select("room_004","rooms")
	panel.present(host.session.sim.snapshot(),catalog)
	check(_labels(panel).has("等待恢复交接"),"a held treatment device is identified from the real recovery handoff")
	panel.controls.status.pressed.emit()
	panel.present(host.session.sim.snapshot(),catalog)
	check(panel.controls.move.disabled and panel.controls.remove.disabled,"closing a busy room cannot make move or demolition appear available")
	h.controls.staff.pressed.emit()
	h.configure_display(Vector2(1920,1080),Vector2(1280,720),480,Rect2(0,0,1920,1080))
	for _i in range(5): await process_frame
	var scroll: ScrollContainer=panel.get_parent()
	footer_rect=panel.controls.recruit.get_global_rect()
	check(footer_rect.end.y<=720 and not scroll.get_global_rect().intersects(footer_rect),"short landscape keeps scrolling employee content separate from its reachable fixed footer")
	check(footer_rect.size.y>=96,"short landscape recruitment retains a scaled 48dp touch height")
	panel.show_list("rooms")
	panel.present(host.session.sim.snapshot(),catalog)
	for _i in range(5): await process_frame
	var contained:=true
	for key in panel.controls:
		if not key.begins_with("room_"): continue
		var card: Button=panel.controls[key]
		contained=contained and card.get_global_rect().encloses(card.get_child(0).get_global_rect())
	check(contained,"short landscape room cards grow around wrapped device names and status tags")
	print("LISTS RESULT: passed=%d failed=%d" % [passed,failed])
	host.free()
	await create_timer(0.24).timeout
	quit(1 if failed else 0)
