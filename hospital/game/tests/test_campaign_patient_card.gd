extends SceneTree

const FormalPaths=preload("res://tests/support/formal_test_paths.gd")
var test_paths:Variant

# Breaks caught: clinical scene selection opens an all-screen form; scrolling loses
# identity; a preview spends money; stale/wrong-patient actions authorize care;
# and missing therapy is replaced by a fake cure or a generic build instruction.
var output:String=""
var passed:int=0
var failed:int=0
var checks:Array=[]
var catalog:ContentCatalog
var card_script:Script
var received:Array=[]
var preparations:Array=[]
var closed_count:int=0
var all_count:int=0

func _initialize()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=").replace("\\","/")
	var reservation:Dictionary=FormalPaths.reserve(output,"campaign-patient-card")
	if not reservation.get("ok",false):
		printerr("FORMAL TEST PATH ERROR: "+str(reservation.get("code","unknown")));quit(2);return
	test_paths=reservation.paths;output=str(reservation.output)
	_run.call_deferred()

func check(ok:bool,label:String,detail:String="")->void:
	checks.append({"ok":ok,"check":label,"detail":detail})
	if ok:passed+=1
	else:failed+=1
	print(("PATIENT CARD PASS: " if ok else "PATIENT CARD FAIL: ")+label+(": "+detail if detail!="" else ""))

func issue(session:GameSession,type:String,payload:Dictionary={})->Dictionary:
	var result:Dictionary=session.issue(type,payload)
	check(bool(result.get("ok",false)),"real fixture command "+type,str(result.get("code","")))
	return result

func build(session:GameSession,kind:String,cell:int)->String:
	var definition:Dictionary=catalog.campaign.facilities[kind]
	var result:Dictionary=issue(session,"build_department",{"unit_id":definition.unit_id,"origin_cell":cell,"layout":FacilityLayout.default_layout(definition.unit_id,kind,0)})
	if not result.get("ok",false):return ""
	var id:String=str(result.data.facility_ids[0])
	for role:String in definition.roles:
		var hire:Dictionary=issue(session,"hire",{"role":role})
		if not hire.get("ok",false):return ""
		if not issue(session,"assign",{"staff_id":hire.data.staff_id,"facility_id":id}).get("ok",false):return ""
	return id

func fixture()->Dictionary:
	var fixture_path:String=test_paths.fixture("hospital")
	if fixture_path=="":
		printerr("FORMAL TEST PATH ERROR: fixture_create_failed");quit(2);return {}
	var session:=GameSession.new(catalog,fixture_path)
	session.sim=Simulation.new(catalog,LongCampaignState.create_formal("long_01",catalog))
	for row:Array in [["U04-E1",25],["O01",33],["O15",40],["O05",125]]:
		if build(session,str(row[0]),int(row[1]))=="":return {}
	var delivery:Dictionary=issue(session,"run_operation",{"facility_kind":"O15"})
	if not delivery.get("ok",false):return {}
	issue(session,"set_paused",{"paused":false})
	for _n:int in range(1200):
		if session.sim.snapshot().work_orders[delivery.data.work_order_id].status=="done":break
		session.sim.advance_ticks(1)
	check(session.sim.snapshot().work_orders[delivery.data.work_order_id].status=="done","real delivered stock precedes patient admission")
	var admission:Dictionary=issue(session,"admit_routine",{"case_id":"U04-C2"})
	if not admission.get("ok",false):return {}
	var id:String=str(admission.data.patient_ids[0])
	var initial:Dictionary=session.sim.snapshot()
	for _n:int in range(1800):
		if CampaignClinicalDecisions.preview(session.sim.snapshot(),catalog,id).get("pending",false):break
		session.sim.advance_ticks(1)
	var pending:Dictionary=session.sim.snapshot()
	check(CampaignClinicalDecisions.preview(pending,catalog,id).get("pending",false),"real examination reaches manual clinical decision without invented history")
	check(SnapshotValidator.validate(pending,catalog)=="","fixture is a genuine save-valid formal clinical hospital")
	return {"session":session,"id":id,"initial":initial,"pending":pending}

