extends SceneTree

# Actual Main/Card regression for diagnostic metadata leaking error codes into
# player copy. Invalid drafts are mechanical fixtures, not normal play.
const Paths=preload("res://tests/support/onboarding_test_paths.gd")
var paths:Variant
var host:Variant
var passed:int=0
var failed:int=0
var checks:Array=[]
var notes:Array=[]
var baseline:Dictionary={}

func _initialize()->void:
	var output:String=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	var reserved:Dictionary=Paths.reserve(output,"build-feedback-text")
	if not reserved.get("ok",false):printerr("BUILD FEEDBACK TEXT PATH ERROR: "+str(reserved.get("code","unknown")));quit(2);return
	paths=reserved.paths
	_run.call_deferred()

func check(ok:bool,label:String,detail:Variant=null)->bool:
	checks.append({"ok":ok,"check":label,"detail":detail})
	if ok:passed+=1
	else:failed+=1
	print(("BUILD FEEDBACK TEXT PASS: " if ok else "BUILD FEEDBACK TEXT FAIL: ")+label)
	return ok

func frames()->void:
	for _n:int in range(5):await process_frame

func inspect(label:String,expected_code:String)->void:
	var controller:CampaignBuildController=host.hud.campaign_build.controller
	var proposal:Dictionary=controller.draft.proposal()
	var raw:Dictionary=FacilityLayout.preview(host.session.sim.snapshot(),proposal)
	check(not raw.get("ok",true) and raw.get("code","")==expected_code,label+" uses the genuine authoritative invalid proposal",raw)
	var view:Dictionary=controller.present()
	await frames()
	var merged:Dictionary=view.get("preview",{})
	check(merged.get("code","")==raw.get("code","") and merged.get("ok",true)==raw.get("ok",false),label+" presentation enrichment preserves backend code and result",merged)
	var raw_data:Dictionary=raw.get("data",{})
	var merged_data:Dictionary=merged.get("data",{})
	# The original invalid previews currently have empty data. Preserve every
	# authoritative field (including a real kind if a backend provides one),
	# and permit only the two presentation-specific additions. No fake source
	# kind or fake conflict_cells is injected to manufacture that coverage.
	for key:Variant in raw_data:
		check(merged_data.has(key) and merged_data[key]==raw_data[key],label+" preserves authoritative data field "+str(key),{"raw":raw_data,"merged":merged_data})
	check(merged_data.has("kind")==raw_data.has("kind") and merged_data.get("kind",null)==raw_data.get("kind",null),label+" diagnostic kind cannot overwrite or invent authoritative facility kind",{"raw":raw_data,"merged":merged_data})
	var additions:Array=[]
	for key:Variant in merged_data:
		if not raw_data.has(key):additions.append(str(key))
	additions.sort()
	check(additions==["conflict_cells","conflict_hint"],label+" only safe conflict cells and human hint are added",additions)
	var text:String=host.hud.campaign_build.card._status.text
	check(not text.contains("door_operating_position") and not text.contains("facility_overlap"),label+" actual Card status never exposes internal door/body error codes",text)
	var hint:String=str(merged_data.get("conflict_hint",""))
	check(hint!="" and text.contains(hint),label+" actual Card keeps the actionable conflict explanation",text)
	check(host.session.sim.snapshot()==baseline,label+" preview and actual Card leave complete hospital unchanged")
	notes.append({"label":label,"raw":raw,"merged":merged,"actual_card_status":text,"source_has_kind":raw_data.has("kind"),"model_unchanged":host.session.sim.snapshot()==baseline})

func _run()->void:
	root.size=Vector2i(932,430)
	var loaded:Dictionary=ContentCatalog.load_checked("res://content")
	if not check(loaded.get("ok",false),"actual production catalog loads"):await finish();return
	var profile:String=paths.fixture("feedback-copy-profile")
	if not check(profile!="","fresh isolated actual Main profile"):await finish();return
	host=load("res://main.gd").new();host.session=GameSession.new(loaded.catalog,profile)
	root.add_child(host);await frames()
	host.hud.configure_display(Vector2(932,430),Vector2(932,430),160,Rect2(59,0,814,409))
	host.hud.flow.close();host.session.dismiss_notice();await frames()
	baseline=host.session.sim.snapshot()
	check(baseline.paused and baseline.rooms.is_empty() and baseline.facilities.is_empty(),"unmodified formal hospital starts empty and paused")
	if not check(host.hud.begin_campaign_build("build","U04-E1"),"actual HUD opens the real build editor"):await finish();return
	var controller:CampaignBuildController=host.hud.campaign_build.controller
	var canonical:Dictionary=FacilityLayout.default_layout("U04","U04-E1",0)
	controller.draft.origin_cell=25;controller.draft.layout=canonical.duplicate(true)
	controller.draft.layout.doors=[{"side":"south","offset":0}]
	controller.draft.step=2;controller.draft.selected_index=0;controller.draft.selected_kind="U04-E1"
	await inspect("door conflict","door_operating_position")
	controller.draft.layout=canonical.duplicate(true)
	var duplicate:Dictionary=controller.draft.layout.facilities[0].duplicate(true)
	duplicate.id="__feedback_copy_overlap__";controller.draft.layout.facilities.append(duplicate)
	await inspect("body overlap","facility_overlap")
	check(SnapshotValidator.validate(host.session.sim.snapshot(),loaded.catalog)=="","actual hospital remains strictly save-valid")
	await finish()

func finish()->void:
	if host!=null:host.free();host=null
	await create_timer(.24).timeout
	if paths.write_report({"passed":passed,"failed":failed,"checks":checks,"notes":notes,"scope":"Actual Main/Controller/Card and genuine invalid door/body proposals. No fake conflict payload or authoritative kind, no backend/clinical/model/clock field edits. Original raw data is compared with enrichment; real-kind preservation is checked if the authoritative API supplies it, while current invalid raw data is empty. This is mechanical UI/metadata evidence, not normal play or native visual acceptance."})!=OK:printerr("BUILD FEEDBACK TEXT REPORT WRITE ERROR");quit(2);return
	print("BUILD FEEDBACK TEXT RESULT: passed=%d failed=%d"%[passed,failed]);quit(1 if failed else 0)
