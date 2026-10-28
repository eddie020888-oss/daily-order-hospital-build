class_name HospitalHud
extends Control

const StaffingCard=preload("res://ui/campaign_staffing_card.gd")

var session: GameSession
var touch: TouchController
var world: HospitalWorld
var controls: Dictionary={}
var palette: BuildPalette
var selection: SelectionPanel
var _top: PanelContainer
var _dock: PanelContainer
var _dock_face: PanelContainer
var _top_frame: PanelContainer
var _crest: TextureRect
var _recovery_panel: PanelContainer
var _recovery_mark: TextureRect
var _nav_labels: Dictionary={}
var _staff_badge: Label
var _speed_style_signature:=""
var _bottom: PanelContainer
var _left: PanelContainer
var _right: PanelContainer
var _notice_panel: PanelContainer
var _preview_panel: PanelContainer
var _stats: Label
signal feedback_result(result: Dictionary)
var settings_page: HospitalSettingsPanel
var _settings_footer: PanelContainer
var _notice: Label
var _preview: Label
var _hint: Label
var _preview_root: Node3D
var _safe:=Rect2(0,0,1280,720)
var _target:=48.0
var _compact:=false
var _settlement_panel: PanelContainer
var _actions: PanelContainer
var _utility: PanelContainer
var _left_title: Label
var _right_title: Label
var _completed: Label
var _clock: Label
var _nav_buttons: Dictionary = {}
var _settlement_title: Label
var _last_status := "running"
var _compact_header := false
var _narrow_header := false
var _actions_width := 272.0
var _status_cards: Array[PanelContainer] = []
var _status_units: Array[Label] = []
var _status_marks: Array[TextureRect] = []
var _dock_two_rows:=false
var _dock_height:=88.0
var _selection_footer: PanelContainer
var _drawer_headers: Array[MarginContainer] = []
var _drawer_scrolls: Array[ScrollContainer] = []
var _ledger: HospitalLedger
var flow: HospitalFlowPages
var _seen_unlock:=""
var _restart_return:="pause"
var _restart_level_id:=""
var placement_details: HospitalPlacementPanel
var operations: HospitalOperationsPanel
var _placement_tools: PanelContainer
var _placement_badge: PanelContainer
var _preview_footer: PanelContainer
var _operations_drawer: PanelContainer
var _operations_title: Label
var _operations_footer: PanelContainer
var _preview_signature:=""
var _editing_preview_room:=""
var campaign_panel:CampaignHospitalPanel
var campaign_build:CampaignBuildEditor
var opening_card:CampaignOpeningCard
var patient_card:CampaignPatientCard
var staffing_card:Variant
var _campaign_overlay:CampaignBuildOverlay
var _opening_signature:=""
var _opening_current:Dictionary={}
var _campaign_preview_signature:=""
var _campaign_build_step:=-1
var _next_career_confirmation:=false
var _long_goals_signature:=""
var _long_goals_cache:Dictionary={}
var _experience_tutorial:HospitalExperienceTutorial
var _experience_button:Button
var _build_task_title:Label
var _build_footer_actions:HFlowContainer
var _placement_tools_row:HBoxContainer
var _wizard_generation:=0
var _wizard_pending:Dictionary={}
var _wizard_auto_queued:=false
var _wizard_return_to_decor:=false

func set_experience_tutorial(tracker:HospitalExperienceTutorial) -> void:
	_experience_tutorial=tracker
	if campaign_panel!=null:
		campaign_panel.experience_tutorial=tracker
		if not campaign_panel.tutorial_focus_requested.is_connected(_experience_focus):campaign_panel.tutorial_focus_requested.connect(_experience_focus)
	if _experience_button==null:
		_experience_button=Button.new()
		_experience_button.text="经营引导"
		_experience_button.add_theme_stylebox_override("normal",HospitalUiStyle.panel(12,HospitalUiStyle.PAPER,10))
		_experience_button.custom_minimum_size=Vector2(210,48)
		_experience_button.pressed.connect(func()->void:_close_drawers();campaign_panel.show_section("tutorial"))
		add_child(_experience_button)
		controls.experience_tutorial=_experience_button
		_apply_targets(_experience_button)
	_experience_button.hide()
	_sync_experience_display()

func _sync_experience_display() -> void:
	if session==null or campaign_panel==null:return
	_present_experience(session.presentation_snapshot())
	_present_opening_guide(session.presentation_snapshot())

func _experience_focus(focus:Dictionary) -> void:
	if campaign_panel==null:return
	if focus.has("staff_id"):campaign_panel._selected_staff=str(focus.staff_id)
	if focus.get("section","")=="facilities" and focus.has("facility_kind"):
		campaign_panel._unit="all"
		campaign_panel._search=str(session.catalog.campaign.facilities.get(focus.facility_kind,{}).get("name",""))
		campaign_panel._page=0
	campaign_panel.show_section(str(focus.get("section","cases")))
	if str(focus.get("preparation",""))!="":
		campaign_panel._feedback=str(focus.preparation)
		campaign_panel._signature=""
		campaign_panel._render()
	_experience_scroll.call_deferred(str(focus.get("control","")))

func _experience_scroll(id:String) -> void:
	await get_tree().process_frame
	if campaign_panel==null or not campaign_panel.visible:return
	var control:Control=campaign_panel.controls.get(id)
	if is_instance_valid(control):
		campaign_panel.scroll.ensure_control_visible(control)
		control.grab_focus()

func _present_experience(snapshot:Dictionary) -> void:
	if _experience_button==null or _experience_tutorial==null:return
	if int(snapshot.get("campaign",{}).get("opening_loop_version",0))==1:
		_experience_button.hide()
		return
	var current:Dictionary=_experience_tutorial.current()
	_experience_button.visible=snapshot.get("ruleset","")=="full-hospital-v2" and current.get("visible",false) and not campaign_panel.visible and not (flow!=null and flow.visible) and session.notice==""
	if not _experience_button.visible:return
	_experience_button.text="引导 %d/%d · %s"%[int(current.number),int(current.total),str(current.title)]
	var height:float=maxf(48,_target)
	_experience_button.size=Vector2(minf(300,_safe.size.x-36),height)
	_experience_button.position=Vector2(_safe.position.x+12,(_dock.position.y if _dock.visible else _console_bounds().end.y)-height-8)

# Output pixels and physical insets are converted once into InputEvent / Camera3D viewport coordinates.
static func layout_metrics(output_pixels: Vector2, viewport_size: Vector2, dpi: float, physical_safe: Rect2) -> Dictionary:
	var scale:=viewport_size/output_pixels.max(Vector2.ONE)
	return {"target":maxf(48.0,48.0*maxf(1.0,dpi/160.0)*maxf(scale.x,scale.y)),"safe":Rect2(physical_safe.position*scale,physical_safe.size*scale)}

