extends SceneTree

# Isolated depth diagnostic. Explicit Consult inspection, never a gameplay capture.
# Acceptance gate: the unfixed production renderer must fail foot retention.
# Root runs this script; the author did not run Godot.
const FRAME_SIZE := Vector2i(384,512)
const VIEW_SIZE := Vector2i(400,500)
var output_dir := ""
var passed := 0
var failed := 0
var views: Array[Dictionary] = []
var reference_dir := ""
var actor_id := "doctor-02"
var clip_selected := "Consult"
var direction_selected := 0
var progress_selected := .5
var checks: Array[Dictionary] = []

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("output="): output_dir=arg.trim_prefix("output=").replace("\\","/")
		if arg.begins_with("reference="): reference_dir=arg.trim_prefix("reference=").replace("\\","/")
		if arg.begins_with("actor="): actor_id=arg.trim_prefix("actor=")
		if arg.begins_with("clip="): clip_selected=arg.trim_prefix("clip=")
		if arg.begins_with("direction="): direction_selected=int(arg.trim_prefix("direction="))
		if arg.begins_with("progress="): progress_selected=float(arg.trim_prefix("progress="))
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks.append({"check":label,"ok":value})
	if value: passed+=1
	else: failed+=1
	print(("FOOT FLOOR PASS: " if value else "FOOT FLOOR FAIL: ")+label)

func build_view(floor_visible: bool) -> Dictionary:
	var viewport := SubViewport.new()
	viewport.size=VIEW_SIZE
	viewport.own_world_3d=true
	viewport.transparent_bg=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var stage := Node3D.new()
	viewport.add_child(stage)
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode=Environment.BG_COLOR
	environment.background_color=Color("e7e2d7")
	environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color=Color("fff6e7")
	environment.ambient_light_energy=.48
	environment.ambient_light_sky_contribution=0
	environment.tonemap_mode=Environment.TONE_MAPPER_LINEAR
	environment_node.environment=environment
	stage.add_child(environment_node)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees=Vector3(-55,-25,0)
	sun.light_color=Color("fff2d9")
	sun.light_energy=.50
	sun.shadow_enabled=false
	stage.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees=Vector3(-35,125,0)
	fill.light_color=Color("e6eff0")
	fill.light_energy=.17
	stage.add_child(fill)
	var floor_root := Node3D.new()
	floor_root.name="ActualHospitalRoomFloor"
	stage.add_child(floor_root)
	var cells: Array[int] = []
	for z in range(8,17):
		for x in range(8,17): cells.append(z*24+x)
	HospitalInteriorArt._floor(floor_root,{"cells":cells,"doorways":[]},Color("47998f"))
	floor_root.position=Vector3(-12,0,-12)
	floor_root.visible=floor_visible
	var camera := Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	# Magnified diagnostic framing; production fixed angle and authored sprite scale.
	camera.size=2.4
	camera.near=.1
	camera.far=100
	var target := Vector3(0,.9,0)
	camera.position=target+CameraRig.VIEW_OFFSET
	stage.add_child(camera)
	camera.look_at(target,Vector3.UP)
	camera.current=true
	var body := PrerenderedCharacter.create_high_quality_for(actor_id)
	if body==null:
		return {"viewport":viewport,"error":"installed v3 factory returned null"}
	stage.add_child(body)
	body.position=Vector3(0,HospitalInteriorArt.ROOM_FLOOR_TOP,0)
	body.set_process(false)
	var shadow := body.get_node_or_null("FootContactShadow") as Node3D
	if shadow!=null: shadow.visible=false
	body.present_progress(clip_selected,TAU*float(direction_selected)/8.0,progress_selected)
	return {"viewport":viewport,"body":body,"camera":camera,"floor":floor_root}

