extends RefCounted

var catalog: ContentCatalog
var sequence := 0

func run(t: TestContext) -> void:
	catalog = ContentCatalog.load_checked("res://content").catalog
	test_tick_9000_order_keeps_income_wages_and_36_dispositions_consistent(t)
	test_bankruptcy_requires_1200_consecutive_negative_ticks_and_resets(t)
	test_unlock_pause_at_2400_and_4800_occurs_once(t)
	test_equivalent_command_replays_match_at_equal_tick(t)
	test_metrics_include_outside_active_and_abandoned(t)
	test_early_outcome_requires_all_arrived_and_no_inside_or_outside(t)
	if not FileAccess.file_exists("res://sim/scenarios.gd"):
		t.expect_true(false,"Scenarios provides real benchmark/layout/load setups")
		return
	test_benchmark_runs_both_strategies_to_tick_9000(t)
	test_layout_changes_real_walk_distance(t)
	test_load_40_replenishes_stable_ids_for_18000_ticks(t)
	test_scenario_inputs_and_player_level(t)
	test_player_scenario_strategy_initializes_new_room_modes(t)

func _send(sim: Simulation, type: String, payload: Dictionary) -> Dictionary:
	sequence += 1
	return sim.submit({"id":"challenge_%d" % sequence,"type":type,"payload":payload})

func _fixture() -> Dictionary:
	var state := ClinicState.create("level_01",catalog)
	return {"state":state,"sim":Simulation.new(catalog,state)}

func _summary(state: ClinicState) -> Dictionary:
	if not FileAccess.file_exists("res://sim/metrics.gd"):
		return {}
	return load("res://sim/metrics.gd").summary(state)

func test_tick_9000_order_keeps_income_wages_and_36_dispositions_consistent(t: TestContext) -> void:
	# Catches business before actual exit, wrong payroll boundary, or fabricated terminals.
	var f := _fixture()
	f.state.data.tick = 8999
	f.state.data.last_payroll_tick = 8400
	f.state.data.arrival_cursor = 36
	f.state.data.patients = {
		"patient_001":{"id":"patient_001","disease_id":"echo","tolerance":70,"arrival_tick":200,"admitted_tick":200,"exit_tick":-1,"abandon_tick":-1,"phase":"leaving","stage":"exit","wait_ticks":10,"wait_by_stage":{"exit":10},"services_complete":true,"treatment_started":true,"cell":216,"path":[216],"path_index":0,"move_progress":0,"walked_cells":2,"slot_id":"","room_id":""},
		"patient_002":{"id":"patient_002","disease_id":"echo","tolerance":70,"arrival_tick":400,"admitted_tick":400,"exit_tick":-1,"abandon_tick":-1,"phase":"reception_queue","stage":"reception","wait_ticks":1799,"wait_by_stage":{"reception":1799},"services_complete":false,"treatment_started":false,"cell":217,"path":[217],"path_index":0,"move_progress":0,"walked_cells":0,"slot_id":"","room_id":"","queue_enter_tick":8999}}
	# The other 34 IDs have already completed; all 36 remain individually traceable.
	for i in range(3,37):
		f.state.data.patients["patient_%03d" % i] = {"id":"patient_%03d" % i,"phase":"completed","arrival_tick":1,"admitted_tick":1,"exit_tick":2,"wait_ticks":1,"wait_by_stage":{"exit":1},"walked_cells":0}
	for p in f.state.data.patients.values():
		p.wait_reason = ""
	f.state.data.metrics.completed = 34
	f.state.data.staff = {"staff_001":{"role":"doctor","room_id":"","phase":"idle","path":[],"path_index":0,"move_progress":0}}
	f.state.data.cash = -100
	f.state.data.negative_cash_ticks = 1199
	f.state.data.paused = false
	f.sim.advance_ticks(1)
	t.expect_equal(f.state.data.metrics.income,150,"valid exit income precedes business outcome")
	t.expect_equal(f.state.data.metrics.wages,0,"9000 is not a 1200-tick payroll boundary")
	t.expect_equal(f.state.data.negative_cash_ticks,0,"income resets bankruptcy counter before deadline")
	t.expect_equal(f.state.data.patients.patient_002.phase,"abandoning","same tick patience intent remains inside")
	t.expect_equal(f.state.data.challenge.status,"won","deadline evaluates final income and actual completions")
	var summary := _summary(f.state)
	t.expect_equal(summary.get("dispositions",{}),{"not_arrived":0,"outside":0,"in_hospital":1,"completed":35,"abandoned":0,"abandoning":1},"all 36 mutually exclusive dispositions; abandoning is inside subset")
	var frozen: Dictionary = f.sim.snapshot()
	f.sim.advance_ticks(100)
	t.expect_true(f.sim.snapshot() == frozen,"outcome freezes unfinished actor and all business")
	# At a true payroll boundary income still arrives first, then one current-staff bill.
	var pay := _fixture()
	pay.state.data.tick = 1199
	pay.state.data.staff = f.state.data.staff.duplicate(true)
	pay.state.data.paused = false
	pay.sim.advance_ticks(1)
	t.expect_equal(pay.state.data.cash,7870,"one doctor wage50 plus fixed80")
	t.expect_equal(pay.state.data.metrics.operating_profit,-130,"Ledger owns expense metric once")
	if FileAccess.file_exists("res://sim/challenge.gd"):
		load("res://sim/challenge.gd").after_tick(pay.state,catalog)
		t.expect_equal(pay.state.data.cash,7870,"same boundary callback cannot double-bill")
		var restored := ClinicState.new()
		restored.data = pay.sim.snapshot()
		load("res://sim/challenge.gd").after_tick(restored,catalog)
		t.expect_equal(restored.data.cash,7870,"reload cannot double-bill")

