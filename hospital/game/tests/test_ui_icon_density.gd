extends SceneTree

var passed:=0
var failed:=0
var _samples:Dictionary={}

func _initialize() -> void:
	_run.call_deferred()

func check(value:bool,label:String) -> void:
	if value:passed+=1
	else:failed+=1
	print(("ICON DENSITY PASS: " if value else "ICON DENSITY FAIL: ")+label)

func _settle() -> void:
	for _i in range(4):
		await process_frame
		await RenderingServer.frame_post_draw

# Inspect the RID while its real Button/TextureRect is drawing. DPITexture's
# ordinary get_image() deliberately returns the 1x image, not this active raster.
func _sample_draw(control:Control,key:String) -> void:
	var texture:Texture2D=(control as Button).icon if control is Button else (control as TextureRect).texture
	var active_rid:RID=texture.call("get_scaled_rid") if texture.has_method("get_scaled_rid") else texture.get_rid()
	var bitmap:Image=RenderingServer.texture_2d_get(active_rid)
	if bitmap==null:return
	var drawn_size:Vector2=texture.get_size()
	if control is TextureRect:
		var rect:TextureRect=control
		var edge:float=maxf(rect.size.x,rect.size.y) if rect.stretch_mode==TextureRect.STRETCH_KEEP_ASPECT_COVERED else minf(rect.size.x,rect.size.y)
		drawn_size=Vector2.ONE*edge
	var draw_scale:Vector2=control.get_global_transform_with_canvas().get_scale().abs()
	_samples[key]={"rid":active_rid.get_id(),"raster":bitmap.get_size(),"drawn":drawn_size*draw_scale,"logical_rect":control.size,"logical_texture":texture.get_size()}

func _check_supply(key:String,label:String) -> void:
	check(_samples.has(key),label+" was inspected during its real draw")
	if not _samples.has(key):return
	var sample:Dictionary=_samples[key]
	var raster:Vector2=sample.raster
	var drawn:Vector2=sample.drawn
	check(raster.x+0.01>=drawn.x and raster.y+0.01>=drawn.y,label+" has enough source pixels for its actual render: "+JSON.stringify(sample))

func _run() -> void:
	if DisplayServer.get_name()=="headless":
		push_error("Icon density requires the real desktop renderer, not the headless dummy renderer")
		quit(1)
		return
	root.size=Vector2i(1280,720)
	var catalog:ContentCatalog=ContentCatalog.load_checked("res://content").catalog
	var host:Node3D=load("res://main.gd").new()
	host.session=GameSession.new(catalog,"E:/CODEX/2026-10-20/医院整体画面继续优化/temp/icon-density-%d/save"%Time.get_ticks_usec())
	root.add_child(host)
	host.set_process(false)
	host.feedback.set_application_active(false)
	host.feedback._music_player.stop()
	host.hud.flow.close()
	host.hud.present()
	await _settle()
	var hud:HospitalHud=host.hud
	# Break caught: dense icon textures must not become 48/96-unit layout assets,
	# nor allocate a new resource on every HUD present/play-state refresh.
	var play:Texture2D=HospitalUiStyle.icon("play")
	check(play==HospitalUiStyle.icon("play"),"the same icon key and logical size reuse one cached texture")
	check(play.get_size()==Vector2(24,24),"default action icons retain their approved 24-unit natural size")
	var result_icon:Texture2D=HospitalUiStyle.icon("check",42)
	check(result_icon.get_size()==Vector2(42,42) and result_icon==HospitalUiStyle.icon("check",42),"explicit 42-unit result artwork retains its natural size and cache")
	for key in ["pause","save","settings"]:
		var button:Button=hud.controls[key]
		button.draw.connect(_sample_draw.bind(button,key))
	for index in range(3):
		var mark:TextureRect=hud._status_cards[index].get_child(0).get_child(0)
		mark.draw.connect(_sample_draw.bind(mark,"status_%d"%index))
	# Density 640 at half-size rendering is the reported short-landscape fixture.
	# The fractional case catches rounding undersupply during display changes.
	for fixture in [[160,Vector2(1280,720),1.0],[480,Vector2(2560,1440),1.5],[640,Vector2(2560,1440),2.0],[160,Vector2(1280,720),1.0]]:
		var output:Vector2=fixture[1]
		var label:String="%d DPI / %.1fx"%[fixture[0],fixture[2]]
		hud.configure_display(output,Vector2(1280,720),fixture[0],Rect2(Vector2.ZERO,output))
		hud.present()
		_samples.clear()
		for key in ["pause","save","settings"]:hud.controls[key].queue_redraw()
		for index in range(3):hud._status_cards[index].get_child(0).get_child(0).queue_redraw()
		await _settle()
		for key in ["pause","save","settings"]:
			_check_supply(key,label+" "+key)
			var button:Button=hud.controls[key]
			var approved:Texture2D=button.icon
			var icon_rect:Rect2=button.get_global_rect()
			var minimum:Vector2=button.get_combined_minimum_size()
			# A real 24px ImageTexture reproduces the original layout contract.
			# Compare actual container reflow, rather than asserting source text.
			button.icon=ImageTexture.create_from_image(Image.create_empty(24,24,false,Image.FORMAT_RGBA8))
			await _settle()
			check(icon_rect.is_equal_approx(button.get_global_rect()) and minimum.is_equal_approx(button.get_combined_minimum_size()),label+" "+key+" button rect and minimum match the approved 24-unit icon layout")
			check(button.custom_minimum_size==Vector2(48,48) and button.get_global_rect().size.y+0.01>=48.0*float(fixture[2]),label+" "+key+" keeps its 48dp touch target")
			button.icon=approved
			await _settle()
		var active_keys:Array[String]=["pause","save","settings"]
		for index in range(3):
			var mark:TextureRect=hud._status_cards[index].get_child(0).get_child(0)
			if not mark.is_visible_in_tree():
				check(index==2 or hud._top.size.x<320,label+" only intentional clock/compact status artwork is hidden")
				continue
			active_keys.append("status_%d"%index)
			_check_supply("status_%d"%index,label+" status_%d"%index)
			var edge:float=20 if hud._top.size.x<420 else 26
			check(mark.size==Vector2.ONE*edge and mark.size_flags_vertical==Control.SIZE_SHRINK_CENTER,label+" status_%d keeps its complete centered A2 artwork in the allocated square"%index)
		var resident_samples:Dictionary=_samples.duplicate(true)
		hud.configure_display(output,Vector2(1280,720),fixture[0],Rect2(Vector2.ZERO,output))
		hud.present()
		for key in ["pause","save","settings"]:hud.controls[key].queue_redraw()
		for index in range(3):hud._status_cards[index].get_child(0).get_child(0).queue_redraw()
		await _settle()
		var reused:bool=true
		var returned_to_1x:bool=true
		for key in active_keys:
			reused=reused and _samples.has(key) and resident_samples.has(key) and _samples[key].rid==resident_samples[key].rid
			if float(fixture[2])==1.0:returned_to_1x=returned_to_1x and _samples.has(key) and _samples[key].raster==Vector2i(_samples[key].logical_texture)
		check(reused and HospitalUiStyle.icon("play")==play,label+" unchanged density reuses the cached icon and active raster RIDs")
		if float(fixture[2])==1.0:check(returned_to_1x,label+" renders each icon at its authored 1x raster after restoring normal density")
	host.free()
	await process_frame
	await process_frame
	print("ICON DENSITY RESULT: passed=%d failed=%d"%[passed,failed])
	quit(1 if failed else 0)
