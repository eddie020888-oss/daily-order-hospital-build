extends SceneTree

var failures := 0
var checks := 0
var free_layout: GDScript
var sequence := 0
var catalog: ContentCatalog

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		print("FREE CORE FAIL: " + label)

func _run() -> void:
	check(FileAccess.file_exists("res://sim/free_room_layout.gd"), "free room geometry module exists")
	if not FileAccess.file_exists("res://sim/free_room_layout.gd"):
		_finish()
		return
	free_layout = load("res://sim/free_room_layout.gd")
	catalog = ContentCatalog.load_checked("res://content").catalog
	_test_rectangles_doors_and_station_rotation()
	_test_strict_types_collisions_and_routes()
	_test_cost_and_command_transactions()
	_test_recovery_upgrade_and_legacy_budget()
	_test_new_furniture_invalidates_cached_actor_route()
	_finish()

func _finish() -> void:
	print("FREE CORE RESULT: checks=%d failed=%d" % [checks, failures])
	quit(1 if failures else 0)

func _layout(width: int = 5, height: int = 4) -> Dictionary:
	return {"width":width,"height":height,"door":{"side":"south","offset":0},"equipment":{"x":1,"y":0,"rotation":0},"furniture":[]}

func _item(kind: String, x: int, y: int) -> Dictionary:
	return {"kind":kind,"x":x,"y":y,"rotation":0}

func _state() -> ClinicState:
	var state := ClinicState.create("level_01", catalog)
	state.data.unlocked_room_kinds = ["reception","diagnosis","echo","motion","sensory","recovery"]
	return state

func _send(state: ClinicState, type: String, payload: Dictionary, id: String = "") -> Dictionary:
	sequence += 1
	return CommandBus.apply(state, catalog, {"id":id if id != "" else "free_core_%d" % sequence,"type":type,"payload":payload})

func _reject_atomic(state: ClinicState, type: String, payload: Dictionary, label: String) -> void:
	var before := state.to_data()
	var result := _send(state,type,payload)
	check(not result.ok, label + " rejected")
	check(state.to_data() == before, label + " leaves cash IDs receipts geometry unchanged")

func _test_rectangles_doors_and_station_rotation() -> void:
	# A wrong perimeter opening, station rotation or ignored rectangle breaks real paths.
	for bounds in [[5,4],[4,6],[7,4]]:
		var layout := _layout(bounds[0],bounds[1])
		var definition: Dictionary = free_layout.definition("diagnosis",layout)
		check(free_layout.validate("diagnosis",layout) == "", "rectangular dimensions accepted")
		check(definition.cells.size() == bounds[0]*bounds[1], "rectangle contains every floor cell")
		check(definition.width == bounds[0] and definition.height == bounds[1], "rectangle dimensions exposed")
		check(definition.wall_edges.size() == 2*(bounds[0]+bounds[1])-1, "only door edge absent")
	for fixture in [
		["north",0,[0,0],[0,-1]], ["east",3,[4,3],[5,3]],
		["south",4,[4,4],[4,5]], ["west",4,[0,4],[-1,4]]
	]:
		var layout := _layout(5,5)
		layout.door = {"side":fixture[0],"offset":fixture[1]}
		layout.equipment = {"x":1,"y":1,"rotation":0}
		check(free_layout.validate("diagnosis",layout) == "", "each door side validates " + fixture[0])
		var definition: Dictionary = free_layout.definition("diagnosis",layout)
		check(definition.door_cell == fixture[2] and definition.door_outside_cell == fixture[3], "door follows chosen edge " + fixture[0])
		var state := _state()
		var preview := GridService.preview(state,{"kind":"diagnosis","origin_cell":54,"rotation":0,"layout":layout})
		check(preview.ok, "world accepts side " + fixture[0])
		if preview.ok:
			state.data.rooms.r = preview.data.room
			for cell in preview.data.room.service_cells + preview.data.room.staff_cells:
				check(not GridService.path(state,217,cell).is_empty(), "actual route reaches rotated room operator")
	var rotated := _layout(5,5)
	rotated.equipment = {"x":1,"y":1,"rotation":1}
	var geometry: Dictionary = free_layout.definition("diagnosis",rotated)
	check(geometry.equipment_cells == [[2,1],[2,2]], "clockwise equipment uses rectangular workstation footprint")
	check(geometry.service_cells == [[1,1]] and geometry.staff_cells == [[1,2]], "operation positions rotate together")
	var small := {"width":4,"height":4,"door":{"side":"south","offset":3},"equipment":{"x":0,"y":0,"rotation":1},"furniture":[]}
	var reception: Dictionary = free_layout.definition("reception",small)
	check(not reception.is_empty(),"rotated reception workstation leaves doorway clear")
	if reception.is_empty(): return
	check(reception.equipment_cells == [[1,0],[1,2]], "three by two workstation rotation retains far equipment")
	check(reception.staff_cells == [[0,2]], "three by two workstation staff rotates correctly")