func initialize(owner_session: GameSession, controller: TouchController, view: HospitalWorld, feedback: HospitalFeedback=null) -> void:
	session=owner_session
	touch=controller
	world=view
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	oversampling_with_scale=CanvasItem.OVERSAMPLING_WITH_SCALE_ENABLED
	theme=load("res://ui/theme.tres").duplicate(true)
	theme.default_font.base_font=theme.default_font.base_font.duplicate()
	HospitalUiStyle.apply_theme(theme)
	_dock=_panel()
	_dock.name="HospitalConsole"
	HospitalA2Skin.panel(_dock)
	_dock_face=PanelContainer.new()
	_dock_face.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_dock_face.add_theme_stylebox_override("panel",StyleBoxEmpty.new())
	_dock.add_child(_dock_face)
	controls.console=_dock
	_top_frame=_panel()
	_top_frame.name="HospitalDutyBar"
	HospitalA2Skin.panel(_top_frame)
	controls.top_console=_top_frame
	_crest=HospitalUiStyle.picture(load("res://assets/branding/app-icon-v1.png") as Texture2D,Vector2(40,40),0)
	_crest.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	add_child(_crest)
	_top=_panel()
	_top.name="ConsoleReadouts"
	_top.add_theme_stylebox_override("panel",StyleBoxEmpty.new())
	var stats_row:=HBoxContainer.new()
	stats_row.add_theme_constant_override("separation",3)
	_top.add_child(stats_row)
	_stats=_status_chip(stats_row,"coin",grouped_number(session.sim.snapshot().cash),"资金",HospitalUiStyle.INK)
	_completed=_status_chip(stats_row,"people","0","治愈")
	_clock=_status_chip(stats_row,"clock","0:00","营业时间")
	_status_cards[0].size_flags_stretch_ratio=1.15
	_status_cards[1].size_flags_stretch_ratio=1.45
	_status_cards[2].size_flags_stretch_ratio=1.0
	_actions=_panel()
	_actions.name="ConsoleSystemControls"
	_actions.add_theme_stylebox_override("panel",StyleBoxEmpty.new())
	var actions_row:=HBoxContainer.new()
	actions_row.add_theme_constant_override("separation",4)
	actions_row.alignment=BoxContainer.ALIGNMENT_END
	_actions.add_child(actions_row)
	_add_icon_button(actions_row,"pause","play","开始营业",func() -> void: session.issue("set_paused",{"paused":not session.sim.snapshot().paused}))
	_add_button(actions_row,"speed1","1×",func() -> void: _run_speed(1))
	_add_button(actions_row,"speed2","2×",func() -> void: _run_speed(2))
	_add_button(actions_row,"speed_toggle","1×",func() -> void: _run_speed(2 if session.sim.snapshot().speed==1 else 1))
	controls.speed_toggle.set_meta("fixed_width",true)
	controls.speed_toggle.hide()
	controls.speed1.set_meta("fixed_width",true)
	controls.speed2.set_meta("fixed_width",true)
	for key in ["speed1","speed2","speed_toggle"]:
		controls[key].add_theme_font_size_override("font_size",16)
	_add_icon_button(actions_row,"save","save","保存",_manual_save)
	_add_icon_button(actions_row,"settings","settings","暂停菜单",_show_pause)
	_add_icon_button(actions_row,"restart","play","重新开局",_request_restart)
	_add_icon_button(actions_row,"settlement","chart","查看结算",func() -> void: flow.show_result(session.sim.snapshot()))
	controls.restart.hide()
	controls.settlement.hide()
	for key in ["pause","speed1","speed2","speed_toggle","save","settings","restart","settlement"]:
		var action_button:Button=controls[key]
		HospitalA2Skin.button(action_button,"primary" if key=="pause" else "paper",16)
		if key in ["pause","save","settings","restart","settlement"]:
			var action_icon:String={"pause":"play","save":"save","settings":"home","restart":"play","settlement":"chart"}[key]
			HospitalA2Skin.button(action_button,"primary" if key=="pause" else "paper",16,action_icon)
	_bottom=_panel()
	_bottom.name="ConsoleManagementControls"
	_bottom.add_theme_stylebox_override("panel",StyleBoxEmpty.new())
	var nav:=HBoxContainer.new()
	nav.add_theme_constant_override("separation",6)
	_bottom.add_child(nav)
	for row in [["build","build","建设"],["staff","staff","员工"],["patients","patient","患者"],["finance","chart","经营"]]:
		var key: String=row[0]
		var b:=_add_button(nav,key,row[2],func() -> void: _navigate(key))
		b.set_meta("minimum_size",Vector2(100,64))
		b.set_meta("fixed_width",true)
		b.icon=null
		b.clip_text=false
		var face:=VBoxContainer.new()
		face.mouse_filter=Control.MOUSE_FILTER_IGNORE
		face.alignment=BoxContainer.ALIGNMENT_CENTER
		face.add_theme_constant_override("separation",1)
		b.add_child(face)
		face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		face.offset_left=4;face.offset_right=-4;face.offset_top=3;face.offset_bottom=-3
		var nav_mark:=HospitalUiStyle.picture(HospitalA2Skin.icon(row[1],32),Vector2(32,32),0)
		nav_mark.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		nav_mark.size_flags_horizontal=Control.SIZE_SHRINK_CENTER
		face.add_child(nav_mark)
		var nav_label:=HospitalUiStyle.text(row[2],17,HospitalA2Skin.INK,700)
		nav_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		face.add_child(nav_label)
		_nav_labels[key]=nav_label
		_nav_buttons[key]=b
		if key=="staff":
			_staff_badge=HospitalUiStyle.text("0",10,HospitalA2Skin.PAPER,700)
			_staff_badge.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
			_staff_badge.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
			_staff_badge.add_theme_stylebox_override("normal",HospitalA2Skin.style("clock",1))
			b.add_child(_staff_badge)
	_left=_panel()
	var left_column:=VBoxContainer.new()
	left_column.add_theme_constant_override("separation",0)
	_left.add_child(left_column)
	_left_title=_drawer_header(left_column,"建设医院","close_build",_close_drawers)
	var build_scroll:=_scroll(left_column)
	build_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	palette=BuildPalette.new()
	palette.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	build_scroll.add_child(palette)
	palette.initialize(session.catalog)
	palette.build_requested.connect(_begin_build)
	palette.command_requested.connect(session.issue)
	controls.merge(palette.controls)
	_right=_panel()
	var right_column:=VBoxContainer.new()
	right_column.add_theme_constant_override("separation",0)
	_right.add_child(right_column)
	_right_title=_drawer_header(right_column,"房间详情","close_detail",_close_drawers)
	var select_scroll:=_scroll(right_column)
	select_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	selection=SelectionPanel.new()
	_selection_footer=PanelContainer.new()
	_selection_footer.add_theme_stylebox_override("panel",_footer_style(false))
	var footer_actions:=HFlowContainer.new()
	footer_actions.add_theme_constant_override("h_separation",9)
	footer_actions.add_theme_constant_override("v_separation",9)
	_selection_footer.add_child(footer_actions)
	selection.action_footer=footer_actions
	selection.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	select_scroll.add_child(selection)
	right_column.add_child(_selection_footer)
	selection.page_changed.connect(func(title: String) -> void: _right_title.text=title; _selection_footer.visible=footer_actions.get_child_count()>0)
	selection.locate_requested.connect(_locate_selection)
	selection.command_requested.connect(session.issue)
	selection.move_requested.connect(_begin_move)
	selection.layout_edit_requested.connect(_begin_layout_edit)
	selection.focus_requested.connect(select_entity)
	selection.recruit_requested.connect(_show_recruitment)
	selection.build_catalog_requested.connect(func() -> void: _navigate("build"))
	selection.hospital_flow_requested.connect(_show_hospital_flow)
	_utility=_panel()
	_utility.z_index=1
	var menu:=VBoxContainer.new()
	menu.add_theme_constant_override("separation",0)
	_utility.add_child(menu)
	_drawer_header(menu,"系统设置","close_settings",_close_drawers)
	var menu_scroll:=_scroll(menu)
	menu_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	settings_page=HospitalSettingsPanel.new()
	settings_page.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	menu_scroll.add_child(settings_page)
	settings_page.initialize(feedback,session.catalog)
	settings_page.preference_result.connect(func(result: Dictionary) -> void: feedback_result.emit(result))
	_settings_footer=PanelContainer.new()
	_settings_footer.add_theme_stylebox_override("panel",_footer_style(false))
	menu.add_child(_settings_footer)
	var settings_actions:=HFlowContainer.new()
	_settings_footer.add_child(settings_actions)
	HospitalUiStyle.primary(_add_button(settings_actions,"close_panel","回到医院",_close_drawers))
	_notice_panel=_panel()
	_notice_panel.add_theme_stylebox_override("panel",HospitalUiStyle.bevel(HospitalUiStyle.IVORY,6))
	var notice_column:=VBoxContainer.new()
	notice_column.add_theme_constant_override("separation",4)
	_notice_panel.add_child(notice_column)
	_notice=_label("",14)
	var notice_scroll:=ScrollContainer.new()
	notice_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	notice_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	_notice.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	notice_column.add_child(notice_scroll)
	notice_scroll.add_child(_notice)
	var notice_actions:=HBoxContainer.new()
	notice_column.add_child(notice_actions)
	_add_button(notice_actions,"dismiss","知道了",func() -> void: session.dismiss_notice())
	_add_button(notice_actions,"locate","查看",_locate_notice)
	_add_button(notice_column,"recover","保留原档并开新局",func() -> void: session.recover_new_game())
	_preview_panel=_panel()
	var preview_column:=VBoxContainer.new()
	preview_column.add_theme_constant_override("separation",0)
	_preview_panel.add_child(preview_column)
	_build_task_title=_drawer_header(preview_column,"放置预览","close_preview",touch.cancel)
	var preview_scroll:=_scroll(preview_column)
	preview_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	placement_details=HospitalPlacementPanel.new()
	placement_details.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	preview_scroll.add_child(placement_details)
	placement_details.initialize(session.catalog)
	preview_column.add_child(placement_details.pinned_header)
	preview_column.move_child(placement_details.pinned_header,2)
	placement_details.furniture_selected.connect(touch.select_furniture)
	placement_details.opening_tool_selected.connect(touch.select_opening_tool)
	placement_details.bounds_adjusted.connect(touch.adjust_build_bounds)
	placement_details.task_layout_changed.connect(_wizard_ui_changed)
	touch.placement_interaction_finished.connect(_placement_interaction_finished)
	for key in placement_details.bounds_buttons:controls["bounds_"+key]=placement_details.bounds_buttons[key]
	for kind in placement_details.furniture_buttons:controls["furn_"+kind]=placement_details.furniture_buttons[kind]
	for kind in placement_details.opening_buttons:controls["opening_"+kind]=placement_details.opening_buttons[kind]
	_preview_footer=PanelContainer.new()
	_preview_footer.add_theme_stylebox_override("panel",_footer_style(false))
	preview_column.add_child(_preview_footer)
	var preview_actions:=HFlowContainer.new()
	_build_footer_actions=preview_actions
	preview_actions.add_theme_constant_override("h_separation",9)
	_preview_footer.add_child(preview_actions)
	HospitalA2Skin.button(_add_button(preview_actions,"cancel","取消",touch.cancel),"paper",15)
	HospitalA2Skin.button(_add_button(preview_actions,"build_back","返回",_back_placement_step),"paper",15)
	controls.build_back.hide()
	var header_row:Node=_build_task_title.get_parent()
	controls.build_back.reparent(header_row)
	header_row.move_child(controls.build_back,0)
	HospitalA2Skin.button(_add_button(preview_actions,"confirm","确认建造",_confirm_placement),"primary",15)
	_placement_tools=_panel()
	_placement_tools.add_theme_stylebox_override("panel",HospitalA2Skin.style("enamel",4))
	var tools_row:=HBoxContainer.new()
	_placement_tools_row=tools_row
	_placement_tools.add_child(tools_row)
	HospitalA2Skin.button(_add_button(tools_row,"rotate","旋转",_use_placement_tool),"paper",15,"rotate")
	HospitalA2Skin.button(_add_button(tools_row,"reposition","换个位置",touch.reposition),"paper",15)
	for key:String in placement_details.wizard_buttons:
		var button:Button=placement_details.wizard_buttons[key]
		button.reparent(preview_actions)
		controls["wizard_"+key]=button
	placement_details.wizard_buttons.decor_openings.pressed.connect(_edit_build_openings)
	_placement_badge=_panel()
	_placement_badge.add_theme_stylebox_override("panel",HospitalA2Skin.style("paper",8))
	_preview=_label("",17)
	_preview.autowrap_mode=TextServer.AUTOWRAP_OFF
	_preview.clip_text=true
	_preview.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	_placement_badge.add_child(_preview)
	_recovery_panel=_panel()
	_recovery_panel.name="RecoveryReadout"
	_recovery_panel.add_theme_stylebox_override("panel",HospitalA2Skin.style("quiet",7))
	var recovery_row:=HBoxContainer.new()
	recovery_row.add_theme_constant_override("separation",7)
	_recovery_panel.add_child(recovery_row)
	_recovery_mark=HospitalUiStyle.picture(HospitalA2Skin.icon("bed",30),Vector2(30,30),0)
	_recovery_mark.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_recovery_mark.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	recovery_row.add_child(_recovery_mark)
	_hint=_label("",12)
	_hint.autowrap_mode=TextServer.AUTOWRAP_OFF
	_hint.clip_text=true
	_hint.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	_hint.add_theme_color_override("font_color",HospitalA2Skin.INK)
	_hint.add_theme_font_override("font",HospitalUiStyle.font(550))
	_hint.add_theme_constant_override("line_spacing",-2)
	_hint.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_hint.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	recovery_row.add_child(_hint)
	_hint.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_settlement_panel=_panel()
	var ledger_column:=VBoxContainer.new()
	ledger_column.add_theme_constant_override("separation",0)
	_settlement_panel.add_child(ledger_column)
	_settlement_title=_drawer_header(ledger_column,"经营账本","close_settlement",func() -> void: _settlement_panel.hide(); _update_nav(""))
	var settlement_scroll:=_scroll(ledger_column)
	settlement_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	_ledger=HospitalLedger.new()
	_ledger.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	settlement_scroll.add_child(_ledger)
	_operations_drawer=_panel()
	var operations_column:=VBoxContainer.new()
	operations_column.add_theme_constant_override("separation",0)
	_operations_drawer.add_child(operations_column)
	_operations_title=_drawer_header(operations_column,"诊疗流程","close_operations",_close_drawers)
	var operations_scroll:=_scroll(operations_column)
	operations_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	operations=HospitalOperationsPanel.new()
	operations.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	operations_scroll.add_child(operations)
	_operations_footer=PanelContainer.new()
	_operations_footer.add_theme_stylebox_override("panel",_footer_style(false))
	operations_column.add_child(_operations_footer)
	var operation_actions:=HFlowContainer.new()
	operation_actions.add_theme_constant_override("h_separation",9)
	operation_actions.add_theme_constant_override("v_separation",9)
	_operations_footer.add_child(operation_actions)
	operations.action_footer=operation_actions
	operations.initialize(session.catalog)
	operations.command_requested.connect(session.issue)
	operations.recovery_requested.connect(_locate_recovery)
	operations.patients_requested.connect(func() -> void: _navigate("patients"))
	operations.stage_requested.connect(_show_patients_stage)
	operations.congestion_requested.connect(_show_congestion)
	if world!=null:
		_preview_root=Node3D.new()
		world.add_child(_preview_root)
	touch.placement_changed.connect(_placement_changed)
	touch.selection_requested.connect(select_entity)
	session.command_result.connect(_command_result)
	for drawer in [_left,_right,_utility,_settlement_panel,_operations_drawer,_preview_panel]:
		drawer.visibility_changed.connect(_sync_drawer_layout)
	get_viewport().size_changed.connect(_layout)
	_close_drawers()
	_settlement_panel.hide()
	flow=HospitalFlowPages.new()
	flow.z_index=2
	add_child(flow)
	flow.initialize(session)
	flow.opening.connect(touch.reset_input)
	flow.opening.connect(settings_page.cancel_drafts)
	flow.action_requested.connect(_flow_action)
	flow.visibility_changed.connect(_sync_experience_display)
	campaign_panel=CampaignHospitalPanel.new()
	add_child(campaign_panel)
	campaign_panel.initialize(session)
	campaign_panel.world=world
	campaign_panel.focus_requested.connect(_campaign_focus)
	campaign_panel.closed.connect(func()->void:_update_nav(""))
	campaign_panel.layout_changed.connect(_sync_drawer_layout)
	campaign_panel.visibility_changed.connect(_sync_experience_display)
	flow.opening.connect(func()->void:campaign_panel.close())
	campaign_build=CampaignBuildEditor.new()
	add_child(campaign_build)
	campaign_build.initialize(session,world,_hits_campaign_external)
	campaign_build.active_changed.connect(_campaign_build_active_changed)
	campaign_build.preview_changed.connect(_campaign_build_preview)
	campaign_build.committed.connect(_campaign_build_committed)
	campaign_build.controller.changed.connect(_campaign_build_view_changed)
	campaign_panel.scene_build_requested.connect(begin_campaign_build)
	flow.opening.connect(_cancel_campaign_build)
	opening_card=CampaignOpeningCard.new()
	add_child(opening_card)
	opening_card.action_requested.connect(_campaign_opening_action)
	controls.opening_action=opening_card.action_button
	patient_card=CampaignPatientCard.new()
	add_child(patient_card)
	patient_card.initialize(session)
	patient_card.closed.connect(func()->void:_opening_signature="";_sync_world_framing.call_deferred())
	patient_card.all_patients_requested.connect(func()->void:_show_campaign("patients"))
	patient_card.preparation_requested.connect(_patient_preparation_requested)
	patient_card.decision_submitted.connect(func(_result:Dictionary)->void:_opening_signature="";present())
	flow.opening.connect(func()->void:patient_card.close())
	staffing_card=StaffingCard.new()
	add_child(staffing_card)
	staffing_card.initialize(session)
	staffing_card.closed.connect(func()->void:_opening_signature="";present();_sync_world_framing.call_deferred())
	staffing_card.manage_requested.connect(_staffing_management_requested)
	flow.opening.connect(func()->void:staffing_card.close())
	if world!=null:
		_campaign_overlay=CampaignBuildOverlay.new()
		world.add_child(_campaign_overlay)
	_layout()
	_placement_changed()
	present()

func _status_chip(parent: Node, icon_name: String, copy: String, unit_copy: String, color: Color=HospitalUiStyle.INK) -> Label:
	var index:int=_status_cards.size()
	var card:=PanelContainer.new()
	_status_cards.append(card)
	card.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	card.clip_contents=true
	card.add_theme_stylebox_override("panel",HospitalA2Skin.style("clock" if index==2 else "paper",4))
	parent.add_child(card)
	var row:=HBoxContainer.new()
	row.add_theme_constant_override("separation",7)
	card.add_child(row)
	var mark:=HospitalUiStyle.picture(HospitalUiStyle.icon("check" if index==1 else icon_name,26),Vector2(26,26),0)
	mark.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mark.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	mark.self_modulate=HospitalA2Skin.GOLD if index==0 else HospitalA2Skin.CORAL if index==1 else color
	row.add_child(mark)
	_status_marks.append(mark)
	var readout:=VBoxContainer.new()
	readout.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	readout.alignment=BoxContainer.ALIGNMENT_CENTER
	readout.add_theme_constant_override("separation",0)
	row.add_child(readout)
	var unit:=HospitalUiStyle.text(unit_copy,11,HospitalA2Skin.PAPER if index==2 else HospitalA2Skin.MUTED,500)
	unit.autowrap_mode=TextServer.AUTOWRAP_OFF
	unit.clip_text=true
	unit.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	readout.add_child(unit)
	_status_units.append(unit)
	var label:=HospitalUiStyle.text(copy,24,HospitalA2Skin.PAPER if index==2 else HospitalA2Skin.INK,750)
	label.autowrap_mode=TextServer.AUTOWRAP_OFF
	label.clip_text=true
	label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	readout.add_child(label)
	return label

func _add_icon_button(parent: Node, key: String, icon_name: String, tip: String, action: Callable) -> Button:
	var b:=_add_button(parent,key,"",action)
	b.icon=HospitalUiStyle.icon(icon_name)
	b.tooltip_text=tip
	b.set_meta("fixed_width",true)
	b.size_flags_horizontal=Control.SIZE_SHRINK_END
	return b

