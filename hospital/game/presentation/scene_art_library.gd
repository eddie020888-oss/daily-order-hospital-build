class_name SceneArtLibrary
extends RefCounted

# Cosmetic identity is derived from stable entity IDs, never medical tolerance.
# Existing saves keep their appearance without adding fields to simulation state.
const COUNTS := {"doctor":60,"technician":8,"receptionist":8,"patient":48}
const APPEARANCE_PINS := {"doctor":1,"patient":0,"receptionist":0,"technician":2}
const OFFSETS := {"doctor":0,"technician":60,"receptionist":68,"patient":76}
# D01 is the artwork source label. The existing simulation/cosmetic identity stays
# doctor-02 (normally staff_002); no other doctor receives this body or portrait.
const CHARACTER_OVERRIDES := {"doctor-02":"res://assets/models/characters-v2/doctor-02.glb"}
const PORTRAIT_OVERRIDES := {"doctor-02":"res://assets/characters-prerendered/doctor-02-consult-v1/portrait.png",
	"patient-01":"res://assets/characters-prerendered/patient-01-consult-v1/portrait.png"}
const SIMPLE_PORTRAITS := {"doctor-02":"res://assets/models/simple-clinic-v3/doctor-02-portrait.png",
	"patient-01":"res://assets/models/simple-clinic-v2/patient-01-portrait.png",
	"receptionist-01":"res://assets/models/character-refinement-v6/support/receptionist-01-portrait.png",
	"technician-03":"res://assets/models/character-refinement-v6/support/technician-03-portrait.png"}
const ARTWORK_SOURCE_IDS := {"doctor-02":"D01","patient-01":"P01","receptionist-01":"R01","technician-03":"T01"}
const EQUIPMENT_MODELS := {
	"reception":"res://assets/models/reference-v1/equipment/reception.glb",
	"diagnosis":"res://assets/models/clinical-suite-v1/consult-workstation.glb",
	"echo":"res://assets/models/reference-v1/equipment/echo.glb",
	"motion":"res://assets/models/reference-v1/equipment/motion.glb",
	"sensory":"res://assets/models/reference-v1/equipment/sensory.glb",
	"recovery":"res://assets/models/reference-v1/equipment/recovery.glb"}
const CONSULT_CHAIRS := {"doctor":"res://assets/models/clinical-suite-v1/doctor-chair.glb","patient":"res://assets/models/clinical-suite-v3/patient-chair.glb"}
const EQUIPMENT_THUMBNAILS := {
	"reception":"res://assets/equipment/grid-isometric-v3/reception-thumbnail.png",
	"diagnosis":"res://assets/equipment/grid-isometric-v3/diagnosis-thumbnail.png",
	"echo":"res://assets/equipment/grid-isometric-v3/echo-thumbnail.png",
	"motion":"res://assets/equipment/grid-isometric-v3/motion-thumbnail.png",
	"sensory":"res://assets/equipment/grid-isometric-v3/sensory-thumbnail.png",
	"recovery":"res://assets/equipment/grid-isometric-v3/recovery-thumbnail.png",
	"general_exam":"res://assets/equipment/catalog-isometric-v1/frames/U01-E1-q0.png",
	"pharmacy":"res://assets/equipment/catalog-isometric-v1/frames/U28-E1-q0.png",
	"ward":"res://assets/equipment/catalog-isometric-v1/frames/U23-E1-q0.png"}
static var _scenes: Dictionary={}
static var _portraits: Dictionary={}
static var _atlas: Texture2D
static var _thumbnails: Dictionary={}
static var _painted_meshes: Dictionary={}
static var _clinical_materials: Dictionary={}
const EQUIPMENT_COLORS := {"ivory":"f0e6d7","teal":"527b79","red":"bb6754","brass":"a18b6d","dark":"365352","leather":"cdbba0","blue":"659599","yellow":"c2a66d","paper":"f7efe2","rubber":"3b4947","cushion":"527b79","brown":"a58060","green":"789658"}

static func ordinal(id: String) -> int:
	var tail:=id.get_slice("_",id.get_slice_count("_")-1)
	return maxi(0,int(tail)-1) if tail.is_valid_int() else absi(id.hash())

static func asset_id(role: String, index: int) -> String:
	role=appearance_family(role)
	return "%s-%02d" % [role,posmod(index,COUNTS[role])+1]

static func seeded_index(role: String,index: int,appearance_seed: int) -> int:
	role=appearance_family(role)
	var count: int=COUNTS[role]
	var original := posmod(index,count)
	if appearance_seed<=0:return original
	var pinned: int=APPEARANCE_PINS[role]
	if original==pinned:return pinned
	# Rotate a deck that excludes the retained identity; ordinary unique indices
	# cannot collide with that pin or each other. No medical fields are consulted.
	var rank := original if original<pinned else original-1
	var rotated := posmod(rank+posmod(appearance_seed-1,count-1),count-1)
	return rotated if rotated<pinned else rotated+1

