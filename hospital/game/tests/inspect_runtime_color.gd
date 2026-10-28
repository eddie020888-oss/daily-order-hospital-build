extends SceneTree
func _initialize() -> void:
	var scene: Node3D=load("res://assets/models/characters/doctor-01.glb").instantiate()
	for item in scene.find_children("*","MeshInstance3D",true,false):
		var mesh: Mesh=item.mesh
		var colors: PackedColorArray=mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
		var mat: StandardMaterial3D=mesh.surface_get_material(0)
		print("COLOR INSPECT: ",item.name," count=",colors.size()," first=",colors[0]," use=",mat.vertex_color_use_as_albedo," albedo=",mat.albedo_color)
	scene.free()
	quit()
