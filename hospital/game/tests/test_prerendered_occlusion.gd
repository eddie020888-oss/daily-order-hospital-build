extends SceneTree

# Controlled native rendering tests, not an actual hospital or product screenshot.
var output_dir := ""
var viewport: SubViewport
var passed := 0
var failed := 0

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("output="):output_dir=arg.trim_prefix("output=")
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	if value:passed+=1
	else:failed+=1
	print(("OCCLUSION PASS: " if value else "OCCLUSION FAIL: ")+label)

func capture(name: String) -> Image:
	for _i in range(3):
		await process_frame
		await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	image.convert(Image.FORMAT_RGBA8)
	image.save_png(output_dir.path_join(name+".png"))
	return image

func retained_body(base: Image, other: Image) -> float:
	var body := 0
	var retained := 0
	for y in range(base.get_height()):
		for x in range(base.get_width()):
			var pixel := base.get_pixel(x,y)
			if pixel.a<.95:continue
			body+=1
			var compare := other.get_pixel(x,y)
			if compare.a>.95 and absf(pixel.r-compare.r)+absf(pixel.g-compare.g)+absf(pixel.b-compare.b)<.1:retained+=1
	return float(retained)/maxi(1,body)

func _run() -> void:
	if DisplayServer.get_name()=="headless" or not output_dir.begins_with("E:/CODEX/") or DirAccess.dir_exists_absolute(output_dir):quit(1);return
	DirAccess.make_dir_recursive_absolute(output_dir)
	root.size=Vector2i(64,64)
	viewport=SubViewport.new();viewport.size=Vector2i(384,512);viewport.own_world_3d=true;viewport.transparent_bg=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var stage := Node3D.new();viewport.add_child(stage)
	var camera := Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=2.0
	camera.position=Vector3(0,.75,0)+Vector3(8.5,19,23).normalized()*6
	stage.add_child(camera);camera.look_at(Vector3(0,.75,0));camera.current=true
	var body := PrerenderedCharacter.create_for("doctor-02")
	stage.add_child(body);body.set_process(false);body.get_node("FootContactShadow").visible=false
	body.present_state("Idle",0,1.0)
	var base := await capture("01-sprite-alone-controlled")
	var wall := MeshInstance3D.new()
	var box := BoxMesh.new();box.size=Vector3(2,3,.1);wall.mesh=box
	var material := StandardMaterial3D.new();material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;material.albedo_color=Color("00dac8")
	wall.material_override=material;stage.add_child(wall)
	var forward := Vector3(8.5,0,23).normalized()
	wall.rotation.y=atan2(forward.x,forward.z)
	wall.position=forward*.6+Vector3(0,1.3,0)
	var front := await capture("02-wall-in-front-controlled")
	wall.position=-forward*.6+Vector3(0,1.3,0)
	var back := await capture("03-wall-behind-controlled")
	box.size=Vector3(1.3,.6,.4)
	wall.position=forward*.4+Vector3(0,.3,0)
	var table := await capture("04-low-block-in-front-controlled")
	var front_retained := retained_body(base,front)
	var back_retained := retained_body(base,back)
	var table_retained := retained_body(base,table)
	check(front_retained<.02,"opaque wall in front hides the character")
	check(back_retained>.98,"wall behind preserves the character")
	check(table_retained>.35 and table_retained<.95,"low front block occludes only part of the character")
	wall.visible=false
	var direction_images := []
	for direction in range(8):
		body.present_state("Walk",TAU*direction/8,1)
		direction_images.append(await capture("05-direction-%d-controlled" % direction))
	check(retained_body(direction_images[0],direction_images[4])<.5,"front and back contain different actual pixels")
	body.present_state("Walk",0,1);body.advance_animation(.0)
	var start := await capture("06-walk-start-controlled")
	body.advance_animation(.4)
	var step := await capture("07-walk-step-controlled")
	check(retained_body(start,step)<.98,"walking advances actual rendered geometry frames")
	var report := {"passed":passed,"failed":failed,"scope":"controlled native depth rendering; colored blocks are test fixtures, not actual game furniture",
		"retained_body_fraction":{"front_wall":front_retained,"rear_wall":back_retained,"low_front_block":table_retained},
		"source_actor_sha256":FileAccess.get_sha256("res://presentation/prerendered_character.gd"),"mobile_hardware_tested":false}
	var file := FileAccess.open(output_dir.path_join("manifest.json"),FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
	viewport.free()
	print("OCCLUSION RESULT: passed=%d failed=%d" % [passed,failed])
	quit(1 if failed else 0)
