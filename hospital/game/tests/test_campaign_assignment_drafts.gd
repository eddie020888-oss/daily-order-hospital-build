extends SceneTree

# Mechanical view-state boundaries. All hospital changes use public commands;
# the one malformed-role case corrupts only a temporary OptionButton's metadata.
const ReviewPaths=preload("res://tests/support/gameplay_review_paths.gd")
var test_paths:Variant
var output:String=""
var passed:int=0
var failed:int=0
var checks:Array=[]
var session:GameSession
var panel:CampaignHospitalPanel

func _initialize()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=").replace("\\","/")
	var reservation:Dictionary=ReviewPaths.reserve(output,"player-assignment")
	if not reservation.get("ok",false):
		printerr("GAMEPLAY REVIEW PATH ERROR: "+str(reservation.get("code","unknown")));quit(2);return
	test_paths=reservation.paths;output=str(test_paths.output_path)
	_run.call_deferred()

func check(ok:bool,label:String,detail:Variant=null)->void:
	checks.append({"ok":ok,"check":label,"detail":detail})
	if ok:passed+=1
	else:failed+=1
	print(("ASSIGNMENT BOUNDARY PASS: " if ok else "ASSIGNMENT BOUNDARY FAIL: ")+label+(" "+str(detail) if detail!=null else ""))

func command(kind:String,payload:Dictionary)->Dictionary:
	var result:Dictionary=session.issue(kind,payload)
	check(result.get("ok",false),"public "+kind,result.get("code",""))
	return result

func build(kind:String)->String:
	var definition:Dictionary=session.catalog.campaign.facilities[kind]
	var layout:Dictionary=FacilityLayout.default_layout(str(definition.unit_id),kind,0)
	for cell:int in range(GridService.WIDTH*GridService.HEIGHT):
		var proposal:Dictionary={"id":"assignment_preview","kind":"campaign_department","ruleset":CampaignContent.RULESET,"unit_id":definition.unit_id,"origin_cell":cell,"rotation":0,"layout":layout,"width":layout.width,"height":layout.height,"status":"open"}
		if not FacilityLayout.preview(session.sim._state,proposal).get("ok",false):continue
		var result:Dictionary=command("build_department",{"unit_id":definition.unit_id,"origin_cell":cell,"layout":layout})
		return str(result.get("data",{}).get("facility_ids",[""])[0]) if result.get("ok",false) else ""
	check(false,"can place "+kind);return ""

func choose(key:String,value:String)->bool:
	var option:OptionButton=panel.controls.get(key)
	if option==null:check(false,"choice exists "+key);return false
	for i:int in range(option.item_count):
		if str(option.get_item_metadata(i))==value:
			option.select(i);option.item_selected.emit(i);return true
	check(false,"choice has target "+key,value);return false

func refresh()->void:
	panel.present(session.presentation_snapshot())
	panel._render()

