extends "res://tests/capture_ui_alignment.gd"

# Internal native review only. Real scenario state and touchscreen actions; no fabricated UI values.
func _run() -> void:
	if DisplayServer.get_name()=="headless" or not output_dir.begins_with("E:/CODEX/") or DirAccess.dir_exists_absolute(output_dir):
		push_error("Native capture requires a new E:/CODEX output directory.")
		quit(1)
		return
	root.size=Vector2i(1280,720)
	DirAccess.make_dir_recursive_absolute(output_dir)
	var catalog: ContentCatalog=ContentCatalog.load_checked("res://content").catalog
	host=load("res://main.gd").new()
	host.session=GameSession.new(catalog,output_dir.path_join("isolated-save"))
	root.add_child(host)
	host.set_process(false)
	await _tap(host.hud.flow.controls.continue_game)
	await _placement_capture("01-S05-placement")
	await _tap(host.hud.controls.cancel)
	# Use a genuine clinical scenario, advanced until its first actual recovery-full handoff.
	host.session.sim=Scenarios.create_sim(catalog,"benchmark_18","fast","standard")
	var blocked:=false
	for _i in range(2500):
		host.session.sim.advance_ticks(1)
		for patient in host.session.sim.snapshot().patients.values():
			if patient.phase=="waiting_recovery" and patient.wait_reason=="recovery_full": blocked=true; break
		if blocked: break
	_check(blocked,"actual recovery handoff fixture reached")
	host.session.issue("set_paused",{"paused":true})
	await _assignment_capture("02-S11-assignment")
	await _flow_captures("03-S15-hospital-flow","04-S20-recovery-congestion")
	await _settings_capture("05-S23-settings")
	# True touch on the range control: only the final release may persist its final value.
	var slider: HSlider=host.hud.settings_page.controls.music_volume
	var pref_path: String=host.session.save_root.path_join("preferences.jsonl")
	var before:=FileAccess.get_file_as_string(pref_path) if FileAccess.file_exists(pref_path) else ""
	var rect:=slider.get_global_rect()
	var start:=rect.position+Vector2(5,rect.size.y/2)
	var end:=rect.position+Vector2(rect.size.x*0.7,rect.size.y/2)
	var down:=InputEventScreenTouch.new()
	down.index=0; down.pressed=true; down.position=start
	Input.parse_input_event(down)
	await process_frame
	var drag:=InputEventScreenDrag.new()
	drag.index=0; drag.position=end; drag.relative=end-start
	Input.parse_input_event(drag)
	await process_frame
	_check((FileAccess.get_file_as_string(pref_path) if FileAccess.file_exists(pref_path) else "")==before,"native range drag does not persist while held")
	var up:=InputEventScreenTouch.new()
	up.index=0; up.pressed=false; up.position=end
	Input.parse_input_event(up)
	for _i in range(3): await process_frame
	_check(FileAccess.file_exists(pref_path) and FileAccess.get_file_as_string(pref_path)!=before,"native range release persists actual preference")
	await _tap(host.hud.controls.close_panel)
	host.hud.configure_display(Vector2(1920,1080),Vector2(1280,720),480,Rect2(0,0,1920,1080))
	await _placement_capture("06-S05-short-landscape")
	await _tap(host.hud.controls.cancel)
	await _assignment_capture("07-S11-short-landscape")
	await _flow_captures("08-S15-short-landscape","09-S20-short-landscape")
	await _settings_capture("10-S23-short-landscape")
	var file:=FileAccess.open(output_dir.path_join("gallery.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"internal_review_only":true,"failed":failed,"captures":captures,"scenario":"benchmark_18 fast standard, advanced to real first recovery_full; UI actions are real touches"},"  "))
	file.close()
	print("ORIGINAL GALLERY RESULT: failed=%d captures=%d" % [failed,captures.size()])
	host.free()
	await create_timer(0.12).timeout
	quit(1 if failed else 0)

func _placement_capture(name:String) -> void:
	await _close_for_navigation()
	var proposal:Dictionary=await preload("res://tests/native_a2_interactions.gd").prepare_native(host.hud,"recovery",121,_tap,_floor_cell)
	_check(not proposal.is_empty(),"real A2 card/start and touch-driven bounds, door and equipment prepare recovery")
	if proposal.is_empty():return
	_check(not host.hud.controls.confirm.disabled,"touch-driven draft is legal before its explicit purchase")
	await _capture(name)

func _assignment_capture(name: String) -> void:
	await _close_for_navigation()
	await _tap(host.hud.controls.staff)
	await _tap(host.hud.selection.controls.staff_003)
	await _tap(host.hud.selection.controls.choose_assignment)
	await _capture(name)

func _flow_captures(flow_name: String, congestion_name: String) -> void:
	await _close_for_navigation()
	await _tap(host.hud.controls.patients)
	await _tap(host.hud.selection.controls.hospital_flow)
	await _capture(flow_name)
	await _tap(host.hud.operations.controls.stage_recovery)
	await _capture(congestion_name)

func _settings_capture(name: String) -> void:
	await _tap(host.hud.controls.settings)
	await _tap(host.hud.flow.controls.pause_help)
	await _capture(name)

func _close_for_navigation() -> void:
	# Close existing pages explicitly before routing; construction alone hides the A2 HUD.
	for pair in [[host.hud._right,"close_detail"],[host.hud._operations_drawer,"close_operations"],[host.hud._utility,"close_settings"],[host.hud._left,"close_build"]]:
		if pair[0].visible: await _tap(host.hud.controls[pair[1]])

static func visible_build_point(view: Node3D) -> Vector2:
	var chosen:=Vector2(-1,-1)
	var best:=INF
	var bounds:=Rect2(Vector2(20,150),Vector2(1240,380))
	for cell in range(432):
		var point: Vector2=view.world.camera_rig.camera.unproject_position(HospitalWorld.cell_position(cell))
		if not bounds.has_point(point) or view.hud.hits_gui(point): continue
		var proposal: Dictionary=view.touch.placement.duplicate(true)
		proposal.origin_cell=cell
		if not view.session.preview(proposal).ok: continue
		var distance:=point.distance_squared_to(Vector2(300,430))
		if distance<best: best=distance; chosen=point
	return chosen