func _drawer_header(parent: Node, title: String, close_key: String, action: Callable) -> Label:
	var bar:=PanelContainer.new()
	var construction_header:bool=close_key in ["close_build","close_preview"]
	bar.add_theme_stylebox_override("panel",HospitalA2Skin.style("enamel",0) if construction_header else HospitalUiStyle.bevel(HospitalUiStyle.DEEP,0))
	parent.add_child(bar)
	var margin:=MarginContainer.new()
	_drawer_headers.append(margin)
	margin.add_theme_constant_override("margin_left",12)
	margin.add_theme_constant_override("margin_right",4)
	margin.add_theme_constant_override("margin_top",0)
	margin.add_theme_constant_override("margin_bottom",0)
	bar.add_child(margin)
	var row:=HBoxContainer.new()
	row.add_theme_constant_override("separation",8)
	margin.add_child(row)
	var icon_key:String={"close_build":"home","close_detail":"person","close_settings":"settings"}.get(close_key,"chart")
	var mark:=HospitalUiStyle.icon_picture(icon_key,20)
	mark.self_modulate=HospitalUiStyle.PAPER
	row.add_child(mark)
	var label:=HospitalUiStyle.text(title,18,HospitalUiStyle.PAPER,700)
	label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	label.clip_text=true
	label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(label)
	var close:=_add_icon_button(row,close_key,"close","关闭",action)
	if construction_header:HospitalA2Skin.button(close,"paper",16,"close")
	else:close.add_theme_stylebox_override("normal",HospitalUiStyle.bevel(HospitalUiStyle.SOFT,4))
	return label

func _footer_style(short_landscape: bool) -> StyleBoxFlat:
	var style:=HospitalUiStyle.panel(2,HospitalUiStyle.SOFT,0)
	style.set_border_width_all(0)
	style.border_width_top=1
	style.border_color=HospitalUiStyle.LINE
	style.corner_radius_bottom_left=4
	style.corner_radius_bottom_right=4
	style.content_margin_left=8 if short_landscape else 10
	style.content_margin_right=8 if short_landscape else 10
	style.content_margin_top=4 if short_landscape else 6
	style.content_margin_bottom=4 if short_landscape else 6
	return style

func _close_drawers() -> void:
	_cancel_campaign_build()
	if staffing_card!=null:staffing_card.close()
	if patient_card!=null:patient_card.close()
	if campaign_panel!=null:
		campaign_panel.hide()
		campaign_panel.picking_origin=false
		if world!=null:world.clear_campaign_preview()
	if settings_page!=null: settings_page.cancel_drafts()
	if _left!=null: _left.hide()
	if _right!=null: _right.hide()
	if _utility!=null: _utility.hide()
	if _settlement_panel!=null: _settlement_panel.hide()
	if _operations_drawer!=null: _operations_drawer.hide()
	_update_nav("")

func _update_nav(active: String) -> void:
	# The closed-world home keeps construction as a primary call to action;
	# active drawers retain their own visual emphasis and all original routes.
	var emphasized:String=active if active!="" else "build"
	for key in _nav_buttons:
		var b:Button=_nav_buttons[key]
		HospitalA2Skin.button(b,"primary" if key==emphasized else "paper",16)
		# Keep real Button.text for accessibility while the authored icon/label
		# family is stacked vertically inside the same interactive button.
		for state in ["font_color","font_hover_color","font_pressed_color","font_hover_pressed_color","font_focus_color","font_disabled_color"]:
			b.add_theme_color_override(state,Color.TRANSPARENT)
		if _nav_labels.has(key):
			_nav_labels[key].add_theme_color_override("font_color",HospitalA2Skin.PAPER if key==emphasized else HospitalA2Skin.INK)
	_sync_drawer_layout()

func _construction_catalog_open() -> bool:
	return _left!=null and _left.visible and _left_title!=null and _left_title.text=="建设医院"

func _construction_overlay_open() -> bool:
	return _construction_catalog_open() or (_preview_panel!=null and _preview_panel.visible) or (campaign_panel!=null and campaign_panel.visible and campaign_panel.section=="facilities")

func _console_bounds() -> Rect2:
	var extent:Vector2=size if size.x>0 and size.y>0 else _safe.end
	# The art's side gutters are a minimum, not extra padding added on top
	# of a physical notch. Real OS insets can always move these edges inward.
	var left:float=maxf(_safe.position.x,roundf(extent.x*.056))
	var right:float=minf(_safe.end.x,extent.x-roundf(extent.x*.056))
	var top:float=maxf(_safe.position.y,12)
	var bottom:float=minf(_safe.end.y,extent.y-24)
	return Rect2(Vector2(left,top),Vector2(maxf(48,right-left),maxf(100,bottom-top)))

func _sync_drawer_layout() -> void:
	if _settlement_panel==null: return
	var short_landscape:=_safe.size.y<430
	var construction:=_construction_overlay_open()
	var show_console:=not (flow!=null and flow.page=="launch") and not construction
	for group in [_dock,_top_frame,_crest,_top,_bottom,_actions,_recovery_panel,_hint]:
		if group!=null:group.visible=show_console
	var bounds:=_console_bounds()
	_crest.visible=show_console and bounds.size.x>=660
	var top:float=_top_frame.position.y+_top_frame.size.y+8 if show_console else bounds.position.y
	var bottom:float=_dock.position.y-8 if show_console else bounds.end.y
	var height:=maxf(80,bottom-top)
	for panel in [_left,_right,_settlement_panel,_preview_panel,_operations_drawer]:
		if panel==null: continue
		var a2_panel:bool=(panel==_left and _construction_catalog_open()) or panel==_preview_panel
		panel.add_theme_stylebox_override("panel",HospitalA2Skin.style("enamel",2) if a2_panel else HospitalUiStyle.bevel(HospitalUiStyle.PAPER,2))
		panel.position.y=top
		panel.size.y=height
	if _construction_catalog_open():
		_left.size.x=minf(570,bounds.size.x)
		_left.position.x=bounds.end.x-_left.size.x
	else:
		_left.size.x=minf(360.0 if _compact else 450.0,_safe.size.x-24)
		_left.position.x=_safe.position.x+12
	# The real four-step free builder opens as a left construction sheet;
	# object detail/legacy relocation retain their existing right drawer.
	var free_preview:bool=_preview_panel.visible and touch.free_build!=null
	if free_preview:
		_preview_panel.size.x=minf(310,bounds.size.x)
		_preview_panel.add_theme_stylebox_override("panel",HospitalA2Skin.style("paper",2))
		var task_height:float=minf(height,maxf(placement_details.preferred_task_height(),_preview_panel.get_combined_minimum_size().y))
		_preview_panel.size.y=task_height
		_preview_panel.position.x=bounds.position.x
		_preview_panel.position.y=bounds.end.y-task_height
	else:
		_preview_panel.position.x=_right.position.x
		_preview_panel.size.x=_right.size.x
	var tools_width:float=minf(300,maxf(144,bounds.size.x-_preview_panel.size.x-18)) if free_preview else minf(240,maxf(144,bounds.size.x-_right.size.x-18))
	if bounds.size.x-_preview_panel.size.x<162:
		# On narrow layouts, tools get their own bottom row instead of
		# covering the builder's pinned confirm/cancel footer.
		_preview_panel.size.y=maxf(80,height-68)
		tools_width=minf(300,bounds.size.x)
	_placement_tools.size=Vector2(tools_width,60)
	_placement_tools.position=Vector2(bounds.end.x-tools_width if free_preview else bounds.position.x,bounds.end.y-60)
	# System settings retain their independent, centered, full-height view.
	_utility.add_theme_stylebox_override("panel",HospitalUiStyle.bevel(HospitalUiStyle.PAPER,2))
	_utility.size=Vector2(minf(600,_safe.size.x-24),minf(500,_safe.size.y-24))
	_utility.position=_safe.position+(_safe.size-_utility.size)*.5
	if campaign_panel!=null:
		campaign_panel.panel.position.y=top
		campaign_panel.panel.size.y=height
	for header in _drawer_headers:
		header.add_theme_constant_override("margin_top",0)
		header.add_theme_constant_override("margin_bottom",0)
	for scroll in _drawer_scrolls:
		var inset:=StyleBoxEmpty.new()
		inset.content_margin_left=8 if short_landscape else 10
		inset.content_margin_right=8 if short_landscape else 10
		inset.content_margin_top=6 if short_landscape else 10
		inset.content_margin_bottom=6 if short_landscape else 10
		scroll.add_theme_stylebox_override("panel",inset)
	if placement_details!=null:
		placement_details.configure_short_landscape(short_landscape)
		if placement_details.pinned_header.visible:
			var header_index:int=1 if touch.free_build!=null else 2
			var preview_column:Node=_preview_panel.get_child(0)
			if placement_details.pinned_header.get_index()!=header_index:preview_column.move_child(placement_details.pinned_header,header_index)
			var preview_scroll:ScrollContainer=placement_details.get_parent()
			var body_inset:StyleBoxEmpty=preview_scroll.get_theme_stylebox("panel").duplicate()
			body_inset.content_margin_top=0 if short_landscape else 10
			body_inset.content_margin_bottom=0 if short_landscape else 10
			preview_scroll.add_theme_stylebox_override("panel",body_inset)
	if selection!=null: selection.configure_short_landscape(short_landscape)
	if _selection_footer!=null: _selection_footer.add_theme_stylebox_override("panel",_footer_style(short_landscape))
	for footer in [_operations_footer,_settings_footer]:
		if footer!=null: footer.add_theme_stylebox_override("panel",_footer_style(short_landscape))
	if _preview_footer!=null:_preview_footer.add_theme_stylebox_override("panel",HospitalA2Skin.style("enamel",4))
	_sync_world_framing()

func _sync_world_framing() -> void:
	if world==null or world.camera_rig==null:return
	var left:float=_safe.position.x+12
	var right:float=_safe.end.x-12
	var top:float=_top_frame.position.y+_top_frame.size.y+8 if _top_frame.visible else _safe.position.y+8
	var bottom:float=_dock.position.y-8 if _dock.visible else _safe.end.y-8
	if _placement_tools.visible:bottom=minf(bottom,_placement_tools.position.y-8)
	if _left.visible:
		if _construction_catalog_open():right=minf(right,_left.position.x-18)
		else:left=maxf(left,_left.position.x+_left.size.x+18)
	for drawer in [_right,_settlement_panel,_operations_drawer]:
		if drawer!=null and drawer.visible:right=minf(right,drawer.position.x-18)
	if _preview_panel.visible:
		if touch.free_build!=null:left=maxf(left,_preview_panel.position.x+_preview_panel.size.x+18)
		else:right=minf(right,_preview_panel.position.x-18)
	if campaign_panel!=null and campaign_panel.visible and not campaign_panel.is_full_page():right=minf(right,campaign_panel.panel.position.x-18)
	if campaign_build!=null and campaign_build.active:
		left=maxf(left,campaign_build.card.position.x+campaign_build.card.size.x+12)
	if patient_card!=null and patient_card.visible:right=minf(right,patient_card.position.x-12)
	if staffing_card!=null and staffing_card.visible:right=minf(right,staffing_card.position.x-12)
	right=maxf(left+48,right)
	bottom=maxf(top+48,bottom)
	var center:=Vector2((left+right)*.5,(top+bottom)*.5)
	world.camera_rig.set_scene_anchor(center*scale/get_viewport_rect().size.max(Vector2.ONE),Vector2(right-left,bottom-top)*scale/get_viewport_rect().size.max(Vector2.ONE))

func _navigate(key: String) -> void:
	if session.is_campaign():
		_show_campaign({"build":"facilities","staff":"staff","patients":"cases","finance":"finance"}.get(key,"cases"))
		return
	touch.reset_input()
	if key=="build":
		_toggle_build()
	elif key=="finance":
		_show_settlement()
	else:
		selection.show_list(key)
		_show_selection()
		present()
	_update_nav(key)

func _show_settings() -> void:
	touch.reset_input()
	var was_visible:=_utility.visible
	_close_drawers()
	_utility.visible=not was_visible

func _show_hospital_flow() -> void:
	_show_operations("flow")

func _show_patients_stage(stage: String) -> void:
	touch.reset_input()
	selection.show_list("patients",stage)
	_show_selection()
	present()
	_update_nav("patients")

func _show_congestion() -> void:
	_show_operations("congestion")

func _show_operations(kind: String) -> void:
	touch.reset_input()
	_close_drawers()
	operations.show_view(kind,session.sim.snapshot())
	if operations.get_parent() is ScrollContainer:
		operations.get_parent().scroll_vertical=0
		operations.get_parent().set_deferred("scroll_vertical",0)
	_operations_title.text="诊疗流程" if kind=="flow" else "恢复区拥堵"
	_operations_drawer.show()
	_update_nav("patients")
	_apply_targets(self)

func _locate_recovery() -> void:
	var id: String=operations.summary.get("recovery_id","")
	if id!="": select_entity(id,"rooms")
	elif operations.view=="congestion": _begin_build("recovery")

func open_launch() -> void:
	_restart_level_id=""
	touch.cancel()
	_close_drawers()
	if not session.storage_blocked and not session.sim.snapshot().paused: session.issue("set_paused",{"paused":true})
	flow.show_launch()
	if session.storage_blocked: flow.show_storage()
	present()
	# A system-menu backdrop starts from a genuine hospital overview rather
	# than retaining the last off-centre employee or room close-up.
	if world!=null and world.camera_rig!=null:
		world.focus_cell(179)
		var aspect:float=get_viewport_rect().size.x/maxf(1,get_viewport_rect().size.y)
		world.camera_rig.set_zoom(minf(18.0,ReferenceHallArt.REFERENCE_FRAME_SIZE.x/maxf(1,aspect)*.94))

func _show_pause() -> void:
	touch.cancel()
	_close_drawers()
	if not session.storage_blocked and not session.sim.snapshot().paused: session.issue("set_paused",{"paused":true})
	flow.show_pause()

