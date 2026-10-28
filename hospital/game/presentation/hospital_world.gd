class_name HospitalWorld
extends Node3D

const ReliefPresentation=preload("res://presentation/hospital_relief_presentation.gd")

# The public boundary is deep JSON-compatible snapshots, never ClinicState or Simulation.
var room_views: Dictionary = {}
var actor_views: Dictionary = {}
var prefer_simplified_characters := true
var camera_rig: CameraRig
var _room_root: Node3D
var _actor_root: Node3D
var _room_cells: Dictionary = {}
var hall_art: ReferenceHallArt
var _wall_preview: Dictionary = {}
var _last_rooms: Dictionary = {}
var _last_slots: Dictionary = {}
var _last_facilities:Dictionary={}
var _campaign_preview:CampaignRoomView

static func cell_position(cell: int) -> Vector3:
	return Vector3(cell%24,0,cell/24)

static func actor_position(actor: Dictionary) -> Vector3:
	var position_value := cell_position(int(actor.get("cell",217)))
	var path: Array = actor.get("path",[])
	var index: int = actor.get("path_index",0)
	var progress: int = actor.get("move_progress",0)
	if progress>0 and index+1<path.size():
		position_value = position_value.lerp(cell_position(int(path[index+1])),float(progress)/maxi(1,int(actor.get("move_ticks",4))))
	return position_value + Vector3(0,0.05,0)

func _ready() -> void:
	_room_root = Node3D.new()
	_room_root.name = "Rooms"
	add_child(_room_root)
	_actor_root = Node3D.new()
	_actor_root.name = "Actors"
	add_child(_actor_root)
	_build_shell()
	camera_rig = CameraRig.new()
	camera_rig.name = "CameraRig"
	add_child(camera_rig)

func _build_shell() -> void:
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("e7e2d7")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("fff6e7")
	settings.ambient_light_energy = 0.48
	settings.ambient_light_sky_contribution = 0.0
	settings.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	# Reflection lighting gives the original brass/enamel equipment a readable
	# warm highlight without changing its authored PBR colours or adding lights.
	var sky_material:=ProceduralSkyMaterial.new()
	sky_material.sky_top_color=Color("bcd2d0")
	sky_material.sky_horizon_color=Color("fff0d3")
	sky_material.ground_horizon_color=Color("ebdcc1")
	sky_material.ground_bottom_color=Color("8d8170")
	var reflection_sky:=Sky.new()
	reflection_sky.radiance_size=Sky.RADIANCE_SIZE_128
	reflection_sky.sky_material=sky_material
	settings.sky=reflection_sky
	settings.reflected_light_source=Environment.REFLECTION_SOURCE_SKY
	environment.environment = settings
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55,-25,0)
	sun.light_color = Color("fff2d9")
	sun.light_energy = 0.50
	sun.shadow_enabled = true
	sun.shadow_blur = 2.0
	sun.shadow_opacity = 0.28
	add_child(sun)
	var fill:=DirectionalLight3D.new()
	fill.name="SoftFill"
	fill.rotation_degrees=Vector3(-35,125,0)
	fill.light_color=Color("e6eff0")
	fill.light_energy=.17
	add_child(fill)
	# Original approved art is a fixed-view 2.5D environment, not substitute 3D scenery.
	# Rooms/actors remain independent world entities above the mathematical y=0 floor.
	hall_art=ReferenceHallArt.new()
	hall_art.name="ReferenceHall"
	add_child(hall_art)

func set_build_grid_visible(value:bool) -> void:
	if is_instance_valid(hall_art):hall_art.set_build_grid_visible(value)

