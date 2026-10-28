extends SceneTree

# This suite uses the real SaveStore JSON/validation path with an in-memory
# filesystem, so no save candidates or archives escape the task's output root.
class MemoryIO extends RefCounted:
	var files: Dictionary = {}
	func exists(path: String) -> bool: return files.has(path)
	func read(path: String) -> String: return files.get(path, "")
	func mkdir(_path: String) -> Error: return OK
	func write(path: String, content: String) -> Error:
		files[path] = content
		return OK
	func rename(source: String, destination: String) -> Error:
		if not files.has(source): return ERR_FILE_NOT_FOUND
		if files.has(destination): return ERR_ALREADY_EXISTS
		files[destination] = files[source]
		files.erase(source)
		return OK

const SAVE_ROOT := "E:/CODEX/2026-10-19/医院自由建造/temp/storage-memory"
var failures := 0
var passed := 0
var catalog: ContentCatalog
var layout_api: Variant

func _initialize() -> void: _run.call_deferred()

func check(value: bool, message: String) -> void:
	if value: passed += 1
	else: failures += 1
	print(("FREE STORAGE PASS: " if value else "FREE STORAGE FAIL: ") + message)

func _run() -> void:
	var content := ContentCatalog.load_checked("res://content")
	check(content.ok, "existing content loads")
	if not content.ok:
		quit(1)
		return
	catalog = content.catalog
	_test_legacy_snapshot_roundtrip()
	_test_layout_shape_rejected_before_geometry()
	_test_receipt_shape_and_deleted_history()
	if ResourceLoader.exists("res://sim/free_room_layout.gd"):
		layout_api = load("res://sim/free_room_layout.gd")
	check(layout_api != null, "free layout implementation is available")
	if layout_api != null:
		_test_real_build_roundtrip_and_price()
		_test_edit_price_history()
		_test_upgraded_free_room_history()
	print("FREE STORAGE RESULT: failed=%d passed=%d" % [failures, passed])
	quit(1 if failures > 0 else 0)

func _layout(width: int = 4, height: int = 4) -> Dictionary:
	return {"width":width, "height":height, "door":{"side":"south", "offset":1}, "equipment":{"x":0, "y":0, "rotation":0}, "furniture":[]}

func _sim() -> Simulation:
	return Simulation.new(catalog, ClinicState.create("level_01", catalog))

func _legacy_sim() -> Simulation:
	var sim := _sim()
	var result := sim.submit({"id":"legacy-build", "type":"build_room", "payload":{"kind":"reception", "origin_cell":25, "rotation":0}})
	check(result.ok, "legacy fixture builds with the unchanged fixed template")
	return sim

func _test_legacy_snapshot_roundtrip() -> void:
	var sim := _legacy_sim()
	var snapshot := sim.snapshot()
	var original_hash := JSON.stringify(snapshot, "", true, true).sha256_text()
	var io := MemoryIO.new()
	check(not snapshot.rooms.room_001.has("layout"), "legacy room remains without a layout key")
	check(SaveStore.save(snapshot, SAVE_ROOT, io).ok, "legacy snapshot still saves")
	var result := SaveStore.load(SAVE_ROOT, catalog, io)
	check(result.ok, "legacy snapshot still loads")
	if not result.ok: return
	check(result.state.to_data() == snapshot, "legacy snapshot fields remain byte-equivalent model data")
	check(JSON.stringify(result.state.to_data(), "", true, true).sha256_text() == original_hash, "legacy snapshot hash remains unchanged")
	check(not result.state.data.rooms.room_001.has("layout"), "load does not retrofit legacy rooms")

