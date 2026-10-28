extends RefCounted

var grid: GDScript
var templates: GDScript

func run(t: TestContext) -> void:
	# Missing modules are an assertion failure, rather than a parser crash.
	var present := FileAccess.file_exists("res://sim/grid_service.gd") and FileAccess.file_exists("res://sim/room_templates.gd")
	t.expect_true(present, "Map geometry and route services exist")
	if not present:
		return
	grid = load("res://sim/grid_service.gd")
	templates = load("res://sim/room_templates.gd")
	test_six_room_layout_and_recovery_upgrade_reachable(t)
	test_rotated_templates_keep_door_and_slots_connected(t)
	test_build_never_seals_actor_or_in_flight_edge(t)
	test_preview_is_atomic_on_overlap_or_main_corridor(t)
	test_paths_follow_edges_equipment_and_fixed_neighbor_order(t)
	test_build_keeps_existing_room_accessible(t)
	test_replacing_room_removes_its_old_geometry(t)

func _state() -> ClinicState:
	return ClinicState.create("level_01", ContentCatalog.load_checked("res://content").catalog)

func _add(t: TestContext, state: ClinicState, proposal: Dictionary, id: String) -> bool:
	var result: Dictionary = grid.preview(state, proposal)
	t.expect_true(result.ok, "valid room " + id + ": " + result.code)
	if not result.ok:
		return false
	state.data.rooms[id] = result.data.room
	return true

func test_six_room_layout_and_recovery_upgrade_reachable(t: TestContext) -> void:
	# Catches blocked doors/slots, blocked floor perimeter, and omitted upgrade geometry.
	var state := _state()
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/layouts.json"))
	for proposal in fixture.standard:
		# JSON numbers arrive as floats; the production state contract uses integers.
		proposal.origin_cell = int(proposal.origin_cell)
		proposal.rotation = int(proposal.rotation)
		if not _add(t, state, proposal, proposal.kind):
			return
	for id in state.data.rooms:
		var room: Dictionary = state.data.rooms[id]
		for cell in room.service_cells + room.staff_cells + [room.door_outside_cell]:
			t.expect_true(grid.path(state, 217, cell).size() > 0, id + " slot reachable: " + str(cell))
	t.expect_equal(state.data.rooms.recovery.service_cells, [164], "base recovery has first seat only")
	var before := state.to_data()
	var upgraded: Dictionary = grid.preview(state, {"room_id":"recovery", "kind":"recovery", "origin_cell":140, "rotation":0, "upgraded":true})
	t.expect_true(upgraded.ok, "second recovery seat upgrade validates")
	t.expect_equal(state.to_data(), before, "upgrade preview remains read only")
	if not upgraded.ok:
		return
	state.data.rooms.recovery = upgraded.data.room
	t.expect_equal(upgraded.data.room.service_cells, [164, 166], "upgrade activates literal second seat")
	t.expect_equal(upgraded.data.room.equipment_cells, [140, 142], "upgrade adds second seat equipment")
	t.expect_true(grid.path(state, 217, 166).size() > 0, "second recovery seat reachable")

