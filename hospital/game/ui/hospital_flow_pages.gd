class_name HospitalFlowPages
extends Control

signal action_requested(action: String)
signal opening

var page := ""
var controls: Dictionary = {}
var result_summary: Dictionary = {}
var session: GameSession
var panel: PanelContainer
var body: VBoxContainer
var footer: HBoxContainer
var _shade: ColorRect
var _scroll: ScrollContainer
var _version: Label
var _blur_material: ShaderMaterial
var _safe := Rect2(8,8,1264,704)
var _unlock_kind := ""
var _header: Control
var _column: VBoxContainer
var _responsive_labels: Array[Label] = []
var _level_grids: Array[GridContainer] = []
var _stat_cards: Array[PanelContainer] = []
var _a2_launch_grid: GridContainer
var _a2_launch_tools: GridContainer

const MENU_FACE := HospitalUiStyle.PAPER
const MENU_INSET := HospitalUiStyle.IVORY

func initialize(owner_session: GameSession) -> void:
	session = owner_session
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shade = ColorRect.new()
	_shade.color = Color("102e3833")
	_shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_shade)
	_blur_material = ShaderMaterial.new()
	# Keep a material on modal shades without obscuring the live hospital.
	var veil := Shader.new()
	veil.code = "shader_type canvas_item; render_mode unshaded; void fragment() { COLOR = vec4(0.045, 0.095, 0.115, 0.20); }"
	_blur_material.shader = veil
	_version = HospitalUiStyle.text("",12,Color("e5eeeb"),500)
	_version.add_theme_stylebox_override("normal",_menu_style(Color("183f48dc"),5))
	add_child(_version)
	hide()

func close() -> void:
	page = ""
	hide()

func configure(safe_rect: Rect2) -> void:
	_safe = safe_rect
	position = Vector2.ZERO
	size = _safe.end + Vector2(8,8)
	_shade.position = Vector2.ZERO
	_shade.size = size
	_version.position = Vector2(_safe.end.x-244,_safe.end.y-32)
	_version.size = Vector2(230,28)
	_version.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_version.visible = page == "launch" and _safe.size.y >= 500
	if panel == null: return
	var compact := _safe.size.y < 600
	if page == "launch":
		_configure_a2_launch()
		return
	var width := 900.0 if page == "result" else 620.0 if page == "launch" else 820.0 if page == "levels" else 470.0 if page == "guide" else 600.0 if page == "pause" else 590.0
	width = minf(width,_safe.size.x-20)
	var inset := 12 if compact else 16
	for label: Label in _responsive_labels:
		if is_instance_valid(label):
			label.add_theme_font_size_override("font_size",int(label.get_meta("compact_font")) if compact else int(label.get_meta("regular_font")))
			if label.has_meta("hide_compact"): label.visible = not compact
	for key: String in controls:
		var control: Control = controls[key]
		if control is Button:
			control.add_theme_font_size_override("font_size",16 if compact else 18)
	for grid: GridContainer in _level_grids:
		if is_instance_valid(grid): grid.columns = 1
	for card: PanelContainer in _stat_cards:
		if is_instance_valid(card):
			card.add_theme_stylebox_override("panel",_menu_style(MENU_INSET,7 if compact else 9,true))
	body.add_theme_constant_override("separation",7 if compact else 10)
	_column.add_theme_constant_override("separation",8 if compact else 10)
	footer.add_theme_constant_override("separation",6 if compact else 8)
	var max_height := minf(620,_safe.size.y-20)
	if page == "guide":
		panel.size = Vector2(width,max_height)
		panel.position = _safe.position+(_safe.size-panel.size)/2.0
	else:
		var fixed_height := inset*2.0
		if _header != null: fixed_height += _header.get_combined_minimum_size().y+(8 if compact else 10)
		if footer.visible: fixed_height += footer.get_combined_minimum_size().y+(8 if compact else 10)
		var content_height := body.get_combined_minimum_size().y+fixed_height
		if page == "levels": content_height = max_height
		if page == "launch": content_height = maxf(content_height,340 if compact else 368)
		panel.size = Vector2(width,minf(max_height,content_height))
		panel.position = _safe.position+(_safe.size-panel.size)/2.0
	panel.add_theme_stylebox_override("panel",_menu_style(MENU_FACE,inset))
	_scroll.custom_minimum_size.y = 0
	if footer.get_child_count() > 2:
		for child: Node in footer.get_children():
			if child is Button: child.size_flags_horizontal = Control.SIZE_EXPAND_FILL

func _menu_style(fill: Color, padding: int=8, recessed: bool=false) -> StyleBoxTexture:
	return HospitalUiStyle.bevel(fill,padding,recessed)

func _open(next_page: String, title: String="") -> void:
	opening.emit()
	page = next_page
	_shade.material = null if page in ["launch","guide"] else _blur_material
	_shade.color = Color("102e3833") if page != "guide" else Color(0,0,0,0.08)
	_version.visible = page == "launch" and _safe.size.y >= 500
	_version.text = "日常秩序医院 · 本机进度"
	controls.clear()
	_responsive_labels.clear()
	_level_grids.clear()
	_stat_cards.clear()
	_a2_launch_grid = null
	_a2_launch_tools = null
	_header = null
	if panel != null:
		remove_child(panel)
		panel.queue_free()
	panel = PanelContainer.new()
	panel.name = "SystemPage_"+page
	add_child(panel)
	_column = VBoxContainer.new()
	_column.add_theme_constant_override("separation",10)
	panel.add_child(_column)
	if title != "":
		_header = _page_heading(_column,title)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_column.add_child(_scroll)
	_scroll.add_theme_stylebox_override("panel",StyleBoxEmpty.new())
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation",9)
	_scroll.add_child(body)
	footer = HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_END
	footer.add_theme_constant_override("separation",10)
	_column.add_child(footer)
	show()
	configure(_safe)
	_finish_layout.call_deferred()

