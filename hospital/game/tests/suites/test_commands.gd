extends RefCounted

var simulation_script: GDScript
var ledger_script: GDScript
var sequence := 0

func run(t: TestContext) -> void:
	var present := FileAccess.file_exists("res://sim/simulation.gd") and FileAccess.file_exists("res://sim/command_bus.gd") and FileAccess.file_exists("res://sim/ledger.gd")
	t.expect_true(present, "Commands simulation, transaction and ledger modules exist")
	if not present:
		return
	simulation_script = load("res://sim/simulation.gd")
	ledger_script = load("res://sim/ledger.gd")
	test_paused_build_and_duplicate_command(t)
	test_all_rooms_and_five_staff_leave_1600(t)
	test_insufficient_cash_does_not_partially_build_or_allocate_id(t)
	test_mutating_snapshot_does_not_mutate_simulation(t)
	test_mode_and_staff_commands_validate_types_and_targets(t)
	test_close_drain_move_remove_and_refund(t)
	test_busy_room_and_staff_cannot_be_moved(t)
	test_upgrade_preserves_fields_and_does_not_charge_twice(t)
	test_clock_controls_validate_and_speed_does_not_multiply_ticks(t)
	test_ledger_posts_once_and_separates_operating_from_capital(t)
	test_invalid_commands_are_atomic_and_retriable(t)
	test_ended_challenge_rejects_new_commands_but_replays_receipts(t)

func _catalog() -> ContentCatalog:
	return ContentCatalog.load_checked("res://content").catalog

func _state(all_rooms: bool = true) -> ClinicState:
	var state := ClinicState.create("level_01", _catalog())
	if all_rooms:
		state.data.unlocked_room_kinds = ["reception", "diagnosis", "echo", "motion", "sensory", "recovery"]
	return state

func _sim(state: ClinicState):
	return simulation_script.new(_catalog(), state)

func _send(sim, type: String, payload: Dictionary = {}) -> Dictionary:
	sequence += 1
	return sim.submit({"id":"test_%d" % sequence, "type":type, "payload":payload})

func _build(sim, kind: String = "reception", cell: int = 121) -> Dictionary:
	return _send(sim, "build_room", {"kind":kind, "origin_cell":cell, "rotation":0})

func _reject(t: TestContext, sim, type: String, payload: Dictionary, code: String) -> void:
	var before: Dictionary = sim.snapshot()
	var result := _send(sim, type, payload)
	t.expect_false(result.ok, "reject " + type + ": " + code)
	t.expect_equal(result.code, code, "stable rejection code")
	t.expect_equal(sim.snapshot(), before, "rejected " + type + " leaves entire state intact")

func test_paused_build_and_duplicate_command(t: TestContext) -> void:
	# Catches duplicate charging, asynchronous control commands, and receipt aliasing.
	var sim = _sim(_state())
	var command := {"id":"c1", "type":"build_room", "payload":{"kind":"reception", "origin_cell":121, "rotation":0}}
	var first: Dictionary = sim.submit(command)
	t.expect_true(first.ok, "first paused build succeeds")
	t.expect_equal(first.data.room_id, "room_001", "first room uses stable ID")
	var after: Dictionary = sim.snapshot()
	t.expect_equal(sim.submit(command), first, "duplicate returns original receipt")
	t.expect_equal(sim.snapshot(), after, "duplicate has no side effects")
	t.expect_equal(after.cash, 7600, "charged only once")
	t.expect_equal(after.tick, 0, "paused clock unchanged")
	t.expect_equal(after.command_sequence, 1, "one committed command sequence")
	t.expect_equal(after.command_receipts.c1.data.tick, 0, "receipt records control tick")
	t.expect_equal(after.command_receipts.c1.data.sequence, 1, "receipt records control order")
	first.data.room_id = "forged"
	t.expect_equal(sim.submit(command).data.room_id, "room_001", "receipt is deep copied")
	command.payload.origin_cell = 54
	t.expect_equal(sim.submit(command).data.room_id, "room_001", "successful ID always replays original result")

