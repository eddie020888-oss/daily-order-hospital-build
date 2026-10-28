class_name HospitalOperationsPanel
extends VBoxContainer

signal recovery_requested
signal patients_requested
signal stage_requested(stage: String)
signal congestion_requested
signal command_requested(type: String, payload: Dictionary)

const STAGES := [["reception","接待","登记、排队与接待中"],["diagnosis","诊断","排队、前往诊断与诊断中"],["general_exam","综合检查","等待检查室与医生"],["pharmacy","发药","等待药房与护士"],["ward","留观","等待空床、护士与留观护理"],["treatment","治疗","等待对应设备与技术员"],["recovery","恢复","前往恢复、候位与恢复中"],["exit","离院","正在走向出口"]]
var view:="flow"
var controls: Dictionary={}
var summary: Dictionary={}
var action_footer: HFlowContainer
var _labels: Dictionary={}
var _snapshot: Dictionary={}
var _catalog: ContentCatalog

func initialize(content: ContentCatalog) -> void:
	_catalog=content

static func project(snapshot: Dictionary) -> Dictionary:
	var state:=ClinicState.new()
	state.data=snapshot
	var metrics:=Metrics.summary(state)
	var counts: Dictionary={}
	for row in STAGES: counts[row[0]]=0
	var waits:=counts.duplicate()
	for patient in snapshot.patients.values():
		if patient.phase in ["outside","completed","abandoned"]: continue
		var stage: String="exit" if patient.phase in ["leaving","abandoning"] else patient.stage
		if not counts.has(stage): continue
		counts[stage]+=1
		if patient.phase not in PatientFlow.SERVICES: waits[stage]=maxi(waits[stage],int(patient.get("wait_by_stage",{}).get(stage,0)))
	var devices: Dictionary={}
	var blocked_patients: Dictionary={}
	for slot in snapshot.slots.values():
		var room: Dictionary=snapshot.rooms.get(slot.room_id,{})
		var patient: Dictionary=snapshot.patients.get(slot.patient_id,{})
		if room.get("kind","") not in ["echo","motion","sensory"] or slot.phase!="blocked": continue
		if patient.get("stage","")!="recovery" or patient.get("phase","") in ["completed","abandoned"]: continue
		devices[slot.room_id]=true
		blocked_patients[slot.patient_id]=true
	var recovery_ids: Array=[]
	for id in snapshot.rooms:
		if snapshot.rooms[id].kind=="recovery": recovery_ids.append(id)
	recovery_ids.sort()
	var targets: Array=[]
	for patient_id in blocked_patients:
		var room_id: String=snapshot.patients[patient_id].get("room_id","")
		if room_id in recovery_ids and room_id not in targets: targets.append(room_id)
	if targets.is_empty():
		for room_id in recovery_ids:
			if snapshot.rooms[room_id].status=="open": targets.append(room_id)
	targets.sort()
	var longest:="reception"
	for row in STAGES:
		if waits[row[0]]>waits[longest]: longest=row[0]
	return {"stage_counts":counts,"stage_waits":waits,"dispositions":metrics.dispositions,"seats":SelectionPanel.recovery_seats(snapshot),"blocked_devices":devices.size(),"blocked_patient_ids":blocked_patients.keys(),"recovery_ids":recovery_ids,"recovery_id":targets[0] if not targets.is_empty() else "" if recovery_ids.is_empty() else recovery_ids[0],"bottleneck":longest}

func show_view(kind: String, snapshot: Dictionary) -> void:
	view=kind
	for child in get_children(): remove_child(child); child.queue_free()
	if action_footer!=null:
		for child in action_footer.get_children(): action_footer.remove_child(child); child.queue_free()
	controls.clear()
	_labels.clear()
	add_theme_constant_override("separation",0)
	if view=="flow": _build_flow()
	else: _build_congestion()
	present(snapshot)

func _label(copy: String, size: int=16, color: Color=HospitalUiStyle.MUTED, weight: int=400) -> Label:
	var label:=HospitalUiStyle.text(copy,size,color,weight)
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	return label

func _gap(height: int=14) -> void:
	var gap:=Control.new()
	gap.custom_minimum_size.y=height
	add_child(gap)

func _button(parent: Node, key: String, copy: String, action: Callable, primary: bool=false) -> Button:
	var button:=BuildPalette.button(copy)
	button.clip_text=false
	button.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
	parent.add_child(button)
	controls[key]=button
	button.pressed.connect(action)
	if primary: HospitalUiStyle.primary(button)
	return button

