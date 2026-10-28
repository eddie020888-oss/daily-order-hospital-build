class_name RoomView
extends Node3D

const COLORS := {"reception":Color("e6d4b7"),"diagnosis":Color("e5e2cf"),"echo":Color("e0e5da"),"motion":Color("eadccc"),"sensory":Color("e4dfe9"),"recovery":Color("e4e6d5"),"general_exam":Color("dfe9e1"),"pharmacy":Color("e4e8d6"),"ward":Color("dde7e3")}
const NAMES := {"reception":"接待台","diagnosis":"诊断室","echo":"声环治疗","motion":"动作校准","sensory":"感官分轨","recovery":"安静恢复","general_exam":"综合检查","pharmacy":"药房","ward":"双床留观"}
var wall_segments: Array[MeshInstance3D] = []
var slot_markers: Dictionary = {}
var _signature := ""
var _status := ""
var _door_lamp: MeshInstance3D
var _label: Label3D
var _door_lamps: Array[MeshInstance3D] = []
var _door_labels: Array[Label3D] = []
var _rotors: Array[Node3D] = []
var _device_lamps: Array[MeshInstance3D] = []
var _active := false
var _tick := 0.0
var _consult_chairs: Dictionary={}
var _consult_contacts: Dictionary={}

func present(room: Dictionary, slots: Dictionary) -> void:
	var signature := JSON.stringify([room.kind,room.cells,room.wall_edges,room.equipment_cells,room.service_cells,room.get("layout",{}),room.get("door_cell",-1),room.get("door_outside_cell",-1),room.get("doorways",[]),room.get("window_edges",[]),room.get("visual_shared_walls",{}),room.get("visual_window_edges",{})])
	if signature != _signature:
		_signature = signature
		_build(room)
	_status = room.get("status","open")
	for lamp in _door_lamps:lamp.material_override = ActorView.material(ActorView.MINT if _status == "open" else ActorView.ORANGE)
	var mode: String = room.get("mode","fast")
	var label_text: String = NAMES[room.kind] + (" · 舒缓" if room.kind in ["echo","motion","sensory"] and mode == "gentle" else "")
	if _status != "open":
		label_text += " · 排空中" if _status == "draining" else " · 已关闭"
	for label in _door_labels:label.text=label_text
	for lamp in _device_lamps:
		lamp.material_override=ActorView.material(Color("d8a052") if _status!="open" else Color("34887d") if mode=="gentle" else Color("c75b40"))
	_active = false
	for cell in slot_markers:
		var occupied := false
		for slot in slots.values():
			if slot.get("cell",-1) == cell and not str(slot.get("patient_id","")).is_empty():
				occupied = true
				_active = _active or slot.get("phase","") == "serving"
		slot_markers[cell].set_meta("slot_occupied",occupied)
		slot_markers[cell].visible=occupied
		slot_markers[cell].material_override = ActorView.material(ActorView.ORANGE if occupied else ActorView.MINT)

func _build(room: Dictionary) -> void:
	set_meta("visual_room_cells",room.cells.duplicate())
	for child in get_children():
		remove_child(child)
		child.queue_free()
	wall_segments.clear()
	slot_markers.clear()
	_rotors.clear()
	_device_lamps.clear()
	_door_lamps.clear()
	_door_labels.clear()
	_consult_chairs.clear()
	_consult_contacts.clear()
	var interior := preload("res://presentation/hospital_interior_art.gd").build(self,room)
	wall_segments.assign(interior.walls)
	_door_lamp = interior.lamp
	_label = interior.label
	_door_lamps.assign(interior.get("door_lamps",[]))
	_door_labels.assign(interior.get("door_labels",[]))
	_build_equipment(room)
	var footprint_version:int=room.get("layout",{}).get("footprint_version",1)
	for item in room.get("layout",{}).get("furniture",[]):
		var furniture:=RoomFurniture.create(item.kind,footprint_version)
		furniture.position=HospitalWorld.cell_position(room.origin_cell+int(item.y)*24+int(item.x))+Vector3(0,HospitalInteriorArt.ROOM_FLOOR_TOP,0)+RoomFurniture.placement_offset(item.kind,item.rotation,footprint_version)
		furniture.rotation.y=-int(item.rotation)*PI/2
		add_child(furniture)
		var contact:=ContactShadow.create(Vector2(.86,.38) if item.kind=="bench" and footprint_version==2 else Vector2(.45,.38),.18)
		contact.position=furniture.position+Vector3(0,.004,0)
		contact.rotation.y=furniture.rotation.y
		add_child(contact)
	for cell in room.service_cells:
		var at := HospitalWorld.cell_position(cell)
		slot_markers[cell] = ActorView.ring(self,at+Vector3(0,0.05,0),0.37,ActorView.MINT)
	var keep: Array=wall_segments.duplicate()
	keep.append_array(_door_lamps)
	keep.append_array(slot_markers.values())
	# Chair contacts must stay separate so fallback/baked-chair visibility can
	# hide their actual geometry instead of leaving a merged grey patch behind.
	keep.append_array(_consult_contacts.values())
	SceneArtLibrary.batch_static(self,keep)
	for child in get_children():
		if child is MeshInstance3D and child not in keep:child.set_meta("hospital_interior",true)

