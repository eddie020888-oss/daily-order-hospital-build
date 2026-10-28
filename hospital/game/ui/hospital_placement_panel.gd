class_name HospitalPlacementPanel
extends VBoxContainer

var values: Dictionary={}
var _catalog: ContentCatalog
var _image: TextureRect
var _name: Label
var _summary: PanelContainer
var _summary_title: Label
var _summary_copy: Label
var _kind:=""
signal furniture_selected(kind:String)
signal opening_tool_selected(kind:String)
signal bounds_adjusted(size_delta:Vector2i,offset:Vector2i)
var furniture_buttons:Dictionary={}
var opening_buttons:Dictionary={}
var bounds_buttons:Dictionary={}
var _legacy:VBoxContainer
var pinned_header:MarginContainer
var _step_chips:Array[Label]=[]
var _free_body:VBoxContainer
var _free_picture:TextureRect
var _free_hero:PanelContainer
var _free_name:Label
var _free_size:Label
var _bounds_tools:GridContainer
var _bounds_feedback_panel:PanelContainer
var _bounds_feedback:Label
var _quote:Label
var _quote_title:Label
var _quote_amount:=""
var _quote_refund:=false
var _warning:=false
var _ending:Label
var _instruction:Label
var _instruction_panel:PanelContainer
var _furniture:GridContainer
var _furniture_names:Dictionary={}
var _furniture_prices:Dictionary={}
var _short_landscape:=false
var _step:=0
var _help:Label
var _opening_tools:GridContainer
var _opening_status:Label

func initialize(content: ContentCatalog) -> void:
	_catalog=content
	add_theme_constant_override("separation",0)
	_legacy=VBoxContainer.new()
	_legacy.add_theme_constant_override("separation",0)
	add_child(_legacy)
	_image=HospitalUiStyle.picture(null,Vector2(80,66),0)
	_image.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_image.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
	_legacy.add_child(_image)
	_gap(18)
	_name=HospitalUiStyle.text("",18,HospitalUiStyle.INK,700)
	_legacy.add_child(_name)
	_gap(10)
	for row in [["size","占地"],["cost","建造费用"],["rotation","旋转方向"],["balance","建成余额"]]: _line(row[0],row[1])
	_gap(14)
	_summary=HospitalUiStyle.summary(_legacy,"保持道路畅通","入口、门前与患者站位均需连通。",false,18,16)
	HospitalA2Skin.panel(_summary,"paper")
	_summary_title=_summary.get_child(0).get_child(0)
	_summary_copy=_summary.get_child(0).get_child(1)
	_gap(14)
	_help=HospitalUiStyle.text("点选场景调整位置；旋转后再次检查门口。",16,HospitalUiStyle.MUTED,400)
	_help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	_legacy.add_child(_help)
	_build_free_header()
	_free_body=VBoxContainer.new()
	_free_body.add_theme_constant_override("separation",10)
	add_child(_free_body)
	_instruction_panel=PanelContainer.new()
	_instruction_panel.add_theme_stylebox_override("panel",HospitalA2Skin.style("paper",10))
	_free_body.add_child(_instruction_panel)
	_instruction=HospitalUiStyle.text("",15,HospitalUiStyle.MUTED)
	_instruction.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	_instruction_panel.add_child(_instruction)
	_furniture=GridContainer.new()
	_furniture.columns=2
	_furniture.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_furniture.add_theme_constant_override("h_separation",8)
	_furniture.add_theme_constant_override("v_separation",8)
	_free_body.add_child(_furniture)
	for row in [["plant","绿植",50],["bench","座椅",80],["cabinet","文件柜",100],["bin","垃圾桶",30]]:
		var kind:String=row[0]
		var button:=BuildPalette.button("")
		HospitalA2Skin.button(button,"paper",16)
		button.set_meta("minimum_size",Vector2(130,64))
		button.custom_minimum_size=Vector2(130,64)
		button.tooltip_text="%s · %d 币"%[row[1],row[2]]
		_furniture.add_child(button)
		furniture_buttons[kind]=button
		var line:=HBoxContainer.new()
		line.mouse_filter=Control.MOUSE_FILTER_IGNORE
		button.add_child(line)
		line.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		line.offset_left=8;line.offset_right=-8;line.offset_top=5;line.offset_bottom=-5
		line.add_theme_constant_override("separation",6)
		var picture:=HospitalUiStyle.picture(load("res://assets/ui/free-build/"+kind+".png"),Vector2(40,40),0)
		picture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		line.add_child(picture)
		var words:=VBoxContainer.new()
		words.mouse_filter=Control.MOUSE_FILTER_IGNORE
		words.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		words.size_flags_vertical=Control.SIZE_SHRINK_CENTER
		words.add_theme_constant_override("separation",2)
		line.add_child(words)
		_furniture_names[kind]=HospitalUiStyle.text(row[1],17,HospitalUiStyle.INK,650)
		words.add_child(_furniture_names[kind])
		_furniture_prices[kind]=HospitalUiStyle.text("%d 币"%row[2],13,HospitalUiStyle.MUTED)
		words.add_child(_furniture_prices[kind])
		button.pressed.connect(func() -> void:furniture_selected.emit(kind))
	_ending=HospitalUiStyle.text("",14,HospitalUiStyle.MUTED)
	_ending.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	_free_body.add_child(_ending)
	_free_body.hide()
	pinned_header.hide()