func restored(snapshot:Dictionary,suffix:String)->GameSession:
	var loaded:Dictionary=ClinicState.from_data(snapshot,catalog)
	check(loaded.get("ok",false),"restore genuine fixture "+suffix,str(loaded.get("error","")))
	var fixture_path:String=test_paths.fixture(suffix)
	if fixture_path=="":
		printerr("FORMAL TEST PATH ERROR: fixture_create_failed");quit(2);return null
	var session:=GameSession.new(catalog,fixture_path)
	if loaded.get("ok",false):session.sim=Simulation.new(catalog,loaded.state)
	return session

func card_for(session:GameSession)->Control:
	var card:Control=card_script.new()
	root.add_child(card)
	card.initialize(session)
	card.decision_submitted.connect(func(result:Dictionary)->void:received.append(result))
	card.preparation_requested.connect(func(focus:Dictionary)->void:preparations.append(focus))
	card.closed.connect(func()->void:closed_count+=1)
	card.all_patients_requested.connect(func()->void:all_count+=1)
	return card

func text_of(node:Node)->String:
	var result:String=""
	if node is Label:result=node.text+"\n"
	elif node is Button:result=node.text+"\n"
	for child:Node in node.get_children():result+=text_of(child)
	return result

func _frames()->void:
	for _n:int in range(5):await process_frame

func test_identity_bounds_and_readonly(data:Dictionary)->void:
	var session:GameSession=restored(data.initial,"before-exam")
	if session==null:return
	var card:Control=card_for(session)
	var before:Dictionary=session.sim.snapshot()
	check(card.show_patient(data.id) and card.visible and card.patient_id==data.id,"scene patient selection opens the selected live card")
	card.configure(Rect2(59,90,814,224))
	await _frames()
	check(Rect2(59,90,814,224).encloses(card.get_global_rect()) and card.size.x>=340 and card.size.x<=360 and card.size.y<=224,"932x430 content bounds retain a narrow right card between real header and dock",str(card.get_global_rect()))
	check(card.position.x>=59+814-card.size.x-9,"short patient card occupies the right edge and leaves hospital visible")
	check(not text_of(card).contains(str(catalog.campaign.diseases[before.patients[data.id].disease_id].name)),"before first examination concrete disease name remains undisclosed")
	check(not text_of(card).contains("已确诊"),"pre-exam card does not claim a confirmed diagnosis")
	check(card.controls.close.size.x>=48 and card.controls.close.size.y>=48,"fixed close entry retains a real48-unit target")
	for _n:int in range(3):card.present(session.sim.snapshot())
	check(session.sim.snapshot()==before,"opening configuring and refreshing cannot change the clinical model")
	card.configure(Rect2(26,88,1228,532))
	await _frames()
	check(card.size.x>=380 and card.size.x<=400 and Rect2(26,88,1228,532).encloses(card.get_global_rect()),"wide viewport uses a380-400 right card within unobstructed content")
	card.controls.all_patients.pressed.emit()
	check(all_count==1 and session.sim.snapshot()==before,"complete list is an explicit navigation signal rather than an implicit full-form replacement")
	card.controls.close.pressed.emit()
	check(not card.visible and card.patient_id=="" and closed_count==1,"closing clears active patient ownership and emits closed")
	check(not card.show_patient("not-a-patient") and not card.visible and card.patient_id=="","unknown entity cannot reopen a stale patient card")
	card.free()