func _manual_save() -> void:
	var result:=session.save_now()
	feedback_result.emit(result)
	flow.show_save(result)

func _request_restart() -> void:
	_restart_return="pause"
	_restart_level_id=str(session.sim.snapshot().level_id)
	flow.show_restart(_restart_level_id)

func _flow_action(action: String) -> void:
	match action:
		"new_formal":
			if session.storage_blocked:flow.show_storage()
			elif session.sim.snapshot().tick>0 or not session.sim.snapshot().rooms.is_empty() or not session.sim.snapshot().staff.is_empty():
				_restart_return="launch"
				_restart_level_id=session.default_new_level_id()
				flow.show_restart(_restart_level_id)
			else:
				var started:Dictionary=session.start_new_hospital()
				feedback_result.emit(started)
				if started.get("ok",false):
					flow.close()
					session.dismiss_notice()
				elif session.storage_blocked:flow.show_storage()
				else:flow.show_launch()
		"choose_level": flow.show_levels()
		"next_level":
			var next:Dictionary=session.next_level_info()
			if next.ok:
				_next_career_confirmation=true
				_restart_return="levels"
				_restart_level_id=str(next.data.level.id)
				flow.show_restart(_restart_level_id)
		"continue", "hospital":
			flow.close()
			if session.storage_blocked: flow.show_storage()
			elif session.notice in ["已保存。","已载入存档；营业保持暂停。"]:session.dismiss_notice()
		"new":
			if session.storage_blocked: flow.show_storage()
			elif session.sim.snapshot().tick>0 or not session.sim.snapshot().rooms.is_empty() or not session.sim.snapshot().staff.is_empty():
				_restart_return="launch"
				_restart_level_id=str(session.sim.snapshot().level_id)
				flow.show_restart(_restart_level_id)
			else: _start_fresh_guide()
		"guide_build":
			if session.is_campaign():
				flow.close()
				if int(session.presentation_snapshot().get("campaign",{}).get("opening_loop_version",0))==1:
					_campaign_opening_action(CampaignOpeningGuide.current(session.presentation_snapshot(),session.catalog).get("focus",{}))
				else:_show_campaign("cases")
				return
			flow.close()
			if session.notice!="": session.dismiss_notice()
			_toggle_build()
		"resume":
			flow.close()
			session.issue("set_paused",{"paused":false})
		"continue_hospital":
			var continued:Dictionary=session.issue("continue_hospital")
			if continued.get("ok",false):
				flow.close()
				session.notice="本院已保留。当前暂停，点播放后继续接诊。"
		"save": _manual_save()
		"help":
			flow.close()
			_show_settings()
		"menu": open_launch()
		"pause": _show_pause()
		"restart": _request_restart()
		"cancel_restart":
			_next_career_confirmation=false
			_restart_level_id=""
			if _restart_return=="launch": flow.show_launch()
			elif _restart_return=="levels": flow.show_levels()
			else: flow.show_pause()
		"confirm_restart": _start_fresh_guide()
		"unlock_later":
			flow.close()
			session.dismiss_notice()
		"recover":
			var result:=session.recover_new_game()
			feedback_result.emit(result)
			if result.ok:
				_seen_unlock=""
				flow.show_guide()
			else: flow.show_storage()
		_:
			if action.begins_with("select_level:"):
				_next_career_confirmation=false
				var selected:=action.trim_prefix("select_level:")
				if session.catalog.levels.has(selected):
					_restart_return="levels"
					_restart_level_id=selected
					flow.show_restart(selected)
			elif action.begins_with("unlock_build:"):
				flow.close()
				session.dismiss_notice()
				_begin_build(action.trim_prefix("unlock_build:"))
	present()

func _start_fresh_guide() -> void:
	touch.cancel()
	_close_drawers()
	var result: Dictionary=session.next_level() if _next_career_confirmation else session.start_level(_restart_level_id) if _restart_level_id!="" else {"ok":true}
	_next_career_confirmation=false
	if not result.get("ok",false):
		if session.storage_blocked: flow.show_storage()
		else: flow.show_levels()
		return
	if _restart_level_id=="": session.restart()
	_restart_level_id=""
	_seen_unlock=""
	if int(session.presentation_snapshot().get("campaign",{}).get("opening_loop_version",0))==1:
		flow.close()
		session.dismiss_notice()
		return
	flow.show_guide()

func _show_recruitment() -> void:
	if session.is_campaign():_show_campaign("staff");return
	if session.storage_blocked: return
	if session.notice!="": session.dismiss_notice()
	_close_drawers()
	_left_title.text="招聘员工"
	palette.show_recruitment(true)
	_left.show()
	_update_nav("staff")

func _panel() -> PanelContainer:
	var result:=PanelContainer.new()
	add_child(result)
	return result

func _scroll(parent: Control) -> ScrollContainer:
	var scroll:=ScrollContainer.new()
	_drawer_scrolls.append(scroll)
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	return scroll

func _label(copy: String, font_size: int) -> Label:
	var result:=Label.new()
	result.text=copy
	result.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	result.add_theme_font_size_override("font_size",font_size)
	return result

func _add_button(parent: Node, key: String, copy: String, action: Callable) -> Button:
	var control:=BuildPalette.button(copy)
	controls[key]=control
	parent.add_child(control)
	control.pressed.connect(action)
	return control

func _layout() -> void:
	var viewport_size:=get_viewport_rect().size
	var output:=Vector2(DisplayServer.window_get_size())
	if output.x<=0: output=viewport_size
	var physical_safe:=Rect2(Vector2.ZERO,output)
	if OS.has_feature("android") or OS.has_feature("ios"): physical_safe=Rect2(DisplayServer.get_display_safe_area())
	configure_display(output,viewport_size,DisplayServer.screen_get_dpi(),physical_safe)

func configure_display(output_pixels: Vector2, viewport_size: Vector2, dpi: float, physical_safe: Rect2) -> void:
	var metrics:=layout_metrics(output_pixels,viewport_size,dpi,physical_safe)
	var ui_scale: float=metrics.target/48.0
	var density_changed:bool=not scale.is_equal_approx(Vector2.ONE*ui_scale)
	scale=Vector2.ONE*ui_scale
	if density_changed:
		# Godot 4.7 retains child sampling after a parent Control scale change.
		# Reapply inheritance once per density change to refresh every icon draw.
		oversampling_with_scale=CanvasItem.OVERSAMPLING_WITH_SCALE_DISABLED
		oversampling_with_scale=CanvasItem.OVERSAMPLING_WITH_SCALE_ENABLED
	theme.default_font.base_font.oversampling=maxf(1.0,ui_scale)
	HospitalUiStyle.font().base_font.oversampling=maxf(1.0,ui_scale)
	size=viewport_size/ui_scale
	_safe=Rect2(metrics.safe.position/ui_scale,metrics.safe.size/ui_scale).grow(-8)
	_target=48.0
	selection.minimum_touch_target=_target
	_compact=_safe.size.x<1100
	_dock_two_rows=_console_bounds().size.x<440
	_compact_header=_dock_two_rows
	_narrow_header=_safe.size.x<740
	_actions_width=204.0 if _narrow_header else 256.0
	_dock_height=126.0 if _dock_two_rows else 80.0
	for index in range(_status_cards.size()):
		_status_cards[index].show()
		_status_cards[index].custom_minimum_size=Vector2(0,48)
		_status_marks[index].visible=_safe.size.x>=620
	_layout_console()
	var left_width:=360.0 if _compact else 450.0
	var right_width:=minf(340.0 if _compact else 400.0,_safe.size.x-24)
	var side_height:=maxf(80,_dock.position.y-_top_frame.position.y-_top_frame.size.y-16)
	_left.position=_safe.position+Vector2(12,8)
	_left.size=Vector2(minf(left_width,_safe.size.x-24),side_height)
	_right.position=_safe.position+Vector2(_safe.size.x-right_width-12,8)
	_right.size=Vector2(right_width,side_height)
	_utility.size=Vector2(minf(600,_safe.size.x-24),minf(500,_safe.size.y-24))
	_utility.position=_safe.position+(_safe.size-_utility.size)*.5
	_operations_drawer.position=_right.position
	_operations_drawer.size=_right.size
	_notice_panel.size=Vector2(minf(360,_safe.size.x-24),88)
	_notice_panel.position=Vector2(_safe.position.x+12,maxf(_safe.position.y+8,_dock.position.y-96))
	_preview_panel.position=_right.position
	_preview_panel.size=_right.size
	var short_landscape:=_safe.size.y<430
	var tools_width:=minf(240,maxf(180,_safe.size.x-right_width-36)) if short_landscape else 240.0
	_placement_tools.size=Vector2(tools_width,60)
	_placement_tools.position=Vector2(_safe.position.x+12 if short_landscape else _safe.position.x+(_safe.size.x-tools_width)/2.0,_dock.position.y-68)
	controls.reposition.text="重选" if short_landscape else "换个位置"
	_placement_badge.size=Vector2(maxf(120,minf(300,_safe.size.x-right_width-36)),48)
	_hint.add_theme_font_size_override("font_size",11 if _dock_two_rows else 12)
	_hint.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	_hint.show()
	var ledger_width:=minf(620,_safe.size.x-24)
	_settlement_panel.position=_safe.position+Vector2(_safe.size.x-ledger_width-12,8)
	_settlement_panel.size=Vector2(ledger_width,side_height)
	palette.configure_short_landscape(_safe.size.y<430)
	_sync_drawer_layout()
	if flow!=null: flow.configure(_safe)
	if campaign_panel!=null:
		campaign_panel.configure(_safe)
		_sync_drawer_layout()
	if campaign_build!=null:campaign_build.configure(_campaign_build_bounds())
	if patient_card!=null:patient_card.configure(_campaign_build_bounds())
	if staffing_card!=null:staffing_card.configure(_campaign_build_bounds())
	_format_status(session.sim.snapshot())
	_sync_actions(session.sim.snapshot())
	_update_preview_visibility.call_deferred()
	_apply_targets(self)
	_sync_experience_display()
	if touch.free_build!=null:_frame_build_room.call_deferred()

func _layout_console() -> void:
	var bounds:=_console_bounds()
	var outer:=8.0
	var gap:=8.0
	var crest_width:=48.0 if bounds.size.x>=660 else 0.0
	var top_rows:bool=bounds.size.x<380
	var top_height:=126.0 if top_rows else 70.0
	_top_frame.position=bounds.position
	_top_frame.size=Vector2(bounds.size.x,top_height)
	_crest.position=_top_frame.position+Vector2(12,15)
	_crest.size=Vector2(40,40)
	_crest.visible=crest_width>0 and _top_frame.visible
	var readout_width:float=minf(650,bounds.size.x-outer*2-crest_width-_actions_width-gap) if not top_rows else bounds.size.x-outer*2
	_top.position=_top_frame.position+Vector2(outer+crest_width,8)
	_top.size=Vector2(maxf(48,readout_width),54)
	_actions.position=Vector2(bounds.end.x-outer-_actions_width,bounds.position.y+(68 if top_rows else 11))
	_actions.size=Vector2(_actions_width,48)
	var nav_button_width:=100.0 if bounds.size.x>=760 else 86.0 if bounds.size.x>=620 else 74.0 if bounds.size.x>=500 else 64.0
	var button_height:=64.0
	var dock_width:float=minf(642,bounds.size.x)
	_dock_two_rows=dock_width<440
	_dock_height=126 if _dock_two_rows else 80
	if _dock_two_rows:
		nav_button_width=maxf(48,floorf((dock_width-outer*2-18)/4))
		button_height=56
	var nav_width:=nav_button_width*4+18.0
	_dock.position=Vector2(bounds.end.x-dock_width,bounds.end.y-_dock_height)
	_dock.size=Vector2(dock_width,_dock_height)
	for key in _nav_buttons:
		var nav_button:Button=_nav_buttons[key]
		nav_button.set_meta("minimum_size",Vector2(nav_button_width,button_height))
		nav_button.custom_minimum_size=Vector2(nav_button_width,button_height)
	_bottom.size=Vector2(nav_width,button_height)
	_bottom.position=Vector2(_dock.position.x+outer if _dock_two_rows else _dock.position.x+dock_width-outer-nav_width,_dock.position.y+(62 if _dock_two_rows else outer))
	_recovery_panel.position=_dock.position+Vector2(outer,outer)
	_recovery_panel.size=Vector2(dock_width-outer*2 if _dock_two_rows else maxf(96,dock_width-nav_width-outer*3),48 if _dock_two_rows else 64)
	_recovery_mark.custom_minimum_size=Vector2(24,24) if _dock_two_rows else Vector2(30,30)
	_hint.add_theme_font_size_override("font_size",11 if _dock_two_rows else 12)
	if _staff_badge!=null:
		_staff_badge.size=Vector2(16,16)
		_staff_badge.position=Vector2(nav_button_width-20,4)
	_fit_status()