func _build_free_header() -> void:
	pinned_header=MarginContainer.new()
	pinned_header.name="BuildProgressAndQuote"
	var column:=VBoxContainer.new()
	column.add_theme_constant_override("separation",8)
	pinned_header.add_child(column)
	var steps:=HBoxContainer.new()
	steps.add_theme_constant_override("separation",5)
	column.add_child(steps)
	for copy in ["1 房间","2 门窗","3 设备","4 家具"]:
		var chip:=HospitalUiStyle.text(copy,14,HospitalUiStyle.MUTED,600)
		chip.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		chip.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		chip.custom_minimum_size.y=30
		chip.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
		steps.add_child(chip);_step_chips.append(chip)
	_free_hero=PanelContainer.new()
	HospitalA2Skin.panel(_free_hero,"paper")
	column.add_child(_free_hero)
	var hero:=HBoxContainer.new()
	hero.add_theme_constant_override("separation",8)
	_free_hero.add_child(hero)
	_free_picture=HospitalUiStyle.picture(null,Vector2(56,46),0)
	_free_picture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	hero.add_child(_free_picture)
	var details:=VBoxContainer.new()
	details.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation",1)
	hero.add_child(details)
	_free_name=HospitalUiStyle.text("",18,HospitalUiStyle.INK,700)
	details.add_child(_free_name)
	_free_size=HospitalUiStyle.text("",13,HospitalUiStyle.MUTED)
	_free_size.name="BuildBoundsSize"
	details.add_child(_free_size)
	var price:=VBoxContainer.new()
	price.add_theme_constant_override("separation",0)
	hero.add_child(price)
	_quote_title=HospitalUiStyle.text("建造费用",12,HospitalUiStyle.MUTED)
	_quote_title.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	price.add_child(_quote_title)
	_quote=HospitalUiStyle.text("",18,Color("ae4935"),750)
	_quote.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	price.add_child(_quote)
	_build_bounds_tools(column)
	_opening_tools=GridContainer.new()
	_opening_tools.columns=2
	_opening_tools.add_theme_constant_override("h_separation",6)
	_opening_tools.add_theme_constant_override("v_separation",6)
	column.add_child(_opening_tools)
	for row in [["door","放门"],["window","开窗"],["move","移动"],["remove","移除"]]:
		var tool:String=row[0]
		var button:=BuildPalette.button(row[1])
		HospitalA2Skin.button(button,"paper",16)
		button.set_meta("minimum_size",Vector2(90,48))
		button.custom_minimum_size=Vector2(90,48)
		button.add_theme_font_size_override("font_size",16)
		button.tooltip_text={"door":"点墙面添加入口，门需通向可达通道；已有入口只会被选中。","window":"点墙面开窗；门和窗不能重叠。","move":"选中门窗，再点新墙面移动。","remove":"点已有门窗移除；至少保留一扇门才能继续。"}[tool]
		button.pressed.connect(func() -> void:opening_tool_selected.emit(tool))
		_opening_tools.add_child(button)
		opening_buttons[tool]=button
	_opening_status=HospitalUiStyle.text("",13,HospitalUiStyle.MUTED)
	_opening_status.clip_text=true
	_opening_status.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(_opening_status)
	_opening_tools.hide();_opening_status.hide()

