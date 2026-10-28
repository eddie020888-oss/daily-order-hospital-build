extends SceneTree

# Real Main + public-command staffing fixture. Actual taps are ScreenTouch;
# direct request/close at the end is an explicitly mechanical cancellation edge.
const OnboardingPaths=preload("res://tests/support/onboarding_test_paths.gd")
var paths:Variant
var host:Variant
var catalog:ContentCatalog
var passed:int=0
var failed:int=0
var checks:Array=[]
var pointer:int=0

func _initialize()->void:
	var output:String=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=").replace("\\","/")
	var reservation:Dictionary=OnboardingPaths.reserve(output,"onboarding-staffing-card")
	if not reservation.get("ok",false):printerr("STAFFING CARD PATH ERROR");quit(2);return
	paths=reservation.paths
	_run.call_deferred()

func check(ok:bool,label:String,detail:Variant=null)->bool:
	checks.append({"ok":ok,"check":label,"detail":detail})
	if ok:passed+=1
	else:failed+=1
	print(("STAFFING CARD PASS: " if ok else "STAFFING CARD FAIL: ")+label)
	return ok

func frames(count:int=4)->void:
	for _n:int in range(count):await process_frame

func issue(type:String,payload:Dictionary)->Dictionary:
	var result:Dictionary=host.session.issue(type,payload)
	check(result.get("ok",false),"public fixture command "+type,result.get("code",""))
	return result

func build(kind:String)->String:
	var definition:Dictionary=catalog.campaign.facilities[kind]
	var layout:Dictionary=FacilityLayout.default_layout(str(definition.unit_id),kind,0)
	for cell:int in range(432):
		var proposal:Dictionary={"id":"staffing_probe","kind":"campaign_department","ruleset":CampaignContent.RULESET,"unit_id":definition.unit_id,"origin_cell":cell,"rotation":0,"layout":layout,"width":layout.width,"height":layout.height,"status":"open"}
		if not FacilityLayout.preview(host.session.sim._state,proposal).get("ok",false):continue
		var result:Dictionary=issue("build_department",{"unit_id":definition.unit_id,"origin_cell":cell,"layout":layout})
		return str(result.get("data",{}).get("facility_ids",[""])[0]) if result.get("ok",false) else ""
	check(false,"fixture can place "+kind)
	return ""

func tap(button:Button)->void:
	if not check(button!=null and button.is_visible_in_tree() and not button.disabled,"actual touch target visible and enabled"):return
	var point:Vector2=button.get_global_rect().get_center()
	check(Rect2(Vector2.ZERO,Vector2(root.size)).has_point(point),"touch center in actual viewport",point)
	var down:=InputEventScreenTouch.new();down.index=pointer;down.pressed=true;down.position=point
	Input.parse_input_event(down);await process_frame
	var up:=InputEventScreenTouch.new();up.index=pointer;up.pressed=false;up.position=point
	Input.parse_input_event(up);pointer+=1;await frames()

func text_of(node:Node)->String:
	var text:String=""
	if node is Label:text+=node.text+"\n"
	elif node is Button:text+=node.text+"\n"
	for child:Node in node.get_children():text+=text_of(child)
	return text