func test_real_terms_prepare_and_scroll(data:Dictionary)->void:
	var session:GameSession=restored(data.pending,"pending")
	if session==null:return
	var card:Control=card_for(session)
	card.configure(Rect2(59,90,814,224))
	card.show_patient(data.id)
	await _frames()
	var before:Dictionary=session.sim.snapshot()
	var view:Dictionary=CampaignClinicalDecisions.preview(before,catalog,data.id)
	check(not card.controls.decision_continue_exam.disabled and not card.controls.decision_refer.disabled,"available examination and real staffed referral remain actionable")
	check(card.controls.decision_cautious_treat.disabled and "missing_facility:U04-E2" in view.terms.cautious_treat.missing,"missing authored therapy disables actual treatment")
	for action:String in ["continue_exam","cautious_treat","refer"]:
		var button:Button=card.controls["decision_"+action]
		var terms:Dictionary=view.terms[action]
		check(button.text.contains(str(int(terms.planned_cost))) and button.text.contains("%.1f"%(float(terms.planned_duration_ticks)/10.0)),action+" displays actual planned cost and duration")
		check(button.get_combined_minimum_size().x>=48 and button.get_combined_minimum_size().y>=48,action+" reserves at least48 units of touch area")
	var header:Rect2=card.controls.close.get_global_rect()
	var portraits:Array=card.find_children("*","TextureRect",true,false)
	check(not portraits.is_empty() and portraits[0].texture!=null and portraits[0].size.x>=48 and portraits[0].size.y>=48,"patient identity uses an existing rendered actor portrait at readable48-unit size")
	var portrait_rect:Rect2=portraits[0].get_global_rect() if not portraits.is_empty() else Rect2()
	var scrolls:Array=card.find_children("*","ScrollContainer",true,false)
	check(not scrolls.is_empty(),"only detail body owns local overflow")
	if not scrolls.is_empty():
		scrolls[0].scroll_vertical=999
		await _frames()
		check(card.controls.close.get_global_rect().is_equal_approx(header) and card.controls.all_patients.get_global_rect().end.y<=314,"body scrolling preserves identity close and complete-list footer inside short content")
		check(not portraits.is_empty() and portraits[0].get_global_rect().is_equal_approx(portrait_rect),"scrolling clinical terms cannot scroll the patient's identity portrait out of the card")
	var prepare:Button=card.controls.get("prepare_treatment",card.controls.get("prepare"))
	check(prepare!=null and prepare.visible and not prepare.disabled,"missing treatment exposes one real preparation action")
	if prepare!=null:
		prepare.pressed.emit()
		check(not preparations.is_empty() and preparations[-1].get("action","")=="build" and preparations[-1].get("facility_kind","")=="U04-E2","preparation signal identifies missing physical treatment equipment instead of a free substitute")
	check(session.sim.snapshot()==before,"terms and preparation navigation cannot spend build refer or cure")
	card.controls.decision_continue_exam.pressed.emit()
	var after:Dictionary=session.sim.snapshot()
	check(not received.is_empty() and received[-1].get("ok",false) and after.patients[data.id].clinical_decision.revision==1,"choosing examination submits the real patient's expected clinical revision")
	check(after.patients[data.id].clinical_decision.receipts.size()==1 and after.metrics.completed==0 and after.metrics.income==0,"accepted examination records one real authorization without instant cure or income")
	card.present(after)
	check(card.visible and card.patient_id==data.id and card.controls.decision_continue_exam.disabled,"nonpending card remains selected and reports actual ongoing service instead of reauthorizing")
	card.free()

func test_stale_rejection_preserves_patient(data:Dictionary)->void:
	var session:GameSession=restored(data.pending,"stale")
	if session==null:return
	var card:Control=card_for(session)
	card.show_patient(data.id)
	var view:Dictionary=CampaignClinicalDecisions.preview(session.sim.snapshot(),catalog,data.id)
	issue(session,"clinical_decision",{"patient_id":data.id,"action":"continue_exam","expected_revision":int(view.revision)})
	var before:Dictionary=session.sim.snapshot()
	var count:int=received.size()
	card.controls.decision_continue_exam.pressed.emit()
	check(received.size()==count+1 and not received[-1].get("ok",true) and received[-1].get("code","") in ["stale_clinical_decision","clinical_decision_not_ready"],"a stale rendered option is rejected through the real command boundary")
	check(card.visible and card.patient_id==data.id and session.sim.snapshot()==before,"rejection keeps the selected patient and preserves model authority")
	check(text_of(card).contains("更新") or text_of(card).contains("阶段"),"rejected stale decision explains why the shown option no longer applies")
	card.free()