func _build_bounds_tools(column:VBoxContainer) -> void:
	_bounds_feedback_panel=PanelContainer.new()
	HospitalA2Skin.panel(_bounds_feedback_panel,"paper")
	column.add_child(_bounds_feedback_panel)
	_bounds_feedback=HospitalUiStyle.text("先画一框，再逐格调整。",13,HospitalA2Skin.INK,500)
	_bounds_feedback.name="BuildBoundsFeedback"
	_bounds_feedback.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	_bounds_feedback.max_lines_visible=2
	_bounds_feedback.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	_bounds_feedback.custom_minimum_size.y=22
	_bounds_feedback.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_bounds_feedback_panel.add_child(_bounds_feedback)
	_bounds_tools=GridContainer.new()
	_bounds_tools.columns=4
	_bounds_tools.add_theme_constant_override("h_separation",6)
	_bounds_tools.add_theme_constant_override("v_separation",6)
	column.add_child(_bounds_tools)
	for row in [
		["width_less","宽−",Vector2i(-1,0),Vector2i.ZERO,"宽度减少1格"],
		["width_more","宽＋",Vector2i(1,0),Vector2i.ZERO,"宽度增加1格"],
		["height_less","高−",Vector2i(0,-1),Vector2i.ZERO,"高度减少1格"],
		["height_more","高＋",Vector2i(0,1),Vector2i.ZERO,"高度增加1格"],
		["move_nw","↖左上",Vector2i.ZERO,Vector2i(-1,0),"沿地砖向左上移动1格"],
		["move_ne","↗右上",Vector2i.ZERO,Vector2i(0,-1),"沿地砖向右上移动1格"],
		["move_sw","↙左下",Vector2i.ZERO,Vector2i(0,1),"沿地砖向左下移动1格"],
		["move_se","↘右下",Vector2i.ZERO,Vector2i(1,0),"沿地砖向右下移动1格"]
	]:
		var key:String=row[0]
		var button:=BuildPalette.button(row[1])
		button.custom_minimum_size=Vector2(60,48)
		HospitalA2Skin.button(button,"paper",15)
		button.tooltip_text=row[4]
		button.disabled=true
		_bounds_tools.add_child(button)
		bounds_buttons[key]=button
		button.pressed.connect(_request_bounds_adjustment.bind(key,row[2],row[3]))
	_bounds_feedback_panel.hide()
	_bounds_tools.hide()

func _request_bounds_adjustment(key:String,size_delta:Vector2i,offset:Vector2i) -> void:
	if _step!=0 or not _bounds_tools.is_visible_in_tree() or bounds_buttons[key].disabled:return
	bounds_adjusted.emit(size_delta,offset)

