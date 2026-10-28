extends SceneTree

# Focused regression for the real architectural geometry and production batching path.
# Run: --headless --script res://tests/test_interior_mesh_batch.gd
const Art = preload("res://presentation/hospital_interior_art.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	for box_first in [true,false]:
		_test_mixed_meshes(box_first)
	_test_sconce_glass_is_exposed()
	for failure in failures: print("FAIL: "+failure)
	print("INTERIOR MESH BATCH: %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)

func _test_mixed_meshes(box_first: bool) -> void:
	var fixture := Node3D.new()
	var order := "box-first" if box_first else "round-first"
	if box_first: Art._box(fixture,Vector3(-1,0,0),Vector3(.8,1,.12),Art.TEAL)
	Art._round_box(fixture,Vector3(1,0,0),Vector3(.8,1,.12),Art.TEAL,.04)
	if not box_first: Art._box(fixture,Vector3(-1,0,0),Vector3(.8,1,.12),Art.TEAL)
	var source_triangles := 0
	for child in fixture.get_children(): source_triangles += child.mesh.get_faces().size()/3
	expect(source_triangles==76,order+": source fixture contains 12 box and 64 rounded triangles")
	SceneArtLibrary.batch_static(fixture)
	expect(fixture.get_child_count()==1,order+": same-material solids really merged into one mesh")
	var merged: MeshInstance3D = fixture.get_child(0)
	var faces: PackedVector3Array = merged.mesh.get_faces()
	var round_vertices := 0
	for point in faces:
		if point.x>0: round_vertices += 1
	expect(faces.size()/3==76,order+": actual drawable indices retain all 76 triangles")
	expect(round_vertices==192,order+": actual drawable faces retain all 64 rounded triangles")
	expect(_outward_faces(merged.mesh),order+": all merged faces retain outward normals and Godot front winding")
	fixture.free()

func _outward_faces(mesh: Mesh) -> bool:
	var arrays: Array = mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if indices.is_empty(): return false
	for i in range(0,indices.size(),3):
		var a := vertices[indices[i]]
		var b := vertices[indices[i+1]]
		var c := vertices[indices[i+2]]
		var center := (a+b+c)/3.0
		var origin := Vector3(1 if center.x>0 else -1,0,0)
		var winding := (b-a).cross(c-a).normalized()
		for index in [indices[i],indices[i+1],indices[i+2]]:
			if normals[index].dot(center-origin)<=0: return false
			if winding.dot(normals[index])>-.99: return false
	return true

func _test_sconce_glass_is_exposed() -> void:
	var fixture := Node3D.new()
	Art._sconce(fixture)
	var glass: MeshInstance3D
	for child in fixture.get_children():
		if child.material_override.emission_enabled: glass=child
	var exposed := glass!=null
	if glass!=null:
		var glass_bounds: AABB = glass.transform*glass.mesh.get_aabb()
		for child in fixture.get_children():
			if child==glass: continue
			var bounds: AABB = child.transform*child.mesh.get_aabb()
			# The glass faces +Z in the wall coordinate frame. An opaque shell
			# that covers its center must end behind the visible glass surface.
			if bounds.position.x<glass.position.x and bounds.end.x>glass.position.x and bounds.position.y<glass.position.y and bounds.end.y>glass.position.y:
				exposed = exposed and bounds.end.z+.003<glass_bounds.end.z
	expect(exposed,"sconce warm glass face sits in front of the opaque brass housing")
	fixture.free()
