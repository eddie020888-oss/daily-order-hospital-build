extends SceneTree

const FormalPaths=preload("res://tests/support/formal_test_paths.gd")
var test_paths:Variant

# Focused pure-reader boundary test, NOT a UI playthrough. Real commands build
# and staff the prerequisite services, then an explicitly synthetic copy sets
# delivered stock and zero cash to isolate the real admission budget reason.
# No GameSession, save, running hospital or product snapshot is overwritten.
const Guide = preload("res://ui/campaign_opening_guide.gd")
var passed := 0
var failed := 0
var checks: Array = []
var catalog: ContentCatalog
var serial := 0
var output := ""

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=").replace("\\","/")
	var reservation:Dictionary=FormalPaths.reserve(output,"opening-budget-guide")
	if not reservation.get("ok",false):
		printerr("FORMAL TEST PATH ERROR: "+str(reservation.get("code","unknown")));quit(2);return
	test_paths=reservation.paths;output=str(reservation.output)
	_run.call_deferred()

func check(ok: bool,label: String,detail: Variant="") -> bool:
	checks.append({"ok":ok,"label":label,"detail":detail})
	if ok:passed+=1
	else:failed+=1
	print(("BUDGET GUIDE PASS: " if ok else "BUDGET GUIDE FAIL: ")+label+" "+str(detail))
	return ok

func _issue(sim: Simulation,type: String,payload: Dictionary) -> Dictionary:
	serial+=1
	var result:Dictionary=sim.submit({"id":"budget_reader_fixture_%04d"%serial,"type":type,"payload":payload})
	check(bool(result.get("ok",false)),"fixture public command "+type,result.get("code",""))
	return result

func _build(sim: Simulation,kind: String,origin: int) -> bool:
	var definition:Dictionary=catalog.campaign.facilities[kind]
	var result:Dictionary=_issue(sim,"build_department",{"unit_id":definition.unit_id,"origin_cell":origin,"layout":FacilityLayout.default_layout(definition.unit_id,kind,0)})
	if not result.get("ok",false):return false
	var facility_id:String=str(result.data.facility_ids[0])
	for role:String in definition.roles:
		var hired:Dictionary=_issue(sim,"hire",{"role":role})
		if not hired.get("ok",false):return false
		if not _issue(sim,"assign",{"staff_id":hired.data.staff_id,"facility_id":facility_id}).get("ok",false):return false
	return true

func _run() -> void:
	var loaded:Dictionary=ContentCatalog.load_checked("res://content")
	if not check(bool(loaded.get("ok",false)),"real catalog loads"):_finish();return
	catalog=loaded.catalog
	var sim:=Simulation.new(catalog,LongCampaignState.create_formal("long_01",catalog))
	if not _build(sim,"U04-E1",25) or not _build(sim,"O01",33) or not _build(sim,"O15",40) or not _build(sim,"O05",125):_finish();return
	var source:Dictionary=sim.snapshot()
	var source_json:String=JSON.stringify(source)
	# Explicit boundary fixture only: no supply/timer gameplay is claimed here.
	var fixture:Dictionary=source.duplicate(true)
	fixture.resources.delivered=100
	fixture.cash=0
	fixture.campaign.intake_enabled=false
	check(fixture.patients.is_empty() and fixture.campaign.live_patient_ids.is_empty(),"boundary fixture has no patient to handle")
	for paused:bool in [false,true]:
		fixture.paused=paused
		var before:String=JSON.stringify(fixture)
		var opening:Dictionary=CampaignOpeningLoop.preview(fixture,catalog)
		check(not opening.can_admit and opening.admission_reasons.has("insufficient_case_budget"),"real admission reader emits insufficient_case_budget",opening.admission_reasons)
		check(opening.next_requirement.get("code","")=="waiting_treatment" and opening.next_requirement.get("reason","")=="insufficient_case_budget","real opening requirement exposes exact budget reason",opening.next_requirement)
		var guide:Dictionary=Guide.current(fixture,catalog)
		check(guide.get("visible",false) and guide.get("focus",{}).get("action","")=="goals" and guide.get("focus",{}).get("section","")=="finance","budget shortage navigates to real finance while paused="+str(paused),guide)
		check(guide.get("focus",{}).get("action","")!="patients" and not str(guide.get("title","")).contains("在院患者") and not str(guide.get("text","")).contains("当前开业客流"),"zero-patient budget block does not tell player to handle inpatients while paused="+str(paused),guide)
		check(JSON.stringify(fixture)==before,"both readers preserve the explicit boundary fixture")
	check(JSON.stringify(sim.snapshot())==source_json,"synthetic boundary never changes the actual command-built source state")
	_finish()

func _finish() -> void:
	var report:Dictionary={"passed":passed,"failed":failed,"checks":checks,"scope":"Explicit synthetic zero-cash/stock boundary copy; real admission and guide readers; not gameplay, delivery, or a native UI run."}
	if test_paths.write_report(report,"  ")!=OK:
		printerr("FORMAL TEST PATH ERROR: report_write_failed");quit(2);return
	print("BUDGET GUIDE RESULT: passed=%d failed=%d"%[passed,failed])
	quit(1 if failed else 0)
