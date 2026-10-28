extends Node3D

var world: HospitalWorld
var session: GameSession
var touch: TouchController
var hud: HospitalHud
var feedback: HospitalFeedback
var _presented_session: GameSession
var _presented_world: HospitalWorld
var _world_revision := -1
var experience_tutorial := HospitalExperienceTutorial.new()
var _experience_events := HospitalExperienceEvents.new()
var _experience_sim: Simulation
var _experience_active := true

func _ready() -> void:
	world = HospitalWorld.new()
	add_child(world)
	var catalog: ContentCatalog=ContentCatalog.load_checked("res://content").catalog
	var save_root:=OS.get_user_data_dir() if OS.has_feature("android") or OS.has_feature("ios") else ProjectSettings.globalize_path("res://../work/userdata")
	if session==null: session=GameSession.new(catalog,save_root)
	session.open_saved()
	feedback=HospitalFeedback.new()
	add_child(feedback)
	feedback.configure(session.save_root)
	hud=HospitalHud.new()
	touch=TouchController.new(world,func(point: Vector2) -> bool: return hud.hits_gui(point),session.reserve_command_id)
	touch.command_requested.connect(session.submit)
	var canvas:=CanvasLayer.new()
	add_child(canvas)
	canvas.add_child(hud)
	hud.initialize(session,touch,world,feedback)
	hud.set_experience_tutorial(experience_tutorial)
	session.command_result.connect(_play_result)
	hud.feedback_result.connect(_play_result)
	session.changed.connect(_present)
	_present()
	hud.open_launch()

func _present() -> void:
	var snapshot: Dictionary=session.presentation_snapshot()
	var revision: int=session.presentation_revision()
	if _experience_sim != session.sim:
		_experience_sim = session.sim
		_experience_events.reset(snapshot, session.sim)
		experience_tutorial.begin(snapshot)
	experience_tutorial.observe(snapshot)
	for cue: Dictionary in _experience_events.poll(snapshot, session.sim, _experience_active):
		if feedback != null: feedback.play_experience(cue)
	if _presented_session!=session or _presented_world!=world or _world_revision!=revision:
		_presented_session=session
		_presented_world=world
		_world_revision=revision
		world.present(snapshot)
	# Notices, selection and modal state may change without a simulation tick.
	hud.present(snapshot)

func _process(delta: float) -> void:
	if session!=null: session.advance_wall_time(roundi(delta*1000000.0))

func _input(event: InputEvent) -> void:
	if hud!=null and hud.campaign_build!=null and hud.campaign_build.active:
		hud.campaign_build.feed(event)
		return
	if touch!=null: touch.feed(event)

func _notification(what: int) -> void:
	if session==null: return
	if what in [NOTIFICATION_APPLICATION_PAUSED,NOTIFICATION_APPLICATION_FOCUS_OUT]:
		_experience_active = false
		if feedback!=null: feedback.set_application_active(false)
		if hud!=null and hud.settings_page!=null: hud.settings_page.cancel_drafts()
		if hud!=null and hud.campaign_build!=null:hud.campaign_build.reset_input()
		touch.reset_input()
		session.handle_focus_lost()
	elif what in [NOTIFICATION_APPLICATION_RESUMED,NOTIFICATION_APPLICATION_FOCUS_IN]:
		_experience_events.reset(session.presentation_snapshot(), session.sim)
		_experience_active = true
		touch.reset_input()
		session.handle_focus_gained()
		if int(session.presentation_snapshot().get("campaign",{}).get("opening_loop_version",0))==1 and session.notice=="已保存。":session.dismiss_notice()
		if feedback!=null: feedback.set_application_active(true)

func _play_result(result: Dictionary) -> void:
	if session != null: experience_tutorial.observe(session.presentation_snapshot(), result)
	if feedback==null: return
	if result.get("ok",false): feedback.play_confirmed()
	else: feedback.play_rejected()
	feedback.request_haptic(30 if result.get("ok",false) else 70)
