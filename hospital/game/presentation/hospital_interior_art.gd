class_name HospitalInteriorArt
extends RefCounted

# Grid-bound architectural modules shared by built rooms and construction previews.
const SURFACES := preload("res://presentation/room_surface_material.gd")

# Read-only scene decoration. All fixtures attach to literal wall boundaries;
# floor inlays have no standing volume and no prop becomes a navigation obstacle.
const CREAM := Color("f0e6d7")
const TEAL := Color("527b79")
const TEAL_DARK := Color("365d5c")
const BRASS := Color("a18b6d")
const WOOD := Color("a58060")
const PAPER := Color("f7efe2")
const INK := Color("355a5b")
const ROOM_FLOOR_TOP := 0.028
const WALL_HEIGHT := 2.0
const WALL_CREAM := Color("f2e5cf")
const WALL_TEAL := Color("326d70")
const WALL_DARK := Color("244f52")
const WALL_BRASS := Color("b99561")
const ACCENTS := {"reception":Color("a18b6d"),"diagnosis":Color("78958b"),"echo":Color("ad806a"),"motion":Color("739592"),"sensory":Color("b1a082"),"recovery":Color("8d9b7e"),"general_exam":Color("729b8b"),"pharmacy":Color("8d9b69"),"ward":Color("759b96")}
static var _materials: Dictionary = {}
static var _rounded_meshes: Dictionary = {}
static var _beveled_meshes: Dictionary = {}
static var _halo_mesh: ArrayMesh
static var _halo_material: StandardMaterial3D
static var _window_glass_material: StandardMaterial3D
static var _opening_selection_material: StandardMaterial3D

static func build(parent: Node3D, room: Dictionary) -> Dictionary:
	var art := Node3D.new()
	art.name = "InteriorConstruction"
	parent.add_child(art)
	var accent: Color = ACCENTS[room.kind]
	_floor(art,room,accent)
	var result := _architecture(art,parent,room,true)
	_flatten(art,parent,Transform3D.IDENTITY)
	parent.remove_child(art)
	art.free()
	return result

static func build_wall_preview(parent: Node3D, proposal: Dictionary) -> void:
	var layout: Dictionary=proposal.get("layout",{})
	var origin: int=proposal.get("origin_cell",-1)
	var width: int=layout.get("width",0)
	var height: int=layout.get("height",0)
	# Invalid extents remain a red ground draft; never wrap walls into another row.
	if origin<0 or width<1 or height<1 or origin%24<1 or origin%24+width>23 or origin/24<1 or origin/24+height>17:return
	var room: Dictionary={"kind":proposal.kind,"cells":[],"wall_edges":[],"door_cell":-1,"door_outside_cell":-1,"doorways":[],"window_edges":[],"visual_shared_walls":proposal.get("visual_shared_walls",{}),"visual_window_edges":proposal.get("visual_window_edges",{})}
	for y in range(height):
		for x in range(width):room.cells.append(origin+y*24+x)
	var door_edges: Dictionary={}
	for spec: Dictionary in RoomOpenings.door_specs(layout):
		var edge: Array=RoomOpenings.global_edge(origin,layout,spec)
		if edge.size()!=2:continue
		room.doorways.append({"door_cell":edge[0],"door_outside_cell":edge[1]})
		door_edges[_edge_key(edge)]=true
	if not room.doorways.is_empty():
		room.door_cell=room.doorways[0].door_cell
		room.door_outside_cell=room.doorways[0].door_outside_cell
	for spec: Dictionary in RoomOpenings.window_specs(layout):
		var edge: Array=RoomOpenings.global_edge(origin,layout,spec)
		if edge.size()==2:room.window_edges.append(edge)
	var edges: Array=[]
	for x in range(width):
		edges.append([origin+x,origin+x-24])
		edges.append([origin+(height-1)*24+x,origin+height*24+x])
	for y in range(height):
		edges.append([origin+y*24,origin+y*24-1])
		edges.append([origin+y*24+width-1,origin+y*24+width])
	for edge in edges:
		if not door_edges.has(_edge_key(edge)):room.wall_edges.append(edge)
	var preview := Node3D.new()
	preview.name="WallPreviewArchitecture"
	parent.add_child(preview)
	var details := Node3D.new()
	preview.add_child(details)
	var result := _architecture(details,preview,room,false)
	for label: Label3D in result.door_labels:label.text="入口"
	_flatten(details,preview,Transform3D.IDENTITY)
	preview.remove_child(details)
	details.free()
	SceneArtLibrary.batch_static(preview)
	_selected_opening_frame(preview,proposal)

