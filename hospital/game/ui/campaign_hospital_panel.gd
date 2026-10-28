class_name CampaignHospitalPanel
extends Control

const FACILITY_PAGE_SIZE: int=3
const OperatingInsights=preload("res://ui/hospital_operating_insights.gd")
const StaffingInsights=preload("res://ui/hospital_staffing_insights.gd")
const ManagementInsights=preload("res://ui/hospital_management_insights.gd")
const ClinicDrive=preload("res://campaign/campaign_clinic_drive.gd")
const PlaytestInsights=preload("res://ui/hospital_playtest_insights.gd")
const StaffRelief=preload("res://campaign/campaign_staff_relief.gd")

signal closed
signal layout_changed
signal focus_requested(id:String,group:String)
signal tutorial_focus_requested(focus:Dictionary)
var experience_tutorial:HospitalExperienceTutorial
var session:GameSession
var world:HospitalWorld
var controls:Dictionary={}
var section:="cases"
var panel:PanelContainer
var body:VBoxContainer
var footer:HFlowContainer
var scroll:ScrollContainer
var _permanent:Dictionary={}
var _safe:=Rect2(8,8,1264,704)
var _snapshot:Dictionary={}
var _signature:=""
var _scroll_reset_serial:=0
var _unit:="all"
var _search:=""
var _page:=0
var _visible:Array=[]
var _facility_grid:GridContainer
var _page_label:Label
var _facility_id:=""
var _selected_room:=""
var _selected_staff:=""
var _draft:Dictionary={}
var _draft_origin:=49
var _draft_unit:="U01"
var _edit_room:=""
var picking_origin:=false:
    set(value):
        if picking_origin==value:return
        picking_origin=value
        configure(_safe)
        layout_changed.emit()
var _feedback:=""
var _preview_label:Label
var _last_preview:Dictionary={}
var _loan_amount:=1000
var _price:=100
var _selected_audit:=""
var _selected_project:=""
var _selected_operation:=""
var _training_unit:="U01"
var _resource_focus:="supplies"
const RESOURCE_NAMES:Dictionary={"supplies":"医疗耗材","sterile":"无菌器械","blood":"可用血液","samples":"标本","prepared":"已阅片病理资料","waste":"待处理废物","water":"饮水与清洗用水","food":"餐食","spares":"维修备件","cleaned_instruments":"已清洗器械","packed":"已包装器械","clean_tools":"已清洗工具","lab_results":"检验结果","sorted_samples":"已分拣标本","tissue":"处理后组织","slides":"组织切片","medication":"已核对药品","sterile_medication":"无菌配制药物","components":"已分离血液成分","matched_blood":"已配型血液","delivered":"已配送物资","sterile_delivered":"已运送无菌物资","sorted_waste":"已分类废物"}
var _hire_role:=""
var _routine_case:=""
var _policy_drafts:Dictionary={}
var _policy_draft_sim:Simulation
var _day_history_expanded:=false
var _stock_stamp:=""
var _stock_projection:Dictionary={}
var _focus_patient:=""
var _guidance_origin:Dictionary={}

func initialize(owner_session:GameSession) -> void:
    session=owner_session
    mouse_filter=Control.MOUSE_FILTER_IGNORE
    panel=PanelContainer.new()
    panel.add_theme_stylebox_override("panel",HospitalUiStyle.panel(18,HospitalUiStyle.PAPER,18))
    add_child(panel)
    var column:=VBoxContainer.new()
    column.add_theme_constant_override("separation",10)
    panel.add_child(column)
    var header:=HBoxContainer.new()
    column.add_child(header)
    var title:=HospitalUiStyle.text("医院经营 · 职业任务",22,HospitalUiStyle.INK,750)
    title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
    header.add_child(title)
    _button(header,"campaign_close","返回医院",func()->void: close())
    var tabs:=HFlowContainer.new()
    tabs.add_theme_constant_override("h_separation",6)
    tabs.add_theme_constant_override("v_separation",6)
    column.add_child(tabs)
    for row:Array in [["facilities","设施"],["cases","病例"],["staff","员工"],["operations","后勤"],["growth","成长与审核"],["finance","财务"]]:
        var key:String=row[0]
        _button(tabs,"section_"+key,row[1],func()->void:show_section(key))
    _permanent=controls.duplicate()
    scroll=ScrollContainer.new()
    scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
    scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
    column.add_child(scroll)
    body=VBoxContainer.new()
    body.size_flags_horizontal=Control.SIZE_EXPAND_FILL
    body.add_theme_constant_override("separation",10)
    scroll.add_child(body)
    footer=HFlowContainer.new()
    footer.add_theme_constant_override("h_separation",8)
    footer.add_theme_constant_override("v_separation",6)
    column.add_child(footer)
    hide()
    configure(_safe)

func configure(safe_rect:Rect2) -> void:
    _safe=safe_rect
    position=Vector2.ZERO
    size=safe_rect.end+Vector2(8,8)
    if panel==null:return
    _sync_phone_footer()
    if is_full_page():
        panel.position=safe_rect.position
        panel.size=safe_rect.size
        _configure_facility_grid()
        return
    var width:float=minf(650,safe_rect.size.x-24)
    var top:float=68 if safe_rect.size.y<430 else 78
    panel.position=Vector2(safe_rect.end.x-width-12,safe_rect.position.y+top)
    panel.size=Vector2(width,maxf(160,safe_rect.size.y-top-(8 if safe_rect.size.y<430 else 86)))
    _configure_facility_grid()

func is_full_page() -> bool:
    var viewport_height:float=get_viewport_rect().size.y if is_inside_tree() else _safe.end.y+8
    return viewport_height<500 and not picking_origin

func _content() -> Dictionary:
    var value:Variant=session.catalog.get("campaign")
    return value if value is Dictionary else {}

func show_section(value:String) -> void:
    if world!=null:world.clear_campaign_preview()
    picking_origin=false
    if section!=value:_feedback=""
    section=value
    _signature=""
    show()
    _render()
    _reset_scroll_top()

func _reset_scroll_top() -> void:
    _scroll_reset_serial+=1
    scroll.scroll_vertical=0
    _settle_scroll_top.call_deferred(_scroll_reset_serial)

func _settle_scroll_top(serial:int) -> void:
    if not is_inside_tree():return
    await get_tree().process_frame
    if serial==_scroll_reset_serial and is_instance_valid(scroll):scroll.scroll_vertical=0

func close() -> void:
    picking_origin=false
    if world!=null:world.clear_campaign_preview()
    hide()
    closed.emit()

func present(snapshot:Dictionary) -> void:
    if not visible:return
    _snapshot=snapshot
    if section=="layout":return
    var focus:Control=get_viewport().gui_get_focus_owner() if is_inside_tree() else null
    if focus is LineEdit and is_ancestor_of(focus):return
    for control:Variant in controls.values():
        if is_instance_valid(control) and control is Button and control.button_pressed:return
    var key:String=""
    if session.is_long_campaign():
        key=JSON.stringify([section,snapshot.get("tick",0)/10,snapshot.get("command_sequence",0),snapshot.get("challenge",{}),snapshot.campaign.get("phase_index",0),snapshot.campaign.get("course_complete",false)])
    else:key=JSON.stringify([section,snapshot.get("tick",0)/10,snapshot.get("command_sequence",0),snapshot.get("challenge",{}),snapshot.get("campaign",{})])
    if key==_signature and _policy_draft_sim==session.sim:return
    _signature=key
    _render()

func _clear(container:Node) -> void:
    for child:Node in container.get_children():
        container.remove_child(child)
        child.queue_free()

func _render() -> void:
    if session==null or body==null:return
    if _policy_draft_sim!=session.sim:
        _policy_drafts.clear()
        _policy_draft_sim=session.sim
        _day_history_expanded=false
        _stock_stamp=""
        _focus_patient=""
        _guidance_origin.clear()
        _scroll_reset_serial+=1
    _snapshot=session.presentation_snapshot()
    _clear(body)
    _facility_grid=null
    _clear(footer)
    controls=_permanent.duplicate()
    if section in ["facilities","facility","layout"]:
        var directory_style:=HospitalA2Skin.style("paper",16)
        directory_style.border_color=Color("47797a")
        directory_style.set_border_width_all(2)
        panel.add_theme_stylebox_override("panel",directory_style)
    else:
        panel.add_theme_stylebox_override("panel",HospitalUiStyle.panel(18,HospitalUiStyle.PAPER,18))
    for key:String in _permanent:
        if key.begins_with("section_"):
            var selected:bool=key=="section_"+section
            _permanent[key].add_theme_stylebox_override("normal",HospitalUiStyle.panel(9,HospitalUiStyle.TEAL if selected else HospitalUiStyle.SOFT,8))
            _permanent[key].add_theme_color_override("font_color",Color.WHITE if selected else HospitalUiStyle.INK)
    if not session.is_campaign():
        _copy("请从主菜单的职业关卡开始经营；原两关继续使用原有建设和派工界面。")
        return
    if _feedback!="":_copy(_feedback,HospitalUiStyle.TEAL)
    if not _guidance_origin.is_empty() and section!=str(_guidance_origin.section):
        var origin_name:String={"management":"经营方案","operations":"后勤工单","resource":"补给来源","rooms":"科室设备","facility":"设备详情"}.get(str(_guidance_origin.section),"上一步")
        _button(body,"guidance_back","返回"+origin_name,_return_guidance)
    match section:
        "facilities":_facilities_page()
        "facility":_facility_page()
        "layout":_layout_page()
        "rooms":_rooms_page()
        "cases":_cases_page()
        "staff":_staff_page()
        "patients":_patients_page()
        "operations":_operations_page()
        "growth":_growth_page()
        "finance":_finance_page()
        "resource":_resource_page()
        "tutorial":_tutorial_page()
        "management":_management_page()
        "review":_review_page()
    _sync_phone_footer()

func _sync_phone_footer() -> void:
    if footer!=null:footer.visible=not is_full_page() or section not in ["patients","staff","finance","operations"]

func _text(parent:Node,copy:String,size_value:int=16,color:Color=HospitalUiStyle.INK) -> Label:
    var label:=HospitalUiStyle.text(copy,size_value,color)
    label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
    parent.add_child(label)
    return label

func _copy(copy:String,color:Color=HospitalUiStyle.MUTED) -> void:
    _text(body,copy,16,color)

func _heading(copy:String) -> void:
    _text(body,copy,21,HospitalUiStyle.INK)

func _button(parent:Node,key:String,copy:String,action:Callable,primary:bool=false) -> Button:
    var button:=BuildPalette.button(copy)
    button.custom_minimum_size=Vector2(80,48)
    button.add_theme_font_size_override("font_size",16)
    if section in ["facilities","facility","layout"]:
        HospitalA2Skin.button(button,"primary" if primary else "paper",16)
    elif primary:HospitalUiStyle.primary(button)
    parent.add_child(button)
    controls[key]=button
    button.pressed.connect(action)
    return button

func _choice(key:String,label:String,rows:Array,current:String,action:Callable) -> OptionButton:
    _copy(label)
    var option:=OptionButton.new()
    option.custom_minimum_size=Vector2(0,48)
    option.size_flags_horizontal=Control.SIZE_EXPAND_FILL
    option.clip_text=true
    var index:=0
    for row:Dictionary in rows:
        option.add_item(str(row.get("name",row.id)))
        option.set_item_metadata(index,str(row.id))
        if str(row.id)==current:option.select(index)
        index+=1
    body.add_child(option)
    controls[key]=option
    option.item_selected.connect(func(i:int)->void: action.call(str(option.get_item_metadata(i))))
    return option

func _selected(key:String) -> String:
    if not controls.has(key):return ""
    var option:OptionButton=controls[key]
    return str(option.get_item_metadata(option.selected)) if option.selected>=0 else ""

func _spin(key:String,label:String,current:int,low:int,high:int,action:Callable=Callable()) -> SpinBox:
    var row:=HBoxContainer.new()
    body.add_child(row)
    var title:=_text(row,label)
    title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
    var spin:=SpinBox.new()
    spin.min_value=low
    spin.max_value=high
    spin.step=1
    spin.value=current
    spin.custom_minimum_size=Vector2(130,48)
    row.add_child(spin)
    controls[key]=spin
    if action.is_valid():spin.value_changed.connect(func(value:float)->void:action.call(int(value)))
    return spin

func _issue(type:String,payload:Dictionary={}) -> Dictionary:
    var result:Dictionary=session.issue(type,payload)
    if result.get("ok",false):
        if type=="set_clinical_policy":_policy_drafts.erase("clinical_policy")
        elif type=="set_procurement_policy":_policy_drafts.erase("procurement_policy")
        elif type=="set_price":_policy_drafts.erase("price_percent")
        elif type=="set_operation_auto":_policy_drafts.erase("auto_target:"+str(payload.get("facility_kind","")))
    _feedback="已完成："+command_name(type) if result.get("ok",false) else "操作未完成："+reason_text(result,_content(),_snapshot)
    if result.get("ok",false) and type=="continue_hospital":_feedback+="。本院已保留，返回医院点播放继续营业。"
    _signature=""
    if result.get("ok",false) and type in ["build_department","edit_department","place_facility"]:
        _selected_room=str(result.get("data",{}).get("room_id",_selected_room))
        if world!=null:world.clear_campaign_preview()
        section="rooms"
    _render.call_deferred()
    return result

static func command_name(type:String) -> String:
    var additions:Dictionary={"set_staff_relief":"员工替班设置","set_staff_relief_operations":"后勤替班设置","set_staff_relief_reserve":"候补登记","set_clinic_drive":"集中门诊设置","set_clinical_policy":"诊疗策略","clinical_decision":"患者诊疗决定","set_procurement_policy":"采购方式","request_patient_need":"个人生活服务已安排","set_staff_wage":"员工薪酬"}
    if additions.has(type):return additions[type]
    return {"build_department":"建设科室","edit_department":"调整房间","place_facility":"安装设施","remove_facility":"出售设施","remove_room":"撤除科室","hire":"招聘员工","assign":"安排岗位","unassign":"撤回员工","dismiss":"解聘员工","accept_case":"接收病例","run_operation":"后勤工单已排队","request_audit":"申请审核","start_research":"研究已安排","start_training":"培训已安排","set_price":"收费政策","take_loan":"借款","repay_loan":"还款","resolve_event":"事件处置","close_facility":"关停设施","reopen_facility":"开放设施","advance_stage":"提交阶段考核","set_intake":"常规客流设置","admit_routine":"接收常规病例","set_operation_auto":"自动补给设置","continue_hospital":"继续本院经营"}.get(type,"操作")

