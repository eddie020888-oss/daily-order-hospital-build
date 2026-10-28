class_name RoomFurniture
extends RefCounted

static func create(kind:String,footprint_version:int=1) -> Node3D:
	var result:=Node3D.new()
	result.name="PlayerFurniture"
	result.set_meta("furniture_kind",kind)
	if kind=="plant":
		var plant:Node3D=load("res://assets/models/interior-v2/plant.glb").instantiate()
		var bounds:=_bounds(plant,Transform3D.IDENTITY)
		var factor:=minf(.78/maxf(bounds.size.x,bounds.size.z),1.25/maxf(.001,bounds.size.y))
		plant.scale*=factor
		plant.position.y=-bounds.position.y*factor
		result.add_child(plant)
	elif kind=="bench":
		var wide:bool=footprint_version==EquipmentFootprints.VERSION
		for x in ([-.64,.64] if wide else [-.27,.27]):
			for z in [-.22,.22]:_box(result,Vector3(x,.18,z),Vector3(.065,.36,.065),HospitalInteriorArt.WOOD,.02)
		for x in ([-.40,.40] if wide else [0.0]):
			_box(result,Vector3(x,.40,0),Vector3(.72,.15,.64),HospitalInteriorArt.TEAL,.075)
			_box(result,Vector3(x,.69,-.26),Vector3(.72,.51,.12),HospitalInteriorArt.TEAL,.055)
		for x in ([-.77,.77] if wide else [-.33,.33]):_box(result,Vector3(x,.57,.02),Vector3(.07,.07,.57),HospitalInteriorArt.WOOD,.025)
	elif kind=="cabinet":
		_box(result,Vector3(0,.48,0),Vector3(.72,.96,.53),HospitalInteriorArt.CREAM,.035)
		_box(result,Vector3(0,.985,0),Vector3(.76,.05,.57),HospitalInteriorArt.WOOD,.02)
		for y in [.19,.47,.75]:
			_box(result,Vector3(0,y,.274),Vector3(.65,.245,.025),HospitalInteriorArt.PAPER,.015)
			_box(result,Vector3(0,y+.04,.30),Vector3(.18,.025,.035),HospitalInteriorArt.TEAL_DARK,.01)
	elif kind=="bin":
		ActorView.cylinder(result,Vector3(0,.23,0),.19,.46,HospitalInteriorArt.TEAL)
		_box(result,Vector3(0,.47,0),Vector3(.42,.075,.42),HospitalInteriorArt.TEAL_DARK,.06)
		_box(result,Vector3(0,.515,0),Vector3(.15,.015,.04),HospitalInteriorArt.CREAM,.01)
	SceneArtLibrary.batch_static(result)
	return result

static func placement_offset(kind:String,rotation_value:int,footprint_version:int=1) -> Vector3:
	if footprint_version!=EquipmentFootprints.VERSION:return Vector3.ZERO
	var size:=EquipmentFootprints.furniture_size(kind,rotation_value)
	return Vector3((size.x-1)*.5,0,(size.y-1)*.5)

static func _box(parent:Node3D,at:Vector3,size:Vector3,color:Color,radius:float) -> void:
	HospitalInteriorArt._round_box(parent,at,size,color,radius)

static func _bounds(node:Node3D,parent_transform:Transform3D) -> AABB:
	var transform:=parent_transform*node.transform
	var result:=AABB()
	if node is MeshInstance3D and node.mesh!=null:result=transform*node.mesh.get_aabb()
	for child in node.get_children():
		if child is Node3D:
			var child_bounds:=_bounds(child,transform)
			if child_bounds.size.length_squared()>.00001:result=result.merge(child_bounds) if result.size.length_squared()>.00001 else child_bounds
	return result
