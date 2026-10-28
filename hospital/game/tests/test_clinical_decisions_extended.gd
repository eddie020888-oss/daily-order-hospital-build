extends "res://tests/test_clinical_decisions.gd"

# Additional real public scenarios; the RED also guards the one-build timeline
# entry point, whose returned policies are checked against actual receipts.
func stock(sim: Simulation) -> bool:
	var r: Dictionary=issue(sim,"run_operation",{"facility_kind":"O15"})
	if not r.get("ok",false):return false
	return drive(sim,func(d: Dictionary)->bool:return d.work_orders[r.data.work_order_id].status=="done",1200,"additional paid physical delivery")

func finish_balanced_first(sim: Simulation) -> String:
	var id: String=accept_first(sim)
	if id=="":return ""
	if not drive(sim,func(d: Dictionary)->bool:return d.patients[id].phase=="left",2600,"first signature under normal balanced policy"):return ""
	return id

func thorough_two_exams() -> void:
	var setup: Dictionary=prepare("balanced")
	if setup.is_empty():return
	var sim: Simulation=setup.sim
	if finish_balanced_first(sim)=="":return
	if build(sim,"U01-E2",121)=="" or not stock(sim):return
	issue(sim,"set_clinical_policy",{"policy":"thorough"})
	var admitted: Dictionary=issue(sim,"accept_case",{"case_id":"U01-C2"})
	if not admitted.get("ok",false):return
	var id: String=admitted.data.patient_ids[0]
	if not drive(sim,func(d: Dictionary)->bool:return d.patients[id].phase=="left",3200,"thorough C2 completes two real extra examinations"):return
	var p: Dictionary=sim._state.data.patients[id]
	check(int(preview(sim,id).get("completed_exams",-1))==2 and p.step_history.size()==5,"C2 73 then 91 then 100 uses max two repeats and original suffix")
	var receipts: Array=p.clinical_decision.receipts
	check(receipts.size()==3 and receipts[0].confidence==73 and receipts[1].confidence==91 and receipts[2].confidence==100 and receipts[2].action=="cautious_treat","thorough 95 target differs from balanced 80 using actual histories")
	check(sim._state.data.campaign.completed_cases==["U01-C1","U01-C2"],"thorough signature completion preserves exact authored case order")
	var copied: Dictionary=sim.snapshot()
	copied.patients[id].clinical_decision.receipts[1].action="cautious_treat"
	reject_copy(copied,"forged early thorough treatment receipt rejects")

func manual_patience_exit() -> void:
	var setup: Dictionary=prepare("manual")
	if setup.is_empty():return
	var sim: Simulation=setup.sim
	var id: String=accept_first(sim)
	if id=="" or not gate(sim,id):return
	if not drive(sim,func(d: Dictionary)->bool:return d.patients[id].phase=="abandoned",4200,"manual pending patient exhausts real patience and walks out"):return
	check(sim._state.data.metrics.completed==0 and sim._state.data.metrics.abandoned==1 and sim._state.data.metrics.income==0,"unanswered decision earns no cure or income and retains abandonment")
	check(sim._state.data.campaign.completed_cases.is_empty() and sim._state.data.campaign.live_patient_ids.is_empty(),"manual abandonment frees live index without signature success")
	check(SnapshotValidator.validate(sim.snapshot(),catalog)=="","manual timeout terminal decision lifecycle remains strictly valid",SnapshotValidator.validate(sim.snapshot(),catalog))

