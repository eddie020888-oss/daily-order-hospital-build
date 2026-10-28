class_name CampaignAppearance
extends RefCounted

## Clear role derivatives of existing technician bodies, not new character
## identities. Only instance materials/badges and copied avatar pixels change.
const DERIVATIVES := {"pharmacist":{"color":"8c82a8","uniform":"e6e9df","mark":"P"},
	"engineer":{"color":"aa8250","uniform":"bfa276","mark":"E"},
	"cleaner":{"color":"498d9b","uniform":"91bfc4","mark":"C"},
	"logistics":{"color":"6d9567","uniform":"a8b99c","mark":"L"}}
static var _portraits:Dictionary={}

static func decorate(body:Node3D,role:String) -> void:
	body.set_meta("clinical_role",role)
	if not DERIVATIVES.has(role):return
	body.set_meta("appearance_derivation","existing technician body; per-instance uniform and role badge")
	var profile:Dictionary=DERIVATIVES[role]
	for mesh:MeshInstance3D in body.find_children("*","MeshInstance3D",true,false):
		for surface:int in range(mesh.mesh.get_surface_count()):
			var source:Material=mesh.get_active_material(surface)
			if not source is StandardMaterial3D:continue
			var label:=source.resource_name.to_lower()
			var uniform:=false
			for hint:String in ["work shirt","denim apron","muted cloth","teal trim","cream cotton"]:
				if label.contains(hint):uniform=true;break
			if not uniform:continue
			var material:StandardMaterial3D=source.duplicate()
			material.albedo_texture=null;material.vertex_color_use_as_albedo=false
			material.albedo_color=Color(profile.color) if label.contains("apron") or label.contains("trim") else Color(profile.uniform)
			material.roughness=.86
			mesh.set_surface_override_material(surface,material)
	var skeletons:=body.find_children("*","Skeleton3D",true,false)
	if skeletons.is_empty():return
	var skeleton:Skeleton3D=skeletons[0]
	var bone:=skeleton.find_bone("chest")
	if bone<0:return
	var attachment:=BoneAttachment3D.new();attachment.name="CampaignRoleBadge";attachment.bone_name="chest"
	skeleton.add_child(attachment)
	var badge:=Node3D.new();attachment.add_child(badge)
	var skeleton_to_body:=Transform3D.IDENTITY
	var cursor:Node3D=skeleton
	while cursor!=null and cursor!=body:
		skeleton_to_body=cursor.transform*skeleton_to_body;cursor=cursor.get_parent() as Node3D
	badge.transform=skeleton.get_bone_global_rest(bone).affine_inverse()*skeleton_to_body.affine_inverse()*Transform3D(Basis.IDENTITY,Vector3(.11,.95,.17))
	var card:=MeshInstance3D.new();var box:=BoxMesh.new();box.size=Vector3(.14,.105,.018)
	var material:=StandardMaterial3D.new();material.albedo_color=Color(profile.color);material.roughness=.9
	card.mesh=box;card.material_override=material;badge.add_child(card)
	var label:=Label3D.new();label.text=profile.mark;label.font_size=48;label.pixel_size=.0013
	label.modulate=Color("fff7e6");label.outline_size=0;label.position.z=.014
	badge.add_child(label)

static func portrait(source:Texture2D,role:String) -> Texture2D:
	if source==null or not DERIVATIVES.has(role):return source
	var canonical:=str(source.get_meta("model_asset",""))
	var key:=role+":"+canonical
	if _portraits.has(key):return _portraits[key]
	var image:Image=source.get_image()
	if image==null:return source
	image=image.duplicate()
	if image.is_compressed() and image.decompress()!=OK:return source
	image.convert(Image.FORMAT_RGBA8)
	var unit:=maxi(1,floori(float(mini(image.get_width(),image.get_height()))/24.0))
	var origin:=Vector2i(image.get_width()-7*unit,image.get_height()-7*unit)
	image.fill_rect(Rect2i(origin,Vector2i(6*unit,6*unit)),Color(DERIVATIVES[role].color))
	# A broad white centre mark stays legible in the48px staff card. Role text
	# is shown by the actual UI; no fake new face/portrait asset is registered.
	image.fill_rect(Rect2i(origin+Vector2i(unit,unit*2),Vector2i(unit*4,unit*2)),Color("fff7e6"))
	var result:=ImageTexture.create_from_image(image)
	result.set_meta("model_asset",canonical);result.set_meta("clinical_role",role)
	result.set_meta("artwork_source_id",source.get_meta("artwork_source_id",""))
	result.set_meta("derived_from_resource",source.resource_path)
	result.set_meta("appearance_derivation","existing technician portrait plus role badge")
	_portraits[key]=result
	return result
