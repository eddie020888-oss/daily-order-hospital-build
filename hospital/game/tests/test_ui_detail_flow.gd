extends SceneTree

var passed:=0
var failed:=0
var host: Node3D

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	if value: passed+=1
	else: failed+=1
	print(("DETAIL PASS: " if value else "DETAIL FAIL: ")+label)

func _run() -> void:
	root.size=Vector2i(1280,720)
	var catalog: ContentCatalog=ContentCatalog.load_checked("res://content").catalog
	host=load("res://main.gd").new()
	host.session=GameSession.new(catalog,"E:/CODEX/2026-10-19/医院原稿落地/reports/detail-%d/save" % Time.get_ticks_usec())
	root.add_child(host)
	host.set_process(false)
	host.hud.flow.controls.continue_game.pressed.emit()
	host.session.sim=Scenarios.create_sim(catalog,"benchmark_18","fast","standard")
	host.session.sim.advance_ticks(200)
	for _i in range(4): await process_frame
	var id: String=host.session.sim.snapshot().patients.keys()[0]
	var h: HospitalHud=host.hud
	h.select_entity(id,"patients")
	for _i in range(4): await process_frame
	var panel: SelectionPanel=h.selection
	check(panel.controls.has("treatment_preview"),"patient detail offers the approved separate treatment preview")
	if not panel.controls.has("treatment_preview"):
		print("DETAIL RESULT: passed=%d failed=%d" % [passed,failed])
		quit(1)
		return
	var authority_before: Dictionary=host.session.sim.snapshot()
	check(panel.controls.has("flow"),"patient diagnostic flow remains reachable from the simplified detail")
	if panel.controls.has("flow"):
		panel.controls.flow.pressed.emit()
		for _i in range(4): await process_frame
		var record: Dictionary=authority_before.patients[id]
		var reception_wait: Label=panel.find_child("Value_接待",true,false)
		check(panel.selected_id==id and reception_wait!=null and is_equal_approx(reception_wait.text.trim_suffix("秒").to_float()*10.0,float(record.get("wait_by_stage",{}).get("reception",0))),"flow opens the same patient's actual accumulated reception wait")
		check(host.session.sim.snapshot()==authority_before,"opening diagnostic details does not change clinical state")
		panel.controls.back.pressed.emit()
		for _i in range(4): await process_frame
		check(panel.selected_id==id and panel.controls.has("treatment_preview"),"return from diagnostic flow restores the same patient's treatment preview entry")
	var action: Button=panel.controls.treatment_preview
	var text_width:=action.get_theme_font("font").get_string_size(action.text,HORIZONTAL_ALIGNMENT_LEFT,-1,action.get_theme_font_size("font_size")).x
	check(action.size.x>=text_width+24,"footer primary action displays its full label without clipping")
	var before:=action.get_global_rect()
	var scroll: ScrollContainer=panel.get_parent()
	scroll.scroll_vertical=1000
	for _i in range(4): await process_frame
	check(action.get_global_rect().is_equal_approx(before),"primary detail action stays visible while body scrolls")
	check(h.hits_gui(before.get_center()),"fixed footer consumes touch instead of selecting the world")
	action.pressed.emit()
	for _i in range(4): await process_frame
	check(panel.controls.has("fast") and panel.controls.has("gentle") and panel.controls.has("apply_mode"),"preview has two option cards and an explicit apply action")
	var original: String=host.session.sim.snapshot().patients[id].get("mode_override","")
	panel.controls.gentle.pressed.emit()
	check(host.session.sim.snapshot().patients[id].get("mode_override","")==original,"choosing a preview card does not alter authoritative patient mode")
	panel.controls.apply_mode.pressed.emit()
	for _i in range(4): await process_frame
	check(host.session.sim.snapshot().patients[id].mode_override=="gentle","apply sends the selected patient mode to the actual simulation")
	panel.controls.back.pressed.emit()
	for _i in range(4): await process_frame
	check(panel.controls.has("treatment_preview"),"back returns to the same patient detail")
	host.session.sim.advance_ticks(500)
	var locked_id:=""
	for key in host.session.sim.snapshot().patients:
		if host.session.sim.snapshot().patients[key].get("treatment_started",false):
			locked_id=key
			break
	check(locked_id!="","fixture reaches a real started treatment")
	if locked_id!="":
		h.select_entity(locked_id,"patients")
		panel.controls.treatment_preview.pressed.emit()
		for _i in range(4): await process_frame
		check(panel.controls.apply_mode.disabled,"started treatment remains locked in the new preview")
	h.configure_display(Vector2(1920,1080),Vector2(1280,720),480,Rect2(0,0,1920,1080))
	for _i in range(5): await process_frame
	check(panel.controls.back.get_global_rect().end.y<=720,"preview footer fits on a short phone landscape")
	check(scroll.get_global_rect().size.y>=160,"short phone preview leaves readable scrolling content")
	print("DETAIL RESULT: passed=%d failed=%d" % [passed,failed])
	host.free()
	await create_timer(0.12).timeout
	quit(1 if failed else 0)
