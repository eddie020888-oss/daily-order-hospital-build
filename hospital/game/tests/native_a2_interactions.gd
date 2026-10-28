extends RefCounted

# Test-only driver: card selection is a UI projection; only the explicit
# start action opens the authoritative four-step free-construction draft.
static func select_card(hud:HospitalHud,kind:String) -> bool:
	if not hud._construction_catalog_open():hud.controls.build.pressed.emit()
	var key:String="build_"+kind
	if not hud.controls.has(key):return false
	var ids:Array=hud.session.catalog.rooms.keys()
	var target_page:int=int(ids.find(kind)/BuildPalette.PAGE_SIZE)
	for _attempt:int in range(ids.size()):
		if hud.palette.page==target_page:break
		hud.controls["facility_next" if hud.palette.page<target_page else "facility_previous"].pressed.emit()
	if hud.palette.page!=target_page:return false
	var card:Button=hud.controls[key]
	if card.disabled:return false
	card.pressed.emit()
	return hud.palette.selected_kind==kind

static func begin_build(hud:HospitalHud,kind:String) -> bool:
	if not select_card(hud,kind) or hud.controls.build_start.disabled:return false
	hud.controls.build_start.pressed.emit()
	return hud.touch.free_build!=null and hud.touch.free_build.kind==kind

# Find a small genuine layout without spending, unlocking, or editing state.
# The production local validator and public preview approve each candidate.
static func fixture(session:GameSession,kind:String,preferred_origin:int) -> Dictionary:
	var minimum:Vector2i=EquipmentFootprints.minimum_room(kind)
	if minimum==Vector2i.ZERO:return {}
	var dimensions:Array[Vector2i]=[minimum]
	if minimum.x!=minimum.y:dimensions.append(Vector2i(minimum.y,minimum.x))
	var layouts:Array[Dictionary]=[]
	for dimensions_value:Vector2i in dimensions:
		var chosen:Dictionary={}
		for rotation:int in range(4):
			for y:int in range(dimensions_value.y):
				for x:int in range(dimensions_value.x):
					for offset:int in range(dimensions_value.x):
						var candidate:Dictionary={"width":dimensions_value.x,"height":dimensions_value.y,"door":{"side":"south","offset":offset},"equipment":{"x":x,"y":y,"rotation":rotation},"furniture":[],"footprint_version":2}
						if FreeRoomLayout.validate(kind,candidate)=="":chosen=candidate;break
					if not chosen.is_empty():break
				if not chosen.is_empty():break
			if not chosen.is_empty():break
		if not chosen.is_empty():layouts.append(chosen)
	var origins:Array[int]=[preferred_origin]
	for cell:int in range(432):
		if cell!=preferred_origin:origins.append(cell)
	var snapshot:Dictionary=session.sim.snapshot()
	for origin:int in origins:
		for layout:Dictionary in layouts:
			if not _clear_bounds(snapshot,origin,layout):continue
			var proposal:Dictionary={"kind":kind,"origin_cell":origin,"rotation":0,"layout":layout.duplicate(true)}
			if session.preview(proposal).ok:return proposal
	return {}

static func _clear_bounds(snapshot:Dictionary,origin:int,layout:Dictionary) -> bool:
	for y:int in range(layout.height):
		for x:int in range(layout.width):
			var gx:int=origin%24+x
			var gy:int=int(origin/24)+y
			if gx<=0 or gx>=23 or gy<=0 or gy>=17 or gy in [8,9]:return false
			for room:Dictionary in snapshot.rooms.values():
				if gy*24+gx in room.cells:return false
	return true

static func door_cell(proposal:Dictionary) -> int:
	var layout:Dictionary=proposal.layout
	return proposal.origin_cell+(layout.height-1)*24+layout.door.offset

static func equipment_cell(proposal:Dictionary) -> int:
	return proposal.origin_cell+proposal.layout.equipment.y*24+proposal.layout.equipment.x

# Synchronous regression driver, deliberately emitting the same real buttons
# and cell choices as a player. Capture companions use real ScreenTouch instead.
static func prepare_build(hud:HospitalHud,kind:String,origin:int) -> Dictionary:
	var proposal:Dictionary=fixture(hud.session,kind,origin)
	if proposal.is_empty() or not begin_build(hud,kind):return {}
	hud.touch.choose_cell(proposal.origin_cell)
	hud.touch.choose_cell(proposal.origin_cell+proposal.layout.width-1+(proposal.layout.height-1)*24)
	hud.controls.confirm.pressed.emit()
	hud.touch.choose_cell(door_cell(proposal))
	hud.controls.confirm.pressed.emit()
	hud.touch.choose_cell(equipment_cell(proposal))
	for _i:int in range(proposal.layout.equipment.rotation):hud.controls.rotate.pressed.emit()
	hud.controls.confirm.pressed.emit()
	return proposal if hud.touch.free_build!=null and hud.touch.free_build.step==3 and not hud.controls.confirm.disabled else {}

# Renderer companions supply their existing tap driver. Alignment and GUI
# review use parsed ScreenTouch; legacy capture_ui uses signal-driven buttons.
static func begin_native(hud:HospitalHud,kind:String,tap:Callable) -> bool:
	if not hud.controls.has("build_"+kind):return false
	if not hud._construction_catalog_open():await tap.call(hud.controls.build)
	var ids:Array=hud.session.catalog.rooms.keys()
	var target_page:int=int(ids.find(kind)/BuildPalette.PAGE_SIZE)
	for _attempt:int in range(ids.size()):
		if hud.palette.page==target_page:break
		await tap.call(hud.controls["facility_next" if hud.palette.page<target_page else "facility_previous"])
	if hud.palette.page!=target_page:return false
	var card:Button=hud.controls["build_"+kind]
	if card.disabled:return false
	await tap.call(card)
	if hud.controls.build_start.disabled:return false
	await tap.call(hud.controls.build_start)
	return hud.touch.free_build!=null and hud.touch.free_build.kind==kind

static func prepare_native(hud:HospitalHud,kind:String,origin:int,tap:Callable,floor_tap:Callable) -> Dictionary:
	var proposal:Dictionary=fixture(hud.session,kind,origin)
	if proposal.is_empty():return {}
	var began:bool=await begin_native(hud,kind,tap)
	if not began:return {}
	return await finish_native(hud,proposal,tap,floor_tap)

static func finish_native(hud:HospitalHud,proposal:Dictionary,tap:Callable,floor_tap:Callable,first_corner_chosen:bool=false) -> Dictionary:
	if not first_corner_chosen:await floor_tap.call(proposal.origin_cell)
	await floor_tap.call(proposal.origin_cell+proposal.layout.width-1+(proposal.layout.height-1)*24)
	await tap.call(hud.controls.confirm)
	await floor_tap.call(door_cell(proposal))
	await tap.call(hud.controls.confirm)
	await floor_tap.call(equipment_cell(proposal))
	for _i:int in range(proposal.layout.equipment.rotation):await tap.call(hud.controls.rotate)
	await tap.call(hud.controls.confirm)
	return proposal if hud.touch.free_build!=null and hud.touch.free_build.step==3 and not hud.controls.confirm.disabled else {}
