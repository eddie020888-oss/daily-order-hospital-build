extends SceneTree

# Isolated pixel regression, not gameplay. Root alone runs Godot.
const VIEW_SIZE := Vector2i(400,500)
const SAMPLES := [
	{"clip":"Idle","phase":"idle","progress":0.0},
	{"clip":"Walk","phase":"walk-a","progress":.25},
	{"clip":"Walk","phase":"walk-b","progress":.75},
	{"clip":"Examine","phase":"examine","progress":.5},
	{"clip":"Consult","phase":"start","progress":0.0},
	{"clip":"Consult","phase":"sit-down","progress":.10},
	{"clip":"Consult","phase":"seated","progress":.5},
	{"clip":"Consult","phase":"rising","progress":.94},
	{"clip":"Consult","phase":"end","progress":1.0}]
var output_dir := ""
var passed := 0
var failed := 0
var checks: Array[Dictionary] = []
var cases: Array[Dictionary] = []
var controls: Array[Dictionary] = []
var views: Array[Dictionary] = []
var hashes: Dictionary = {}
var started_ms := 0

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("output="): output_dir=arg.trim_prefix("output=").replace("\\","/")
	_run.call_deferred()

func check(value: bool,label: String) -> void:
	checks.append({"check":label,"ok":value})
	if value: passed+=1
	else:
		failed+=1
		printerr("GROUND MATRIX FAIL: "+label)

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
	camera.size=2.4
	camera.near=.1
	camera.far=100
	var target := Vector3(0,.9,0)
	camera.position=target+CameraRig.VIEW_OFFSET
	stage.add_child(camera)
	camera.look_at(target,Vector3.UP)
	camera.current=true
	return {"viewport":viewport,"stage":stage,"camera":camera,"floor":floor_root}

func _set_actor(canonical: String) -> bool:
	for item in views:
		if item.has("body"):
			var previous: PrerenderedCharacter=item.body
			previous.free()
		var body := PrerenderedCharacter.create_high_quality_for(canonical)
		if body==null: return false
		var stage: Node3D=item.stage
		stage.add_child(body)
		body.position=Vector3(0,HospitalInteriorArt.ROOM_FLOOR_TOP,0)
		body.set_process(false)
		var shadow := body.get_node_or_null("FootContactShadow") as Node3D
		if shadow!=null: shadow.visible=false
		item["body"]=body
	return true

func _pose(clip: String,direction: int,progress: float) -> void:
	for item in views:
		var body: PrerenderedCharacter=item.body
		body.present_progress(clip,TAU*float(direction)/8.0,progress)

func _settle() -> void:
	for _i in range(2):
		await process_frame
		await RenderingServer.frame_post_draw

func _image(index: int) -> Image:
	var viewport: SubViewport=views[index].viewport
	var result := viewport.get_texture().get_image()
	result.convert(Image.FORMAT_RGBA8)
	return result

func _hash(path: String) -> String:
	if not hashes.has(path): hashes[path]=FileAccess.get_sha256(path)
	return str(hashes[path])

func _measure(base: Image,other: Image) -> Dictionary:
	var box := base.get_used_rect()
	var bytes := base.get_data()
	var compared := other.get_data()
	var start_foot := box.position.y+int(floor(float(box.size.y)*.70))
	var body_count := 0
	var foot_count := 0
	var foot_changed := 0
	var upper_count := 0
	var upper_changed := 0
	for y in range(box.position.y,box.end.y):
		for x in range(box.position.x,box.end.x):
			var at := (y*VIEW_SIZE.x+x)*4
			if int(bytes[at+3])<250: continue
			body_count+=1
			var difference := absi(int(bytes[at])-int(compared[at]))+absi(int(bytes[at+1])-int(compared[at+1]))+absi(int(bytes[at+2])-int(compared[at+2]))
			var changed := int(compared[at+3])<243 or difference>25
			if y>=start_foot:
				foot_count+=1
				if changed: foot_changed+=1
			else:
				upper_count+=1
				if changed: upper_changed+=1
	return {"opaque_pixels":body_count,"opaque_foot_pixels":foot_count,"changed_foot_pixels":foot_changed,
		"foot_retained_fraction":1.0-float(foot_changed)/maxi(1,foot_count),
		"upper_retained_fraction":1.0-float(upper_changed)/maxi(1,upper_count),
		"whole_retained_fraction":1.0-float(foot_changed+upper_changed)/maxi(1,body_count),
		"baseline_alpha_bbox_xywh":[box.position.x,box.position.y,box.size.x,box.size.y],"foot_roi_start_y":start_foot}