func test_all_rooms_and_five_staff_leave_1600(t: TestContext) -> void:
	# Catches incorrect prices, dropped entities, and non-capital build/hire entries.
	var sim = _sim(_state())
	for pair in [["reception",121],["diagnosis",100],["echo",104],["motion",108],["sensory",112],["recovery",140]]:
		t.expect_true(_build(sim, pair[0], pair[1]).ok, "build " + pair[0])
	for role in ["receptionist", "doctor", "technician", "technician", "technician"]:
		t.expect_true(_send(sim, "hire_staff", {"role":role}).ok, "hire " + role)
	var snapshot: Dictionary = sim.snapshot()
	t.expect_equal(snapshot.cash, 1600, "six facilities and five hires leave exact budget")
	t.expect_equal(snapshot.rooms.size(), 6, "six rooms")
	t.expect_equal(snapshot.staff.size(), 5, "five staff")
	t.expect_equal(snapshot.slots.size(), 6, "one authoritative service slot per room")
	t.expect_equal(snapshot.ledger_entries.size(), 11, "one ledger entry per capital purchase")
	t.expect_equal(snapshot.metrics.operating_profit, 0, "capital spending excluded from operating profit")
	for index in range(3):
		t.expect_true(_send(sim, "hire_staff", {"role":"technician"}).ok, "hire up to limit")
	_reject(t, sim, "hire_staff", {"role":"technician"}, "staff_limit")

func test_insufficient_cash_does_not_partially_build_or_allocate_id(t: TestContext) -> void:
	# Catches reserving an ID or creating slots/ledger before cash validation.
	var state := _state()
	state.data.cash = 399
	var sim = _sim(state)
	_reject(t, sim, "build_room", {"kind":"reception", "origin_cell":121, "rotation":0}, "insufficient_cash")
	t.expect_equal(state.data.next_ids.room, 1, "failed build keeps next room ID")
	t.expect_true(_send(sim, "hire_staff", {"role":"doctor"}).ok, "affordable hire still succeeds")
	_reject(t, sim, "hire_staff", {"role":"receptionist"}, "insufficient_cash")
	t.expect_equal(state.data.next_ids.staff, 2, "failed hire keeps next staff ID")
	var locked = _sim(_state(false))
	_reject(t, locked, "build_room", {"kind":"motion", "origin_cell":108, "rotation":0}, "room_locked")

func test_mutating_snapshot_does_not_mutate_simulation(t: TestContext) -> void:
	# Catches nested state aliases through snapshots or caller-owned command payloads.
	var sim = _sim(_state())
	_build(sim)
	var before: Dictionary = sim.snapshot()
	var snapshot: Dictionary = sim.snapshot()
	snapshot.rooms.room_001.cells.clear()
	snapshot.command_receipts.clear()
	snapshot.scheduled_arrivals.clear()
	snapshot.metrics.wait_ticks.changed = 1
	t.expect_equal(sim.snapshot(), before, "all nested snapshot state is isolated")

