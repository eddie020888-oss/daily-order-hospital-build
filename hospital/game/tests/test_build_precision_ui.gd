extends SceneTree

const BOUNDS_KEYS := ["width_less", "width_more", "height_less", "height_more", "move_nw", "move_ne", "move_sw", "move_se"]
const BOUNDS_CHANGES := {
	"width_less": [Vector2i(-1,0), Vector2i.ZERO], "width_more": [Vector2i(1,0), Vector2i.ZERO],
	"height_less": [Vector2i(0,-1), Vector2i.ZERO], "height_more": [Vector2i(0,1), Vector2i.ZERO],
	"move_nw": [Vector2i.ZERO, Vector2i(-1,0)], "move_ne": [Vector2i.ZERO, Vector2i(0,-1)],
	"move_sw": [Vector2i.ZERO, Vector2i(0,1)], "move_se": [Vector2i.ZERO, Vector2i(1,0)]
}
const ISSUE := "房间跨越中央通道，请移开一格。"

var passed := 0
var failed := 0
var host: Node3D
var _events: Array = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> bool:
	if ok: passed += 1
	else: failed += 1
	print(("PRECISION UI PASS: " if ok else "PRECISION UI FAIL: ")+label)
	return ok

func _settle(count: int=4) -> void:
	for _frame in range(count): await process_frame

func _has_property(object: Object, key: String) -> bool:
	for property: Dictionary in object.get_property_list():
		if str(property.name) == key: return true
	return false

func _api_ready(panel: HospitalPlacementPanel) -> bool:
	var ready := check(panel.has_signal("bounds_adjusted"), "panel declares the preview-only bounds-adjusted signal")
	var has_buttons := _has_property(panel,"bounds_buttons")
	ready = check(has_buttons,"panel exposes its eight bounds controls") and ready
	if has_buttons:
		var buttons: Variant = panel.get("bounds_buttons")
		ready = check(buttons is Dictionary,"bounds controls are a dictionary") and ready
		if buttons is Dictionary:
			for key: String in BOUNDS_KEYS:
				ready = check(buttons.has(key) and buttons[key] is Button,"panel creates bounds control "+key) and ready
	var supports_feedback := false
	for method: Dictionary in panel.get_method_list():
		if str(method.name) == "present_free": supports_feedback = method.args.size() >= 9
	ready = check(supports_feedback,"present_free accepts explicit bounds issue and action permissions") and ready
	for method: String in ["set_precision_expanded","set_opening_options_expanded"]:
		ready = check(panel.has_method(method),"wizard supports explicit advanced disclosure via "+method) and ready
	return check(_has_property(panel,"precision_expanded"),"precision disclosure state is explicit") and ready

func _expand_precision(panel: HospitalPlacementPanel) -> void:
	# Build3 deliberately hides these tools until the player asks for them.
	panel.call("set_precision_expanded",true)
	check(panel.get("precision_expanded") == true,"precision regression explicitly opens the optional adjustment tools")

func _visible_inside(control: Control, safe: Rect2) -> bool:
	if not is_instance_valid(control) or not control.is_visible_in_tree(): return false
	var rectangle := control.get_global_rect()
	if rectangle.size.x <= 0 or rectangle.size.y <= 0 or not safe.grow(0.1).encloses(rectangle): return false
	var ancestor := control.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer and not ancestor.get_global_rect().grow(0.1).encloses(rectangle): return false
		ancestor = ancestor.get_parent()
	return true

func _tap(button: Button) -> void:
	var point := button.get_global_rect().get_center()
	for down in [true,false]:
		var event := InputEventScreenTouch.new()
		event.index = 0
		event.pressed = down
		event.position = point
		Input.parse_input_event(event)
		await process_frame
	await _settle(2)

func _project_bounds(panel: HospitalPlacementPanel, snapshot: Dictionary, proposal: Dictionary, issue: String, permissions: Dictionary) -> void:
	# Dynamic call intentionally keeps a missing interface a clean red assertion.
	panel.callv("present_free",[snapshot,proposal,host.session.preview(proposal),0,"","door",{},issue,permissions])

func _all_permissions() -> Dictionary:
	var permissions := {}
	for key: String in BOUNDS_KEYS: permissions[key] = true
	return permissions

