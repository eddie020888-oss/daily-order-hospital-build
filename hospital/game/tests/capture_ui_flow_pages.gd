extends SceneTree

var host: Node3D
var output:=""
var failed:=0
var captures: Array=[]

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("output="): output=arg.trim_prefix("output=")
	_run.call_deferred()

func check(ok: bool, copy: String) -> void:
	if not ok: failed+=1
	print(("FLOW GUI PASS: " if ok else "FLOW GUI FAIL: ")+copy)

func finger(down: bool, point: Vector2) -> void:
	var event:=InputEventScreenTouch.new()
	event.index=0
	event.position=point
	event.pressed=down
	Input.parse_input_event(event)

func tap(button: Button) -> void:
	for _i in range(3): await process_frame
	var parent: Node=button.get_parent()
	while parent!=null:
		if parent is ScrollContainer:
			parent.ensure_control_visible(button)
			break
		parent=parent.get_parent()
	for _i in range(3): await process_frame
	check(button.is_visible_in_tree(),"touch button visible: "+button.text)
	var point:=button.get_global_rect().get_center()
	check(Rect2(Vector2.ZERO,Vector2(root.size)).has_point(point),"touch center within viewport: "+button.text)
	for down in [true,false]:
		var event:=InputEventScreenTouch.new()
		event.index=0
		event.position=point
		event.pressed=down
		Input.parse_input_event(event)
		await process_frame
	for _i in range(3): await process_frame

func capture(name: String) -> void:
	for _i in range(4): await process_frame; await RenderingServer.frame_post_draw
	var path:=output.path_join(name+".png")
	check(not FileAccess.file_exists(path) and root.get_texture().get_image().save_png(path)==OK,"render "+name)
	var file:=FileAccess.open(path+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"snapshot":host.session.sim.snapshot(),"page":host.hud.flow.page,"panel":str(host.hud.flow.panel.get_global_rect()),"renderer":RenderingServer.get_current_rendering_method(),"display":DisplayServer.get_name(),"source":"native rendered GameSession; actual ScreenTouch actions"},"  "))
	file.close()
	captures.append(path)