func _page_heading(parent: Node, title: String) -> Control:
	var header := VBoxContainer.new()
	header.add_theme_constant_override("separation",8)
	parent.add_child(header)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",8)
	header.add_child(row)
	var symbols := {"levels":"home","pause":"pause","saved":"check","save_failed":"alert","storage":"save","unlock":"plus","restart":"alert","result":"chart"}
	var symbol := HospitalUiStyle.icon_picture(str(symbols.get(page,"medical")),20)
	symbol.modulate = HospitalUiStyle.TEAL
	row.add_child(symbol)
	var heading := _text(row,title,21,HospitalUiStyle.INK,700)
	heading.autowrap_mode = TextServer.AUTOWRAP_OFF
	heading.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if page == "guide":
		var close_button := _button(row,"close_guide","","hospital")
		close_button.icon = HospitalUiStyle.icon("close")
	header.add_child(HSeparator.new())
	return header

func _finish_layout() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if page != "":
		configure(_safe)
		_focus_default()

func _focus_default() -> void:
	var preferred := str({"launch":"continue_game","pause":"resume_game","restart":"cancel_restart","levels":"levels_back","guide":"guide_build","saved":"back_hospital","save_failed":"retry_save","storage":"storage_back","unlock":"unlock_later","result":"back_hospital"}.get(page,""))
	if page == "levels":
		for key: String in controls:
			if key.begins_with("level_") and not controls[key].disabled:
				preferred = key
				break
	if controls.has(preferred):
		var target: Control = controls[preferred]
		if target.is_visible_in_tree() and not (target is Button and target.disabled):
			target.grab_focus()
		elif page == "pause" and controls.has("main_menu"):
			controls.main_menu.grab_focus()

func _text(parent: Node, copy: String, font_size: int=18, color: Color=HospitalUiStyle.INK, weight: int=400) -> Label:
	var label := HospitalUiStyle.text(copy,font_size,color,weight)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.set_meta("regular_font",font_size)
	label.set_meta("compact_font",font_size-4 if font_size >= 25 else font_size-2 if font_size >= 18 else font_size)
	_responsive_labels.append(label)
	parent.add_child(label)
	return label

func _button(parent: Node, key: String, copy: String, action: String, primary: bool=false, danger: bool=false) -> Button:
	var b := BuildPalette.button(copy)
	b.clip_text = false
	b.add_theme_font_override("font",HospitalUiStyle.font(650))
	b.custom_minimum_size = Vector2(48,48)
	b.set_meta("minimum_size",Vector2(48,48))
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL if parent is VBoxContainer or parent is GridContainer else Control.SIZE_SHRINK_END
	parent.add_child(b)
	controls[key] = b
	for state: String in ["normal","hover","pressed","disabled"]:
		var fill := MENU_INSET if state == "normal" else HospitalUiStyle.SOFT if state == "hover" else Color("c0d8d4") if state == "pressed" else Color("dce4df")
		b.add_theme_stylebox_override(state,_menu_style(fill,9,state == "pressed"))
	for state: String in ["font_color","font_hover_color","font_focus_color","font_pressed_color","font_hover_pressed_color","icon_normal_color","icon_hover_color","icon_pressed_color","icon_hover_pressed_color"]:
		b.add_theme_color_override(state,HospitalUiStyle.INK)
	if primary:
		HospitalUiStyle.primary(b)
		b.add_theme_color_override("icon_pressed_color",Color.WHITE)
	if danger:
		for state: String in ["normal","hover","pressed"]:
			var color := Color("f0e4dc") if state == "normal" else Color("ead4c6") if state == "hover" else Color("a64b3b")
			b.add_theme_stylebox_override(state,_menu_style(color,9,state == "pressed"))
		b.add_theme_color_override("font_color",Color("773c30"))
		b.add_theme_color_override("font_hover_color",Color("773c30"))
		b.add_theme_color_override("font_pressed_color",Color.WHITE)
		b.add_theme_color_override("font_hover_pressed_color",Color.WHITE)
	b.pressed.connect(func() -> void: action_requested.emit(action))
	return b

func _copy(copy: String) -> void:
	_text(body,copy,16,HospitalUiStyle.MUTED,400)

func _icon_card(parent: Node, icon_name: String, edge: int, fill: Color, ink: Color) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(edge,edge)
	card.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var style := _menu_style(fill,5)
	card.add_theme_stylebox_override("panel",style)
	parent.add_child(card)
	var picture := HospitalUiStyle.icon_picture(icon_name,26)
	picture.modulate = ink
	card.add_child(picture)
	return card

func _badge(parent: Node, copy: String, amber: bool=false) -> Label:
	var label := _text(parent,copy,12,Color("725025") if amber else HospitalUiStyle.TEAL,650)
	# A badge owns its natural width; wrapping would make it a one-glyph column.
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var style := _menu_style(Color("eee2c3") if amber else HospitalUiStyle.SOFT,3,true).duplicate() as StyleBoxTexture
	style.content_margin_left = 6
	style.content_margin_right = 6
	label.add_theme_stylebox_override("normal",style)
	return label

func _stat(parent: Node, title: String, value: String, icon_name: String) -> void:
	var card := PanelContainer.new()
	card.set_meta("hospital_stat",title)
	card.set_meta("hospital_stat_value",value)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := _menu_style(MENU_INSET,9,true)
	card.add_theme_stylebox_override("panel",style)
	_stat_cards.append(card)
	parent.add_child(card)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation",1)
	card.add_child(stack)
	var label_row := HBoxContainer.new()
	stack.add_child(label_row)
	var symbol := HospitalUiStyle.icon_picture(icon_name,15)
	symbol.modulate = HospitalUiStyle.TEAL
	label_row.add_child(symbol)
	_text(label_row,title,12,HospitalUiStyle.MUTED)
	var figure := _text(stack,value,23,HospitalUiStyle.INK,750)
	figure.autowrap_mode = TextServer.AUTOWRAP_OFF
	figure.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS

