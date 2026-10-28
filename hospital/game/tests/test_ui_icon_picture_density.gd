extends "res://tests/test_ui_icon_density.gd"

func _icon_pictures(node:Node) -> Array[TextureRect]:
	var found:Array[TextureRect]=[]
	if node is TextureRect:
		var picture:TextureRect=node
		if picture.texture is DPITexture:found.append(picture)
	for child in node.get_children():found.append_array(_icon_pictures(child))
	return found

func _run() -> void:
	if DisplayServer.get_name()=="headless":
		push_error("Icon pictures require the real desktop renderer")
		quit(1)
		return
	root.size=Vector2i(1280,720)
	var host:Node3D=load("res://main.gd").new()
	host.session=GameSession.new(ContentCatalog.load_checked("res://content").catalog,"E:/CODEX/2026-10-20/医院整体画面继续优化/temp/icon-pictures-%d/save"%Time.get_ticks_usec())
	root.add_child(host);host.set_process(false)
	host.feedback.set_application_active(false);host.feedback._music_player.stop()
	var hud:HospitalHud=host.hud
	hud.flow.close();hud.present()
	await _settle()
	for fixture in [[160,Vector2(1280,720)],[640,Vector2(2560,1440)]]:
		var label:String="%d DPI"%fixture[0]
		hud.flow.close()
		hud.configure_display(fixture[1],Vector2(1280,720),fixture[0],Rect2(Vector2.ZERO,fixture[1]))
		hud.present()
		_samples.clear()
		# Break caught: a 27-unit alert is built before the hidden operations
		# drawer opens, and the 50-unit padded card must not stretch/crop it.
		hud._show_congestion()
		var alerts:Array[TextureRect]=_icon_pictures(hud.operations)
		check(alerts.size()==1,label+" the real congestion panel creates one SVG alert")
		if alerts.size()==1:
			var alert:TextureRect=alerts[0]
			alert.draw.connect(_sample_draw.bind(alert,"alert"))
			await _settle()
			check(alert.size==Vector2(27,27) and alert.size_flags_horizontal==Control.SIZE_SHRINK_CENTER and alert.size_flags_vertical==Control.SIZE_SHRINK_CENTER,label+" congestion alert remains a complete centered 27-unit square")
			_check_supply("alert",label+" real congestion alert")
			check(alert.get_parent().size==Vector2(50,50),label+" congestion icon card retains its approved 50-unit footprint")
		# Break caught: the existing guide close is created before _open shows
		# the page; its first visible draw still needs the active density.
		hud.flow.show_guide()
		var close_button:Button=hud.flow.controls.close_guide
		close_button.draw.connect(_sample_draw.bind(close_button,"guide_close"))
		await _settle()
		_check_supply("guide_close",label+" real guide close")
		check(close_button.custom_minimum_size==Vector2(48,48),label+" guide close preserves its 48dp touch target")
		# Use the authoritative, unmodified snapshot. Both result SVG keys use
		# this 42-unit slot; no fabricated won state is needed for a layout test.
		hud.flow.close()
		hud.flow.show_result(host.session.sim.snapshot())
		var emblems:Array[TextureRect]=_icon_pictures(hud.flow.body)
		check(emblems.size()==1,label+" the real result page creates its existing SVG emblem")
		if emblems.size()==1:
			var emblem:TextureRect=emblems[0]
			emblem.draw.connect(_sample_draw.bind(emblem,"result_emblem"))
			await _settle()
			check(emblem.size==Vector2(42,42) and emblem.size_flags_horizontal==Control.SIZE_SHRINK_CENTER and emblem.size_flags_vertical==Control.SIZE_SHRINK_CENTER,label+" result artwork remains a complete centered 42-unit square")
			_check_supply("result_emblem",label+" real result 42-unit artwork")
			var card:Control=emblem.get_parent()
			var approved_card:Rect2=card.get_global_rect()
			# Compare the unchanged card layout with the original FILL behavior.
			emblem.size_flags_horizontal=Control.SIZE_FILL
			emblem.size_flags_vertical=Control.SIZE_FILL
			await _settle()
			check(card.get_global_rect().is_equal_approx(approved_card),label+" centering the artwork preserves the result card and heading layout")
		hud.flow.close()
	host.free();await process_frame;await process_frame
	print("ICON PICTURE DENSITY RESULT: passed=%d failed=%d"%[passed,failed])
	if failed>0:quit(1)
	else:quit(0)