func test_mode_and_staff_commands_validate_types_and_targets(t: TestContext) -> void:
	# Catches role mismatch, stale targets, malformed booleans and edits to active treatment.
	var state := _state()
	var sim = _sim(state)
	_build(sim)
	_build(sim, "echo", 104)
	_send(sim, "hire_staff", {"role":"doctor"})
	_send(sim, "hire_staff", {"role":"technician"})
	_reject(t, sim, "assign_staff", {"staff_id":"staff_001", "room_id":"room_001"}, "role_mismatch")
	_reject(t, sim, "assign_staff", {"staff_id":"missing", "room_id":"room_002"}, "unknown_staff")
	_reject(t, sim, "assign_staff", {"staff_id":"staff_002", "room_id":"missing"}, "unknown_room")
	t.expect_true(_send(sim, "assign_staff", {"staff_id":"staff_002", "room_id":"room_002"}).ok, "matching technician assigned")
	t.expect_equal(sim.snapshot().rooms.room_002.staff_id, "staff_002", "room knows assigned staff")
	t.expect_equal(sim.snapshot().staff.staff_002.room_id, "room_002", "staff knows assigned room")
	_reject(t, sim, "set_room_mode", {"room_id":"room_002", "mode":"turbo"}, "invalid_mode")
	_reject(t, sim, "set_room_mode", {"room_id":"room_001", "mode":"fast"}, "not_treatment_room")
	t.expect_true(_send(sim, "set_room_mode", {"room_id":"room_002", "mode":"gentle"}).ok, "set treatment default")
	t.expect_equal(sim.snapshot().rooms.room_002.mode, "gentle", "mode committed")
	_reject(t, sim, "set_auto_route", {"enabled":1}, "invalid_payload")
	t.expect_true(_send(sim, "set_auto_route", {"enabled":true}).ok, "enable tolerance routing")
	t.expect_true(sim.snapshot().auto_route, "routing persisted")
	_reject(t, sim, "set_patient_mode", {"patient_id":"missing", "mode":"gentle"}, "unknown_patient")
	state.data.patients.p = {"phase":"treatment_queue", "treatment_started":false}
	t.expect_true(_send(sim, "set_patient_mode", {"patient_id":"p", "mode":"gentle"}).ok, "queued patient override accepted")
	t.expect_equal(state.data.patients.p.mode_override, "gentle", "override persisted")
	_reject(t, sim, "set_patient_mode", {"patient_id":"p", "mode":"bad"}, "invalid_mode")
	state.data.patients.p.phase = "treatment_service"
	_reject(t, sim, "set_patient_mode", {"patient_id":"p", "mode":"fast"}, "treatment_started")
	state.data.patients.p.phase = "treatment_queue"
	state.data.patients.p.treatment_started = true
	_reject(t, sim, "set_patient_mode", {"patient_id":"p", "mode":"fast"}, "treatment_started")

func test_close_drain_move_remove_and_refund(t: TestContext) -> void:
	# Catches moving an open room, lost defaults, repeated charges and stale room references.
	var sim = _sim(_state())
	_build(sim, "echo", 104)
	_send(sim, "hire_staff", {"role":"technician"})
	_send(sim, "assign_staff", {"staff_id":"staff_001", "room_id":"room_001"})
	_send(sim, "set_room_mode", {"room_id":"room_001", "mode":"gentle"})
	_reject(t, sim, "move_room", {"room_id":"room_001", "kind":"sensory", "origin_cell":54, "rotation":0}, "invalid_payload")
	_reject(t, sim, "move_room", {"room_id":"room_001", "origin_cell":54, "rotation":0}, "room_open")
	t.expect_true(_send(sim, "close_room", {"room_id":"room_001"}).ok, "close room enters draining")
	t.expect_true(_send(sim, "move_room", {"room_id":"room_001", "origin_cell":54, "rotation":0}).ok, "empty closed room moves")
	t.expect_equal(sim.snapshot().cash, 6800, "move costs zero")
	t.expect_equal(sim.snapshot().rooms.room_001.mode, "gentle", "move retains mode")
	t.expect_equal(sim.snapshot().rooms.room_001.staff_id, "staff_001", "move retains staff assignment")
	t.expect_equal(sim.snapshot().slots["room_001:0"].cell, 79, "move updates authoritative slot geometry")
	t.expect_true(_send(sim, "reopen_room", {"room_id":"room_001"}).ok, "reopen draining room")
	_reject(t, sim, "remove_room", {"room_id":"room_001"}, "room_open")
	_send(sim, "close_room", {"room_id":"room_001"})
	t.expect_true(_send(sim, "remove_room", {"room_id":"room_001"}).ok, "remove empty closed room")
	var snapshot: Dictionary = sim.snapshot()
	t.expect_equal(snapshot.cash, 7550, "three quarters of room investment refunded")
	t.expect_equal(snapshot.metrics.operating_profit, 0, "refund excluded from operating profit")
	t.expect_equal(snapshot.ledger_entries[-1].category, "capital_refund", "separate capital refund category")
	t.expect_equal(snapshot.staff.staff_001.room_id, "", "removed room unassigns retained employee")
	t.expect_equal(snapshot.slots, {}, "remove clears room slots")
	t.expect_equal(snapshot.queues, {}, "remove clears room queue")
	_reject(t, sim, "reopen_room", {"room_id":"room_001"}, "unknown_room")
	_reject(t, sim, "set_room_mode", {"room_id":"room_001", "mode":"fast"}, "unknown_room")

