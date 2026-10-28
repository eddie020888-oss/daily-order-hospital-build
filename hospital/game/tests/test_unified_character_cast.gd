extends SceneTree

# This script can run before installation: no static reference to the new class
# is parsed until its actual production script resource has been found/loaded.
const CAST_CLASS_PATH: String = "res://presentation/unified_character_cast.gd"
const CAST_DIRECTORY: String = "res://assets/models/unified-cast-v1/"
const CAST_MANIFEST: String = CAST_DIRECTORY+"manifest.json"
const DOCTOR01_V11: String = "res://assets/models/doctor-refinement-v11/doctor-01.glb"
const DOCTOR01_V11_SHA: String = "36734a5fc91f7baa9dfcee8cf07b6929b0733d20e8fe2b81b9e5769fd728b0fd"
var passed: int = 0
var failed: int = 0
var cast: Script

func _initialize() -> void:
	create_timer(120.0).timeout.connect(func(): push_error("Unified cast test timed out"); quit(2))
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	if value:passed+=1
	else:failed+=1
	print(("UNIFIED PASS: " if value else "UNIFIED FAIL: ")+label)

func _finish() -> void:
	print("UNIFIED RESULT: passed=%d failed=%d"%[passed,failed])
	quit(1 if failed else 0)

func _entry(canonical: String) -> Dictionary:
	var value: Variant = cast.call("entry",canonical)
	return value if value is Dictionary else {}

func _signature(skeleton: Skeleton3D) -> String:
	var parts: PackedStringArray = []
	for bone: int in range(skeleton.get_bone_count()):
		parts.append(str(skeleton.get_bone_pose(bone)))
	return "|".join(parts).sha256_text()

func _skeleton(body: Node) -> Skeleton3D:
	var bones: Array[Node] = body.find_children("*","Skeleton3D",true,false)
	return bones[0] as Skeleton3D if bones.size()==1 else null

func _finite(skeleton: Skeleton3D) -> bool:
	for bone: int in range(skeleton.get_bone_count()):
		if not skeleton.get_bone_global_pose(bone).is_finite():return false
	return true

func _atomic_fixture_checks(raw: Dictionary) -> void:
	var valid: Variant = cast.call("_validated_entries",raw,false)
	check(valid is Dictionary and valid.size()==124,"complete in-memory manifest validates atomically")
	var mutations: Array[Dictionary] = []
	var changed: Dictionary = raw.duplicate(true)
	changed.entries.erase("patient-48")
	mutations.append({"label":"missing identity rejects whole batch","value":changed})
	changed=raw.duplicate(true);changed.entries["doctor-03"].model="../doctor-03.glb"
	mutations.append({"label":"path traversal rejects whole batch","value":changed})
	changed=raw.duplicate(true);changed.entries["doctor-03"].walk_source_speed=-1.0
	mutations.append({"label":"negative speed rejects whole batch","value":changed})
	changed=raw.duplicate(true);changed.entries["doctor-03"].walk_source_speed=NAN
	mutations.append({"label":"nonfinite speed rejects whole batch","value":changed})
	changed=raw.duplicate(true);changed.entries["doctor-03"].glb_sha256="not-a-sha256"
	mutations.append({"label":"invalid hash rejects whole batch","value":changed})
	changed=raw.duplicate(true);changed.entries["doctor-03"].canonical_asset_id="doctor-04"
	mutations.append({"label":"mismatched identity rejects whole batch","value":changed})
	changed=raw.duplicate(true);changed.entries["doctor-03"].clips=["Idle","Walk","Examine"]
	mutations.append({"label":"doctor without Consult rejects whole batch","value":changed})
	changed=raw.duplicate(true);changed.entries["patient-03"].clips=["Idle","Walk","Examine"]
	mutations.append({"label":"patient without Consult rejects whole batch","value":changed})
	changed=raw.duplicate(true);changed.entries["doctor-03"].expected_bones=21
	mutations.append({"label":"wrong bone contract rejects whole batch","value":changed})
	changed=raw.duplicate(true);changed.entries["doctor-03"].clips=["Idle","Walk","Examine","Examine"]
	mutations.append({"label":"duplicate clips reject whole batch","value":changed})
	for mutation: Dictionary in mutations:
		var rejected: Variant = cast.call("_validated_entries",mutation.value,false)
		check(rejected is Dictionary and rejected.is_empty(),str(mutation.label))
	for invalid: String in ["doctor-00","doctor-61","doctor-1","Doctor-01","doctor-+1","patient-49","nurse-01","../doctor-01"]:
		check(not bool(cast.call("id_available",invalid)),"invalid canonical rejected: "+invalid)
	var copy: Dictionary = _entry("doctor-03")
	copy.model="changed.glb"
	var actual: Dictionary = _entry("doctor-03")
	check(actual.get("model","")=="doctor-03.glb","returned entry is a defensive copy")

