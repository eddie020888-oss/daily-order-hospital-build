extends SceneTree

# Standalone world-space regression; no fixed prop counts or art acceptance.
const PIXEL_EPSILON := .75
const LANDMARKS := [
	[Vector2(947.74,499.85),Vector2(725.55,382.47)],
	[Vector2(1023.90,542.05),Vector2(783.85,414.77)],
	[Vector2(912.83,518.80),Vector2(698.81,396.98)],
	[Vector2(988.72,561.46),Vector2(756.92,429.64)]]
var failures := 0
var passed := 0

func _initialize() -> void:_run.call_deferred()

func check(ok:bool,message:String) -> void:
	if ok:passed+=1
	else:failures+=1
	print(("EXTERIOR PASS: " if ok else "EXTERIOR FAIL: ")+message)

func _run() -> void:
	root.size=Vector2i(1280,720)
	var world:=HospitalWorld.new()
	root.add_child(world)
	await process_frame
	var hall:ReferenceHallArt=world.hall_art
	check(is_instance_valid(hall),"normal hospital owns the approved world-space environment")
	if not is_instance_valid(hall):
		world.free();_finish();return
	var environments:=0
	for child in world.find_children("*","Node",true,false):
		if child is ReferenceHallArt:environments+=1
	check(environments==1,"one hall environment exists without old scenery duplicates")
	check(hall.get_parent()==world and bool(hall.get_meta("display_only_environment",false)),"hall is a display-only world child, not a camera overlay")
	check(hall.find_children("*","CollisionObject3D",true,false).is_empty(),"environment introduces no physical collision object")
	check(is_instance_valid(hall.art_view) and hall.art_view.mesh!=null,"original art has an actual drawable world mesh")
	if not is_instance_valid(hall.art_view) or hall.art_view.mesh==null:
		world.free();_finish();return
	var art:MeshInstance3D=hall.art_view
	check(bool(art.get_meta("display_only_environment",false)),"art surface is explicitly display-only")
	check(is_instance_valid(hall.grid_overlay) and not hall.grid_overlay.visible,"construction grid is hidden during ordinary gameplay")
	world.set_build_grid_visible(true)
	check(hall.grid_overlay.visible,"construction can expose its real protected grid")
	world.set_build_grid_visible(false)
	check(not hall.grid_overlay.visible,"leaving construction hides the real grid again")
	var original_transform:Transform3D=art.global_transform
	hall.build()
	check(hall.art_view==art and art.global_transform.is_equal_approx(original_transform),"rebuilding preserves the same mesh and registration")
	var catalog:ContentCatalog=ContentCatalog.load_checked("res://content").catalog
	_assert_map_rules(ClinicState.create("level_01",catalog))
	var rig:CameraRig=world.camera_rig
	# Source intersections and expected pixels were measured in the original PNG,
	# independently of the helper's implementation and reference_basis().
	rig.target=Vector3(11.5,0,7.5)
	rig.set_scene_anchor(Vector2(.5,.5))
	rig.set_zoom(22.0)
	await process_frame
	_round_trips(rig,"reference view")
	var samples:Array=_landmark_samples(art,rig.camera)
	check(samples.size()==LANDMARKS.size(),"four original floor landmarks have finite floor anchors")
	_check_registration(art,rig.camera,samples,"reference view",original_transform)
	rig.pan(Vector3(2.75,0,-1.5))
	rig.set_zoom(18.25)
	await process_frame
	_round_trips(rig,"panned and zoomed-in view")
	_check_registration(art,rig.camera,samples,"panned and zoomed-in view",original_transform)
	rig.pan(Vector3(-6,0,4))
	rig.set_zoom(26.0)
	rig.set_scene_anchor(Vector2(.32,.5),Vector2(.60,.72))
	await process_frame
	_round_trips(rig,"zoomed-out drawer composition")
	_check_registration(art,rig.camera,samples,"zoomed-out drawer composition",original_transform)
	root.size=Vector2i(960,540)
	await process_frame
	rig.set_zoom(15.5)
	await process_frame
	_round_trips(rig,"resized viewport")
	_check_registration(art,rig.camera,samples,"resized viewport",original_transform)
	# Real commands create all rooms/staff; ordinary ticks admit real patients.
	var sim:Simulation=Scenarios.create_sim(catalog,"benchmark_18","fast","standard")
	check(sim!=null,"real clinical fixture can be constructed")
	if sim!=null:
		sim.advance_ticks(360)
		var snapshot:Dictionary=sim.snapshot()
		var before:Dictionary=snapshot.duplicate(true)
		world.present(snapshot)
		check(snapshot==before,"presentation leaves simulation data unchanged")
		_check_background_depth(world)
		rig.pan(Vector3(3,0,-2))
		rig.set_zoom(10.5)
		await process_frame
		_check_background_depth(world)
	world.free()
	_finish()

func _round_trips(rig:CameraRig,label:String) -> void:
	var misses:Array=[]
	var boundary_misses:Array=[]
	for z in range(18):
		for x in range(24):
			var cell:int=z*24+x
			var screen:Vector2=rig.camera.unproject_position(Vector3(x,0,z))
			var picked:int=rig.screen_to_cell(screen)
			var interior:bool=x>=1 and x<=22 and z>=1 and z<=16
			if interior or cell==216:
				if picked!=cell and misses.size()<6:misses.append([cell,picked])
			elif picked!=-1 and boundary_misses.size()<6:boundary_misses.append([cell,picked])
	check(misses.is_empty(),label+": all 22x16 centres and exit216 survive projection/picking "+str(misses))
	check(boundary_misses.is_empty(),label+": other boundary centres stay unpickable "+str(boundary_misses))
	var outside_clear:=true
	for point in [Vector3(-1,0,9),Vector3(24,0,9),Vector3(12,0,-1),Vector3(12,0,18)]:
		outside_clear=outside_clear and rig.screen_to_cell(rig.camera.unproject_position(point))==-1
	check(outside_clear,label+": points outside the finite map cannot pick an interior cell")

