class_name ClinicalPathways
extends RefCounted

const CARE_STAGES := ["general_exam","pharmacy","ward"]

# Read-only adapters shared by simulation, strict validation and patient UI.
static func is_care(patient: Dictionary,catalog: ContentCatalog) -> bool:
	return not catalog.diseases.get(patient.get("disease_id",""),{}).get("care_steps",[]).is_empty()

static func current_room_kind(patient: Dictionary,catalog: ContentCatalog) -> String:
	var stage: String=patient.get("stage","")
	return catalog.diseases[patient.disease_id].room_kind if stage=="treatment" else stage

static func staff_occupation(slots: Dictionary,room_id: String) -> String:
	var blocked := false
	for slot: Dictionary in slots.values():
		if slot.room_id!=room_id: continue
		if slot.phase=="serving": return "serving"
		if slot.phase=="blocked": blocked=true
	return "blocked" if blocked else ""

static func info(patient: Dictionary,catalog: ContentCatalog) -> Dictionary:
	var terminal: bool=patient.get("phase","") in ["completed","abandoned"]
	var result := {"is_care":is_care(patient,catalog),"steps":[],"current_step":"" if terminal else patient.get("stage",""),"next_step":"","terminal":terminal,"abandoned":patient.get("abandon_tick",-1)>=0}
	if not result.is_care: return result
	var care: Array=catalog.diseases[patient.disease_id].care_steps
	var started: Dictionary=patient.get("care_started_ticks",{})
	var completed: Dictionary=patient.get("care_completed_ticks",{})
	var stage: String=patient.get("stage","")
	var reception_done: bool=patient.get("tolerance_revealed",false) or stage=="diagnosis" or stage in care or patient.get("wait_by_stage",{}).has("diagnosis")
	for kind: String in ["reception","diagnosis"]+care+["exit"]:
		var status := "next"
		if kind=="reception" and reception_done: status="completed"
		elif kind=="diagnosis" and patient.get("tolerance_revealed",false): status="completed"
		elif kind in care and completed.has(kind): status="completed"
		elif kind=="exit" and patient.get("phase","")=="completed": status="completed"
		elif kind==stage and not terminal and patient.get("phase","")!="outside": status="current"
		result.steps.append({"id":kind,"kind":kind,"status":status,"started_tick":started.get(kind,-1),"completed_tick":completed.get(kind,-1)})
		if not terminal and result.next_step=="" and status=="next": result.next_step=kind
	return result