static func reason_text(value:Variant,content:Dictionary={},snapshot:Dictionary={}) -> String:
    if value is Array:
        var lines:Array[String]=[]
        for item:Variant in value:lines.append(reason_text(item,content,snapshot))
        return "；".join(lines)
    if value is String:
        var mark:int=value.find(":")
        return reason_text({"code":value.substr(0,mark) if mark>=0 else value,"data":{"subject":value.substr(mark+1) if mark>=0 else ""}},content,snapshot)
    if not value is Dictionary:return str(value)
    var code:String=str(value.get("code",value.get("reason","")))
    var detail:Dictionary=value.get("data",value)
    if value.has("message"):return str(value.message)
    var names:Dictionary={"missing_facility":"缺少可用设施","missing_staff":"缺少可用匹配员工，请检查派岗、技能、当前工作或短休返岗进度","missing_skill":"员工缺少本专科技能，需要培训","missing_resource":"物资不足，需要后勤补给","insufficient_resource":"物资不足，需要后勤补给","insufficient_cash":"现金不足","staff_busy":"员工仍在服务、预约、工单、培训、移动或补给短休中","facility_busy":"设施尚有患者、预约或工单","room_busy":"科室尚有人员或进行中的工作","path_blocked":"通路不可达，请调整位置与门口净空","room_unreachable":"房门或操作位无法到达","case_not_next":"请先完成当前病例批次","wave_active":"当前批次仍未结束","level_locked":"须先完成上一职业关卡","career_invalid":"职业记录未通过校验，当前医院保持","patient_active":"患者仍在就诊","audit_failed":"审核尚有缺项","missing_research":"研究条件尚未完成","invalid_layout":"房间布局尚未有效","boundary":"房间超出可建范围","room_overlap":"与已有科室重叠","main_corridor":"主走廊需要保持畅通","facility_closed":"设施已关闭","facility_broken":"设备需要维修","role_mismatch":"岗位不匹配","staff_limit":"员工已达本关上限","no_facility":"未安装对应设施","not_campaign":"请先进入职业关卡","career_complete":"十二关职业任务已全部完成","level_not_won":"须真实完成本关目标后才能进入下一关","facility_work_required":"必须完成一次该设施的真实工序","completed_case_required":"必须有完整离院的病例任务","assigned_role_required":"需要已派到设施的对应岗位","sterilization_batch_required":"需要完成消毒供应的真实批次","completed_support_order_required":"需要完成一项医技支持工序","verified_blood_batch_required":"需要完成输血检验工序","maintenance_required":"有设备需要维修后复核","cleaning_required":"卫生条件不足，需要清洁","roster_handoff_required":"需要完成排班交接工单","earned_income_required":"需要真实病例离院收入","missing_or_busy_staff":"匹配员工缺岗、忙碌或需要休息","unreachable_workplace":"员工到工作点的路线不通","insufficient_resources":"现金或物资不足","not_next_case":"请按本关病例任务顺序接收","operation_not_ready":"后勤工序尚未准备齐全","operation_pending":"该工序已有未完成工单","audit_requirements":"审核有缺项，补齐后可复核","patient_service_required":"医疗设备须由真实患者使用","research_workplace_required":"需要研究终端与对应人员","teaching_workplace_required":"需要教学讲台与对应人员","staff_busy_or_trained":"员工仍在工作或已经完成该方向培训","research_completed":"该研究已经完成","research_pending":"该研究正在进行","event_work_required":"请先完成事件所需后勤工单，再复核","wrong_role":"员工岗位与设备不匹配","role_filled":"该岗位已有足够人员","unassign_staff_first":"请先撤回设备上的员工","loan_limit":"借款金额或总负债超过限制","invalid_repayment":"还款额需大于零且不超过当前贷款","invalid_origin":"请选择医院内有效位置","invalid_unit":"请选择有效科室","invalid_facilities":"请检查设备列表","invalid_facility_placement":"设备位置或四向角度不合法","facility_overlap":"设备本体或操作位重叠","reserved_plot":"本关此区域不可建造","facility_out_of_bounds":"设备本体超出房间范围","facility_access_out_of_bounds":"操作位或检修位超出房间范围","facility_access_overlap":"操作位或检修位被设备本体挡住","facility_work_position_overlap":"两台设备的操作或检修位置重叠","door_operating_position":"门口通道占用了操作或检修位置","facility_unreachable":"设备操作位或检修位无法到达","invalid_facility_id":"设备编号重复，请重新选择放置","invalid_layout_dimensions":"房间宽须3–22格、深须3–7格，且应完整留出操作位","missing_cash":"现金不足以准备本批诊疗","reserved_resources_unavailable":"已预约的资源暂不可用，请检查库存和现金","support_unavailable":"后勤或医技支持设施尚不可用","support_queued":"后勤或医技支持工序正在排队","support_missing":"支持工单尚未找到，请检查所需设施","patience_exhausted":"患者等候超过耐心，正在离院","fire_system_check_required":"需用消防报警面板完成一次消防检查，再申请审核","archive_after_care_required":"需在本关最后一个病例完成后，重新运行审核证据归档台归档，再申请复核","all_cases_before_archive_audit_required":"完成本关全部病例后再归档审核","facility_occupied_unreachable":"员工或患者站定后会堵住操作通道，请为工作位外侧留出通道","phase_requirements":"本阶段目标尚未完成，请查看逐项目标","stage_requirements":"本阶段目标尚未完成，请查看逐项目标","phase_locked":"此签名病例将在后续经营阶段开放","facility_locked":"此设施尚未到开放阶段","intake_disabled":"常规接诊已关闭","no_routine_case":"先完成本阶段签名病例，才能接收相应常规客流","no_completed_case":"先完成一个签名病例，才能接收相应常规客流","signature_active":"当前签名病例仍在就诊","signature_not_ready":"当前签名病例尚未准备齐全","hospital_full":"当前在院人数已达接诊容量","patient_limit":"当前在院人数已达接诊容量","not_long_campaign":"此操作只用于长线经营模式","course_not_complete":"尚未通过综合考核","already_continuing":"当前医院已在继续经营","auto_not_supported":"此工序没有可自动补给的产出物","invalid_auto_target":"请设置有效的目标库存","intake_must_stop":"请先关闭常规接诊，再申请综合考核","patients_remaining":"仍有患者在院，请等待实际离院后申请考核","case_stage_locked":"此病例将在后续经营阶段开放","routine_case_not_established":"先真实完成签名病例，才能接收相应常规客流","intake_paused":"常规接诊已关闭","intake_waiting":"正在等待下一次常规接诊调度","invalid_automation_target":"请设置允许范围内的库存或维护阈值","automation_not_supported":"这项工序不能自动化，请按需手动安排","course_already_complete":"综合考核已通过，无须重复提交","case_locked":"此病例尚未到开放阶段","routine_case_not_completed":"先实际完成签名病例，才能接收相应常规客流","challenge_ended":"本次经营已停止，请从结算页选择合法后续操作","new_cures":"本阶段新增治愈离院人数不足","signature_cases":"本阶段签名病例尚未完成","hospital_value":"当前医院实体价值不足","cash":"现金未达到本阶段安全线","reputation":"声誉尚未达标","cure_rate":"最近30分钟实际结案治愈率尚未达标","profitable_days":"连续达标经营日不足，利润、当日治愈人数与当日治愈率须同时达标","research":"完成的独立研究数量不足","trained_staff":"本关临床岗位上、专科匹配的受训员工不足","roles":"实际派岗的岗位种类不足","operations":"指定运营设施尚未实际使用","audits":"本阶段综合审核尚未完成","events":"营业事件尚未闭环","debt":"仍有贷款尚未清偿","empty_hospital":"请关闭常规接诊，并等待所有在院患者实际离院","facility_stage_locked":"此设施需后续阶段开放","trainee_requires_separate_teacher":"学员需与教学设施教师分开安排","event_repair_target_required":"请先修复本次事件指定设备再复核","quality_samples":"最近30分钟有效结案样本不足，请继续完成实际诊疗","trained_units":"在岗受训员工覆盖的不同临床专科不足","hygiene":"卫生水平尚未达标，请安排清洁或过滤工单"}
    names["queue_position_blocked"]="这里已有患者等候或正在前往，请等患者离开后再调整"
    names.merge({"clinical_decision_required":"检查已完成，请决定继续检查、审慎治疗或转诊","clinical_policy_blocked":"自动诊疗正在等待条件，请查看该患者的方案缺项","clinical_option_unavailable":"所选方案尚缺人员、设施、耗材或费用","clinical_decision_not_ready":"当前尚未到诊疗决定阶段","stale_clinical_decision":"该患者的决定已更新，请使用当前方案","clinical_exam_limit":"该患者已经完成最多两次复检","invalid_clinical_policy":"请选择允许的诊疗策略","need_facility_unreachable":"尚无开放且可到达的生活设施","need_missing_resource":"生活服务缺少物资","need_insufficient_cash":"生活服务费用不足","personal_need_using":"正在使用个人生活设施","personal_need_canceled":"本次生活服务已取消，继续原诊疗路线","need_already_used_this_step":"本诊疗步骤已经安排过一次生活服务","need_cooldown":"请等待生活服务冷却结束","need_not_due":"当前需求较低，暂不需要安排","patient_busy":"患者正在接受服务或移动，请等空闲后安排","patient_finished_care":"患者已完成诊疗，将前往出口","invalid_wage_raise":"薪资只能提高到允许档位，最高150%","invalid_procurement_policy":"请选择普通、节省或加急采购"})
    names.merge({"staff_rest_cooldown":"刚完成补给短休，请稍后再安排","staff_rest_missing_resources":"补给短休缺少可用现金、水或餐食，请先补给","staff_rest_facility_unreachable":"尚无开放且可达的饮水或便食设施","staff_rest_not_due":"员工当前状态良好，可稍后安排","invalid_staff_rest":"请选择有效员工和饮水或便食短休","experience_not_enabled":"本院保留原经营规则，新开医院可启用自动照顾","stale_management_event":"经营方案已更新，请使用当前页面","management_evidence_required":"尚未完成该方案要求的实际业务，请查看进度提示","management_choice_required":"请先选择经营方案，再完成对应业务","management_event_already_resolved":"这项经营方案已经完成","legacy_management_rules":"本院保留原经营规则，新开医院可体验新方案"})
    names.merge({"invalid_clinic_drive":"请选择4、8或12批有效门诊计划","clinic_drive_active":"已有集中门诊在进行，请先完成或停止当前计划","staff_relief_assignment_locked":"替班交接未结束，候补返回待命区后可调整该设备员工岗位"})
    names.merge({"staff_relief_disabled":"请先启用临床替班，再登记已聘候补","staff_in_relief_pool":"请先退出候补登记，再安排主岗","staff_relief_registered":"请先退出候补登记，再安排主岗","relief_staff_busy":"员工正在替班或交还岗位，请等实际交接完成","no_available_relief":"暂无角色、技能、状态和路线均合适的已登记候补","not_in_relief_pool":"该员工尚未登记为候补","missing_relief_skill":"候补尚未具备所需专科技能"})
    var copy:String=names.get(code,SelectionPanel.reason(code))
    if code not in names and copy==SelectionPanel.reason("unknown"):copy="条件未满足："+code
    var kind:String=str(detail.get("facility_kind",detail.get("kind","")))
    var subject:String=str(detail.get("subject",""))
    if code=="missing_facility" and _damaged_facility(snapshot,subject if subject!="" else kind)!="":copy="设备损坏，需维修"
    if subject!="":copy+=" · "+subject_name(subject,content)
    if kind!="":copy+=" · "+str(content.get("facilities",{}).get(kind,{}).get("name",kind))
    for key:String in ["role","resource","required","current","required_name"]:
        if detail.has(key):copy+=" · "+str(detail[key])
    if detail.has("missing"):copy+="："+reason_text(detail.missing,content,snapshot)
    if detail.has("reasons"):copy+="："+reason_text(detail.reasons,content,snapshot)
    return copy

static func _damaged_facility(snapshot:Dictionary,kind:String) -> String:
    var broken:=""
    for facility:Dictionary in snapshot.get("facilities",{}).values():
        if str(facility.get("kind",""))!=kind:continue
        if facility.get("status","")=="open" and int(facility.get("condition",100))>0:return ""
        if int(facility.get("condition",100))<=0:broken=str(facility.get("id",""))
    return broken

static func subject_name(subject:String,content:Dictionary) -> String:
    for group:String in ["facilities","roles","units","audits","diseases"]:
        if content.get(group,{}).has(subject):return str(content[group][subject].get("name",subject))
    for task:Dictionary in content.get("cases",{}).values():
        for step:Dictionary in task.get("steps",[]):
            if step.get("id","")==subject:return str(content.facilities.get(step.facility_kind,{}).get("name",step.facility_kind))
    return RESOURCE_NAMES.get(subject,subject)

func _effect_text(item:Dictionary) -> String:
    var names:Dictionary={"clinical":"完成对应病例诊疗","reception":"为真实到院患者完成接待登记","repair":"恢复磨损设备状态","floor_clean":"清洁地面并改善卫生","toilet_clean":"清洁如厕设施","filter":"过滤环境并改善卫生","tool_clean":"清洗工具","waste_sort":"分类清理医疗废物","waste_transport":"转运废物","temperature":"改善室内舒适度","ventilation":"改善通风","ups":"提供备用供电保障","power":"保障区域供电","fire":"建立消防准备","privacy":"保护访问与隐私","identity":"核对患者身份","ticket":"发放患者排队号","call":"改善叫号与队列调度","referral":"安排转诊调度","education":"开展患者教育","accessibility":"提供无障碍协助","roster":"排班交接并降低员工疲劳","toilet":"提供如厕支持","food":"提供餐食支持","water":"提供饮水支持","archive":"归档审核证据","research":"完成指定研究并解锁经营能力","training":"培训员工专科技能"}
    var result:String=names.get(str(item.get("handler","clinical")),"按病例或后勤任务完成指定工序")
    var output:Dictionary=item.get("output",{})
    var parts:Array[String]=[]
    for key:String in output:parts.append(subject_name(key,_content())+"%+d"%int(output[key]))
    if not parts.is_empty():result+="；每次完成："+"、".join(parts)
    return result

func filtered_facility_ids() -> Array:
    var result:Array=[]
    var content:Dictionary=_content()
    for id:String in content.get("facilities",{}):
        var item:Dictionary=content.facilities[id]
        var unit:String="operations" if id.begins_with("O") else str(item.get("unit_id",""))
        if _unit!="all" and unit!=_unit:continue
        if _search!="" and not (str(item.name)+" "+id+" "+str(content.get("units",{}).get(unit,{}).get("name",unit))).to_lower().contains(_search.to_lower()):continue
        result.append(id)
    result.sort()
    return result

func visible_facility_ids() -> Array:
    return _visible.duplicate()

func set_facility_filter(unit:String,search:String) -> void:
    _unit=unit
    _search=search
    _page=0
    show_section("facilities")

func _facilities_page() -> void:
    var directory_head:=HBoxContainer.new()
    directory_head.add_theme_constant_override("separation",9)
    body.add_child(directory_head)
    var directory_icon:=HospitalUiStyle.picture(HospitalA2Skin.icon("build",36),Vector2(36,36),0)
    directory_icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    directory_head.add_child(directory_icon)
    _text(directory_head,"设施目录",21)
    _text(body,"可用资金  "+HospitalHud.grouped_number(int(_snapshot.get("cash",0)))+" 币",17,HospitalUiStyle.INK)
    _text(body,"真实科室与公共设施；设备占格、房间大小、入口与操作位分开检查。",14,HospitalUiStyle.MUTED)
    var rows:Array=[{"id":"all","name":"全部科室与公共设施"}]
    for unit:Dictionary in _content().get("units",{}).values():rows.append({"id":unit.id,"name":unit.name})
    _choice("facility_unit","科室筛选",rows,_unit,func(value:String)->void:_unit=value;_page=0;_render_facility_cards())
    var search:=LineEdit.new()
    search.text=_search
    search.placeholder_text="搜索设施名称或科室"
    search.custom_minimum_size=Vector2(0,48)
    var search_normal:=HospitalA2Skin.style("paper",10)
    var search_focus:StyleBoxFlat=search_normal.duplicate()
    search_focus.border_color=Color("d95742")
    search_focus.set_border_width_all(2)
    search.add_theme_stylebox_override("normal",search_normal)
    search.add_theme_stylebox_override("focus",search_focus)
    search.add_theme_stylebox_override("read_only",search_normal)
    search.add_theme_color_override("font_color",HospitalUiStyle.INK)
    search.add_theme_color_override("font_placeholder_color",HospitalUiStyle.MUTED)
    search.add_theme_color_override("caret_color",HospitalUiStyle.TEAL)
    search.add_theme_color_override("selection_color",Color("d9574240"))
    body.add_child(search)
    controls.facility_search=search
    search.text_changed.connect(func(value:String)->void:_search=value;_page=0;_render_facility_cards())
    _facility_grid=GridContainer.new()
    _facility_grid.size_flags_horizontal=Control.SIZE_EXPAND_FILL
    _facility_grid.add_theme_constant_override("h_separation",8)
    _facility_grid.add_theme_constant_override("v_separation",8)
    body.add_child(_facility_grid)
    _configure_facility_grid()
    _page_label=_text(body,"")
    _button(footer,"facility_previous","上一页",func()->void:_page=maxi(0,_page-1);_render_facility_cards())
    _button(footer,"facility_next","下一页",func()->void:_page+=1;_render_facility_cards())
    _button(footer,"department_list","已建科室",func()->void:show_section("rooms"))
    _render_facility_cards()

func _configure_facility_grid() -> void:
    if section!="facilities" or not is_instance_valid(_facility_grid):return
    var available_width:float=panel.size.x-36
    _facility_grid.columns=3 if available_width>=466 else 2 if available_width>=310 else 1