func _run() -> void:
	if DisplayServer.get_name()=="headless" or not output.begins_with("E:/CODEX/") or DirAccess.dir_exists_absolute(output): quit(1); return
	DirAccess.make_dir_recursive_absolute(output)
	root.size=Vector2i(1280,720)
	var catalog: ContentCatalog=ContentCatalog.load_checked("res://content").catalog
	host=load("res://main.gd").new()
	host.session=GameSession.new(catalog,output.path_join("isolated-save"))
	root.add_child(host)
	host.set_process(false)
	await capture("S01-启动主菜单")
	check(host.hud.flow._shade.material==null,"launch retains its unblurred backdrop")
	await tap(host.hud.flow.controls.start_new)
	check(host.hud.flow.page=="guide","native new-game touch opens guidance")
	check(host.hud.flow._shade.material==null,"guidance retains its unblurred backdrop")
	await capture("S02-首次引导")
	await tap(host.hud.flow.controls.guide_build)
	check(host.hud._left.visible,"native guidance touch opens actual building catalog")
	await tap(host.hud.controls.close_build)
	await tap(host.hud.controls.settings)
	check(host.hud.flow.page=="pause" and host.session.sim.snapshot().paused,"native settings touch pauses clinic")
	await capture("S17-暂停菜单")
	var backdrop: Material=host.hud.flow._shade.material
	check(backdrop!=null,"pause uses the original two-pixel backdrop blur")
	host.hud.flow._shade.material=null
	await capture("V06-暂停菜单无模糊对照")
	host.hud.flow._shade.material=backdrop
	await tap(host.hud.flow.controls.save_progress)
	check(host.hud.flow.page=="saved" and FileAccess.file_exists(host.session.save_root.path_join("main.json")),"native save writes disk before success feedback")
	await capture("V02-保存成功")
	await tap(host.hud.flow.controls.back_hospital)
	await tap(host.hud.controls.settings)
	await tap(host.hud.flow.controls.restart_game)
	await capture("S24-重新开局确认")
	await tap(host.hud.flow.controls.cancel_restart)
	await tap(host.hud.flow.controls.resume_game)
	host.session.advance_wall_time(239900000)
	finger(true,Vector2(1100,450))
	await process_frame
	host.session.advance_wall_time(100000)
	var target: Vector3=host.world.camera_rig.target
	var held_drag:=InputEventScreenDrag.new()
	held_drag.index=0
	held_drag.position=Vector2(1200,500)
	Input.parse_input_event(held_drag)
	await process_frame
	check(host.world.camera_rig.target.is_equal_approx(target),"native held ScreenTouch cannot pan through an automatic unlock modal")
	finger(false,Vector2(1200,500))
	check(host.hud.flow.page=="unlock","real 240-second hint owns unlock modal")
	await capture("S19-动作设施解锁")
	await tap(host.hud.flow.controls.unlock_build)
	check(host.touch.placement.get("kind","")=="motion","native unlock touch selects correct real facility")
	host.touch.cancel()
	for _i in range(5):
		host.session.issue("set_paused",{"paused":false})
		host.session.advance_wall_time(900000000)
		if host.session.sim.snapshot().challenge.status!="running": break
	await capture("S22-真实失败结算")
	host.hud.configure_display(Vector2(1920,1080),Vector2(1280,720),480,Rect2(0,0,1920,1080))
	await capture("V05-手机横屏结算")
	check(host.hud.flow.controls.restart_game.get_global_rect().end.y<=720,"short phone result retains fixed reachable footer")
	await tap(host.hud.flow.controls.back_hospital)
	host.hud.configure_display(Vector2(1280,720),Vector2(1280,720),160,Rect2(0,0,1280,720))
	var win:=GameSession.new(catalog,output.path_join("win-save"))
	var fixture: Dictionary=_integers(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/replay_commands.json")))
	for _i in range(9001):
		var snapshot:=win.sim.snapshot()
		for command in fixture.commands:
			if command.tick==snapshot.tick:
				var row: Dictionary=command.duplicate(true)
				row.erase("tick")
				win.submit(row)
		if snapshot.challenge.status!="running": break
		win.advance_wall_time(100000)
	host.session.sim=win.sim
	host._present()
	check(host.session.sim.snapshot().challenge.status=="won","native victory screen uses actual successful command replay")
	await capture("S21-真实胜利结算")
	# Exercise actual corrupt-save protection without touching user data.
	var blocked_root:=output.path_join("corrupt-save")
	DirAccess.make_dir_recursive_absolute(blocked_root)
	var bad:=FileAccess.open(blocked_root.path_join("main.json"),FileAccess.WRITE)
	bad.store_string("corrupt-save-fixture")
	bad.close()
	var blocked:=GameSession.new(catalog,blocked_root)
	blocked.open_saved()
	var second: Node3D=load("res://main.gd").new()
	second.session=blocked
	root.add_child(second)
	second.set_process(false)
	host.hide()
	host.hud.hide()
	var first:=host
	host=second
	check(blocked.storage_blocked and host.hud.flow.page=="storage","actual unreadable save opens protected recovery page")
	await capture("S18-存档保护与恢复")
	await tap(host.hud.flow.controls.storage_back)
	check(host.hud.flow.page=="pause" and host.hud.flow.controls.resume_game.disabled and host.hud.flow.controls.save_progress.disabled and host.hud.flow.controls.restart_game.disabled,"native protected-save Return reaches paused menu with invalid actions disabled")
	await capture("V07-保护存档返回暂停菜单")
	await tap(host.hud.flow.controls.main_menu)
	await tap(host.hud.flow.controls.recover_game)
	check(not blocked.storage_blocked and host.hud.flow.page=="guide","native recovery preserves original then enters fresh guided game")
	first.queue_free()
	var report:=FileAccess.open(output.path_join("manifest.json"),FileAccess.WRITE)
	report.store_string(JSON.stringify({"failed":failed,"captures":captures,"source":"actual native touch and simulation; no fabricated operating values"},"  "))
	report.close()
	print("FLOW GUI RESULT: failed=%d captures=%d output=%s" % [failed,captures.size(),output])
	quit(1 if failed else 0)

func _integers(value: Variant) -> Variant:
	if value is float: return int(value)
	if value is Array:
		var rows: Array=[]
		for item in value: rows.append(_integers(item))
		return rows
	if value is Dictionary:
		var row: Dictionary={}
		for key in value: row[key]=_integers(value[key])
		return row
	return value
