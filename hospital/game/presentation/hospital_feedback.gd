class_name HospitalFeedback
extends Node

signal preferences_changed(value: Dictionary)
signal persistence_error(error: String)

const DEFAULT_PREFERENCES := {"music_enabled":true,"haptics_enabled":true,"music_volume":0.32,"sfx_volume":0.65}
const CONFIG_VERSION := 1
const MUSIC_STREAM: AudioStreamWAV = preload("res://assets/audio/clinic_soft_jazz_loop.wav")
const CONFIRM_STREAM: AudioStreamWAV = preload("res://assets/audio/ui_confirm.wav")
const REJECT_STREAM: AudioStreamWAV = preload("res://assets/audio/ui_reject.wav")
const EXPERIENCE_STREAMS := {
	"clinical": preload("res://assets/audio/experience/clinical.wav"),
	"support": preload("res://assets/audio/experience/support.wav"),
	"logistics": preload("res://assets/audio/experience/logistics.wav"),
	"maintenance": preload("res://assets/audio/experience/maintenance.wav"),
	"admin": preload("res://assets/audio/experience/admin.wav"),
	"environment": preload("res://assets/audio/experience/environment.wav"),
	"personal": preload("res://assets/audio/experience/personal.wav"),
	"complete": preload("res://assets/audio/experience/complete.wav"),
	"breakdown": preload("res://assets/audio/experience/event_breakdown.wav"),
	"supply_delay": preload("res://assets/audio/experience/event_supply_delay.wav"),
	"infection_alert": preload("res://assets/audio/experience/event_infection_alert.wav"),
	"urgent_referral": preload("res://assets/audio/experience/event_urgent_referral.wav"),
	"management": preload("res://assets/audio/experience/management.wav")
}

var _root := ""
var _settings_path := ""
var _configured := false
var _application_active := true
var _preferences: Dictionary = DEFAULT_PREFERENCES.duplicate(true)
var _music_player: AudioStreamPlayer
var _sfx_player: AudioStreamPlayer
var _experience_player: AudioStreamPlayer
var _experience_voices: Array[AudioStreamPlayer] = []
var _experience_voice_index := 0

func configure(preference_root: String) -> Dictionary:
	if _configured:
		return {"ok":false,"error":"already_configured"}
	if preference_root.strip_edges() == "":
		return {"ok":false,"error":"empty_preference_root"}
	_root = preference_root
	_settings_path = _root.path_join("preferences.jsonl")
	var directory_error := DirAccess.make_dir_recursive_absolute(_root)
	if directory_error != OK:
		return {"ok":false,"error":"preference_directory_failed:%d" % directory_error}
	_preferences = _load_preferences()
	_music_player = AudioStreamPlayer.new()
	_music_player.name = "MusicPlayer"
	var looping_music := MUSIC_STREAM.duplicate() as AudioStreamWAV
	looping_music.loop_mode = AudioStreamWAV.LOOP_FORWARD
	looping_music.loop_begin = 0
	looping_music.loop_end = looping_music.data.size()/2
	_music_player.stream = looping_music
	_music_player.bus = "Master"
	_sfx_player = AudioStreamPlayer.new()
	_sfx_player.name = "SfxPlayer"
	_sfx_player.bus = "Master"
	add_child(_music_player)
	add_child(_sfx_player)
	_experience_player = AudioStreamPlayer.new()
	_experience_player.name = "ExperienceSfxPlayer"
	_experience_player.bus = "Master"
	add_child(_experience_player)
	_experience_voices.append(_experience_player)
	var second_voice := AudioStreamPlayer.new()
	second_voice.name = "ExperienceSfxPlayer2"
	second_voice.bus = "Master"
	add_child(second_voice)
	_experience_voices.append(second_voice)
	_configured = true
	_apply_music()
	return {"ok":true,"preferences":preferences()}

func _exit_tree() -> void:
	if _music_player != null:
		_music_player.stop()
		_music_player.stream = null
	if _sfx_player != null:
		_sfx_player.stop()
		_sfx_player.stream = null
	for voice: AudioStreamPlayer in _experience_voices:
		voice.stop()
		voice.stream = null

func set_application_active(active: bool) -> void:
	if _application_active == active:
		return
	_application_active = active
	if not active and _sfx_player != null:
		_sfx_player.stop()
	if not active:
		for voice: AudioStreamPlayer in _experience_voices: voice.stop()
	_apply_music()

func preferences() -> Dictionary:
	return _preferences.duplicate(true)

func set_music_enabled(enabled: bool) -> Dictionary:
	var next := _preferences.duplicate(true)
	next.music_enabled = enabled
	return _commit(next)

func set_haptics_enabled(enabled: bool) -> Dictionary:
	var next := _preferences.duplicate(true)
	next.haptics_enabled = enabled
	return _commit(next)

func set_music_volume(value: float) -> Dictionary:
	var next := _preferences.duplicate(true)
	next.music_volume = _bounded_volume(value)
	return _commit(next)

func set_sfx_volume(value: float) -> Dictionary:
	var next := _preferences.duplicate(true)
	next.sfx_volume = _bounded_volume(value)
	return _commit(next)

func play_confirmed() -> void:
	_play_sfx(CONFIRM_STREAM)

func play_rejected() -> void:
	_play_sfx(REJECT_STREAM)

