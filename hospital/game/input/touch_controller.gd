class_name TouchController
extends RefCounted

signal command_requested(command: Dictionary)
signal placement_changed
signal selection_requested(id: String, group: String)

var placement: Dictionary={}
var free_build: FreeBuildDraft
var world: HospitalWorld
var _gui_hit: Callable
var _fingers: Dictionary={}
var _start: Dictionary={}
var _blocked: Dictionary={}
var _dragged := false
var _multitouch := false
var _mouse_down := false
var _reserve_id: Callable
var _free_id:=""
var _draw_backup: Dictionary={}
var _drawing_rectangle:=false
var _draw_first:=-1
var _draw_last:=-1
var _draw_mode:="draw"
# A small fraction of a tile absorbs sub-pixel release jitter without changing
# the shared camera projection or the actual integer room footprint.
const BUILD_SNAP_MARGIN:=0.15

func _init(view: HospitalWorld=null, gui_hit: Callable=Callable(), reserve_id: Callable=Callable()) -> void:
	world=view
	_gui_hit=gui_hit
	_reserve_id=reserve_id

func begin_placement(kind: String, room_id: String="") -> void:
	# A preview-only host may omit allocation; emitting model commands requires a receipt-aware provider.
	free_build=null
	_clear_drawing()
	var id: String=_reserve_id.call() if _reserve_id.is_valid() else ""
	placement={"kind":kind,"room_id":room_id,"origin_cell":-1,"rotation":0,"id":id}
	placement_changed.emit()

func begin_free_build(kind: String, room_id: String="", layout: Dictionary={}, origin_cell: int=-1) -> void:
	_clear_drawing()
	free_build=FreeBuildDraft.new(kind,room_id,layout,origin_cell)
	_free_id=_reserve_id.call() if _reserve_id.is_valid() else ""
	_sync_free_build()

func choose_cell(cell: int) -> void:
	if placement.is_empty(): return
	if free_build!=null:
		if cell<0 or cell>=GridService.WIDTH*GridService.HEIGHT:return
		free_build.choose_cell(cell)
		_sync_free_build()
		return
	placement.origin_cell=cell
	placement_changed.emit()

func reposition() -> void:
	if placement.is_empty():return
	if free_build==null:
		choose_cell(-1)
		return
	var has_version:bool=free_build.layout.has("footprint_version")
	var version:Variant=free_build.layout.get("footprint_version")
	_clear_drawing()
	free_build=FreeBuildDraft.new(free_build.kind,free_build.room_id)
	if has_version:free_build.layout.footprint_version=version
	else:free_build.layout.erase("footprint_version")
	_sync_free_build()

func advance_build_step() -> bool:
	if free_build==null: return false
	var changed:=free_build.next_step()
	if changed: _sync_free_build()
	return changed

func adjust_build_bounds(size_delta:Vector2i,offset:Vector2i=Vector2i.ZERO) -> bool:
	if free_build==null:return false
	if not free_build.adjust_bounds(size_delta,offset):return false
	_clear_drawing()
	_sync_free_build()
	return true

func back_build_step() -> void:
	if free_build==null: return
	free_build.previous_step()
	_sync_free_build()

func select_furniture(kind: String) -> void:
	if free_build==null: return
	free_build.select_furniture(kind)
	_sync_free_build()

func choose_wall(side:String,offset:int) -> void:
	if free_build==null:return
	free_build.choose_wall(side,offset)
	_sync_free_build()

func select_opening_tool(kind:String) -> void:
	if free_build==null:return
	free_build.select_opening_tool(kind)
	_sync_free_build()

func remove_furniture_at(cell: int) -> void:
	if free_build==null: return
	free_build.remove_furniture_at(cell)
	_sync_free_build()

func rotate() -> void:
	if placement.is_empty(): return
	if free_build!=null:
		free_build.rotate()
		_sync_free_build()
		return
	placement.rotation=(placement.rotation+1)%4
	placement_changed.emit()

func cancel() -> void:
	placement={}
	free_build=null
	_free_id=""
	_clear_drawing()
	placement_changed.emit()

