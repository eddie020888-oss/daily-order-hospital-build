extends SceneTree

var output := ""
var passed := 0
var failed := 0
var checks: Array=[]

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=").replace("\\","/")
	_run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks.append({"ok":ok,"check":label})
	if ok: passed+=1
	else: failed+=1
	print(("CAMPAIGN GROWTH PASS: " if ok else "CAMPAIGN GROWTH FAIL: ")+label)

func _run() -> void:
	if not output.begins_with("E:/CODEX/") or output.simplify_path()!=output or FileAccess.file_exists(output): quit(2); return
	var loaded: Dictionary=ContentCatalog.load_checked("res://content")
	check(bool(loaded.get("ok",false)),"real campaign catalog loads")
	var flow: Script=load("res://campaign/campaign_clinical_flow.gd")
	var ready: bool=flow!=null and flow.has_method("service_terms") and flow.has_method("patience_limit")
	check(ready,"growth has actual service timing and recoverable patience effects")
	if loaded.get("ok",false) and ready:
		var catalog: ContentCatalog=loaded.catalog
		var state: ClinicState=CampaignState.create("career_01",catalog)
		var d: Dictionary=state.data
		d.staff={"staff_001":{"skills":[]}}
		# Intake now precedes medical care. Test the intended U01 clinical
		# specialty, not whichever step happens to occupy array index zero.
		var step: Dictionary={}
		for candidate: Dictionary in catalog.campaign.cases["U01-C1"].steps:
			if candidate.facility_kind=="U01-E1": step=candidate.duplicate(true); break
		step.duration_ticks=100
		var original: Dictionary=step.duplicate(true)
		var terms: Dictionary=flow.service_terms(d,catalog,step,["staff_001"])
		check(terms.planned_duration==100 and terms.effective_duration==100 and terms.efficiency_source=="","untrained baseline preserves the authored service duration")
		d.staff.staff_001.skills=["U01"]
		terms=flow.service_terms(d,catalog,step,["staff_001"])
		check(terms.effective_duration==90 and terms.efficiency_source=="training:staff_001","unit-qualified training shortens actual service by ten percent")
		d.campaign.research=["efficiency"]
		terms=flow.service_terms(d,catalog,step,["staff_001"])
		check(terms.effective_duration==90,"training and research cannot stack into an unintended speed multiplier")
		d.staff.staff_001.skills=[]
		terms=flow.service_terms(d,catalog,step,["staff_001"])
		check(terms.effective_duration==90 and terms.efficiency_source=="research:efficiency","completed efficiency research applies to real clinical timing")
		d.campaign.research=[]; d.staff.staff_001.skills=["U02"]
		check(flow.service_terms(d,catalog,step,["staff_001"]).effective_duration==100 and step==original,"unrelated training cannot change this unit or rewrite the case plan")
		var p := {"comfort_bonus":0}
		var baseline: int=catalog.levels.career_01.patience_ticks
		check(flow.patience_limit(d,catalog,p)==baseline,"ordinary price and hygiene preserve the authored waiting allowance")
		d.campaign.price_percent=125
		check(flow.patience_limit(d,catalog,p)==int(baseline*100/125),"higher prices measurably reduce waiting allowance")
		d.campaign.research=["clinical_quality"]
		p.comfort_bonus=100
		check(flow.patience_limit(d,catalog,p)==int(baseline*100/125)+700,"quality research and actual food or water comfort extend waiting allowance")
		d.campaign.hygiene=69
		check(flow.patience_limit(d,catalog,p)==int(baseline*100/125)+400,"poor hygiene applies a bounded recoverable waiting penalty")
		d.campaign.hygiene=70
		check(flow.patience_limit(d,catalog,p)==int(baseline*100/125)+700,"restored hygiene removes its penalty without rebuilding patient state")
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	var file := FileAccess.open(output,FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed":passed,"failed":failed,"checks":checks,"scope":"Explicit pure-rule growth units; public research/training jobs and effective service clock are verified by campaign playthroughs and clinical saves."},"  "))
	print("CAMPAIGN GROWTH RESULT: passed=%d failed=%d"%[passed,failed])
	quit(1 if failed else 0)
