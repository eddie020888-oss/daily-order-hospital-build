class_name CampaignBuildDraft
extends RefCounted

var mode:="build"
var kind:=""
var unit_id:=""
var room_id:=""
var step:=0
var origin_cell:=-1
var layout:Dictionary={"width":0,"height":0,"doors":[],"windows":[],"facilities":[]}
var original_layout:Dictionary={}
var opening_tool:="door"
var selected_opening:Dictionary={}
var selected_index:=-1
var selected_kind:=""
var _rotation:=0
var _anchor:=-1
var _awaiting_corner:=false
var _serial:=0
var bounds_issue:=""

func initialize(operation:String,facility_kind:String,room:Dictionary={}) -> void:
	mode=operation;kind=facility_kind;selected_kind=facility_kind
	unit_id=str(FacilityLayout.facility_spec(facility_kind).get("unit_id",room.get("unit_id","")))
	if not room.is_empty():
		room_id=str(room.id);unit_id=str(room.unit_id);origin_cell=int(room.origin_cell)
		layout=room.layout.duplicate(true);original_layout=room.layout.duplicate(true)
		_anchor=origin_cell
		if mode=="edit":
			selected_index=0 if not layout.facilities.is_empty() else -1
			if selected_index>=0:kind=str(layout.facilities[0].kind);selected_kind=kind
		else:step=2

func proposal() -> Dictionary:
	var value:Dictionary={"unit_id":unit_id,"origin_cell":origin_cell,"rotation":0,"layout":layout.duplicate(true)}
	if room_id!="":value.room_id=room_id
	return value

func capture_state() -> Dictionary:
	return {"origin_cell":origin_cell,"layout":layout.duplicate(true),"anchor":_anchor,"awaiting":_awaiting_corner,"selected_index":selected_index,"selected_kind":selected_kind,"rotation":_rotation,"opening_tool":opening_tool,"selected_opening":selected_opening.duplicate(true),"serial":_serial}

func restore_state(value:Dictionary) -> void:
	bounds_issue=""
	origin_cell=int(value.origin_cell);layout=value.layout.duplicate(true);_anchor=int(value.anchor);_awaiting_corner=bool(value.awaiting)
	selected_index=int(value.selected_index);selected_kind=str(value.selected_kind);_rotation=int(value.rotation)
	opening_tool=str(value.opening_tool);selected_opening=value.selected_opening.duplicate(true);_serial=int(value.serial)

func choose_cell(cell:int) -> void:
	if cell<0 or cell>=432:return
	if step==0:
		if mode=="edit":set_bounds(origin_cell,cell);return
		if _awaiting_corner:set_bounds(_anchor,cell)
		else:_anchor=cell;origin_cell=cell;layout.width=1;layout.height=1;_awaiting_corner=true
		return
	var local:=Vector2i(cell%24-origin_cell%24,int(cell/24)-int(origin_cell/24))
	if local.x<0 or local.y<0 or local.x>=int(layout.width) or local.y>=int(layout.height):return
	if step==1:
		var side:String="south" if local.y==int(layout.height)-1 else "east" if local.x==int(layout.width)-1 else "north" if local.y==0 else "west" if local.x==0 else ""
		if side!="":choose_wall(side,local.x if side in ["north","south"] else local.y)
	elif step in [2,3] and selected_kind!="":
		if selected_index<0:
			_serial+=1
			layout.facilities.append({"id":"__scene_draft_%04d"%_serial,"kind":selected_kind,"x":local.x,"y":local.y,"rotation":_rotation})
			selected_index=layout.facilities.size()-1
		else:
			layout.facilities[selected_index].x=local.x;layout.facilities[selected_index].y=local.y

func set_bounds(first:int,last:int) -> void:
	if step!=0 or first<0 or last<0 or first>=432 or last>=432:return
	bounds_issue=""
	var width:int=last%24-origin_cell%24+1 if mode=="edit" else absi(first%24-last%24)+1
	var height:int=int(last/24)-int(origin_cell/24)+1 if mode=="edit" else absi(int(first/24)-int(last/24))+1
	if _would_crop_opening(width,height):
		bounds_issue="先移动边缘门窗，再缩小房间。";return
	if mode!="edit":origin_cell=mini(first%24,last%24)+mini(int(first/24),int(last/24))*24
	layout.width=width;layout.height=height
	_anchor=origin_cell;_awaiting_corner=false

func _would_crop_opening(width:int,height:int) -> bool:
	for group:String in ["doors","windows"]:
		for spec:Dictionary in layout[group]:
			var extent:int=width if str(spec.side) in ["north","south"] else height
			if int(spec.offset)<0 or int(spec.offset)>=extent:return true
	return false

