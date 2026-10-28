class_name ConsultationView
extends RefCounted

# Cosmetic context is derived from the live slot and literal actor cells.
# The simulation's service clock remains the only authority, including pause/load.
static var _diagnosis_ticks := 0
static func context(snapshot: Dictionary, entity: String, is_staff: bool) -> Dictionary:
	var actor: Dictionary=snapshot.get("staff" if is_staff else "patients",{}).get(entity,{})
	if actor.is_empty() or int(actor.get("move_progress",0))!=0:return {}
	var room: Dictionary=snapshot.get("rooms",{}).get(actor.get("room_id",""),{})
	if room.get("kind","")!="diagnosis":return {}
	if is_staff and room.get("staff_id","")!=entity:return {}
	if actor.get("phase","")!=("serving" if is_staff else "diagnosis_service"):return {}
	var serving: Dictionary={}
	for slot in snapshot.get("slots",{}).values():
		if slot.get("room_id","")==actor.room_id and slot.get("phase","")=="serving":
			if is_staff or slot.get("patient_id","")==entity:serving=slot;break
	if serving.is_empty():return {}
	var staff_cell: int=room.staff_cells[0]
	var patient_cell: int=serving.cell
	if int(actor.get("cell",-1))!=(staff_cell if is_staff else patient_cell):return {}
	if _diagnosis_ticks==0:
		_diagnosis_ticks=int(ContentCatalog.load_checked("res://content").catalog.rooms.diagnosis.service_ticks)
	var direction := HospitalWorld.cell_position(patient_cell if is_staff else staff_cell)-HospitalWorld.cell_position(staff_cell if is_staff else patient_cell)
	return {"progress":clampf(1.0-float(serving.remaining_ticks)/maxi(1,_diagnosis_ticks),0,1),
		"heading":atan2(direction.x,direction.z),"room_id":actor.room_id,"is_staff":is_staff}