func _test_strict_types_collisions_and_routes() -> void:
	# Truncating values, ignoring furniture or checking endpoints alone makes these pass illegally.
	for field in ["width","height"]:
		var layout := _layout()
		layout[field] = 4.0
		check(free_layout.validate("diagnosis",layout) != "", "strict dimension int " + field)
	for field in ["x","y","rotation"]:
		var layout := _layout()
		layout.equipment[field] = 1.0
		check(free_layout.validate("diagnosis",layout) != "", "strict equipment int " + field)
	for bad in [null, [], "layout", 3, {"width":5}, {"width":5,"height":4,"door":[],"equipment":{},"furniture":[]}]:
		check(free_layout.validate("diagnosis",bad) != "", "malformed layout rejected without crash")
	for change in [
		{"door":{"side":"ceiling","offset":0}}, {"door":{"side":"east","offset":4}},
		{"door":{"side":"south","offset":0.0}}, {"width":23}, {"height":8},
		{"equipment":{"x":4,"y":3,"rotation":0}}, {"equipment":{"x":1,"y":0,"rotation":4}},
		{"furniture":[{"kind":"plant","x":4,"y":3,"rotation":0.0}]},
		{"furniture":[{"kind":"unknown","x":4,"y":3,"rotation":0}]},
		{"furniture":[{"kind":"plant","x":4,"y":3}]}, {"extra":1.0}
	]:
		var layout := _layout()
		layout.merge(change,true)
		check(free_layout.validate("diagnosis",layout) != "", "invalid layout value rejected " + str(change))
	var layout := _layout()
	layout.furniture = [_item("plant",1,1)]
	check(free_layout.validate("diagnosis",layout) != "", "furniture cannot occupy service")
	layout.furniture = [_item("plant",2,1)]
	check(free_layout.validate("diagnosis",layout) != "", "furniture cannot occupy staff")
	layout.furniture = [_item("plant",1,0)]
	check(free_layout.validate("diagnosis",layout) != "", "furniture cannot occupy equipment")
	layout.furniture = [_item("plant",4,3),_item("bench",4,3)]
	check(free_layout.validate("diagnosis",layout) != "", "furniture footprints cannot duplicate")
	layout.furniture = [_item("plant",0,3)]
	check(free_layout.validate("diagnosis",layout) != "", "door floor remains clear")
	layout.furniture = [_item("plant",0,2)]
	check(free_layout.validate("diagnosis",layout) != "", "one inner doorway cell remains clear")
	layout = _layout(4,4)
	layout.door = {"side":"west","offset":3}
	layout.furniture = [_item("plant",0,1),_item("bench",1,2),_item("cabinet",3,1),_item("bin",2,2)]
	check(free_layout.validate("diagnosis",layout) != "", "all operations must connect through actual interior floor")
	var state := _state()
	layout = _layout()
	layout.furniture = [_item("plant",4,3)]
	var preview := GridService.preview(state,{"kind":"diagnosis","origin_cell":49,"rotation":0,"layout":layout})
	check(preview.ok,"valid furniture layout accepted")
	if preview.ok:
		state.data.rooms.r = preview.data.room
		check(preview.data.room.furniture_cells == [125],"furniture geometry uses world origin")
		check(GridService.path(state,217,125).is_empty(),"furniture blocks real navigation")
	_reject_atomic(state,"build_room",{"kind":"echo","origin_cell":61,"rotation":1,"layout":_layout()},"free room exterior rotation")
	_reject_atomic(state,"build_room",{"kind":"echo","origin_cell":61,"rotation":0,"layout":{"width":4.5}},"fractional malformed layout")

