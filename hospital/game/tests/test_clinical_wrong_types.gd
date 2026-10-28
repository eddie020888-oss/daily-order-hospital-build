extends "res://tests/test_clinical_decisions.gd"

# Root runs with --quit-after=100. Any SCRIPT ERROR or missing final result is
# a failed test, even if Godot's process counter exits zero after the watchdog.
var probes: Array=[]

func reject_without_error(d: Dictionary,label: String) -> void:
	var before: Dictionary=d.duplicate(true)
	var error: String=SnapshotValidator.validate(d,catalog)
	check(error!="" and before==d,label,error)
	probes.append({"probe":label,"validator_error":error,"source_copy_unchanged":before==d})
	# Partial output is explicitly not success and helps locate a later engine
	# error. Only the final result file is an acceptance artifact.
	var partial:=FileAccess.open(output.get_basename()+"-partial.json",FileAccess.WRITE)
	if partial!=null:partial.store_string(JSON.stringify({"complete":false,"ok":false,"probes":probes},"\t"));partial.close()

func _run() -> void:
	if not output.begins_with("E:/CODEX/") or output.simplify_path()!=output or FileAccess.file_exists(output) or FileAccess.file_exists(output.get_basename()+"-partial.json"):
		printerr("Require fresh E:/CODEX output and partial report");quit(2);return
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	var loaded: Dictionary=ContentCatalog.load_checked("res://content")
	check(bool(loaded.get("ok",false)),"real catalog loads",str(loaded.get("error","")))
	if loaded.get("ok",false):
		catalog=loaded.catalog
		decisions=load("res://campaign/campaign_clinical_decisions.gd")
		var setup: Dictionary=prepare("manual")
		if not setup.is_empty():
			var sim: Simulation=setup.sim
			var id: String=accept_first(sim)
			if id!="" and gate(sim,id):
				var pending: Dictionary=sim.snapshot()
				var v: Dictionary=preview(sim,id)
				if issue(sim,"clinical_decision",{"patient_id":id,"action":"continue_exam","expected_revision":v.revision}).get("ok",false):
					var active: Dictionary=sim.snapshot()
					check(SnapshotValidator.validate(active,catalog)=="","genuine receipt and plan valid before corruption",SnapshotValidator.validate(active,catalog))
					var corrupt: Dictionary=active.duplicate(true)
					corrupt.patients[id].clinical_decision.receipts[0].history_count={"wrong_type":1}
					reject_without_error(corrupt,"object history_count returns reject without engine error")
					corrupt=active.duplicate(true)
					corrupt.patients[id].clinical_decision.receipts[0].deficit={"wrong_type":1}
					reject_without_error(corrupt,"object deficit returns reject without engine error")
					corrupt=pending.duplicate(true)
					corrupt.patients[id].clinical_decision="wrong_type"
					reject_without_error(corrupt,"non-Dictionary clinical state at terminal cursor gate rejects without engine error")
					corrupt=pending.duplicate(true)
					corrupt.patients[id].clinical_decision=[]
					reject_without_error(corrupt,"Array clinical state at terminal cursor gate rejects without engine error")
	check(probes.size()==4,"all four malformed-type probes completed without abort")
	var file:=FileAccess.open(output,FileAccess.WRITE)
	if file==null:quit(2);return
	file.store_string(JSON.stringify({"complete":true,"ok":failed==0,"passed":passed,"failed":failed,"checks":checks,"probes":probes,"acceptance":"Requires this complete final result AND full engine log contains no SCRIPT ERROR/ERROR; watchdog process exit alone is insufficient"},"\t"));file.close()
	print("CLINICAL WRONG TYPE RESULT passed="+str(passed)+" failed="+str(failed))
	quit(0 if failed==0 else 1)
