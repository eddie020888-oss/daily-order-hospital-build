class_name CameraRig
extends Node3D

var camera: Camera3D
var target := Vector3(11.5,0,7.5)
var zoom_size := 22.0
var scene_anchor:=Vector2(.5,.5)
var scene_extent:=Vector2.ONE
var _subject_shift:=Vector2.ZERO
var _fit_zoom_limit:=26.0
# Fixed 35.26 degree view shared by the approved prerendered hall and live objects.
const VIEW_OFFSET:=Vector3(18,18,18)

func _init() -> void:
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.near = 0.1
	camera.far = 100
	add_child(camera)

func _ready() -> void:
	camera.current = true
	_update_camera()

func _update_camera() -> void:
	camera.size = zoom_size
	camera.position = target + VIEW_OFFSET
	camera.look_at(target,Vector3.UP)
	var viewport_size:=get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(1280,720)
	camera.h_offset=(.5-scene_anchor.x)*zoom_size*viewport_size.x/maxf(1,viewport_size.y)+_subject_shift.x
	camera.v_offset=(scene_anchor.y-.5)*zoom_size+_subject_shift.y

func set_scene_anchor(value:Vector2,extent:Vector2=Vector2.ONE) -> void:
	var next:=value.clamp(Vector2(.1,.2),Vector2(.9,.8))
	var next_extent:=extent.clamp(Vector2(.1,.1),Vector2.ONE)
	if scene_anchor.is_equal_approx(next) and scene_extent.is_equal_approx(next_extent):return
	scene_anchor=next
	scene_extent=next_extent
	_update_camera()

func frame_room(room:Dictionary) -> void:
	if room.get("cells",[]).is_empty():return
	var low:=Vector3(INF,0,INF)
	var high:=Vector3(-INF,2.05,-INF)
	var center:=Vector3.ZERO
	for cell in room.cells:
		var at:=HospitalWorld.cell_position(cell)
		center+=at
		low.x=minf(low.x,at.x-.5);low.z=minf(low.z,at.z-.5)
		high.x=maxf(high.x,at.x+.5);high.z=maxf(high.z,at.z+.5)
	target=center/room.cells.size()
	_update_camera()
	var minimum:=Vector2(INF,INF)
	var maximum:=Vector2(-INF,-INF)
	for x in [low.x,high.x]:
		for y in [low.y,high.y]:
			for z in [low.z,high.z]:
				var relative:=Vector3(x,y,z)-target
				var projected:=Vector2(relative.dot(camera.global_basis.x),relative.dot(camera.global_basis.y))
				minimum=minimum.min(projected);maximum=maximum.max(projected)
	var viewport_size:=get_viewport().get_visible_rect().size
	var aspect:float=viewport_size.x/maxf(1,viewport_size.y)
	var needed:Vector2=(maximum-minimum)/scene_extent
	zoom_size=maxf(maxf(needed.x/aspect,needed.y)*1.08,5.5)
	_fit_zoom_limit=maxf(26.0,zoom_size)
	_subject_shift=(minimum+maximum)*.5
	_update_camera()

func focus_cell(cell: int) -> void:
	if cell >= 0 and cell < 432:
		target = HospitalWorld.cell_position(cell)
		_subject_shift=Vector2.ZERO
		_update_camera()

func set_zoom(value: float) -> void:
	zoom_size = clampf(value,5.5,_fit_zoom_limit)
	_update_camera()

func pan(offset: Vector3) -> void:
	target.x = clampf(target.x+offset.x,0.0,23.0)
	target.z = clampf(target.z+offset.z,0.0,17.0)
	_update_camera()

func screen_to_cell(screen_position: Vector2) -> int:
	var ray_start := camera.project_ray_origin(screen_position)
	var ray_direction := camera.project_ray_normal(screen_position)
	if absf(ray_direction.y) < 0.00001:
		return -1
	var distance := -ray_start.y/ray_direction.y
	if distance < 0:
		return -1
	var floor_position := ray_start+ray_direction*distance
	var x := floori(floor_position.x+0.5)
	var y := floori(floor_position.z+0.5)
	if x < 0 or x >= 24 or y < 0 or y >= 18:
		return -1
	# The only boundary floor is the shared entrance, cell 216.
	if (x == 0 or x == 23 or y == 0 or y == 17) and not (x == 0 and y == 9):
		return -1
	return y*24+x

# Pick the closed wall envelope, including existing door/window openings, so
# an opening can be selected or removed without falling through to the floor.
# Side and offset come from the intersected face, resolving corner-cell ties.
func screen_to_wall(screen_position:Vector2,origin_cell:int,width:int,height:int) -> Dictionary:
	if origin_cell<0 or origin_cell>=432 or width<=0 or height<=0:return {}
	var low:=Vector2(origin_cell%24-.5,origin_cell/24-.5)
	var high:=low+Vector2(width,height)
	var ray_start:Vector3=camera.project_ray_origin(screen_position)
	var direction:Vector3=camera.project_ray_normal(screen_position)
	var nearest:=INF
	var picked:Dictionary={}
	for side in ["north","east","south","west"]:
		var along_x:bool=side in ["north","south"]
		var component:float=direction.z if along_x else direction.x
		if absf(component)<.00001:continue
		var plane:float=(low.y if side=="north" else high.y) if along_x else (low.x if side=="west" else high.x)
		var distance:float=(plane-(ray_start.z if along_x else ray_start.x))/component
		if distance<0 or distance>=nearest:continue
		var at:Vector3=ray_start+direction*distance
		if at.y<0 or at.y>2.07:continue
		var along:float=at.x if along_x else at.z
		var start:float=low.x if along_x else low.y
		var length:int=width if along_x else height
		if along<start-.00001 or along>start+length+.00001:continue
		nearest=distance
		picked={"side":side,"offset":clampi(floori(along-start),0,length-1)}
	return picked
