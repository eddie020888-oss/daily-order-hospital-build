class_name CampaignOpeningLoop
extends RefCounted

# A versioned admission policy inside full-hospital-v2, sharing the original
# patient, station, stock, work-order, clinical decision and financial clock.
const VERSION:int=1
const TEMPLATE_CASE_ID:String="U04-C2"
const LIVE_LIMIT:int=2
const INTAKE_KIND:String="O01"
const PRIMARY_KIND:String="U04-E1"
const TREATMENT_KIND:String="U04-E2"
const REFERRAL_KIND:String="O05"
const SUPPLY_KIND:String="O15"

static func enabled(d:Dictionary)->bool:
	return LongCampaign.is_long(d) and d.get("campaign",{}).get("opening_loop_version") is int and d.campaign.opening_loop_version==VERSION

static func is_template(d:Dictionary,case_id:String)->bool:
	return enabled(d) and case_id==TEMPLATE_CASE_ID

static func validate_version(d:Dictionary)->String:
	if not d.campaign.has("opening_loop_version"):return ""
	if not enabled(d) or d.campaign.get("clinical_decisions_version",0)!=1:return "invalid_opening_loop_version"
	return ""

static func _state(d:Dictionary)->ClinicState:
	var state:=ClinicState.new()
	state.data=d
	return state

static func _steps(catalog:ContentCatalog)->Array:
	return catalog.campaign.cases[TEMPLATE_CASE_ID].steps

static func _reasons(state:ClinicState,catalog:ContentCatalog,steps:Array)->Array:
	return CampaignClinicalFlow._case_preparation_reasons(state,catalog,TEMPLATE_CASE_ID,false,steps)

static func live_count(d:Dictionary)->int:
	var count:int=0
	for instance:Dictionary in d.campaign.case_instances.values():
		if instance.kind!="routine" or instance.case_id!=TEMPLATE_CASE_ID:continue
		for id:String in instance.patient_ids:
			if d.patients[id].phase not in ["left","abandoned"]:count+=1
	return count

static func admission_reasons(state:ClinicState,catalog:ContentCatalog)->Array:
	var d:Dictionary=state.data
	if not enabled(d):return ["opening_loop_disabled"]
	var steps:Array=_steps(catalog)
	var entry:Array=steps.slice(0,2)
	var reasons:Array=_reasons(state,catalog,entry)
	# Checking the combined entry+exit plan covers cumulative cash and stock,
	# rather than independently promising the same money to both services.
	if reasons.is_empty() and not _reasons(state,catalog,steps).is_empty():
		var exit_plan:Array=entry.duplicate(true)
		exit_plan.append(CampaignClinicalDecisions._referral(catalog,TEMPLATE_CASE_ID))
		reasons=_reasons(state,catalog,exit_plan)
	if live_count(d)+int(catalog.campaign.cases[TEMPLATE_CASE_ID].patient_count)>LIVE_LIMIT:reasons.append("opening_patient_limit")
	return reasons

static func _requirement(code:String,kind:String="",role:String="",resource:String="",reason:String="")->Dictionary:
	return {"code":code,"facility_kind":kind,"role":role,"resource":resource,"reason":reason}

static func _facility_requirement(d:Dictionary,catalog:ContentCatalog,kind:String)->Dictionary:
	var found:bool=false
	var staffed:bool=false
	var first_missing:String=""
	for facility:Dictionary in d.facilities.values():
		if facility.kind!=kind:continue
		found=true
		if facility.status!="open" or int(facility.condition)<=0:continue
		var roles:Array=catalog.campaign.facilities[kind].roles
		if CampaignClinicalFlow._qualified_staff(d,facility,roles,false).size()==roles.size():staffed=true;break
		for role:String in roles:
			var assigned:bool=false
			for id:String in facility.staff_ids:
				if d.staff.has(id) and d.staff[id].role==role:assigned=true;break
			if not assigned:first_missing=role;break
	if not found:return _requirement("build",kind)
	if staffed:return _requirement("")
	if first_missing!="":
		for worker:Dictionary in d.staff.values():
			if worker.role==first_missing and worker.get("facility_id","")=="":return _requirement("assign",kind,first_missing)
		return _requirement("hire",kind,first_missing)
	# A closed/broken facility is not working capacity. The reason lets the
	# existing facility controls explain reopening/repair instead of hiring.
	return _requirement("waiting_treatment",kind,"","","facility_unavailable")