func _check_every_identity() -> void:
	var counts: Dictionary = {"doctor":60,"technician":8,"receptionist":8,"patient":48}
	var total: int = 0
	for family: String in counts:
		for ordinal: int in range(1,int(counts[family])+1):
			var canonical: String = "%s-%02d"%[family,ordinal]
			var entry: Dictionary = _entry(canonical)
			check(not entry.is_empty() and bool(cast.call("id_available",canonical)),canonical+" registered")
			if entry.is_empty():continue
			var model: String = str(cast.call("model_path",canonical))
			var portrait: String = str(cast.call("portrait_path",canonical))
			check(model==CAST_DIRECTORY+canonical+".glb" and ResourceLoader.exists(model),canonical+" model path exists")
			check(portrait==CAST_DIRECTORY+canonical+"-portrait.png" and ResourceLoader.exists(portrait),canonical+" portrait path exists")
			check(FileAccess.get_sha256(model)==str(entry.glb_sha256),canonical+" installed GLB hash matches manifest")
			check(FileAccess.get_sha256(portrait)==str(entry.portrait_sha256),canonical+" installed portrait hash matches manifest")
			var body: SimplifiedCharacter = SimplifiedCharacter.create_for(canonical)
			check(body!=null,canonical+" actual SimplifiedCharacter instantiates")
			if body==null:continue
			root.add_child(body)
			check(body.get_child_count()>0 and body.get_child(0).scene_file_path==model,canonical+" actual scene is unified model")
			var skeleton: Skeleton3D = _skeleton(body)
			check(skeleton!=null and skeleton.get_bone_count()==int(entry.expected_bones),canonical+" actual bone count")
			var clip_set_matches: bool = body.clips.size()==entry.clips.size()
			for clip: String in entry.clips:
				clip_set_matches=clip_set_matches and body.clips.has(clip)
			check(clip_set_matches,canonical+" actual semantic clips match manifest")
			check(is_equal_approx(float(body.get_meta("walk_source_speed",0.0)),float(entry.walk_source_speed)),canonical+" actual walk speed matches manifest")
			if skeleton!=null:
				for clip: String in entry.clips:
					body.player.play(body.clips[clip])
					var animation: Animation = body.player.get_animation(body.clips[clip])
					body.player.seek(animation.length*.5,true)
					check(_finite(skeleton),canonical+" finite actual pose: "+clip)
			body.free()
			total+=1
	check(total==124,"all 124 actual model instances checked and released sequentially")

func _ordinary_routes() -> void:
	for canonical: String in ["doctor-02","patient-01"]:
		var staff: bool = canonical.begins_with("doctor-")
		var actor: ActorView = ActorView.new()
		actor.entity_id="staff_002" if staff else "patient_001"
		root.add_child(actor)
		actor.present({"role":"doctor","disease_id":"echo","appearance_id":canonical,"cell":100,"phase":"idle"},staff)
		check(actor._simplified!=null and actor._prerendered==null,canonical+" ordinary ActorView selects unified 3D")
		if actor._simplified!=null:
			check(actor._simplified.get_child(0).scene_file_path==CAST_DIRECTORY+canonical+".glb",canonical+" ordinary model path")
		var portrait: Texture2D = SceneArtLibrary.portrait("doctor" if staff else "patient",1 if staff else 0,0,canonical)
		check(portrait!=null and portrait.resource_path==CAST_DIRECTORY+canonical+"-portrait.png",canonical+" ordinary UI selects same-model unified portrait")
		actor.free()
		var legacy: ActorView = ActorView.new()
		legacy.entity_id="staff_002" if staff else "patient_001"
		legacy.prefer_simplified=false
		root.add_child(legacy)
		legacy.present({"role":"doctor","disease_id":"echo","appearance_id":canonical,"cell":100,"phase":"idle"},staff)
		check(legacy._simplified==null and legacy._prerendered!=null,canonical+" explicit legacy preference retains old pilot")
		if legacy._prerendered!=null:
			check(not legacy._prerendered.is_high_quality() and legacy._body_root.get_meta("model_asset","")==canonical,canonical+" legacy fallback remains the original identity pilot")
		legacy.free()
	var nurse: ActorView = ActorView.new()
	nurse.entity_id="staff_061"
	root.add_child(nurse)
	nurse.present({"role":"nurse","appearance_id":"technician-01","cell":100,"phase":"idle"},true)
	check(nurse._simplified!=null and nurse._body_root.get_meta("clinical_role","")=="nurse","nurse still derives from own unified technician body")
	check(not nurse._body_root.find_children("NurseRoleBadge","BoneAttachment3D",true,false).is_empty(),"nurse badge attaches to actual retained chest bone")
	var nurse_portrait: Texture2D = SceneArtLibrary.portrait("nurse",0,0,"technician-01")
	check(nurse_portrait!=null and nurse_portrait.get_meta("clinical_role","")=="nurse" and nurse_portrait.get_meta("derived_from_resource","")==CAST_DIRECTORY+"technician-01-portrait.png","nurse UI derives from new unified portrait")
	nurse.free()
	for role: String in ["pharmacist","engineer","cleaner","logistics"]:
		var employee: ActorView = ActorView.new()
		employee.entity_id="staff_062"
		root.add_child(employee)
		employee.present({"role":role,"appearance_id":"technician-01","cell":100,"phase":"idle"},true)
		check(employee._simplified!=null and employee._body_root.get_meta("clinical_role","")==role,role+" still derives from unified technician")
		check(not employee._body_root.find_children("CampaignRoleBadge","BoneAttachment3D",true,false).is_empty(),role+" role badge attaches to retained chest")
		var role_portrait: Texture2D = SceneArtLibrary.portrait(role,0,0,"technician-01")
		check(role_portrait!=null and role_portrait.get_meta("clinical_role","")==role and role_portrait.get_meta("derived_from_resource","")==CAST_DIRECTORY+"technician-01-portrait.png",role+" portrait derives from correct new body identity")
		employee.free()

