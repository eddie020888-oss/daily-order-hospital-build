extends SceneTree

# INTERNAL NOT ACCEPTED. Native review helper, excluded by export_presets tests/*.
# Run through tools/Invoke-Godot.ps1 with --script res://tests/render_d01_repair.gd
# -- model=res://assets/models/reference-v1/characters/D01-repair/doctor.glb
# output=E:/CODEX/<new evidence directory> [clip=library/name seek=0.25 tick=1400]
# No assets, resource index, simulation implementation, or production views are changed.
var output_dir := ""
var model_path := "res://assets/models/reference-v1/characters/D01-repair/doctor.glb"
var clip_name := ""
var seek_seconds := 0.0
var scenario_tick := 1400
var host: Node3D
var target_actor: ActorView
var candidate: Node3D
var frozen_snapshot: Dictionary
var snapshot_hash := ""
var report: Dictionary = {"status":"INTERNAL NOT ACCEPTED", "internal_review_only":true, "captures":[], "errors":[]}
var failed := false
var world_bounds := AABB()
var has_bounds := false

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		var pair := argument.split("=",true,1)
		if pair.size()!=2: continue
		match pair[0]:
			"output": output_dir=pair[1].replace("\\","/").simplify_path()
			"model": model_path=pair[1]
			"clip", "name": clip_name=pair[1]
			"seek": seek_seconds=float(pair[1])
			"tick": scenario_tick=int(pair[1])
	_run.call_deferred()

func _error(message: String) -> void:
	failed=true
	report.errors.append(message)
	push_error("D01 INTERNAL REVIEW: "+message)