func _save_pair(left: Image,right: Image,name: String) -> String:
	var combined := Image.create(VIEW_SIZE.x*2,VIEW_SIZE.y,false,Image.FORMAT_RGBA8)
	combined.blit_rect(left,Rect2i(Vector2i.ZERO,VIEW_SIZE),Vector2i.ZERO)
	combined.blit_rect(right,Rect2i(Vector2i.ZERO,VIEW_SIZE),Vector2i(VIEW_SIZE.x,0))
	var path := output_dir.path_join(name+"-floor-on-off.png")
	combined.save_png(path)
	return path

func _chair(canonical: String,direction_index: int) -> Node3D:
	var chair := SceneArtLibrary.consult_chair(canonical=="doctor-02")
	var stage: Node3D=views[0].stage
	stage.add_child(chair)
	var heading := TAU*float(direction_index)/8.0
	var direction := Vector3(sin(heading),0,cos(heading))
	chair.position=-direction*.32+Vector3(0,HospitalInteriorArt.ROOM_FLOOR_TOP,0)
	chair.rotation.y=heading
	return chair

func _wall_controls(canonical: String) -> Dictionary:
	_pose("Consult",0,.5)
	await _settle()
	var base := _image(1)
	var stage: Node3D=views[1].stage
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
	await _settle()
	var front := _image(1)
	var front_result := _measure(base,front)
	check(float(front_result.whole_retained_fraction)<.01,canonical+" opaque front wall still hides >=99 percent")
	front.save_png(output_dir.path_join(canonical+"-front-wall.png"))
	wall.position=-towards_camera*.9+Vector3(0,1,0)
	await _settle()
	var rear := _image(1)
	var rear_result := _measure(base,rear)
	check(float(rear_result.whole_retained_fraction)>.995,canonical+" rear wall preserves >99.5 percent")
	rear.save_png(output_dir.path_join(canonical+"-rear-wall.png"))
	wall.free()
	return {"model_asset":canonical,"direction":0,"clip":"Consult","frame":32,"front":front_result,"rear":rear_result}

func _run() -> void:
	started_ms=Time.get_ticks_msec()
	if DisplayServer.get_name()=="headless" or not output_dir.begins_with("E:/CODEX/") or DirAccess.dir_exists_absolute(output_dir):
		printerr("Requires native renderer and fresh output=E:/CODEX/... directory")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(output_dir)
	root.size=Vector2i(64,64)
	views.append(build_view(true))
	views.append(build_view(false))
	for canonical: String in ["doctor-02","patient-01"]:
		if not _set_actor(canonical):
			check(false,canonical+" actual high-quality factory must load")
			_write_report()
			quit(1)
			return
		var left: PrerenderedCharacter=views[0].body
		var right: PrerenderedCharacter=views[1].body
		check(left.is_high_quality() and right.is_high_quality(),canonical+" actual v3 source")
		check(left.global_transform==right.global_transform and left.sprite.global_transform==right.sprite.global_transform,canonical+" floor pair identical factory world transforms")
		check(not left.sprite.no_depth_test and not right.sprite.no_depth_test,canonical+" Sprite3D normal depth flag retained")
		for direction in range(8):
			var sheet := Image.create(480,600,false,Image.FORMAT_RGBA8)
			for sample_index in range(SAMPLES.size()):
				var sample: Dictionary=SAMPLES[sample_index]
				var clip := str(sample.clip)
				var phase := str(sample.phase)
				var progress := float(sample.progress)
				var case_id := "%s-d%d-%s-%s" % [canonical,direction,clip,phase]
				_pose(clip,direction,progress)
				await _settle()
				var floor_on := _image(0)
				var floor_off := _image(1)
				var measure := _measure(floor_off,floor_on)
				var same_pose := left.clip_name==clip and left.direction_index==direction and right.clip_name==clip and right.direction_index==direction and left.frame_index==right.frame_index and left.animation_time==right.animation_time and left.sprite.texture==right.sprite.texture and left.sprite.region_rect==right.sprite.region_rect
				check(same_pose,case_id+" actual identical requested frame and source")
				check(int(measure.opaque_pixels)>100 and int(measure.opaque_foot_pixels)>50,case_id+" nonempty actual character and foot control")
				var foot_ok := float(measure.foot_retained_fraction)>=.998
				check(foot_ok,case_id+" foot retention >=99.8 percent")
				check(float(measure.upper_retained_fraction)>.99,case_id+" upper character unchanged >99 percent")
				var atlas_path := left.sprite.texture.resource_path
				var record := {"case":case_id,"model_asset":canonical,"clip":clip,"phase":phase,"requested_progress":progress,
					"direction":direction,"frame":left.frame_index,"runtime_animation_time":left.animation_time,
					"atlas":atlas_path,"atlas_sha256":_hash(atlas_path),"region":str(left.sprite.region_rect),"measurement":measure,
					"source_manifest_sha256":_hash("res://assets/character-pilots-v3/"+canonical+"/manifest.json"),
					"body_global_y":left.global_position.y,"sprite_global_y":left.sprite.global_position.y,"pixel_size":left.sprite.pixel_size,"sprite_scale_y":left.sprite.scale.y,
					"contact_sheet":"%s-d%d-nine-phases-floor-visible.png" % [canonical,direction],"contact_sheet_cell":[sample_index%3,sample_index/3]}
				if not foot_ok or not same_pose or float(measure.upper_retained_fraction)<=.99 or phase=="seated":
					record["native_pair_png"]=_save_pair(floor_on,floor_off,case_id)
				var thumb := floor_on.duplicate() as Image
				thumb.resize(160,200,Image.INTERPOLATE_BILINEAR)
				sheet.blit_rect(thumb,Rect2i(0,0,160,200),Vector2i((sample_index%3)*160,(sample_index/3)*200))
				if phase=="seated":
					var chair := _chair(canonical,direction)
					await _settle()
					var chair_image := _image(0)
					var chair_file := case_id+"-actual-chair.png"
					chair_image.save_png(output_dir.path_join(chair_file))
					var chair_measure := _measure(floor_on,chair_image)
					record["chair_image"]=chair_file
					record["chair_visibility_only"]=chair_measure
					check(float(chair_measure.whole_retained_fraction)>.55,case_id+" actual chair does not hide most character")
					chair.free()
				cases.append(record)
			sheet.save_png(output_dir.path_join("%s-d%d-nine-phases-floor-visible.png" % [canonical,direction]))
			print("GROUND MATRIX: %s direction%d complete (9 phases)" % [canonical,direction])
		controls.append(await _wall_controls(canonical))
	check(cases.size()==144,"complete two-role eight-direction nine-pose matrix =144 actual cases")
	_write_report()
	print("GROUND MATRIX RESULT: passed=%d failed=%d cases=%d elapsed=%.2fs" % [passed,failed,cases.size(),float(Time.get_ticks_msec()-started_ms)/1000.0])
	quit(1 if failed else 0)

