extends SceneTree

# Public command regressions. Each case creates an independent genuine game.
# Malformed-payload cases run separately so a product ScriptError cannot hide
# the economic/layout/recovery evidence from the other cases.
var output := ""
var selected := "safe"
var passed := 0
var failed := 0
var sequence := 0
var checks: Array=[]
var catalog: ContentCatalog

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=").replace("\\","/")
		if arg.begins_with("--case="): selected=arg.trim_prefix("--case=")
	_run.call_deferred()

func check(ok: bool,label: String,detail: String="") -> void:
	checks.append({"ok":ok,"check":label,"detail":detail})
	if ok: passed+=1
	else: failed+=1
	print(("CAMPAIGN COMMAND PASS: " if ok else "CAMPAIGN COMMAND FAIL: ")+label+(": "+detail if detail!="" else ""))

func command(sim: Simulation,type: String,payload: Dictionary,required: bool=true) -> Dictionary:
	sequence+=1
	var result: Dictionary=sim.submit({"id":"command_safety_%04d"%sequence,"type":type,"payload":payload})
	if required: check(bool(result.get("ok",false)),"public "+type,str(result.get("code","")))
	return result

func fixture(kind: String) -> Dictionary:
	var state: ClinicState=CampaignState.create("career_01",catalog)
	var sim := Simulation.new(catalog,state)
	var definition: Dictionary=catalog.campaign.facilities[kind]
	var built: Dictionary=command(sim,"build_department",{"unit_id":definition.unit_id,"origin_cell":25,"layout":FacilityLayout.default_layout(definition.unit_id,kind,0)})
	return {"state":state,"sim":sim,"built":built}

func staff_fixture(kind: String) -> Dictionary:
	var f: Dictionary=fixture(kind)
	if not f.built.get("ok",false): return f
	f.staff_ids=[]
	for role: String in catalog.campaign.facilities[kind].roles:
		var hired: Dictionary=command(f.sim,"hire",{"role":role})
		if not hired.get("ok",false): return f
		f.staff_ids.append(hired.data.staff_id)
		command(f.sim,"assign",{"staff_id":hired.data.staff_id,"facility_id":f.built.data.facility_ids[0]})
	return f

func test_preserved_id_kind() -> void:
	var f: Dictionary=fixture("U01-E1")
	if not f.built.get("ok",false): return
	var before: Dictionary=f.sim.snapshot()
	var replacement := ""
	var original: Dictionary=catalog.campaign.facilities["U01-E1"]
	for id: String in catalog.campaign.facilities:
		var candidate: Dictionary=catalog.campaign.facilities[id]
		if id!="U01-E1" and candidate.body_size==original.body_size and candidate.roles.size()==original.roles.size(): replacement=id; break
	check(replacement!="","authored same-footprint replacement exists")
	if replacement=="": return
	var room_id: String=f.built.data.room_id
	var layout: Dictionary=before.rooms[room_id].layout.duplicate(true)
	layout.facilities[0].kind=replacement
	var result: Dictionary=command(f.sim,"edit_department",{"room_id":room_id,"layout":layout},false)
	check(not result.get("ok",false) and f.sim.snapshot()==before,"preserving an ID cannot turn its device into a different kind without a transaction",str(result.get("code","")))
	var error: String=SnapshotValidator.validate(f.sim.snapshot(),catalog)
	check(error=="","every accepted layout edit remains a valid saved hospital",error)

func test_capital_refund() -> void:
	var f: Dictionary=fixture("U01-E1")
	if not f.built.get("ok",false): return
	var before: Dictionary=f.sim.snapshot()
	var cost: int=f.built.data.cost
	var facility_id: String=f.built.data.facility_ids[0]
	var sold: Dictionary=command(f.sim,"remove_facility",{"facility_id":facility_id})
	if not sold.get("ok",false): return
	var cash_after: int=f.sim.snapshot().cash
	var receipt_id := "command_safety_%04d"%sequence
	var replay: Dictionary=f.sim.submit({"id":receipt_id,"type":"remove_facility","payload":{"facility_id":facility_id}})
	check(replay==sold and f.sim.snapshot().cash==cash_after,"replaying a sale command cannot refund twice")
	command(f.sim,"remove_room",{"room_id":f.built.data.room_id})
	var refunded: int=f.sim.snapshot().cash-int(before.cash)
	check(refunded<=int(cost*.7),"selling a device then its empty room cannot refund the same capital twice","actual=%d maximum=%d"%[refunded,int(cost*.7)])
	check(SnapshotValidator.validate(f.sim.snapshot(),catalog)=="","real sale receipts and allocator remain save-valid",SnapshotValidator.validate(f.sim.snapshot(),catalog))

