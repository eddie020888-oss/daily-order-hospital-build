class_name CampaignClinicalDecisionsValidator
extends RefCounted

static func _fields(d: Dictionary,shape: Dictionary) -> bool:
	for key: String in shape:
		if not d.has(key) or typeof(d[key])!=shape[key]:return false
	return true

static func policy_timeline(d: Dictionary) -> Array:
	var result: Array=[]
	for row: Dictionary in d.command_receipts.values():
		if row.data.command.type=="set_clinical_policy":result.append({"sequence":int(row.data.sequence),"policy":str(row.data.command.payload.get("policy",""))})
	result.sort_custom(func(a: Dictionary,b: Dictionary)->bool:return int(a.sequence)<int(b.sequence))
	result.push_front({"sequence":0,"policy":"balanced"})
	return result

static func _policy_at(timeline: Array,sequence: int) -> String:
	var lo: int=0
	var hi: int=timeline.size()-1
	var policy: String="balanced"
	while lo<=hi:
		var mid: int=int((lo+hi)/2)
		var row: Dictionary=timeline[mid]
		if int(row.sequence)<=sequence:policy=str(row.policy);lo=mid+1
		else:hi=mid-1
	return policy

static func _evidence(d: Dictionary,catalog: ContentCatalog,p: Dictionary) -> String:
	var cd: Dictionary=p.clinical_decision
	var ai: int=CampaignClinicalDecisions.anchor_index(catalog.campaign.cases[p.case_id])
	if cd.anchor_base_index!=ai or ai<0:return "invalid_clinical_anchor"
	var e: Dictionary=cd.evidence
	if p.step_history.size()<=ai:
		return "" if e.is_empty() else "unearned_clinical_anchor_evidence"
	if not _fields(e,{"history_index":TYPE_INT,"step_id":TYPE_STRING,"started_tick":TYPE_INT,"unit_id":TYPE_STRING,"staff_ids":TYPE_ARRAY,"trained_staff_id":TYPE_STRING,"training_order_id":TYPE_STRING,"quality_order_id":TYPE_STRING}):return "invalid_clinical_anchor_evidence"
	var h: Dictionary=p.step_history[ai]
	if e.history_index!=ai or e.step_id!=h.step_id or e.started_tick!=h.started_tick or e.staff_ids!=h.staff_ids or e.unit_id!=catalog.campaign.facilities[h.facility_kind].unit_id:return "invalid_clinical_anchor_provenance"
	if (e.trained_staff_id=="")!=(e.training_order_id==""):return "invalid_clinical_training_pair"
	if e.training_order_id!="":
		var order: Dictionary=d.work_orders.get(e.training_order_id,{})
		if order.is_empty() or order.status!="done" or order.get("handler","")!="training" or order.get("trainee_id","")!=e.trained_staff_id or e.trained_staff_id not in h.staff_ids or order.get("unit_id","")!=e.unit_id or int(order.completed_tick)>int(h.started_tick):return "unearned_clinical_training_confidence"
		var found: bool=false
		for row: Dictionary in d.campaign.training:
			if row.staff_id==e.trained_staff_id and row.unit_id==e.unit_id and row.order_id==e.training_order_id and int(row.tick)==int(order.completed_tick):found=true
		if not found:return "missing_clinical_training_receipt"
	if e.quality_order_id!="":
		var order: Dictionary=d.work_orders.get(e.quality_order_id,{})
		if order.is_empty() or order.status!="done" or order.get("handler","")!="research" or order.get("project_id","")!="clinical_quality" or int(order.completed_tick)>int(h.started_tick):return "unearned_clinical_quality_confidence"
	return ""

