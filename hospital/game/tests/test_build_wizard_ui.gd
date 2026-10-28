extends SceneTree

var passed := 0
var failed := 0
var host: Node3D
var _finished_interactions: Array = []
var _commands: Array = []
var _cash_before := 0
var _rooms_before := 0
const BOUNDS_KEYS := ["width_less", "width_more", "height_less", "height_more", "move_nw", "move_ne", "move_sw", "move_se"]
const DISPLAY_CASES := [
	[Vector2i(932,430), Rect2(59,0,814,409)],
	[Vector2i(844,390), Rect2(0,0,844,390)],
	[Vector2i(720,360), Rect2(0,0,720,360)]
]

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> bool:
	if ok: passed += 1
	else: failed += 1
	print(("WIZARD UI PASS: " if ok else "WIZARD UI FAIL: ") + label)
	return ok

func _has_property(object: Object, key: String) -> bool:
	for property: Dictionary in object.get_property_list():
		if str(property.name) == key: return true
	return false

func _api_ready(panel: HospitalPlacementPanel, touch: TouchController) -> bool:
	var ready := check(panel.has_signal("task_layout_changed"), "panel reports current-task layout changes")
	for key: String in ["precision_expanded", "opening_options_expanded", "wizard_buttons"]:
		ready = check(_has_property(panel, key), "panel exposes " + key) and ready
	for method: String in ["set_precision_expanded", "set_opening_options_expanded", "reset_task_expansion", "current_task_title", "preferred_task_height"]:
		ready = check(panel.has_method(method), "panel provides " + method) and ready
	if _has_property(panel, "wizard_buttons"):
		var buttons: Variant = panel.get("wizard_buttons")
		ready = check(buttons is Dictionary, "wizard controls use a dictionary") and ready
		if buttons is Dictionary:
			for key: String in ["precision", "opening_options", "decor_openings"]:
				ready = check(buttons.has(key) and buttons[key] is Button, "panel creates wizard control " + key) and ready
	var completion := touch.has_signal("placement_interaction_finished")
	ready = check(completion, "touch exposes completed real placement interactions") and ready
	if completion:
		for signal_info: Dictionary in touch.get_signal_list():
			if str(signal_info.name) == "placement_interaction_finished":
				ready = check(signal_info.args.size() == 2, "completed placement carries stage and reserved receipt") and ready
	return ready

func _run() -> void:
	var loaded: Dictionary = ContentCatalog.load_checked("res://content")
	var catalog: ContentCatalog = loaded.catalog
	var panel := HospitalPlacementPanel.new()
	panel.initialize(catalog)
	var controller := TouchController.new()
	var ready := _api_ready(panel, controller)
	# The real HUD adopts this independent header. The API probe owns it on red.
	if is_instance_valid(panel.pinned_header) and panel.pinned_header.get_parent() == null:
		panel.pinned_header.free()
	panel.free()
	if not ready:
		await _finish()
		return
	var save_root := _save_root()
	if save_root == "":
		await _finish()
		return
	root.size = Vector2i(932,430)
	host = load("res://main.gd").new()
	host.session = GameSession.new(catalog, save_root)
	root.add_child(host)
	host.set_process(false)
	host.feedback.set_application_active(false)
	host.feedback._music_player.stop()
	host.hud.flow.close()
	host.touch.connect("placement_interaction_finished", func(step: int, receipt: String) -> void:
		_finished_interactions.append({"step":step,"receipt":receipt}))
	host.touch.command_requested.connect(func(command: Dictionary) -> void:
		if command.get("type", "") in ["build_room", "edit_room_layout"]: _commands.append(command.duplicate(true)))
	await _settle(5)
	_cash_before = int(host.session.sim.snapshot().cash)
	_rooms_before = host.session.sim.snapshot().rooms.size()
	await _test_layouts()
	await _configure(DISPLAY_CASES[0])
	await _test_programmatic_and_invalid()
	await _test_interruptions_and_stale_queue()
	await _test_cross_stage_fast_touch()
	await _test_advanced_openings()
	await _test_real_flow_and_final_purchase()
	await _finish()

