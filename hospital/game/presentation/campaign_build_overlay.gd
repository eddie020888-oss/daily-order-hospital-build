class_name CampaignBuildOverlay
extends Node3D

# The coloured cells are the actual body/operation/worker/repair masks.
# They never participate in picking or simulation navigation.
var _signature := ""

func clear() -> void:
	_signature=""
	for child:Node in get_children():remove_child(child);child.queue_free()

func present(proposal: Dictionary,result: Dictionary,room: Dictionary) -> void:
	var signature:String=JSON.stringify([proposal,result.get("ok",false),result.get("code","")])
	if signature==_signature:return
	clear();_signature=signature
	var layout:Dictionary=proposal.get("layout",{})
	var origin:int=int(proposal.get("origin_cell",-1))
	var width:int=int(layout.get("width",0))
	var height:int=int(layout.get("height",0))
	if origin<0 or origin%24+width>24 or origin/24+height>18:return
	var good:bool=bool(result.get("ok",false))
	var border:Color=Color("649ca1") if good else Color("ca775e")
	for y:int in range(height):
		for x:int in range(width):_outline(origin+y*24+x,border,.014)
	if room.is_empty():
		var wall:Dictionary=proposal.duplicate(true)
		wall.kind="general_exam"
		HospitalInteriorArt.build_wall_preview(self,wall)
		return
	for item:Dictionary in layout.get("facilities",[]):
		var station:Dictionary=FacilityLayout.facility_geometry(room,item)
		for cell:int in station.get("equipment_cells",[]):_outline(cell,Color("267d89") if good else Color("d45b43"),.045)
		for cell:int in station.get("service_cells",[]):_mark(cell,Color("d8ad62"),.30)
		for cell:int in station.get("staff_cells",[]):_mark(cell,Color("67a587"),.22)
		var maintenance:int=int(station.get("maintenance_cell",-1))
		if maintenance>=0:_outline(maintenance,Color("b4835c"),.038)

func _outline(cell:int,color:Color,thickness:float) -> void:
	if cell<0 or cell>=432:return
	var at:Vector3=HospitalWorld.cell_position(cell)+Vector3(0,HospitalInteriorArt.ROOM_FLOOR_TOP+.012,0)
	for offset:float in [-.48,.48]:
		ActorView.box(self,at+Vector3(offset,0,0),Vector3(thickness,.006,.96),color)
		ActorView.box(self,at+Vector3(0,0,offset),Vector3(.96,.006,thickness),color)

func _mark(cell:int,color:Color,radius:float) -> void:
	if cell<0 or cell>=432:return
	ActorView.ring(self,HospitalWorld.cell_position(cell)+Vector3(0,HospitalInteriorArt.ROOM_FLOOR_TOP+.018,0),radius,color)
