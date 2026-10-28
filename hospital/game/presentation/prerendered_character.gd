class_name PrerenderedCharacter
extends Node3D

# One cosmetic pilot. The source 3D identity remains independently loadable.
const PILOTS := {"doctor-02":"res://assets/characters-prerendered/doctor-02-consult-v1/manifest.json",
	"patient-01":"res://assets/characters-prerendered/patient-01-consult-v1/manifest.json"}
const HIGH_QUALITY_DIRECTORY := "res://assets/character-pilots-v3/"
const HIGH_QUALITY_FRAMES := {"Idle":4,"Walk":16,"Examine":8,"Consult":16}
const GROUND_DEPTH_SHADER := preload("res://presentation/prerendered_ground_depth.gdshader")
static var _high_quality_manifests: Dictionary={}
var manifest: Dictionary={}
var sprite: Sprite3D
var clip_name := ""
var direction_index := 0
var frame_index := 0
var animation_time := 0.0
var playback_speed := 1.0
var _directory := ""
var _frame_size := Vector2i(192,256)
var _texture_path := ""
var _progress_driven := false
var _ground_material: ShaderMaterial

static func create_for(canonical: String) -> PrerenderedCharacter:
	if not PILOTS.has(canonical): return null
	var path: String=PILOTS[canonical]
	if not FileAccess.file_exists(path): return null
	var parsed: Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	return create_from_manifest(canonical,parsed,path.get_base_dir())

static func create_high_quality_for(canonical: String) -> PrerenderedCharacter:
	var parsed := _high_quality_manifest(canonical)
	return _instantiate(canonical,parsed,HIGH_QUALITY_DIRECTORY+canonical) if not parsed.is_empty() else null

static func high_quality_portrait_path(canonical: String) -> String:
	return HIGH_QUALITY_DIRECTORY+canonical+"/portrait.png" if not _high_quality_manifest(canonical).is_empty() else ""

static func _high_quality_manifest(canonical: String) -> Dictionary:
	if not PILOTS.has(canonical):return {}
	if _high_quality_manifests.has(canonical):return _high_quality_manifests[canonical]
	var directory := HIGH_QUALITY_DIRECTORY+canonical
	var path := directory+"/manifest.json"
	if not FileAccess.file_exists(path):return {}
	var parsed: Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary or parsed.get("version",0)!=3 or not _manifest_valid(canonical,parsed,directory):return {}
	_high_quality_manifests[canonical]=parsed.duplicate(true)
	return _high_quality_manifests[canonical]

static func create_from_manifest(canonical: String, parsed: Variant, directory: String) -> PrerenderedCharacter:
	if not _manifest_valid(canonical,parsed,directory):return null
	return _instantiate(canonical,parsed,directory)

