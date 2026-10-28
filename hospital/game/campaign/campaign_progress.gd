class_name CampaignProgress
extends RefCounted

static func empty() -> Dictionary:
	return {"completed_levels":[],"receipts":{}}

static func _seal(receipt: Dictionary) -> String:
	# Integrity against accidental corruption; not a security boundary or DRM.
	var proof:=receipt.duplicate(true)
	proof.erase("seal")
	return JSON.stringify(proof,"",true).sha256_text()

static func validate(career: Variant, catalog: ContentCatalog) -> String:
	if career is Dictionary and career.get("ruleset","")=="full-hospital-v2":return LongCampaign.validate_career(career,catalog)
	if not career is Dictionary or not career.get("completed_levels") is Array or not career.get("receipts") is Dictionary: return "invalid_career"
	if career.completed_levels.size()!=career.receipts.size() or career.completed_levels.size()>12: return "invalid_career_counts"
	for n in range(career.completed_levels.size()):
		var id:="career_%02d"%(n+1)
		if career.completed_levels[n]!=id or not career.receipts.has(id) or not catalog.campaign.levels.has(id): return "invalid_career_order"
		var r: Variant=career.receipts[id]
		if not r is Dictionary or r.get("level_id")!=id or r.get("order")!=n+1 or r.get("seal","")!=_seal(r): return "invalid_career_receipt"
		if r.get("completed_cases",[])!=catalog.campaign.levels[id].case_ids or r.get("audit_ids",[])!=catalog.campaign.levels[id].audit_ids: return "invalid_career_objectives"
	return ""

static func record_win(d: Dictionary, catalog: ContentCatalog) -> void:
	if LongCampaign.is_long(d):return
	var level: Dictionary=catalog.levels[d.level_id]
	if d.campaign.completed_cases!=level.case_ids: return
	for id in level.operation_ids:
		if d.evidence.facilities.get(id,0)<1: return
	for id in level.audit_ids:
		if not d.campaign.audits.get(id,{}).get("passed",false): return
	for event in d.campaign.events:
		if event.status!="resolved": return
	if d.metrics.abandoned>0: return
	var career: Dictionary=d.campaign.career
	if career.receipts.has(d.level_id):
		d.challenge={"status":"won","reason":"career_objectives_complete","ended_tick":d.tick}
		d.paused=true
		return
	if career.completed_levels.size()!=level.order-1: return
	var receipt:={"level_id":d.level_id,"order":level.order,"completed_cases":d.campaign.completed_cases.duplicate(),"facility_evidence":d.evidence.facilities.duplicate(true),"audit_ids":level.audit_ids.duplicate(),"tick":d.tick,"income":d.metrics.income,"expenses":d.metrics.get("expenses",{}).duplicate(true)}
	receipt.seal=_seal(receipt)
	career.completed_levels.append(d.level_id)
	career.receipts[d.level_id]=receipt
	sync_tracks(d)
	d.challenge={"status":"won","reason":"career_objectives_complete","ended_tick":d.tick}
	d.paused=true
	CampaignFinance.post(d,"grant",level.mission_grant,"mission:"+d.level_id)

static func sync_tracks(d:Dictionary)->void:
	if not d.has("career_tracks"):return
	var career:Dictionary=d.get("campaign",{}).get("career",d.get("campaign_career",{}))
	if career.get("completed_levels",[]).is_empty():return
	var key:String=str(career.get("ruleset","full-hospital-v1"))
	d.career_tracks[key]=career.duplicate(true)