func configure_short_landscape(value:bool) -> void:
	_short_landscape=value
	for side in ["left","right"]:pinned_header.add_theme_constant_override("margin_"+side,16 if value else 22)
	for side in ["top","bottom"]:pinned_header.add_theme_constant_override("margin_"+side,2 if value else 8)
	pinned_header.get_child(0).add_theme_constant_override("separation",0 if value else 8)
	_free_picture.visible=not value
	_free_size.visible=not value or _step==0
	_free_hero.add_theme_stylebox_override("panel",HospitalA2Skin.style("paper",4 if value and _step==0 else 8))
	_bounds_feedback_panel.add_theme_stylebox_override("panel",HospitalA2Skin.style("paper",3 if value else 5))
	_bounds_tools.add_theme_constant_override("v_separation",4 if value else 6)
	_quote_title.visible=not value
	_free_name.add_theme_font_size_override("font_size",16 if value else 18)
	_quote.add_theme_font_size_override("font_size",16 if value else 18)
	_quote.text=(("退回 " if _quote_refund else "费用 ")+_quote_amount) if value else _quote_amount
	for chip in _step_chips:chip.custom_minimum_size.y=24 if value else 30
	# A short phone has enough drawer width for four concise tool labels. One
	# row keeps the fixed footer inside its viewport without shrinking targets
	# or hiding an action behind the scroll area.
	_opening_tools.columns=4 if value else 2
	_opening_tools.add_theme_constant_override("v_separation",4 if value else 6)
	for button in opening_buttons.values():
		button.set_meta("minimum_size",Vector2(60 if value else 90,48))
		button.custom_minimum_size=Vector2(60 if value else 90,48)
		button.add_theme_font_size_override("font_size",15 if value else 16)
	for kind in furniture_buttons:
		var button:Button=furniture_buttons[kind]
		button.set_meta("minimum_size",Vector2(130,48 if value else 64))
		button.custom_minimum_size=Vector2(130,48 if value else 64)
		button.get_child(0).offset_top=4 if value else 5
		button.get_child(0).offset_bottom=-4 if value else -5
		var picture:TextureRect=button.get_child(0).get_child(0)
		picture.custom_minimum_size=Vector2(32,32) if value else Vector2(40,40)
		button.get_child(0).get_child(1).add_theme_constant_override("separation",1 if value else 2)
		_furniture_names[kind].add_theme_font_size_override("font_size",14 if value else 17)
		_furniture_prices[kind].add_theme_font_size_override("font_size",12 if value else 13)
	_furniture.add_theme_constant_override("v_separation",6 if value else 8)
	_instruction_panel.visible=(not value or _step!=3 or _warning) and not (value and _step==0)
	_ending.visible=not value

func _gap(height: int) -> void:
	var gap:=Control.new()
	gap.custom_minimum_size.y=height
	_legacy.add_child(gap)

func _line(key: String, copy: String) -> void:
	var margin:=MarginContainer.new()
	margin.add_theme_constant_override("margin_top",10)
	margin.add_theme_constant_override("margin_bottom",10)
	_legacy.add_child(margin)
	var row:=HBoxContainer.new()
	margin.add_child(row)
	var title:=HospitalUiStyle.text(copy,17,HospitalUiStyle.INK,400)
	title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	row.add_child(title)
	var value:=HospitalUiStyle.text("",17,HospitalUiStyle.INK,650)
	value.name="Value_"+copy
	row.add_child(value)
	values[key]=value
	_legacy.add_child(HSeparator.new())

