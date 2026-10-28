extends RefCounted

var catalog: ContentCatalog
var store: Variant
var run_root: String
var number := 0

# Real disk I/O remains in use. Only a specified OS boundary returns failure;
# crash mode fails all later mutations, including attempted rollback.
class FaultIO extends RefCounted:
	var fail_at := 0
	var operations := 0
	var crash := false
	var writes_fail := false
	var corrupt_read := ""
	var fail_after := false
	var substitute_path := ""
	var substitute_text := ""
	func exists(path: String) -> bool:
		return FileAccess.file_exists(path)
	func read(path: String) -> String:
		if path.get_file() == corrupt_read: return "{injected short read"
		return FileAccess.get_file_as_string(path)
	func mkdir(path: String) -> Error:
		return DirAccess.make_dir_recursive_absolute(path)
	func write(path: String, text: String) -> Error:
		if writes_fail or (crash and operations >= fail_at):
			return ERR_CANT_CREATE
		var file := FileAccess.open(path,FileAccess.WRITE)
		if file == null:
			return FileAccess.get_open_error()
		file.store_string(substitute_text if path.get_file() == substitute_path else text)
		file.flush()
		return file.get_error()
	func rename(from: String, to: String) -> Error:
		operations += 1
		if fail_after and operations == fail_at:
			DirAccess.rename_absolute(from,to)
			return ERR_CANT_CREATE
		if operations == fail_at or (crash and operations >= fail_at):
			return ERR_CANT_CREATE
		return DirAccess.rename_absolute(from,to)

func run(t: TestContext) -> void:
	catalog = ContentCatalog.load_checked("res://content").catalog
	run_root = ProjectSettings.globalize_path("res://../temp/tests/save-%d" % Time.get_ticks_usec())
	if FileAccess.file_exists("res://storage/save_store.gd"):
		store = load("res://storage/save_store.gd")
	test_congested_reload_matches_uninterrupted_run(t)
	test_save_immediately_after_paused_build_keeps_tick_cash_and_receipt(t)
	test_truncated_main_uses_valid_backup(t)
	test_write_failure_preserves_main_and_backup(t)
	test_unknown_content_incompatible_version_and_double_corruption_preserve_files(t)
	test_duplicate_income_and_wages_do_not_reappear_after_load(t)
	test_exchange_boundaries_recover_committed_snapshots(t)
	test_strict_validation_rejects_inconsistent_snapshots(t)
	test_scenario_history_and_actor_absence_roundtrip(t)
	test_lossless_json_numbers_and_invalid_snapshot_ownership(t)
	test_paused_map_edit_preserves_pending_replan(t)
	test_candidate_backup_verification_and_postpromotion_crash(t)
	test_outside_negative_cash_and_shutdown_snapshots(t)
	test_verified_copy_must_match_intended_snapshot(t)
	test_malformed_treatment_rejects_without_partial_state(t)
	test_truncated_cached_route_rejects_in_memory_and_on_disk(t)
	test_falsely_current_wall_route_rejects_in_memory_and_on_disk(t)
	test_changed_goal_and_empty_pending_route_restore(t)

func _available(t: TestContext, label: String) -> bool:
	t.expect_true(store != null,label + " save implementation exists")
	return store != null

func _root() -> String:
	number += 1
	return run_root.path_join(str(number))