func _run() -> void:
	if DisplayServer.get_name()=="headless" or not output_dir.begins_with("E:/CODEX/") or DirAccess.dir_exists_absolute(output_dir):
		printerr("Requires native rendering and a fresh output=E:/CODEX/... directory")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(output_dir)
	root.size=Vector2i(64,64)
	views.append(build_view(true))
	views.append(build_view(false))
	for item in views:
		if item.has("error"):
			printerr(str(item.error))
			quit(1)
			return
	var left: PrerenderedCharacter=views[0].body
	var right: PrerenderedCharacter=views[1].body
	check(left.clip_name==clip_selected and left.direction_index==direction_selected,"actual requested clip and direction selected")
	if actor_id=="doctor-02" and clip_selected=="Consult" and direction_selected==0 and is_equal_approx(progress_selected,.5):
		check(left.frame_index==32,"reproduction uses actual installed Consult direction0 frame32")
	check(right.clip_name==left.clip_name and right.frame_index==left.frame_index and right.animation_time==left.animation_time,"both views share clip, frame, direction and time")
	check(left.sprite.texture==right.sprite.texture and left.sprite.region_rect==right.sprite.region_rect,"same actual texture and atlas region")
	check(left.global_transform==right.global_transform and left.sprite.global_transform==right.sprite.global_transform,"same body and sprite world transforms")
	check(is_equal_approx(left.global_position.y,HospitalInteriorArt.ROOM_FLOOR_TOP),"actual body root equals actual room floor top .028")
	for _i in range(5):
		await process_frame
		await RenderingServer.frame_post_draw
	var floor_on: Image=views[0].viewport.get_texture().get_image()
	var floor_off: Image=views[1].viewport.get_texture().get_image()
	floor_on.convert(Image.FORMAT_RGBA8)
	floor_off.convert(Image.FORMAT_RGBA8)
	check(floor_on.get_size()==VIEW_SIZE and floor_off.get_size()==VIEW_SIZE,"both actual native images are 400x500")
	floor_on.save_png(output_dir.path_join("01-isolated-floor-visible.png"))
	floor_off.save_png(output_dir.path_join("02-isolated-floor-hidden.png"))
	var composite := Image.create(VIEW_SIZE.x*2,VIEW_SIZE.y,false,Image.FORMAT_RGBA8)
	composite.blit_rect(floor_on,Rect2i(Vector2i.ZERO,VIEW_SIZE),Vector2i.ZERO)
	composite.blit_rect(floor_off,Rect2i(Vector2i.ZERO,VIEW_SIZE),Vector2i(VIEW_SIZE.x,0))
	composite.save_png(output_dir.path_join("03-ISOLATED-DIAGNOSTIC-left-floor-on-right-floor-off.png"))
	var min_x := VIEW_SIZE.x
	var min_y := VIEW_SIZE.y
	var max_x := -1
	var max_y := -1
	var opaque_body := 0
	for y in range(VIEW_SIZE.y):
		for x in range(VIEW_SIZE.x):
			if floor_off.get_pixel(x,y).a<.98: continue
			opaque_body+=1
			min_x=mini(min_x,x); min_y=mini(min_y,y)
			max_x=maxi(max_x,x); max_y=maxi(max_y,y)
	check(opaque_body>100,"floor-hidden control contains opaque character pixels")
	var foot_start := int(floor(float(min_y)+(float(max_y-min_y+1)*.70)))
	var changed_body := 0
	var changed_foot := 0
	var opaque_foot := 0
	var unchanged_upper := 0
	var upper_count := 0
	var diff_mask := Image.create(VIEW_SIZE.x,VIEW_SIZE.y,false,Image.FORMAT_RGBA8)
	for y in range(VIEW_SIZE.y):
		for x in range(VIEW_SIZE.x):
			var base := floor_off.get_pixel(x,y)
			if base.a<.98: continue
			var other := floor_on.get_pixel(x,y)
			var distance := absf(base.r-other.r)+absf(base.g-other.g)+absf(base.b-other.b)
			var changed := other.a<.95 or distance>.10
			if y>=foot_start:
				opaque_foot+=1
				if changed: changed_foot+=1
			else:
				upper_count+=1
				if not changed: unchanged_upper+=1
			if changed:
				changed_body+=1
				diff_mask.set_pixel(x,y,Color(1,0,0,1))
	diff_mask.save_png(output_dir.path_join("04-character-pixels-changed-by-floor-red.png"))
	var source: Image=left.sprite.texture.get_image().get_region(Rect2i(left.sprite.region_rect))
	source.convert(Image.FORMAT_RGBA8)
	source.save_png(output_dir.path_join("05-actual-installed-frame.png"))
	var pixel_height := left.sprite.pixel_size*left.sprite.scale.y
	var floor_source_row := float(FRAME_SIZE.y)*.5+(left.sprite.global_position.y-HospitalInteriorArt.ROOM_FLOOR_TOP)/pixel_height
	var source_below_floor := 0
	for y in range(source.get_height()):
		if float(y)+.5<=floor_source_row: continue
		for x in range(source.get_width()):
			if source.get_pixel(x,y).a>=.98: source_below_floor+=1
	check(source.get_size()==FRAME_SIZE,"extracted installed atlas region is actual 384x512 source frame")
	check(float(unchanged_upper)/maxi(1,upper_count)>.99,"upper 70 percent retained under floor-only visibility change")
	var foot_retained := 1.0-float(changed_foot)/maxi(1,opaque_foot)
	check(changed_foot<=8 or foot_retained>=.998,"FLOOR FOOT RETENTION: at least 99.8 percent of opaque lower character pixels retained")
	var depth_controls: Dictionary=await _depth_controls(views[1],floor_off,foot_start)
	var report := {
		"scope":"ISOLATED diagnostic, not hospital gameplay; same factory sprite and actual HospitalInteriorArt._floor, only floor visibility differs",
		"passed":passed,"failed":failed,"checks":checks,"acceptance_passed":failed==0,
		"foot_retained_fraction":foot_retained,"minimum_foot_retained_fraction":.998,
		"depth_controls":depth_controls,
		"visible_character_foot_pixels_changed_by_floor":changed_foot,
		"foot_occlusion_observed":changed_foot>10,
		"opaque_foot_control_pixels":opaque_foot,"changed_all_character_pixels":changed_body,
		"foot_roi_definition":"bottom 30 percent of floor-hidden opaque character bounding box",
		"foot_roi_start_y":foot_start,"opaque_character_bbox_xyxy":[min_x,min_y,max_x,max_y],
		"comparison_rgb_L1_threshold":.10,"opaque_alpha_threshold":.98,
		"upper_character_retained_fraction":float(unchanged_upper)/maxi(1,upper_count),
		"source_opaque_pixels_below_world_floor":source_below_floor,"predicted_floor_source_row":floor_source_row,
		"model_asset":actor_id,"clip":left.clip_name,"direction":left.direction_index,"frame":left.frame_index,
		"animation_time":left.animation_time,"atlas":left.sprite.texture.resource_path,
		"atlas_sha256":FileAccess.get_sha256(left.sprite.texture.resource_path),"atlas_region":str(left.sprite.region_rect),
		"body_global_y":left.global_position.y,"sprite_global_y":left.sprite.global_position.y,
		"sprite_scale_y":left.sprite.scale.y,"pixel_size":left.sprite.pixel_size,
		"floor_top":HospitalInteriorArt.ROOM_FLOOR_TOP,"floor_generator":"HospitalInteriorArt._floor",
		"camera_offset":[18,18,18],"camera_target":[0,.9,0],"camera_orthographic_size":2.4,
		"camera_framing":"magnified isolated diagnostic; production fixed direction, factory world scale unchanged",
		"viewport_size":[400,500],"panels":"left floor visible / right floor hidden",
		"foot_contact_shadow_hidden_in_both":true,"sprite_no_depth_test":left.sprite.no_depth_test,
		"sprite_billboard":left.sprite.billboard,"sprite_alpha_cut":left.sprite.alpha_cut,
		"limits":"Pixel gate tests floor visibility and opaque wall controls; actual chair image still needs visual review. Not physical shoe mesh-floor intersection, gameplay, full animation or phone hardware test.",
		"script_sha256":FileAccess.get_sha256(get_script().resource_path),"mobile_hardware_tested":false
	}
	var file := FileAccess.open(output_dir.path_join("manifest.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	print("FOOT FLOOR RESULT: passed=%d failed=%d changed_foot_pixels=%d source_below_floor=%d" % [passed,failed,changed_foot,source_below_floor])
	quit(1 if failed else 0)

func _capture(view: SubViewport,filename: String) -> Image:
	for _i in range(3):
		await process_frame
		await RenderingServer.frame_post_draw
	var result := view.get_texture().get_image()
	result.convert(Image.FORMAT_RGBA8)
	result.save_png(output_dir.path_join(filename))
	return result

func _retention(base: Image,other: Image,max_y: int=-1) -> Dictionary:
	var count := 0
	var kept := 0
	for y in range(base.get_height()):
		if max_y>=0 and y>=max_y: continue
		for x in range(base.get_width()):
			var pixel := base.get_pixel(x,y)
			if pixel.a<.98: continue
			count+=1
			var other_pixel := other.get_pixel(x,y)
			if other_pixel.a>=.95 and absf(pixel.r-other_pixel.r)+absf(pixel.g-other_pixel.g)+absf(pixel.b-other_pixel.b)<=.10: kept+=1
	return {"opaque_pixels":count,"retained_pixels":kept,"retained_fraction":float(kept)/maxi(1,count)}

func _depth_controls(item: Dictionary,base: Image,foot_start: int) -> Dictionary:
	var body: PrerenderedCharacter=item.body
	var viewport: SubViewport=item.viewport
	var stage: Node3D=body.get_parent()
	var wall := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size=Vector3(3,3,.04)
	wall.mesh=box
	var material := StandardMaterial3D.new()
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color=Color("ed00ed")
	wall.material_override=material
	wall.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stage.add_child(wall)
	var towards_camera := Vector3(1,0,1).normalized()
	wall.rotation.y=atan2(towards_camera.x,towards_camera.z)
	wall.position=towards_camera*.9+Vector3(0,1,0)
	var front := await _capture(viewport,"06-controlled-front-wall.png")
	var front_result := _retention(base,front)
	check(float(front_result.retained_fraction)<.01,"FRONT WALL: foreground opaque wall still hides at least 99 percent of character")
	wall.position=-towards_camera*.9+Vector3(0,1,0)
	var rear := await _capture(viewport,"07-controlled-rear-wall.png")
	var rear_result := _retention(base,rear)
	check(float(rear_result.retained_fraction)>.995,"REAR WALL: wall behind retains at least 99.5 percent of character")
	wall.visible=false
	var chair := SceneArtLibrary.consult_chair(actor_id=="doctor-02")
	stage.add_child(chair)
	var heading := TAU*float(direction_selected)/8.0
	var direction := Vector3(sin(heading),0,cos(heading))
	chair.position=-direction*.32+Vector3(0,HospitalInteriorArt.ROOM_FLOOR_TOP,0)
	chair.rotation.y=heading
	var chair_image := await _capture(viewport,"08-controlled-real-chair.png")
	var chair_result := _retention(base,chair_image)
	check(float(chair_result.retained_fraction)>.55,"REAL CHAIR: character remains mostly visible with actual chair")
	# A reference captures unchanged upper-body/armrest ordering, not a claim of anatomical collision freedom.
	var comparison: Dictionary={"requested":not reference_dir.is_empty(),"scope":"same actual source pixels and upper-body chair occlusion"}
	if not reference_dir.is_empty():
		var reference_file := reference_dir.path_join("08-controlled-real-chair.png")
		var reference_manifest_file := reference_dir.path_join("manifest.json")
		var ref_json: Variant=JSON.parse_string(FileAccess.get_file_as_string(reference_manifest_file)) if FileAccess.file_exists(reference_manifest_file) else null
		var compatible := ref_json is Dictionary and str(ref_json.get("model_asset",""))==actor_id and str(ref_json.get("clip",""))==clip_selected and int(ref_json.get("direction",-1))==direction_selected and int(ref_json.get("frame",-1))==body.frame_index and str(ref_json.get("atlas_sha256",""))==FileAccess.get_sha256(body.sprite.texture.resource_path)
		check(compatible,"REFERENCE: identical asset, clip, frame, heading and actual source texture hash")
		if compatible and FileAccess.file_exists(reference_file):
			var old_image := Image.load_from_file(reference_file)
			var same_size := old_image!=null and old_image.get_size()==chair_image.get_size()
			check(same_size,"REFERENCE: actual native chair image dimensions match")
			if same_size:
				comparison["upper_retention"]=_retention(old_image,chair_image,foot_start)
				check(float(comparison.upper_retention.retained_fraction)>.995,"REFERENCE: upper-body and chair occlusion pixels unchanged above foot region")
		else:
			check(false,"REFERENCE: readable native chair control image required")
	return {"front_wall":front_result,"rear_wall":rear_result,"actual_chair":chair_result,"reference":comparison,
		"limits":"Wall controls prove real depth testing. Chair image needs visual review; retained fraction alone does not prove anatomical separation or exact near-armrest correctness."}