func test_rotated_templates_keep_door_and_slots_connected(t: TestContext) -> void:
	# Catches wrong clockwise rotation of doors/outside cells and disconnected service geometry.
	var door3 := [[1,2], [0,1], [1,0], [2,1]]
	var outside3 := [[1,3], [-1,1], [1,-1], [3,1]]
	var door4 := [[1,3], [0,1], [2,0], [3,2]]
	var outside4 := [[1,4], [-1,1], [2,-1], [4,2]]
	var service3 := [[0,1], [1,0], [2,1], [1,2]]
	var staff3 := [[2,1], [1,2], [0,1], [1,0]]
	var service4 := [[1,1], [2,1], [2,2], [1,2]]
	var staff4 := [[2,1], [2,2], [1,2], [1,1]]
	for kind in ["reception", "diagnosis", "echo", "motion", "sensory", "recovery"]:
		for rotation in range(4):
			var definition: Dictionary = templates.definition(kind, rotation)
			var small: bool = kind in ["reception", "recovery"]
			t.expect_equal(definition.door_cell, door3[rotation] if small else door4[rotation], kind + " rotated door")
			t.expect_equal(definition.door_outside_cell, outside3[rotation] if small else outside4[rotation], kind + " rotated door exterior")
			var expected_service: Array = service3[rotation] if small else service4[rotation]
			t.expect_equal(definition.service_cells, [expected_service], kind + " rotated service position")
			t.expect_equal(definition.staff_cells, [] if kind == "recovery" else [staff3[rotation] if small else staff4[rotation]], kind + " rotated staff position")
			if kind == "recovery":
				t.expect_equal(definition.upgrade_service_cells, [staff3[rotation]], "rotated second recovery seat")
			var state := _state()
			if not _add(t, state, {"kind":kind, "origin_cell":54, "rotation":rotation, "upgraded":kind == "recovery"}, "r"):
				continue
			var room: Dictionary = state.data.rooms.r
			for cell in room.service_cells + room.staff_cells + [room.door_cell, room.door_outside_cell]:
				t.expect_true(grid.path(state, 217, cell).size() > 0, kind + " rotation " + str(rotation) + " reachable slot")
	t.expect_equal(templates.definition("unknown", 0), {}, "unknown template rejected")
	t.expect_equal(templates.definition("reception", 4), {}, "invalid template rotation rejected")

func test_build_never_seals_actor_or_in_flight_edge(t: TestContext) -> void:
	# Catches checking only actor.cell, or checking connectivity without preserving the active edge.
	for collection in ["patients", "staff"]:
		for actor in [
			{"cell":101, "path":[], "path_index":0, "move_progress":0},
			{"cell":125, "path":[125,101], "path_index":0, "move_progress":1},
			{"cell":125, "path":[125,124], "path_index":0, "move_progress":3},
			{"cell":124, "path":[124,125], "path_index":0, "move_progress":2}
		]:
			var state := _state()
			state.data[collection].actor_1 = actor
			var before := state.to_data()
			var result: Dictionary = grid.preview(state, {"kind":"reception", "origin_cell":101, "rotation":0})
			t.expect_false(result.ok, collection + " current cell and moving edge protected")
			t.expect_equal(result.code, "in_flight_edge_blocked" if actor.path.size() > 0 and actor.path[1] in [124,125] else "actor_blocked", "stable actor rejection")
			t.expect_equal(result.data.actor_id, "actor_1", "actor rejection identifies actor")
			t.expect_equal(state.to_data(), before, "actor rejection atomic")
	# A future route can be recomputed; only an actively traversed edge is protected.
	var idle := _state()
	idle.data.patients.p = {"cell":125, "path":[125,124], "path_index":0, "move_progress":0}
	t.expect_true(grid.preview(idle, {"kind":"reception", "origin_cell":101, "rotation":0}).ok, "idle actor remains connected via door")

func test_preview_is_atomic_on_overlap_or_main_corridor(t: TestContext) -> void:
	# Catches mutating previews, overlap checks against equipment only, and corridor/boundary bypasses.
	var state := _state()
	if not _add(t, state, {"kind":"reception", "origin_cell":121, "rotation":0}, "original"):
		return
	for row in [
		[{"kind":"reception", "origin_cell":193, "rotation":0}, "main_corridor"],
		[{"kind":"recovery", "origin_cell":122, "rotation":0}, "room_overlap"],
		[{"kind":"reception", "origin_cell":24, "rotation":0}, "boundary"],
		[{"kind":"reception", "origin_cell":143, "rotation":0}, "boundary"],
		[{"kind":"unknown", "origin_cell":54, "rotation":0}, "unknown_kind"],
		[{"kind":"reception", "origin_cell":54, "rotation":-1}, "invalid_rotation"],
		[{"kind":"reception", "origin_cell":-1, "rotation":0}, "invalid_origin"],
		[{"kind":"reception", "origin_cell":54.5, "rotation":0}, "invalid_origin"],
		[{"kind":"reception", "origin_cell":54, "rotation":0, "upgraded":true}, "invalid_upgrade"],
		[{"room_id":"missing", "kind":"reception", "origin_cell":54, "rotation":0}, "unknown_room"]
	]:
		var before := state.to_data()
		var result: Dictionary = grid.preview(state, row[0])
		t.expect_false(result.ok, "reject " + row[1])
		t.expect_equal(result.code, row[1], "stable validation code")
		t.expect_equal(state.to_data(), before, "invalid preview is read only")
	var overlap: Dictionary = grid.preview(state, {"kind":"reception", "origin_cell":122, "rotation":0})
	t.expect_equal(overlap.data.room_id, "original", "overlap identifies room")
	t.expect_equal(overlap.data.cell, 122, "overlap identifies first occupied cell")
	var before := state.to_data()
	var valid: Dictionary = grid.preview(state, {"kind":"recovery", "origin_cell":54, "rotation":0})
	t.expect_true(valid.ok, "valid preview")
	valid.data.room.cells.clear()
	t.expect_equal(state.to_data(), before, "success and returned geometry cannot mutate state")

