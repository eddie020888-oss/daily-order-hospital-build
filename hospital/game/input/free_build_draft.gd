class_name FreeBuildDraft
extends RefCounted

const GRID_WIDTH:=24
const GRID_HEIGHT:=18
const SIDES:=["north","east","south","west"]
const FURNITURE:=["plant","bench","cabinet","bin"]

var kind: String
var room_id: String
var step:=0
var anchor:=-1
var end:=-1
var layout: Dictionary={"width":0,"height":0,"door":{},"equipment":{},"furniture":[],"footprint_version":2}
var furniture_kind:=""
var opening_tool:="door"
var selected_opening:Dictionary={}
var _openings_edited:=false
var _awaiting_corner:=false
var _selected_furniture:=-1
var _furniture_rotation:=0

func _init(room_kind: String, existing_room_id: String="", existing_layout: Dictionary={}, origin_cell: int=-1) -> void:
	kind=room_kind
	room_id=existing_room_id
	if not existing_layout.is_empty():
		layout=existing_layout.duplicate(true)
		if origin_cell>=0:
			anchor=origin_cell
			end=origin_cell+int(layout.get("width",0))-1+(int(layout.get("height",0))-1)*GRID_WIDTH

func choose_cell(cell: int) -> void:
	if step==0:
		if not _valid_cell(cell):
			_clear_bounds()
		elif _awaiting_corner:
			set_bounds(anchor,cell)
		else:
			set_bounds(cell,cell)
			_awaiting_corner=true
		return
	var local:=_local_cell(cell)
	if local.x<0: return
	if step==1:
		var side:="south" if local.y==int(layout.height)-1 else "east" if local.x==int(layout.width)-1 else "north" if local.y==0 else "west" if local.x==0 else ""
		if side!="":
			var offset:int=local.x if side in ["north","south"] else local.y
			# Keep old programmatic single-door drafts and receipts byte-for-byte
			# compatible until a player uses the explicit wall/opening tools.
			if not _openings_edited and not layout.has("doors") and not layout.has("windows"):
				layout.door={"side":side,"offset":offset}
				selected_opening={"kind":"door","index":0}
			else:choose_wall(side,offset)
	elif step==2:
		layout.equipment={"x":local.x,"y":local.y,"rotation":int(layout.equipment.get("rotation",0))}
	elif step==3 and furniture_kind in FURNITURE:
		for i in range(layout.furniture.size()):
			var item: Dictionary=layout.furniture[i]
			if item.kind==furniture_kind and _furniture_contains(item,local):
				layout.furniture.remove_at(i)
				_selected_furniture=-1
				return
		layout.furniture.append({"kind":furniture_kind,"x":local.x,"y":local.y,"rotation":_furniture_rotation})
		_selected_furniture=layout.furniture.size()-1

func set_bounds(first_cell: int, last_cell: int) -> void:
	if step!=0 or not _valid_cell(first_cell) or not _valid_cell(last_cell): return
	var width:=absi(first_cell%GRID_WIDTH-last_cell%GRID_WIDTH)+1
	var height:=absi(first_cell/GRID_WIDTH-last_cell/GRID_WIDTH)+1
	var origin:=mini(first_cell%GRID_WIDTH,last_cell%GRID_WIDTH)+mini(first_cell/GRID_WIDTH,last_cell/GRID_WIDTH)*GRID_WIDTH
	var changed: bool=origin!=_origin_cell() or width!=int(layout.width) or height!=int(layout.height)
	anchor=first_cell
	end=last_cell
	_awaiting_corner=false
	layout.width=width
	layout.height=height
	if changed: _clear_items()

func can_advance() -> bool:
	if not _size_valid(): return false
	if step==0: return true
	if not _door_valid(): return false
	if step==1: return true
	return FreeRoomLayout.validate(kind,layout)==""

func next_step() -> bool:
	if step>=3 or not can_advance(): return false
	step+=1
	_selected_furniture=-1
	return true

