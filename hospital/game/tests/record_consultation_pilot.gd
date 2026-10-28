extends "res://tests/capture_ui_alignment.gd"

func _run() -> void:
	if DisplayServer.get_name()=="headless" or not output_dir.begins_with("E:/CODEX/") or DirAccess.dir_exists_absolute(output_dir):quit(1);return
	DirAccess.make_dir_recursive_absolute(output_dir);root.size=Vector2i(1280,720)
	var catalog: ContentCatalog=ContentCatalog.load_checked("res://content").catalog
	host=load("res://main.gd").new();host.session=GameSession.new(catalog,output_dir.path_join("isolated-save"))
	root.add_child(host);host.set_process(false)
	host.world.prefer_simplified_characters=false
	await _tap(host.hud.flow.controls.continue_game)
	var state:=ClinicState.create("level_01",catalog);state.data.unlocked_room_kinds=Scenarios.ROOM_KINDS.duplicate();state.data.hint_flags.disabled=true
	host.session.sim=Simulation.new(catalog,state)
	for row in [["reception",244,2],["diagnosis",76,0],["echo",80,0],["motion",84,0],["sensory",248,2],["recovery",253,2]]:
		var build: Dictionary=host.session.issue("build_room",{"kind":row[0],"origin_cell":row[1],"rotation":row[2]})
		_check(build.ok,"real movie fixture room")
		if not build.ok:host.free();quit(1);return
		if row[0]=="recovery":continue
		var hire: Dictionary=host.session.issue("hire_staff",{"role":catalog.rooms[row[0]].staff_role})
		_check(hire.ok and host.session.issue("assign_staff",{"staff_id":hire.data.staff_id,"room_id":build.data.room_id}).ok,"real movie fixture assignment")
	host.session.issue("set_paused",{"paused":false})
	var patient_id: String=catalog.levels.level_01.arrivals[0].id
	var found:=false
	for _i in range(2400):
		host.session.sim.advance_ticks(1)
		if host.session.sim.snapshot().patients.get(patient_id,{}).get("phase","")=="diagnosis_service":found=true;break
	host.session.issue("set_paused",{"paused":true})
	_check(found,"movie starts at genuine service")
	if not found:host.free();quit(1);return
	host.world.camera_rig.target=Vector3(5.4,0,4.3);host.world.camera_rig.set_zoom(5.5)
	await _capture("00-movie-start")
	var before: Dictionary=host.session.sim.snapshot()
	# Ordinary Main._process and GameSession scheduler advance every recorded frame.
	# No fabricated phase, pose, camera orbit, image backdrop or manual sim tick.
	host.session.issue("set_paused",{"paused":false});host.set_process(true)
	for _frame in range(300):await process_frame
	host.set_process(false);host.session.issue("set_paused",{"paused":true})
	var after: Dictionary=host.session.sim.snapshot()
	_check(int(after.tick)-int(before.tick)>=99 and int(after.tick)-int(before.tick)<=101,"ordinary 30 FPS playback advanced ten actual seconds")
	_check(after.patients[patient_id].phase!="diagnosis_service","ordinary playback completed consultation and departed")
	await _capture("01-movie-end")
	var file:=FileAccess.open(output_dir.path_join("manifest.json"),FileAccess.WRITE)
	var metadata:={"failed":failed,"native_movie_maker":true,"fps":30,"recorded_gameplay_frames":300,"tick_start":before.tick,"tick_end":after.tick,"phase_start":before.patients[patient_id].phase,"phase_end":after.patients[patient_id].phase,"art_accepted":false,"android_hardware_tested":false,"source_sha256":{}}
	for source in ["res://presentation/hospital_world.gd","res://presentation/room_view.gd","res://presentation/actor_view.gd","res://presentation/prerendered_character.gd","res://presentation/consultation_view.gd","res://presentation/scene_art_library.gd",PrerenderedCharacter.PILOTS["doctor-02"],PrerenderedCharacter.PILOTS["patient-01"]]:metadata.source_sha256[source]=FileAccess.get_sha256(source)
	file.store_string(JSON.stringify(metadata,"  "));file.close()
	host.free();print("CONSULT MOVIE: failed=%d" % failed);quit(1 if failed else 0)