func test_preparation_advances_and_old_hospital_callback(data:Dictionary)->void:
	var session:GameSession=restored(data.pending,"preparation-and-context")
	if session==null:return
	var card:Control=card_for(session)
	card.show_patient(data.id)
	var definition:Dictionary=catalog.campaign.facilities["U04-E2"]
	var built:Dictionary=issue(session,"build_department",{"unit_id":definition.unit_id,"origin_cell":129,"layout":FacilityLayout.default_layout(definition.unit_id,"U04-E2",0)})
	if not built.get("ok",false):card.free();return
	card.present(session.sim.snapshot())
	var focus:Variant=card.get("preparation_focus")
	check(focus is Dictionary and focus.get("action","")=="staff" and focus.get("facility_kind","")=="U04-E2" and focus.get("role","")=="doctor","building genuine therapy changes preparation to its actual missing clinical role instead of another build")
	card.controls.prepare_treatment.pressed.emit()
	check(not preparations.is_empty() and preparations[-1].get("action","")=="staff","preparation emits the same actual staff target exposed to UI observation")
	var button:Button=card.controls.decision_continue_exam
	var connections:Array=button.pressed.get_connections()
	check(not connections.is_empty(),"clinical option has a real captured UI callback")
	if not connections.is_empty():
		var old_callback:Callable=connections[0].callable
		var next:GameSession=restored(data.pending,"replacement-hospital")
		if next==null:return
		session.sim=next.sim
		var before:Dictionary=session.sim.snapshot()
		old_callback.call()
		check(session.sim.snapshot()==before,"old patient001 callback cannot authorize the same number in a different real Simulation")
		check(not card.visible and card.patient_id=="","hospital replacement revokes the old card selection")
	card.free()

func test_closed_existing_and_synthetic_broken_therapy(data:Dictionary)->void:
	# Closed fixture: genuine authored pending patient and public build/close commands.
	var session:GameSession=restored(data.pending,"closed-therapy-route")
	if session==null:return
	var definition:Dictionary=catalog.campaign.facilities["U04-E2"]
	var built:Dictionary=issue(session,"build_department",{"unit_id":definition.unit_id,"origin_cell":129,"layout":FacilityLayout.default_layout(definition.unit_id,"U04-E2",0)})
	if not built.get("ok",false):return
	var facility_id:String=str(built.data.facility_ids[0])
	var closing:Dictionary=issue(session,"close_facility",{"facility_id":facility_id})
	if not closing.get("ok",false):return
	var before:Dictionary=session.sim.snapshot()
	check(before.facilities[facility_id].status=="closed" and int(before.facilities[facility_id].condition)>0,"closed-route fixture is a real healthy facility closed through its public command")
	var card:Control=card_for(session)
	card.show_patient(data.id)
	var focus:Dictionary=card.preparation_focus
	check(focus.get("action","")=="goals" and focus.get("section","")=="rooms" and focus.get("facility_id","")==facility_id and focus.get("control","")=="close_"+facility_id,"a genuinely closed existing therapy station prepares its actual reopen control instead of a catalog or duplicate build")
	var count:int=preparations.size()
	card.controls.prepare_treatment.pressed.emit()
	check(preparations.size()==count+1 and preparations[-1].get("section","")=="rooms" and preparations[-1].get("control","")=="close_"+facility_id,"closed equipment preparation signal reaches the exact existing-room control")
	check(session.sim.snapshot()==before,"closed equipment preparation cannot reopen build charge or authorize clinical care")
	# Synthetic UI projection only: do not load this as a valid save or claim actual wear.
	# The model stays at the genuine closed snapshot. Only a detached display copy is damaged.
	var damaged:Dictionary=before.duplicate(true)
	damaged.facilities[facility_id].status="open"
	damaged.facilities[facility_id].condition=0
	card.present(damaged)
	focus=card.preparation_focus
	check(focus.get("action","")=="operation" and focus.get("facility_kind","")=="O11" and focus.get("scroll_control","")=="run_operation" and focus.get("control","")!="run_operation","synthetic damaged display projection navigates to genuine O11 repair preparation without auto-running or instant repair")
	count=preparations.size()
	card.controls.prepare_treatment.pressed.emit()
	check(preparations.size()==count+1 and preparations[-1].get("action","")=="operation" and preparations[-1].get("facility_kind","")=="O11","damaged equipment preparation emits a real maintenance-operation navigation target")
	check(session.sim.snapshot()==before and int(session.sim.snapshot().facilities[facility_id].condition)>0,"synthetic wear and preparation remain UI-only and cannot mutate actual condition inventory money or work orders")
	card.free()