func test_paths_follow_edges_equipment_and_fixed_neighbor_order(t: TestContext) -> void:
	# Catches diagonal paths, whole-perimeter tile walls, wraparound and unstable tie breaking.
	var state := _state()
	t.expect_equal(grid.path(state, 217, 194), [217,193,194], "north wins equivalent routes")
	t.expect_equal(grid.path(state, 216, 217), [216,217], "entrance connects to indoor entry")
	t.expect_equal(grid.path(state, 217, 217), [217], "path includes identical start/end")
	for target in [-1, 0, 23, 431, 432]:
		t.expect_equal(grid.path(state, 217, target), [], "invalid or boundary target unreachable")
	if not _add(t, state, {"kind":"reception", "origin_cell":54, "rotation":0}, "r"):
		return
	t.expect_equal(grid.path(state, 217, 54), [], "equipment is impassable")
	t.expect_equal(grid.path(state, 54, 217), [], "equipment cannot be path origin")
	t.expect_equal(grid.path(state, 102, 126), [102,103,127,126], "south wall only opens at door")
	t.expect_equal(grid.path(state, 78, 102), [78,102], "perimeter floor is traversable inside room")
	t.expect_equal(grid.path(state, 126, 102), [126,127,103,102], "walls block travel in both directions")

func test_build_keeps_existing_room_accessible(t: TestContext) -> void:
	# Catches validating only candidate slots and forgetting existing doors and actors isolated inside.
	var state := _state()
	if not _add(t, state, {"kind":"reception", "origin_cell":53, "rotation":0}, "old"):
		return
	var before := state.to_data()
	var result: Dictionary = grid.preview(state, {"kind":"reception", "origin_cell":125, "rotation":0})
	t.expect_false(result.ok, "new perimeter cannot seal existing room door")
	t.expect_equal(result.code, "room_unreachable", "stable disconnected room code")
	t.expect_equal(result.data.room_id, "old", "disconnected room identified")
	t.expect_equal(state.to_data(), before, "disconnected candidate leaves state intact")


func test_replacing_room_removes_its_old_geometry(t: TestContext) -> void:
	# Catches including the old footprint/walls in a candidate move and stale cached paths.
	var state := _state()
	if not _add(t, state, {"kind":"reception", "origin_cell":54, "rotation":0}, "r"):
		return
	var before := state.to_data()
	var moved: Dictionary = grid.preview(state, {"room_id":"r", "kind":"reception", "origin_cell":60, "rotation":1})
	t.expect_true(moved.ok, "existing room can move and rotate")
	t.expect_equal(state.to_data(), before, "move preview atomic")
	if not moved.ok:
		return
	state.data.rooms.r = moved.data.room
	t.expect_true(grid.path(state, 217, 54).size() > 0, "old equipment becomes floor")
	t.expect_equal(grid.path(state, 217, 62), [], "new rotated equipment blocks movement")
	var in_place: Dictionary = grid.preview(state, {"room_id":"r", "kind":"reception", "origin_cell":60, "rotation":1})
	t.expect_true(in_place.ok, "replacement does not overlap itself")
