class_name FreeRoomLayout
extends RefCounted

const FURNITURE_COSTS := {"plant":50,"bench":80,"cabinet":100,"bin":30}
const STATION_KEYS := ["equipment_cells","service_cells","staff_cells","upgrade_equipment_cells","upgrade_service_cells"]

# Layouts contain only local, strictly integral model data. This shape check is
# also usable for a historical move receipt whose room has since been removed.
static func validate_shape(layout: Variant) -> String:
	if not layout is Dictionary:
		return "invalid_layout"
	var keys := ["width","height","door","equipment","furniture"]
	if layout.has("footprint_version"):
		if not layout.footprint_version is int or layout.footprint_version != 2:
			return "invalid_layout"
		keys.append("footprint_version")
	for optional in ["doors","windows"]:
		if layout.has(optional): keys.append(optional)
	if not _keys(layout,keys):
		return "invalid_layout"
	if not layout.width is int or not layout.height is int:
		return "invalid_layout_dimensions"
	if layout.width < 3 or layout.width > 22 or layout.height < 3 or layout.height > 7:
		return "invalid_layout_dimensions"
	var opening_error := RoomOpenings.validate_shape(layout)
	if opening_error != "": return opening_error
	if not layout.equipment is Dictionary or not _keys(layout.equipment,["x","y","rotation"]) or not _placement(layout.equipment,layout.width,layout.height):
		return "invalid_equipment"
	if not layout.furniture is Array or layout.furniture.size() > layout.width * layout.height:
		return "invalid_furniture"
	var occupied := {}
	for item in layout.furniture:
		if not item is Dictionary or not _keys(item,["kind","x","y","rotation"]):
			return "invalid_furniture"
		if not item.kind is String or not FURNITURE_COSTS.has(item.kind) or not _placement(item,layout.width,layout.height):
			return "invalid_furniture"
		var cells: Array = EquipmentFootprints.furniture_cells(item) if _version_two(layout) else [[item.x,item.y]]
		if cells.is_empty():
			return "invalid_furniture"
		for point in cells:
			if not _inside(point,layout.width,layout.height):
				return "invalid_furniture"
			var cell := _cell(point,layout.width)
			if occupied.has(cell):
				return "furniture_overlap"
			occupied[cell] = true
	return ""

static func validate(kind: String, layout: Variant, upgraded: bool = false) -> String:
	if RoomTemplates.definition(kind,0).is_empty():
		return "unknown_kind"
	if upgraded and kind != "recovery":
		return "invalid_upgrade"
	var shape_error := validate_shape(layout)
	if shape_error != "":
		return shape_error
	if _version_two(layout):
		if not EquipmentFootprints.fits_room(kind,layout.width,layout.height):
			return "invalid_layout_dimensions"
	else:
		var minimum := 5 if kind=="ward" else 3 if kind in ["reception","recovery"] else 4
		if layout.width < minimum or layout.height < minimum:
			return "invalid_layout_dimensions"
	var geometry := _definition(kind,layout)
	var equipment: Array = geometry.equipment_cells.duplicate()
	var operations: Array = geometry.service_cells + geometry.staff_cells
	var clearance: Array = geometry.get("clearance_cells",[])
	if upgraded:
		equipment.append_array(geometry.upgrade_equipment_cells)
		operations.append_array(geometry.upgrade_service_cells)
	var blocked := {}
	var doorways: Array = geometry.get("doorways",[{"door_cell":geometry.door_cell,"door_outside_cell":geometry.door_outside_cell}])
	var forbidden: Array = []
	for doorway in doorways:
		forbidden.append(doorway.door_cell)
		forbidden.append(_inner_door(doorway))
	for point in equipment + operations + clearance:
		if not _inside(point,layout.width,layout.height):
			return "equipment_out_of_bounds"
	for point in equipment:
		if point in forbidden:
			return "door_blocked"
		blocked[_cell(point,layout.width)] = true
	for point in geometry.furniture_cells:
		if point in forbidden:
			return "door_blocked"
		var cell := _cell(point,layout.width)
		if blocked.has(cell) or point in operations or point in clearance:
			return "furniture_overlap"
		blocked[cell] = true
	for point in operations + clearance:
		if blocked.has(_cell(point,layout.width)):
			return "equipment_overlap"
	var reachable := _flood(layout.width,layout.height,geometry.door_cell,blocked)
	var required: Array = operations + clearance
	for doorway in doorways:
		required.append(doorway.door_cell)
		required.append(_inner_door(doorway))
	for point in required:
		if not reachable.has(_cell(point,layout.width)):
			return "room_unreachable"
	return ""