static func appearance_family(role:String) -> String:
	# No nurse body was authored in the original124. Reuse actual employee art
	# explicitly, while the clinical role stays nurse in every simulation record.
	if role=="nurse":return "technician"
	if role in ["pharmacist","engineer","cleaner","logistics"]:return "technician"
	return role if COUNTS.has(role) else "patient"

static func appearance_asset(role:String,index:int,appearance_seed:int=0,explicit_id:String="") -> String:
	var family:=appearance_family(role)
	var tail:=explicit_id.get_slice("-",1)
	if explicit_id.get_slice_count("-")==2 and explicit_id.get_slice("-",0)==family and tail.is_valid_int():
		var ordinal_value:=int(tail)
		if ordinal_value>=1 and ordinal_value<=int(COUNTS[family]) and explicit_id=="%s-%02d"%[family,ordinal_value]:return explicit_id
	return asset_id(role,seeded_index(role,index,appearance_seed))

static func character(role: String, id: String,appearance_seed: int=0,appearance_id:String="") -> Node3D:
	var canonical := appearance_asset(role,ordinal(id),appearance_seed,appearance_id)
	var path: String=CHARACTER_OVERRIDES.get(canonical,"res://assets/models/characters/"+canonical+".glb")
	var result := _instance(path)
	result.set_meta("model_asset",canonical)
	if CHARACTER_OVERRIDES.has(canonical): result.set_meta("artwork_source_id","D01")
	return result

static func equipment(kind: String,footprint_version:int=1) -> Node3D:
	if GridEquipmentFrames.has_catalog(kind):
		# These original four-view assets have no GLB counterpart. An honest empty
		# unsupported-view fallback avoids pretending they are reconstructed meshes.
		var source_only:=Node3D.new()
		source_only.name="CatalogImageSource"
		source_only.set_meta("catalog_source_only",true)
		return EquipmentSprite.create(kind,source_only,{"enabled":true,"footprint_version":2,"catalog_only":true})
	var result := _instance(EQUIPMENT_MODELS[kind])
	if footprint_version==EquipmentFootprints.VERSION:
		EquipmentGridFit.fit(kind,result)
		return EquipmentSprite.create(kind,result,{"enabled":true,"footprint_version":footprint_version})
	if kind=="echo":return EquipmentSprite.create(kind,result,{"enabled":true,"footprint_version":footprint_version})
	if kind in ["diagnosis","echo","motion","sensory"]:return result
	# Authored treatment apparatus retains the reference enamel/brass PBR.
	# Reception/recovery keep their existing matte palette; characters are unchanged.
	for item: MeshInstance3D in result.find_children("*","MeshInstance3D",true,false):
		for surface in range(item.mesh.get_surface_count()):
			var source := item.mesh.surface_get_material(surface) as StandardMaterial3D
			if source==null:continue
			var palette_name := source.resource_name.get_slice(".",0)
			if not EQUIPMENT_COLORS.has(palette_name):continue
			if not _clinical_materials.has(source):
				var material := source.duplicate() as StandardMaterial3D
				material.albedo_color=Color(EQUIPMENT_COLORS[palette_name])
				material.roughness=.78
				material.metallic=.12 if palette_name=="brass" else .0
				material.metallic_specular=.18
				_clinical_materials[source]=material
			item.set_surface_override_material(surface,_clinical_materials[source])
	return result

static func consult_chair(is_staff: bool = true) -> Node3D:
	return _instance(CONSULT_CHAIRS["doctor" if is_staff else "patient"])

static func _instance(path: String) -> Node3D:
	if not _scenes.has(path): _scenes[path]=load(path)
	var scene: PackedScene=_scenes[path]
	var model: Node3D=scene.instantiate() if scene!=null else Node3D.new()
	apply_vertex_colors(model)
	return model

static func apply_vertex_colors(model: Node3D) -> void:
	for item in model.find_children("*","MeshInstance3D",true,false):
		var source: Mesh=item.mesh
		var painted_surfaces:=false
		for surface in range(source.get_surface_count()):
			if source.surface_get_arrays(surface)[Mesh.ARRAY_COLOR]!=null: painted_surfaces=true
		# Reference models retain their authored enamel, upholstery and metallic PBR materials.
		if not painted_surfaces: continue
		if not _painted_meshes.has(source):
			var painted:=ArrayMesh.new()
			for surface in range(source.get_surface_count()):
				var arrays:=source.surface_get_arrays(surface)
				var colors: PackedColorArray=arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR]!=null else PackedColorArray()
				# Compatibility renders vertex data in display color space. glTF stores linear color.
				# Controlled unshaded swatch probe verifies this conversion against albedo_color.
				if RenderingServer.get_current_rendering_method()=="gl_compatibility":
					for i in range(colors.size()): colors[i]=colors[i].linear_to_srgb()
				arrays[Mesh.ARRAY_COLOR]=colors
				painted.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
				var material: StandardMaterial3D=source.surface_get_material(surface).duplicate()
				material.vertex_color_use_as_albedo=not colors.is_empty()
				painted.surface_set_material(surface,material)
			_painted_meshes[source]=painted
		item.mesh=_painted_meshes[source]

