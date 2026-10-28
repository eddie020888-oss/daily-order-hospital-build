extends RefCounted

# Presentation-only detail for the authoritative preview's already-known code.
# Never approves a layout, relaxes navigation or changes simulation/draft data.
const HINTS:Dictionary={
	"boundary":"此方向超出院区可建范围，请移动房间后再扩建。",
	"main_corridor":"此方向会占用主走廊，请移动房间或改向另一侧扩建。",
	"facility_overlap":"红格是两台设备本体重叠的位置，请移动其中一台。",
	"facility_out_of_bounds":"设备本体超出房间，请移动设备或扩大房间。",
	"facility_access_out_of_bounds":"操作或检修位置超出房间，请为这些位置留出室内空间。",
	"facility_access_overlap":"红格的操作或检修位置被设备本体挡住，请移动设备。",
	"facility_work_position_overlap":"红格被多台设备同时用作操作或检修位置。",
	"door_blocked":"红格占用了门口通道，请移动设备或调整门位。",
	"door_operating_position":"红格的操作或检修位置与门口通道重叠。",
	"room_overlap":"红格与已有房间重叠，请移动或缩小当前房间。",
	"room_unreachable":"标记的房门或门外位置无法通行，请保留连通的入口。",
	"facility_unreachable":"标记的操作或检修位置无法到达，请留出连通通道。",
	"facility_occupied_unreachable":"标记位置在人站定后无法到达，请在工作位外侧留出通道。"
}

static func diagnose(snapshot:Dictionary,proposal:Dictionary,code:String)->Dictionary:
	var result:Dictionary={"kind":code,"conflict_cells":[],"conflict_hint":str(HINTS.get(code,""))}
	if code=="" or not HINTS.has(code):return result
	var layout:Variant=proposal.get("layout",{})
	var origin:Variant=proposal.get("origin_cell",-1)
	if not layout is Dictionary or not origin is int or origin<0 or origin>=432:return result
	var width:Variant=layout.get("width",0)
	var height:Variant=layout.get("height",0)
	if not width is int or not height is int or width<1 or width>24 or height<1 or height>18:return result
	var ox:int=origin%24
	var oy:int=origin/24
	if code in ["boundary","main_corridor"]:
		for y:int in range(height):
			for x:int in range(width):
				var at:=Vector2i(ox+x,oy+y)
				var conflict:bool=at.x<1 or at.x>=23 or at.y<1 or at.y>=17 if code=="boundary" else at.y in [8,9]
				if conflict:_add_point(result.conflict_cells,at)
		return result
	if FacilityLayout._shape_error(proposal)!="":return result
	var room:Dictionary=FacilityLayout.geometry(proposal)
	if room.is_empty():return result
	var room_cells:Dictionary={}
	for cell:int in room.cells:room_cells[cell]=true
	var body:Dictionary={}
	var work:Dictionary={}
	var forbidden:Dictionary={}
	for door:Dictionary in room.doorways:
		forbidden[int(door.door_cell)]=true
		forbidden[int(door.door_cell)*2-int(door.door_outside_cell)]=true
	for item:Dictionary in layout.facilities:
		var station:Dictionary=FacilityLayout._station(str(item.kind),int(item.rotation))
		for point:Array in station.equipment_cells:
			var at:=Vector2i(ox+int(item.x)+int(point[0]),oy+int(item.y)+int(point[1]))
			if not _inside(at):continue
			var cell:int=at.y*24+at.x
			if code=="facility_out_of_bounds" and not room_cells.has(cell):_add(result.conflict_cells,cell)
			if code=="facility_overlap" and body.has(cell):_add(result.conflict_cells,cell)
			if code=="door_blocked" and forbidden.has(cell):_add(result.conflict_cells,cell)
			body[cell]=true
	for item:Dictionary in layout.facilities:
		var station:Dictionary=FacilityLayout._station(str(item.kind),int(item.rotation))
		for point:Array in station.service_cells+station.staff_cells+[station.maintenance]:
			var at:=Vector2i(ox+int(item.x)+int(point[0]),oy+int(item.y)+int(point[1]))
			if not _inside(at):continue
			var cell:int=at.y*24+at.x
			if code=="facility_access_out_of_bounds" and not room_cells.has(cell):_add(result.conflict_cells,cell)
			if code=="facility_access_overlap" and body.has(cell):_add(result.conflict_cells,cell)
			if code=="facility_work_position_overlap" and work.has(cell):_add(result.conflict_cells,cell)
			if code=="door_operating_position" and forbidden.has(cell):_add(result.conflict_cells,cell)
			work[cell]=true
	if code=="room_overlap":
		for id:String in snapshot.get("rooms",{}):
			if id==str(proposal.get("room_id",proposal.get("id",""))):continue
			for cell:int in GridService._room_geometry(snapshot.rooms[id]).get("cells",[]):
				if room_cells.has(cell):_add(result.conflict_cells,cell)
	if code in ["room_unreachable","facility_unreachable","facility_occupied_unreachable"]:
		_path_targets(snapshot,proposal,room,code,result.conflict_cells)
	return result