func _build_flow() -> void:
	_labels.overview=_label("")
	add_child(_labels.overview)
	_gap(18)
	add_child(_label("哪里在等",18,HospitalUiStyle.INK,700))
	_gap(10)
	for i in range(STAGES.size()):
		var stage: Array=STAGES[i]
		var card:=_button(self,"stage_"+stage[0],"",func() -> void:
			if stage[0]=="recovery": congestion_requested.emit()
			else: stage_requested.emit(stage[0]))
		card.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		card.custom_minimum_size.y=82
		card.set_meta("minimum_size",Vector2(48,82))
		var style:=HospitalUiStyle.panel(12,Color("edf2e8"),13)
		style.set_border_width_all(0)
		card.add_theme_stylebox_override("normal",style)
		var row:=HBoxContainer.new()
		row.mouse_filter=Control.MOUSE_FILTER_IGNORE
		card.add_child(row)
		row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		row.offset_left=15; row.offset_right=-15; row.offset_top=13; row.offset_bottom=-13
		row.add_theme_constant_override("separation",14)
		var badge:=_label(str(i+1),16,HospitalUiStyle.INK,700)
		badge.autowrap_mode=TextServer.AUTOWRAP_OFF
		badge.custom_minimum_size=Vector2(36,36)
		badge.size_flags_vertical=Control.SIZE_SHRINK_CENTER
		badge.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
		badge.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		badge.add_theme_stylebox_override("normal",HospitalUiStyle.panel(18,Color("d5e3d0"),0))
		row.add_child(badge)
		var copy:=VBoxContainer.new()
		copy.mouse_filter=Control.MOUSE_FILTER_IGNORE
		copy.add_theme_constant_override("separation",2)
		copy.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		row.add_child(copy)
		copy.add_child(_label(stage[1],18,HospitalUiStyle.INK,700))
		var detail:=_label(stage[2],14)
		copy.add_child(detail)
		_labels["detail_"+stage[0]]=detail
		var count_column:=VBoxContainer.new()
		count_column.custom_minimum_size.x=34
		count_column.size_flags_vertical=Control.SIZE_SHRINK_CENTER
		count_column.add_theme_constant_override("separation",0)
		count_column.mouse_filter=Control.MOUSE_FILTER_IGNORE
		row.add_child(count_column)
		var count:=_label("0",23,HospitalUiStyle.INK,750)
		count.autowrap_mode=TextServer.AUTOWRAP_OFF
		count.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
		count_column.add_child(count)
		var unit:=_label("人",14)
		unit.autowrap_mode=TextServer.AUTOWRAP_OFF
		unit.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
		count_column.add_child(unit)
		_labels["count_"+stage[0]]=count
		_gap(10)
	var note:=HospitalUiStyle.summary(self,"最长等待","",true,18,16)
	_labels.bottleneck=note.get_child(0).get_child(0)
	_labels.advice=note.get_child(0).get_child(1)
	_button(action_footer,"recovery","定位恢复区",func() -> void: recovery_requested.emit(),true)
	_button(action_footer,"patients","患者清单",func() -> void: patients_requested.emit())