func _ignore_facility_card_input(node:Node) -> void:
    if node is Control:node.mouse_filter=Control.MOUSE_FILTER_IGNORE
    for child:Node in node.get_children():_ignore_facility_card_input(child)

func _render_facility_cards() -> void:
    if not is_instance_valid(_facility_grid):return
    _clear(_facility_grid)
    for key:Variant in controls.keys():
        if str(key).begins_with("facility_card_"):controls.erase(key)
    var ids:Array=filtered_facility_ids()
    var pages:int=maxi(1,ceili(ids.size()/float(FACILITY_PAGE_SIZE)))
    _page=clampi(_page,0,pages-1)
    _visible=ids.slice(_page*FACILITY_PAGE_SIZE,mini(ids.size(),(_page+1)*FACILITY_PAGE_SIZE))
    for id:String in _visible:
        var item:Dictionary=_content().facilities[id]
        var available:bool=_facility_available(id)
        var selected:bool=id==_facility_id
        var card:=_button(_facility_grid,"facility_card_"+id,"",func()->void:_facility_id=id;show_section("facility"))
        card.custom_minimum_size=Vector2(150,232 if available else 264)
        card.set_meta("minimum_size",card.custom_minimum_size)
        card.set_meta("a2_selected",selected)
        HospitalA2Skin.button(card,"selected" if selected else "paper",16)
        card.tooltip_text=str(item.name)+" · "+str(item.cost)+"币\n"+("查看设施与真实建设选项" if available else _facility_unlock_copy(id))
        var box:=VBoxContainer.new()
        card.add_child(box)
        box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        box.offset_left=8;box.offset_right=-8;box.offset_top=8;box.offset_bottom=-8
        box.add_theme_constant_override("separation",3)
        var title:=_text(box,str(item.name),17)
        title.custom_minimum_size.y=42
        var texture:Texture2D=HospitalA2Skin.equipment_texture(id)
        var views:Array=item.get("views",[])
        if texture==null and not views.is_empty():texture=load(str(views[0].path)) as Texture2D
        var picture:=HospitalUiStyle.picture(texture,Vector2(0,84),0)
        picture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
        box.add_child(picture)
        _text(box,HospitalHud.grouped_number(int(item.cost))+" 币",21,Color("ae4935"))
        _text(box,"设备 %d×%d格"%[item.body_size[0],item.body_size[1]],14)
        var state:=_text(box,("✓ " if selected else "")+("已开放 · 查看建设" if available else "锁定 · "+_facility_unlock_copy(id)),13,HospitalUiStyle.TEAL if available else HospitalUiStyle.MUTED)
        state.tooltip_text=_facility_unlock_copy(id) if not available else "保留真实设施、派岗与安装流程"
        _ignore_facility_card_input(box)
    _page_label.text="%d 项 · 第%d/%d页"%[ids.size(),_page+1,pages]
    controls.facility_previous.disabled=_page==0
    controls.facility_next.disabled=_page+1>=pages

func _facility_page() -> void:
    var content:Dictionary=_content()
    if not content.get("facilities",{}).has(_facility_id):show_section("facilities");return
    var item:Dictionary=content.facilities[_facility_id]
    _heading(str(item.name))
    var facility_picture:=HospitalUiStyle.picture(HospitalA2Skin.equipment_texture(_facility_id),Vector2(0,112),0)
    facility_picture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    body.add_child(facility_picture)
    _copy(str(content.units.get(item.unit_id,{}).get("name",item.unit_id))+" · 本体%d×%d格 · %d币"%[item.body_size[0],item.body_size[1],item.cost])
    var role_names:Array[String]=[]
    for role:String in item.get("roles",[]):role_names.append(str(content.roles.get(role,{}).get("name",role)))
    _copy("岗位："+"、".join(role_names)+"\n标准工序 %.1f秒 · 每次耗材 %d币"%[item.duration_ticks/10.0,item.consumable_cost])
    _copy("设施作用："+_effect_text(item))
    _copy("病例指定的服务时间、人数和耗材以当前任务步骤为准。")
    var installed_count:int=0
    for installed:Dictionary in _snapshot.get("facilities",{}).values():
        if installed.kind!=_facility_id:continue
        installed_count+=1
        if installed_count<=4:_facility_staffing(str(installed.id))
    if not _facility_available(_facility_id):
        _copy(_facility_unlock_copy(_facility_id)+"。完成当前阶段目标后提交阶段考核。",Color("ab5145"))
        _button(footer,"facility_goals","查看阶段目标",func()->void:show_section("cases"),true)
        _button(footer,"facility_back","返回设施",func()->void:show_section("facilities"))
        return
    var rooms:Array=[]
    for room:Dictionary in _snapshot.rooms.values():
        if room.get("unit_id","")==item.unit_id:rooms.append({"id":room.id,"name":_room_name(room)})
    if not rooms.is_empty():
        if _selected_room=="":_selected_room=rooms[0].id
        _choice("install_room","安装到已有同科室房间",rooms,_selected_room,func(value:String)->void:_selected_room=value;_update_install_preview())
        _spin("install_x","设备左上角横格",0,0,23,func(_value:int)->void:_update_install_preview())
        _spin("install_y","设备左上角纵格",0,0,17,func(_value:int)->void:_update_install_preview())
        _spin("install_q","设备朝向（0/1/2/3）",0,0,3,func(_value:int)->void:_update_install_preview())
        _button(body,"pick_facility_cell","点房间地面选择设备位置",func()->void:picking_origin=true;focus_requested.emit(_selected("install_room"),"rooms"))
        _button(body,"place_facility","安装到所选房间",func()->void:_issue("place_facility",{"room_id":_selected("install_room"),"kind":_facility_id,"x":int(controls.install_x.value),"y":int(controls.install_y.value),"rotation":int(controls.install_q.value)}),true)
        _preview_label=_text(body,"")
        _update_install_preview()
    _button(footer,"new_department","新建科室",func()->void:_begin_layout(_facility_id),true)
    _button(footer,"facility_back","返回设施",func()->void:show_section("facilities"))

func _update_install_preview() -> void:
    for key:String in ["install_room","install_x","install_y","install_q","place_facility"]:
        if not controls.has(key):return
    var room:Dictionary=session.sim.snapshot().rooms.get(_selected("install_room"),{}).duplicate(true)
    if room.is_empty():return
    room.layout.facilities.append({"id":"__preview_facility__","kind":_facility_id,"x":int(controls.install_x.value),"y":int(controls.install_y.value),"rotation":int(controls.install_q.value)})
    var proposal:Dictionary={"room_id":room.id,"unit_id":room.unit_id,"origin_cell":int(room.origin_cell),"layout":room.layout}
    var result:Dictionary=FacilityLayout.preview(session.sim.snapshot(),proposal)
    controls.place_facility.disabled=not result.get("ok",false)
    if is_instance_valid(_preview_label):_preview_label.text="位置有效 · 按设备四向格线安装" if result.get("ok",false) else "请调整："+reason_text(result,_content(),_snapshot)
    if world!=null:
        if result.get("ok",false):world.show_campaign_preview(result.data.room)
        else:world.clear_campaign_preview()

func _begin_layout(kind:String) -> void:
    if not _facility_available(kind):
        _facility_id=kind
        show_section("facility")
        return
    _facility_id=kind
    _draft_unit=str(_content().facilities[kind].unit_id)
    _draft=FacilityLayout.default_layout(_draft_unit,kind,0).duplicate(true)
    _edit_room=""
    _draft_origin=49
    show_section("layout")

func edit_room(room_id:String) -> void:
    var room:Dictionary=session.sim.snapshot().rooms.get(room_id,{})
    if room.is_empty():return
    _edit_room=room_id
    _selected_room=room_id
    _draft_unit=room.unit_id
    _draft=room.layout.duplicate(true)
    _draft_origin=int(room.origin_cell)
    show_section("layout")

func _layout_page() -> void:
    _heading("调整科室" if _edit_room!="" else "建设科室")
    _copy(str(_content().units.get(_draft_unit,{}).get("name",_draft_unit))+" · 自定大小与多个入口，设备本体/操作位/检修位不能重叠。")
    _spin("room_width","房间宽（格）",int(_draft.width),3,22,func(value:int)->void:_draft.width=value;_update_layout_preview())
    _spin("room_height","房间深（格）",int(_draft.height),3,7,func(value:int)->void:_draft.height=value;_update_layout_preview())
    if _edit_room=="":
        _spin("room_origin_x","医院横格",_draft_origin%24,1,22,func(value:int)->void:_draft_origin=(_draft_origin/24)*24+value;_update_layout_preview())
        _spin("room_origin_y","医院纵格",_draft_origin/24,1,16,func(value:int)->void:_draft_origin=value*24+(_draft_origin%24);_update_layout_preview())
        _button(body,"pick_department_origin","点医院地面选择位置",func()->void:picking_origin=true;_feedback="请点医院空地选择房间左上角。")
    else:_copy("当前科室位置：横格%d · 纵格%d。可以在这里调整面积、设备朝向和多个门窗。"%[_draft_origin%24,_draft_origin/24])
    for i:int in range(_draft.facilities.size()):
        var placed:Dictionary=_draft.facilities[i]
        var def:Dictionary=_content().facilities[placed.kind]
        _text(body,str(def.name),18)
        _spin("layout_x_"+str(i),"设备横格",int(placed.x),0,21,func(value:int)->void:_draft.facilities[i].x=value;_update_layout_preview())
        _spin("layout_y_"+str(i),"设备纵格",int(placed.y),0,15,func(value:int)->void:_draft.facilities[i].y=value;_update_layout_preview())
        _spin("layout_q_"+str(i),"设备朝向（0/1/2/3）",int(placed.rotation),0,3,func(value:int)->void:_draft.facilities[i].rotation=value;_update_layout_preview())
    _opening_editor("doors","房门")
    _opening_editor("windows","窗户")
    _preview_label=_text(body,"",16,HospitalUiStyle.TEAL)
    _copy("科室地面 150+每格8币，设备另计。扩建只收增加面积和新增设备，缩小面积不退款；保留设备不会刷新磨损。")
    _button(footer,"confirm_department","确认调整" if _edit_room!="" else "确认建设",_confirm_layout,true)
    _button(footer,"cancel_department","返回科室" if _edit_room!="" else "返回设施",func()->void:show_section("rooms" if _edit_room!="" else "facility"))
    _update_layout_preview()

func _opening_editor(field:String,title:String) -> void:
    _text(body,title+"位置",18)
    for index:int in range(_draft.get(field,[]).size()):
        var opening:Dictionary=_draft[field][index]
        var line:=HBoxContainer.new();body.add_child(line)
        _text(line,{"north":"北侧","east":"东侧","south":"南侧","west":"西侧"}.get(str(opening.side),str(opening.side))+" · 第%d格"%(int(opening.offset)+1))
        _button(line,"remove_"+field+str(index),"移除",func()->void:_draft[field].remove_at(index);_render())
    var sides:Array=[{"id":"north","name":"北侧"},{"id":"east","name":"东侧"},{"id":"south","name":"南侧"},{"id":"west","name":"西侧"}]
    _choice(field+"_side","选择墙面",sides,"south",func(_value:String)->void:pass)
    _spin(field+"_offset","从该墙起点数第几格",1,1,maxi(int(_draft.width),int(_draft.height)))
    _button(body,"add_"+field,"添加"+title,func()->void:_draft[field].append({"side":_selected(field+"_side"),"offset":int(controls[field+"_offset"].value)-1});_render())

func choose_origin(cell:int) -> void:
    if cell<0:return
    if section=="facility" and controls.has("install_room"):
        var room:Dictionary=_snapshot.rooms.get(_selected("install_room"),{})
        if room.is_empty():return
        controls.install_x.value=cell%24-int(room.origin_cell)%24
        controls.install_y.value=cell/24-int(room.origin_cell)/24
        picking_origin=false
        _update_install_preview()
        return
    _draft_origin=cell
    picking_origin=false
    _render()

func _layout_proposal() -> Dictionary:
    var proposal:Dictionary={"unit_id":_draft_unit,"origin_cell":_draft_origin,"layout":_draft.duplicate(true),"rotation":0}
    if _edit_room!="":proposal.room_id=_edit_room
    return proposal

func _update_layout_preview() -> void:
    if not is_instance_valid(_preview_label):return
    var state:=ClinicState.new()
    state.data=session.sim.snapshot()
    _last_preview=FacilityLayout.preview(state,_layout_proposal())
    var ok:bool=_last_preview.get("ok",false)
    _preview_label.text="布局有效 · 可确认" if ok else "请调整："+reason_text(_last_preview,_content(),_snapshot)
    if controls.has("confirm_department"):controls.confirm_department.disabled=not ok
    if world!=null:
        if ok:world.show_campaign_preview(_last_preview.get("data",{}).get("room",{}))
        else:world.clear_campaign_preview()

func _confirm_layout() -> void:
    _update_layout_preview()
    if not _last_preview.get("ok",false):return
    if _edit_room!="":_issue("edit_department",{"room_id":_edit_room,"layout":_draft.duplicate(true)})
    else:_issue("build_department",{"unit_id":_draft_unit,"origin_cell":_draft_origin,"layout":_draft.duplicate(true)})

func _room_name(room:Dictionary) -> String:
    return str(_content().get("units",{}).get(room.get("unit_id",""),{}).get("name","科室"))+" · "+str(room.id).get_slice("_",1)

func _rooms_page() -> void:
    _heading("已建科室与设备")
    if _snapshot.rooms.is_empty():_copy("还没有科室。先从设施目录选择当前病例需要的设备。")
    for room:Dictionary in _snapshot.rooms.values():
        _text(body,_room_name(room),19)
        var room_id:String=room.id
        var row:=HFlowContainer.new();body.add_child(row)
        _button(row,"edit_"+room_id,"编辑大小与门窗",func()->void:edit_room(room_id))
        _button(row,"locate_"+room_id,"定位",func()->void:focus_requested.emit(room_id,"rooms"))
        _button(row,"remove_"+room_id,"撤除空科室",func()->void:_issue("remove_room",{"room_id":room_id}))
        for facility:Dictionary in _snapshot.facilities.values():
            if facility.room_id!=room_id:continue
            var id:String=facility.id
            var definition:Dictionary=_content().facilities[facility.kind]
            _copy(str(definition.name)+" · 状态 "+phase_name(str(facility.status))+" · 完好度%d%% · 使用%d次"%[facility.condition,facility.uses])
            _facility_staffing(id)
            var actions:=HFlowContainer.new();body.add_child(actions)
            var closed_value:bool=str(facility.status)=="closed"
            _button(actions,"close_"+id,"重新开放" if closed_value else "关停",func()->void:_issue("reopen_facility" if closed_value else "close_facility",{"facility_id":id}))
            _button(actions,"sell_"+id,"空闲出售（70%）",func()->void:_issue("remove_facility",{"facility_id":id}))
    _button(footer,"rooms_catalog","回设施目录",func()->void:show_section("facilities"),true)

func _next_case_id() -> String:
    var ids:Array=session.level_data().get("case_ids",[])
    var index:int=int(_snapshot.get("campaign",{}).get("wave_index",0))
    return str(ids[index]) if index>=0 and index<ids.size() else ""

func _case_reasons(id:String) -> Array:
    if id=="":return []
    var state:=ClinicState.new()
    state.data=session.sim.snapshot()
    if session.is_long_campaign():return LongCampaignClinical.instance_readiness(state,session.catalog,id)
    return CampaignClinicalFlow.case_readiness(state,session.catalog,id)

