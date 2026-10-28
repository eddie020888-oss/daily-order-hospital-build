extends RefCounted

var world_script: GDScript

func run(t: TestContext) -> void:
	var exists := FileAccess.file_exists("res://presentation/hospital_world.gd")
	t.expect_true(exists, "Presentation: world scene exists")
	if not exists:
		return
	world_script = load("res://presentation/hospital_world.gd")
	test_room_visual_edges_match_walkable_door_geometry(t)
	test_snapshot_present_does_not_mutate_model(t)
	test_three_disease_views_and_cure_feedback_are_distinct(t)
	test_world_pick_maps_known_cell_centers(t)
	test_chinese_font_uses_real_weight_and_covers_ui_copy(t)
	test_actor_quarter_edge_and_visual_reuse(t)
	test_each_treatment_footprint_renders_one_machine(t)
	test_repeated_snapshot_does_not_restart_symptom_animation(t)
	test_rotated_doorways_remain_open_at_literal_boundaries(t)
	test_reception_footprint_preserves_walkable_gap_in_all_rotations(t)

func _sim() -> Simulation:
	return Scenarios.create_sim(ContentCatalog.load_checked("res://content").catalog,"benchmark_18","fast","standard")

func _world() -> Node3D:
	var world: Node3D = world_script.new()
	Engine.get_main_loop().root.add_child(world)
	return world

func test_room_visual_edges_match_walkable_door_geometry(t: TestContext) -> void:
	# Break caught: wall render crosses the open doorway, or uses cell corners instead of boundaries.
	var sim := _sim()
	var world := _world()
	world.present(sim.snapshot())
	var snapshot := sim.snapshot()
	for id in snapshot.rooms:
		var room: Dictionary = snapshot.rooms[id]
		var view: Node3D = world.room_views[id]
		t.expect_equal(view.wall_segments.size(), room.wall_edges.size(), "all physical walls rendered " + id)
		var door_mid: Vector3 = (world.cell_position(room.door_cell) + world.cell_position(room.door_outside_cell)) / 2.0
		for segment in view.wall_segments:
			t.expect_true(not segment.get_aabb().has_point(segment.to_local(door_mid+Vector3(0,0.15,0))), "door edge remains open " + id)
		for edge in room.wall_edges:
			var midpoint: Vector3 = (world.cell_position(edge[0]) + world.cell_position(edge[1])) / 2.0
			var found := false
			for segment in view.wall_segments:
				if Vector2(segment.position.x,segment.position.z).distance_to(Vector2(midpoint.x,midpoint.z)) < 0.01:
					found = true
			t.expect_true(found,"wall at template boundary " + str(edge))
	world.free()

func test_snapshot_present_does_not_mutate_model(t: TestContext) -> void:
	# Break caught: view owns mutable snapshot arrays, rebuilds every present, or leaves terminal ghosts.
	var sim := _sim()
	sim.advance_ticks(250)
	var snapshot := sim.snapshot()
	var before := snapshot.duplicate(true)
	var world := _world()
	world.present(snapshot)
	t.expect_equal(snapshot,before,"presentation cannot change state")
	var first_room: Node3D = world.room_views.room_001
	world.present(sim.snapshot())
	t.expect_equal(world.room_views.room_001,first_room,"unchanged room geometry retained")
	var patient_id: String = snapshot.patients.keys()[0]
	t.expect_true(world.actor_views.has(patient_id),"on-map patient is visible")
	snapshot.patients[patient_id].erase("cell")
	world.present(snapshot)
	t.expect_false(world.actor_views.has(patient_id),"historical patient without cell has no visual actor")
	t.expect_true(sim.snapshot().patients[patient_id].has("cell"),"visual input changes never write simulation")
	world.free()

func test_three_disease_views_and_cure_feedback_are_distinct(t: TestContext) -> void:
	# Break caught: all diseases use one silhouette/marker, or cure still shows symptom glyphs.
	var world := _world()
	var snapshot := _sim().snapshot()
	snapshot.patients = {}
	for i in range(3):
		var id := "visual_" + str(i)
		snapshot.patients[id] = {"cell":218+i,"disease_id":["echo","motion","sensory"][i],"phase":"treatment_queue","path":[],"move_progress":0}
	world.present(snapshot)
	var kinds := {}
	for actor in world.actor_views.values():
		kinds[actor.symptom_kind] = true
		t.expect_true(actor.symptoms.get_child_count() > 0,"symptom has actual geometry")
	t.expect_equal(kinds.size(),3,"three distinct disease presentations")
	for patient in snapshot.patients.values():
		patient.phase = "leaving"
		patient.services_complete = true
	world.present(snapshot)
	for actor in world.actor_views.values():
		t.expect_false(actor.symptoms.visible,"cure clears symptom visuals")
		t.expect_true(actor.cure_feedback.visible,"cure displays independent feedback")
	world.free()