func test_busy_room_and_staff_cannot_be_moved(t: TestContext) -> void:
	# Catches ignoring queues/reservations, in-room actors, traversed edges or draining staff.
	for busy in ["queue", "slot", "reserved", "serving", "blocked", "patient", "staff", "in_flight"]:
		var state := _state()
		var sim = _sim(state)
		_build(sim, "echo", 104)
		_send(sim, "close_room", {"room_id":"room_001"})
		match busy:
			"queue": state.data.queues.room_001.append("p")
			"slot": state.data.slots["room_001:0"].patient_id = "p"
			"reserved", "serving", "blocked": state.data.slots["room_001:0"].phase = busy
			"patient": state.data.patients.p = {"cell":129}
			"staff": state.data.staff.s = {"cell":130}
			"in_flight": state.data.patients.p = {"cell":201, "path":[201,177], "path_index":0, "move_progress":1}
		_reject(t, sim, "move_room", {"room_id":"room_001", "origin_cell":54, "rotation":0}, "room_busy")
		_reject(t, sim, "remove_room", {"room_id":"room_001"}, "room_busy")
	var state := _state()
	var sim = _sim(state)
	_build(sim, "echo", 104)
	_build(sim, "motion", 108)
	_send(sim, "hire_staff", {"role":"technician"})
	_send(sim, "assign_staff", {"staff_id":"staff_001", "room_id":"room_001"})
	_send(sim, "close_room", {"room_id":"room_001"})
	state.data.queues.room_001 = ["p"]
	_reject(t, sim, "assign_staff", {"staff_id":"staff_001", "room_id":"room_002"}, "staff_busy")
	state.data.queues.room_001.clear()
	state.data.staff.staff_001.phase = "serving"
	state.data.slots["room_001:0"].remaining_ticks = 321
	_reject(t, sim, "assign_staff", {"staff_id":"staff_001", "room_id":"room_002"}, "staff_busy")
	t.expect_equal(_send(sim, "assign_staff", {"staff_id":"staff_001", "room_id":"room_002"}).data.remaining_ticks, 321, "busy rejection reports remaining service time")
	state.data.staff.staff_001.phase = "blocked"
	state.data.slots["room_001:0"].phase = "blocked"
	state.data.slots["room_001:0"].remaining_ticks = 0
	_reject(t, sim, "assign_staff", {"staff_id":"staff_001", "room_id":"room_002"}, "staff_busy")
	state.data.slots["room_001:0"].phase = "free"
	state.data.staff.staff_001.phase = "idle"
	t.expect_true(_send(sim, "assign_staff", {"staff_id":"staff_001", "room_id":"room_002"}).ok, "idle technician may transfer")
	t.expect_equal(state.data.rooms.room_001.staff_id, "", "transfer clears previous assignment")
	_send(sim, "close_room", {"room_id":"room_002"})
	_send(sim, "hire_staff", {"role":"technician"})
	state.data.rooms.room_002.staff_id = ""
	state.data.staff.staff_001.room_id = ""
	state.data.queues.room_002 = ["waiting"]
	t.expect_true(_send(sim, "assign_staff", {"staff_id":"staff_002", "room_id":"room_002"}).ok, "draining room accepts replacement staff")
	_reject(t, sim, "assign_staff", {"staff_id":"staff_001", "room_id":"room_002"}, "room_staffed")

