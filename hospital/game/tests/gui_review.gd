extends SceneTree

var failed:=false
var output_dir: String
var width:=1280
var host: Node3D
var session: GameSession

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		var pair:=argument.split("=",true,1)
		if pair.size()!=2: continue
		if pair[0]=="output": output_dir=pair[1]
		if pair[0]=="width": width=int(pair[1])
	_run.call_deferred()

func _check(value: bool, label: String) -> void:
	print(("REVIEW GUI PASS: " if value else "REVIEW GUI FAIL: ")+label)
	failed=failed or not value

func _finger(index: int, down: bool, point: Vector2, canceled: bool=false) -> void:
	var event:=InputEventScreenTouch.new()
	event.index=index
	event.pressed=down
	event.position=point
	event.canceled=canceled
	Input.parse_input_event(event)

func _tap(button: Button) -> void:
	for _i in range(2): await process_frame
	var ancestor: Node=button.get_parent()
	while ancestor!=null:
		if ancestor is ScrollContainer:
			ancestor.ensure_control_visible(button)
			break
		ancestor=ancestor.get_parent()
	for _i in range(2): await process_frame
	var point:=button.get_global_rect().get_center()
	_finger(0,true,point)
	await process_frame
	_finger(0,false,point)
	for _i in range(2): await process_frame

func _floor_cell(cell:int) -> void:
	host.world.focus_cell(cell)
	for _i in range(3):await process_frame
	var point:Vector2=host.world.camera_rig.camera.unproject_position(HospitalWorld.cell_position(cell))
	_check(not host.hud.hits_gui(point),"construction touch is outside visible A2 GUI")
	_finger(0,true,point)
	await process_frame
	_finger(0,false,point)
	for _i in range(2):await process_frame

func _capture(name: String) -> void:
	for _i in range(4):
		await process_frame
		await RenderingServer.frame_post_draw
	var path:=output_dir.path_join(name+"-%dx720.png" % width)
	if FileAccess.file_exists(path):
		failed=true
		return
	var image:=root.get_texture().get_image()
	_check(image.get_size()==Vector2i(width,720) and image.save_png(path)==OK,"real rendered capture "+name)
	var metadata:=FileAccess.open(path+".json",FileAccess.WRITE)
	metadata.store_string(JSON.stringify({"snapshot":session.sim.snapshot(),"notice_target":session.notice_target,"selected_id":host.hud.selection.selected_id,"selected_group":host.hud.selection.selected_group,"display":DisplayServer.get_name(),"renderer":RenderingServer.get_current_rendering_method(),"adapter":RenderingServer.get_video_adapter_name(),"frames":4},"  "))
	metadata.close()
	print("REVIEW GUI CAPTURE: "+path)