static func _patient(d: Dictionary,catalog: ContentCatalog,p: Dictionary,seen_commands: Dictionary,timeline: Array) -> String:
	if not p.get("clinical_decision") is Dictionary:return "missing_clinical_decision_state"
	var cd: Dictionary=p.clinical_decision
	if not _fields(cd,{"version":TYPE_INT,"revision":TYPE_INT,"state":TYPE_STRING,"anchor_base_index":TYPE_INT,"evidence":TYPE_DICTIONARY,"receipts":TYPE_ARRAY,"treatment_confidence":TYPE_INT,"deficit":TYPE_INT,"referral_order_id":TYPE_STRING}) or cd.version!=1 or cd.revision!=cd.receipts.size():return "invalid_clinical_decision_state"
	var evidence_error: String=_evidence(d,catalog,p)
	if evidence_error!="":return evidence_error
	var plan: Array=CampaignClinicalDecisions.effective_steps(d,catalog,p)
	if plan.is_empty() or p.steps!=plan:return "invalid_clinical_effective_plan"
	var ai: int=cd.anchor_base_index
	var exams: int=0
	var last_tick: int=p.arrived_tick
	var last_sequence: int=0
	var final_action: String=""
	var final_confidence: int=-1
	var final_deficit: int=0
	for n: int in range(cd.receipts.size()):
		var value: Variant=cd.receipts[n]
		if not value is Dictionary:return "invalid_clinical_decision_receipt"
		var r: Dictionary=value
		if not _fields(r,{"id":TYPE_STRING,"revision":TYPE_INT,"tick":TYPE_INT,"sequence":TYPE_INT,"source":TYPE_STRING,"command_id":TYPE_STRING,"policy":TYPE_STRING,"action":TYPE_STRING,"confidence":TYPE_INT,"deficit":TYPE_INT,"history_count":TYPE_INT}):return "invalid_clinical_decision_receipt"
		if final_action!="" or r.id!=str(p.id)+":decision:"+str(n+1) or r.revision!=n or r.action not in CampaignClinicalDecisions.ACTIONS or r.source not in ["manual","policy"] or r.tick<last_tick or r.tick>d.tick or r.sequence<last_sequence or r.sequence>d.command_sequence:return "invalid_clinical_decision_order"
		if r.history_count!=ai+1+exams or r.history_count>p.step_history.size():return "invalid_clinical_decision_history_cursor"
		var preceding: Dictionary=p.step_history[r.history_count-1]
		if int(preceding.completed_tick)<0 or int(preceding.completed_tick)>int(r.tick):return "unearned_clinical_decision_check"
		if p.step_history.size()>int(r.history_count) and int(p.step_history[r.history_count].started_tick)<int(r.tick):return "retroactive_clinical_decision"
		var expected: int=CampaignClinicalDecisions.confidence(p,r.history_count)
		if r.confidence!=expected or r.deficit!=maxi(0,80-expected):return "invalid_clinical_confidence_formula"
		var policy: String=_policy_at(timeline,r.sequence)
		if r.policy!=policy or policy not in CampaignClinicalDecisions.POLICIES:return "invalid_clinical_policy_history"
		if r.source=="manual":
			if r.command_id=="" or seen_commands.has(r.command_id) or not d.command_receipts.has(r.command_id):return "missing_clinical_decision_command"
			var public: Dictionary=d.command_receipts[r.command_id]
			var command: Dictionary=public.data.command
			if command.type!="clinical_decision" or public.data.sequence!=r.sequence or public.data.tick!=r.tick or command.payload!={"patient_id":p.id,"action":r.action,"expected_revision":r.revision}:return "invalid_clinical_decision_command"
			if public.data.get("patient_id","")!=p.id or public.data.get("revision",-1)!=n+1 or public.data.get("confidence",-1)!=r.confidence or public.data.get("action","")!=r.action or public.data.get("deficit",-1)!=r.deficit:return "invalid_clinical_decision_result"
			seen_commands[r.command_id]=true
		else:
			if r.command_id!="" or policy=="manual":return "invalid_automatic_clinical_decision"
			var limit: int=2 if policy=="thorough" else 1
			var target: int=95 if policy=="thorough" else 80
			var action: String="continue_exam" if expected<target and exams<limit else "cautious_treat"
			if r.action!=action:return "invalid_automatic_clinical_policy_choice"
		if r.action=="continue_exam":
			exams+=1
			if exams>2:return "clinical_extra_exam_limit"
		else:final_action=r.action;final_confidence=r.confidence;final_deficit=r.deficit
		last_tick=r.tick;last_sequence=r.sequence
	if final_action=="cautious_treat":
		if cd.treatment_confidence!=final_confidence or cd.deficit!=final_deficit:return "invalid_clinical_treatment_terms"
	elif cd.treatment_confidence!=-1 or cd.deficit!=0:return "unearned_clinical_treatment_terms"
	var expected_state: String="not_ready"
	var anchor_complete: bool=p.step_history.size()>ai and int(p.step_history[ai].completed_tick)>=0
	if anchor_complete:expected_state="pending"
	if not cd.receipts.is_empty():
		var last: Dictionary=cd.receipts[-1]
		if last.action=="continue_exam":
			expected_state="examining"
			if p.step_history.size()>int(last.history_count) and int(p.step_history[last.history_count].completed_tick)>=0:expected_state="pending"
		elif last.action=="cautious_treat":expected_state="settled" if p.phase=="left" and p.outcome=="completed" else "authorized"
		elif last.action=="refer":expected_state="settled" if p.phase=="left" and p.outcome=="referred" else "referring"
	if cd.state!=expected_state:return "invalid_clinical_decision_lifecycle"
	if cd.state=="pending" and p.phase not in ["care_queue","moving_exit","abandoned"]:return "invalid_clinical_pending_phase"
	if p.phase=="left" and p.outcome=="completed" and final_action!="cautious_treat":return "clinical_treatment_not_authorized"
	if p.outcome=="referred" or cd.referral_order_id!="":
		if final_action!="refer" or cd.referral_order_id=="":return "unearned_clinical_referral"
		var order: Dictionary=d.work_orders.get(cd.referral_order_id,{})
		if order.is_empty() or order.facility_kind!="O05" or order.patient_id!=p.id or order.step_id!=str(p.case_id)+":decision:referral" or order.status!="done":return "invalid_clinical_referral_order"
		var proof: bool=false
		for h: Dictionary in p.step_history:
			if h.work_order_id==order.id and int(h.completed_tick)==int(order.completed_tick) and int(h.completed_tick)>=0:proof=true
		if not proof:return "missing_clinical_referral_handover"
	if final_action!="refer" and p.step_index>=p.steps.size() and p.phase=="moving_exit" and p.outcome!="abandoned" and final_action!="cautious_treat":return "clinical_early_success_exit"
	return ""

