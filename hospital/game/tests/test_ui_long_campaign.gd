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
    print(("LONG UI PASS: " if ok else "LONG UI FAIL: ")+label)
func text_of(node:Node)->String:
    var result:String=node.text+"\n" if node is Label or node is Button else ""
    for child:Node in node.get_children():result+=text_of(child)
    return result
func choose(option:OptionButton,id:String)->bool:
    for index:int in range(option.item_count):
        if str(option.get_item_metadata(index))==id:
            option.select(index);option.item_selected.emit(index);return true
    return false
func finish()->void:
    var file:=FileAccess.open(output,FileAccess.WRITE)
    if file==null:quit(2);return
    file.store_string(JSON.stringify({"passed":passed,"failed":failed,"checks":checks,"scope":"Real catalog/session/normal controls/public commands and disk roundtrip. No fabricated progress, receipts, patients, money, resources or phase/win. UI entry coverage does not prove complete long-term playthrough."},"  "))
    file.close()
    print("LONG UI RESULT: passed=%d failed=%d"%[passed,failed])
    quit(1 if failed>0 else 0)
func _run()->void:
    if not output.begins_with("E:/CODEX/2026-10-22/医院长线经营扩展/") or FileAccess.file_exists(output) or DirAccess.dir_exists_absolute(output.get_basename()+"-saves"):
        push_error("Require fresh task output");quit(2);return
    var loaded:Dictionary=ContentCatalog.load_checked("res://content")
    check(loaded.get("ok",false),"actual content catalog loads")
    if not loaded.get("ok",false):finish();return
    var session:=GameSession.new(loaded.catalog,output.get_basename()+"-saves")
    var old_levels:Array=session.campaign_levels()
    check(old_levels.size()==12 and old_levels[0].id=="career_01" and old_levels[11].id=="career_12","legacy campaign_levels retains exactly ordered v1 twelve levels")
    check(session.has_method("long_campaign_levels"),"session exposes independent long-term level track")
    if not session.has_method("long_campaign_levels"):finish();return
    var levels:Array=session.call("long_campaign_levels")
    check(levels.size()==12,"all twelve authored long-term levels are listed separately")
    if levels.size()!=12:finish();return
    check(levels[0].id=="long_01" and levels[11].id=="long_12" and levels[0].get("ruleset","")=="full-hospital-v2","new list is ordered v2 and does not replace old track")
    var pages:=HospitalFlowPages.new()
    root.add_child(pages);pages.initialize(session);pages.show_levels()
    check(pages.controls.has("level_long_01") and pages.controls.has("level_long_02") and pages.controls.has("level_career_01") and pages.controls.has("level_level_01"),"normal level menu exposes long-term mode while retaining both legacy modes")
    if not pages.controls.has("level_long_01") or not pages.controls.has("level_long_02"):pages.free();finish();return
    check(not pages.controls.level_long_01.disabled and pages.controls.level_long_02.disabled,"first long-term clinic opens while next requires real v2 receipt")
    var before:Dictionary=session.sim.snapshot()
    var rejected:Dictionary=session.start_level("long_02")
    check(not rejected.get("ok",false) and session.sim.snapshot()==before,"locked long-term start preserves current clinic atomically")
    var started:Dictionary=session.start_level("long_01")
    check(started.get("ok",false) and session.sim.snapshot().get("schema_version",0)==3,"public start creates actual schema3 clinic")
    if not started.get("ok",false):pages.free();finish();return
    check(session.is_campaign(),"shared campaign workbench recognizes genuine schema3")
    check(not session.next_level_info().get("ok",false),"unfinished long-term clinic cannot unlock next level")
    var panel:=CampaignHospitalPanel.new()
    root.add_child(panel);panel.initialize(session);panel.show_section("cases")
    check(panel.controls.has("advance_stage") and panel.controls.has("set_intake"),"normal cases page exposes real stage submission and automatic intake control")
    check(text_of(panel).contains("开业") and text_of(panel).contains("治愈"),"cases page displays actual opening-stage clinical goals")
    check(session.sim.snapshot().patients.is_empty(),"read-only goal and readiness display creates no patients")
    check(panel.controls.has("advance_stage") and panel.controls.advance_stage.disabled,"initial clinic cannot advance without real operating goals")
    panel.set_facility_filter("U02","")
    panel.controls["facility_card_U02-E1"].pressed.emit()
    check(panel.controls.has("facility_goals") and not panel.controls.has("new_department"),"catalog remains browsable but future specialty has truthful stage lock")
    panel.show_section("operations")
    check(choose(panel.controls.operation_kind,"O11"),"normal operation selector reaches maintenance")
    check(panel.controls.has("set_operation_auto") and panel.controls.operation_auto_target.max_value==100 and text_of(panel).contains("设备状态阈值"),"maintenance automation shows actual condition threshold")
    if panel.controls.has("set_operation_auto"):
        panel.controls.set_operation_auto.pressed.emit()
        for _i:int in range(2):await process_frame
        check(session.sim.snapshot().campaign.get("automation",{}).get("O11",{}).get("enabled",false),"maintenance policy control submits persistent real command")
    check(choose(panel.controls.operation_kind,"O12"),"normal operation selector reaches tool cleaning")
    check(panel.controls.has("set_operation_auto") and panel.controls.operation_auto_target.max_value==1000 and text_of(panel).contains("目标库存"),"output-producing tool cleaner uses stock target rather than hygiene threshold")
    panel.show_section("cases")
    if panel.controls.has("set_intake"):
        panel.controls.set_intake.pressed.emit()
        for _i:int in range(2):await process_frame
        check(session.sim.snapshot().campaign.get("intake_enabled",false),"intake control submits real persistent enabled state")
        panel.controls.set_intake.pressed.emit()
        for _i:int in range(2):await process_frame
        check(not session.sim.snapshot().campaign.get("intake_enabled",true),"same normal control actually disables intake")
    pages.show_guide()
    check(text_of(pages).contains("稳定") and text_of(pages).contains("扩建") and text_of(pages).contains("考核"),"normal guide explains all four real operating stages")
    check(session.save_now().get("ok",false),"new long-term clinic uses real atomic save")
    var saved:Dictionary=session.sim.snapshot()
    session.open_saved()
    check(not session.storage_blocked and session.sim.snapshot().campaign==saved.campaign and session.sim.snapshot().level_id=="long_01","strict disk reopen preserves schema3 stage and intake state")
    check(session.start_level("career_01").get("ok",false) and session.sim.snapshot().get("schema_version",0)==2,"normal legacy selection still creates v1 clinic without upgrading")
    panel.show_section("cases")
    check(not panel.controls.has("advance_stage") and not panel.controls.has("set_intake") and panel.controls.has("accept_case"),"legacy batch UI keeps original manual admission without long-term controls")
    panel.free();pages.free();finish()
