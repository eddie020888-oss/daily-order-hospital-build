class_name CampaignRoomView
extends Node3D

## Actual independent device instances inside the same closed architecture kit.
## No baked whole-room picture, patient teleport or fake operating phase.
var wall_segments:Array[MeshInstance3D]=[]
var facility_views:Dictionary={}
var slot_markers:Dictionary={}
var _labels:Array[Label3D]=[]
var _lamps:Array[MeshInstance3D]=[]
var _signature := ""

func present(room:Dictionary,slots:Dictionary,facilities:Dictionary={}) -> void:
	var signature:=JSON.stringify([room.get("layout",{}),room.get("origin_cell",-1),room.get("unit_id",""),room.get("wall_edges",[]),room.get("visual_shared_walls",{}),room.get("visual_window_edges",{}),room.get("campaign_preview",false)])
	if signature!=_signature:
		_signature=signature
		_build(room)
	var title:=FacilityLayout.unit_name(str(room.get("unit_id","")))
	if room.get("campaign_preview",false):title="预览 · "+title
	if room.get("status","open")!="open":title+=" · 已关闭"
	for label:Label3D in _labels:label.text=title
	for lamp:MeshInstance3D in _lamps:lamp.material_override=ActorView.material(ActorView.MINT if room.get("status","open")=="open" else ActorView.ORANGE)
	for id:String in facility_views:
		var current:Dictionary=facilities.get(id,{})
		facility_views[id].set_meta("facility_status",current.get("status","open"))
		facility_views[id].set_meta("condition",current.get("condition",100))
	for cell:int in slot_markers:
		var occupied:=false
		for slot:Dictionary in slots.values():
			if slot.get("room_id","")!=room.get("id","") or str(slot.get("patient_id","")).is_empty():continue
			if slot.get("cell",-1)==cell:
				occupied=true;break
			var station:Dictionary=room.get("facility_geometries",{}).get(slot.get("facility_id",""),{})
			if cell in station.get("service_cells",[]):occupied=true;break
		slot_markers[cell].visible=occupied

func _build(room:Dictionary) -> void:
	for child:Node in get_children():remove_child(child);child.queue_free()
	wall_segments.clear();facility_views.clear();slot_markers.clear();_labels.clear();_lamps.clear()
	set_meta("visual_room_cells",room.cells.duplicate())
	set_meta("ruleset","full-hospital-v1")
	set_meta("unit_id",room.get("unit_id",""))
	# Reuse the approved cream/teal/brass architecture palette. This is a
	# display-only kit selector, not a change to the room's clinical identity.
	var construction:Dictionary=room.duplicate(true)
	construction.kind="general_exam"
	var interior:=HospitalInteriorArt.build(self,construction)
	wall_segments.assign(interior.walls)
	_labels.assign(interior.get("door_labels",[]));_lamps.assign(interior.get("door_lamps",[]))
	for item:Dictionary in room.layout.facilities:
		var station:=FacilityLayout.facility_geometry(room,item)
		if station.is_empty():continue
		var center:=Vector3.ZERO
		for cell:int in station.equipment_cells:center+=HospitalWorld.cell_position(cell)
		center/=maxi(1,station.equipment_cells.size())
		var assembly:=Node3D.new();assembly.name="Facility_"+str(item.id)
		assembly.position=center;assembly.rotation.y=-int(item.rotation)*PI*.5
		assembly.set_meta("facility_id",item.id);assembly.set_meta("equipment_kind",item.kind)
		assembly.set_meta("footprint_version",2)
		add_child(assembly)
		var equipment:Node3D=SceneArtLibrary.equipment(item.kind,2)
		equipment.set_meta("facility_id",item.id)
		assembly.add_child(equipment)
		facility_views[item.id]=equipment
		var original:=GridEquipmentFrames.catalog_item(item.kind)
		var body:Array=original.body_size
		var contact:=ContactShadow.create(Vector2(float(body[0])*.42,float(body[1])*.34),.17)
		contact.position.y=HospitalInteriorArt.ROOM_FLOOR_TOP+.003
		assembly.add_child(contact)
		for cell:int in station.service_cells:
			var marker:=ActorView.ring(self,HospitalWorld.cell_position(cell)+Vector3(0,.05,0),.34,ActorView.MINT)
			marker.visible=false;slot_markers[cell]=marker
	# duplicate() retains the source Array[MeshInstance3D] element constraint,
	# even when assigned to an unparameterized Array. Allocate a Node array so
	# real door labels and wall/lamp meshes can safely share the exclusion set.
	var keep:Array[Node]=[]
	keep.append_array(wall_segments);keep.append_array(_labels);keep.append_array(_lamps);keep.append_array(slot_markers.values())
	SceneArtLibrary.batch_static(self,keep)
	for child:Node in get_children():
		if child is MeshInstance3D and not child in keep:child.set_meta("hospital_interior",true)

func set_consult_chair_visibility(_staff_visible:bool,_patient_visible:bool) -> void:
	# Current catalog actors operate at explicit external service positions.
	# No lying/chair animation is claimed by a device PNG or generic Examine.
	pass

func hide_consult_chair(_is_staff:bool) -> void:
	pass
