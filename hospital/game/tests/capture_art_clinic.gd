extends SceneTree

var host: Node3D
var output:="E:/CODEX/2026-10-19/医院场景美术实装/outputs/新版医院近景-最终"
var failed:=false

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("output="): output=arg.trim_prefix("output=")
	_run.call_deferred()

func issue(kind: String, payload: Dictionary={}) -> void:
	var result: Dictionary=host.session.issue(kind,payload)
	if not result.ok:
		failed=true;push_error("ART CLINIC COMMAND "+kind+" "+str(result))

func capture(name: String) -> void:
	for _i in range(4): await process_frame;await RenderingServer.frame_post_draw
	var path:=output.path_join(name+".png")
	if FileAccess.file_exists(path) or root.get_texture().get_image().save_png(path)!=OK: failed=true
	var file:=FileAccess.open(path+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"snapshot":host.session.sim.snapshot(),"camera_target":str(host.world.camera_rig.target),"zoom":host.world.camera_rig.zoom_size,"source":"paid commands and actual normal level simulation"},"  "));file.close()
	print("ART CLINIC CAPTURE: "+path)

func advance(until: int) -> void:
	issue("set_speed",{"speed":2});issue("set_paused",{"paused":false})
	while host.session.sim.snapshot().tick<until and host.session.sim.snapshot().challenge.status=="running" and not failed:
		host.session.advance_wall_time(50000)
		if host.session.sim.snapshot().tick%20==0: await process_frame
		if host.session.sim.snapshot().paused and host.session.sim.snapshot().tick<until and host.session.sim.snapshot().challenge.status=="running":
			push_error("ART CLINIC unexpected pause at tick=%d, target=%d, background=%s" % [host.session.sim.snapshot().tick,until,host.session._background])
			failed=true

func _run() -> void:
	if DisplayServer.get_name()=="headless" or not output.begins_with("E:/CODEX/") or DirAccess.dir_exists_absolute(output):quit(1);return
	DirAccess.make_dir_recursive_absolute(output)
	root.size=Vector2i(1280,720)
	var catalog: ContentCatalog=ContentCatalog.load_checked("res://content").catalog
	host=load("res://main.gd").new();host.session=GameSession.new(catalog,output.path_join("isolated-save"))
	root.add_child(host);host.set_process(false)
	host.hud.flow.controls.continue_game.pressed.emit()
	for _i in range(3): await process_frame
	for row in [["reception",74],["diagnosis",78],["echo",82],["recovery",266]]:
		issue("build_room",{"kind":row[0],"origin_cell":row[1],"rotation":0})
	for row in [["receptionist","staff_001","room_001"],["doctor","staff_002","room_002"],["technician","staff_003","room_003"]]:
		issue("hire_staff",{"role":row[0]});issue("assign_staff",{"staff_id":row[1],"room_id":row[2]})
	await advance(2400)
	if failed: quit(1); return
	issue("build_room",{"kind":"motion","origin_cell":270,"rotation":0})
	issue("hire_staff",{"role":"technician"});issue("assign_staff",{"staff_id":"staff_004","room_id":"room_005"})
	await advance(4800)
	if failed: quit(1); return
	issue("build_room",{"kind":"sensory","origin_cell":274,"rotation":0})
	issue("hire_staff",{"role":"technician"});issue("assign_staff",{"staff_id":"staff_005","room_id":"room_006"})
	issue("upgrade_recovery",{"room_id":"room_004"})
	await advance(5100)
	if failed: quit(1); return
	issue("set_paused",{"paused":true});host.session.dismiss_notice();host.hud._close_drawers()
	host.world.camera_rig.target=Vector3(7.5,0,8.5);host.world.camera_rig.set_zoom(12.5)
	await capture("01-实际经营中的新版医院")
	for row in [["room_001",99,"02-接待处近景"],["room_002",104,"03-医生诊断近景"],["room_003",108,"04-声环治疗器材近景"],["room_005",296,"05-动作治疗器材近景"],["room_006",300,"06-感官治疗器材近景"],["room_004",291,"07-恢复区近景"]]:
		host.hud._close_drawers();host.world.focus_cell(row[1]);host.world.camera_rig.set_zoom(5.5)
		await capture(row[2])
	host.hud.select_entity("staff_002","staff")
	host.world.camera_rig.set_zoom(5.5)
	await capture("08-医生模型与头像对应")
	await advance(9000)
	var final: Dictionary=host.session.sim.snapshot()
	if final.challenge.status!="won":failed=true
	print("ART CLINIC RESULT: "+JSON.stringify({"failed":failed,"status":final.challenge.status,"completed":final.metrics.completed,"abandoned":final.metrics.abandoned,"cash":final.cash,"profit":final.metrics.operating_profit}))
	quit(1 if failed else 0)