func _format_status(snapshot: Dictionary) -> void:
	var cash:int=int(snapshot.cash)
	var short_units:=_top.size.x<320
	_stats.text=("%.1f万"%(cash/10000.0)) if _top.size.x<260 and absi(cash)>=10000 else grouped_number(cash)
	_status_units[0].text="资金" if short_units else "可用资金"
	_status_cards[0].tooltip_text="可用资金 %s 币"%grouped_number(cash)
	if session.is_long_campaign():
		var view:Dictionary=_long_view(snapshot)
		var day_ticks:int=maxi(1,int(session.level_data().get("day_ticks",6000)))
		var day:int=int(snapshot.tick)/day_ticks+1
		var completed:int=int(snapshot.metrics.get("completed",0))
		_completed.text=("%.1f万"%(completed/10000.0)) if _top.size.x<260 and completed>=10000 else grouped_number(completed)
		_status_cards[1].tooltip_text="累计治愈 %s 人"%grouped_number(completed)
		_status_units[1].text="治愈" if short_units else "累计治愈"
		_clock.text="%d日"%day
		_status_units[2].text=("暂停" if snapshot.paused else "%d×"%snapshot.speed)+" · %d:%02d"%[snapshot.tick/600,(snapshot.tick/10)%60]
		_status_cards[2].tooltip_text="第%d经营日 · 已营业 %d:%02d"%[day,snapshot.tick/600,(snapshot.tick/10)%60]
		for unit in _status_units:unit.show()
		_top.tooltip_text="%s · %s · 第%d经营日 · 累计治愈%d人 · 在院%d人 · 现金%s币"%[HospitalFlowPages.level_name(session.level_data()),view.get("phase_name","开业"),day,snapshot.metrics.get("completed",0),view.get("live_count",0),grouped_number(int(snapshot.cash))]
		_fit_status.call_deferred(snapshot)
		return
	var total: int=snapshot.scheduled_arrivals.size()
	if snapshot.get("schema_version",1)==2:
		total=0
		for case_id:String in session.level_data().get("case_ids",[]):total+=int(session.catalog.campaign.cases[case_id].get("patient_count",1))
	var level: Dictionary=session.level_data(str(snapshot.level_id))
	_completed.text="%d/%d" % [snapshot.metrics.completed,total]
	_status_cards[1].tooltip_text="已完成 %s / 预约总量 %s 人"%[grouped_number(int(snapshot.metrics.completed)),grouped_number(total)]
	_status_units[1].text="已完成" if short_units else "已完成 / 预约总量"
	_status_units[2].text=("暂停" if snapshot.paused else "%d× 营业"%snapshot.speed) if short_units else ("已暂停 · 时钟" if snapshot.paused else "%d× 营业中"%snapshot.speed)
	_clock.text="%d:%02d" % [snapshot.tick/600,(snapshot.tick/10)%60]
	_status_cards[2].tooltip_text="已营业 %d / %d 秒"%[snapshot.tick/10,level.end_tick/10]
	for unit in _status_units: unit.show()
	_top.tooltip_text="%s · 现金 %s 币 · 完成 %d / %d 人 · %d / %d 秒" % [HospitalFlowPages.level_name(level),grouped_number(int(snapshot.cash)),snapshot.metrics.completed,total,snapshot.tick/10,level.end_tick/10]
	_fit_status.call_deferred(snapshot)

static func grouped_number(value: int) -> String:
	var digits:=str(absi(value))
	var result:=""
	for i in range(digits.length()):
		if i>0 and (digits.length()-i)%3==0: result+=","
		result+=digits[i]
	return ("-" if value<0 else "")+result

func _fit_status(_snapshot:Dictionary={}) -> void:
	# Readouts fit only their assigned cells; they never move into actions.
	var font_size:int=14 if _top.size.x<280 else 18 if _top.size.x<390 else 24
	for label in [_stats,_completed,_clock]:label.add_theme_font_size_override("font_size",font_size)
	for index in range(_status_marks.size()):
		_status_marks[index].visible=index<2 and _top.size.x>=320
		_status_marks[index].custom_minimum_size=Vector2(20,20) if _top.size.x<420 else Vector2(26,26)
	for card in _status_cards:
		card.custom_minimum_size=Vector2(0,54)
		card.show()

func _sync_actions(snapshot: Dictionary) -> void:
	var ended: bool=snapshot.challenge.status!="running"
	var course_complete:bool=session.is_long_campaign() and snapshot.campaign.get("course_complete",false)
	var use_speed_toggle:bool=_narrow_header or course_complete
	controls.restart.visible=ended
	controls.settlement.visible=ended or course_complete
	for key in ["pause","speed1","speed2"]:
		controls[key].visible=not ended and (key=="pause" or not use_speed_toggle)
		controls[key].disabled=session.storage_blocked
	controls.speed_toggle.visible=not ended and use_speed_toggle
	controls.speed_toggle.disabled=session.storage_blocked
	controls.speed_toggle.text="%d×" % snapshot.speed
	var count:=0
	for key in ["pause","speed1","speed2","speed_toggle","save","settings","restart","settlement"]:
		if controls[key].visible:count+=1
	_actions_width=count*48.0+maxi(0,count-1)*4.0
	_style_speed_buttons(snapshot)
	_layout_console()

func _style_speed_buttons(snapshot:Dictionary) -> void:
	var signature:String=str(snapshot.speed)
	if signature==_speed_style_signature:return
	_speed_style_signature=signature
	for speed in [1,2]:
		HospitalA2Skin.button(controls["speed"+str(speed)],"selected" if snapshot.speed==speed else "paper",16)
	HospitalA2Skin.button(controls.speed_toggle,"selected",16)

func _toggle_build() -> void:
	if session.is_campaign():_show_campaign("facilities");return
	if session.storage_blocked: return
	touch.reset_input()
	if session.notice!="": session.dismiss_notice()
	var was_visible:=_left.visible and _left_title.text=="建设医院"
	_close_drawers()
	_left_title.text="建设医院"
	palette.show_recruitment(false)
	_left.visible=not was_visible
	_update_nav("build" if _left.visible else "")

func _show_selection() -> void:
	touch.reset_input()
	_close_drawers()
	_right.show()
	_right_title.text={"rooms":"房间详情","staff":"员工详情","patients":"患者详情"}[selection.selected_group] if selection.selected_id!="" else {"rooms":"房间清单","staff":"员工","patients":"患者"}[selection.selected_group]
	if selection.selected_group=="rooms" and session.sim.snapshot().rooms.has(selection.selected_id):
		_right_title.text=session.catalog.rooms[session.sim.snapshot().rooms[selection.selected_id].kind].name
	_update_nav(selection.selected_group if selection.selected_group in ["staff","patients"] else "build")

func _show_settlement() -> void:
	if session.is_campaign():_show_campaign("finance");return
	_close_drawers()
	var snapshot:=session.sim.snapshot()
	_ledger.present(snapshot)
	_settlement_panel.show()
	_update_nav("finance")
	present()

static func settlement_text(snapshot: Dictionary) -> String:
	var state:=ClinicState.new()
	state.data=snapshot.duplicate(true)
	var m:=Metrics.summary(state)
	var d: Dictionary=m.dispositions
	var clinical: bool=snapshot.level_id=="clinical_02"
	var consumables := "诊疗耗材" if clinical else "治疗耗材"
	var lines: Array[String]=["经营账本" if snapshot.challenge.status=="running" else ("首关达成" if snapshot.level_id=="level_01" else "本关达成") if snapshot.challenge.status=="won" else "本局未达标",
		"患者去向（冻结于 %.1f秒）" % (snapshot.tick/10.0),
		"未到院 %d · 院外等候 %d · 在院未完成 %d · 已完成离院 %d · 已弃诊离院 %d" % [d.not_arrived,d.outside,d.in_hospital,d.completed,d.abandoned],
		"合计 %d 人；弃诊离院中 %d 人（包含在在院未完成中，不重复相加）。" % [d.not_arrived+d.outside+d.in_hospital+d.completed+d.abandoned,d.abandoning],
		"未离院者保留本局状态，不计成功或已弃诊。",
		"经营利润 %+d币 · 现金 %d币" % [m.operating_profit,m.cash],
		"诊疗收入 %d币 − %s %d币 − 恢复耗材 %d币 − 工资 %d币 − 固定支出 %d币" % [m.income,consumables,m.treatment_cost,m.recovery_cost,m.wages,m.fixed_cost]]
	if clinical: lines.append("诊疗耗材包括治疗、发药与留观；恢复耗材单独列出。")
	var capital:={"capital_build":0,"capital_hire":0,"capital_upgrade":0,"capital_refund":0}
	for entry in snapshot.ledger_entries:
		if capital.has(entry.category): capital[entry.category]+=entry.delta
	lines.append("资本收支（不计入经营利润）：建造 %d币 · 招聘 %d币 · 升级 %d币 · 退款 +%d币" % [capital.capital_build,capital.capital_hire,capital.capital_upgrade,capital.capital_refund])
	lines.append("累计非服务等待（含所有已到院者，服务时间除外）")
	for stage in SelectionPanel.stage_rows(snapshot.level_id=="clinical_02"):
		lines.append("%s：%.1f秒" % [stage[1],m.wait_by_stage.get(stage[0],0)/10.0])
	lines.append("已到院 %d人 · 平均等待 %.1f秒" % [m.arrived_count,m.waiting_mean_ticks/10.0])
	lines.append("逐人去向")
	var ids: Array=m.patients.keys()
	ids.sort()
	for id in ids:
		var p: Dictionary=m.patients[id]
		var label: String={"not_arrived":"未到院","outside":"院外等候","in_hospital":"在院未完成","completed":"已完成离院","abandoned":"已弃诊离院"}[p.disposition]
		if p.get("phase","")=="abandoning": label+="（弃诊离院中）"
		lines.append("患者%s · %s" % [id.get_slice("_",1),label])
	return "\n".join(lines)

func _apply_targets(node: Node) -> void:
	if node is Button:
		var minimum: Vector2=node.get_meta("minimum_size",Vector2.ONE*_target)
		node.custom_minimum_size=minimum.max(Vector2.ONE*_target)
		if node.get_parent() is HBoxContainer and not node.get_meta("fixed_width",false):
			node.custom_minimum_size.x=maxf(minimum.x,node.get_theme_font("font").get_string_size(node.text,HORIZONTAL_ALIGNMENT_LEFT,-1,node.get_theme_font_size("font_size")).x+24)
	for child in node.get_children(): _apply_targets(child)

func hits_gui(point: Vector2) -> bool:
	if campaign_build!=null and campaign_build.active and campaign_build.hits_gui(point):return true
	return _hits_campaign_external(point)

func _hits_campaign_external(point: Vector2) -> bool:
	if staffing_card!=null and staffing_card.is_visible_in_tree() and staffing_card.get_global_rect().has_point(point):return true
	if patient_card!=null and patient_card.is_visible_in_tree() and patient_card.get_global_rect().has_point(point):return true
	if opening_card!=null and opening_card.is_visible_in_tree() and opening_card.get_global_rect().has_point(point):return true
	if _experience_button!=null and _experience_button.is_visible_in_tree() and _experience_button.get_global_rect().has_point(point):return true
	if campaign_panel!=null and campaign_panel.visible:
		if campaign_panel.picking_origin:return true
		if campaign_panel.panel.get_global_rect().has_point(point):return true
	if flow!=null and flow.visible: return true
	for panel in [_dock,_top_frame,_recovery_panel,_top,_actions,_bottom,_left,_right,_utility,_notice_panel,_preview_panel,_settlement_panel,_operations_drawer,_placement_tools,_placement_badge]:
		if panel!=null and panel.is_visible_in_tree() and panel.get_global_rect().has_point(point): return true
	return false

func _run_speed(speed: int) -> void:
	session.issue("set_speed",{"speed":speed})
	session.issue("set_paused",{"paused":false})

func _locate_notice() -> void:
	var snapshot:=session.sim.snapshot()
	var target:=session.notice_target.duplicate(true)
	if target.get("group","")=="build":
		_close_drawers()
		_left_title.text="建设医院"
		palette.show_recruitment(false)
		_left.show()
	elif target.get("expand_flow",false) and snapshot.patients.has(target.get("patient_id","")):
		if HospitalOperationsPanel.project(snapshot).blocked_devices>0:
			_show_congestion()
		else:
			select_entity(target.patient_id,"patients")
			selection.expand_flow(target.patient_id)
			present()
		if world!=null and snapshot.rooms.has(target.get("id","")): world.focus_cell(snapshot.rooms[target.id].origin_cell)
	elif snapshot.get(target.get("group",""),{}).has(target.get("id","")):
		select_entity(target.id,target.group)
	session.dismiss_notice()

func _begin_build(kind: String) -> void:
	if session.storage_blocked: return
	_reset_build_task()
	touch.reset_input()
	if session.notice!="": session.dismiss_notice()
	_close_drawers()
	session.issue("set_paused",{"paused":true})
	touch.begin_free_build(kind)
	placement_details.get_parent().scroll_vertical=0
	_left.hide()
	_update_nav("build")

func _begin_move(kind: String, room_id: String) -> void:
	if session.storage_blocked: return
	_reset_build_task()
	touch.reset_input()
	if session.notice!="": session.dismiss_notice()
	_close_drawers()
	session.issue("set_paused",{"paused":true})
	touch.begin_placement(kind,room_id)
	placement_details.get_parent().scroll_vertical=0
	var room:Dictionary=session.sim.snapshot().rooms.get(room_id,{})
	if room.has("layout"):
		touch.placement.layout=room.layout.duplicate(true)
		touch.placement_changed.emit()
	_right.hide()
	_update_nav("build")

func _begin_layout_edit(kind:String,room_id:String) -> void:
	if session.storage_blocked:return
	var room:Dictionary=session.sim.snapshot().rooms.get(room_id,{})
	if room.is_empty():return
	# Conversion is local to this explicit edit gesture. Opening a save or
	# cancelling the draft must leave historical templates and receipts intact.
	var layout:Dictionary=room.layout.duplicate(true) if room.has("layout") else FreeRoomLayout.from_template(kind,int(room.get("rotation",0)))
	if layout.is_empty():return
	_reset_build_task()
	touch.reset_input();_close_drawers()
	session.issue("set_paused",{"paused":true})
	touch.begin_free_build(kind,room_id,layout,room.origin_cell)
	placement_details.get_parent().scroll_vertical=0
	_update_nav("build")

func _confirm_placement() -> void:
	if touch.free_build!=null and touch.free_build.step<3:
		var frame_bounds:bool=touch.free_build.step==0
		var return_decor:bool=_wizard_return_to_decor and touch.free_build.step==1
		if not touch.advance_build_step():return
		if return_decor:
			_wizard_return_to_decor=false
			if touch.free_build.can_advance() and session.preview(_proposal()).ok:touch.advance_build_step()
		if frame_bounds:_frame_build_room()
	else:touch.confirm()