func _write(path: String, content: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(content)
	file.flush()

func _sim() -> Simulation:
	return Scenarios.create_sim(catalog,"benchmark_18","fast","standard")

# Removing blocked occupancy or losing any route quarter must diverge after load.
func test_congested_reload_matches_uninterrupted_run(t: TestContext) -> void:
	if not _available(t,"congested reload"): return
	var sim := _sim()
	var found := false
	for tick in range(4500):
		sim.advance_ticks(1)
		var d := sim.snapshot()
		for p in d.patients.values():
			if p.slot_id == "": continue
			for slot in d.slots.values():
				if slot.patient_id == p.id and slot.phase == "blocked" and d.slots[p.slot_id].phase == "reserved":
					found = true
		if found: break
	t.expect_true(found,"real flow reaches old blocked + next reserved handoff")
	var root := _root()
	t.expect_true(store.save(sim.snapshot(),root).ok,"congested full state saves")
	var result: Dictionary = store.load(root,catalog)
	t.expect_true(result.ok,"congested load: " + result.error)
	if not result.ok: return
	t.expect_equal(result.state.to_data(),sim.snapshot(),"all authoritative fields survive disk")
	var resumed := Simulation.new(catalog,result.state)
	sim.advance_ticks(2200)
	resumed.advance_ticks(2200)
	t.expect_equal(resumed.snapshot(),sim.snapshot(),"same tick complete snapshot matches uninterrupted run")

func test_save_immediately_after_paused_build_keeps_tick_cash_and_receipt(t: TestContext) -> void:
	if not _available(t,"paused transaction"): return
	var sim := Scenarios.create_sim(catalog,"level_01","fast","standard")
	var command := {"id":"touch-build","type":"build_room","payload":{"kind":"reception","origin_cell":121,"rotation":0}}
	var receipt := sim.submit(command)
	var root := _root()
	t.expect_true(receipt.ok,"paused real build accepted")
	t.expect_true(store.save(sim.snapshot(),root).ok,"paused transaction saves")
	var loaded: Dictionary = store.load(root,catalog)
	t.expect_true(loaded.ok,"paused load succeeds")
	if not loaded.ok: return
	var resumed := Simulation.new(catalog,loaded.state)
	t.expect_equal(resumed.submit(command),receipt,"touch redelivery returns saved receipt")
	resumed.advance_ticks(12)
	t.expect_equal(resumed.snapshot(),sim.snapshot(),"paused tick/cash/receipt preserved")

func test_truncated_main_uses_valid_backup(t: TestContext) -> void:
	if not _available(t,"backup recovery"): return
	var sim := _sim()
	var before := sim.snapshot()
	var root := _root()
	t.expect_true(store.save(before,root).ok,"first committed snapshot")
	sim.advance_ticks(400)
	t.expect_true(store.save(sim.snapshot(),root).ok,"second committed snapshot")
	_write(root.path_join("main.json"),"{truncated")
	var loaded: Dictionary = store.load(root,catalog)
	t.expect_true(loaded.ok and loaded.used_backup,"corrupt main explicitly reports backup")
	t.expect_true(loaded.error != "","backup diagnosis visible")
	if loaded.ok: t.expect_equal(loaded.state.to_data(),before,"previous committed snapshot chosen")
	t.expect_equal(FileAccess.get_file_as_string(root.path_join("main.json")),"{truncated","corrupt main retained verbatim")

func test_write_failure_preserves_main_and_backup(t: TestContext) -> void:
	if not _available(t,"write failure"): return
	var sim := _sim()
	var root := _root()
	store.save(sim.snapshot(),root)
	sim.advance_ticks(40)
	store.save(sim.snapshot(),root)
	var main := FileAccess.get_file_as_string(root.path_join("main.json"))
	var backup := FileAccess.get_file_as_string(root.path_join("previous.json"))
	var io := FaultIO.new()
	io.writes_fail = true
	sim.advance_ticks(40)
	var result: Dictionary = store.save(sim.snapshot(),root,io)
	t.expect_false(result.ok,"candidate write failure reported")
	t.expect_true(result.error != "","I/O error exposed")
	t.expect_equal(FileAccess.get_file_as_string(root.path_join("main.json")),main,"write failure keeps main bytes")
	t.expect_equal(FileAccess.get_file_as_string(root.path_join("previous.json")),backup,"write failure keeps previous bytes")

func test_unknown_content_incompatible_version_and_double_corruption_preserve_files(t: TestContext) -> void:
	if not _available(t,"bad committed files"): return
	var original := _sim().snapshot()
	for field in ["schema_version","content_version","unknown_room","fractional"]:
		var d := original.duplicate(true)
		match field:
			"schema_version": d.schema_version = 99
			"content_version": d.content_version = "future"
			"unknown_room": d.rooms.room_001.kind = "unknown"
			"fractional": d.cash = 1.5
		var root := _root()
		var raw := JSON.stringify(d)
		_write(root.path_join("main.json"),raw)
		_write(root.path_join("previous.json"),"{broken previous")
		var loaded: Dictionary = store.load(root,catalog)
		t.expect_false(loaded.ok,field + " rejected")
		t.expect_equal(loaded.state,null,"no partial state escapes")
		t.expect_true(loaded.error != "","failure gives diagnosis")
		t.expect_false(store.save(original,root).ok,"no implicit fresh overwrite of double corruption")
		t.expect_equal(FileAccess.get_file_as_string(root.path_join("main.json")),raw,"bad main unchanged")
		t.expect_equal(FileAccess.get_file_as_string(root.path_join("previous.json")),"{broken previous","bad previous unchanged")
	var root := _root()
	_write(root.path_join("candidate.json"),JSON.stringify(original))
	t.expect_false(store.load(root,catalog).ok,"uncommitted candidate never used as new game")

func test_duplicate_income_and_wages_do_not_reappear_after_load(t: TestContext) -> void:
	if not _available(t,"no duplicate money"): return
	var sim := _sim()
	sim.advance_ticks(3600)
	var root := _root()
	t.expect_true(store.save(sim.snapshot(),root).ok,"payroll and exits save")
	var loaded: Dictionary = store.load(root,catalog)
	t.expect_true(loaded.ok,"payroll state restores")
	if not loaded.ok: return
	var before: Dictionary = loaded.state.to_data()
	Challenge.after_tick(loaded.state,catalog)
	t.expect_equal(loaded.state.to_data(),before,"same business boundary cannot deduct twice")
	var resumed := Simulation.new(catalog,loaded.state)
	sim.advance_ticks(2400)
	resumed.advance_ticks(2400)
	t.expect_equal(resumed.snapshot(),sim.snapshot(),"no real-time catch-up or repeated income/wages")

func test_exchange_boundaries_recover_committed_snapshots(t: TestContext) -> void:
	if not _available(t,"rotation boundaries"): return
	for crash in [false,true]:
		for boundary in range(1,5):
			var sim := _sim()
			var first := sim.snapshot()
			var root := _root()
			store.save(first,root)
			sim.advance_ticks(30)
			var old := sim.snapshot()
			store.save(old,root)
			sim.advance_ticks(30)
			var io := FaultIO.new()
			io.fail_at = boundary
			io.crash = crash
			var saved: Dictionary = store.save(sim.snapshot(),root,io)
			t.expect_false(saved.ok,"rotation boundary %d crash=%s reports failure" % [boundary,crash])
			var recovered: Dictionary = store.load(root,catalog)
			t.expect_true(recovered.ok,"startup recovers committed state at each boundary")
			if recovered.ok: t.expect_equal(recovered.state.to_data(),old,"failed promotion restores last main")
			if not crash:
				t.expect_equal(FileAccess.get_file_as_string(root.path_join("previous.json")),JSON.stringify(first),"reported failure restores previous too")

func test_strict_validation_rejects_inconsistent_snapshots(t: TestContext) -> void:
	var state := ClinicState.new()
	if not state.has_method("from_data"):
		t.expect_true(false,"strict from_data validation exists")
		return
	var sim := _sim()
	sim.advance_ticks(900)
	var good := sim.snapshot()
	var result: Dictionary = state.call("from_data",good,catalog)
	t.expect_true(result.ok,"strict in-memory integer snapshot accepted: "+result.error)
	var cases := []
	for pair in [["tick",1.0],["tick",-1],["speed",3],["paused",1],["cash",999999],["scenario_id","invalid"],["schema_version",2],["arrival_cursor",999],["next_ids",{"room":1,"staff":1,"patient":1}]]:
		var d := good.duplicate(true)
		d[pair[0]] = pair[1]
		cases.append(d)
	var d := good.duplicate(true)
	d.ledger_entries.append(d.ledger_entries[0].duplicate(true))
	cases.append(d)
	d = good.duplicate(true)
	d.staff.staff_001.room_id = "missing"
	cases.append(d)
	d = good.duplicate(true)
	d.rooms.room_001.staff_id = ""
	cases.append(d)
	d = good.duplicate(true)
	d.slots["room_001:0"].remaining_ticks = -1
	cases.append(d)
	d = good.duplicate(true)
	d.queues.room_001.append("missing")
	cases.append(d)
	d = good.duplicate(true)
	d.patients[d.patients.keys()[0]].move_progress = 4
	cases.append(d)
	d = good.duplicate(true)
	d.patients[d.patients.keys()[0]].phase = "invalid"
	cases.append(d)
	d = good.duplicate(true)
	d.scheduled_arrivals[0].id = d.scheduled_arrivals[1].id
	cases.append(d)
	d = good.duplicate(true)
	d.metrics.income += 1
	cases.append(d)
	for invalid in cases:
		result = state.call("from_data",invalid,catalog)
		t.expect_false(result.ok,"invalid typed/linked/financial snapshot rejected")
		t.expect_equal(result.state,null,"invalid recovery publishes no state")
	t.expect_equal(sim.snapshot(),good,"validation does not mutate live snapshot")

func test_scenario_history_and_actor_absence_roundtrip(t: TestContext) -> void:
	if not _available(t,"scenario retention"): return
	for scenario in ["load_40","level_01"]:
		var sim := Scenarios.create_sim(catalog,scenario,"tolerance","longer_walk")
		if scenario == "load_40": sim.advance_ticks(2500)
		else: sim.submit({"id":"new-staff","type":"hire_staff","payload":{"role":"doctor"}})
		var root := _root()
		t.expect_true(store.save(sim.snapshot(),root).ok,"scenario saves including absent actor cells")
		var loaded: Dictionary = store.load(root,catalog)
		t.expect_true(loaded.ok,"scenario restores: " + loaded.error)
		if loaded.ok: t.expect_equal(loaded.state.to_data(),sim.snapshot(),"scenario flags, six-digit replenishment IDs and terminal history retained")

func test_lossless_json_numbers_and_invalid_snapshot_ownership(t: TestContext) -> void:
	if not _available(t,"precision and ownership"): return
	var original := _sim().snapshot()
	for token in ["9007199254740990.1","1.00000000000000001","1e100","-9007199254740992","0.1","1e-3"]:
		var root := _root()
		_write(root.path_join("main.json"),JSON.stringify(original).replace('"tick":0','"tick":'+token))
		t.expect_false(store.load(root,catalog).ok,"nonintegral or unsafe JSON token rejected: "+token)
	for token in ["0.0","0e5","0e-5"]:
		var root := _root()
		_write(root.path_join("main.json"),JSON.stringify(original).replace('"tick":0','"tick":'+token))
		t.expect_true(store.load(root,catalog).ok,"lossless integral JSON token accepted: "+token)
	var cases := []
	var d := original.duplicate(true)
	d.staff.staff_001.phase = "serving"
	cases.append(d)
	d = original.duplicate(true)
	d.last_payroll_tick = 1200
	d.tick = 1200
	cases.append(d)
	d = original.duplicate(true)
	d.command_receipts.setup_build_reception.data.command.payload.kind = "unknown"
	cases.append(d)
	d = original.duplicate(true)
	d.ledger_entries[0].event_id = "invented"
	cases.append(d)
	d = original.duplicate(true)
	d.ledger_entries[0].delta += 1
	d.cash += 1
	cases.append(d)
	d = original.duplicate(true)
	d.next_ids.patient += 1
	cases.append(d)
	d = original.duplicate(true)
	d.tick = 900
	d.last_business_tick = 900
	cases.append(d)
	for invalid in cases:
		t.expect_false(ClinicState.from_data(invalid,catalog).ok,"staff/clock/receipt/event inconsistency rejected")
	var sim := _sim()
	sim.advance_ticks(900)
	d = sim.snapshot()
	var active := []
	for id in d.slots:
		if d.slots[id].phase in ["reserved","serving"]: active.append(id)
	t.expect_true(active.size() >= 2,"real flow supplies distinct active owners")
	if active.size() >= 2:
		d.slots[active[1]].patient_id = d.slots[active[0]].patient_id
		t.expect_false(ClinicState.from_data(d,catalog).ok,"two active slots cannot own one actor")

func test_paused_map_edit_preserves_pending_replan(t: TestContext) -> void:
	if not _available(t,"paused populated replan"): return
	var state := ClinicState.create("level_01",catalog)
	state.data.hint_flags.disabled = true
	var sim := Simulation.new(catalog,state)
	sim.submit({"id":"first-room","type":"build_room","payload":{"kind":"diagnosis","origin_cell":28,"rotation":0}})
	sim.submit({"id":"hire","type":"hire_staff","payload":{"role":"doctor"}})
	sim.submit({"id":"assign","type":"assign_staff","payload":{"staff_id":"staff_001","room_id":"room_001"}})
	sim.submit({"id":"start","type":"set_paused","payload":{"paused":false}})
	sim.advance_ticks(1)
	sim.submit({"id":"pause","type":"set_paused","payload":{"paused":true}})
	var old_revision: int = state.data.staff.staff_001.route_revision
	var route: Array = state.data.staff.staff_001.path.duplicate()
	var built := sim.submit({"id":"build","type":"build_room","payload":{"kind":"reception","origin_cell":121,"rotation":0}})
	t.expect_true(built.ok,"populated paused build accepted")
	t.expect_true(121 in route and 121 in state.data.rooms.room_002.equipment_cells,"pending future path actually crosses new equipment")
	t.expect_equal(state.data.staff.staff_001.move_progress,1,"in-flight quarter edge retained before replan")
	t.expect_true(state.data.map_revision > old_revision,"cached actor revision awaits clinical replan")
	var falsely_current := sim.snapshot()
	falsely_current.staff.staff_001.route_revision = falsely_current.map_revision
	_expect_route_rejected(t,falsely_current,"falsely current equipment-crossing cache")
	var root := _root()
	t.expect_true(store.save(sim.snapshot(),root).ok,"pending map revision saves")
	var restored: Dictionary = store.load(root,catalog)
	t.expect_true(restored.ok,"pending replan restores")
	if not restored.ok: return
	t.expect_equal(restored.state.to_data(),sim.snapshot(),"save does not trigger replan")
	var resumed := Simulation.new(catalog,restored.state)
	var command := {"id":"resume","type":"set_paused","payload":{"paused":false}}
	sim.submit(command)
	resumed.submit(command)
	sim.advance_ticks(700)
	resumed.advance_ticks(700)
	t.expect_equal(resumed.snapshot(),sim.snapshot(),"map invalidation resumes identically")

func test_candidate_backup_verification_and_postpromotion_crash(t: TestContext) -> void:
	if not _available(t,"verification boundaries"): return
	for short_read in ["candidate.json","previous.next.json"]:
		var sim := _sim()
		var root := _root()
		store.save(sim.snapshot(),root)
		sim.advance_ticks(20)
		store.save(sim.snapshot(),root)
		var before := FileAccess.get_file_as_string(root.path_join("main.json"))
		var backup := FileAccess.get_file_as_string(root.path_join("previous.json"))
		var io := FaultIO.new()
		io.corrupt_read = short_read
		sim.advance_ticks(20)
		t.expect_false(store.save(sim.snapshot(),root,io).ok,"reread failure rejects "+short_read)
		t.expect_equal(FileAccess.get_file_as_string(root.path_join("main.json")),before,"verification failure keeps committed main bytes")
		t.expect_equal(FileAccess.get_file_as_string(root.path_join("previous.json")),backup,"verification failure keeps backup bytes")
	var sim := _sim()
	var root := _root()
	store.save(sim.snapshot(),root)
	sim.advance_ticks(20)
	var old := sim.snapshot()
	store.save(old,root)
	sim.advance_ticks(20)
	var io := FaultIO.new()
	io.fail_at = 4
	io.fail_after = true
	io.crash = true
	t.expect_false(store.save(sim.snapshot(),root,io).ok,"ambiguous rename completion reported")
	var restored: Dictionary = store.load(root,catalog)
	t.expect_true(restored.ok,"already promoted main remains complete")
	if restored.ok: t.expect_equal(restored.state.to_data(),sim.snapshot(),"completed promotion wins over stale swap")
	t.expect_equal(FileAccess.get_file_as_string(root.path_join("previous.json")),JSON.stringify(old),"previous remains last committed main")

func test_outside_negative_cash_and_shutdown_snapshots(t: TestContext) -> void:
	if not _available(t,"outside negative and shutdown"): return
	var initial := Scenarios.create_sim(catalog,"load_40","fast","standard").snapshot()
	var state: ClinicState = ClinicState.from_data(initial,catalog).state
	# Additional real arrival beyond the forty admitted actors; no cash override.
	Scenarios._append_arrival(state,0)
	PatientFlow.admit_arrivals(state,catalog)
	t.expect_equal(state.data.outside_queue.size(),1,"forty-first actual arrival remains outside")
	var root := _root()
	t.expect_true(store.save(state.to_data(),root).ok,"outside no-cell snapshot saves")
	var restored: Dictionary = store.load(root,catalog)
	t.expect_true(restored.ok,"outside no-cell snapshot loads")
	if restored.ok: t.expect_equal(restored.state.to_data(),state.to_data(),"outside membership and omitted cell retained")
	var sim := Scenarios.create_sim(catalog,"load_40","fast","standard")
	t.expect_true(sim.submit({"id":"extra-recovery","type":"build_room","payload":{"kind":"recovery","origin_cell":308,"rotation":0}}).ok,"paid extra recovery consumes600")
	t.expect_true(sim.submit({"id":"extra-reception","type":"build_room","payload":{"kind":"reception","origin_cell":289,"rotation":0}}).ok,"paid extra reception consumes400")
	for tick in range(1000):
		sim.advance_ticks(1)
		if sim.snapshot().cash < 0: break
	t.expect_true(sim.snapshot().cash < 0 and sim.snapshot().negative_cash_ticks > 0,"real treatment cost produces conserved negative cash")
	sim.submit({"id":"drain","type":"close_room","payload":{"room_id":"room_003"}})
	sim.submit({"id":"stop","type":"set_paused","payload":{"paused":true}})
	root = _root()
	t.expect_true(store.save(sim.snapshot(),root).ok,"negative timer and draining room save")
	restored = store.load(root,catalog)
	t.expect_true(restored.ok,"negative timer and draining room load")
	if restored.ok: t.expect_equal(restored.state.to_data(),sim.snapshot(),"negative duration/shutdown/modes preserved exactly")

func test_verified_copy_must_match_intended_snapshot(t: TestContext) -> void:
	if not _available(t,"verified copy identity"): return
	for target in ["candidate.json","previous.next.json"]:
		var sim := _sim()
		var first := sim.snapshot()
		var root := _root()
		store.save(first,root)
		sim.advance_ticks(10)
		store.save(sim.snapshot(),root)
		var before := FileAccess.get_file_as_string(root.path_join("main.json"))
		var backup := FileAccess.get_file_as_string(root.path_join("previous.json"))
		sim.advance_ticks(10)
		var io := FaultIO.new()
		io.substitute_path = target
		io.substitute_text = JSON.stringify(first)
		t.expect_false(store.save(sim.snapshot(),root,io).ok,"valid but wrong written snapshot rejected: "+target)
		t.expect_equal(FileAccess.get_file_as_string(root.path_join("main.json")),before,"wrong copied snapshot cannot change main")
		t.expect_equal(FileAccess.get_file_as_string(root.path_join("previous.json")),backup,"wrong copied snapshot cannot change previous")

func test_malformed_treatment_rejects_without_partial_state(t: TestContext) -> void:
	var sim := _sim()
	var id := ""
	for tick in range(1500):
		sim.advance_ticks(1)
		for p in sim.snapshot().patients.values():
			if p.phase == "treatment_service": id = p.id
		if id != "": break
	t.expect_true(id != "","actual treatment supplies malformed-data fixture")
	if id == "": return
	var d := sim.snapshot()
	d.patients[id].phase = "reception_service"
	d.patients[id].treatment_started = false
	d.patients[id].erase("service_mode")
	var result: Variant = ClinicState.from_data(d,catalog)
	t.expect_true(result is Dictionary and result.get("ok",true) == false,"inconsistent service phase is a reported validation failure")
	t.expect_true(result is Dictionary and result.get("state") == null,"malformed service never publishes partial state")

func _expect_route_rejected(t: TestContext, snapshot: Dictionary, label: String) -> void:
	var before := snapshot.duplicate(true)
	var result := ClinicState.from_data(snapshot,catalog)
	t.expect_false(result.ok,label+" rejected by from_data")
	t.expect_equal(result.state,null,label+" publishes no in-memory state")
	t.expect_equal(snapshot,before,label+" validation leaves input unchanged")
	var root := _root()
	var raw := JSON.stringify(snapshot)
	_write(root.path_join("main.json"),raw)
	result = store.load(root,catalog)
	t.expect_false(result.ok,label+" rejected by disk load")
	t.expect_equal(result.state,null,label+" publishes no disk state")
	t.expect_equal(FileAccess.get_file_as_string(root.path_join("main.json")),raw,label+" corrupt file preserved")

func test_truncated_cached_route_rejects_in_memory_and_on_disk(t: TestContext) -> void:
	if not _available(t,"truncated cached route"): return
	var sim := _sim()
	sim.advance_ticks(4)
	var d := sim.snapshot()
	var actor: Dictionary = d.staff.staff_001
	t.expect_equal(actor.move_progress,0,"real moving employee reaches quarter-edge boundary")
	t.expect_true(actor.cell != actor.route_goal_cell and actor.route_revision == d.map_revision,"moving employee has current cache to a different destination")
	actor.path = [actor.cell]
	actor.path_index = 0
	_expect_route_rejected(t,d,"truncated current cached route")

func test_falsely_current_wall_route_rejects_in_memory_and_on_disk(t: TestContext) -> void:
	if not _available(t,"wall-only cached route"): return
	var state := ClinicState.create("level_01",catalog)
	var sim := Simulation.new(catalog,state)
	sim.submit({"id":"diagnosis","type":"build_room","payload":{"kind":"diagnosis","origin_cell":28,"rotation":0}})
	sim.submit({"id":"hire","type":"hire_staff","payload":{"role":"doctor"}})
	sim.submit({"id":"assign","type":"assign_staff","payload":{"staff_id":"staff_001","room_id":"room_001"}})
	sim.submit({"id":"start","type":"set_paused","payload":{"paused":false}})
	sim.advance_ticks(1)
	sim.submit({"id":"pause","type":"set_paused","payload":{"paused":true}})
	t.expect_true(sim.submit({"id":"reception","type":"build_room","payload":{"kind":"reception","origin_cell":97,"rotation":0}}).ok,"real paused build obstructs a future wall edge")
	var d := sim.snapshot()
	var actor: Dictionary = d.staff.staff_001
	t.expect_true(169 in actor.path and 145 in actor.path and [145,169] in d.rooms.room_002.wall_edges,"cached route crosses newly built wall")
	for cell in d.rooms.room_002.equipment_cells:
		t.expect_false(cell in actor.path,"wall-only fixture does not rely on equipment obstruction")
	t.expect_true(ClinicState.from_data(d,catalog).ok,"stale wall-crossing cache remains valid pending replan")
	actor.route_revision = d.map_revision
	_expect_route_rejected(t,d,"falsely current wall-crossing cache")

func test_changed_goal_and_empty_pending_route_restore(t: TestContext) -> void:
	if not _available(t,"changed destination pending route"): return
	var state := ClinicState.create("level_01",catalog)
	var sim := Simulation.new(catalog,state)
	sim.submit({"id":"echo","type":"build_room","payload":{"kind":"echo","origin_cell":104,"rotation":0}})
	sim.submit({"id":"hire","type":"hire_staff","payload":{"role":"technician"}})
	sim.submit({"id":"assign","type":"assign_staff","payload":{"staff_id":"staff_001","room_id":"room_001"}})
	sim.submit({"id":"start","type":"set_paused","payload":{"paused":false}})
	sim.advance_ticks(2)
	sim.submit({"id":"close","type":"close_room","payload":{"room_id":"room_001"}})
	t.expect_true(sim.submit({"id":"move","type":"move_room","payload":{"room_id":"room_001","origin_cell":54,"rotation":0}}).ok,"real move changes destination while staff traverses a protected edge")
	sim.submit({"id":"reopen","type":"reopen_room","payload":{"room_id":"room_001"}})
	var actor: Dictionary = state.data.staff.staff_001
	t.expect_true(actor.route_goal_cell != state.data.rooms.room_001.staff_cells[0],"old cached destination differs from newly assigned staff position")
	t.expect_true(ClinicState.from_data(sim.snapshot(),catalog).ok,"changed destination accepts old coherent cache")
	sim.advance_ticks(2)
	t.expect_equal(state.data.staff.staff_001.path,[],"completion of protected edge leaves an empty pending route")
	t.expect_equal(state.data.staff.staff_001.path_index,0,"empty pending route has normalized index")
	var root := _root()
	t.expect_true(store.save(sim.snapshot(),root).ok,"empty pending replan saves")
	var restored: Dictionary = store.load(root,catalog)
	t.expect_true(restored.ok,"empty pending replan loads")
	if not restored.ok: return
	var resumed := Simulation.new(catalog,restored.state)
	sim.advance_ticks(100)
	resumed.advance_ticks(100)
	t.expect_equal(resumed.snapshot(),sim.snapshot(),"changed destination and empty replan continue identically")