static func _manifest_valid(canonical: String, parsed: Variant, directory: String) -> bool:
	if not PILOTS.has(canonical) or not parsed is Dictionary: return false
	if not _number(parsed.get("version",null)):return false
	if parsed.get("version",0)!=1 and parsed.get("version",0)!=2 and parsed.get("version",0)!=3: return false
	if parsed.get("canonical_asset_id","")!=canonical: return false
	var high_quality: bool=parsed.version==3
	var paged: bool=parsed.version>=2
	if paged and parsed.get("layout","")!="direction-pages": return false
	if not parsed.get("frame_size",null) is Array: return false
	var frame: Array=parsed.get("frame_size",[])
	if parsed.get("directions",0)!=8 or frame.size()!=2: return false
	if not _number(frame[0]) or not _number(frame[1]): return false
	if paged:
		if frame[0]!=384 or frame[1]!=512: return false
	elif frame[0]!=192 or frame[1]!=256: return false
	for field in ["pixel_size","ortho_height","center_height"]:
		if not _number(parsed.get(field,null)): return false
	var expected_ortho_height := 2.4 if high_quality else 2.0
	if not is_equal_approx(parsed.ortho_height,expected_ortho_height) or not is_equal_approx(parsed.pixel_size,expected_ortho_height/float(frame[1])): return false
	if parsed.center_height<0.0 or parsed.center_height>2.0: return false
	if high_quality and not is_equal_approx(parsed.center_height,1.0):return false
	if not parsed.get("camera_offset",null) is Array or parsed.camera_offset.size()!=3: return false
	for component in parsed.camera_offset:
		if not _number(component): return false
	var offset := Vector3(parsed.camera_offset[0],parsed.camera_offset[1],parsed.camera_offset[2])
	if high_quality:
		if not offset.is_equal_approx(CameraRig.VIEW_OFFSET):return false
		if typeof(parsed.get("embedded_chair",null))!=TYPE_BOOL or parsed.embedded_chair:return false
		if not _number(parsed.get("walk_source_speed",null)) or parsed.walk_source_speed<=0:return false
		if not parsed.get("artwork_source_id",null) is String or parsed.artwork_source_id.is_empty():return false
		if not parsed.get("source_blend",null) is String or not parsed.source_blend.ends_with(".blend"):return false
		if parsed.get("portrait",null)!="portrait.png" or not _portrait_valid(directory+"/portrait.png"):return false
	elif offset.length_squared()<.001 or not offset.normalized().is_equal_approx(Vector3(8.5,19,23).normalized()): return false
	if not parsed.get("clips",null) is Dictionary: return false
	for required in ["Idle","Walk","Examine"]:
		if not parsed.clips.has(required):return false
	if high_quality and (parsed.clips.size()!=4 or not parsed.clips.has("Consult")):return false
	for clip in parsed.clips:
		if not parsed.clips.get(clip,null) is Dictionary: return false
		var entry: Dictionary=parsed.clips[clip]
		if not _number(entry.get("frames",null)) or not _number(entry.get("duration",null)): return false
		if entry.frames<1 or entry.frames>128 or entry.frames!=floorf(entry.frames) or entry.duration<=0: return false
		var temporal: bool=high_quality and clip=="Consult" and entry.frames==64
		if high_quality:
			if not HIGH_QUALITY_FRAMES.has(clip) or (entry.frames!=HIGH_QUALITY_FRAMES[clip] and not temporal):return false
			if entry.has("chair_included") and (typeof(entry.chair_included)!=TYPE_BOOL or entry.chair_included):return false
		if not entry.get("atlas_size",null) is Array or entry.atlas_size.size()!=2: return false
		var filenames: Array=[]
		if paged:
			if entry.get("columns",0)!=4: return false
			if not entry.get("pages",null) is Array:return false
			if temporal:
				if not _number(entry.get("frames_per_page",null)) or entry.frames_per_page!=16:return false
				if not _number(entry.get("pages_per_direction",null)) or entry.pages_per_direction!=4:return false
				if not _number(entry.get("directions_per_page",null)):return false
				if entry.get("rows_per_direction",0)!=4 or entry.get("directions_per_page",0)!=1:return false
				if entry.pages.size()!=32 or entry.get("texture","")!=entry.pages[0]:return false
			else:
				if not int(entry.frames) in [4,8,16]:return false
				var rows: int=int(entry.frames)/4
				var directions: int=4/rows
				if entry.get("rows_per_direction",0)!=rows or entry.get("directions_per_page",0)!=directions: return false
				if entry.pages.size()!=8/directions or entry.get("texture","")!=entry.pages[0]: return false
			if entry.atlas_size[0]!=1536 or entry.atlas_size[1]!=2048: return false
			filenames=entry.pages
		else:
			if entry.atlas_size[0]!=192*entry.frames or entry.atlas_size[1]!=256*8: return false
			filenames=[entry.get("texture",null)]
		var seen: Dictionary={}
		for filename in filenames:
			if not _texture_valid(filename,directory,int(entry.atlas_size[0]),int(entry.atlas_size[1])): return false
			if high_quality and seen.has(filename):return false
			seen[filename]=true
	return true

static func _instantiate(canonical: String, parsed: Dictionary, directory: String) -> PrerenderedCharacter:
	var result := PrerenderedCharacter.new()
	result.manifest=parsed.duplicate(true)
	result._directory=directory
	result._frame_size=Vector2i(int(parsed.frame_size[0]),int(parsed.frame_size[1]))
	result.set_meta("model_asset",canonical)
	result.set_meta("artwork_source_id",parsed.get("artwork_source_id",""))
	result.set_meta("manifest_version",int(parsed.version))
	result.set_meta("presentation","high-quality-prerendered-pilot" if parsed.version==3 else "fixed-camera-prerendered-pilot")
	result._build()
	if result.is_high_quality():result.set_process(false)
	return result

static func _number(value: Variant) -> bool:
	return (typeof(value)==TYPE_FLOAT or typeof(value)==TYPE_INT) and is_finite(float(value))

static func _texture_valid(filename: Variant,directory: String,width: int,height: int) -> bool:
	if not filename is String or filename!=filename.get_file() or not filename.ends_with(".png") or "/" in filename or "\\" in filename or ":" in filename: return false
	var path := directory.path_join(filename)
	if not ResourceLoader.exists(path): return false
	var texture: Resource=load(path)
	return texture is Texture2D and texture.get_width()==width and texture.get_height()==height

static func _portrait_valid(path: String) -> bool:
	if not ResourceLoader.exists(path):return false
	var texture: Resource=load(path)
	return texture is Texture2D and texture.get_width()>0 and texture.get_height()>0

