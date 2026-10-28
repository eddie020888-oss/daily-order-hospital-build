class_name SelectionPanel
extends VBoxContainer

signal recruit_requested
signal command_requested(type: String, payload: Dictionary)
signal move_requested(kind: String, room_id: String)
signal layout_edit_requested(kind:String,room_id:String)
signal focus_requested(id: String, group: String)
signal locate_requested(id: String, group: String)
signal page_changed(title: String)
signal hospital_flow_requested
signal build_catalog_requested
var selected_id := ""
var selected_group := "rooms"
var catalog: ContentCatalog
var minimum_touch_target:=48.0
var controls: Dictionary={}
var _signature := ""
var _expanded_patients: Dictionary={}
var _pending_snapshot: Dictionary={}
var _patient_filter := "active"
var _patient_stage := ""
var action_footer: HFlowContainer
var _view:="detail"
var _draft_mode:=""
var _short_landscape:=false
var _snapshot: Dictionary={}

const REASONS := {"missing_room":"缺少已解锁的对应房间","missing_staff":"房间缺岗，或员工尚未到位","equipment_busy":"设备正在服务，请等待","recovery_full":"恢复席位已满","path_blocked":"道路暂时无法通过","hospital_full":"院内已满，正在院外等候","insufficient_cash":"现金不足，操作未执行","room_locked":"设施尚未解锁","boundary":"房间超出可建边界","main_corridor":"主走廊必须保持畅通","room_overlap":"与已有房间重叠","room_unreachable":"房门或服务位置无法到达","actor_blocked":"这会封住院内人员","in_flight_edge_blocked":"人员正经过此处，请稍后再试","room_open":"请先关停并等待房间排空","room_busy":"队列、服务或人员尚未排空","staff_busy":"员工仍在服务或有已预约患者","room_staffed":"该房间已有员工","role_mismatch":"员工岗位与房间不匹配","staff_limit":"人员已达上限，可在员工详情解聘闲置员工","staff_assigned":"请先关停岗位并撤回待派工，再解聘员工","staff_moving":"员工仍在移动，请等回到待派工位置后再解聘","treatment_started":"治疗已经开始，不能更改本次模式","already_upgraded":"恢复区已升级","challenge_ended":"本局已结束，请重新开局","storage_blocked":"存档异常，请先保留并检查原文件"}

const CARE_STAGES := ["general_exam","pharmacy","ward"]
const STAGE_NAMES := {"outside":"院外","reception":"接待","diagnosis":"诊断","general_exam":"综合检查","pharmacy":"发药","ward":"留观","treatment":"治疗","recovery":"恢复","exit":"离院"}

static func stage_rows(include_care: bool=false) -> Array:
	var rows: Array=[]
	for key: String in STAGE_NAMES:
		if key in CARE_STAGES and not include_care: continue
		rows.append([key,STAGE_NAMES[key]])
	return rows

static func care_workload(snapshot: Dictionary, room_id: String) -> Dictionary:
	var result := {"serving":0,"reserved":0,"departing":0,"total":0}
	for slot in snapshot.slots.values():
		if slot.room_id!=room_id: continue
		result.total+=1
		if slot.phase=="serving": result.serving+=1
		elif slot.phase=="reserved": result.reserved+=1
		elif slot.phase=="blocked": result.departing+=1
	return result

static func room_beds(snapshot: Dictionary, room_id: String) -> Array:
	var beds: Array=[]
	var ids: Array=snapshot.slots.keys()
	ids.sort()
	for id: String in ids:
		var slot: Dictionary=snapshot.slots[id]
		if slot.room_id!=room_id: continue
		var copy := "空闲"
		if slot.phase=="reserved": copy="预约 · 患者前往中"
		elif slot.phase=="serving": copy="留观中 · 剩余"+_seconds(slot.remaining_ticks)
		elif slot.phase=="blocked": copy="离床中 · 等待实际腾空"
		if slot.patient_id!="": copy+=" · 患者"+slot.patient_id.get_slice("_",1)
		beds.append({"id":id,"phase":slot.phase,"patient_id":slot.patient_id,"remaining_ticks":slot.remaining_ticks,"copy":copy})
	return beds

static func patient_wait_reason(patient: Dictionary, snapshot: Dictionary, content: ContentCatalog) -> String:
	var code: String=patient.get("wait_reason","")
	if not patient.has("care_steps"): return reason(code) if code!="" else "当前没有排队阻塞"
	var kind: String=ClinicalPathways.current_room_kind(patient,content)
	if code=="missing_staff" and content.rooms.has(kind):
		var role: String=content.rooms[kind].staff_role
		var name: String=content.staff.get(role,{}).get("name","匹配员工")
		return "缺少在岗%s，需为本房安排%s。" % [name,name]
	if code=="missing_room" and content.rooms.has(kind): return "缺少开放的"+content.rooms[kind].name
	if code in ["equipment_busy","ward_full"] and kind=="ward": return "病床已满，等待空床。"
	return reason(code) if code!="" else "当前没有排队阻塞"

static func reason(code: String) -> String:
	var opening_reasons:={"invalid_doors":"请至少设置一扇有效的门","invalid_primary_door":"请重新选择主入口","duplicate_door":"这段墙已经有门了","invalid_windows":"请重新选择窗户位置","invalid_window":"窗户须放在房间的墙边","opening_overlap":"同一段墙不能同时开门和开窗","duplicate_window":"这段墙已经有窗户了"}
	if opening_reasons.has(code):return opening_reasons[code]
	var build_reasons:={"invalid_layout":"请完成房间、门与必需设备的选择","invalid_layout_dimensions":"房间尺寸未达要求或超出可建范围","invalid_door":"请在房间边缘选择门的位置","invalid_equipment":"请先放置必需工作站","invalid_furniture":"家具的全部占格必须放在房间内","furniture_overlap":"家具占用了设备、操作位、维护通道或另一件家具","equipment_out_of_bounds":"设备本体、操作位和维护通道须完整放在房间内","door_blocked":"门口与门内通道需要留空","equipment_overlap":"工作站操作位或维护通道被设备占用","invalid_rotation":"请使用设备旋转调整朝向"}
	if build_reasons.has(code):return build_reasons[code]
	return REASONS.get(code,"操作未完成，请检查选择和房间状态。")