static func _selected_opening_frame(parent: Node3D,proposal: Dictionary) -> void:
	# A transient, depth-tested construction cue. Never added by built-room art,
	# never stored in a room snapshot, and never placed across the clear opening.
	var selected: Variant=proposal.get("visual_selected_opening",{})
	if not selected is Dictionary or selected.get("kind","") not in ["door","window"] or not selected.get("index") is int:return
	var layout: Dictionary=proposal.get("layout",{})
	var specs: Array=RoomOpenings.door_specs(layout) if selected.kind=="door" else RoomOpenings.window_specs(layout)
	var index: int=selected.index
	if index<0 or index>=specs.size():return
	var edge: Array=RoomOpenings.global_edge(proposal.origin_cell,layout,specs[index])
	if edge.size()!=2:return
	var a:=HospitalWorld.cell_position(edge[0])
	var b:=HospitalWorld.cell_position(edge[1])
	var outline:=_plane(parent,(a+b)*.5,(b-a).normalized())
	outline.name="PreviewOpeningSelection"
	if _opening_selection_material==null:
		_opening_selection_material=StandardMaterial3D.new()
		_opening_selection_material.resource_name="OpeningSelectionGold"
		_opening_selection_material.albedo_color=Color("dcb86e")
		_opening_selection_material.roughness=.68
		_opening_selection_material.metallic=.10
		_opening_selection_material.emission_enabled=true
		_opening_selection_material.emission=Color("dcb86e")
		_opening_selection_material.emission_energy_multiplier=.12
	if selected.kind=="door":
		for face in [-1.0,1.0]:
			for x in [-.545,.545]:_opening_selection_edge(outline,Vector3(x,1.03,face*.148),Vector3(.024,2.04,.024))
			_opening_selection_edge(outline,Vector3(0,2.06,face*.148),Vector3(1.114,.024,.024))
	else:
		for face in [-1.0,1.0]:
			for x in [-.458,.458]:_opening_selection_edge(outline,Vector3(x,1.345,face*.178),Vector3(.024,.98,.024))
			for y in [.855,1.835]:_opening_selection_edge(outline,Vector3(0,y,face*.178),Vector3(.94,.024,.024))

static func _opening_selection_edge(parent: Node3D,at: Vector3,size: Vector3) -> void:
	var edge:=_bevel_box(parent,at,size,Color("dcb86e"),.006)
	edge.name="OpeningSelectionEdge"
	edge.material_override=_opening_selection_material
	edge.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

static func _architecture(art: Node3D,parent: Node3D,room: Dictionary,decorate: bool) -> Dictionary:
	var walls: Array[MeshInstance3D] = []
	var back_walls: Array[Dictionary] = []
	var side_walls: Array[Dictionary] = []
	var joints: Dictionary={}
	var doorways: Array=_doorways(room)
	var doors: Array[Vector3]=[]
	for doorway: Dictionary in doorways:doors.append((HospitalWorld.cell_position(doorway.door_cell)+HospitalWorld.cell_position(doorway.door_outside_cell))*.5)
	var windows: Dictionary=room.get("visual_window_edges",{}).duplicate()
	for edge: Array in room.get("window_edges",[]):windows[_edge_key(edge)]=true
	for edge in room.wall_edges:
		var a := HospitalWorld.cell_position(edge[0])
		var b := HospitalWorld.cell_position(edge[1])
		var at := (a+b)*.5
		var inside: Vector3 = a if room.cells.has(edge[0]) else b
		var normal := (inside-at).normalized()
		var edge_key:=_edge_key(edge)
		var near_wall:bool=normal.x<-.5 or normal.z<-.5 or room.get("visual_shared_walls",{}).has(edge_key)
		# Every literal boundary remains a full opaque wall, including near/shared sides.
		# Facing only controls which interior decorations are visible to the camera.
		var height := WALL_HEIGHT
		var window: bool=windows.has(edge_key)
		if window:
			var parts: Array[MeshInstance3D]=_window_wall(_plane(art,at,normal))
			for part: MeshInstance3D in parts:
				part.name="RoomBoundary"
				part.set_meta("wall_profile","clinic-window-v1")
				part.set_meta("wall_edge",edge.duplicate())
				walls.append(part)
		else:
			var size := Vector3(1.0,height,.18) if absf(a.z-b.z)>.1 else Vector3(.18,height,1.0)
			var wall := _wall_section(parent,at+Vector3(0,height*.5,0),size,WALL_CREAM,.025)
			wall.name = "RoomBoundary"
			wall.set_meta("wall_profile","clinic-wall-v2")
			wall.set_meta("wall_edge",edge.duplicate())
			walls.append(wall)
		# A shallow alpha mark anchors the wall to its floor without adding
		# an obstacle or another light/shadow pass. It batches with prop marks.
		var grounding:=ContactShadow.create(Vector2(.53,.21),.12)
		grounding.position=at+normal*.09+Vector3(0,ROOM_FLOOR_TOP+.004,0)
		if absf(normal.x)>.5:grounding.rotation.y=PI*.5
		art.add_child(grounding)
		var panel := _plane(art,at,normal)
		_wall_finish(panel,height)
		var tangent := Vector3.RIGHT if absf(a.z-b.z)>.1 else Vector3.BACK
		for direction in [-1.0,1.0]:
			var point: Vector3 = at+tangent*direction*.5
			var key := Vector2(point.x,point.z)
			if not joints.has(key):joints[key]={"at":point,"height":height,"directions":[]}
			joints[key].height=maxf(joints[key].height,height)
			joints[key].directions.append(tangent)
		if not near_wall and not window:
			if normal.z > .5: back_walls.append({"at":at,"normal":normal})
			elif absf(normal.x)>.5: side_walls.append({"at":at,"normal":normal})
	for joint: Dictionary in joints.values():
		var beside_door := false
		for door: Vector3 in doors:
			if Vector2(joint.at.x-door.x,joint.at.z-door.z).length()<.70:beside_door=true;break
		if beside_door:continue
		var directions: Array=joint.directions
		if directions.size()==2 and absf(directions[0].dot(directions[1]))>.9:continue
		_corner_post(art,joint.at,joint.height)
	back_walls.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a.at.x < b.at.x)
	side_walls.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a.at.z < b.at.z)
	if decorate:_decorate_walls(art,room,back_walls,side_walls,doors)
	var result: Dictionary={"walls":walls,"label":null,"lamp":null,"door_labels":[],"door_lamps":[]}
	for index in range(doorways.size()):
		var doorway: Dictionary=doorways[index]
		var outward := (HospitalWorld.cell_position(doorway.door_outside_cell)-HospitalWorld.cell_position(doorway.door_cell)).normalized()
		var door_result := _doorway(_plane(art,doors[index],outward))
		if index>0:
			door_result.label.name="WallMountedRoomName%d"%index
			door_result.lamp.name="DoorStatusLamp%d"%index
		result.door_labels.append(door_result.label)
		result.door_lamps.append(door_result.lamp)
	if not result.door_labels.is_empty():
		result.label=result.door_labels[0]
		result.lamp=result.door_lamps[0]
	return result

