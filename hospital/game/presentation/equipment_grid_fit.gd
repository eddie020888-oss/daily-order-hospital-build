class_name EquipmentGridFit
extends RefCounted

## Presentation contract for NEW version-2 equipment only. The simulation
## registry owns the footprint; every rendered GLB keeps its proportions and
## its actual meshes inside that rectangle. The low plinth makes the whole
## reserved body visible, including deliberately empty safety margins. The
## RoomView assembly owns the only placement yaw: exact quarter turns.
## A sprite wrapper must be added AFTER fit() so its calibrated art is never
## scaled or translated by a GLB fit. The plinth then hides with its fallback.

const MODEL_INSET := 0.12
const PLINTH_INSET := 0.06
const PLINTH_HEIGHT := 0.05
const PLINTH_COLORS := {
	"reception":Color("6a8580"),"diagnosis":Color("d8cbb7"),
	"echo":Color("9a4035"),"motion":Color("426864"),
	"sensory":Color("527b79"),"recovery":Color("638079"),
}


static func body_size(kind:String) -> Vector2i:
	# Version-2 reception is one complete two-cell counter assembly.
	# Recovery is fitted per seat, including the identical upgraded second seat.
	var profile:Dictionary=EquipmentFootprints.profile(kind)
	return profile.get("body_size",Vector2i.ZERO)


static func fit(kind:String,raw_glb:Node3D) -> Node3D:
	if raw_glb==null or raw_glb.get_meta("grid_fit_version",0)==2:return raw_glb
	var size:Vector2i=body_size(kind)
	if size.x<=0 or size.y<=0:return raw_glb
	var before:AABB=visible_bounds(raw_glb)
	if before.size.x<=0.00001 or before.size.z<=0.00001:return raw_glb
	# One multiplier on all axes preserves authored machine proportions. Using
	# the tighter horizontal axis prevents horns/rails from spilling into the
	# adjacent operation or maintenance cells. No nonuniform rectangle stretch.
	var factor:float=minf((float(size.x)-MODEL_INSET)/before.size.x,(float(size.y)-MODEL_INSET)/before.size.z)
	raw_glb.scale*=factor
	var scaled:AABB=visible_bounds(raw_glb)
	var centre:Vector3=scaled.get_center()
	raw_glb.position+=Vector3(-centre.x,HospitalInteriorArt.ROOM_FLOOR_TOP+PLINTH_HEIGHT-scaled.position.y,-centre.z)
	var fitted:AABB=visible_bounds(raw_glb)
	raw_glb.set_meta("grid_fit_version",2)
	raw_glb.set_meta("grid_body_size",size)
	raw_glb.set_meta("grid_model_bounds",fitted)
	raw_glb.set_meta("grid_source_bounds",before)
	raw_glb.set_meta("grid_uniform_multiplier",factor)
	raw_glb.set_meta("grid_yaw_owned_by_assembly",true)
	_add_plinth(raw_glb,kind,size)
	return raw_glb


## Bounds in the immediate parent's coordinates, also before entering a tree.
## Recurse through local transforms so imported multi-node meshes and authored
## roots are measured, rather than assuming an origin or a single GLB mesh.
static func visible_bounds(model:Node3D) -> AABB:
	var bounds:Array[AABB]=[]
	_collect_bounds(model,Transform3D.IDENTITY,bounds)
	if bounds.is_empty():return AABB()
	var result:AABB=bounds[0]
	for index in range(1,bounds.size()):result=result.merge(bounds[index])
	return result


static func _collect_bounds(node:Node,parent_transform:Transform3D,bounds:Array[AABB]) -> void:
	var current:Transform3D=parent_transform
	if node is Node3D:
		if not node.visible:return
		current=parent_transform*node.transform
	if node is MeshInstance3D and node.mesh!=null:
		bounds.append(current*node.get_aabb())
	for child in node.get_children():_collect_bounds(child,current,bounds)


static func _add_plinth(raw_glb:Node3D,kind:String,size:Vector2i) -> void:
	var plinth:=MeshInstance3D.new()
	plinth.name="GridAlignedEquipmentPlinth"
	var mesh:=BoxMesh.new()
	mesh.size=Vector3(float(size.x)-PLINTH_INSET,PLINTH_HEIGHT,float(size.y)-PLINTH_INSET)
	plinth.mesh=mesh
	plinth.material_override=ActorView.material(PLINTH_COLORS.get(kind,Color("527b79")))
	# The plinth is an unscaled rectangle in assembly coordinates, but stays a
	# child of raw_glb so the complete fallback disappears when a sprite is used.
	var at:=Vector3(0,HospitalInteriorArt.ROOM_FLOOR_TOP+PLINTH_HEIGHT*.5,0)
	plinth.transform=raw_glb.transform.affine_inverse()*Transform3D(Basis.IDENTITY,at)
	plinth.set_meta("equipment_body_plinth",true)
	plinth.set_meta("logical_body_size",size)
	raw_glb.add_child(plinth)
