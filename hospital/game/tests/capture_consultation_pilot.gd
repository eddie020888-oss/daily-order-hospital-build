extends "res://tests/capture_ui_alignment.gd"

func _advance(ticks: int) -> void:
	host.session.issue("set_paused",{"paused":false})
	host.session.sim.advance_ticks(ticks)
	host.session.issue("set_paused",{"paused":true})

func _run() -> void:
	if DisplayServer.get_name()=="headless" or not output_dir.begins_with("E:/CODEX/") or DirAccess.dir_exists_absolute(output_dir):quit(1);return
	DirAccess.make_dir_recursive_absolute(output_dir)
	root.size=Vector2i(1280,720)
	var catalog: ContentCatalog=ContentCatalog.load_checked("res://content").catalog
	host=load("res://main.gd").new();host.session=GameSession.new(catalog,output_dir.path_join("isolated-save"))
	root.add_child(host);host.set_process(false)
	host.world.prefer_simplified_characters=false
	await _tap(host.hud.flow.controls.continue_game)
	var state:=ClinicState.create("level_01",catalog)
	state.data.unlocked_room_kinds=Scenarios.ROOM_KINDS.duplicate();state.data.hint_flags.disabled=true
	host.session.sim=Simulation.new(catalog,state)
	for row in [["reception",244,2],["diagnosis",76,0],["echo",80,0],["motion",84,0],["sensory",248,2],["recovery",253,2]]:
		var build: Dictionary=host.session.issue("build_room",{"kind":row[0],"origin_cell":row[1],"rotation":row[2]})
		_check(build.ok,"paid real room "+row[0])
		if not build.ok:host.free();quit(1);return
		if row[0]=="recovery":continue
		var hire: Dictionary=host.session.issue("hire_staff",{"role":catalog.rooms[row[0]].staff_role})
		_check(hire.ok and host.session.issue("assign_staff",{"staff_id":hire.data.staff_id,"room_id":build.data.room_id}).ok,"real hire and assignment")
	_advance(1)
	host.world.camera_rig.target=Vector3(5.4,0,4.3);host.world.camera_rig.set_zoom(5.5)
	await _capture("00-empty-clinic")
	var patient_id: String=catalog.levels.level_01.arrivals[0].id
	var found:=false
	host.session.issue("set_paused",{"paused":false})
	for _i in range(2400):
		host.session.sim.advance_ticks(1)
		var snap: Dictionary=host.session.sim.snapshot()
		if snap.patients.get(patient_id,{}).get("phase","")=="diagnosis_service":found=true;break
	host.session.issue("set_paused",{"paused":true})
	_check(found,"actual P01 diagnosis reached without changing any phase or position")
	if not found:host.free();quit(1);return
	var doc: ActorView=host.world.actor_views.staff_002
	var patient: ActorView=host.world.actor_views[patient_id]
	_check(doc._prerendered.clip_name=="Consult" and patient._prerendered.clip_name=="Consult","both real actors use their own consultation sprite")
	await _capture("01-start-standing")
	_advance(14);await _capture("02-sitting-down")
	_advance(26);await _capture("03-real-consultation")
	var frozen_frame: int=patient._prerendered.frame_index
	await create_timer(.3).timeout
	_check(patient._prerendered.frame_index==frozen_frame,"paused actual game keeps exact clinical pose")
	await _tap(host.hud.controls.patients)
	await _tap(host.hud.selection.controls[patient_id])
	host.world.camera_rig.target=Vector3(5.4,0,4.3)
	host.world.camera_rig.set_zoom(5.5)
	await _capture("04-patient-detail")
	await _tap(host.hud.controls.close_detail)
	_advance(33);await _capture("05-standing-up")
	_advance(8);await _capture("06-real-departure")
	_check(patient._prerendered.clip_name!="Consult","service completion releases the independent patient into ordinary movement")
	var report:={"failed":failed,"captures":captures,"scope":"actual Main/GameSession paid commands, real service slot clock, no fabricated actor pose or screenshot background","viewport":[1280,720],"art_accepted":false,"android_hardware_tested":false,"source_sha256":{}}
	report.active_textures={}
	for body in [doc._prerendered,patient._prerendered]:
		var pixels: Image=body.sprite.texture.get_image()
		report.active_textures[str(body.get_meta("model_asset"))]={"page":body.sprite.texture.resource_path,"bytes":pixels.get_data_size(),"compressed":pixels.is_compressed(),"mipmaps":pixels.has_mipmaps()}
		_check(pixels.is_compressed() and pixels.has_mipmaps(),"active sprite page uses compressed mipmaps")
	report.failed=failed
	for path in ["res://presentation/consultation_view.gd","res://presentation/actor_view.gd","res://presentation/prerendered_character.gd","res://presentation/room_view.gd",PrerenderedCharacter.PILOTS["doctor-02"],PrerenderedCharacter.PILOTS["patient-01"]]:report.source_sha256[path]=FileAccess.get_sha256(path)
	var file:=FileAccess.open(output_dir.path_join("manifest.json"),FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
	host.free();print("CONSULT GAME CAPTURE: failed=%d captures=%d" % [failed,captures.size()]);quit(1 if failed else 0)
