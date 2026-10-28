class_name HospitalSettingsPanel
extends VBoxContainer

signal preference_result(result: Dictionary)
var controls: Dictionary={}
var haptics_hint: Label
var _feedback: HospitalFeedback
var _volume_dragging:=false
var _error: Label
var _sound_page: VBoxContainer
var _guide_page: VBoxContainer
var _volume_value: Label
var _switch_states: Dictionary={}
var section:="sound"
const PANEL_BLUE:=HospitalUiStyle.PAPER
const PANEL_LINE:=HospitalUiStyle.LINE
const TITLE_BLUE:=HospitalUiStyle.DEEP

func initialize(feedback: HospitalFeedback, catalog: ContentCatalog) -> void:
	_feedback=feedback
	add_theme_constant_override("separation",6)
	var navigation:=HBoxContainer.new()
	navigation.add_theme_constant_override("separation",6)
	add_child(navigation)
	for item in [["sound","声音反馈"],["guide","操作指南"]]:
		var key: String=item[0]
		var tab:=Button.new()
		tab.text=item[1]
		tab.toggle_mode=true
		tab.custom_minimum_size=Vector2(48,48)
		tab.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		tab.add_theme_font_size_override("font_size",16)
		navigation.add_child(tab)
		controls["settings_"+key]=tab
		tab.pressed.connect(func() -> void: _select_section(key))
	_sound_page=VBoxContainer.new()
	_sound_page.add_theme_constant_override("separation",6)
	add_child(_sound_page)
	_guide_page=VBoxContainer.new()
	_guide_page.add_theme_constant_override("separation",6)
	add_child(_guide_page)

	var sound:=_card(_sound_page)
	_card_heading(sound,"sound","声音与设备")
	_switch_row(sound,"music","背景音乐","播放医院背景音乐",func() -> void: _set_preference("music_enabled"))
	_divider(sound)
	var volume:=VBoxContainer.new()
	volume.add_theme_constant_override("separation",0)
	sound.add_child(volume)
	var volume_header:=HBoxContainer.new()
	volume.add_child(volume_header)
	var title:=HospitalUiStyle.text("音乐音量",15,HospitalUiStyle.INK,650)
	title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	volume_header.add_child(title)
	_volume_value=HospitalUiStyle.text("0%",16,TITLE_BLUE,700)
	_volume_value.custom_minimum_size.x=48
	_volume_value.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	volume_header.add_child(_volume_value)
	controls.music_volume_value=_volume_value
	var slider:=HSlider.new()
	slider.custom_minimum_size=Vector2(150,48)
	slider.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	slider.min_value=0; slider.max_value=100; slider.step=1
	slider.tooltip_text="音乐音量"
	var track:=_surface(HospitalUiStyle.SOFT,2,0)
	track.content_margin_top=2
	track.content_margin_bottom=2
	track.set_border_width_all(0)
	var filled:=track.duplicate() as StyleBoxFlat
	filled.bg_color=HospitalUiStyle.TEAL
	slider.add_theme_stylebox_override("slider",track)
	slider.add_theme_stylebox_override("grabber_area",filled)
	slider.add_theme_stylebox_override("grabber_area_highlight",filled)
	for state in ["grabber","grabber_highlight","grabber_disabled"]:
		var knob_image:=Image.new()
		var fill: String="#f3f3e8" if state!="grabber_disabled" else "#d1e2de"
		knob_image.load_svg_from_string('<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24"><circle cx="12" cy="12" r="10" fill="'+fill+'" stroke="#277a80" stroke-width="1.5"/></svg>')
		slider.add_theme_icon_override(state,ImageTexture.create_from_image(knob_image))
	volume.add_child(slider)
	controls.music_volume=slider
	slider.drag_started.connect(func() -> void: _volume_dragging=true)
	slider.value_changed.connect(func(value: float) -> void:
		_volume_value.text="%d%%" % roundi(value)
		if not _volume_dragging: _commit_volume(value))
	slider.drag_ended.connect(func(changed: bool) -> void:
		if not _volume_dragging: return
		_volume_dragging=false
		if changed: _commit_volume(slider.value)
		else: _sync({} if _feedback==null else _feedback.preferences()))
	_divider(sound)
	haptics_hint=_switch_row(sound,"haptics","触觉反馈","操作时提供振动反馈",func() -> void: _set_preference("haptics_enabled"))
	if _feedback==null: haptics_hint.text="声音与触觉服务当前不可用"
	elif not _feedback.haptics_supported(): haptics_hint.text="此设备不支持触觉反馈"
	var note:=HospitalUiStyle.text("偏好保存在本机；调整设置不推进医院时间。",14,HospitalUiStyle.MUTED)
	note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	_sound_page.add_child(note)
	_error=HospitalUiStyle.text("",15,Color("9e4737"))
	_error.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	_error.hide()
	add_child(_error)

	var gestures:=_card(_guide_page)
	_card_heading(gestures,"settings","基本操作")
	var copy:=HospitalUiStyle.text("单指点选与拖动，双指缩放。放置设施时，可以旋转、取消与确认。",14,HospitalUiStyle.INK)
	copy.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	gestures.add_child(copy)
	_step(1,"先暂停，再调整","暂停时可以建设与派岗；费用仍正常计算。")
	_step(2,"留出恢复席位","刺激严格大于患者耐受时才需要恢复。快速刺激 %d，舒缓刺激 %d；恢复服务 %d 秒。" % [catalog.diseases.echo.modes.fast.stimulus,catalog.diseases.echo.modes.gentle.stimulus,catalog.rooms.recovery.service_ticks/10])
	_step(3,"离院后才收款","患者实际离院后结算。移动与排队会消耗耐心，实际服务时间不消耗。")
	if _feedback!=null: _feedback.preferences_changed.connect(_sync)
	_sync({} if _feedback==null else _feedback.preferences())
	_select_section("sound")