func _save_root() -> String:
	var suffix := "precision-ui-%d/save" % Time.get_ticks_usec()
	if OS.get_name() == "macOS":
		var runtime := OS.get_environment("HOSPITAL_CI_RUNTIME_ROOT").replace("\\","/").simplify_path().trim_suffix("/")
		var runner_temp := OS.get_environment("RUNNER_TEMP").replace("\\","/").simplify_path().trim_suffix("/")
		if not check(runtime.is_absolute_path() and runner_temp.is_absolute_path() and runtime == runner_temp.path_join("hospital-ios-build/runtime"),"Mac UI fixture save stays inside the declared isolated CI runtime"):
			return ""
		return runtime.path_join(suffix)
	return "E:/CODEX/2026-10-27/医院建设触控优化/temp/"+suffix

func _shrink_protection(h: HospitalHud, panel: HospitalPlacementPanel, initial: Dictionary, safe: Rect2, viewport_size: Vector2i) -> void:
	for fixture: Dictionary in [
		{"name":"edge north window","window":true,"furniture":[],"button":"width_less","reason":"门窗"},
		{"name":"horizontal modern bench second cell","window":false,"furniture":[{"kind":"bench","x":3,"y":2,"rotation":0}],"button":"width_less","reason":"家具"},
		{"name":"vertical modern bench second cell","window":false,"furniture":[{"kind":"bench","x":3,"y":2,"rotation":1}],"button":"height_less","reason":"家具"}
	]:
		var layout := {
			"width":5,"height":4,"door":{"side":"south","offset":2},
			"doors":[{"side":"south","offset":2}],
			"windows":[{"side":"north","offset":4}] if fixture.window else [],
			"equipment":{},"furniture":fixture.furniture.duplicate(true),"footprint_version":2
		}
		host.touch.begin_free_build("diagnosis","",layout,54)
		h._present_placement_details(initial,h._proposal(),host.session.preview(h._proposal()))
		_expand_precision(panel)
		await _settle()
		var name_value := "%s %s" % [str(viewport_size),fixture.name]
		var button: Button = panel.get("bounds_buttons")[fixture.button]
		check(button.disabled,name_value+" refuses the one-cell shrink that would crop it")
		check(not h.controls.confirm.disabled,name_value+" can still proceed to the ordinary edit steps")
		var feedback := panel.pinned_header.find_child("BuildBoundsFeedback",true,false) as Label
		if check(feedback != null,name_value+" has its fixed crop-protection explanation"):
			check(feedback.text.contains(fixture.reason) and feedback.text.contains("移开"),name_value+" explains which edit step must move the item first")
			check(_visible_inside(feedback,safe) and feedback.get_line_count() <= 2 and feedback.get_visible_line_count() >= feedback.get_line_count(),name_value+" keeps the complete reason visible")
		var size_label := panel.pinned_header.find_child("BuildBoundsSize",true,false) as Label
		check(size_label != null and size_label.text.contains("5×4") and _visible_inside(size_label,safe),name_value+" retains the current 5x4 size readout")
		for key: String in ["confirm","cancel"]:
			check(_visible_inside(h.controls[key],safe),name_value+" leaves "+key+" inside the safe area")
		var draft_before: Dictionary = host.touch.free_build.capture_state().duplicate(true)
		var proposal_before: Dictionary = host.touch.placement.duplicate(true)
		var events_before := _events.size()
		await _tap(button)
		check(host.touch.free_build.capture_state() == draft_before and host.touch.placement == proposal_before,name_value+" ignores parsed touches without deleting or moving any draft item")
		check(_events.size() == events_before,name_value+" disabled target emits no correction")
		check(host.session.sim.snapshot() == initial,name_value+" cannot modify real funds or hospital state")

