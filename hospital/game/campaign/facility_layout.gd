class_name FacilityLayout
extends RefCounted

## Campaign layouts describe real grid cells. Device x/y is always the
## rotated BODY rectangle's top-left; operation cells never enlarge that body.
const RULESET := "full-hospital-v1"
const ART_CATALOG := "res://assets/equipment/catalog-isometric-v1/catalog.json"
const CONTENT := "res://content/full_hospital.json"
static var _art:Dictionary={}
static var _definitions:Dictionary={}
static var _units:Dictionary={}
static var _art_loaded := false
static var _content_loaded := false

static func facility_spec(kind:String) -> Dictionary:
	if not _art_loaded:
		_art_loaded=true
		var raw:Variant=JSON.parse_string(FileAccess.get_file_as_string(ART_CATALOG))
		if raw is Dictionary and raw.get("items") is Array:
			for item:Variant in raw.items:
				if item is Dictionary and item.get("id") is String:_art[item.id]=item
	if not _content_loaded and FileAccess.file_exists(CONTENT):
		var raw:Variant=JSON.parse_string(FileAccess.get_file_as_string(CONTENT))
		if raw is Dictionary and raw.get("facilities") is Dictionary:
			_definitions=raw.facilities
			_units=raw.get("units",{})
			_content_loaded=true
	if not _art.has(kind):return {}
	var result:Dictionary=_art[kind].duplicate(true)
	if _definitions.has(kind):result.merge(_definitions[kind],true)
	return result

static func unit_name(unit_id:String) -> String:
	# Trigger the same read-only content loader without duplicating assets.
	facility_spec("U01-E1")
	if _units.has(unit_id):return str(_units[unit_id].get("name",unit_id))
	for item:Dictionary in _art.values():
		if item.get("unit_id","")==unit_id:return str(item.get("unit_name",unit_id))
	return "运营服务" if unit_id in ["","OPS","operations"] else unit_id

static func default_layout(_unit_id:String,facility_kind:String,quarter:int=0) -> Dictionary:
	var station:=_station(facility_kind,quarter)
	if station.is_empty():return {}
	var low:=Vector2i(1000,1000)
	var high:=Vector2i(-1000,-1000)
	for point:Array in _station_points(station):
		low=low.min(Vector2i(point[0],point[1]));high=high.max(Vector2i(point[0],point[1]))
	# Rotate the two canonical empty aisles with the work positions: q0 has
	# east/south, q1 west/south, q2 west/north, q3 east/north. Keeping the
	# margin always east/south can trap a patient or repairer behind coworkers.
	# The extents do not grow; the3x5 scanner still fits the7-cell-deep strip.
	var width:=maxi(3,high.x-low.x+2)
	var height:=maxi(3,high.y-low.y+2)
	var placement:Vector2i=-low
	if quarter in [1,2]:placement.x+=1
	if quarter in [2,3]:placement.y+=1
	# Both vertical aisles reach the south edge. Use that aisle's corner so
	# the default doorway stays useful beside the main corridor even for a
	# room occupying all7 rows. Other legal door sides remain editable.
	var door_offset:int=0 if quarter in [1,2] else width-1
	return {"width":width,"height":height,"doors":[{"side":"south","offset":door_offset}],"windows":[],
		"facilities":[{"id":"__preview_facility__","kind":facility_kind,"x":placement.x,"y":placement.y,"rotation":quarter}]}

static func facility_geometry(record:Dictionary,item:Dictionary) -> Dictionary:
	var station:=_station(str(item.get("kind","")),int(item.get("rotation",-1)))
	if station.is_empty() or not item.get("x") is int or not item.get("y") is int:return {}
	var origin:int=record.get("origin_cell",0)
	var result:Dictionary={"id":item.get("id",""),"kind":item.kind,"room_id":record.get("id",""),"x":item.x,"y":item.y,"rotation":item.rotation,
		"equipment_cells":[],"service_cells":[],"staff_cells":[],"body_size":station.body_size.duplicate()}
	for key:String in ["equipment_cells","service_cells","staff_cells"]:
		for point:Array in station[key]:result[key].append(_global(origin,[point[0]+item.x,point[1]+item.y]))
	var maintenance:Array=station.maintenance
	result.maintenance_cell=_global(origin,[maintenance[0]+item.x,maintenance[1]+item.y])
	return result

