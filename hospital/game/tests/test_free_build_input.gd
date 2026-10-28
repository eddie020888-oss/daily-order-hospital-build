extends SceneTree

var passed:=0
var failed:=0
var touch_script: GDScript
var draft_script: GDScript

func _initialize() -> void: _run.call_deferred()

func check(value: bool, copy: String) -> void:
	if value: passed+=1
	else: failed+=1
	print(("FREE INPUT PASS: " if value else "FREE INPUT FAIL: ")+copy)

func _run() -> void:
	touch_script=load("res://input/touch_controller.gd")
	var controller: RefCounted=touch_script.new()
	check(controller.has_method("begin_free_build"),"four-step construction has an input entry point")
	check(FileAccess.file_exists("res://input/free_build_draft.gd"),"construction draft exists independently of the HUD")
	if not controller.has_method("begin_free_build") or not FileAccess.file_exists("res://input/free_build_draft.gd"):
		_finish()
		return
	draft_script=load("res://input/free_build_draft.gd")
	_atomic_submission()
	_step_gates_and_resize()
	_versioned_dimensions()
	_editing_preserves_input_layout()
	_reposition_preserves_version()
	_door_rotation_and_furniture()
	_two_cell_bench()
	_gesture_ownership()
	_legacy_path()
	_finish()

func _finish() -> void:
	print("FREE INPUT RESULT: passed=%d failed=%d" % [passed,failed])
	quit(1 if failed else 0)

func _controller(view: HospitalWorld=null, hit: Callable=Callable()) -> RefCounted:
	return touch_script.new(view,hit,func() -> String: return "free_input_receipt")

func _complete(c: RefCounted) -> void:
	c.begin_free_build("diagnosis")
	c.choose_cell(54)
	c.choose_cell(130) # (6,2)..(10,5), five by four.
	c.advance_build_step()
	c.choose_cell(127) # South wall offset one.
	c.advance_build_step()
	c.choose_cell(55) # Workstation anchor (1,0).
	c.advance_build_step()

func _atomic_submission() -> void:
	# Break caught: a step button purchases the room before the door/equipment were placed.
	var c:=_controller()
	var emitted: Array=[]
	c.command_requested.connect(func(command: Dictionary) -> void: emitted.append(command))
	c.begin_free_build("diagnosis")
	check(c.free_build.layout.get("footprint_version") is int and c.free_build.layout.footprint_version==2,"new construction explicitly starts with version2 footprints")
	c.choose_cell(54)
	c.choose_cell(130)
	c.confirm()
	check(emitted.is_empty() and c.free_build.step==0,"size confirmation cannot dispatch a purchase")
	check(c.advance_build_step(),"five by four bounds advance to the door step")
	c.choose_cell(127)
	c.confirm()
	check(emitted.is_empty(),"door confirmation cannot dispatch a purchase")
	check(c.advance_build_step(),"a selected boundary door advances to equipment")
	c.choose_cell(55)
	c.confirm()
	check(emitted.is_empty(),"equipment confirmation cannot skip the decoration step")
	check(c.advance_build_step() and c.free_build.step==3,"a complete workstation advances to optional decoration")
	c.confirm()
	c.confirm()
	check(emitted.size()==1,"repeated final confirmation emits one receipt")
	if emitted.size()==1:
		var command: Dictionary=emitted[0]
		check(command.id=="free_input_receipt" and command.type=="build_room","final construction uses the reserved receipt")
		check(command.payload=={"kind":"diagnosis","origin_cell":54,"rotation":0,"layout":{"width":5,"height":4,"door":{"side":"south","offset":1},"equipment":{"x":1,"y":0,"rotation":0},"furniture":[],"footprint_version":2}},"only the complete literal version2 layout reaches the model")
	check(c.placement.is_empty() and c.free_build==null,"successful submission clears the entire draft")
	_complete(c)
	c.cancel()
	c.confirm()
	check(emitted.size()==1,"cancel never emits a second purchase")

