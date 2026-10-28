class_name RoomOpenings
extends RefCounted

# Optional arrays extend an old single-door layout without rewriting it.
# Their order is stable: door remains the compatibility alias for doors[0].
static func door_specs(layout: Dictionary) -> Array:
	if layout.has("doors"):
		return layout.doors.duplicate(true) if layout.doors is Array else []
	return [layout.door.duplicate(true)] if layout.get("door") is Dictionary else []

static func window_specs(layout: Dictionary) -> Array:
	return layout.windows.duplicate(true) if layout.get("windows") is Array else []

static func local_edge(layout: Dictionary, spec: Dictionary) -> Array:
	if not _dimensions(layout) or not _spec(spec,layout.width,layout.height):
		return []
	var offset: int = spec.offset
	match spec.side:
		"north": return [[offset,0],[offset,-1]]
		"east": return [[layout.width-1,offset],[layout.width,offset]]
		"south": return [[offset,layout.height-1],[offset,layout.height]]
	return [[0,offset],[-1,offset]]

static func global_edge(origin: int, layout: Dictionary, spec: Dictionary) -> Array:
	var edge := local_edge(layout,spec)
	if edge.is_empty(): return []
	return [origin+edge[0][1]*GridService.WIDTH+edge[0][0],origin+edge[1][1]*GridService.WIDTH+edge[1][0]]

static func validate_shape(layout: Dictionary) -> String:
	if not _dimensions(layout) or not _spec(layout.get("door"),layout.width,layout.height):
		return "invalid_door"
	if layout.has("doors"):
		if not layout.doors is Array or layout.doors.is_empty() or layout.doors.size()>2*(layout.width+layout.height):
			return "invalid_doors"
		if layout.doors[0]!=layout.door:
			return "invalid_primary_door"
	var occupied := {}
	for spec in door_specs(layout):
		if not _spec(spec,layout.width,layout.height): return "invalid_door"
		var key: String = spec.side+":"+str(spec.offset)
		if occupied.has(key): return "duplicate_door"
		occupied[key] = true
	if layout.has("windows"):
		if not layout.windows is Array or layout.windows.size()>2*(layout.width+layout.height):
			return "invalid_windows"
	var windows := {}
	for spec in window_specs(layout):
		if not _spec(spec,layout.width,layout.height): return "invalid_window"
		var key: String = spec.side+":"+str(spec.offset)
		if occupied.has(key): return "opening_overlap"
		if windows.has(key): return "duplicate_window"
		windows[key] = true
	return ""

static func _dimensions(layout: Dictionary) -> bool:
	return layout.get("width") is int and layout.get("height") is int and layout.width>0 and layout.height>0

static func _spec(value: Variant, width: int, height: int) -> bool:
	if not value is Dictionary or value.size()!=2 or not value.get("side") is String or not value.get("offset") is int:
		return false
	if value.side not in ["north","east","south","west"]:
		return false
	var limit: int = width if value.side in ["north","south"] else height
	return value.offset>=0 and value.offset<limit