func _write_report() -> void:
	var report := {"scope":"ISOLATED actual factory pixels, not gameplay. Only floor visibility differs in pixel gate; actual chairs and opaque walls are separate controls.",
		"passed":passed,"failed":failed,"acceptance_passed":failed==0,"checks":checks,"cases":cases,"depth_controls":controls,
		"expected_case_count":144,"actual_case_count":cases.size(),"samples":SAMPLES,
		"foot_retention_minimum":.998,"foot_roi":"bottom 30 percent of floor-hidden alpha bbox; only alpha >=250/255 pixels counted",
		"RGB_L1_difference_threshold_bytes":25,"comparison_alpha_minimum_byte":243,
		"camera_offset":[18,18,18],"camera_target":[0,.9,0],"ortho_size":2.4,"viewport_size":[400,500],
		"floor_top":HospitalInteriorArt.ROOM_FLOOR_TOP,"floor_source":"HospitalInteriorArt._floor","foot_shadow_hidden_both":true,
		"contact_sheet_order":"3 columns x3 rows, row-major SAMPLES order. Thumbnail layout loses detail, never proof of tiny-feature correctness.",
		"evidence_storage":"Full 800x500 on/off pair for seated representatives and failed cases. Full 400x500 actual chair for all16 role/directions. Other cases retained as measured native pixels in case index and thumbnails.",
		"limits":"144 sampled poses, not every raw frame or every transition. Chair retention is only a coarse visibility check; near-armrest anatomy and occlusion need visual review. No simulation modification, no phone performance test, no art acceptance.",
		"elapsed_seconds":float(Time.get_ticks_msec()-started_ms)/1000.0,"mobile_hardware_tested":false,"art_accepted":false,
		"script_sha256":FileAccess.get_sha256(get_script().resource_path),
		"renderer":RenderingServer.get_current_rendering_method(),
		"character_script_sha256":FileAccess.get_sha256("res://presentation/prerendered_character.gd"),
		"depth_shader_sha256":FileAccess.get_sha256("res://presentation/prerendered_ground_depth.gdshader")}
	var file := FileAccess.open(output_dir.path_join("manifest.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
