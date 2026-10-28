class_name CampaignPatientCard
extends PanelContainer

signal closed
signal decision_submitted(result:Dictionary)
signal preparation_requested(focus:Dictionary)
signal all_patients_requested

const ACTION_LABELS:Dictionary={"continue_exam":"继续检查","cautious_treat":"审慎治疗","refer":"转诊交接"}
const ResourceInsights=preload("res://ui/hospital_operating_insights.gd")
var patient_id:String=""
var controls:Dictionary={}
var preparation_focus:Dictionary:
	get:return _preparation.duplicate(true)
var _session:GameSession
var _selected_model:Simulation
var _callbacks:Dictionary={}
var _bounds:=Rect2(26,88,1228,532)
var _column:VBoxContainer
var _header:HBoxContainer
var _scroll:ScrollContainer
var _body:VBoxContainer
var _choices:HBoxContainer
var _footer:HBoxContainer
var _snapshot:Dictionary={}
var _decision:Dictionary={}
var _preparation:Dictionary={}
var _failure:String=""
var _built:bool=false

func initialize(session:GameSession)->void:
	_session=session
	if not _built:_build()
	hide()
	patient_id=""
	configure(_bounds)

func _build()->void:
	_built=true
	mouse_filter=Control.MOUSE_FILTER_STOP
	HospitalA2Skin.panel(self,"paper")
	_column=VBoxContainer.new()
	_column.add_theme_constant_override("separation",6)
	add_child(_column)
	_header=HBoxContainer.new()
	_header.custom_minimum_size.y=48
	_header.add_theme_constant_override("separation",8)
	_column.add_child(_header)
	var portrait:=HospitalUiStyle.picture(null,Vector2(48,48),4)
	portrait.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
	portrait.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	_header.add_child(portrait)
	controls.portrait=portrait
	var identity:=VBoxContainer.new()
	identity.add_theme_constant_override("separation",2)
	identity.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	identity.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	_header.add_child(identity)
	controls.name=_label(identity,"",16,HospitalA2Skin.INK,700,false)
	controls.phase=_label(identity,"",12,HospitalA2Skin.MUTED,400,false)
	var dismiss:=_button(_header,"close","×",func()->void:close(),"paper",22)
	dismiss.custom_minimum_size=Vector2(48,48)
	dismiss.size_flags_horizontal=Control.SIZE_SHRINK_END
	dismiss.tooltip_text="关闭患者卡"
	_scroll=ScrollContainer.new()
	_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_AUTO
	_column.add_child(_scroll)
	_body=VBoxContainer.new()
	_body.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation",6)
	_scroll.add_child(_body)
	controls.confidence=_label(_body,"",13,HospitalA2Skin.TEAL,650)
	_choices=HBoxContainer.new()
	_choices.add_theme_constant_override("separation",4)
	_body.add_child(_choices)
	for action:String in CampaignClinicalDecisions.ACTIONS:
		var button:=_button(_choices,"decision_"+action,str(ACTION_LABELS[action]),Callable(),"enamel" if action=="continue_exam" else "paper",13)
		button.custom_minimum_size=Vector2(48,64)
		button.set_meta("minimum_size",Vector2(48,64))
		button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	controls.status=_label(_body,"",13,HospitalA2Skin.MUTED)
	controls.message=_label(_body,"",13,HospitalA2Skin.CORAL)
	_footer=HBoxContainer.new()
	_footer.add_theme_constant_override("separation",6)
	_column.add_child(_footer)
	var prepare:=_button(_footer,"prepare_treatment","准备治疗",func()->void:
		if not _preparation.is_empty():preparation_requested.emit(_preparation.duplicate(true)),"primary",14)
	prepare.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	controls.prepare=prepare
	var all:=_button(_footer,"all_patients","完整名单",func()->void:all_patients_requested.emit(),"paper",14)
	all.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	prepare.hide()

func _label(parent:Node,copy:String,font_size:int,color:Color,weight:int=400,wrap:bool=true)->Label:
	var label:=HospitalUiStyle.text(copy,font_size,color,weight)
	label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART if wrap else TextServer.AUTOWRAP_OFF
	if not wrap:
		label.clip_text=true
		label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	parent.add_child(label)
	return label

func _button(parent:Node,key:String,copy:String,action:Callable,variant:String,font_size:int)->Button:
	var button:=Button.new()
	button.text=copy
	HospitalA2Skin.button(button,variant,font_size)
	if action.is_valid():button.pressed.connect(action)
	parent.add_child(button)
	controls[key]=button
	return button

