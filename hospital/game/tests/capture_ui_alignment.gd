extends SceneTree

var output_dir := ""
var host: Node3D
var failed := 0
var captures: Array = []

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("output="): output_dir=arg.trim_prefix("output=")
	_run.call_deferred()

func _check(value: bool, label: String) -> void:
	if not value: failed+=1
	print(("GALLERY PASS: " if value else "GALLERY FAIL: ")+label)

func _tap(button: Button) -> void:
	var parent: Node=button.get_parent()
	while parent!=null:
		if parent is ScrollContainer:
			parent.ensure_control_visible(button)
			break
		parent=parent.get_parent()
	for _i in range(3): await process_frame
	_check(button.is_visible_in_tree(),"tested button is visible")
	var point:=button.get_global_rect().get_center()
	for down in [true,false]:
		var event:=InputEventScreenTouch.new()
		event.index=0
		event.pressed=down
		event.position=point
		Input.parse_input_event(event)
		await process_frame
	for _i in range(3): await process_frame

func _capture(name: String) -> void:
	for _i in range(4):
		await process_frame
		await RenderingServer.frame_post_draw
	var path:=output_dir.path_join(name+".png")
	_check(not FileAccess.file_exists(path),"preserve existing capture "+name)
	_check(root.get_texture().get_image().save_png(path)==OK,"render "+name)
	var snapshot: Dictionary=host.session.sim.snapshot()
	var metadata:={"snapshot":snapshot,"display":DisplayServer.get_name(),"renderer":RenderingServer.get_current_rendering_method(),"status_rect":str(host.hud._top.get_global_rect()),"actions_rect":str(host.hud._actions.get_global_rect()),"left_drawer_visible":host.hud._left.visible,"right_drawer_visible":host.hud._right.visible}
	metadata.camera={"target":str(host.world.camera_rig.target),"orthographic_size":host.world.camera_rig.zoom_size,"transform":str(host.world.camera_rig.camera.global_transform)}
	metadata.presentation_sha256={}
	for source in ["res://project.godot","res://presentation/hospital_world.gd","res://presentation/hospital_interior_art.gd","res://presentation/room_view.gd","res://presentation/actor_view.gd","res://presentation/scene_art_library.gd","res://ui/hospital_hud.gd","res://ui/hospital_settings_panel.gd","res://ui/selection_panel.gd","res://assets/models/characters-v2/doctor-02.glb","res://assets/models/characters-v2/doctor-02-portrait.png","res://assets/models/interior-v2/bench.glb","res://assets/models/interior-v2/plant.glb"]:
		metadata.presentation_sha256[source]=FileAccess.get_sha256(source)
	var file:=FileAccess.open(path+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify(metadata,"  "))
	file.close()
	captures.append(path)
	print("GALLERY CAPTURE: "+path)

func _floor_cell(cell:int) -> void:
	host.world.focus_cell(cell)
	for _i in range(3):await process_frame
	var point:Vector2=host.world.camera_rig.camera.unproject_position(HospitalWorld.cell_position(cell))
	_check(not host.hud.hits_gui(point),"real construction cell is outside visible GUI")
	for down in [true,false]:
		var event:=InputEventScreenTouch.new()
		event.index=0;event.pressed=down;event.position=point
		Input.parse_input_event(event)
		await process_frame

func _build(kind:String,cell:int) -> void:
	var proposal:Dictionary=await preload("res://tests/native_a2_interactions.gd").prepare_native(host.hud,kind,cell,_tap,_floor_cell)
	_check(not proposal.is_empty(),"A2 card/start and all four real stages prepare "+kind)
	if proposal.is_empty():return
	await _tap(host.hud.controls.confirm)
	_check(host.touch.placement.is_empty(),"final explicit purchase commits "+kind)

func _assign(id: String, room_id: String) -> void:
	await _tap(host.hud.controls.staff)
	await _tap(host.hud.selection.controls[id])
	await _tap(host.hud.selection.controls.choose_assignment)
	await _tap(host.hud.selection.controls["assign_"+room_id])

