class_name CharacterRoster
extends RefCounted

# Only the complete, validated batch may extend the existing four identities.
# The simulation's IDs and role vocabulary remain authoritative and unchanged.
const MANIFEST_PATH := "res://assets/models/character-refinement-v6/roster/manifest.json"
const DIRECTORY := "res://assets/models/character-refinement-v6/roster/"
const REFINED_DOCTOR_DIRECTORY := "res://assets/models/doctor-refinement-v11/"
const REFINED_DOCTOR_WALK_SPEED := 1.0663354770576525
const COUNTS := {"doctor":60,"technician":8,"receptionist":8,"patient":48}
const RETAINED := ["doctor-02","patient-01","receptionist-01","technician-03"]
const REQUIRED_CLIPS := ["Idle","Walk","Examine"]
static var _loaded := false
static var _entries: Dictionary = {}

static func entry(canonical: String) -> Dictionary:
	if UnifiedCharacterCast.id_available(canonical):return UnifiedCharacterCast.entry(canonical)
	if not _canonical_allowed(canonical): return {}
	_load_entries()
	var value: Dictionary = _entries.get(canonical,{})
	return value.duplicate(true)

static func model_path(canonical: String) -> String:
	if UnifiedCharacterCast.id_available(canonical):return UnifiedCharacterCast.model_path(canonical)
	var value := entry(canonical)
	if canonical=="doctor-01" and not value.is_empty():return REFINED_DOCTOR_DIRECTORY+"doctor-01.glb"
	return DIRECTORY+str(value.model) if not value.is_empty() else ""

static func portrait_path(canonical: String) -> String:
	if UnifiedCharacterCast.id_available(canonical):return UnifiedCharacterCast.portrait_path(canonical)
	var value := entry(canonical)
	if canonical=="doctor-01" and not value.is_empty():return REFINED_DOCTOR_DIRECTORY+"doctor-01-portrait.png"
	return DIRECTORY+str(value.portrait) if not value.is_empty() else ""

static func walk_speed(canonical: String) -> float:
	if UnifiedCharacterCast.id_available(canonical):return UnifiedCharacterCast.walk_speed(canonical)
	var value := entry(canonical)
	if canonical=="doctor-01" and not value.is_empty():return REFINED_DOCTOR_WALK_SPEED
	return float(value.walk_source_speed) if not value.is_empty() else 0.0

static func _canonical_allowed(canonical: String) -> bool:
	if canonical in RETAINED or canonical.get_slice_count("-")!=2: return false
	var family := canonical.get_slice("-",0)
	var suffix := canonical.get_slice("-",1)
	if not COUNTS.has(family) or not suffix.is_valid_int(): return false
	var index := int(suffix)
	return index>=1 and index<=int(COUNTS[family]) and canonical=="%s-%02d"%[family,index]

static func _safe_filename(value: Variant, expected: String) -> bool:
	return value is String and value==expected and value==value.get_file() and not "/" in value and not "\\" in value and not ":" in value

static func _valid_entry(canonical: String, value: Variant) -> bool:
	if not _canonical_allowed(canonical) or not value is Dictionary: return false
	if value.get("canonical_asset_id","")!=canonical or value.get("family","")!=canonical.get_slice("-",0): return false
	if not _safe_filename(value.get("model",null),canonical+".glb") or not _safe_filename(value.get("portrait",null),canonical+"-portrait.png"): return false
	var speed: Variant = value.get("walk_source_speed",null)
	if typeof(speed) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(speed)) or float(speed)<=0: return false
	var clips: Variant = value.get("clips",null)
	if not clips is Array: return false
	for required: String in REQUIRED_CLIPS:
		if not required in clips: return false
	if value.has("geometry_sha256"):
		var fingerprint: Variant = value.geometry_sha256
		if not fingerprint is String or fingerprint.length()!=64 or not fingerprint.is_valid_hex_number(false): return false
	return true

static func _load_entries() -> void:
	if _loaded: return
	_loaded=true
	if not FileAccess.file_exists(MANIFEST_PATH): return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	if not parsed is Dictionary or parsed.get("schema_version",0)!=1 or not parsed.get("entries",null) is Dictionary: return
	var values: Dictionary = parsed.entries
	if values.size()!=120: return
	for canonical: Variant in values:
		if not canonical is String or not _valid_entry(canonical,values[canonical]): return
	_entries=values.duplicate(true)