func present(snapshot: Dictionary, proposal: Dictionary, result: Dictionary) -> void:
	if proposal.is_empty(): return
	_legacy.show();_free_body.hide();pinned_header.hide()
	_bounds_tools.hide();_bounds_feedback_panel.hide()
	_help.text="点选场景调整位置；旋转后再次检查门口。"
	var definition: Dictionary=_catalog.rooms[proposal.kind]
	if _kind!=proposal.kind:
		_kind=proposal.kind
		_image.texture=HospitalA2Skin.equipment_texture(_kind)
		_name.text=HospitalUiStyle.DEVICE_NAMES.get(_kind,definition.name)
	var moving: bool=proposal.get("room_id","")!=""
	var cost: int=0 if moving else definition.cost
	values.size.text="%d×%d" % [proposal.get("layout",{}).get("width",definition.width),proposal.get("layout",{}).get("height",definition.height)]
	values.cost.text="%d 币" % cost
	values.cost.get_parent().get_child(0).text="移动费用" if moving else "建造费用"
	values.rotation.text="%d°" % (int(proposal.rotation)*90)
	values.balance.text="%d 币" % (snapshot.cash-cost)
	values.balance.get_parent().get_child(0).text="移动后余额" if moving else "建成余额"
	var selecting: bool=proposal.get("origin_cell",-1)<0
	_summary_title.text="请先选择地面位置" if selecting else "保持道路畅通" if result.ok else "请保留门口与主走廊"
	_summary_copy.text="点选场景中房间左上角的位置，再检查门口。" if selecting else "入口、门前与患者站位均需连通。" if result.ok else SelectionPanel.reason(result.code)+"。请换一个位置，确认前不会扣款。"
	var style:=HospitalA2Skin.style("paper",12)
	if not result.ok and not selecting:
		style.bg_color=Color("f8e5d8")
		style.border_color=Color("ae4935")
	_summary.add_theme_stylebox_override("panel",style)

