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
	if test_paths.write_report({"ok":failed==0,"passed":passed,"failed":failed,"checks":checks,"scope":"focused compact real patient card; no native visual acceptance claim"},"\t")!=OK:
		printerr("FORMAL TEST PATH ERROR: report_write_failed");quit(2);return

	print("PATIENT CARD RESULT passed="+str(passed)+" failed="+str(failed))
	quit(0 if failed==0 else 1)
