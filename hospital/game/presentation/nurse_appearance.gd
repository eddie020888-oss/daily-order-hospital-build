class_name NurseAppearance
extends RefCounted

## A marked derivative of existing technician art, not an additional original
## character. Meshes, textures, bones and actions remain shared and read-only;
## only per-instance uniform overrides and a chest-attached role badge are new.
static var _portraits:Dictionary={}

static func decorate(body:Node3D) -> void:
	body.set_meta("clinical_role","nurse")
	body.set_meta("appearance_derivation","existing technician; nurse uniform and role badge")
	for mesh:MeshInstance3D in body.find_children("*","MeshInstance3D",true,false):
		for surface in range(mesh.mesh.get_surface_count()):
			var source:Material=mesh.get_active_material(surface)
			if not source is StandardMaterial3D:continue
			var label:=source.resource_name.to_lower()
			var is_uniform:=false
			for hint:String in ["work shirt","denim apron","muted cloth","teal trim","cream cotton"]:
				if label.contains(hint):is_uniform=true;break
			if not is_uniform:continue
			var material:StandardMaterial3D=source.duplicate()
			material.albedo_texture=null
			material.vertex_color_use_as_albedo=false
			material.albedo_color=Color("80b8b0") if label.contains("apron") or label.contains("trim") else Color("e5eee6")
			material.roughness=.86
			mesh.set_surface_override_material(surface,material)
	var skeletons:=body.find_children("*","Skeleton3D",true,false)
	if skeletons.is_empty():return
	var skeleton:Skeleton3D=skeletons[0]
	var bone:=skeleton.find_bone("chest")
	if bone<0:return
	var attachment:=BoneAttachment3D.new()
	attachment.name="NurseRoleBadge"
	attachment.bone_name="chest"
	skeleton.add_child(attachment)
	var badge:=Node3D.new()
	attachment.add_child(badge)
	# Convert the desired root-local chest point to the bone's rest space, so
	# the badge follows the real chest in Idle/Walk/Examine without floating.
	var desired:=Transform3D(Basis.IDENTITY,Vector3(.11,.95,.17))
	var skeleton_to_body:=Transform3D.IDENTITY
	var cursor:Node3D=skeleton
	while cursor!=null and cursor!=body:
		skeleton_to_body=cursor.transform*skeleton_to_body
		cursor=cursor.get_parent() as Node3D
	badge.transform=skeleton.get_bone_global_rest(bone).affine_inverse()*skeleton_to_body.affine_inverse()*desired
	_box(badge,Vector3.ZERO,Vector3(.14,.105,.018),Color("267b78"))
	_box(badge,Vector3(0,0,.013),Vector3(.08,.025,.006),Color("fff7e6"))
	_box(badge,Vector3(0,0,.014),Vector3(.025,.075,.006),Color("fff7e6"))

static func _box(parent:Node3D,at:Vector3,size:Vector3,color:Color) -> void:
	var item:=MeshInstance3D.new()
	var mesh:=BoxMesh.new();mesh.size=size
	var material:=StandardMaterial3D.new();material.albedo_color=color;material.roughness=.9
	item.mesh=mesh;item.material_override=material;item.position=at
	parent.add_child(item)

static func portrait(source:Texture2D) -> Texture2D:
	if source==null:return null
	var canonical:=str(source.get_meta("model_asset",""))
	if _portraits.has(canonical):return _portraits[canonical]
	var image:Image=source.get_image()
	if image==null:return source
	image=image.duplicate()
	if image.is_compressed() and image.decompress()!=OK:return source
	image.convert(Image.FORMAT_RGBA8)
	var unit:=maxi(1,floori(float(mini(image.get_width(),image.get_height()))/24.0))
	var origin:=Vector2i(image.get_width()-unit*7,image.get_height()-unit*7)
	image.fill_rect(Rect2i(origin,Vector2i(unit*6,unit*6)),Color("267b78"))
	image.fill_rect(Rect2i(origin+Vector2i(unit,unit*2),Vector2i(unit*4,unit)),Color("fff7e6"))
	image.fill_rect(Rect2i(origin+Vector2i(unit*2,unit),Vector2i(unit,unit*4)),Color("fff7e6"))
	var result:=ImageTexture.create_from_image(image)
	result.set_meta("model_asset",canonical)
	result.set_meta("clinical_role","nurse")
	result.set_meta("artwork_source_id",source.get_meta("artwork_source_id",""))
	result.set_meta("derived_from_resource",source.resource_path)
	result.set_meta("appearance_derivation","existing technician portrait plus nurse role badge")
	_portraits[canonical]=result
	return result