func _settle(count: int = 4) -> void:
	for _frame in range(count): await process_frame

func _save_root() -> String:
	var suffix := "wizard-ui-%d/save" % Time.get_ticks_usec()
	if OS.get_name() == "macOS":
		var runtime := OS.get_environment("HOSPITAL_CI_RUNTIME_ROOT").replace("\\", "/").simplify_path().trim_suffix("/")
		var runner_temp := OS.get_environment("RUNNER_TEMP").replace("\\", "/").simplify_path().trim_suffix("/")
		if not check(runtime.is_absolute_path() and runner_temp.is_absolute_path() and runtime == runner_temp.path_join("hospital-ios-build/runtime"), "Mac wizard saves stay inside the exact isolated runtime"):
			return ""
		return runtime.path_join(suffix)
	return "E:/CODEX/2026-10-27/医院建设触控优化/temp/" + suffix

func _configure(fixture: Array) -> void:
	root.size = fixture[0]
	await _settle()
	host.hud.configure_display(Vector2(fixture[0]), Vector2(fixture[0]), 160, fixture[1])
	await _settle()

func _finger(index: int, down: bool, point: Vector2) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.pressed = down
	event.position = point
	Input.parse_input_event(event)

func _tap_at(point: Vector2) -> void:
	_finger(0, true, point)
	await process_frame
	_finger(0, false, point)
	await _settle()

func _tap(button: Button) -> void:
	if not check(is_instance_valid(button) and button.is_visible_in_tree(), "real touch target is present and visible"):
		return
	await _tap_at(button.get_global_rect().get_center())

func _visible_inside(control: Control, safe: Rect2) -> bool:
	if not is_instance_valid(control) or not control.is_visible_in_tree(): return false
	var rectangle := control.get_global_rect()
	if rectangle.size.x <= 0 or rectangle.size.y <= 0 or not safe.grow(0.1).encloses(rectangle): return false
	var ancestor := control.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer and not ancestor.get_global_rect().grow(0.1).encloses(rectangle): return false
		ancestor = ancestor.get_parent()
	return true

func _new_room(step: int = 0) -> void:
	host.hud._begin_build("diagnosis")
	host.touch.choose_cell(54)
	host.touch.choose_cell(130) # Literal 5x4 at (6,2); only fixture preparation is programmatic.
	if step >= 1: host.touch.advance_build_step()
	if step >= 2:
		host.touch.choose_cell(127) # south offset1
		host.touch.advance_build_step()
	if step >= 3:
		host.touch.choose_cell(55) # local workstation(1,0)
		host.touch.advance_build_step()
	host.hud._frame_build_room(false)
	await _settle()
	check(host.touch.free_build != null and host.touch.free_build.step == step, "fixture reaches only the requested manual stage %d" % step)

func _preview_fixture() -> bool:
	var candidate := {"kind":"diagnosis", "origin_cell":54, "rotation":0,
		"layout":{"width":5,"height":4,"door":{"side":"south","offset":1},
		"doors":[{"side":"south","offset":1}],"windows":[],
		"equipment":{"x":1,"y":0,"rotation":0},"furniture":[],"footprint_version":2}}
	var result: Dictionary = host.session.preview(candidate)
	return check(bool(result.ok), "literal south1/anchor55 fixture passes actual full grid preview before flow testing")

func _advanced_fixture() -> Dictionary:
	# Select an actually legal full layout before testing UI progression. The
	# assertion concerns multiple openings, not a lucky collision-free location.
	for second: Dictionary in [{"side":"south","offset":3},{"side":"south","offset":2},{"side":"east","offset":3},{"side":"east","offset":2}]:
		for offset in [1,2,0,3]:
			var window := {"side":"east","offset":offset}
			if window == second: continue
			var proposal := {"kind":"diagnosis","origin_cell":54,"rotation":0,
				"layout":{"width":5,"height":4,"door":{"side":"south","offset":1},
				"doors":[{"side":"south","offset":1},second.duplicate()],"windows":[window],
				"equipment":{"x":1,"y":0,"rotation":0},"furniture":[],"footprint_version":2}}
			var preview: Dictionary = host.session.preview(proposal)
			if bool(preview.ok): return {"second":second.duplicate(),"window":window.duplicate()}
	return {}