static func _edge_key(edge: Array) -> String:
	return "%d:%d"%[mini(edge[0],edge[1]),maxi(edge[0],edge[1])]

static func _doorways(room: Dictionary) -> Array:
	if room.has("doorways"):return room.doorways
	if room.get("door_cell",-1)>=0 and room.get("door_outside_cell",-1)>=0:return [{"door_cell":room.door_cell,"door_outside_cell":room.door_outside_cell}]
	return []

static func _window_wall(panel: Node3D) -> Array[MeshInstance3D]:
	# A literal opening, not a dark decal. The room boundary is retained below,
	# above and on both sides; all four world-facing orientations use this kit.
	var parts: Array[MeshInstance3D]=[]
	parts.append(_wall_section(panel,Vector3(0,.445,0),Vector3(1.0,.89,.18),WALL_CREAM,.018))
	parts.append(_wall_section(panel,Vector3(0,1.90,0),Vector3(1.0,.20,.18),WALL_CREAM,.018))
	for x in [-.44,.44]:parts.append(_wall_section(panel,Vector3(x,1.345,0),Vector3(.12,.91,.18),WALL_CREAM,.016))
	# Teal casing and fine brass beads have real depth and read on either face
	# of a shared wall. Their clear middle never fills the window aperture.
	for x in [-.385,.385]:
		_bevel_box(panel,Vector3(x,1.345,0),Vector3(.07,.91,.245),WALL_TEAL,.018)
		for face in [-1.0,1.0]:_bevel_box(panel,Vector3(x,1.345,face*.128),Vector3(.014,.83,.012),WALL_BRASS,.004)
	for y in [.91,1.78]:
		_bevel_box(panel,Vector3(0,y,0),Vector3(.84,.07,.245),WALL_TEAL,.018)
		for face in [-1.0,1.0]:_bevel_box(panel,Vector3(0,y,face*.128),Vector3(.76,.014,.012),WALL_BRASS,.004)
	_bevel_box(panel,Vector3(0,.895,0),Vector3(.94,.07,.31),WALL_CREAM,.024)
	if _window_glass_material==null:
		_window_glass_material=StandardMaterial3D.new()
		_window_glass_material.resource_name="ClinicWindowGlass"
		_window_glass_material.albedo_color=Color(.64,.85,.89,.28)
		_window_glass_material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
		_window_glass_material.cull_mode=BaseMaterial3D.CULL_DISABLED
		_window_glass_material.roughness=.28
		_window_glass_material.metallic_specular=.38
	var mesh:=QuadMesh.new()
	mesh.size=Vector2(.70,.77)
	var pane:=_part(panel,mesh,Vector3(0,1.345,0),WALL_CREAM)
	pane.name="RoomWindowGlass"
	pane.material_override=_window_glass_material
	pane.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return parts

