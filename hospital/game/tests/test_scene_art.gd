extends SceneTree

var passed:=0
var failed:=0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	if value: passed+=1
	else: failed+=1
	print(("ART PASS: " if value else "ART FAIL: ")+label)

func geometry(node: Node3D, origin: Transform3D) -> String:
	var points:=PackedVector3Array()
	_collect(node,origin,points)
	return str(points).sha256_text()

func _collect(node: Node, origin: Transform3D, points: PackedVector3Array) -> void:
	if node is MeshInstance3D and not node.get_parent().name in ["Symptoms","CureFeedback"]:
		var tr: Transform3D=origin.affine_inverse()*node.global_transform
		for p in node.mesh.get_faces(): points.append(tr*p)
	for child in node.get_children(): _collect(child,origin,points)

func valid_runtime_skin(model: Node3D) -> bool:
	var skeletons := model.find_children("*","Skeleton3D",true,false)
	var meshes := model.find_children("*","MeshInstance3D",true,false)
	if skeletons.size()!=1 or skeletons[0].get_bone_count()!=20 or meshes.size()!=1: return false
	var item: MeshInstance3D=meshes[0]
	if item.skin==null or item.skin.get_bind_count()!=20 or item.mesh.get_surface_count()!=1: return false
	if item.mesh.get_faces().size()/3>10000: return false
	var surface := item.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array=surface[Mesh.ARRAY_VERTEX]
	var weights: PackedFloat32Array=surface[Mesh.ARRAY_WEIGHTS]
	if vertices.is_empty() or weights.is_empty(): return false
	var stride: int=weights.size()/vertices.size()
	if stride not in [4,8]: return false
	for vertex in range(vertices.size()):
		var total := 0.0
		var influences := 0
		for slot in range(stride):
			var weight: float=weights[vertex*stride+slot]
			total+=weight
			if weight>.000001: influences+=1
		if influences>4 or absf(total-1.0)>.0001: return false
	var material: BaseMaterial3D=item.get_active_material(0)
	return material!=null and material.albedo_texture!=null and material.normal_enabled and material.normal_texture!=null and material.roughness_texture!=null and material.metallic_texture!=null

func _run() -> void:
	root.size=Vector2i(1280,720)
	var world:=HospitalWorld.new()
	root.add_child(world)
	var catalog: ContentCatalog=ContentCatalog.load_checked("res://content").catalog
	var sim:=Scenarios.create_sim(catalog,"benchmark_18","fast","standard")
	var snapshot:=sim.snapshot()
	snapshot.patients={}
	for i in range(36):
		var id:="patient_%03d" % (i+1)
		snapshot.patients[id]={"cell":218+i%20,"disease_id":["echo","motion","sensory"][i%3],"phase":"treatment_queue","path":[],"move_progress":0}
	var before:=snapshot.duplicate(true)
	world.present(snapshot)
	var signatures:={}
	for id in snapshot.patients:
		var actor: Node3D=world.actor_views[id]
		signatures[geometry(actor,actor.global_transform)]=true
	check(signatures.size()==36,"all 36 level patients have distinct actual geometry")
	check(snapshot==before,"new presentation does not mutate authoritative snapshot")
	check(FileAccess.file_exists("res://assets/models/manifest.json"),"runtime models have a provenance and geometry manifest")
	check(world.actor_views.patient_001.has_meta("model_asset"),"actual patient view identifies its loaded runtime model")
	check(SceneArtLibrary.portrait("echo",0).get_meta("model_asset")==world.actor_views.patient_001.get_meta("model_asset"),"patient detail portrait is rendered from that person's actual model")
	var colored:=true
	for mesh in world.actor_views.patient_001.find_children("*","MeshInstance3D",true,false):
		if mesh.get_meta("display_only_contact_shadow",false):continue
		if mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]!=null:
			colored=colored and mesh.mesh.surface_get_material(0).vertex_color_use_as_albedo
	check(colored,"runtime model material uses authored skin and clothing vertex colors")
	var first: Node3D=world.actor_views.patient_001
	var first_hash:=geometry(first,first.global_transform)
	snapshot.patients.patient_001.cell=220
	world.present(snapshot)
	check(geometry(first,first.global_transform)==first_hash,"walking to another cell preserves personal appearance")
	world.room_views.room_001._process(.1)
	check(world.room_views.room_001._device_lamps[0].scale.x<.08,"operating lamp preserves its authored small size")
	var motion: Node3D=world.actor_views.patient_002
	motion._process(.2)
	check(motion.symptoms.position.y>.40,"motion symptom animation stays above taller character head")
	snapshot.staff={}
	var single: Dictionary=snapshot.patients.patient_001
	snapshot.patients={"patient_001":single}
	world.present(snapshot)
	world.camera_rig.set_zoom(5.5)
	world.focus_cell(220)
	var selected: Array=[]
	var touch:=TouchController.new(world,func(_p: Vector2)->bool: return false)
	touch.selection_requested.connect(func(id: String,_group: String)->void: selected.append(id))
	var face:=world.camera_rig.camera.unproject_position(first.position+Vector3(0,1.25,0))
	touch._tap(face)
	check(selected==["patient_001"],"close zoom face tap selects the actual taller patient")
	var art: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/manifest.json"))
	var within_budget:=true
	var proper_bounds:=true
	var connected:=true
	var rigged_valid:=true
	var rigged_count:=0
	for entry in art.characters:
		within_budget=within_budget and entry.triangles<=10000 and entry.parts<=6
		var model:=SceneArtLibrary.character(entry.role,"asset_%03d" % (int(str(entry.id).get_slice("-",1))))
		for mesh in model.find_children("*","MeshInstance3D",true,false):
			var bounds: AABB=mesh.mesh.get_aabb()
			proper_bounds=proper_bounds and bounds.size.x<1.05 and bounds.end.y<1.70
		if not model.find_children("*","Skeleton3D",true,false).is_empty():
			rigged_count+=1
			rigged_valid=rigged_valid and valid_runtime_skin(model)
		else:
			var body: MeshInstance3D=model.find_child("Body",true,false)
			for leg_name in ["LegL","LegR"]:
				var leg: MeshInstance3D=model.find_child(leg_name,true,false)
				connected=connected and body.mesh.get_aabb().position.y<=leg.mesh.get_aabb().end.y+.005
		model.free()
	check(within_budget,"all character assets fit the documented triangle and six-part budget")
	check(proper_bounds,"every character part fits human bounds including technical headset")
	check(connected,"all legacy character garments overlap the hips without a floating torso gap")
	check(rigged_count==1 and rigged_valid,"only doctor-02 replaces rigid parts with a real single-mesh 20-bone four-weight PBR skin within budget")
	world.free()
	print("ART RESULT: passed=%d failed=%d" % [passed,failed])
	quit(1 if failed else 0)