func _no_purchase(label: String) -> void:
	var snapshot: Dictionary = host.session.sim.snapshot()
	check(_commands.is_empty() and int(snapshot.cash) == _cash_before and snapshot.rooms.size() == _rooms_before, label + " cannot buy or debit the hospital")

func _card_state(step: int, safe: Rect2, label: String) -> void:
	var h: HospitalHud = host.hud
	var panel: HospitalPlacementPanel = h.placement_details
	var card: PanelContainer = h._preview_panel
	check(_visible_inside(card, safe), label + " current-task card fits inside safe area")
	check(card.get_global_rect().size.y < safe.size.y, label + " card leaves hospital space visible")
	if step < 3: check(card.get_global_rect().size.y < safe.size.y * 0.7, label + " ordinary task uses under seventy percent of safe height")
	check(float(panel.call("preferred_task_height")) > 0, label + " derives a positive task height")
	var title := str(panel.call("current_task_title"))
	var words: Array = [["大小","房间"],["入口","门"],["设备","工作站"],["家具"]][step]
	var title_matches := false
	for word: String in words: title_matches = title_matches or title.contains(word)
	check(title_matches, label + " names only the current task")
	if _has_property(panel, "_step_chips"):
		for chip: Control in panel.get("_step_chips"): check(not chip.is_visible_in_tree(), label + " hides the old four-stage chips")
	for key: String in BOUNDS_KEYS: check(not panel.bounds_buttons[key].is_visible_in_tree(), label + " keeps default " + key + " folded")
	var footer_keys: Array[String] = ["cancel"]
	if step == 0 or step == 3:
		footer_keys.append("confirm")
	else:
		# These fixtures deliberately have no door/station yet. Normal mode
		# offers an explicit reuse action only after the required object exists.
		check(not h.controls.confirm.is_visible_in_tree() and h.controls.confirm.disabled, label + " hides reuse confirmation before a valid current object exists")
	for key: String in footer_keys:
		var button: Button = h.controls[key]
		check(_visible_inside(button, safe) and button.size.x >= 48 and button.size.y >= 48, label + " keeps " + key + " as a reachable 48-unit target")
	for button: Button in panel.opening_buttons.values(): check(not button.is_visible_in_tree(), label + " hides advanced opening tools by default")
	if step != 3:
		for button: Button in panel.furniture_buttons.values(): check(not button.is_visible_in_tree(), label + " hides unrelated furniture controls")
	if step == 0:
		check(not h.controls.rotate.is_visible_in_tree() and not h.controls.reposition.is_visible_in_tree(), label + " folds zoom and redraw with precision tools")
		check(h.controls.confirm.text.contains("大小"), label + " explicitly confirms size instead of purchasing")
	if step == 2: check(_visible_inside(h.controls.rotate, safe), label + " offers equipment rotation inside the current task")
	if step == 3: check((h.controls.confirm.text.contains("完成") or h.controls.confirm.text.contains("建好房间")) and not h.controls.confirm.disabled, label + " allows explicit completion without furniture")
	print("BUILD WIZARD UI METRIC: " + JSON.stringify({"viewport":str(root.size),"safe":str(safe),"step":step,"card":str(card.get_global_rect()),"physical_device_measured":false}))