func _run()->void:
	root.size=Vector2i(932,430)
	var loaded:Dictionary=ContentCatalog.load_checked("res://content")
	check(loaded.get("ok",false),"real content loads")
	if not loaded.get("ok",false):finish();return
	var save_root:String=test_paths.fixture("hospital")
	if save_root=="":printerr("GAMEPLAY REVIEW PATH ERROR: fixture_create_failed");quit(2);return
	session=GameSession.new(loaded.catalog,save_root)
	check(session.start_level("long_01").get("ok",false),"formal factory starts")
	var first:String=build("U04-E1")
	var second:String=build("U04-E1")
	var reception:String=build("O01")
	var ha:Dictionary=command("hire",{"role":"doctor"})
	var hb:Dictionary=command("hire",{"role":"doctor"})
	var a:String=str(ha.get("data",{}).get("staff_id",""))
	var b:String=str(hb.get("data",{}).get("staff_id",""))
	if first=="" or second=="" or reception=="" or a=="" or b=="":finish();return
	command("assign",{"staff_id":a,"facility_id":first})
	command("assign",{"staff_id":b,"facility_id":second})
	panel=CampaignHospitalPanel.new();root.add_child(panel);panel.initialize(session)
	panel.configure(Rect2(59,0,814,409));panel.show_section("staff")
	choose("assign_staff",a);choose("assign_facility",second)
	choose("assign_staff",b);choose("assign_facility",first)
	choose("assign_staff",a)
	check(panel._selected("assign_facility")==second,"employee A keeps own unconfirmed target")
	choose("assign_staff",b)
	check(panel._selected("assign_facility")==first,"employee B keeps a separate unconfirmed target")
	choose("assign_staff",a)
	var before_fail:Dictionary=session.sim.snapshot()
	var rejected:Dictionary=panel._issue("assign",{"staff_id":a,"facility_id":second})
	check(not rejected.get("ok",false) and rejected.get("code","")=="role_filled","occupied second station rejects assignment normally")
	refresh()
	check(panel._selected("assign_facility")==second,"failed confirmation retains the player's intended target")
	check(session.sim.snapshot().staff==before_fail.staff and session.sim.snapshot().cash==before_fail.cash,"rejected assignment cannot move staff or charge cash")
	check(panel._issue("unassign",{"staff_id":b}).get("ok",false),"free target through public panel unassign")
	check(panel._issue("assign",{"staff_id":a,"facility_id":second}).get("ok",false),"confirm intended target when it becomes available")
	refresh()
	check(session.sim.snapshot().staff[a].facility_id==second,"successful confirmation assigns the intended real device")
	# An external model command changes the actual assignment afterwards. A
	# consumed old draft must not override this new model fact on redraw.
	command("unassign",{"staff_id":a});refresh()
	check(panel._selected("assign_facility")==first,"successful confirmation consumed its draft rather than overriding a later external unassign")
	command("assign",{"staff_id":a,"facility_id":second});refresh()
	choose("assign_facility",first)
	command("remove_facility",{"facility_id":first});refresh()
	check(panel._selected("assign_facility")==second,"removed draft target falls back to the real surviving assignment")
	refresh()
	check(panel._selected("assign_facility")==second,"removed target cannot reappear on a second redraw")
	var invalid_choice:OptionButton=panel.controls.assign_facility
	invalid_choice.set_item_metadata(invalid_choice.selected,reception)
	invalid_choice.item_selected.emit(invalid_choice.selected)
	refresh()
	check(panel._selected("assign_facility")==second,"malformed role-incompatible UI draft cannot replace a legal doctor's target")
	choose("assign_facility",second)
	var old_choice:OptionButton=panel.controls.assign_facility
	var old_index:int=old_choice.selected
	check(session.start_level("long_01").get("ok",false),"explicit new hospital replaces simulation through public factory")
	var new_first:String=build("U04-E1")
	var new_second:String=build("U04-E1")
	var new_hire:Dictionary=command("hire",{"role":"doctor"})
	var new_a:String=str(new_hire.get("data",{}).get("staff_id",""))
	command("assign",{"staff_id":new_a,"facility_id":new_first})
	panel.show_section("staff")
	check(a==new_a and second==new_second,"new hospital deliberately reuses staff and facility IDs for isolation boundary")
	check(panel._selected("assign_facility")==new_first,"same IDs in another simulation cannot revive an earlier hospital's draft")
	if is_instance_valid(old_choice):old_choice.item_selected.emit(old_index)
	refresh()
	check(panel._selected("assign_facility")==new_first,"late callback from the old hospital cannot populate the new hospital's draft")
	panel.show_section("patients")
	var before_navigation:Dictionary=session.sim.snapshot()
	check(panel.controls.has("clinical_policy_entry"),"patient list exposes the real clinical strategy entry")
	if panel.controls.has("clinical_policy_entry"):panel.controls.clinical_policy_entry.pressed.emit()
	for _n:int in range(4):await process_frame
	check(panel.section=="cases" and panel.controls.has("clinical_policy"),"strategy entry navigates to the existing strategy editor")
	check(session.sim.snapshot()==before_navigation,"strategy navigation neither issues model commands nor changes the player's policy")
	check(session.sim.snapshot().campaign.clinical_policy=="manual","manual policy survives merely opening its settings")
	check(SnapshotValidator.validate(session.sim.snapshot(),loaded.catalog)=="","all boundary hospital changes remain strictly save-valid")
	finish()

func finish()->void:
	if panel!=null:panel.free();panel=null
	if test_paths.write_report({"passed":passed,"failed":failed,"checks":checks,"scope":"Mechanical UI draft and navigation boundaries over real paid public commands. No fabricated clinical state or physical-device claim."},"  ")!=OK:
		printerr("GAMEPLAY REVIEW PATH ERROR: report_write_failed");quit(2);return
	print("ASSIGNMENT BOUNDARY RESULT: passed=%d failed=%d"%[passed,failed])
	quit(1 if failed>0 else 0)
