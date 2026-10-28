extends SceneTree

const Paths=preload("res://tests/support/onboarding_test_paths.gd")
const HELPER:String="res://input/campaign_build_diagnostics.gd"
var paths:Variant
var passed:int=0
var failed:int=0
var checks:Array=[]
var notes:Dictionary={}

func _initialize()->void:
	var requested:String=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):requested=arg.trim_prefix("--output=")
	var reserved:Dictionary=Paths.reserve(requested,"build-feedback-red")
	if not reserved.get("ok",false):
		printerr("BUILD FEEDBACK PATH ERROR: "+str(reserved.get("code","report_path_rejected")));quit(2);return
	paths=reserved.paths
	_run.call_deferred()

func check(ok:bool,label:String,detail:Variant=null)->void:
	checks.append({"ok":ok,"check":label,"detail":detail})
	if ok:passed+=1
	else:failed+=1
	print(("BUILD FEEDBACK PASS: " if ok else "BUILD FEEDBACK FAIL: ")+label)

func proposal(kind:String,origin:int=25)->Dictionary:
	return {"unit_id":str(FacilityLayout.facility_spec(kind).unit_id),"origin_cell":origin,"layout":FacilityLayout.default_layout("U04",kind,0)}

func diagnose(helper:Script,state:Dictionary,plan:Dictionary,code:String,label:String,expected:Array)->void:
	var original_state:Dictionary=state.duplicate(true)
	var original_plan:Dictionary=plan.duplicate(true)
	var result:Dictionary=helper.call("diagnose",state,plan,code)
	check(state==original_state and plan==original_plan,label+" diagnosis is read-only")
	var cells:Array=result.get("conflict_cells",[])
	for cell:int in expected:check(cell in cells,label+" marks the actual conflicting or unreachable target",{"expected":cell,"actual":cells})
	check(not str(result.get("conflict_hint","")).is_empty(),label+" has actionable text")
	var unique:Dictionary={}
	for value:Variant in cells:
		check(value is int and value>=0 and value<432,label+" emitted cell stays inside actual grid",value)
		unique[value]=true
	check(unique.size()==cells.size(),label+" emits unique cells")
	notes[label]={"code":code,"diagnostics":result}

func _run()->void:
	var loaded:Dictionary=ContentCatalog.load_checked("res://content")
	check(loaded.get("ok",false),"real catalog loads")
	if not loaded.get("ok",false):finish();return
	var state:ClinicState=LongCampaignState.create_formal("long_01",loaded.catalog)
	var original:Dictionary=state.to_data()
	var canonical:Dictionary=proposal("U04-E1")
	check(FacilityLayout.preview(state,canonical).get("ok",false),"existing canonical4x4 first-exam layout is really valid")
	var door:Dictionary=canonical.duplicate(true);door.layout.doors=[{"side":"south","offset":0}]
	var door_result:Dictionary=FacilityLayout.preview(state,door)
	check(door_result.get("code","")=="door_operating_position","wrong door produces actual access collision",door_result)
	var access:Dictionary=canonical.duplicate(true);access.layout.doors=[{"side":"south","offset":0}];access.layout.facilities[0].x=2
	var access_result:Dictionary=FacilityLayout.preview(state,access)
	check(access_result.get("code","")=="facility_access_out_of_bounds","repair position outside room is rejected",access_result)
	var overlap:Dictionary=canonical.duplicate(true)
	var duplicate:Dictionary=overlap.layout.facilities[0].duplicate(true);duplicate.id="__second_feedback__";overlap.layout.facilities.append(duplicate)
	var overlap_result:Dictionary=FacilityLayout.preview(state,overlap)
	check(overlap_result.get("code","")=="facility_overlap","overlapping bodies are really rejected",overlap_result)
	var occupied:Dictionary=canonical.duplicate(true);occupied.layout.height=3
	var occupied_result:Dictionary=FacilityLayout.preview(state,occupied)
	check(occupied_result.get("code","")=="facility_occupied_unreachable","shortening canonical south aisle produces real occupied-target failure",occupied_result)
	check(state.to_data()==original,"all authoritative preview queries leave hospital unchanged")
	var draft:=CampaignBuildDraft.new();draft.initialize("build","U04-E1");draft.origin_cell=97;draft.layout=canonical.layout.duplicate(true)
	check(draft.bounds_error(original)=="","4-row draft ends before main corridor")
	var before:Dictionary=draft.capture_state()
	check(not draft.adjust_bounds(Vector2i(0,1)),"expansion into main corridor is rejected")
	check(draft.capture_state()==before,"rejected expansion preserves draft exactly")
	check(not draft.bounds_issue.is_empty() and draft.bounds_issue.contains("走廊"),"rejected expansion explains the actual main-corridor reason",draft.bounds_issue)
	check(FileAccess.file_exists(HELPER),"read-only conflict diagnosis helper is available")
	if FileAccess.file_exists(HELPER):
		var helper:Script=load(HELPER)
		diagnose(helper,original,door,"door_operating_position","door conflict",[73])
		diagnose(helper,original,access,"facility_access_out_of_bounds","repair outside room",[29])
		diagnose(helper,original,overlap,"facility_overlap","body overlap",[25,26,49,50])
		diagnose(helper,original,occupied,"facility_occupied_unreachable","occupied unreachable target",[73])
		var path_result:Dictionary=helper.call("diagnose",original,occupied,"facility_occupied_unreachable")
		check(path_result.get("conflict_cells",[]).size()==1,"occupied-access feedback marks a proven target, not a fictitious unique blocking cell",path_result)
		var legal_result:Dictionary=helper.call("diagnose",original,canonical,"")
		check(legal_result.get("conflict_cells",[]).is_empty(),"valid recommendation never paints false conflict cells")
	finish()

func finish()->void:
	paths.write_report({"passed":passed,"failed":failed,"checks":checks,"notes":notes,"scope":"External read-only geometry/draft diagnostics. Fresh real formal factory; no built rooms, staff, funds or simulation clocks are injected. Invalid proposals and draft-only expansion are mechanical fixtures, not normal-player or device acceptance."})
	print("BUILD FEEDBACK RESULT: passed=%d failed=%d"%[passed,failed])
	quit(1 if failed else 0)
