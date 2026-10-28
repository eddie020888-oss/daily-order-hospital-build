extends "res://tests/capture_ui.gd"

# Focused real-outcome visual regression for the restart control's second appearance.
func _run() -> void:
	if DisplayServer.get_name()=="headless" or not output_dir.replace("\\","/").begins_with("E:/CODEX/"):
		quit(1)
		return
	root.size=Vector2i(width,height)
	var catalog: ContentCatalog=ContentCatalog.load_checked("res://content").catalog
	session=GameSession.new(catalog,output_dir.path_join("isolated-save"))
	world=HospitalWorld.new()
	root.add_child(world)
	hud=HospitalHud.new()
	var layer:=CanvasLayer.new()
	root.add_child(layer)
	layer.add_child(hud)
	touch=TouchController.new(world,hud.hits_gui,session.reserve_command_id)
	touch.command_requested.connect(session.submit)
	hud.initialize(session,touch,world)
	session.changed.connect(_present)
	_present()
	# Two actual untreated rounds exercise hide -> show -> hide -> show of restart.
	for round_index in range(2):
		_press(hud.controls.speed2)
		await _until(2400)
		_press(hud.controls.dismiss)
		_press(hud.controls.speed2)
		await _until(4800)
		_press(hud.controls.dismiss)
		_press(hud.controls.speed2)
		await _until(9000)
		_check(session.sim.snapshot().challenge.status=="lost","actual failure round "+str(round_index+1))
		await _capture("failure-round-"+str(round_index+1))
		_press(hud.controls.restart)
		_check(session.sim.snapshot().paused and session.sim.snapshot().tick==0,"actual failure restart "+str(round_index+1))
	print("FAILURE VISUAL RESULT: "+("FAILED" if failed else "OK"))
	quit(1 if failed else 0)
