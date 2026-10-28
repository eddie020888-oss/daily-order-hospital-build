extends SceneTree

# Read-only product audit probe. The prepared hospital uses real public commands;
# selecting an OptionButton programmatically is a mechanical UI fixture, not a
# human/native touch acceptance or a normal-player playthrough.
const ReviewPaths=preload("res://tests/support/gameplay_review_paths.gd")
var test_paths:Variant
var output:String=""
var passed:int=0
var failed:int=0
var checks:Array=[]
var host:Variant
var setup_ok:bool=true

func _initialize()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=").replace("\\","/")
	var reservation:Dictionary=ReviewPaths.reserve(output,"player-choice")
	if not reservation.get("ok",false):
		printerr("GAMEPLAY REVIEW PATH ERROR: "+str(reservation.get("code","unknown")));quit(2);return
	test_paths=reservation.paths;output=str(test_paths.output_path)
	_run.call_deferred()

func check(ok:bool,label:String,detail:Variant=null)->void:
	checks.append({"ok":ok,"check":label,"detail":detail})
	if ok:passed+=1
	else:failed+=1
	print(("PLAYER FLOW PASS: " if ok else "PLAYER FLOW FAIL: ")+label+(" "+str(detail) if detail!=null else ""))

func command(kind:String,payload:Dictionary)->Dictionary:
	var result:Dictionary=host.session.issue(kind,payload)
	check(result.get("ok",false),"setup public "+kind,result.get("code",""))
	if not result.get("ok",false):setup_ok=false
	return result

func build(kind:String)->String:
	var definition:Dictionary=host.session.catalog.campaign.facilities[kind]
	var layout:Dictionary=FacilityLayout.default_layout(str(definition.unit_id),kind,0)
	for cell:int in range(GridService.WIDTH*GridService.HEIGHT):
		var proposal:Dictionary={"id":"flow_probe_preview","kind":"campaign_department","ruleset":CampaignContent.RULESET,"unit_id":definition.unit_id,"origin_cell":cell,"rotation":0,"layout":layout,"width":layout.width,"height":layout.height,"status":"open"}
		if not FacilityLayout.preview(host.session.sim._state,proposal).get("ok",false):continue
		var result:Dictionary=command("build_department",{"unit_id":definition.unit_id,"origin_cell":cell,"layout":layout})
		return str(result.get("data",{}).get("facility_ids",[""])[0]) if result.get("ok",false) else ""
	check(false,"fixture can place "+kind);setup_ok=false;return ""

func _run()->void:
	root.size=Vector2i(932,430)
	var loaded:Dictionary=ContentCatalog.load_checked("res://content")
	check(loaded.get("ok",false),"actual content loads")
	if not loaded.get("ok",false):finish();return
	var save_root:String=test_paths.fixture("hospital")
	if save_root=="":printerr("GAMEPLAY REVIEW PATH ERROR: fixture_create_failed");quit(2);return
	host=load("res://main.gd").new()
	host.session=GameSession.new(loaded.catalog,save_root)
	check(host.session.start_level("long_01").get("ok",false),"real formal new factory")
	root.add_child(host)
	for _n:int in range(4):await process_frame
	host.hud.configure_display(Vector2(932,430),Vector2(932,430),160,Rect2(59,0,814,409))
	host.hud.flow.close();host.session.dismiss_notice()
	var first:String=build("U04-E1")
	var second:String=build("U04-E1")
	var hired:Dictionary=command("hire",{"role":"doctor"})
	var sid:String=str(hired.get("data",{}).get("staff_id",""))
	if first=="" or second=="" or sid=="" or not setup_ok:finish();return
	command("assign",{"staff_id":sid,"facility_id":first})
	host.hud._show_campaign("staff")
	command("set_paused",{"paused":false})
	for _n:int in range(3):await process_frame
	await create_timer(4.0).timeout
	var panel=host.hud.campaign_panel
	var choice:OptionButton=panel.controls.get("assign_facility")
	check(choice!=null and choice.item_count==2,"two same-role real destination facilities")
	if choice==null or choice.item_count!=2:finish();return
	for i:int in range(choice.item_count):
		if str(choice.get_item_metadata(i))==second:
			choice.select(i);choice.item_selected.emit(i);break
	var selected_before:String=panel._selected("assign_facility")
	check(selected_before==second,"player selected intended second workplace")
	var before_tick:int=int(host.session.sim.snapshot().tick)
	# Main remains active. The real clock and changed/present chain perform the
	# normal one-second page refresh; no tick/data/receipt injection occurs here.
	await create_timer(1.45).timeout
	var after_tick:int=int(host.session.sim.snapshot().tick)
	var selected_after:String=panel._selected("assign_facility")
	check(after_tick-before_tick>=10,"real Main clock passed one UI refresh",{"before_tick":before_tick,"after_tick":after_tick})
	check(selected_after==second,"unconfirmed workplace selection survives operating refresh",{"actual":selected_after,"expected":second,"original":first})
	panel.controls.assign.pressed.emit()
	for _n:int in range(2):await process_frame
	var assigned:String=str(host.session.sim.snapshot().staff[sid].facility_id)
	check(assigned==second,"assign button uses workplace the player selected",{"actual":assigned,"expected":second,"original":first})
	var second_hire:Dictionary=command("hire",{"role":"doctor"})
	var second_sid:String=str(second_hire.get("data",{}).get("staff_id",""))
	panel.show_section("growth")
	_choose(panel,"training_staff",second_sid)
	_choose(panel,"training_unit","U02")
	await create_timer(1.45).timeout
	check(panel._selected("training_staff")==second_sid and panel._selected("training_unit")=="U02","training employee and specialty drafts survive normal refresh")
	panel.show_section("finance")
	_choose(panel,"procurement_policy","economy")
	await create_timer(1.45).timeout
	check(panel._selected("procurement_policy")=="economy","unconfirmed procurement draft survives normal refresh")
	panel.show_section("cases")
	_choose(panel,"clinical_policy","thorough")
	await create_timer(1.45).timeout
	check(panel._selected("clinical_policy")=="thorough","unconfirmed clinical strategy draft survives normal refresh")
	check(SnapshotValidator.validate(host.session.sim.snapshot(),loaded.catalog)=="","model remains strictly valid")
	finish()

func _choose(panel:Variant,key:String,value:String)->void:
	var option:OptionButton=panel.controls.get(key)
	if option==null:check(false,"choice exists "+key);return
	for i:int in range(option.item_count):
		if str(option.get_item_metadata(i))==value:
			option.select(i);option.item_selected.emit(i);return
	check(false,"choice has requested value "+key,value)

func finish()->void:
	if host!=null:
		host.free();host=null
		await create_timer(.24).timeout
	if test_paths.write_report({"passed":passed,"failed":failed,"checks":checks,"scope":"Prepared real Main/HUD and public model commands; mechanical UI select fixture, real wall-clock refresh; no physical iPhone or full gameplay acceptance."},"  ")!=OK:
		printerr("GAMEPLAY REVIEW PATH ERROR: report_write_failed");quit(2);return
	print("PLAYER FLOW RESULT: passed=%d failed=%d"%[passed,failed])
	quit(1 if failed>0 else 0)
