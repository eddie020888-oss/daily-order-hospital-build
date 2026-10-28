class_name GridService
extends RefCounted

const WIDTH := 24
const HEIGHT := 18
const EXIT_CELL := 216

# Returns candidate geometry only. The caller commits data.room after its own
# transaction checks; an optional room_id replaces that room for move/upgrade.
static func preview(state: ClinicState, proposal: Dictionary) -> Dictionary:
	if not proposal.get("kind") is String:
		return _reject("unknown_kind")
	var kind: String = proposal.kind
	if RoomTemplates.definition(kind, 0).is_empty():
		return _reject("unknown_kind")
	if not proposal.get("rotation") is int or proposal.rotation < 0 or proposal.rotation > 3:
		return _reject("invalid_rotation")
	if not proposal.get("origin_cell") is int or proposal.origin_cell < 0 or proposal.origin_cell >= WIDTH * HEIGHT:
		return _reject("invalid_origin")
	if not proposal.get("upgraded", false) is bool or (proposal.get("upgraded", false) and kind != "recovery"):
		return _reject("invalid_upgrade")
	if proposal.has("layout"):
		if proposal.rotation != 0:
			return _reject("invalid_rotation")
		var layout_error := FreeRoomLayout.validate(kind,proposal.layout,proposal.get("upgraded",false))
		if layout_error != "":
			return _reject(layout_error)
	var replacement: Variant = proposal.get("room_id", "")
	if not replacement is String or (replacement != "" and not state.data.rooms.has(replacement)):
		return _reject("unknown_room")
	var definition := RoomTemplates.definition(kind, proposal.rotation)
	if proposal.has("layout"):
		definition = FreeRoomLayout.definition(kind,proposal.layout,proposal.get("upgraded",false))
	var origin_x: int = proposal.origin_cell % WIDTH
	var origin_y: int = proposal.origin_cell / WIDTH
	for local in definition.cells:
		var x: int = origin_x + local[0]
		var y: int = origin_y + local[1]
		if x <= 0 or x >= WIDTH - 1 or y <= 0 or y >= HEIGHT - 1:
			return _reject("boundary", {"cell":y * WIDTH + x})
		if y in [8,9]:
			return _reject("main_corridor", {"cell":y * WIDTH + x})
	var room := _room_geometry(proposal)
	var rooms: Dictionary = state.data.rooms.duplicate(true)
	rooms.erase(replacement)
	for id in rooms:
		var occupied := _room_geometry(rooms[id])
		for cell in room.cells:
			if cell in occupied.cells:
				return _reject("room_overlap", {"cell":cell, "room_id":id})
	var candidate_id: String = replacement if replacement != "" else "__candidate__"
	# Candidate IDs are private map keys; never collide with a caller's stable ID.
	while rooms.has(candidate_id):
		candidate_id += "_"
	rooms[candidate_id] = room
	var navigation := _navigation(rooms)
	var reachable := _flood(navigation, EXIT_CELL)
	for id in rooms:
		var geometry := _room_geometry(rooms[id])
		var doorways: Array = geometry.get("doorways",[{"door_cell":geometry.door_cell,"door_outside_cell":geometry.door_outside_cell}])
		var required: Array = geometry.service_cells + geometry.staff_cells
		for doorway in doorways:
			required.append(doorway.door_outside_cell)
			required.append(doorway.door_cell)
			# Another room's solid shared wall can block this entrance even if
			# both endpoints are reachable by a different door. Test the edge.
			if not _can_step(navigation,doorway.door_cell,doorway.door_outside_cell):
				return _reject("room_unreachable", {"cell":doorway.door_outside_cell,"room_id":replacement if id == candidate_id else id})
		for cell in required:
			if not reachable.has(cell):
				return _reject("room_unreachable", {"cell":cell, "room_id":replacement if id == candidate_id else id})
	for collection in ["patients", "staff"]:
		for id in state.data[collection]:
			var actor: Dictionary = state.data[collection][id]
			if not actor.has("cell"):
				continue
			var current: int = actor.cell
			if not reachable.has(current):
				return _reject("actor_blocked", {"cell":current, "actor_id":id})
			if actor.get("move_progress", 0) > 0:
				var route: Array = actor.get("path", [])
				var index: int = actor.get("path_index", 0)
				if index < 0 or index + 1 >= route.size() or route[index] != current:
					return _reject("invalid_actor_path", {"cell":current, "actor_id":id})
				var next: int = route[index + 1]
				if not reachable.has(next):
					return _reject("actor_blocked", {"cell":next, "actor_id":id})
				if not _can_step(navigation, current, next):
					return _reject("in_flight_edge_blocked", {"cell":current, "to_cell":next, "actor_id":id})
	return {"ok":true, "code":"ok", "data":{"room":room}}

# BFS always explores north/east/south/west and includes both endpoints.
static func path(state: ClinicState, from_cell: int, to_cell: int) -> Array:
	return path_avoiding(state,from_cell,to_cell,{})