func test_bankruptcy_requires_1200_consecutive_negative_ticks_and_resets(t: TestContext) -> void:
	# Catches off-by-one and retaining negative time after any nonnegative step.
	var f := _fixture()
	f.state.data.cash = -1
	f.state.data.paused = false
	f.sim.advance_ticks(1199)
	t.expect_equal(f.state.data.challenge.status,"running","1199 negative ticks still running")
	t.expect_equal(f.state.data.negative_cash_ticks,1199,"all negative intervals counted")
	f.state.data.cash = 1000
	f.sim.advance_ticks(1)
	t.expect_equal(f.state.data.negative_cash_ticks,0,"nonnegative interval resets counter after payroll")
	f.state.data.cash = -1
	f.sim.advance_ticks(1199)
	t.expect_equal(f.state.data.challenge.status,"running","new negative run starts from zero")
	f.sim.advance_ticks(1)
	t.expect_equal(f.state.data.challenge.status,"lost","exact1200 negative ticks fail")
	t.expect_equal(f.state.data.challenge.reason,"bankruptcy","bankruptcy reason stable")
	t.expect_equal(f.state.data.challenge.ended_tick,2400,"bankruptcy takes priority over unlock pause")

func test_unlock_pause_at_2400_and_4800_occurs_once(t: TestContext) -> void:
	# Catches repeated pause or initial locked rooms becoming player-buildable too early.
	var f := _fixture()
	f.state.data.paused = false
	f.sim.advance_ticks(3000)
	t.expect_equal(f.state.data.tick,2400,"motion hint pauses exactly at2400")
	t.expect_true("motion" in f.state.data.unlocked_room_kinds,"motion actually unlocked")
	t.expect_true(f.state.data.paused,"unlock is a real pause")
	_send(f.sim,"set_paused",{"paused":false})
	f.sim.advance_ticks(3000)
	t.expect_equal(f.state.data.tick,4800,"sensory hint pauses exactly at4800 once")
	_send(f.sim,"set_paused",{"paused":false})
	f.sim.advance_ticks(1)
	t.expect_equal(f.state.data.tick,4801,"unlocks do not repeat after resume")
	t.expect_true("sensory" in f.state.data.unlocked_room_kinds,"sensory unlocked")