func _test_layout_shape_rejected_before_geometry() -> void:
	var original := _legacy_sim().snapshot()
	var bad_layouts: Array = ["invalid", [], {}, {"width":3, "height":3}]
	for mutation in ["width", "height", "door", "equipment", "furniture", "equipment_rotation", "furniture_kind", "furniture_overlap"]:
		var layout := _layout(3, 3)
		match mutation:
			"width": layout.width = 2
			"height": layout.height = 8
			"door": layout.door.side = "diagonal"
			"equipment": layout.equipment.x = -1
			"furniture": layout.furniture = {}
			"equipment_rotation": layout.equipment.rotation = 4
			"furniture_kind": layout.furniture = [{"kind":"unknown", "x":1, "y":1, "rotation":0}]
			"furniture_overlap": layout.furniture = [{"kind":"plant", "x":0, "y":0, "rotation":0}]
		bad_layouts.append(layout)
	for index in range(bad_layouts.size()):
		var invalid: Dictionary = original.duplicate(true)
		invalid.rooms.room_001.layout = bad_layouts[index]
		var before := invalid.duplicate(true)
		var result := ClinicState.from_data(invalid, catalog)
		check(not result.ok and result.state == null, "invalid room layout %d is rejected without partial state" % index)
		check(invalid == before, "validation leaves invalid room layout %d untouched" % index)
	var invalid := original.duplicate(true)
	invalid.rooms.room_001.layout = _layout(3, 3)
	invalid.rooms.room_001.rotation = 1
	check(not ClinicState.from_data(invalid, catalog).ok, "free room outer rotation must stay zero")
	invalid = original.duplicate(true)
	invalid.rooms.room_001.layout = _layout(3, 3)
	invalid.rooms.room_001.layout.width = 3.0
	check(not ClinicState.from_data(invalid, catalog).ok, "in-memory layout dimensions require actual integers")

func _test_receipt_shape_and_deleted_history() -> void:
	var sim := _legacy_sim()
	var original := sim.snapshot()
	for layout in ["invalid", [], {}, {"width":3, "height":3}]:
		var invalid: Dictionary = original.duplicate(true)
		invalid.command_receipts["legacy-build"].data.command.payload.layout = layout
		var result := ClinicState.from_data(invalid, catalog)
		check(not result.ok and result.state == null, "malformed historical build layout is rejected")
	check(sim.submit({"id":"close", "type":"close_room", "payload":{"room_id":"room_001"}}).ok, "legacy room closes before relocation")
	check(sim.submit({"id":"move", "type":"move_room", "payload":{"room_id":"room_001", "origin_cell":29, "rotation":0}}).ok, "legacy relocation creates a historical receipt")
	check(sim.submit({"id":"remove", "type":"remove_room", "payload":{"room_id":"room_001"}}).ok, "legacy room removal retains command history")
	var deleted := sim.snapshot()
	deleted.command_receipts.move.data.command.payload.layout = _layout(3, 3)
	check(ClinicState.from_data(deleted, catalog).ok, "well-shaped deleted-room move history does not require a current room kind")
	deleted.command_receipts.move.data.command.payload.layout.equipment.rotation = "0"
	check(not ClinicState.from_data(deleted, catalog).ok, "deleted-room move history still requires strict layout types")

func _test_real_build_roundtrip_and_price() -> void:
	var sim := _sim()
	var layout := _layout()
	layout.furniture = [{"kind":"plant", "x":3, "y":2, "rotation":0}]
	check(layout_api.validate("reception", layout) == "", "roundtrip fixture has valid equipment, door, and furniture")
	var command := {"id":"free-build", "type":"build_room", "payload":{"kind":"reception", "origin_cell":25, "rotation":0, "layout":layout}}
	var receipt := sim.submit(command)
	check(receipt.ok, "real free build succeeds")
	if not receipt.ok: return
	var snapshot := sim.snapshot()
	var room: Dictionary = snapshot.rooms[receipt.data.room_id]
	check(room.get("layout") == layout, "committed room stores the exact layout")
	check(room.invested_cost == catalog.rooms.reception.cost + 7 * 20 + 50, "floor and furniture prices are included in invested cost")
	var result := ClinicState.from_data(snapshot, catalog)
	check(result.ok, "real free build passes snapshot and capital ledger validation")
	var io := MemoryIO.new()
	check(SaveStore.save(snapshot, SAVE_ROOT, io).ok, "real free room saves through full candidate verification")
	var loaded := SaveStore.load(SAVE_ROOT, catalog, io)
	check(loaded.ok, "real free room loads")
	if loaded.ok:
		check(loaded.state.to_data() == snapshot, "layout, cached geometry, slots, funds, and receipts roundtrip exactly")
		var resumed := Simulation.new(catalog, loaded.state)
		check(resumed.submit(command) == receipt and resumed.snapshot() == snapshot, "redelivery after reload preserves the original build receipt and charge")
	_test_free_layout_corruption(snapshot)
	_test_json_layout_numbers(snapshot)