func reset_input() -> void:
	_fingers.clear()
	_start.clear()
	_blocked.clear()
	_dragged=false
	_multitouch=false
	_mouse_down=false
	cancel()

func confirm() -> void:
	if placement.is_empty() or placement.origin_cell<0 or placement.id=="": return
	if free_build!=null and (free_build.step!=3 or not free_build.can_advance()): return
	var p:=placement.duplicate(true)
	# Clear before dispatch: repeated input cannot allocate a second purchase ID.
	cancel()
	var payload:={"origin_cell":p.origin_cell,"rotation":p.rotation}
	if p.has("layout"): payload.layout=p.layout
	if p.room_id!="": payload.room_id=p.room_id
	else: payload.kind=p.kind
	command_requested.emit({"id":p.id,"type":"move_room" if p.room_id!="" else "build_room","payload":payload})

func _sync_free_build() -> void:
	if free_build==null: return
	placement=free_build.proposal()
	placement.room_id=free_build.room_id
	placement.id=_free_id
	placement_changed.emit()

func _clear_drawing() -> void:
	_draw_backup={}
	_drawing_rectangle=false
	_draw_first=-1
	_draw_last=-1
	_draw_mode="draw"

func _abandon_drawing() -> void:
	if free_build!=null and not _draw_backup.is_empty():
		free_build.restore_state(_draw_backup)
		_sync_free_build()
	_clear_drawing()