# Output mirrors RoomTemplates: the upgrade arrays remain separate, and the
# caller activates them only when upgraded. Validation checks the active set.
static func definition(kind: String, layout: Variant, upgraded: bool = false) -> Dictionary:
	if validate(kind,layout,upgraded) != "":
		return {}
	return _definition(kind,layout)

# Only an explicit player edit calls this. Reading an old save never converts
# it, and its fixed-room price, work positions and entrance remain unchanged.
static func from_template(kind: String, rotation: int) -> Dictionary:
	var template := RoomTemplates.definition(kind,rotation)
	if template.is_empty(): return {}
	var size: int = template.size
	var min_x: int = size
	var min_y: int = size
	for key in STATION_KEYS:
		for point in template[key]:
			min_x = mini(min_x,point[0])
			min_y = mini(min_y,point[1])
	var door: Array = template.door_cell
	var outside: Array = template.door_outside_cell
	var side := "north" if outside[1]<0 else "east" if outside[0]>=size else "south" if outside[1]>=size else "west"
	var offset: int = door[0] if side in ["north","south"] else door[1]
	return {"width":size,"height":size,"door":{"side":side,"offset":offset},"equipment":{"x":min_x,"y":min_y,"rotation":rotation},"furniture":[]}

static func base_cost(kind: String, layout: Dictionary, catalog: ContentCatalog, upgraded: bool = false) -> int:
	if catalog == null or not catalog.rooms.has(kind):
		return 0
	var cost: int = catalog.rooms[kind].cost
	if not layout.is_empty():
		var minimum := 5 if kind=="ward" else 3 if kind in ["reception","recovery"] else 4
		var minimum_area := minimum * minimum
		var dimensions_ok: bool = layout.get("width") is int and layout.get("height") is int and layout.width >= minimum and layout.width <= 22 and layout.height >= minimum and layout.height <= 7
		if _version_two(layout):
			var size: Vector2i = EquipmentFootprints.minimum_room(kind)
			minimum_area = size.x * size.y
			dimensions_ok = layout.get("width") is int and layout.get("height") is int and layout.width >= 3 and layout.width <= 22 and layout.height >= 3 and layout.height <= 7 and EquipmentFootprints.fits_room(kind,layout.width,layout.height)
		# The same price function quotes an unfinished UI draft. Live commands
		# validate the complete layout first; an absent door does not hide cost.
		if dimensions_ok:
			cost += maxi(0,layout.width * layout.height - minimum_area) * 20
		if layout.get("furniture") is Array:
			for item in layout.furniture:
				if item is Dictionary and item.get("kind") is String and FURNITURE_COSTS.has(item.kind):
					cost += FURNITURE_COSTS[item.kind]
	if upgraded and kind == "recovery":
		cost += catalog.rooms.recovery.upgrade_cost
	return cost