func _hospital_stats(parent: Node, snapshot: Dictionary) -> void:
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation",8)
	parent.add_child(stats)
	_stat(stats,"可用资金",_amount(int(snapshot.get("cash",0))),"coin")
	_stat(stats,"治愈人数",str(snapshot.get("metrics",{}).get("completed",0)),"check")
	_stat(stats,"在职员工",str(snapshot.get("staff",{}).size()),"people")

func _amount(value: int) -> String:
	var raw := str(absi(value))
	var formatted := ""
	for i: int in range(raw.length()):
		if i > 0 and (raw.length()-i)%3 == 0: formatted += ","
		formatted += raw[i]
	return ("−" if value < 0 else "")+formatted

func _clock(tick: int) -> String:
	var seconds := int(tick/10.0)
	return "%02d:%02d" % [int(seconds/60.0),seconds%60]

func show_launch() -> void:
	_open("launch")
	var snapshot: Dictionary = session.sim.snapshot()
	_header = VBoxContainer.new()
	_header.add_theme_constant_override("separation",5)
	_column.add_child(_header)
	_column.move_child(_header,0)
	var clip := ColorRect.new()
	clip.color = HospitalA2Skin.GOLD
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.custom_minimum_size = Vector2(72,5)
	clip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_header.add_child(clip)
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation",12)
	_header.add_child(title_row)
	var crest := HospitalUiStyle.picture(load("res://assets/branding/app-icon-v1.png") as Texture2D,Vector2(44,44),0)
	crest.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	title_row.add_child(crest)
	var title_stack := VBoxContainer.new()
	title_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_stack.add_theme_constant_override("separation",1)
	title_row.add_child(title_stack)
	_text(title_stack,"院长值班档案",12,Color("dae7d5"),500)
	var identity := _text(title_stack,"日常秩序医院",28,HospitalA2Skin.PAPER,750)
	identity.set_meta("compact_font",28)
	identity.autowrap_mode = TextServer.AUTOWRAP_OFF
	identity.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_a2_launch_grid = GridContainer.new()
	_a2_launch_grid.columns = 2
	_a2_launch_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_a2_launch_grid.add_theme_constant_override("h_separation",12)
	_a2_launch_grid.add_theme_constant_override("v_separation",8)
	body.add_child(_a2_launch_grid)
	var record := PanelContainer.new()
	record.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	record.add_theme_stylebox_override("panel",HospitalA2Skin.style("paper",10))
	_a2_launch_grid.add_child(record)
	var record_body := VBoxContainer.new()
	record_body.add_theme_constant_override("separation",6)
	record.add_child(record_body)
	_text(record_body,"经营记录",12,HospitalA2Skin.MUTED)
	var current := HBoxContainer.new()
	current.add_theme_constant_override("separation",7)
	record_body.add_child(current)
	var hospital := _text(current,level_name(session.level_data()),21,HospitalA2Skin.INK,700)
	hospital.set_meta("compact_font",21)
	hospital.autowrap_mode = TextServer.AUTOWRAP_OFF
	hospital.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var paused := HospitalUiStyle.text("Ⅱ 已暂停" if snapshot.get("paused",true) else "● 营业中",12,HospitalA2Skin.INK,600)
	paused.add_theme_stylebox_override("normal",HospitalA2Skin.style("paper",4))
	paused.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	current.add_child(paused)
	record_body.add_child(HSeparator.new())
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation",12)
	record_body.add_child(stats)
	_a2_launch_stat(stats,"可用资金 / 币",_amount(int(snapshot.get("cash",0))),"可用资金")
	var completed := int(snapshot.get("metrics",{}).get("completed",0))
	var arrivals := int(snapshot.get("scheduled_arrivals",[]).size())
	_a2_launch_stat(stats,"治愈人数" if session.is_campaign() else "已完成 / 预约总量",str(completed) if session.is_campaign() else "%d / %d" % [completed,arrivals],"治愈人数",str(completed))
	_a2_launch_stat(stats,"在职员工",str(snapshot.get("staff",{}).size()),"在职员工")
	record_body.add_child(HSeparator.new())
	var status := "进度 / 本机医院档案"
	if session.is_long_campaign():
		status = "阶段凭证 %d/4" % snapshot.get("campaign",{}).get("phase_receipts",[]).size()
	elif session.is_campaign():
		status = "病例 %d/%d" % [snapshot.get("campaign",{}).get("completed_cases",[]).size(),session.level_data().get("case_ids",[]).size()]
	else:
		status = "最低治愈门槛  %d / %d" % [completed,goal_rules(session.level_data()).get("completed_min",0)]
	var progress := HBoxContainer.new()
	record_body.add_child(progress)
	_text(progress,"通关目标",14,HospitalA2Skin.INK,600)
	var progress_label := _text(progress,status,14,HospitalA2Skin.CORAL,700)
	progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	progress_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	progress_label.custom_minimum_size.y = 22
	progress_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var time_row := HBoxContainer.new()
	record_body.add_child(time_row)
	_text(time_row,"营业时钟 "+_clock(int(snapshot.get("tick",0))),12,HospitalA2Skin.INK,600)
	var stored := _text(time_row,"进度保存在本机",12,HospitalA2Skin.MUTED)
	stored.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var resume := _button(record_body,"continue_game","继续经营","continue",true)
	HospitalA2Skin.button(resume,"primary",20,"play")
	resume.custom_minimum_size.y = 52
	resume.set_meta("minimum_size",Vector2(48,52))
	resume.tooltip_text = "回到当前医院，保持现有营业状态。"
	_a2_launch_tools = GridContainer.new()
	_a2_launch_tools.columns = 1
	_a2_launch_tools.add_theme_constant_override("h_separation",8)
	_a2_launch_tools.add_theme_constant_override("v_separation",8)
	_a2_launch_tools.custom_minimum_size.x = 146
	_a2_launch_grid.add_child(_a2_launch_tools)
	if not session.long_campaign_levels().is_empty():
		HospitalA2Skin.button(_button(_a2_launch_tools,"start_long","深度经营","choose_level"),"paper",15,"chart")
	HospitalA2Skin.button(_button(_a2_launch_tools,"choose_level","选择医院","choose_level"),"paper",15,"crest")
	HospitalA2Skin.button(_button(_a2_launch_tools,"launch_help","设置与帮助","help"),"paper",15,"settings")
	HospitalA2Skin.button(_button(_a2_launch_tools,"start_new","开始新局","new",false,true),"danger",15,"alert")
	footer.hide()
	configure(_safe)

