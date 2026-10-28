extends RefCounted

# Read-only, bounded suggestions. Every returned complete plan passes the same
# geometry, occupied-workplace, actor and in-flight-edge checks as normal build.
static var _dimensions:Dictionary={}
const MAX_PREVIEWS:int=64

static func dimensions(kind:String)->Dictionary:
	if _dimensions.has(kind):return _dimensions[kind].duplicate(true)
	var spec:Dictionary=FacilityLayout.facility_spec(kind)
	if spec.is_empty():return {}
	for quarter:int in range(4):
		var layout:Dictionary=FacilityLayout.default_layout(str(spec.unit_id),kind,quarter)
		if int(layout.width)<=22 and int(layout.height)<=7:
			var value:Dictionary={"width":int(layout.width),"height":int(layout.height),"rotation":quarter,"body_size":spec.body_size.duplicate()}
			_dimensions[kind]=value
			return value.duplicate(true)
	return {}

static func room(snapshot:Dictionary,kind:String,origin:int,preferred:int=179,reserved:Array=[])->Dictionary:
	var size:Dictionary=dimensions(kind)
	if size.is_empty():return {"ok":false,"code":"unknown_facility"}
	var origins:Array=[]
	if origin>=0:origins.append(origin)
	else:
		var target:int=clampi(preferred,0,431)
		for y:int in range(1,17-int(size.height)+1):
			for x:int in range(1,23-int(size.width)+1):origins.append(y*24+x)
		origins.sort_custom(func(a:int,b:int)->bool:
			var ad:int=absi(a%24-target%24)+absi(int(a/24)-int(target/24))
			var bd:int=absi(b%24-target%24)+absi(int(b/24)-int(target/24))
			return ad<bd or (ad==bd and a<b))
	var last:Dictionary={"ok":false,"code":"recommended_room_unavailable"}
	var remaining:int=MAX_PREVIEWS
	for cell:int in origins:
		var layout:Dictionary={"width":int(size.width),"height":int(size.height),"doors":[],"windows":[],"facilities":[]}
		var draft:=CampaignBuildDraft.new();draft.origin_cell=cell;draft.layout=layout
		var error:String=draft.bounds_error(snapshot)
		if error!="":last={"ok":false,"code":error};continue
		var blocked:int=_reserved_cell(cell,int(layout.width),int(layout.height),reserved)
		if blocked>=0:last={"ok":false,"code":"reserved_plot","data":{"cell":blocked}};continue
		var offered:Dictionary=furnish(snapshot,kind,cell,layout,mini(8,remaining),reserved)
		if offered.get("ok",false):return offered
		last=offered
		remaining-=int(offered.get("checks",0))
		if remaining<=0:return last
	return last

static func furnish(snapshot:Dictionary,kind:String,origin:int,source:Dictionary,budget:int=MAX_PREVIEWS,reserved:Array=[])->Dictionary:
	if not source.get("facilities",[]).is_empty():return {"ok":false,"code":"recommendation_has_facilities"}
	var draft:=CampaignBuildDraft.new();draft.origin_cell=origin;draft.layout=source.duplicate(true)
	var error:String=draft.bounds_error(snapshot)
	if error!="":return {"ok":false,"code":error}
	var blocked:int=_reserved_cell(origin,int(source.width),int(source.height),reserved)
	if blocked>=0:return {"ok":false,"code":"reserved_plot","data":{"cell":blocked}}
	var spec:Dictionary=FacilityLayout.facility_spec(kind)
	if spec.is_empty():return {"ok":false,"code":"unknown_facility"}
	var width:int=int(source.width);var height:int=int(source.height)
	var count:int=0
	var last:Dictionary={"ok":false,"code":"recommended_layout_unavailable"}
	for quarter:int in range(4):
		var station:Dictionary=FacilityLayout._station(kind,quarter)
		var low:=Vector2i(1000,1000);var high:=Vector2i(-1000,-1000)
		for point:Array in FacilityLayout._station_points(station):
			low=low.min(Vector2i(point[0],point[1]));high=high.max(Vector2i(point[0],point[1]))
		var anchors:Array=[]
		var canonical:Dictionary=FacilityLayout.default_layout(str(spec.unit_id),kind,quarter)
		var first:Vector2i=Vector2i(canonical.facilities[0].x,canonical.facilities[0].y)
		for y:int in range(-low.y,height-high.y):
			for x:int in range(-low.x,width-high.x):anchors.append(Vector2i(x,y))
		anchors.sort_custom(func(a:Vector2i,b:Vector2i)->bool:
			var ad:int=absi(a.x-first.x)+absi(a.y-first.y)
			var bd:int=absi(b.x-first.x)+absi(b.y-first.y)
			return ad<bd or (ad==bd and (a.y<b.y or (a.y==b.y and a.x<b.x))))
		var door_plans:Array=[]
		if not source.get("doors",[]).is_empty():door_plans.append(source.doors.duplicate(true))
		else:
			var preferred:Dictionary={"side":"south","offset":0 if quarter in [1,2] else width-1}
			door_plans.append([preferred])
			for side:String in ["south","east","north","west"]:
				for offset:int in range(width if side in ["south","north"] else height):
					var door:Dictionary={"side":side,"offset":offset}
					if door==preferred or door in source.get("windows",[]):continue
					door_plans.append([door])
		for anchor:Vector2i in anchors:
			for doors:Array in door_plans:
				if not _entrance_clear(station,anchor,doors,width,height):continue
				var layout:Dictionary=source.duplicate(true)
				layout.doors=doors.duplicate(true)
				layout.facilities=[{"id":"__scene_recommended_0001","kind":kind,"x":anchor.x,"y":anchor.y,"rotation":quarter}]
				var proposal:Dictionary={"unit_id":str(spec.unit_id),"origin_cell":origin,"rotation":0,"layout":layout}
				var preview:Dictionary=FacilityLayout.preview(snapshot,proposal)
				count+=1
				if preview.get("ok",false):return {"ok":true,"code":"ok","proposal":proposal,"preview":preview,"checks":count}
				last={"ok":false,"code":str(preview.get("code","recommended_layout_unavailable")),"checks":count}
				if count>=budget:return last
	return last

static func _reserved_cell(origin:int,width:int,height:int,reserved:Array)->int:
	var x:int=origin%24;var y:int=int(origin/24)
	for value:Variant in reserved:
		var cell:int=int(value)
		if cell%24>=x and cell%24<x+width and int(cell/24)>=y and int(cell/24)<y+height:return cell
	return -1

static func _entrance_clear(station:Dictionary,anchor:Vector2i,doors:Array,width:int,height:int)->bool:
	var occupied:Dictionary={}
	for point:Array in FacilityLayout._station_points(station):occupied[Vector2i(point[0],point[1])+anchor]=true
	for door:Dictionary in doors:
		var cell:=Vector2i.ZERO;var inward:=Vector2i.ZERO
		match str(door.side):
			"north":cell=Vector2i(int(door.offset),0);inward=Vector2i.DOWN
			"south":cell=Vector2i(int(door.offset),height-1);inward=Vector2i.UP
			"east":cell=Vector2i(width-1,int(door.offset));inward=Vector2i.LEFT
			"west":cell=Vector2i(0,int(door.offset));inward=Vector2i.RIGHT
			_:return false
		if occupied.has(cell) or occupied.has(cell+inward):return false
	return true