func _build_equipment(room:Dictionary) -> void:
	var rotation_value:int=room.get("layout",{}).get("equipment",{}).get("rotation",room.rotation)
	var footprint_version:int=room.get("layout",{}).get("footprint_version",1)
	if room.kind == "reception" and footprint_version!=2:
		# Legacy layouts separate the pods; version 2 places them side by side.
		var reception := Node3D.new()
		reception.name="EquipmentAssembly"
		reception.set_meta("equipment_kind","reception")
		add_child(reception)
		for cell in room.equipment_cells:
			_build_device(room.kind,HospitalWorld.cell_position(cell),rotation_value,false,reception,footprint_version)
	elif room.kind=="ward":
		# The canonical12 hard cells are two disjoint6-cell beds, not a single
		# image stretched across the walkable middle aisle.
		for index in range(0,room.equipment_cells.size(),6):
			var center:=Vector3.ZERO
			for offset in range(6):center+=HospitalWorld.cell_position(room.equipment_cells[index+offset])
			_build_device(room.kind,center/6,rotation_value,false,null,2)
	elif room.kind == "recovery":
		var cells_per_seat:int=2 if footprint_version==2 else 1
		for index in range(0,room.equipment_cells.size(),cells_per_seat):
			var center:=Vector3.ZERO
			for offset in range(cells_per_seat):center+=HospitalWorld.cell_position(room.equipment_cells[index+offset])
			_build_device(room.kind,center/cells_per_seat,rotation_value,false,null,footprint_version)
	else:
		var equipment_center := Vector3.ZERO
		for cell in room.equipment_cells:
			equipment_center += HospitalWorld.cell_position(cell)
		equipment_center /= room.equipment_cells.size()
		_build_device(room.kind,equipment_center,rotation_value,true,null,footprint_version)
	if room.kind=="diagnosis":
		for is_staff in [true,false]:
			var cell: int=room.staff_cells[0] if is_staff else room.service_cells[0]
			var other: int=room.service_cells[0] if is_staff else room.staff_cells[0]
			var direction := (HospitalWorld.cell_position(other)-HospitalWorld.cell_position(cell)).normalized()
			var chair: Node3D=SceneArtLibrary.consult_chair(is_staff)
			chair.position=HospitalWorld.cell_position(cell)-direction*.32+Vector3(0,HospitalInteriorArt.ROOM_FLOOR_TOP,0)
			chair.rotation.y=atan2(direction.x,direction.z)
			add_child(chair)
			var contact:=ContactShadow.create(Vector2(.44,.38),.18)
			contact.position=chair.position+Vector3(0,.004,0)
			add_child(contact)
			_consult_chairs[is_staff]=chair
			_consult_contacts[is_staff]=contact

func _build_device(kind: String, at: Vector3, rotation_value: int, _wide: bool, device_parent: Node3D = null, footprint_version: int = 1) -> void:
	if GridEquipmentFrames.CATALOG_IDS.has(kind):footprint_version=2
	var base:=Node3D.new()
	base.name="EquipmentAssembly"
	base.set_meta("equipment_kind",kind)
	base.set_meta("footprint_version",footprint_version)
	base.position=at
	base.rotation.y=-rotation_value*PI/2
	if device_parent==null: device_parent=self
	device_parent.add_child(base)
	var apparatus:=SceneArtLibrary.equipment(kind,footprint_version)
	base.add_child(apparatus)
	var contact_size:=Vector2(.85,.58) if kind=="diagnosis" else Vector2(1.0,.65) if apparatus is EquipmentSprite and apparatus.using_sprite else Vector2(.52,.50)
	var contact:=ContactShadow.create(contact_size,.20)
	contact.position.y=HospitalInteriorArt.ROOM_FLOOR_TOP+.003
	base.add_child(contact)
	if kind=="diagnosis" or apparatus is EquipmentSprite:return
	var lamp:=ActorView.ball(base,Vector3(.26,1.08,.30),Vector3.ONE*.065,ActorView.MINT)
	_device_lamps.append(lamp)

func _process(delta: float) -> void:
	_tick += delta
	for lamp in _device_lamps:
		lamp.scale=Vector3.ONE*.065*(.85+.15*sin(_tick*3.0) if _active else 1.0)
	if _active:
		for i in range(_rotors.size()):
			_rotors[i].rotation.y += delta*(0.8+i*0.3)

func set_consult_chair_visibility(staff_visible: bool,patient_visible: bool) -> void:
	if _consult_chairs.has(true):_consult_chairs[true].visible=staff_visible
	if _consult_chairs.has(false):_consult_chairs[false].visible=patient_visible
	if _consult_contacts.has(true):_consult_contacts[true].visible=staff_visible
	if _consult_contacts.has(false):_consult_contacts[false].visible=patient_visible
	if not _consult_chairs.is_empty():
		for marker in slot_markers.values():marker.visible=bool(marker.get_meta("slot_occupied",false)) and not patient_visible

func hide_consult_chair(is_staff: bool) -> void:
	if _consult_chairs.has(is_staff):_consult_chairs[is_staff].visible=false
	if _consult_contacts.has(is_staff):_consult_contacts[is_staff].visible=false