func _run() -> void:
	# Refuse an existing directory even when empty: previous evidence is immutable.
	if not output_dir.to_upper().begins_with("E:/CODEX/") or DirAccess.dir_exists_absolute(output_dir) or FileAccess.file_exists(output_dir):
		_error("output must be a completely new absolute directory inside E:/CODEX")
		quit(1); return
	if DisplayServer.get_name()=="headless":
		_error("capture needs native rendering; headless is only for --check-only parsing")
		quit(1); return
	if not model_path.begins_with("res://") or not ResourceLoader.exists(model_path):
		_error("candidate model is not ready: "+model_path)
		quit(1); return
	if scenario_tick<0 or scenario_tick>9000 or seek_seconds<0.0:
		_error("tick must be 0..9000; seek must be nonnegative")
		quit(1); return
	var packed := load(model_path) as PackedScene
	if packed==null:
		_error("candidate must load as a PackedScene")
		quit(1); return
	if DirAccess.make_dir_recursive_absolute(output_dir)!=OK:
		_error("could not create output directory")
		quit(1); return
	root.size=Vector2i(1280,720)
	var checked: Dictionary=ContentCatalog.load_checked("res://content")
	var catalog: ContentCatalog=checked.get("catalog")
	if catalog==null:
		_error("content catalog did not load"); _finish(); return
	host=load("res://main.gd").new()
	host.session=GameSession.new(catalog,output_dir.path_join("isolated-save"))
	root.add_child(host)
	host.set_process(false)
	host.set_process_input(false)
	# Dismiss the real launch flow before substituting the genuine benchmark simulation.
	host.hud.flow.controls.continue_game.pressed.emit()
	host.session.sim=Scenarios.create_sim(catalog,"benchmark_18","fast","standard")
	if host.session.sim==null:
		_error("benchmark_18 could not be constructed"); _finish(); return
	host.session.sim.advance_ticks(scenario_tick)
	var pause_result: Dictionary=host.session.issue("set_paused",{"paused":true})
	if not pause_result.get("ok",false):
		_error("real session pause command failed"); _finish(); return
	host.session.dismiss_notice()
	frozen_snapshot=host.session.sim.snapshot()
	snapshot_hash=_hash_snapshot(frozen_snapshot)
	report.merge({"recorded_at_utc":Time.get_datetime_string_from_system(true), "model":model_path,
		"candidate_sha256":FileAccess.get_sha256(ProjectSettings.globalize_path(model_path)),
		"scenario":"benchmark_18 fast standard", "snapshot":frozen_snapshot,
		"snapshot_sha256":snapshot_hash, "snapshot_hash_encoding":"JSON.stringify(snapshot, empty indent, sorted keys=true, full_precision=true), UTF-8 SHA-256",
		"display":DisplayServer.get_name(), "renderer":RenderingServer.get_current_rendering_method(),
		"adapter":RenderingServer.get_video_adapter_name(), "engine":Engine.get_version_info(),
		"viewport":[1280,720], "isolated_save":host.session.save_root,
		"scope":"Only one actual doctor ActorView._body_root replaced in real Main. Close views are structural inspection, not whole-hospital acceptance."})
	var ids: Array=frozen_snapshot.staff.keys()
	ids.sort()
	for id in ids:
		if frozen_snapshot.staff[id].get("role","")=="doctor" and host.world.actor_views.has(id):
			target_actor=host.world.actor_views[id]
			break
	if target_actor==null:
		_error("no actual doctor ActorView in real snapshot"); _finish(); return
	var old_body: Node3D=target_actor._body_root
	var old_transform := old_body.transform
	report.replacement={"entity_id":target_actor.entity_id, "actor_path":str(target_actor.get_path()),
		"original_model_asset":str(target_actor.get_meta("model_asset","")), "old_body_path":str(old_body.get_path()),
		"original_body_transform":str(old_transform), "actor_global_transform":str(target_actor.global_transform),
		"staff_snapshot":frozen_snapshot.staff[target_actor.entity_id],
		"old_per_limb_animation_disabled":true, "candidate_scale_adjustment":"none"}
	# Production ActorView._process writes old limb pivots; do not let it touch a rig.
	target_actor.set_process(false)
	target_actor.remove_child(old_body)
	old_body.queue_free()
	var replacement := Node3D.new()
	replacement.name="D01InternalCandidateBody"
	replacement.transform=old_transform
	target_actor.add_child(replacement)
	target_actor._body_root=replacement
	candidate=packed.instantiate() as Node3D
	if candidate==null:
		_error("candidate scene root is not Node3D"); _finish(); return
	replacement.add_child(candidate)
	# This rig is authored with the sole at local Y=0. Legacy ActorView has a
	# 5cm origin offset; fit the new sole to the actual RoomView tile top.
	var actor_room: String=frozen_snapshot.staff[target_actor.entity_id].get("room_id","")
	var room_floor: bool=frozen_snapshot.rooms.has(actor_room)
	var actual_floor_top := (0.012 if room_floor else -0.012)+0.025*0.5
	candidate.position.y=actual_floor_top-target_actor.global_position.y
	report.replacement["foot_origin_adjustment_m"]=candidate.position.y
	report.replacement["actual_floor_top_world_y"]=actual_floor_top
	report.replacement["floor_basis"]="RoomView tile center Y=0.012 or HospitalWorld hall center Y=-0.012, both actual BoxMesh height=0.025; no actor scale adjustment"
	# The same existing vertex-color presentation rule as normal characters, no resource edits.
	SceneArtLibrary.apply_vertex_colors(candidate)
	report.replacement.candidate_body_path=str(replacement.get_path())
	if not _sample_animation(): _finish(); return
	for _i in range(3): await process_frame
	_inspect_candidate()
	if not has_bounds or world_bounds.size.length()<0.0001:
		_error("candidate has no nonempty mesh bounds"); _finish(); return
	_add_internal_mark()
	# Capture the untouched normal game camera FIRST, at its real default zoom/target.
	await _capture("01-normal-game-camera", "normal game camera; no zoom, pan or actor scaling", host.world.camera_rig.camera)
	var camera := Camera3D.new()
	camera.name="D01InternalInspectionCamera"
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.near=0.01
	camera.far=100.0
	host.world.add_child(camera)
	camera.make_current()
	var center := world_bounds.get_center()
	var extent := maxf(world_bounds.size.y,maxf(world_bounds.size.x,world_bounds.size.z))
	var forward := (replacement.global_basis*Vector3.FORWARD).normalized()
	# Authored character front is +Z for normal ActorView models. No skeleton names assumed.
	forward=-forward
	forward.y=0.0
	forward=forward.normalized()
	if forward.length()<0.1: forward=Vector3.BACK
	var right := Vector3.UP.cross(forward).normalized()
	for entry in [["02-front",forward],["03-side",right],["04-back",-forward]]:
		_set_camera(camera,center,entry[1],_inspection_distance(entry[1]),extent*1.55)
		await _capture(entry[0],"structural orbit camera; authored +Z front; actual hospital retained",camera)
	# Bounds-derived crop targets are reported explicitly, not guesses at named skeleton joints.
	var head_center := center+Vector3.UP*(world_bounds.size.y*0.27)
	_set_camera(camera,head_center,forward,_inspection_distance(forward),extent*0.82)
	await _capture("05-head-close", "upper body/head inspection; target from mesh bounds, not semantic bone names",camera)
	var hands_center := center-Vector3.UP*(world_bounds.size.y*0.06)
	_set_camera(camera,hands_center,forward,_inspection_distance(forward),extent*0.95)
	await _capture("06-hands-close", "torso and hand region inspection; target from mesh bounds, not semantic bone names",camera)
	_finish()