func _test_layouts() -> void:
	for fixture: Array in DISPLAY_CASES:
		await _configure(fixture)
		var safe: Rect2 = fixture[1]
		for step in range(4):
			await _new_room(step)
			_card_state(step, safe, "%s stage%d" % [str(fixture[0]),step])
			if step in [1,2]:
				var completion_count := _finished_interactions.size()
				host.touch.choose_cell(127 if step == 1 else 55)
				await _settle()
				var reuse: Button = host.hud.controls.confirm
				check(_visible_inside(reuse,safe) and reuse.size.x >= 48 and reuse.size.y >= 48 and not reuse.disabled, "existing valid stage%d object exposes a reachable explicit reuse action" % step)
				check(host.touch.free_build.step == step and _finished_interactions.size() == completion_count, "showing reuse confirmation cannot itself auto-advance")
		await _new_room()
		var panel: HospitalPlacementPanel = host.hud.placement_details
		var before_count := _finished_interactions.size()
		await _tap(panel.get("wizard_buttons").precision)
		check(bool(panel.get("precision_expanded")), "precision expands through its real GUI button")
		var rectangles: Array[Rect2] = []
		for key: String in BOUNDS_KEYS:
			var button: Button = panel.bounds_buttons[key]
			check(_visible_inside(button,safe) and button.size.x >= 48 and button.size.y >= 48, "expanded " + key + " remains a reachable 48-unit target")
			for other: Rect2 in rectangles: check(not button.get_global_rect().intersects(other), "expanded precision targets do not overlap")
			rectangles.append(button.get_global_rect())
			for footer: String in ["confirm","cancel"]: check(not button.get_global_rect().intersects(host.hud.controls[footer].get_global_rect()), "precision does not cover " + footer)
		for footer: String in ["confirm","cancel"]: check(_visible_inside(host.hud.controls[footer],safe), "expanded precision retains " + footer)
		await _tap(panel.bounds_buttons.width_more)
		check(host.touch.free_build.step == 0 and int(host.touch.free_build.layout.width) == 6, "expanded real GUI correction adjusts one cell without leaving size")
		check(_finished_interactions.size() == before_count, "GUI precision changes never report completed world placement")
		await _new_room(1)
		check(not bool(panel.get("precision_expanded")) and not bool(panel.get("opening_options_expanded")), "a new room resets expansion flags")
		await _tap(panel.get("wizard_buttons").opening_options)
		check(bool(panel.get("opening_options_expanded")), "opening tools expand only on request")
		for button: Button in panel.opening_buttons.values(): check(_visible_inside(button,safe) and button.size.x >= 48 and button.size.y >= 48, "expanded opening tool is a reachable 48-unit target")
		for footer: String in ["confirm","cancel"]: check(_visible_inside(host.hud.controls[footer],safe), "advanced opening mode retains " + footer)
		check(host.hud.controls.confirm.disabled, "advanced mode shows disabled completion until an entrance exists")
		var empty_entrance: Dictionary = host.touch.free_build.capture_state().duplicate(true)
		await _tap(host.hud.controls.confirm)
		check(host.touch.free_build.capture_state() == empty_entrance and host.touch.free_build.step == 1, "disabled advanced completion cannot bypass the required entrance")
		_no_purchase("layout and optional tools")

func _wall_point(side: String, offset: int) -> Vector2:
	var p: Dictionary = host.touch.placement
	var origin := HospitalWorld.cell_position(int(p.origin_cell))
	var width := int(p.layout.width)
	var height := int(p.layout.height)
	var point := origin + Vector3(0,1.035,0) # Center of the actual 0..2.07 wall envelope, never a floor substitute.
	match side:
		"south": point += Vector3(offset,0,height - 0.5)
		"north": point += Vector3(offset,0,-0.5)
		"east": point += Vector3(width - 0.5,0,offset)
		"west": point += Vector3(-0.5,0,offset)
	return host.world.camera_rig.camera.unproject_position(point)

func _point_available(point: Vector2, label: String) -> bool:
	return check(root.get_visible_rect().has_point(point) and not host.hud.hits_gui(point), label + " projects to exposed hospital space")

func _wall_tap(side: String, offset: int) -> bool:
	var point := _wall_point(side,offset)
	var p: Dictionary = host.touch.placement
	var picked: Dictionary = host.world.camera_rig.screen_to_wall(point,int(p.origin_cell),int(p.layout.width),int(p.layout.height))
	if not check(picked == {"side":side,"offset":offset}, "wall face center ray picks literal " + side + str(offset)): return false
	if not _point_available(point,"wall " + side + str(offset)): return false
	var before := _finished_interactions.size()
	_finger(0,true,point)
	await process_frame
	check(host.touch.free_build != null and host.touch.free_build.step == 1 and _finished_interactions.size() == before, "door press alone cannot auto-advance")
	_finger(0,false,point)
	await _settle()
	return true

