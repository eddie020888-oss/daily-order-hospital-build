class_name BuildPalette
extends VBoxContainer

signal build_requested(kind: String)
signal command_requested(type: String, payload: Dictionary)
var controls: Dictionary={}
var catalog: ContentCatalog
var selected_kind: String=""
var page: int=0
const PAGE_SIZE: int=3
var _facilities: VBoxContainer
var _recruitment: VBoxContainer
var _recruit_portraits: Dictionary={}
var _facility_ids: Array[String]=[]
var _facility_grid: GridContainer
var _page_label: Label
var _budget_label: Label
var _selection_name: Label
var _selection_copy: Label
var _start_button: Button
var _directory_help: Label
var _short_landscape:=false
var _snapshot: Dictionary={}

static func button(copy: String) -> Button:
	var result:=Button.new()
	result.text=copy
	result.custom_minimum_size=Vector2(48,48)
	result.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	result.add_theme_font_size_override("font_size",18)
	result.clip_text=true
	return result

func initialize(content: ContentCatalog) -> void:
	catalog=content
	add_theme_constant_override("separation",6)
	_facilities=VBoxContainer.new()
	_facilities.add_theme_constant_override("separation",6)
	add_child(_facilities)
	var pages:=HBoxContainer.new()
	pages.add_theme_constant_override("separation",6)
	_facilities.add_child(pages)
	_budget_label=HospitalUiStyle.text("设施档案",16,HospitalUiStyle.INK,700)
	_budget_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_budget_label.clip_text=true
	_budget_label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	pages.add_child(_budget_label)
	var previous:=button("")
	HospitalA2Skin.button(previous,"paper",16,"back")
	previous.set_meta("fixed_width",true)
	previous.size_flags_horizontal=Control.SIZE_SHRINK_END
	previous.tooltip_text="上一页设施"
	pages.add_child(previous)
	controls.facility_previous=previous
	previous.pressed.connect(func() -> void: _set_page(page-1))
	_page_label=HospitalUiStyle.text("",14,HospitalUiStyle.MUTED,600)
	_page_label.custom_minimum_size.x=38
	_page_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	_page_label.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	pages.add_child(_page_label)
	var next:=button("")
	HospitalA2Skin.button(next,"paper",16,"next")
	next.set_meta("fixed_width",true)
	next.size_flags_horizontal=Control.SIZE_SHRINK_END
	next.tooltip_text="下一页设施"
	pages.add_child(next)
	controls.facility_next=next
	next.pressed.connect(func() -> void: _set_page(page+1))
	_facility_grid=GridContainer.new()
	_facility_grid.columns=3
	_facility_grid.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_facility_grid.add_theme_constant_override("h_separation",7)
	_facility_grid.add_theme_constant_override("v_separation",7)
	_facilities.add_child(_facility_grid)
	for kind: String in catalog.rooms:
		_facility_ids.append(kind)
		_create_facility_card(kind)
	var footer:=PanelContainer.new()
	footer.add_theme_stylebox_override("panel",HospitalA2Skin.style("paper",4))
	_facilities.add_child(footer)
	var footer_row:=HBoxContainer.new()
	footer_row.add_theme_constant_override("separation",8)
	footer.add_child(footer_row)
	var selected_copy:=VBoxContainer.new()
	selected_copy.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	selected_copy.add_theme_constant_override("separation",1)
	footer_row.add_child(selected_copy)
	_selection_name=HospitalUiStyle.text("选择设施",17,HospitalUiStyle.INK,700)
	_selection_name.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	selected_copy.add_child(_selection_name)
	_selection_copy=HospitalUiStyle.text("",13,HospitalUiStyle.MUTED)
	_selection_copy.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	selected_copy.add_child(_selection_copy)
	_start_button=button("划定房间")
	HospitalA2Skin.button(_start_button,"primary",16,"next")
	_start_button.set_meta("minimum_size",Vector2(136,48))
	_start_button.custom_minimum_size=Vector2(136,48)
	_start_button.set_meta("fixed_width",true)
	_start_button.size_flags_horizontal=Control.SIZE_SHRINK_END
	_start_button.disabled=true
	footer_row.add_child(_start_button)
	controls.build_start=_start_button
	_start_button.pressed.connect(_request_selected_build)
	_directory_help=HospitalUiStyle.text("设备占格与房间面积分开；先准备接待、诊断、治疗和恢复。",13,HospitalUiStyle.MUTED)
	_directory_help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	_facilities.add_child(_directory_help)
	_create_recruitment()
	resized.connect(_reflow_directory)
	if not _facility_ids.is_empty(): selected_kind=_facility_ids[0]
	show_recruitment(false)
	_reflow_directory.call_deferred()

