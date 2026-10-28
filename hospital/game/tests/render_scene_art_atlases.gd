extends SceneTree

var stage: Node3D
var view: SubViewport
var camera: Camera3D

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name()=="headless": quit(1); return
	view=SubViewport.new()
	view.size=Vector2i(384,384)
	view.own_world_3d=true
	view.msaa_3d=Viewport.MSAA_4X
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	stage=Node3D.new()
	view.add_child(stage)
	var env:=WorldEnvironment.new()
	var settings:=Environment.new()
	settings.background_mode=Environment.BG_COLOR
	settings.background_color=Color("f6f0df")
	settings.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color=Color("fff6e6")
	settings.ambient_light_energy=.8
	env.environment=settings
	stage.add_child(env)
	var light:=DirectionalLight3D.new()
	light.rotation_degrees=Vector3(-32,-25,0)
	light.light_energy=1.0
	stage.add_child(light)
	camera=Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=.82
	camera.position=Vector3(.65,1.37,4)
	stage.add_child(camera)
	camera.look_at(Vector3(0,1.08,0))
	var atlas:=Image.create(2304,2112,false,Image.FORMAT_RGBA8)
	atlas.fill(Color("f6f0df"))
	var manifest: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/manifest.json"))
	var index:=0
	for entry in manifest.characters:
		var model: Node3D=load(entry.path).instantiate()
		SceneArtLibrary.apply_vertex_colors(model)
		stage.add_child(model)
		for _i in range(2): await process_frame; await RenderingServer.frame_post_draw
		var img:=view.get_texture().get_image()
		img.resize(192,192,Image.INTERPOLATE_LANCZOS)
		atlas.blit_rect(img,Rect2i(0,0,192,192),Vector2i((index%12)*192,(index/12)*192))
		stage.remove_child(model);model.queue_free()
		index+=1
	if atlas.save_png("res://assets/models/portraits.png")!=OK: quit(1); return
	print("ART PORTRAITS: "+str(index))
	view.size=Vector2i(640,440)
	camera.size=2.35
	camera.position=Vector3(2.5,2.3,4)
	camera.look_at(Vector3(0,.72,0))
	var device_atlas:=Image.create(960,440,false,Image.FORMAT_RGBA8)
	device_atlas.fill(Color("f6f0df"))
	index=0
	for entry in manifest.equipment:
		var model: Node3D=load(entry.path).instantiate()
		SceneArtLibrary.apply_vertex_colors(model)
		stage.add_child(model)
		for _i in range(2): await process_frame; await RenderingServer.frame_post_draw
		var img:=view.get_texture().get_image()
		img.resize(320,220,Image.INTERPOLATE_LANCZOS)
		device_atlas.blit_rect(img,Rect2i(0,0,320,220),Vector2i((index%3)*320,(index/3)*220))
		stage.remove_child(model);model.queue_free();index+=1
	if device_atlas.save_png("res://assets/models/equipment-thumbnails.png")!=OK: quit(1); return
	print("ART EQUIPMENT THUMBNAILS: "+str(index))
	quit(0)
