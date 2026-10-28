class_name ActorView
extends Node3D

# Runtime art follows the approved toy 3D direction; simulation snapshots remain read-only.
static var materials: Dictionary = {}
const NAVY := Color("253e54")
const MINT := Color("62c6b1")
const ORANGE := Color("f4a45d")
var symptoms: Node3D
var cure_feedback: Node3D
var symptom_kind := ""
var left_arm: Node3D
var right_arm: Node3D
var left_foot: Node3D
var right_foot: Node3D
var entity_id := ""
var work_target:=Vector3.INF
var consultation_context: Dictionary={}
var interaction_context: Dictionary={}
var _interaction_root: Node3D
var _interaction_fill: MeshInstance3D
var _interaction_label: Label3D
var _body_root: Node3D
var _operating := false
var _identity := ""
var _phase := ""
var _walk := false
var _time := 0.0
var _rig_player: AnimationPlayer
var _prerendered: PrerenderedCharacter
var _simplified: SimplifiedCharacter
var prefer_simplified := true
var prefer_high_quality := true
var appearance_seed: int = 0
var presentation_paused := true
var presentation_speed := 1
var presentation_tick := 0
var _visual_motion := ActorVisualMotion.new()
# Explicit per-instance fallback for source-rig inspection; ordinary game uses the pilot.
var prefer_prerendered := true
var _rig_clips: Dictionary={}
var _rig_state := ""
var _motion_position := Vector3.INF
var _motion_elapsed := 0.0
var _travel_speed := 2.5
var _route_active := false
# Keep a readable gait at the existing fast grid speed. Source stride is short;
# exact foot locking would require 11-23x playback and visibly flicker on phones.
# Navigation owns displacement; a longer authored stride is a separate art task.
const RIG_NAVIGATION_SPEED := 2.5
const RIG_BASE_CADENCE := 1.6
const RIG_MAX_CADENCE := 2.4
const HALL_FLOOR_TOP := .0005

