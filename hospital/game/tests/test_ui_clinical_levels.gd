extends SceneTree
var passed := 0
var failed := 0
var checks: Array=[]
var output := ""
var host: Node3D
func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=").replace("\\","/")
	_run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks.append({"ok":ok,"check":label})
	if ok: passed+=1
	else: failed+=1
	print(("CLINICAL UI PASS: " if ok else "CLINICAL UI FAIL: ")+label)
func all_text(node: Node) -> String:
	var value := ""
	if node is Label or node is Button: value+=node.text+"\n"
	for child in node.get_children(): value+=all_text(child)
	return value
func finish() -> void:
	var f: FileAccess=FileAccess.open(output,FileAccess.WRITE)
	if f==null: quit(2); return
	f.store_string(JSON.stringify({"passed":passed,"failed":failed,"checks":checks,"scope":"Real GameSession, actual menu controls, real empty-budget clinical_02, public build/hire/assign/time/save/load. UI inspection never injects clinical phases, money or a won result."},"  "))
	print("CLINICAL UI RESULT: passed=%d failed=%d"%[passed,failed])
	if host!=null: host.free()
	quit(1 if failed>0 else 0)
func _run() -> void:
	var base := "E:/CODEX/2026-10-21/医院诊疗护理扩展/"
	if output=="" or not output.begins_with(base) or output.simplify_path()!=output or FileAccess.file_exists(output) or DirAccess.dir_exists_absolute(output.get_basename()+"-saves"):
		push_error("Require a fresh --output JSON under this task")
		quit(2); return
	root.size=Vector2i(1280,720)
	var checked: Dictionary=ContentCatalog.load_checked("res://content")
	check(bool(checked.get("ok",false)),"production content loads")
	if not checked.get("ok",false): finish(); return
	var catalog: ContentCatalog=checked.catalog
	var session := GameSession.new(catalog,output.get_basename()+"-saves")
	var probe := HospitalFlowPages.new()
	root.add_child(probe)
	probe.initialize(session)
	probe.show_launch()
	check(session.has_method("start_level"),"public session supports validated level selection")
	check(probe.controls.has("choose_level"),"actual launch offers explicit level selection")
	if not session.has_method("start_level") or not probe.controls.has("choose_level"):
		probe.free(); finish(); return
	probe.free()
	host=load("res://main.gd").new()
	host.session=session
	root.add_child(host)
	host.set_process(false)
	for _i in range(4): await process_frame
	var h: HospitalHud=host.hud
	var pages: HospitalFlowPages=h.flow
	var original: Dictionary=session.sim.snapshot()
	pages.controls.choose_level.pressed.emit()
	check(pages.page=="levels" and pages.controls.has("level_level_01") and pages.controls.has("level_clinical_02"),"actual menu exposes both normal playable levels")
	if not pages.controls.has("level_clinical_02"): finish(); return
	pages.controls.level_clinical_02.pressed.emit()
	check(pages.page=="restart" and session.sim.snapshot()==original,"selecting second level only opens confirmation; original game is unchanged")
	pages.controls.cancel_restart.pressed.emit()
	check(pages.page=="levels" and session.sim.snapshot()==original,"cancel level change preserves original clinic exactly")
	pages.controls.level_clinical_02.pressed.emit()
	pages.controls.confirm_restart.pressed.emit()
	var clinical: Dictionary=session.sim.snapshot()
	check(pages.page=="guide" and clinical.level_id=="clinical_02" and clinical.cash==15000 and clinical.paused and clinical.rooms.is_empty(),"explicit confirmation opens the real empty paused 15000-budget second level")
	var guide: String=all_text(pages)
	check(guide.contains("48") and guide.contains("60") and guide.contains("护士") and guide.contains("药房") and guide.contains("留观"),"second-level guide shows its actual goal and nursing route")
	check(not guide.contains("弃诊不超过6") and not guide.contains("利润和现金都不能为负"),"second level does not inherit first-level extra victory requirements")
	h.present()
	check(h._top.tooltip_text.contains("60") and h._top.tooltip_text.contains("1200"),"HUD denominator and duration come from selected level")
	for key: String in ["build_general_exam","build_pharmacy","build_ward","hire_nurse"]: check(h.palette.controls.has(key),"real build/recruit catalog contains "+key)
	pages.controls.guide_build.pressed.emit()
	h.controls.settings.pressed.emit()
	pages.controls.restart_game.pressed.emit()
	check(all_text(pages).contains("15,000") or all_text(pages).contains("15000"),"restart confirmation uses the current level's initial cash")
	pages.controls.confirm_restart.pressed.emit()
	check(session.sim.snapshot().level_id=="clinical_02" and session.sim.snapshot().cash==15000,"normal restart stays in the selected level")
	pages.controls.guide_build.pressed.emit()
	var built: Dictionary=session.issue("build_room",{"kind":"ward","origin_cell":265,"rotation":0})
	check(bool(built.get("ok",false)),"publicly build actual two-bed ward")
	var hire: Dictionary=session.issue("hire_staff",{"role":"nurse"})
	check(bool(hire.get("ok",false)),"publicly recruit actual nurse")
	if not built.get("ok",false) or not hire.get("ok",false): finish(); return
	check(bool(session.issue("assign_staff",{"staff_id":hire.data.staff_id,"room_id":built.data.room_id}).get("ok",false)),"actual nurse publicly assigned to ward")
	h.select_entity(built.data.room_id,"rooms")
	check(all_text(h.selection).contains("病床1") and all_text(h.selection).contains("病床2"),"ward detail identifies each independent real bed")
	h.select_entity(hire.data.staff_id,"staff")
	check(all_text(h.selection).contains("照护") and all_text(h.selection).contains("护士"),"nurse detail shows clinical role and care workload")
	session.issue("set_paused",{"paused":false})
	for _i in range(850): session.advance_wall_time(GameSession.STEP_USEC)
	var observed: Dictionary=session.sim.snapshot()
	check(observed.patients.has("patient_006") and observed.patients.patient_006.has("care_steps"),"original sixth scheduled full-pathway care patient really arrives")
	if not observed.patients.has("patient_006"): finish(); return
	var before_view: Dictionary=session.sim.snapshot()
	h.select_entity("patient_006","patients")
	check(not h.selection.controls.has("treatment_preview") and all_text(h.selection).contains("药房"),"care patient exposes its route without inapplicable fast/gentle controls")
	check(all_text(h.selection).contains("下一站") or all_text(h.selection).contains("待进行"),"patient route communicates remaining real steps")
	check(session.sim.snapshot()==before_view,"viewing care details does not alter any authoritative state")
	h._ledger.present(observed)
	check(all_text(h._ledger).contains("发药") and all_text(h._ledger).contains("留观"),"finance explains nursing consumables and exposes care waiting stages")
	check(SnapshotValidator.validate(observed,catalog)=="","real observed clinical state validates")
	check(bool(session.save_now().get("ok",false)),"selected-level state actually saves")
	var loaded: Dictionary=SaveStore.load(session.save_root,catalog)
	check(bool(loaded.get("ok",false)) and loaded.state.to_data()==observed,"actual disk load preserves selected level and clinical state")
	session.open_saved()
	h.present()
	check(session.sim.snapshot().level_id=="clinical_02" and session.sim.snapshot().paused and not session.storage_blocked,"public reopen restores second-level UI while paused")
	var safe: Dictionary=session.sim.snapshot()
	var bad: Dictionary=session.call("start_level","unknown_level")
	check(not bad.get("ok",false) and session.sim.snapshot()==safe,"unknown level selection rejects without changing existing clinic")
	pages.show_result(session.sim.snapshot())
	var result_copy: String=all_text(pages)
	check(result_copy.contains("48") and result_copy.contains("60") and not result_copy.contains("须不超过6人"),"result explains actual second-level conditions without first-level thresholds")
	session.call("start_level","level_01")
	pages.show_guide()
	check(all_text(pages).contains("30") and all_text(pages).contains("6") and all_text(pages).contains("15分钟"),"first-level guidance keeps its original criteria")
	finish()