func test_world_pick_maps_known_cell_centers(t: TestContext) -> void:
	# Break caught: screen ray uses wrong plane/cell offset, invalid border becomes buildable, or camera focus clamps incorrectly.
	var world := _world()
	for cell in [25,100,217,308,406]:
		var projected: Vector2 = world.camera_rig.camera.unproject_position(world.cell_position(cell))
		t.expect_equal(world.camera_rig.screen_to_cell(projected),cell,"pick maps known center " + str(cell))
	t.expect_equal(world.camera_rig.screen_to_cell(Vector2(-50000,-50000)),-1,"no floor outside board")
	world.focus_cell(100)
	var center: Vector2 = world.camera_rig.camera.unproject_position(world.cell_position(100))
	t.expect_equal(world.camera_rig.screen_to_cell(center),100,"focus keeps picking aligned")
	world.free()



func test_chinese_font_uses_real_weight_and_covers_ui_copy(t: TestContext) -> void:
	# Break caught: variable-font axis ignored (rendering Thin), or packaged Chinese glyphs omitted.
	var theme: Theme = load("res://ui/theme.tres")
	var font: Font = theme.default_font
	t.expect_false(font.base_font.allow_system_fallback,"Chinese rendering does not rely on host system fallback")
	var server := TextServerManager.get_primary_interface()
	var coords := server.font_get_variation_coordinates(font.get_rids()[0])
	var weight := server.name_to_tag("wght")
	print("FONT BACKEND AXES: " + str(coords))
	t.expect_true(float(coords.get(weight,coords.get("wght",0)))>=400.0,"real font backend weight is readable Regular or stronger")
	var text := "句尾回放症动作串线症感官串台症快速舒缓按耐受分流等待恢复席位恢复区满员未完成弃诊离院中等待通路接待诊断招聘建造移动拆除升级关闭重新开放暂停继续保存加载速度资金耐心不足设备占用；，。：！？（）0123456789+−×%"
	for character in text:
		t.expect_true(font.has_char(character.unicode_at(0)),"packaged Chinese/UI glyph " + character)

func test_actor_quarter_edge_and_visual_reuse(t: TestContext) -> void:
	# Break caught: snap to next cell, wrong quarter-step fraction, or every snapshot rebuilds actors.
	var world := _world()
	var snapshot := _sim().snapshot()
	snapshot.patients={"p":{"cell":217,"disease_id":"motion","phase":"moving_diagnosis","path":[217,218],"path_index":0,"move_progress":1}}
	world.present(snapshot)
	var actor: Node3D = world.actor_views.p
	t.expect_equal(actor.position,Vector3(1.25,0.05,9),"quarter edge interpolates physical grid")
	var head: Node3D = actor.get_node("CharacterModel")
	snapshot.patients.p.move_progress=3
	world.present(snapshot)
	t.expect_equal(world.actor_views.p,actor,"actor Node retained")
	t.expect_equal(actor.get_node("CharacterModel"),head,"actor mesh retained")
	t.expect_equal(actor.position,Vector3(1.75,0.05,9),"three-quarter edge interpolates")
	world.free()


func test_each_treatment_footprint_renders_one_machine(t: TestContext) -> void:
	# Break caught: treating the two blocked equipment cells as two independently duplicated machines.
	var world := _world()
	world.present(_sim().snapshot())
	for id in world.room_views:
		var room: Node3D = world.room_views[id]
		var machines := 0
		for child in room.get_children():
			if child is Node3D and child.has_meta("equipment_kind"):
				machines += 1
		t.expect_equal(machines,1,"one apparatus per base room " + id)
	world.free()


func test_repeated_snapshot_does_not_restart_symptom_animation(t: TestContext) -> void:
	# Break caught: present() resets a visual clock at every snapshot and freezes wrong-order motion.
	var world := _world()
	var snapshot := _sim().snapshot()
	snapshot.patients={"p":{"cell":218,"disease_id":"motion","phase":"treatment_queue","path":[],"move_progress":0}}
	world.present(snapshot)
	var actor: Node3D=world.actor_views.p
	actor._process(0.2)
	if actor._simplified!=null:
		var player:AnimationPlayer=actor._simplified.player
		var before:float=player.current_animation_position
		world.present(snapshot)
		t.expect_true(is_equal_approx(player.current_animation_position,before),"repeated snapshots do not rewind the new character's actual animation")
		actor._process(0.2)
		t.expect_true(player.current_animation_position>before+.01,"new character animation continues over snapshots")
	else:
		var before: float=actor.right_arm.rotation.z
		world.present(snapshot)
		actor._process(0.2)
		t.expect_true(absf(actor.right_arm.rotation.z-before)>0.01,"wrong-order action continues over snapshots")
	world.free()



