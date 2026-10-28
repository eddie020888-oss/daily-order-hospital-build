class_name ReferenceHallArt
extends Node3D
## Fixed-world 2.5D hospital/courtyard painting, extended from the approved art.
## This is NOT a 3D reconstruction, a light bake, or collision geometry.
## Both the art and optional grid are fixed world children. There is no camera
## parenting, billboard mode, _process, or per-frame screen-position matching.
## Host CameraRig owns navigation, focus/framing, and mathematical cell picking.

const ART_PATH := "res://assets/environment/reference-hall-v1/09-empty-hospital.png"
const CAMPUS_ART_PATH := "res://assets/environment/campus-v1/campus-surroundings.png"
const REFERENCE_VIEW_OFFSET := Vector3(18.0,18.0,18.0)
const REFERENCE_TARGET := Vector3(11.5,0.0,7.5)
const REFERENCE_ZOOM := 22.0
const REFERENCE_VIEWPORT := Vector2(1280.0,720.0)
const REFERENCE_FRAME_SIZE := Vector2(22.0*1280.0/720.0,22.0)
const BACKGROUND_DEPTH := 26.0
# One quad has constant geometry cost. Its extent also covers a long-room fit
# beside a narrow drawer, which may legitimately zoom much farther than26.
const OVERSCAN_SIZE := Vector2(1024.0,1024.0)
const GRID_HEIGHT := 0.035

var art_view: MeshInstance3D
var grid_overlay: Node3D
var _grid_requested := false


func _init() -> void:
	name="ReferenceHallArt"
	set_meta("display_only_environment",true)
	set_meta("source_is_fixed_view_2_5d_original",true)
	set_meta("source_is_3d_reconstruction",false)
	set_meta("overscan_is_clamped_original_edges",false)
	set_meta("overscan_finish","world_registered_courtyard_and_gardens")


func _ready() -> void:
	build()


## Idempotent; the host may call this before adding the helper to the tree.
## Missing art is reported without introducing a hard preload/parse dependency.
func build() -> void:
	if not is_instance_valid(art_view):
		_build_art()
	if not is_instance_valid(grid_overlay):
		_build_grid_overlay()
	grid_overlay.visible=_grid_requested


static func reference_basis() -> Basis:
	# QuadMesh's +Z normal faces the default camera; X/Y match its right/up.
	var outward:Vector3=REFERENCE_VIEW_OFFSET.normalized()
	var right:Vector3=Vector3.UP.cross(outward).normalized()
	var up:Vector3=outward.cross(right).normalized()
	return Basis(right,up,outward)


static func reference_plane_center() -> Vector3:
	# 26m behind the world target along the fixed viewing ray. Its centre is
	# about 57m from the default camera, within the existing camera's far=100.
	return REFERENCE_TARGET-REFERENCE_VIEW_OFFSET.normalized()*BACKGROUND_DEPTH


## Informational calibration only. Never mutates or clamps CameraRig.
## Exact original framing assumes orthographic KEEP_HEIGHT, centred anchor,
## zero h/v offset, and the stated reference viewport/target/zoom/orientation.
static func calibration() -> Dictionary:
	return {
		"view_offset":REFERENCE_VIEW_OFFSET,
		"target":REFERENCE_TARGET,
		"zoom_size":REFERENCE_ZOOM,
		"viewport":REFERENCE_VIEWPORT,
		"original_frame_world_size":REFERENCE_FRAME_SIZE,
		"plane_center":reference_plane_center(),
		"plane_basis":reference_basis(),
		"overscan_world_size":OVERSCAN_SIZE,
		"overscan_content":"one extended hospital/courtyard painting, with continuous paving/low planting beyond its edge; display only, no extra simulated land",
		"reference_source":ART_PATH,
		"displayed_source":CAMPUS_ART_PATH,
		"fixed_world_transform":true,
	}