func _ground_tap(cell: int) -> bool:
	var point: Vector2 = host.world.camera_rig.camera.unproject_position(HospitalWorld.cell_position(cell))
	if not check(host.world.camera_rig.screen_to_cell(point) == cell, "equipment floor projection selects literal cell " + str(cell)): return false
	if not _point_available(point,"equipment cell " + str(cell)): return false
	var before := _finished_interactions.size()
	_finger(0,true,point)
	await process_frame
	check(host.touch.free_build != null and host.touch.free_build.step == 2 and _finished_interactions.size() == before, "equipment press alone cannot auto-advance")
	_finger(0,false,point)
	await _settle()
	return true

func _invalid_point() -> Vector2:
	# A visible non-GUI ray with no room wall and no room cell. It is not a fabricated floor click on a wall.
	for y in range(36,root.size.y - 20,24):
		for x in range(root.size.x - 24,24,-24):
			var point := Vector2(x,y)
			if host.hud.hits_gui(point): continue
			if not host.world.camera_rig.screen_to_wall(point,54,5,4).is_empty(): continue
			var cell: int = host.world.camera_rig.screen_to_cell(point)
			if cell < 0 or cell % 24 < 6 or cell % 24 > 10 or cell / 24 < 2 or cell / 24 > 5: return point
	return Vector2(-10000,-10000)

func _test_programmatic_and_invalid() -> void:
	await _new_room(1)
	if not _preview_fixture(): return
	var before := _finished_interactions.size()
	var invalid := _invalid_point()
	if _point_available(invalid,"invalid map ray"):
		await _tap_at(invalid)
		check(host.touch.free_build.step == 1 and _finished_interactions.size() == before, "invalid wall placement remains on the entrance task")
	host.touch.choose_cell(127)
	await _settle()
	check(host.touch.free_build.step == 1 and _finished_interactions.size() == before, "programmatic door choice cannot schedule auto-next")
	host.touch.rotate()
	await _settle()
	check(host.touch.free_build.step == 1 and _finished_interactions.size() == before, "rotating a door cannot schedule auto-next")
	await _new_room(2)
	host.touch.choose_cell(55)
	await _settle()
	check(host.touch.free_build.step == 2 and _finished_interactions.size() == before, "programmatic valid equipment choice cannot schedule auto-next")
	await _tap(host.hud.controls.rotate)
	check(host.touch.free_build.step == 2 and _finished_interactions.size() == before, "real GUI rotate changes no task and emits no world completion")
	invalid = _invalid_point()
	if _point_available(invalid,"invalid equipment ray"):
		await _tap_at(invalid)
		check(host.touch.free_build.step == 2 and _finished_interactions.size() == before, "invalid equipment release cannot auto-next")
	await _new_room(2)
	# This is a real in-room map tap which changes the station anchor, but its
	# body/operation footprint runs past the room. Full preview must gate next.
	if await _ground_tap(130):
		if check(host.touch.free_build != null and host.touch.free_build.step == 2, "released in-room invalid workstation stays on the equipment task"):
			var rejected: Dictionary = host.session.preview(host.hud._proposal())
			check(host.touch.free_build.layout.equipment == {"x":4,"y":3,"rotation":0}, "invalid equipment case actually reaches literal room-local anchor4,3")
			check(not bool(rejected.ok) and host.hud.controls.confirm.disabled, "actual full preview rejects anchor130 and prevents reuse confirmation")
	_no_purchase("manual, invalid and GUI-only operations")