static func material(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if not materials.has(key):
		var result := StandardMaterial3D.new()
		result.albedo_color = color
		result.roughness = 0.9
		result.metallic_specular = 0.12
		materials[key] = result
	return materials[key]

static func part(parent: Node3D, mesh: Mesh, at: Vector3, color: Color, scale_value := Vector3.ONE) -> MeshInstance3D:
	var item := MeshInstance3D.new()
	item.mesh = mesh
	item.material_override = material(color)
	item.position = at
	item.scale = scale_value
	parent.add_child(item)
	return item

static func ball(parent: Node3D, at: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 12
	mesh.rings = 6
	return part(parent,mesh,at,color,size)

static func box(parent: Node3D, at: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return part(parent,mesh,at,color)

static func cylinder(parent: Node3D, at: Vector3, radius: float, height: float, color: Color) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 20
	return part(parent,mesh,at,color)

static func ring(parent: Node3D, at: Vector3, radius: float, color: Color) -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = radius - 0.024
	mesh.outer_radius = radius + 0.024
	mesh.rings = 20
	mesh.ring_segments = 6
	return part(parent,mesh,at,color)

func present(actor: Dictionary, is_staff: bool) -> void:
	var identity: String = actor.get("role", "patient") if is_staff else actor.get("disease_id", "echo")
	var family := identity if is_staff else "patient"
	var canonical := SceneArtLibrary.appearance_asset(family,SceneArtLibrary.ordinal(entity_id),appearance_seed,str(actor.get("appearance_id","")))
	var appearance:=identity+":"+canonical
	if _identity != appearance:
		_identity = appearance
		_build(identity,is_staff,canonical)
		_time = float(actor.get("cell",0))*0.37
	position = HospitalWorld.actor_position(actor)
	_visual_motion.present(position,presentation_tick,presentation_paused,presentation_speed)
	_apply_visual_offset(_visual_motion.offset())
	_phase = actor.get("phase", actor.get("status","idle"))
	_walk = int(actor.get("move_progress",0)) > 0
	_operating = _phase in ["serving","working","care_service","reception_service","diagnosis_service","treatment_service","general_exam_service","pharmacy_service","ward_service"]
	if not interaction_context.is_empty(): _operating = bool(interaction_context.get("active", false)) and interaction_context.get("clip", "Examine") != "Idle"
	if is_staff and actor.has("work_order_id") and str(actor.get("status","")) in ["working","serving"]:_operating=true
	var path: Array=actor.get("path",[])
	var index: int=actor.get("path_index",0)
	# Queue relocation and personal trips retain the queue/support phase.
	# Keep its real remaining route visible at a move_progress==0 cell boundary.
	var personal_route: bool=actor.get("need_activity",{}).get("state","")=="walking"
	var queue_route: bool=_phase in ["care_queue","waiting_support"] and (int(actor.get("queue_cell",-1))>=0 or personal_route)
	_route_active=_walk or ((_phase.begins_with("moving") or queue_route or is_staff and actor.get("status", "") == "walking") and index>=0 and index+1<path.size())
	if _rig_player!=null or _prerendered!=null or _simplified!=null:
		if not _motion_position.is_finite() or (_route_active and _rig_state!="Walk"):
			_motion_position=position
			_motion_elapsed=0.0
			_travel_speed=2.5
		var distance := position.distance_to(_motion_position) if _motion_position.is_finite() else 0.0
		if distance>.00001:
			if _motion_elapsed>.001 and _motion_elapsed<=.25 and distance<1.1:
				_travel_speed=clampf(distance/_motion_elapsed,.1,10.0)
			_motion_position=position
			_motion_elapsed=0.0
		_body_root.position.y=_rig_floor_top(actor)-.05
		if _rig_player!=null: _update_rig_animation()
	if (_walk or queue_route) and index>=0 and index+1<path.size():
		var direction:=HospitalWorld.cell_position(path[index+1])-HospitalWorld.cell_position(path[index])
		_body_root.rotation.y=atan2(direction.x,direction.z)
	elif _operating and work_target.is_finite():
		var direction:=work_target-position
		_body_root.rotation.y=atan2(direction.x,direction.z)
	var actual_interaction: bool = not _route_active and interaction_context.get("active", false)
	if actual_interaction: _body_root.rotation.y = float(interaction_context.get("heading", _body_root.rotation.y))
	if _prerendered!=null:
		_prerendered.set_process(not presentation_paused and not _prerendered.is_high_quality())
		var state := "Walk" if _route_active else "Examine" if _operating else "Idle"
		_rig_state=state
		var cadence := clampf(RIG_BASE_CADENCE*_travel_speed/RIG_NAVIGATION_SPEED,.65,RIG_MAX_CADENCE) if state=="Walk" else 1.0
		if _prerendered.is_high_quality():
			cadence=_prerendered.walk_cadence(_visual_motion.display_velocity(),cadence) if state=="Walk" else float(maxi(1,presentation_speed))
		if _operating and not _route_active and not consultation_context.is_empty() and _prerendered.manifest.clips.has("Consult"):
			_body_root.rotation.y=float(consultation_context.heading)
			_prerendered.present_progress("Consult",_body_root.rotation.y,float(consultation_context.progress))
		elif actual_interaction:
			_rig_state = str(interaction_context.get("clip", "Examine"))
			_prerendered.present_progress(_rig_state, _body_root.rotation.y, float(interaction_context.progress))
		else:_prerendered.present_state(state,_body_root.rotation.y,cadence)
	if _simplified!=null:
		var state := "Walk" if _route_active else "Examine" if _operating else "Idle"
		_rig_state=state
		if _operating and not _route_active and not consultation_context.is_empty() and _simplified.can_consult():
			_body_root.rotation.y=float(consultation_context.heading)
			_simplified.present_progress("Consult",float(consultation_context.progress),not presentation_paused,presentation_speed)
		elif actual_interaction:
			_rig_state = str(interaction_context.get("clip", "Examine"))
			_simplified.present_progress(_rig_state, float(interaction_context.progress), not presentation_paused, presentation_speed)
		else:
			var cadence:=clampf(RIG_BASE_CADENCE*_travel_speed/RIG_NAVIGATION_SPEED,.65,RIG_MAX_CADENCE) if state=="Walk" else 1.0
			if state=="Walk":cadence=_simplified.walk_cadence(_visual_motion.display_velocity(),cadence)
			_simplified.present_state(state,cadence,not presentation_paused)
	var cured: bool = actor.get("services_complete",false) or _phase in ["recovering","moving_recovery","waiting_recovery","leaving"]
	if actor.has("case_id"):
		# Exit is also used by abandonment and referral. Only an actually finished
		# treatment route may display the existing green cure motif.
		var steps: Array=actor.get("steps",[])
		cured=not steps.is_empty() and int(actor.get("step_index",-1))==steps.size() and actor.get("stage","")=="exit" and str(actor.get("outcome","")) in ["","completed"]
	symptoms.visible = not is_staff and not cured and not actual_interaction and not ((_prerendered!=null and _prerendered.clip_name=="Consult") or (_simplified!=null and _simplified.can_consult() and _simplified.clip_name=="Consult"))
	cure_feedback.visible = not is_staff and cured
	_present_interaction(actual_interaction)
	set_process(true)

func _build(identity: String, is_staff: bool,canonical: String="") -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	var role:=identity if is_staff else "patient"
	if canonical.is_empty():canonical=SceneArtLibrary.asset_id(role,SceneArtLibrary.seeded_index(role,SceneArtLibrary.ordinal(entity_id),appearance_seed))
	set_meta("model_asset",canonical)
	_prerendered=PrerenderedCharacter.create_high_quality_for(str(get_meta("model_asset"))) if prefer_high_quality and prefer_simplified and prefer_prerendered and not UnifiedCharacterCast.id_available(str(get_meta("model_asset"))) else null
	_simplified=SimplifiedCharacter.create_for(str(get_meta("model_asset"))) if prefer_simplified and _prerendered==null else null
	if _prerendered==null and _simplified==null and prefer_prerendered:
		_prerendered=PrerenderedCharacter.create_for(str(get_meta("model_asset")))
	_body_root=_simplified if _simplified!=null else _prerendered if _prerendered!=null else SceneArtLibrary.character(role,entity_id,appearance_seed,canonical)
	_body_root.name="CharacterModel"
	add_child(_body_root)
	if is_staff and identity=="nurse":NurseAppearance.decorate(_body_root)
	elif is_staff:CampaignAppearance.decorate(_body_root,identity)
	if _prerendered==null:
		var contact:=ContactShadow.create(Vector2(.39,.30),.18)
		contact.position.y=.004
		_body_root.add_child(contact)
	_rig_player=null
	_rig_clips.clear()
	_rig_state=""
	_motion_position=Vector3.INF
	_motion_elapsed=0.0
	_travel_speed=2.5
	left_arm=null;right_arm=null;left_foot=null;right_foot=null
	if _simplified==null and _prerendered==null and not _configure_rig():
		left_arm=_joint("ArmL",Vector3(-.20,.82,0))
		right_arm=_joint("ArmR",Vector3(.20,.82,0))
		left_foot=_joint("LegL",Vector3(-.085,.40,0))
		right_foot=_joint("LegR",Vector3(.085,.40,0))
	symptoms=Node3D.new()
	symptoms.name="Symptoms"
	symptoms.position.y=.46
	add_child(symptoms)
	cure_feedback=Node3D.new()
	cure_feedback.name="CureFeedback"
	cure_feedback.position.y=.46
	add_child(cure_feedback)
	_build_interaction()
	symptom_kind="" if is_staff else identity
	if not is_staff:
		_build_symptoms(identity)
		_build_cure(identity)

func _configure_rig() -> bool:
	var skeletons := _body_root.find_children("*","Skeleton3D",true,false)
	if skeletons.is_empty(): return false
	for player: AnimationPlayer in _body_root.find_children("*","AnimationPlayer",true,false):
		var clips: Dictionary={}
		for clip in player.get_animation_list():
			var short_name := String(clip).get_file()
			if short_name in ["Idle","Walk","Examine"]: clips[short_name]=clip
		if clips.size()!=3: continue
		# Local copies keep loop flags independent of cached imported resources.
		for library_name in player.get_animation_library_list():
			var library: AnimationLibrary=player.get_animation_library(library_name).duplicate(true)
			player.remove_animation_library(library_name)
			player.add_animation_library(library_name,library)
		for clip in clips.values(): player.get_animation(clip).loop_mode=Animation.LOOP_LINEAR
		_rig_player=player
		_rig_clips=clips
		return true
	return false

func _rig_floor_top(actor: Dictionary) -> float:
	# Assigned room_id can remain set while a staff member crosses the hall. Use
	# the actual displayed cell when hosted by HospitalWorld; never move the actor.
	var world := get_parent().get_parent() as HospitalWorld if get_parent()!=null else null
	if world!=null:
		var cell := roundi(position.z)*24+roundi(position.x)
		for cells in world._room_cells.values():
			if cell in cells: return HospitalInteriorArt.ROOM_FLOOR_TOP
		return HALL_FLOOR_TOP
	return HospitalInteriorArt.ROOM_FLOOR_TOP if str(actor.get("room_id","")).length()>0 else HALL_FLOOR_TOP

func _update_rig_animation() -> void:
	var state := "Walk" if _route_active else "Examine" if _operating else "Idle"
	var actual_interaction: bool = not _route_active and interaction_context.get("active", false)
	if actual_interaction: state = str(interaction_context.get("clip", "Examine"))
	# Examine is a restrained communication lift, not contact with medical equipment.
	if _rig_state!=state:
		_rig_state=state
		_rig_player.play(_rig_clips[state],.12)
	_rig_player.speed_scale=0.0 if presentation_paused else clampf(RIG_BASE_CADENCE*_travel_speed/RIG_NAVIGATION_SPEED,.65,RIG_MAX_CADENCE) if state=="Walk" else 1.0
	if actual_interaction:
		_rig_player.speed_scale = 0.0
		_rig_player.seek(clampf(float(interaction_context.progress), 0.0, 1.0) * _rig_player.get_animation(_rig_clips[state]).length, true)

func _build_interaction() -> void:
	_interaction_root = Node3D.new()
	_interaction_root.name = "InteractionFeedback"
	add_child(_interaction_root)
	box(_interaction_root, Vector3(0, 1.88, 0), Vector3(.50, .035, .025), NAVY)
	_interaction_fill = box(_interaction_root, Vector3(0, 1.90, 0), Vector3(.50, .040, .030), MINT)
	_interaction_label = Label3D.new()
	_interaction_label.name = "ActualActivity"
	_interaction_label.position.y = 2.03
	_interaction_label.pixel_size = .0034
	_interaction_label.font_size = 30
	_interaction_label.outline_size = 7
	_interaction_label.modulate = Color("fff8e9")
	_interaction_label.outline_modulate = NAVY
	_interaction_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_interaction_label.no_depth_test = false
	_interaction_label.font = HospitalUiStyle.font(650)
	_interaction_root.add_child(_interaction_label)
	_interaction_root.visible = false

func _present_interaction(active: bool) -> void:
	if _interaction_root == null: return
	_interaction_root.visible = active
	if not active: return
	var progress: float = clampf(float(interaction_context.get("progress", 0)), 0.0, 1.0)
	_interaction_fill.scale.x = maxf(.001, progress)
	_interaction_fill.position.x = -.25 + .25 * progress
	var short_label: String = {"clinical": "诊疗", "support": "检验加工", "logistics": "补给运输", "maintenance": "清洁维护", "admin": "调度教学", "environment": "环境保障", "personal": "生活服务"}.get(interaction_context.get("category", ""), "工作")
	if interaction_context.get("source", "") in ["personal", "staff_rest"]: short_label = str(interaction_context.get("label", short_label))
	_interaction_label.text = short_label
	_interaction_root.set_meta("actual_progress", progress)
	_interaction_root.set_meta("occurrence_id", str(interaction_context.get("occurrence_id", "")))

func _joint(part_name: String, pivot: Vector3) -> Node3D:
	var part:=_body_root.find_child(part_name,true,false) as Node3D
	var joint:=Node3D.new()
	joint.name=part_name+"Joint"
	_body_root.add_child(joint)
	joint.position=pivot
	if part!=null:
		part.reparent(joint,false)
		part.position-=pivot
	return joint

func _build_symptoms(kind: String) -> void:
	if kind == "echo":
		for i in range(3):
			var halo := ring(symptoms,Vector3(0,1.16+i*0.105,0),0.19+i*0.055,ORANGE)
			halo.rotation.x = 0.22*i
	elif kind == "motion":
		for i in range(3):
			var arrow := box(symptoms,Vector3(-0.28+i*0.27,1.22+0.12*(i%2),0),Vector3(0.13,0.13,0.07),ORANGE)
			arrow.rotation.z = PI/4
	else:
		for i in range(4):
			var icon := ball(symptoms,Vector3(-0.30+i*0.20,1.24+0.12*(i%2),0),Vector3(0.14,0.16,0.10),MINT if i%2 == 0 else ORANGE)
			if i%2:
				box(icon,Vector3(0,-0.55,0),Vector3(0.18,0.7,0.18),Color("fff4db"))

func _build_cure(kind: String) -> void:
	# Each disease resolves its own motif, followed by an unambiguous common check mark.
	var color := MINT
	if kind == "echo":
		for i in range(3):
			ball(cure_feedback,Vector3(-0.23+i*0.23,1.20,0),Vector3.ONE*0.09,color)
	elif kind == "motion":
		for i in range(3):
			box(cure_feedback,Vector3(-0.23+i*0.23,1.20,0),Vector3(0.12,0.07,0.07),color)
	else:
		for i in range(2):
			ring(cure_feedback,Vector3(0,1.16+i*0.12,0),0.22,color)
	var short_stroke := box(cure_feedback,Vector3(-0.055,1.48,0),Vector3(0.08,0.20,0.05),color)
	short_stroke.rotation.z = 0.72
	var long_stroke := box(cure_feedback,Vector3(0.065,1.54,0),Vector3(0.08,0.32,0.05),color)
	long_stroke.rotation.z = -0.62

func _process(delta: float) -> void:
	var visual_delta:=0.0 if presentation_paused else maxf(0.0,delta)*maxi(1,presentation_speed)
	_time += visual_delta
	if _simplified!=null and _rig_state=="Walk" and _simplified.has_calibrated_walk():
		_simplified.present_state("Walk",_simplified.walk_cadence(_visual_motion.display_velocity(delta),1.0),not presentation_paused)
	if _prerendered!=null and _prerendered.is_high_quality() and _rig_state=="Walk":
		_prerendered.present_state("Walk",_body_root.rotation.y,_prerendered.walk_cadence(_visual_motion.display_velocity(delta),1.0))
	if _body_root!=null:
		_apply_visual_offset(_visual_motion.advance(delta))
	if _simplified!=null:
		_motion_elapsed+=delta
		_simplified.advance_animation(delta)
		return
	if _prerendered!=null:
		_motion_elapsed+=delta
		if _prerendered.is_high_quality() and not presentation_paused:_prerendered.advance_animation(delta)
		return
	if _rig_player!=null:
		_motion_elapsed+=delta
		# Skeleton animation already includes body/foot motion. Legacy pivots and
		# procedural bounce must never be applied to this genuinely skinned model.
		return
	var walking := sin(_time*11.0)*0.45 if _route_active else 0.0
	left_arm.rotation.x = walking
	right_arm.rotation.x = -walking
	left_foot.rotation.x = -walking
	right_foot.rotation.x = walking
	_body_root.position.y=absf(walking)*.018
	if _operating and not _walk:
		left_arm.rotation.x=-.38+sin(_time*3.2)*.06
		right_arm.rotation.x=-.52+sin(_time*3.2+.5)*.10
	if symptoms.visible:
		if symptom_kind == "echo":
			symptoms.rotation.y += visual_delta*0.7
		elif symptom_kind == "motion":
			left_arm.rotation.z = sin(_time*4.2)*0.75
			right_arm.rotation.z = sin(_time*4.2+1.9)*0.75
			symptoms.position.y = .46+sin(_time*3.0)*0.035
		else:
			symptoms.rotation.y = sin(_time*2.0)*0.45
	else:
		left_arm.rotation.z = 0
		right_arm.rotation.z = 0

func _apply_visual_offset(offset:Vector3) -> void:
	for item:Node3D in [_body_root,symptoms,cure_feedback,_interaction_root]:
		if item!=null:item.position.x=offset.x;item.position.z=offset.z
