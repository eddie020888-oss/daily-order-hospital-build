extends SceneTree
var output:=""
var checks:Array=[]
var passed:=0
var failed:=0
func _initialize()->void:
    for arg:String in OS.get_cmdline_user_args():
        if arg.begins_with("--output="):output=arg.trim_prefix("--output=").replace("\\","/")
    _run.call_deferred()
func check(ok:bool,label:String)->void:
    checks.append({"ok":ok,"check":label})
    if ok:passed+=1
    else:failed+=1
    print(("UI BUILD PASS: " if ok else "UI BUILD FAIL: ")+label)
func finish()->void:
    var file:=FileAccess.open(output,FileAccess.WRITE)
    if file==null:quit(2);return
    file.store_string(JSON.stringify({"passed":passed,"failed":failed,"checks":checks,"scope":"Actual campaign controls, paid build/hire/assign/admission and original first case to actual departure. No fabricated phases or money."},"  "))
    print("UI BUILD RESULT: passed=%d failed=%d"%[passed,failed])
    quit(1 if failed>0 else 0)
func _run()->void:
    if not output.begins_with("E:/CODEX/2026-10-22/医院全设施病例任务贯通/") or FileAccess.file_exists(output) or DirAccess.dir_exists_absolute(output.get_basename()+"-saves"):quit(2);return
    var loaded:Dictionary=ContentCatalog.load_checked("res://content")
    check(loaded.get("ok",false),"actual campaign catalog loads")
    if not loaded.get("ok",false):finish();return
    var session:=GameSession.new(loaded.catalog,output.get_basename()+"-saves")
    check(session.start_level("career_01").get("ok",false),"normal public session opens first career")
    if not session.is_campaign():finish();return
    var panel:=CampaignHospitalPanel.new()
    root.add_child(panel);panel.initialize(session)
    panel.set_facility_filter("U01","")
    panel.controls["facility_card_U01-E1"].pressed.emit()
    panel.controls.new_department.pressed.emit()
    check(panel.section=="layout" and panel.controls.has("layout_q_0"),"real facility card enters editable four-angle room layout")
    panel.controls.layout_q_0.value=1
    check(int(panel._draft.facilities[0].rotation)==1,"angle control changes actual local facility draft")
    panel.controls.layout_q_0.value=0
    panel.controls.doors_side.select(0)
    panel.controls.doors_offset.value=panel._draft.width
    panel.controls.add_doors.pressed.emit()
    check(panel._draft.doors.size()==2,"user adds second independent entrance")
    panel.controls.windows_side.select(0)
    panel.controls.windows_offset.value=1
    panel.controls.add_windows.pressed.emit()
    check(panel._draft.windows.size()==1,"user adds an independently selected window")
    var before:Dictionary=session.sim.snapshot()
    check(not panel.controls.confirm_department.disabled,"real geometry preview accepts this editable paid layout")
    if panel.controls.confirm_department.disabled:panel.free();finish();return
    panel.controls.confirm_department.pressed.emit()
    for _i in range(2):await process_frame
    var built:Dictionary=session.sim.snapshot()
    check(built.rooms.size()==1 and built.facilities.size()==1 and built.cash<before.cash,"confirmation creates real room and device and charges actual money")
    if built.rooms.is_empty():panel.free();finish();return
    var room:Dictionary=built.rooms.values()[0]
    check(room.layout.doors.size()==2 and room.layout.windows.size()==1,"chosen two doors and window persist in authoritative room")
    panel.show_section("staff")
    panel.controls.hire.pressed.emit()
    for _i in range(2):await process_frame
    check(session.sim.snapshot().staff.size()==1 and panel.controls.has("assign"),"paid recruit reveals matching actual device assignment")
    if not panel.controls.has("assign"):panel.free();finish();return
    panel.controls.assign.pressed.emit()
    for _i in range(2):await process_frame
    var employee:Dictionary=session.sim.snapshot().staff.values()[0]
    check(employee.facility_id!="","assign control binds employee to actual device")
    await build_extra(panel,"O01",7,1)
    await build_extra(panel,"O15",14,2)
    await hire_assign(panel,session,"receptionist","O01")
    await hire_assign(panel,session,"logistics","O15")
    panel.show_section("operations")
    choose_option(panel.controls.operation_kind,"O15")
    check(not panel.controls.run_operation.disabled,"staffed delivery UI has real supplies input and can queue production")
    if panel.controls.run_operation.disabled:panel.free();finish();return
    panel.controls.run_operation.pressed.emit()
    for _i in range(2):await process_frame
    session.issue("set_paused",{"paused":false})
    for _i in range(2400):
        session.sim.advance_ticks(1)
        if int(session.sim.snapshot().resources.get("delivered",0))>=6:break
    session.issue("set_paused",{"paused":true})
    check(int(session.sim.snapshot().resources.get("delivered",0))>=6,"normal logistics worker completes paid actual delivery before admission")
    panel.show_section("cases")
    check(not panel.controls.accept_case.disabled,"readiness becomes actionable after real preparation")
    panel.controls.accept_case.pressed.emit()
    for _i in range(2):await process_frame
    check(session.sim.snapshot().patients.size()==1,"accept control admits original first case without injected patient state")
    session.issue("set_paused",{"paused":false})
    for _i in range(2400):
        session.sim.advance_ticks(1)
        if "U01-C1" in session.sim.snapshot().campaign.completed_cases:break
    var complete:Dictionary=session.sim.snapshot()
    check("U01-C1" in complete.campaign.completed_cases and complete.metrics.completed==1,"real reception then clinical movement and full service timers complete first authored case")
    var patient:Dictionary=complete.patients.values()[0]
    check(patient.phase=="left" and complete.metrics.income==loaded.catalog.campaign.cases["U01-C1"].income,"income is collected only after actual complete departure")
    check(CampaignValidator.validate(complete,loaded.catalog)=="","UI-created clinical state validates with real histories and geometry")
    check(session.save_now().get("ok",false),"UI-built two-door room and completed case really save")
    var saved:Dictionary=SaveStore.load(session.save_root,loaded.catalog)
    check(saved.get("ok",false) and saved.state.to_data()==complete,"actual disk round trip preserves entire clinical and layout state")
    panel.free();finish()