static func _inside(at:Vector2i)->bool:
	return at.x>=0 and at.x<24 and at.y>=0 and at.y<18

static func _add_point(cells:Array,at:Vector2i)->void:
	if _inside(at):_add(cells,at.y*24+at.x)

static func _add(cells:Array,cell:int)->void:
	if cell>=0 and cell<432 and not cells.has(cell):cells.append(cell)

static func _path_targets(snapshot:Dictionary,proposal:Dictionary,room:Dictionary,code:String,cells:Array)->void:
	var candidate_rooms:Dictionary=snapshot.get("rooms",{}).duplicate(true)
	candidate_rooms.erase(str(proposal.get("room_id",proposal.get("id",""))))
	var id:String="__feedback_candidate__"
	while candidate_rooms.has(id):id+="_"
	candidate_rooms[id]=room
	if code=="facility_occupied_unreachable":
		var occupied:Dictionary={}
		var targets:Array=[]
		for record:Dictionary in candidate_rooms.values():
			if record.get("ruleset","")!=FacilityLayout.RULESET and record.get("kind","")!="campaign_department":continue
			var geometry:Dictionary=FacilityLayout.geometry(record)
			for target:int in geometry.get("service_cells",[])+geometry.get("staff_cells",[]):
				occupied[target]=true;targets.append(target)
			targets.append_array(geometry.get("maintenance_cells",[]))
		var state:=ClinicState.new();state.data={"rooms":candidate_rooms}
		for target:int in targets:
			var blocked:Dictionary=occupied.duplicate();blocked.erase(target)
			if GridService.path_avoiding(state,GridService.EXIT_CELL,target,blocked).is_empty():
				# This is an actually unreachable destination, not a fabricated
				# unique obstruction or a claim that one worker caused the failure.
				_add(cells,target);return
		return
	var navigation:Dictionary=GridService._navigation(candidate_rooms)
	var reachable:Dictionary=GridService._flood(navigation,GridService.EXIT_CELL)
	for record:Dictionary in candidate_rooms.values():
		var geometry:Dictionary=GridService._room_geometry(record)
		if code=="room_unreachable":
			for door:Dictionary in geometry.get("doorways",[]):
				if not GridService._can_step(navigation,int(door.door_cell),int(door.door_outside_cell)) or not reachable.has(door.door_cell) or not reachable.has(door.door_outside_cell):
					_add(cells,int(door.door_cell));_add(cells,int(door.door_outside_cell))
		elif code=="facility_unreachable":
			for target:int in geometry.get("service_cells",[])+geometry.get("staff_cells",[])+geometry.get("maintenance_cells",[]):
				if not reachable.has(target):_add(cells,target)