static func command_feedback(result: Dictionary, snapshot: Dictionary, target: Dictionary) -> String:
	if result.code!="staff_busy": return reason(result.code)
	var employee: Dictionary=snapshot.staff.get(result.data.get("staff_id",target.get("id","")),{})
	if employee.get("role","")=="nurse": return "护士仍有已预约、护理中或未离床患者；须完成实际交接后调岗。"
	if employee.get("phase","")=="blocked": return "员工正在等待患者移交并离开设备；请检查恢复席位与通路，暂时不能调岗。"
	var ticks: int=result.data.get("remaining_ticks",0)
	if employee.get("phase","")=="serving" and ticks>0: return "员工正在服务，本次服务还需%s；服务结束并完成患者移交后才能调岗。" % _seconds(ticks)
	return reason("staff_busy")

static func patient_information(patient: Dictionary, snapshot: Dictionary, content: ContentCatalog) -> String:
	var info: String="%s\n%s" % [content.diseases[patient.disease_id].name,_phase_name(patient.phase)]
	var wait: String=patient.get("wait_reason","")
	if wait!="": info+="\n等待原因："+reason(wait)
	if patient.has("care_steps"):
		var pathway: Dictionary=ClinicalPathways.info(patient,content)
		var route: Array[String]=[]
		for step in pathway.steps: route.append(STAGE_NAMES.get(step.kind,step.kind))
		return info+"\n诊疗路线："+" → ".join(route)+"\n"+patient_wait_reason(patient,snapshot,content)
	if not patient.get("tolerance_revealed",false): return info+"\n耐受：诊断完成后显示。"
	info+="\n耐受 %d" % patient.tolerance
	if patient.get("treatment_started",false): return info+"\n本次治疗已开始，模式已锁定。"
	var mode: String=patient.get("mode_override","")
	if mode=="":
		if snapshot.auto_route:
			mode="gentle" if content.diseases[patient.disease_id].modes.fast.stimulus>patient.tolerance else "fast"
		else:
			var room_id: String=patient.get("room_id","")
			var slot: Dictionary=snapshot.slots.get(patient.get("slot_id",""),{})
			if slot.get("patient_id","")==patient.get("id",""): room_id=slot.get("room_id",room_id)
			var assigned: Dictionary=snapshot.rooms.get(room_id,{})
			if assigned.get("kind","")!=content.diseases[patient.disease_id].room_kind:
				return info+"\n待分配治疗设备后显示精确预测。"
			mode=assigned.mode
	var prediction: Dictionary=content.diseases[patient.disease_id].modes[mode]
	var recovery: bool=prediction.stimulus>patient.tolerance
	return info+"\n下一次：%s\n%d秒 · %d币耗材\n%s" % ["舒缓" if mode=="gentle" else "快速",prediction.duration_ticks/10,prediction.cost,"需恢复40秒，另耗10币" if recovery else "无需恢复"]

static func recovery_seats(snapshot: Dictionary, room_id: String="") -> Dictionary:
	var count:={"occupied":0,"reserved":0,"total":0}
	for slot in snapshot.slots.values():
		if room_id!="" and slot.room_id!=room_id: continue
		if snapshot.rooms.get(slot.room_id,{}).get("kind","")!="recovery": continue
		count.total+=1
		if slot.phase=="reserved": count.reserved+=1
		elif slot.phase!="free" or slot.patient_id!="": count.occupied+=1
	return count

static func patient_flow_information(patient: Dictionary) -> String:
	var names: Dictionary={}
	for row in stage_rows(patient.has("care_steps")): names[row[0]]=row[1]
	var longest:="outside"
	var maximum:=0
	var segments: Array[String]=[]
	for stage in names:
		var ticks: int=patient.get("wait_by_stage",{}).get(stage,0)
		segments.append(names[stage]+" "+_seconds(ticks))
		if ticks>maximum:
			maximum=ticks
			longest=stage
	var current_reason: String=patient.get("wait_reason","")
	return "流程累计等待\n"+" → ".join(segments)+"\n最长累计等待：%s %s\n当前环节：%s\n当前原因：%s" % [names[longest],_seconds(maximum),names.get(patient.get("stage",""),"已离院"),reason(current_reason) if current_reason!="" else "当前没有排队阻塞"]

static func _seconds(ticks: int) -> String:
	return "%d秒" % (ticks/10) if ticks%10==0 else "%.1f秒" % (ticks/10.0)

func expand_flow(patient_id: String) -> void:
	_expanded_patients[patient_id]=true
	_view="flow"
	_signature=""

func _toggle_flow(patient_id: String, snapshot: Dictionary) -> void:
	_expanded_patients[patient_id]=not _expanded_patients.get(patient_id,false)
	_signature=""
	# Release can run while its Button is still pressed; keep the newest queued projection.
	present(_pending_snapshot if not _pending_snapshot.is_empty() else snapshot,catalog)

static func _phase_name(phase: String) -> String:
	for kind: String in CARE_STAGES:
		if phase==kind+"_queue": return "等待"+STAGE_NAMES[kind]
		if phase==kind+"_service": return STAGE_NAMES[kind]+"中"
		if phase=="moving_"+kind: return "前往"+STAGE_NAMES[kind]
	return {"outside":"院外等候","reception_queue":"等待接待","reception_service":"接待中","diagnosis_queue":"等待诊断","diagnosis_service":"诊断中","treatment_queue":"等待治疗","treatment_service":"治疗中","waiting_recovery":"等待恢复席位","recovering":"恢复中","leaving":"正在离院","completed":"已完成离院","abandoned":"已弃诊离院","abandoning":"弃诊后离院中"}.get(phase,"正在前往服务位置")

func select(id: String, group: String) -> void:
	selected_id=id
	selected_group=group
	_signature=""
	_view="detail"
	_draft_mode=""
	# A fresh selection opens at its hero, independent of the previous list scroll.
	if get_parent() is ScrollContainer: get_parent().set_deferred("scroll_vertical",0)

func show_list(group: String, stage: String="") -> void:
	select("",group)
	_patient_stage=stage if group=="patients" else ""
	if _patient_stage!="": _patient_filter="active"