# New boundaries below are detached UI projections, not valid saved hospitals.
# Facility geometry, roles and the queued O15 order first come from real commands;
# only explicit stock/order-state boundary copies are passed to Card.present.
func _delivery_input_fixture(data:Dictionary,suffix:String)->Dictionary:
	var session:GameSession=restored(data.pending,suffix)
	if session==null:return {}
	if build(session,"U04-E2",129)=="":return {}
	var order:Dictionary=issue(session,"run_operation",{"facility_kind":"O15"})
	if not order.get("ok",false):return {}
	return {"session":session,"order_id":str(order.data.work_order_id)}

func _delivery_projection(session:GameSession,order_id:String,supplies:int)->Dictionary:
	var copy:Dictionary=session.sim.snapshot()
	copy.resources.delivered=0
	copy.resources.supplies=supplies
	# UI-only walking/not-started shortage boundary; never loaded into Simulation.
	copy.work_orders[order_id].status="walking"
	copy.work_orders[order_id].started_tick=-1
	copy.work_orders[order_id].reason="insufficient_resources" if supplies<6 else ""
	copy.paused=false
	return copy

func test_blocked_delivery_prepares_upstream_without_hiding_referral(data:Dictionary)->void:
	var fixture:Dictionary=_delivery_input_fixture(data,"blocked-delivery-absent-source")
	if fixture.is_empty():return
	var session:GameSession=fixture.session
	var before:Dictionary=session.sim.snapshot()
	var card:Control=card_for(session)
	card.show_patient(data.id)
	card.present(_delivery_projection(session,fixture.order_id,4))
	var focus:Dictionary=card.preparation_focus
	check(focus.get("action","")=="build" and focus.get("facility_kind","")=="O14","unstarted O15 with only4 of6 supplies prepares the actual absent O14 input source rather than waiting for delivered output")
	check(not card.controls.decision_refer.disabled and card.controls.decision_refer.is_visible_in_tree(),"a feasible paid referral remains visible and actionable while delivery input preparation is needed")
	var count:int=preparations.size()
	card.controls.prepare_treatment.pressed.emit()
	check(preparations.size()==count+1 and preparations[-1].get("facility_kind","")=="O14","blocked delivery preparation signal names upstream supply production rather than another O15")
	check(session.sim.snapshot()==before,"stock shortage projection and upstream navigation do not create stock orders costs or clinical receipts")
	card.controls.decision_refer.pressed.emit()
	var after:Dictionary=session.sim.snapshot()
	check(after.patients[data.id].clinical_decision.receipts.size()==1 and after.patients[data.id].clinical_decision.receipts[-1].action=="refer" and int(after.metrics.completed)==0,"preparation guidance cannot swallow the real feasible referral decision or count it as an immediate cure")
	card.free()

