extends SceneTree

var output: String
var records: Array=[]

func _initialize() -> void:
	output=ProjectSettings.globalize_path("res://../outputs/reviewed-preview-%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(output)
	_run.call_deferred()

func _run() -> void:
	var catalog: ContentCatalog=ContentCatalog.load_checked("res://content").catalog
	for physical in [Vector2(2400,1350),Vector2(2640,1080)]:
		for factor in [1.0,0.5]:
			var viewport:=SubViewport.new()
			viewport.size=Vector2i(physical*factor)
			viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
			root.add_child(viewport)
			var world:=HospitalWorld.new()
			viewport.add_child(world)
			var s:=GameSession.new(catalog,output.path_join("save-%d" % records.size()))
			s.sim=Scenarios.create_sim(catalog,"benchmark_18","fast","standard")
			s.sim.advance_ticks(1042)
			s.issue("set_paused",{"paused":true})
			world.present(s.sim.snapshot())
			var canvas:=CanvasLayer.new()
			viewport.add_child(canvas)
			var h:=HospitalHud.new()
			canvas.add_child(h)
			h.initialize(s,TouchController.new(world,Callable(),s.reserve_command_id),world)
			h.configure_display(physical,physical*factor,480,Rect2(Vector2(72,0),physical-Vector2(144,0)))
			s.notice=""
			h.select_entity("patient_000005","patients")
			h.selection.expand_flow("patient_000005")
			h.present()
			await _capture(viewport,h,physical,factor,"patient")
			h.controls.close_panel.pressed.emit()
			await _capture(viewport,h,physical,factor,"world")
			var io:=SaveFileIO.new()
			io.mkdir(s.save_root)
			io.write(s.save_root.path_join("main.json"),"invalid original main")
			io.write(s.save_root.path_join("previous.json"),"invalid original previous")
			s.open_saved()
			h.present()
			await _capture(viewport,h,physical,factor,"recovery")
			h.controls.recover.pressed.emit()
			s.dismiss_notice()
			var fixture: RefCounted=load("res://tests/suites/test_final_fix.gd").new()
			fixture.catalog=catalog
			var state:=ClinicState.new()
			state.data=fixture._failure_snapshot()
			s.sim=Simulation.new(catalog,state)
			world.present(s.sim.snapshot())
			h.present()
			h.controls.settlement.pressed.emit()
			await _capture(viewport,h,physical,factor,"settlement")
			var scroll: ScrollContainer=h._ledger.get_parent()
			scroll.scroll_vertical=210
			await _capture(viewport,h,physical,factor,"settlement-waits")
			viewport.queue_free()
			await process_frame
	var f:=FileAccess.open(output.path_join("display-evidence.json"),FileAccess.WRITE)
	f.store_string(JSON.stringify({"scope":"Actual desktop SubViewport rendering, injected physical display 480dpi; not Android device acceptance","engine":Engine.get_version_info(),"captures":records},"\t"))
	f.close()
	print("FINAL CAPTURES: "+output)
	quit()

func _capture(viewport: SubViewport, h: HospitalHud, physical: Vector2, factor: float, mode: String) -> void:
	for i in range(5): await RenderingServer.frame_post_draw
	var name:="%dx%d-%s-%s.png" % [physical.x,physical.y,"native" if factor==1.0 else "scaled",mode]
	for panel in [h._left,h._right,h._notice_panel,h._settlement_panel]:
		if panel.is_visible_in_tree() and ((h._top_frame.is_visible_in_tree() and panel.get_global_rect().intersects(h._top_frame.get_global_rect())) or (h._dock.is_visible_in_tree() and panel.get_global_rect().intersects(h._dock.get_global_rect()))):
			push_error("Rendered panel overlaps status or primary controls: "+mode)
			quit(1)
			return
	var img:=viewport.get_texture().get_image()
	if img.save_png(output.path_join(name))!=OK: quit(1); return
	var b: Button=h.controls.pause
	var row:={"path":name,"physical_output":str(physical),"viewport":str(viewport.size),"dpi":480,"factor":factor,"button_font_dp":b.get_theme_font_size("font_size")*h.scale.x/factor/3.0,"button_target_dp":b.custom_minimum_size.y*h.scale.y/factor/3.0,"hud_scale":str(h.scale),"top":str(h._top.get_global_rect()),"bottom":str(h._bottom.get_global_rect()),"notice":str(h._notice_panel.get_global_rect()),"settlement":str(h._settlement_panel.get_global_rect())}
	records.append(row)