func _button(copy: String, key: String, action: Callable) -> Button:
	var control:=BuildPalette.button(copy)
	control.custom_minimum_size=Vector2.ONE*minimum_touch_target
	controls[key]=control
	control.pressed.connect(action)
	control.button_up.connect(func() -> void: _flush_pending.call_deferred())
	add_child(control)
	return control

func _footer_button(copy: String, key: String, action: Callable, primary: bool=false) -> Button:
	var control:=_button(copy,key,action)
	control.clip_text=false
	if action_footer!=null:
		remove_child(control)
		action_footer.add_child(control)
		control.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
	if primary: HospitalUiStyle.primary(control)
	if not _short_landscape:
		for state in ["normal","hover","pressed","disabled","focus"]:
			var style:=control.get_theme_stylebox(state).duplicate() as StyleBox
			style.content_margin_left=18
			style.content_margin_right=18
			control.add_theme_stylebox_override(state,style)
	return control

func configure_short_landscape(enabled: bool) -> void:
	if _short_landscape==enabled: return
	_short_landscape=enabled
	_signature=""
	if not _snapshot.is_empty(): present.call_deferred(_snapshot,catalog)

func _change_view(view: String) -> void:
	_view=view
	_signature=""
	if not _snapshot.is_empty(): present(_snapshot,catalog)
	if get_parent() is ScrollContainer: get_parent().set_deferred("scroll_vertical",0)

func _gap(height: float=14) -> void:
	var gap:=Control.new()
	gap.custom_minimum_size.y=height
	add_child(gap)

func _section(copy: String) -> void:
	_gap(18)
	add_child(HospitalUiStyle.text(copy,18,HospitalUiStyle.INK,700))
	_gap(8)

func _flush_pending() -> void:
	if _pending_snapshot.is_empty(): return
	var snapshot:=_pending_snapshot
	_pending_snapshot={}
	present(snapshot,catalog)

func _text(copy: String) -> void:
	var label:=Label.new()
	label.text=copy
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size",18)
	add_child(label)

func _hero(texture: Texture2D, title: String, subtitle: String, status: String="", amber: bool=false, small: bool=false, device: bool=false) -> void:
	var row:=HBoxContainer.new()
	row.add_theme_constant_override("separation",18)
	add_child(row)
	row.add_child(HospitalUiStyle.picture(texture,Vector2(80,66) if device else Vector2(66,66) if small or _short_landscape else Vector2(94,94),2))
	var col:=VBoxContainer.new()
	col.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	row.add_child(col)
	col.add_theme_constant_override("separation",6)
	var name_label:=HospitalUiStyle.text(title,19 if small or _short_landscape else 25,HospitalUiStyle.INK,750)
	name_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	col.add_child(name_label)
	var detail:=HospitalUiStyle.text(subtitle,16,HospitalUiStyle.MUTED)
	detail.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	col.add_child(detail)
	if status!="": col.add_child(HospitalUiStyle.tag(status,amber))
	_gap(10 if selected_group=="patients" and _view=="detail" and not _short_landscape else 18)

func _kv(key: String, value: String) -> void:
	var row:=HBoxContainer.new()
	var inset:=MarginContainer.new()
	inset.add_theme_constant_override("margin_top",10)
	inset.add_theme_constant_override("margin_bottom",10)
	add_child(inset)
	inset.add_child(row)
	var left:=HospitalUiStyle.text(key,17)
	left.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	row.add_child(left)
	var right:=HospitalUiStyle.text(value,17,HospitalUiStyle.INK,650)
	right.name="Value_"+key
	right.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	right.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	right.custom_minimum_size.x=100
	right.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	row.add_child(right)
	add_child(HSeparator.new())

func _list_card(texture: Texture2D, title: String, subtitle: String, key: String, action: Callable, device: bool=false, badge: String="", amber: bool=false, badge_below: bool=false) -> Button:
	var b:=_button("",key,action)
	var height:=84 if badge_below and badge!="" else 112 if device and badge!="" else 88 if device else 70
	b.set_meta("minimum_size",Vector2(48,height))
	b.custom_minimum_size.y=height
	var row_style:=HospitalUiStyle.panel(0,HospitalUiStyle.PAPER,8)
	row_style.set_border_width_all(0)
	row_style.border_width_bottom=1
	b.add_theme_stylebox_override("normal",row_style)
	b.add_theme_stylebox_override("hover",HospitalUiStyle.bevel(HospitalUiStyle.PAPER.lightened(.12),8))
	var row:=HBoxContainer.new()
	row.mouse_filter=Control.MOUSE_FILTER_IGNORE
	b.add_child(row)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left=10
	row.offset_right=-10
	row.offset_top=10
	row.offset_bottom=-10
	row.add_theme_constant_override("separation",8)
	row.add_child(HospitalUiStyle.picture(texture,Vector2(80,66) if device else Vector2(48,48),2))
	var col:=VBoxContainer.new()
	col.mouse_filter=Control.MOUSE_FILTER_IGNORE
	col.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	if badge_below: col.add_theme_constant_override("separation",4)
	row.add_child(col)
	var heading:=HFlowContainer.new()
	heading.mouse_filter=Control.MOUSE_FILTER_IGNORE
	heading.add_theme_constant_override("h_separation",6)
	col.add_child(heading)
	heading.add_child(HospitalUiStyle.text(title,19,HospitalUiStyle.INK,700))
	if badge!="" and not device and not badge_below: heading.add_child(HospitalUiStyle.tag(badge,amber))
	var detail:=HospitalUiStyle.text(subtitle,14,HospitalUiStyle.MUTED)
	detail.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	col.add_child(detail)
	if badge!="" and (device or badge_below): col.add_child(HospitalUiStyle.tag(badge,amber))
	row.add_child(HospitalUiStyle.text("›",24,HospitalUiStyle.MUTED))
	# A list can be rebuilt before queued layout work runs. Keep only weak
	# references in both deferred paths; freed Controls cannot pass typed args.
	var card_ref:WeakRef=weakref(b)
	var row_ref:WeakRef=weakref(row)
	row.minimum_size_changed.connect(func() -> void: _fit_list_card.call_deferred(card_ref,row_ref,height))
	_fit_list_card.call_deferred(card_ref,row_ref,height)
	return b