func test_blocked_delivery_resolves_real_input_source_staff_and_reservations(data:Dictionary)->void:
	var fixture:Dictionary=_delivery_input_fixture(data,"blocked-delivery-source-staff")
	if fixture.is_empty():return
	var session:GameSession=fixture.session
	var definition:Dictionary=catalog.campaign.facilities["O14"]
	var layout:Dictionary=FacilityLayout.default_layout(definition.unit_id,"O14",0)
	var source_id:String=""
	for cell:int in range(GridService.WIDTH*GridService.HEIGHT):
		var payload:Dictionary={"unit_id":definition.unit_id,"origin_cell":cell,"layout":layout}
		if not FacilityLayout.preview(session.sim.snapshot(),payload).get("ok",false):continue
		var built:Dictionary=issue(session,"build_department",payload)
		if built.get("ok",false):source_id=str(built.data.facility_ids[0])
		break
	check(source_id!="","real geometry creates an unstaffed O14 input source for routing boundary")
	if source_id=="":return
	var card:Control=card_for(session)
	card.show_patient(data.id)
	card.present(_delivery_projection(session,fixture.order_id,4))
	var focus:Dictionary=card.preparation_focus
	check(focus.get("action","")=="staff" and focus.get("facility_kind","")=="O14" and focus.get("facility_id","")==source_id and focus.get("role","")=="logistics","existing unstaffed O14 prepares its actual logistics role instead of duplicate building or a disabled source-run control")
	var hire:Dictionary=issue(session,"hire",{"role":"logistics"})
	if not hire.get("ok",false):card.free();return
	if not issue(session,"assign",{"staff_id":hire.data.staff_id,"facility_id":source_id}).get("ok",false):card.free();return
	var before:Dictionary=session.sim.snapshot()
	card.present(_delivery_projection(session,fixture.order_id,4))
	focus=card.preparation_focus
	check(focus.get("action","")=="goals" and focus.get("section","")=="resource" and focus.get("resource","")=="supplies" and focus.get("facility_kind","")=="O14" and focus.get("control","")=="resource_run_O14","staffed affordable O14 routes to its real supplies production control without auto-producing")
	# UI-only reservation boundary: nominal6 supplies,2 held for existing care =>4 usable.
	var reserved:Dictionary=_delivery_projection(session,fixture.order_id,6)
	reserved.patients[data.id].reservation_resource="supplies"
	reserved.patients[data.id].reservation_quantity=2
	reserved.work_orders[fixture.order_id].reason="insufficient_resources"
	card.present(reserved)
	focus=card.preparation_focus
	check(focus.get("resource","")=="supplies" and focus.get("facility_kind","")=="O14","patient reservations prevent nominal6 supplies from being misreported as6 available delivery inputs")
	check(session.sim.snapshot()==before,"source staffing navigation and detached reservation projections cannot mutate the real hospital")
	card.free()

func test_real_eligible_or_paid_delivery_waits_without_duplicate_order(data:Dictionary)->void:
	var fixture:Dictionary=_delivery_input_fixture(data,"eligible-delivery-progress")
	if fixture.is_empty():return
	var session:GameSession=fixture.session
	var before:Dictionary=session.sim.snapshot()
	var card:Control=card_for(session)
	card.show_patient(data.id)
	var moving:Dictionary=_delivery_projection(session,fixture.order_id,6)
	card.present(moving)
	var focus:Dictionary=card.preparation_focus
	check(focus.get("action","")=="goals" and focus.get("section","")=="resource" and focus.get("resource","")=="delivered" and focus.get("control","")!="resource_run_O15","a genuinely supplied not-yet-started delivery only exposes progress and never queues another O15")
	moving.paused=true
	card.present(moving)
	check(card.preparation_focus.get("action","")=="resume","paused delivery with sufficient unreserved inputs may resume rather than manufacture upstream work")
	# Paid-working UI boundary: inputs were already consumed when actual service started.
	var paid:Dictionary=_delivery_projection(session,fixture.order_id,0)
	paid.work_orders[fixture.order_id].status="working"
	paid.work_orders[fixture.order_id].started_tick=int(paid.tick)
	paid.work_orders[fixture.order_id].reason=""
	card.present(paid)
	focus=card.preparation_focus
	check(focus.get("action","")=="goals" and focus.get("resource","")=="delivered" and focus.get("facility_kind","")!="O14","a paid working delivery does not require its already-consumed6 inputs a second time")
	check(session.sim.snapshot()==before,"eligible and paid delivery projections preserve all actual finance stock and order evidence")
	card.free()

# Disease disclosure boundaries: real completed examination and real treatment.
# The original pre-exam hidden-name test above is retained unchanged.
func _check_diagnosis_header(card:Control,snapshot:Dictionary,id:String,label:String)->void:
	var patient:Dictionary=snapshot.patients[id]
	var disease_name:String=str(catalog.campaign.diseases[patient.disease_id].name)
	var header:Label=card.controls.phase
	check(header.text.contains(disease_name) and (header.text.contains("疑似") or header.text.contains("初诊")) and not header.text.contains("已确诊"),label+" fixed header names the actual catalog disease with a preliminary qualifier rather than claiming confirmation")
	check(not header.text.contains(str(catalog.campaign.cases[patient.case_id].title)),label+" uses actual disease identity rather than the case-task title")
	var width:float=header.get_theme_font("font").get_string_size(header.text,HORIZONTAL_ALIGNMENT_LEFT,-1,header.get_theme_font_size("font_size")).x
	check(width<=header.size.x+1.0,label+" actual disease and qualifier fit the visible short-card header without relying on clipped tooltip text",str({"text_width":width,"available":header.size.x}))

