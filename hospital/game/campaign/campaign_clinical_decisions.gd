class_name CampaignClinicalDecisions
extends RefCounted

# Optional, versioned clinical layer. Missing version is the exact legacy path.
const VERSION: int=1
const SAFE_THRESHOLD: int=80
const THOROUGH_TARGET: int=95
const MAX_EXAMS: int=2
const ACTIONS: Array=["continue_exam","cautious_treat","refer"]
const POLICIES: Array=["balanced","thorough","manual"]

static func enabled(d: Dictionary) -> bool:
	return LongCampaign.is_long(d) and d.campaign.get("clinical_decisions_version",0)==VERSION

static func anchor_index(definition: Dictionary) -> int:
	for n: int in range(definition.steps.size()):
		var step: Dictionary=definition.steps[n]
		if step.kind=="patient" and step.facility_kind!="O01":return n
	return -1

static func initialize_patient(d: Dictionary,definition: Dictionary,p: Dictionary) -> void:
	if not enabled(d):return
	p.clinical_decision={"version":VERSION,"revision":0,"state":"not_ready","anchor_base_index":anchor_index(definition),"evidence":{},"receipts":[],"treatment_confidence":-1,"deficit":0,"referral_order_id":""}

static func _quality_order(d: Dictionary,tick: int) -> String:
	if "clinical_quality" not in d.campaign.research:return ""
	var ids: Array=d.work_orders.keys();ids.sort()
	for id: String in ids:
		var order: Dictionary=d.work_orders[id]
		if order.get("project_id","")=="clinical_quality" and order.status=="done" and int(order.completed_tick)<=tick:return id
	return ""

static func _training_order(d: Dictionary,sid: String,unit: String,tick: int) -> String:
	for row: Dictionary in d.campaign.training:
		if row.staff_id==sid and row.unit_id==unit and int(row.tick)<=tick:
			var order: Dictionary=d.work_orders.get(row.order_id,{})
			if not order.is_empty() and order.status=="done" and order.get("trainee_id","")==sid and order.get("unit_id","")==unit and int(order.completed_tick)<=tick:return str(order.id)
	return ""

static func service_started(d: Dictionary,catalog: ContentCatalog,p: Dictionary) -> void:
	if not enabled(d) or not p.has("clinical_decision"):return
	var cd: Dictionary=p.clinical_decision
	var definition: Dictionary=catalog.campaign.cases[p.case_id]
	var index: int=anchor_index(definition)
	if index<0 or p.step_history.is_empty() or p.steps[p.step_index].id!=definition.steps[index].id:return
	if not cd.evidence.is_empty():return
	var h: Dictionary=p.step_history[-1]
	var unit: String=catalog.campaign.facilities[h.facility_kind].unit_id
	var trained: String=""
	var training: String=""
	for sid: String in h.staff_ids:
		if not d.staff.has(sid) or unit not in d.staff[sid].get("skills",[]):continue
		var proof: String=_training_order(d,sid,unit,int(d.tick))
		if proof!="":trained=sid;training=proof;break
	cd.evidence={"history_index":p.step_index,"step_id":h.step_id,"started_tick":int(d.tick),"unit_id":unit,"staff_ids":h.staff_ids.duplicate(),"trained_staff_id":trained,"training_order_id":training,"quality_order_id":_quality_order(d,int(d.tick))}

static func extra_exams(p: Dictionary,at_count: int=-1) -> int:
	var count: int=0
	var end: int=int(p.step_history.size()) if at_count<0 else at_count
	for n: int in range(mini(end,p.step_history.size())):
		var h: Dictionary=p.step_history[n]
		if ":decision:exam:" in str(h.step_id) and int(h.completed_tick)>=0:count+=1
	return count

static func confidence(p: Dictionary,at_count: int=-1) -> int:
	if not p.has("clinical_decision") or p.clinical_decision.evidence.is_empty():return -1
	var cd: Dictionary=p.clinical_decision
	var end: int=p.step_history.size() if at_count<0 else at_count
	var ai: int=int(cd.anchor_base_index)
	if ai<0 or ai>=end or ai>=p.step_history.size() or int(p.step_history[ai].completed_tick)<0:return -1
	var tier: int=clampi(int(str(p.case_id).get_slice("-C",1)),1,4)
	return clampi(77-4*(tier-1)+18*extra_exams(p,at_count)+(10 if cd.evidence.trained_staff_id!="" else 0)+(5 if cd.evidence.quality_order_id!="" else 0),0,100)

