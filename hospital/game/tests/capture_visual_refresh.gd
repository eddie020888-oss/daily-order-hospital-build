extends "res://tests/capture_ui_alignment.gd"

# Internal visual review: compact rooms built by real commands in an isolated save.
# This fixture never changes the campaign, saved hospital or clinical rules.
func _run() -> void:
	if DisplayServer.get_name()=="headless" or not output_dir.begins_with("E:/CODEX/") or DirAccess.dir_exists_absolute(output_dir):
		push_error("Visual review requires a new E:/CODEX native output directory")
		quit(1); return
	root.size=Vector2i(1280,720)
	DirAccess.make_dir_recursive_absolute(output_dir)
	var catalog: ContentCatalog=ContentCatalog.load_checked("res://content").catalog
	host=load("res://main.gd").new()
	host.session=GameSession.new(catalog,output_dir.path_join("isolated-save"))
	root.add_child(host)
	host.set_process(false)
	await _tap(host.hud.flow.controls.continue_game)
	var state:=ClinicState.create("level_01",catalog)
	state.data.unlocked_room_kinds=Scenarios.ROOM_KINDS.duplicate()
	state.data.hint_flags.disabled=true
	host.session.sim=Simulation.new(catalog,state)
	for row in [["reception",244,2],["diagnosis",76,0],["echo",80,0],["motion",84,0],["sensory",248,2],["recovery",253,2]]:
		var result: Dictionary=host.session.issue("build_room",{"kind":row[0],"origin_cell":row[1],"rotation":row[2]})
		_check(result.ok,"real compact fixture builds "+row[0]+(" "+str(result) if not result.ok else ""))
		if not result.ok: host.free(); quit(1); return
		if row[0]=="recovery": continue
		var hired: Dictionary=host.session.issue("hire_staff",{"role":catalog.rooms[row[0]].staff_role})
		_check(hired.ok,"real fixture hires "+row[0])
		if not hired.ok: host.free(); quit(1); return
		_check(host.session.issue("assign_staff",{"staff_id":hired.data.staff_id,"room_id":result.data.room_id}).ok,"real fixture assignment "+row[0])
	host.session.issue("set_paused",{"paused":false})
	host.session.sim.advance_ticks(1400)
	host.session.issue("set_paused",{"paused":true})
	host.world.camera_rig.target=Vector3(10,0,7.8)
	host.world.camera_rig.set_zoom(11.5)
	await _capture("01-hospital-overview")
	await _tap(host.hud.controls.build)
	await _capture("02-S04-build")
	await _tap(host.hud.controls.close_build)
	host.hud.select_entity("room_002","rooms")
	await _capture("03-S07-diagnosis")
	await _tap(host.hud.selection.controls.back)
	await _capture("03b-S06-room-list")
	await _tap(host.hud.selection.controls.new_build)
	_check(host.hud._left.visible and not host.hud._right.visible,"room list construction action opens actual catalog")
	await _tap(host.hud.controls.close_build)
	await _tap(host.hud.controls.staff)
	await _capture("04-S08-staff")
	await _tap(host.hud.selection.controls.staff_002)
	await _capture("05-S10-doctor")
	host.world.camera_rig.set_zoom(5.5)
	await _capture("05b-D01-game-close")
	host.world.camera_rig.set_zoom(11.5)
	await _tap(host.hud.controls.close_detail)
	await _tap(host.hud.controls.finance)
	await _capture("06-finance")
	await _tap(host.hud.controls.settings)
	await _tap(host.hud.flow.controls.pause_help)
	await _capture("07-S23-settings")
	await _tap(host.hud.controls.close_panel)
	host.hud.configure_display(Vector2(1920,1080),Vector2(1280,720),480,Rect2(0,0,1920,1080))
	await _tap(host.hud.controls.staff)
	await _capture("08-S08-short-landscape")
	await _tap(host.hud.controls.close_detail)
	host.hud.select_entity("room_002","rooms")
	await _capture("09-S07-short-landscape")
	var file:=FileAccess.open(output_dir.path_join("gallery.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"internal_review_only":true,"failed":failed,"captures":captures,"fixture":"six rooms built/hired/assigned through normal commands; level_01 arrivals advanced 1400 ticks; paused; camera overview zoom11.5"},"  "))
	file.close()
	print("VISUAL REFRESH RESULT: failed=%d captures=%d" % [failed,captures.size()])
	host.free()
	await create_timer(.12).timeout
	quit(1 if failed else 0)