static func validate(d: Dictionary,catalog: ContentCatalog) -> String:
	if not LongCampaign.is_long(d):return ""
	if not d.campaign.has("clinical_decisions_version"):return ""
	if typeof(d.campaign.clinical_decisions_version)!=TYPE_INT or d.campaign.clinical_decisions_version!=1:return "invalid_clinical_decisions_version"
	if not d.campaign.get("clinical_policy") is String or d.campaign.clinical_policy not in CampaignClinicalDecisions.POLICIES:return "invalid_clinical_policy"
	# Build once for this immutable validation input; never retain a stale global
	# cache across save/load or different hospitals. Lookups only see policy rows.
	var timeline: Array=policy_timeline(d)
	if _policy_at(timeline,int(d.command_sequence))!=d.campaign.clinical_policy:return "invalid_current_clinical_policy"
	var seen: Dictionary={}
	var referred: int=0
	for p: Dictionary in d.patients.values():
		var error: String=_patient(d,catalog,p,seen,timeline)
		if error!="":return error
		if p.phase=="left" and p.outcome=="referred":referred+=1
	if not d.metrics.get("referred") is int or int(d.metrics.referred)!=referred:return "invalid_clinical_referral_metrics"
	for row: Dictionary in d.command_receipts.values():
		if row.data.command.type=="clinical_decision" and not seen.has(row.data.command.id):return "orphan_clinical_decision_command"
	return ""