func _run() -> void:
	var catalog: ContentCatalog = ContentCatalog.load_checked("res://content").catalog
	var api_probe := HospitalPlacementPanel.new()
	api_probe.initialize(catalog)
	var ready := _api_ready(api_probe)
	# The real HUD adopts this header after initialize(); the API-only fixture
	# never attaches it, so own and release that independent node on red too.
	if is_instance_valid(api_probe.pinned_header) and api_probe.pinned_header.get_parent() == null:
		api_probe.pinned_header.free()
	api_probe.free()
	if not ready:
		await _finish()
		return
	var save_root := _save_root()
	if save_root == "":
		await _finish()
		return
	root.size = Vector2i(932,430)
	host = load("res://main.gd").new()
	host.session = GameSession.new(catalog,save_root)
	root.add_child(host)
	host.set_process(false)
	host.feedback.set_application_active(false)
	host.feedback._music_player.stop()
	host.hud.flow.close()
	await _settle(5)
	var h: HospitalHud = host.hud
	h._begin_build("diagnosis")
	host.touch.choose_cell(54)
	host.touch.choose_cell(129) # A real 4x4 local draft with room for all eight corrections.
	await _settle()
	var panel: HospitalPlacementPanel = h.placement_details
	check(panel.get("precision_expanded") == false,"new room task starts with optional precision tools collapsed")
	for key: String in BOUNDS_KEYS: check(not panel.get("bounds_buttons")[key].is_visible_in_tree(),"default room task does not show unrelated "+key+" controls")
	panel.connect("bounds_adjusted",func(size_delta: Vector2i, offset: Vector2i) -> void: _events.append([size_delta,offset]))
	var initial: Dictionary = host.session.sim.snapshot()
	var receipt: String = str(host.touch.placement.id)
	for fixture: Array in [
		[Vector2i(932,430),Rect2(59,0,814,409)],
		[Vector2i(844,390),Rect2(0,0,844,390)],
		[Vector2i(720,360),Rect2(0,0,720,360)]
	]:
		root.size = fixture[0]
		await _settle()
		var viewport_size := Vector2(fixture[0])
		var safe: Rect2 = fixture[1]
		h.configure_display(viewport_size,viewport_size,160,safe)
		await _settle()
		# Exercise the actual HUD-generated long minimum-size reason, rather
		# than only a short test projection that happens to fit on one line.
		host.touch.reposition()
		host.touch.choose_cell(54)
		host.touch.choose_cell(54)
		h._present_placement_details(initial,h._proposal(),host.session.preview(h._proposal()))
		_expand_precision(panel)
		await _settle()
		var actual_issue := panel.pinned_header.find_child("BuildBoundsFeedback",true,false) as Label
		var actual_size := panel.pinned_header.find_child("BuildBoundsSize",true,false) as Label
		if check(actual_issue != null,"real minimum-size failure has a pinned feedback label"):
			check(actual_issue.text.contains("尺寸") and (actual_issue.text.contains("至少") or actual_issue.text.contains("最小")),"%s shows the actual HUD minimum-size reason" % str(fixture[0]))
			check(_visible_inside(actual_issue,safe) and actual_issue.get_line_count() <= 2 and actual_issue.get_visible_line_count() >= actual_issue.get_line_count(),"%s shows the whole long minimum-size reason without clipping" % str(fixture[0]))
		if actual_size != null: check(actual_size.text.contains("1×1") and _visible_inside(actual_size,safe),"undersized selection still shows its real 1x1 dimensions")
		for footer_key: String in ["confirm","cancel"]:
			check(_visible_inside(h.controls[footer_key],safe),"%s long reason leaves %s inside the safe area" % [str(fixture[0]),footer_key])
		host.touch.reposition()
		host.touch.choose_cell(54)
		host.touch.choose_cell(129)
		h._present_placement_details(initial,h._proposal(),host.session.preview(h._proposal()))
		_expand_precision(panel)
		await _settle()
		var proposal: Dictionary = h._proposal()
		_project_bounds(panel,initial,proposal,ISSUE,_all_permissions())
		await _settle()
		# HUD adopts this independent header next to the scrolling panel body.
		var size_label := panel.pinned_header.find_child("BuildBoundsSize",true,false) as Label
		var issue_label := panel.pinned_header.find_child("BuildBoundsFeedback",true,false) as Label
		check(size_label != null,"step0 has a stable visible bounds-size readout")
		check(issue_label != null,"step0 has a fixed bounds feedback readout")
		if size_label != null:
			check(size_label.text.contains("4×4") and _visible_inside(size_label,safe),"%s keeps current 4x4 size visible inside the safe area" % str(fixture[0]))
		if issue_label != null:
			check(issue_label.text == ISSUE and _visible_inside(issue_label,safe),"%s keeps the supplied invalid-bounds reason visible" % str(fixture[0]))
		var rectangles: Array[Rect2] = []
		for key: String in BOUNDS_KEYS:
			var button: Button = panel.get("bounds_buttons")[key]
			check(_visible_inside(button,safe),"%s %s is visible and unclipped" % [str(fixture[0]),key])
			check(button.size.x >= 48 and button.size.y >= 48,"%s keeps its 48-unit minimum touch target" % key)
			var rectangle := button.get_global_rect()
			for other: Rect2 in rectangles: check(not rectangle.intersects(other),"bounds controls do not overlap")
			rectangles.append(rectangle)
			for footer_key: String in ["confirm","cancel"]:
				check(not rectangle.intersects(h.controls[footer_key].get_global_rect()),key+" cannot cover "+footer_key)
			check(h.controls.has("bounds_"+key) and h.controls["bounds_"+key] == button,"HUD maps the real "+key+" target")
		for footer_key: String in ["confirm","cancel"]:
			check(_visible_inside(h.controls[footer_key],safe),"%s keeps %s reachable" % [str(fixture[0]),footer_key])
		var scroll: ScrollContainer = panel.get_parent()
		scroll.scroll_vertical = 10000
		await _settle()
		if size_label != null: check(_visible_inside(size_label,safe),"size stays pinned while scrolling the instructions")
		if issue_label != null: check(_visible_inside(issue_label,safe),"reason stays pinned while scrolling the instructions")
	# Real parsed ScreenTouch delivery, rather than emitting button signals.
	_project_bounds(panel,initial,h._proposal(),"",_all_permissions())
	await _settle()
	for key: String in BOUNDS_KEYS:
		var button: Button = panel.get("bounds_buttons")[key]
		var prior_count := _events.size()
		await _tap(button)
		check(_events.size() == prior_count+1,"parsed touch dispatches exactly one "+key+" correction")
		if _events.size() == prior_count+1: check(_events.back() == BOUNDS_CHANGES[key],key+" uses its declared size/diagonal ground delta")
		check(str(host.touch.placement.id) == receipt,"correction preserves the draft receipt")
		check(host.session.sim.snapshot() == initial,"correction remains a preview without changing real hospital state")
	var permissions := _all_permissions()
	permissions.width_more = false
	_project_bounds(panel,initial,h._proposal(),ISSUE,permissions)
	await _settle()
	var disabled_button: Button = panel.get("bounds_buttons").width_more
	check(disabled_button.disabled,"panel obeys the caller's refused width expansion")
	var prior_count := _events.size()
	await _tap(disabled_button)
	check(_events.size() == prior_count,"a disabled correction does not emit an adjustment")
	check(h.controls.rotate.text == "放大选区" and not h.controls.rotate.disabled,"step0 reuses the existing tool as enabled zoom-to-selection")
	var placement_before_zoom: Dictionary = host.touch.placement.duplicate(true)
	host.world.camera_rig.set_zoom(26.0)
	await _settle(2)
	var zoom_before: float = host.world.camera_rig.zoom_size
	await _tap(h.controls.rotate)
	check(host.world.camera_rig.zoom_size < zoom_before,"parsed zoom-to-selection touch reduces the camera's wide overview size")
	check(host.touch.placement == placement_before_zoom and host.session.sim.snapshot() == initial,"zoom-to-selection cannot change the draft or real hospital state")
	for fixture: Array in [
		[Vector2i(932,430),Rect2(59,0,814,409)],
		[Vector2i(844,390),Rect2(0,0,844,390)],
		[Vector2i(720,360),Rect2(0,0,720,360)]
	]:
		root.size = fixture[0]
		await _settle()
		h.configure_display(Vector2(fixture[0]),Vector2(fixture[0]),160,fixture[1])
		await _settle()
		await _shrink_protection(h,panel,initial,fixture[1],fixture[0])
	# Existing later-step tools and final purchase flow keep their own space.
	host.touch.begin_free_build("diagnosis")
	host.touch.choose_cell(54)
	host.touch.choose_cell(129)
	h._present_placement_details(initial,h._proposal(),host.session.preview(h._proposal()))
	h.controls.confirm.pressed.emit()
	await _settle()
	check(host.touch.free_build.step == 1,"valid room size still advances to the original door stage")
	check(h.controls.rotate.text == "换墙面","step1 keeps the original selected-opening wall tool")
	for key: String in BOUNDS_KEYS: check(not panel.get("bounds_buttons")[key].is_visible_in_tree(),"door stage hides step0 "+key)
	for button: Button in panel.opening_buttons.values(): check(not button.is_visible_in_tree(),"ordinary door task keeps multi-opening tools collapsed")
	panel.call("set_opening_options_expanded",true)
	await _settle()
	for button: Button in panel.opening_buttons.values(): check(button.is_visible_in_tree(),"door-stage tools remain available")
	await _finish()

func _finish() -> void:
	if host != null:
		host.touch.cancel()
		host.free()
		host = null
	await _settle(4)
	print("BUILD PRECISION UI RESULT: passed=%d failed=%d" % [passed,failed])
	quit(1 if failed else 0)