func test_upgrade_preserves_fields_and_does_not_charge_twice(t: TestContext) -> void:
	# Catches losing upgraded=true on replacement and incorrect 75% investment refunds.
	var state := _state()
	var sim = _sim(state)
	_build(sim, "recovery", 140)
	t.expect_true(_send(sim, "upgrade_recovery", {"room_id":"room_001"}).ok, "recovery upgrades while open")
	t.expect_equal(state.data.cash, 7000, "base and upgrade charged once")
	t.expect_equal(state.data.slots.size(), 2, "second authoritative recovery slot")
	_reject(t, sim, "upgrade_recovery", {"room_id":"room_001"}, "already_upgraded")
	_send(sim, "close_room", {"room_id":"room_001"})
	t.expect_true(_send(sim, "move_room", {"room_id":"room_001", "origin_cell":54, "rotation":0}).ok, "move upgraded recovery")
	t.expect_true(state.data.rooms.room_001.upgraded, "move keeps upgraded flag")
	t.expect_equal(state.data.rooms.room_001.status, "draining", "replacement retains business fields")
	t.expect_equal(state.data.slots.size(), 2, "move keeps second seat")
	t.expect_true(_send(sim, "remove_room", {"room_id":"room_001"}).ok, "remove upgraded recovery")
	t.expect_equal(state.data.cash, 7750, "upgrade investment included in refund")
	var poor := _state()
	var poor_sim = _sim(poor)
	_build(poor_sim, "recovery", 140)
	poor.data.cash = 399
	_reject(t, poor_sim, "upgrade_recovery", {"room_id":"room_001"}, "insufficient_cash")
	var occupied := _state()
	var occupied_sim = _sim(occupied)
	_build(occupied_sim, "recovery", 140)
	occupied.data.slots["room_001:0"].patient_id = "p"
	occupied.data.slots["room_001:0"].phase = "serving"
	occupied.data.slots["room_001:0"].remaining_ticks = 123
	t.expect_true(_send(occupied_sim, "upgrade_recovery", {"room_id":"room_001"}).ok, "upgrade preserves occupied first seat")
	t.expect_equal(occupied.data.slots["room_001:0"].remaining_ticks, 123, "upgrade retains clinical service progress")
	t.expect_equal(occupied.data.slots["room_001:0"].patient_id, "p", "upgrade retains patient reservation")

func test_clock_controls_validate_and_speed_does_not_multiply_ticks(t: TestContext) -> void:
	# Catches speed scaling inside simulation, unintended paused progression and invalid types.
	var sim = _sim(_state())
	sim.advance_ticks(20)
	t.expect_equal(sim.snapshot().tick, 0, "paused ticks do not advance")
	_reject(t, sim, "set_speed", {"speed":3}, "invalid_speed")
	_reject(t, sim, "set_speed", {"speed":2.0}, "invalid_speed")
	_reject(t, sim, "set_paused", {"paused":0}, "invalid_payload")
	t.expect_true(_send(sim, "set_speed", {"speed":2}).ok, "speed two stored")
	_send(sim, "set_paused", {"paused":false})
	sim.advance_ticks(7)
	t.expect_equal(sim.snapshot().tick, 7, "two speed still advances requested fixed ticks")
	_send(sim, "set_paused", {"paused":true})
	sim.advance_ticks(10)
	t.expect_equal(sim.snapshot().tick, 7, "pause freezes later advance")
	sim.advance_ticks(-1)
	t.expect_equal(sim.snapshot().tick, 7, "negative tick requests are no op")
	var state := _state()
	var ended = _sim(state)
	state.data.paused = false
	state.data.challenge.status = "failed"
	ended.advance_ticks(10)
	t.expect_equal(state.data.tick, 0, "ended challenge freezes simulation")