func _test_cost_and_command_transactions() -> void:
	var layout := _layout(5,5)
	layout.furniture = [_item("plant",4,0),_item("bench",4,1),_item("cabinet",4,2),_item("bin",4,3)]
	check(free_layout.base_cost("echo",layout,catalog) == 1440,"extra floor plus all four furniture prices")
	check(free_layout.base_cost("echo",{},catalog) == 1000,"legacy empty layout retains exact original cost")
	check(free_layout.base_cost("echo",{"width":5,"height":4,"furniture":[]},catalog) == 1080,"incomplete draft can quote safe floor area before door and equipment")
	var state := _state()
	layout = _layout()
	layout.furniture = [_item("plant",4,3)]
	var payload := {"kind":"diagnosis","origin_cell":49,"rotation":0,"layout":layout}
	var built := _send(state,"build_room",payload,"free_duplicate")
	check(built.ok,"free room build commits")
	if not built.ok: return
	check(state.data.cash == 7070 and state.data.rooms.room_001.invested_cost == 930,"new floor and furniture charged atomically")
	var after := state.to_data()
	check(_send(state,"build_room",payload,"free_duplicate") == built,"double submit returns original receipt")
	check(state.to_data() == after,"double submit never charges again")
	_reject_atomic(state,"move_room",{"room_id":"room_001","origin_cell":61,"rotation":0,"layout":_layout(6,4)},"editing open room")
	_send(state,"close_room",{"room_id":"room_001"})
	var moved := _send(state,"move_room",{"room_id":"room_001","origin_cell":61,"rotation":0})
	check(moved.ok and state.data.rooms.room_001.layout == layout,"whole room move retains layout")
	check(state.data.cash == 7070,"whole room move is free")
	state.data.queues.room_001 = ["waiting"]
	_reject_atomic(state,"move_room",{"room_id":"room_001","origin_cell":61,"rotation":0,"layout":_layout(6,4)},"editing queued room")
	state.data.queues.room_001.clear()
	var larger := _layout(6,4)
	larger.furniture = [_item("plant",4,3)]
	check(_send(state,"move_room",{"room_id":"room_001","origin_cell":61,"rotation":0,"layout":larger}).ok,"closed empty room expands")
	check(state.data.cash == 6990 and state.data.rooms.room_001.invested_cost == 1010,"expansion charges only eighty difference")
	check(state.data.ledger_entries[-1].category == "capital_build","edit expense reuses capital build ledger")
	check(_send(state,"move_room",{"room_id":"room_001","origin_cell":61,"rotation":0,"layout":layout}).ok,"closed empty room contracts")
	check(state.data.cash == 7050 and state.data.rooms.room_001.invested_cost == 930,"contraction refunds only seventy five percent of difference")
	check(state.data.ledger_entries[-1].category == "capital_refund","edit reduction reuses refund ledger")
	state.data.cash = 79
	_reject_atomic(state,"move_room",{"room_id":"room_001","origin_cell":61,"rotation":0,"layout":larger},"unaffordable expansion")
	var poor := _state()
	poor.data.cash = 929
	_reject_atomic(poor,"build_room",payload,"full free room cost checked before commit")
	var debt := _state()
	_send(debt,"build_room",payload)
	_send(debt,"close_room",{"room_id":"room_001"})
	debt.data.cash = -1000
	check(_send(debt,"move_room",{"room_id":"room_001","origin_cell":61,"rotation":0,"layout":layout}).ok,"zero cost layout edit remains available with operating debt")
	var smaller := _layout(4,4)
	check(_send(debt,"move_room",{"room_id":"room_001","origin_cell":61,"rotation":0,"layout":smaller}).ok,"layout reduction can refund while cash is negative")
	check(debt.data.cash == -903,"debt layout reduction returns seventy five percent of floor and furniture difference")

