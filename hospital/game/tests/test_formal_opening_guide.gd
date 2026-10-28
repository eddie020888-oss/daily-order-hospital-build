extends SceneTree

# Standalone entry/guide contract test. Uses the real catalog, factories,
# public session actions and SaveStore; the runner owns engine execution.
var passed := 0
var failed := 0
var catalog: ContentCatalog
var output := ""
var save_base := ""
var pages: HospitalFlowPages
var actions: Array = []
var test_paths:FormalTestPaths

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=").replace("\\","/")
	_run.call_deferred()

func check(ok: bool, label: String) -> bool:
	if ok: passed += 1
	else: failed += 1
	print(("FORMAL OPENING PASS: " if ok else "FORMAL OPENING FAIL: ")+label)
	return ok

func _settle(count: int = 5) -> void:
	for _frame in range(count): await process_frame

func _runtime_root() -> String:
	return test_paths.run_root

func _text_of(node: Node) -> String:
	var value := str(node.text)+"\n" if node is Label or node is Button else ""
	for child: Node in node.get_children(): value += _text_of(child)
	return value

func _tap(button: Button) -> void:
	var point := button.get_global_rect().get_center()
	for down in [true,false]:
		var event := InputEventScreenTouch.new()
		event.index = 0
		event.pressed = down
		event.position = point
		Input.parse_input_event(event)
		await process_frame
	await _settle()

func _run() -> void:
	var allocation:Dictionary=FormalTestPaths.reserve(output,"formal-opening")
	if not allocation.get("ok",false):
		printerr("FORMAL TEST PATH ERROR: "+str(allocation.get("code","unknown")));quit(2);return
	test_paths=allocation.paths
	var loaded: Dictionary = ContentCatalog.load_checked("res://content")
	if not check(bool(loaded.get("ok",false)), "real production catalog loads"):
		await _finish()
		return
	catalog = loaded.catalog
	var runtime := _runtime_root()
	if runtime == "":
		await _finish()
		return
	save_base = runtime.path_join("formal-entry-%d-%d" % [OS.get_process_id(),Time.get_ticks_usec()])
	if not check(not DirAccess.dir_exists_absolute(save_base), "all test hospitals use a fresh isolated directory"):
		await _finish()
		return
	DirAccess.make_dir_recursive_absolute(save_base)
	await _test_entry_and_menu()
	_test_legacy_roundtrips()
	_test_pure_guide()
	_test_live_requirement_navigation()
	_test_staff_rest_guidance_boundaries()
	await _finish()

func _test_entry_and_menu() -> void:
	var session := GameSession.new(catalog,save_base.path_join("fresh"))
	var snapshot: Dictionary = session.sim.snapshot()
	check(snapshot.get("ruleset","") == "full-hospital-v2" and int(snapshot.get("schema_version",0)) == 3 and snapshot.level_id == "long_01", "a clean production session starts in the formal same-hospital ruleset")
	check(int(snapshot.get("campaign",{}).get("opening_loop_version",0)) == 1, "the new session uses the explicit formal opening factory")
	check(snapshot.get("campaign",{}).get("clinical_policy","") == "manual", "formal first visits expose real diagnosis decisions")
	var ready := true
	for method: String in ["default_new_level_id","start_new_hospital","has_saved_hospital"]:
		ready = check(session.has_method(method), "session provides "+method) and ready
	if ready:
		check(str(session.call("default_new_level_id")) == "long_01", "default new hospital is the first actual formal campaign level")
		check(not bool(session.call("has_saved_hospital")), "a never-saved clean session is not mislabeled as a saved hospital")
	root.size = Vector2i(932,430)
	pages = HospitalFlowPages.new()
	root.add_child(pages)
	pages.initialize(session)
	pages.configure(Rect2(59,0,814,409))
	pages.action_requested.connect(func(action: String) -> void: actions.append(action))
	pages.show_launch()
	await _settle()
	check(pages.controls.has("continue_game") and pages.controls.continue_game.text == "开始经营", "clean launch has a discoverable start action instead of pretending to continue a save")
	check(pages.controls.has("start_new") and "正式医院" in str(pages.controls.start_new.text), "launch explicitly names the formal new-hospital action")
	var copy := _text_of(pages)
	check(not "预约总量" in copy and not "36" in copy and not "15分钟" in copy, "formal launch does not advertise the old appointment challenge")
	if pages.controls.has("start_new"):
		var before: Dictionary = session.sim.snapshot()
		actions.clear()
		await _tap(pages.controls.start_new)
		check(actions == ["new_formal"], "real new-hospital tap requests the explicit formal confirmation route")
		check(session.sim.snapshot() == before, "launch navigation alone never replaces the current hospital")
	pages.free()
	pages = null
	await _settle()
	if not ready: return
	var started: Dictionary = session.call("start_new_hospital")
	check(bool(started.get("ok",false)) and session.is_long_campaign(), "explicit session new-hospital action starts the formal track")
	check(bool(session.call("has_saved_hospital")), "the new hospital is committed through the existing save path")
	check(SnapshotValidator.validate(session.sim.snapshot(),catalog) == "", "formal entry remains a strictly valid existing-schema snapshot")
	var legacy: Dictionary = session.start_level("level_01")
	check(bool(legacy.get("ok",false)) and session.sim.snapshot().level_id == "level_01", "explicit legacy tutorial selection still starts its original rules")
	session.restart()
	check(session.sim.snapshot().level_id == "level_01", "restart keeps the explicitly selected legacy level")