func _cases_page() -> void:
    if session.is_long_campaign():
        _long_cases_page()
        return
    var content:Dictionary=_content()
    var campaign:Dictionary=_snapshot.campaign
    var level:Dictionary=session.level_data()
    _heading(str(level.name))
    _copy(str(level.get("description","")))
    _copy("病例任务 %d/%d · 当前批次%s"%[campaign.get("completed_cases",[]).size(),level.get("case_ids",[]).size(),"进行中" if campaign.get("wave_active",false) else "待接收"])
    var id:String=str(campaign.get("current_case_id","")) if campaign.get("wave_active",false) else _next_case_id()
    if id!="" and content.cases.has(id):
        var task:Dictionary=content.cases[id]
        _text(body,str(task.title),21)
        _copy(str(content.diseases.get(task.disease_id,{}).get("name",task.disease_id))+" · 本批%d位患者 · 完整离院收入每人%d币（当前收费）"%[task.get("patient_count",1),CampaignExperience.clinical_income(_snapshot,int(task.income),int(campaign.get("price_percent",100)))])
        _copy(str(task.get("summary","")))
        var number:=1
        for step:Dictionary in task.steps:
            var definition:Dictionary=content.facilities[step.facility_kind]
            var roles:Array[String]=[]
            for role:String in step.get("roles",[]):roles.append(str(content.roles.get(role,{}).get("name",role)))
            _copy("%d. %s · %.1f秒 · 耗材%d币%s"%[number,definition.name,step.duration_ticks/10.0,step.cost," · "+"/".join(roles) if not roles.is_empty() else ""])
            number+=1
        if not campaign.get("wave_active",false):
            _case_stock(task)
        var reasons:Array=_case_reasons(id)
        _text(body,"批次进行中，请在患者清单查看真实进度。" if campaign.get("wave_active",false) else "准备完毕，可以接收。" if reasons.is_empty() else "尚缺："+reason_text(reasons,content,_snapshot),16,HospitalUiStyle.TEAL if reasons.is_empty() else Color("ab5145"))
        _button(footer,"prepare_case","准备当前病例",func()->void:_prepare_case(id),true)
        if not campaign.get("wave_active",false):_copy("接收后，若顶栏仍显示暂停，请点播放开始营业；每批完成会自动暂停，方便准备下一批。")
        var accept:=_button(footer,"accept_case","接收本批患者",func()->void:_issue("accept_case",{"case_id":id}),true)
        accept.disabled=not reasons.is_empty() or bool(campaign.get("wave_active",false)) or _snapshot.challenge.status!="running"
    else:
        _copy("本关病例批次已处理。完成本关后勤、审核与事件目标后查看结算。")
        _button(footer,"prepare_case","查看审核与事件",func()->void:show_section("growth"),true)
    _button(footer,"show_patients","在院患者",func()->void:show_section("patients"))
    _text(body,"本关任务清单",18)
    for case_id:String in level.get("case_ids",[]):
        var task:Dictionary=content.cases[case_id]
        var completed:bool=case_id in campaign.get("completed_cases",[])
        _copy(("✓ 已完成 · " if completed else "正在处理 · " if case_id==id else "待接收 · ")+str(task.title))
    _text(body,"本关后勤任务",18)
    for kind:String in level.get("operation_ids",[]):
        var definition:Dictionary=content.facilities[kind]
        var count:int=int(_snapshot.evidence.get("facilities",{}).get(kind,0))
        _copy(("✓ 已完成 · " if count>0 else "待完成 · ")+str(definition.name)+" · 真实使用%d次"%count)
        if count==0 and definition.get("kind","")!="patient":
            var selected:String=kind
            _button(body,"case_operation_"+kind,"准备"+str(definition.name),func()->void:_selected_operation=selected;show_section("operations"))
        elif count==0:_copy("此设施须由真实病例完成接待或诊疗，不能空转工单代替。")
    _copy("审核与营业事件在“成长与审核”查看，补齐缺项后可申请复核。96个病例任务分布于12职业关，病例任务与疾病种类分别计数。")

func _prepare_case(id:String) -> void:
    var task:Dictionary=_content().cases[id]
    var reasons:Array=_case_reasons(id)
    for reason:Variant in reasons:
        if reason is String:
            var mark:int=reason.find(":")
            var code:String=reason.substr(0,mark) if mark>=0 else reason
            var subject:String=reason.substr(mark+1) if mark>=0 else ""
            if code=="missing_facility" and _content().facilities.has(subject):
                if _damaged_facility(_snapshot,subject)!="":
                    _selected_operation="O11"
                    show_section("operations")
                    return
                _facility_id=subject
                show_section("facility")
                return
            if code=="missing_resource":_resource_focus=subject;show_section("resource");return
            if code=="missing_cash":show_section("finance");return
            if code=="missing_staff":show_section("staff");return
            if code=="path_blocked":show_section("rooms");return
            if code in ["phase_locked","facility_locked","case_locked","case_stage_locked"]:show_section("cases");return
        if reason is Dictionary:
            var detail:Dictionary=reason.get("data",reason)
            var kind:String=str(detail.get("facility_kind",detail.get("kind","")))
            if _content().facilities.has(kind):
                _facility_id=kind
                show_section("facility")
                return
    if not task.steps.is_empty():
        var kind:String=str(task.steps[0].facility_kind)
        if not _has_facility(kind):_facility_id=kind;show_section("facility");return
    show_section("staff")

func _has_facility(kind:String) -> bool:
    for facility:Dictionary in _snapshot.get("facilities",{}).values():
        if facility.kind==kind:return true
    return false

func _patients_page() -> void:
    _heading("在院病例与诊疗路线")
    _autonomy_controls("patient")
    var active:=0
    var patients:Array=_snapshot.patients.values()
    if session.is_long_campaign():
        patients=[]
        for id:String in _snapshot.campaign.get("live_patient_ids",[]):
            if _snapshot.patients.has(id):patients.append(_snapshot.patients[id])
    var focused:Dictionary=_snapshot.patients.get(_focus_patient,{})
    if not focused.is_empty() and focused in patients:
        patients.erase(focused);patients.push_front(focused)
        _copy("经营方案关注的患者已排在最前。",HospitalUiStyle.TEAL)
    for patient:Dictionary in patients:
        if patient.phase in ["left","abandoned"]:continue
        active+=1
        var case_data:Dictionary=_content().cases.get(patient.get("case_id",""),{})
        var identity:=HBoxContainer.new()
        identity.add_theme_constant_override("separation",12)
        body.add_child(identity)
        var portrait:TextureRect=HospitalUiStyle.picture(SceneArtLibrary.actor_portrait(patient,false,int(_snapshot.get("appearance_seed",0))),Vector2(66,66))
        portrait.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
        portrait.size_flags_vertical=Control.SIZE_SHRINK_BEGIN
        identity.add_child(portrait)
        var description:=VBoxContainer.new()
        description.size_flags_horizontal=Control.SIZE_EXPAND_FILL
        identity.add_child(description)
        _text(description,"患者"+str(patient.id).get_slice("_",1)+" · "+str(_content().diseases.get(patient.disease_id,{}).get("name",patient.disease_id)),19)
        _text(description,"当前："+phase_name(str(patient.phase))+" · 累计等候%.1f秒"%(patient.get("wait_ticks",0)/10.0),16,HospitalUiStyle.MUTED)
        _clinical_patient_controls(patient)
        _patient_need_controls(patient)
        if str(patient.get("wait_reason",""))!="":_copy("等待原因："+reason_text({"code":patient.wait_reason},_content(),_snapshot),Color("ab5145"))
        var steps:Array=patient.get("steps",case_data.get("steps",[]))
        var cursor:int=int(patient.get("step_index",0))
        for index:int in range(steps.size()):
            var step:Dictionary=steps[index]
            var status:String="已完成" if index<cursor else "当前" if index==cursor else "待进行"
            _copy(status+" · "+str(_content().facilities.get(step.facility_kind,{}).get("name",step.facility_kind)))
        var wait_reason:String=str(patient.get("wait_reason",""))
        if wait_reason.begins_with("missing_resource:"):
            var key:String=wait_reason.trim_prefix("missing_resource:")
            _button(body,"patient_stock_"+str(patient.id),"补给"+resource_label(key),func()->void:_resource_focus=key;show_section("resource"))
        if patient.phase=="care_service":_copy("本次服务 %.1f / %.1f秒"%[patient.get("service_work",0)/10.0,patient.get("service_needed",0)/10.0])
        var id:String=patient.id
        _button(body,"patient_locate_"+id,"定位患者",func()->void:focus_requested.emit(id,"patients"))
    if active==0:
        if session.is_long_campaign():_copy("目前没有在院患者。"+_intake_copy(LongCampaign.goals(_snapshot,session.catalog)))
        else:_copy("目前没有在院患者。准备当前病例后，主动接收本批患者。")
    _button(footer,"patients_cases","返回病例任务",func()->void:show_section("cases"),true)

static func phase_name(phase:String) -> String:
    return {"care_queue":"等待诊疗","moving_care":"前往设施","care_service":"正在诊疗","waiting_support":"等待后勤工序","moving_exit":"完成后离院中","left":"已实际离院","abandoned":"已放弃","idle":"待派工","moving":"前往岗位","serving":"服务中","working":"工单处理中","walking":"前往工作点","queued":"工单排队","blocked":"等待条件","done":"已完成","open":"开放","closed":"已关停","broken":"需要维修"}.get(phase,phase)

func _staff_page() -> void:
    var content:Dictionary=_content()
    _heading("招聘与岗位安排")
    _text(body,"岗位与短休概览",19)
    var staffing:Dictionary=StaffingInsights.overview(_snapshot,session.catalog)
    _copy("补给短休及返岗中 %d人；临时离岗仍保留原岗位。"%int(staffing.resting_count))
    for summary:String in staffing.facility_summaries:_copy(summary)
    _autonomy_controls("staff")
    _copy("员工 %d / %d · 招聘后为实际设施分配岗位。服务、预约或后勤工单完成交接前不能调走人员。"%[_snapshot.staff.size(),session.level_data().max_staff])
    if CampaignExperience.enabled(_snapshot):_copy("已派岗员工短休或返岗时主岗仍保留；没有合资格候补实际到岗时，对应岗位暂时停工。先查看员工和替班状态，再决定是否增员。")
    var roles:Array=[]
    for role:Dictionary in content.get("roles",{}).values():roles.append({"id":role.id,"name":"%s · 招聘%d · 日薪%d"%[role.name,role.hire_cost,CampaignExperience.daily_wage(_snapshot,int(role.daily_wage))]})
    if _hire_role=="" and not roles.is_empty():_hire_role=roles[0].id
    _choice("hire_role","招聘岗位",roles,_hire_role,func(value:String)->void:_hire_role=value)
    _button(body,"hire","招聘所选岗位",func()->void:_issue("hire",{"role":_selected("hire_role")}),true)
    var staff_rows:Array=[]
    for employee:Dictionary in _snapshot.staff.values():staff_rows.append({"id":employee.id,"name":str(content.roles.get(employee.role,{}).get("name",employee.role))+" "+str(employee.id).get_slice("_",1)+" · "+phase_name(str(employee.get("status","idle")))})
    if staff_rows.is_empty():_staff_relief_controls({});return
    if not _snapshot.staff.has(_selected_staff):_selected_staff=staff_rows[0].id
    _choice("assign_staff","选择员工",staff_rows,_selected_staff,func(value:String)->void:_selected_staff=value;_render())
    var employee:Dictionary=_snapshot.staff.get(_selected_staff,{})
    _staff_relief_controls(employee)
    var portrait:TextureRect=HospitalUiStyle.picture(SceneArtLibrary.actor_portrait(employee,true,int(_snapshot.get("appearance_seed",0))),Vector2(78,78))
    portrait.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
    body.add_child(portrait)
    var skills:Array[String]=[]
    for unit:String in employee.get("skills",[]):skills.append(str(content.units.get(unit,{}).get("name",unit)))
    _copy("主岗："+str(_content().facilities.get(_snapshot.facilities.get(employee.get("facility_id",""),{}).get("kind",""),{}).get("name","未派主岗"))+" · 疲劳 "+str(employee.get("fatigue",0))+" · 专科技能 "+("、".join(skills) if not skills.is_empty() else "尚无"))
    if CampaignPeople.enabled(_snapshot):
        _copy("心情 %d / 100 · 实际日薪%d币 · 薪资%d%%"%[int(employee.morale),CampaignPeople.staff_daily_wage(_snapshot,session.catalog,employee),int(employee.wage_percent)],HospitalUiStyle.TEAL)
        if CampaignExperience.enabled(_snapshot):
            _copy("空闲时可到饮水/便食设施补给短休，实际使用后恢复心情与疲劳；有合资格候补真实到岗时可临时覆盖临床岗位。补给点应就近可达。")
            var rest:Dictionary=employee.get("rest_activity",{})
            if not rest.is_empty():
                var event:Dictionary=_snapshot.campaign.get("staff_rest_events",{}).get(rest.get("event_id",""),{})
                _copy("当前短休："+str({"walking":"前往补给点","using":"正在补给短休","returning":"返回原岗位"}.get(event.get("state",""),"交接中")),HospitalUiStyle.TEAL)
                var detail:Dictionary=StaffingInsights.employee(_snapshot,str(employee.id))
                _copy(str(detail.label)+(" · 离岗已%.1f秒"%(float(detail.elapsed_ticks)/10.0) if int(detail.elapsed_ticks)>=0 else ""))
                if int(detail.remaining_use_ticks)>0:_copy("本次补给还需%.1f秒，之后仍需返回岗位。"%(float(detail.remaining_use_ticks)/10.0))
                if int(detail.get("remaining_route_ticks",-1))>=0:_copy(str(detail.route_estimate_label))
            var rest_row:=HFlowContainer.new();body.add_child(rest_row)
            for need:String in ["water","food"]:
                var selected_need:String=need
                var rest_sid:String=employee.id
                var rest_button:=_button(rest_row,"rest_"+rest_sid+"_"+need,"安排饮水短休" if need=="water" else "安排便食短休",func()->void:_issue("request_staff_rest",{"staff_id":rest_sid,"need":selected_need}))
                rest_button.disabled=CampaignCommands._staff_busy(employee)
        else:_copy("心情低于40时，空闲疲劳恢复速度减半；安排工作和加薪时请留意持续负荷。")
        var request:Dictionary=employee.get("salary_request",{})
        if request.get("status","")=="pending":_copy("员工诉求：希望调整薪酬。忙碌与欠薪会影响心情，加薪计入之后的真实工资。",Color("ab5145"))
        if int(employee.wage_percent)<150:
            var sid:String=employee.id
            var next_percent:int=int(employee.wage_percent)+10
            _button(body,"raise_"+sid,"调整为%d%%日薪"%next_percent,func()->void:_issue("set_staff_wage",{"staff_id":sid,"percent":next_percent}))
    var facilities:Array=[]
    for facility:Dictionary in _snapshot.facilities.values():
        var definition:Dictionary=content.facilities[facility.kind]
        if employee.get("role","") in definition.get("roles",[]) or employee.get("role","")==definition.get("role",""):
            facilities.append({"id":facility.id,"name":str(definition.name)+" · "+_room_name(_snapshot.rooms[facility.room_id])})
    if not facilities.is_empty():
        _choice("assign_facility","可匹配设备岗位",facilities,str(employee.get("facility_id","")),func(_value:String)->void:pass)
        var assign_button:Button=_button(body,"assign","派往所选设施",func()->void:_issue("assign",{"staff_id":_selected("assign_staff"),"facility_id":_selected("assign_facility")}),true)
        assign_button.disabled=CampaignCommands._staff_busy(employee) or bool(StaffingInsights.relief(_snapshot,str(employee.id)).registered) or StaffRelief.assignment_locked(_snapshot,employee)
    else:_copy("尚无该岗位匹配的已建设施，请先建设或选择另一岗位。")
    var row:=HFlowContainer.new();body.add_child(row)
    var unassign_button:Button=_button(row,"unassign","撤回待派工",func()->void:_issue("unassign",{"staff_id":_selected("assign_staff")}))
    var dismiss_button:Button=_button(row,"dismiss_staff","解聘闲置员工",func()->void:_issue("dismiss",{"staff_id":_selected("assign_staff")}))
    var locked:bool=CampaignCommands._staff_busy(employee) or bool(StaffingInsights.relief(_snapshot,str(employee.id)).registered) or StaffRelief.assignment_locked(_snapshot,employee)
    unassign_button.disabled=locked;dismiss_button.disabled=locked
    _button(footer,"staff_growth","培训与成长",func()->void:show_section("growth"))
    _button(footer,"staff_facilities","设施目录",func()->void:show_section("facilities"))