func test_training_and_research() -> void:
	var f: Dictionary=staff_fixture("O09")
	if not f.built.get("ok",false) or not f.has("staff_ids") or f.staff_ids.is_empty(): return
	var target: String=f.staff_ids[0]
	var first: Dictionary=command(f.sim,"start_training",{"staff_id":target,"unit_id":"U01"})
	if not first.get("ok",false): return
	var before: Dictionary=f.sim.snapshot()
	var repeat: Dictionary=command(f.sim,"start_training",{"staff_id":target,"unit_id":"U01"},false)
	check(not repeat.get("ok",false) and f.sim.snapshot()==before,"a pending identical trainee and unit cannot be billed and queued twice",str(repeat.get("code","")))
	var research: Dictionary=staff_fixture("O10")
	if not research.built.get("ok",false): return
	var started: Dictionary=command(research.sim,"start_research",{"project_id":"efficiency"})
	if not started.get("ok",false): return
	before=research.sim.snapshot()
	repeat=command(research.sim,"start_research",{"project_id":"efficiency"},false)
	check(not repeat.get("ok",false) and research.sim.snapshot()==before,"pending research cannot queue duplicate charges or proof")
	command(research.sim,"set_paused",{"paused":false})
	research.sim.advance_ticks(700)
	check("efficiency" in research.sim.snapshot().campaign.research,"research actually completes through a staffed workplace")
	before=research.sim.snapshot()
	repeat=command(research.sim,"start_research",{"project_id":"efficiency"},false)
	check(not repeat.get("ok",false) and research.sim.snapshot()==before,"completed research cannot repeat for extra evidence or charges")

func test_active_order_close() -> void:
	var f: Dictionary=staff_fixture("O14")
	if not f.built.get("ok",false): return
	var order: Dictionary=command(f.sim,"run_operation",{"facility_kind":"O14"})
	if not order.get("ok",false): return
	command(f.sim,"set_paused",{"paused":false})
	var working := false
	for _n in range(400):
		f.sim.advance_ticks(1)
		var current: Dictionary=f.sim.snapshot().work_orders[order.data.work_order_id]
		if current.status=="working" and current.work>=5: working=true; break
	check(working,"stock order genuinely reaches working state")
	if not working: return
	var facility_id: String=f.built.data.facility_ids[0]
	var closed: Dictionary=command(f.sim,"close_facility",{"facility_id":facility_id},false)
	f.sim.advance_ticks(15)
	var error: String=SnapshotValidator.validate(f.sim.snapshot(),catalog)
	check(error=="","closing an active backend device cannot create a permanently invalid service clock",error)
	if closed.get("ok",false): command(f.sim,"reopen_facility",{"facility_id":facility_id})
	f.sim.advance_ticks(700)
	check(f.sim.snapshot().work_orders[order.data.work_order_id].status=="done","backend job is recoverable after close refusal or reopening")
	check(SnapshotValidator.validate(f.sim.snapshot(),catalog)=="","recovered backend order retains valid timing and ledger",SnapshotValidator.validate(f.sim.snapshot(),catalog))

func test_bad_payload() -> void:
	var state: ClinicState=CampaignState.create("career_01",catalog)
	var sim := Simulation.new(catalog,state)
	var before: Dictionary=sim.snapshot()
	var result: Dictionary={}
	if selected=="build-shape":
		result=command(sim,"build_department",{"unit_id":"U01","origin_cell":25,"layout":{"facilities":[]}},false)
	else:
		var amount: Variant="1000" if selected=="loan-string" else {"not":"an integer"}
		result=command(sim,"take_loan",{"amount":amount},false)
	var rejection: bool=result.get("ok") is bool and not result.ok and result.get("code") is String and result.code!="" and result.get("data") is Dictionary
	check(rejection and sim.snapshot()==before,"malformed command returns a complete typed safe rejection for "+selected,str(result.get("code","")))

func _run() -> void:
	if not output.begins_with("E:/CODEX/") or output.simplify_path()!=output or FileAccess.file_exists(output): quit(2); return
	var loaded: Dictionary=ContentCatalog.load_checked("res://content")
	check(bool(loaded.get("ok",false)),"actual content loads",str(loaded.get("error","")))
	if loaded.get("ok",false):
		catalog=loaded.catalog
		if selected=="safe":
			test_preserved_id_kind(); test_capital_refund(); test_training_and_research(); test_active_order_close()
		elif selected in ["loan-string","loan-object","build-shape"]: test_bad_payload()
		else: check(false,"known selected case")
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	var file := FileAccess.open(output,FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed":passed,"failed":failed,"checks":checks,"case":selected,"scope":"Independent actual public command games; no money, resource or actor-phase injection. Malformed loan payloads are separate invocations because product ScriptError is itself the regression."},"  "))
	print("CAMPAIGN COMMAND RESULT: passed=%d failed=%d"%[passed,failed])
	quit(1 if failed else 0)