func show_patient(id:String)->bool:
	if _session==null:return false
	var current:Dictionary=_session.presentation_snapshot()
	if id=="" or not current.get("patients",{}).has(id):
		close()
		return false
	if patient_id!=id or _selected_model!=_session.sim:
		_failure=""
		_scroll.scroll_vertical=0
	_selected_model=_session.sim
	patient_id=id
	show()
	present(current)
	return true

func close()->void:
	var active:bool=visible or patient_id!=""
	patient_id=""
	_selected_model=null
	for action:String in _callbacks:
		var button:Button=controls["decision_"+action]
		if button.pressed.is_connected(_callbacks[action]):button.pressed.disconnect(_callbacks[action])
		button.disabled=true
	_callbacks.clear()
	_snapshot={};_decision={};_preparation={};_failure=""
	hide()
	if active:closed.emit()

func present(snapshot:Dictionary={})->void:
	if _session==null or patient_id=="":return
	if _selected_model!=_session.sim:close();return
	_snapshot=_session.presentation_snapshot() if snapshot.is_empty() else snapshot
	var patient:Dictionary=_snapshot.get("patients",{}).get(patient_id,{})
	if patient.is_empty():close();return
	_decision=CampaignClinicalDecisions.preview(_snapshot,_session.catalog,patient_id)
	var name:String=str(patient.get("display_name",""))
	if name.strip_edges()=="":name="门诊号 "+patient_id.trim_prefix("patient_")
	controls.name.text=name
	controls.name.tooltip_text=name
	controls.portrait.texture=SceneArtLibrary.actor_portrait(patient,false,int(_snapshot.get("appearance_seed",0)))
	var pending:bool=bool(_decision.get("pending",false))
	var phase:String="复检完成 · 待决定" if pending and int(_decision.get("completed_exams",0))>0 else "首诊完成 · 待决定" if pending else CampaignHospitalPanel.phase_name(str(patient.get("phase","")))
	controls.phase.text=phase
	controls.phase.tooltip_text=phase
	var confidence:int=int(_decision.get("confidence",-1))
	if confidence>=0:
		var disease_name:String=str(_session.catalog.campaign.get("diseases",{}).get(str(patient.get("disease_id","")),{}).get("name",""))
		if disease_name!="":
			phase="疑似："+disease_name+" · "+("待决定" if pending else phase)
			controls.phase.text=phase
			controls.phase.tooltip_text=phase
	controls.confidence.text="诊断依据：等待首诊检查" if confidence<0 else "诊断把握度 %d / 100 · 治疗建议线 %d"%[confidence,int(_decision.get("safe_threshold",80))]
	_preparation={}
	var unavailable:Array[String]=[]
	var blocked:bool=_session.storage_blocked or str(_snapshot.get("challenge",{}).get("status","running"))!="running"
	for action:String in CampaignClinicalDecisions.ACTIONS:
		var button:Button=controls["decision_"+action]
		var terms:Dictionary=_decision.get("terms",{}).get(action,{})
		var missing:Array=terms.get("missing",[])
		var exhausted:bool=action=="continue_exam" and int(_decision.get("completed_exams",0))>=int(_decision.get("max_exams",CampaignClinicalDecisions.MAX_EXAMS))
		button.disabled=not pending or blocked or exhausted or not missing.is_empty()
		button.text=str(ACTION_LABELS[action])
		if pending and not terms.is_empty():button.text+="\n%d币 · %.1f秒"%[int(terms.planned_cost),float(terms.planned_duration_ticks)/10.0]
		var why:String="存档暂不可写，请先检查保存状态。" if _session.storage_blocked else "本阶段已结束。" if blocked else "当前不在诊疗决定阶段。" if not pending else "已经完成最多%d次复检。"%int(_decision.get("max_exams",2)) if exhausted else _reason(missing) if not missing.is_empty() else ""
		button.tooltip_text=why
		_bind_choice(action)
		if pending and button.disabled and why!="":unavailable.append(str(ACTION_LABELS[action])+"："+why)
	_choices.visible=pending
	if pending and not blocked:
		for action:String in ["cautious_treat","continue_exam","refer"]:
			var missing:Array=_decision.get("terms",{}).get(action,{}).get("missing",[])
			_preparation=_prepare_for(missing)
			if not _preparation.is_empty():_preparation.decision_action=action
			if not _preparation.is_empty():break
	controls.prepare_treatment.visible=not _preparation.is_empty()
	controls.prepare_treatment.disabled=_preparation.is_empty()
	controls.prepare_treatment.text="准备转诊" if _preparation.get("decision_action","")=="refer" else "准备治疗"
	if _preparation.get("action","")=="staff":controls.prepare_treatment.text="安排诊疗岗位"
	elif _preparation.get("action","")=="resume":controls.prepare_treatment.text="继续补给"
	elif _preparation.get("section","")=="resource":controls.prepare_treatment.text="查看诊疗物资"
	controls.prepare_treatment.set_meta("focus",preparation_focus)
	controls.prepare_treatment.tooltip_text=_reason(_decision.get("terms",{}).get("cautious_treat",{}).get("missing",[]))
	controls.status.text="；".join(unavailable) if pending else _service_status(patient)
	controls.status.visible=controls.status.text!=""
	controls.message.text=_failure
	controls.message.visible=_failure!=""
	configure(_bounds)