func _staff_relief_controls(employee:Dictionary) -> void:
    if not CampaignPeople.autonomy_enabled(_snapshot):return
    _text(body,"员工替班与候补登记",19)
    _copy("临床员工短休时，由已聘用并登记待命的同职候补前往补位。原员工主岗保留；候补需要对应技能与通畅的到岗路线。")
    var configured:bool=StaffRelief.configured(_snapshot)
    var enabled:bool=StaffRelief.enabled(_snapshot)
    var toggle:Button=_button(body,"staff_relief_toggle","停用员工替班，完成已有交接" if enabled else "启用员工替班",func()->void:_issue("set_staff_relief",{"enabled":not enabled}),true)
    toggle.disabled=_snapshot.challenge.status!="running"
    _copy("停用后，候补会完成手头工作并交还岗位。尚在路上的候补到岗后才能接手工作。")
    var operations_enabled:bool=StaffRelief.operations_enabled(_snapshot)
    var operations_toggle:Button=_button(body,"staff_relief_operations_toggle","关闭普通后勤替班" if operations_enabled else "启用普通后勤替班",func()->void:_issue("set_staff_relief_operations",{"enabled":not operations_enabled}))
    operations_toggle.disabled=not configured or not enabled or _snapshot.challenge.status!="running"
    _copy("后勤替班可处理普通物流、消毒供应和维修等工单。接待、教学、研究、排班及患者专属医技工单仍按原队伍执行。")
    var detail:Dictionary=StaffingInsights.relief(_snapshot,str(employee.get("id","")))
    if not employee.is_empty():
        _copy("所选员工：员工"+str(employee.get("id","")).trim_prefix("staff_")+" · "+str(_content().roles.get(str(employee.get("role","")),{}).get("name",employee.get("role",""))),HospitalUiStyle.TEAL)
        if StaffRelief.assignment_locked(_snapshot,employee):_copy("该设备正在交班，候补返回待命区后可调整员工岗位；原员工仍可正常服务。")
        var destination:Dictionary=_snapshot.facilities.get(str(detail.facility_id),{})
        var name:String=str(_content().facilities.get(str(destination.get("kind","")),{}).get("name",""))
        _copy(str(detail.label)+(" · "+name if name!="" and detail.active else ""),HospitalUiStyle.TEAL)
    var registered:bool=bool(detail.registered)
    var sid:String=str(employee.get("id",""))
    var reserve:Button=_button(body,"staff_relief_reserve","退出所选员工候补登记" if registered else "将所选员工登记为候补",func()->void:_issue("set_staff_relief_reserve",{"staff_id":sid,"enabled":not registered}))
    var eligible:bool=configured and not employee.is_empty() and employee.get("facility_id","")=="" and not CampaignCommands._staff_busy(employee) and int(employee.get("move_progress",0))==0
    reserve.disabled=not eligible or _snapshot.challenge.status!="running"
    if not configured:_copy("先启用员工替班，再选择闲置员工登记为候补。")
    elif not eligible:_copy("候补登记只用于已聘、未派主岗且没有服务、预约、工单、培训、短休、替班或跨格移动的员工。")
    elif registered:_copy("已登记待命。需要安排固定主岗或解聘时，先退出候补登记；替班中须等实际交接完成。")
    else:_copy("登记不会改变工资或技能；角色或专科技能不匹配、状态欠佳、路线不通时仍不能替班。")

func _operations_page() -> void:
    var content:Dictionary=_content()
    _heading("后勤工单与资源")
    _resources()
    _stock_forecast()
    _button(body,"stock_help","补给与生产来源",func()->void:show_section("resource"))
    var facilities:Array=[]
    for definition:Dictionary in content.facilities.values():
        if definition.get("kind","patient")!="patient":facilities.append({"id":definition.id,"name":definition.name})
    if _selected_operation=="" and not facilities.is_empty():_selected_operation=facilities[0].id
    _choice("operation_kind","选择后勤工序",facilities,_selected_operation,func(value:String)->void:_selected_operation=value;_render())
    if _selected_operation!="":
        var definition:Dictionary=content.facilities[_selected_operation]
        _copy(_effect_text(definition))
        var quote:Dictionary=CampaignBusiness.preview_terms(_snapshot,definition)
        _copy("新工单报价：%d币 · 基础用时%.1f秒（物流研究在开工时结算）。"%[int(quote.cost),float(quote.duration_ticks)/10.0])
        var estimate:Dictionary=OperatingInsights.operation(_snapshot,session.catalog,_selected_operation) if session.is_long_campaign() else {}
        if not estimate.is_empty():
            _copy("本单开工后可用资金约%d币（已扣临床预约，尚未扣其他排队工单和之后工资）。"%int(estimate.cash_after))
        var input:String=str(definition.get("input_resource",""))
        var quantity:int=int(definition.get("input_quantity",0))
        var stock:int=int(_snapshot.resources.get(input,0))
        if input!="":
            _copy("本次需要%s %d份，当前%d份。"%[resource_label(input),quantity,stock])
            _button(body,"operation_supply","查看"+resource_label(input)+"来源",func()->void:_resource_focus=input;show_section("resource"))
        var reasons:Array=CampaignOperations.readiness(_snapshot,session.catalog,_selected_operation)
        _copy("可以安排真实工单，营业运行后开始处理。" if reasons.is_empty() else "尚缺："+reason_text(reasons,content,_snapshot))
        var run:=_button(body,"run_operation","安排工单",func()->void:_issue("run_operation",{"facility_kind":_selected("operation_kind")}),true)
        run.disabled=not reasons.is_empty() or stock<quantity or int(_snapshot.cash)<int(quote.cost)
        if not estimate.is_empty():
            run.disabled=not reasons.is_empty() or int(estimate.missing_input)>0 or int(estimate.cash_after)<0
            if int(estimate.missing_input)>0 and stock>=quantity:_copy("部分库存已留给在院患者；请先补足可用库存。",Color("ab5145"))
            if int(estimate.cash_after)<0 and int(_snapshot.cash)>=int(quote.cost):_copy("剩余现金已预约用于在院诊疗，请先补足可用资金。",Color("ab5145"))
        if stock<quantity:_copy("先完成上游工序补齐库存，再安排本工序。",Color("ab5145"))
        if int(_snapshot.cash)<int(quote.cost):_copy("运行费用不足，可从财务调整资金。",Color("ab5145"))
        _button(body,"prepare_operation","准备所需设施",func()->void:_facility_id=_selected_operation;show_section("facility"))
        if session.is_long_campaign():
            var output:Dictionary=definition.get("output",{})
            var handler:String=str(definition.get("handler",""))
            var threshold:bool=output.is_empty() and handler in ["repair","floor_clean","toilet_clean","filter","tool_clean"]
            if output.is_empty() and not threshold:_copy("这项管理工序按需手动安排；没有库存或维护阈值，不开启自动化。")
            else:
                var automation:Dictionary=_snapshot.campaign.get("automation",{}).get(_selected_operation,{})
                var enabled:bool=bool(automation.get("enabled",false))
                var purpose:String="设备状态低于阈值时安排维修" if threshold and handler=="repair" else "卫生低于阈值时安排清洁" if threshold else "产出库存低于目标时安排补给"
                _copy("自动工单："+("已开启" if enabled else "已关闭")+"。"+purpose+"，仍需真实人员、费用与投入物。")
                var label:String="设备状态阈值（1–100）" if threshold and handler=="repair" else "卫生阈值（1–100）" if threshold else "目标库存（每种产出，1–1000）"
                var draft_key:String="auto_target:"+_selected_operation
                _spin("operation_auto_target",label,int(_policy_drafts.get(draft_key,automation.get("target",80 if threshold else 6))),1,100 if threshold else 1000,func(value:int)->void:_policy_drafts[draft_key]=value)
                _button(body,"set_operation_auto","关闭自动工单" if enabled else "开启自动工单",func()->void:_issue("set_operation_auto",{"facility_kind":_selected("operation_kind"),"enabled":not enabled,"target":int(controls.operation_auto_target.value)}),true)
    var active:Array=[]
    var done:Array=[]
    for order:Dictionary in _snapshot.work_orders.values():
        if order.status=="done":done.append(order)
        else:active.append(order)
    _text(body,"进行中工单 %d · 已完成 %d"%[active.size(),done.size()],18)
    var displayed:Array=active+done.slice(maxi(0,done.size()-6),done.size())
    for order:Dictionary in displayed.slice(0,18):
        _copy(str(content.facilities.get(order.facility_kind,{}).get("name",order.facility_kind))+" · "+phase_name(str(order.status))+" · %.1f/%.1f秒"%[order.get("work",0)/10.0,order.get("needed",0)/10.0]+("\n"+reason_text({"code":order.reason},content,_snapshot) if str(order.get("reason",""))!="" else ""))
    _button(footer,"operations_growth","审核与事件",func()->void:show_section("growth"))

func _resources() -> void:
    var copies:Array[String]=[]
    for key:String in _snapshot.get("resources",{}):copies.append(resource_label(key)+" "+str(_snapshot.resources[key]))
    _copy(" · ".join(copies))

func resource_label(key:String) -> String:
    return str(RESOURCE_NAMES.get(key,key))

func resource_plan(key:String) -> Array:
    var result:Array=[]
    _trace_resource(key,[],{},result)
    return result

func _trace_resource(key:String,stack:Array,seen:Dictionary,result:Array) -> void:
    if key=="" or key in stack or seen.has(key):return
    var source:Dictionary={}
    for definition:Dictionary in _content().get("facilities",{}).values():
        if definition.get("kind","patient")=="patient":continue
        if int(definition.get("output",{}).get(key,0))>0:source=definition;break
    if source.is_empty():return
    var chain:Array=stack.duplicate()
    chain.append(key)
    var input:String=str(source.get("input_resource",""))
    if input!="":_trace_resource(input,chain,seen,result)
    seen[key]=true
    var quote:Dictionary=CampaignBusiness.preview_terms(_snapshot,source)
    result.append({"resource":key,"facility_kind":source.id,"facility_name":source.name,"input_resource":input,"input_quantity":int(source.get("input_quantity",0)),"output_quantity":int(source.output[key]),"cost":int(quote.cost),"duration_ticks":int(quote.duration_ticks),"roles":source.get("roles",[]).duplicate()})

func _case_stock(task:Dictionary) -> void:
    var required:Dictionary={}
    for step:Dictionary in task.get("steps",[]):
        var key:String=str(step.get("resource",""))
        if key!="":required[key]=int(required.get(key,0))+int(step.get("quantity",0))*int(task.get("patient_count",1))
    if required.is_empty():return
    _text(body,"本批库存核对",18)
    for key:String in required:
        var current:int=int(_snapshot.resources.get(key,0))
        _copy("%s：需%d份 / 现有%d份"%[resource_label(key),int(required[key]),current],HospitalUiStyle.TEAL if current>=int(required[key]) else Color("ab5145"))
        if current<int(required[key]):
            var resource:String=key
            _button(body,"case_resource_"+key,"准备"+resource_label(key),func()->void:_resource_focus=resource;show_section("resource"))

func _resource_page() -> void:
    _heading("补给 · "+resource_label(_resource_focus))
    _resource_estimate(_resource_focus)
    var plan:Array=resource_plan(_resource_focus)
    var next:Dictionary=_next_production_step(plan)
    _copy("补做下一步："+str(next.facility_name)+"  ↓ 查看完整工序与操作" if not next.is_empty() else "先完成真实病例，产生所需证据或物资 ↓")
    var rows:Array=[]
    for key:String in RESOURCE_NAMES:rows.append({"id":key,"name":resource_label(key)})
    _choice("resource_kind","准备哪种库存",rows,_resource_focus,func(value:String)->void:_resource_focus=value;_render();_reset_scroll_top())
    _copy("按下列真实工序从上游准备。库存足够时可以跳过补做；工单运行和产出需要营业时间，查看此页不会增加物资。")
    if _resource_focus in ["waste","sorted_waste"]:_copy("待处理医疗废物来自真实患者诊疗步骤完成。先完成病例，再用分类废物桶分类，最后以密闭废物转运车处理；不能空转医疗设备制造记录。")
    if plan.is_empty() and _resource_focus!="waste":_copy("该项没有可直接补做的生产工序；请查看病例或审核的具体处理要求。")
    var index:=1
    for row:Dictionary in plan:
        _text(body,"%d. %s"%[index,row.facility_name],19)
        var input:String=str(row.input_resource)
        var input_copy:String="无需上游物资" if input=="" else "消耗%s%d份，现有%d份"%[resource_label(input),row.input_quantity,_snapshot.resources.get(input,0)]
        _copy(input_copy+" → 产出%s%d份 · %.1f秒 · %d币"%[resource_label(row.resource),row.output_quantity,row.duration_ticks/10.0,row.cost])
        var names:Array[String]=[]
        for role:String in row.roles:names.append(str(_content().roles.get(role,{}).get("name",role)))
        _copy("岗位："+"、".join(names))
        var missing:Array=CampaignOperations.readiness(_snapshot,session.catalog,row.facility_kind)
        if not missing.is_empty():_copy("尚缺："+reason_text(missing,_content(),_snapshot),Color("ab5145"))
        var kind:String=row.facility_kind
        var actions:=HFlowContainer.new();body.add_child(actions)
        _button(actions,"resource_prepare_"+kind,"准备设备与岗位",func()->void:_facility_id=kind;show_section("facility"))
        var run:=_button(actions,"resource_run_"+kind,"运行此工序",func()->void:_issue("run_operation",{"facility_kind":kind}),true)
        run.disabled=not missing.is_empty() or int(_snapshot.cash)<int(row.cost) or (input!="" and int(_snapshot.resources.get(input,0))<int(row.input_quantity))
        if session.is_long_campaign():
            var estimate:Dictionary=OperatingInsights.operation(_snapshot,session.catalog,kind)
            run.disabled=not missing.is_empty() or int(estimate.cash_after)<0 or int(estimate.missing_input)>0
            if input!="":
                var raw:int=int(_snapshot.resources.get(input,0))
                _copy("%s可用%d份（库存%d，临床预约%d）。"%[resource_label(input),int(estimate.available_input),raw,maxi(0,raw-int(estimate.available_input))])
                if int(estimate.missing_input)>0:_copy("本工序还缺可用%s%d份，请先完成上游补给。"%[resource_label(input),int(estimate.missing_input)],Color("ab5145"))
            if int(estimate.cash_after)<0:_copy("扣除临床预约后，可用资金不足本单%d币费用。"%int(estimate.cost),Color("ab5145"))
        if input!="" and int(_snapshot.resources.get(input,0))<int(row.input_quantity):_copy("先完成上游工序补齐"+resource_label(input)+"。",Color("ab5145"))
        index+=1
    _text(body,"当前库存",18)
    _resources()
    _button(footer,"resource_orders","查看工单进度",func()->void:show_section("operations"))
    _button(footer,"resource_cases","回到当前病例",func()->void:show_section("cases"),true)

func _next_production_step(plan:Array) -> Dictionary:
    for index:int in range(plan.size()):
        var row:Dictionary=plan[index]
        var needed:int=1
        if index+1<plan.size() and plan[index+1].input_resource==row.resource:needed=int(plan[index+1].input_quantity)
        if int(_snapshot.resources.get(row.resource,0))<needed or index+1==plan.size():return row
    return {}

