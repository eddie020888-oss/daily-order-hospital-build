extends RefCounted

func run(t: TestContext) -> void:
	test_catalog_preserves_spec_values(t)
	test_level_has_36_stable_arrivals(t)
	test_invalid_content_rejected(t)

func test_catalog_preserves_spec_values(t: TestContext) -> void:
	# Catches wrong content prices, durations, stimulus, role costs or omitted validation.
	var loaded := ContentCatalog.load_checked("res://content")
	t.expect_true(loaded.ok, "valid catalog loads")
	if not loaded.ok:
		return
	var c: ContentCatalog = loaded.catalog
	for row in [["reception", 3, 3, 400, "receptionist"], ["diagnosis", 4, 4, 800, "doctor"], ["echo", 4, 4, 1000, "technician"], ["motion", 4, 4, 1200, "technician"], ["sensory", 4, 4, 1400, "technician"], ["recovery", 3, 3, 600, ""]]:
		var room: Dictionary = c.rooms[row[0]]
		t.expect_equal([room.width, room.height, room.cost, room.staff_role, room.capacity], [row[1], row[2], row[3], row[4], 1], row[0] + " room purchase contract")
		t.expect_true(room.cost is int, "normalized integer money: " + row[0])
	for row in [["receptionist", 100, 20], ["doctor", 300, 50], ["technician", 200, 30]]:
		t.expect_equal([c.staff[row[0]].hire_cost, c.staff[row[0]].daily_wage], [row[1], row[2]], row[0] + " hire and wages")
	var cost := 0
	for kind in ["reception","diagnosis","echo","motion","sensory","recovery"]:
		cost += c.rooms[kind].cost
	t.expect_equal(cost, 5400, "six room purchase total")
	t.expect_equal(c.staff.receptionist.hire_cost + c.staff.doctor.hire_cost + 3 * c.staff.technician.hire_cost, 1000, "five staff hiring total")
	t.expect_equal(c.staff.receptionist.daily_wage + c.staff.doctor.daily_wage + 3 * c.staff.technician.daily_wage + c.levels.level_01.fixed_daily_cost, 240, "five staff daily expenses")
	for row in [["echo", 200, 120, 15, 25, 150], ["motion", 300, 180, 30, 45, 230], ["sensory", 400, 240, 45, 65, 300]]:
		var disease: Dictionary = c.diseases[row[0]]
		t.expect_equal(disease.modes.gentle.duration_ticks, row[1], row[0] + " gentle duration")
		t.expect_equal(disease.modes.fast.duration_ticks, row[2], row[0] + " fast duration")
		t.expect_equal(disease.modes.gentle.cost, row[3], row[0] + " gentle consumables")
		t.expect_equal(disease.modes.fast.cost, row[4], row[0] + " fast consumables")
		t.expect_equal(disease.modes.gentle.stimulus, 20, row[0] + " gentle stimulus")
		t.expect_equal(disease.modes.fast.stimulus, 60, row[0] + " fast stimulus")
		t.expect_equal(disease.income, row[5], row[0] + " completion income")
	t.expect_equal(c.rooms.reception.service_ticks, 40, "reception duration")
	t.expect_equal(c.rooms.diagnosis.service_ticks, 80, "diagnosis duration")
	t.expect_equal(c.rooms.recovery.service_ticks, 400, "recovery duration")
	t.expect_equal(c.rooms.recovery.consumable_cost, 10, "recovery consumables")
	t.expect_equal(c.rooms.recovery.upgrade_cost, 400, "recovery second seat cost")