static func portrait(role: String, index: int,appearance_seed: int=0,appearance_id:String="") -> Texture2D:
	if role=="nurse":return NurseAppearance.portrait(portrait("technician",index,appearance_seed,appearance_id))
	if role in ["pharmacist","engineer","cleaner","logistics"]:
		return CampaignAppearance.portrait(portrait("technician",index,appearance_seed,appearance_id),role)
	role=appearance_family(role)
	var canonical := appearance_asset(role,index,appearance_seed,appearance_id)
	var selected_index := int(canonical.get_slice("-",1))-1
	var path:String=UnifiedCharacterCast.portrait_path(canonical) if UnifiedCharacterCast.id_available(canonical) else SIMPLE_PORTRAITS.get(canonical,PORTRAIT_OVERRIDES.get(canonical,CharacterRoster.portrait_path(canonical)))
	var high_quality_path := "" if UnifiedCharacterCast.id_available(canonical) else PrerenderedCharacter.high_quality_portrait_path(canonical)
	if not high_quality_path.is_empty():path=high_quality_path
	if not path.is_empty():
		if not _portraits.has(canonical) or _portraits[canonical].resource_path!=path:
			if ResourceLoader.exists(path):
				var rendered: Resource=load(path)
				if rendered is Texture2D:
					rendered.set_meta("model_asset",canonical)
					var artwork_source: String=ARTWORK_SOURCE_IDS.get(canonical,CharacterRoster.entry(canonical).get("artwork_source_id",""))
					if not high_quality_path.is_empty():artwork_source=PrerenderedCharacter._high_quality_manifest(canonical).get("artwork_source_id","")
					rendered.set_meta("artwork_source_id",artwork_source)
					_portraits[canonical]=rendered
		if _portraits.has(canonical):return _portraits[canonical]
	if _atlas==null: _atlas=load("res://assets/models/portraits.png")
	var cell: int=OFFSETS[role]+selected_index
	var result:=AtlasTexture.new()
	result.atlas=_atlas
	result.region=Rect2((cell%12)*192,(cell/12)*192,192,192)
	result.filter_clip=true
	result.set_meta("model_asset",canonical)
	return result

static func actor_portrait(actor:Dictionary,is_staff:bool,appearance_seed:int=0) -> Texture2D:
	var role:String=actor.get("role","patient") if is_staff else "patient"
	return portrait(role,ordinal(str(actor.get("id",""))),appearance_seed,str(actor.get("appearance_id","")))

static func thumbnail(kind: String) -> Texture2D:
	if not _thumbnails.has(kind):
		var path:String=EQUIPMENT_THUMBNAILS.get(kind,GridEquipmentFrames.frame(kind,0).get("path",""))
		if path.is_empty():return null
		_thumbnails[kind]=load(path)
	return _thumbnails[kind]

static func guide_portrait() -> Texture2D:
	# Use the approved R01 portrait region, identical to the original prototype's SVG viewBox.
	var result:=AtlasTexture.new()
	result.atlas=load("res://assets/models/reference-v1/ui/approved-staff-roster.png")
	result.region=Rect2(.40*1086-105,.815*1448-105,210,210)
	result.filter_clip=true
	return result

static func batch_static(parent: Node3D, excluded: Array=[]) -> void:
	# Merge immutable tiles and trim by material. Interactive lamps and walls keep their nodes.
	var batches: Dictionary={}
	var originals: Array[Node]=[]
	for child in parent.get_children():
		if not child is MeshInstance3D or child in excluded: continue
		var mesh: Mesh=child.mesh
		for surface in range(mesh.get_surface_count()):
			var material: Material=child.material_override if child.material_override!=null else mesh.surface_get_material(surface)
			if not batches.has(material):
				var builder:=SurfaceTool.new()
				builder.begin(Mesh.PRIMITIVE_TRIANGLES)
				batches[material]=builder
			batches[material].append_from(mesh,surface,child.transform)
		originals.append(child)
	for material in batches:
		var item:=MeshInstance3D.new()
		item.name="ArchitecturalBatch"
		item.mesh=batches[material].commit()
		item.material_override=material
		parent.add_child(item)
	for item in originals:
		parent.remove_child(item)
		item.queue_free()