func _step_gates_and_resize() -> void:
	# Break caught: minimum dimensions or required items are silently defaulted.
	var d: RefCounted=draft_script.new("diagnosis")
	d.choose_cell(54)
	d.choose_cell(79)
	check(not d.next_step() and d.step==0,"a two by two diagnosis room cannot advance")
	d.choose_cell(130)
	d.choose_cell(54)
	check(d.layout.width==5 and d.layout.height==4 and d.proposal().origin_cell==54,"reverse corners normalize into the same rectangle")
	check(d.next_step() and not d.next_step(),"door step requires the player to place a door")
	d.choose_cell(80)
	check(d.layout.door.is_empty(),"an interior cell cannot become a wall door")
	d.choose_cell(127)
	check(d.next_step() and not d.next_step(),"equipment step remains incomplete until its workstation is placed")
	d.choose_cell(55)
	check(d.next_step(),"valid equipment fulfills the required workstation")
	d.previous_step()
	d.previous_step()
	d.previous_step()
	d.choose_cell(54)
	d.choose_cell(131)
	check(d.layout.width==6 and d.layout.height==4,"returning to size allows a new rectangle")
	check(d.layout.door.is_empty() and d.layout.equipment.is_empty() and d.layout.furniture.is_empty(),"resizing clears dependent items instead of silently moving them")
	check(d.layout.footprint_version==2,"resizing keeps the new draft footprint version")
	var small: RefCounted=draft_script.new("recovery")
	small.choose_cell(54)
	small.choose_cell(104)
	check(small.next_step(),"a three by three recovery room meets its own minimum")

func _versioned_dimensions() -> void:
	# Break caught: the new draft still applies one four-by-four minimum to all
	# equipment, or silently applies new minima to a legacy imported layout.
	for row in [["diagnosis",3,3,false],["diagnosis",3,4,true],["diagnosis",4,3,true],["motion",4,4,false],["motion",4,5,true],["motion",5,4,true],["sensory",3,4,false],["sensory",3,5,true],["sensory",5,3,true]]:
		var d:RefCounted=draft_script.new(row[0])
		d.set_bounds(54,54+int(row[1])-1+(int(row[2])-1)*24)
		check(d.can_advance()==row[3],"new %s %d by %d size gate matches its version2 minimum"%[row[0],row[1],row[2]])
	for kind in ["motion","sensory"]:
		var old:={"width":4,"height":4,"door":{"side":"south","offset":0},"equipment":{"x":0,"y":0,"rotation":0},"furniture":[]}
		var d:RefCounted=draft_script.new(kind,"room_legacy",old,54)
		check(d.can_advance() and not d.layout.has("footprint_version"),"legacy %s four-by-four draft retains its original size gate"%kind)

func _editing_preserves_input_layout() -> void:
	# Break caught: editing changes the live room before its final transaction.
	var original:={"width":5,"height":4,"door":{"side":"south","offset":1},"equipment":{"x":1,"y":0,"rotation":0},"furniture":[{"kind":"plant","x":0,"y":3,"rotation":0}]}
	var untouched:=original.duplicate(true)
	var c:=_controller()
	c.begin_free_build("diagnosis","room_007",original,54)
	check(c.free_build.step==0 and c.placement.origin_cell==54 and c.placement.layout==untouched,"edit opens with the existing layout and origin")
	check(not c.free_build.layout.has("footprint_version"),"editing a legacy layout does not add a footprint version")
	c.advance_build_step()
	c.advance_build_step()
	c.advance_build_step()
	c.select_furniture("plant")
	c.choose_cell(126)
	check(original==untouched and c.free_build.layout.furniture.is_empty(),"editing owns a deep copy and can remove existing decoration")
	var emitted: Array=[]
	c.command_requested.connect(func(command: Dictionary) -> void: emitted.append(command))
	c.confirm()
	check(emitted.size()==1 and emitted[0].type=="move_room" and emitted[0].payload.room_id=="room_007" and not emitted[0].payload.has("kind"),"edit dispatches the existing room identity with its custom layout")
	if emitted.size()==1:
		check(not emitted[0].payload.layout.has("footprint_version"),"legacy edit receipt stays versionless")

