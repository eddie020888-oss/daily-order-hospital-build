extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name()=="headless": quit(1); return
	var output:="res://assets/models/reference-v1/equipment-thumbnails.png"
	if FileAccess.file_exists(output):
		push_error("Preserve approved atlas; use a new version before replacing it")
		quit(1); return
	var view:=SubViewport.new()
	view.size=Vector2i(640,440)
	view.own_world_3d=true
	view.msaa_3d=Viewport.MSAA_4X
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var stage:=Node3D.new()
	view.add_child(stage)
	var world:=WorldEnvironment.new()
	var environment:=Environment.new()
	environment.background_mode=Environment.BG_COLOR
	environment.background_color=Color("f6f0df")
	environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color=Color("fff6e6")
	environment.ambient_light_energy=.8
	world.environment=environment
	stage.add_child(world)
	var light:=DirectionalLight3D.new()
	light.rotation_degrees=Vector3(-32,-25,0)
	stage.add_child(light)
	var camera:=Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=2.7
	camera.position=Vector3(2.5,2.3,4)
	stage.add_child(camera)
	camera.look_at(Vector3(0,.80,0))
	var atlas:=Image.create(960,440,false,Image.FORMAT_RGBA8)
	atlas.fill(Color("f6f0df"))
	var kinds:=["reception","diagnosis","echo","motion","sensory","recovery"]
	for index in range(kinds.size()):
		var model:=SceneArtLibrary.equipment(kinds[index])
		stage.add_child(model)
		for _frame in range(3): await process_frame; await RenderingServer.frame_post_draw
		var img:=view.get_texture().get_image()
		img.resize(320,220,Image.INTERPOLATE_LANCZOS)
		atlas.blit_rect(img,Rect2i(0,0,320,220),Vector2i((index%3)*320,(index/3)*220))
		stage.remove_child(model)
		model.queue_free()
	if atlas.save_png(output)!=OK: quit(1); return
	print("REFERENCE EQUIPMENT ATLAS: 6, actual SceneArtLibrary models")
	quit(0)