static func after_service(d: Dictionary,catalog: ContentCatalog,p: Dictionary) -> void:
	if not enabled(d) or not p.has("clinical_decision") or p.step_history.is_empty():return
	var cd: Dictionary=p.clinical_decision
	var h: Dictionary=p.step_history[-1]
	if int(h.completed_tick)<0:return
	var definition: Dictionary=catalog.campaign.cases[p.case_id]
	var ai: int=anchor_index(definition)
	var first: bool=ai>=0 and h.step_id==definition.steps[ai].id
	if first or ":decision:exam:" in str(h.step_id):
		cd.state="pending";p.phase="care_queue";p.stage="care";p.wait_reason="clinical_decision_required"
	elif str(h.step_id)==str(p.case_id)+":decision:referral":
		cd.referral_order_id=h.work_order_id
		p.outcome="referred";p.phase="moving_exit";p.stage="exit";p.wait_reason=""

static func _clone(definition: Dictionary,suffix: String) -> Dictionary:
	var ai: int=anchor_index(definition)
	if ai<0:return {}
	var step: Dictionary=definition.steps[ai].duplicate(true)
	step.id=str(definition.id)+":decision:"+suffix
	return step

static func _referral(catalog: ContentCatalog,case_id: String) -> Dictionary:
	var f: Dictionary=catalog.campaign.facilities["O05"]
	return {"id":case_id+":decision:referral","facility_kind":"O05","kind":"support","duration_ticks":int(f.duration_ticks),"cost":int(f.consumable_cost),"roles":f.roles.duplicate(),"resource":str(f.get("input_resource","")),"quantity":int(f.get("input_quantity",0))}

static func effective_steps(d: Dictionary,catalog: ContentCatalog,p: Dictionary) -> Array:
	if not catalog.campaign.cases.has(p.get("case_id","")):return []
	var definition: Dictionary=catalog.campaign.cases[p.case_id]
	var plan: Array=definition.steps.duplicate(true)
	if not enabled(d) or not p.get("clinical_decision") is Dictionary:return plan
	if not p.clinical_decision.get("receipts") is Array:return []
	var exams: int=0
	for receipt: Variant in p.clinical_decision.get("receipts",[]):
		if not receipt is Dictionary:return []
		# This reader is used by the core identity check before the detailed
		# decision validator. Reject malformed JSON types without conversion.
		if not receipt.get("history_count") is int or not receipt.get("deficit") is int or not receipt.get("action") is String:return []
		if int(receipt.deficit)<0 or int(receipt.deficit)>SAFE_THRESHOLD:return []
		var at: int=int(receipt.get("history_count",-1))
		if at<0 or at>plan.size():return []
		match str(receipt.get("action","")):
			"continue_exam":
				exams+=1
				plan.insert(at,_clone(definition,"exam:"+str(exams)))
			"cautious_treat":
				if at==plan.size():plan.append(_clone(definition,"treatment"))
				var deficit: int=int(receipt.get("deficit",0))
				if deficit>0:
					var remedy: Dictionary=_clone(definition,"remedy")
					remedy.duration_ticks=maxi(20,int((int(remedy.duration_ticks)*deficit+19)/20))
					remedy.cost=int(remedy.cost)+2*deficit
					plan.append(remedy)
			"refer":plan.insert(at,_referral(catalog,p.case_id))
			_:return []
	return plan