func test_pending_patient_discloses_actual_preliminary_diagnosis(data:Dictionary)->void:
	var session:GameSession=restored(data.pending,"disease-label-pending")
	if session==null:return
	var before:Dictionary=session.sim.snapshot()
	check(CampaignClinicalDecisions.preview(before,catalog,data.id).pending,"diagnosis-label fixture uses a genuinely completed first examination")
	var card:Control=card_for(session)
	card.configure(Rect2(59,90,814,224))
	card.show_patient(data.id)
	await _frames()
	_check_diagnosis_header(card,before,data.id,"pending first examination")
	check(session.sim.snapshot()==before,"disclosing the real preliminary diagnosis cannot create clinical evidence or change treatment")
	card.free()

func test_actual_treatment_keeps_preliminary_disease_visible(data:Dictionary)->void:
	var session:GameSession=restored(data.pending,"disease-label-active-treatment")
	if session==null:return
	if build(session,"U04-E2",129)=="":return
	var view:Dictionary=CampaignClinicalDecisions.preview(session.sim.snapshot(),catalog,data.id)
	if not issue(session,"clinical_decision",{"patient_id":data.id,"action":"cautious_treat","expected_revision":int(view.revision)}).get("ok",false):return
	issue(session,"set_paused",{"paused":false})
	var active:bool=false
	for _n:int in range(1600):
		var current:Dictionary=session.sim.snapshot()
		var patient:Dictionary=current.patients[data.id]
		var index:int=int(patient.step_index)
		if patient.phase=="care_service" and patient.clinical_decision.state=="authorized" and index<patient.steps.size() and patient.steps[index].facility_kind=="U04-E2":active=true;break
		session.sim.advance_ticks(1)
	if not active:
		check(false,"real authorized patient reaches actual distinct U04-E2 treatment before diagnosis-header inspection")
		return
	var before:Dictionary=session.sim.snapshot()
	check(SnapshotValidator.validate(before,catalog)=="","active-treatment diagnosis-label fixture is a real save-valid service state")
	var card:Control=card_for(session)
	card.configure(Rect2(59,90,814,224))
	card.show_patient(data.id)
	await _frames()
	_check_diagnosis_header(card,before,data.id,"actual authorized treatment")
	check(session.sim.snapshot()==before and int(before.metrics.completed)==0,"reading disease identity during real service cannot manufacture a completed cure")
	card.free()

func _run()->void:
	root.size=Vector2i(932,430)
	var loaded:Dictionary=ContentCatalog.load_checked("res://content")
	check(loaded.get("ok",false),"real content loads",str(loaded.get("error","")))
	var exists:bool=ResourceLoader.exists("res://ui/campaign_patient_card.gd")
	check(exists,"scene patient selection has a compact real patient-card component")
	if loaded.get("ok",false) and exists:
		catalog=loaded.catalog;card_script=load("res://ui/campaign_patient_card.gd")
		var data:Dictionary=fixture()
		if not data.is_empty():
			await test_identity_bounds_and_readonly(data)
			await test_real_terms_prepare_and_scroll(data)
			test_stale_rejection_preserves_patient(data)
			test_preparation_advances_and_old_hospital_callback(data)
			test_closed_existing_and_synthetic_broken_therapy(data)
			test_blocked_delivery_prepares_upstream_without_hiding_referral(data)
			test_blocked_delivery_resolves_real_input_source_staff_and_reservations(data)
			test_real_eligible_or_paid_delivery_waits_without_duplicate_order(data)
			await test_pending_patient_discloses_actual_preliminary_diagnosis(data)
			await test_actual_treatment_keeps_preliminary_disease_visible(data)
	if test_paths.write_report({"ok":failed==0,"passed":passed,"failed":failed,"checks":checks,"scope":"focused compact real patient card; no native visual acceptance claim"},"\t")!=OK:
		printerr("FORMAL TEST PATH ERROR: report_write_failed");quit(2);return

	print("PATIENT CARD RESULT passed="+str(passed)+" failed="+str(failed))
	quit(0 if failed==0 else 1)