static func _wall_finish(panel: Node3D,height: float) -> void:
	var dado_top := .60
	_wall_section(panel,Vector3(0,dado_top*.5,0),Vector3(1.0,dado_top,.19),WALL_TEAL,.018)
	_wall_section(panel,Vector3(0,.055,0),Vector3(1.0,.09,.20),WALL_DARK,.014)
	_wall_section(panel,Vector3(0,dado_top,0),Vector3(1.0,.065,.20),WALL_TEAL.lightened(.045),.018)
	_wall_section(panel,Vector3(0,dado_top+.041,0),Vector3(1.0,.016,.20),WALL_BRASS,.005)
	_wall_section(panel,Vector3(0,.345,.095),Vector3(.82,.36,.008),WALL_TEAL.lightened(.035),.022)
	for x in [-.46,.46]:
		_bevel_box(panel,Vector3(x,.34,.095),Vector3(.018,.43,.010),WALL_TEAL.darkened(.05),.004)
	_bevel_box(panel,Vector3(0,.708,.087),Vector3(1.0,.034,.026),WOOD,.007)
	_bevel_box(panel,Vector3(0,.731,.091),Vector3(1.0,.010,.018),WALL_BRASS,.004)
	_wall_section(panel,Vector3(0,height+.02,0),Vector3(1.0,.085,.20),WALL_CREAM.lightened(.025),.027)

static func _corner_post(parent: Node3D,at: Vector3,height: float) -> void:
	var dado_top := .60 if height>1.0 else .31
	var base := _bevel_box(parent,at+Vector3(0,dado_top*.5,0),Vector3(.208,dado_top,.208),WALL_TEAL,.018)
	base.material_override=SURFACES.wall_material(WALL_TEAL)
	if height>1.0:
		var shaft := _bevel_box(parent,at+Vector3(0,(height+dado_top)*.5,0),Vector3(.194,height-dado_top,.194),WALL_CREAM,.017)
		shaft.material_override=SURFACES.wall_material(WALL_CREAM)
	_bevel_box(parent,at+Vector3(0,dado_top+.04,0),Vector3(.222,.018,.222),WALL_BRASS,.005)
	var crown := _bevel_box(parent,at+Vector3(0,height+.02,0),Vector3(.23,.085,.23),WALL_CREAM.lightened(.025),.024)
	crown.material_override=SURFACES.wall_material(WALL_CREAM.lightened(.025))

static func _decorate_walls(parent: Node3D,room: Dictionary,back: Array[Dictionary],side: Array[Dictionary],doors: Array[Vector3]) -> void:
	var candidates: Array[Dictionary]=[]
	for entry: Dictionary in back+side:
		# Keep wall-mounted props away from the actual machine body. A clock
		# or rail placed directly behind a tall apparatus would intersect its
		# fixed-view depth proxy and appear painted across the machine itself.
		var inside:Vector3=entry.at+entry.normal*.5
		var cell:=roundi(inside.z)*24+roundi(inside.x)
		if cell in room.get("equipment_cells",[]):continue
		var beside_door:=false
		for door: Vector3 in doors:
			if Vector2(entry.at.x-door.x,entry.at.z-door.z).length()<=1.15:beside_door=true;break
		if not beside_door:candidates.append(entry)
	var used: Dictionary={}
	var lamps: Array[Vector3]=[]
	# A few wall-mounted lights scale with wall length, including player-built rooms.
	for index in range(candidates.size()-1,-1,-1):
		var entry: Dictionary=candidates[index]
		var separated := true
		for at: Vector3 in lamps:
			if at.distance_to(entry.at)<3.2:separated=false
		if not separated or lamps.size()>=6:continue
		_sconce(_plane(parent,entry.at,entry.normal))
		used[entry.at]=true
		lamps.append(entry.at)
	var accent: Color=ACCENTS[room.kind]
	var remaining: Array[Dictionary]=[]
	for entry: Dictionary in candidates:
		if not used.has(entry.at):remaining.append(entry)
	if not remaining.is_empty():
		var entry: Dictionary=remaining.pop_at(remaining.size()/2)
		_clock(_plane(parent,entry.at+entry.normal*.03,entry.normal))
	if not remaining.is_empty():
		var entry: Dictionary=remaining.pop_front()
		_picture(_plane(parent,entry.at+entry.normal*.03,entry.normal),room.kind,accent)
	if not remaining.is_empty():
		var entry: Dictionary=remaining.pop_back()
		_planter(_plane(parent,entry.at+entry.normal*.03,entry.normal),accent)
	if not remaining.is_empty():
		var entry: Dictionary=remaining.pop_front()
		_wall_specialty(_plane(parent,entry.at+entry.normal*.03,entry.normal),room.kind,accent)