func _test_free_layout_corruption(snapshot: Dictionary) -> void:
	for field in ["cells", "equipment_cells", "service_cells", "staff_cells", "furniture_cells", "wall_edges", "door_cell", "door_outside_cell", "width", "height"]:
		var invalid := snapshot.duplicate(true)
		var room: Dictionary = invalid.rooms.room_001
		if room[field] is Array: room[field] = []
		else: room[field] += 1
		check(not ClinicState.from_data(invalid, catalog).ok, "forged free room geometry is rejected: " + field)
	var invalid := snapshot.duplicate(true)
	invalid.rooms.room_001.invested_cost -= 1
	check(not ClinicState.from_data(invalid, catalog).ok, "free room invested cost cannot omit one coin")
	invalid = snapshot.duplicate(true)
	invalid.rooms.room_001.layout.furniture[0].x = 0
	invalid.rooms.room_001.layout.furniture[0].y = 0
	check(not ClinicState.from_data(invalid, catalog).ok, "furniture cannot claim an equipment footprint in a save")
	invalid = snapshot.duplicate(true)
	invalid.command_receipts["free-build"].data.command.payload.layout.width = 2
	check(not ClinicState.from_data(invalid, catalog).ok, "historical build layout is validated independently of the current room")

func _test_json_layout_numbers(snapshot: Dictionary) -> void:
	var raw := JSON.stringify(snapshot)
	for token in ["4.1", "4.00000000000000001", "9007199254740992", "1e100"]:
		var io := MemoryIO.new()
		io.files[SAVE_ROOT.path_join("main.json")] = raw.replace('"width":4', '"width":' + token)
		var result := SaveStore.load(SAVE_ROOT, catalog, io)
		check(not result.ok and result.error.contains("invalid_json_integer"), "raw JSON layout number is checked losslessly: " + token)
	var io := MemoryIO.new()
	io.files[SAVE_ROOT.path_join("main.json")] = raw.replace('"width":4', '"width":4.0')
	var result := SaveStore.load(SAVE_ROOT, catalog, io)
	check(result.ok, "lossless integral JSON layout dimensions normalize to integers")
	if result.ok: check(result.state.to_data() == snapshot, "integral JSON layout notation restores the identical snapshot")

