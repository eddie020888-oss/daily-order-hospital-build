extends SceneTree

var failed:=false
var output_dir: String
var host: Node3D

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("output="): output_dir=argument.trim_prefix("output=")
	_run.call_deferred()

func _check(value: bool, label: String) -> void:
	print(("GUI PASS: " if value else "GUI FAIL: ")+label)
	failed=failed or not value

func _finger(pressed: bool, point: Vector2) -> void:
	var event:=InputEventScreenTouch.new()
	event.index=0
	event.pressed=pressed
	event.position=point
	Input.parse_input_event(event)

func _run() -> void:
	if output_dir=="" or DisplayServer.get_name()=="headless":
		quit(1)
		return
	var catalog: ContentCatalog=ContentCatalog.load_checked("res://content").catalog
	var session:=GameSession.new(catalog,output_dir.path_join("isolated-save"))
	host=load("res://main.gd").new()
	host.session=session
	root.add_child(host)
	host.set_process(false)
	host.hud.flow.controls.continue_game.pressed.emit()
	for _i in range(4): await process_frame
	var hud: HospitalHud=host.hud
	var start: Vector2=hud.controls.pause.get_global_rect().get_center()
	_finger(true,start)
	await process_frame
	_finger(false,start)
	await process_frame
	_check(not session.sim.snapshot().paused,"actual ScreenTouch tap routes through Main and GUI to start clinic")
	# Set up a real paid room through the existing UI command path.
	_check(not preload("res://tests/native_a2_interactions.gd").prepare_build(hud,"echo",104).is_empty(),"A2 explicit start and all four real stages prepare a legal treatment room")
	hud.controls.confirm.pressed.emit()
	hud.select_entity("room_001","rooms")
	hud.controls.speed1.pressed.emit()
	session.advance_wall_time(900000)
	for _i in range(4): await process_frame
	var button: Button=hud.selection.controls.mode_gentle
	var point:=button.get_global_rect().get_center()
	_check(hud._right.get_global_rect().has_point(point),"tested action is visibly inside selection panel")
	_finger(true,point)
	await process_frame
	_check(button.button_pressed,"real GUI owns held touch")
	session.advance_wall_time(100000)
	await process_frame
	_check(is_instance_valid(button) and button.is_inside_tree(),"held action survives tick refresh")
	_finger(false,point)
	for _i in range(4): await process_frame
	_check(session.sim.snapshot().rooms.room_001.mode=="gentle","release after100ms tick executes mode command exactly once")
	_check(session.sim.snapshot().cash==7000,"GUI action never duplicates room charge")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output_dir.path_join("gui-dispatch.png"))
	print("GUI DISPATCH RESULT: "+("FAILED" if failed else "OK"))
	quit(1 if failed else 0)