func _back_placement_step() -> void:
	_wizard_return_to_decor=false
	touch.back_build_step()

func _reset_build_task() -> void:
	_wizard_generation+=1
	_wizard_pending={}
	_wizard_return_to_decor=false
	placement_details.reset_task_expansion()

func _wizard_ui_changed() -> void:
	_wizard_generation+=1
	_wizard_pending={}
	if touch!=null and touch.free_build!=null and not touch.placement.is_empty():
		_update_preview_visibility()
		var proposal:=_proposal()
		_present_placement_details(session.sim.snapshot(),proposal,session.preview(proposal))
	_sync_drawer_layout()

func _edit_build_openings() -> void:
	if touch.free_build==null or touch.free_build.step!=3:return
	_wizard_pending={}
	_wizard_return_to_decor=true
	touch.back_build_step()
	touch.back_build_step()
	placement_details.set_opening_options_expanded(true)

func _placement_interaction_finished(step:int,receipt:String) -> void:
	if touch.free_build==null or step not in [1,2] or touch.free_build.step!=step:return
	if touch.placement.get("id","")!=receipt:return
	_wizard_pending={"step":step,"receipt":receipt,"generation":_wizard_generation}
	if not _wizard_auto_queued:
		_wizard_auto_queued=true
		_advance_wizard_interaction.call_deferred()

func _advance_wizard_interaction() -> void:
	_wizard_auto_queued=false
	var pending:=_wizard_pending
	_wizard_pending={}
	if not is_inside_tree() or pending.is_empty() or touch.free_build==null or session.storage_blocked:return
	# A following press still belongs to this task. Its release can schedule the
	# latest completion; an earlier idle callback must not change its meaning.
	if touch.has_active_pointers():return
	if int(pending.generation)!=_wizard_generation or touch.placement.get("id","")!=pending.receipt:return
	var step:int=pending.step
	if touch.free_build.step!=step or step not in [1,2] or not touch.free_build.can_advance():return
	var proposal:=_proposal()
	if not _free_bounds_valid(proposal,session.sim.snapshot()):return
	if step==1:
		if placement_details.opening_options_expanded or touch.free_build.opening_tool!="door":return
	elif not session.preview(proposal).ok:return
	# This path can only advance to equipment/furniture. It never purchases.
	touch.advance_build_step()

func _present_task_controls() -> void:
	var free:bool=touch.free_build!=null
	controls.close_preview.visible=not free
	if not free:
		_build_task_title.text="放置预览"
		controls.confirm.show()
		for button:Button in placement_details.wizard_buttons.values():button.hide()
		if controls.rotate.get_parent()!=_placement_tools_row:controls.rotate.reparent(_placement_tools_row)
		controls.rotate.show();controls.reposition.show()
		return
	var step:int=touch.free_build.step
	_build_task_title.text=placement_details.current_task_title()
	controls.wizard_precision.visible=step==0
	controls.wizard_opening_options.visible=step==1
	controls.wizard_decor_openings.visible=step==3
	var header_row:Node=_build_task_title.get_parent()
	if controls.wizard_decor_openings.get_parent()!=header_row:controls.wizard_decor_openings.reparent(header_row)
	var footer_rotate:bool=step==2 or (step==3 and touch.free_build.furniture_kind!="")
	var destination:Node=_build_footer_actions if footer_rotate else _placement_tools_row
	if controls.rotate.get_parent()!=destination:controls.rotate.reparent(destination)
	controls.rotate.visible=footer_rotate or (step==0 and placement_details.precision_expanded)
	controls.reposition.visible=step==0 and placement_details.precision_expanded
	for key:String in ["cancel","confirm","rotate","wizard_precision","wizard_opening_options","wizard_decor_openings"]:
		var button:Button=controls[key]
		button.set_meta("minimum_size",Vector2(84,48))
		button.custom_minimum_size=Vector2(maxf(84,_target),maxf(48,_target))
	controls.build_back.set_meta("minimum_size",Vector2(60,48))
	controls.build_back.custom_minimum_size=Vector2(maxf(60,_target),maxf(48,_target))
	_build_footer_actions.add_theme_constant_override("h_separation",6)
	_build_footer_actions.move_child(controls.confirm,_build_footer_actions.get_child_count()-1)
	controls.confirm.text=["确定大小","门窗完成" if placement_details.opening_options_expanded else "沿用入口","设备就位","完成改造" if touch.free_build.room_id!="" else "建好房间"][step]
	controls.confirm.visible=step==0 or step==3 or (step==1 and placement_details.opening_options_expanded) or not controls.confirm.disabled

func _use_placement_tool() -> void:
	if touch.free_build!=null and touch.free_build.step==0:_frame_build_room(false)
	else:touch.rotate()

func _frame_build_room(require_valid:bool=true) -> void:
	if touch.free_build==null:return
	var p:=_proposal()
	if p.get("origin_cell",-1)<0 or int(p.layout.get("width",0))<=0 or int(p.layout.get("height",0))<=0:return
	if require_valid and not _free_bounds_valid(p,session.sim.snapshot()):return
	var cells:Array=[]
	for y in range(int(p.layout.get("height",0))):
		for x in range(int(p.layout.get("width",0))):cells.append(p.origin_cell+y*24+x)
	world.focus_room({"cells":cells})

func _proposal() -> Dictionary:
	var result:=touch.placement.duplicate(true)
	result.erase("id")
	if result.get("room_id","")=="": result.erase("room_id")
	elif session.sim.snapshot().rooms.has(result.room_id): result.upgraded=session.sim.snapshot().rooms[result.room_id].upgraded
	return result

func _restore_editing_room() -> void:
	if is_instance_valid(world):world.set_wall_preview({})
	if is_instance_valid(world) and world.room_views.has(_editing_preview_room):
		var room_view:Node3D=world.room_views[_editing_preview_room]
		if is_instance_valid(room_view):room_view.show()
	_editing_preview_room=""

func _sync_editing_room_visibility() -> void:
	var editing_id:String=touch.placement.get("room_id","") if is_inside_tree() else ""
	if _editing_preview_room!=editing_id:_restore_editing_room()
	if is_instance_valid(world) and editing_id!="" and world.room_views.has(editing_id):
		var room_view:Node3D=world.room_views[editing_id]
		if is_instance_valid(room_view):room_view.hide()
	_editing_preview_room=editing_id

func _exit_tree() -> void:
	_restore_editing_room()
	if is_instance_valid(_preview_root):
		for child in _preview_root.get_children():
			_preview_root.remove_child(child)
			child.queue_free()
	_preview_signature=""

func _placement_changed() -> void:
	_wizard_generation+=1
	_sync_editing_room_visibility()
	if is_instance_valid(world):world.set_build_grid_visible(not touch.placement.is_empty())
	if is_instance_valid(_preview_root):
		for child in _preview_root.get_children():
			_preview_root.remove_child(child)
			child.queue_free()
	if not is_inside_tree():
		if is_instance_valid(world):world.set_wall_preview({})
		return
	_update_preview_visibility()
	if touch.placement.is_empty():
		if is_instance_valid(world):world.set_wall_preview({})
		_preview_signature=""
		_present_recovery(session.sim.snapshot())
		return
	var p:=_proposal()
	var result:=session.preview(p)
	_preview_signature=JSON.stringify([p,result.ok,result.code])
	_present_placement_details(session.sim.snapshot(),p,result)
	if p.origin_cell<0 or _preview_root==null:
		if is_instance_valid(world):world.set_wall_preview({})
		return
	if p.has("layout"):
		_draw_free_preview(p,result)
		return
	if is_instance_valid(world):world.set_wall_preview({})
	var definition:=RoomTemplates.definition(p.kind,p.rotation)
	var color:=Color("63c8ac") if result.ok else Color("e98159")
	for cell in definition.cells:
		var x: int=p.origin_cell%24+cell[0]
		var y: int=p.origin_cell/24+cell[1]
		ActorView.box(_preview_root,Vector3(x,0.055,y),Vector3(0.92,0.09,0.92),color)
	if result.ok:
		var door: int=result.data.room.door_cell
		ActorView.box(_preview_root,HospitalWorld.cell_position(door)+Vector3(0,0.14,0),Vector3(0.45,0.15,0.45),Color("f3ba73"))

func _present_placement_details(snapshot: Dictionary, p: Dictionary, result: Dictionary) -> void:
	controls.build_back.visible=touch.free_build!=null and touch.free_build.step>0
	if touch.free_build!=null:
		var draft:FreeBuildDraft=touch.free_build
		var valid:bool=draft.can_advance() and _free_bounds_valid(p,snapshot)
		if draft.step>=2:valid=valid and result.ok
		if draft.step==3:
			var cost:int=FreeRoomLayout.base_cost(p.kind,p.layout,session.catalog,bool(p.get("upgraded",false)))
			var old_cost:int=snapshot.rooms.get(p.get("room_id",""),{}).get("invested_cost",0)
			valid=valid and (cost<=old_cost or cost-old_cost<=snapshot.cash)
		controls.confirm.disabled=not valid
		controls.confirm.text="完成改造" if draft.step==3 and p.has("room_id") else "完成建造" if draft.step==3 else "下一步"
		controls.rotate.disabled=p.origin_cell<0 if draft.step==0 else (draft.step==1 and draft.selected_opening.is_empty())
		controls.rotate.text="放大选区" if draft.step==0 else "换墙面" if draft.step==1 else "旋转"
		controls.rotate.tooltip_text="放大并居中当前房间；双指仍可缩放。" if draft.step==0 else "仅切换选中门窗的墙面" if draft.step==1 else "旋转家具" if draft.step==3 else "旋转必需工作站"
		controls.reposition.text="重画房间"
		var bounds_issue:=_free_bounds_issue(p,snapshot)
		if draft.step==0 and bounds_issue=="" and not draft.can_advance():
			var minimum:Vector2i=EquipmentFootprints.minimum_room(p.kind) if p.layout.has("footprint_version") else Vector2i(3,3) if p.kind in ["reception","recovery"] else Vector2i(4,4)
			bounds_issue="尺寸不足，至少 %d×%d 格（可换向），请调整宽高。"%[minimum.x,minimum.y]
		if draft.step==0 and bounds_issue=="":
			var shrink_issues:Array=[draft.bounds_adjustment_issue(Vector2i(-1,0)),draft.bounds_adjustment_issue(Vector2i(0,-1))]
			if "cropped_opening" in shrink_issues:bounds_issue="边缘有门窗：先在门窗步骤移开，再缩小。"
			elif "cropped_furniture" in shrink_issues:bounds_issue="边缘有家具：先在家具步骤移开，再缩小。"
		placement_details.present_free(snapshot,p,result,draft.step,draft.furniture_kind,draft.opening_tool,draft.selected_opening,bounds_issue,_bounds_adjustment_actions(draft))
		_present_task_controls()
		_hint.text=["点两角或拖框选房 · 框内拖动移动 · 按钮逐格微调","选门窗工具 · 点墙面定位","点地面放设备 · 可旋转","选家具点地面放置 · 再点移除"][draft.step]
		_sync_drawer_layout()
		_preview.text=["划定大小","自由设置门窗","点地面摆设备","家具自选"][draft.step]+(" · %d×%d"%[p.layout.width,p.layout.height] if int(p.layout.get("width",0))>0 else "")
		if draft.step>=2 and not result.ok:_preview.text=SelectionPanel.reason(result.code)
		_position_placement_badge()
		return
	controls.confirm.text="确认移动" if p.has("room_id") else "确认建造"
	controls.rotate.disabled=p.has("layout")
	controls.rotate.text="旋转"
	controls.confirm.disabled=not result.ok
	placement_details.present(snapshot,p,result)
	_present_task_controls()
	_preview.text=("✓ 位置可建" if result.ok else "请点选地面位置" if p.origin_cell<0 else "这里不能建造")+" · "+session.catalog.rooms[p.kind].name
	_position_placement_badge()

func _free_bounds_valid(p:Dictionary,snapshot:Dictionary) -> bool:
	return _free_bounds_issue(p,snapshot)==""

func _bounds_adjustment_actions(draft:FreeBuildDraft) -> Dictionary:
	var changes:Dictionary={
		"width_less":[Vector2i(-1,0),Vector2i.ZERO],"width_more":[Vector2i(1,0),Vector2i.ZERO],
		"height_less":[Vector2i(0,-1),Vector2i.ZERO],"height_more":[Vector2i(0,1),Vector2i.ZERO],
		"move_nw":[Vector2i.ZERO,Vector2i(-1,0)],"move_ne":[Vector2i.ZERO,Vector2i(0,-1)],
		"move_sw":[Vector2i.ZERO,Vector2i(0,1)],"move_se":[Vector2i.ZERO,Vector2i(1,0)]}
	var actions:Dictionary={}
	for key in changes:actions[key]=not draft.adjusted_bounds(changes[key][0],changes[key][1]).is_empty()
	return actions

func _free_bounds_issue(p:Dictionary,snapshot:Dictionary) -> String:
	if p.get("origin_cell",-1)<0:return "请先拖框，或点两个对角划定房间。"
	var layout:Dictionary=p.get("layout",{})
	if int(layout.get("width",0))<=0 or int(layout.get("height",0))<=0:return "请先划出房间，再调整宽高。"
	for y in range(int(layout.get("height",0))):
		for x in range(int(layout.get("width",0))):
			var gx:int=p.origin_cell%24+x
			var gy:int=p.origin_cell/24+y
			if gx<=0 or gx>=23 or gy<=0 or gy>=17:return "房间超出可建区域，请移动或缩小。"
			if gy in [8,9]:return "房间跨越中央通道，请移到通道一侧。"
			for id in snapshot.rooms:
				if id!=p.get("room_id","") and gy*24+gx in snapshot.rooms[id].cells:return "与已有房间重叠，请移动或缩小。"
	return ""