func _a2_launch_stat(parent: Node, title: String, value: String, metadata_title: String, metadata_value: String="") -> void:
	var card := PanelContainer.new()
	card.set_meta("hospital_stat",metadata_title)
	card.set_meta("hospital_stat_value",value if metadata_value == "" else metadata_value)
	card.tooltip_text = title+"："+value
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel",StyleBoxEmpty.new())
	parent.add_child(card)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation",1)
	card.add_child(stack)
	_text(stack,title,12,HospitalA2Skin.INK)
	var figure := _text(stack,value,24,HospitalA2Skin.INK,750)
	figure.set_meta("compact_font",24)
	figure.autowrap_mode = TextServer.AUTOWRAP_OFF
	figure.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS

func _configure_a2_launch() -> void:
	var width := minf(720 if _safe.size.x > 1100 else 640,_safe.size.x-20)
	var height := minf(420 if _safe.size.y >= 600 else 380,_safe.size.y-20)
	panel.add_theme_stylebox_override("panel",HospitalA2Skin.style("enamel",12))
	panel.size = Vector2(width,height)
	panel.position = _safe.position+Vector2(minf(64.0,maxf(0.0,(_safe.size.x-width)*0.5)),maxf(0.0,(_safe.size.y-height)*0.5))
	_column.add_theme_constant_override("separation",8)
	body.add_theme_constant_override("separation",0)
	_scroll.custom_minimum_size.y = 0
	if is_instance_valid(_a2_launch_grid): _a2_launch_grid.columns = 1 if width < 570 else 2
	if is_instance_valid(_a2_launch_tools):
		_a2_launch_tools.columns = 2 if width < 570 else 1
		_a2_launch_tools.custom_minimum_size.x = 0 if width < 570 else 146

func show_levels() -> void:
	_open("levels","选择医院")
	_copy("选择医院后确认开局；确认前保留当前经营进度。")
	var ids: Array[String] = []
	for level: Dictionary in session.long_campaign_levels(): ids.append(str(level.id))
	for id: String in ["level_01","clinical_02"]:
		if session.catalog.levels.has(id): ids.append(id)
	for level: Dictionary in session.campaign_levels(): ids.append(str(level.id))
	var track_counts: Dictionary = {}
	for id: String in ids:
		var track := str(session.level_data(id).get("ruleset","legacy"))
		track_counts[track] = int(track_counts.get(track,0))+1
	var previous_track := ""
	var grid: GridContainer
	var index := 0
	var snapshot: Dictionary = session.sim.snapshot()
	for id: String in ids:
		var level: Dictionary = session.level_data(id)
		var track := str(level.get("ruleset","legacy"))
		if track != previous_track:
			var track_row := HBoxContainer.new()
			track_row.add_theme_constant_override("separation",6)
			body.add_child(track_row)
			_text(track_row,str({"full-hospital-v2":"深度经营 / 四阶段","full-hospital-v1":"经典职业 / 病例任务"}.get(track,"教学与联合诊疗")),17,HospitalUiStyle.INK,700)
			_badge(track_row,"%d 家医院" % int(track_counts[track]))
			_level_table_heading(body)
			grid = GridContainer.new()
			grid.columns = 1
			grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			grid.add_theme_constant_override("h_separation",0)
			grid.add_theme_constant_override("v_separation",3)
			body.add_child(grid)
			_level_grids.append(grid)
			previous_track = track
			index = 0
		index += 1
		_level_card(grid,level,index,snapshot)
	_button(footer,"levels_back","返回主菜单","menu").icon = HospitalUiStyle.icon("back")

func _level_table_heading(parent: Node) -> void:
	var strip := PanelContainer.new()
	strip.add_theme_stylebox_override("panel",_menu_style(HospitalUiStyle.SOFT,6,true))
	parent.add_child(strip)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",8)
	strip.add_child(row)
	for column: Array in [["编号",40],["医院档案",0],["开放状态",84],["操作",66]]:
		var label := _text(row,str(column[0]),13,HospitalUiStyle.MUTED,600)
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		if int(column[1]) > 0:
			label.custom_minimum_size.x = int(column[1])
			label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN

func _completed_level(snapshot: Dictionary, id: String, track: String) -> bool:
	var career: Dictionary = snapshot.get("career_tracks",{}).get(track,{})
	var active_track := str(session.level_data().get("ruleset","legacy"))
	if track == active_track:
		career = snapshot.get("campaign",{}).get("career",snapshot.get("campaign_career",career))
	return id in career.get("completed_levels",[]) and career.get("receipts",{}).has(id)