static func geometry(record:Dictionary) -> Dictionary:
	if _shape_error(record)!="":return {}
	var layout:Dictionary=record.layout
	var result:Dictionary=record.duplicate(true)
	result.kind="campaign_department";result.ruleset=RULESET;result.rotation=0
	result.width=layout.width;result.height=layout.height
	for key:String in ["cells","equipment_cells","service_cells","staff_cells","maintenance_cells","furniture_cells","wall_edges","doorways","window_edges"]:result[key]=[]
	result.facility_geometries={}
	for y:int in range(layout.height):
		for x:int in range(layout.width):result.cells.append(_global(record.origin_cell,[x,y]))
	var doors:Dictionary={}
	for spec:Dictionary in layout.doors:
		var edge:Array=RoomOpenings.global_edge(record.origin_cell,layout,spec)
		result.doorways.append({"door_cell":edge[0],"door_outside_cell":edge[1]})
		doors[_edge_key(edge[0],edge[1])]=true
	result.door_cell=result.doorways[0].door_cell
	result.door_outside_cell=result.doorways[0].door_outside_cell
	for spec:Dictionary in layout.get("windows",[]):
		var edge:Array=RoomOpenings.global_edge(record.origin_cell,layout,spec)
		result.window_edges.append([mini(edge[0],edge[1]),maxi(edge[0],edge[1])])
	var perimeter:Array=[]
	for x:int in range(layout.width):
		perimeter.append([_global(record.origin_cell,[x,0]),_global(record.origin_cell,[x,-1])])
		perimeter.append([_global(record.origin_cell,[x,layout.height-1]),_global(record.origin_cell,[x,layout.height])])
	for y:int in range(layout.height):
		perimeter.append([_global(record.origin_cell,[0,y]),_global(record.origin_cell,[-1,y])])
		perimeter.append([_global(record.origin_cell,[layout.width-1,y]),_global(record.origin_cell,[layout.width,y])])
	for edge:Array in perimeter:
		if not doors.has(_edge_key(edge[0],edge[1])):result.wall_edges.append([mini(edge[0],edge[1]),maxi(edge[0],edge[1])])
	for item:Dictionary in layout.facilities:
		var station:=facility_geometry(record,item)
		if station.is_empty():return {}
		result.facility_geometries[item.id]=station
		for key:String in ["equipment_cells","service_cells","staff_cells"]:result[key].append_array(station[key])
		result.maintenance_cells.append(station.maintenance_cell)
	return result

static func validate(record:Dictionary,rooms:Dictionary={}) -> String:
	var error:=_shape_error(record)
	if error!="":return error
	var layout:Dictionary=record.layout
	var ox:int=record.origin_cell%24
	var oy:int=record.origin_cell/24
	if ox<1 or ox+layout.width>23 or oy<1 or oy+layout.height>17:return "boundary"
	for y:int in range(oy,oy+layout.height):
		if y in [8,9]:return "main_corridor"
	var room:=geometry(record)
	var body:Dictionary={}
	var work:Dictionary={}
	var forbidden:Dictionary={}
	for doorway:Dictionary in room.doorways:
		forbidden[doorway.door_cell]=true
		forbidden[doorway.door_cell*2-doorway.door_outside_cell]=true
	for station:Dictionary in room.facility_geometries.values():
		for cell:int in station.equipment_cells:
			if not cell in room.cells:return "facility_out_of_bounds"
			if body.has(cell):return "facility_overlap"
			if forbidden.has(cell):return "door_blocked"
			body[cell]=true
	for station:Dictionary in room.facility_geometries.values():
		for cell:int in station.service_cells+station.staff_cells+[station.maintenance_cell]:
			if not cell in room.cells:return "facility_access_out_of_bounds"
			if body.has(cell):return "facility_access_overlap"
			if work.has(cell):return "facility_work_position_overlap"
			if forbidden.has(cell):return "door_operating_position"
			work[cell]=true
	var candidate_rooms:Dictionary=rooms.duplicate(true)
	var own_id:String=record.get("id",record.get("room_id",""))
	if not own_id.is_empty():candidate_rooms.erase(own_id)
	for other:Dictionary in candidate_rooms.values():
		var existing:Dictionary=GridService._room_geometry(other)
		for cell:int in existing.get("cells",[]):
			if cell in room.cells:return "room_overlap"
	var candidate_id:="__campaign_candidate__"
	while candidate_rooms.has(candidate_id):candidate_id+="_"
	candidate_rooms[candidate_id]=room
	var navigation:Dictionary=GridService._navigation(candidate_rooms)
	var reachable:Dictionary=GridService._flood(navigation,GridService.EXIT_CELL)
	# A window stays a wall for walking. Each real door must have an open edge,
	# including against the independently owned boundary of an adjacent room.
	for existing_record:Dictionary in candidate_rooms.values():
		var existing:Dictionary=GridService._room_geometry(existing_record)
		for doorway:Dictionary in existing.get("doorways",[{"door_cell":existing.door_cell,"door_outside_cell":existing.door_outside_cell}]):
			if not GridService._can_step(navigation,doorway.door_cell,doorway.door_outside_cell):return "room_unreachable"
			if not reachable.has(doorway.door_cell) or not reachable.has(doorway.door_outside_cell):return "room_unreachable"
		for cell:int in existing.get("service_cells",[])+existing.get("staff_cells",[])+existing.get("maintenance_cells",[]):
			if not reachable.has(cell):return "facility_unreachable"
	return _occupied_access_error(candidate_rooms)

