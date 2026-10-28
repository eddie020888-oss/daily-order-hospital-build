extends SceneTree

# Actual source GLB animation -> transparent fixed-camera pixels. No concept compositing.
const SOURCE := "res://assets/models/characters-v2/doctor-02.glb"
const FRAME := Vector2i(192,256)
const COUNTS := {"Idle":4,"Walk":8,"Examine":8}
var output_dir := ""

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("output="): output_dir=arg.trim_prefix("output=").replace("\\","/")
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name()=="headless" or not output_dir.begins_with("E:/CODEX/") or DirAccess.dir_exists_absolute(output_dir):
		push_error("Bake requires native rendering and a new E:/CODEX directory"); quit(1); return
	DirAccess.make_dir_recursive_absolute(output_dir)
	root.size=Vector2i(64,64)
	var started := Time.get_ticks_msec()
	var viewport := SubViewport.new()
	viewport.size=FRAME
	viewport.own_world_3d=true
	viewport.transparent_bg=true
	viewport.msaa_3d=Viewport.MSAA_4X
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var stage := Node3D.new(); viewport.add_child(stage)
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode=Environment.BG_COLOR
	env.background_color=Color(0,0,0,0)
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color=Color("f4f3ed")
	env.ambient_light_energy=.55
	env.tonemap_mode=Environment.TONE_MAPPER_LINEAR
	environment.environment=env;stage.add_child(environment)
	var key := DirectionalLight3D.new()
	key.rotation_degrees=Vector3(-50,-35,0);key.light_energy=.8;key.light_color=Color("fffaf4");stage.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees=Vector3(-30,135,0);fill.light_energy=.22;stage.add_child(fill)
	var camera := Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=2.0
	camera.position=Vector3(0,.75,0)+Vector3(8.5,19,23).normalized()*6.0
	stage.add_child(camera);camera.look_at(Vector3(0,.75,0));camera.current=true
	var model: Node3D=load(SOURCE).instantiate()
	stage.add_child(model)
	var player: AnimationPlayer=model.find_children("*","AnimationPlayer",true,false)[0]
	player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var clips: Dictionary={}
	for name in player.get_animation_list():
		var short_name := String(name).get_file()
		if COUNTS.has(short_name): clips[short_name]=name
	var manifest := {"version":1,"canonical_asset_id":"doctor-02","artwork_source_id":"D01",
		"status":"TECHNICAL PILOT; overall artwork not accepted; no sitting or equipment-contact clips",
		"source_glb":SOURCE,"source_sha256":FileAccess.get_sha256(SOURCE),
		"frame_size":[FRAME.x,FRAME.y],"directions":8,"heading_rule":"row = round(world_yaw / (TAU/8)) mod 8; authored front +Z; no mirror",
		"camera_offset":[8.5,19,23],"ortho_height":2.0,"center_height":.75,
		"pixel_size":2.0/FRAME.y,"clips":{},"renderer":RenderingServer.get_current_rendering_method(),
		"adapter":RenderingServer.get_video_adapter_name(),"engine":Engine.get_version_info(),"frames":160}
	var border_failures := 0
	for short_name in COUNTS:
		if not clips.has(short_name): push_error("Missing source animation "+short_name); quit(1);return
		var count: int=COUNTS[short_name]
		var duration: float=player.get_animation(clips[short_name]).length
		var atlas := Image.create(FRAME.x*count,FRAME.y*8,false,Image.FORMAT_RGBA8)
		atlas.fill(Color(0,0,0,0))
		var nonempty := 0
		for direction in range(8):
			model.rotation.y=TAU*direction/8.0
			player.play(clips[short_name])
			for frame in range(count):
				player.seek(duration*frame/count,true)
				player.advance(0)
				for _i in range(2):
					await process_frame
					await RenderingServer.frame_post_draw
				var sample := viewport.get_texture().get_image()
				sample.convert(Image.FORMAT_RGBA8)
				if sample.get_pixel(0,0).a>.001:
					push_error("Transparent background failed");quit(1);return
				var used := sample.get_used_rect()
				if used.size.x>0 and used.size.y>0: nonempty+=1
				if used.position.x<3 or used.position.y<3 or used.end.x>FRAME.x-3 or used.end.y>FRAME.y-3: border_failures+=1
				atlas.blit_rect(sample,Rect2i(Vector2i.ZERO,FRAME),Vector2i(frame*FRAME.x,direction*FRAME.y))
				if frame==0: sample.save_png(output_dir.path_join("%s-direction-%d.png" % [short_name,direction]))
		var filename: String=String(short_name).to_lower()+".png"
		var path := output_dir.path_join(filename)
		if atlas.save_png(path)!=OK: push_error("Atlas save failed");quit(1);return
		manifest.clips[short_name]={"texture":filename,"frames":count,"duration":duration,"loop":true,
			"atlas_size":[atlas.get_width(),atlas.get_height()],"nonempty_frames":nonempty,
			"rgba8_bytes_without_mipmaps":atlas.get_width()*atlas.get_height()*4,"sha256":FileAccess.get_sha256(path)}
		print("BAKED "+short_name+" actual_frames="+str(nonempty)+" source_duration="+str(duration))
	manifest["edge_clipped_frames"]=border_failures
	manifest["elapsed_seconds"]=(Time.get_ticks_msec()-started)/1000.0
	manifest["recorded_at_utc"]=Time.get_datetime_string_from_system(true)
	var file := FileAccess.open(output_dir.path_join("manifest.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest,"  "));file.close()
	viewport.free()
	print("BAKE RESULT: frames=160 border_failures=%d elapsed_seconds=%.3f" % [border_failures,manifest.elapsed_seconds])
	quit(1 if border_failures else 0)