func _level_card(parent: Node, level: Dictionary, number: int, snapshot: Dictionary) -> void:
	var id := str(level.id)
	var track := str(level.get("ruleset","legacy"))
	var access: Dictionary = session.level_access(id)
	var available := bool(access.get("ok",false))
	var current := id == str(snapshot.level_id)
	var completed := available and _completed_level(snapshot,id,track)
	var card := _button(parent,"level_"+id,"","select_level:"+id)
	card.custom_minimum_size = Vector2(48,48)
	card.set_meta("minimum_size",Vector2(48,48))
	card.disabled = not available
	card.tooltip_text = goal_summary(level)+("\n开放条件：完成"+str(access.get("data",{}).get("required_name","上一职业关卡")) if not available else "")
	for state: String in ["normal","hover","pressed","disabled"]:
		var fill := MENU_INSET if state == "normal" else HospitalUiStyle.SOFT if state == "hover" else Color("c0d8d4") if state == "pressed" else Color("dce4df")
		if current and state != "disabled": fill = Color("c9e2dd")
		card.add_theme_stylebox_override(state,_menu_style(fill,0,state == "pressed" or current))
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left","right"]: margin.add_theme_constant_override("margin_"+side,8)
	for side: String in ["top","bottom"]: margin.add_theme_constant_override("margin_"+side,4)
	card.add_child(margin)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation",8)
	margin.add_child(top)
	var ordinal := _text(top,"%02d"%number,17,HospitalUiStyle.TEAL if available else HospitalUiStyle.MUTED,700)
	ordinal.autowrap_mode = TextServer.AUTOWRAP_OFF
	ordinal.custom_minimum_size.x = 40
	ordinal.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	# The ordinal has its own column; the authoritative level name stays intact.
	var display_name := level_name(level).trim_prefix("%02d · " % number)
	var name := _text(top,display_name,16,HospitalUiStyle.INK if available else HospitalUiStyle.MUTED,650)
	name.autowrap_mode = TextServer.AUTOWRAP_OFF
	name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var state_label := _text(top,"当前医院" if current else "已通关" if completed else "可经营" if available else "未解锁",13,HospitalUiStyle.INK if available else HospitalUiStyle.MUTED,600)
	state_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	state_label.custom_minimum_size.x = 84
	state_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var command := _text(top,"选择 >" if available else "锁定",14,HospitalUiStyle.TEAL if available else HospitalUiStyle.MUTED,700)
	command.autowrap_mode = TextServer.AUTOWRAP_OFF
	command.custom_minimum_size.x = 66
	command.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_ignore_pointer(margin)

func _ignore_pointer(node: Node) -> void:
	if node is Control: node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child: Node in node.get_children(): _ignore_pointer(child)

func show_guide() -> void:
	if session.is_campaign():
		show_campaign_guide()
		return
	var level: Dictionary=session.level_data()
	var care: bool=level.id=="clinical_02"
	_open("guide","开业操作单")
	_text(body,level_name(level),21,HospitalUiStyle.INK,700)
	_text(body,"联合诊疗 / 六类病情" if care else "基础诊疗 / 接待与设备",15,HospitalUiStyle.MUTED)
	_text(body,goal_summary(level),16,HospitalUiStyle.MUTED)
	_step(1,"接待与医生诊断","建议配置两位门诊医生，并为综合检查另配一位医生。" if care else "患者先登记，再由医生确定病症。")
	_step(2,"安排检查、发药和留观" if care else "准备治疗与恢复席位","药房与双床留观病房分别需要护士。病房护理与刺激恢复区各司其职。" if care else "先用声环设备完成第一类诊疗。")
	_step(3,"保留设备治疗与恢复" if care else "招聘并派到岗位","三种设备仍由技术员负责；按患者路线配置岗位，已承诺的护理完成后才能调岗。" if care else "接待员、医生与技术员各司其职。")
	HospitalUiStyle.summary(body,"营业前可以暂停准备","开始后依然可以随时暂停，先想清楚再调整。")
	_button(footer,"guide_build","去建设","guide_build",true)

func _step(number: int, title: String, copy: String) -> void:
	var row:=HBoxContainer.new()
	row.add_theme_constant_override("separation",8)
	body.add_child(row)
	var badge:=_text(row,str(number),18,Color.WHITE,700)
	badge.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
	badge.custom_minimum_size=Vector2(28,28)
	badge.autowrap_mode=TextServer.AUTOWRAP_OFF
	badge.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	badge.add_theme_stylebox_override("normal",_menu_style(HospitalUiStyle.TEAL,3,true))
	var copy_column:=VBoxContainer.new()
	copy_column.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	row.add_child(copy_column)
	_text(copy_column,title,18,HospitalUiStyle.INK,700)
	_text(copy_column,copy,16,HospitalUiStyle.MUTED)
	body.add_child(HSeparator.new())

func show_pause() -> void:
	_open("pause","医院菜单")
	var snapshot: Dictionary = session.sim.snapshot()
	var state_row := HBoxContainer.new()
	body.add_child(state_row)
	var hospital := _text(state_row,level_name(session.level_data()),18,HospitalUiStyle.INK,700)
	hospital.autowrap_mode = TextServer.AUTOWRAP_OFF
	hospital.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_badge(state_row,"时间已停止" if snapshot.get("paused",true) else "营业中")
	_hospital_stats(body,snapshot)
	_text(body,"经营时钟  "+_clock(int(snapshot.get("tick",0)))+"  /  本机医院档案",13,HospitalUiStyle.MUTED)
	var actions := GridContainer.new()
	actions.columns = 2
	actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_theme_constant_override("h_separation",6)
	actions.add_theme_constant_override("v_separation",6)
	body.add_child(actions)
	var save_button := _button(actions,"save_progress","保存进度","save")
	save_button.icon = HospitalUiStyle.icon("save")
	save_button.disabled = session.storage_blocked
	_button(actions,"pause_help","设置与帮助","help").icon = HospitalUiStyle.icon("settings")
	_button(actions,"main_menu","返回主菜单","menu").icon = HospitalUiStyle.icon("home")
	var restart := _button(actions,"restart_game","重新开局","restart",false,true)
	restart.disabled = session.storage_blocked
	restart.tooltip_text = "重新开始会替换当前医院；点击后需要再次确认。"
	if session.is_long_campaign() and snapshot.campaign.get("course_complete",false) and not snapshot.campaign.get("continuing",false):
		_button(actions,"continue_hospital","继续本院经营","continue_hospital").disabled = session.storage_blocked
	var resume := _button(footer,"resume_game","继续营业","resume",true)
	resume.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	resume.icon = HospitalUiStyle.icon("play")
	resume.disabled = session.storage_blocked or snapshot.challenge.status != "running"