func _fit_list_card(card_ref: WeakRef, row_ref: WeakRef, minimum_height: int) -> void:
	var card:=card_ref.get_ref() as Button
	var row:=row_ref.get_ref() as HBoxContainer
	if not is_instance_valid(card) or not is_instance_valid(row): return
	if card.is_queued_for_deletion() or row.is_queued_for_deletion(): return
	var height:=maxf(minimum_height,row.get_combined_minimum_size().y+20)
	card.set_meta("minimum_size",Vector2(48,height))
	card.custom_minimum_size.y=height

func _list_header(copy: String, action_copy: String, key: String, action: Callable, plus: bool=false) -> void:
	var row:=HBoxContainer.new()
	add_child(row)
	var count:=HospitalUiStyle.text(copy,16,HospitalUiStyle.MUTED)
	count.name="ListCount"
	count.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	count.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	row.add_child(count)
	var button:=_button(action_copy,key,action)
	remove_child(button)
	row.add_child(button)
	button.size_flags_horizontal=Control.SIZE_SHRINK_END
	button.clip_text=false
	button.add_theme_stylebox_override("normal",StyleBoxEmpty.new())
	button.add_theme_color_override("font_color",HospitalUiStyle.TEAL)
	if plus: button.icon=HospitalUiStyle.icon("plus")
	_gap(12)

func _room_activity(room: Dictionary, snapshot: Dictionary, id: String) -> Dictionary:
	var busy: bool=not snapshot.queues.get(id,[]).is_empty()
	var phase:="等待接诊"
	var handoff:=false
	for slot in snapshot.slots.values():
		if slot.room_id!=id: continue
		busy=busy or slot.phase!="free" or slot.patient_id!=""
		if slot.phase=="blocked":
			handoff=snapshot.patients.get(slot.patient_id,{}).get("stage","")=="recovery"
			phase="等待恢复交接" if handoff else "等待患者离开"
		elif slot.phase=="serving" and not handoff: phase="服务中"
		elif slot.phase=="reserved" and phase=="等待接诊": phase="患者前往设备"
	var actor_inside:=false
	for group in ["staff","patients"]:
		for actor in snapshot[group].values():
			if actor.get("cell",-1) in room.cells: actor_inside=true
			var route: Array=actor.get("path",[])
			var index: int=actor.get("path_index",0)
			if actor.get("move_progress",0)>0 and index>=0 and index+1<route.size() and route[index+1] in room.cells: actor_inside=true
	var edit_reason:="请先关停并等待房间排空。" if room.status=="open" else "队列、服务、预留或房内人员尚未排空。" if busy or actor_inside else ""
	return {"phase":phase,"handoff":handoff,"busy":busy,"edit_reason":edit_reason}

func _set_filter(value: String, snapshot: Dictionary) -> void:
	_patient_filter=value
	_patient_stage=""
	_signature=""
	present(_pending_snapshot if not _pending_snapshot.is_empty() else snapshot,catalog)

