class_name ClinicState
extends RefCounted

var data: Dictionary = {}

static func create(level_id: String, catalog: ContentCatalog) -> ClinicState:
	if not catalog.levels.has(level_id):
		return null
	if catalog.levels[level_id].get("ruleset","")=="full-hospital-v2": return LongCampaignState.create(level_id,catalog)
	if CampaignContent.is_campaign(catalog.levels[level_id]): return CampaignState.create(level_id,catalog)
	var level: Dictionary = catalog.levels[level_id]
	var state := ClinicState.new()
	state.data = {
		"schema_version": 1,
		"content_version": catalog.content_version,
		"level_id": level_id,
		"scenario_id": level_id,
		"scenario_strategy": "fast",
		"scenario_layout": "standard",
		"tick": 0,
		"paused": true,
		"speed": 1,
		"next_ids": {"room": 1, "staff": 1, "patient": level.arrivals.size() + 1},
		"command_sequence": 0,
		"map_revision": 0,
		"auto_route": false,
		"unlocked_room_kinds": level.initial_unlocked_room_kinds.duplicate(),
		"cash": level.initial_cash,
		"rooms": {},
		"staff": {},
		"patients": {},
		"slots": {},
		"queues": {},
		"scheduled_arrivals": level.arrivals.duplicate(true),
		"arrival_cursor": 0,
		"outside_queue": [],
		"ledger_entries": [],
		"command_receipts": {},
		"negative_cash_ticks": 0,
		"last_payroll_tick": 0,
		"last_business_tick": -1,
		"hint_flags": {},
		"challenge": {"status": "running", "reason": "", "ended_tick": -1},
		"metrics": {
			"completed": 0, "abandoned": 0, "operating_profit": 0,
			"income": 0, "treatment_cost": 0, "recovery_cost": 0,
			"wages": 0, "fixed_cost": 0, "wait_ticks": {}, "patient_totals": {}
		}
	}
	return state

func to_data() -> Dictionary:
	return data.duplicate(true)

static func from_data(snapshot: Dictionary, catalog: ContentCatalog) -> Dictionary:
	var error := SnapshotValidator.validate(snapshot,catalog)
	if error != "":
		return {"ok":false,"state":null,"error":error,"used_backup":false}
	var state := ClinicState.new()
	state.data = snapshot.duplicate(true)
	return {"ok":true,"state":state,"error":"","used_backup":false}