func _create_facility_card(kind: String) -> void:
	var data: Dictionary=catalog.rooms[kind]
	var profile: Dictionary=EquipmentFootprints.profile(kind)
	var body: Vector2i=profile.body_size
	var minimum: Vector2i=profile.minimum_room
	var recommended: Vector2i=profile.recommended_room
	var card:=button("")
	card.clip_text=false
	card.custom_minimum_size=Vector2(144,232)
	card.set_meta("minimum_size",card.custom_minimum_size)
	HospitalA2Skin.button(card,"paper",16)
	card.tooltip_text="%s · %s\n最小房间 %d×%d，可换向；建议 %d×%d\n基础设施套餐 %d 币；扩建地面与家具另计。\n%s"%[data.name,EquipmentFootprints.body_label(kind),minimum.x,minimum.y,recommended.x,recommended.y,data.cost,profile.reason]
	controls["build_"+kind]=card
	_facility_grid.add_child(card)
	var box:=VBoxContainer.new()
	card.add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left=8;box.offset_right=-8;box.offset_top=7;box.offset_bottom=-7
	box.add_theme_constant_override("separation",2)
	var name_label:=HospitalUiStyle.text(data.name,17,HospitalUiStyle.INK,750)
	name_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	box.add_child(name_label)
	var picture:=HospitalUiStyle.picture(HospitalA2Skin.equipment_texture(kind),Vector2(0,94),0)
	picture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	box.add_child(picture)
	var price:=HospitalUiStyle.text("%d 币"%data.cost,21,Color("ae4935"),750)
	box.add_child(price)
	box.add_child(HospitalUiStyle.text("设备 2床·各2×3" if kind=="ward" else "设备 %d×%d格"%[body.x,body.y],13,HospitalUiStyle.INK))
	box.add_child(HospitalUiStyle.text("最小 %d×%d · 可换向"%[minimum.x,minimum.y],13,HospitalUiStyle.INK))
	var state:=HospitalUiStyle.text("待同步开放状态",13,HospitalUiStyle.MUTED,600)
	state.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	box.add_child(state)
	card.set_meta("price_label",price)
	card.set_meta("state_label",state)
	card.set_meta("name_label",name_label)
	card.set_meta("equipment_picture",picture)
	_ignore_card_input(box)
	card.pressed.connect(func() -> void: select_facility(kind))

func _ignore_card_input(node: Node) -> void:
	if node is Control: node.mouse_filter=Control.MOUSE_FILTER_IGNORE
	for child: Node in node.get_children(): _ignore_card_input(child)

func _create_recruitment() -> void:
	_recruitment=VBoxContainer.new()
	add_child(_recruitment)
	var note:=HospitalUiStyle.text("招聘后，在员工详情中选择对应岗位。",16,HospitalUiStyle.MUTED)
	note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	_recruitment.add_child(note)
	for role in catalog.staff:
		var data: Dictionary=catalog.staff[role]
		var panel:=PanelContainer.new()
		HospitalA2Skin.panel(panel,"paper")
		_recruitment.add_child(panel)
		var col:=VBoxContainer.new()
		panel.add_child(col)
		var row:=HBoxContainer.new()
		col.add_child(row)
		var portrait:=HospitalUiStyle.picture(HospitalUiStyle.portrait(role,0),Vector2(66,66),2)
		_recruit_portraits[role]=portrait
		row.add_child(portrait)
		var info:=VBoxContainer.new()
		row.add_child(info)
		info.add_child(HospitalUiStyle.text(data.name,20))
		info.add_child(HospitalUiStyle.text("招聘 %d · 日薪 %d 币" % [data.hire_cost,data.daily_wage],14,HospitalUiStyle.MUTED))
		var hire:=button("录用"+data.name)
		HospitalA2Skin.button(hire,"primary",17)
		controls["hire_"+role]=hire
		col.add_child(hire)
		hire.pressed.connect(func() -> void: command_requested.emit("hire_staff",{"role":role}))

func select_facility(kind: String) -> void:
	if not catalog.rooms.has(kind): return
	selected_kind=kind
	page=int(_facility_ids.find(kind)/PAGE_SIZE)
	_update_directory()

func _set_page(value: int) -> void:
	var pages:=maxi(1,ceili(_facility_ids.size()/float(PAGE_SIZE)))
	page=clampi(value,0,pages-1)
	if not _facility_ids.is_empty(): selected_kind=_facility_ids[page*PAGE_SIZE]
	_update_directory()
	if get_parent() is ScrollContainer: get_parent().set_deferred("scroll_vertical",0)

func _request_selected_build() -> void:
	if _start_button.disabled or selected_kind=="" or not catalog.rooms.has(selected_kind): return
	if not (selected_kind in _snapshot.get("unlocked_room_kinds",[])): return
	if int(_snapshot.get("cash",0))<int(catalog.rooms[selected_kind].cost): return
	build_requested.emit(selected_kind)