func _motion_checks() -> void:
	for canonical: String in ["doctor-01","doctor-02","patient-01","receptionist-01","technician-03"]:
		var body: SimplifiedCharacter = SimplifiedCharacter.create_for(canonical)
		check(body!=null,canonical+" motion sample instantiates")
		if body==null:continue
		root.add_child(body)
		var skeleton: Skeleton3D = _skeleton(body)
		if skeleton==null:
			check(false,canonical+" motion sample skeleton exists")
			body.free()
			continue
		body.present_state("Walk",1.0,true)
		body.advance_animation(.13)
		var first: String = _signature(skeleton)
		var before: float = body.player.current_animation_position
		body.advance_animation(.11)
		check(body.player.current_animation_position>before and _signature(skeleton)!=first,canonical+" Walk advances real bones")
		body.present_state("Walk",1.0,false)
		before=body.player.current_animation_position
		first=_signature(skeleton)
		body.advance_animation(.2)
		check(is_equal_approx(body.player.current_animation_position,before) and _signature(skeleton)==first,canonical+" pause freezes actual Walk pose")
		var speed: float = float(cast.call("walk_speed",canonical))
		check(is_equal_approx(body.walk_cadence(1.2,1.0),clampf(1.2/speed,0.0,6.4)),canonical+" cadence uses its registered source speed")
		if body.can_consult():
			var length: float = body.player.get_animation(body.clips["Consult"]).length
			body.present_progress("Consult",.5,false,1)
			check(is_equal_approx(body.player.current_animation_position,length*.5),canonical+" Consult seeks actual midpoint")
			before=body.player.current_animation_position
			first=_signature(skeleton)
			body.advance_animation(.3)
			check(is_equal_approx(body.player.current_animation_position,before) and _signature(skeleton)==first,canonical+" paused Consult remains still")
			body.present_progress("Consult",.51,true,1)
			body.advance_animation(.025)
			check(body.player.current_animation_position>length*.5 and body.player.current_animation_position<length*.51,canonical+" resumed Consult interpolates between simulation ticks")
			body.present_progress("Consult",.51,true,2)
			body.advance_animation(.0375)
			check(is_equal_approx(body.player.current_animation_position,length*.51),canonical+" Consult speed switch preserves target time")
			body.present_state("Walk",1.0,true)
			body.advance_animation(.13)
			check(body.clip_name=="Walk" and body.player.current_animation_position>0,canonical+" departure restores Walk")
		body.free()

func _run() -> void:
	check(ResourceLoader.exists(CAST_CLASS_PATH),"production UnifiedCharacterCast script exists; missing means not installed")
	if failed>0:
		_finish()
		return
	cast=load(CAST_CLASS_PATH) as Script
	check(cast!=null and cast.can_instantiate(),"production UnifiedCharacterCast script loads")
	if failed>0:
		_finish()
		return
	check(FileAccess.file_exists(CAST_MANIFEST),"production complete-batch manifest exists")
	if failed>0:
		_finish()
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CAST_MANIFEST))
	check(parsed is Dictionary,"production manifest parses as dictionary")
	if not parsed is Dictionary:
		_finish()
		return
	cast.call("reset_for_test")
	check(bool(cast.call("id_available","doctor-01")),"installed full-batch gate opens")
	if failed>0:
		_finish()
		return
	_atomic_fixture_checks(parsed)
	_check_every_identity()
	check(FileAccess.get_sha256(DOCTOR01_V11)==DOCTOR01_V11_SHA,"retained original doctor01 v11 source is unchanged")
	check(FileAccess.get_sha256(CAST_DIRECTORY+"doctor-01.glb")==DOCTOR01_V11_SHA,"unified doctor01 is byte-identical to retained v11")
	_ordinary_routes()
	_motion_checks()
	_finish()