func _sample_animation() -> bool:
	var players: Array[Node]=candidate.find_children("*","AnimationPlayer",true,false)
	for tree in candidate.find_children("*","AnimationTree",true,false): tree.active=false
	var clips: Array=[]
	var matching: Array[AnimationPlayer]=[]
	for player: AnimationPlayer in players:
		player.stop()
		player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		for animation_name in player.get_animation_list():
			var animation: Animation=player.get_animation(animation_name)
			clips.append({"player_path":str(player.get_path()),"name":animation_name,"duration_seconds":animation.length,"tracks":animation.get_track_count()})
			if animation_name==clip_name: matching.append(player)
	report.animations={"available_clips":clips,"requested_clip":clip_name,"requested_seek_seconds":seek_seconds,"autoplay_disabled":true,"sampled":false}
	if clip_name=="": return true
	if matching.size()!=1:
		_error("requested clip must match exactly one AnimationPlayer (use exact library/name): "+clip_name)
		return false
	var chosen := matching[0]
	var selected: Animation=chosen.get_animation(clip_name)
	if seek_seconds>selected.length:
		_error("requested seek exceeds clip duration "+str(selected.length)); return false
	chosen.play(clip_name)
	chosen.seek(seek_seconds,true)
	chosen.pause()
	report.animations.sampled=true
	report.animations.sampled_player=str(chosen.get_path())
	report.animations.sampled_duration_seconds=selected.length
	return true

func _inspect_candidate() -> void:
	var meshes: Array=[]
	var bones: Array=[]
	var total_triangles := 0
	var mesh_nodes: Array[Node]=candidate.find_children("*","MeshInstance3D",true,false)
	if candidate is MeshInstance3D: mesh_nodes.push_front(candidate)
	for item: MeshInstance3D in mesh_nodes:
		if item.mesh==null: continue
		var surfaces: Array=[]
		for surface in range(item.mesh.get_surface_count()):
			var arrays: Array=item.mesh.surface_get_arrays(surface)
			var vertices: int=arrays[Mesh.ARRAY_VERTEX].size() if arrays[Mesh.ARRAY_VERTEX]!=null else 0
			var indices: int=arrays[Mesh.ARRAY_INDEX].size() if arrays[Mesh.ARRAY_INDEX]!=null else 0
			var count := indices if indices>0 else vertices
			var primitive: int=item.mesh.surface_get_primitive_type(surface)
			var triangles := count/3 if primitive==Mesh.PRIMITIVE_TRIANGLES else maxi(0,count-2) if primitive==Mesh.PRIMITIVE_TRIANGLE_STRIP else 0
			total_triangles+=triangles
			var material: Material=item.get_active_material(surface)
			var material_info: Dictionary={"class":"none"}
			if material!=null:
				material_info={"class":material.get_class(),"name":material.resource_name,"resource_path":material.resource_path}
				if material is BaseMaterial3D:
					material_info.merge({"albedo_color":str(material.albedo_color),"albedo_texture":material.albedo_texture.resource_path if material.albedo_texture!=null else "", "roughness":material.roughness,"metallic":material.metallic,"vertex_color_use_as_albedo":material.vertex_color_use_as_albedo})
					material_info.merge({"normal_enabled":material.normal_enabled,"normal_texture":material.normal_texture.resource_path if material.normal_texture!=null else "", "roughness_texture":material.roughness_texture.resource_path if material.roughness_texture!=null else "", "metallic_texture":material.metallic_texture.resource_path if material.metallic_texture!=null else ""})
					var packed_orm: Texture2D=material.orm_texture if material is ORMMaterial3D else null
					material_info["orm_texture"]=packed_orm.resource_path if packed_orm!=null else ""
					if material.albedo_texture==null or material.normal_texture==null or (packed_orm==null and (material.roughness_texture==null or material.metallic_texture==null)):
						_error("candidate lost a required baked PBR texture in engine: "+str(item.get_path()))
				else:
					_error("candidate did not import as a standard PBR material")
			surfaces.append({"surface":surface,"vertices":vertices,"indices":indices,"primitive":primitive,"triangles":triangles,"material":material_info})
		var local_aabb := item.get_aabb()
		var bounds: AABB=item.global_transform*local_aabb
		world_bounds=world_bounds.merge(bounds) if has_bounds else bounds
		has_bounds=true
		meshes.append({"path":str(item.get_path()),"visible_in_tree":item.is_visible_in_tree(),"surfaces":surfaces,"local_aabb":_aabb(local_aabb),"world_aabb":_aabb(bounds),"skeleton_path":str(item.skeleton),"has_skin":item.skin!=null})
	for skeleton: Skeleton3D in candidate.find_children("*","Skeleton3D",true,false):
		bones.append({"path":str(skeleton.get_path()),"bone_count":skeleton.get_bone_count()})
	var bone_count := 0
	for skeleton in bones: bone_count+=int(skeleton.bone_count)
	report.candidate_geometry={"meshes":meshes,"mesh_count":meshes.size(),"total_surface_triangles":total_triangles,"world_aabb":_aabb(world_bounds),"skeletons":bones,"total_bone_count":bone_count,"bounds_note":"Mesh AABB transformed to world; skinned animated vertex bounds may differ."}
	if meshes.size()!=1 or total_triangles>10000 or bone_count!=20:
		_error("candidate violates the single mesh, 10000-triangle or 20-bone review contract")