func choose_option(option:OptionButton,id:String)->bool:
    for index:int in range(option.item_count):
        if str(option.get_item_metadata(index))==id:
            option.select(index)
            option.item_selected.emit(index)
            return true
    check(false,"actual option exists: "+id)
    return false

func build_extra(panel:CampaignHospitalPanel,kind:String,x:int,y:int)->void:
    panel.set_facility_filter("operations",kind)
    var key:String="facility_card_"+kind
    check(panel.controls.has(key),"real operations search reaches "+kind)
    if not panel.controls.has(key):return
    panel.controls[key].pressed.emit()
    panel.controls.new_department.pressed.emit()
    panel.controls.room_origin_x.value=x
    panel.controls.room_origin_y.value=y
    check(not panel.controls.confirm_department.disabled,"additional real department preview is legal for "+kind)
    if panel.controls.confirm_department.disabled:return
    panel.controls.confirm_department.pressed.emit()
    for _i in range(2):await process_frame

func hire_assign(panel:CampaignHospitalPanel,session:GameSession,role:String,kind:String)->void:
    panel.show_section("staff")
    choose_option(panel.controls.hire_role,role)
    panel.controls.hire.pressed.emit()
    for _i in range(2):await process_frame
    var snapshot:Dictionary=session.sim.snapshot()
    var ids:Array=snapshot.staff.keys()
    ids.sort()
    var sid:String=ids[-1]
    choose_option(panel.controls.assign_staff,sid)
    for _i in range(2):await process_frame
    var fid:=""
    for facility:Dictionary in snapshot.facilities.values():
        if facility.kind==kind:fid=facility.id;break
    check(panel.controls.has("assign_facility") and fid!="","matching public workplace exists for "+role)
    if not panel.controls.has("assign_facility") or fid=="":return
    choose_option(panel.controls.assign_facility,fid)
    panel.controls.assign.pressed.emit()
    for _i in range(2):await process_frame
    check(session.sim.snapshot().staff[sid].facility_id==fid,"real recruit and assign controls bind "+role+" to "+kind)