func feed(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.canceled: reset_input()
		else: _pointer(event.index,event.pressed,event.position)
	elif event is InputEventScreenDrag:
		_motion(event.index,event.position)
	elif event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.device!=-1:
		_mouse_down=event.pressed
		_pointer(-1,event.pressed,event.position)
	elif event is InputEventMouseMotion and _mouse_down:
		_motion(-1,event.position)
	elif event is InputEventMouseButton and event.pressed and world!=null:
		if _hits_gui(event.position): return
		if event.button_index==MOUSE_BUTTON_WHEEL_UP: world.camera_rig.set_zoom(world.camera_rig.zoom_size-1)
		if event.button_index==MOUSE_BUTTON_WHEEL_DOWN: world.camera_rig.set_zoom(world.camera_rig.zoom_size+1)

func _hits_gui(point: Vector2) -> bool:
	return _gui_hit.is_valid() and _gui_hit.call(point)

func _pointer(index: int, pressed: bool, point: Vector2) -> void:
	if pressed:
		_fingers[index]=point
		_start[index]=point
		_blocked[index]=_hits_gui(point)
		if _fingers.size()==1:
			_dragged=false
			_multitouch=false
		elif _fingers.size()>=2:
			_multitouch=true
			if free_build!=null: _abandon_drawing()
			else: cancel()
	else:
		if not _fingers.has(index): return
		var tap: bool=not _multitouch and not _dragged and not _blocked[index] and not _hits_gui(point)
		if _drawing_rectangle:
			if _hits_gui(point) or _multitouch or world.camera_rig.screen_to_cell(point)<0:
				_abandon_drawing()
			else:
				_update_rectangle(point)
				_clear_drawing()
		_fingers.erase(index)
		_start.erase(index)
		_blocked.erase(index)
		if tap: _tap(point)

func _motion(index: int, point: Vector2) -> void:
	if not _fingers.has(index): return
	var before: Vector2=_fingers[index]
	if _fingers.size()>=2 and world!=null:
		var keys:=_fingers.keys()
		var other: int=keys[1] if keys[0]==index else keys[0]
		if not _blocked[index] and not _blocked[other]:
			var old_distance:=before.distance_to(_fingers[other])
			var new_distance:=point.distance_to(_fingers[other])
			if old_distance>1 and new_distance>1: world.camera_rig.set_zoom(world.camera_rig.zoom_size*old_distance/new_distance)
	elif not _blocked[index] and not _multitouch:
		if point.distance_to(_start[index])>10: _dragged=true
		if _dragged and world!=null:
			if free_build!=null and free_build.step==0:
				if not _drawing_rectangle:
					_draw_backup=free_build.capture_state()
					_draw_first=world.camera_rig.screen_to_cell(_start[index])
					_draw_last=_draw_first
					var proposal:=free_build.proposal()
					var origin:int=proposal.get("origin_cell",-1)
					var local:=Vector2i(_draw_first%GridService.WIDTH-origin%GridService.WIDTH,_draw_first/GridService.WIDTH-origin/GridService.WIDTH)
					if free_build.has_completed_bounds() and _draw_first>=0 and local.x>=0 and local.y>=0 and local.x<int(free_build.layout.width) and local.y<int(free_build.layout.height):_draw_mode="move"
					_drawing_rectangle=true
				if not _hits_gui(point):
					_update_rectangle(point)
			elif placement.is_empty():
				var rig:=world.camera_rig
				var from:=_floor_point(before)
				var to:=_floor_point(point)
				rig.pan(from-to)
	_fingers[index]=point

func _construction_cell(point:Vector2) -> int:
	var picked:=world.camera_rig.screen_to_cell(point)
	if picked<0 or _draw_last<0:return picked
	var at:=_floor_point(point)
	var x:int=picked%GridService.WIDTH
	var y:int=picked/GridService.WIDTH
	var old_x:int=_draw_last%GridService.WIDTH
	var old_y:int=_draw_last/GridService.WIDTH
	if absf(at.x-float(old_x))<=0.5+BUILD_SNAP_MARGIN:x=old_x
	if absf(at.z-float(old_y))<=0.5+BUILD_SNAP_MARGIN:y=old_y
	if (x==0 or x==GridService.WIDTH-1 or y==0 or y==GridService.HEIGHT-1) and not (x==0 and y==9):return picked
	return y*GridService.WIDTH+x

func _update_rectangle(point:Vector2) -> void:
	var cell:=_construction_cell(point)
	if cell<0 or _draw_first<0:return
	_draw_last=cell
	if _draw_mode=="move":
		free_build.restore_state(_draw_backup)
		var offset:=Vector2i(cell%GridService.WIDTH-_draw_first%GridService.WIDTH,cell/GridService.WIDTH-_draw_first/GridService.WIDTH)
		free_build.adjust_bounds(Vector2i.ZERO,offset)
	else:free_build.set_bounds(_draw_first,cell)
	_sync_free_build()

func _floor_point(point: Vector2) -> Vector3:
	var camera:=world.camera_rig.camera
	var origin:=camera.project_ray_origin(point)
	var direction:=camera.project_ray_normal(point)
	return origin-direction*(origin.y/direction.y)

func _tap(point: Vector2) -> void:
	if world==null: return
	if not placement.is_empty():
		if free_build!=null and free_build.step==0 and free_build.has_completed_bounds():return
		if free_build!=null and free_build.step==1:
			var wall:Dictionary=world.camera_rig.screen_to_wall(point,int(placement.origin_cell),int(free_build.layout.width),int(free_build.layout.height))
			if not wall.is_empty():
				choose_wall(wall.side,int(wall.offset))
				return
		var cell:=world.camera_rig.screen_to_cell(point)
		if free_build!=null and cell<0:return
		choose_cell(cell)
		return
	# Pick the rendered body/head, not only the tiny floor cell under its head.
	var nearest:=""
	var distance:=34.0
	for id in world.actor_views:
		var view: Node3D=world.actor_views[id]
		var camera:=world.camera_rig.camera
		var feet:=camera.unproject_position(view.position+Vector3(0,.18,0))
		var head:=camera.unproject_position(view.position+Vector3(0,1.40,0))
		var spine:=head-feet
		var fraction:=clampf((point-feet).dot(spine)/maxf(1.0,spine.length_squared()),0.0,1.0)
		var d:=point.distance_to(feet+spine*fraction)
		if d<distance:
			distance=d
			nearest=id
	if nearest!="":
		selection_requested.emit(nearest,"staff" if nearest.begins_with("staff_") else "patients")
		return
	var cell:=world.camera_rig.screen_to_cell(point)
	var room_id:=world.room_at_cell(cell)
	if room_id!="": selection_requested.emit(room_id,"rooms")
