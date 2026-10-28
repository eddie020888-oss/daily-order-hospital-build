extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var output:=""
	var source:=""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("output="): output=arg.trim_prefix("output=")
		if arg.begins_with("source="): source=arg.trim_prefix("source=")
	if not output.replace("\\","/").begins_with("E:/CODEX/"):
		push_error("Benchmark evidence must stay on E drive")
		quit(1)
		return
	var t:=TestContext.new()
	var catalog: ContentCatalog=ContentCatalog.load_checked("res://content").catalog
	var evidence:={"recorded_at_utc":Time.get_datetime_string_from_system(true),"content_version":catalog.content_version,"source_commit":source,"engine":Engine.get_version_info(),"horizon_ticks":9000,"step_milliseconds":100,"scenario":"benchmark_18","initial_budget":8000,"parameters_changed":[],"layouts":{"standard":Scenarios.STANDARD,"longer_walk":Scenarios.LONGER_WALK},"configurations":{}}
	for layout in ["standard","longer_walk"]:
		for strategy in ["fast","tolerance"]:
			var sim:=Scenarios.create_sim(catalog,"benchmark_18",strategy,layout)
			var initial:=sim.snapshot()
			t.expect_equal(initial.cash,1600,"common actual paid setup cash: "+layout+"/"+strategy)
			t.expect_equal(initial.staff.size(),5,"common five employees")
			sim.advance_ticks(9000)
			var snapshot:=sim.snapshot()
			t.expect_equal(snapshot.tick,9000,"full horizon")
			t.expect_equal(snapshot.patients.size(),18,"whole patient history")
			var state:=ClinicState.new()
			state.data=snapshot
			var summary:=Metrics.summary(state)
			t.expect_equal(summary.patients.size(),18,"all18 per-patient disposition rows")
			var total:=0
			for key in ["not_arrived","outside","in_hospital","completed","abandoned"]: total+=int(summary.dispositions[key])
			t.expect_equal(total,18,"exclusive dispositions conserve all18")
			evidence.configurations[layout+"/"+strategy]={"initial_snapshot":initial,"summary":summary,"snapshot":snapshot}
	var fast: Dictionary=evidence.configurations["standard/fast"].summary
	var route: Dictionary=evidence.configurations["standard/tolerance"].summary
	var longer: Dictionary=evidence.configurations["longer_walk/tolerance"].summary
	var conditions:={"waiting_reduction_at_least_20_percent":route.waiting_sum_ticks*5<=fast.waiting_sum_ticks*4,"completed_not_fewer":route.completed>=fast.completed,"abandoned_not_more":route.abandoned<=fast.abandoned,"profit_not_lower":route.operating_profit>=fast.operating_profit,"standard_less_walking":route.walked_cells<longer.walked_cells,"layout_improves_wait_or_visit":route.waiting_mean_ticks<longer.waiting_mean_ticks or route.visit_mean_ticks<longer.visit_mean_ticks,"same_arrivals_all_configurations":true}
	for config in evidence.configurations.values():
		conditions.same_arrivals_all_configurations=conditions.same_arrivals_all_configurations and config.snapshot.scheduled_arrivals==evidence.configurations["standard/fast"].snapshot.scheduled_arrivals
	for condition in conditions: t.expect_true(conditions[condition],condition)
	evidence.acceptance=conditions
	evidence.waiting_reduction_fraction=1.0-float(route.waiting_sum_ticks)/fast.waiting_sum_ticks
	evidence.test_result={"failed":t.failed,"passed":t.passed}
	var file:=FileAccess.open(output,FileAccess.WRITE)
	file.store_string(JSON.stringify(evidence,"  "))
	file.close()
	print("BENCHMARK RESULT: "+JSON.stringify({"output":output,"acceptance":conditions,"wait_reduction":evidence.waiting_reduction_fraction,"failed":t.failed,"passed":t.passed}))
	quit(0 if t.failed==0 else 1)
