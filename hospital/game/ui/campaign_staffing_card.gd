extends PanelContainer

signal closed
signal manage_requested(focus:Dictionary)
const Flow=preload("res://ui/campaign_staffing_flow.gd")
var facility_id:String=""
var controls:Dictionary={}
var _flow:Variant
var _session:GameSession
var _view:Dictionary={}
var _bounds:=Rect2(8,88,916,240)
var _title:Label
var _copy:Label
var _status:Label
var _choice:OptionButton
var _body:VBoxContainer
var _scroll:ScrollContainer
var _footer:HBoxContainer
var _choice_key:String=""

func initialize(session:GameSession)->void:
	_session=session;_flow=Flow.new();_flow.initialize(session)
	mouse_filter=Control.MOUSE_FILTER_STOP
	HospitalA2Skin.panel(self,"paper")
	var column:=VBoxContainer.new();column.add_theme_constant_override("separation",4);add_child(column)
	var header:=HBoxContainer.new();column.add_child(header)
	_title=HospitalUiStyle.text("安排岗位",17,HospitalA2Skin.INK,700);_title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_title.clip_text=true;_title.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;header.add_child(_title)
	var dismiss:=_button(header,"close","×",close)
	dismiss.size_flags_horizontal=Control.SIZE_SHRINK_END
	_scroll=ScrollContainer.new();_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;column.add_child(_scroll)
	_body=VBoxContainer.new();_body.size_flags_horizontal=Control.SIZE_EXPAND_FILL;_body.add_theme_constant_override("separation",4);_scroll.add_child(_body)
	_copy=HospitalUiStyle.text("",14,HospitalA2Skin.INK);_copy.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;_body.add_child(_copy)
	_choice=OptionButton.new();_choice.custom_minimum_size=Vector2(48,48);_choice.size_flags_horizontal=Control.SIZE_EXPAND_FILL;_choice.clip_text=true;_body.add_child(_choice);controls.candidate=_choice
	_status=HospitalUiStyle.text("",13,HospitalA2Skin.CORAL);_status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;_body.add_child(_status)
	_footer=HBoxContainer.new();_footer.add_theme_constant_override("separation",6);column.add_child(_footer)
	_button(_footer,"use_existing","使用已有员工",func()->void:_request("existing"),true)
	_button(_footer,"hire_assign","招聘并派岗",func()->void:_request("hire"),true)
	_button(_footer,"manage_staff","员工管理",_manage)
	_flow.changed.connect(present)
	hide();configure(_bounds)

func _button(parent:Node,key:String,text:String,action:Callable,primary:bool=false)->Button:
	var button:=Button.new();button.text=text;button.custom_minimum_size=Vector2(48,48);button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	HospitalA2Skin.button(button,"primary" if primary else "paper",14)
	button.pressed.connect(action);parent.add_child(button);controls[key]=button
	return button

func show_facility(id:String)->bool:
	if not _flow.open(id):return false
	facility_id=id;_choice_key="";_scroll.scroll_vertical=0
	var plan:Dictionary=_flow.view({},true)
	if plan.get("complete",false) and str(plan.get("retained_staff_id",""))=="":_flow.close();facility_id="";hide();return false
	show();present();return true

func close()->void:
	var had:bool=visible or facility_id!=""
	if _flow!=null:_flow.close()
	facility_id="";_view={};hide()
	if had:closed.emit()

func present(snapshot:Dictionary={})->void:
	if facility_id=="" or _flow==null:return
	_view=_flow.view(snapshot)
	if not _view.get("active",false):close();return
	if _view.get("complete",false) and not _view.get("busy",false) and str(_view.get("retained_staff_id",""))=="":close();return
	_title.text=str(_view.facility_name)+" · 安排岗位";_title.tooltip_text=_title.text
	var existing:bool=str(_view.mode) in ["existing","recovery"]
	_copy.text="缺%s %d人\n招聘%d币 · 新聘日薪%d币"%[str(_view.role_name),int(_view.missing_count),int(_view.hire_cost),int(_view.daily_wage)]
	if existing:_copy.text="缺%s %d人 · 优先安排已有员工\n派岗0币，保留其原有日薪。"%[str(_view.role_name),int(_view.missing_count)]
	if _view.complete:_copy.text="这台设备岗位已齐，另有已聘员工尚未安置。"
	var candidates:Array=_view.candidates
	var signature:String=JSON.stringify(candidates)
	if signature!=_choice_key:
		var selected:String=str(_choice.get_item_metadata(_choice.selected)) if _choice.selected>=0 else ""
		_choice_key=signature;_choice.clear()
		for candidate:Dictionary in candidates:
			_choice.add_item(str(candidate.name)+" · 日薪%d币"%int(candidate.daily_wage));_choice.set_item_metadata(_choice.item_count-1,candidate.id)
			if candidate.id==selected:_choice.select(_choice.item_count-1)
	_choice.visible=existing and not candidates.is_empty()
	controls.use_existing.visible=existing;controls.hire_assign.visible=not existing and not _view.complete
	controls.use_existing.text="继续派岗" if str(_view.mode)=="recovery" else "使用已有员工"
	controls.use_existing.disabled=not bool(_view.can_fill);controls.hire_assign.disabled=not bool(_view.can_fill)
	controls.manage_staff.disabled=bool(_view.busy)
	var failure:Dictionary=_view.failure
	_status.text=""
	if str(failure.get("code",""))=="staffing_changed_review":_status.text="岗位或人员状态已变化，请查看最新安排后再确认。"
	elif not failure.is_empty():_status.text=CampaignHospitalPanel.reason_text(failure,_session.catalog.campaign,_session.presentation_snapshot())
	elif not _view.get("unavailable",{}).is_empty():_status.text=CampaignHospitalPanel.reason_text(_view.unavailable,_session.catalog.campaign,_session.presentation_snapshot())
	if str(_view.retained_staff_id)!="":_status.text="员工已聘用并保留，继续派岗无需再付招聘费。"+("\n"+_status.text if _status.text!="" else "")
	_status.visible=_status.text!=""
	configure(_bounds)

func _request(expected:String)->void:
	if not visible or _view.is_empty():return
	var actual:String=str(_view.get("mode",""))
	if expected=="existing" and actual=="recovery":expected="recovery"
	if expected!=actual:return
	var selected:String=str(_choice.get_item_metadata(_choice.selected)) if _choice.selected>=0 else ""
	_flow.request_fill(expected,selected)

func request_fill()->void:
	if visible and not _view.is_empty():_request("hire" if str(_view.mode)=="hire" else "existing")

func _manage()->void:
	var focus:Dictionary={"facility_id":facility_id,"role":str(_view.get("role","")),"staff_id":str(_view.get("retained_staff_id",""))}
	close();manage_requested.emit(focus)

func configure(bounds:Rect2)->void:
	_bounds=bounds
	if _body==null:return
	var width:float=minf(350,maxf(48,bounds.size.x))
	_body.custom_minimum_size.x=maxf(32,width-32)
	_scroll.custom_minimum_size.y=0
	custom_minimum_size=Vector2(width,0);size=Vector2(width,minf(260,maxf(0,bounds.size.y)))
	position=Vector2(bounds.end.x-width,bounds.position.y)