static func _floor(parent: Node3D, room: Dictionary, accent: Color) -> void:
	for cell in room.cells:
		var at := HospitalWorld.cell_position(cell)
		var parity: int = (cell%24+cell/24)%2
		var tint := Color("e7e0d2") if parity==0 else Color("e5decf")
		# Narrow seams and close-value tiles leave the attention on staff and equipment.
		var tile := _box(parent,at+Vector3(0,ROOM_FLOOR_TOP*.5,0),Vector3(.994,ROOM_FLOOR_TOP,.994),tint)
		tile.material_override=SURFACES.floor_material()
	# A flat entry welcome tile keeps the threshold distinct without suggesting a blocked step.
	for doorway: Dictionary in _doorways(room):
		var door := HospitalWorld.cell_position(doorway.door_cell)
		var threshold := _box(parent,door+Vector3(0,.033,0),Vector3(.72,.008,.72),accent.lerp(CREAM,.78))
		threshold.material_override=SURFACES.floor_material()

static func _doorway(parent: Node3D) -> Dictionary:
	# The 0.82m wide / 1.76m high opening contains no door leaf or hanging sign.
	for side in [-1,1]:
		# Recess the inner jamb face 1 cm behind a perpendicular corner wall.
		# Its outer edge stays at .52, so first/last-cell doors do not acquire
		# coplanar vertical faces or a narrower walking aperture.
		_bevel_box(parent,Vector3(side*.470,.89,0),Vector3(.10,1.78,.21),WALL_TEAL,.035)
		_box(parent,Vector3(side*.470,.11,.005),Vector3(.115,.20,.19),WALL_BRASS)
		_bevel_box(parent,Vector3(side*.465,1.735,0),Vector3(.13,.18,.22),WALL_TEAL,.045)
		_box(parent,Vector3(side*.420,.92,.095),Vector3(.014,1.56,.018),WALL_BRASS)
	_bevel_box(parent,Vector3(0,1.83,0),Vector3(1.04,.16,.22),WALL_TEAL,.055)
	var crown := _bevel_box(parent,Vector3(0,1.948,.025),Vector3(.96,.20,.16),WALL_CREAM,.045)
	crown.material_override=SURFACES.wall_material(WALL_CREAM)
	_round_box(parent,Vector3(0,1.948,.101),Vector3(.89,.145,.018),WALL_DARK,.035)
	_round_box(parent,Vector3(0,1.948,.113),Vector3(.81,.112,.008),WALL_TEAL,.025)
	var label := Label3D.new()
	label.name = "WallMountedRoomName"
	label.font = load("res://ui/theme.tres").default_font
	label.font_size = 26
	label.pixel_size = .0023
	label.modulate = PAPER
	label.outline_size = 0
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	label.no_depth_test = false
	label.position = Vector3(0,1.947,.117)
	parent.add_child(label)
	var lamp := _ball(parent,Vector3(.41,1.945,.127),Vector3(.065,.065,.028),Color("9dd1ab"))
	lamp.name = "DoorStatusLamp"
	return {"label":label,"lamp":lamp}

static func _clock(parent: Node3D) -> void:
	var pivot := Node3D.new()
	parent.add_child(pivot)
	pivot.position = Vector3(0,1.17,.065)
	_disk(pivot,Vector3.ZERO,.25,.055,TEAL)
	_disk(pivot,Vector3(0,0,.035),.224,.022,BRASS)
	_disk(pivot,Vector3(0,0,.050),.209,.018,PAPER)
	for i in range(12):
		var angle := float(i)*TAU/12.0
		var marker := _box(pivot,Vector3(sin(angle)*.176,cos(angle)*.176,.063),Vector3(.013,.030 if i%3==0 else .018,.006),BRASS)
		marker.rotation.z = -angle
	var hour := _box(pivot,Vector3(-.036,.035,.074),Vector3(.018,.112,.008),INK)
	hour.rotation.z = .8
	var minute := _box(pivot,Vector3(.05,.044,.078),Vector3(.012,.148,.008),INK)
	minute.rotation.z = -.86
	_disk(pivot,Vector3(0,0,.087),.022,.012,Color("b66c4e"))

static func _sconce(parent: Node3D) -> void:
	_sconce_glow(parent)
	_disk(parent,Vector3(0,1.23,.115),.09,.045,WALL_BRASS)
	_round_box(parent,Vector3(0,1.24,.16),Vector3(.035,.055,.12),WALL_BRASS,.012)
	# Keep the opaque housing behind the warm glass without extending into the aisle.
	_round_box(parent,Vector3(0,1.12,.18),Vector3(.19,.25,.075),WALL_BRASS,.045)
	var glass := _round_box(parent,Vector3(0,1.12,.20),Vector3(.145,.19,.045),Color("ffe5a4"),.04)
	glass.material_override = _material(Color("ffe5a4"),true)
	_disk(parent,Vector3(0,1.28,.18),.05,.022,WALL_BRASS)