func _test_interruptions_and_stale_queue() -> void:
	await _new_room(1)
	var point := _wall_point("south",1)
	if not _point_available(point,"multi-finger wall ray"): return
	var before := _finished_interactions.size()
	var backup: Dictionary = host.touch.free_build.capture_state().duplicate(true)
	_finger(0,true,point)
	_finger(1,true,point + Vector2(12,0))
	_finger(0,false,point)
	_finger(1,false,point + Vector2(12,0))
	await _settle()
	check(host.touch.free_build.step == 1 and host.touch.free_build.capture_state() == backup and _finished_interactions.size() == before, "two-finger interaction rolls back without auto-next")
	await _tap(host.hud.placement_details.get("wizard_buttons").opening_options)
	check(host.touch.free_build.step == 1 and _finished_interactions.size() == before, "advanced GUI toggle emits no world completion")
	# Release is real; cancellation/back happen before the deferred idle callback.
	for action: String in ["cancel","back","replace","serial_change"]:
		await _new_room(1)
		point = _wall_point("south",1)
		if not _point_available(point,"stale " + action + " ray"): continue
		_finger(0,true,point)
		await process_frame
		_finger(0,false,point)
		var old_receipt := str(host.touch.placement.get("id",""))
		match action:
			"cancel": host.touch.cancel()
			"back": host.touch.back_build_step()
			"replace": host.hud._begin_build("diagnosis")
			"serial_change": host.touch.select_opening_tool("window")
		await _settle()
		if action == "cancel": check(host.touch.free_build == null and host.touch.placement.is_empty(), "cancel invalidates queued auto-next")
		elif action == "back": check(host.touch.free_build != null and host.touch.free_build.step == 0, "back invalidates queued auto-next")
		elif action == "replace": check(host.touch.free_build != null and host.touch.free_build.step == 0 and str(host.touch.placement.id) != old_receipt, "new receipt cannot consume stale auto-next")
		else: check(host.touch.free_build != null and host.touch.free_build.step == 1, "a newer draft change invalidates queued auto-next")
	_no_purchase("interrupted and stale queued gestures")

func _test_cross_stage_fast_touch() -> void:
	await _new_room(1)
	var wall := _wall_point("south",1)
	var floor_point: Vector2 = host.world.camera_rig.camera.unproject_position(HospitalWorld.cell_position(55))
	if not _point_available(wall,"quick door ray") or not _point_available(floor_point,"quick next finger ray"): return
	var picked: Dictionary = host.world.camera_rig.screen_to_wall(wall,54,5,4)
	if not check(picked == {"side":"south","offset":1} and host.world.camera_rig.screen_to_cell(floor_point) == 55, "fast-transition fixture uses an actual door face and valid station floor ray"): return
	var before := _finished_interactions.size()
	var receipt := str(host.touch.placement.id)
	_finger(0,true,wall)
	await process_frame
	_finger(0,false,wall)
	# No yield here: another gesture starts before the door's queued idle work.
	# The task must not change while that new finger is still held.
	_finger(0,true,floor_point)
	await _settle()
	if not check(host.touch.free_build != null and host.touch.free_build.step == 1, "a newly held finger keeps the entrance task and invalidates old queued auto-next"):
		_finger(0,false,floor_point)
		await _settle()
		return
	var equipment_before: Dictionary = host.touch.free_build.layout.equipment.duplicate(true)
	check(equipment_before.is_empty() and _finished_interactions.size() == before + 1, "held next gesture has not placed or completed equipment")
	check(host.world.camera_rig.screen_to_cell(floor_point) == 55 and host.world.camera_rig.screen_to_wall(floor_point,54,5,4).is_empty(), "the original release point is valid station floor but not an entrance wall")
	_finger(0,false,floor_point)
	await _settle()
	if not check(host.touch.free_build != null and host.touch.free_build.step == 1, "releasing that floor gesture cannot change task or interpret it as equipment"): return
	check(host.touch.free_build.layout.equipment == equipment_before and _finished_interactions.size() == before + 1, "old-stage floor release preserves equipment and emits no second completion")
	check(str(host.touch.placement.id) == receipt, "fast input handoff preserves the original construction receipt")
	_no_purchase("held-finger task protection")
	if not await _wall_tap("south",1): return
	if not check(host.touch.free_build != null and host.touch.free_build.step == 2 and _finished_interactions.size() == before + 2, "a new complete entrance gesture safely advances to equipment after the finger is released"): return
	if await _ground_tap(55):
		check(host.touch.free_build != null and host.touch.free_build.step == 3 and _finished_interactions.size() == before + 3, "a new equipment gesture safely advances to furniture after held-finger protection")
	_no_purchase("recovered fresh task gestures")