func show_save(result: Dictionary) -> void:
	_open("saved" if result.ok else "save_failed","进度已保存" if result.ok else "进度未能保存")
	_badge(body,"本机存档 · 写入完成" if result.ok else "本机存档 · 写入失败",not result.ok)
	_text(body,level_name(session.level_data()),20,HospitalUiStyle.INK,700)
	_hospital_stats(body,session.sim.snapshot())
	HospitalUiStyle.summary(body,"已保存至当前设备" if result.ok else "请先保留当前游戏", "重新进入医院时保持暂停，确认安排后继续营业。" if result.ok else "本次未成功写入。检查设备存储空间与权限后重试，成功前请保持游戏开启。",not result.ok)
	_button(footer,"back_hospital","回到医院","hospital",bool(result.ok))
	if not result.ok: _button(footer,"retry_save","重试保存","save",true)

func show_storage() -> void:
	_open("storage","存档暂时无法读取")
	_copy("主存档和备份都无法读取。原文件仍保留，当前不会自动覆盖。")
	HospitalUiStyle.summary(body,"保留原档，再开始新局","先保留原始文件，再建立新存档。若保留失败，继续阻止覆盖并提示重试。",true)
	_copy(session.notice)
	_button(footer,"storage_back","返回","pause")
	_button(footer,"recover_game","保留原档并开新局","recover",true)

func show_unlock(kind: String) -> void:
	_unlock_kind=kind
	_open("unlock","新设施已解锁")
	var row:=HBoxContainer.new()
	row.add_theme_constant_override("separation",14)
	body.add_child(row)
	row.add_child(HospitalUiStyle.picture(HospitalUiStyle.thumbnail(kind),Vector2(64,54),0))
	var names:=VBoxContainer.new()
	names.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	row.add_child(names)
	_text(names,session.catalog.rooms[kind].name,25,HospitalUiStyle.INK,700)
	names.add_child(HospitalUiStyle.tag("%d 秒解锁" % (240 if kind=="motion" else 480)))
	_copy("%s患者开始到院。建好%s，并安排一名技术员。" % ["动作循环症" if kind=="motion" else "感官串台症",session.catalog.rooms[kind].name])
	_info(body,"建造费用","%s 币" % session.catalog.rooms[kind].cost)
	_info(body,"所需岗位","技术员")
	_button(footer,"unlock_later","稍后处理","unlock_later")
	_button(footer,"unlock_build","前往建设","unlock_build:"+kind,true)

func show_restart(level_id: String="") -> void:
	var level: Dictionary=session.level_data(level_id)
	_open("restart","开始"+level_name(level)+"？")
	_copy("确认后将开始%s，回到 %d 币、暂停营业、尚未建造的起点。当前医院会被新局替换。" % [level_name(level),level.initial_cash])
	HospitalUiStyle.summary(body,"先保存当前进度","如果希望保留这次经营结果，可以返回后手动保存。")
	_button(footer,"cancel_restart","取消","cancel_restart")
	_button(footer,"confirm_restart","确认重新开局","confirm_restart",false,true)

func _info(parent: Node, label: String, value: String, color: Color=HospitalUiStyle.INK) -> void:
	var column:=VBoxContainer.new()
	column.add_theme_constant_override("separation",4)
	parent.add_child(column)
	var row:=HBoxContainer.new()
	column.add_child(row)
	_text(row,label,17)
	var number:=_text(row,value,17,color,650)
	number.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	column.add_child(HSeparator.new())