func is_high_quality() -> bool:return int(manifest.get("version",0))==3

func embeds_consult_chair() -> bool:
	return bool(manifest.get("embedded_chair",true))

func has_calibrated_walk() -> bool:return is_high_quality()

func walk_cadence(display_velocity: float,fallback: float) -> float:
	return clampf(display_velocity/float(manifest.walk_source_speed),0.0,6.4) if has_calibrated_walk() else fallback

func _build() -> void:
	sprite=Sprite3D.new()
	sprite.name="BakedCharacter"
	sprite.pixel_size=float(manifest.pixel_size)
	sprite.position.y=float(manifest.center_height)
	# A vertical billboard roots depth at the feet. Undo camera foreshortening
	# because the source pixels already contain the fixed camera's inclination.
	var offset: Array=manifest.camera_offset
	var view_direction := Vector3(offset[0],offset[1],offset[2]).normalized()
	sprite.billboard=BaseMaterial3D.BILLBOARD_FIXED_Y
	sprite.scale.y=1.0/sqrt(1.0-view_direction.y*view_direction.y)
	sprite.shaded=false
	sprite.no_depth_test=false
	sprite.fixed_size=false
	sprite.alpha_cut=SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	sprite.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	sprite.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sprite.region_enabled=true
	if is_high_quality():
		_ground_material=ShaderMaterial.new()
		_ground_material.shader=GROUND_DEPTH_SHADER
		_ground_material.set_shader_parameter("center_height",float(manifest.center_height))
		_ground_material.set_shader_parameter("vertical_compensation",sprite.scale.y)
		sprite.material_override=_ground_material
	add_child(sprite)
	var shadow := MeshInstance3D.new()
	shadow.name="FootContactShadow"
	var disk := CylinderMesh.new()
	disk.top_radius=.25;disk.bottom_radius=.25;disk.height=.001;disk.radial_segments=24
	shadow.mesh=disk
	shadow.position.y=.003
	shadow.scale.z=.7
	var material := StandardMaterial3D.new()
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color=Color(.12,.12,.10,.14)
	shadow.material_override=material
	shadow.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shadow)
	present_state("Idle",0,1.0)

func present_state(state: String, heading: float, speed: float) -> void:
	if not is_finite(heading) or not is_finite(speed):return
	_progress_driven=false
	if not manifest.clips.has(state): state="Idle"
	if state!=clip_name:
		clip_name=state
		animation_time=0.0
	direction_index=posmod(roundi(heading/(TAU/8.0)),8)
	playback_speed=clampf(speed,0.0,6.4) if state=="Walk" and has_calibrated_walk() else clampf(speed,.1,3.0)
	_update_frame()

func advance_animation(delta: float) -> void:
	if _progress_driven or not is_finite(delta) or delta<=0:return
	animation_time=fposmod(animation_time+maxf(delta,0.0)*playback_speed,float(manifest.clips[clip_name].duration))
	_update_frame()

func present_progress(state: String, heading: float, progress: float) -> void:
	if not manifest.clips.has(state) or not is_finite(progress) or not is_finite(heading):return
	clip_name=state
	_progress_driven=true
	direction_index=posmod(roundi(heading/(TAU/8.0)),8)
	animation_time=clampf(progress,0,1)*float(manifest.clips[state].duration)
	_update_frame()

func _update_frame() -> void:
	var clip: Dictionary=manifest.clips[clip_name]
	frame_index=mini(int(animation_time/float(clip.duration)*int(clip.frames)),int(clip.frames)-1)
	var filename: String=clip.texture
	var x := frame_index
	var y := direction_index
	if manifest.version>=2:
		if int(clip.frames)==64:
			filename=clip.pages[direction_index*int(clip.pages_per_direction)+frame_index/int(clip.frames_per_page)]
			var local_frame := frame_index%int(clip.frames_per_page)
			x=local_frame%int(clip.columns)
			y=local_frame/int(clip.columns)
		else:
			filename=clip.pages[direction_index/int(clip.directions_per_page)]
			x=frame_index%int(clip.columns)
			y=(direction_index%int(clip.directions_per_page))*int(clip.rows_per_direction)+frame_index/int(clip.columns)
	var path := _directory.path_join(filename)
	# Only this heading page is strongly referenced. Neighbouring actors share
	# the engine resource; no global cache pins every visited action/direction.
	if path!=_texture_path:
		_texture_path=path
		sprite.texture=load(path)
		if _ground_material!=null:
			_ground_material.set_shader_parameter("character_atlas",sprite.texture)
	sprite.region_rect=Rect2(Vector2(x*_frame_size.x,y*_frame_size.y),Vector2(_frame_size))

func _process(delta: float) -> void: advance_animation(delta)
