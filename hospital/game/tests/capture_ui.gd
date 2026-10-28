extends SceneTree

var output_dir: String
var width:=1280
var height:=720
var session: GameSession
var world: HospitalWorld
var touch: TouchController
var hud: HospitalHud
var rounds: Array=[]
var opening_only:=false
var failed:=false

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		var pair:=arg.split("=",true,1)
		if pair.size()!=2: continue
		match pair[0]:
			"output": output_dir=pair[1]
			"width": width=int(pair[1])
			"height": height=int(pair[1])
			"opening_only": opening_only=pair[1]=="true"
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name()=="headless" or not output_dir.replace("\\","/").begins_with("E:/CODEX/"):
		push_error("UI rounds require real renderer and E-drive output")
		quit(1)
		return
	root.size=Vector2i(width,height)
	var catalog: ContentCatalog=ContentCatalog.load_checked("res://content").catalog
	session=GameSession.new(catalog,output_dir.path_join("isolated-save"))
	world=HospitalWorld.new()
	root.add_child(world)
	hud=HospitalHud.new()
	var layer:=CanvasLayer.new()
	root.add_child(layer)
	layer.add_child(hud)
	touch=TouchController.new(world,hud.hits_gui,session.reserve_command_id)
	touch.command_requested.connect(session.submit)
	hud.initialize(session,touch,world)
	session.changed.connect(_present)
	_present()
	await _capture("01-operational")
	print("UI INITIAL RECTS: "+str([hud._top.get_rect(),hud._bottom.get_rect(),hud._notice_panel.get_rect(),hud._preview_panel.get_rect()]))
	_check(hud._top.size.y<180,"opening header leaves world visible")
	if opening_only:
		quit(1 if failed else 0)
		return
	await _gesture_round()
	await _build("reception",121)
	_press(hud.controls.save)
	_press(hud.controls.dismiss)
	# Empty-room close, move with preview, reopen; each action travels through its visible control.
	hud.select_entity("room_001","rooms")
	_press(hud.selection.controls.status)
	_press(hud.selection.controls.move)
	await _floor_tap(97)
	_press(hud.controls.confirm)
	hud.select_entity("room_001","rooms")
	_press(hud.selection.controls.move)
	await _floor_tap(121)
	_press(hud.controls.confirm)
	hud.select_entity("room_001","rooms")
	_press(hud.selection.controls.status)
	await _build("diagnosis",100)
	await _build("echo",104)
	await _build("recovery",140)
	_hire_assign("receptionist","room_001")
	_hire_assign("doctor","room_002")
	_hire_assign("technician","room_003")
	_press(hud.controls.patients)
	_press(hud.selection.controls.hospital_flow)
	_press(hud.operations.controls.stage_recovery)
	_press(hud.operations.controls.auto_route)
	hud.select_entity("room_003","rooms")
	_press(hud.selection.controls.mode_gentle)
	_press(hud.selection.controls.mode_fast)
	await _capture("03-prepared")
	_press(hud.controls.speed2)
	while not session.sim.snapshot().patients.get("patient_001",{}).get("tolerance_revealed",false):
		session.advance_wall_time(50000)
		if session.sim.snapshot().tick%10==0: await process_frame
	_press(hud.controls.pause)
	var actor: Node3D=world.actor_views.patient_001
	world.focus_cell(session.sim.snapshot().patients.patient_001.cell)
	await process_frame
	var actor_point:=world.camera_rig.camera.unproject_position(actor.position+Vector3(0,0.65,0))
	_screen_touch(0,true,actor_point)
	_screen_touch(0,false,actor_point)
	_check(hud.selection.selected_id=="patient_001","rendered actor head/body is selectable")
	_press(hud.selection.controls.treatment_preview)
	_press(hud.selection.controls.gentle)
	_press(hud.selection.controls.apply_mode)
	_check(session.sim.snapshot().patients.patient_001.mode_override=="gentle","selected patient override before service")
	await _capture("03b-patient-prediction")
	_press(hud.controls.speed2)
	await _until(2400)
	_check(session.sim.snapshot().paused,"motion hint pauses at2400")
	await _capture("04-motion-unlock")
	_press(hud.controls.dismiss)
	await _build("motion",108)
	_hire_assign("technician","room_005")
	_press(hud.controls.speed2)
	await _until(4800)
	_check(session.sim.snapshot().paused,"sensory hint pauses at4800")
	await _capture("05-sensory-unlock")
	_press(hud.controls.dismiss)
	await _build("sensory",112)
	_hire_assign("technician","room_006")
	# Recovery expansion is a real paid action, available through room management.
	hud.select_entity("room_004","rooms")
	_press(hud.selection.controls.upgrade)
	_press(hud.controls.speed2)
	await _until(9000)
	var won:=session.sim.snapshot()
	_check(won.challenge.status=="won","normal level01 won")
	rounds.append({"round":"legal_level01","snapshot":won})
	await _capture("06-legal-win")
	_check(hud._safe.encloses(hud.controls.restart.get_global_rect()),"terminal restart is inside safe toolbar")
	_check(not hud._right.visible or not hud._right.get_global_rect().intersects(hud.controls.restart.get_global_rect()),"terminal restart does not overlap sidebar")
	_press(hud.controls.restart)
	_check(session.sim.snapshot().tick==0 and session.sim.snapshot().cash==8000,"restart after win creates fresh paused clinic")
	_press(hud.controls.speed2)
	await _until(2400)
	_press(hud.controls.dismiss)
	_press(hud.controls.speed2)
	await _until(4800)
	_press(hud.controls.dismiss)
	_press(hud.controls.speed2)
	await _until(9000)
	var lost:=session.sim.snapshot()
	_check(lost.challenge.status=="lost","no-treatment round fails normally")
	rounds.append({"round":"failure_level01","snapshot":lost})
	await _capture("07-failure")
	_press(hud.controls.restart)
	_check(session.sim.snapshot().paused and session.sim.snapshot().cash==8000 and session.sim.snapshot().rooms.is_empty(),"failure restart clean and paused")
	await _capture("08-restarted")
	hud.configure_display(Vector2(width*2,height*2),Vector2(width,height),480,Rect2(80,0,width*2-160,height*2))
	_check(await preload("res://tests/native_a2_interactions.gd").begin_native(hud,"reception",_press),"A2 selected card starts the density fixture")
	await _floor_tap(121)
	_check(touch.placement.origin_cell==121,"scaled high-density input picks actual center cell")
	_check(hud.controls.confirm.get_global_rect().size.x>=72 and hud.controls.confirm.get_global_rect().size.y>=72,"scaled high-density confirm meets48dp")
	await _capture("09-density-safe-area")
	_press(hud.controls.cancel)
	print("UI ROUNDS OK: "+JSON.stringify({"win":won.challenge,"completed":won.metrics.completed,"abandoned":won.metrics.abandoned,"profit":won.metrics.operating_profit,"cash":won.cash,"failure":lost.challenge,"failure_abandoned":lost.metrics.abandoned}))
	quit(1 if failed else 0)

