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
	var reservation:Dictionary=OnboardingPaths.reserve(output,"onboarding-staffing-boundaries")
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

func _fresh(level:String="long_01")->bool:
	if host!=null:host.free();host=null;await create_timer(.15).timeout
	var loaded:Dictionary=ContentCatalog.load_checked("res://content")
	if not check(loaded.get("ok",false),"real catalog loads for boundary"):return false
	catalog=loaded.catalog
	var profile:String=paths.fixture("staffing-boundary")
	host=load("res://main.gd").new();host.session=GameSession.new(catalog,profile)
	if not check(host.session.start_level(level).get("ok",false),"public start "+level):return false
	root.add_child(host);await frames()
	host.hud.configure_display(Vector2(932,430),Vector2(932,430),160,Rect2(59,0,814,409))
	host.hud.flow.close();host.session.dismiss_notice()
	return check(host.hud.has_method("show_campaign_staffing") and host.hud.get("staffing_card")!=null,"actual focused staffing implementation available")

func _double_and_stale()->void:
	var ready:bool=await _fresh()
	if not ready:return
	var fid:String=build("O01")
	if fid=="":return
	host.hud.show_campaign_staffing(fid);await frames()
	var card:Variant=host.hud.staffing_card
	var before:Dictionary=host.session.sim.snapshot()
	card.controls.hire_assign.pressed.emit();card.controls.hire_assign.pressed.emit()
	await frames()
	var after:Dictionary=host.session.sim.snapshot()
	check(after.staff.size()==before.staff.size()+1 and after.command_sequence==before.command_sequence+2,"same-frame double activation cannot recruit or assign twice")
	check(after.cash==before.cash-int(catalog.campaign.roles.receptionist.hire_cost),"double activation has exactly one genuine recruitment fee")
	var next:String=build("O01")
	if next=="":return
	host.hud.show_campaign_staffing(next);await frames()
	card.request_fill()
	var hired:Dictionary=issue("hire",{"role":"receptionist"})
	var manual_only:Dictionary=host.session.sim.snapshot()
	await frames()
	check(host.session.sim.snapshot()==manual_only,"new existing employee invalidates a queued hire rather than charging for another")
	check(card.visible and card.controls.use_existing.is_visible_in_tree() and not card.controls.hire_assign.is_visible_in_tree(),"revalidated choice asks to use actual existing employee")
	check(hired.get("ok",false) and host.session.sim.snapshot().staff[str(hired.data.staff_id)].facility_id=="","an external hire is not silently assigned without the player's refreshed choice")
	card.close()

func _existing_reassignment_race()->void:
	var ready:bool=await _fresh()
	if not ready:return
	var a:String=build("O01");var b:String=build("O01")
	var first:Dictionary=issue("hire",{"role":"receptionist"})
	var other:Dictionary=issue("hire",{"role":"receptionist"})
	if a=="" or b=="" or not first.get("ok",false) or not other.get("ok",false):return
	var sid:String=str(first.data.staff_id)
	host.hud.show_campaign_staffing(a);await frames()
	var card:Variant=host.hud.staffing_card
	card.request_fill()
	issue("assign",{"staff_id":sid,"facility_id":b})
	var manual_only:Dictionary=host.session.sim.snapshot()
	await frames()
	check(host.session.sim.snapshot()==manual_only and host.session.sim.snapshot().staff[sid].facility_id==b,"queued selection cannot steal a worker who was assigned elsewhere before dispatch")
	card.close()

func _partial_recovery()->void:
	var ready:bool=await _fresh()
	if not ready:return
	var a:String=build("O01");var b:String=build("O01")
	var worker:Dictionary=issue("hire",{"role":"receptionist"})
	if a=="" or b=="" or not worker.get("ok",false):return
	var old_sid:String=str(worker.data.staff_id)
	issue("assign",{"staff_id":old_sid,"facility_id":b})
	host.hud.show_campaign_staffing(a);await frames()
	var card:Variant=host.hud.staffing_card
	var before:Dictionary=host.session.sim.snapshot()
	var injection:Dictionary={"done":false,"hired":"","assign_result":{}}
	# Explicit command-result fixture: another genuine public assignment fills
	# the requested slot between the hire and assign commands. No model edits.
	var callback:Callable=func(result:Dictionary)->void:
		if injection.done or not result.get("ok",false) or result.get("data",{}).get("command",{}).get("type","")!="hire":return
		injection.done=true;injection.hired=str(result.data.staff_id)
		injection.assign_result=host.session.issue("assign",{"staff_id":old_sid,"facility_id":a})
	host.session.command_result.connect(callback)
	await tap(card.controls.hire_assign)
	host.session.command_result.disconnect(callback)
	var partial:Dictionary=host.session.sim.snapshot()
	var new_sid:String=str(injection.hired)
	check(injection.done and injection.assign_result.get("ok",false),"partial-failure fixture really fills the slot via public assignment")
	check(partial.staff.size()==before.staff.size()+1 and partial.cash==before.cash-int(catalog.campaign.roles.receptionist.hire_cost),"successful hire survives failed assignment with exactly one fee")
	check(partial.staff.has(new_sid) and partial.staff[new_sid].facility_id=="" and partial.staff[old_sid].facility_id==a,"partial assignment failure retains actual newly hired idle worker")
	check(card.visible and text_of(card).contains("保留"),"partial result explains the retained worker in the same focused card")
	card.request_fill();await frames()
	check(host.session.sim.snapshot()==partial,"retry while original slot is filled cannot charge another hire")
	card.close();host.hud.show_campaign_staffing(a);await frames()
	check(host.session.sim.snapshot()==partial and not card.controls.hire_assign.is_visible_in_tree(),"closing and reopening partial result retains no-hire recovery")
	issue("unassign",{"staff_id":old_sid})
	await frames()
	var retry_before:Dictionary=host.session.sim.snapshot()
	await tap(card.controls.use_existing)
	var recovered:Dictionary=host.session.sim.snapshot()
	check(recovered.staff[new_sid].facility_id==a and recovered.cash==retry_before.cash and recovered.staff.size()==retry_before.staff.size(),"continuation assigns the already paid worker without recruiting again")
	check(SnapshotValidator.validate(recovered,catalog)=="","recovered partial-flow hospital remains strict-valid")

