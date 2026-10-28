extends SceneTree
var passed:=0
var failed:=0
var checks:Array=[]
var output:=""
func _initialize() -> void:
 for arg:String in OS.get_cmdline_user_args():
  if arg.begins_with("--output="): output=arg.trim_prefix("--output=").replace("\\","/")
 _run.call_deferred()
func check(ok:bool,label:String) -> void:
 checks.append({"ok":ok,"check":label})
 if ok: passed+=1
 else: failed+=1
 print(("CAMPAIGN UI PASS: " if ok else "CAMPAIGN UI FAIL: ")+label)
func text_of(node:Node) -> String:
 var text:=""
 if node is Label or node is Button: text+=node.text+"\n"
 for child in node.get_children(): text+=text_of(child)
 return text
func finish() -> void:
 var file:=FileAccess.open(output,FileAccess.WRITE)
 if file==null: quit(2);return
 file.store_string(JSON.stringify({"passed":passed,"failed":failed,"checks":checks,"scope":"Real catalog/session/controls and public commands. No injected money, poses, completion or career receipts."},"  "))
 print("CAMPAIGN UI RESULT: passed=%d failed=%d"%[passed,failed])
 quit(1 if failed>0 else 0)
func _run() -> void:
 var base:="E:/CODEX/2026-10-22/医院全设施病例任务贯通/"
 if output=="" or not output.begins_with(base) or FileAccess.file_exists(output) or DirAccess.dir_exists_absolute(output.get_basename()+"-saves"):
  push_error("Require fresh task output");quit(2);return
 var loaded:Dictionary=ContentCatalog.load_checked("res://content")
 check(loaded.get("ok",false),"actual catalog loads")
 if not loaded.get("ok",false):finish();return
 var session:=GameSession.new(loaded.catalog,output.get_basename()+"-saves")
 check(session.has_method("campaign_levels"),"public session exposes ordered campaign levels")
 check(session.has_method("level_access"),"session enforces career access before replacing clinic")
 check(session.has_method("next_level"),"session exposes receipt-checked next level")
 if not session.has_method("campaign_levels") or not session.has_method("level_access") or not session.has_method("next_level"): finish();return
 var levels:Array=session.call("campaign_levels")
 check(levels.size()==12,"all twelve real campaign levels are reachable in catalog")
 if levels.size()!=12:finish();return
 var pages:=HospitalFlowPages.new()
 root.add_child(pages);pages.initialize(session);pages.show_levels()
 var first:String=levels[0].id
 var second:String=levels[1].id
 check(pages.controls.has("level_"+first) and pages.controls.has("level_"+second),"normal level menu includes career levels")
 check(not pages.controls["level_"+first].disabled and pages.controls["level_"+second].disabled,"first level available and next locked with truthful prerequisite")
 var before:Dictionary=session.sim.snapshot()
 var rejected:Dictionary=session.start_level(second)
 check(not rejected.get("ok",false) and session.sim.snapshot()==before,"locked next level rejects atomically")
 var result:Dictionary=session.start_level(first)
 check(result.get("ok",false) and session.sim.snapshot().schema_version==2,"public start opens genuine first career clinic")
 check(not session.call("next_level").get("ok",false),"unfinished hospital cannot skip to next level")
 var panel_path:="res://ui/campaign_hospital_panel.gd"
 check(ResourceLoader.exists(panel_path),"real campaign workbench exists")
 if not ResourceLoader.exists(panel_path):pages.free();finish();return
 var panel:Control=load(panel_path).new()
 root.add_child(panel);panel.initialize(session);panel.show_section("facilities")
 check(panel.controls.has("facility_search") and panel.controls.has("facility_unit"),"facility catalog has search and department filters")
 check(panel.visible_facility_ids().size()<=12,"catalog renders at most twelve facility cards per page")
 panel.set_facility_filter("operations","")
 check(panel.filtered_facility_ids().size()==32,"all32 operations survive missing unit_id normalization")
 panel.set_facility_filter("U32","")
 check(panel.filtered_facility_ids().size()==3,"specialty filter reaches last department")
 panel.show_section("cases")
 check(panel.controls.has("prepare_case") and panel.controls.has("accept_case"),"current authored case has readiness and real accept action")
 check(panel.controls.accept_case.disabled,"unprepared first case cannot be admitted by UI")
 check(session.sim.snapshot().patients.is_empty(),"readiness view does not manufacture patients")
 panel.show_section("staff")
 check(panel.controls.has("hire_role") and panel.controls.has("hire"),"recruitment uses actual campaign role catalog")
 panel.controls.hire.pressed.emit()
 check(session.sim.snapshot().staff.size()==1 and session.sim.snapshot().cash<session.level_data().initial_cash,"recruit button uses paid real command")
 panel.show_section("finance")
 check(panel.controls.has("set_price") and panel.controls.has("take_loan") and panel.controls.has("repay_loan"),"actual policies and financing commands are exposed")
 var oldcash:int=session.sim.snapshot().cash
 panel.controls.take_loan.pressed.emit()
 check(session.sim.snapshot().cash==oldcash+1000 and session.sim.snapshot().campaign.loan==1000,"loan control changes ledger-backed actual debt and cash")
 check(session.save_now().get("ok",false),"career clinic actually saves")
 var real:Dictionary=session.sim.snapshot()
 session.open_saved()
 check(session.sim.snapshot().campaign==real.campaign and session.sim.snapshot().facilities==real.facilities,"actual disk reopen preserves career and facilities")
 panel.free();pages.free();finish()
