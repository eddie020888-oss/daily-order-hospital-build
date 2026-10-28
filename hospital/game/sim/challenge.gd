class_name Challenge
extends RefCounted

# Called after service completion, movement/actual exits, patience and arrivals.
static func after_tick(state: ClinicState, catalog: ContentCatalog) -> void:
	var d := state.data
	if d.challenge.status != "running":
		return
	var level: Dictionary = catalog.levels[d.level_id]
	_payroll(state,catalog,level)
	# A repeated callback at the same tick must not count bankruptcy time twice.
	if d.get("last_business_tick",-1) != d.tick:
		d.negative_cash_ticks = d.negative_cash_ticks+1 if d.cash < 0 else 0
		d.last_business_tick = d.tick
	var scenario: String = d.get("scenario_id","level_01")
	if scenario == "load_40":
		Scenarios.replenish_load(state,catalog)
		if d.tick >= 18000:
			_end(state,"finished","load_horizon")
		return
	# The benchmark is a fixed-horizon experiment; no bankruptcy or early outcome
	# may cut one strategy short or remove its unfinished patients from comparison.
	if scenario == "benchmark_18":
		if d.tick >= level.end_tick:
			_end(state,"finished","benchmark_horizon")
		return
	if d.negative_cash_ticks >= level.negative_cash_limit_ticks:
		_end(state,"lost","bankruptcy")
		return
	var counts := _counts(state)
	if d.tick >= level.end_tick or (d.arrival_cursor == d.scheduled_arrivals.size() and counts.active == 0):
		var goal: Dictionary = level.get("goal",{"completed_min":30,"abandoned_max":6,"operating_profit_min":0,"cash_min":0,"require_all_departed":false})
		var won: bool = d.metrics.completed >= goal.completed_min and d.cash >= goal.cash_min
		if goal.has("abandoned_max"): won = won and d.metrics.abandoned <= goal.abandoned_max
		if goal.has("operating_profit_min"): won = won and d.metrics.operating_profit >= goal.operating_profit_min
		if goal.require_all_departed: won = won and counts.active == 0 and d.arrival_cursor == d.scheduled_arrivals.size()
		_end(state,"won" if won else "lost","time_limit" if d.tick >= level.end_tick else "all_departed")
		return
	for unlock in level.unlocks:
		var key: String = "unlock_"+unlock.room_kind
		if d.tick >= unlock.tick and not d.hint_flags.get(key,false):
			if unlock.room_kind not in d.unlocked_room_kinds:
				d.unlocked_room_kinds.append(unlock.room_kind)
			d.hint_flags[key] = true
			if not d.hint_flags.get("disabled",false):
				d.hint_flags.pending = key
				d.paused = true

static func _payroll(state: ClinicState, catalog: ContentCatalog, level: Dictionary) -> void:
	var d := state.data
	if d.tick <= 0 or d.tick % level.day_ticks != 0 or d.last_payroll_tick >= d.tick:
		return
	var wages := 0
	for employee in d.staff.values():
		wages += catalog.staff[employee.role].daily_wage
	Ledger.post(state,"wages:"+str(d.tick),"wages",-wages,d.tick)
	Ledger.post(state,"fixed_cost:"+str(d.tick),"fixed_cost",-level.fixed_daily_cost,d.tick)
	d.last_payroll_tick = d.tick

static func _counts(state: ClinicState) -> Dictionary:
	var active := 0
	for p in state.data.patients.values():
		if p.phase not in ["completed","abandoned"]:
			active += 1
	return {"active":active}

static func _end(state: ClinicState, status: String, reason: String) -> void:
	state.data.challenge = {"status":status,"reason":reason,"ended_tick":state.data.tick}
	state.data.paused = true