func _draw_free_preview(p:Dictionary,result:Dictionary) -> void:
	var layout:Dictionary=p.layout
	var snapshot:Dictionary=session.sim.snapshot()
	var bounds_ok:=_free_bounds_valid(p,snapshot)
	if is_instance_valid(world):world.set_wall_preview(p if bounds_ok else {})
	var full_ok:=FreeRoomLayout.validate(p.kind,layout,bool(p.get("upgraded",false)))==""
	var color:=Color("d4e2cf") if bounds_ok else Color("edb5a5")
	for y in range(int(layout.get("height",0))):
		for x in range(int(layout.get("width",0))):
			# Preview ground shares the built-room elevation. A raised opaque
			# overlay would bury correctly calibrated machine bases/chair legs.
			ActorView.box(_preview_root,HospitalWorld.cell_position(p.origin_cell)+Vector3(x,(HospitalInteriorArt.ROOM_FLOOR_TOP-.002)*.5,y),Vector3(.975,HospitalInteriorArt.ROOM_FLOOR_TOP-.002,.975),color)
	var preview_proposal:Dictionary=p.duplicate()
	var shared_walls:Dictionary={}
	var shared_windows:Dictionary={}
	var rooms:Dictionary=snapshot.get("rooms",{})
	for room_id in rooms:
		if room_id==p.get("room_id",""):continue
		for edge in rooms[room_id].get("wall_edges",[]):
			shared_walls["%d:%d"%[mini(edge[0],edge[1]),maxi(edge[0],edge[1])]]=true
		for edge in rooms[room_id].get("window_edges",[]):
			shared_windows["%d:%d"%[mini(edge[0],edge[1]),maxi(edge[0],edge[1])]]=true
	preview_proposal.visual_shared_walls=shared_walls
	preview_proposal.visual_window_edges=shared_windows
	preview_proposal.visual_selected_opening=touch.free_build.selected_opening.duplicate() if touch.free_build!=null and touch.free_build.step==1 else {}
	HospitalInteriorArt.build_wall_preview(_preview_root,preview_proposal)
	# Draw the same local station geometry the command validates, including a
	# complete invalid footprint so the player can see which cells need space.
	if not layout.get("equipment",{}).is_empty() and not layout.get("door",{}).is_empty():
		var local:=FreeRoomLayout._definition(p.kind,layout)
		var body_cells:Array=local.equipment_cells.duplicate()
		var operation_cells:Array=local.service_cells+local.staff_cells
		if bool(p.get("upgraded",false)):
			body_cells.append_array(local.upgrade_equipment_cells)
			operation_cells.append_array(local.upgrade_service_cells)
		_draw_free_cell_outlines(p.origin_cell,body_cells,Color("4180a5") if full_ok and bounds_ok else Color("cc7156"),"body")
		_draw_free_cell_outlines(p.origin_cell,operation_cells,Color("259c98"),"operation")
		_draw_free_cell_outlines(p.origin_cell,local.get("clearance_cells",[]),Color("d2a14b"),"maintenance")
		_draw_free_cell_outlines(p.origin_cell,local.furniture_cells,Color("719849"),"furniture")
	if full_ok and bounds_ok:
		var geometry:=GridService._room_geometry(p)
		var apparatus:=RoomView.new()
		_preview_root.add_child(apparatus)
		apparatus.set_meta("visual_room_cells",geometry.cells.duplicate())
		apparatus._build_equipment(geometry)
		for item in layout.furniture:
			var version:int=layout.get("footprint_version",1)
			var prop:=RoomFurniture.create(item.kind,version)
			prop.position=HospitalWorld.cell_position(p.origin_cell+int(item.y)*24+int(item.x))+Vector3(0,HospitalInteriorArt.ROOM_FLOOR_TOP,0)+RoomFurniture.placement_offset(item.kind,item.rotation,version)
			prop.rotation.y=-int(item.rotation)*PI/2
			_preview_root.add_child(prop)
		for cell in geometry.service_cells+geometry.staff_cells:
			ActorView.ring(_preview_root,HospitalWorld.cell_position(cell)+Vector3(0,.095,0),.28,HospitalUiStyle.TEAL)
	if not result.ok and touch.free_build!=null and touch.free_build.step>=2 and not layout.get("equipment",{}).is_empty():
		var equipment:Dictionary=layout.equipment
		ActorView.ring(_preview_root,HospitalWorld.cell_position(p.origin_cell)+Vector3(equipment.x,.12,equipment.y),.4,Color("d77955"))

func _draw_free_cell_outlines(origin:int,cells:Array,color:Color,group:String) -> void:
	for point in cells:
		# Keep local coordinates before conversion: an out-of-bounds X must
		# remain outside the room rather than wrap into the next global row.
		var center:=HospitalWorld.cell_position(origin)+Vector3(point[0],HospitalInteriorArt.ROOM_FLOOR_TOP+.001,point[1])
		for axis in [0,1]:
			for side in [-1,1]:
				var offset:=Vector3(side*.44,0,0) if axis==0 else Vector3(0,0,side*.44)
				var line:=ActorView.box(_preview_root,center+offset,Vector3(.035,.002,.91) if axis==0 else Vector3(.91,.002,.035),color)
				line.set_meta("footprint_group",group)
				line.set_meta("footprint_cell",point.duplicate())

func _refresh_placement(snapshot: Dictionary) -> void:
	if touch.placement.is_empty(): return
	var p:=_proposal()
	var result:=session.preview(p)
	if JSON.stringify([p,result.ok,result.code])!=_preview_signature: _placement_changed()
	else: _present_placement_details(snapshot,p,result)

func _update_preview_visibility() -> void:
	_preview_panel.visible=not touch.placement.is_empty() and not session.storage_blocked
	if _preview_panel.visible and _notice_panel.visible and _notice_panel.get_global_rect().intersects(_preview_panel.get_global_rect()):
		_preview_panel.hide()
	_placement_tools.visible=_preview_panel.visible and (touch.free_build==null or (touch.free_build.step==0 and placement_details.precision_expanded))
	_placement_badge.visible=_preview_panel.visible and touch.free_build==null and _safe.size.y>=430
	_sync_drawer_layout()

func _position_placement_badge() -> void:
	var point:=_safe.position+Vector2(_safe.size.x*0.42,96)
	if world!=null and touch.placement.get("origin_cell",-1)>=0:
		point=get_global_transform().affine_inverse()*world.camera_rig.camera.unproject_position(HospitalWorld.cell_position(touch.placement.origin_cell))
	var width:=minf(300,maxf(160,_preview_panel.position.x-_safe.position.x-36))
	_placement_badge.size=Vector2(width,48)
	var right_limit:float=maxf(_safe.position.x+12,_preview_panel.position.x-width-12)
	var bottom_limit:float=_dock.position.y if _dock.visible else _console_bounds().end.y
	_placement_badge.position=Vector2(clampf(point.x-width/2,_safe.position.x+12,right_limit),clampf(point.y-64,_safe.position.y+8,maxf(_safe.position.y+8,bottom_limit-64)))

func _command_result(result: Dictionary) -> void:
	if session.is_campaign():
		if not result.ok:session.notice=CampaignHospitalPanel.reason_text(result,session.catalog.campaign)
		return
	if not result.ok:
		session.notice=SelectionPanel.command_feedback(result,session.sim.snapshot(),session.notice_target)
		present()

func select_entity(id: String, group: String) -> void:
	if session.is_campaign():
		if group=="patients":
			show_campaign_patient(id)
			return
		_show_campaign({"rooms":"rooms","staff":"staff","patients":"patients"}.get(group,"cases"))
		# A newly opened hospital resets panel drafts on its first render; apply
		# scene identity after that reset, then render the requested actual actor.
		if group=="patients":campaign_panel._focus_patient=id
		elif group=="staff":campaign_panel._selected_staff=id
		elif group=="rooms":campaign_panel._selected_room=id
		campaign_panel._signature=""
		campaign_panel._render()
		_campaign_focus(id,group)
		if group=="staff":_experience_scroll.call_deferred("assign_staff")
		elif group=="rooms":_experience_scroll.call_deferred("edit_"+id)
		return
	selection.select(id,group)
	_show_selection()
	var snapshot:=session.sim.snapshot()
	if world!=null and snapshot[group].has(id):
		var record: Dictionary=snapshot[group][id]
		if group=="rooms":world.focus_room(record)
		else:world.focus_cell(record.get("cell",217))
	present()

func _locate_selection(id: String, group: String) -> void:
	_close_drawers()
	var record: Dictionary=session.sim.snapshot()[group].get(id,{})
	if world!=null:
		if group=="rooms":world.focus_room(record)
		else:world.focus_cell(record.get("cell",217))

func present(snapshot:Dictionary={}) -> void:
	if not is_inside_tree():return
	if snapshot.is_empty():snapshot=session.presentation_snapshot()
	if session.is_campaign():
		_present_campaign(snapshot)
		_present_experience(snapshot)
		_present_opening_guide(snapshot)
		return
	if opening_card!=null:opening_card.hide()
	if _experience_button!=null:_experience_button.hide()
	# Main presents the world first; any recreated room node needs the current
	# editor visibility reapplied even when the layout signature is unchanged.
	_sync_editing_room_visibility()
	var on_launch:=flow!=null and flow.page=="launch"
	_top.visible=not on_launch
	_actions.visible=not on_launch
	_hint.visible=not on_launch
	_sync_drawer_layout()
	if on_launch:
		_bottom.hide()
		_hint.hide()
	_format_status(snapshot)
	if touch.placement.is_empty():_present_recovery(snapshot)
	if _staff_badge!=null:_staff_badge.text=str(snapshot.staff.size())
	palette.present(snapshot)
	selection.present(snapshot,session.catalog)
	_apply_targets(selection)
	controls.pause.icon=HospitalUiStyle.icon("play" if snapshot.paused else "pause")
	controls.pause.tooltip_text="开始营业" if snapshot.paused else "暂停营业"
	_notice_panel.visible=session.notice!="" and not _utility.visible
	_notice.text=session.notice
	# A notification that arrives during placement owns the interaction until dismissed.
	# This prevents stacked panels on short high-density landscapes.
	_update_preview_visibility()
	_refresh_placement(snapshot)
	var ended: bool=snapshot.challenge.status!="running"
	_settlement_title.text="经营账本" if not ended else ("首关达成" if snapshot.level_id=="level_01" else "本关达成") if snapshot.challenge.status=="won" else "本局未达标"
	if ended and _last_status!=snapshot.challenge.status:
		_close_drawers()
		if flow!=null: flow.show_result(snapshot)
	elif not ended and _last_status!="running":
		_close_drawers()
	_last_status=snapshot.challenge.status
	if flow!=null and flow.page=="unlock" and session.notice=="": flow.close()
	var pending: String=snapshot.hint_flags.get("pending","")
	if flow!=null and pending!="" and pending!=_seen_unlock and session.notice_target.get("group","")=="build":
		_seen_unlock=pending
		flow.show_unlock(pending.trim_prefix("unlock_"))
	if flow!=null and flow.visible: _notice_panel.hide()
	_sync_actions(snapshot)
	controls.recover.visible=session.storage_blocked
	controls.dismiss.visible=not session.storage_blocked
	controls.locate.visible=not session.storage_blocked and not session.notice_target.is_empty()
	if ended:
		_hint.text=("首关达成" if snapshot.level_id=="level_01" else HospitalFlowPages.level_name(session.level_data())+"达成")+" · 可查看结算" if snapshot.challenge.status=="won" else "本局结束 · 可重新开局"
	if session.storage_blocked:
		_close_drawers()
		_preview_panel.hide()
	if _settlement_panel.visible: _ledger.present(snapshot)
	if _operations_drawer.visible: operations.present(snapshot)
	_apply_targets(self)

func _present_recovery(snapshot:Dictionary) -> void:
	var seats:=SelectionPanel.recovery_seats(snapshot)
	_recovery_mark.texture=HospitalA2Skin.icon("bed",30)
	_hint.text="恢复区 %d / %d\n占用 %d · 预留 %d\n无需专职员工"%[seats.occupied,seats.total,seats.occupied,seats.reserved]

func _show_campaign(section:String) -> void:
	if session.storage_blocked:return
	touch.reset_input()
	_close_drawers()
	if flow!=null:flow.close()
	campaign_panel.show_section(section)
	_update_nav({"facilities":"build","rooms":"build","staff":"staff","cases":"patients","patients":"patients","finance":"finance"}.get(section,"finance"))

func show_campaign_staffing(id:String) -> bool:
	if session==null or session.storage_blocked or not session.is_campaign() or staffing_card==null:return false
	var snapshot:Dictionary=session.presentation_snapshot()
	if not snapshot.facilities.has(id):return false
	touch.reset_input();_close_drawers()
	if flow!=null:flow.close()
	staffing_card.configure(_campaign_build_bounds())
	if not staffing_card.show_facility(id):return false
	var target:Dictionary=snapshot.facilities[id]
	if world!=null and snapshot.rooms.has(target.room_id):world.focus_room(snapshot.rooms[target.room_id])
	_update_nav("staff");_opening_signature="";present()
	_sync_world_framing.call_deferred()
	return true

func _staffing_management_requested(focus:Dictionary) -> void:
	_show_campaign("staff")
	if str(focus.get("role",""))!="":campaign_panel._hire_role=str(focus.role)
	if session.presentation_snapshot().staff.has(str(focus.get("staff_id",""))):campaign_panel._selected_staff=str(focus.staff_id)
	campaign_panel._signature="";campaign_panel._render()
	_opening_staff_focus.call_deferred("","assign",str(focus.get("facility_id","")))
	present()