func test_equivalent_command_replays_match_at_equal_tick(t: TestContext) -> void:
	# Catches display-call chunking/speed changing fixed-step behavior.
	var a := _fixture()
	var b := _fixture()
	for f in [a,b]:
		f.sim.submit({"id":"start","type":"set_paused","payload":{"paused":false}})
	a.sim.advance_ticks(300)
	for _i in range(100):
		b.sim.advance_ticks(3)
	for f in [a,b]:
		f.sim.submit({"id":"pause","type":"set_paused","payload":{"paused":true}})
	b.sim.advance_ticks(500)
	for f in [a,b]:
		f.sim.submit({"id":"speed","type":"set_speed","payload":{"speed":2}})
		f.sim.submit({"id":"resume","type":"set_paused","payload":{"paused":false}})
	a.sim.advance_ticks(300)
	for _i in range(50):
		b.sim.advance_ticks(6)
	t.expect_equal(a.sim.snapshot(),b.sim.snapshot(),"same simulated tick commands yield identical full state")

func test_metrics_include_outside_active_and_abandoned(t: TestContext) -> void:
	# Catches successful-patients-only denominator and lost unfinished/outside waiting.
	var f := _fixture()
	f.state.data.arrival_cursor = 4
	f.state.data.patients = {
		"a":{"phase":"completed","wait_ticks":10,"wait_by_stage":{"exit":10}},
		"b":{"phase":"outside","wait_ticks":50,"wait_by_stage":{"outside":50}},
		"c":{"phase":"treatment_queue","wait_ticks":30,"wait_by_stage":{"treatment":30}},
		"d":{"phase":"abandoned","wait_ticks":70,"wait_by_stage":{"reception":70}}}
	var s := _summary(f.state)
	t.expect_equal(s.get("arrived_count"),4,"denominator includes all four arrived patients")
	t.expect_equal(s.get("waiting_sum_ticks"),160,"waiting numerator includes all outcomes")
	t.expect_equal(s.get("waiting_mean_ticks"),40.0,"fair wait mean")
	var empty := _summary(_fixture().state)
	t.expect_equal(empty.get("waiting_mean_ticks"),0.0,"no arrival mean is defined zero")

func test_early_outcome_requires_all_arrived_and_no_inside_or_outside(t: TestContext) -> void:
	# Catches outcome based solely on completion count while actors remain.
	var f := _fixture()
	f.state.data.scheduled_arrivals = [{"id":"last","tick":10,"disease_id":"echo","tolerance":70}]
	f.state.data.paused = false
	f.sim.advance_ticks(9)
	t.expect_equal(f.state.data.challenge.status,"running","future arrivals prevent early outcome")
	f.sim.advance_ticks(1802)
	t.expect_equal(f.state.data.challenge.status,"lost","no remaining inside/outside permits early result")
	t.expect_equal(f.state.data.challenge.reason,"all_departed","early result reason")
	t.expect_equal(f.state.data.challenge.ended_tick,1811,"intention at1810; actual exit next step determines early end")

func _scenario(id: String, strategy: String = "fast", layout: String = "standard") -> Simulation:
	return load("res://sim/scenarios.gd").create_sim(catalog,id,strategy,layout)

func _sim_summary(sim: Simulation) -> Dictionary:
	var state := ClinicState.new()
	state.data = sim.snapshot()
	return _summary(state)