# Walking can reserve occupied work positions without changing building
# previews, map reachability or the geometric legality of historical saves.
static func path_avoiding(state: ClinicState, from_cell: int, to_cell: int, blocked_cells: Dictionary) -> Array:
	var navigation := _navigation(state.data.rooms)
	for cell in blocked_cells: navigation.blocked[int(cell)]=true
	if not _walkable(navigation, from_cell) or not _walkable(navigation, to_cell):
		return []
	var parents := _flood(navigation, from_cell, to_cell)
	if not parents.has(to_cell):
		return []
	var result: Array = [to_cell]
	while result[-1] != from_cell:
		result.append(parents[result[-1]])
	result.reverse()
	return result

static func _room_geometry(record: Dictionary) -> Dictionary:
	if record.get("ruleset","")=="full-hospital-v1" or record.get("kind","")=="campaign_department":
		var campaign_layout:Variant=load("res://campaign/facility_layout.gd")
		return campaign_layout.geometry(record)
	var template := RoomTemplates.definition(record.kind, record.rotation)
	var room := {"kind":record.kind, "origin_cell":record.origin_cell, "rotation":record.rotation, "upgraded":record.get("upgraded", false)}
	if record.has("layout"):
		template = FreeRoomLayout.definition(record.kind,record.layout,room.upgraded)
		room.layout = record.layout.duplicate(true)
		room.width = template.width
		room.height = template.height
		room.furniture_cells = []
		for local in template.furniture_cells:
			room.furniture_cells.append(_global_cell(record.origin_cell,local))
	for key in ["cells", "equipment_cells", "service_cells", "staff_cells"]:
		room[key] = []
		for local in template[key]:
			room[key].append(_global_cell(record.origin_cell, local))
	if room.upgraded:
		for local in template.upgrade_equipment_cells:
			room.equipment_cells.append(_global_cell(record.origin_cell, local))
		for local in template.upgrade_service_cells:
			room.service_cells.append(_global_cell(record.origin_cell, local))
	room.door_cell = _global_cell(record.origin_cell, template.door_cell)
	room.door_outside_cell = _global_cell(record.origin_cell, template.door_outside_cell)
	if template.has("doorways"):
		room.doorways = []
		room.window_edges = []
		for doorway in template.doorways:
			room.doorways.append({"door_cell":_global_cell(record.origin_cell,doorway.door_cell),"door_outside_cell":_global_cell(record.origin_cell,doorway.door_outside_cell)})
		for edge in template.window_edges:
			var a := _global_cell(record.origin_cell,edge[0])
			var b := _global_cell(record.origin_cell,edge[1])
			room.window_edges.append([mini(a,b),maxi(a,b)])
	room.wall_edges = []
	for edge in template.wall_edges:
		var a := _global_cell(record.origin_cell, edge[0])
		var b := _global_cell(record.origin_cell, edge[1])
		room.wall_edges.append([mini(a,b), maxi(a,b)])
	return room

static func _global_cell(origin: int, local: Array) -> int:
	return origin + local[1] * WIDTH + local[0]

static func _navigation(rooms: Dictionary) -> Dictionary:
	var navigation := {"blocked":{}, "walls":{}}
	for record in rooms.values():
		var room := _room_geometry(record)
		for cell in room.equipment_cells:
			navigation.blocked[cell] = true
		for cell in room.get("furniture_cells",[]):
			navigation.blocked[cell] = true
		for edge in room.wall_edges:
			navigation.walls[_edge_key(edge[0], edge[1])] = true
	return navigation

static func _walkable(navigation: Dictionary, cell: int) -> bool:
	if cell < 0 or cell >= WIDTH * HEIGHT or navigation.blocked.has(cell):
		return false
	var x := cell % WIDTH
	var y: int = cell / WIDTH
	return cell == EXIT_CELL or (x > 0 and x < WIDTH - 1 and y > 0 and y < HEIGHT - 1)

static func _can_step(navigation: Dictionary, from_cell: int, to_cell: int) -> bool:
	var distance := absi(from_cell % WIDTH - to_cell % WIDTH) + absi(from_cell / WIDTH - to_cell / WIDTH)
	return distance == 1 and _walkable(navigation, to_cell) and not navigation.walls.has(_edge_key(from_cell, to_cell))

static func _edge_key(a: int, b: int) -> int:
	return mini(a,b) * WIDTH * HEIGHT + maxi(a,b)

static func _flood(navigation: Dictionary, start: int, target: int = -1) -> Dictionary:
	if not _walkable(navigation, start):
		return {}
	var parents := {start:start}
	var queue: Array = [start]
	var head := 0
	while head < queue.size():
		var cell: int = queue[head]
		head += 1
		if cell == target:
			break
		for neighbor in [cell-WIDTH, cell+1, cell+WIDTH, cell-1]:
			if not parents.has(neighbor) and _can_step(navigation, cell, neighbor):
				parents[neighbor] = cell
				queue.append(neighbor)
	return parents

static func _reject(code: String, data: Dictionary = {}) -> Dictionary:
	return {"ok":false, "code":code, "data":data}