func present(snapshot: Dictionary, content: ContentCatalog) -> void:
	catalog=content
	_snapshot=snapshot.duplicate(true)
	for control in controls.values():
		if is_instance_valid(control) and control.button_pressed:
			_pending_snapshot=snapshot.duplicate(true)
			return
	var signature:=JSON.stringify([selected_id,selected_group,_patient_filter,_patient_stage,_view,_draft_mode,_short_landscape,snapshot.tick/10,snapshot.rooms,snapshot.staff.keys(),snapshot.patients if _patient_stage!="" else snapshot.patients.keys(),snapshot.auto_route,snapshot.slots,snapshot[selected_group].get(selected_id,{}),recovery_seats(snapshot,selected_id),snapshot.get("appearance_seed",0)])
	if signature==_signature: return
	_signature=signature
	for child in get_children():
		remove_child(child)
		child.queue_free()
	controls.clear()
	add_theme_constant_override("separation",0)
	if action_footer!=null:
		for child in action_footer.get_children():
			action_footer.remove_child(child)
			child.queue_free()
	if selected_id=="" or not snapshot[selected_group].has(selected_id):
		var list_count: Label
		if selected_group=="staff":
			_list_header("在职 %d / %d 人" % [snapshot.staff.size(),catalog.levels[snapshot.level_id].max_staff],"招聘","recruit_header",func() -> void: recruit_requested.emit(),true)
			_footer_button("招聘员工","recruit",func() -> void: recruit_requested.emit(),true)
		elif selected_group=="rooms":
			_list_header("已建 %d 个设施" % snapshot.rooms.size(),"新建设施","new_build",func() -> void: build_catalog_requested.emit())
		elif selected_group=="patients":
			var tab_panel:=PanelContainer.new()
			tab_panel.add_theme_stylebox_override("panel",HospitalUiStyle.panel(10,HospitalUiStyle.SOFT,4))
			add_child(tab_panel)
			var tabs:=HBoxContainer.new()
			tabs.add_theme_constant_override("separation",6)
			tab_panel.add_child(tabs)
			for item in [["active","在院"],["completed","已完成"],["abandoned","已弃诊"]]:
				var tab:=BuildPalette.button(item[1])
				controls["filter_"+item[0]]=tab
				tabs.add_child(tab)
				var style:=HospitalUiStyle.panel(8,HospitalUiStyle.PAPER if item[0]==_patient_filter else Color(0,0,0,0),8)
				style.set_border_width_all(0)
				tab.add_theme_stylebox_override("normal",style)
				tab.pressed.connect(func() -> void: _set_filter(item[0],snapshot))
				tab.button_up.connect(func() -> void: _flush_pending.call_deferred())
			_gap(15)
			var list_header:=HBoxContainer.new()
			add_child(list_header)
			list_count=HospitalUiStyle.text("",16,HospitalUiStyle.MUTED,400)
			list_count.size_flags_horizontal=Control.SIZE_EXPAND_FILL
			list_header.add_child(list_count)
			var overview:=BuildPalette.button("诊疗流程")
			overview.size_flags_horizontal=Control.SIZE_SHRINK_END
			overview.add_theme_stylebox_override("normal",StyleBoxEmpty.new())
			overview.pressed.connect(func() -> void: hospital_flow_requested.emit())
			controls.hospital_flow=overview
			list_header.add_child(overview)
			_gap(12)
		var displayed:=0
		for id in snapshot[selected_group]:
			var row: Dictionary=snapshot[selected_group][id]
			var title: String=id
			var detail:=""
			var badge:=""
			var amber:=false
			var texture: Texture2D
			if selected_group=="rooms":
				title=catalog.rooms[row.kind].name
				detail=HospitalUiStyle.DEVICE_NAMES.get(row.kind,title)+" · 队列 %d 人" % snapshot.queues[id].size()
				var activity:=_room_activity(row,snapshot,id)
				badge="等恢复 · 占用中" if activity.handoff else "营业中" if row.status=="open" else "关停排空中" if row.status=="draining" else "已关闭"
				amber=activity.handoff or row.status!="open"
				texture=HospitalUiStyle.thumbnail(row.kind)
			elif selected_group=="staff":
				title=catalog.staff[row.role].name+_number(id)
				badge=catalog.staff[row.role].name
				detail=("等待派岗" if row.room_id=="" else catalog.rooms[snapshot.rooms[row.room_id].kind].name)+" · 每日 %d 币" % catalog.staff[row.role].daily_wage
				texture=HospitalUiStyle.portrait(row.role,int(id.get_slice("_",1))-1,snapshot.get("appearance_seed",0))
			else:
				var terminal: bool=row.phase in ["completed","abandoned"]
				if _patient_filter=="active" and terminal: continue
				if _patient_filter!="active" and row.phase!=_patient_filter: continue
				if _patient_stage!="":
					var actual_stage: String="exit" if row.phase in ["leaving","abandoning"] else row.stage
					if actual_stage!=_patient_stage or row.phase=="outside": continue
				title="患者"+_number(id)
				detail=catalog.diseases[row.disease_id].name
				badge=_phase_name(row.phase)
				amber=row.get("wait_reason","")!=""
				texture=HospitalUiStyle.portrait(row.disease_id,int(id.get_slice("_",1))-1,snapshot.get("appearance_seed",0))
			_list_card(texture,title,detail,id,func() -> void: focus_requested.emit(id,selected_group),selected_group=="rooms",badge,amber,selected_group=="patients")
			_gap(10)
			displayed+=1
		if displayed==0: _text("还没有房间，先从建设开始。" if selected_group=="rooms" else "目前没有员工，可以先招聘。" if selected_group=="staff" else "当前分类没有患者。")
		if list_count!=null:
			var stage_name: String=STAGE_NAMES.get(_patient_stage,"")
			list_count.text=(stage_name+"阶段 · " if stage_name!="" else "")+"%d 人" % displayed
		if selected_group=="staff": HospitalUiStyle.summary(self,"岗位分工","接待员登记，医生诊断与检查，技术员操作治疗设备，护士负责药房和留观；恢复区无需专人。")
		page_changed.emit({"rooms":"房间清单","staff":"员工","patients":"患者"}[selected_group])
		return
	var record: Dictionary=snapshot[selected_group][selected_id]
	var id:=selected_id
	if selected_group=="patients":
		_patient_page(record,snapshot,id)
		page_changed.emit("诊疗模式" if _view=="modes" else "诊疗流程" if _view=="flow" else "患者详情")
		return
	if selected_group=="staff" and _view=="assignment":
		_staff_assignment(record,snapshot,id)
		page_changed.emit("派往岗位")
		return
	var back:=_footer_button("返回" if _short_landscape else "返回列表","back",func() -> void: show_list(selected_group); present(_snapshot,catalog))
	back.icon=HospitalUiStyle.icon("back")
	if selected_group=="rooms":
		var activity:=_room_activity(record,snapshot,id)
		var role: String=catalog.rooms[record.kind].staff_role
		_hero(HospitalUiStyle.thumbnail(record.kind),HospitalUiStyle.DEVICE_NAMES.get(record.kind,catalog.rooms[record.kind].name),catalog.rooms[record.kind].name,"营业中" if record.status=="open" else "关停排空中" if record.status=="draining" else "已关闭",record.status!="open",false,true)
		_section("当前运行")
		_kv("岗位",catalog.staff[role].name if role!="" else "无需专人")
		_kv("等待人数","%d 人" % snapshot.queues[id].size())
		if record.kind=="recovery":
			var seats:=recovery_seats(snapshot,id)
			_kv("恢复席位","占用 %d · 预留 %d · 共 %d" % [seats.occupied,seats.reserved,seats.total])
		elif record.kind=="ward":
			var beds:=room_beds(snapshot,id)
			for index in range(beds.size()): _kv("病床%d" % (index+1),beds[index].copy)
		else: _kv("设备状态",activity.phase)
		var employee_copy:="无需员工" if record.kind=="recovery" else "尚未派工"
		if record.staff_id!="": employee_copy=catalog.staff[snapshot.staff[record.staff_id].role].name+_number(record.staff_id)
		_kv("当前员工",employee_copy)
		_gap(14)
		if record.kind=="ward":
			HospitalUiStyle.summary(self,"双床独立护理","一名护士照护本房两床，分别计时。已有预约、护理或离床交接时不能调走护士。",activity.busy,18,16)
		elif record.kind in ["general_exam","pharmacy"]:
			HospitalUiStyle.summary(self,"本次服务已锁定" if activity.busy else "等待接诊","服务在患者和匹配员工实际到位后开始，已预约或服务中的患者会保留交接。",activity.busy,18,16)
		else:
			HospitalUiStyle.summary(self,"容量决定设备能否继续接诊" if record.kind=="recovery" else "患者还没有离开治疗设备" if activity.handoff else "本次服务已锁定" if activity.busy else "设备当前空闲", "增加恢复席位，可缩短治疗室等待交接的时间。" if record.kind=="recovery" else "恢复区满员时，患者和技师仍占用治疗位；离开后才释放。" if activity.handoff else "模式调整作用于下一位患者，不打断已经开始的服务。",activity.handoff,18,16)
		_gap(14)
		if record.kind=="recovery":
			var rule: Dictionary=catalog.rooms.recovery
			var upgrading:=_button("已升级 · 共有%d席" % rule.upgraded_capacity if record.upgraded else "增加恢复席位 · %d币" % rule.upgrade_cost,"upgrade",func() -> void: command_requested.emit("upgrade_recovery",{"room_id":id}))
			upgrading.disabled=record.upgraded
		elif record.kind in ["echo","motion","sensory"]:
			_section("下一位患者的治疗模式")
			for mode in ["fast","gentle"]:
				var b:=_button("默认"+("快速" if mode=="fast" else "舒缓")+(" ✓" if record.mode==mode else ""),"mode_"+mode,func() -> void: command_requested.emit("set_room_mode",{"room_id":id,"mode":mode}))
				if record.mode==mode: HospitalUiStyle.primary(b)
		if catalog.rooms[record.kind].staff_role!="":
			_section("派入匹配岗位员工")
			for employee_id in snapshot.staff:
				if snapshot.staff[employee_id].role!=catalog.rooms[record.kind].staff_role: continue
				_button("派入 "+catalog.staff[snapshot.staff[employee_id].role].name+_number(employee_id),"assign_"+employee_id,func() -> void: command_requested.emit("assign_staff",{"staff_id":employee_id,"room_id":id}))
		_section("调整设施")
		var edit_row:=HFlowContainer.new()
		edit_row.add_theme_constant_override("h_separation",8)
		edit_row.add_theme_constant_override("v_separation",8)
		add_child(edit_row)
		var status:=_button("关停并排空" if record.status=="open" else "重新开放","status",func() -> void: command_requested.emit("close_room" if record.status=="open" else "reopen_room",{"room_id":id}))
		var moving:=_button("移动","move",func() -> void: move_requested.emit(record.kind,id))
		var editing:=_button("编辑布局","edit_layout",func() -> void:layout_edit_requested.emit(record.kind,id))
		remove_child(editing);edit_row.add_child(editing)
		editing.disabled=activity.edit_reason!=""
		editing.tooltip_text=activity.edit_reason
		var removing:=_button("拆除","remove",func() -> void: command_requested.emit("remove_room",{"room_id":id}))
		for button in [status,moving,removing]:
			remove_child(button)
			edit_row.add_child(button)
			button.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
		moving.disabled=activity.edit_reason!=""
		removing.disabled=activity.edit_reason!=""
		moving.tooltip_text=activity.edit_reason
		removing.tooltip_text=activity.edit_reason if removing.disabled else "拆除退还 %d 币，不计入经营利润。" % (record.invested_cost*3/4)
		removing.add_theme_color_override("font_color",Color("9a392f"))
		_gap(12)
		var legal:=HospitalUiStyle.text(activity.edit_reason if activity.edit_reason!="" else "队列、预留、服务和房内角色全部清空后，可移动或拆除。拆除退还 %d 币，不计入经营利润。" % (record.invested_cost*3/4),14,HospitalUiStyle.MUTED)
		legal.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		add_child(legal)
		back.text="返回" if _short_landscape else "返回清单"
	else:
		_hero(HospitalUiStyle.portrait(record.role,int(id.get_slice("_",1))-1,snapshot.get("appearance_seed",0)),catalog.staff[record.role].name+_number(id),"岗位分工 · "+catalog.staff[record.role].name)
		_kv("当前房间",catalog.rooms[snapshot.rooms[record.room_id].kind].name if record.room_id!="" else "未派工")
		_kv("每日工资","%d 币" % catalog.staff[record.role].daily_wage)
		if record.role=="nurse":
			var workload:=care_workload(snapshot,record.room_id)
			_kv("当前照护","%d人护理中 · %d人预约前往 · %d人离床中" % [workload.serving,workload.reserved,workload.departing])
		_kv("工作状态",{"serving":"正在服务","blocked":"等待患者交接","moving":"前往岗位","idle":"空闲"}.get(record.phase,"待派工"))
		_gap()
		var lock:=_staff_lock(record,snapshot)
		HospitalUiStyle.summary(self,lock.title,lock.copy,lock.busy,18,16)
		var dismiss:=_button("解聘闲置员工","dismiss",func() -> void: command_requested.emit("dismiss_staff",{"staff_id":id}))
		var route: Array=record.get("path",[])
		var can_dismiss: bool=record.room_id=="" and record.phase=="idle" and int(record.get("move_progress",0))==0 and int(record.get("path_index",0))+1>=route.size()
		dismiss.disabled=not can_dismiss or snapshot.challenge.status!="running"
		dismiss.tooltip_text="招聘费用不退还；释放一个在职名额。" if can_dismiss else reason("staff_assigned" if record.room_id!="" else "staff_moving")
		_text("解聘不退招聘费用。" if can_dismiss else dismiss.tooltip_text)
		var choose:=_footer_button("选择岗位","choose_assignment",func() -> void: _change_view("assignment"),true)
		if action_footer!=null: action_footer.move_child(choose,0)
		back.text="返回" if _short_landscape else "返回员工"
	if action_footer==null: move_child(back,get_child_count()-1)
	page_changed.emit(catalog.rooms[record.kind].name if selected_group=="rooms" else "员工详情")

