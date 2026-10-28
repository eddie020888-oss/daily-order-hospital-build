extends SceneTree
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	root.size=Vector2i(800,200)
	var stage:=Node3D.new();root.add_child(stage)
	var cam:=Camera3D.new();cam.projection=Camera3D.PROJECTION_ORTHOGONAL;cam.size=2
	cam.position=Vector3(0,0,10);stage.add_child(cam)
	var source:=Color("24616a")
	for i in range(4):
		var arrays:=BoxMesh.new().get_mesh_arrays()
		var colors:=PackedColorArray();colors.resize(arrays[Mesh.ARRAY_VERTEX].size())
		colors.fill(source.srgb_to_linear() if i==2 else source)
		arrays[Mesh.ARRAY_COLOR]=colors
		var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		var material:=StandardMaterial3D.new();material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color=source if i==0 else Color.WHITE
		material.vertex_color_use_as_albedo=i>0
		material.vertex_color_is_srgb=i==3
		var item:=MeshInstance3D.new();item.mesh=mesh;item.material_override=material;item.position.x=-3+i*2
		stage.add_child(item)
	for _i in range(3): await process_frame; await RenderingServer.frame_post_draw
	var img:=root.get_texture().get_image()
	for i in range(4): print("PROBE COLOR ",i," ",img.get_pixel(100+i*200,100))
	img.save_png("E:/CODEX/2026-10-19/医院场景美术实装/reports/vertex-color-probe.png")
	quit()