func _test_legacy_roundtrips() -> void:
	for level_id: String in ["level_01","long_01"]:
		var legacy := ClinicState.create(level_id,catalog)
		if not check(legacy != null, "original factory remains available for "+level_id): continue
		var legacy_data: Dictionary = legacy.to_data()
		check(not legacy_data.get("campaign",{}).has("opening_loop_version"), "original "+level_id+" factory does not silently opt in to formal rules")
		var legacy_root := save_base.path_join("existing-"+level_id)
		var saved: Dictionary = SaveStore.save(legacy_data,legacy_root)
		if not check(bool(saved.get("ok",false)), "real existing "+level_id+" snapshot can be saved"): continue
		var path := legacy_root.path_join("main.json")
		var bytes_before := FileAccess.get_file_as_bytes(path)
		var session := GameSession.new(catalog,legacy_root)
		session.open_saved()
		var restored: Dictionary = session.sim.snapshot()
		check(not session.storage_blocked and restored.level_id == level_id and restored.schema_version == legacy_data.schema_version, "loading "+level_id+" preserves its original level and schema")
		check(not restored.get("campaign",{}).has("opening_loop_version"), "loading "+level_id+" never applies the new opening factory")
		check(restored.get("campaign",{}).get("clinical_policy","") == legacy_data.get("campaign",{}).get("clinical_policy",""), "loading "+level_id+" preserves its diagnosis policy")
		check(FileAccess.get_file_as_bytes(path) == bytes_before, "merely loading "+level_id+" preserves its committed save bytes")
		check(restored.paused, "legacy continue retains the existing safe paused-on-load contract")
		if session.has_method("has_saved_hospital"):
			check(bool(session.call("has_saved_hospital")), "loaded "+level_id+" is recognized as a saved hospital")

func _test_pure_guide() -> void:
	const PATH := "res://ui/campaign_opening_guide.gd"
	if not check(ResourceLoader.exists(PATH), "a dedicated pure current-task guide exists"): return
	var script: GDScript = load(PATH)
	var guide: Variant = script.new()
	if not check(guide.has_method("current"), "guide provides current(snapshot,catalog)"): return
	for level_id: String in ["level_01","long_01"]:
		var legacy := ClinicState.create(level_id,catalog)
		var old_view: Dictionary = guide.call("current",legacy.to_data(),catalog)
		check(not bool(old_view.get("visible",false)), "new formal opening guide does not change old "+level_id+" saves")
	var session := GameSession.new(catalog,save_base.path_join("guide"))
	var snapshot: Dictionary = session.sim.snapshot()
	if int(snapshot.get("campaign",{}).get("opening_loop_version",0)) != 1:
		check(false, "guide fixture requires the real new formal factory")
		return
	var before := JSON.stringify(snapshot)
	var view: Dictionary = guide.call("current",snapshot,catalog)
	check(bool(view.get("visible",false)), "the same-hospital opening guide is visible immediately")
	check(str(view.get("title","")).contains("接待"), "the first actual missing service names reception")
	check(str(view.get("phase_name","")) != "", "the guide reports the actual campaign stage")
	var focus: Dictionary = view.get("focus",{})
	check(focus.get("action","") == "build" and focus.get("facility_kind","") == "O01", "first guide tap targets actual reception building, not a generic page")
	check(not str(view.get("text","")).contains("36") and not str(view.get("text","")).contains("15分钟"), "guide copy describes the formal hospital rather than legacy appointments")
	check(JSON.stringify(snapshot) == before and session.sim.snapshot() == snapshot, "reading guidance cannot mutate model, money, admissions, receipts or snapshot")
	check(guide.call("current",snapshot,catalog) == view, "the same actual state derives the same current task without UI progress flags")
	check(SnapshotValidator.validate(snapshot,catalog) == "", "guidance leaves the actual clinical save strictly valid")