func _test_edit_price_history() -> void:
	var sim := _sim()
	var built := sim.submit({"id":"price-build", "type":"build_room", "payload":{"kind":"reception", "origin_cell":25, "rotation":0, "layout":_layout()}})
	check(built.ok, "price-history fixture builds")
	if not built.ok: return
	check(sim.submit({"id":"price-close", "type":"close_room", "payload":{"room_id":"room_001"}}).ok, "empty free room closes for editing")
	var expanded := sim.submit({"id":"price-expand", "type":"move_room", "payload":{"room_id":"room_001", "origin_cell":25, "rotation":0, "layout":_layout(5, 4)}})
	check(expanded.ok, "larger edited room commits its additional floor cost")
	if not expanded.ok: return
	check(ClinicState.from_data(sim.snapshot(), catalog).ok, "larger edit is validated against its preceding build price")
	var shrunk := sim.submit({"id":"price-shrink", "type":"move_room", "payload":{"room_id":"room_001", "origin_cell":25, "rotation":0, "layout":_layout(3, 3)}})
	check(shrunk.ok, "smaller edited room commits its partial refund")
	if not shrunk.ok: return
	var snapshot := sim.snapshot()
	check(ClinicState.from_data(snapshot, catalog).ok, "smaller edit is validated against its preceding expanded price")
	var found := false
	var invalid := snapshot.duplicate(true)
	for entry: Dictionary in invalid.ledger_entries:
		if entry.event_id != "command:price-shrink": continue
		found = true
		entry.delta += 1
		invalid.cash += 1
	check(found and not ClinicState.from_data(invalid, catalog).ok, "conserved cash cannot justify a forged edit refund")
	var moved := sim.submit({"id":"price-relocate", "type":"move_room", "payload":{"room_id":"room_001", "origin_cell":30, "rotation":0}})
	check(moved.ok, "whole-room relocation preserves the layout without a new price event")
	check(ClinicState.from_data(sim.snapshot(), catalog).ok, "unchanged-layout relocation keeps capital history valid")
	check(sim.submit({"id":"price-remove", "type":"remove_room", "payload":{"room_id":"room_001"}}).ok, "edited room removal commits its current-cost refund")
	snapshot = sim.snapshot()
	check(ClinicState.from_data(snapshot, catalog).ok, "removed room keeps enough history to validate all edit prices")
	var io := MemoryIO.new()
	check(SaveStore.save(snapshot, SAVE_ROOT, io).ok, "deleted edited-room history saves")
	var loaded := SaveStore.load(SAVE_ROOT, catalog, io)
	check(loaded.ok and loaded.state.to_data() == snapshot, "deleted edited-room history roundtrips exactly")
	invalid = snapshot.duplicate(true)
	invalid.command_receipts["price-remove"].data.refund += 1
	for entry: Dictionary in invalid.ledger_entries:
		if entry.event_id == "command:price-remove":
			entry.delta += 1
			invalid.cash += 1
	check(not ClinicState.from_data(invalid, catalog).ok, "matching forged receipt and ledger cannot increase a removal refund")

func _test_upgraded_free_room_history() -> void:
	var sim := _sim()
	var built := sim.submit({"id":"recovery-build", "type":"build_room", "payload":{"kind":"recovery", "origin_cell":25, "rotation":0, "layout":_layout()}})
	check(built.ok, "free recovery room builds")
	if not built.ok: return
	var upgraded := sim.submit({"id":"recovery-upgrade", "type":"upgrade_recovery", "payload":{"room_id":"room_001"}})
	check(upgraded.ok, "free recovery room adds its second equipment and service position")
	if not upgraded.ok: return
	check(ClinicState.from_data(sim.snapshot(), catalog).ok, "free recovery upgrade cost and slot geometry validate")
	check(sim.submit({"id":"recovery-close", "type":"close_room", "payload":{"room_id":"room_001"}}).ok, "upgraded recovery closes for editing")
	var edited := sim.submit({"id":"recovery-edit", "type":"move_room", "payload":{"room_id":"room_001", "origin_cell":25, "rotation":0, "layout":_layout(5, 4)}})
	check(edited.ok, "upgraded recovery room can change its floor layout")
	if not edited.ok: return
	var snapshot := sim.snapshot()
	check(snapshot.rooms.room_001.invested_cost == catalog.rooms.recovery.cost + 11 * 20 + catalog.rooms.recovery.upgrade_cost, "upgraded edit retains the upgrade in its canonical price")
	check(ClinicState.from_data(snapshot, catalog).ok, "upgraded edit validates against pre-upgrade and prior-layout history")
	var io := MemoryIO.new()
	check(SaveStore.save(snapshot, SAVE_ROOT, io).ok, "upgraded edited recovery room saves")
	var loaded := SaveStore.load(SAVE_ROOT, catalog, io)
	check(loaded.ok and loaded.state.to_data() == snapshot, "upgraded edited recovery layout and slot order roundtrip exactly")
