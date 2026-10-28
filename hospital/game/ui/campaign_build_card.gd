class_name CampaignBuildCard
extends PanelContainer

var controller:CampaignBuildController
var controls:Dictionary={}
var _title:Label
var _instruction:Label
var _quote:Label
var _status:Label
var _bounds:HBoxContainer
var _openings:HFlowContainer
var _extras:VBoxContainer
var _column:VBoxContainer
var _scroll:ScrollContainer
var _body:VBoxContainer
var _footer:GridContainer
var _choices:OptionButton
var _instances:OptionButton
var _option_signature:=""
var _instance_signature:=""
var _safe:=Rect2(8,8,916,414)

func initialize(owner:CampaignBuildController) -> void:
	controller=owner
	mouse_filter=Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel",HospitalA2Skin.style("paper",8))
	_column=VBoxContainer.new();_column.add_theme_constant_override("separation",3);add_child(_column)
	_title=HospitalUiStyle.text("场景建设",18,HospitalA2Skin.INK,700)
	_title.clip_text=true;_title.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;_column.add_child(_title)
	_scroll=ScrollContainer.new();_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_AUTO;_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	_column.add_child(_scroll)
	_body=VBoxContainer.new();_body.size_flags_horizontal=Control.SIZE_EXPAND_FILL;_body.add_theme_constant_override("separation",3);_scroll.add_child(_body)
	_instruction=HospitalUiStyle.text("",15,HospitalA2Skin.INK,500);_instruction.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;_body.add_child(_instruction)
	_quote=HospitalUiStyle.text("",14,HospitalA2Skin.MUTED)
	_quote.clip_text=true;_quote.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;_body.add_child(_quote)
	_status=HospitalUiStyle.text("",14,HospitalA2Skin.INK);_status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;_body.add_child(_status)
	_bounds=HBoxContainer.new();_bounds.add_theme_constant_override("separation",4);_body.add_child(_bounds)
	for row:Array in [["narrow","宽−",Vector2i(-1,0)],["widen","宽+",Vector2i(1,0)],["shorten","深−",Vector2i(0,-1)],["deepen","深+",Vector2i(0,1)]]:
		var delta:Vector2i=row[2]
		_button(_bounds,row[0],row[1],func()->void:controller.adjust_bounds(delta))
	_openings=HFlowContainer.new();_openings.add_theme_constant_override("h_separation",4);_body.add_child(_openings)
	for row:Array in [["door","房门"],["window","窗户"],["move","移动"],["remove","移除"]]:
		var tool:String=row[0]
		_button(_openings,"opening_"+tool,row[1],func()->void:controller.select_opening_tool(tool))
	_extras=VBoxContainer.new();_extras.add_theme_constant_override("separation",4);_body.add_child(_extras)
	var support_row:=HBoxContainer.new();support_row.add_theme_constant_override("separation",4);_extras.add_child(support_row)
	_choices=OptionButton.new();_choices.custom_minimum_size=Vector2(120,48);_choices.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_choices.clip_text=true;_choices.add_theme_font_size_override("font_size",17);support_row.add_child(_choices);controls.support_kind=_choices
	_button(support_row,"add_support","添加",func()->void:
		if _choices.selected>=0:controller.choose_facility(str(_choices.get_item_metadata(_choices.selected))))
	_instances=OptionButton.new();_instances.custom_minimum_size=Vector2(90,48);_instances.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_instances.clip_text=true;_instances.add_theme_font_size_override("font_size",17);_extras.add_child(_instances);controls.placed_facility=_instances
	_instances.item_selected.connect(func(index:int)->void:controller.select_facility(int(_instances.get_item_metadata(index))))
	_footer=GridContainer.new();_footer.columns=5;_footer.add_theme_constant_override("h_separation",4);_footer.add_theme_constant_override("v_separation",4);_column.add_child(_footer)
	_button(_footer,"cancel","取消",controller.cancel)
	_button(_footer,"back","上一步",controller.back)
	_button(_footer,"rotate","旋转",controller.rotate)
	_button(_footer,"remove","移除",func()->void:controller.remove_selected())
	_button(_footer,"pan_view","移视角",func()->void:controller.set_navigation_mode(not bool(controller.view().get("navigation_mode",false))))
	var proceed:Callable=func()->void:
		if controller.draft!=null and controller.draft.step==3:controller.request_confirm()
		else:controller.advance()
	_button(_footer,"next","下一步",proceed,true)
	hide()

func _button(parent:Node,key:String,copy:String,action:Callable,primary:bool=false) -> Button:
	var button:=Button.new();button.text=copy;button.custom_minimum_size=Vector2(48,48)
	button.size_flags_horizontal=Control.SIZE_EXPAND_FILL;button.set_meta("fixed_width",true)
	HospitalA2Skin.button(button,"primary" if primary else "paper",17)
	# Five final actions fit a328-unit card without reducing readable text
	# or its48-unit target; narrower portrait cards use two footer columns.
	for state:String in ["normal","hover","pressed","disabled"]:
		var style:StyleBoxFlat=button.get_theme_stylebox(state).duplicate()
		style.content_margin_left=6;style.content_margin_right=6
		button.add_theme_stylebox_override(state,style)
	parent.add_child(button);button.pressed.connect(action);controls[key]=button
	return button