func _test_advanced_openings() -> void:
	await _new_room(1)
	var fixture := _advanced_fixture()
	if not check(not fixture.is_empty(), "multiple-opening fixture passes actual complete preview before touch testing"): return
	var panel: HospitalPlacementPanel = host.hud.placement_details
	await _tap(panel.get("wizard_buttons").opening_options)
	if not check(bool(panel.get("opening_options_expanded")), "advanced entrance task is explicitly expanded"): return
	if not await _wall_tap("south",1): return
	check(host.touch.free_build.step == 1 and host.touch.free_build.layout.get("doors",[]).size() == 1, "valid first advanced door stays on the same task")
	if not await _wall_tap(str(fixture.second.side),int(fixture.second.offset)): return
	check(host.touch.free_build.step == 1 and host.touch.free_build.layout.get("doors",[]).size() == 2, "advanced mode accepts a second independent entrance before continuing")
	await _tap(panel.opening_buttons.window)
	if not await _wall_tap(str(fixture.window.side),int(fixture.window.offset)): return
	check(host.touch.free_build.step == 1 and host.touch.free_build.layout.get("windows",[]).size() == 1, "advanced mode accepts a real wall window without auto-next")
	await _tap(host.hud.controls.confirm)
	if not check(host.touch.free_build != null and host.touch.free_build.step == 2, "explicit advanced completion moves exactly to equipment"): return
	if not await _ground_tap(55): return
	if not check(host.touch.free_build != null and host.touch.free_build.step == 3, "valid equipment release completes advanced route to optional furniture"): return
	check(host.touch.free_build.layout.doors.size() == 2 and host.touch.free_build.layout.windows.size() == 1, "automatic progression preserves all independently placed openings")
	await _tap(panel.get("wizard_buttons").decor_openings)
	if not check(host.touch.free_build != null and host.touch.free_build.step == 1 and bool(panel.get("opening_options_expanded")), "furniture can reopen advanced door/window editing"): return
	await _tap(host.hud.controls.confirm)
	check(host.touch.free_build != null and host.touch.free_build.step == 3, "existing valid equipment returns from advanced openings to furniture without repurchase")
	_no_purchase("multiple openings and optional editing")

func _test_real_flow_and_final_purchase() -> void:
	await _new_room()
	if not _preview_fixture(): return
	var receipt := str(host.touch.placement.id)
	var before := _finished_interactions.size()
	await _tap(host.hud.controls.confirm)
	if not check(host.touch.free_build != null and host.touch.free_build.step == 1, "real size-confirm button advances only to entrance"): return
	_no_purchase("explicit size confirmation")
	if not await _wall_tap("south",1): return
	if not check(host.touch.free_build != null and host.touch.free_build.step == 2, "valid released wall tap automatically shows equipment"): return
	check(_finished_interactions.size() == before + 1 and _finished_interactions.back() == {"step":1,"receipt":receipt}, "real door completion carries exactly the original stage and receipt")
	_no_purchase("automatic entrance completion")
	if not await _ground_tap(55): return
	if not check(host.touch.free_build != null and host.touch.free_build.step == 3, "valid released floor tap automatically shows optional furniture"): return
	check(_finished_interactions.size() == before + 2 and _finished_interactions.back() == {"step":2,"receipt":receipt}, "real equipment completion emits once and cannot skip furniture")
	await _settle(4)
	check(host.touch.free_build.step == 3 and host.touch.free_build.layout.furniture.is_empty(), "idle frames cannot purchase or require optional furniture")
	_no_purchase("all auto-next tasks")
	var proposal: Dictionary = host.hud._proposal()
	var cost := FreeRoomLayout.base_cost("diagnosis",proposal.layout,host.session.catalog,false)
	var prior_room_ids: Array = host.session.sim.snapshot().rooms.keys()
	var confirm_point: Vector2 = host.hud.controls.confirm.get_global_rect().get_center()
	await _tap_at(confirm_point)
	await _tap_at(confirm_point) # A real rapid repeat after the card disappeared must not create another purchase.
	var snapshot: Dictionary = host.session.sim.snapshot()
	if not check(_commands.size() == 1, "only explicit final completion emits one construction command"): return
	check(str(_commands[0].id) == receipt and snapshot.command_receipts.has(receipt), "final purchase uses the reserved draft receipt")
	check(snapshot.rooms.size() == _rooms_before + 1 and int(snapshot.cash) == _cash_before - cost, "final completion builds one actual room and debits its actual quote once")
	check(host.touch.free_build == null and host.touch.placement.is_empty(), "successful final purchase releases the complete draft")
	var committed: Dictionary = snapshot.duplicate(true)
	host.session.submit(_commands[0]) # Actual model idempotency, not a mocked counter.
	await _settle()
	var repeated: Dictionary = host.session.sim.snapshot()
	check(repeated.cash == committed.cash and repeated.rooms == committed.rooms and repeated.command_receipts == committed.command_receipts, "replaying the identical receipt cannot debit or build again")
	var built_room_id := ""
	for id: String in repeated.rooms:
		if id not in prior_room_ids: built_room_id = id
	if check(built_room_id != "", "legacy regression uses the room actually created by final UI confirmation"):
		await _test_legacy_controls_after_hidden_confirm(built_room_id)