func _inspection_distance(direction: Vector3) -> float:
	# Orthographic framing uses size, not distance. Stay near the actual actor
	# so the camera does not cross the surrounding diagnostic-room walls.
	var half := world_bounds.size*0.5
	return absf(direction.x)*half.x+absf(direction.y)*half.y+absf(direction.z)*half.z+0.18

func _set_camera(camera: Camera3D, center: Vector3, direction: Vector3, distance: float, size_value: float) -> void:
	camera.size=maxf(0.1,size_value)
	camera.global_position=center+direction*distance+Vector3.UP*(size_value*0.06)
	camera.look_at(center,Vector3.UP)

func _capture(name_value: String, purpose: String, camera: Camera3D) -> void:
	for _i in range(4):
		await process_frame
		await RenderingServer.frame_post_draw
	if _hash_snapshot(host.session.sim.snapshot())!=snapshot_hash:
		_error("snapshot changed during capture "+name_value); return
	var path := output_dir.path_join(name_value+".png")
	if FileAccess.file_exists(path) or FileAccess.file_exists(path+".json"):
		_error("refusing to overwrite evidence "+path); return
	var image := root.get_texture().get_image()
	if image==null or image.is_empty() or image.get_size()!=root.size:
		_error("invalid native viewport image for "+name_value); return
	if image.save_png(path)!=OK:
		_error("cannot write native capture "+path); return
	var entry: Dictionary={"status":"INTERNAL NOT ACCEPTED","path":path,"purpose":purpose,"snapshot_sha256":snapshot_hash,"camera_path":str(camera.get_path()),"camera_transform":str(camera.global_transform),"camera_projection":camera.projection,"camera_size":camera.size,"actual_actor_transform":str(target_actor.global_transform),"candidate_world_aabb":_aabb(world_bounds),"waited_render_frames":4,"all_hospital_and_game_ui_retained":true,"sha256":FileAccess.get_sha256(path)}
	if not _write_json(path+".json",entry): return
	report.captures.append(entry)
	print("D01 INTERNAL CAPTURE: "+path)

func _add_internal_mark() -> void:
	var layer := CanvasLayer.new()
	layer.layer=100
	root.add_child(layer)
	var label := Label.new()
	label.text="INTERNAL NOT ACCEPTED | D01 candidate | actual paused benchmark_18"
	label.position=Vector2(18,112)
	label.add_theme_font_size_override("font_size",17)
	label.add_theme_color_override("font_color",Color("ffc86e"))
	label.add_theme_color_override("font_shadow_color",Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x",1)
	label.add_theme_constant_override("shadow_offset_y",1)
	layer.add_child(label)

func _hash_snapshot(snapshot: Dictionary) -> String:
	return JSON.stringify(snapshot,"",true,true).sha256_text()

func _aabb(value: AABB) -> Dictionary:
	return {"position":[value.position.x,value.position.y,value.position.z],"size":[value.size.x,value.size.y,value.size.z]}

func _write_json(path: String, data: Dictionary) -> bool:
	if FileAccess.file_exists(path):
		_error("refusing to overwrite metadata "+path); return false
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file==null:
		_error("cannot write metadata "+path); return false
	file.store_string(JSON.stringify(data,"  ",true,true))
	file.close()
	return true

func _finish() -> void:
	if report.captures.size()!=6: _error("expected six real captures; got "+str(report.captures.size()))
	report.failed=failed
	if not output_dir.is_empty() and DirAccess.dir_exists_absolute(output_dir):
		_write_json(output_dir.path_join("internal-review.json"),report)
	print("D01 INTERNAL NOT ACCEPTED RESULT: "+JSON.stringify({"failed":failed,"captures":report.captures.size(),"output":output_dir}))
	if host!=null: host.free()
	quit(1 if failed else 0)