func show_result(snapshot: Dictionary) -> void:
	if snapshot.get("schema_version",1) in [2,3]:
		show_campaign_result(snapshot)
		return
	var state:=ClinicState.new()
	state.data=snapshot.duplicate(true)
	result_summary=Metrics.summary(state)
	var m:=result_summary
	var won: bool=snapshot.challenge.status=="won"
	_open("result","经营结算 · "+level_name(session.level_data(str(snapshot.level_id))))
	_badge(body,"本局达标 / 患者结算" if won else "本局未达标 / 患者结算",not won)
	var dispositions:=HBoxContainer.new()
	dispositions.add_theme_constant_override("separation",7)
	body.add_child(dispositions)
	var keys:=["not_arrived","outside","in_hospital","completed","abandoned"]
	var names:=["未到院","院外等待","在院未完成","完成离院","弃诊离院"]
	for i in range(5):
		var card:=PanelContainer.new()
		card.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		card.add_theme_stylebox_override("panel",_menu_style(MENU_INSET,7,true))
		dispositions.add_child(card)
		var stack:=VBoxContainer.new()
		card.add_child(stack)
		var caption := _text(stack,names[i],13)
		caption.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		caption.autowrap_mode=TextServer.AUTOWRAP_OFF
		_text(stack,str(m.dispositions[keys[i]]),23,HospitalUiStyle.INK,750).horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	_text(body,"五类互斥合计 %d 人。弃诊后尚未离院者属于在院未完成，不重复计数。" % snapshot.scheduled_arrivals.size(),14,HospitalUiStyle.MUTED)
	var columns:=HBoxContainer.new()
	columns.add_theme_constant_override("separation",14)
	body.add_child(columns)
	var business:=VBoxContainer.new()
	business.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	columns.add_child(business)
	var waits:=VBoxContainer.new()
	waits.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	columns.add_child(waits)
	_text(business,"经营收支",18,HospitalUiStyle.INK,700)
	_info(business,"离院收入","%d 币" % m.income)
	_info(business,"诊疗 / 恢复耗材" if snapshot.level_id=="clinical_02" else "治疗 / 恢复耗材","%d / %d" % [m.treatment_cost,m.recovery_cost])
	if snapshot.level_id=="clinical_02": _text(business,"诊疗耗材包含治疗、发药与留观，恢复耗材单列。",13,HospitalUiStyle.MUTED)
	_info(business,"工资 / 固定支出","%d / %d" % [m.wages,m.fixed_cost])
	_info(business,"经营利润","%+d 币" % m.operating_profit,Color("3f8164") if m.operating_profit>=0 else Color("ab5145"))
	_info(business,"最终现金","%d 币" % m.cash)
	var capital:=0
	var refund:=0
	for entry in snapshot.ledger_entries:
		if entry.category in ["capital_build","capital_hire","capital_upgrade"]: capital-=int(entry.delta)
		if entry.category=="capital_refund": refund+=int(entry.delta)
	_text(business,"资本投入 %d 币、退款 %d，单独核算。" % [capital,refund],13,HospitalUiStyle.MUTED)
	_text(waits,"各阶段累计等待",18,HospitalUiStyle.INK,700)
	for stage in SelectionPanel.stage_rows(snapshot.level_id=="clinical_02"):
		_info(waits,stage[1],"%.1f 秒" % (m.wait_by_stage.get(stage[0],0)/10.0))
	var reason: String=snapshot.challenge.reason
	var level: Dictionary=session.level_data(str(snapshot.level_id))
	var missed:=missing_goals(snapshot,level)
	_text(body,level_name(level)+"目标已全部达到。" if missed.is_empty() else "未达目标："+"；".join(missed)+"。",15,HospitalUiStyle.INK)
	_text(body,"已完成患者满足离院结算条件。" if won else "现金连续为负满 %d 秒，经营失败。" % (level.negative_cash_limit_ticks/10) if reason=="bankruptcy" else "本局未达到本关目标；未完成患者保留在终止时的阶段。",15,HospitalUiStyle.MUTED)
	_button(footer,"back_hospital","回到医院","hospital")
	_button(footer,"restart_game","重新开局","restart",true)

static func level_name(level: Dictionary) -> String:
	return str(level.get("name","首关 · 诊疗节奏" if level.get("id","")=="level_01" else "经营关卡"))

static func goal_rules(level: Dictionary) -> Dictionary:
	return level.get("goal",{"completed_min":30,"abandoned_max":6,"operating_profit_min":0,"cash_min":0,"require_all_departed":false}).duplicate(true)

static func goal_summary(level: Dictionary) -> String:
	if level.get("ruleset","")=="full-hospital-v2":return "%s：开业、稳定经营、扩建专科、综合考核四阶段；经营目标以当前阶段进度为准，通过后仍可继续经营当前医院。"%level_name(level)
	if level.get("ruleset","")=="full-hospital-v1": return "%s：完成%d个病例任务、规定后勤工序、审核与事件；从准备到实际离院全程结算。"%[level_name(level),level.get("case_ids",[]).size()]
	var goal:=goal_rules(level)
	var count: int=level.get("arrivals",[]).size()
	var copy := "%s目标：%d名预约患者，治愈至少%d人" % [level_name(level),count,goal.get("completed_min",0)]
	if goal.has("abandoned_max"): copy+="，弃诊不超过%d人" % goal.abandoned_max
	if goal.has("operating_profit_min") and goal.get("cash_min",-1)==0 and goal.operating_profit_min==0:
		copy+="；经营利润和现金都不能为负。"
	else:
		if goal.has("operating_profit_min"): copy+="；经营利润至少%d币" % goal.operating_profit_min
		if goal.has("cash_min"): copy+="；现金不能为负。" if goal.cash_min==0 else "；现金至少%d币。" % goal.cash_min
	if goal.get("require_all_departed",false): copy+="全部%d人须完成或放弃后实际离院，%d分钟内达到目标。" % [count,level.end_tick/600]
	else: copy+="全部患者离院或%d分钟结束时结算。" % (level.end_tick/600)
	return copy

static func missing_goals(snapshot: Dictionary, level: Dictionary) -> Array[String]:
	var goal:=goal_rules(level)
	var m: Dictionary=snapshot.metrics
	var missed: Array[String]=[]
	if m.completed<goal.get("completed_min",0): missed.append("治愈%d/%d人" % [m.completed,goal.completed_min])
	if goal.has("abandoned_max") and m.abandoned>goal.abandoned_max: missed.append("弃诊%d人，须不超过%d人" % [m.abandoned,goal.abandoned_max])
	if goal.has("operating_profit_min") and m.operating_profit<goal.operating_profit_min: missed.append("经营利润%d币，须至少%d币" % [m.operating_profit,goal.operating_profit_min])
	if goal.has("cash_min") and snapshot.cash<goal.cash_min: missed.append("现金%d币，须至少%d币" % [snapshot.cash,goal.cash_min])
	var count: int=snapshot.scheduled_arrivals.size()
	if goal.get("require_all_departed",false) and m.completed+m.abandoned<count: missed.append("实际离院%d/%d人" % [m.completed+m.abandoned,count])
	return missed