static func _sconce_glow(parent: Node3D) -> void:
	# Native vertex-colour falloff, no bitmap, extra light or shadow pass.
	# The transparent disc stays on the wall, behind the opaque lamp housing.
	if _halo_mesh==null:
		var builder := SurfaceTool.new()
		builder.begin(Mesh.PRIMITIVE_TRIANGLES)
		var radii := [0.0,.30,.67,1.0]
		var alpha := [.16,.12,.045,0.0]
		for ring in range(3):
			for step in range(24):
				var a := TAU*step/24.0
				var b := TAU*(step+1)/24.0
				var points := [Vector2(cos(a),sin(a))*radii[ring],Vector2(cos(b),sin(b))*radii[ring],Vector2(cos(b),sin(b))*radii[ring+1],Vector2(cos(a),sin(a))*radii[ring+1]]
				for index in [0,2,1,0,3,2]:
					builder.set_normal(Vector3.FORWARD)
					builder.set_color(Color(1.0,.79,.42,alpha[ring] if index<2 else alpha[ring+1]))
					builder.add_vertex(Vector3(points[index].x*.40,points[index].y*.52,0))
		builder.index()
		_halo_mesh=builder.commit()
		_halo_material=StandardMaterial3D.new()
		_halo_material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		_halo_material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
		_halo_material.cull_mode=BaseMaterial3D.CULL_DISABLED
		_halo_material.vertex_color_use_as_albedo=true
		_halo_material.emission_enabled=true
		_halo_material.emission=Color("ffd79a")
		_halo_material.emission_energy_multiplier=.12
	var halo := MeshInstance3D.new()
	halo.name="WallLightFalloff"
	halo.mesh=_halo_mesh
	halo.material_override=_halo_material
	halo.position=Vector3(0,1.12,.099)
	halo.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(halo)

static func _picture(parent: Node3D, kind: String, accent: Color) -> void:
	var picture := Node3D.new()
	parent.add_child(picture)
	picture.position = Vector3(0,1.12,.064)
	_round_box(picture,Vector3.ZERO,Vector3(.61,.67,.035),WOOD,.025)
	_round_box(picture,Vector3(0,0,.023),Vector3(.558,.616,.016),BRASS,.018)
	_box(picture,Vector3(0,0,.035),Vector3(.515,.574,.012),PAPER)
	_motif(picture,kind,accent,.046)

static func _motif(parent: Node3D, kind: String, accent: Color, depth: float) -> void:
	if kind == "reception":
		# A small hospital crest and orderly information bars above the reception counter.
		_disk(parent,Vector3(0,.085,depth),.135,.009,TEAL)
		_box(parent,Vector3(0,.085,depth+.008),Vector3(.06,.18,.008),PAPER)
		_box(parent,Vector3(0,.085,depth+.009),Vector3(.18,.06,.008),PAPER)
		for i in range(3): _box(parent,Vector3(0,-.12-i*.05,depth),Vector3(.32-i*.045,.013,.008),accent)
	elif kind == "diagnosis":
		# An illustrated eye chart: actual raised glyphs, with no unreadable text texture.
		for row in range(3):
			var width := .095-float(row)*.019
			for column in range(row+1):
				var glyph := Node3D.new()
				parent.add_child(glyph)
				glyph.position = Vector3((column-float(row)*.5)*.13,.17-row*.135,depth)
				glyph.rotation.z = float((row+column)%4)*PI*.5
				_box(glyph,Vector3(-width*.4,0,0),Vector3(width*.2,width,.008),INK)
				for line in [-1,0,1]: _box(glyph,Vector3(0,line*width*.4,0),Vector3(width,width*.18,.008),INK)
	elif kind == "echo":
		for i in range(9):
			var height := .06+.18*absf(sin(float(i)*.9))
			_round_box(parent,Vector3((i-4)*.047,0,depth),Vector3(.022,height,.012),accent,.01)
		_box(parent,Vector3(0,-.21,depth),Vector3(.36,.015,.009),TEAL)
	elif kind == "motion":
		for side in [-1,1]:
			var foot := _ball(parent,Vector3(side*.09,side*.06,depth),Vector3(.095,.23,.012),TEAL if side<0 else accent)
			foot.rotation.z = side*-.25
			for toe in range(3): _disk(parent,Vector3(side*.09+(toe-1)*.029,side*.06+.13,depth),.016,.008,accent)
		_box(parent,Vector3(0,-.22,depth),Vector3(.34,.016,.009),BRASS)
	elif kind == "sensory":
		for i in range(3):
			_disk(parent,Vector3((i-1)*.13,.095,depth),.063,.012,[Color("b95843"),Color("5e9296"),Color("cfac56")][i])
		for i in range(4):
			var stripe := _box(parent,Vector3((i-1.5)*.073,-.11,depth),Vector3(.035,.16,.009),accent if i%2==0 else TEAL)
			stripe.rotation.z = -.3
	else:
		# Botanical print repeats the living leaf shapes in the approved recovery room.
		_box(parent,Vector3(0,0,depth),Vector3(.018,.40,.01),WOOD)
		for i in range(5):
			var sign_value := -1.0 if i%2==0 else 1.0
			var leaf := _ball(parent,Vector3(sign_value*.075,-.12+i*.066,depth+.008),Vector3(.16,.065,.018),accent if i%2==0 else TEAL)
			leaf.rotation.z = sign_value*.5

