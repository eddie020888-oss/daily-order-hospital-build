extends SceneTree

var passed:=0
var failed:=0
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, copy: String) -> void:
	if ok: passed+=1
	else: failed+=1
	print(("SETTINGS PASS: " if ok else "SETTINGS FAIL: ")+copy)

func _run() -> void:
	root.size=Vector2i(1280,720)
	var host: Node3D=load("res://main.gd").new()
	var save_root: String="E:/CODEX/2026-10-19/医院原稿落地/reports/settings-%d" % Time.get_ticks_usec()
	host.session=GameSession.new(ContentCatalog.load_checked("res://content").catalog,save_root)
	root.add_child(host)
	host.set_process(false)
	host.hud.flow.controls.continue_game.pressed.emit()
	var feedback: Variant=host.get("feedback")
	check(feedback!=null,"Main owns the real configured sound and haptics service")
	if feedback!=null: await _settings(host,feedback,save_root)
	var body:=HospitalUiStyle.text("正文")
	check(body.get_theme_font("font").variation_opentype[2003265652]==400.0,"shared default body text uses the original regular weight")
	body.free()
	check(HospitalUiStyle.icon("check",42).get_width()==42,"result status icon is rasterized at its approved display size")
	var small:=HospitalUiStyle.picture(null,Vector2(66,66))
	var large:=HospitalUiStyle.picture(null,Vector2(94,94))
	var device:=HospitalUiStyle.picture(null,Vector2(80,66))
	check(small.material is ShaderMaterial and large.material is ShaderMaterial and device.material is ShaderMaterial,"shared picture actually clips image pixels to rounded corners")
	if small.material is ShaderMaterial:
		check(small.material.get_shader_parameter("radius")==13.0 and large.material.get_shader_parameter("radius")==19.0 and device.material.get_shader_parameter("radius")==10.0,"small portrait large portrait and device keep their different approved radii")
	small.free(); large.free(); device.free()
	host.free()
	# Let the independent audio mixing thread release stopped one-shots before engine teardown.
	await create_timer(0.12).timeout
	print("SETTINGS RESULT: passed=%d failed=%d" % [passed,failed])
	quit(1 if failed else 0)

func _settings(host: Node3D, feedback: Variant, save_root: String) -> void:
	var h: HospitalHud=host.hud
	h.controls.settings.pressed.emit()
	h.flow.controls.pause_help.pressed.emit()
	var page: Variant=h.get("settings_page")
	check(page!=null and h._utility.visible,"pause help opens the independent original S23 preferences page")
	if page==null: return
	var snapshot: Dictionary=host.session.sim.snapshot()
	host.session.save_now()
	var main_path: String=save_root.path_join("main.json")
	var main_bytes:=FileAccess.get_file_as_bytes(main_path)
	page.controls.music.pressed.emit()
	check(not feedback.preferences().music_enabled and not feedback.get_node("MusicPlayer").playing,"music switch controls actual playback after persisted preference success")
	var pref_path: String=save_root.path_join("preferences.jsonl")
	var before:=FileAccess.get_file_as_string(pref_path)
	var slider: HSlider=page.controls.music_volume
	for _i in range(4): await process_frame
	var slider_rect:=slider.get_global_rect()
	var from:=slider_rect.position+Vector2(slider_rect.size.x*0.32,slider_rect.size.y/2)
	var to:=slider_rect.position+Vector2(slider_rect.size.x*0.70,slider_rect.size.y/2)
	var down:=InputEventScreenTouch.new()
	down.index=0; down.pressed=true; down.position=from
	Input.parse_input_event(down)
	await process_frame
	var drag:=InputEventScreenDrag.new()
	drag.index=0; drag.position=to; drag.relative=to-from
	Input.parse_input_event(drag)
	await process_frame
	check(FileAccess.get_file_as_string(pref_path)==before,"real slider touch and movement defer disk write until finger release")
	var up:=InputEventScreenTouch.new()
	up.index=0; up.pressed=false; up.position=to
	Input.parse_input_event(up)
	for _i in range(3): await process_frame
	check(feedback.preferences().music_volume>0.5,"real slider touch release updates the actual music volume")
	feedback.set_music_volume(0.32)
	before=FileAccess.get_file_as_string(pref_path)
	slider.drag_started.emit()
	slider.value=47
	slider.value=63
	check(FileAccess.get_file_as_string(pref_path)==before and is_equal_approx(feedback.preferences().music_volume,0.32),"slider movement does not write preferences before release")
	slider.drag_ended.emit(true)
	check(is_equal_approx(feedback.preferences().music_volume,0.63) and FileAccess.get_file_as_string(pref_path).split("\n",false).size()==before.split("\n",false).size()+1,"slider release commits exactly one final real preference")
	check(host.session.sim.snapshot()==snapshot and FileAccess.get_file_as_bytes(main_path)==main_bytes,"settings leave simulation authority and its primary save untouched")
	check(page.controls.haptics.disabled and page.haptics_hint.text.contains("不支持"),"desktop reports unavailable vibration rather than offering a fake switch")
	page.controls.music.pressed.emit()
	check(feedback.get_node("MusicPlayer").playing,"enabling music starts the actual preference-owned looping stream")
	var copy:=HospitalFeedback.new()
	root.add_child(copy)
	copy.configure(save_root)
	check(copy.preferences()==feedback.preferences(),"a fresh service restores the actual settings independently of the simulation save")
	copy.free()
	host.session.issue("hire_staff",{"role":"doctor"})
	check(feedback.get_node("SfxPlayer").stream==HospitalFeedback.CONFIRM_STREAM,"successful real command plays confirmed feedback")
	host.session.issue("build_room",{"kind":"reception","origin_cell":-1,"rotation":0})
	check(feedback.get_node("SfxPlayer").stream==HospitalFeedback.REJECT_STREAM,"rejected real command plays rejected feedback")
	slider.drag_started.emit(); slider.value=91
	host._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	slider.drag_ended.emit(true)
	check(is_equal_approx(feedback.preferences().music_volume,0.63) and is_equal_approx(slider.value,63),"focus loss cancels a pending volume drag without a late commit")
	check(feedback.get_node("MusicPlayer").stream_paused and not feedback.get_node("SfxPlayer").playing,"focus loss pauses music and stops any active effects")
	host.session.issue("hire_staff",{"role":"doctor"})
	check(not feedback.get_node("SfxPlayer").playing,"commands while unfocused cannot start sound effects")
	host._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	check(not feedback.get_node("MusicPlayer").stream_paused and host.session.sim.snapshot().paused,"focus return resumes preferred music without resuming the game")
	h.configure_display(Vector2(1920,1080),Vector2(1280,720),480,Rect2(0,0,1920,1080))
	for _i in range(4): await process_frame
	var footer: Rect2=h.controls.close_panel.get_global_rect()
	page.get_parent().scroll_vertical=2000
	for _i in range(3): await process_frame
	check(footer.end.y<=720 and footer.is_equal_approx(h.controls.close_panel.get_global_rect()),"short landscape retains the fixed return footer while settings content scrolls")
	slider.drag_started.emit(); slider.value=21
	h.controls.save.pressed.emit()
	slider.drag_ended.emit(true)
	check(is_equal_approx(feedback.preferences().music_volume,0.63),"opening a modal cancels an unfinished settings volume drag")