func show_campaign_patient(id:String) -> bool:
	if session==null or session.storage_blocked or not session.is_campaign() or patient_card==null:return false
	if not session.presentation_snapshot().get("patients",{}).has(id):return false
	touch.reset_input()
	_close_drawers()
	if flow!=null:flow.close()
	patient_card.configure(_campaign_build_bounds())
	if not patient_card.show_patient(id):return false
	_campaign_focus(id,"patients")
	_update_nav("patients")
	_sync_world_framing.call_deferred()
	return true

func _patient_preparation_requested(focus:Dictionary) -> void:
	# Copy before closing the inspector, whose selection owns and clears its focus.
	var destination:Dictionary=focus.duplicate(true)
	if patient_card!=null:patient_card.close()
	_campaign_opening_action(destination)

func begin_campaign_build(mode:String,kind:String,room_id:String="") -> bool:
	if session==null or session.storage_blocked or not session.is_campaign() or campaign_build==null:return false
	touch.cancel()
	_close_drawers()
	if flow!=null:flow.close()
	if session.notice!="":session.dismiss_notice()
	if not session.presentation_snapshot().paused:session.issue("set_paused",{"paused":true})
	if mode=="build" and world!=null:
		world.focus_cell(179)
		world.camera_rig.set_zoom(18)
	var opened:=false
	match mode:
		"build":opened=campaign_build.begin_build(kind)
		"install":opened=campaign_build.begin_install(kind,room_id)
		"edit":opened=campaign_build.begin_edit(room_id)
	if opened:
		_update_nav("build")
		_sync_world_framing.call_deferred()
	else:
		session.notice="无法开始这次建设，请检查设备是否开放、科室是否可改造。"
		present()
	return opened

func _cancel_campaign_build() -> void:
	if campaign_build!=null and campaign_build.active:campaign_build.cancel()
	if _campaign_overlay!=null:_campaign_overlay.clear()
	if world!=null:
		world.clear_campaign_preview()
		world.set_wall_preview({})
		for room:Node3D in world.room_views.values():room.show()
	_campaign_preview_signature=""
	_campaign_build_step=-1

func _campaign_build_bounds() -> Rect2:
	var top:float=_top_frame.position.y+_top_frame.size.y+8 if _top_frame.visible else _safe.position.y+8
	var bottom:float=_dock.position.y-8 if _dock.visible else _safe.end.y-8
	return Rect2(Vector2(_safe.position.x,top),Vector2(_safe.size.x,maxf(48,bottom-top)))

func _campaign_build_active_changed(active:bool) -> void:
	if campaign_build!=null:campaign_build.configure(_campaign_build_bounds())
	if world!=null:world.set_build_grid_visible(active)
	if not active:_cancel_campaign_build()
	_sync_experience_display()
	_sync_world_framing.call_deferred()

func _campaign_build_view_changed(view:Dictionary) -> void:
	var step:int=int(view.get("step",-1)) if view.get("active",false) else -1
	var changed:bool=step!=_campaign_build_step
	_campaign_build_step=step
	if not changed or step<1 or world==null:return
	var proposal:Dictionary=view.get("proposal",{})
	var layout:Dictionary=proposal.get("layout",{})
	var origin:int=int(proposal.get("origin_cell",-1))
	if origin<0:return
	var cells:Array=[]
	for y:int in range(int(layout.get("height",0))):
		for x:int in range(int(layout.get("width",0))):cells.append(origin+y*24+x)
	if not cells.is_empty():world.focus_room.call_deferred({"cells":cells})

func _campaign_build_preview(proposal:Dictionary,result:Dictionary) -> void:
	if world==null or _campaign_overlay==null:return
	if proposal.is_empty():
		_cancel_campaign_build()
		return
	var signature:String=JSON.stringify([proposal,result.get("ok",false),result.get("code",""),result.get("data",{})])
	if signature==_campaign_preview_signature:return
	_campaign_preview_signature=signature
	var record:Dictionary=proposal.duplicate(true)
	record["id"]=str(proposal.get("room_id","__campaign_preview__"))
	record["kind"]="campaign_department"
	record["ruleset"]=FacilityLayout.RULESET
	record["rotation"]=0
	var room:Dictionary=result.get("data",{}).get("room",{})
	if room.is_empty():room=FacilityLayout.geometry(record)
	if not room.is_empty():world.show_campaign_preview(room)
	else:world.clear_campaign_preview()
	world.set_wall_preview(record)
	for id:String in world.room_views:
		world.room_views[id].visible=id!=str(proposal.get("room_id",""))
	_campaign_overlay.present(record,result,room)

func _campaign_build_committed(result:Dictionary) -> void:
	feedback_result.emit(result)
	if result.get("ok",false):
		_cancel_campaign_build()
		_opening_signature=""
		_sync_experience_display()
		present()

func _present_opening_guide(snapshot:Dictionary) -> void:
	if opening_card==null or session==null:return
	if int(snapshot.get("campaign",{}).get("opening_loop_version",0))!=1:
		opening_card.hide()
		return
	# A stable half-second glance update avoids re-running every readiness graph
	# in the render path; actual commands and pause changes refresh immediately.
	var signature:String=JSON.stringify([session.sim.get_instance_id(),int(snapshot.tick)/5,snapshot.command_sequence,snapshot.paused])
	if signature!=_opening_signature:
		_opening_signature=signature
		_opening_current=CampaignOpeningGuide.current(snapshot,session.catalog)
	var available:bool=not session.storage_blocked and not (flow!=null and flow.visible) and not campaign_panel.visible and not campaign_build.active and not (patient_card!=null and patient_card.visible) and not (staffing_card!=null and staffing_card.visible) and session.notice==""
	var top:float=_top_frame.position.y+_top_frame.size.y+8 if _top_frame.visible else _safe.position.y+8
	var bottom:float=_dock.position.y-8 if _dock.visible else _safe.end.y-8
	opening_card.present(_opening_current,available,Rect2(Vector2(_safe.position.x+8,top),Vector2(_safe.size.x-16,maxf(48,bottom-top))))

func _campaign_opening_action(focus:Dictionary) -> void:
	if session.storage_blocked:return
	var kind:String=str(focus.get("facility_kind",""))
	match str(focus.get("action","")):
		"build":begin_campaign_build("build",kind)
		"staff":
			var exact_facility:String=str(focus.get("facility_id",""))
			if exact_facility=="":
				for facility:Dictionary in session.presentation_snapshot().facilities.values():
					if facility.kind==kind and facility.status=="open":exact_facility=str(facility.id);break
			if exact_facility!="" and show_campaign_staffing(exact_facility):return
			_show_campaign("staff")
			campaign_panel._hire_role=str(focus.get("role","doctor"))
			var snapshot:Dictionary=session.presentation_snapshot()
			var requested_staff:String=str(focus.get("staff_id",""))
			if snapshot.staff.has(requested_staff):campaign_panel._selected_staff=requested_staff
			else:
				for employee:Dictionary in snapshot.staff.values():
					if employee.role==campaign_panel._hire_role and str(employee.get("facility_id",""))=="":
						campaign_panel._selected_staff=employee.id
						break
			campaign_panel._signature=""
			campaign_panel._render()
			_opening_staff_focus.call_deferred(kind,str(focus.get("control","hire")),str(focus.get("facility_id","")))
		"operation":
			if str(focus.get("control",""))=="run_operation":
				var result:Dictionary=session.issue("run_operation",{"facility_kind":kind})
				feedback_result.emit(result)
				if result.get("ok",false) and session.presentation_snapshot().paused:session.issue("set_paused",{"paused":false})
			else:
				campaign_panel._selected_operation=kind
				_show_campaign("operations")
				_experience_scroll.call_deferred(str(focus.get("scroll_control","")))
		"resume":
			_close_drawers()
			flow.close()
			session.issue("set_paused",{"paused":false})
		"open_intake":
			var result:Dictionary=session.issue("set_intake",{"enabled":true})
			feedback_result.emit(result)
			if result.get("ok",false) and session.presentation_snapshot().paused:session.issue("set_paused",{"paused":false})
		"clinical","patients":
			var selected_patient:String=str(focus.get("patient_id",""))
			if selected_patient=="" or not show_campaign_patient(selected_patient):_show_campaign("patients")
		"goals":
			_show_campaign(str(focus.get("section","cases")))
			if str(focus.get("resource",""))!="":
				campaign_panel._resource_focus=str(focus.resource)
				campaign_panel._signature=""
				campaign_panel._render()
			if str(focus.get("section",""))=="staff" and session.presentation_snapshot().staff.has(str(focus.get("staff_id",""))):
				campaign_panel._selected_staff=str(focus.staff_id)
				campaign_panel._signature=""
				campaign_panel._render()
			_experience_scroll.call_deferred(str(focus.get("control","")))
	_opening_signature=""
	present()

func _opening_staff_focus(kind:String,control_id:String,facility_id:String="") -> void:
	var owner= session.sim
	await get_tree().process_frame
	if session.sim!=owner or not campaign_panel.visible or campaign_panel.section!="staff":return
	var target:String=facility_id
	if target=="":
		for facility:Dictionary in session.presentation_snapshot().facilities.values():
			if str(facility.kind)==kind:target=str(facility.id);break
	var choice:OptionButton=campaign_panel.controls.get("assign_facility")
	if choice!=null and target!="":
		for index:int in range(choice.item_count):
			if str(choice.get_item_metadata(index))==target:choice.select(index);break
	_experience_scroll(control_id)

func _campaign_focus(id:String,group:String) -> void:
	var snapshot:Dictionary=session.sim.snapshot()
	var record:Dictionary=snapshot.get(group,{}).get(id,{})
	if world==null or record.is_empty():return
	if group=="rooms":world.focus_room(record)
	else:world.focus_cell(int(record.get("cell",217)))

func _input(event:InputEvent) -> void:
	if campaign_panel==null or not campaign_panel.visible or not campaign_panel.picking_origin or world==null:return
	var point:=Vector2.ZERO
	var released:=false
	if event is InputEventScreenTouch:point=event.position;released=not event.pressed
	elif event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:point=event.position;released=not event.pressed
	if released and not campaign_panel.panel.get_global_rect().has_point(point):
		campaign_panel.choose_origin(world.camera_rig.screen_to_cell(point))
		get_viewport().set_input_as_handled()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel") or event.is_echo():return
	# Back always dismisses or cancels the foremost interface; it never confirms
	# replacing a hospital or bypasses protected storage.
	if campaign_build!=null and campaign_build.active:
		campaign_build.cancel()
	elif patient_card!=null and patient_card.visible:
		patient_card.close()
	elif staffing_card!=null and staffing_card.visible:
		staffing_card.close()
	elif flow!=null and flow.visible:
		match flow.page:
			"launch": pass
			"levels": _flow_action("menu")
			"restart": _flow_action("cancel_restart")
			"storage": _flow_action("pause")
			"pause":
				if not flow.controls.resume_game.disabled:_flow_action("resume")
			"unlock": _flow_action("unlock_later")
			_: _flow_action("hospital")
	elif not touch.placement.is_empty() or touch.free_build!=null:
		touch.cancel()
	elif _left.visible or _right.visible or _utility.visible or _settlement_panel.visible or _operations_drawer.visible or (campaign_panel!=null and campaign_panel.visible):
		_close_drawers()
	else:_show_pause()
	get_viewport().set_input_as_handled()

func _present_campaign(snapshot:Dictionary) -> void:
	var on_launch:bool=flow!=null and flow.page=="launch"
	_dock.visible=not on_launch
	_top.visible=not on_launch
	_actions.visible=not on_launch
	_bottom.visible=not on_launch
	_hint.visible=not on_launch
	_format_status(snapshot)
	_recovery_mark.texture=HospitalA2Skin.icon("patient",30)
	_hint.text="病例任务 %d / %d\n%s\n查看患者与诊疗进度"%[snapshot.campaign.get("completed_cases",[]).size(),session.level_data().get("case_ids",[]).size(),"已暂停" if snapshot.paused else "%d× 营业中"%snapshot.speed]
	if _staff_badge!=null:_staff_badge.text=str(snapshot.staff.size())
	if session.is_long_campaign():
		var view:Dictionary=_long_view(snapshot)
		_hint.text="%s\n%s\n在院 %d 人"%[str(view.get("phase_name","开业")),"常规接诊开启" if view.get("intake_enabled",false) else "常规接诊关闭",int(view.get("live_count",0))]
	controls.pause.icon=HospitalUiStyle.icon("play" if snapshot.paused else "pause")
	controls.pause.tooltip_text="开始营业" if snapshot.paused else "暂停营业"
	_notice_panel.visible=session.notice!="" and not _utility.visible and not (flow!=null and flow.visible)
	_notice.text=session.notice
	controls.recover.visible=session.storage_blocked
	controls.dismiss.visible=not session.storage_blocked
	controls.locate.visible=false
	var ended:bool=snapshot.challenge.status!="running"
	if ended and _last_status!=snapshot.challenge.status:
		_close_drawers()
		flow.show_result(snapshot)
	_last_status=snapshot.challenge.status
	_sync_actions(snapshot)
	campaign_panel.present(snapshot)
	if campaign_build!=null:campaign_build.present(snapshot)
	if patient_card!=null:patient_card.present(snapshot)
	if staffing_card!=null:staffing_card.present(snapshot)
	if session.storage_blocked:_close_drawers()
	_sync_drawer_layout()

func _long_view(snapshot:Dictionary) -> Dictionary:
	var signature:String=JSON.stringify([snapshot.level_id,snapshot.tick/10,snapshot.get("command_sequence",0),snapshot.challenge.status,snapshot.campaign.get("phase_index",0)])
	if signature!=_long_goals_signature:
		_long_goals_signature=signature
		_long_goals_cache=LongCampaign.goals(snapshot,session.catalog)
	return _long_goals_cache