func _build_art() -> void:
	if not ResourceLoader.exists(ART_PATH):
		push_warning("ReferenceHallArt needs the approved original image: "+ART_PATH)
		return
	var source:Texture2D=load(ART_PATH) as Texture2D
	if source==null:
		push_warning("ReferenceHallArt source is not a Texture2D: "+ART_PATH)
		return
	var source_size:Vector2=source.get_size()
	if source_size.x<=0.0 or source_size.y<=0.0:
		push_warning("ReferenceHallArt source has no image dimensions")
		return
	# Centre/cover preserves the source aspect ratio. The approved 1280x720
	# source is exact; a differently proportioned replacement would be cropped.
	var image_size:Vector2=REFERENCE_FRAME_SIZE
	var aspect:float=source_size.x/source_size.y
	if aspect>REFERENCE_VIEWPORT.x/REFERENCE_VIEWPORT.y:
		image_size.x=REFERENCE_ZOOM*aspect
	else:
		image_size.y=REFERENCE_FRAME_SIZE.x/aspect
	var shader:Shader=load("res://presentation/hospital_surroundings.gdshader")
	var material:=ShaderMaterial.new()
	material.shader=shader
	material.set_shader_parameter("hall_texture",source)
	material.set_shader_parameter("art_uv_scale",OVERSCAN_SIZE/image_size)
	material.set_shader_parameter("overscan_color",Color("e7e2d7"))
	material.set_shader_parameter("garden_grass",Color("9aa67c"))
	material.set_shader_parameter("garden_leaf",Color("5e7950"))
	material.set_shader_parameter("garden_stone",Color("c1ad8c"))
	material.set_shader_parameter("garden_flower",Color("f2deb0"))
	if ResourceLoader.exists(CAMPUS_ART_PATH):
		material.set_shader_parameter("campus_texture",load(CAMPUS_ART_PATH) as Texture2D)
		material.set_shader_parameter("has_campus_art",true)
	var quad:=QuadMesh.new()
	quad.size=OVERSCAN_SIZE
	art_view=MeshInstance3D.new()
	art_view.name="ApprovedOriginal2_5DWorldPlane"
	art_view.mesh=quad
	art_view.material_override=material
	art_view.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	art_view.transform=Transform3D(reference_basis(),reference_plane_center())
	art_view.set_meta("display_only_environment",true)
	art_view.set_meta("original_source",ART_PATH)
	art_view.set_meta("original_source_pixels",source_size)
	art_view.set_meta("original_image_world_size",image_size)
	art_view.set_meta("campus_source",CAMPUS_ART_PATH)
	art_view.set_meta("displayed_source",CAMPUS_ART_PATH if ResourceLoader.exists(CAMPUS_ART_PATH) else ART_PATH)
	art_view.set_meta("campus_is_display_only_not_extra_buildable_land",true)
	art_view.set_meta("overscan_is_clamped_original_edges",false)
	art_view.set_meta("overscan_finish","world_registered_courtyard_and_gardens")
	art_view.set_meta("no_extra_scene_geometry_is_represented",true)
	add_child(art_view)


func set_build_grid_visible(value:bool) -> void:
	_grid_requested=value
	if not is_instance_valid(grid_overlay):
		_build_grid_overlay()
	grid_overlay.visible=value


func _grid_material(color:Color) -> StandardMaterial3D:
	var material:=StandardMaterial3D.new()
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color=color
	material.cull_mode=BaseMaterial3D.CULL_DISABLED
	material.no_depth_test=false
	return material


func _line_view(label:String,points:PackedVector3Array,color:Color) -> MeshInstance3D:
	var lines:=ImmediateMesh.new()
	lines.surface_begin(Mesh.PRIMITIVE_LINES,_grid_material(color))
	for point in points:
		lines.surface_add_vertex(point)
	lines.surface_end()
	var view:=MeshInstance3D.new()
	view.name=label
	view.mesh=lines
	view.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	view.set_meta("display_only_environment",true)
	return view


## Real grid coordinates, never a screen-space grid or a navigation obstacle.
## Cell centres remain x1..22/z1..16; the visible cell boundaries are half units.
func _build_grid_overlay() -> void:
	if is_instance_valid(grid_overlay):
		return
	grid_overlay=Node3D.new()
	grid_overlay.name="BuildGridOverlay"
	grid_overlay.visible=false
	grid_overlay.set_meta("display_only_environment",true)
	grid_overlay.set_meta("protected_rows",[8,9])
	grid_overlay.set_meta("playable_floor_bounds",Rect2(.5,.5,22.0,16.0))
	add_child(grid_overlay)
	var points:=PackedVector3Array()
	for column in range(23):
		var x:float=.5+float(column)
		points.append(Vector3(x,GRID_HEIGHT,.5))
		points.append(Vector3(x,GRID_HEIGHT,16.5))
	for row in range(17):
		var z:float=.5+float(row)
		points.append(Vector3(.5,GRID_HEIGHT,z))
		points.append(Vector3(22.5,GRID_HEIGHT,z))
	grid_overlay.add_child(_line_view("TruePlayableCellLines",points,Color(.30,.49,.46,.24)))
	var lane:=MeshInstance3D.new()
	lane.name="ProtectedRows8And9Hint"
	var lane_mesh:=PlaneMesh.new()
	lane_mesh.size=Vector2(22.0,2.0)
	lane.mesh=lane_mesh
	lane.material_override=_grid_material(Color(.73,.57,.32,.055))
	lane.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lane.position=Vector3(11.5,GRID_HEIGHT-.0005,8.5)
	lane.set_meta("protected_rows",[8,9])
	grid_overlay.add_child(lane)
	var protected_edges:=PackedVector3Array([
		Vector3(.5,GRID_HEIGHT+.001,7.5),Vector3(22.5,GRID_HEIGHT+.001,7.5),
		Vector3(.5,GRID_HEIGHT+.001,9.5),Vector3(22.5,GRID_HEIGHT+.001,9.5)])
	grid_overlay.add_child(_line_view("ProtectedLaneBoundaries",protected_edges,Color(.62,.46,.25,.28)))
	grid_overlay.visible=_grid_requested