func show_campaign_guide() -> void:
	if session.is_long_campaign():
		show_long_campaign_guide()
		return
	var level:Dictionary=session.level_data()
	_open("guide",level_name(level))
	_text(body,"按病例逐批准备，完整运营科室",25,HospitalUiStyle.INK,700)
	_copy(str(level.get("description","")))
	_step(1,"先看病例缺项","病例页显示当前任务的设备、人员、技能和资源要求。准备齐全后主动接收本批患者，尚未准备时不会自动塞入患者。")
	_step(2,"自己建设与派工","从32专科和公共运营设施中筛选；房间大小、设备四向与多个门窗可以编辑。招聘员工后派到匹配设施。")
	_step(3,"让后勤与成长真正工作","工单、研究和培训需要设施、人员、物资和营业时间；审核列出实际缺项，事件处理完成后复核。完成本关后正常点击进入下一关。")
	_copy("开始营业、暂停、倍速与保存在控制台。收费、借款和实际账本在经营页。")
	_button(footer,"guide_build","查看当前病例","guide_build",true)

func show_campaign_result(snapshot:Dictionary) -> void:
	if session.is_long_campaign():
		show_long_campaign_result(snapshot)
		return
	var won:bool=snapshot.challenge.status=="won"
	_open("result",("本关达标 · " if won else "本关未达标 · ")+level_name(session.level_data()))
	var campaign:Dictionary=snapshot.campaign
	_copy("病例任务 %d/%d · 实际完成离院 %d人 · 现金 %d币"%[campaign.get("completed_cases",[]).size(),session.level_data().case_ids.size(),snapshot.metrics.get("completed",0),snapshot.cash])
	_copy("累计收入 %d币 · 经营盈余 %d币 · 贷款余额 %d币"%[snapshot.metrics.get("income",0),snapshot.metrics.get("operating_profit",0),campaign.get("loan",0)])
	_copy("本关补助和病例收入均已按真实账本计入；通关不会额外重复发奖。职业记录与当前医院一起保存。")
	_text(body,"本关审核",18,HospitalUiStyle.INK,700)
	for id:String in session.level_data().get("audit_ids",[]):
		_copy(str(session.catalog.campaign.audits.get(id,{}).get("name",id))+" · "+("已通过" if campaign.get("audits",{}).get(id,{}).get("passed",false) else "未通过"))
	_text(body,"完成病例任务",18,HospitalUiStyle.INK,700)
	for id:String in campaign.get("completed_cases",[]):_copy(str(session.catalog.campaign.cases.get(id,{}).get("title",id)))
	if won:
		var next:Dictionary=session.next_level_info()
		if next.ok:_button(footer,"next_level","继续下一关","next_level",true)
		elif next.code=="career_complete":_copy("十二关职业任务已全部完成。可以重开已通关关卡，原职业解锁保留。")
		else:_copy("职业记录尚未通过检查，当前医院已保留；请先保存并查看提示。")
	else:_copy("本关未完成目标，可以查看当前医院的真实状态后重试；失败不会解锁下一关。")
	_button(footer,"back_hospital","回到医院","hospital")
	_button(footer,"restart_game","重试本关","restart",not won)

func show_long_campaign_guide() -> void:
	_open("guide",level_name(session.level_data()))
	_text(body,"让同一座医院逐步成长",25,HospitalUiStyle.INK,700)
	_step(1,"开业","准备接待、诊疗和供给，先接收签名病例。真实完成的病例会进入常规客流，自动接诊由你开启或关闭。")
	_step(2,"稳定经营","让已掌握的病例持续就诊，关注新增治愈、现金与连续达标经营日；每天的利润、治愈人数和当日治愈率须同时达标。近期质量按最近30分钟有效结案统计，全程记录另行保留。")
	_step(3,"扩建专科","满足目标后手动提交阶段考核，在同一医院开放更多诊疗。研究有独立经营收益，临床研究与匹配专科培训可叠加；考核只计仍在匹配临床岗位的受训员工及不同专科覆盖。自动补给、维护和卫生工单都需要真实设施、人员和时间。")
	_step(4,"综合考核","完成临床、盈利、声誉、运营与审核目标，关闭常规接诊并等待在院患者实际离院，再申请最终考核。通过后可保留本院继续经营，或确认进入下一关。")
	_copy("每个经营日为10分钟1×经营时钟，可用2×营业；暂停不推进。四阶段达标日目标按实际经营记录计数，新旧职业记录分开保存，旧关卡不自动升级。")
	_button(footer,"guide_build","查看开业目标","guide_build",true)

func show_long_campaign_result(snapshot:Dictionary) -> void:
	var passed:bool=bool(snapshot.campaign.get("course_complete",false))
	var continuing:bool=bool(snapshot.campaign.get("continuing",false))
	_open("result",("综合考核已通过 · " if passed else "经营未达标 · ")+level_name(session.level_data()))
	_copy("当前累计治愈 %d人 · 现金 %d币 · 经营盈余 %d币"%[snapshot.metrics.get("completed",0),snapshot.cash,snapshot.metrics.get("operating_profit",0)])
	_copy("四阶段凭证 %d/4 · 签名病例 %d/8 · 贷款余额 %d币"%[snapshot.campaign.get("phase_receipts",[]).size(),snapshot.campaign.get("completed_cases",[]).size(),snapshot.campaign.get("loan",0)])
	if passed:
		_copy("考核资格会随当前医院一起存档；继续营业保留科室、员工、患者、库存与账本，不重复发放阶段奖励。")
		if not continuing:_button(footer,"continue_hospital","继续本院经营","continue_hospital",true)
		else:_copy("本院正在继续经营。可回到医院接诊，或在确认后进入下一关。")
		var next:Dictionary=session.next_level_info()
		if next.get("ok",false):_button(footer,"next_level","下一关","next_level",continuing)
		elif next.get("code","")=="career_complete":_copy("长线十二关已全部通过，当前医院仍可继续经营。")
		else:_copy("下一关资格尚未通过检查，请保存并查看职业记录提示。")
	else:_copy("当前医院保留真实终止状态；失败不解锁下一关。可查看经营问题后重新开局。")
	_button(footer,"back_hospital","回到医院","hospital")
	_button(footer,"restart_game","重试本关","restart",not passed)
