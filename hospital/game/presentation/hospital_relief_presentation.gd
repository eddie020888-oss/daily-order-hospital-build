class_name HospitalReliefPresentation
extends RefCounted

# A world-only view. It never changes home assignments, geometry or save data.
const RELIEF=preload("res://campaign/campaign_staff_relief.gd")

static func for_world(d:Dictionary)->Dictionary:
	if not d.get("staff") is Dictionary or not d.get("facilities") is Dictionary or not d.get("campaign") is Dictionary:return d
	if not RELIEF.configured(d):return d
	var result:Dictionary=d
	var copied_facilities:Dictionary={}
	var ids:Array=d.staff.keys();ids.sort()
	for sid:String in ids:
		var fid:String=RELIEF.active_facility(d,sid)
		if fid=="" or not d.facilities.has(fid) or not RELIEF.owns(d,sid,fid):continue
		var f:Dictionary=d.facilities[fid]
		var cell:int=RELIEF.work_cell(d,fid,sid)
		var place:int=f.get("staff_cells",[]).find(cell)
		if cell<0 or place<0 or place>=f.get("staff_ids",[]).size() or RELIEF.slot_owner(d,fid,place)!=sid:continue
		if is_same(result,d):
			result=d.duplicate(false)
			result.staff=d.staff.duplicate(false)
			result.facilities=d.facilities.duplicate(false)
		var actor:Dictionary=d.staff[sid].duplicate(false)
		actor.facility_id=fid;actor.room_id=str(f.get("room_id",""))
		result.staff[sid]=actor
		if not copied_facilities.has(fid):
			var visual:Dictionary=f.duplicate(false)
			visual.staff_ids=f.staff_ids.duplicate()
			result.facilities[fid]=visual
			copied_facilities[fid]=true
		result.facilities[fid].staff_ids[place]=sid
	return result