func _test_recovery_upgrade_and_legacy_budget() -> void:
	var state := _state()
	var layout := {"width":4,"height":4,"door":{"side":"south","offset":1},"equipment":{"x":0,"y":0,"rotation":0},"furniture":[_item("plant",2,0)]}
	check(_send(state,"build_room",{"kind":"recovery","origin_cell":49,"rotation":0,"layout":layout}).ok,"base recovery can decorate future seat position")
	_reject_atomic(state,"upgrade_recovery",{"room_id":"room_001"},"upgrade colliding future equipment")
	_send(state,"close_room",{"room_id":"room_001"})
	layout.furniture.clear()
	check(_send(state,"move_room",{"room_id":"room_001","origin_cell":49,"rotation":0,"layout":layout}).ok,"decoration removed before upgrade")
	var cash_before: int = state.data.cash
	check(_send(state,"upgrade_recovery",{"room_id":"room_001"}).ok,"valid recovery layout upgrade")
	check(state.data.cash == cash_before-400,"recovery charges existing upgrade price")
	check(state.data.rooms.room_001.layout == layout,"recovery upgrade preserves user layout")
	check(state.data.rooms.room_001.equipment_cells == [49,51] and state.data.rooms.room_001.service_cells == [73,75],"recovery upgrade uses shifted workstation positions")
	check(state.data.slots.size() == 2,"free recovery upgrade creates real second service slot")
	check(free_layout.base_cost("recovery",layout,catalog,true) == 1140,"upgraded free room canonical cost includes original upgrade")
	var legacy := _state()
	for pair in [["reception",121],["diagnosis",100],["echo",104],["motion",108],["sensory",112],["recovery",140]]:
		check(_send(legacy,"build_room",{"kind":pair[0],"origin_cell":pair[1],"rotation":0}).ok,"legacy build " + pair[0])
	for role in ["receptionist","doctor","technician","technician","technician"]:
		check(_send(legacy,"hire_staff",{"role":role}).ok,"legacy staff hire")
	check(legacy.data.cash == 1600,"legacy exact all room and five hire budget preserved")

func _test_new_furniture_invalidates_cached_actor_route() -> void:
	# Omitting furniture from cached-route validation lets a map revision bless
	# an old path through a new obstacle, even though fresh BFS avoids the cell.
	var state := _state()
	check(_send(state,"hire_staff",{"role":"doctor"}).ok,"cache regression uses a real hired staff member")
	var actor: Dictionary = state.data.staff.staff_001
	actor.merge({"cell":50,"phase":"moving","goal_cell":217,"route_goal_cell":217,
		"path":[50,74,98,122,146,170,194,218,217],"path_index":0,
		"route_revision":0,"move_progress":0,"walked_cells":0},true)
	check(SnapshotValidator.validate(state.data,catalog) == "","cached route is valid before new furniture exists")
	var layout := {"width":5,"height":7,"door":{"side":"south","offset":1},
		"equipment":{"x":3,"y":0,"rotation":0},"furniture":[_item("plant",1,3)]}
	var built := _send(state,"build_room",{"kind":"diagnosis","origin_cell":25,"rotation":0,"layout":layout})
	check(built.ok,"new room may block a future cached cell while current actor stays connected")
	if not built.ok: return
	actor = state.data.staff.staff_001
	check(state.data.rooms.room_001.furniture_cells == [98],"new plant occupies literal old route cell98")
	check(not PatientFlow._route_usable(state,actor),"new furniture invalidates an existing cached route")
	PatientFlow.move_actors(state,catalog)
	actor = state.data.staff.staff_001
	check(not actor.path.is_empty() and 98 not in actor.path,"first movement replans future path around new furniture")
	check(actor.route_revision == state.data.map_revision,"replanned route belongs to current map revision")
	check(SnapshotValidator.validate(state.data,catalog) == "","replanned actor remains valid for save immediately after movement")
	var avoided_furniture: bool = actor.cell != 98
	for tick in range(40):
		PatientFlow.move_actors(state,catalog)
		avoided_furniture = avoided_furniture and state.data.staff.staff_001.cell != 98
	check(avoided_furniture,"actor never steps onto new furniture while following replacement route")
	check(state.data.staff.staff_001.cell == 217,"replacement route reaches the original destination")
	check(SnapshotValidator.validate(state.data,catalog) == "","completed detour preserves a valid save model")