func _assert_map_rules(state:ClinicState) -> void:
	var boundary_safe:=true
	for z in range(18):
		for x in range(24):
			if x not in [0,23] and z not in [0,17]:continue
			var result:Dictionary=GridService.preview(state,{"kind":"reception","origin_cell":z*24+x,"rotation":0})
			boundary_safe=boundary_safe and not result.ok and result.code=="boundary"
	check(boundary_safe,"map edges and exit remain forbidden construction origins")
	var corridor_safe:=true
	for z in [8,9]:
		for x in range(1,23):
			var result:Dictionary=GridService.preview(state,{"kind":"reception","origin_cell":z*24+x,"rotation":0})
			corridor_safe=corridor_safe and not result.ok and result.code=="main_corridor"
	for z in [6,7]:
		var result:Dictionary=GridService.preview(state,{"kind":"reception","origin_cell":z*24+4,"rotation":0})
		corridor_safe=corridor_safe and not result.ok and result.code=="main_corridor"
	check(corridor_safe,"rows8/9 stay protected even when a footprint begins above them")
	var above:Dictionary=GridService.preview(state,{"kind":"reception","origin_cell":52,"rotation":0})
	var below:Dictionary=GridService.preview(state,{"kind":"reception","origin_cell":244,"rotation":0})
	check(above.ok and below.ok,"valid rooms remain buildable on both sides of the corridor")
	var route:Array=GridService.path(state,216,238)
	check(not route.is_empty() and route[0]==216 and route[-1]==238,"exit216 and the real corridor remain navigable")

func _landmark_samples(art:MeshInstance3D,camera:Camera3D) -> Array:
	var size:Vector2=art.get_meta("original_image_world_size",Vector2.ZERO)
	var samples:Array=[]
	check(size.x>0 and size.y>0,"background exposes a finite source-image extent")
	if size.x<=0 or size.y<=0:return samples
	for row in LANDMARKS:
		var source:Vector2=row[0]
		var expected:Vector2=row[1]
		var local:=Vector3((source.x/1672.0-.5)*size.x,(.5-source.y/941.0)*size.y,0)
		var landmark:Vector3=art.global_transform*local
		check(camera.unproject_position(landmark).distance_to(expected)<PIXEL_EPSILON,"known original intersection retains its reference pixel")
		var ray_origin:Vector3=camera.project_ray_origin(expected)
		var ray_direction:Vector3=camera.project_ray_normal(expected)
		var floor_hit:Variant=Plane(Vector3.UP,0).intersects_ray(ray_origin,ray_direction)
		if floor_hit is Vector3 and floor_hit.is_finite():samples.append({"local":local,"floor":floor_hit})
	return samples

func _check_registration(art:MeshInstance3D,camera:Camera3D,samples:Array,label:String,original_transform:Transform3D) -> void:
	var registered:=not samples.is_empty()
	for sample in samples:
		# Read current mesh transform AFTER a frame; a camera-following or separately
		# rescaled backdrop must fail against these fixed world floor points.
		var landmark:Vector3=art.global_transform*sample.local
		registered=registered and camera.unproject_position(landmark).distance_to(camera.unproject_position(sample.floor))<PIXEL_EPSILON
	check(registered,label+": texture landmarks and fixed floor points stay registered")
	check(art.global_transform.is_equal_approx(original_transform),label+": background stays fixed in world space")

func _check_background_depth(world:HospitalWorld) -> void:
	var camera:Camera3D=world.camera_rig.camera
	var art:MeshInstance3D=world.hall_art.art_view
	var direction:Vector3=-camera.global_basis.z
	var background_min:=INF
	var box:AABB=art.get_aabb()
	for i in range(8):
		var point:Vector3=art.global_transform*box.get_endpoint(i)
		background_min=minf(background_min,(point-camera.global_position).dot(direction))
	var deepest_live:float=-INF
	var room_meshes:=0
	var actor_meshes:=0
	for group in [world._room_root,world._actor_root]:
		for item:MeshInstance3D in group.find_children("*","MeshInstance3D",true,false):
			if item.mesh==null:continue
			if group==world._room_root:room_meshes+=1
			else:actor_meshes+=1
			var bounds:AABB=item.get_aabb()
			for i in range(8):
				var point:Vector3=item.global_transform*bounds.get_endpoint(i)
				deepest_live=maxf(deepest_live,(point-camera.global_position).dot(direction))
	check(room_meshes>0 and actor_meshes>0,"depth check exercises actual live room and actor meshes")
	check(background_min>deepest_live+.1 and background_min<camera.far,"background stays behind all live geometry and inside far clip")
	var depth_enabled:=false
	if art.material_override is ShaderMaterial:
		var material:ShaderMaterial=art.material_override
		var code:String=material.shader.code if material.shader!=null else ""
		depth_enabled=not code.is_empty() and not code.contains("depth_test_disabled") and not code.contains("ALPHA =")
	elif art.material_override is StandardMaterial3D:
		var material:StandardMaterial3D=art.material_override
		depth_enabled=not material.no_depth_test and material.transparency==BaseMaterial3D.TRANSPARENCY_DISABLED
	check(depth_enabled,"opaque background keeps depth testing instead of painting over live entities")

func _finish() -> void:
	print("EXTERIOR RESULT: passed=%d failed=%d"%[passed,failures])
	quit(1 if failures else 0)