func _build_congestion() -> void:
	var hero:=HBoxContainer.new()
	hero.add_theme_constant_override("separation",14)
	add_child(hero)
	var icon_card:=PanelContainer.new()
	icon_card.custom_minimum_size=Vector2(50,50)
	icon_card.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	icon_card.add_theme_stylebox_override("panel",HospitalUiStyle.panel(12,Color("e7eddf"),11))
	hero.add_child(icon_card)
	var mark:=HospitalUiStyle.icon_picture("alert",27)
	mark.self_modulate=HospitalUiStyle.INK
	icon_card.add_child(mark)
	var copy:=VBoxContainer.new()
	copy.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	copy.add_theme_constant_override("separation",4)
	hero.add_child(copy)
	_labels.held=_label("",23,HospitalUiStyle.INK,700)
	copy.add_child(_labels.held)
	_labels.seats=HospitalUiStyle.tag("",true)
	_labels.seats.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_labels.seats.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	copy.add_child(_labels.seats)
	_gap()
	var note:=HospitalUiStyle.summary(self,"患者尚未离开设备","",true,18,16)
	_labels.explanation_title=note.get_child(0).get_child(0)
	_labels.explanation=note.get_child(0).get_child(1)
	_gap(18)
	add_child(_label("可以这样改善",18,HospitalUiStyle.INK,700))
	var capacity_copy:="第二席位升级 %d 币，或新建恢复区 %d 币。" % [_catalog.rooms.recovery.upgrade_cost,_catalog.rooms.recovery.cost]
	var routing_copy:="舒缓模式刺激 %d，可减少恢复需求。" % _catalog.diseases.echo.modes.gentle.stimulus
	for row in [["增加恢复容量",capacity_copy],["提前分流低耐受患者",routing_copy],["检查通行路线","保持设备到恢复席位的路径畅通。"]]:
		var step:=HBoxContainer.new()
		step.add_theme_constant_override("separation",13)
		add_child(step)
		var badge:=_label(str(["增加恢复容量","提前分流低耐受患者","检查通行路线"].find(row[0])+1),18,Color.WHITE,700)
		badge.custom_minimum_size=Vector2(33,33)
		badge.size_flags_vertical=Control.SIZE_SHRINK_BEGIN
		badge.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		badge.add_theme_stylebox_override("normal",HospitalUiStyle.panel(10,HospitalUiStyle.TEAL,4))
		step.add_child(badge)
		var body:=VBoxContainer.new()
		body.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		body.add_theme_constant_override("separation",5)
		step.add_child(body)
		body.add_child(_label(row[0],18,HospitalUiStyle.INK,700))
		body.add_child(_label(row[1]))
		_gap()
		add_child(HSeparator.new())
		_gap()
	_button(action_footer,"recovery","查看恢复区",func() -> void: recovery_requested.emit(),true)
	_button(action_footer,"auto_route","按耐受分流",func() -> void: command_requested.emit("set_auto_route",{"enabled":not _snapshot.auto_route}))

func present(snapshot: Dictionary) -> void:
	_snapshot=snapshot
	summary=project(snapshot)
	if _labels.is_empty(): return
	var s:=summary
	var seats: Dictionary=s.seats
	if view=="flow":
		_labels.overview.text="%d 人在院 · %d 人已弃诊 · %d 人完成离院" % [s.dispositions.in_hospital,s.dispositions.abandoned,s.dispositions.completed]
		if s.dispositions.outside>0: _labels.overview.text+=" · %d 人院外等候" % s.dispositions.outside
		for row in STAGES:
			_labels["count_"+row[0]].text=str(s.stage_counts[row[0]])
			controls["stage_"+row[0]].visible=row[0] not in SelectionPanel.CARE_STAGES or snapshot.level_id=="clinical_02"
		var full: bool=seats.total>0 and seats.occupied+seats.reserved>=seats.total
		_labels.detail_recovery.text=("满员 · " if full else "交接中 · ")+"%d台设备等交接" % s.blocked_devices if s.blocked_devices>0 else "前往恢复、候位与恢复中"
		var name: String=""
		for row in STAGES:
			if row[0]==s.bottleneck: name=row[1]
		_labels.bottleneck.text="最长等待：%s阶段" % name if s.stage_waits[s.bottleneck]>0 else "恢复阶段等待交接" if s.blocked_devices>0 else "当前没有等待瓶颈"
		_labels.advice.text="先调整低耐受患者的模式，或增加恢复席位。" if s.blocked_devices>0 else "当前阶段人数包含排队、移动与服务；已离院患者不重复计数。"
		controls.recovery.disabled=s.recovery_id==""
		controls.recovery.tooltip_text="尚未建造恢复区。" if s.recovery_id=="" else ""
	else:
		_labels.held.text="%d 台设备等待交接" % s.blocked_devices if s.blocked_devices>0 else "当前没有设备等待交接"
		_labels.explanation_title.text="患者尚未离开设备" if s.blocked_devices>0 else "恢复交接已疏通"
		_labels.seats.text="恢复席位 %d / %d 已占用 · 预留 %d" % [seats.occupied,seats.total,seats.reserved]
		_labels.explanation.text="当前技师仍被占用。空闲恢复席位出现并完成移动后，设备才会释放。" if s.blocked_devices>0 else "当前没有恢复交接阻塞；席位、设备与技师状态会随真实营业更新。"
		controls.recovery.text="查看恢复区" if s.recovery_id!="" else "新建恢复区"
		controls.recovery.disabled=s.recovery_id=="" and snapshot.challenge.status!="running"
		controls.auto_route.text="按耐受分流：开" if snapshot.auto_route else "按耐受分流"
		controls.auto_route.disabled=snapshot.challenge.status!="running"
