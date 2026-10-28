extends SceneTree

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name()=="headless":quit(1);return
	var output:="E:/CODEX/2026-10-19/医院原稿落地/outputs/人物结构初检"
	if DirAccess.dir_exists_absolute(output):quit(1);return
	DirAccess.make_dir_recursive_absolute(output)
	root.size=Vector2i(1200,1320)
	root.msaa_3d=Viewport.MSAA_4X
	var stage:=Node3D.new();root.add_child(stage)
	var env:=WorldEnvironment.new();var settings:=Environment.new()
	settings.background_mode=Environment.BG_COLOR;settings.background_color=Color("eee6d4")
	settings.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;settings.ambient_light_energy=.5
	settings.ambient_light_color=Color("fff3e0");env.environment=settings;stage.add_child(env)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-35,-25,0);light.light_energy=.68;stage.add_child(light)
	var camera:=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=2.1
	camera.position=Vector3(.3,1.4,6);stage.add_child(camera);camera.look_at(Vector3(0,.70,0))
	for role in ["doctor","technician","receptionist","patient"]:
		var pair:=Node3D.new();stage.add_child(pair)
		for i in range(2):
			var path:="res://assets/models/reference-v1/characters/%s-%02d.glb" % [role,i+1]
			var model: Node3D=load(path).instantiate();SceneArtLibrary.apply_vertex_colors(model)
			pair.add_child(model);model.position.x=(i-.5)*.85;model.rotation.y=.10 if i==0 else -.10
		for _i in range(4):await process_frame;await RenderingServer.frame_post_draw
		var path:=output.path_join(role+".png")
		if root.get_texture().get_image().save_png(path)!=OK:quit(1);return
		stage.remove_child(pair);pair.queue_free()
	print("REFERENCE CAST REVIEW: 8 actual engine models")
	quit()
