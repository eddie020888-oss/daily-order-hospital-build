extends SceneTree

var output_path := ""
var state_name := "busy"
var width := 1280
var height := 720

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		var pair := argument.split("=",true,1)
		if pair.size()!=2:
			continue
		match pair[0]:
			"output": output_path=pair[1]
			"state": state_name=pair[1]
			"width": width=int(pair[1])
			"height": height=int(pair[1])
	capture.call_deferred()

func capture() -> void:
	if FileAccess.file_exists(output_path) or DisplayServer.get_name() == "headless" or not output_path.replace("\\","/").begins_with("E:/CODEX/"):
		push_error("Capture requires a real rendered window and E:/CODEX output")
		quit(1)
		return
	root.size=Vector2i(width,height)
	var catalog: ContentCatalog = ContentCatalog.load_checked("res://content").catalog
	var sim := Scenarios.create_sim(catalog,"benchmark_18","fast","standard")
	var snapshot := _find_snapshot(sim)
	if snapshot.is_empty():
		push_error("No real simulation snapshot matched " + state_name)
		quit(1)
		return
	var world := HospitalWorld.new()
	root.add_child(world)
	world.present(snapshot)
	if state_name in ["echo","motion","sensory","recovery_full"]:
		for room in snapshot.rooms.values():
			if room.kind == ("recovery" if state_name == "recovery_full" else state_name):
				world.focus_cell(room.service_cells[0])
				world.camera_rig.set_zoom(8.0)
	_add_caption(snapshot)
	# Real Windows/OpenGL window. Wait for four submitted frames before reading its viewport texture.
	for frame in range(4):
		await process_frame
		await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null or image.is_empty() or image.get_size()!=Vector2i(width,height):
		push_error("Invalid rendered viewport image")
		quit(1)
		return
	var result := image.save_png(output_path)
	if result != OK:
		push_error("Cannot save rendered viewport: " + str(result))
		quit(1)
		return
	var metadata := {"state":state_name,"tick":snapshot.tick,"viewport":[width,height],"waited_render_frames":4,"display":DisplayServer.get_name(),"renderer":RenderingServer.get_current_rendering_method(),"rendering_driver":RenderingServer.get_current_rendering_driver_name(),"adapter":RenderingServer.get_video_adapter_name(),"api":RenderingServer.get_video_adapter_api_version(),"patients":snapshot.patients,"slots":snapshot.slots,"cash":snapshot.cash,"output":output_path}
	var file := FileAccess.open(output_path+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify(metadata,"  "))
	file.close()
	print("CAPTURE OK: " + JSON.stringify({"path":output_path,"state":state_name,"tick":snapshot.tick,"renderer":metadata.renderer,"adapter":metadata.adapter,"frames":4}))
	quit(0)

func _find_snapshot(sim: Simulation) -> Dictionary:
	if state_name in ["opening","typography"]:
		return sim.snapshot()
	for tick in range(9000):
		sim.advance_ticks(1)
		var snapshot := sim.snapshot()
		if state_name == "busy" and tick == 1400:
			return snapshot
		if state_name in ["echo","motion","sensory"]:
			for patient in snapshot.patients.values():
				if patient.phase == "treatment_service" and patient.disease_id == state_name:
					return snapshot
		if state_name == "recovery_full":
			var recovering := false
			var blocked := false
			for patient in snapshot.patients.values():
				recovering = recovering or patient.phase == "recovering"
				blocked = blocked or patient.phase == "waiting_recovery"
			if recovering and blocked:
				return snapshot
	return {}

func _add_caption(snapshot: Dictionary) -> void:
	var layer := CanvasLayer.new()
	root.add_child(layer)
	var canvas := Control.new()
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.theme=load("res://ui/theme.tres")
	layer.add_child(canvas)
	var top := ColorRect.new()
	top.color=Color("f7f5e8")
	top.position=Vector2(24,20)
	top.size=Vector2(width-48,76)
	canvas.add_child(top)
	var title := Label.new()
	title.text="日常秩序医院"
	title.position=Vector2(44,28)
	title.add_theme_font_size_override("font_size",30)
	canvas.add_child(title)
	var subtitle := Label.new()
	subtitle.text="原创 Q 版场景  /  薄荷色的一天"
	subtitle.position=Vector2(46,65)
	subtitle.add_theme_font_size_override("font_size",15)
	canvas.add_child(subtitle)
	var status := Label.new()
	var state_title: String = {"opening":"开院准备","typography":"中文排版 · 500 字重","busy":"忙碌时刻","echo":"句尾回放症 · 声环梳理","motion":"动作串线症 · 节奏校准","sensory":"感官串台症 · 双轨分离","recovery_full":"恢复区满员 · 等待恢复席位"}[state_name]
	status.text="%s   |   %d 币   |   %d 秒" % [state_title,snapshot.cash,snapshot.tick/10]
	status.position=Vector2(width-690,44)
	status.add_theme_font_size_override("font_size",20)
	canvas.add_child(status)
	var footer := ColorRect.new()
	footer.color=Color("f7f5e8")
	footer.position=Vector2(24,height-80)
	footer.size=Vector2(width-48,58)
	canvas.add_child(footer)
	var legend := Label.new()
	legend.text="◌ 句尾回放症     ◇ 动作串线症     ● 感官串台症     ✓ 治疗完成    |    薄荷：空闲 / 暖橙：占用"
	legend.position=Vector2(44,height-65)
	legend.add_theme_font_size_override("font_size",19)
	canvas.add_child(legend)
	if state_name == "typography":
		_add_typography_card(canvas)


func _add_typography_card(canvas: Control) -> void:
	var panel := ColorRect.new()
	panel.color=Color("f7f5e8")
	panel.position=Vector2(width/2-470,140)
	panel.size=Vector2(940,430)
	canvas.add_child(panel)
	var samples := [
		[30,"句尾回放症 / 动作串线症 / 感官串台症"],
		[22,"快速　舒缓　按耐受分流　暂停　继续　1× / 2×　8000 币"],
		[22,"建造　招聘　分配　移动　拆除　升级　关闭　重新开放　保存　加载"],
		[22,"恢复区满员：该患者已完成治疗，但正在等待恢复席位。请建造或升级恢复区，释放治疗设备；耐心不足的患者可能弃诊。"],
		[18,"未完成 12 / 36 · 弃诊离院中 · 等待通路（设备占用）！原因说明：资金不足，无法完成这次操作。"]
	]
	var y:=164
	for sample in samples:
		var label:=Label.new()
		label.text=sample[1]
		label.position=Vector2(width/2-446,y)
		label.size=Vector2(892,100 if sample[1].length()>60 else 60)
		label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override("font_size",sample[0])
		canvas.add_child(label)
		y+=96 if sample[1].length()>60 else 70
