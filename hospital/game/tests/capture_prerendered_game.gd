extends "res://tests/capture_ui_alignment.gd"

func _run() -> void:
	if DisplayServer.get_name()=="headless" or not output_dir.begins_with("E:/CODEX/") or DirAccess.dir_exists_absolute(output_dir):
		push_error("Use a new E:/CODEX native capture directory");quit(1);return
	root.size=Vector2i(1280,720)
	DirAccess.make_dir_recursive_absolute(output_dir)
	var catalog: ContentCatalog=ContentCatalog.load_checked("res://content").catalog
	host=load("res://main.gd").new()
	host.session=GameSession.new(catalog,output_dir.path_join("isolated-save"))
	root.add_child(host);host.set_process(false)
	host.world.prefer_simplified_characters=false
	await _tap(host.hud.flow.controls.continue_game)
	var state := ClinicState.create("level_01",catalog)
	state.data.unlocked_room_kinds=Scenarios.ROOM_KINDS.duplicate()
	state.data.hint_flags.disabled=true
	host.session.sim=Simulation.new(catalog,state)
	for row in [["reception",244,2],["diagnosis",76,0],["echo",80,0],["motion",84,0],["sensory",248,2],["recovery",253,2]]:
		var built: Dictionary=host.session.issue("build_room",{"kind":row[0],"origin_cell":row[1],"rotation":row[2]})
		_check(built.ok,"real build "+row[0])
		if not built.ok:host.free();quit(1);return
		if row[0]=="recovery":continue
		var hired: Dictionary=host.session.issue("hire_staff",{"role":catalog.rooms[row[0]].staff_role})
		_check(hired.ok,"real hire "+row[0])
		_check(host.session.issue("assign_staff",{"staff_id":hired.data.staff_id,"room_id":built.data.room_id}).ok,"real assignment")
	host.session.issue("set_paused",{"paused":false})
	host.session.sim.advance_ticks(10)
	host.session.issue("set_paused",{"paused":true})
	var moving: Dictionary=host.session.sim.snapshot().staff.staff_002
	host.world.focus_cell(int(moving.cell))
	host.world.camera_rig.set_zoom(5.5)
	_check(host.world.actor_views.staff_002._prerendered.clip_name=="Walk","actual initial staff travel selects walk")
	await _capture("00-normal-game-real-walk")
	host.session.issue("set_paused",{"paused":false})
	host.session.sim.advance_ticks(1390)
	host.session.issue("set_paused",{"paused":true})
	var actor: ActorView=host.world.actor_views.staff_002
	_check(actor._body_root is PrerenderedCharacter,"normal game uses the new 2.5D pilot")
	host.world.camera_rig.target=Vector3(10,0,7.8)
	host.world.camera_rig.set_zoom(11.5)
	await _capture("01-normal-game-overview")
	host.world.focus_cell(int(host.session.sim.snapshot().staff.staff_002.cell))
	host.world.camera_rig.set_zoom(5.5)
	await _capture("02-normal-game-maximum-zoom")
	await _tap(host.hud.controls.staff)
	await _tap(host.hud.selection.controls.staff_002)
	await _capture("03-normal-game-character-detail")
	await _tap(host.hud.controls.close_detail)
	# Search genuine simulation time, never assign a fabricated phase to an actor.
	host.session.issue("set_paused",{"paused":false})
	var service_found := false
	for _tick in range(1800):
		host.session.sim.advance_ticks(1)
		var data: Dictionary=host.session.sim.snapshot().staff.staff_002
		if str(data.phase) in ["serving","diagnosis_service"]:
			service_found=true;break
	host.session.issue("set_paused",{"paused":true})
	_check(service_found,"actual diagnosis session reached in genuine simulation")
	if service_found:
		host.world.focus_cell(int(host.session.sim.snapshot().staff.staff_002.cell))
		host.world.camera_rig.set_zoom(5.5)
		_check(actor._prerendered.clip_name=="Consult","actual service phase selects synchronized consultation")
		await _capture("04-normal-game-real-service")
	# A second real diagnosis assignment yields a genuine southward/front-facing
	# walk. This is an isolated paid-command fixture, never a forced actor yaw.
	var second: Dictionary=host.session.issue("build_room",{"kind":"diagnosis","origin_cell":258,"rotation":2})
	_check(second.ok,"real additional diagnosis room for front-view route")
	if second.ok:
		host.session.issue("set_paused",{"paused":false})
		for _tick in range(400):
			if str(host.session.sim.snapshot().staff.staff_002.phase)=="idle":break
			host.session.sim.advance_ticks(1)
		host.session.issue("set_paused",{"paused":true})
		_check(host.session.issue("assign_staff",{"staff_id":"staff_002","room_id":second.data.room_id}).ok,"real reassignment for front-view route")
		host.session.issue("set_paused",{"paused":false})
		var front_found := false
		for _tick in range(300):
			host.session.sim.advance_ticks(1)
			var data: Dictionary=host.session.sim.snapshot().staff.staff_002
			var path: Array=data.get("path",[])
			var index: int=data.get("path_index",0)
			if int(data.get("move_progress",0))>0 and index+1<path.size() and int(path[index+1])-int(path[index])==24:
				front_found=true;break
		host.session.issue("set_paused",{"paused":true})
		_check(front_found,"ordinary navigation produced actual southward walk")
		if front_found:
			host.world.focus_cell(int(host.session.sim.snapshot().staff.staff_002.cell))
			host.world.camera_rig.set_zoom(5.5)
			_check(actor._prerendered.direction_index==0,"real front-facing path selects independently rendered row zero")
			await _capture("05-normal-game-front-walk")
	var textures := {}
	for clip in ["Idle","Walk","Examine"]:
		var entry: Dictionary=actor._prerendered.manifest.clips[clip]
		var texture: Texture2D=load(actor._prerendered._directory.path_join(entry.texture))
		var image := texture.get_image()
		textures[clip]={"width":texture.get_width(),"height":texture.get_height(),"format":image.get_format(),
			"compressed":image.is_compressed(),"mipmaps":image.has_mipmaps(),"image_data_bytes":image.get_data_size(),
			"scope":"one heading page; only one active page is retained","total_pages":entry.get("pages",[entry.texture]).size()}
	var report := {"failed":failed,"captures":captures,"scope":"normal Main/HospitalWorld/ActorView; real command-built isolated fixture; no body substitution",
		"pilot_entity":"staff_002","canonical":"doctor-02","clip":actor._prerendered.clip_name,"heading_row":actor._prerendered.direction_index,
		"textures":textures,"no_live_pilot_skeleton":actor._body_root.find_children("*","Skeleton3D",true,false).is_empty(),
		"viewport":[1280,720],"android_hardware_tested":false,"art_accepted":false,"sources":{}}
	for path in ["res://presentation/actor_view.gd","res://presentation/prerendered_character.gd","res://presentation/scene_art_library.gd",PrerenderedCharacter.PILOTS["doctor-02"]]:
		report.sources[path]=FileAccess.get_sha256(path)
	var asset_files: Array=["portrait.png"]
	for entry in actor._prerendered.manifest.clips.values():asset_files.append_array(entry.get("pages",[entry.texture]))
	for file_name in asset_files:
		var path: String=actor._prerendered._directory.path_join(file_name)
		report.sources[path]=FileAccess.get_sha256(path)
	var file := FileAccess.open(output_dir.path_join("manifest.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "));file.close()
	host.free()
	print("PRERENDERED GAME CAPTURE: failed=%d captures=%d" % [failed,captures.size()])
	quit(1 if failed else 0)