func _staff_lock(record: Dictionary, snapshot: Dictionary) -> Dictionary:
	var remaining:=0
	var busy: bool=record.phase in ["serving","blocked"]
	var recovery_handoff:=false
	if record.room_id!="":
		busy=busy or not snapshot.queues.get(record.room_id,[]).is_empty()
		for slot in snapshot.slots.values():
			if slot.room_id!=record.room_id: continue
			busy=busy or slot.phase!="free" or slot.patient_id!=""
			remaining=maxi(remaining,int(slot.remaining_ticks))
			if slot.phase=="blocked" and snapshot.patients.get(slot.patient_id,{}).get("stage","")=="recovery": recovery_handoff=true
	if record.role=="nurse" and busy: return {"busy":true,"title":"正在照护患者","copy":"本房仍有预约、护理、离床交接或排队患者；全部完成后可调岗。"}
	if record.phase=="blocked": return {"busy":true,"title":"现在无法调离","copy":"患者仍占着设备，需等恢复席位可用并实际离开治疗位。" if recovery_handoff else "患者仍占用服务位置，需完成交接并实际离开后才能调离。"}
	if busy: return {"busy":true,"title":"本次服务尚未结束","copy":"预计剩余 %s；服务结束并完成患者交接后再调整岗位。" % _seconds(remaining) if remaining>0 else "已有患者排队或预留岗位，当前安排不能直接调离。"}
	return {"busy":false,"title":"可以派往对应岗位","copy":"选择与职业匹配的已建房间。"}

