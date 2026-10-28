extends SceneTree

# A command-built UI fixture, not a normal playthrough or a physical iPhone.
# The purchase action below must arrive through real ScreenTouch GUI delivery.
const Paths=preload("res://tests/support/formal_test_paths.gd")
const SAFE:=Rect2(59,0,814,409)
var paths:Variant
var passed:int=0
var failed:int=0
var checks:Array=[]
var metrics:Dictionary={}
var host:Variant

func _initialize()->void:
	var output:String=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	var reserved:Dictionary=Paths.reserve(output,"resource-short-screen")
	if not reserved.get("ok",false):
		printerr("FORMAL TEST PATH ERROR: "+str(reserved.get("code","unknown")));quit(2);return
	paths=reserved.paths
	_run.call_deferred()

func check(ok:bool,label:String,detail:Variant="")->bool:
	checks.append({"ok":ok,"check":label,"detail":detail})
	if ok:passed+=1
	else:failed+=1
	print(("RESOURCE SCREEN PASS: " if ok else "RESOURCE SCREEN FAIL: ")+label+" "+str(detail))
	return ok

func settle()->void:
	for _n:int in range(4):await process_frame

func issue(type:String,payload:Dictionary)->Dictionary:
	var result:Dictionary=host.session.issue(type,payload)
	check(result.get("ok",false),"public fixture "+type,result.get("code",""))
	return result

func clipped_rect(control:Control)->Rect2:
	var visible_rect:Rect2=control.get_global_rect().intersection(SAFE)
	var ancestor:Node=control.get_parent()
	while ancestor!=null:
		if ancestor is Control and ancestor.clip_contents:
			visible_rect=visible_rect.intersection(ancestor.get_global_rect())
		ancestor=ancestor.get_parent()
	return visible_rect.intersection(root.get_visible_rect())

func tap(point:Vector2)->void:
	for down:bool in [true,false]:
		var event:=InputEventScreenTouch.new()
		event.index=0;event.pressed=down;event.position=point
		Input.parse_input_event(event)
		await process_frame
	await settle()

func _run()->void:
	root.size=Vector2i(932,430)
	var loaded:Dictionary=ContentCatalog.load_checked("res://content")
	if not check(loaded.get("ok",false),"real catalog loads"):await finish();return
	var save_path:String=paths.fixture("normal-main-hospital")
	if save_path=="":printerr("FORMAL TEST PATH ERROR: fixture_create_failed");quit(2);return
	host=load("res://main.gd").new()
	host.session=GameSession.new(loaded.catalog,save_path)
	root.add_child(host)
	await settle()
	host.hud.configure_display(Vector2(932,430),Vector2(932,430),160,SAFE)
	host.hud.flow.close();host.session.dismiss_notice()
	check(host.session.sim.snapshot().paused,"fixture keeps actual new hospital paused")
	var definition:Dictionary=loaded.catalog.campaign.facilities["O14"]
	var built:Dictionary=issue("build_department",{"unit_id":definition.unit_id,"origin_cell":25,"layout":FacilityLayout.default_layout(definition.unit_id,"O14",0)})
	if not built.get("ok",false):await finish();return
	var hired:Dictionary=issue("hire",{"role":"logistics"})
	if not hired.get("ok",false):await finish();return
	var assigned:Dictionary=issue("assign",{"staff_id":hired.data.staff_id,"facility_id":built.data.facility_ids[0]})
	if not assigned.get("ok",false):await finish();return
	var panel:CampaignHospitalPanel=host.hud.campaign_panel
	panel.show_section("resource")
	await settle()
	var run:Button=panel.controls.get("resource_run_O14")
	if not check(is_instance_valid(run),"real supplies resource page exposes its O14 operation"):await finish();return
	check(not run.disabled,"real assigned O14 operation is available without state injection")
	panel.scroll.ensure_control_visible(run)
	await settle()
	var bounds:Rect2=run.get_global_rect()
	var visible_bounds:Rect2=clipped_rect(run)
	metrics={"viewport":[932,430],"safe_rect":[59,0,814,409],"scroll_rect":[panel.scroll.global_position.x,panel.scroll.global_position.y,panel.scroll.size.x,panel.scroll.size.y],"button_rect":[bounds.position.x,bounds.position.y,bounds.size.x,bounds.size.y],"visible_button_rect":[visible_bounds.position.x,visible_bounds.position.y,visible_bounds.size.x,visible_bounds.size.y],"footer_visible":panel.footer.visible,"physical_device_measured":false}
	check(panel.scroll.size.y>=48.0,"short-screen body viewport can contain a complete 48px action",panel.scroll.size.y)
	check(bounds.size.y>=48.0 and visible_bounds.size.x>=bounds.size.x-0.5 and visible_bounds.size.y>=bounds.size.y-0.5,"ensure-visible exposes the whole real operation button through every clipping ancestor",metrics)
	var before:Dictionary=host.session.sim.snapshot()
	await tap(bounds.get_center())
	var after:Dictionary=host.session.sim.snapshot()
	var operations:int=0
	for id:String in after.command_receipts:
		if before.command_receipts.has(id):continue
		var command:Dictionary=after.command_receipts[id].data.command
		if command.type=="run_operation" and command.payload.get("facility_kind","")=="O14":operations+=1
	check(operations==1 and after.work_orders.size()==before.work_orders.size()+1,"one real ScreenTouch tap submits exactly one public O14 operation",{"new_operation_receipts":operations,"new_orders":after.work_orders.size()-before.work_orders.size()})
	check(after.rooms==before.rooms and after.facilities==before.facilities and after.staff==before.staff,"touching the resource action cannot purchase or rearrange a fixture")
	check(SnapshotValidator.validate(after,loaded.catalog)=="","actual post-touch operation history remains strictly valid",SnapshotValidator.validate(after,loaded.catalog))
	await settle()
	check(host.session.sim.snapshot().work_orders.size()==after.work_orders.size(),"release and deferred GUI callbacks never duplicate the same operation")
	await finish()

func finish()->void:
	if host!=null:
		host.free();host=null
	await create_timer(0.24).timeout
	if paths.write_report({"passed":passed,"failed":failed,"checks":checks,"metrics":metrics,"scope":"Real NormalMain/HUD, public command-built O14 fixture and actual ScreenTouch GUI delivery at 932x430 safe59,0,814,409; not ordinary gameplay or physical-phone acceptance."})!=OK:
		printerr("FORMAL TEST PATH ERROR: report_write_failed");quit(2);return
	print("RESOURCE SCREEN RESULT: passed=%d failed=%d"%[passed,failed])
	quit(1 if failed else 0)
