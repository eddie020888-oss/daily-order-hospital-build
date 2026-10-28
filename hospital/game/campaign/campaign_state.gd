class_name CampaignState
extends RefCounted

const RULESET := "full-hospital-v1"
const INITIAL_RESOURCES := {"supplies":40,"sterile":8,"blood":4,"samples":0,"prepared":0,"waste":0,"water":20,"food":20,"spares":6}

static func create(level_id: String,catalog: ContentCatalog) -> ClinicState:
	if not catalog.levels.has(level_id) or catalog.levels[level_id].get("ruleset","")!=RULESET: return null
	var level: Dictionary=catalog.levels[level_id]
	var state := ClinicState.new()
	state.data={
		"schema_version":2,"content_version":catalog.content_version,"ruleset":RULESET,
		"level_id":level_id,"scenario_id":level_id,"scenario_strategy":"campaign","scenario_layout":"custom",
		"tick":0,"paused":true,"speed":1,"appearance_seed":1,
		"next_ids":{"room":1,"staff":1,"patient":1,"facility":1,"work_order":1},
		"command_sequence":0,"map_revision":0,"auto_route":false,
		"unlocked_room_kinds":level.get("initial_unlocked_room_kinds",[]).duplicate(),
		"cash":level.initial_cash,"rooms":{},"facilities":{},"staff":{},"patients":{},"slots":{},"queues":{},
		"scheduled_arrivals":[],"arrival_cursor":0,"outside_queue":[],
		"work_orders":{},"resources":INITIAL_RESOURCES.duplicate(true),
		"ledger_entries":[],"command_receipts":{},"negative_cash_ticks":0,"last_payroll_tick":0,"last_business_tick":-1,"hint_flags":{},
		"challenge":{"status":"running","reason":"","ended_tick":-1},
		"metrics":{"completed":0,"abandoned":0,"operating_profit":0,"income":0,"treatment_cost":0,"recovery_cost":0,"wages":0,"fixed_cost":0,"expenses":{},"wait_ticks":{},"patient_totals":{}},
		"evidence":{"facilities":{},"cases":{},"audits":{},"events":{},"diseases":{}},
		"campaign":{"wave_index":0,"wave_active":false,"current_case_id":"","completed_cases":[],"completed_waves":[],"price_percent":100,"loan":0,"reputation":50,"research":[],"training":[],"events":[],"audits":{},"career":{"completed_levels":[],"receipts":{}}}
	}
	return state