static func _wall_specialty(parent: Node3D, kind: String, accent: Color) -> void:
	if kind == "echo":
		for i in range(5):
			_round_box(parent,Vector3((i-2)*.105,1.08,.070),Vector3(.07,.56,.075),TEAL_DARK if i%2==0 else WOOD,.025)
	elif kind == "motion":
		# Therapy wall rail is confined to the wall strip, never a freestanding barrier.
		for x in [-.25,.25]: _box(parent,Vector3(x,.78,.07),Vector3(.035,.14,.08),BRASS)
		_round_box(parent,Vector3(0,.84,.115),Vector3(.66,.045,.045),WOOD,.018)
		for i in range(3): _disk(parent,Vector3((i-1)*.13,1.16,.065),.04,.02,accent)
	elif kind == "sensory":
		for i in range(3):
			_round_box(parent,Vector3((i-1)*.16,1.13,.07),Vector3(.12,.31,.035),[Color("b95e49"),Color("5e9394"),Color("ccaa5c")][i],.025)
	else:
		_round_box(parent,Vector3(0,.96,.075),Vector3(.60,.045,.12),WOOD,.015)
		for i in range(4):
			var book := _box(parent,Vector3((i-1.5)*.075,1.065,.075),Vector3(.05,.17+float(i%2)*.035,.085),accent if i%2==0 else TEAL)
			book.rotation.z = .10 if i==3 else 0.0
			_box(parent,Vector3((i-1.5)*.075,1.06,.121),Vector3(.032,.009,.005),PAPER)

static func _planter(parent: Node3D, accent: Color) -> void:
	# A wall-mounted half-depth planter, not a pot planted in a navigable floor cell.
	_round_box(parent,Vector3(0,.83,.065),Vector3(.43,.22,.13),CREAM,.04)
	_box(parent,Vector3(0,.91,.138),Vector3(.39,.025,.018),BRASS)
	_box(parent,Vector3(0,.925,.065),Vector3(.34,.018,.105),Color("66533d"))
	for i in range(7):
		var x := (i-3)*.051
		var leaf := _ball(parent,Vector3(x,1.045+(.075 if i%2==0 else 0),.079),Vector3(.105,.25,.055),Color("527847") if i%2==0 else Color("789658"))
		leaf.rotation.z = -x*3.5
	_box(parent,Vector3(0,.75,.137),Vector3(.16,.045,.009),accent)

static func _plane(parent: Node3D, at: Vector3, normal: Vector3) -> Node3D:
	var plane := Node3D.new()
	parent.add_child(plane)
	plane.position = at
	plane.rotation.y = atan2(normal.x,normal.z)
	return plane

static func _material(color: Color, glow := false) -> StandardMaterial3D:
	var key := color.to_html()+str(glow)
	if not _materials.has(key):
		var result := StandardMaterial3D.new()
		result.albedo_color = color
		result.roughness = .72 if color in [TEAL,TEAL_DARK,WALL_TEAL,WALL_DARK] else .65 if color in [BRASS,WALL_BRASS] else .86
		result.metallic = .12 if color in [BRASS,WALL_BRASS] else .0
		result.metallic_specular = .20
		if glow:
			result.emission_enabled = true
			result.emission = color
			result.emission_energy_multiplier = .42
		_materials[key] = result
	return _materials[key]

static func _part(parent: Node3D, mesh: Mesh, at: Vector3, color: Color) -> MeshInstance3D:
	var item := MeshInstance3D.new()
	item.mesh = mesh
	item.position = at
	item.material_override = _material(color)
	item.set_meta("hospital_interior",true)
	parent.add_child(item)
	return item

