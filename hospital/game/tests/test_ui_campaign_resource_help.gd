extends SceneTree
var output:=""
var passed:=0
var failed:=0
var checks:Array=[]
func _initialize()->void:
    for arg:String in OS.get_cmdline_user_args():
        if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
    _run.call_deferred()
func check(ok:bool,label:String)->void:
    checks.append({"ok":ok,"check":label})
    if ok:passed+=1
    else:failed+=1
    print(("RESOURCE UI PASS: " if ok else "RESOURCE UI FAIL: ")+label)
func finish()->void:
    var file:=FileAccess.open(output,FileAccess.WRITE)
    if file==null:quit(2);return
    file.store_string(JSON.stringify({"passed":passed,"failed":failed,"checks":checks,"scope":"Real campaign definitions and read-only user-facing preparation plans; no fabricated stock or completion."},"  "))
    print("RESOURCE UI RESULT: passed=%d failed=%d"%[passed,failed])
    quit(1 if failed>0 else 0)
func _run()->void:
    if not output.begins_with("E:/CODEX/2026-10-22/医院全设施病例任务贯通/") or FileAccess.file_exists(output):quit(2);return
    var checked:Dictionary=ContentCatalog.load_checked("res://content")
    check(checked.get("ok",false),"actual source content loads")
    if not checked.get("ok",false):finish();return
    var session:=GameSession.new(checked.catalog,output.get_basename()+"-saves")
    var panel:=CampaignHospitalPanel.new()
    root.add_child(panel);panel.initialize(session)
    check(panel.has_method("resource_plan"),"resource help exposes actual producer chain and readable quantities")
    if not panel.has_method("resource_plan"):panel.free();finish();return
    var before:Dictionary=session.sim.snapshot()
    var plan:Array=panel.call("resource_plan","sterile")
    var kinds:Array=[]
    for row:Dictionary in plan:kinds.append(row.facility_kind)
    check(kinds==["O25","U32-E1","U32-E3","U32-E2"],"sterile preparation is actual water to wash to package to sterilize source order")
    check(panel.call("resource_label","cleaned_instruments")=="已清洗器械" and panel.call("resource_label","packed")=="已包装器械","intermediate resources have readable Chinese labels")
    check(CampaignHospitalPanel.reason_text("missing_resource:packed",checked.catalog.campaign).contains("已包装器械"),"clinical readiness explains missing intermediate stock in Chinese")
    var supply:Array=panel.call("resource_plan","supplies")
    check(supply.size()==1 and supply[0].facility_kind=="O14" and int(supply[0].output_quantity)==30,"medical supplies lead to actual stock producer and real yield")
    var slides:Array=panel.call("resource_plan","slides")
    var order:Array=[]
    for row:Dictionary in slides:order.append(row.facility_kind)
    check(order==["O29","U27-E1","U27-E2"],"pathology inputs resolve to actual distinct sampling processing and cutting producers")
    check(session.sim.snapshot()==before,"viewing producer plan never manufactures inventory or completion")
    panel.free();finish()