func _reason(value:Variant)->String:
	return CampaignHospitalPanel.reason_text(value,_session.catalog.campaign,_snapshot)

func _prepare_for(missing:Array)->Dictionary:
	for value:Variant in missing:
		var code:String=str(value)
		if code.begins_with("missing_facility:"):
			var kind:String=code.trim_prefix("missing_facility:")
			for facility:Dictionary in _snapshot.get("facilities",{}).values():
				if str(facility.kind)!=kind:continue
				if int(facility.get("condition",0))<=0:
					return {"action":"operation","facility_kind":"O11","scroll_control":"run_operation","patient_id":patient_id}
				return {"action":"goals","section":"rooms","facility_kind":kind,"facility_id":str(facility.id),"control":"close_"+str(facility.id),"patient_id":patient_id}
			return {"action":"build","facility_kind":kind,"patient_id":patient_id}
		if code.begins_with("missing_staff:"):
			return _staff_focus(code.trim_prefix("missing_staff:"))
		if code.begins_with("missing_resource:"):
			return _resource_focus(code.trim_prefix("missing_resource:"))
		if code=="insufficient_cash":return {"action":"goals","section":"finance","patient_id":patient_id}
	return {}

func _step_for(subject:String)->Dictionary:
	var patient:Dictionary=_snapshot.patients.get(patient_id,{})
	var steps:Array=patient.get("steps",[]).duplicate()
	steps.append_array(_session.catalog.campaign.cases.get(patient.get("case_id",""),{}).get("steps",[]))
	for terms:Dictionary in _decision.get("terms",{}).values():steps.append_array(terms.get("steps",[]))
	for step:Dictionary in steps:
		if str(step.get("id",""))==subject:return step
	if _session.catalog.campaign.facilities.has(subject):
		return {"facility_kind":subject,"roles":_session.catalog.campaign.facilities[subject].get("roles",[])}
	return {}

func _staff_focus(subject:String)->Dictionary:
	var step:Dictionary=_step_for(subject)
	var kind:String=str(step.get("facility_kind",""))
	if kind=="":return {}
	for facility:Dictionary in _snapshot.facilities.values():
		if str(facility.kind)!=kind or str(facility.status)!="open" or int(facility.condition)<=0:continue
		for role:String in step.get("roles",[]):
			if not CampaignClinicalFlow._qualified_staff(_snapshot,facility,[role],false).is_empty():continue
			var focus:Dictionary={"action":"staff","facility_kind":kind,"facility_id":str(facility.id),"role":role,"control":"hire","patient_id":patient_id}
			for employee:Dictionary in _snapshot.staff.values():
				if employee.role==role and str(employee.get("facility_id",""))=="" and not CampaignPeople.staff_busy(employee):
					focus.control="assign";focus.staff_id=str(employee.id);break
			return focus
	return {"action":"goals","section":"staff","facility_kind":kind,"patient_id":patient_id}