func _surface(color: Color, radius: int=6, margin: int=8) -> StyleBoxFlat:
	var style:=StyleBoxFlat.new()
	style.bg_color=color
	style.border_color=PANEL_LINE
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.set_content_margin_all(margin)
	return style

func _divider(parent: Node) -> void:
	var line:=HSeparator.new()
	var style:=StyleBoxLine.new()
	style.color=HospitalUiStyle.LINE
	style.thickness=1
	line.add_theme_stylebox_override("separator",style)
	line.custom_minimum_size.y=3
	parent.add_child(line)

func _card(parent: Node, color: Color=PANEL_BLUE) -> VBoxContainer:
	var card:=PanelContainer.new()
	card.add_theme_stylebox_override("panel",_surface(color))
	parent.add_child(card)
	var body:=VBoxContainer.new()
	body.add_theme_constant_override("separation",4)
	card.add_child(body)
	return body

func _card_heading(parent: Node, icon_key: String, copy: String) -> void:
	var row:=HBoxContainer.new()
	row.add_theme_constant_override("separation",6)
	parent.add_child(row)
	var icon:=HospitalUiStyle.icon_picture(icon_key,16)
	icon.self_modulate=HospitalUiStyle.TEAL
	row.add_child(icon)
	row.add_child(HospitalUiStyle.text(copy,15,TITLE_BLUE,700))

func _select_section(key: String) -> void:
	if _volume_dragging: cancel_drafts()
	section=key
	_sound_page.visible=key=="sound"
	_guide_page.visible=key=="guide"
	for tab_key in ["sound","guide"]:
		var tab: Button=controls["settings_"+tab_key]
		var selected: bool=tab_key==key
		tab.set_pressed_no_signal(selected)
		for state in ["normal","hover","pressed"]:
			var background: Color=HospitalUiStyle.PAPER if selected else HospitalUiStyle.SOFT
			if state=="hover": background=HospitalUiStyle.IVORY if selected else HospitalUiStyle.PAPER
			if state=="pressed": background=HospitalUiStyle.SOFT
			var style:=_surface(background,5,7)
			style.border_color=HospitalUiStyle.TEAL if selected else HospitalUiStyle.LINE
			tab.add_theme_stylebox_override(state,style)
		for state in ["font_color","font_hover_color","font_pressed_color","font_hover_pressed_color","font_focus_color"]:
			tab.add_theme_color_override(state,HospitalUiStyle.TEAL if selected else HospitalUiStyle.MUTED)
	if get_parent() is ScrollContainer: get_parent().set_deferred("scroll_vertical",0)