func _growth_page() -> void:
    var content:Dictionary=_content()
    var career:Dictionary=_snapshot.campaign
    var development:Dictionary=LongCampaign.development_effects(_snapshot) if session.is_long_campaign() else {}
    _heading("研究、培训与合规")
    _copy("本关病例 %d/%d · 已通关职业关 %d/12 · 声誉 %d"%[career.get("completed_cases",[]).size(),session.level_data().case_ids.size(),career.get("career",{}).get("completed_levels",[]).size(),career.get("reputation",50)])
    if session.is_long_campaign():_long_stage_summary(LongCampaign.goals(_snapshot,session.catalog))
    _text(body,"临床与后勤研究",19)
    var projects:Array=[]
    for project:Dictionary in content.get("projects",{}).values():projects.append({"id":project.id,"name":str(project.name)+" · "+str(project.cost)+"币"})
    if _selected_project=="" and not projects.is_empty():_selected_project=projects[0].id
    if not projects.is_empty():
        _choice("research_project","研究主题",projects,_selected_project,func(value:String)->void:_selected_project=value;_render())
        if session.is_long_campaign():_research_effect_copy(_selected_project,development)
        var completed:Array[String]=[]
        for project_id:String in career.get("research",[]):completed.append(str(content.projects.get(project_id,{}).get("name",project_id)))
        _copy("需要研究终端与匹配人员，付费后经过真实工作时间完成。已完成："+("、".join(completed) if not completed.is_empty() else "尚无"))
        var research_missing:Array=CampaignOperations.readiness(_snapshot,session.catalog,"O10")
        if not research_missing.is_empty():_copy("研究准备："+reason_text(research_missing,content,_snapshot))
        _growth_orders("research")
        _button(body,"start_research","开始所选研究",func()->void:_issue("start_research",{"project_id":_selected("research_project")}),true)
    _text(body,"专科技能培训",19)
    var staff:Array=[]
    for employee:Dictionary in _snapshot.staff.values():staff.append({"id":employee.id,"name":str(content.roles.get(employee.role,{}).get("name",employee.role))+" "+str(employee.id).get_slice("_",1)})
    var units:Array=[]
    for unit:Dictionary in content.units.values():
        if str(unit.id)!="operations":units.append({"id":unit.id,"name":unit.name})
    if not staff.is_empty():
        _choice("training_staff","参与员工",staff,_selected_staff,func(value:String)->void:_selected_staff=value;_render())
        _choice("training_unit","专科方向",units,_training_unit,func(value:String)->void:_training_unit=value;_render())
        _copy("培训180币，占用员工、教学设施与真实时间；服务和工单尚未交接时不能抽走员工。")
        if session.is_long_campaign():
            var training:Dictionary=development.get("training",{})
            _copy("匹配专科培训在对应临床岗位生效，临床服务用时减少%d%%；与临床效率研究均生效时合计减少%d%%。"%[int(training.get("clinical_discount_percent",0)),int(training.get("combined_clinical_discount_percent",0))])
            _copy("考核只统计仍在本关临床岗位、所学专科与岗位匹配的受训员工；专科覆盖按不同临床专科去重。离岗或专业不匹配不计入当前考核。")
        var training_missing:Array=CampaignOperations.readiness(_snapshot,session.catalog,"O09")
        if not training_missing.is_empty():_copy("教学准备："+reason_text(training_missing,content,_snapshot))
        for trained:Dictionary in career.get("training",[]):
            _copy("已完成：员工"+str(trained.get("staff_id","")).get_slice("_",1)+" · "+str(content.units.get(trained.get("unit_id",""),{}).get("name",trained.get("unit_id",""))))
        _growth_orders("training")
        _button(body,"start_training","安排培训",func()->void:_issue("start_training",{"staff_id":_selected("training_staff"),"unit_id":_selected("training_unit")}),true)
    else:_copy("请先招聘需要培训的员工。")
    _text(body,"本关审核",19)
    var audits:Array=[]
    for id:String in session.level_data().get("audit_ids",[]):audits.append({"id":id,"name":content.audits.get(id,{}).get("name",id)})
    if not audits.is_empty():
        if _selected_audit=="":_selected_audit=audits[0].id
        _choice("audit_kind","审核项目",audits,_selected_audit,func(value:String)->void:_selected_audit=value;_render())
        var audit:Dictionary=content.audits.get(_selected_audit,{})
        _copy("通过依据："+str(audit.get("pass_rule",""))+"\n检查条件："+_audit_requirements(audit.get("requirements",[]))+"\n当前结果："+("已通过" if career.get("audits",{}).get(_selected_audit,{}).get("passed",false) else "待申请或待补齐条件"))
        var missing:Array=CampaignOperations.audit_missing(_snapshot,session.catalog,_selected_audit)
        _copy("已具备申请条件。" if missing.is_empty() else "待补齐："+reason_text(missing,content,_snapshot),HospitalUiStyle.TEAL if missing.is_empty() else Color("ab5145"))
        _button(body,"request_audit","申请真实审核 / 复核",func()->void:_issue("request_audit",{"audit_id":_selected("audit_kind")}),true)
    _text(body,"营业事件",19)
    var events:Array=career.get("events",[])
    if events.is_empty():_copy("当前没有触发的营业事件。继续病例任务会按本关安排触发。")
    for event:Dictionary in events:
        _copy(str(event.get("name",event.id))+" · "+("已处理" if event.get("status","") in ["resolved","done"] else "待处理")+"\n处理所需："+str(content.facilities.get(event.get("facility_kind",""),{}).get("name",event.get("facility_kind",""))))
        var id:String=event.id
        var resolve:=_button(body,"resolve_"+id,"复核并处理事件",func()->void:_issue("resolve_event",{"event_id":id}))
        resolve.disabled=str(event.get("status","")) in ["resolved","done"]
    _button(footer,"growth_orders","查看真实工单",func()->void:show_section("operations"))
    _button(footer,"growth_cases","继续病例任务",func()->void:show_section("cases"),true)

func _growth_orders(handler:String) -> void:
    for order:Dictionary in _snapshot.get("work_orders",{}).values():
        if order.get("handler","")!=handler or order.get("status","")=="done":continue
        var name:String="研究" if handler=="research" else "培训"
        if handler=="research":name=str(_content().projects.get(order.get("project_id",""),{}).get("name",name))
        elif order.has("unit_id"):name+=" · "+str(_content().units.get(order.unit_id,{}).get("name",order.unit_id))
        _copy(name+" · "+phase_name(str(order.status))+" · %.1f/%.1f秒"%[order.get("work",0)/10.0,order.get("needed",0)/10.0])
        if str(order.get("reason",""))!="":_copy(reason_text(str(order.reason),_content(),_snapshot),Color("ab5145"))

func _audit_requirements(value:Variant) -> String:
    if value is Array:
        var result:Array[String]=[]
        for item:Variant in value:result.append(_audit_requirements(item))
        return "、".join(result)
    var text:String=str(value)
    return str(_content().get("facilities",{}).get(text,{}).get("name",{"facility":"必需设施","clinical":"完成实际诊疗","operations":"后勤工序","staff":"在岗人员"}.get(text,text)))

func _finance_page() -> void:
    _heading("经营账本与政策")
    _cash_planning()
    if CampaignExperience.enabled(_snapshot):
        _copy("诊疗收入在患者入院时锁定，之后调价不会改已有患者。工资、采购、维修和补给短休都计入实际经营成本。")
        var due:int=0
        for employee:Dictionary in _snapshot.staff.values():due+=CampaignPeople.staff_daily_wage(_snapshot,session.catalog,employee)
        _copy("下一经营日工资预算 %d币 · 请同时预留临床耗材、补给短休和维修费用。"%due,HospitalUiStyle.TEAL)
    _procurement_controls()
    var metrics:Dictionary=_snapshot.get("metrics",{})
    _copy("现金 %d币 · 已完成 %d人 · 累计收入 %d币"%[_snapshot.cash,metrics.get("completed",0),metrics.get("income",0)],HospitalUiStyle.INK)
    _copy("贷款余额 %d币 · 收费比例 %d%% · 声誉 %d"%[_snapshot.campaign.get("loan",0),_snapshot.campaign.get("price_percent",100),_snapshot.campaign.get("reputation",50)])
    if session.is_long_campaign():
        _copy("日利润已计入应付工资；补发不重复计日成本。累计经营盈余按已收已付现金统计。")
        _daily_operating_goal_copy()
        _operating_history()
        var unpaid:int=int(_snapshot.campaign.get("unpaid_wages",0))
        if unpaid>0:_copy("当前欠薪 %d币。后续工资结算时会尝试一并补发，请预留现金。"%unpaid,Color("ab5145"))
    var categories:Dictionary={}
    for entry:Dictionary in _snapshot.ledger_entries:
        var category:String=str(entry.get("category",""))
        categories[category]=int(categories.get(category,0))+int(entry.get("delta",entry.get("amount",0)))
    var names:Dictionary={"income":"实际离院收入","wages":"员工工资","fixed_cost":"固定支出","capital_build":"科室与设备","build":"科室与设备","hire":"招聘","sale":"出售退款","grant":"任务补助","repay":"偿还本金","operations":"后勤运行","capital_hire":"招聘","capital_refund":"出售退款","supplies":"物资采购","research":"研究","training":"培训","loan":"借入本金","loan_repay":"偿还本金","interest":"贷款利息","treatment_cost":"诊疗耗材","operation_cost":"后勤运行","mission_grant":"任务补助"}
    for category:String in categories:_copy(str(names.get(category,category))+"  %s%d币"%["+" if int(categories[category])>0 else "",categories[category]])
    _copy("借款单次1000–10000币，还款不超过当前本金；贷款本金与建设资金单独核算，实际每笔收入支出以账本为准。改变收费政策会影响后续病例的真实结算和相关经营条件。")
    _price=int(_policy_drafts.get("price_percent",_snapshot.campaign.get("price_percent",100)))
    _spin("price_percent","收费比例（75–150%）",_price,75,150,func(value:int)->void:_price=value;_policy_drafts["price_percent"]=value)
    _button(body,"set_price","应用收费政策",func()->void:_issue("set_price",{"percent":int(controls.price_percent.value)}),true)
    _spin("loan_amount","借款 / 还款金额",_loan_amount,1,10000,func(value:int)->void:_loan_amount=value)
    var row:=HFlowContainer.new();body.add_child(row)
    _button(row,"take_loan","申请借款",func()->void:_issue("take_loan",{"amount":int(controls.loan_amount.value)}))
    _button(row,"repay_loan","偿还贷款",func()->void:_issue("repay_loan",{"amount":int(controls.loan_amount.value)}))
    _button(footer,"finance_tasks","查看任务目标",func()->void:show_section("cases"),true)

func _facility_staffing(fid:String) -> void:
    var info:Dictionary=StaffingInsights.facility(_snapshot,session.catalog,fid)
    _copy(str(info.summary),HospitalUiStyle.TEAL if info.available_complete else HospitalUiStyle.MUTED)
    for cover:Dictionary in info.get("relief_rows",[]):
        _copy("主岗员工%s → 实际候补%s：%s"%[str(cover.owner_staff_id).trim_prefix("staff_"),str(cover.staff_id).trim_prefix("staff_"),str(cover.label)])
    var shown:int=0
    for row:Dictionary in info.unavailable:
        if shown>=3:break
        shown+=1
        _copy("员工"+str(row.staff_id).get_slice("_",1)+" · "+str(row.label))
    if not info.unavailable.is_empty():
        var selected:String=str(info.unavailable[0].staff_id)
        _button(body,"facility_staff_"+fid,"查看该设备员工状态",func()->void:_remember_origin(fid);_selected_staff=selected;show_section("staff"))

func _cash_planning() -> void:
    var funds:Dictionary=OperatingInsights.finance(_snapshot,session.catalog)
    if not funds.enabled:return
    _text(body,"资金安排",19)
    _copy("临床预约资金 %d币 · 当前可用 %d币。"%[int(funds.reserved_cash),int(funds.available_cash)])
    _copy("待开工工单 %d币（含临床支持%d币） · 欠薪 %d币。"%[int(funds.queued_cost),int(funds.queued_support_cost),int(funds.arrears)])
    _copy("下次工资 %d币 · 贷款利息 %d币，约%.1f游戏分钟后结算。"%[int(funds.payroll),int(funds.interest),float(funds.until_day_ticks)/600.0])
    _copy("已知支出后余量 %d币。"%int(funds.safety_balance),HospitalUiStyle.TEAL if int(funds.safety_balance)>=0 else Color("ab5145"))
    _copy("按排队订单全部开工估算；新诊疗、维修和之后的补货还需另留资金。")

func _operating_history() -> void:
    var review:Dictionary=OperatingInsights.day_review(_snapshot,session.catalog)
    if not review.enabled:return
    var lost:Dictionary=review.latest_break
    if not lost.is_empty():_copy("第%d日曾中断连续%d日：%s。"%[int(lost.index),int(lost.previous_streak),"；".join(lost.missing)],Color("ab5145"))
    _button(body,"toggle_day_history","收起经营日历史" if _day_history_expanded else "查看最近7个经营日",func()->void:_day_history_expanded=not _day_history_expanded;_render())
    if not _day_history_expanded:return
    _text(body,"近期完整经营日",19)
    for interruption:Dictionary in review.get("history_breaks",[]):
        if not lost.is_empty() and int(interruption.index)==int(lost.index):continue
        _copy("历史记录：第%d日曾中断连续%d日：%s。"%[int(interruption.index),int(interruption.previous_streak),"；".join(interruption.missing)])
    if review.rows.is_empty():_copy("尚无完整经营日；今日不提前判定。")
    for row:Dictionary in review.rows:
        var state:String={"passed":"达标","failed":"未达标","previous":"跨阶段，不计本阶段","partial":"未完整，不计达标","reference":"经营参考"}.get(row.status,"经营参考")
        _copy("第%d日 · %s%s · 利润%d币 · 治愈%d人 · %s"%[int(row.index),"历史 · " if row.get("historical",false) else "",state,int(row.profit),int(row.completed),"治愈率%d%%"%int(row.quality) if int(row.quality)>=0 else "无有效结案"],HospitalUiStyle.TEAL if row.status=="passed" else HospitalUiStyle.MUTED)
        if not row.missing.is_empty():_copy("差项："+"；".join(row.missing))

func _stock_insights() -> Dictionary:
    var stamp:String=str(session.sim.get_instance_id())+":"+str(_snapshot.get("level_id",""))+":"+str(_snapshot.get("tick",0))+":"+str(_snapshot.get("command_sequence",0))
    if stamp!=_stock_stamp:
        _stock_projection=OperatingInsights.resources(_snapshot,session.catalog)
        _stock_stamp=stamp
    return _stock_projection

func _resource_estimate(key:String) -> void:
    var stock:Dictionary=_stock_insights().get(key,{})
    if stock.is_empty():return
    _copy("可用库存 %d份 · 临床预约 %d份 · 已入库 %d份。"%[int(stock.available),int(stock.reserved),int(stock.stock)],HospitalUiStyle.TEAL)
    _copy("在制待交付 %d份，含排队工单；完成前不计入可用库存。"%int(stock.pending_output))
    if int(stock.runway_ticks)<0:_copy("最近没有实际消耗样本，暂不能估算续航。")
    else:_copy("最近%.1f游戏分钟消耗%d份；按此节奏约可支持%.1f游戏分钟。"%[float(stock.sample_ticks)/600.0,int(stock.consumed),float(stock.runway_ticks)/600.0])
    _copy("续航是历史消耗估算；扩容、恢复接诊或调整排班后会变化。")

func _stock_forecast() -> void:
    if not session.is_long_campaign():return
    _text(body,"库存续航（估算）",19)
    var stocks:Dictionary=_stock_insights()
    var keys:Array=[]
    for key:String in stocks:
        if int(stocks[key].consumed)>0 and key not in ["waste","sorted_waste"]:keys.append(key)
    keys.sort_custom(func(a:String,b:String)->bool:return int(stocks[a].runway_ticks)<int(stocks[b].runway_ticks) if int(stocks[a].runway_ticks)!=int(stocks[b].runway_ticks) else a<b)
    if keys.is_empty():_copy("最近没有实际消耗样本。先营业，再按当前节奏估算。")
    for key:String in keys.slice(0,3):
        var stock:Dictionary=stocks[key]
        _copy("%s：可用%d份 · 估算约%.1f游戏分钟。"%[resource_label(key),int(stock.available),float(stock.runway_ticks)/600.0])
        var resource:String=key
        _button(body,"stock_runway_"+key,"查看"+resource_label(key)+"补给",func()->void:_remember_origin(resource);_resource_focus=resource;show_section("resource"))
    _copy("按最近实际消耗估算，排队或在制产出尚未入库；恢复接诊后需重新留意用量。")

func _facility_available(kind:String) -> bool:
    return not session.is_long_campaign() or LongCampaign.facility_unlocked(_snapshot if not _snapshot.is_empty() else session.sim.snapshot(),session.catalog,kind)