func _staff_assignment(record: Dictionary, snapshot: Dictionary, id: String) -> void:
	_hero(HospitalUiStyle.portrait(record.role,int(id.get_slice("_",1))-1,snapshot.get("appearance_seed",0)),catalog.staff[record.role].name+_number(id),catalog.staff[record.role].name,"",false,true)
	_section("匹配房间")
	var ids: Array=snapshot.rooms.keys()
	ids.sort()
	var count:=0
	var lock:=_staff_lock(record,snapshot)
	for room_id in ids:
		var room: Dictionary=snapshot.rooms[room_id]
		if catalog.rooms[room.kind].staff_role!=record.role: continue
		var card:=_list_card(HospitalUiStyle.thumbnail(room.kind),catalog.rooms[room.kind].name,_status(room.status)+(" · 当前岗位" if record.room_id==room_id else " · 已有员工" if room.staff_id!="" else " · 等待派岗"),"assign_"+room_id,func() -> void: command_requested.emit("assign_staff",{"staff_id":id,"room_id":room_id}),true)
		card.get_child(0).get_child(0).custom_minimum_size=Vector2(80,66)
		card.disabled=lock.busy or (room.staff_id!="" and room.staff_id!=id)
		card.tooltip_text=lock.copy if lock.busy else "该房间已有员工" if card.disabled else ""
		_gap(10)
		count+=1
	if count==0: _text("尚未建造对应职业的房间。")
	HospitalUiStyle.summary(self,"忙碌时保留当前服务",lock.copy if lock.busy else "调离请求会明确说明剩余时间或等待恢复的原因。",true,18,16)
	_gap()
	var withdraw:=_button("撤回待派工","unassign",func() -> void: command_requested.emit("assign_staff",{"staff_id":id,"room_id":""}))
	withdraw.disabled=lock.busy
	withdraw.tooltip_text=lock.copy if lock.busy else ""
	_footer_button("返回" if _short_landscape else "返回员工详情","back",func() -> void: _change_view("detail"))

func _resolved_mode(record: Dictionary, snapshot: Dictionary) -> String:
	if record.has("care_steps"): return ""
	if record.get("treatment_started",false): return record.get("service_mode","")
	if record.get("mode_override","")!="": return record.mode_override
	if snapshot.auto_route and record.get("tolerance_revealed",false):
		return "gentle" if catalog.diseases[record.disease_id].modes.fast.stimulus>record.tolerance else "fast"
	var slot: Dictionary=snapshot.slots.get(record.get("slot_id",""),{})
	var room_id: String=slot.get("room_id",record.get("room_id","")) if slot.get("patient_id","")==record.id else record.get("room_id","")
	var room: Dictionary=snapshot.rooms.get(room_id,{})
	return room.get("mode","") if room.get("kind","")==catalog.diseases[record.disease_id].room_kind else ""