func _public(session:GameSession,type:String,payload:Dictionary={}) -> Dictionary:
	var result:Dictionary=session.issue(type,payload)
	check(bool(result.get("ok",false)),"real guide fixture command "+type+" / "+str(result.get("code","")))
	return result

func _build_service(session:GameSession,kind:String,origin:int,staffed:bool=true) -> String:
	var definition:Dictionary=catalog.campaign.facilities[kind]
	var result:Dictionary=_public(session,"build_department",{"unit_id":definition.unit_id,"origin_cell":origin,"layout":FacilityLayout.default_layout(definition.unit_id,kind,0)})
	if not result.get("ok",false):return ""
	var id:String=str(result.data.facility_ids[0])
	if staffed:
		for role:String in definition.roles:
			var hired:Dictionary=_public(session,"hire",{"role":role})
			if not hired.get("ok",false):return ""
			if not _public(session,"assign",{"staff_id":hired.data.staff_id,"facility_id":id}).get("ok",false):return ""
	return id

func _test_live_requirement_navigation() -> void:
	if not ResourceLoader.exists("res://ui/campaign_opening_guide.gd"):return
	var reader:Variant=load("res://ui/campaign_opening_guide.gd").new()
	if not reader.has_method("current"):return
	var session:=GameSession.new(catalog,save_base.path_join("live-guide"))
	if int(session.sim.snapshot().get("campaign",{}).get("opening_loop_version",0))!=1:return
	var reception:String=_build_service(session,"O01",33,false)
	if reception=="":return
	var view:Dictionary=reader.call("current",session.sim.snapshot(),catalog)
	check(view.get("focus",{}).get("action","")=="staff" and view.focus.get("role","")=="receptionist" and view.focus.get("control","")=="hire", "built reception requests its actual missing profession instead of another room")
	var hired:Dictionary=_public(session,"hire",{"role":"receptionist"})
	if not hired.get("ok",false):return
	view=reader.call("current",session.sim.snapshot(),catalog)
	check(view.focus.get("control","")=="assign" and view.focus.get("staff_id","")==str(hired.data.staff_id) and view.focus.get("facility_id","")==reception, "an already-hired receptionist is directed to the actual unstaffed reception")
	if not _public(session,"assign",{"staff_id":hired.data.staff_id,"facility_id":reception}).get("ok",false):return
	if _build_service(session,"U04-E1",25)=="" or _build_service(session,"O15",40)=="":return
	var snapshot:Dictionary=session.sim.snapshot()
	view=reader.call("current",snapshot,catalog)
	check(view.focus.get("action","")=="operation" and view.focus.get("facility_kind","")=="O15" and view.focus.get("control","")=="run_operation", "an already-built staffed supply desk directs one real delivery order")
	check(session.sim.snapshot()==snapshot,"reading an order prompt never creates stock or an order")
	if not _public(session,"run_operation",{"facility_kind":"O15"}).get("ok",false):return
	view=reader.call("current",session.sim.snapshot(),catalog)
	check(view.focus.get("action","")=="resume", "paused real delivery asks to resume instead of rebuilding or ordering twice")
	if not _public(session,"set_paused",{"paused":false}).get("ok",false):return
	snapshot=session.sim.snapshot()
	view=reader.call("current",snapshot,catalog)
	check(view.focus.get("action","")=="operation" and view.focus.get("control","")!="run_operation", "running delivery only navigates to progress without requesting duplicate work")
	check(session.sim.snapshot()==snapshot and SnapshotValidator.validate(snapshot,catalog)=="", "all current-task navigation remains read-only on the real in-progress hospital")