func test_benchmark_runs_both_strategies_to_tick_9000(t: TestContext) -> void:
	# Catches weakened threshold, selective patient reporting or early benchmark termination.
	var fast_sim := _scenario("benchmark_18")
	var tolerance_sim := _scenario("benchmark_18","tolerance")
	if fast_sim == null or tolerance_sim == null:
		t.expect_true(false,"both benchmark scenarios created")
		return
	for sim in [fast_sim,tolerance_sim]:
		var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/benchmark_18.json"))
		for arrival in fixture.arrivals:
			arrival.tick = int(arrival.tick)
			arrival.tolerance = int(arrival.tolerance)
		t.expect_equal(sim.snapshot().scheduled_arrivals,fixture.arrivals,"all18 exact fixed arrival inputs")
		t.expect_equal(sim.snapshot().cash,1600,"paid six facilities and five hires")
		t.expect_equal(sim.snapshot().staff.size(),5,"same five employees")
		sim.advance_ticks(9000)
		t.expect_equal(sim.snapshot().tick,9000,"fixed comparison horizon")
		t.expect_equal(sim.snapshot().arrival_cursor,18,"all18 arrivals retained")
	var fast := _sim_summary(fast_sim)
	var tolerance := _sim_summary(tolerance_sim)
	t.expect_true(tolerance.waiting_mean_ticks <= fast.waiting_mean_ticks * 0.8,"20 percent lower wait")
	t.expect_true(tolerance.completed >= fast.completed,"no completion regression")
	t.expect_true(tolerance.abandoned <= fast.abandoned,"no abandonment regression")
	t.expect_true(tolerance.operating_profit >= fast.operating_profit,"no profit regression")
	var result := {"recorded_at_utc":Time.get_datetime_string_from_system(true),"horizon_ticks":9000,"content_version":catalog.content_version,"layout":"standard","parameters_changed":[],"fast":{"summary":fast,"snapshot":fast_sim.snapshot()},"tolerance":{"summary":tolerance,"snapshot":tolerance_sim.snapshot()}}
	var stamp := Time.get_datetime_string_from_system(true).replace(":","-")
	var path := "res://../reports/implementation/benchmark-18-"+stamp+"-"+str(Time.get_ticks_usec())+".json"
	var file := FileAccess.open(path,FileAccess.WRITE)
	t.expect_true(file != null,"benchmark full evidence file opens")
	if file != null:
		file.store_string(JSON.stringify(result,"\t"))
		file.close()
	print("BENCHMARK: "+JSON.stringify({"fast":fast,"tolerance":tolerance,"evidence":path}))

func test_layout_changes_real_walk_distance(t: TestContext) -> void:
	# Catches geometry-only layout changes that do not affect actual actor travel/time.
	var near := _scenario("benchmark_18","tolerance")
	var far := _scenario("benchmark_18","tolerance","longer_walk")
	if near == null or far == null:
		t.expect_true(false,"both legal layouts created")
		return
	near.advance_ticks(9000)
	far.advance_ticks(9000)
	var a := _sim_summary(near)
	var b := _sim_summary(far)
	t.expect_equal(near.snapshot().scheduled_arrivals,far.snapshot().scheduled_arrivals,"layout holds patient inputs constant")
	t.expect_true(a.walked_cells < b.walked_cells,"standard layout reduces real walking")
	t.expect_true(a.waiting_mean_ticks < b.waiting_mean_ticks or a.visit_mean_ticks < b.visit_mean_ticks,"layout improves measured wait or visit time")
	var path := "res://../reports/implementation/layout-"+Time.get_datetime_string_from_system(true).replace(":","-")+"-"+str(Time.get_ticks_usec())+".json"
	var evidence := FileAccess.open(path,FileAccess.WRITE)
	t.expect_true(evidence != null,"layout evidence opens")
	if evidence != null:
		evidence.store_string(JSON.stringify({"recorded_at_utc":Time.get_datetime_string_from_system(true),"strategy":"tolerance","horizon_ticks":9000,"standard":{"summary":a,"snapshot":near.snapshot()},"longer_walk":{"summary":b,"snapshot":far.snapshot()}},"\t"))
		evidence.close()

