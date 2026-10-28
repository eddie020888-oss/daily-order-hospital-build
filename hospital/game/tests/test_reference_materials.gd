extends SceneTree

func _initialize() -> void:
	var holder:=Node3D.new()
	var native:=MeshInstance3D.new()
	native.mesh=BoxMesh.new()
	var brass:=StandardMaterial3D.new()
	brass.albedo_color=Color("c69b51")
	brass.metallic=.82
	brass.roughness=.26
	native.mesh.material=brass
	holder.add_child(native)
	var painted:=MeshInstance3D.new()
	var source:=BoxMesh.new()
	var arrays:=source.surface_get_arrays(0)
	var colors:=PackedColorArray()
	colors.resize(arrays[Mesh.ARRAY_VERTEX].size())
	colors.fill(Color(.2,.4,.3))
	arrays[Mesh.ARRAY_COLOR]=colors
	var mesh:=ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	mesh.surface_set_material(0,StandardMaterial3D.new())
	painted.mesh=mesh
	holder.add_child(painted)
	SceneArtLibrary.apply_vertex_colors(holder)
	var preserved: bool=native.mesh.surface_get_material(0)==brass and is_equal_approx(brass.metallic,.82) and is_equal_approx(brass.roughness,.26)
	var converted: bool=painted.mesh.surface_get_material(0).vertex_color_use_as_albedo
	print("REFERENCE MATERIALS: native_brass_preserved=%s later_vertex_paint_processed=%s" % [preserved,converted])
	holder.free()
	quit(0 if preserved and converted else 1)