func _facility_unlock_copy(kind:String) -> String:
    var names:Array[String]=["开业","稳定经营","扩建专科","综合考核"]
    var ids:Array=session.level_data().get("case_ids",[])
    for index:int in range(ids.size()):
        var task:Dictionary=_content().cases.get(ids[index],{})
        for step:Dictionary in task.get("steps",[]):
            if str(step.get("facility_kind",""))==kind:return names[mini(3,index/2)]+"阶段开放"
    return "本关尚未开放此临床设施"

func _daily_operating_goal_copy() -> void:
    if not session.is_long_campaign():return
    if bool(_snapshot.campaign.get("course_complete",false)):
        _copy("本院连续经营日考核已通过；继续经营不会重新要求本阶段连续日。")
        return
    var level:Dictionary=session.level_data()
    var phases:Array=level.get("phases",[])
    if phases.is_empty():return
    var phase:Dictionary=phases[clampi(int(_snapshot.campaign.get("phase_index",0)),0,phases.size()-1)]
    var required_days:int=int(phase.get("profitable_days",0))
    var min_profit:int=int(phase.get("min_daily_profit",0))
    var min_cures:int=int(phase.get("min_daily_cures",0))
    var min_quality:int=int(phase.get("cure_rate",0))
    if required_days>0:
        _copy("每日达标线：利润 ≥%d币 · 治愈 ≥%d人 · 当日治愈率 ≥%d%%。"%[min_profit,min_cures,min_quality],HospitalUiStyle.TEAL)
        _copy("须连续%d个完整经营日三项都达标。任一完整日未达标，连续计数重新开始；今日未结束不判失败，跨阶段的未完整经营日不计入。"%required_days)
    else:_copy("本阶段不要求连续达标经营日；完整日经营记录仅作参考。")
    var days:Array=_snapshot.campaign.get("day_records",[])
    var recent:Dictionary={}
    var day_ticks:int=maxi(1,int(level.get("day_ticks",6000)))
    var phase_started:int=int(_snapshot.campaign.get("phase_started_tick",0))
    for index:int in range(days.size()-1,-1,-1):
        var day:Dictionary=days[index]
        var start:int=int(day.get("start_tick",-1))
        var end:int=int(day.get("end_tick",-1))
        if start<phase_started or end>int(_snapshot.tick) or end-start!=day_ticks:continue
        recent=day
        break
    if recent.is_empty():
        _copy("本阶段尚未形成完整经营日；今日与跨阶段的未完整经营日不计失败。")
        return
    var profit:int=int(recent.get("profit",0))
    var completed:int=int(recent.get("completed",0))
    var abandoned:int=int(recent.get("abandoned",0))
    var ended:int=completed+abandoned
    var quality:int=int(completed*100/ended) if ended>0 else 0
    var quality_copy:String="当日治愈率 %d%%"%quality if ended>0 else "当日暂无有效结案"
    _copy("最近完整经营日：第%d日 · 利润 %d币 · 治愈 %d人 · %s（弃诊%d人）。"%[int(recent.get("index",0)),profit,completed,quality_copy,abandoned])
    if required_days<=0:return
    var missing:Array[String]=[]
    if profit<min_profit:missing.append("利润不足（%d / %d币）"%[profit,min_profit])
    if completed<min_cures:missing.append("治愈不足（%d / %d人）"%[completed,min_cures])
    if ended<=0:missing.append("当日无有效结案，不能计作达标日")
    elif quality<min_quality:missing.append("治愈率不足（%d%% / %d%%）"%[quality,min_quality])
    if missing.is_empty():_copy("该完整经营日三项均达标；今日结束后再结算新的连续记录。",HospitalUiStyle.TEAL)
    else:_copy("未达标原因："+"；".join(missing)+"。",Color("ab5145"))

func _long_stage_summary(view:Dictionary) -> void:
    var phase:int=int(view.get("phase_index",0))
    _text(body,"阶段："+str(view.get("phase_name","开业")),21,HospitalUiStyle.INK)
    _copy("开业 → 稳定经营 → 扩建专科 → 综合考核"+(" · 已通过" if phase>=4 else ""))
    for goal:Dictionary in view.get("goals",[]):
        _copy(("✓ " if goal.get("passed",false) else "○ ")+str(goal.get("label",goal.get("id","目标")))+"  "+str(goal.get("current",0))+" / "+str(goal.get("target",0)),HospitalUiStyle.TEAL if goal.get("passed",false) else HospitalUiStyle.INK)
    _daily_operating_goal_copy()
    _button(body,"operating_review","查看经营日记录与资金安排",func()->void:_remember_origin("operating_review");show_section("finance"))
    var quality:Dictionary=view.get("quality",{})
    var samples:int=int(quality.get("samples",0))
    if samples>0:
        _copy("最近30分钟：治愈率 %.1f%% · 有效结案%d人（治愈%d / 弃诊%d）。"%[float(quality.get("rate",0)),samples,int(quality.get("completed",0)),int(quality.get("abandoned",0))])
    else:_copy("最近30分钟：暂无有效结案。仅实际离院患者计入质量样本，在院患者不计入。")
    var completed:int=int(_snapshot.metrics.get("completed",0))
    var lifetime_samples:int=int(view.get("lifetime_samples",0))
    var total:int=int(session.level_data().get("treated_target",0))
    _copy("全程累计：治愈%d/%d人 · 治愈率 %.1f%% · 已结案%d人。"%[completed,total,float(view.get("lifetime_cure_rate",0)),lifetime_samples] if lifetime_samples>0 else "全程累计：治愈%d/%d人 · 暂无有效结案。"%[completed,total])
    _copy("医院实体价值 %d币。近期质量、全程记录与本阶段新增治愈人数分别统计。"%int(view.get("hospital_value",0)))
    if view.get("course_complete",false):_copy("综合考核已通过。继续经营保留当前医院；下一关需要确认后另开新院，奖励不会重复发放。",HospitalUiStyle.TEAL)
    elif not view.get("can_advance",false):_copy("补齐以上尚未满足的目标后，再提交阶段考核。")

func _intake_copy(view:Dictionary) -> String:
    if not view.get("intake_enabled",false):return "常规接诊已关闭；可先准备科室，签名病例仍可手动接收。"
    if _snapshot.paused:return "常规接诊已开启 · 医院已暂停，请返回医院点播放，才会继续到院调度。"
    var reason:String=str(view.get("intake_reason",""))
    if reason!="":return "常规接诊已开启，当前等待："+reason_text(reason,_content(),_snapshot)
    var remaining:int=maxi(0,int(view.get("next_arrival_tick",0))-int(_snapshot.tick))
    return "常规接诊已开启 · 在院%d人 · 下一次调度约%.1f秒。"%[int(view.get("live_count",0)),remaining/10.0]

func _long_cases_page() -> void:
    var content:Dictionary=_content()
    var campaign:Dictionary=_snapshot.campaign
    var view:Dictionary=LongCampaign.goals(_snapshot,session.catalog)
    _heading(str(session.level_data().get("name","长线经营")))
    if not CampaignClinicalDecisions.enabled(_snapshot) or not CampaignPeople.enabled(_snapshot) or not CampaignBusiness.enabled(_snapshot):
        _copy("这座医院沿用旧版经营规则，当前进度已保留。新版诊疗、个人需求与采购策略将在新开医院或进入下一关时启用。",HospitalUiStyle.TEAL)
    if not CampaignExperience.enabled(_snapshot):_copy("本院沿用原有收益与人物规则；自动补给短休、主动生活服务及新经营方案在新医院启用。",HospitalUiStyle.TEAL)
    _button(body,"experience_lessons","经营引导与新规则",func()->void:show_section("tutorial"))
    _button(body,"playtest_review","查看经营复盘与排队瓶颈",func()->void:_remember_origin("playtest_review");show_section("review"))
    _management_controls()
    _clinical_policy_controls()
    if CampaignBusiness.enabled(_snapshot):
        var environment:Dictionary=CampaignBusiness.profile(_snapshot)
        _copy("本关环境 · "+str(environment.name)+"：产出型后勤基价%d%%，事件间隔约%.1f分钟。"%[int(environment.market_percent),float(environment.event_interval)/600.0])
    _long_stage_summary(view)
    _text(body,"接诊与医院负荷",19)
    _copy(_intake_copy(view),HospitalUiStyle.TEAL)
    _copy("常规客流只来自已真实完成的签名病例，按真实岗位、供给和接诊容量到院。关闭常规接诊后，已在院患者继续就诊。综合考核前须关闭常规接诊并清空在院患者。")
    var intake_enabled:bool=bool(view.get("intake_enabled",false))
    var intake:=_button(footer,"set_intake","关闭常规接诊" if intake_enabled else "开启常规接诊",func()->void:_issue("set_intake",{"enabled":not intake_enabled}))
    intake.disabled=_snapshot.challenge.status!="running"
    var advance:=_button(footer,"advance_stage","提交综合考核" if int(view.get("phase_index",0))==3 else "提交阶段考核",func()->void:_issue("advance_stage"),true)
    advance.disabled=not view.get("can_advance",false) or view.get("course_complete",false) or _snapshot.challenge.status!="running"
    _button(footer,"show_patients","在院患者",func()->void:show_section("patients"))
    if view.get("course_complete",false):
        if not view.get("continuing",false):_button(body,"continue_hospital","继续本院经营",func()->void:_issue("continue_hospital"),true)
        var next:Dictionary=session.next_level_info()
        if next.get("ok",false):_copy("下一关已开放，可从结算页或主菜单选择；进入前会再次确认。")
    var active_signature:Dictionary={}
    for instance:Dictionary in campaign.get("case_instances",{}).values():
        if instance.get("kind","")=="signature" and instance.get("status","")=="active":active_signature=instance;break
    var id:String=str(active_signature.get("case_id",view.get("signature_case_id","")))
    _text(body,"签名病例 · %d/8"%campaign.get("completed_cases",[]).size(),19)
    if id!="" and content.cases.has(id):
        var task:Dictionary=content.cases[id]
        _text(body,str(task.title),20)
        _copy(str(content.diseases.get(task.disease_id,{}).get("name",task.disease_id))+" · 本次%d人 · 每人离院收入%d币（当前收费）"%[task.get("patient_count",1),CampaignExperience.clinical_income(_snapshot,int(task.income),int(campaign.get("price_percent",100)))])
        _copy(str(task.get("summary","")))
        for step:Dictionary in task.get("steps",[]):
            _copy(str(content.facilities.get(step.facility_kind,{}).get("name",step.facility_kind))+" · %.1f秒 · 耗材%d币"%[step.duration_ticks/10.0,step.cost])
        var reasons:Array=_case_reasons(id)
        _copy("这次签名病例仍在就诊；常规患者可以同时运营。" if not active_signature.is_empty() else "准备齐全，可接收签名病例。" if reasons.is_empty() else "尚缺："+reason_text(reasons,content,_snapshot))
        _button(body,"prepare_case","准备签名病例",func()->void:_prepare_case(id),true)
        var accept:=_button(body,"accept_case","接收签名病例",func()->void:_issue("accept_case",{"case_id":id}),true)
        accept.disabled=not active_signature.is_empty() or not reasons.is_empty() or _snapshot.challenge.status!="running"
        if active_signature.is_empty():_case_stock(task)
    else:_copy("本阶段签名病例已完成。继续接诊并改善经营指标，满足目标后提交阶段考核。")
    var routine_rows:Array=[]
    for case_id:String in view.get("unlocked_case_ids",[]):
        if case_id in campaign.get("completed_cases",[]):routine_rows.append({"id":case_id,"name":str(content.cases.get(case_id,{}).get("title",case_id))})
    if not routine_rows.is_empty():
        if _routine_case=="" or _routine_case not in campaign.get("completed_cases",[]):_routine_case=routine_rows[0].id
        _choice("routine_case","手动补充常规病例",routine_rows,_routine_case,func(value:String)->void:_routine_case=value;_render())
        var routine_missing:Array=_case_reasons(_routine_case)
        var routine:=_button(body,"admit_routine","手动接收所选常规病例",func()->void:_issue("admit_routine",{"case_id":_selected("routine_case")}))
        routine.disabled=not routine_missing.is_empty() or _snapshot.challenge.status!="running"
        if not routine_missing.is_empty():_copy("常规接诊准备："+reason_text(routine_missing,content,_snapshot))
        _clinic_drive_controls(routine_missing)
    _text(body,"本关签名任务与阶段开放",19)
    var unlocked:Array=view.get("unlocked_case_ids",[])
    var ids:Array=session.level_data().get("case_ids",[])
    var names:Array[String]=["开业","稳定经营","扩建专科","综合考核"]
    for index:int in range(ids.size()):
        var case_id:String=ids[index]
        _copy(("✓ " if case_id in campaign.get("completed_cases",[]) else "待完成 · " if case_id in unlocked else "尚未开放 · ")+str(content.cases.get(case_id,{}).get("title",case_id))+" · "+names[mini(3,index/2)])
    _button(body,"long_growth","查看研究、培训与审核",func()->void:show_section("growth"))

func _clinic_drive_controls(missing:Array) -> void:
    var drive:Dictionary=ClinicDrive.view(_snapshot,session.catalog)
    _text(body,"集中门诊",19)
    _copy("选择上方已开展的病例，安排4、8或12批集中到诊。不会加快治疗或游戏时钟，仍需真实员工、物资和接诊容量；客流更密集可能增加排队。")
    _choice("clinic_drive_batches","本次接诊批数",[{"id":"4","name":"4批 · 小批量"},{"id":"8","name":"8批 · 连续接诊"},{"id":"12","name":"12批 · 高负荷"}],str(_policy_drafts.get("clinic_drive_batches","4")),func(value:String)->void:_policy_drafts["clinic_drive_batches"]=value)
    var active:bool=drive.status in ["admitting","paused","finishing"]
    if drive.status!="none" and drive.status!="canceled":
        var names:Dictionary={"admitting":"集中接诊中","paused":"已暂停到诊","finishing":"本批患者正在收尾","completed":"本批已实际结案","stage_ended":"上阶段门诊已结束"}
        _copy(str(names.get(drive.status,drive.status))+" · 到诊%d/%d批 · 完成%d批 · 未治愈结案%d批。"%[int(drive.admitted),int(drive.target_batches),int(drive.completed),int(drive.failed)],HospitalUiStyle.TEAL)
    var start:Button=_button(body,"clinic_drive_start","开始所选病例的集中门诊",func()->void:_issue("set_clinic_drive",{"enabled":true,"case_id":_selected("routine_case"),"batches":int(_selected("clinic_drive_batches"))}),true)
    start.disabled=active or not missing.is_empty() or not _snapshot.campaign.intake_enabled or _snapshot.challenge.status!="running"
    if active:
        _button(body,"clinic_drive_cancel","停止集中到诊，保留在院治疗",func()->void:_issue("set_clinic_drive",{"enabled":false,"case_id":"","batches":0}))
    elif not _snapshot.campaign.intake_enabled:_copy("先开启常规接诊，再开始集中门诊。")
    elif not missing.is_empty():_copy("集中接诊准备："+reason_text(missing,_content(),_snapshot))
    _copy("完成批数以实际离院结果计算，不增加毕业奖励；取消后恢复混合常规客流，已在院患者继续就诊。")

func _review_page() -> void:
    _heading("经营复盘")
    var review:Dictionary=PlaytestInsights.review(_snapshot,session.catalog)
    if not review.enabled:_copy("请在长线医院中查看经营记录。");return
    _copy("查看近期经营表现，找出候诊、供货和人员瓶颈。")
    _text(body,"经营节奏",19)
    _copy("本阶段已运行%.1f游戏分钟 · 经营操作%d次。"%[float(review.phase_elapsed_ticks)/600.0,int(review.operating_commands)])
    if int(review.since_command_ticks)>=0:_copy("距最近经营操作%.1f游戏分钟；暂停和倍速切换不计作经营决策。"%(float(review.since_command_ticks)/600.0))
    _copy("最近%d个完整经营日：治愈%d人，合计经营利润%d币。"%[int(review.full_days),int(review.day_cures),int(review.day_profit)])
    _copy("最近%.1f游戏分钟实际结案%d人：治愈%d人、转诊%d人、弃诊%d人；平均累计排队与支持等待%.1f秒。"%[float(review.window_ticks)/600.0,int(review.samples),int(review.completed),int(review.referred),int(review.abandoned),float(review.average_wait_ticks)/10.0])
    if int(review.samples)==0:_copy("完成诊疗并离院后，这里会显示近期治愈与等候表现。")
    _text(body,"当前排队瓶颈",19)
    var index:int=0
    for row:Dictionary in review.queues.slice(0,4):
        var patient_id:String=str(row.patient_id)
        var reason:String="等待临床安排" if row.reason=="clinical_queue" else reason_text(row.reason,_content(),_snapshot)
        _copy("%d位患者：%s。"%[int(row.count),reason])
        _button(body,"review_queue_%d"%index,"查看这类等待的患者",func()->void:_focus_patient=patient_id;_remember_origin("review_patient");show_section("patients"))
        index+=1
    if review.queues.is_empty():_copy("当前没有排队或等待医技支持的患者。")
    _copy("病例人数尚未达标且团队有余力时，可尝试小批量集中门诊；出现队列时先定位缺岗、补给或设备瓶颈，再决定是否扩容。")
    _button(body,"review_staff","查看员工与替班",func()->void:_remember_origin("review_staff");show_section("staff"))
    _button(body,"review_supply","查看库存与补给",func()->void:_remember_origin("review_supply");show_section("operations"))

