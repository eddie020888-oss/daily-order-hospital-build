extends SceneTree
var passed:=0
var failed:=0
func _initialize() -> void:_run.call_deferred()
func check(value:bool,copy:String) -> void:
	if value:passed+=1
	else:failed+=1
	print(("READ PASS: " if value else "READ FAIL: ")+copy)
func readable(control:Control) -> bool:
	if not control.is_visible_in_tree():return false
	var rect:=control.get_global_rect()
	if not Rect2(Vector2.ZERO,Vector2(root.size)).encloses(rect):return false
	var parent:=control.get_parent()
	while parent!=null:
		if parent is ScrollContainer and not parent.get_global_rect().encloses(rect):return false
		parent=parent.get_parent()
	return true
func has_readable_label(parent:Node,copy:String) -> bool:
	for node in parent.find_children("*","Label",true,false):
		if node.text==copy and readable(node):return true
	return false
func _run() -> void:
	root.size=Vector2i(1280,720)
	var catalog:ContentCatalog=ContentCatalog.load_checked("res://content").catalog
	var host:Node3D=load("res://main.gd").new()
	host.session=GameSession.new(catalog,"E:/CODEX/2026-10-19/医院UI再次纠偏/temp/readability-%d"%Time.get_ticks_usec())
	root.add_child(host);host.set_process(false);host.hud.flow.close()
	host.feedback.set_application_active(false);host.feedback._music_player.stop()
	var h:HospitalHud=host.hud
	h._begin_build("diagnosis");host.touch.choose_cell(100);host.touch.choose_cell(175)
	h.controls.confirm.pressed.emit();host.touch.choose_cell(174)
	h.controls.confirm.pressed.emit();host.touch.choose_cell(101);h.controls.confirm.pressed.emit()
	for _i in range(6):await process_frame
	check(host.touch.free_build.step==3,"fixture reaches real furniture selection")
	var scroll:ScrollContainer=h.placement_details.get_parent()
	for row in [[Vector2(1280,720),Vector2(1280,720),160],[Vector2(2560,1440),Vector2(1280,720),640]]:
		h.configure_display(row[0],row[1],row[2],Rect2(Vector2.ZERO,row[0]))
		for _i in range(6):await process_frame
		scroll.scroll_vertical=0
		for _i in range(4):await process_frame
		print("READ LAYOUT: dpi=",row[2]," panel=",h._preview_panel.get_global_rect()," scroll=",scroll.get_global_rect()," fixed=",h.placement_details.pinned_header.get_global_rect()," footer=",h._preview_footer.get_global_rect()," bin=",h.controls.furn_bin.get_global_rect()," body=",h.placement_details.size)
		for kind in ["plant","bench","cabinet","bin"]:
			var item:Button=h.controls["furn_"+kind]
			check(readable(item),"%d DPI can choose %s without scrolling away other items"%[row[2],kind])
			for label in item.find_children("*","Label",true,false):
				check(item.get_global_rect().encloses(label.get_global_rect()),"%d DPI %s card contains its full name and price"%[row[2],kind])
		scroll.scroll_vertical=1000
		for _i in range(4):await process_frame
		check(has_readable_label(h._preview_panel,"费用 880 币" if row[2]==640 else "880 币"),"%d DPI current version2 total remains readable while browsing furniture"%row[2])
		check(readable(h.controls.confirm),"%d DPI purchase action remains readable"%row[2])
		for key in ["cancel","build_back","confirm"]:
			check(not h._placement_badge.is_visible_in_tree() or not h._placement_badge.get_global_rect().intersects(h.controls[key].get_global_rect()),"%d DPI floating hint cannot cover %s"%[row[2],key])
		check(not h._placement_badge.is_visible_in_tree() or not h._placement_badge.get_global_rect().intersects(h._preview_panel.get_global_rect()),"%d DPI floating hint cannot cover the construction drawer"%row[2])
		if h._hint.visible:check(readable(h._hint),"construction hint stays inside the screen")
	var selected:StyleBoxFlat=h.controls.build.get_theme_stylebox("normal")
	check(selected.bg_color.is_equal_approx(HospitalA2Skin.CORAL) and not h.controls.build.is_visible_in_tree(),"construction retains its A2 primary state while the full builder owns HUD space")
	host.touch.cancel()
	var layout:={"width":5,"height":4,"door":{"side":"south","offset":0},"equipment":{"x":1,"y":0,"rotation":0},"furniture":[{"kind":"plant","x":4,"y":1,"rotation":0}]}
	var built:Dictionary=host.session.issue("build_room",{"kind":"diagnosis","origin_cell":100,"rotation":0,"layout":layout})
	check(built.ok,"refund fixture buys a real room with a 50-coin plant")
	if built.ok:
		var id:String=built.data.room_id
		host.session.issue("close_room",{"room_id":id})
		h._begin_layout_edit("diagnosis",id)
		for _i in range(3):h.controls.confirm.pressed.emit()
		host.touch.select_furniture("plant");host.touch.choose_cell(128)
		for _i in range(4):await process_frame
		check(has_readable_label(h._preview_panel,"退回 37 币"),"short phone clearly labels the real 75-percent furniture refund")
		var debt:Dictionary=host.session.sim.snapshot().duplicate(true);debt.cash=-1000
		h._present_placement_details(debt,h._proposal(),host.session.preview(h._proposal()))
		for _i in range(4):await process_frame
		check(not has_readable_label(h._preview_panel,"现金不足，请缩小房间或减少家具。") and not h.controls.confirm.disabled,"operating debt cannot falsely block or warn against a refund edit")
		host.touch.choose_cell(128)
		h._present_placement_details(debt,h._proposal(),host.session.preview(h._proposal()))
		for _i in range(4):await process_frame
		check(not has_readable_label(h._preview_panel,"现金不足，请缩小房间或减少家具。") and not h.controls.confirm.disabled,"operating debt cannot falsely block or warn against a zero-cost edit")
		host.touch.cancel()
	h._begin_build("diagnosis");host.touch.choose_cell(106);host.touch.choose_cell(181)
	h.controls.confirm.pressed.emit();host.touch.choose_cell(180)
	h.controls.confirm.pressed.emit();host.touch.choose_cell(107);h.controls.confirm.pressed.emit()
	var before:Dictionary=host.session.sim.snapshot()
	var projection:Dictionary=before.duplicate(true);projection.cash=879
	h._present_placement_details(projection,h._proposal(),host.session.preview(h._proposal()))
	for _i in range(4):await process_frame
	check(h.controls.confirm.disabled,"insufficient-cash projection blocks purchase")
	check(has_readable_label(h._preview_panel,"现金不足，请缩小房间或减少家具。"),"short phone shows the reason for its disabled purchase action")
	check(host.session.sim.snapshot()==before,"feedback projection cannot alter real funds or room state")
	host.touch.cancel();host.free()
	await process_frame;await process_frame
	print("READABILITY RESULT: passed=%d failed=%d"%[passed,failed]);quit(1 if failed else 0)
