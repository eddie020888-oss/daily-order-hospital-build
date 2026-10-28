extends SceneTree

# Dedicated observational host: normal session scheduler + unmodified world/HUD.
# No startup save/focus lifecycle, input replay, storage or Android claims.
var output := ""
var source := ""
var duration := 1800
var session: GameSession
var world: HospitalWorld
var hud: HospitalHud
var frames: FileAccess
var states: FileAccess
var started := 0
var previous_process := 0
var previous_draw := 0
var last_sample := -1
var draw_count := 0
var process_count := 0
var draw_times: Array[float] = []
var process_times: Array[float] = []
var delta_times: Array[float] = []
var captures: Array = []
var interruptions: Array = []
var active := false
var meta: Dictionary

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		var pair := arg.split("=",true,1)
		if pair.size()!=2: continue
		match pair[0]:
			"output": output=pair[1]
			"source": source=pair[1]
			"duration": duration=int(pair[1])
	_setup.call_deferred()

func _setup() -> void:
	if not output.replace("\\","/").begins_with("E:/CODEX/") or DisplayServer.get_name()=="headless" or duration<1:
		push_error("Rendered load requires E drive, visible renderer and positive duration")
		quit(1)
		return
	Engine.max_fps=60
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	root.size=Vector2i(1280,720)
	var catalog: ContentCatalog=ContentCatalog.load_checked("res://content").catalog
	session=GameSession.new(catalog,output.path_join("unused-save"))
	session.sim=Scenarios.create_sim(catalog,"load_40","tolerance","standard")
	world=HospitalWorld.new()
	root.add_child(world)
	var layer:=CanvasLayer.new()
	root.add_child(layer)
	hud=HospitalHud.new()
	layer.add_child(hud)
	var touch:=TouchController.new(world,func(_point: Vector2) -> bool: return true,session.reserve_command_id)
	hud.initialize(session,touch,world)
	world.present(session.sim.snapshot())
	hud.present()
	for i in range(4): await RenderingServer.frame_post_draw
	meta={"pid":OS.get_process_id(),"source_commit":source,"content_version":catalog.content_version,"engine":Engine.get_version_info(),"scenario":"load_40","strategy":"tolerance","layout":"standard","scope":"normal 1x GameSession scheduler + HospitalWorld + HospitalHud snapshot presentation; no interactive input, lifecycle/save or Android device coverage","duration_requested_seconds":duration,"speed":1,"time_scale":Engine.time_scale,"max_fps":Engine.max_fps,"vsync":DisplayServer.window_get_vsync_mode(),"viewport":[1280,720],"display":DisplayServer.get_name(),"renderer":RenderingServer.get_current_rendering_method(),"driver":RenderingServer.get_current_rendering_driver_name(),"adapter":RenderingServer.get_video_adapter_name(),"api":RenderingServer.get_video_adapter_api_version(),"start_utc":Time.get_datetime_string_from_system(true)}
	_write_json("engine.json",meta)
	frames=FileAccess.open(output.path_join("frames.csv"),FileAccess.WRITE)
	frames.store_line("kind,elapsed_usec,delta_ms,interval_ms,tick")
	states=FileAccess.open(output.path_join("state-samples.jsonl"),FileAccess.WRITE)
	RenderingServer.frame_post_draw.connect(_draw)
	root.focus_entered.connect(func() -> void: interruptions.append({"event":"focus_entered","elapsed_usec":Time.get_ticks_usec()-started}))
	root.focus_exited.connect(func() -> void: interruptions.append({"event":"focus_exited","elapsed_usec":Time.get_ticks_usec()-started}))
	started=Time.get_ticks_usec()
	previous_process=started
	previous_draw=started
	active=true
	print("LOAD START: "+JSON.stringify(meta))

func _process(delta: float) -> bool:
	if not active: return false
	var now:=Time.get_ticks_usec()
	var interval:=float(now-previous_process)/1000.0
	previous_process=now
	process_count+=1
	process_times.append(interval)
	delta_times.append(delta*1000.0)
	session.advance_wall_time(roundi(delta*1000000.0))
	var snapshot:=session.sim.snapshot()
	world.present(snapshot)
	hud.present()
	frames.store_line("process,%d,%.6f,%.6f,%d" % [now-started,delta*1000.0,interval,snapshot.tick])
	return false