static func _box(parent: Node3D, at: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _part(parent,mesh,at,color)

static func _round_box(parent: Node3D, at: Vector3, size: Vector3, color: Color, radius: float) -> MeshInstance3D:
	# Rounded XY silhouette extruded along Z; 12 edge facets, shared meshes and no subdivision.
	var key := str(size)+":"+str(radius)
	if not _rounded_meshes.has(key):
		var r := minf(radius,minf(size.x,size.y)*.5)
		var outline: Array[Vector2] = []
		for corner in range(4):
			var sign_x := 1.0 if corner in [0,3] else -1.0
			var sign_y := 1.0 if corner in [0,1] else -1.0
			var center := Vector2(sign_x*(size.x*.5-r),sign_y*(size.y*.5-r))
			for step in range(4):
				var angle := float(corner)*PI*.5+float(step)*PI/6.0
				outline.append(center+Vector2(cos(angle),sin(angle))*r)
		var builder := SurfaceTool.new()
		builder.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in range(outline.size()):
			var a: Vector2 = outline[i]
			var b: Vector2 = outline[(i+1)%outline.size()]
			_triangle(builder,Vector3(0,0,size.z*.5),Vector3(a.x,a.y,size.z*.5),Vector3(b.x,b.y,size.z*.5))
			_triangle(builder,Vector3(0,0,-size.z*.5),Vector3(b.x,b.y,-size.z*.5),Vector3(a.x,a.y,-size.z*.5))
			_triangle(builder,Vector3(a.x,a.y,size.z*.5),Vector3(a.x,a.y,-size.z*.5),Vector3(b.x,b.y,-size.z*.5))
			_triangle(builder,Vector3(a.x,a.y,size.z*.5),Vector3(b.x,b.y,-size.z*.5),Vector3(b.x,b.y,size.z*.5))
		# All architectural sources must be indexed before same-material batching.
		# SurfaceTool.append_from preserves a mixed batch's existing index buffer,
		# leaving non-indexed source vertices unreachable when BoxMesh is also present.
		builder.index()
		_rounded_meshes[key] = builder.commit()
	return _part(parent,_rounded_meshes[key],at,color)

static func _bevel_box(parent: Node3D, at: Vector3, size: Vector3, color: Color, radius: float) -> MeshInstance3D:
	# A shared, indexed rounded cuboid gives visible wall/casing edges real depth.
	# Unlike the flat XY trim, all twelve edges and eight corners carry normals.
	var key := str(size)+":"+str(radius)
	if not _beveled_meshes.has(key):
		var half := size*.5
		var r := minf(radius,minf(half.x,minf(half.y,half.z)))
		var inner := half-Vector3.ONE*r
		var builder := SurfaceTool.new()
		builder.begin(Mesh.PRIMITIVE_TRIANGLES)
		for axis in range(3):
			var u := (axis+1)%3
			var v := (axis+2)%3
			var us := [-half[u],-inner[u],inner[u],half[u]]
			var vs := [-half[v],-inner[v],inner[v],half[v]]
			for side in [-1.0,1.0]:
				for i in range(3):
					for j in range(3):
						var corners: Array[Vector3] = []
						var normals: Array[Vector3] = []
						for pair in [[i,j],[i+1,j],[i+1,j+1],[i,j+1]]:
							var p := Vector3.ZERO
							p[axis]=side*half[axis];p[u]=us[pair[0]];p[v]=vs[pair[1]]
							var core := p.clamp(-inner,inner)
							var normal := (p-core).normalized()
							corners.append(core+normal*r);normals.append(normal)
						for index in ([0,2,1,0,3,2] if side>0 else [0,1,2,0,2,3]):
							builder.set_normal(normals[index]);builder.add_vertex(corners[index])
		builder.index()
		_beveled_meshes[key]=builder.commit()
	return _part(parent,_beveled_meshes[key],at,color)

static func _wall_section(parent: Node3D, at: Vector3, size: Vector3, color: Color, radius: float) -> MeshInstance3D:
	# Round the cross-section, keeping the adjoining cell ends flush. Rounding
	# every segment end would draw a vertical seam through an otherwise solid wall.
	var item: MeshInstance3D
	if size.x>size.z:
		item=_round_box(parent,at,Vector3(size.z,size.y,size.x),color,radius)
		item.rotation.y=PI*.5
	else:
		item=_round_box(parent,at,size,color,radius)
	item.material_override=SURFACES.wall_material(color)
	return item

static func _triangle(builder: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	# Godot front faces use clockwise winding.
	var normal := (b-a).cross(c-a).normalized()
	for vertex in [a,c,b]:
		builder.set_normal(normal)
		builder.add_vertex(vertex)

static func _ball(parent: Node3D, at: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = .5
	mesh.height = 1.0
	mesh.radial_segments = 10
	mesh.rings = 4
	var item := _part(parent,mesh,at,color)
	item.scale = size
	return item

static func _disk(parent: Node3D, at: Vector3, radius: float, depth: float, color: Color) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = depth
	mesh.radial_segments = 20
	var item := _part(parent,mesh,at,color)
	item.rotation.x = PI*.5
	return item

static func _flatten(node: Node3D, target: Node3D, accumulated: Transform3D) -> void:
	for child in node.get_children():
		var transform_value: Transform3D = accumulated*child.transform
		if child is MeshInstance3D or child is Label3D:
			node.remove_child(child)
			target.add_child(child)
			child.transform = transform_value
		else:
			_flatten(child,target,transform_value)