func _check(value: bool, label: String) -> void:
	print(("UI PASS: " if value else "UI FAIL: ")+label)
	if not value:
		failed=true

func _press(button: Button) -> void:
	button.pressed.emit()
	_present()

func _screen_touch(index: int, down: bool, point: Vector2) -> void:
	var event:=InputEventScreenTouch.new()
	event.index=index
	event.pressed=down
	event.position=point
	touch.feed(event)

func _floor_tap(cell: int) -> void:
	world.focus_cell(cell)
	await process_frame
	var point:=world.camera_rig.camera.unproject_position(HospitalWorld.cell_position(cell))
	_check(not hud.hits_gui(point),"floor center input is outside GUI")
	_screen_touch(0,true,point)
	_screen_touch(0,false,point)

func _build(kind:String,cell:int) -> void:
	var proposal:Dictionary=await preload("res://tests/native_a2_interactions.gd").prepare_native(hud,kind,cell,_press,_floor_tap)
	_check(not proposal.is_empty(),"A2 explicit start and all four stages prepare "+kind)
	if proposal.is_empty():return
	_press(hud.controls.confirm)
	_press(hud.controls.confirm)
	_check(touch.placement.is_empty(),"confirmed transaction cleared "+kind)
	_present()

func _hire_assign(role: String, room_id: String) -> void:
	_press(hud.controls["hire_"+role])
	var ids: Array=session.sim.snapshot().staff.keys()
	var staff_id: String=ids.back()
	hud.select_entity(room_id,"rooms")
	_press(hud.selection.controls["assign_"+staff_id])
	_check(session.sim.snapshot().staff[staff_id].room_id==room_id,"hired employee assigned "+room_id)

