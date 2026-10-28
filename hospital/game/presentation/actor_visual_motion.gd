class_name ActorVisualMotion
extends RefCounted

# A display-only offset behind the latest authoritative position. The helper
# never predicts a path edge or changes simulation coordinates or floor height.
const TICK_SECONDS := .1
const MAX_SEGMENT_DISTANCE := .36
const POSITION_EPSILON := .00001

var _initialized := false
var _tick := 0
var _paused := false
var _speed := 1
var _from := Vector3.ZERO
var _target := Vector3.ZERO
var _progress := 1.0

func present(position: Vector3, tick: int, paused: bool, speed: int) -> void:
	var target := Vector3(position.x, 0, position.z)
	if not target.is_finite(): return
	var changed_pause := _initialized and paused != _paused
	var distance := target.distance_to(_target)
	_speed = maxi(1, speed)
	if not _initialized or paused or changed_pause or tick < _tick or tick > _tick + 1 or distance > MAX_SEGMENT_DISTANCE:
		_align(target, tick, paused)
		return
	if tick == _tick:
		# Repeated render frames and non-spatial commands must preserve progress.
		# A same-tick teleport is an explicit spatial discontinuity, not a route.
		if distance > POSITION_EPSILON: _align(target, tick, paused)
		return
	_tick = tick
	_paused = paused
	_from = _target
	_target = target
	_progress = 0.0 if distance > POSITION_EPSILON else 1.0

func advance(delta: float) -> Vector3:
	if not is_moving() or not is_finite(delta) or delta <= 0: return offset()
	_progress = minf(1.0, _progress + delta * _speed / TICK_SECONDS)
	return offset()

func offset() -> Vector3:
	if not is_moving(): return Vector3.ZERO
	return _from.lerp(_target, _progress) - _target

func is_moving() -> bool:
	return _initialized and not _paused and _progress < 1.0

func display_velocity(delta:float=0.0) -> float:
	if not is_moving():return 0.0
	var distance:=_from.distance_to(_target)
	var velocity:float=distance*_speed/TICK_SECONDS
	# A render frame can consume only the remaining part of this real segment.
	return minf(velocity,distance*(1.0-_progress)/delta) if delta>0 else velocity

func _align(target: Vector3, tick: int, paused: bool) -> void:
	_initialized = true
	_tick = tick
	_paused = paused
	_from = target
	_target = target
	_progress = 1.0