static func _occupied_access_error(rooms:Dictionary) -> String:
	# A geometrically empty aisle is insufficient if its only route crosses
	# another assigned employee or a patient. Reserve every campaign work
	# position, then release only the destination being tested. Maintenance
	# must also be reachable while staff/patients remain at their stations.
	var occupied:Dictionary={}
	var targets:Array=[]
	for record:Dictionary in rooms.values():
		if record.get("ruleset","")!=RULESET and record.get("kind","")!="campaign_department":continue
		var room:Dictionary=geometry(record)
		for cell:int in room.get("service_cells",[])+room.get("staff_cells",[]):
			occupied[cell]=true;targets.append(cell)
		targets.append_array(room.get("maintenance_cells",[]))
	var state:ClinicState=ClinicState.new()
	state.data={"rooms":rooms}
	for cell:int in targets:
		var blocked:Dictionary=occupied.duplicate()
		blocked.erase(cell)
		if GridService.path_avoiding(state,GridService.EXIT_CELL,cell,blocked).is_empty():return "facility_occupied_unreachable"
	return ""

static func preview(state:Variant,proposal:Dictionary) -> Dictionary:
	var record:Dictionary=proposal.duplicate(true)
	record["id"]=proposal.get("room_id",proposal.get("id","__preview_room__"))
	record["kind"]="campaign_department";record["ruleset"]=RULESET;record["rotation"]=0
	record["status"]=proposal.get("status","open");record["staff_id"]="";record["upgraded"]=false
	var rooms:Dictionary={}
	if state is ClinicState:rooms=state.data.get("rooms",{})
	elif state is Dictionary:rooms=state.get("rooms",{})
	var error:=validate(record,rooms)
	if error!="":return {"ok":false,"code":error,"data":{}}
	var candidate:=geometry(record)
	var candidate_rooms:Dictionary=rooms.duplicate(true)
	candidate_rooms.erase(record.id)
	candidate_rooms[record.id]=candidate
	var navigation:Dictionary=GridService._navigation(candidate_rooms)
	var reachable:Dictionary=GridService._flood(navigation,GridService.EXIT_CELL)
	var data:Dictionary=state.data if state is ClinicState else state if state is Dictionary else {}
	if data.get("schema_version",0)==3 and data.get("ruleset","")=="full-hospital-v2":
		var queue_excluded:Dictionary=queue_excluded_cells(candidate_rooms)
		for patient_id:String in data.get("campaign",{}).get("live_patient_ids",[]):
			var patient:Dictionary=data.patients[patient_id]
			if not patient.has("queue_cell"):continue
			var queue_cell:int=int(patient.queue_cell)
			if queue_excluded.has(queue_cell) or not reachable.has(queue_cell):
				return {"ok":false,"code":"queue_position_blocked","data":{"actor_id":patient_id,"cell":queue_cell}}
	for collection:String in ["patients","staff"]:
		for actor_id:String in data.get(collection,{}):
			var actor:Dictionary=data[collection][actor_id]
			if not actor.has("cell"):continue
			var current:int=actor.cell
			if not GridService._walkable(navigation,current) or not reachable.has(current):
				return {"ok":false,"code":"actor_blocked","data":{"actor_id":actor_id,"cell":current}}
			if int(actor.get("move_progress",0))<=0:continue
			var route:Array=actor.get("path",[])
			var index:int=actor.get("path_index",0)
			if index<0 or index+1>=route.size() or route[index]!=current:
				return {"ok":false,"code":"invalid_actor_path","data":{"actor_id":actor_id,"cell":current}}
			var next:int=route[index+1]
			if not reachable.has(next) or not GridService._can_step(navigation,current,next):
				return {"ok":false,"code":"in_flight_edge_blocked","data":{"actor_id":actor_id,"cell":current,"to_cell":next}}
	return {"ok":true,"code":"ok","data":{"room":candidate}}