func _switch_row(parent: Node, key: String, title: String, description: String, action: Callable) -> Label:
	var row:=HBoxContainer.new()
	row.add_theme_constant_override("separation",8)
	parent.add_child(row)
	var body:=VBoxContainer.new()
	body.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	body.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	body.add_theme_constant_override("separation",1)
	row.add_child(body)
	var heading:=HBoxContainer.new()
	body.add_child(heading)
	var heading_copy:=HospitalUiStyle.text(title,16,HospitalUiStyle.INK,700)
	heading_copy.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	heading.add_child(heading_copy)
	var state:=HospitalUiStyle.text("关闭",14,HospitalUiStyle.MUTED,600)
	state.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	heading.add_child(state)
	_switch_states[key]=state
	controls[key+"_state"]=state
	var copy:=HospitalUiStyle.text(description,14,HospitalUiStyle.MUTED)
	copy.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	body.add_child(copy)
	var button:=Button.new()
	button.custom_minimum_size=Vector2(56,48)
	button.set_meta("minimum_size",Vector2(56,48))
	button.set_meta("fixed_width",true)
	button.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	button.tooltip_text=title
	controls[key]=button
	row.add_child(button)
	var track:=Panel.new()
	track.name="Track"
	track.mouse_filter=Control.MOUSE_FILTER_IGNORE
	button.add_child(track)
	var knob:=Panel.new()
	knob.name="Knob"
	knob.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var knob_style:=_surface(HospitalUiStyle.IVORY,10,0)
	knob.add_theme_stylebox_override("panel",knob_style)
	knob.size=Vector2(20,20)
	track.add_child(knob)
	button.resized.connect(func() -> void: _switch_visual(button,bool(button.get_meta("enabled",false))))
	button.pressed.connect(action)
	return copy

func _switch_visual(button: Button, enabled: bool) -> void:
	button.set_meta("enabled",enabled)
	for state in ["normal","hover","pressed","disabled"]:
		button.add_theme_stylebox_override(state,StyleBoxEmpty.new())
	var track: Panel=button.get_node("Track")
	var style:=_surface(HospitalUiStyle.TEAL if enabled else HospitalUiStyle.LINE,12,0)
	style.border_color=HospitalUiStyle.TEAL if enabled else HospitalUiStyle.LINE
	track.add_theme_stylebox_override("panel",style)
	track.size=Vector2(48,24)
	track.position=Vector2((button.size.x-48)/2,(button.size.y-24)/2)
	track.get_node("Knob").position=Vector2(26 if enabled else 2,2)

func _step(number: int, title: String, copy: String) -> void:
	var body:=_card(_guide_page)
	var row:=HBoxContainer.new()
	row.add_theme_constant_override("separation",7)
	body.add_child(row)
	var badge:=HospitalUiStyle.text(str(number),14,HospitalUiStyle.TEAL,700)
	badge.custom_minimum_size=Vector2(27,25)
	badge.size_flags_vertical=Control.SIZE_SHRINK_BEGIN
	badge.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	badge.add_theme_stylebox_override("normal",_surface(HospitalUiStyle.SOFT,5,3))
	row.add_child(badge)
	var heading:=HospitalUiStyle.text(title,16,HospitalUiStyle.INK,700)
	heading.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	heading.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	heading.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	row.add_child(heading)
	var detail:=HospitalUiStyle.text(copy,14,HospitalUiStyle.INK)
	detail.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	body.add_child(detail)

func _sync(preferences: Dictionary) -> void:
	controls.music.disabled=_feedback==null
	controls.haptics.disabled=_feedback==null or not _feedback.haptics_supported()
	controls.music_volume.editable=_feedback!=null
	for key in ["music","haptics"]:
		var button: Button=controls[key]
		var enabled: bool=bool(preferences.get(key+"_enabled",false)) and not button.disabled
		_switch_visual(button,enabled)
		var state: Label=_switch_states[key]
		state.text="不可用" if button.disabled else "开启" if enabled else "关闭"
		state.add_theme_color_override("font_color",HospitalUiStyle.TEAL if enabled else HospitalUiStyle.MUTED)
		button.tooltip_text=("背景音乐" if key=="music" else "触觉反馈")+" · "+state.text
	if not _volume_dragging:
		controls.music_volume.set_value_no_signal(float(preferences.get("music_volume",0))*100)
		_volume_value.text="%d%%" % roundi(controls.music_volume.value)

func cancel_drafts() -> void:
	_volume_dragging=false
	_sync({} if _feedback==null else _feedback.preferences())

func _set_preference(key: String) -> void:
	if _feedback==null or (key=="haptics_enabled" and not _feedback.haptics_supported()): return
	var enabled: bool=not _feedback.preferences()[key]
	_finish(_feedback.set_music_enabled(enabled) if key=="music_enabled" else _feedback.set_haptics_enabled(enabled))

func _commit_volume(value: float) -> void:
	if _feedback!=null: _finish(_feedback.set_music_volume(value/100.0))

func _finish(result: Dictionary) -> void:
	_error.visible=not result.ok
	_error.text="设置未保存，请检查设备存储空间后重试。" if not result.ok else ""
	_sync(_feedback.preferences())
	preference_result.emit(result)