static func _supply_requirement(d:Dictionary,catalog:ContentCatalog)->Dictionary:
	var required:int=int(_steps(catalog)[1].get("quantity",0))
	if int(d.resources.get("delivered",0))>=required:return _requirement("")
	var facility:Dictionary=_facility_requirement(d,catalog,SUPPLY_KIND)
	if facility.code!="":return facility
	for order:Dictionary in d.work_orders.values():
		if order.facility_kind==SUPPLY_KIND and order.status not in ["done","failed","cancelled"]:return _requirement("supply_in_progress",SUPPLY_KIND,"","delivered")
	return _requirement("supply_operation",SUPPLY_KIND,"","delivered")

static func _next_requirement(d:Dictionary,catalog:ContentCatalog,view:Dictionary)->Dictionary:
	if not view.clinical_pending_patient_ids.is_empty():return _requirement("clinical_pending",TREATMENT_KIND)
	for kind:String in [INTAKE_KIND,PRIMARY_KIND]:
		var need:Dictionary=_facility_requirement(d,catalog,kind)
		if need.code!="":return need
	var supply:Dictionary=_supply_requirement(d,catalog)
	if supply.code!="":return supply
	if not view.treatment_ready and not view.referral_ready:
		# Prefer completing an already-built therapy station. Otherwise provide
		# the affordable, real staffed referral route before accepting visitors.
		var therapy_exists:bool=false
		for facility:Dictionary in d.facilities.values():
			if facility.kind==TREATMENT_KIND:therapy_exists=true;break
		var kind:String=TREATMENT_KIND if therapy_exists else REFERRAL_KIND
		var exit_need:Dictionary=_facility_requirement(d,catalog,kind)
		if exit_need.code!="":return exit_need
	if view.can_admit and not d.campaign.intake_enabled:return _requirement("open_intake")
	if view.live_count>=LIVE_LIMIT:return _requirement("waiting_treatment",TREATMENT_KIND,"","","opening_patient_limit")
	if not view.admission_reasons.is_empty():return _requirement("waiting_treatment",TREATMENT_KIND,"","",str(view.admission_reasons[0]))
	return _requirement("")

static func preview(d:Dictionary,catalog:ContentCatalog)->Dictionary:
	var result:Dictionary={"enabled":enabled(d),"version":VERSION if enabled(d) else 0,"template_case_id":TEMPLATE_CASE_ID,"intake_kind":INTAKE_KIND,"primary_kind":PRIMARY_KIND,"treatment_kind":TREATMENT_KIND,"referral_kind":REFERRAL_KIND,"supply_kind":SUPPLY_KIND,"required_roles":[],"primary_ready":false,"treatment_ready":false,"referral_ready":false,"live_count":0,"live_limit":LIVE_LIMIT,"can_admit":false,"admission_reasons":[],"next_requirement":_requirement(""),"clinical_pending_patient_ids":[],"status":"setup"}
	if not result.enabled:return result
	for kind:String in [INTAKE_KIND,PRIMARY_KIND,SUPPLY_KIND,REFERRAL_KIND,TREATMENT_KIND]:
		for role:String in catalog.campaign.facilities[kind].roles:
			if not result.required_roles.has(role):result.required_roles.append(role)
	var state:ClinicState=_state(d)
	var steps:Array=_steps(catalog)
	result.primary_ready=_reasons(state,catalog,steps.slice(0,2)).is_empty()
	result.treatment_ready=_reasons(state,catalog,steps.slice(2)).is_empty()
	result.referral_ready=_reasons(state,catalog,[CampaignClinicalDecisions._referral(catalog,TEMPLATE_CASE_ID)]).is_empty()
	result.live_count=live_count(d)
	result.admission_reasons=LongCampaignClinical.instance_readiness(state,catalog,TEMPLATE_CASE_ID,"routine")
	result.can_admit=result.admission_reasons.is_empty() and d.challenge.status=="running"
	for id:String in d.campaign.live_patient_ids:
		var patient:Dictionary=d.patients[id]
		if CampaignClinicalDecisions.preview(d,catalog,id).get("pending",false):result.clinical_pending_patient_ids.append(id)
	result.next_requirement=_next_requirement(d,catalog,result)
	if not result.clinical_pending_patient_ids.is_empty():result.status="clinical_decision"
	elif result.live_count>0:result.status="waiting_treatment" if result.next_requirement.code=="waiting_treatment" else "running"
	elif result.can_admit:result.status="ready"
	return result