# Queue destinations must leave every station, maintenance point and doorway
# available. Shared by movement, saved-state validation and atomic layout edits.
static func queue_excluded_cells(rooms:Dictionary) -> Dictionary:
	var excluded:Dictionary={GridService.EXIT_CELL:true}
	for record:Dictionary in rooms.values():
		var room:Dictionary=geometry(record)
		for key:String in ["equipment_cells","service_cells","staff_cells","maintenance_cells"]:
			for cell:int in room.get(key,[]):excluded[cell]=true
		for doorway:Dictionary in room.get("doorways",[]):
			excluded[int(doorway.door_cell)]=true
			excluded[int(doorway.door_outside_cell)]=true
	return excluded

static func _shape_error(record:Dictionary) -> String:
	if not record.get("origin_cell") is int or record.origin_cell<0 or record.origin_cell>=432:return "invalid_origin"
	if not record.get("unit_id") is String:return "invalid_unit"
	if not record.get("layout") is Dictionary:return "invalid_layout"
	var layout:Dictionary=record.layout
	if not layout.get("width") is int or not layout.get("height") is int:return "invalid_layout_dimensions"
	if layout.width<3 or layout.width>22 or layout.height<3 or layout.height>7:return "invalid_layout_dimensions"
	if record.has("width") and record.width!=layout.width or record.has("height") and record.height!=layout.height:return "invalid_layout_dimensions"
	if not layout.get("doors") is Array or layout.doors.is_empty():return "invalid_doors"
	var openings:Dictionary=layout.duplicate(true)
	openings["door"]=layout.doors[0]
	var opening_error:=RoomOpenings.validate_shape(openings)
	if opening_error!="":return opening_error
	if not layout.get("facilities") is Array or layout.facilities.size()>128:return "invalid_facilities"
	var ids:Dictionary={}
	for value:Variant in layout.facilities:
		if not value is Dictionary:return "invalid_facility"
		if not value.get("id") is String or value.id.is_empty() or ids.has(value.id):return "invalid_facility_id"
		ids[value.id]=true
		if not value.get("kind") is String or facility_spec(value.kind).is_empty():return "unknown_facility"
		for field:String in ["x","y","rotation"]:
			if not value.get(field) is int:return "invalid_facility_placement"
		if value.rotation<0 or value.rotation>3 or value.x<0 or value.y<0 or value.x>=layout.width or value.y>=layout.height:return "invalid_facility_placement"
	return ""

static func _station(kind:String,quarter:int) -> Dictionary:
	var spec:=facility_spec(kind)
	if spec.is_empty() or quarter<0 or quarter>3:return {}
	var width:int=spec.body_size[0]
	var height:int=spec.body_size[1]
	var staff_count:int=maxi(1,spec.get("roles",[]).size())
	var result:Dictionary={"equipment_cells":[],"service_cells":[_rotate([0,height],width,height,quarter)],"staff_cells":[],
		"maintenance":_rotate([width,0],width,height,quarter),"body_size":[height,width] if quarter%2 else [width,height]}
	for y:int in range(height):
		for x:int in range(width):result.equipment_cells.append(_rotate([x,y],width,height,quarter))
	for index:int in range(staff_count):result.staff_cells.append(_rotate([index+1,height],width,height,quarter))
	return result

static func _station_points(station:Dictionary) -> Array:
	return station.equipment_cells+station.service_cells+station.staff_cells+[station.maintenance]

static func _rotate(point:Array,width:int,height:int,quarter:int) -> Array:
	var result:Array=point.duplicate()
	for step:int in range(quarter):
		result=[height-1-result[1],result[0]]
		var previous_width:int=width;width=height;height=previous_width
	return result

static func _global(origin:int,point:Array) -> int:
	return origin+int(point[1])*24+int(point[0])

static func _edge_key(a:int,b:int) -> String:
	return "%d:%d"%[mini(a,b),maxi(a,b)]