func _reposition_preserves_version() -> void:
	# Break caught: recreating the draft on redraw upgrades an old room's rules.
	var old:={"width":4,"height":4,"door":{"side":"south","offset":0},"equipment":{"x":0,"y":0,"rotation":0},"furniture":[]}
	var c:=_controller()
	c.begin_free_build("motion","room_legacy",old,54)
	var receipt:String=c.placement.id
	c.reposition()
	check(c.free_build.step==0 and c.placement.origin_cell==-1 and c.free_build.layout.width==0 and c.free_build.layout.height==0 and c.free_build.layout.door.is_empty() and c.free_build.layout.equipment.is_empty() and c.free_build.layout.furniture.is_empty(),"legacy redraw clears all unfinished dimensions and dependent choices")
	check(not c.free_build.layout.has("footprint_version") and c.placement.id==receipt and c.free_build.room_id=="room_legacy","legacy edit then redraw retains version1, room identity and receipt")
	c.choose_cell(54);c.choose_cell(129)
	check(c.free_build.can_advance(),"redrawn legacy motion room still accepts its original four-by-four minimum")
	c.cancel();c.begin_free_build("motion");c.reposition()
	c.choose_cell(54);c.choose_cell(129)
	check(c.free_build.layout.footprint_version==2 and not c.free_build.can_advance(),"new version2 redraw keeps its stricter motion size gate")

func _door_rotation_and_furniture() -> void:
	# Break caught: corner ambiguity or furniture collision creates a hidden invalid layout.
	var c:=_controller()
	_complete(c)
	c.back_build_step()
	c.back_build_step()
	c.choose_cell(130)
	check(c.free_build.layout.door=={"side":"south","offset":4},"south wins at the southeast corner")
	c.rotate()
	check(c.free_build.layout.door.side=="west","rotating a door selects its next wall")
	c.choose_cell(127)
	c.advance_build_step()
	c.rotate()
	check(c.free_build.layout.equipment.rotation==1 and c.placement.rotation==0,"workstation rotation leaves the room rotation fixed")
	c.rotate(); c.rotate(); c.rotate()
	c.advance_build_step()
	c.select_furniture("plant")
	c.choose_cell(55)
	check(not c.free_build.can_advance(),"decoration colliding with equipment blocks final construction")
	c.choose_cell(55)
	check(c.free_build.can_advance() and c.free_build.layout.furniture.is_empty(),"tapping the same kind and cell removes that decoration")
	c.choose_cell(126)
	c.rotate()
	check(c.free_build.layout.furniture.size()==1 and c.free_build.layout.furniture[0].rotation==1,"rotation applies to the selected decoration")
	c.remove_furniture_at(126)
	check(c.free_build.layout.furniture.is_empty(),"explicit decoration removal changes only the selected cell")

func _two_cell_bench() -> void:
	# Break caught: the second occupied bench cell is ignored by placement,
	# rotation bounds, tap-to-remove, or explicit removal.
	var c:=_controller()
	c.begin_free_build("diagnosis")
	c.choose_cell(54);c.choose_cell(128)
	c.advance_build_step();c.choose_cell(126)
	c.advance_build_step();c.choose_cell(54);c.advance_build_step()
	check(c.free_build.step==3,"version2 three-by-four diagnosis fixture reaches furniture selection")
	if c.free_build.step!=3:return
	c.select_furniture("bench");c.choose_cell(127)
	check(c.free_build.can_advance() and FreeRoomLayout.definition("diagnosis",c.free_build.layout).furniture_cells==[[1,3],[2,3]],"horizontal bench occupies both literal free cells")
	c.choose_cell(128)
	check(c.free_build.layout.furniture.is_empty(),"tapping the bench second cell removes the same furniture item")
	c.choose_cell(127);c.rotate()
	check(not c.free_build.can_advance(),"rotated bench cannot extend its second cell outside the room")
	c.rotate();c.remove_furniture_at(128)
	check(c.free_build.layout.furniture.is_empty(),"explicit removal also finds the bench by its second cell")
	c.select_furniture("plant");c.choose_cell(56)
	check(not c.free_build.can_advance(),"furniture cannot occupy the diagnosis maintenance clearance")
	c.choose_cell(56)
	check(c.free_build.can_advance(),"removing clearance obstruction restores the valid draft")

func _finger(c: RefCounted, index: int, down: bool, point: Vector2, canceled: bool=false) -> void:
	var e:=InputEventScreenTouch.new()
	e.index=index; e.pressed=down; e.position=point; e.canceled=canceled
	c.feed(e)