func present(view:Dictionary) -> void:
	visible=bool(view.get("active",false))
	if not visible:return
	var step:int=view.step
	var navigating:bool=bool(view.get("navigation_mode",false))
	var layout:Dictionary=view.proposal.layout
	_title.text="%s · %d/4"%[str(view.name),step+1]
	if navigating:_title.text+=" · 移视角"
	_instruction.text=["单指划房；双指移动、缩放视角。","点墙放门窗；拖动画面，双指缩放。","点地面摆设备；拖动画面，双指缩放。","添加配套后点地面；拖动画面可移视角。"][step]
	if navigating:_instruction.text="单指拖动画面；点“继续划房”返回。"
	_quote.text="当前草稿 %s 币 · 可用 %s 币"%[HospitalHud.grouped_number(int(view.quote)),HospitalHud.grouped_number(int(view.cash))]
	var valid:bool=bool(view.preview.get("ok",false))
	if step==0:
		_status.text="房间 %d×%d 格"%[layout.width,layout.height] if int(layout.width)>0 else "先划定房间，设备与入口由你放置"
	elif step==1:_status.text="%d 扇门 · %d 扇窗"%[layout.doors.size(),layout.windows.size()]
	else:_status.text="%d 台独立设备 · 完成后余额 %s 币"%[layout.facilities.size(),HospitalHud.grouped_number(int(view.balance))]
	if step==0 and str(view.get("bounds_issue",""))!="":_status.text+=" · "+str(view.bounds_issue)
	var error:String=str(view.bounds_error) if step==0 else str(view.preview.get("code",""))
	if step==0 and int(layout.width)>1 and error!="":
		_status.text+=" · "+CampaignHospitalPanel.reason_text({"ok":false,"code":error,"data":{}},controller.session.catalog.campaign,controller.session.sim.snapshot())
	if step>0 and not valid and not error.is_empty():
		_status.text=CampaignHospitalPanel.reason_text(view.preview,controller.session.catalog.campaign,controller.session.sim.snapshot())
		_status.add_theme_color_override("font_color",Color("ae4935"))
	else:_status.add_theme_color_override("font_color",HospitalA2Skin.INK)
	_bounds.visible=step==0 and not navigating;_openings.visible=step==1;_extras.visible=step==3
	controls.pan_view.visible=step==0
	controls.pan_view.text="继续划房" if navigating else "移视角"
	HospitalA2Skin.button(controls.pan_view,"selected" if navigating else "paper",17)
	controls.back.visible=step>(2 if view.mode=="install" else 0)
	controls.rotate.visible=step in [1,2,3]
	controls.remove.visible=step==3
	controls.next.text="完成建设" if step==3 and view.mode=="build" else "确认安装" if step==3 and view.mode=="install" else "确认调整" if step==3 else "下一步"
	controls.next.disabled=not bool(view.can_confirm if step==3 else view.can_advance)
	for tool:String in ["door","window","move","remove"]:
		HospitalA2Skin.button(controls["opening_"+tool],"selected" if view.opening_tool==tool else "paper",17)
	var options:Array=view.options
	var signature:String=JSON.stringify(options)
	if signature!=_option_signature:
		_option_signature=signature;_choices.clear()
		for item:Dictionary in options:
			_choices.add_item(str(item.name)+" · "+str(item.cost));_choices.set_item_metadata(_choices.item_count-1,item.id)
	var instances:String=JSON.stringify(layout.facilities)
	if instances!=_instance_signature:
		_instance_signature=instances;_instances.clear()
		for index:int in range(layout.facilities.size()):
			var item:Dictionary=layout.facilities[index]
			_instances.add_item("%d · %s"%[index+1,str(controller.session.catalog.campaign.facilities[item.kind].name)])
			_instances.set_item_metadata(index,index)
	if int(view.selected_index)>=0:_instances.select(int(view.selected_index))
	controls.remove.disabled=int(view.selected_index)<0
	_configure_position.call_deferred()

func configure(safe_rect:Rect2) -> void:
	_safe=safe_rect;_configure_position()

func _configure_position() -> void:
	if not is_inside_tree():return
	# Root supplies the unobstructed content rectangle between the real
	# header and dock. This card never claims the center or their reserved rows.
	var available_width:float=maxf(48,_safe.size.x-16)
	var portrait:bool=_safe.size.y>_safe.size.x
	var preferred:float=available_width if portrait else 340.0 if _safe.size.x<1050 or _safe.size.y<430 else 380.0
	var width:float=minf(preferred,available_width)
	var visible_actions:=0
	for child:Node in _footer.get_children():
		if child is Control and child.visible:visible_actions+=1
	_footer.columns=maxi(1,visible_actions) if width>=328 else 2
	var wrap_width:float=maxf(32,width-34)
	custom_minimum_size=Vector2(width,0)
	size.x=width
	# Give wrapped labels a real width before their first minimum-height
	# calculation; a fresh Label must not measure itself one glyph wide.
	_body.custom_minimum_size.x=wrap_width
	_instruction.custom_minimum_size.x=wrap_width
	_status.custom_minimum_size.x=wrap_width
	var available_height:float=maxf(48,_safe.size.y-16)
	var fixed_height:float=_title.get_combined_minimum_size().y+_footer.get_combined_minimum_size().y+22
	_scroll.custom_minimum_size.y=minf(80,maxf(0,available_height-fixed_height))
	var natural_height:float=_body.get_combined_minimum_size().y+fixed_height
	var height:float=minf(natural_height,available_height)
	size.y=height
	position=Vector2(_safe.position.x+8,_safe.position.y+8)
