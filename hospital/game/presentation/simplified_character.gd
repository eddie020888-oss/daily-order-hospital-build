class_name SimplifiedCharacter
extends Node3D

# Independent identity bodies. Existing art remains available for comparison.
const MODELS := {"doctor-02":"res://assets/models/simple-clinic-v3/doctor-02.glb",
	"patient-01":"res://assets/models/simple-clinic-v2/patient-01.glb",
	"receptionist-01":"res://assets/models/character-refinement-v6/support/receptionist-01.glb",
	"technician-03":"res://assets/models/character-refinement-v6/support/technician-03.glb"}
var player:AnimationPlayer
var clips:Dictionary={}
var clip_name:=""
var _playing:=false
var _speed:=1.0
var _target_time:=-1.0
var _start_time:=0.0
var _elapsed:=0.0
var _interval:=.1
var _consult_speed:=1
const SUPPORT_WALK_SPEEDS := {"receptionist-01":.8125,"technician-03":.84375}

static func create_for(canonical:String) -> SimplifiedCharacter:
	var path:String=UnifiedCharacterCast.model_path(canonical) if UnifiedCharacterCast.id_available(canonical) else MODELS.get(canonical,CharacterRoster.model_path(canonical))
	if path.is_empty() or not ResourceLoader.exists(path):return null
	var packed:Resource=load(path)
	if not packed is PackedScene:return null
	var result:=SimplifiedCharacter.new()
	result.add_child(packed.instantiate())
	for candidate:AnimationPlayer in result.find_children("*","AnimationPlayer",true,false):
		for animation in candidate.get_animation_list():
			var short_name:=String(animation).get_file()
			if short_name in ["Idle","Walk","Examine","Consult"]:result.clips[short_name]=animation
		if result.clips.has("Idle") and result.clips.has("Walk") and result.clips.has("Examine"):
			result.player=candidate;break
		result.clips.clear()
	if result.player==null:result.free();return null
	for library_name in result.player.get_animation_library_list():
		var library:AnimationLibrary=result.player.get_animation_library(library_name).duplicate(true)
		result.player.remove_animation_library(library_name)
		result.player.add_animation_library(library_name,library)
	for short_name in result.clips:
		result.player.get_animation(result.clips[short_name]).loop_mode=Animation.LOOP_NONE if short_name=="Consult" else Animation.LOOP_LINEAR
	result.player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	result.set_meta("model_asset",canonical)
	result.set_meta("presentation","simplified-skinned-character")
	result.set_meta("family",canonical.get_slice("-",0))
	result.set_meta("walk_source_speed",CharacterRoster.walk_speed(canonical))
	result.present_state("Idle",1.0,false)
	return result

func can_consult() -> bool:return clips.has("Consult")

func is_support_staff() -> bool:return SUPPORT_WALK_SPEEDS.has(str(get_meta("model_asset","")))

func _walk_source_speed() -> float:
	return float(SUPPORT_WALK_SPEEDS.get(str(get_meta("model_asset","")),get_meta("walk_source_speed",0.0)))

func has_calibrated_walk() -> bool:return _walk_source_speed()>0.0

func walk_cadence(display_velocity:float,fallback:float) -> float:
	var source_speed:float=_walk_source_speed()
	return clampf(display_velocity/source_speed,0.0,6.4) if source_speed>0 else fallback

func present_state(state:String,speed:float,playing:bool) -> void:
	if not clips.has(state):state="Idle"
	_playing=playing
	_speed=clampf(speed,0.0,6.4) if state=="Walk" and has_calibrated_walk() else clampf(speed,.1,3.0)
	_target_time=-1.0
	if clip_name==state:return
	clip_name=state
	player.play(clips[state],.12)
	player.advance(0)

func present_progress(state:String,progress:float,playing:bool,speed:int) -> void:
	if not clips.has(state) or not is_finite(progress):return
	_playing=playing
	var target:=clampf(progress,0,1)*player.get_animation(clips[state]).length
	var changed:=clip_name!=state
	if changed:
		clip_name=state;player.play(clips[state]);player.advance(0)
	if changed or not playing or target<_target_time or absf(target-_target_time)>.201:
		_target_time=target;_start_time=target;_elapsed=0
		_consult_speed=maxi(1,speed)
		player.seek(target,true)
		return
	# Repeated UI presents within the same simulation tick preserve interpolation.
	if is_equal_approx(target,_target_time):
		if speed!=_consult_speed and _elapsed<_interval:
			_start_time=player.current_animation_position
			_interval=maxf(.000001,(_interval-_elapsed)*_consult_speed/maxi(1,speed))
			_elapsed=0
		_consult_speed=maxi(1,speed)
		return
	_start_time=player.current_animation_position
	_target_time=target
	_elapsed=0
	_interval=.1/maxi(1,speed)
	_consult_speed=maxi(1,speed)

func advance_animation(delta:float) -> void:
	if not _playing or delta<=0:return
	if _target_time>=0:
		_elapsed=minf(_elapsed+delta,_interval)
		player.seek(lerpf(_start_time,_target_time,_elapsed/_interval),true)
	else:player.advance(delta*_speed)