func adjust_bounds(delta:Vector2i,offset:Vector2i=Vector2i.ZERO) -> bool:
	if step!=0 or origin_cell<0 or (mode=="edit" and offset!=Vector2i.ZERO):return false
	bounds_issue=""
	var width:int=int(layout.width)+delta.x
	var height:int=int(layout.height)+delta.y
	var x:int=origin_cell%24+offset.x
	var y:int=int(origin_cell/24)+offset.y
	if width<3 or width>22 or height<3 or height>7 or x<1 or x+width>23 or y<1 or y+height>17:return false
	for row:int in range(y,y+height):
		if row in [8,9]:return false
	if _would_crop_opening(width,height):
		bounds_issue="先移动边缘门窗，再缩小房间。";return false
	layout.width=width;layout.height=height;origin_cell=y*24+x;_anchor=origin_cell;_awaiting_corner=false
	return true

func select_opening_tool(tool:String) -> void:
	if tool in ["door","window","move","remove"]:opening_tool=tool

func choose_wall(side:String,offset:int) -> void:
	if step!=1 or not _opening_valid(side,offset):return
	bounds_issue=""
	var spec:Dictionary={"side":side,"offset":offset}
	var at:Dictionary={}
	for group:String in ["doors","windows"]:
		for index:int in range(layout[group].size()):
			if layout[group][index]==spec:at={"group":group,"index":index}
	if not at.is_empty():
		selected_opening=at
		if opening_tool=="remove":layout[at.group].remove_at(at.index);selected_opening={}
		return
	if opening_tool=="move":
		if not selected_opening.is_empty():layout[selected_opening.group][selected_opening.index]=spec
	elif opening_tool in ["door","window"]:
		var group:String="doors" if opening_tool=="door" else "windows"
		layout[group].append(spec);selected_opening={"group":group,"index":layout[group].size()-1}

func _opening_valid(side:String,offset:int) -> bool:
	return side in ["north","east","south","west"] and offset>=0 and offset<int(layout.width if side in ["north","south"] else layout.height)

func choose_facility(facility_kind:String) -> void:
	selected_kind=facility_kind;selected_index=-1;_rotation=0

func select_facility(index:int) -> void:
	if index<0 or index>=layout.facilities.size():return
	selected_index=index;selected_kind=str(layout.facilities[index].kind);_rotation=int(layout.facilities[index].rotation)

func remove_selected() -> bool:
	if step==1 and not selected_opening.is_empty():
		layout[selected_opening.group].remove_at(selected_opening.index);selected_opening={};return true
	if step in [2,3] and selected_index>=0 and selected_index<layout.facilities.size():
		layout.facilities.remove_at(selected_index);selected_index=-1;return true
	return false

func rotate() -> void:
	if step==1 and not selected_opening.is_empty():
		var previous:Dictionary=layout[selected_opening.group][selected_opening.index]
		var sides:Array=["north","east","south","west"]
		var side:String=sides[(sides.find(previous.side)+1)%4]
		var extent:int=layout.width if side in ["north","south"] else layout.height
		var next:Dictionary={"side":side,"offset":mini(int(previous.offset),extent-1)}
		for group:String in ["doors","windows"]:
			if next in layout[group]:return
		layout[selected_opening.group][selected_opening.index]=next
	elif step in [2,3]:
		_rotation=(_rotation+1)%4
		if selected_index>=0:layout.facilities[selected_index].rotation=_rotation

func bounds_error(snapshot:Dictionary) -> String:
	var width:int=layout.width;var height:int=layout.height
	if origin_cell<0 or width<3 or width>22 or height<3 or height>7:return "invalid_layout_dimensions"
	var x:int=origin_cell%24;var y:int=origin_cell/24
	if x<1 or x+width>23 or y<1 or y+height>17:return "boundary"
	var restrictions:Array=[]
	for row:int in range(y,y+height):
		if row in [8,9]:return "main_corridor"
		for column:int in range(x,x+width):restrictions.append(row*24+column)
	for id:String in snapshot.get("rooms",{}):
		if id==room_id:continue
		for cell:int in snapshot.rooms[id].cells:
			if cell in restrictions:return "room_overlap"
	return ""

func required_placed() -> bool:
	if mode=="edit":return not layout.facilities.is_empty()
	for item:Dictionary in layout.facilities:
		if item.kind!=kind:continue
		if mode=="build" or not _preserved(str(item.id)):return true
	return false

func _preserved(id:String) -> bool:
	for item:Dictionary in original_layout.get("facilities",[]):
		if item.id==id:return true
	return false

func command() -> Dictionary:
	if mode=="build":return {"type":"build_department","payload":{"unit_id":unit_id,"origin_cell":origin_cell,"layout":layout.duplicate(true)}}
	if mode=="install":
		var added:Array=[]
		for item:Dictionary in layout.facilities:
			if not _preserved(str(item.id)):added.append(item)
		# The fast single-install command is valid only when every retained
		# instance still matches the preview, including position and rotation.
		var baseline:Dictionary=layout.duplicate(true);baseline.facilities=[]
		for item:Dictionary in layout.facilities:
			if _preserved(str(item.id)):baseline.facilities.append(item.duplicate(true))
		if added.size()==1 and baseline==original_layout:
			var item:Dictionary=added[0]
			return {"type":"place_facility","payload":{"room_id":room_id,"kind":item.kind,"x":item.x,"y":item.y,"rotation":item.rotation}}
	return {"type":"edit_department","payload":{"room_id":room_id,"layout":layout.duplicate(true)}}