func _rest_boundary(source:Dictionary,fatigue:int)->Dictionary:
	# UI reader boundaries only: these artificial fatigue values are not
	# saved, submitted to commands, or claimed as normal-play rest evidence.
	var copy:Dictionary=source.duplicate(true)
	var selected:String=""
	var ids:Array=copy.staff.keys();ids.sort()
	for id:String in ids:
		copy.staff[id].fatigue=0
		if selected=="" and copy.staff[id].role=="doctor" and copy.staff[id].facility_id!="":selected=id
	if selected!="":copy.staff[selected].fatigue=fatigue
	return copy

func _test_staff_rest_guidance_boundaries()->void:
	var session:=GameSession.new(catalog,save_base.path_join("rest-reader"))
	if _build_service(session,"U04-E1",25)=="" or _build_service(session,"O01",33)=="" or _build_service(session,"O15",40)=="" or _build_service(session,"O05",125)=="" or _build_service(session,"U04-E2",129)=="":return
	var delivery:Dictionary=_public(session,"run_operation",{"facility_kind":"O15"})
	if not delivery.get("ok",false):return
	if not _public(session,"set_paused",{"paused":false}).get("ok",false):return
	# Real unit-model ticks complete the actual supply command. This is not
	# the native observer, a wall-clock playthrough, or a fabricated stock grant.
	for _tick:int in range(1200):
		if session.sim.snapshot().work_orders[delivery.data.work_order_id].status=="done":break
		session.sim.advance_ticks(1)
	var source:Dictionary=session.sim.snapshot()
	if not check(source.work_orders[delivery.data.work_order_id].status=="done" and SnapshotValidator.validate(source,catalog)=="","rest reader starts from strictly valid command-built and delivered hospital"):return
	var original:String=JSON.stringify(source)
	for fatigue:int in [47,48,64,100]:
		var boundary:Dictionary=_rest_boundary(source,fatigue)
		var before:String=JSON.stringify(boundary)
		var view:Dictionary=CampaignOpeningGuide.current(boundary,catalog)
		var focus:Dictionary=view.get("focus",{})
		check((focus.get("action","")=="build" and focus.get("facility_kind","")=="O25") if fatigue>=48 else not (focus.get("action","")=="build" and focus.get("facility_kind","") in ["O25","O26"]),"assigned fatigue%d has the correct48-only early rest preparation boundary"%fatigue)
		check(JSON.stringify(boundary)==before,"fatigue%d guidance cannot change fatigue,stock,cash,orders or history"%fatigue)
	check(JSON.stringify(session.sim.snapshot())==original,"all detached fatigue boundaries leave actual test hospital unchanged")
	# Existing self-service water stock does not require a production operator.
	var definition:Dictionary=catalog.campaign.facilities.O25
	var layout:Dictionary=FacilityLayout.default_layout(str(definition.unit_id),"O25",0)
	var placed:bool=false
	for cell:int in range(GridService.WIDTH*GridService.HEIGHT):
		if not FacilityLayout.preview(session.sim.snapshot(),{"unit_id":definition.unit_id,"origin_cell":cell,"layout":layout}).get("ok",false):continue
		placed=_build_service(session,"O25",cell,false)!="";break
	if not check(placed,"real rest supply geometry can be built without hiring a self-service operator"):return
	var supplied:Dictionary=session.sim.snapshot()
	var high:Dictionary=_rest_boundary(supplied,64)
	var view:Dictionary=CampaignOpeningGuide.current(high,catalog)
	check(not (view.get("focus",{}).get("action","")=="build" and view.focus.get("facility_kind","") in ["O25","O26"]),"existing supplied water point prevents duplicate rest building")
	check(session.sim.snapshot()==supplied and SnapshotValidator.validate(supplied,catalog)=="","reader leaves real supplied hospital and strict validation unchanged")
	_test_manual_rest_and_broken_repair(session)