func exhausted_stock_and_recovery() -> void:
	var setup: Dictionary=prepare("balanced")
	if setup.is_empty():return
	var sim: Simulation=setup.sim
	if finish_balanced_first(sim)=="":return
	check(int(sim._state.data.resources.get("delivered",-1))==3,"first true treatment leaves exactly three delivered units")
	issue(sim,"set_clinical_policy",{"policy":"manual"})
	var admitted: Dictionary=issue(sim,"admit_routine",{"case_id":"U01-C1"})
	if not admitted.get("ok",false):return
	var id: String=admitted.data.patient_ids[0]
	if not gate(sim,id):return
	for _n: int in range(2):
		var v: Dictionary=preview(sim,id)
		if not issue(sim,"clinical_decision",{"patient_id":id,"action":"continue_exam","expected_revision":v.revision}).get("ok",false):return
		if not gate(sim,id):return
	check(int(sim._state.data.resources.get("delivered",-1))==0 and int(preview(sim,id).completed_exams)==2,"two real repeats exhaust remaining stock without creating resources")
	var v: Dictionary=preview(sim,id)
	var before: Dictionary=sim.snapshot()
	var third: Dictionary=sim.submit({"id":"extended_third_exam","type":"clinical_decision","payload":{"patient_id":id,"action":"continue_exam","expected_revision":v.revision}})
	check(not third.get("ok",false) and str(third.get("code",""))=="clinical_exam_limit" and sim.snapshot()==before,"third examination rejects with exact cap and no mutation")
	var treatment: Dictionary=sim.submit({"id":"extended_missing_stock","type":"clinical_decision","payload":{"patient_id":id,"action":"cautious_treat","expected_revision":v.revision}})
	check(not treatment.get("ok",false) and sim.snapshot()==before,"missing treatment stock cannot silently complete or charge")
	issue(sim,"set_clinical_policy",{"policy":"balanced"})
	sim.advance_ticks(40)
	check(bool(preview(sim,id).pending) and sim._state.data.patients[id].phase=="care_queue" and sim._state.data.patients[id].wait_reason.begins_with("clinical_policy_blocked:"),"policy switch retains shortage and waits visibly instead of inventing cure")
	if not stock(sim):return
	if not drive(sim,func(d: Dictionary)->bool:return d.patients[id].phase=="left",1600,"real public delivery restores automatic treatment after policy switch"):return
	check(sim._state.data.metrics.completed==2 and sim._state.data.metrics.abandoned==0 and sim._state.data.campaign.completed_cases==["U01-C1"],"restocking completes routine without duplicating signature proof")
	check(SnapshotValidator.validate(sim.snapshot(),catalog)=="","shortage/recovery histories, policies and stock strictly validate",SnapshotValidator.validate(sim.snapshot(),catalog))
	var validator: Script=load("res://campaign/campaign_clinical_decisions_validator.gd")
	check(validator!=null and validator.has_method("policy_timeline"),"validator exposes once-built policy timeline")
	if validator!=null and validator.has_method("policy_timeline"):
		var unchanged: Dictionary=sim.snapshot()
		var actual: Array=validator.call("policy_timeline",sim._state.data)
		var expected: Array=[{"sequence":0,"policy":"balanced"}]
		var rows: Array=sim._state.data.command_receipts.values()
		rows.sort_custom(func(a: Dictionary,b: Dictionary)->bool:return int(a.data.sequence)<int(b.data.sequence))
		for row: Dictionary in rows:
			if row.data.command.type=="set_clinical_policy":expected.append({"sequence":int(row.data.sequence),"policy":str(row.data.command.payload.policy)})
		check(actual==expected and sim.snapshot()==unchanged,"cached timeline is exact ordered real policy commands and read-only")

func _run() -> void:
	if not output.begins_with("E:/CODEX/") or output.simplify_path()!=output or FileAccess.file_exists(output):
		printerr("Require fresh E:/CODEX output");quit(2);return
	var loaded: Dictionary=ContentCatalog.load_checked("res://content")
	check(bool(loaded.get("ok",false)),"real catalog loads",str(loaded.get("error","")))
	if loaded.get("ok",false):
		catalog=loaded.catalog
		decisions=load("res://campaign/campaign_clinical_decisions.gd")
		if decisions!=null:thorough_two_exams();manual_patience_exit();exhausted_stock_and_recovery()
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	var file:=FileAccess.open(output,FileAccess.WRITE)
	if file==null:quit(2);return
	file.store_string(JSON.stringify({"ok":failed==0,"passed":passed,"failed":failed,"checks":checks,"scope":"public thorough C2, real manual timeout, real depleted stock/policy change/delivery recovery; timeline cache entry point"},"\t"));file.close()
	print("CLINICAL EXTENDED RESULT passed="+str(passed)+" failed="+str(failed))
	quit(0 if failed==0 else 1)