func play_experience(cue: Dictionary) -> void:
	if not _configured or not _application_active or _experience_player == null or float(_preferences.sfx_volume) <= 0.0: return
	var kind: String = str(cue.get("kind", ""))
	var key: String = str(cue.get("category", ""))
	if kind.ends_with("complete") or kind.ends_with("resolved"): key = "complete"
	elif kind == "event_open": key = str(cue.get("definition_id", "management"))
	elif kind.begins_with("management_"): key = "management"
	if not EXPERIENCE_STREAMS.has(key): return
	# A quiet independent voice preserves the user's command confirmation.
	var voice: AudioStreamPlayer = _experience_voices[_experience_voice_index % _experience_voices.size()]
	_experience_voice_index += 1
	voice.stream = EXPERIENCE_STREAMS[key]
	voice.volume_db = _linear_to_db(float(_preferences.sfx_volume) * .48)
	voice.play()

func haptics_supported() -> bool:
	return OS.has_feature("android") or OS.has_feature("ios")

func request_haptic(duration_ms: int = 40) -> Dictionary:
	if not _application_active:
		return {"ok":true,"supported":haptics_supported(),"requested":false,"reason":"application_inactive"}
	if not _preferences.haptics_enabled:
		return {"ok":true,"supported":haptics_supported(),"requested":false,"reason":"disabled_by_preference"}
	if not haptics_supported():
		return {"ok":true,"supported":false,"requested":false,"reason":"platform_unsupported"}
	Input.vibrate_handheld(clampi(duration_ms,20,1000))
	return {"ok":true,"supported":true,"requested":true,"reason":"request_sent"}

func _play_sfx(stream: AudioStreamWAV) -> void:
	if not _configured or not _application_active or _sfx_player == null:
		return
	_sfx_player.stream = stream
	_sfx_player.volume_db = _linear_to_db(float(_preferences.sfx_volume))
	_sfx_player.play()

func _apply_music() -> void:
	if not _configured or _music_player == null:
		return
	_music_player.volume_db = _linear_to_db(float(_preferences.music_volume))
	if not bool(_preferences.music_enabled):
		if _music_player.playing:
			_music_player.stop()
		return
	if not _application_active:
		if _music_player.playing:
			_music_player.stream_paused = true
		return
	if not _music_player.playing:
		_music_player.play()
	_music_player.stream_paused = false

func _linear_to_db(value: float) -> float:
	return -80.0 if value <= 0.0 else linear_to_db(value)

func _bounded_volume(value: float) -> float:
	return clampf(value,0.0,1.0) if is_finite(value) else 0.0

func _commit(next: Dictionary) -> Dictionary:
	if not _configured:
		return {"ok":false,"error":"not_configured"}
	next.music_volume = _bounded_volume(float(next.music_volume))
	next.sfx_volume = _bounded_volume(float(next.sfx_volume))
	var result := _append_preferences(next)
	if not result.ok:
		persistence_error.emit(result.error)
		return result
	_preferences = next
	_apply_music()
	for voice: AudioStreamPlayer in _experience_voices:
		voice.volume_db = _linear_to_db(float(_preferences.sfx_volume) * .48)
		if float(_preferences.sfx_volume) <= 0.0: voice.stop()
	preferences_changed.emit(preferences())
	return {"ok":true,"error":""}

func _load_preferences() -> Dictionary:
	if not FileAccess.file_exists(_settings_path):
		return DEFAULT_PREFERENCES.duplicate(true)
	var content := FileAccess.get_file_as_string(_settings_path)
	var lines := content.split("\n",false)
	var found: Dictionary = {}
	for line in lines:
		var parser := JSON.new()
		if parser.parse(line.strip_edges()) != OK:
			continue
		var parsed: Variant = parser.data
		if not parsed is Dictionary or int(parsed.get("version",-1)) != CONFIG_VERSION:
			continue
		if not parsed.get("music_enabled") is bool or not parsed.get("haptics_enabled") is bool:
			continue
		if not parsed.get("music_volume") is float and not parsed.get("music_volume") is int:
			continue
		if not parsed.get("sfx_volume") is float and not parsed.get("sfx_volume") is int:
			continue
		found = {
			"music_enabled":parsed.music_enabled,
			"haptics_enabled":parsed.haptics_enabled,
			"music_volume":_bounded_volume(float(parsed.music_volume)),
			"sfx_volume":_bounded_volume(float(parsed.sfx_volume))
		}
	return DEFAULT_PREFERENCES.duplicate(true) if found.is_empty() else found

func _append_preferences(value: Dictionary) -> Dictionary:
	var file: FileAccess
	if FileAccess.file_exists(_settings_path):
		file = FileAccess.open(_settings_path,FileAccess.READ_WRITE)
	else:
		file = FileAccess.open(_settings_path,FileAccess.WRITE_READ)
	if file == null:
		return {"ok":false,"error":"preferences_open_failed:%d" % FileAccess.get_open_error()}
	if file.get_length() > 0:
		file.seek(file.get_length()-1)
		if file.get_8() != 10:
			file.seek_end()
			file.store_8(10)
	file.seek_end()
	var record := value.duplicate(true)
	record["version"] = CONFIG_VERSION
	file.store_line(JSON.stringify(record))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK:
		return {"ok":false,"error":"preferences_write_failed:%d" % error}
	return {"ok":true,"error":""}