static func _definition(kind: String, layout: Dictionary) -> Dictionary:
	var width: int = layout.width
	var height: int = layout.height
	var door := _door(layout)
	var outside: Array = door[1]
	var result := {"width":width,"height":height,"cells":[],"wall_edges":[],"door_cell":door[0],"door_outside_cell":outside,"furniture_cells":[]}
	if layout.has("doors") or layout.has("windows"):
		result.doorways = []
		result.window_edges = []
		for spec in RoomOpenings.door_specs(layout):
			var edge := RoomOpenings.local_edge(layout,spec)
			result.doorways.append({"door_cell":edge[0],"door_outside_cell":edge[1]})
		for spec in RoomOpenings.window_specs(layout):
			result.window_edges.append(RoomOpenings.local_edge(layout,spec))
	for y in range(height):
		for x in range(width):
			result.cells.append([x,y])
	for x in range(width):
		_add_wall(result,[[x,0],[x,-1]])
		_add_wall(result,[[x,height-1],[x,height]])
	for y in range(height):
		_add_wall(result,[[0,y],[-1,y]])
		_add_wall(result,[[width-1,y],[width,y]])
	var station: Dictionary = EquipmentFootprints.station(kind) if _version_two(layout) else RoomTemplates.definition(kind,0)
	var station_keys: Array = STATION_KEYS.duplicate()
	if _version_two(layout): station_keys.append("clearance_cells")
	var min_x := 100
	var min_y := 100
	var max_x := 0
	var max_y := 0
	for key in station_keys:
		for point in station[key]:
			min_x = mini(min_x,point[0])
			min_y = mini(min_y,point[1])
			max_x = maxi(max_x,point[0])
			max_y = maxi(max_y,point[1])
	var station_width := max_x-min_x+1
	var station_height := max_y-min_y+1
	for key in station_keys:
		result[key] = []
		for point in station[key]:
			var rotated := _rotate([point[0]-min_x,point[1]-min_y],station_width,station_height,layout.equipment.rotation)
			result[key].append([rotated[0]+layout.equipment.x,rotated[1]+layout.equipment.y])
	for item in layout.furniture:
		if _version_two(layout): result.furniture_cells.append_array(EquipmentFootprints.furniture_cells(item))
		else: result.furniture_cells.append([item.x,item.y])
	return result

static func _version_two(layout: Dictionary) -> bool:
	return layout.get("footprint_version") is int and layout.footprint_version == 2

static func _keys(value: Dictionary, keys: Array) -> bool:
	if value.size() != keys.size():
		return false
	for key in keys:
		if not value.has(key):
			return false
	return true

static func _placement(value: Dictionary, width: int, height: int) -> bool:
	for key in ["x","y","rotation"]:
		if not value.get(key) is int:
			return false
	return value.x >= 0 and value.x < width and value.y >= 0 and value.y < height and value.rotation >= 0 and value.rotation <= 3

static func _door(layout: Dictionary) -> Array:
	return RoomOpenings.local_edge(layout,layout.door)

static func _inner_door(geometry: Dictionary) -> Array:
	return [geometry.door_cell[0]*2-geometry.door_outside_cell[0],geometry.door_cell[1]*2-geometry.door_outside_cell[1]]

static func _add_wall(result: Dictionary, edge: Array) -> void:
	for doorway in result.get("doorways",[{"door_cell":result.door_cell,"door_outside_cell":result.door_outside_cell}]):
		if edge == [doorway.door_cell,doorway.door_outside_cell]: return
	result.wall_edges.append(edge)

static func _rotate(point: Array, width: int, height: int, rotation: int) -> Array:
	var result := point.duplicate()
	for turn in range(rotation):
		result = [height-1-result[1],result[0]]
		var previous_width := width
		width = height
		height = previous_width
	return result

static func _inside(point: Array, width: int, height: int) -> bool:
	return point[0] >= 0 and point[0] < width and point[1] >= 0 and point[1] < height

static func _cell(point: Array, width: int) -> int:
	return point[1]*width+point[0]

static func _flood(width: int, height: int, start: Array, blocked: Dictionary) -> Dictionary:
	var first := _cell(start,width)
	var found := {first:true}
	var queue: Array = [start]
	var head := 0
	while head < queue.size():
		var point: Array = queue[head]
		head += 1
		for next in [[point[0],point[1]-1],[point[0]+1,point[1]],[point[0],point[1]+1],[point[0]-1,point[1]]]:
			var cell := _cell(next,width)
			if _inside(next,width,height) and not blocked.has(cell) and not found.has(cell):
				found[cell] = true
				queue.append(next)
	return found