func present(snapshot: Dictionary) -> void:
	# Initialization can also be used before entering the tree by hosts, but rendering needs _ready.
	if _room_root == null:
		return
	# Temporary ownership is a shallow read-only projection for work contexts.
	# Actor identity, body/path position and retained room geometry stay original.
	var projected:Dictionary=ReliefPresentation.for_world(snapshot)
	var rooms: Dictionary = snapshot.get("rooms",{})
	var slots: Dictionary = snapshot.get("slots",{})
	_last_rooms=rooms.duplicate(true)
	_last_slots=slots.duplicate(true)
	_last_facilities=snapshot.get("facilities",{}).duplicate(true)
	_present_rooms(rooms,slots)
	var visible_ids := {}
	for group in ["staff","patients"]:
		for id in snapshot.get(group,{}):
			var actor: Dictionary = snapshot[group][id]
			# Completed long-career records remain in the save, not as hundreds
			# of invisible 3D actors at the hospital exit.
			if snapshot.get("schema_version",0)==3 and group=="patients" and actor.get("phase","") in ["left","abandoned"]:continue
			if not actor.has("cell"):
				continue
			visible_ids[id] = true
			if not actor_views.has(id):
				var view := ActorView.new()
				view.entity_id=id
				view.prefer_simplified=prefer_simplified_characters
				_actor_root.add_child(view)
				actor_views[id] = view
			actor_views[id].appearance_seed=int(snapshot.get("appearance_seed",0))
			actor_views[id].work_target=Vector3.INF
			actor_views[id].presentation_paused=bool(snapshot.get("paused",true)) or snapshot.get("challenge",{}).get("status","running")!="running"
			actor_views[id].presentation_speed=int(snapshot.get("speed",1))
			actor_views[id].presentation_tick=int(snapshot.get("tick",0))
			actor_views[id].consultation_context=ConsultationView.context(projected,id,group=="staff")
			actor_views[id].interaction_context=FacilityInteraction.context(projected,id,group=="staff")
			var work_actor:Dictionary=projected.get(group,{}).get(id,actor)
			var assigned: Dictionary=rooms.get(work_actor.get("room_id",""),{})
			if not assigned.is_empty():
				var target:=Vector3.ZERO
				var equipment:Array=assigned.equipment_cells
				if assigned.get("ruleset","")=="full-hospital-v1":
					var station:Dictionary=assigned.get("facility_geometries",{}).get(work_actor.get("facility_id",""),{})
					if station.is_empty():
						for item:Dictionary in assigned.get("layout",{}).get("facilities",[]):
							if item.id==work_actor.get("facility_id",""):station=FacilityLayout.facility_geometry(assigned,item);break
					equipment=station.get("equipment_cells",[])
				for cell:int in equipment:target+=cell_position(cell)
				if not equipment.is_empty():actor_views[id].work_target=target/equipment.size()
			actor_views[id].present(actor,group == "staff")
	for id in actor_views.keys():
		if not visible_ids.has(id):
			_remove_view(actor_views,id)
	_sync_consult_chairs(rooms,slots)

func show_campaign_preview(record:Dictionary) -> void:
	if not is_inside_tree():return
	if not is_instance_valid(_campaign_preview):
		_campaign_preview=CampaignRoomView.new()
		_campaign_preview.name="CampaignConstructionPreview"
		add_child(_campaign_preview)
	var copy:Dictionary=record.duplicate(true)
	copy["campaign_preview"]=true
	_campaign_preview.present(copy,{},{})
	_campaign_preview.visible=true
	_campaign_preview.set_meta("visual_only_not_navigation",true)

func clear_campaign_preview() -> void:
	if not is_instance_valid(_campaign_preview):return
	remove_child(_campaign_preview);_campaign_preview.queue_free();_campaign_preview=null

func set_wall_preview(proposal: Dictionary) -> void:
	# Only display edges are retained. Draft rooms never enter room_views or picking.
	var draft: Dictionary=_preview_boundary(proposal)
	if draft==_wall_preview:return
	_wall_preview=draft
	if _room_root==null:return
	_present_rooms(_last_rooms,_last_slots)
	# A changed wall may rebuild a room's chairs; keep the current actor-driven
	# chair state without re-presenting actors or restarting their movement.
	_sync_consult_chairs(_last_rooms,_last_slots)

func _preview_boundary(proposal: Dictionary) -> Dictionary:
	var origin: int=proposal.get("origin_cell",-1)
	var layout: Dictionary=proposal.get("layout",{})
	var width: int=layout.get("width",0)
	var height: int=layout.get("height",0)
	if origin<0 or width<1 or height<1 or origin%24<1 or origin%24+width>23 or origin/24<1 or origin/24+height>17:return {}
	for y in range(height):
		if origin/24+y in [8,9]:return {}
	var door_edges: Dictionary={}
	for spec: Dictionary in RoomOpenings.door_specs(layout):
		var edge: Array=RoomOpenings.global_edge(origin,layout,spec)
		if edge.size()==2:door_edges[_wall_edge_key(edge)]=true
	var windows: Dictionary={}
	for spec: Dictionary in RoomOpenings.window_specs(layout):
		var edge: Array=RoomOpenings.global_edge(origin,layout,spec)
		if edge.size()==2:windows[_wall_edge_key(edge)]=true
	var perimeter: Array=[]
	for x in range(width):
		perimeter.append([origin+x,origin+x-24])
		perimeter.append([origin+(height-1)*24+x,origin+height*24+x])
	for y in range(height):
		perimeter.append([origin+y*24,origin+y*24-1])
		perimeter.append([origin+y*24+width-1,origin+y*24+width])
	var edges: Array=[]
	for edge in perimeter:
		if not door_edges.has(_wall_edge_key(edge)):edges.append(edge)
	return {"room_id":proposal.get("room_id",""),"edges":edges,"windows":windows}