func _test_legacy_controls_after_hidden_confirm(room_id: String) -> void:
	var snapshot: Dictionary = host.session.sim.snapshot()
	var cash: int = snapshot.cash
	var rooms: Dictionary = snapshot.rooms.duplicate(true)
	var commands_before := _commands.size()
	var origin: int = rooms[room_id].origin_cell
	await _new_room(1)
	if not check(host.hud.controls.confirm.disabled and not host.hud.controls.confirm.is_visible_in_tree(), "fresh entrance task really hides unusable reuse confirmation before legacy regression"): return
	await _tap(host.hud.controls.cancel)
	if not check(host.touch.free_build == null and host.touch.placement.is_empty(), "real cancel exits the hidden-confirm wizard before legacy movement"): return
	host.hud._begin_move("diagnosis",room_id)
	host.touch.choose_cell(origin)
	await _settle()
	var h: HospitalHud = host.hud
	var safe: Rect2 = DISPLAY_CASES[0][1]
	var preview: Dictionary = host.session.preview(h._proposal())
	check(host.touch.free_build == null and str(host.touch.placement.get("room_id","")) == room_id and bool(preview.ok), "legacy movement targets the actual room at a legal existing location")
	var confirm: Button = h.controls.confirm
	check(_visible_inside(confirm,safe) and confirm.size.x >= 48 and confirm.size.y >= 48 and not confirm.disabled, "legacy confirmation becomes visible and usable after wizard reuse confirmation was hidden")
	for key: String in ["rotate","reposition","close_preview"]:
		check(_visible_inside(h.controls[key],safe), "legacy " + key + " recovers its visible original control")
	check(h.controls.rotate.text == "旋转", "legacy rotation restores its original action instead of a size-step tool")
	for button: Button in h.placement_details.get("wizard_buttons").values(): check(not button.is_visible_in_tree(), "legacy movement hides all wizard-only task options")
	var unchanged: Dictionary = host.session.sim.snapshot()
	check(_commands.size() == commands_before and int(unchanged.cash) == cash and unchanged.rooms == rooms, "switching to legacy movement remains a preview without another purchase or debit")
	await _tap(h.controls.close_preview)
	check(host.touch.free_build == null and host.touch.placement.is_empty(), "restored legacy close button really cancels the preview")

func _finish() -> void:
	if host != null:
		host.touch.cancel()
		host.free()
		host = null
	await _settle(4)
	print("BUILD WIZARD UI RESULT: passed=%d failed=%d" % [passed, failed])
	quit(1 if failed else 0)
