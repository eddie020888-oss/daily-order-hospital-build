extends SceneTree

var failed:=false
var output_dir: String
var host: Node3D

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("output="): output_dir=argument.trim_prefix("output=")
	_run.call_deferred()

func _check(value: bool, label: String) -> void:
	print(("HELD FLOW PASS: " if value else "HELD FLOW FAIL: ")+label)
	failed=failed or not value

func _finger(down: bool, point: Vector2) -> void:
	var event:=InputEventScreenTouch.new()
	event.index=0
	event.pressed=down
	event.position=point
	Input.parse_input_event(event)

func _copy(node: Node) -> String:
	var text: String=node.text if node is Label else ""
	for child in node.get_children(): text+="\n"+_copy(child)
	return text

func _run() -> void:
	if DisplayServer.get_name()=="headless" or not output_dir.replace("\\","/").begins_with("E:/CODEX/"):
		quit(1)
		return
	root.size=Vector2i(1280,720)
	var catalog: ContentCatalog=ContentCatalog.load_checked("res://content").catalog
	var session:=GameSession.new(catalog,output_dir.path_join("isolated-save"))
	session.sim=Scenarios.create_sim(catalog,"benchmark_18","fast","standard")
	session.sim.advance_ticks(350)
	host=load("res://main.gd").new()
	host.session=session
	root.add_child(host)
	host.set_process(false)
	host.hud.flow.controls.continue_game.pressed.emit()
	host.hud.select_entity("patient_000001","patients")
	for _i in range(4): await process_frame
	var panel: SelectionPanel=host.hud.selection
	var held: Button=panel.controls.flow
	var point:=held.get_global_rect().get_center()
	_check(host.hud._right.get_global_rect().has_point(point),"flow touch is visibly inside actual Main panel")
	_finger(true,point)
	await process_frame
	_check(held.button_pressed,"parsed ScreenTouch owns flow button")
	session.sim.advance_ticks(70)
	session.issue("set_paused",{"paused":true})
	var latest:=session.sim.snapshot()
	_check(latest.paused and latest.patients.patient_000001.phase=="treatment_service","real patient progresses diagnosis350 to treatment420 then pauses while held")
	_check(is_instance_valid(held) and held.is_inside_tree() and held.button_pressed,"held flow survives clinical refresh")
	_finger(false,point)
	for _i in range(4): await process_frame
	var copy:=_copy(panel)
	print("HELD FLOW TEXT: "+copy)
	_check(copy.contains("治疗中") and not copy.contains("诊断中"),"release shows latest treatment phase without another simulation tick")
	_check(copy.contains("耐受 70") and not copy.contains("诊断完成后显示"),"release exposes diagnosed tolerance")
	_check(copy.contains("最长累计等待：治疗 3.9秒"),"release shows latest longest waiting stage")
	_check(panel.controls.fast.disabled and panel.controls.gentle.disabled,"release keeps both individual modes locked during active treatment")
	_check(session.sim.snapshot()==latest,"flow toggle never changes paused authoritative state")
	await RenderingServer.frame_post_draw
	var image_path:=output_dir.path_join("held-flow-paused-1280x720.png")
	_check(not FileAccess.file_exists(image_path) and root.get_texture().get_image().save_png(image_path)==OK,"preserve new actual rendered paused-flow capture")
	var metadata:=FileAccess.open(image_path+".json",FileAccess.WRITE)
	metadata.store_string(JSON.stringify({"snapshot":latest,"expanded_text_after_release":copy,"renderer":RenderingServer.get_current_rendering_method(),"adapter":RenderingServer.get_video_adapter_name()},"  "))
	metadata.close()
	# A subsequent collapse remains responsive while the simulation stays paused.
	var flow: Button=panel.controls.flow
	var ancestor: Node=flow.get_parent()
	while ancestor!=null:
		if ancestor is ScrollContainer:
			ancestor.ensure_control_visible(flow)
			break
		ancestor=ancestor.get_parent()
	for _i in range(3): await process_frame
	point=flow.get_global_rect().get_center()
	_finger(true,point)
	await process_frame
	_finger(false,point)
	for _i in range(3): await process_frame
	_check(not _copy(panel).contains("最长累计等待") and panel.controls.fast.disabled,"second parsed flow tap collapses current paused projection without unlocking modes")
	print("HELD FLOW RESULT: "+("FAILED" if failed else "OK"))
	quit(1 if failed else 0)