static func _option_terms(d: Dictionary,catalog: ContentCatalog,p: Dictionary,action: String) -> Dictionary:
	var definition: Dictionary=catalog.campaign.cases[p.case_id]
	var steps: Array=[]
	var score: int=confidence(p)
	var deficit: int=maxi(0,SAFE_THRESHOLD-score)
	if action=="continue_exam":steps.append(_clone(definition,"exam:preview"))
	elif action=="refer":steps.append(_referral(catalog,p.case_id))
	else:
		for n: int in range(int(p.step_index),p.steps.size()):steps.append(p.steps[n].duplicate(true))
		if steps.is_empty():steps.append(_clone(definition,"treatment"))
		if deficit>0:
			var remedy: Dictionary=_clone(definition,"remedy")
			remedy.duration_ticks=maxi(20,int((int(remedy.duration_ticks)*deficit+19)/20));remedy.cost=int(remedy.cost)+2*deficit
			steps.append(remedy)
	var cost: int=0
	var duration: int=0
	var resources: Dictionary={}
	var missing: Array=[]
	for step: Dictionary in steps:
		cost+=int(step.cost);duration+=int(step.duration_ticks)
		var resource: String=str(step.get("resource",""))
		if resource!="":resources[resource]=int(resources.get(resource,0))+int(step.quantity)
		var found: bool=false
		var staffed: bool=false
		for f: Dictionary in d.facilities.values():
			if f.kind!=step.facility_kind or f.status!="open" or int(f.condition)<=0:continue
			found=true
			if CampaignClinicalFlow._qualified_staff(d,f,step.roles,false).size()==step.roles.size():staffed=true;break
		if not found and not missing.has("missing_facility:"+str(step.facility_kind)):missing.append("missing_facility:"+str(step.facility_kind))
		elif not staffed and not missing.has("missing_staff:"+str(step.facility_kind)):missing.append("missing_staff:"+str(step.facility_kind))
	for resource: String in resources:
		if int(d.resources.get(resource,0))<int(resources[resource]):missing.append("missing_resource:"+resource)
	if CampaignClinicalFlow._available_cash(d,p.id)<cost:missing.append("insufficient_cash")
	return {"planned_cost":cost,"planned_duration_ticks":duration,"resources":resources,"steps":steps,"missing":missing,"deficit":deficit}

static func preview(d: Dictionary,catalog: ContentCatalog,patient_id: String) -> Dictionary:
	if not enabled(d):return {"enabled":false,"pending":false,"reason":"legacy_clinical_rules"}
	if not d.patients.has(patient_id):return {"enabled":true,"pending":false,"reason":"unknown_patient"}
	var p: Dictionary=d.patients[patient_id]
	var cd: Dictionary=p.get("clinical_decision",{})
	if cd.is_empty():return {"enabled":true,"pending":false,"reason":"missing_clinical_decision"}
	var pending: bool=cd.state=="pending" and p.phase=="care_queue"
	var score: int=confidence(p)
	var terms: Dictionary={}
	if pending:
		for action: String in ACTIONS:terms[action]=_option_terms(d,catalog,p,action)
	return {"enabled":true,"patient_id":patient_id,"revision":int(cd.revision),"state":str(cd.state),"pending":pending,"confidence":score,"safe_threshold":SAFE_THRESHOLD,"deficit":maxi(0,SAFE_THRESHOLD-score) if score>=0 else -1,"completed_exams":extra_exams(p),"max_exams":MAX_EXAMS,"policy":str(d.campaign.get("clinical_policy","balanced")),"policy_target":THOROUGH_TARGET if d.campaign.get("clinical_policy","balanced")=="thorough" else SAFE_THRESHOLD,"options":ACTIONS.duplicate(),"terms":terms}

static func _yes(data: Dictionary={}) -> Dictionary:return {"ok":true,"code":"ok","data":data}
static func _no(code: String,data: Dictionary={}) -> Dictionary:return {"ok":false,"code":code,"data":data}

static func set_policy(state: ClinicState,_catalog: ContentCatalog,payload: Dictionary,_reference: String) -> Dictionary:
	if not enabled(state.data):return _no("legacy_clinical_rules")
	if payload.size()!=1 or not payload.get("policy") is String or payload.policy not in POLICIES:return _no("invalid_clinical_policy")
	state.data.campaign.clinical_policy=payload.policy
	return _yes({"policy":payload.policy})

static func apply(state: ClinicState,catalog: ContentCatalog,payload: Dictionary,reference: String) -> Dictionary:
	if not enabled(state.data):return _no("legacy_clinical_rules")
	if payload.size()!=3 or not payload.get("patient_id") is String or not payload.get("action") is String or not payload.get("expected_revision") is int:return _no("invalid_payload")
	return _decide(state,catalog,payload.patient_id,payload.action,payload.expected_revision,"manual",reference.trim_prefix("command:"),int(state.data.command_sequence)+1)