func _run()->void:
	root.size=Vector2i(932,430)
	var loaded:Dictionary=ContentCatalog.load_checked("res://content")
	if not check(loaded.get("ok",false),"real content loads"):await finish();return
	catalog=loaded.catalog
	var folder:String=paths.fixture("staffing-profile")
	if not check(folder!="","isolated fresh profile"):await finish();return
	host=load("res://main.gd").new()
	host.session=GameSession.new(catalog,folder)
	check(host.session.start_level("long_01").get("ok",false),"public formal hospital starts")
	root.add_child(host);await frames()
	host.hud.configure_display(Vector2(932,430),Vector2(932,430),160,Rect2(59,0,814,409))
	host.hud.flow.close();host.session.dismiss_notice()
	var fid:String=build("O01")
	if fid=="":await finish();return
	await frames()
	var has_route:bool=host.hud.has_method("show_campaign_staffing")
	var card:Variant=host.hud.get("staffing_card")
	check(has_route,"HUD exposes focused staffing flow rather than full staff page")
	check(card!=null,"actual HUD owns focused staffing card")
	if not has_route or card==null:await finish();return
	var before:Dictionary=host.session.sim.snapshot()
	check(host.hud.show_campaign_staffing(fid),"focused card opens exact actual facility")
	await frames()
	check(card.visible and card.facility_id==fid,"card targets requested equipment")
	check(host.session.sim.snapshot()==before,"opening staffing card never hires spends or advances clock")
	var role:String=str(catalog.campaign.facilities.O01.roles[0])
	var price:int=int(catalog.campaign.roles[role].hire_cost)
	var wage:int=CampaignPeople.staff_daily_wage(before,catalog,{"role":role,"wage_percent":100})
	var copy:String=text_of(card)
	check(copy.contains(str(catalog.campaign.roles[role].name)) and copy.contains(str(price)) and copy.contains(str(wage)),"card shows actual role recruitment cost and daily wage",copy)
	check(card.controls.has("hire_assign") and card.controls.has("use_existing") and card.controls.has("manage_staff"),"card exposes explicit current-role actions and full management")
	if not card.controls.has("hire_assign"):await finish();return
	check(card.controls.hire_assign.is_visible_in_tree() and not card.controls.use_existing.is_visible_in_tree(),"no idle worker offers paid hire and assignment only")
	await tap(card.controls.close)
	check(host.session.sim.snapshot()==before,"cancel before action preserves exact hospital")
	await frames()
	await tap(host.hud.opening_card.action_button)
	check(card.visible and card.facility_id==fid and not host.hud.campaign_panel.visible,"real guide tap opens focused equipment staffing without full staff menu")
	await tap(card.controls.hire_assign)
	await frames()
	var after:Dictionary=host.session.sim.snapshot()
	check(after.staff.size()==before.staff.size()+1 and after.cash==before.cash-price,"one touch recruits exactly one paid actual employee")
	var assigned:Array=after.facilities[fid].staff_ids
	check(assigned.size()==1 and after.staff[str(assigned[0])].role==role and after.staff[str(assigned[0])].facility_id==fid,"same actual employee is assigned to exact equipment")
	check(after.command_sequence==before.command_sequence+2,"flow uses exactly the public hire and assign commands")
	card.request_fill();await frames()
	check(host.session.sim.snapshot()==after,"late fill request after completed slot cannot recruit twice")
	var second:String=build("O01")
	var hired:Dictionary=issue("hire",{"role":role})
	if second=="" or not hired.get("ok",false):await finish();return
	var existing:String=str(hired.data.staff_id)
	host.hud.show_campaign_staffing(second);await frames()
	var existing_before:Dictionary=host.session.sim.snapshot()
	check(card.controls.use_existing.is_visible_in_tree() and not card.controls.hire_assign.is_visible_in_tree(),"idle eligible employee is offered before another recruitment")
	await tap(card.controls.use_existing)
	var existing_after:Dictionary=host.session.sim.snapshot()
	check(existing_after.cash==existing_before.cash and existing_after.staff.size()==existing_before.staff.size() and existing_after.staff[existing].facility_id==second,"existing staff action only assigns without duplicate hire or wage creation")
	check(existing_after.command_sequence==existing_before.command_sequence+1,"existing worker path submits one genuine assign command")
	var third:String=build("O01")
	if third!="":
		host.hud.show_campaign_staffing(third);await frames()
		var cancel_before:Dictionary=host.session.sim.snapshot()
		card.request_fill();card.close();await frames()
		check(host.session.sim.snapshot()==cancel_before,"queued fill is canceled when card closes before dispatch")
	check(SnapshotValidator.validate(host.session.sim.snapshot(),catalog)=="","resulting hospital remains strict save valid")
	await finish()

func finish()->void:
	if host!=null:host.free();host=null
	await create_timer(.24).timeout
	if paths.write_report({"passed":passed,"failed":failed,"checks":checks,"scope":"Actual Main and ScreenTouch navigation/actions; prepared public-command hospital and mechanical close race. No fake workers, cash, resources or injected clock. Not human enjoyment or phone acceptance."})!=OK:printerr("STAFFING CARD WRITE ERROR");quit(2);return
	print("STAFFING CARD RESULT: passed=%d failed=%d"%[passed,failed])
	quit(1 if failed else 0)
