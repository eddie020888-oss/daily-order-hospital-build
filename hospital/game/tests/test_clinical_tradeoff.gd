extends "res://tests/test_clinical_decisions.gd"

# Both routes are separate, identical public construction/manual/admission
# fixtures. No clocks, stock, plan, patient or clinical score is injected.
var routes: Array=[]

func route(recheck: bool) -> Dictionary:
	var setup: Dictionary=prepare("manual")
	if setup.is_empty():return {}
	var sim: Simulation=setup.sim
	var id: String=accept_first(sim)
	if id=="" or not gate(sim,id):return {}
	var began: int=int(sim._state.data.tick)
	var stock_before: int=int(sim._state.data.resources.get("delivered",0))
	var ledger_start: int=sim._state.data.ledger_entries.size()
	var history_start: int=sim._state.data.patients[id].step_history.size()
	check(int(preview(sim,id).confidence)==77,"same untrained real C1 first examination confidence")
	if recheck:
		var first: Dictionary=preview(sim,id)
		if not issue(sim,"clinical_decision",{"patient_id":id,"action":"continue_exam","expected_revision":first.revision}).get("ok",false):return {}
		if not gate(sim,id):return {}
	var ready: Dictionary=preview(sim,id)
	if not issue(sim,"clinical_decision",{"patient_id":id,"action":"cautious_treat","expected_revision":ready.revision}).get("ok",false):return {}
	if not drive(sim,func(d: Dictionary)->bool:return d.patients[id].phase=="left",2200,"actual chosen route treatment and departure"):return {}
	var p: Dictionary=sim._state.data.patients[id]
	var work: int=0
	var history: Array=[]
	for n: int in range(history_start,p.step_history.size()):
		var h: Dictionary=p.step_history[n]
		work+=int(h.completed_tick)-int(h.started_tick)
		history.append(h.duplicate(true))
	var cost: int=0
	var ledger: Array=[]
	for n: int in range(ledger_start,sim._state.data.ledger_entries.size()):
		var row: Dictionary=sim._state.data.ledger_entries[n]
		if row.category=="treatment_cost" and str(row.reference).begins_with("care:"+id+":"):
			cost-=int(row.amount);ledger.append(row.duplicate(true))
	var report: Dictionary={"route":"recheck_then_treat" if recheck else "cautious_then_remedy","started_tick":began,"ended_tick":int(sim._state.data.tick),"actual_elapsed_ticks":int(sim._state.data.tick)-began,"actual_service_ticks":work,"actual_care_cost":cost,"actual_delivered_consumed":stock_before-int(sim._state.data.resources.get("delivered",0)),"history":history,"care_ledger":ledger,"snapshot":sim.snapshot()}
	check(p.outcome=="completed" and int(sim._state.data.metrics.completed)==1 and sim._state.data.metrics.abandoned==0,"route is a real successful cure")
	check(SnapshotValidator.validate(sim.snapshot(),catalog)=="","route strict snapshot and historical money/stock",SnapshotValidator.validate(sim.snapshot(),catalog))
	routes.append(report)
	return report

func _run() -> void:
	if not output.begins_with("E:/CODEX/") or output.simplify_path()!=output or FileAccess.file_exists(output):
		printerr("Require fresh E:/CODEX output");quit(2);return
	var loaded: Dictionary=ContentCatalog.load_checked("res://content")
	check(bool(loaded.get("ok",false)),"real catalog loads",str(loaded.get("error","")))
	if loaded.get("ok",false):
		catalog=loaded.catalog
		decisions=load("res://campaign/campaign_clinical_decisions.gd")
		if decisions!=null:
			var checked: Dictionary=route(true)
			var cautious: Dictionary=route(false)
			if not checked.is_empty() and not cautious.is_empty():
				check(checked.actual_care_cost==22 and checked.actual_service_ticks==208,"real extra exam route costs 22 and 208 service ticks")
				check(cautious.actual_care_cost==28 and cautious.actual_service_ticks==124,"real cautious route costs 28 and 124 service ticks")
				check(cautious.actual_care_cost>checked.actual_care_cost and cautious.actual_service_ticks<checked.actual_service_ticks,"cautious is genuinely more expensive and faster in actual work")
				check(cautious.actual_elapsed_ticks<checked.actual_elapsed_ticks,"cautious also reaches real exit sooner with matching geometry")
				check(checked.actual_delivered_consumed==2 and cautious.actual_delivered_consumed==2,"both routes consume the same two real units after initial examination")
				var remedy: Dictionary=cautious.history[-1]
				check(str(remedy.step_id).ends_with(":decision:remedy") and remedy.cost==17 and remedy.planned_duration==20 and remedy.completed_tick-remedy.started_tick==20,"remedy uses published deficit-only 17 cost and 20 actual ticks")
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	var file:=FileAccess.open(output,FileAccess.WRITE)
	if file==null:quit(2);return
	file.store_string(JSON.stringify({"ok":failed==0,"passed":passed,"failed":failed,"checks":checks,"routes":routes,"scope":"Two independent real public C1 manual clinical paths; state snapshots are observed outputs only"},"\t"));file.close()
	print("CLINICAL TRADEOFF RESULT passed="+str(passed)+" failed="+str(failed))
	quit(0 if failed==0 else 1)