func test_rotated_doorways_remain_open_at_literal_boundaries(t: TestContext) -> void:
	# Break caught: mesh doorway rotation is independent of authoritative path rotation.
	var catalog: ContentCatalog=ContentCatalog.load_checked("res://content").catalog
	var state:=ClinicState.create("level_01",catalog)
	var world:=_world()
	var expected_doors: Array[Vector3]=[Vector3(7,0,5.5),Vector3(5.5,0,3),Vector3(8,0,1.5),Vector3(9.5,0,4)]
	for rotation_value in range(4):
		var result:=GridService.preview(state,{"kind":"echo","origin_cell":54,"rotation":rotation_value})
		t.expect_true(result.ok,"rotated geometry fixture validates")
		if not result.ok:
			continue
		world.present({"rooms":{"r":result.data.room},"slots":{}})
		for segment in world.room_views.r.wall_segments:
			t.expect_false(segment.get_aabb().has_point(segment.to_local(expected_doors[rotation_value]+Vector3(0,0.15,0))),"literal rotated door is physically open " + str(rotation_value))
	world.free()

func test_reception_footprint_preserves_walkable_gap_in_all_rotations(t: TestContext) -> void:
	# Break caught: averaging the two separated reception equipment cells puts solids in a navigable gap.
	# Literal origin 54=(6,2), size 3: equipment and center gap rotate clockwise around the room.
	var catalog: ContentCatalog=ContentCatalog.load_checked("res://content").catalog
	var state:=ClinicState.create("level_01",catalog)
	var fixtures: Array = [
		{"equipment":[54,56],"gap":55},
		{"equipment":[56,104],"gap":80},
		{"equipment":[104,102],"gap":103},
		{"equipment":[102,54],"gap":78}
	]
	var world:=_world()
	for rotation_value in range(4):
		state.data.rooms={}
		var result:=GridService.preview(state,{"kind":"reception","origin_cell":54,"rotation":rotation_value})
		t.expect_true(result.ok,"reception rotation validates " + str(rotation_value))
		if not result.ok:
			continue
		state.data.rooms={"r":result.data.room}
		var fixture: Dictionary=fixtures[rotation_value]
		t.expect_equal(result.data.room.equipment_cells,fixture.equipment,"literal blocked reception cells " + str(rotation_value))
		t.expect_true(GridService.path(state,217,fixture.gap).size()>0,"center gap remains genuinely navigable " + str(rotation_value))
		world.present({"rooms":state.data.rooms,"slots":{}})
		var meshes: Array[Node]=[]
		for branch in world.room_views.r.get_children():
			if branch is Node3D and branch.get_child_count()>0:
				meshes.append_array(branch.find_children("*","MeshInstance3D",true,false))
		t.expect_true(meshes.size()>0,"reception has rendered equipment geometry")
		var gap: int=fixture.gap
		var gap_volume:=AABB(Vector3(gap%24-0.49,0.04,gap/24-0.49),Vector3(0.98,1.1,0.98))
		var gap_clear:=true
		var footprint_confined:=true
		var covered: Dictionary={}
		for mesh in meshes:
			var bounds: AABB=mesh.global_transform*mesh.get_aabb()
			# A flat alpha grounding mark is not an equipment solid. It may
			# extend slightly beyond the blocked cell, but must stay below the
			# walking volume and must never introduce a physical obstacle.
			if mesh.get_meta("display_only_contact_shadow",false):
				t.expect_true(bounds.end.y<gap_volume.position.y and mesh.find_children("*","CollisionObject3D",true,false).is_empty(),"contact shading stays below the walking volume without collision " + str(rotation_value))
				continue
			gap_clear = gap_clear and not bounds.intersects(gap_volume)
			var fits_one_cell:=false
			for cell in fixture.equipment:
				var x: int=cell%24
				var z: int=cell/24
				if bounds.has_point(Vector3(x,0.15,z)):
					covered[cell]=true
				fits_one_cell = fits_one_cell or (bounds.position.x>=x-0.501 and bounds.end.x<=x+0.501 and bounds.position.z>=z-0.501 and bounds.end.z<=z+0.501)
			footprint_confined = footprint_confined and fits_one_cell
		t.expect_true(gap_clear,"full reception center walking volume has no apparatus " + str(rotation_value))
		t.expect_true(footprint_confined,"every reception solid stays on a literal blocked cell " + str(rotation_value))
		t.expect_equal(covered.size(),2,"both actual reception equipment centers contain physical components " + str(rotation_value))
	world.free()
