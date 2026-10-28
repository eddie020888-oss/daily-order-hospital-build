extends SceneTree

const BRAND_PATH := "res://assets/branding/app-icon-v1.png"
const DISPLAY_CASES := [
	[Vector2i(932,430),Rect2(59,0,814,409)],
	[Vector2i(844,390),Rect2(0,0,844,390)],
	[Vector2i(720,360),Rect2(0,0,720,360)],
]
var passed := 0
var failed := 0

func _initialize() -> void:_run.call_deferred()

func check(ok:bool,label:String) -> bool:
	if ok:passed+=1
	else:failed+=1
	print(("BRAND PASS: " if ok else "BRAND FAIL: ")+label)
	return ok

func _run() -> void:
	check(str(ProjectSettings.get_setting("application/config/icon",""))==BRAND_PATH,"project icon selects the new hospital brand asset")
	_check_source_image()
	var loaded:Dictionary=ContentCatalog.load_checked("res://content")
	if not check(bool(loaded.ok),"real hospital content loads before launch branding"):
		_finish();return
	var save_root:=_isolated_save_root()
	if save_root=="":_finish();return
	var session:=GameSession.new(loaded.catalog,save_root)
	var before:Dictionary=session.sim.snapshot()
	var flow:=HospitalFlowPages.new()
	root.add_child(flow)
	flow.initialize(session)
	for fixture:Array in DISPLAY_CASES:
		root.size=fixture[0]
		flow.configure(fixture[1])
		flow.show_launch()
		for _frame in range(5):await process_frame
		_check_launch(flow,fixture[1],str(fixture[0]))
	check(session.sim.snapshot()==before,"launch branding and responsive layout do not change hospital state")
	flow.free()
	await process_frame
	await _check_live_hud(loaded.catalog,save_root.path_join("hud-brand"))
	_finish()

func _check_live_hud(catalog:ContentCatalog,save_root:String) -> void:
	root.size=Vector2i(932,430)
	var host:Node3D=load("res://main.gd").new()
	host.session=GameSession.new(catalog,save_root)
	root.add_child(host)
	host.set_process(false)
	host.feedback.set_application_active(false)
	host.feedback._music_player.stop()
	for _frame in range(3):await process_frame
	var badge:TextureRect=host.hud.get("_crest") as TextureRect
	check(badge!=null and badge.texture!=null and badge.texture.resource_path==BRAND_PATH,"actual hospital HUD brand badge uses the same asset as the app and launch mark")
	# Launch may hide the normal HUD. Identity is asserted on the actual texture,
	# without claiming that the badge must be visible through a system menu.
	host.free()
	for _frame in range(4):await process_frame

func _check_source_image() -> void:
	if not check(FileAccess.file_exists(BRAND_PATH),"new brand PNG exists as a real source asset"):return
	var bytes:=FileAccess.get_file_as_bytes(BRAND_PATH)
	check(bytes.size()>33 and bytes.slice(0,8)==PackedByteArray([137,80,78,71,13,10,26,10]) and bytes[24]==8 and bytes[25]==2,"source PNG is encoded as eight-bit RGB without an alpha channel")
	var image:=Image.load_from_file(BRAND_PATH)
	if not check(image!=null and not image.is_empty(),"new hospital mark decodes from its actual PNG pixels"):return
	check(image.get_width()==image.get_height() and image.get_width()>=1024,"source brand is square and large enough for the real iOS icon")
	check(image.get_format()==Image.FORMAT_RGB8 and image.detect_alpha()==Image.ALPHA_NONE,"decoded source retains opaque RGB pixels")

func _check_launch(flow:HospitalFlowPages,safe:Rect2,label:String) -> void:
	check(flow.page=="launch" and safe.grow(.1).encloses(flow.panel.get_global_rect()),label+" launch panel remains inside the phone safe area")
	var brands:Array[TextureRect]=[]
	for node:Node in flow.panel.find_children("*","TextureRect",true,false):
		var picture:=node as TextureRect
		if picture.texture!=null and picture.texture.resource_path==BRAND_PATH:brands.append(picture)
	if check(brands.size()==1,label+" actual launch header displays the same asset as the app icon"):
		var brand:TextureRect=brands[0]
		check(brand.is_visible_in_tree() and safe.grow(.1).encloses(brand.get_global_rect()) and flow.panel.get_global_rect().encloses(brand.get_global_rect()),label+" brand mark is visible inside the launch header")
		check(brand.stretch_mode==TextureRect.STRETCH_KEEP_ASPECT_CENTERED and brand.size.x>=40 and brand.size.y>=40,label+" mark preserves its aspect and readable minimum footprint")
	for key:String in ["continue_game","start_new"]:
		var action:Button=flow.controls[key]
		check(action.is_visible_in_tree() and safe.grow(.1).encloses(action.get_global_rect()) and action.size.y>=48,label+" "+key+" remains a reachable launch action")

func _isolated_save_root() -> String:
	var suffix:="brand-identity-%d/save"%Time.get_ticks_usec()
	if OS.get_name()=="macOS":
		var runtime:=OS.get_environment("HOSPITAL_CI_RUNTIME_ROOT").replace("\\","/").simplify_path().trim_suffix("/")
		var runner:=OS.get_environment("RUNNER_TEMP").replace("\\","/").simplify_path().trim_suffix("/")
		if not check(runtime.is_absolute_path() and runner.is_absolute_path() and runtime==runner.path_join("hospital-ios-build/runtime"),"Mac brand fixture uses the exact isolated runtime"):return ""
		return runtime.path_join(suffix)
	return "E:/CODEX/2026-10-27/医院缩放与扩建场景补全/temp/"+suffix

func _finish() -> void:
	print("BRAND IDENTITY RESULT: passed=%d failed=%d"%[passed,failed])
	quit(1 if failed else 0)