func _clinical_policy_controls() -> void:
    if not CampaignClinicalDecisions.enabled(_snapshot):return
    _text(body,"诊疗策略",19)
    var rows:Array=[{"id":"balanced","name":"均衡 · 目标80，最多复检1次"},{"id":"thorough","name":"充分检查 · 目标95，最多复检2次"},{"id":"manual","name":"手动 · 检查后等待院长决定"}]
    _choice("clinical_policy","全院默认策略",rows,str(_policy_drafts.get("clinical_policy",_snapshot.campaign.clinical_policy)),func(value:String)->void:_policy_drafts["clinical_policy"]=value)
    _button(body,"set_clinical_policy","应用诊疗策略",func()->void:_issue("set_clinical_policy",{"policy":_selected("clinical_policy")}))
    _copy("复检会实际占用检查设备、人员和耗材。把握度低于80时，审慎治疗还需追加补治。手动模式请在患者页面及时决定，等候仍计入耐心。")

func _clinical_patient_controls(patient:Dictionary) -> void:
    if not CampaignClinicalDecisions.enabled(_snapshot):return
    var view:Dictionary=CampaignClinicalDecisions.preview(_snapshot,session.catalog,str(patient.id))
    var score:int=int(view.get("confidence",-1))
    if score<0:
        _copy("诊断依据：等待真实首诊检查。")
        return
    _copy("诊断把握度 %d / 100 · 建议治疗线80 · 已完成复检%d次"%[score,int(view.completed_exams)],HospitalUiStyle.TEAL)
    if int(view.deficit)>0:_copy("当前把握度不足，直接审慎治疗需要额外补治。",Color("ab5145"))
    if not view.get("pending",false):return
    var names:Dictionary={"continue_exam":"继续检查","cautious_treat":"审慎治疗","refer":"转诊交接"}
    var choices:=GridContainer.new()
    choices.columns=3 if minf(_safe.size.x,panel.size.x)>=560 else 1
    choices.add_theme_constant_override("h_separation",8)
    choices.size_flags_horizontal=Control.SIZE_EXPAND_FILL
    body.add_child(choices)
    for action:String in view.options:
        var terms:Dictionary=view.terms[action]
        var card:=VBoxContainer.new()
        card.size_flags_horizontal=Control.SIZE_EXPAND_FILL
        choices.add_child(card)
        _text(card,"%d币 · %.1f秒"%[int(terms.planned_cost),float(terms.planned_duration_ticks)/10.0],16,HospitalUiStyle.MUTED)
        var patient_id:String=patient.id
        var revision:int=int(view.revision)
        var chosen:String=action
        var button:Button=_button(card,"decision_"+patient_id+"_"+action,str(names[action]),func()->void:_issue("clinical_decision",{"patient_id":patient_id,"action":chosen,"expected_revision":revision}),action=="continue_exam")
        button.disabled=not terms.missing.is_empty() or (action=="continue_exam" and int(view.completed_exams)>=int(view.max_exams))
        if not terms.missing.is_empty():_text(card,"尚缺："+reason_text(terms.missing,_content(),_snapshot),14,Color("ab5145"))

func _procurement_controls() -> void:
    if not CampaignBusiness.enabled(_snapshot):return
    var environment:Dictionary=CampaignBusiness.profile(_snapshot)
    _text(body,"采购与生产节奏",19)
    _copy("本关 · "+str(environment.name)+"，产出型后勤基价%d%%。"%int(environment.market_percent))
    _choice("procurement_policy","新工单采购方式",[{"id":"standard","name":"普通 · 成本100% / 用时100%"},{"id":"economy","name":"节省 · 成本75% / 用时150%"},{"id":"express","name":"加急 · 成本150% / 用时70%"}],str(_policy_drafts.get("procurement_policy",_snapshot.campaign.procurement_policy)),func(value:String)->void:_policy_drafts["procurement_policy"]=value)
    _button(body,"set_procurement_policy","应用采购方式",func()->void:_issue("set_procurement_policy",{"policy":_selected("procurement_policy")}))
    _copy("仅影响之后创建的纯产出型后勤工单。已有工单保留原报价；物流研究在开工时再减少15%用时。患者疗程、研究与培训另按各自规则运行。")

func _patient_need_controls(patient:Dictionary) -> void:
    if not CampaignPeople.enabled(_snapshot):return
    var needs:Dictionary=patient.get("needs",{})
    _copy("个人需求 · 口渴%d · 饥饿%d · 如厕%d（越高越需要照顾）"%[int(needs.get("water",0)),int(needs.get("food",0)),int(needs.get("toilet",0))])
    _copy("当前需求使耐心减少%.1f游戏秒；三项需求超过40后逐步扣减，合计最多60秒，完成个人服务可恢复。"%(CampaignPeople.patience_penalty(_snapshot,patient)/10.0))
    var activity:Dictionary=patient.get("need_activity",{})
    if not activity.is_empty():_copy("生活服务进行中，需实际走到设施才能使用；完成后继续原有诊疗路线。")
    var used_this_step:bool=false
    var last_end:int=-CampaignPeople.COOLDOWN
    for history:Dictionary in patient.get("need_history",[]):
        if int(history.step_index)==int(patient.step_index):used_this_step=true
        last_end=maxi(last_end,maxi(int(history.get("completed_tick",-1)),int(history.get("canceled_tick",-1))))
    var cooldown:int=maxi(0,CampaignPeople.COOLDOWN-(int(_snapshot.tick)-last_end))
    if CampaignExperience.enabled(_snapshot):used_this_step=false
    if used_this_step:_copy("本步骤已安排过生活服务；下一诊疗步骤可再次安排。")
    elif cooldown>0:_copy("生活服务还需冷却%.1f秒。"%(cooldown/10.0))
    else:_copy("生活服务使用后冷却30游戏秒；自动照顾按真实需求安排。" if CampaignExperience.enabled(_snapshot) else "每个诊疗步骤最多安排一次生活服务，使用后冷却30游戏秒。")
    var names:Dictionary={"water":"前往饮水","food":"前往用餐","toilet":"前往如厕"}
    var row:=HFlowContainer.new();body.add_child(row)
    for need:String in names:
        var pid:String=patient.id
        var selected_need:String=need
        var button:Button=_button(row,"need_"+pid+"_"+need,names[need],func()->void:_issue("request_patient_need",{"patient_id":pid,"need":selected_need}))
        button.disabled=patient.phase!="care_queue" or str(patient.slot_id)!="" or str(patient.support_order_id)!="" or int(patient.move_progress)>0 or not activity.is_empty() or used_this_step or cooldown>0 or int(needs.get(need,0))<20

func _autonomy_controls(kind:String) -> void:
    if not CampaignExperience.enabled(_snapshot):return
    var patient_auto:bool=bool(_snapshot.campaign.get("auto_patient_needs",true))
    var staff_auto:bool=bool(_snapshot.campaign.get("auto_staff_rest",true))
    var patient_page:bool=kind=="patient"
    _button(body,"toggle_patient_autonomy" if patient_page else "toggle_staff_autonomy",("患者主动生活服务：" if patient_page else "员工自动补给短休：")+("开启" if (patient_auto if patient_page else staff_auto) else "关闭"),func()->void:_issue("set_people_autonomy",{"patient_needs":not patient_auto if patient_page else patient_auto,"staff_rest":staff_auto if patient_page else not staff_auto}))
    _copy("患者会按本人需求寻找可用设施，实际走到并使用后恢复；关闭后仍可手动安排。" if patient_page else "疲劳或心情需要照顾时，空闲员工会实际离岗短休，完成后返回原岗位；关闭后仍可手动安排。")

func _management_controls() -> void:
    if not CampaignManagementEvents.enabled(_snapshot):return
    var events:Array=_snapshot.campaign.get("management_events",[])
    _text(body,"经营方案",19)
    if section!="management":
        if events.is_empty():_copy("随签名病例进展出现，可选，不增加毕业门槛。")
        else:
            for event:Dictionary in events:_copy(("✓ " if event.status=="resolved" else "○ ")+str(CampaignManagementEvents.NAMES.get(event.definition_id,"经营方案")))
            _button(body,"management_plans","查看可选经营方案",func()->void:show_section("management"))
        return
    _copy("可选，不影响本院毕业；在真实业务中完成，不额外发钱或增加等待门槛。")
    if events.is_empty():
        _copy("继续完成本关签名病例，经营方案将随进展出现。")
        return
    for event:Dictionary in events:
        var eid:String=event.id
        var revision:int=int(event.revision)
        var insight:Dictionary=ManagementInsights.event(_snapshot,session.catalog,eid)
        _text(body,("✓ " if event.status=="resolved" else "○ ")+str(insight.get("title","经营方案")),18)
        if event.status=="resolved":
            _copy("已核验实际业务完成。",HospitalUiStyle.TEAL)
            continue
        for choice:Dictionary in CampaignManagementEvents.choices(str(event.definition_id)):
            var cid:String=choice.id
            _copy(str(choice.get("description","")))
            var option:=_button(body,"management_"+eid+"_"+cid,("当前方案 · " if event.get("choice","")==cid else "选择 · ")+str(choice.label),func()->void:_issue("choose_management_event",{"event_id":eid,"choice":cid,"expected_revision":revision}))
            option.disabled=event.get("choice","")==cid
        _text(body,"完成步骤",17)
        for step:Dictionary in insight.get("steps",[]):
            _copy(("✓ " if step.done else "○ ")+str(step.label),HospitalUiStyle.TEAL if step.done else HospitalUiStyle.INK)
        _copy(str(insight.get("next_action",event.get("next_action",""))),HospitalUiStyle.TEAL)
        var progress:Dictionary={"ready":bool(insight.get("ready",false)),"current":1 if insight.get("ready",false) else 0,"target":1}
        _copy("实际业务进度 %d / %d"%[int(progress.get("current",0)),int(progress.get("target",1))])
        var actions:=HFlowContainer.new();body.add_child(actions)
        var action_info:Dictionary=insight.duplicate(true)
        action_info["event_id"]=eid
        var destination:String=str(action_info.get("section","cases"))
        var label:String={"finance":"前往财务设置","operations":"查看目标工单","resource":"准备目标资源","staff":"查看目标人员","cases":"接诊目标病例","patients":"查看相关患者"}.get(destination,"前往相关操作")
        var action_button:=_button(actions,"management_action_"+eid,"请先选择上方方案" if event.status=="open" else label,func()->void:_management_go(action_info))
        action_button.disabled=event.status=="open"
        var verify:=_button(actions,"management_verify_"+eid,"核验实际完成",func()->void:_issue("resolve_management_event",{"event_id":eid,"expected_revision":revision}),true)
        verify.disabled=not progress.get("ready",false)

func _management_go(info:Dictionary) -> void:
    var destination:String=str(info.get("section","cases"))
    _remember_origin(str(info.get("event_id","")))
    var kind:String=str(info.get("facility_kind",""))
    if kind!="":_selected_operation=kind
    if str(info.get("resource",""))!="":_resource_focus=str(info.resource)
    if str(info.get("case_id",""))!="":_routine_case=str(info.case_id)
    _focus_patient=str(info.get("patient_id",""))
    if str(info.get("staff_id",""))!="":_selected_staff=str(info.staff_id)
    elif destination=="staff" and kind!="":
        for facility:Dictionary in _snapshot.get("facilities",{}).values():
            if facility.kind==kind and not facility.staff_ids.is_empty():_selected_staff=str(facility.staff_ids[0]);break
    show_section(destination if destination in ["cases","finance","operations","resource","staff","patients"] else "cases")

func _remember_origin(subject:String="") -> void:
    if not _guidance_origin.is_empty() and section!=str(_guidance_origin.section):return
    _guidance_origin={"section":section,"scroll":int(scroll.scroll_vertical),"subject":subject}

func _return_guidance() -> void:
    if _guidance_origin.is_empty():return
    var origin:Dictionary=_guidance_origin.duplicate()
    _guidance_origin.clear()
    show_section(str(origin.section))
    _scroll_reset_serial+=1
    var serial:int=_scroll_reset_serial
    scroll.scroll_vertical=int(origin.scroll)
    _restore_guidance_scroll.call_deferred(serial,int(origin.scroll))

func _restore_guidance_scroll(serial:int,value:int) -> void:
    if not is_inside_tree():return
    await get_tree().process_frame
    if serial==_scroll_reset_serial and is_instance_valid(scroll):scroll.scroll_vertical=value

func _management_page() -> void:
    _heading("可选经营方案")
    _management_controls()
    _button(footer,"management_cases","返回病例与阶段目标",func()->void:show_section("cases"),true)

func _tutorial_page() -> void:
    _heading("经营引导")
    if experience_tutorial==null:
        _copy("从长线经营医院进入引导。")
        return
    var current:Dictionary=experience_tutorial.current()
    if current.get("visible",false):
        _text(body,"%d / %d · %s"%[int(current.number),int(current.total),str(current.title)],20)
        _copy(str(current.text))
        _copy(str(current.waiting),HospitalUiStyle.TEAL)
        var focus:Dictionary=current.get("focus",{})
        if str(focus.get("preparation",""))!="":_copy(str(focus.preparation),HospitalUiStyle.TEAL)
        _button(body,"tutorial_go","前往当前操作",func()->void:tutorial_focus_requested.emit(focus),true)
        _button(body,"tutorial_close","收起引导",func()->void:experience_tutorial.close();close())
        _button(body,"tutorial_skip","跳过整套引导",func()->void:experience_tutorial.skip();close())
    else:_copy("引导已收起或已完成。可随时从下方重新学习一课，操作记录不会被修改。")
    _text(body,"按需学习",19)
    var names:Dictionary={"clinical_policy":"诊疗策略","clinical_decision":"患者诊疗决定","personal_need":"个人生活服务","staff_wage":"员工照顾与薪资","procurement":"采购与新工单","event":"事件处理"}
    for id:String in HospitalExperienceTutorial.STEPS:
        var step:String=id
        _button(body,"tutorial_start_"+id,str(names[id]),func()->void:experience_tutorial.begin(session.presentation_snapshot(),step);_signature="";_render())

func _research_effect_copy(project_id:String,effects:Dictionary) -> void:
    var effect:Dictionary=effects.get(project_id,{})
    var name:String=str(_content().get("projects",{}).get(project_id,{}).get("name",project_id))
    _text(body,"所选研究："+name+" · "+("已生效" if effect.get("active",false) else "完成后生效"),18)
    match project_id:
        "clinical_quality":_copy("患者耐心增加%d游戏秒。"%int(int(effect.get("patience_bonus_ticks",0))/10))
        "efficiency":
            var training:Dictionary=effects.get("training",{})
            _copy("临床服务用时减少%d%%。与匹配专科培训均生效时合计减少%d%%；已经开始的疗程不追溯改变。"%[int(effect.get("clinical_discount_percent",0)),int(training.get("combined_clinical_discount_percent",0))])
        "logistics":_copy("纯后台工单用时减少%d%%；患者支持疗程、研究与培训不享受这项加速，已开始工序不追溯改变。"%int(effect.get("operation_discount_percent",0)))
