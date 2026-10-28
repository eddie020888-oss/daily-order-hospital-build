extends SceneTree

var output := ""
var passed := 0
var failed := 0
var sequence := 0
var checks: Array=[]
var catalog: ContentCatalog

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=").replace("\\","/")
	_run.call_deferred()

func check(ok: bool,label: String,detail: String="") -> void:
	checks.append({"ok":ok,"check":label,"detail":detail})
	if ok: passed+=1
	else: failed+=1
	print(("CAMPAIGN BATCH PASS: " if ok else "CAMPAIGN BATCH FAIL: ")+label+(": "+detail if detail!="" else ""))

func command(sim: Simulation,type: String,payload: Dictionary) -> Dictionary:
	sequence+=1
	var result: Dictionary=sim.submit({"id":"batch_%03d"%sequence,"type":type,"payload":payload})
	check(bool(result.get("ok",false)),"public "+type,str(result.get("code","")))
	return result

func _run() -> void:
	if not output.begins_with("E:/CODEX/") or output.simplify_path()!=output or FileAccess.file_exists(output) or DirAccess.dir_exists_absolute(output.get_basename()+"-save"): quit(2); return
	var loaded: Dictionary=ContentCatalog.load_checked("res://content")
	check(bool(loaded.get("ok",false)),"actual batch content loads",str(loaded.get("error","")))
	var handoff: Dictionary={}
	if loaded.get("ok",false):
		catalog=loaded.catalog
		var state: ClinicState=CampaignState.create("career_01",catalog)
		var sim := Simulation.new(catalog,state)
		var setup := true
		for row: Array in [["U32-E1",25],["U32-E3",33]]:
			var kind: String=str(row[0])
			var layout: Dictionary=FacilityLayout.default_layout("U32",kind,0)
			var built: Dictionary=command(sim,"build_department",{"unit_id":"U32","origin_cell":int(row[1]),"layout":layout})
			if not built.get("ok",false): setup=false; break
			var hired: Dictionary=command(sim,"hire",{"role":"technician"})
			if not hired.get("ok",false): setup=false; break
			if not command(sim,"assign",{"staff_id":hired.data.staff_id,"facility_id":built.data.facility_ids[0]}).get("ok",false): setup=false; break
		if setup:
			check(int(state.data.resources.get("cleaned_instruments",0))==0,"downstream has genuinely no initial upstream batch")
			var first: Dictionary=command(sim,"run_operation",{"facility_kind":"U32-E1"})
			var second: Dictionary=command(sim,"run_operation",{"facility_kind":"U32-E3"})
			command(sim,"set_paused",{"paused":false})
			if first.get("ok",false) and second.get("ok",false):
				for _n in range(800):
					sim.advance_ticks(1)
					var snapshot: Dictionary=sim.snapshot()
					var upper: Dictionary=snapshot.work_orders[first.data.work_order_id]
					var lower: Dictionary=snapshot.work_orders[second.data.work_order_id]
					if upper.status=="done" and lower.status=="working" and lower.started_tick==snapshot.tick:
						handoff=snapshot
						check(lower.started_tick==upper.completed_tick,"downstream really starts on the same tick its earlier upstream order produces the first batch")
						break
				check(not handoff.is_empty(),"real concurrent workers reach the same-tick production handoff")
				if not handoff.is_empty():
					var error: String=SnapshotValidator.validate(handoff,catalog)
					check(error=="","strict validation respects actual within-tick operation order",error)
					var saved: Dictionary=SaveStore.save(handoff,output.get_basename()+"-save")
					check(bool(saved.get("ok",false)),"real same-tick batch state saves",str(saved.get("error","")))
					var read: Dictionary=SaveStore.load(output.get_basename()+"-save",catalog)
					check(bool(read.get("ok",false)),"real same-tick batch state loads",str(read.get("error","")))
					if read.get("ok",false):
						check(read.state.to_data()==handoff,"batch stocks clocks and receipts survive exact JSON roundtrip")
						var resumed := Simulation.new(catalog,read.state)
						sim.advance_ticks(600); resumed.advance_ticks(600)
						check(sim.snapshot()==resumed.snapshot(),"batch input consumption and completion replay deterministically")
						check(resumed.snapshot().work_orders[second.data.work_order_id].status=="done","downstream completes without replenishment or phase edits")
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	var file := FileAccess.open(output,FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed":passed,"failed":failed,"checks":checks,"handoff":handoff,"scope":"Actual public construction/hire/assign/run_operation in career01; zero starting cleaned instruments; concurrent physical workers and exact same-tick upstream production/downstream consumption; no money/resource/phase edits."},"  "))
	print("CAMPAIGN BATCH RESULT: passed=%d failed=%d"%[passed,failed])
	quit(1 if failed else 0)