func _patient_page(record: Dictionary, snapshot: Dictionary, id: String) -> void:
	if record.has("care_steps"):
		_care_patient_page(record,snapshot,id)
		return
	var revealed: bool=record.get("tolerance_revealed",false)
	var locked: bool=record.get("treatment_started",false) or record.phase in ["completed","abandoned","abandoning","leaving"]
	var disease: Dictionary=catalog.diseases[record.disease_id]
	var mode:=_resolved_mode(record,snapshot)
	_hero(HospitalUiStyle.portrait(record.disease_id,int(id.get_slice("_",1))-1,snapshot.get("appearance_seed",0)),"患者"+_number(id),disease.name,_phase_name(record.phase) if _view!="modes" else "",record.get("wait_reason","")!="",_view=="modes")
	if _view=="modes":
		if _draft_mode=="": _draft_mode=mode if mode!="" else "fast"
		_kv("刺激耐受",str(record.tolerance) if revealed else "诊断后显示")
		_gap(12)
		for option in ["fast","gentle"]:
			var rule: Dictionary=disease.modes[option]
			var need: bool=revealed and rule.stimulus>record.tolerance
			var card:=_button("",option,func() -> void: _draft_mode=option; _signature=""; present(_snapshot,catalog))
			card.set_meta("minimum_size",Vector2(48,150))
			card.custom_minimum_size.y=150
			var style:=HospitalUiStyle.panel(13,HospitalUiStyle.PAPER if _draft_mode==option else HospitalUiStyle.IVORY,16)
			style.set_border_width_all(2)
			style.border_color=HospitalUiStyle.TEAL if _draft_mode==option else HospitalUiStyle.LINE
			card.add_theme_stylebox_override("normal",style)
			var body:=VBoxContainer.new()
			body.mouse_filter=Control.MOUSE_FILTER_IGNORE
			card.add_child(body)
			body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			body.offset_left=16
			body.offset_right=-16
			body.offset_top=14
			body.offset_bottom=-14
			body.add_theme_constant_override("separation",8)
			var heading:=HBoxContainer.new()
			body.add_child(heading)
			var title:=HospitalUiStyle.text("快速治疗" if option=="fast" else "舒缓治疗",19,HospitalUiStyle.INK,700)
			title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
			heading.add_child(title)
			heading.add_child(HospitalUiStyle.tag("诊断后判定" if not revealed else "需恢复" if need else "无需恢复",need))
			var detail:=HospitalUiStyle.text("治疗 %d 秒 · 刺激 %d · 耗材 %d 币" % [rule.duration_ticks/10,rule.stimulus,rule.cost],15,HospitalUiStyle.MUTED)
			detail.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
			body.add_child(detail)
			var note:=HospitalUiStyle.text("诊断完成后显示恢复需求。" if not revealed else "还需40秒恢复；满员时继续占用治疗设备。" if need else "治疗完成后可直接离院，无需占恢复席位。",14,HospitalUiStyle.MUTED)
			note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
			body.add_child(note)
			_gap(12)
		var route:=_button("按耐受自动分流："+("开" if snapshot.auto_route else "关"),"auto_route",func() -> void: command_requested.emit("set_auto_route",{"enabled":not _snapshot.auto_route}))
		route.icon=HospitalUiStyle.icon("people")
		_gap(12)
		HospitalUiStyle.summary(self,"本次服务已锁定" if locked else "先比较，再应用","可查看方案，已开始的治疗不会被改写。" if locked else "单独设置优先于自动分流和房间默认。")
		var apply:=_footer_button(("已锁定" if _short_landscape else "本次模式已锁定") if locked else "应用到此患者","apply_mode",func() -> void: command_requested.emit("set_patient_mode",{"patient_id":id,"mode":_draft_mode}),true)
		apply.disabled=locked
		_footer_button("返回" if _short_landscape else "返回患者详情","back",func() -> void: _change_view("detail"))
	elif _view=="flow":
		_kv("刺激耐受",str(record.tolerance) if revealed else "诊断后显示")
		_kv("当前阶段",_phase_name(record.phase))
		_section("各阶段累计等待")
		var stages:=stage_rows(false)
		var longest:="院外"
		var maximum:=0
		for stage in stages:
			var ticks: int=record.get("wait_by_stage",{}).get(stage[0],0)
			_kv(stage[1],_seconds(ticks))
			if ticks>maximum:
				maximum=ticks
				longest=stage[1]
		_gap()
		HospitalUiStyle.summary(self,"最长累计等待：%s %s" % [longest,_seconds(maximum)],"累计等待包含排队和移动，不包含实际服务时间。")
		HospitalUiStyle.summary(self,"等待原因",reason(record.wait_reason) if record.get("wait_reason","")!="" else "当前没有排队阻塞。",record.get("wait_reason","")!="")
		_footer_button("返回" if _short_landscape else "返回患者详情","back",func() -> void: _change_view("detail"))
	else:
		_kv("刺激耐受",str(record.tolerance) if revealed else "诊断后显示")
		if mode!="" and revealed:
			var rule: Dictionary=disease.modes[mode]
			_kv("本次刺激" if record.get("treatment_started",false) else "预计刺激",str(rule.stimulus))
			_kv("需要恢复","需要 · 40 秒" if rule.stimulus>record.tolerance else "无需恢复")
		else:
			_kv("预计刺激","方案确定后显示" if revealed else "诊断后显示")
			_kv("需要恢复","方案确定后显示" if revealed else "诊断后显示")
		_kv("到院后等待",_seconds(record.wait_ticks))
		_footer_button("治疗预览" if _short_landscape else "查看治疗预览","treatment_preview",func() -> void: _change_view("modes"),true)
		if not _short_landscape: _footer_button("定位患者","locate",func() -> void: locate_requested.emit(id,"patients"))
		_footer_button("返回" if _short_landscape else "返回患者","back",func() -> void: show_list("patients",_patient_stage); present(_snapshot,catalog))
		if _short_landscape or action_footer==null:
			_gap()
			_button("查看诊疗流程","flow",func() -> void: _change_view("flow"))
		else:
			var flow:=_footer_button("诊疗流程","flow",func() -> void: _change_view("flow"))
			var link_style:=StyleBoxEmpty.new()
			link_style.content_margin_left=6
			link_style.content_margin_right=6
			flow.add_theme_stylebox_override("normal",link_style)
			flow.add_theme_font_size_override("font_size",16)
			flow.add_theme_color_override("font_color",HospitalUiStyle.TEAL)
			# Keep the fixed HFlow footer contract, while making the approved
			# primary/locate row independent from return and the light flow link.
			var rows:=VBoxContainer.new()
			rows.add_theme_constant_override("separation",9)
			rows.size_flags_horizontal=Control.SIZE_EXPAND_FILL
			action_footer.add_child(rows)
			for keys in [["treatment_preview","locate"],["back","flow"]]:
				var row:=HBoxContainer.new()
				row.add_theme_constant_override("separation",9)
				rows.add_child(row)
				for key in keys:
					var button: Button=controls[key]
					action_footer.remove_child(button)
					row.add_child(button)

func _care_patient_page(record: Dictionary, snapshot: Dictionary, id: String) -> void:
	var disease: Dictionary=catalog.diseases[record.disease_id]
	_hero(HospitalUiStyle.portrait("patient",int(id.get_slice("_",1))-1,snapshot.get("appearance_seed",0)),"患者"+_number(id),disease.name,_phase_name(record.phase),record.get("wait_reason","")!="")
	_kv("当前阶段",_phase_name(record.phase))
	_kv("到院后等待",_seconds(record.wait_ticks))
	var pathway: Dictionary=ClinicalPathways.info(record,catalog)
	_section("诊疗路线")
	var next_name := "完成全部步骤后实际离院"
	var ended: bool=record.phase in ["completed","abandoned","abandoning"]
	if record.phase=="completed": next_name="已完成全部诊疗并实际离院"
	elif record.phase=="abandoned": next_name="已弃诊离院，未完成步骤不再执行"
	elif record.phase=="abandoning": next_name="弃诊后离院中，未完成步骤不再执行"
	var found_next := false
	for step in pathway.steps:
		var name: String=STAGE_NAMES.get(step.kind,catalog.rooms.get(step.kind,{}).get("name",step.kind))
		var status: String={"completed":"已完成","current":"正在进行" if record.phase in PatientFlow.SERVICES else "当前环节","next":"待进行"}.get(step.status,"待进行")
		if ended and step.status!="completed": status="未完成"
		_kv(name,status)
		if step.status=="next" and not found_next and not ended:
			next_name=name; found_next=true
	_kv("下一站",next_name)
	HospitalUiStyle.summary(self,"等待原因",patient_wait_reason(record,snapshot,catalog),record.get("wait_reason","")!="")
	HospitalUiStyle.summary(self,"按路线完成诊疗","检查、发药与留观使用固定服务。药房和病房开始服务才扣耗材；全部规定步骤完成并实际离院后结算收入。")
	if _view=="flow":
		_section("各阶段累计等待")
		for stage in stage_rows(true): _kv(stage[1],_seconds(record.get("wait_by_stage",{}).get(stage[0],0)))
		_footer_button("返回患者详情","back",func() -> void: _change_view("detail"))
	else:
		_footer_button("诊疗流程","flow",func() -> void: _change_view("flow"),true)
		_footer_button("定位患者","locate",func() -> void: locate_requested.emit(id,"patients"))
		_footer_button("返回患者","back",func() -> void: show_list("patients",_patient_stage); present(_snapshot,catalog))

static func _status(status: String) -> String:
	return {"open":"开放","draining":"排空中","closed":"已关闭"}.get(status,"待处理")

static func _number(id: String) -> String:
	return "%03d" % int(id.get_slice("_",1))