func present_free(snapshot:Dictionary,proposal:Dictionary,result:Dictionary,step:int,selected_furniture:String,opening_tool:String="door",selected_opening:Dictionary={},bounds_issue:String="",bounds_actions:Dictionary={}) -> void:
	present(snapshot,proposal,result)
	_legacy.hide();_free_body.show();pinned_header.show()
	_step=step
	var layout:Dictionary=proposal.get("layout",{})
	var width:int=layout.get("width",0)
	var height:int=layout.get("height",0)
	_bounds_tools.visible=step==0
	_bounds_feedback_panel.visible=step==0
	_bounds_feedback.text=bounds_issue if bounds_issue!="" else "先画一框，再逐格调整。" if width<=0 or height<=0 else "框内拖动可平移，按钮每次调整1格。"
	_bounds_feedback.tooltip_text=_bounds_feedback.text
	for key:String in bounds_buttons:
		bounds_buttons[key].disabled=step!=0 or width<=0 or height<=0 or not bool(bounds_actions.get(key,false))
	var footprint_version:int=layout.get("footprint_version",1)
	var body:Vector2i=EquipmentFootprints.profile(proposal.kind).body_size if footprint_version==2 else Vector2i(2,1)
	var equipment_rotation:int=layout.get("equipment",{}).get("rotation",0)
	if equipment_rotation%2==1:body=Vector2i(body.y,body.x)
	var minimum:Vector2i=EquipmentFootprints.minimum_room(proposal.kind) if footprint_version==2 else Vector2i(3,3) if proposal.kind in ["reception","recovery"] else Vector2i(4,4)
	var station:Dictionary=EquipmentFootprints.station(proposal.kind) if footprint_version==2 else RoomTemplates.definition(proposal.kind,0)
	var operations:int=station.service_cells.size()+station.staff_cells.size()
	var clearance:int=station.get("clearance_cells",[]).size()
	var moving:bool=proposal.get("room_id","")!=""
	var upgraded:bool=bool(proposal.get("upgraded",false))
	var body_count:int=station.equipment_cells.size()
	if upgraded:
		body_count+=station.upgrade_equipment_cells.size()
		operations+=station.upgrade_service_cells.size()
	var body_copy:String=("单席 %d×%d · 两席共 %d 格"%[body.x,body.y,body_count] if upgraded else "本体 %d×%d · %d 格"%[body.x,body.y,body_count]) if footprint_version==2 else "旧版本体 %d 格"%body_count
	var cost:int=FreeRoomLayout.base_cost(proposal.kind,layout,_catalog,upgraded)
	var old_cost:int=int(snapshot.rooms.get(proposal.get("room_id",""),{}).get("invested_cost",0)) if moving else 0
	var delta:int=cost-old_cost
	var refund:int=(-delta)*3/4 if delta<0 else 0
	values.size.text="%d×%d"%[width,height] if width>0 else "等待划定"
	values.cost.get_parent().get_child(0).text="预计退回" if delta<0 else "改造费用" if moving else "建造费用"
	values.cost.text="%d 币"%(refund if delta<0 else maxi(0,delta))
	values.balance.text="%d 币"%(snapshot.cash+refund if delta<0 else snapshot.cash-maxi(0,delta))
	values.rotation.get_parent().get_child(0).text="门朝向" if step==1 else "设备朝向"
	var door:Dictionary=layout.get("door",{})
	values.rotation.text={"north":"北侧","east":"东侧","south":"南侧","west":"西侧"}.get(door.get("side",""),"未放置") if step==1 else "%d°"%(int(layout.get("equipment",{}).get("rotation",0))*90)
	_furniture.visible=step==3
	_opening_tools.visible=step==1
	_opening_status.visible=step==1
	_present_openings(layout,opening_tool,selected_opening)
	var valid:bool=result.ok
	_summary_title.text=["自由划定房间大小","自由选择门窗位置","摆放必需工作站","家具可选，可直接完成"][step]
	_summary_copy.text=["单指拖框，或依次点两个对角。最小 %d×%d，可换向；房间可继续扩大。"%[minimum.x,minimum.y],"先选放门或开窗，再点墙面。可设置多个入口；每扇门内外通道都要留空。",body_copy+"；另留 %d 格操作位、%d 格维护通道。点地面放置，可旋转。"%[operations,clearance],"选物件后点地面放置；再点同物件所在格移除。操作位、维护通道和门口均需留空。"][step]
	if step>=2 and not valid:
		_summary_copy.text=SelectionPanel.reason(result.code)+"。请调整位置，完成前不会扣款。"
	if delta>0 and delta>snapshot.cash and step>=2:
		_summary_copy.text="现金不足，请缩小房间或减少家具。完成前不会扣款。"
	_free_picture.texture=HospitalA2Skin.equipment_texture(proposal.kind)
	_free_name.text=_catalog.rooms[proposal.kind].name
	_free_size.text=("房间 %d×%d"%[width,height] if width>0 else "待划定大小")+(" · 两席共 %d 格"%body_count if upgraded else " · 本体 %d×%d"%[body.x,body.y] if footprint_version==2 else " · 旧版本体 %d 格"%body_count)
	if step==0:_free_size.text="房间 %d×%d 格"%[width,height] if width>0 and height>0 else "待划定大小"
	_free_name.tooltip_text=_summary_copy.text
	_free_size.tooltip_text=_summary_copy.text
	_quote_title.text=values.cost.get_parent().get_child(0).text
	_quote_amount=values.cost.text
	_quote_refund=delta<0
	_quote.tooltip_text=values.balance.text+" · 完成后余额"
	_ending.text="完成后余额  "+HospitalHud.grouped_number(snapshot.cash+refund if delta<0 else snapshot.cash-maxi(0,delta))+" 币"
	var opening_help:String={"door":"点墙面放门，门需通向可达通道。已有门窗只会被选中，可再选择移动或移除。","window":"点墙面开窗。每扇窗占一段墙，门与窗不能重叠。","move":"点选已有门窗，再点目标墙面。仅移动选中项。","remove":"点已有门窗移除。最后一扇门可以删除，继续前需重新放门。"}.get(opening_tool,"")
	if layout.get("door",{}).is_empty():opening_help+="\n至少放置一扇门，才能进入下一步。"
	_instruction.text=[body_copy+"；最小房间 %d×%d，可换向。拖框自定房间大小。"%[minimum.x,minimum.y],opening_help,body_copy+"｜操作 %d 格｜维护 %d 格\n蓝色本体 · 青色操作 · 黄色维护。点地面放置，可旋转。"%[operations,clearance],"选家具后点地面摆放，再点原位移除。双人长椅占 2×1 格，可旋转。" if footprint_version==2 else "选家具后点地面摆放，再点原位移除。"][step]
	var warning:bool=step>=2 and not valid
	if warning:_instruction.text=SelectionPanel.reason(result.code)+("\n"+body_copy+"；另留操作 %d 格、维护 %d 格。"%[operations,clearance] if step==2 else "")
	if delta>0 and delta>snapshot.cash and step>=2:_instruction.text="现金不足，请缩小房间或减少家具。";warning=true
	_warning=warning
	var instruction_style:=HospitalA2Skin.style("paper",10)
	if warning:
		instruction_style.bg_color=Color("f8e5d8")
		instruction_style.border_color=Color("ae4935")
	_instruction_panel.add_theme_stylebox_override("panel",instruction_style)
	for index in range(_step_chips.size()):
		var chip:Label=_step_chips[index]
		chip.add_theme_stylebox_override("normal",HospitalA2Skin.style("primary" if index==step else "paper",3))
		chip.add_theme_color_override("font_color",Color("fff8e9") if index==step else HospitalUiStyle.TEAL if index<step else HospitalUiStyle.MUTED)
	for kind in furniture_buttons:
		var button:Button=furniture_buttons[kind]
		var selected:bool=kind==selected_furniture
		var visual_state:String=str(selected)+":"+str(_short_landscape)
		if str(button.get_meta("a2_visual_state",""))!=visual_state:
			HospitalA2Skin.button(button,"selected" if selected else "paper",14 if _short_landscape else 17)
			button.set_meta("a2_visual_state",visual_state)
		var count:=0
		for item in layout.get("furniture",[]):
			if item.kind==kind:count+=1
		var price:int={"plant":50,"bench":80,"cabinet":100,"bin":30}[kind]
		var furniture_size:Vector2i=EquipmentFootprints.furniture_size(kind,0) if footprint_version==2 else Vector2i.ONE
		if kind=="bench":
			var picture:TextureRect=button.get_child(0).get_child(0)
			picture.texture=load("res://assets/ui/free-build/bench-v2.png" if footprint_version==2 else "res://assets/ui/free-build/bench.png")
		_furniture_names[kind].text="双人长椅" if kind=="bench" and footprint_version==2 else {"plant":"绿植","bench":"座椅","cabinet":"文件柜","bin":"垃圾桶"}[kind]
		_furniture_prices[kind].text="%d币 · %d×%d"%[price,furniture_size.x,furniture_size.y]+(" · %d件"%count if count>0 else "")
		button.tooltip_text="%s · %d×%d，占 %d 格 · %d 币\n旋转后全部占格一起变化。"%[_furniture_names[kind].text,furniture_size.x,furniture_size.y,furniture_size.x*furniture_size.y,price]
	configure_short_landscape(_short_landscape)

