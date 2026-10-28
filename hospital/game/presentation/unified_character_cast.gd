class_name UnifiedCharacterCast
extends RefCounted

# A complete cosmetic batch is committed atomically. Any invalid or incomplete
# batch returns empty paths, preserving each caller's existing legacy fallback.
const MANIFEST_PATH: String = "res://assets/models/unified-cast-v1/manifest.json"
const DIRECTORY: String = "res://assets/models/unified-cast-v1/"
const COUNTS: Dictionary = {"doctor":60,"technician":8,"receptionist":8,"patient":48}
const REQUIRED_CLIPS: Array[String] = ["Idle","Walk","Examine"]
const ALLOWED_CLIPS: Array[String] = ["Idle","Walk","Examine","Consult"]
static var _loaded: bool = false
static var _entries: Dictionary = {}

static func entry(canonical: String) -> Dictionary:
	if not _canonical_allowed(canonical):return {}
	_load_entries()
	var value: Dictionary = _entries.get(canonical,{})
	return value.duplicate(true)

static func id_available(canonical: String) -> bool:
	if not _canonical_allowed(canonical):return false
	_load_entries()
	return _entries.has(canonical)

static func model_path(canonical: String) -> String:
	var value: Dictionary = entry(canonical)
	return DIRECTORY+str(value.model) if not value.is_empty() else ""

static func portrait_path(canonical: String) -> String:
	var value: Dictionary = entry(canonical)
	return DIRECTORY+str(value.portrait) if not value.is_empty() else ""

static func walk_speed(canonical: String) -> float:
	var value: Dictionary = entry(canonical)
	return float(value.walk_source_speed) if not value.is_empty() else 0.0

static func reset_for_test() -> void:
	_loaded=false
	_entries={}

static func _canonical_allowed(canonical: String) -> bool:
	if canonical.get_slice_count("-")!=2:return false
	var family: String = canonical.get_slice("-",0)
	var suffix: String = canonical.get_slice("-",1)
	if not COUNTS.has(family) or not suffix.is_valid_int():return false
	var ordinal: int = int(suffix)
	return ordinal>=1 and ordinal<=int(COUNTS[family]) and canonical=="%s-%02d"%[family,ordinal]

static func _safe_filename(value: Variant, expected: String) -> bool:
	return value is String and value==expected and value==value.get_file() and not "/" in value and not "\\" in value and not ":" in value

static func _valid_hash(value: Variant) -> bool:
	return value is String and value.length()==64 and value.is_valid_hex_number(false)

static func _valid_entry(canonical: String, value: Variant) -> bool:
	if not _canonical_allowed(canonical) or not value is Dictionary:return false
	var family: String = canonical.get_slice("-",0)
	if value.get("canonical_asset_id",null)!=canonical or value.get("family",null)!=family:return false
	if not _safe_filename(value.get("model",null),canonical+".glb"):return false
	if not _safe_filename(value.get("portrait",null),canonical+"-portrait.png"):return false
	var speed: Variant = value.get("walk_source_speed",null)
	if typeof(speed) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(speed)) or float(speed)<=0:return false
	var bones: Variant = value.get("expected_bones",null)
	if typeof(bones) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(bones)):return false
	if float(bones)!=float(65 if canonical=="doctor-01" else 20):return false
	if not _valid_hash(value.get("glb_sha256",null)) or not _valid_hash(value.get("portrait_sha256",null)):return false
	var clips: Variant = value.get("clips",null)
	if not clips is Array or clips.size()<3 or clips.size()>4:return false
	var seen: Dictionary = {}
	for clip: Variant in clips:
		if not clip is String or not clip in ALLOWED_CLIPS or seen.has(clip):return false
		seen[clip]=true
	for clip: String in REQUIRED_CLIPS:
		if not seen.has(clip):return false
	if family in ["doctor","patient"] and not seen.has("Consult"):return false
	return true

# Pure validation is also used by the regression script to reject malformed
# in-memory fixtures. Production always checks all actual imported resources.
static func _validated_entries(parsed: Variant, require_resources: bool = true) -> Dictionary:
	if not parsed is Dictionary or parsed.get("schema_version",null)!=1:return {}
	var values: Variant = parsed.get("entries",null)
	if not values is Dictionary or values.size()!=124:return {}
	var candidate: Dictionary = {}
	for family: String in COUNTS:
		for ordinal: int in range(1,int(COUNTS[family])+1):
			var canonical: String = "%s-%02d"%[family,ordinal]
			var value: Variant = values.get(canonical,null)
			if not _valid_entry(canonical,value):return {}
			if require_resources:
				if not ResourceLoader.exists(DIRECTORY+str(value.model)):return {}
				if not ResourceLoader.exists(DIRECTORY+str(value.portrait)):return {}
			candidate[canonical]=value.duplicate(true)
	return candidate

static func _load_entries() -> void:
	if _loaded:return
	_loaded=true
	if not FileAccess.file_exists(MANIFEST_PATH):return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	var candidate: Dictionary = _validated_entries(parsed,true)
	if candidate.size()==124:_entries=candidate