func _build_rest_test_service(session:GameSession,kind:String,staffed:bool)->String:
	var definition:Dictionary=catalog.campaign.facilities[kind]
	var layout:Dictionary=FacilityLayout.default_layout(str(definition.unit_id),kind,0)
	for cell:int in range(GridService.WIDTH*GridService.HEIGHT):
		if FacilityLayout.preview(session.sim.snapshot(),{"unit_id":definition.unit_id,"origin_cell":cell,"layout":layout}).get("ok",false):return _build_service(session,kind,cell,staffed)
	check(false,"real detached fixture has legal geometry for "+kind)
	return ""

func _manual_rest_fixture(source:Dictionary)->Dictionary:
	var boundary:Dictionary=_rest_boundary(source,0)
	boundary.campaign.auto_staff_rest=false
	var ids:Array=boundary.staff.keys();ids.sort()
	var sid:String=""
	for id:String in ids:
		if boundary.staff[id].role=="doctor" and boundary.staff[id].facility_id!="":sid=id
	if sid!="":boundary.staff[sid].fatigue=64
	return {"snapshot":boundary,"staff_id":sid}

func _test_manual_rest_and_broken_repair(session:GameSession)->void:
	# Detached UI-only boundaries. No broken condition, forced fatigue or
	# automatic-rest policy below is submitted back to the real test hospital.
	var manual:Dictionary=_manual_rest_fixture(session.sim.snapshot())
	var before:String=JSON.stringify(manual.snapshot)
	var water:Dictionary=CampaignOpeningGuide.current(manual.snapshot,catalog)
	check(manual.staff_id!="" and water.get("focus",{}).get("staff_id","")==manual.staff_id and water.focus.get("control","")=="rest_"+str(manual.staff_id)+"_water","manual water guidance targets the actual tired employee and exact water action")
	check(JSON.stringify(manual.snapshot)==before,"manual water guidance is read-only")
	var workshop:String=_build_rest_test_service(session,"O11",true)
	if workshop=="":return
	var broken:Dictionary=_rest_boundary(session.sim.snapshot(),64)
	var supply_id:String=""
	for f:Dictionary in broken.facilities.values():
		if f.kind=="O25":supply_id=str(f.id);f.condition=0
	broken.facilities[workshop].condition=0
	before=JSON.stringify(broken)
	if not check(supply_id!="" and CampaignOperations.readiness(broken,catalog,"O11").is_empty(),"real operation readiness permits an open staffed broken repair workshop"):return
	var repair:Dictionary=CampaignOpeningGuide.current(broken,catalog)
	check(repair.get("focus",{}).get("action","")=="operation" and repair.focus.get("facility_kind","")=="O11" and repair.focus.get("control","")=="run_operation","broken repair workshop guides a real paid repair order instead of its close control")
	check(JSON.stringify(broken)==before,"broken workshop guidance changes neither condition nor orders")
	if _build_rest_test_service(session,"O26",false)=="":return
	manual=_manual_rest_fixture(session.sim.snapshot())
	manual.snapshot.resources.water=0
	before=JSON.stringify(manual.snapshot)
	var food:Dictionary=CampaignOpeningGuide.current(manual.snapshot,catalog)
	check(food.get("focus",{}).get("staff_id","")==manual.staff_id and food.focus.get("control","")=="rest_"+str(manual.staff_id)+"_food","manual food guidance targets the actual employee and food action when water is empty")
	check(JSON.stringify(manual.snapshot)==before,"manual food guidance remains read-only")
	check(SnapshotValidator.validate(session.sim.snapshot(),catalog)=="","all synthetic repair and manual-rest boundaries leave the actual hospital valid")

func _finish() -> void:
	if is_instance_valid(pages):
		pages.free()
		pages = null
	await _settle()
	if test_paths.write_report({"passed":passed,"failed":failed,"save_root":save_base,"scope":"Real catalog and formal entry, existing-save preservation, launch navigation, pure state-derived guidance. Engine run owned by parent."},"  ")!=OK:
		printerr("FORMAL TEST PATH ERROR: report_write_failed");quit(2);return
	print("FORMAL OPENING RESULT: passed=%d failed=%d" % [passed,failed])
	quit(1 if failed else 0)