func _until(limit: int) -> void:
	while session.sim.snapshot().tick<limit and session.sim.snapshot().challenge.status=="running":
		if session.sim.snapshot().paused: break
		session.advance_wall_time(50000)
		if session.sim.snapshot().tick%100==0: await process_frame
	_present()

func _gesture_round() -> void:
	var proposal:Dictionary=await preload("res://tests/native_a2_interactions.gd").prepare_native(hud,"reception",121,_press,_floor_tap)
	_check(not proposal.is_empty(),"gesture fixture reaches a real unpaid A2 purchase draft")
	await _capture("02-placement-preview")
	session.notice="诊断完成后会显示患者耐受，开始治疗前可以为这位患者选择快速或舒缓。关闭房间后，请等待队列、预约、治疗以及正在离房的人员全部排空，再移动或拆除。".repeat(8)
	hud.present()
	await _capture("02b-long-copy")
	_check(not hud._preview_panel.visible or not hud._notice_panel.get_global_rect().intersects(hud.controls.confirm.get_global_rect()),"long Chinese notice owns interaction without exposing an overlapping confirm")
	_check(hud.controls.confirm.get_global_rect().end.y<height-12,"confirm stays inside safe viewport")
	_press(hud.controls.dismiss)
	var cash: int=session.sim.snapshot().cash
	_screen_touch(0,true,Vector2(width/2-50,330))
	_screen_touch(1,true,Vector2(width/2+50,330))
	var drag:=InputEventScreenDrag.new()
	drag.index=1
	drag.position=Vector2(width/2+100,330)
	touch.feed(drag)
	_screen_touch(0,false,Vector2(width/2-50,330))
	_screen_touch(1,false,drag.position)
	_press(hud.controls.confirm)
	_check(session.sim.snapshot().cash==cash and session.sim.snapshot().rooms.is_empty(),"actual two-finger pinch cancels placement without charge")
	_check(world.camera_rig.zoom_size<17.6,"actual pinch zoom moves camera")
	world.camera_rig.set_zoom(17.6)
	var prior:=world.camera_rig.target
	_screen_touch(0,true,Vector2(width/2,330))
	drag.index=0
	drag.position=Vector2(width/2+40,340)
	touch.feed(drag)
	_screen_touch(0,false,drag.position)
	_check(world.camera_rig.target!=prior,"actual blank drag pans")
	var gui_point: Vector2=hud.controls.pause.get_global_rect().get_center()
	prior=world.camera_rig.target
	_screen_touch(0,true,gui_point)
	drag.position=gui_point+Vector2(40,0)
	touch.feed(drag)
	_screen_touch(0,false,drag.position)
	_check(world.camera_rig.target==prior,"GUI-origin drag cannot pan")

func _present() -> void:
	world.present(session.sim.snapshot())
	hud.present()

func _capture(label: String) -> void:
	for _frame in range(4):
		await process_frame
		await RenderingServer.frame_post_draw
	var path:=output_dir.path_join(label+"-%dx%d.png" % [width,height])
	if FileAccess.file_exists(path):
		push_error("Refusing capture overwrite")
		quit(1)
		return
	var image:=root.get_texture().get_image()
	if image.get_size()!=Vector2i(width,height) or image.save_png(path)!=OK:
		push_error("Invalid real frame")
		quit(1)
		return
	var file:=FileAccess.open(path+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"snapshot":session.sim.snapshot(),"viewport":[width,height],"display":DisplayServer.get_name(),"renderer":RenderingServer.get_current_rendering_method(),"adapter":RenderingServer.get_video_adapter_name(),"frames":4,"rounds":rounds},"  "))
	file.close()
	print("UI CAPTURE OK: "+path)