func test_load_40_replenishes_stable_ids_for_18000_ticks(t: TestContext) -> void:
	# Catches decaying load, reused IDs, gameplay pauses/bankruptcy and premature horizon.
	var sim := _scenario("load_40","tolerance")
	if sim == null:
		t.expect_true(false,"load scenario created")
		return
	t.expect_equal(sim.snapshot().staff.size(),8,"load has exact eight staff")
	t.expect_equal(_sim_summary(sim).dispositions.in_hospital,40,"load starts with40 inside at tick0")
	# Public snapshot rehydration gives the test an owned state for inspecting each
	# step without making 18000 deep copies of the growing historical evidence.
	var state := ClinicState.new()
	state.data = sim.snapshot()
	state.data.cash = -100000
	sim = Simulation.new(catalog,state)
	var exact := true
	var no_outside := true
	for _i in range(18000):
		sim.advance_ticks(1)
		var inside := 0
		for p in state.data.patients.values():
			if p.has("cell"):
				inside += 1
		exact = exact and inside == 40
		no_outside = no_outside and state.data.outside_queue.is_empty()
	t.expect_true(exact,"every load step preserves40 actual inside actors")
	t.expect_true(no_outside,"load does not silently build an outside backlog")
	t.expect_equal(sim.snapshot().tick,18000,"full30 minute simulated horizon")
	t.expect_equal(sim.snapshot().challenge.status,"finished","load ends only at18000")
	t.expect_true(sim.snapshot().patients.size()>40,"terminal actors replaced with new identities")
	t.expect_equal(sim.snapshot().next_ids.patient,sim.snapshot().patients.size()+1,"monotonic stable IDs never reused")
	var evidence_path := "res://../reports/implementation/load40-"+Time.get_datetime_string_from_system(true).replace(":","-")+"-"+str(Time.get_ticks_usec())+".json"
	var evidence := FileAccess.open(evidence_path,FileAccess.WRITE)
	t.expect_true(evidence != null,"load evidence opens")
	if evidence != null:
		evidence.store_string(JSON.stringify({"recorded_at_utc":Time.get_datetime_string_from_system(true),"simulated_horizon_ticks":18000,"initial_cash_override_for_bankruptcy_test":-100000,"every_tick_exact40":exact,"no_outside_backlog":no_outside,"summary":Metrics.summary(state),"snapshot":sim.snapshot()},"\t"))
		evidence.close()
	print("LOAD40: "+JSON.stringify({"tick":state.data.tick,"retained_patient_records":state.data.patients.size(),"next_patient_id":state.data.next_ids.patient,"exact40_each_tick":exact,"evidence":evidence_path}))
	var frozen := sim.snapshot()
	sim.advance_ticks(1)
	t.expect_equal(sim.snapshot(),frozen,"load also freezes exactly at horizon")

func test_scenario_inputs_and_player_level(t: TestContext) -> void:
	var player := _scenario("level_01")
	t.expect_true(player.snapshot().paused,"normal player starts paused")
	t.expect_equal(player.snapshot().rooms.size(),0,"normal player builds own rooms")
	t.expect_equal(player.snapshot().scheduled_arrivals.size(),36,"normal36 fixed arrivals")
	t.expect_equal(player.snapshot().cash,8000,"normal player retains initial budget")
	t.expect_equal(_scenario("unknown"),null,"unknown scenario rejected")
	t.expect_equal(_scenario("benchmark_18","unknown"),null,"unknown strategy rejected")
	t.expect_equal(_scenario("benchmark_18","fast","unknown"),null,"unknown layout rejected")

func test_player_scenario_strategy_initializes_new_room_modes(t: TestContext) -> void:
	# Catches a requested gentle strategy silently becoming fast when player builds.
	for strategy in ["fast","gentle","tolerance"]:
		var sim := _scenario("level_01",strategy)
		var result := _send(sim,"build_room",{"kind":"echo","origin_cell":104,"rotation":0})
		t.expect_true(result.ok,"player can build initial echo paused")
		t.expect_equal(sim.snapshot().rooms[result.data.room_id].mode,"gentle" if strategy == "gentle" else "fast","requested strategy initializes future treatment room")
		t.expect_equal(sim.snapshot().auto_route,strategy == "tolerance","tolerance retains explicit routing toggle")
	var state := ClinicState.create("level_01",catalog)
	state.data.erase("scenario_strategy")
	var legacy := Simulation.new(catalog,state)
	var built := _send(legacy,"build_room",{"kind":"echo","origin_cell":104,"rotation":0})
	t.expect_equal(legacy.snapshot().rooms[built.data.room_id].mode,"fast","missing scenario strategy keeps existing default")