static func _wall_edge_key(edge: Array) -> String:
	return "%d:%d"%[mini(edge[0],edge[1]),maxi(edge[0],edge[1])]

func _present_rooms(rooms: Dictionary,slots: Dictionary) -> void:
	_room_cells.clear()
	for id in rooms: _room_cells[id]=rooms[id].cells.duplicate()
	var edge_owners:Dictionary={}
	var window_edges:Dictionary={}
	var editing_id: String=_wall_preview.get("room_id","")
	for id in rooms:
		if id==editing_id:continue
		for edge in rooms[id].wall_edges:
			var key:=_wall_edge_key(edge)
			edge_owners[key]=edge_owners.get(key,0)+1
		for edge: Array in rooms[id].get("window_edges",[]):window_edges[_wall_edge_key(edge)]=true
	for edge in _wall_preview.get("edges",[]):
		var key:=_wall_edge_key(edge)
		edge_owners[key]=edge_owners.get(key,0)+1
	window_edges.merge(_wall_preview.get("windows",{}),true)
	for id in room_views.keys():
		if not rooms.has(id):
			_remove_view(room_views,id)
	for id in rooms:
		var campaign_room:bool=rooms[id].get("ruleset","")=="full-hospital-v1" or rooms[id].get("kind","")=="campaign_department"
		if room_views.has(id) and (room_views[id] is CampaignRoomView)!=campaign_room:_remove_view(room_views,id)
		if not room_views.has(id):
			var room:Node3D=CampaignRoomView.new() if campaign_room else RoomView.new()
			_room_root.add_child(room)
			room_views[id] = room
		var visual_room:Dictionary=rooms[id].duplicate()
		var shared:Dictionary={}
		var visual_windows:Dictionary={}
		for edge in rooms[id].wall_edges:
			var key:=_wall_edge_key(edge)
			if edge_owners.get(key,0)>1:shared[key]=true
			# Adjacent rooms each own their geometric boundary. Mirror a window
			# only in their display copies, so a second solid wall cannot seal it.
			if window_edges.has(key):visual_windows[key]=true
		visual_room.visual_shared_walls=shared
		visual_room.visual_window_edges=visual_windows
		if campaign_room:room_views[id].present(visual_room,slots,_last_facilities)
		else:room_views[id].present(visual_room,slots)

func _sync_consult_chairs(rooms: Dictionary,slots: Dictionary) -> void:
	# Only legacy sprites with a baked chair hide the live geometry. V3 renders
	# people alone and keeps the real chair and its contact shadow visible.
	for room_id in room_views:
		if room_views[room_id] is CampaignRoomView:continue
		var staff_id: String=rooms[room_id].get("staff_id","")
		var patient_id := ""
		for slot in slots.values():
			if slot.get("room_id","")==room_id and not str(slot.get("patient_id","")).is_empty():
				patient_id=slot.patient_id;break
		var staff_ready:=_can_consult(actor_views.get(staff_id))
		var patient_ready:=_can_consult(actor_views.get(patient_id))
		var staff_show:=staff_id.is_empty() or staff_ready
		var patient_show:=patient_id.is_empty() or patient_ready
		room_views[room_id].set_consult_chair_visibility(staff_show,patient_show)
	for actor in actor_views.values():
		if actor.consultation_context.is_empty() or actor._prerendered==null:continue
		if actor._prerendered.clip_name!="Consult":continue
		if not actor._prerendered.embeds_consult_chair():continue
		var context: Dictionary=actor.consultation_context
		if room_views.has(context.room_id):room_views[context.room_id].hide_consult_chair(bool(context.is_staff))


func _can_consult(actor: ActorView) -> bool:
	return actor!=null and ((actor._simplified!=null and actor._simplified.can_consult()) or (actor._prerendered!=null and actor._prerendered.manifest.clips.has("Consult")))

func _remove_view(views: Dictionary, id: String) -> void:
	var view: Node3D = views[id]
	view.get_parent().remove_child(view)
	view.queue_free()
	views.erase(id)

func focus_cell(cell: int) -> void:
	camera_rig.focus_cell(cell)

func focus_room(room:Dictionary) -> void:
	camera_rig.frame_room(room)

func room_at_cell(cell: int) -> String:
	for id in _room_cells:
		if cell in _room_cells[id]: return id
	return ""
