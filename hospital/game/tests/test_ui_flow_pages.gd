extends SceneTree

var failed:=0
var passed:=0
var host: Node3D

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, copy: String) -> void:
	if ok: passed+=1
	else: failed+=1
	print(("PAGES PASS: " if ok else "PAGES FAIL: ")+copy)

func _run() -> void:
	root.size=Vector2i(1280,720)
	var catalog: ContentCatalog=ContentCatalog.load_checked("res://content").catalog
	host=load("res://main.gd").new()
	host.session=GameSession.new(catalog,"E:/CODEX/2026-10-19/医院原稿落地/reports/ui-pages-%d/save" % Time.get_ticks_usec())
	root.add_child(host)
	host.set_process(false)
	for _i in range(4): await process_frame
	var h: HospitalHud=host.hud
	var pages: Variant=h.get("flow")
	check(pages!=null,"main opens the approved launch flow")
	if pages==null:
		quit(1)
		return
	check(pages.page=="launch" and h.hits_gui(Vector2(1200,500)),"launch consumes world touches over the entire screen")
	pages.controls.start_new.pressed.emit()
	check(pages.page=="guide" and host.session.sim.snapshot().paused,"new clinic enters guidance while paused")
	pages.controls.guide_build.pressed.emit()
	check(pages.page=="" and h._left.visible,"guidance opens actual construction catalog")
	h.controls.speed1.pressed.emit()
	host.session.advance_wall_time(100000)
	h.controls.settings.pressed.emit()
	check(pages.page=="pause" and host.session.sim.snapshot().paused,"pause menu stops real simulation before showing")
	var tick: int=host.session.sim.snapshot().tick
	host.session.advance_wall_time(500000)
	check(host.session.sim.snapshot().tick==tick,"paused menu cannot consume simulation time")
	pages.controls.save_progress.pressed.emit()
	check(pages.page=="saved" and FileAccess.file_exists(host.session.save_root.path_join("main.json")),"manual save feedback follows a successful real disk write")
	pages.controls.back_hospital.pressed.emit()
	h.controls.settings.pressed.emit()
	pages.controls.restart_game.pressed.emit()
	var before: Dictionary=host.session.sim.snapshot()
	pages.controls.cancel_restart.pressed.emit()
	check(host.session.sim.snapshot()==before and pages.page=="pause","cancel restart preserves every authoritative state field")
	pages.controls.restart_game.pressed.emit()
	pages.controls.confirm_restart.pressed.emit()
	check(pages.page=="guide" and host.session.sim.snapshot().cash==8000 and host.session.sim.snapshot().tick==0,"confirmed restart creates the real empty paused clinic")
	pages.controls.guide_build.pressed.emit()
	host.session.issue("set_paused",{"paused":false})
	host.session.advance_wall_time(240000000)
	check(pages.page=="unlock" and host.session.sim.snapshot().unlocked_room_kinds.has("motion"),"actual 240 second unlock opens the matching facility modal")
	pages.controls.unlock_build.pressed.emit()
	check(host.touch.placement.get("kind","")=="motion" and host.session.sim.snapshot().paused,"unlock action enters real newly unlocked facility placement")
	host.touch.cancel()
	# A real no-service run ends by the authoritative challenge rules.
	for _i in range(5):
		host.session.issue("set_paused",{"paused":false})
		host.session.advance_wall_time(900000000)
		if host.session.sim.snapshot().challenge.status!="running": break
	check(host.session.sim.snapshot().challenge.status=="lost" and pages.page=="result","real losing challenge automatically opens result")
	var frozen: Dictionary=host.session.sim.snapshot()
	pages.controls.back_hospital.pressed.emit()
	check(host.session.sim.snapshot()==frozen,"viewing ended hospital cannot resume or alter frozen result")
	h.controls.settlement.pressed.emit()
	check(pages.page=="result","terminal result can be reopened separately from finance ledger")
	var win:=GameSession.new(catalog,host.session.save_root.path_join("win"))
	var fixture: Dictionary=_integers(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/replay_commands.json")))
	for _i in range(9001):
		var snapshot:=win.sim.snapshot()
		for command in fixture.commands:
			if int(command.tick)==snapshot.tick:
				var row: Dictionary=command.duplicate(true)
				row.erase("tick")
				win.submit(row)
		if snapshot.challenge.status!="running": break
		win.advance_wall_time(100000)
	host.session.sim=win.sim
	h.present()
	check(win.sim.snapshot().challenge.status=="won" and pages.page=="result","actual winning command replay renders victory")
	var summary: Dictionary=pages.result_summary
	check(summary.completed==win.sim.snapshot().metrics.completed and summary.cash==win.sim.snapshot().cash,"result values come from the actual frozen simulation")
	var d: Dictionary=summary.dispositions
	check(d.not_arrived+d.outside+d.in_hospital+d.completed+d.abandoned==36,"result preserves five mutually exclusive dispositions")
	await _test_storage_return(catalog)
	await _test_automatic_modal_ownership(catalog)
	print("PAGES RESULT: passed=%d failed=%d" % [passed,failed])
	# Dispose players first, then let the audio mixing thread consume their queued stops.
	host.free()
	host=null
	await create_timer(0.24).timeout
	quit(1 if failed else 0)

func _fresh_host(catalog: ContentCatalog, suffix: String) -> Node3D:
	var view: Node3D=load("res://main.gd").new()
	view.session=GameSession.new(catalog,host.session.save_root.path_join(suffix))
	root.add_child(view)
	view.set_process(false)
	view.hud.flow.controls.continue_game.pressed.emit()
	return view

func _test_storage_return(catalog: ContentCatalog) -> void:
	# Break caught: the protected recovery page loops back into itself instead of pause.
	var path: String=host.session.save_root.path_join("blocked-return")
	DirAccess.make_dir_recursive_absolute(path)
	var file:=FileAccess.open(path.path_join("main.json"),FileAccess.WRITE)
	file.store_string("original-unreadable-save")
	file.close()
	var view: Node3D=load("res://main.gd").new()
	view.session=GameSession.new(catalog,path)
	root.add_child(view)
	view.set_process(false)
	var flow: HospitalFlowPages=view.hud.flow
	check(flow.page=="storage" and view.session.storage_blocked,"corrupt original enters actual storage protection")
	flow.controls.storage_back.pressed.emit()
	check(flow.page=="pause","storage Return opens the approved pause menu instead of looping")
	if flow.page=="pause":
		check(flow.controls.resume_game.disabled and flow.controls.save_progress.disabled and flow.controls.restart_game.disabled,"storage-blocked pause disables resume save and restart")
	check(view.session.storage_blocked and FileAccess.get_file_as_string(path.path_join("main.json"))=="original-unreadable-save","returning leaves original bytes and overwrite protection intact")
	view.free()

func _press(touch: TouchController, index: int, point: Vector2) -> void:
	var event:=InputEventScreenTouch.new()
	event.index=index
	event.pressed=true
	event.position=point
	touch.feed(event)

func _drag(touch: TouchController, index: int, point: Vector2) -> void:
	var event:=InputEventScreenDrag.new()
	event.index=index
	event.position=point
	touch.feed(event)

func _test_automatic_modal_ownership(catalog: ContentCatalog) -> void:
	# Break caught: a world gesture accepted before the modal retains its old ownership.
	var view:=_fresh_host(catalog,"modal-ownership")
	await create_timer(0.05).timeout
	view.hud.controls.speed1.pressed.emit()
	view.session.advance_wall_time(239900000)
	_press(view.touch,0,Vector2(1100,450))
	view.session.advance_wall_time(100000)
	var target: Vector3=view.world.camera_rig.target
	_drag(view.touch,0,Vector2(1200,500))
	check(view.hud.flow.page=="unlock" and view.world.camera_rig.target.is_equal_approx(target),"unlock revokes a held world drag before it can move the camera")
	view.hud.flow.controls.unlock_later.pressed.emit()
	view.hud.controls.speed1.pressed.emit()
	view.session.advance_wall_time(239900000)
	view.touch.reset_input()
	_press(view.touch,0,Vector2(1050,450))
	_press(view.touch,1,Vector2(1150,450))
	view.session.advance_wall_time(100000)
	var zoom: float=view.world.camera_rig.zoom_size
	_drag(view.touch,1,Vector2(1230,500))
	check(view.hud.flow.page=="unlock" and is_equal_approx(view.world.camera_rig.zoom_size,zoom),"sensory unlock revokes an existing pinch before it can change zoom")
	view.hud.flow.controls.unlock_later.pressed.emit()
	check(preload("res://tests/native_a2_interactions.gd").begin_build(view.hud,"reception"),"modal fixture uses A2 explicit construction start")
	view.hud.controls.speed1.pressed.emit()
	view.touch.reset_input()
	view.touch.begin_placement("reception")
	_press(view.touch,0,Vector2(1100,450))
	view.session.advance_wall_time(900000000)
	target=view.world.camera_rig.target
	_drag(view.touch,0,Vector2(1200,500))
	check(view.hud.flow.page=="result" and view.touch.placement.is_empty() and not view.hud._preview_panel.visible,"automatic result clears active placement and its visual preview")
	check(view.world.camera_rig.target.is_equal_approx(target),"automatic result revokes the previously held world gesture")
	view.touch.cancel()
	_drag(view.touch,0,Vector2(1220,550))
	check(view.world.camera_rig.target.is_equal_approx(target),"removing a leftover preview cannot reactivate a pre-result world drag")
	view.free()

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
