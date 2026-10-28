extends SceneTree
var output:=""
var checks:Array=[]
var passed:=0
var failed:=0
var scene_editor:CampaignBuildEditor
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
    if not output.begins_with("E:/CODEX/2026-10-28/医院经营闭环优化/") or FileAccess.file_exists(output) or DirAccess.dir_exists_absolute(output.get_basename()+"-saves"):quit(2);return
    var loaded:Dictionary=ContentCatalog.load_checked("res://content")
    check(loaded.get("ok",false),"actual campaign catalog loads")
    if not loaded.get("ok",false):finish();return
    var session:=GameSession.new(loaded.catalog,output.get_basename()+"-saves")
    check(session.start_level("career_01").get("ok",false),"normal public session opens first career")
    if not session.is_campaign():finish();return
    var panel:=CampaignHospitalPanel.new()
    root.add_child(panel);panel.initialize(session)
    scene_editor=CampaignBuildEditor.new();root.add_child(scene_editor)
    scene_editor.initialize(session,null,Callable());scene_editor.configure(Rect2(8,8,1264,704))
    panel.scene_build_requested.connect(func(mode:String,kind:String,room_id:String)->void:
        panel.hide()
        session.issue("set_paused",{"paused":true})
        if mode=="build":scene_editor.begin_build(kind)
        elif mode=="install":scene_editor.begin_install(kind,room_id)
        else:scene_editor.begin_edit(room_id))
    panel.set_facility_filter("U01","")
    panel.controls["facility_card_U01-E1"].pressed.emit()
    panel.controls.new_department.pressed.emit()
    check(scene_editor.active and scene_editor.controller.draft.step==0 and scene_editor.controller.draft.layout.facilities.is_empty(),"real facility card enters empty scene construction without coordinate forms")
    var first:Dictionary=FacilityLayout.default_layout("U01","U01-E1",0)
    var origin:int=49
    scene_editor.controller.choose_cell(origin)
    scene_editor.controller.choose_cell(origin+first.width-1+(first.height-1)*24)
    check(scene_editor.controller.advance(),"drawn real room proceeds to scene wall selection")
    scene_editor.controller.choose_wall("south",int(first.width)-1)
    scene_editor.controller.choose_wall("north",int(first.width)-1)
    scene_editor.controller.select_opening_tool("window");scene_editor.controller.choose_wall("north",0)
    scene_editor.controller.select_opening_tool("door")
    check(scene_editor.controller.draft.layout.doors.size()==2 and scene_editor.controller.draft.layout.windows.size()==1,"scene walls create two independent entrances and one chosen window")
    check(scene_editor.controller.advance(),"chosen openings advance to required equipment")
    scene_editor.controller.choose_cell(origin+int(first.facilities[0].y)*24+int(first.facilities[0].x))
    scene_editor.controller.rotate()
    check(int(scene_editor.controller.draft.layout.facilities[0].rotation)==1,"scene rotate changes actual local machine quarter turn")
    for _i in range(3):scene_editor.controller.rotate()
    check(scene_editor.controller.advance(),"legal real device advances to optional support")
    var before:Dictionary=session.sim.snapshot()
    check(scene_editor.controller.view().can_confirm,"real geometry and finance preview permit the unpaid scene draft")
    if not scene_editor.controller.view().can_confirm:scene_editor.free();panel.free();finish();return
    var purchase:Dictionary=scene_editor.controller.confirm()
    for _i in range(2):await process_frame
    var built:Dictionary=session.sim.snapshot()
    check(purchase.get("ok",false) and built.rooms.size()==1 and built.facilities.size()==1 and built.cash==int(before.cash)-int(purchase.get("data",{}).get("cost",0)),"scene confirmation creates real room/device and charges exactly the actual command cost")
    if built.rooms.is_empty():scene_editor.free();panel.free();finish();return
    var room:Dictionary=built.rooms.values()[0]
    var first_id:String=str(room.layout.facilities[0].id)
    check(room.layout.doors.size()==2 and room.layout.windows.size()==1,"chosen two doors and window persist in authoritative room")
    panel.edit_room(str(room.id))
    check(scene_editor.controller.adjust_bounds(Vector2i(3,0)),"existing scene room expands while anchored at its actual origin")
    check(scene_editor.controller.advance() and scene_editor.controller.advance() and scene_editor.controller.advance(),"expansion preserves current real openings and machine")
    var expansion:Dictionary=scene_editor.controller.confirm()
    check(expansion.get("ok",false) and int(expansion.get("data",{}).get("cost",-1))==int(room.height)*24,"area expansion charges only its true added floor cells")
    panel.show_section("facility")
    panel.controls.place_facility.pressed.emit()
    scene_editor.controller.choose_cell(origin+3)
    check(scene_editor.controller.advance(),"a second actual device has separate valid scene work cells")
    var second:Dictionary=scene_editor.controller.confirm()
    built=session.sim.snapshot();room=built.rooms[room.id]
    check(second.get("ok",false) and room.layout.facilities.size()==2 and room.layout.facilities[0].id==first_id and room.layout.facilities[1].id!=first_id,"scene installation adds an independent paid instance without replacing its first device")
    check(int(second.get("data",{}).get("cost",-1))==int(loaded.catalog.campaign.facilities["U01-E1"].cost),"second device uses its real purchase price")
    panel.show_section("staff")
    panel.controls.hire.pressed.emit()
    for _i in range(2):await process_frame
    check(session.sim.snapshot().staff.size()==1 and panel.controls.has("assign"),"paid recruit reveals matching actual device assignment")
    if not panel.controls.has("assign"):panel.free();finish();return
    panel.controls.assign.pressed.emit()
    for _i in range(2):await process_frame
    var employee:Dictionary=session.sim.snapshot().staff.values()[0]
    check(employee.facility_id!="","assign control binds employee to actual device")
    var first_employee:String=str(employee.id)
    panel.show_section("staff");panel.controls.hire.pressed.emit()
    for _i in range(2):await process_frame
    var doctors:Array=session.sim.snapshot().staff.keys();doctors.sort()
    var second_employee:String=str(doctors[-1])
    choose_option(panel.controls.assign_staff,second_employee)
    for _i in range(2):await process_frame
    choose_option(panel.controls.assign_facility,str(room.layout.facilities[1].id))
    panel.controls.assign.pressed.emit()
    for _i in range(2):await process_frame
    check(session.sim.snapshot().staff[first_employee].facility_id==first_id and session.sim.snapshot().staff[second_employee].facility_id==room.layout.facilities[1].id,"two paid doctors bind to distinct independent machine instances")
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
    scene_editor.free();panel.free();finish()

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
    panel.controls[key].pressed.emit();panel.controls.new_department.pressed.emit()
    var content:Dictionary=panel.session.catalog.campaign
    var layout:Dictionary=FacilityLayout.default_layout(str(content.facilities[kind].unit_id),kind,0)
    var origin:int=y*24+x
    scene_editor.controller.choose_cell(origin)
    scene_editor.controller.choose_cell(origin+int(layout.width)-1+(int(layout.height)-1)*24)
    check(scene_editor.controller.advance(),"additional real room bounds fit for "+kind)
    scene_editor.controller.choose_wall(str(layout.doors[0].side),int(layout.doors[0].offset))
    check(scene_editor.controller.advance(),"additional real door reaches the hospital for "+kind)
    scene_editor.controller.choose_cell(origin+int(layout.facilities[0].y)*24+int(layout.facilities[0].x))
    check(scene_editor.controller.advance(),"additional real device and work cells fit for "+kind)
    var result:Dictionary=scene_editor.controller.confirm()
    check(result.get("ok",false),"scene final purchase builds "+kind)
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