func test_level_has_36_stable_arrivals(t: TestContext) -> void:
	# Catches missing/duplicate patients, wrong group-specific tolerance, ticks and unsafe snapshots.
	var loaded := ContentCatalog.load_checked("res://content")
	t.expect_true(loaded.ok, "state catalog loads")
	if not loaded.ok:
		return
	var state := ClinicState.create("level_01", loaded.catalog)
	t.expect_equal(state.data.cash, 8000, "initial cash")
	t.expect_equal(state.data.tick, 0, "initial tick")
	t.expect_true(state.data.paused, "initially paused")
	t.expect_equal(state.data.scheduled_arrivals.size(), 36, "patient cohort")
	t.expect_equal(state.data.scheduled_arrivals[-1].tick, 5550, "last arrival")
	t.expect_equal(state.data.next_ids, {"room": 1, "staff": 1, "patient": 37}, "next IDs preserve preallocated patient cohort")
	t.expect_equal(state.data.unlocked_room_kinds, ["reception", "diagnosis", "echo", "recovery"], "initial room unlocks")
	t.expect_equal(loaded.catalog.levels.level_01.unlocks, [{"tick": 2400, "room_kind": "motion"}, {"tick": 4800, "room_kind": "sensory"}], "later unlock timing")
	t.expect_equal(state.data.arrival_cursor, 0, "no initial arrivals consumed")
	for key in ["rooms", "staff", "patients", "slots", "queues", "outside_queue", "ledger_entries", "command_receipts", "hint_flags"]:
		t.expect_true(state.data[key].is_empty(), "initially empty " + key)
	t.expect_equal(state.data.negative_cash_ticks, 0, "no inherited debt time")
	t.expect_equal(state.data.last_payroll_tick, 0, "no inherited payroll boundary")
	t.expect_equal(state.data.speed, 1, "initial speed")
	t.expect_equal(state.data.schema_version, 1, "schema version")
	t.expect_equal(state.data.content_version, "0.1.0", "content version")
	var ids := {}
	var low_by_disease := {"echo": 0, "motion": 0, "sensory": 0}
	for arrival in state.data.scheduled_arrivals:
		t.expect_false(ids.has(arrival.id), "unique patient " + arrival.id)
		ids[arrival.id] = true
		if arrival.tolerance == 30:
			low_by_disease[arrival.disease_id] += 1
	t.expect_equal(low_by_disease, {"echo": 5, "motion": 8, "sensory": 4}, "group-specific low tolerance distribution")
	t.expect_equal(state.data.scheduled_arrivals[0], {"id": "patient_001", "tick": 200, "disease_id": "echo", "tolerance": 30}, "first patient")
	t.expect_equal(state.data.scheduled_arrivals[12], {"id": "patient_013", "tick": 2600, "disease_id": "echo", "tolerance": 30}, "second cohort starts")
	t.expect_equal(state.data.scheduled_arrivals[24], {"id": "patient_025", "tick": 5000, "disease_id": "echo", "tolerance": 70}, "surge starts")
	var snapshot := state.to_data()
	snapshot.scheduled_arrivals[0].tolerance = 70
	t.expect_equal(state.data.scheduled_arrivals[0].tolerance, 30, "snapshot deep copy")
	t.expect_equal(state.to_data(), ClinicState.create("level_01", loaded.catalog).to_data(), "deterministic initial state")
	t.expect_true(_only_json_values(state.to_data()), "state contains only JSON primitives with integer numbers")
	t.expect_equal(ClinicState.create("unknown_level", loaded.catalog), null, "unknown level is rejected")
	state.data.scheduled_arrivals[0].tolerance = 70
	t.expect_equal(loaded.catalog.levels.level_01.arrivals[0].tolerance, 30, "state cannot mutate catalog arrivals")

func test_invalid_content_rejected(t: TestContext) -> void:
	# Mutates real copied content, preserving the originals; catches silent truncation and bad references.
	var root := "user://bootstrap-invalid"
	DirAccess.make_dir_recursive_absolute(root)
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/invalid_content.json"))
	for case in fixture.cases:
		for name in ["rooms", "diseases", "staff", "level_01", "clinical_02"]:
			var source := FileAccess.get_file_as_string("res://content/%s.json" % name)
			if name == case.file:
				var document: Dictionary = JSON.parse_string(source)
				for item in document.items:
					if item.id == case.target:
						if case.get("remove", false):
							item.erase(case.field)
						else:
							item[case.field] = case.value
				source = JSON.stringify(document)
			var file := FileAccess.open(root.path_join(name + ".json"), FileAccess.WRITE)
			file.store_string(source)
			file.close()
		var result := ContentCatalog.load_checked(root)
		t.expect_false(result.ok, "reject " + case.name)
		t.expect_contains(result.error, case.error, "specific error for " + case.name)
	t.expect_true(ContentCatalog.load_checked("res://content").ok, "original content intact")
	var malformed := FileAccess.open(root.path_join("rooms.json"), FileAccess.WRITE)
	malformed.store_string("{truncated")
	malformed.close()
	var malformed_result := ContentCatalog.load_checked(root)
	t.expect_false(malformed_result.ok, "malformed JSON rejected")
	t.expect_contains(malformed_result.error, "invalid_json", "malformed JSON reason")
	var missing_result := ContentCatalog.load_checked("user://missing-content-folder")
	t.expect_false(missing_result.ok, "missing content rejected")
	t.expect_contains(missing_result.error, "missing_file", "missing content reason")

func _only_json_values(value: Variant) -> bool:
	if value is Dictionary:
		for key in value:
			if not key is String or not _only_json_values(value[key]):
				return false
		return true
	if value is Array:
		for item in value:
			if not _only_json_values(item):
				return false
		return true
	return value is String or value is bool or value is int
