extends SceneTree

# Actual Main / actual first-exam facility / focused card. This is a
# presentation regression: no employee is hired and no model time is injected.
const Paths=preload("res://tests/support/onboarding_test_paths.gd")
var paths:Variant
var host:Variant
var catalog:ContentCatalog
var passed:int=0
var failed:int=0
var checks:Array=[]
var geometry:Dictionary={}

func _initialize()->void:
	var requested:String=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):requested=arg.trim_prefix("--output=")
	var reservation:Dictionary=Paths.reserve(requested,"onboarding-staffing-header-layout")
	if not reservation.get("ok",false):printerr("STAFFING HEADER PATH ERROR");quit(2);return
	paths=reservation.paths
	_run.call_deferred()

func check(ok:bool,label:String,detail:Variant=null)->bool:
	checks.append({"ok":ok,"check":label,"detail":detail})
	if ok:passed+=1
	else:failed+=1
	print(("STAFFING HEADER PASS: " if ok else "STAFFING HEADER FAIL: ")+label)
	return ok

func frames(count:int=5)->void:
	for _i:int in range(count):await process_frame

func build()->String:
	var kind:String="U04-E1"
	var definition:Dictionary=catalog.campaign.facilities[kind]
	var layout:Dictionary=FacilityLayout.default_layout(str(definition.unit_id),kind,0)
	for cell:int in range(432):
		var proposal:Dictionary={"unit_id":definition.unit_id,"origin_cell":cell,"rotation":0,"layout":layout}
		if not FacilityLayout.preview(host.session.sim.snapshot(),proposal).get("ok",false):continue
		var result:Dictionary=host.session.issue("build_department",{"unit_id":definition.unit_id,"origin_cell":cell,"layout":layout})
		if not check(result.get("ok",false),"public fixture builds one real first-exam facility",result):return ""
		return str(result.data.facility_ids[0])
	check(false,"actual hospital has space for the real first-exam fixture")
	return ""

func _run()->void:
	root.size=Vector2i(932,430)
	var loaded:Dictionary=ContentCatalog.load_checked("res://content")
	if not check(loaded.get("ok",false),"real content loads"):await finish();return
	catalog=loaded.catalog
	var profile:String=paths.fixture("staffing-header-profile")
	if not check(profile!="","fresh isolated profile"):await finish();return
	host=load("res://main.gd").new();host.session=GameSession.new(catalog,profile)
	if not check(host.session.start_level("long_01").get("ok",false),"public formal hospital starts"):await finish();return
	root.add_child(host);await frames()
	host.hud.configure_display(Vector2(932,430),Vector2(932,430),160,Rect2(59,0,814,409))
	host.hud.flow.close();host.session.dismiss_notice()
	var fid:String=build()
	if fid=="":await finish();return
	await frames()
	if not check(host.hud.show_campaign_staffing(fid),"actual focused staffing card opens for the real first-exam device"):await finish();return
	await frames()
	var card:Variant=host.hud.staffing_card
	var title:Label=card._title
	var dismiss:Button=card.controls.close
	var header:HBoxContainer=dismiss.get_parent()
	var header_rect:Rect2=header.get_global_rect()
	var title_rect:Rect2=title.get_global_rect()
	var close_rect:Rect2=dismiss.get_global_rect()
	var separation:int=header.get_theme_constant("separation")
	var required_text:float=title.get_theme_font("font").get_string_size(title.text,HORIZONTAL_ALIGNMENT_LEFT,-1,title.get_theme_font_size("font_size")).x
	geometry={"card":card.get_global_rect(),"header":header_rect,"title":title_rect,"close":close_rect,"header_separation":separation,"title_text":title.text,"title_required_width":required_text}
	check(absf(card.size.x-350.0)<=1.0,"actual phone staffing card retains normal350px width",card.size)
	check(title.text==str(catalog.campaign.facilities["U04-E1"].name)+" · 安排岗位","header uses complete actual facility name and action",title.text)
	check(absf(close_rect.size.x-48.0)<=1.0 and close_rect.size.y>=48.0,"close control keeps48px touch width instead of consuming half the header",geometry)
	check((dismiss.size_flags_horizontal & Control.SIZE_EXPAND)==0,"header close has no horizontal expansion flag",dismiss.size_flags_horizontal)
	check((title.size_flags_horizontal & Control.SIZE_EXPAND)!=0 and absf(title_rect.size.x-(header_rect.size.x-close_rect.size.x-float(separation)))<=1.0,"title receives all header width left after fixed close and separation",geometry)
	check(required_text<=title_rect.size.x+1.0,"representative actual long facility title fits without premature ellipsis",geometry)
	check(card.get_global_rect().encloses(close_rect) and card.get_global_rect().encloses(title_rect) and not title_rect.intersects(close_rect),"title and whole close target stay inside card without overlap",geometry)
	var primary:Button=card.controls.hire_assign
	var manage:Button=card.controls.manage_staff
	check(primary.is_visible_in_tree() and manage.is_visible_in_tree() and (primary.size_flags_horizontal & Control.SIZE_EXPAND)!=0 and (manage.size_flags_horizontal & Control.SIZE_EXPAND)!=0,"header fix preserves expanding footer actions")
	check(primary.size.x>=48.0 and primary.size.y>=48.0 and manage.size.x>=48.0 and manage.size.y>=48.0,"footer actions retain minimum touch targets")
	var before:Dictionary=host.session.sim.snapshot()
	var point:Vector2=close_rect.get_center()
	var down:=InputEventScreenTouch.new();down.index=0;down.pressed=true;down.position=point;Input.parse_input_event(down)
	await process_frame
	var up:=InputEventScreenTouch.new();up.index=0;up.pressed=false;up.position=point;Input.parse_input_event(up)
	await frames()
	check(not card.visible,"real ScreenTouch closes the compact header button")
	check(host.session.sim.snapshot()==before,"header inspection and close cannot hire pay or alter the hospital")
	await finish()

func finish()->void:
	if host!=null:host.free();host=null
	await create_timer(.24).timeout
	if paths.write_report({"passed":passed,"failed":failed,"checks":checks,"geometry":geometry,"scope":"Actual Main phone-sized safe area, actual first-exam title from catalog, real public build fixture, measured header/footer geometry and ScreenTouch close. No hiring, clock injection or physical-phone claim."})!=OK:
		printerr("STAFFING HEADER WRITE ERROR");quit(2);return
	print("STAFFING HEADER RESULT: passed=%d failed=%d"%[passed,failed]);quit(1 if failed else 0)