func _owner_and_storage()->void:
	var ready:bool=await _fresh()
	if not ready:return
	var fid:String=build("O01")
	if fid=="":return
	host.hud.show_campaign_staffing(fid);await frames()
	var card:Variant=host.hud.staffing_card
	card.request_fill()
	check(host.session.start_level("career_01").get("ok",false),"explicit public switch replaces only this isolated fixture")
	var switched:Dictionary=host.session.sim.snapshot()
	await frames()
	check(host.session.sim.snapshot()==switched and not card.visible,"queued staffing cannot cross into another hospital even when IDs repeat")
	var second:String=build("O01")
	if second=="":return
	host.hud.show_campaign_staffing(second);await frames()
	var storage_before:Dictionary=host.session.sim.snapshot()
	# Transient session storage failure boundary, never clinical data injection.
	host.session.storage_blocked=true;card.present();card.request_fill();await frames()
	check(host.session.sim.snapshot()==storage_before and card.controls.hire_assign.disabled,"storage-blocked session disables hiring without touching clinical state")
	host.session.storage_blocked=false;card.close()

func _multi_role()->void:
	var ready:bool=await _fresh("career_01")
	if not ready:return
	# Legacy factory legitimately permits the existing three-role equipment;
	# this fixture is not a new-mode unlock or campaign progression claim.
	var fid:String=build("U09-E1")
	if fid=="":return
	host.hud.show_campaign_staffing(fid);await frames()
	var card:Variant=host.hud.staffing_card
	var roles:Array=catalog.campaign.facilities["U09-E1"].roles
	for index:int in range(roles.size()):
		var before:Dictionary=host.session.sim.snapshot()
		check(card.visible and card.controls.hire_assign.is_visible_in_tree(),"multi-role slot presents one explicit paid choice "+str(index))
		await tap(card.controls.hire_assign)
		var after:Dictionary=host.session.sim.snapshot()
		check(after.staff.size()==before.staff.size()+1 and after.facilities[fid].staff_ids.size()==index+1 and after.cash==before.cash-int(catalog.campaign.roles[roles[index]].hire_cost),"one confirmation fills exactly one actual required role "+str(index))
		if index<roles.size()-1:check(card.visible,"same card continues to next required role without full staff menu")
	var final:Dictionary=host.session.sim.snapshot()
	var actual:Array=[]
	for sid:String in final.facilities[fid].staff_ids:actual.append(final.staff[sid].role)
	check(actual==roles and not card.visible,"duplicate doctor roles use separate paid employees before final card closes")
	check(SnapshotValidator.validate(final,catalog)=="","actual multi-role hospital stays strict-valid")

func _run()->void:
	root.size=Vector2i(932,430)
	await _double_and_stale()
	await _existing_reassignment_race()
	await _partial_recovery()
	await _owner_and_storage()
	await _multi_role()
	await finish()

func finish()->void:
	if host!=null:host.free();host=null
	await create_timer(.24).timeout
	if paths.write_report({"passed":passed,"failed":failed,"checks":checks,"scope":"Actual Main, public commands and ScreenTouch; explicitly mechanical same-frame races and a public command-result interleaving fixture. Storage blocking is transient session state only. Multi-role uses an actual legacy factory, not new-mode unlock evidence. No clinical-state or clock injection; not phone or human enjoyment acceptance."})!=OK:printerr("STAFFING CARD WRITE ERROR");quit(2);return
	print("STAFFING BOUNDARY RESULT: passed=%d failed=%d"%[passed,failed])
	quit(1 if failed else 0)