func previous_step() -> void:
	step=maxi(0,step-1)
	_awaiting_corner=false
	_selected_furniture=-1

func rotate() -> void:
	if step==1 and _door_valid():
		if _openings_edited or layout.has("doors") or layout.has("windows"):
			_rotate_opening()
		else:
			var side: String=SIDES[(SIDES.find(layout.door.side)+1)%SIDES.size()]
			var length: int=layout.width if side in ["north","south"] else layout.height
			layout.door={"side":side,"offset":mini(int(layout.door.offset),length-1)}
	elif step==2 and not layout.equipment.is_empty():
		layout.equipment.rotation=(int(layout.equipment.rotation)+1)%4
	elif step==3:
		_furniture_rotation=(_furniture_rotation+1)%4
		if _selected_furniture>=0 and _selected_furniture<layout.furniture.size():
			layout.furniture[_selected_furniture].rotation=(int(layout.furniture[_selected_furniture].rotation)+1)%4
	elif step==1:
		_rotate_opening()

func select_opening_tool(tool:String) -> void:
	if tool not in ["door","window","move","remove"]:return
	opening_tool=tool
	_ensure_openings()

func choose_wall(side:String,offset:int) -> void:
	if step!=1 or not _opening_valid({"side":side,"offset":offset}):return
	_ensure_openings()
	var spec:Dictionary={"side":side,"offset":offset}
	var occupied:Dictionary=_opening_at(spec)
	if not occupied.is_empty():
		selected_opening=occupied
		if opening_tool=="remove":
			var items:Array=layout.doors if occupied.kind=="door" else layout.windows
			items.remove_at(int(occupied.index))
			selected_opening={}
			_sync_primary()
		return
	if opening_tool=="remove":return
	if opening_tool=="move":
		if selected_opening.is_empty():return
		var items:Array=layout.doors if selected_opening.kind=="door" else layout.windows
		var index:int=selected_opening.index
		if index<0 or index>=items.size():return
		items[index]=spec
		_sync_primary()
		return
	var items:Array=layout.doors if opening_tool=="door" else layout.windows
	items.append(spec)
	selected_opening={"kind":opening_tool,"index":items.size()-1}
	_sync_primary()

func _ensure_openings() -> void:
	if not layout.has("doors"):
		layout.doors=[layout.door.duplicate(true)] if _opening_valid(layout.get("door",{})) else []
	if not layout.has("windows"):layout.windows=[]
	_openings_edited=true

func _sync_primary() -> void:
	layout.door=layout.doors[0].duplicate(true) if not layout.doors.is_empty() else {}

func _opening_at(spec:Dictionary) -> Dictionary:
	for group in ["door","window"]:
		var items:Array=layout.get("doors" if group=="door" else "windows",[])
		for index in range(items.size()):
			if items[index]==spec:return {"kind":group,"index":index}
	return {}

func _rotate_opening() -> void:
	if selected_opening.is_empty():return
	_ensure_openings()
	var items:Array=layout.doors if selected_opening.kind=="door" else layout.windows
	var index:int=selected_opening.index
	if index<0 or index>=items.size():return
	var previous:Dictionary=items[index]
	var side:String=SIDES[(SIDES.find(previous.side)+1)%SIDES.size()]
	var length:int=layout.width if side in ["north","south"] else layout.height
	var target:Dictionary={"side":side,"offset":mini(int(previous.offset),length-1)}
	if not _opening_at(target).is_empty():return
	items[index]=target
	_sync_primary()

func _opening_valid(spec:Dictionary) -> bool:
	if spec.get("side","") not in SIDES or not spec.get("offset") is int:return false
	var length:int=layout.width if spec.side in ["north","south"] else layout.height
	return spec.offset>=0 and spec.offset<length

func select_furniture(furniture: String) -> void:
	furniture_kind=furniture if furniture in FURNITURE else ""
	_selected_furniture=-1
	_furniture_rotation=0