func _resource_focus(resource:String,visited:Dictionary={})->Dictionary:
	var focus:Dictionary={"action":"goals","section":"resource","resource":resource,"patient_id":patient_id}
	if visited.has(resource):return focus
	var seen:Dictionary=visited.duplicate()
	seen[resource]=true
	for order:Dictionary in _snapshot.get("work_orders",{}).values():
		if int(order.get("output",{}).get(resource,0))<=0 or order.status in ["done","failed","cancelled"]:continue
		# A queued/walking output is not progress when its inputs cannot be paid.
		# Working jobs already consumed their locked input/cost; never charge twice.
		if order.status!="working" and int(order.get("started_tick",-1))<0:
			var input:String=str(order.get("resource",""))
			if not CampaignClinicalFlow._stock_ready(_snapshot,{"resource":input,"quantity":int(order.get("quantity",0))}):
				return _resource_focus(input,seen)
			if CampaignClinicalFlow._available_cash(_snapshot)<int(order.get("cost",0)):
				return {"action":"goals","section":"finance","patient_id":patient_id}
			var missing:Array=CampaignOperations.readiness(_snapshot,_session.catalog,str(order.facility_kind))
			if not missing.is_empty():return _prepare_for(missing)
			var reason:String=str(order.get("reason",""))
			if reason in ["missing_or_busy_staff","missing_staff"]:
				return {"action":"goals","section":"staff","facility_kind":str(order.facility_kind),"patient_id":patient_id}
			if reason in ["unreachable_workplace","path_blocked"]:
				return {"action":"goals","section":"rooms","facility_id":str(order.facility_id),"patient_id":patient_id}
		if bool(_snapshot.get("paused",true)):return {"action":"resume","resource":resource,"work_order_id":str(order.id),"patient_id":patient_id}
		return focus
	for definition:Dictionary in _session.catalog.campaign.facilities.values():
		if int(definition.get("output",{}).get(resource,0))<=0:continue
		var kind:String=str(definition.id)
		var missing:Array=CampaignOperations.readiness(_snapshot,_session.catalog,kind)
		if not missing.is_empty():
			var preparation:Dictionary=_prepare_for(missing)
			preparation.resource=resource
			return preparation
		var estimate:Dictionary=ResourceInsights.operation(_snapshot,_session.catalog,kind)
		if int(estimate.get("missing_input",0))>0:return _resource_focus(str(estimate.get("input_resource","")),seen)
		if int(estimate.get("cash_after",0))<0:return {"action":"goals","section":"finance","patient_id":patient_id}
		focus.facility_kind=kind
		focus.control="resource_run_"+kind
		break
	return focus

func _service_status(patient:Dictionary)->String:
	var phase:String=str(patient.get("phase",""))
	if phase=="left":return "已完成转诊并实际离院；不计本院治愈。" if patient.get("outcome","")=="referred" else "本次诊疗已完成并实际离院。"
	if phase=="abandoned":return "患者已放弃就诊，未完成本次诊疗。"
	var steps:Array=patient.get("steps",[])
	var index:int=int(patient.get("step_index",0))
	var kind:String=str(steps[index].get("facility_kind","")) if index>=0 and index<steps.size() else ""
	var facility:String=str(_session.catalog.campaign.facilities.get(kind,{}).get("name",kind))
	if phase=="care_service":return "正在%s · %.1f / %.1f秒"%[facility,float(patient.get("service_work",0))/10.0,float(patient.get("service_needed",0))/10.0]
	var reason:String=str(patient.get("wait_reason",""))
	if reason!="":return _reason(reason)
	if phase=="moving_exit":return "正在前往出口；实际离院后才结算。"
	if phase=="moving_care":return "正在前往"+facility+"，尚未开始本次服务。"
	if phase=="waiting_support":return "正在等待实际后勤工序与交接完成。"
	return "正在等候"+facility+"；需要真实人员、设备与供给。"

func _bind_choice(action:String)->void:
	var button:Button=controls["decision_"+action]
	if _callbacks.has(action) and button.pressed.is_connected(_callbacks[action]):button.pressed.disconnect(_callbacks[action])
	var model:Simulation=_selected_model
	var id:String=patient_id
	var revision:int=int(_decision.get("revision",-1))
	var callback:Callable=func()->void:_submit(action,model,id,revision)
	_callbacks[action]=callback
	button.pressed.connect(callback)

func _submit(action:String,model:Simulation,id:String,revision:int)->void:
	if _session==null or _session.sim!=model:
		close()
		decision_submitted.emit({"ok":false,"code":"patient_context_changed","data":{"message":"医院已切换，请重新选择患者。"}})
		return
	if patient_id!=id:
		_failure="所选患者已切换，请查看当前患者的方案。"
		present()
		decision_submitted.emit({"ok":false,"code":"patient_selection_changed","data":{"message":_failure}})
		return
	var button:Button=controls["decision_"+action]
	if patient_id=="" or button.disabled:return
	var result:Dictionary=_session.issue("clinical_decision",{"patient_id":id,"action":action,"expected_revision":revision})
	_failure="" if result.get("ok",false) else _reason(result)
	present()
	decision_submitted.emit(result)

func configure(content_bounds:Rect2)->void:
	_bounds=content_bounds
	if not _built:return
	var width:float=minf(350 if content_bounds.size.x<1050 or content_bounds.size.y<330 else 390,maxf(48,content_bounds.size.x))
	var height:float=minf(280,maxf(0,content_bounds.size.y))
	custom_minimum_size=Vector2(width,0)
	_body.custom_minimum_size.x=maxf(48,width-32)
	_scroll.custom_minimum_size.y=0
	size=Vector2(width,height)
	position=Vector2(content_bounds.end.x-width,content_bounds.position.y)