func test_ledger_posts_once_and_separates_operating_from_capital(t: TestContext) -> void:
	# Catches duplicate event charging, refund profit inflation and missing metric components.
	var state := _state()
	t.expect_true(ledger_script.post(state, "purchase", "capital_build", -400, 0), "first capital event posted")
	var before := state.to_data()
	t.expect_false(ledger_script.post(state, "purchase", "income", 9999, 0), "event ID deduplicates across category")
	t.expect_equal(state.to_data(), before, "duplicate ledger post is atomic")
	for row in [["sale","income",150],["treat","treatment_cost",-25],["recover","recovery_cost",-10],["pay","wages",-50],["fixed","fixed_cost",-80],["refund","capital_refund",300]]:
		t.expect_true(ledger_script.post(state, row[0], row[1], row[2], 1), "post " + row[1])
	t.expect_equal(state.data.cash, 7885, "ledger is sole cash arithmetic")
	t.expect_equal(state.data.metrics.operating_profit, -15, "only operating categories affect profit")
	t.expect_equal(state.data.metrics.income, 150, "income metric")
	t.expect_equal(state.data.metrics.treatment_cost, 25, "expense metric is positive cost")
	state.data.cash = 0
	t.expect_true(ledger_script.post(state, "debt", "treatment_cost", -25, 2), "operating expense may incur debt")
	t.expect_equal(state.data.cash, -25, "operating spending may be negative")
	before = state.to_data()
	t.expect_false(ledger_script.post(state, "bad", "unknown", 1, 2), "unknown ledger category refused")
	t.expect_equal(state.to_data(), before, "invalid ledger post atomic")

func test_invalid_commands_are_atomic_and_retriable(t: TestContext) -> void:
	# Catches type coercion, premature receipt allocation and committing invalid map previews.
	var sim = _sim(_state())
	for command in [{}, {"id":1,"type":"build_room","payload":{}}, {"id":"","type":"build_room","payload":{}}, {"id":"x","type":1,"payload":{}}, {"id":"x","type":"build_room","payload":[]}]:
		var before: Dictionary = sim.snapshot()
		t.expect_equal(sim.submit(command).code, "invalid_command", "malformed envelope rejected")
		t.expect_equal(sim.snapshot(), before, "malformed command leaves state intact")
	_reject(t, sim, "unknown", {}, "unknown_command")
	_reject(t, sim, "build_room", {"kind":"reception", "origin_cell":193, "rotation":0}, "main_corridor")
	var retry := {"id":"retry", "type":"build_room", "payload":{"kind":"reception", "origin_cell":193, "rotation":0}}
	t.expect_false(sim.submit(retry).ok, "invalid command can be retried")
	retry.payload.origin_cell = 121
	t.expect_true(sim.submit(retry).ok, "rejected ID was not consumed")
	_reject(t, sim, "move_room", {"room_id":1, "origin_cell":54, "rotation":0}, "invalid_payload")
	_send(sim, "close_room", {"room_id":"room_001"})
	_reject(t, sim, "move_room", {"room_id":"room_001", "origin_cell":193, "rotation":0}, "main_corridor")
	_reject(t, sim, "hire_staff", {"role":"wizard"}, "unknown_role")
	_reject(t, sim, "set_auto_route", {"enabled":true, "extra":Vector2(1,2)}, "invalid_command")

func test_ended_challenge_rejects_new_commands_but_replays_receipts(t: TestContext) -> void:
	# Catches capital changes to a frozen challenge while retaining idempotent delivery.
	var state := _state()
	var sim = _sim(state)
	var command := {"id":"before_end", "type":"build_room", "payload":{"kind":"reception", "origin_cell":121, "rotation":0}}
	var receipt: Dictionary = sim.submit(command)
	state.data.challenge.status = "failed"
	t.expect_equal(sim.submit(command), receipt, "ended state still replays committed receipt")
	_reject(t, sim, "hire_staff", {"role":"doctor"}, "challenge_ended")
	_reject(t, sim, "set_paused", {"paused":false}, "challenge_ended")