func _draw() -> void:
	if not active: return
	var now:=Time.get_ticks_usec()
	var interval:=float(now-previous_draw)/1000.0
	previous_draw=now
	draw_count+=1
	draw_times.append(interval)
	var elapsed:=float(now-started)/1000000.0
	var snapshot:=session.sim.snapshot()
	frames.store_line("draw,%d,0,%.6f,%d" % [now-started,interval,snapshot.tick])
	if interval>5000.0 or DisplayServer.window_get_mode()==DisplayServer.WINDOW_MODE_MINIMIZED:
		_finish(false,"draw gap >5 seconds or minimized window")
		return
	if snapshot.speed!=1 or Engine.time_scale!=1.0 or (snapshot.paused and snapshot.tick<18000):
		_finish(false,"unexpected scheduler setting/pause")
		return
	if int(elapsed)>last_sample:
		last_sample=int(elapsed)
		_sample(snapshot,elapsed)
		if not active: return
		frames.flush()
		states.flush()
	if captures.is_empty(): _capture("start",snapshot,elapsed)
	elif captures.size()==1 and elapsed>=duration/2.0: _capture("middle",snapshot,elapsed)
	if not active: return
	if elapsed>=duration and (duration<1800 or snapshot.tick==18000):
		_capture("end",snapshot,elapsed)
		if not active: return
		_finish(true,"completed")

func _sample(snapshot: Dictionary, elapsed: float) -> void:
	var live_ids: Array=[]
	var patients:=0
	for id in snapshot.patients:
		if snapshot.patients[id].has("cell"):
			patients+=1
			live_ids.append(id)
	for id in snapshot.staff:
		if snapshot.staff[id].has("cell"): live_ids.append(id)
	live_ids.sort()
	var view_ids: Array=world.actor_views.keys()
	view_ids.sort()
	var row:={"elapsed_seconds":elapsed,"tick":snapshot.tick,"paused":snapshot.paused,"status":snapshot.challenge.status,"patients_inside":patients,"staff":snapshot.staff.size(),"actor_views":view_ids.size(),"view_ids_match":live_ids==view_ids,"room_views":world.room_views.size(),"rooms":snapshot.rooms.size(),"nodes":get_node_count(),"orphan_nodes":Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),"resources":Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),"engine_static_bytes":Performance.get_monitor(Performance.MEMORY_STATIC),"patient_history":snapshot.patients.size(),"scheduled_history":snapshot.scheduled_arrivals.size(),"ledger_entries":snapshot.ledger_entries.size(),"draws":draw_count,"processes":process_count}
	states.store_line(JSON.stringify(row))
	if patients!=40 or snapshot.staff.size()!=8 or live_ids!=view_ids or (snapshot.tick>0 and view_ids.size()!=48) or world.room_views.size()!=6:
		_finish(false,"live population/view mismatch")

func _capture(label: String, snapshot: Dictionary, elapsed: float) -> void:
	var img:=root.get_texture().get_image()
	if img==null or img.is_empty() or img.get_size()!=Vector2i(1280,720) or img.save_png(output.path_join(label+".png"))!=OK:
		_finish(false,"invalid capture")
		return
	captures.append({"label":label,"elapsed_seconds":elapsed,"tick":snapshot.tick,"draw":draw_count})

func _stats(values: Array[float]) -> Dictionary:
	var sorted:=values.duplicate()
	sorted.sort()
	return {"count":sorted.size(),"p50_ms":sorted[maxi(0,ceili(sorted.size()*0.5)-1)],"p95_ms":sorted[maxi(0,ceili(sorted.size()*0.95)-1)],"max_ms":sorted[-1],"percentile":"nearest rank; all startup-after-four-draw measurements included"}

func _finish(ok: bool, reason: String) -> void:
	if not active: return
	active=false
	meta.merge({"ok":ok,"reason":reason,"end_utc":Time.get_datetime_string_from_system(true),"monotonic_start_usec":started,"monotonic_end_usec":Time.get_ticks_usec(),"elapsed_seconds":float(Time.get_ticks_usec()-started)/1000000.0,"tick":session.sim.snapshot().tick,"draw_count":draw_count,"process_count":process_count,"draw_intervals":_stats(draw_times),"process_intervals":_stats(process_times),"process_delta":_stats(delta_times),"captures":captures,"focus_events":interruptions},true)
	frames.close()
	states.close()
	_write_json("run.json",meta)
	_write_json("final-snapshot.json",session.sim.snapshot())
	print("LOAD RESULT: "+JSON.stringify(meta))
	quit(0 if ok else 1)

func _write_json(name: String, value: Dictionary) -> void:
	var file:=FileAccess.open(output.path_join(name),FileAccess.WRITE)
	file.store_string(JSON.stringify(value,"  "))
	file.close()