func _drag(c: RefCounted, index: int, point: Vector2) -> void:
	var e:=InputEventScreenDrag.new()
	e.index=index; e.position=point
	c.feed(e)

func _gesture_ownership() -> void:
	# Break caught: a pinch release or GUI-owned drag becomes a construction tap.
	root.size=Vector2i(1280,720)
	var world:=HospitalWorld.new()
	root.add_child(world)
	var camera:=world.camera_rig.camera
	var a:=camera.unproject_position(HospitalWorld.cell_position(54))
	var b:=camera.unproject_position(HospitalWorld.cell_position(130))
	var c:=_controller(world)
	c.begin_free_build("diagnosis")
	_finger(c,0,true,a)
	_drag(c,0,b)
	_finger(c,0,false,b)
	check(c.placement.origin_cell==54 and c.placement.layout.width==5 and c.placement.layout.height==4,"one finger drag creates the literal rectangle without panning")
	var before: Dictionary=c.placement.duplicate(true)
	_finger(c,0,true,a)
	_drag(c,0,camera.unproject_position(HospitalWorld.cell_position(155)))
	_finger(c,1,true,b)
	_finger(c,0,false,a)
	_finger(c,1,false,b)
	check(c.placement==before,"pinch abandons the unfinished drag and preserves the confirmed draft")
	c.advance_build_step()
	before=c.placement.duplicate(true)
	_finger(c,0,true,a)
	_finger(c,1,true,b)
	_finger(c,0,false,a)
	_finger(c,1,false,b)
	check(c.placement==before and c.free_build.step==1,"remaining fingers cannot place an accidental door after pinch")
	var outside:=camera.unproject_position(Vector3(0,0,4))
	_finger(c,0,true,outside);_finger(c,0,false,outside)
	check(c.placement==before and c.free_build.step==1,"a harmless tap outside the buildable map preserves the confirmed draft")
	var redraw:=_controller(world)
	redraw.begin_free_build("diagnosis")
	redraw.choose_cell(54);redraw.choose_cell(130)
	var original_bounds:Dictionary=redraw.placement.duplicate(true)
	_finger(redraw,0,true,a);_drag(redraw,0,camera.unproject_position(HospitalWorld.cell_position(155)));_drag(redraw,0,outside);_finger(redraw,0,false,outside)
	check(redraw.placement==original_bounds,"a rectangle drag released outside the map restores the previous draft")
	var gui:=_controller(world,func(point: Vector2) -> bool: return point.distance_to(a)<3)
	gui.begin_free_build("diagnosis")
	_finger(gui,0,true,a)
	_drag(gui,0,b)
	_finger(gui,0,false,b)
	check(gui.placement.origin_cell==-1,"a drag beginning on GUI cannot draw a room")
	_finger(gui,0,true,b)
	_drag(gui,0,a)
	_finger(gui,0,false,a)
	check(gui.placement.origin_cell==-1,"a drag ending on GUI rolls back its unfinished rectangle")
	_finger(c,0,true,a)
	_finger(c,0,false,a,true)
	check(c.free_build==null and c.placement.is_empty(),"a canceled screen touch clears gesture and draft ownership")
	_complete(c)
	c.reset_input()
	_finger(c,0,false,a)
	check(c.free_build==null and c.placement.is_empty(),"focus or page reset cannot retain a stale construction pointer")
	world.free()

func _legacy_path() -> void:
	# Break caught: adding free placement changes old template receipts or pinch cancellation.
	var c:=_controller()
	var emitted: Array=[]
	c.command_requested.connect(func(command: Dictionary) -> void: emitted.append(command))
	c.begin_placement("reception")
	c.choose_cell(121)
	c.confirm()
	check(emitted.size()==1 and emitted[0].payload=={"kind":"reception","origin_cell":121,"rotation":0},"legacy begin_placement keeps its original command payload")
	c.begin_placement("reception")
	c.choose_cell(121)
	_finger(c,0,true,Vector2(450,300))
	_finger(c,1,true,Vector2(550,300))
	check(c.placement.is_empty() and c.free_build==null,"legacy second finger still cancels the template placement")