static func _decide(state: ClinicState,catalog: ContentCatalog,id: String,action: String,revision: int,source: String,command_id: String,sequence: int) -> Dictionary:
	var d: Dictionary=state.data
	if not d.patients.has(id):return _no("unknown_patient")
	var p: Dictionary=d.patients[id]
	var cd: Dictionary=p.get("clinical_decision",{})
	if cd.is_empty() or cd.state!="pending" or p.phase!="care_queue":return _no("clinical_decision_not_ready")
	if revision!=int(cd.revision):return _no("stale_clinical_decision")
	if action not in ACTIONS:return _no("invalid_clinical_decision")
	if action=="continue_exam" and extra_exams(p)>=MAX_EXAMS:return _no("clinical_exam_limit")
	var terms: Dictionary=_option_terms(d,catalog,p,action)
	# A choice can wait for a busy worker, but may not authorize absent resources
	# or create a free alternative treatment. Missing terms remain visible in UI.
	if not terms.missing.is_empty():return _no("clinical_option_unavailable",{"missing":terms.missing})
	var score: int=confidence(p)
	var receipt: Dictionary={"id":id+":decision:"+str(int(cd.revision)+1),"revision":int(cd.revision),"tick":int(d.tick),"sequence":sequence,"source":source,"command_id":command_id,"policy":str(d.campaign.get("clinical_policy","balanced")),"action":action,"confidence":score,"deficit":maxi(0,SAFE_THRESHOLD-score),"history_count":int(p.step_index)}
	cd.receipts.append(receipt);cd.revision+=1
	if action=="continue_exam":cd.state="examining"
	elif action=="refer":cd.state="referring"
	else:cd.state="authorized";cd.treatment_confidence=score;cd.deficit=maxi(0,SAFE_THRESHOLD-score)
	p.steps=effective_steps(d,catalog,p)
	p.wait_reason="";p.phase="care_queue";p.stage="care"
	return _yes({"patient_id":id,"revision":int(cd.revision),"action":action,"confidence":score,"deficit":receipt.deficit})

static func before_schedule(state: ClinicState,catalog: ContentCatalog,p: Dictionary) -> bool:
	var d: Dictionary=state.data
	if not enabled(d) or not p.has("clinical_decision"):return false
	var cd: Dictionary=p.clinical_decision
	if cd.state!="pending":return false
	p.wait_reason="clinical_decision_required"
	var policy: String=str(d.campaign.get("clinical_policy","balanced"))
	if policy=="manual":return true
	var limit: int=MAX_EXAMS if policy=="thorough" else 1
	var target: int=THOROUGH_TARGET if policy=="thorough" else SAFE_THRESHOLD
	var action: String="continue_exam" if confidence(p)<target and extra_exams(p)<limit else "cautious_treat"
	var result: Dictionary=_decide(state,catalog,p.id,action,int(cd.revision),"policy","",int(d.command_sequence))
	if not result.ok:p.wait_reason="clinical_policy_blocked:"+str(result.code);return true
	return false

static func finish_exit(state: ClinicState,_catalog: ContentCatalog,p: Dictionary) -> bool:
	var d: Dictionary=state.data
	if not enabled(d) or not p.has("clinical_decision"):return false
	var cd: Dictionary=p.clinical_decision
	if p.outcome!="referred":
		if cd.state=="authorized" and p.step_index==p.steps.size():cd.state="settled"
		return false
	if p.phase in ["left","abandoned"]:return true
	var order: Dictionary=d.work_orders.get(cd.referral_order_id,{})
	if order.is_empty() or order.status!="done" or order.patient_id!=p.id or order.facility_kind!="O05":return true
	p.phase="left";p.outcome="referred";p.completed_tick=int(d.tick);p.path=[];p.path_index=0;p.move_progress=0
	if p.blocked_slot_id!="" and d.slots.has(p.blocked_slot_id):CampaignClinicalFlow._free_slot(d,d.slots[p.blocked_slot_id])
	p.blocked_slot_id="";CampaignClinicalFlow._clear_active(p);cd.state="settled"
	d.metrics.referred=int(d.metrics.get("referred",0))+1
	d.metrics.patient_totals[p.id]={"arrival_tick":p.arrived_tick,"exit_tick":d.tick,"phase":p.phase,"outcome":"referred","wait_ticks":p.wait_ticks,"total_ticks":d.tick-p.arrived_tick}
	return true