func _run() -> void:
	if DisplayServer.get_name()=="headless" or not output_dir.begins_with("E:/CODEX/"):
		quit(1)
		return
	root.size=Vector2i(1280,720)
	DirAccess.make_dir_recursive_absolute(output_dir)
	var catalog: ContentCatalog=ContentCatalog.load_checked("res://content").catalog
	host=load("res://main.gd").new()
	host.session=GameSession.new(catalog,output_dir.path_join("isolated-save"))
	root.add_child(host)
	host.set_process(false)
	host.hud.flow.controls.continue_game.pressed.emit()
	for _i in range(4): await process_frame
	await _capture("01-operating-home")
	await _tap(host.hud.controls.build)
	await _capture("02-facility-catalog")
	await _tap(host.hud.controls.close_build)
	for row in [["reception",121],["diagnosis",100],["echo",104],["recovery",140]]:
		await _build(row[0],row[1])
	await _tap(host.hud.controls.staff)
	await _tap(host.hud.selection.controls.recruit)
	await _capture("03-recruitment")
	for role in ["receptionist","doctor","technician"]:
		await _tap(host.hud.controls["hire_"+role])
	await _tap(host.hud.controls.staff)
	await _capture("04-staff-list")
	await _tap(host.hud.selection.controls.staff_002)
	await _capture("05-doctor-detail")
	for row in [["staff_001","room_001"],["staff_002","room_002"],["staff_003","room_003"]]:
		await _assign(row[0],row[1])
	await _tap(host.hud.controls.close_detail)
	await _capture("06-operating-prepared")
	await _tap(host.hud.controls.speed2)
	while not host.session.sim.snapshot().patients.get("patient_001",{}).get("tolerance_revealed",false):
		host.session.advance_wall_time(50000)
		if host.session.sim.snapshot().tick%10==0: await process_frame
	await _tap(host.hud.controls.pause)
	host.hud.select_entity("patient_001","patients")
	await _capture("07-patient-detail")
	await _tap(host.hud.selection.controls.treatment_preview)
	await _tap(host.hud.selection.controls.gentle)
	await _capture("12-treatment-preview")
	await _tap(host.hud.selection.controls.apply_mode)
	_check(host.session.sim.snapshot().patients.patient_001.mode_override=="gentle","explicit apply updates actual patient mode")
	await _tap(host.hud.selection.controls.back)
	await _tap(host.hud.selection.controls.flow)
	await _capture("13-patient-flow")
	await _tap(host.hud.controls.finance)
	await _capture("08-finance-ledger")
	await _tap(host.hud.controls.settings)
	await _tap(host.hud.flow.controls.pause_help)
	await _capture("09-settings-help")
	host.hud.configure_display(Vector2(1920,1080),Vector2(1280,720),480,Rect2(0,0,1920,1080))
	await _tap(host.hud.controls.close_settings)
	await _tap(host.hud.controls.build)
	await _capture("10-compact-catalog-640dp")
	_check(not host.hud._top.get_global_rect().intersects(host.hud._actions.get_global_rect()),"compact header has no collision")
	var card: Button=host.hud.controls.build_reception
	var scroll: ScrollContainer=host.hud.palette.get_parent()
	_check(card.get_global_rect().end.y<=scroll.get_global_rect().end.y,"compact catalog shows first facility name and price without scrolling")
	await _tap(host.hud.controls.close_build)
	await _tap(host.hud.controls.finance)
	await _capture("11-compact-finance-640dp")
	_check(host.hud._bottom.visible and host.hud._top_frame.visible and not host.hud._settlement_panel.get_global_rect().intersects(host.hud._dock.get_global_rect()) and host.hud._settlement_panel.get_global_rect().end.y<=720,"compact ledger fits between the real A2 HUD frames")
	host.hud.select_entity("patient_001","patients")
	await _capture("14-compact-patient-detail")
	_check(host.hud.selection.controls.treatment_preview.get_global_rect().end.y<=720,"compact detail keeps primary footer on screen")
	await _tap(host.hud.selection.controls.treatment_preview)
	await _capture("15-compact-treatment-preview")
	var summary:={"failed":failed,"captures":captures,"snapshot":host.session.sim.snapshot()}
	var file:=FileAccess.open(output_dir.path_join("gallery.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(summary,"  "))
	file.close()
	print("GALLERY RESULT: failed=%d captures=%d" % [failed,captures.size()])
	quit(1 if failed else 0)
