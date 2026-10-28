class_name CampaignContent
extends RefCounted

const RULESET := "full-hospital-v1"
const LONG_RULESET := "full-hospital-v2"

static func is_campaign(d: Dictionary) -> bool:
	return d.get("schema_version",0) in [2,3] or d.get("ruleset","") in [RULESET,LONG_RULESET]

static func load_into(catalog: ContentCatalog, root: String) -> String:
	var path:=root.path_join("full_hospital.json")
	if not FileAccess.file_exists(path): return "" # Legacy fixture catalogs remain valid.
	var parser:=JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path))!=OK or not parser.data is Dictionary: return "invalid_full_hospital_json"
	# Projection calibration intentionally contains fractional pixel positions.
	# Only model/business numbers use the integer-only legacy normalizer.
	var raw: Dictionary=parser.data
	var view_data:={}
	for id in raw.get("facilities",{}):
		view_data[id]=raw.facilities[id].get("views",[])
		raw.facilities[id].erase("views")
	var normalized:=ContentCatalog._normalize(raw)
	if not normalized.ok: return "campaign_"+normalized.error
	var full: Dictionary=normalized.value
	for id in full.get("facilities",{}): full.facilities[id].views=view_data[id]
	if full.get("version","")!=RULESET: return "invalid_campaign_version"
	for check in [["facilities",128],["diseases",39],["cases",96],["audits",16],["levels",12],["roles",8]]:
		if not full.get(check[0]) is Dictionary or full[check[0]].size()!=check[1]: return "campaign_count:"+check[0]
	for id in full.facilities:
		var f: Dictionary=full.facilities[id]
		if f.get("id")!=id or not full.units.has(f.get("unit_id","")): return "campaign_facility_id:"+id
		if not f.get("body_size") is Array or f.body_size.size()!=2 or f.body_size[0]<1 or f.body_size[1]<1: return "campaign_footprint:"+id
		if not f.get("views") is Array or f.views.size()!=4: return "campaign_views:"+id
		if f.get("cost",0)<1 or f.get("duration_ticks",0)<1 or f.get("consumable_cost",-1)<0: return "campaign_facility_numbers:"+id
		if not f.get("roles") is Array or f.roles.is_empty(): return "campaign_facility_roles:"+id
		for role in f.roles:
			if not full.roles.has(role): return "campaign_unknown_role:"+str(role)
		for q in range(4):
			var view: Dictionary=f.views[q]
			if view.get("quarter",-1)!=q or not FileAccess.file_exists(view.get("path","")): return "campaign_missing_view:"+id
	for id in full.cases:
		var c: Dictionary=full.cases[id]
		if c.get("id")!=id or not full.diseases.has(c.get("disease_id","")) or not full.units.has(c.get("unit_id","")): return "campaign_case_id:"+id
		if not c.get("steps") is Array or c.steps.is_empty() or c.get("patient_count",0) not in [1,2,3]: return "campaign_case_steps:"+id
		var step_ids:={}
		for step in c.steps:
			if not step is Dictionary or step_ids.has(step.get("id","")) or step.get("id","")=="": return "campaign_step_id:"+id
			step_ids[step.id]=true
			if not full.facilities.has(step.get("facility_kind","")): return "campaign_case_facility:"+id
			if step.get("kind","") not in ["patient","support"] or step.get("duration_ticks",0)<1 or step.get("cost",-1)<0: return "campaign_step_numbers:"+id
	var assigned:={}
	for n in range(1,13):
		var id:="career_%02d"%n
		if not full.levels.has(id): return "campaign_level_missing:"+id
		var level: Dictionary=full.levels[id]
		if level.get("order",0)!=n or level.get("ruleset","")!=RULESET or level.get("case_ids",[]).size()!=8: return "campaign_level_fields:"+id
		for case_id in level.case_ids:
			if not full.cases.has(case_id) or assigned.has(case_id): return "campaign_level_case:"+id
			assigned[case_id]=true
		for audit_id in level.audit_ids:
			if not full.audits.has(audit_id): return "campaign_unknown_audit"
	if assigned.size()!=96: return "campaign_cases_unassigned"
	catalog.campaign=full
	for id in full.levels: catalog.levels[id]=full.levels[id].duplicate(true)
	return _load_long(catalog,root)

static func _load_long(catalog:ContentCatalog,root:String)->String:
	var path:String=root.path_join("long_campaign.json")
	if not FileAccess.file_exists(path):return ""
	var parsed:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	var normalized:Dictionary=ContentCatalog._normalize(parsed)
	if not normalized.ok or not normalized.value is Dictionary:return "invalid_long_content"
	var data:Dictionary=normalized.value
	if data.get("version","")!=LONG_RULESET or data.get("schema_version",0)!=3 or not data.get("levels") is Dictionary or data.levels.size()!=12:return "invalid_long_content_version"
	var total:=0
	for n in range(1,13):
		var id:String="long_%02d"%n
		if not data.levels.has(id):return "missing_long_level"
		var level:Dictionary=data.levels[id]
		if level.get("id","")!=id or level.get("ruleset","")!=LONG_RULESET or level.get("order",0)!=n or not level.get("phases") is Array or level.phases.size()!=4:return "invalid_long_level"
		if level.get("case_ids",[])!=catalog.campaign.levels["career_%02d"%n].case_ids:return "invalid_long_signature_cases"
		var quotas:=0
		for index in range(4):
			var p:Variant=level.phases[index]
			if not p is Dictionary:return "invalid_long_phase"
			for key:String in ["new_cures","signature_cases","hospital_value","cash","reputation","cure_rate","profitable_days","min_daily_profit","min_daily_cures","research","trained_staff","trained_units","quality_samples","hygiene","roles","reward","arrival_interval_ticks","max_live"]:
				if not p.get(key) is int or p[key]<0:return "invalid_long_phase_number"
			if p.new_cures<1 or p.signature_cases!=(index+1)*2 or p.arrival_interval_ticks<80 or p.max_live<1 or p.max_live>level.max_patients:return "invalid_long_phase_capacity"
			if p.cure_rate>100 or p.hygiene>100 or p.trained_units>level.unit_ids.size() or p.quality_samples<1 or p.research>catalog.campaign.projects.size():return "invalid_long_phase_requirements"
			quotas+=p.new_cures
		if quotas!=level.get("treated_target",0) or level.get("day_ticks",0)!=6000:return "invalid_long_targets"
		total+=quotas
	if total!=6470:return "invalid_long_total"
	catalog.campaign["long_form"]=data
	for id:String in data.levels:
		catalog.campaign.levels[id]=data.levels[id].duplicate(true)
		catalog.levels[id]=data.levels[id].duplicate(true)
	return ""