func _present_openings(layout:Dictionary,tool:String,selection:Dictionary) -> void:
	var primary:Dictionary=layout.get("door",{})
	var doors:Array=layout.get("doors",[primary] if not primary.is_empty() else [])
	var windows:Array=layout.get("windows",[])
	var copy:String="%d 扇门 · %d 扇窗"%[doors.size(),windows.size()]
	if not selection.is_empty():
		var items:Array=doors if selection.get("kind","")=="door" else windows
		var index:int=int(selection.get("index",-1))
		if index>=0 and index<items.size():
			var item:Dictionary=items[index]
			copy+=" · 已选%s %s%d"%["门" if selection.kind=="door" else "窗",{"north":"北","east":"东","south":"南","west":"西"}.get(item.side,""),int(item.offset)+1]
	_opening_status.text=copy
	_opening_status.tooltip_text=copy
	for kind in opening_buttons:
		var button:Button=opening_buttons[kind]
		var selected:bool=kind==tool
		var visual_state:String=str(selected)+":"+str(_short_landscape)
		if str(button.get_meta("a2_visual_state",""))!=visual_state:
			HospitalA2Skin.button(button,"selected" if selected else "paper",15 if _short_landscape else 16)
			button.set_meta("a2_visual_state",visual_state)
		button.disabled=kind in ["move","remove"] and doors.is_empty() and windows.is_empty()