func remove_furniture_at(cell: int) -> void:
	var local:=_local_cell(cell)
	if local.x<0: return
	for i in range(layout.furniture.size()-1,-1,-1):
		if _furniture_contains(layout.furniture[i],local): layout.furniture.remove_at(i)
	_selected_furniture=-1

func proposal() -> Dictionary:
	var result:={"kind":kind,"origin_cell":_origin_cell(),"rotation":0,"layout":layout.duplicate(true)}
	if room_id!="": result.room_id=room_id
	return result

# A drawing gesture can be abandoned without losing the previously confirmed draft.
func capture_state() -> Dictionary:
	return {"anchor":anchor,"end":end,"layout":layout.duplicate(true),"awaiting_corner":_awaiting_corner,"opening_tool":opening_tool,"selected_opening":selected_opening.duplicate(),"openings_edited":_openings_edited}

func restore_state(state: Dictionary) -> void:
	anchor=state.anchor
	end=state.end
	layout=state.layout.duplicate(true)
	_awaiting_corner=state.awaiting_corner
	opening_tool=state.get("opening_tool","door")
	selected_opening=state.get("selected_opening",{}).duplicate()
	_openings_edited=state.get("openings_edited",false)

func _size_valid() -> bool:
	if layout.has("footprint_version"):
		if not layout.footprint_version is int or layout.footprint_version != 2: return false
		return _origin_cell()>=0 and int(layout.width)>=3 and int(layout.height)>=3 and int(layout.width)<=22 and int(layout.height)<=7 and EquipmentFootprints.fits_room(kind,int(layout.width),int(layout.height))
	var minimum:=3 if kind in ["reception","recovery"] else 4
	return _origin_cell()>=0 and int(layout.width)>=minimum and int(layout.height)>=minimum and int(layout.width)<=22 and int(layout.height)<=7

func _furniture_contains(item: Dictionary, local: Vector2i) -> bool:
	if not layout.has("footprint_version"):
		return item.x==local.x and item.y==local.y
	return [local.x,local.y] in EquipmentFootprints.furniture_cells(item)

func _door_valid() -> bool:
	var door: Dictionary=layout.get("door",{})
	if not _opening_valid(door):return false
	if not layout.has("doors") and not layout.has("windows"):return true
	var doors:Array=layout.get("doors",[door])
	if doors.is_empty() or doors[0]!=door:return false
	var occupied:Array=[]
	for spec in doors+layout.get("windows",[]):
		if not spec is Dictionary or not _opening_valid(spec) or spec in occupied:return false
		occupied.append(spec)
	return true

func _origin_cell() -> int:
	if anchor<0 or end<0: return -1
	return mini(anchor%GRID_WIDTH,end%GRID_WIDTH)+mini(anchor/GRID_WIDTH,end/GRID_WIDTH)*GRID_WIDTH

func _local_cell(cell: int) -> Vector2i:
	var origin:=_origin_cell()
	if origin<0 or not _valid_cell(cell): return Vector2i(-1,-1)
	var local:=Vector2i(cell%GRID_WIDTH-origin%GRID_WIDTH,cell/GRID_WIDTH-origin/GRID_WIDTH)
	return local if local.x>=0 and local.y>=0 and local.x<int(layout.width) and local.y<int(layout.height) else Vector2i(-1,-1)

func _valid_cell(cell: int) -> bool:
	return cell>=0 and cell<GRID_WIDTH*GRID_HEIGHT

func _clear_bounds() -> void:
	anchor=-1
	end=-1
	_awaiting_corner=false
	layout.width=0
	layout.height=0
	_clear_items()

func _clear_items() -> void:
	layout.door={}
	layout.erase("doors")
	layout.erase("windows")
	_openings_edited=false
	selected_opening={}
	opening_tool="door"
	layout.equipment={}
	layout.furniture=[]
	_selected_furniture=-1