func _run() -> void:
	if DisplayServer.get_name()=="headless" or not output_dir.replace("\\","/").begins_with("E:/CODEX/"):
		quit(1)
		return
	root.size=Vector2i(width,720)
	var catalog: ContentCatalog=ContentCatalog.load_checked("res://content").catalog
	var save_root:=output_dir.path_join("isolated-save")
	var seed:=GameSession.new(catalog,save_root)
	seed.submit({"id":"forced_process_restart_1","type":"hire_staff","payload":{"role":"receptionist"}})
	seed.submit({"id":"external_running","type":"set_paused","payload":{"paused":false}})
	_check(seed.save_now().ok,"valid running save fixture committed")
	session=GameSession.new(catalog,save_root)
	session._prefix="forced_process_restart"
	host=load("res://main.gd").new()
	host.session=session
	root.add_child(host)
	host.set_process(false)
	host.hud.flow.controls.continue_game.pressed.emit()
	for _i in range(4): await process_frame
	_check(session.sim.snapshot().paused,"actual Main load skips colliding receipt and forces pause")
	await _tap(host.hud.controls.dismiss)
	# Missing releases are intentional: Main must completely revoke the old pinch.
	_finger(0,true,Vector2(width/2-60,330))
	_finger(1,true,Vector2(width/2+60,330))
	await process_frame
	host.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	host.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	await _tap(host.hud.controls.dismiss)
	_check(await preload("res://tests/native_a2_interactions.gd").begin_native(host.hud,"reception",_tap),"real A2 card and start open reception")
	host.world.focus_cell(121)
	await process_frame
	var floor_point: Vector2=host.world.camera_rig.camera.unproject_position(HospitalWorld.cell_position(121))
	_finger(0,true,floor_point)
	_finger(0,false,floor_point)
	await process_frame
	_check(host.touch.placement.get("origin_cell",-1)==121,"parsed single touch chooses floor after interrupted pinch")
	await _capture("01-resumed-placement")
	var resumed:Dictionary=preload("res://tests/native_a2_interactions.gd").fixture(session,"reception",121)
	var prepared:Dictionary=await preload("res://tests/native_a2_interactions.gd").finish_native(host.hud,resumed,_tap,_floor_cell,true)
	_check(not prepared.is_empty(),"post-resume draft completes its real size, door and equipment stages")
	await _tap(host.hud.controls.confirm)
	_check(session.sim.snapshot().rooms.size()==1 and session.sim.snapshot().cash==7500,"parsed confirmation executes once despite loaded ID collision")
	_check(await preload("res://tests/native_a2_interactions.gd").begin_native(host.hud,"echo",_tap),"A2 explicit start opens cancellation fixture")
	host.world.focus_cell(104)
	await process_frame
	floor_point=host.world.camera_rig.camera.unproject_position(HospitalWorld.cell_position(104))
	_finger(0,true,floor_point)
	_finger(0,false,floor_point,true)
	await process_frame
	_check(host.touch.placement.is_empty() and session.sim.snapshot().rooms.size()==1,"parsed canceled touch cannot place")
	# Existing test-only clinical fixture; no patient, reservation or outcome is patched.
	session.sim=Scenarios.create_sim(catalog,"benchmark_18","fast","standard")
	host._present()
	host.hud.select_entity("room_006","rooms")
	await _tap(host.hud.selection.controls.upgrade)
	_check(session.sim.snapshot().rooms.room_006.upgraded,"real upgrade button pays for second recovery seat")
	for _i in range(2000):
		session.advance_wall_time(100000)
		if session.notice.contains("拥堵"): break
		if _i%10==0: await process_frame
	var target:=session.notice_target.duplicate(true)
	_check(target.get("expand_flow",false),"actual first congestion offers contextual flow")
	await _tap(host.hud.controls.locate)
	_check(host.hud.selection.selected_id==target.get("patient_id",""),"parsed notice click opens its own patient's expanded flow")
	_check(host.world.camera_rig.target==HospitalWorld.cell_position(session.sim.snapshot().rooms[target.id].origin_cell),"congestion navigation focuses corresponding room")
	for child in host.hud.selection.get_children():
		if child is Label and child.text.begins_with("流程累计等待"):
			(host.hud.selection.get_parent() as ScrollContainer).ensure_control_visible(child)
	await _capture("02-congestion-flow")
	var found:=false
	for _i in range(5000):
		var count:=SelectionPanel.recovery_seats(session.sim.snapshot(),"room_006")
		if count.occupied==1 and count.reserved==1:
			found=true
			break
		session.advance_wall_time(100000)
		if _i%20==0: await process_frame
	_check(found,"real simulation reaches occupied1 reserved1 total2")
	host.hud.select_entity("room_006","rooms")
	await _capture("03-recovery-occupancy")
	await _tap(host.hud.selection.controls.status)
	_check(not host.hud.selection.controls.remove.disabled,"real close refresh enables removal validation without another simulation tick")
	await _tap(host.hud.selection.controls.remove)
	_check(session.notice_target.get("id","")=="room_006","busy-room refusal retains exact room target")
	await _capture("04-busy-room-notice")
	await _tap(host.hud.controls.locate)
	_check(host.hud.selection.selected_group=="rooms" and host.hud.selection.selected_id=="room_006","parsed room-busy notice selects blocked recovery room")
	await _capture("05-notice-located")
	# A second same-kind device has a different default; the closed first device must not pollute prediction.
	var second:Dictionary=await preload("res://tests/native_a2_interactions.gd").prepare_native(host.hud,"echo",244,_tap,_floor_cell)
	_check(not second.is_empty(),"second same-kind device has a real legal four-step draft")
	await _tap(host.hud.controls.confirm)
	_check(session.sim.snapshot().rooms.has("room_007"),"parsed build buys second same-kind device")
	await _tap(host.hud.controls.staff)
	await _tap(host.hud.selection.controls.recruit)
	await _tap(host.hud.controls.hire_technician)
	host.hud.select_entity("room_007","rooms")
	await _tap(host.hud.selection.controls.mode_gentle)
	await _tap(host.hud.selection.controls.assign_staff_006)
	host.hud.select_entity("room_003","rooms")
	await _tap(host.hud.selection.controls.status)
	await _tap(host.hud.controls.speed1)
	var assigned:=false
	for _i in range(2000):
		session.advance_wall_time(100000)
		var snapshot:=session.sim.snapshot()
		var patient: Dictionary=snapshot.patients.get("patient_000010",{})
		if patient.get("room_id","")=="room_007" and not patient.get("treatment_started",false) and snapshot.rooms.room_003.status=="closed":
			assigned=true
			break
		if _i%20==0: await process_frame
	_check(assigned,"actual patient assigned gentle second room after fast first closes")
	await _tap(host.hud.controls.pause)
	host.hud.select_entity("patient_000010","patients")
	_check(SelectionPanel.patient_information(session.sim.snapshot().patients.patient_000010,session.sim.snapshot(),catalog).contains("20秒 · 15币"),"visible assigned-device prediction matches real gentle rule")
	await _capture("06-assigned-device-prediction")
	print("REVIEW GUI RESULT: "+("FAILED" if failed else "OK"))
	quit(1 if failed else 0)