func _unlock_copy(kind: String) -> String:
	if kind in ["general_exam","pharmacy","ward"]: return "联合诊疗关卡开放"
	var level: Dictionary=catalog.levels.get(str(_snapshot.get("level_id","level_01")),{})
	for unlock: Dictionary in level.get("unlocks",[]):
		if str(unlock.get("room_kind",""))==kind: return "%d分解锁"%int(int(unlock.get("tick",0))/600)
	return "尚未开放"

func _update_directory() -> void:
	if not is_instance_valid(_facility_grid): return
	var pages:=maxi(1,ceili(_facility_ids.size()/float(PAGE_SIZE)))
	page=clampi(page,0,pages-1)
	_page_label.text="%d/%d"%[page+1,pages]
	_budget_label.text="可用资金  "+HospitalHud.grouped_number(int(_snapshot.get("cash",0)))+" 币"
	_budget_label.tooltip_text=_budget_label.text
	controls.facility_previous.disabled=page==0
	controls.facility_next.disabled=page+1>=pages
	for index: int in range(_facility_ids.size()):
		var kind: String=_facility_ids[index]
		var card: Button=controls["build_"+kind]
		var unlocked: bool=kind in _snapshot.get("unlocked_room_kinds",[])
		var selected: bool=kind==selected_kind
		card.visible=int(index/PAGE_SIZE)==page
		card.disabled=not unlocked
		card.set_meta("a2_selected",selected)
		var visual_state: String=str(selected)+":"+str(unlocked)
		if str(card.get_meta("a2_visual_state",""))!=visual_state:
			HospitalA2Skin.button(card,"selected" if selected else "paper",16)
			card.set_meta("a2_visual_state",visual_state)
		var price: Label=card.get_meta("price_label")
		price.text="%d 币"%catalog.rooms[kind].cost
		var state: Label=card.get_meta("state_label")
		state.text=("✓ " if selected else "")+("已开放" if unlocked else "锁定 · "+_unlock_copy(kind))
		state.add_theme_color_override("font_color",HospitalUiStyle.TEAL if unlocked else HospitalUiStyle.MUTED)
	if selected_kind=="": return
	var data: Dictionary=catalog.rooms[selected_kind]
	var allowed: bool=selected_kind in _snapshot.get("unlocked_room_kinds",[])
	var affordable: bool=int(_snapshot.get("cash",0))>=int(data.cost)
	_selection_name.text=data.name
	_selection_copy.text=("基础套餐 %d币 · 超面积与家具另计"%data.cost) if allowed and affordable else "现金不足，基础套餐需要%d币"%data.cost if allowed else _unlock_copy(selected_kind)
	_start_button.disabled=not allowed or not affordable
	_start_button.text="划定房间" if allowed else "尚未开放"
	_start_button.tooltip_text=_selection_copy.text

func _reflow_directory() -> void:
	if not is_instance_valid(_facility_grid): return
	_facility_grid.columns=3 if size.x>=446 else 2 if size.x>=295 else 1

func show_recruitment(enabled: bool) -> void:
	_facilities.visible=not enabled
	_recruitment.visible=enabled
	if not enabled: _set_page(0)
	if get_parent() is ScrollContainer: get_parent().set_deferred("scroll_vertical",0)

func configure_short_landscape(enabled: bool) -> void:
	_short_landscape=enabled
	_directory_help.visible=not enabled
	for kind: String in _facility_ids:
		var card: Button=controls["build_"+kind]
		card.custom_minimum_size=Vector2(144,208 if enabled else 232)
		card.set_meta("minimum_size",card.custom_minimum_size)
		var picture: TextureRect=card.get_meta("equipment_picture")
		picture.custom_minimum_size.y=72 if enabled else 94
		var name_label: Label=card.get_meta("name_label")
		name_label.add_theme_font_size_override("font_size",16 if enabled else 17)
	_reflow_directory()

func present(snapshot: Dictionary) -> void:
	_snapshot=snapshot
	for role in _recruit_portraits:
		_recruit_portraits[role].texture=HospitalUiStyle.portrait(role,int(snapshot.next_ids.staff)-1,snapshot.get("appearance_seed",0))
	if controls.has("hire_nurse"):
		var level:Dictionary=catalog.levels.get(str(snapshot.get("level_id","level_01")),{})
		var available:Array=level.get("initial_unlocked_room_kinds",snapshot.get("unlocked_room_kinds",[]))
		var nurse_available:bool="pharmacy" in available or "ward" in available
		var hire_nurse:Button=controls["hire_nurse"]
		hire_nurse.disabled=not nurse_available
		hire_nurse.text="录用"+str(catalog.staff.nurse.name) if nurse_available else "联合诊疗关卡开放护士岗位"
		hire_nurse.tooltip_text="" if nurse_available else "联合诊疗关卡开放护士岗位；当前关卡无需招聘护士。"
	_update_directory()
