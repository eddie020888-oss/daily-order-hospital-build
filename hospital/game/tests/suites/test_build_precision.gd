extends RefCounted

var _t: TestContext

func run(t: TestContext) -> void:
	_t=t
	_adjust_bounds()
	_protected_shrink()
	_pointer_precision()

func _expect(ok:bool,label:String) -> void:
	_t.expect_true(ok,"build precision: "+label)

func _controller(world:HospitalWorld=null,hit:Callable=Callable()) -> TouchController:
	return TouchController.new(world,hit,func() -> String:return "precision_receipt")

func _adjust_bounds() -> void:
	var draft:=FreeBuildDraft.new("diagnosis")
	_expect(draft.has_method("adjust_bounds") and draft.has_method("adjusted_bounds"),"selected bounds expose precise adjustment without redrawing")
	if not draft.has_method("adjust_bounds") or not draft.has_method("adjusted_bounds"):return
	_expect(not draft.call("adjust_bounds",Vector2i(1,0)),"empty draft cannot be enlarged without a selected location")
	draft.set_bounds(130,54)
	var before:Dictionary=draft.capture_state()
	_expect(draft.call("adjust_bounds",Vector2i(1,0)),"one width increment changes the existing rectangle")
	_expect(draft.proposal().origin_cell==54 and draft.layout.width==6 and draft.layout.height==4,"reverse-corner selection normalizes origin before adding exactly one column")
	_expect(draft.call("adjust_bounds",Vector2i(0,1)) and draft.layout.width==6 and draft.layout.height==5,"height increment changes exactly one row")
	_expect(draft.call("adjust_bounds",Vector2i(-1,-1)) and draft.layout.width==5 and draft.layout.height==4,"decrement preserves location and restores exact size")
	before=draft.capture_state()
	_expect(not draft.call("adjust_bounds",Vector2i.ZERO,Vector2i(-100,0)) and draft.capture_state()==before,"off-map translation leaves the whole draft unchanged")
	_expect(not draft.call("adjust_bounds",Vector2i(-5,0)) and draft.capture_state()==before,"zero width is rejected without changing the draft")
	draft.step=1
	_expect(not draft.call("adjust_bounds",Vector2i(1,0)) and draft.layout.width==5,"size controls cannot mutate a later construction step")
	var original:Dictionary={"width":5,"height":4,"door":{"side":"south","offset":2},"doors":[{"side":"south","offset":2}],"windows":[{"side":"west","offset":1}],"equipment":{"x":0,"y":0,"rotation":1},"furniture":[{"kind":"plant","x":4,"y":0,"rotation":0}]}
	var c:=_controller()
	var commands:Array=[]
	c.command_requested.connect(func(command:Dictionary) -> void:commands.append(command))
	c.begin_free_build("diagnosis","old_room",original,54)
	_expect(c.has_method("adjust_build_bounds"),"controller exposes preview-only bounds adjustment")
	if not c.has_method("adjust_build_bounds"):return
	_expect(c.call("adjust_build_bounds",Vector2i.ZERO,Vector2i(1,0)),"whole rectangle moves one grid column")
	_expect(c.placement.origin_cell==55 and c.placement.layout==original,"moving retains all relative doors windows equipment and furniture")
	_expect(c.call("adjust_build_bounds",Vector2i(1,0)),"existing room width can be adjusted without erasing its contents")
	_expect(c.free_build.layout.door==original.door and c.free_build.layout.windows==original.windows and c.free_build.layout.equipment==original.equipment and c.free_build.layout.furniture==original.furniture,"resizing retains relative contents for normal validation instead of silently deleting them")
	_expect(not c.free_build.layout.has("footprint_version") and c.placement.id=="precision_receipt" and c.placement.room_id=="old_room","micro adjustments preserve legacy version room identity and receipt")
	_expect(commands.is_empty() and original.width==5,"adjustments never purchase or mutate the original room input")
	var modern:Dictionary=original.duplicate(true)
	modern.footprint_version=2
	c.begin_free_build("diagnosis","modern_room",modern,54)
	_expect(c.call("adjust_build_bounds",Vector2i(0,1),Vector2i(0,1)) and c.free_build.layout.footprint_version==2 and c.placement.origin_cell==78,"modern footprint rules survive combined one-row growth and movement")
	_expect(c.free_build.layout.equipment==modern.equipment and c.free_build.layout.doors==modern.doors,"combined adjustment retains the modern relative workstation and door list")

func _finger(c:TouchController,down:bool,point:Vector2,index:int=0) -> void:
	var event:=InputEventScreenTouch.new()
	event.index=index;event.pressed=down;event.position=point
	c.feed(event)

func _protected_shrink() -> void:
	var layout:Dictionary={"width":5,"height":4,"door":{"side":"south","offset":2},"doors":[{"side":"south","offset":2}],"windows":[{"side":"north","offset":4}],"equipment":{"x":0,"y":0,"rotation":0},"furniture":[],"footprint_version":2}
	var opening:=FreeBuildDraft.new("diagnosis","old_room",layout,54)
	var before:Dictionary=opening.capture_state()
	_expect(not opening.adjust_bounds(Vector2i(-1,0)) and opening.capture_state()==before,"shrink cannot strand an existing edge window outside its selectable wall")
	var bench_layout:Dictionary=layout.duplicate(true)
	bench_layout.windows=[]
	bench_layout.furniture=[{"kind":"bench","x":3,"y":2,"rotation":0}]
	var bench:=FreeBuildDraft.new("diagnosis","old_room",bench_layout,54)
	before=bench.capture_state()
	_expect(not bench.adjust_bounds(Vector2i(-1,0)) and bench.capture_state()==before,"modern two-cell furniture cannot be partly cropped by a one-column shrink")
	bench_layout.erase("footprint_version")
	var legacy:=FreeBuildDraft.new("diagnosis","legacy_room",bench_layout,54)
	_expect(legacy.adjust_bounds(Vector2i(-1,0)) and legacy.layout.width==4,"legacy single-cell furniture keeps its old shrinking footprint rules")
	_expect(opening.adjust_bounds(Vector2i(1,0)) and opening.layout.windows==layout.windows,"growth still preserves and repairs the edge item without silently deleting it")

func _drag(c:TouchController,point:Vector2) -> void:
	var event:=InputEventScreenDrag.new()
	event.index=0;event.position=point
	c.feed(event)

func _pointer_precision() -> void:
	var tree:=Engine.get_main_loop() as SceneTree
	var original_size:Vector2i=tree.root.size
	tree.root.size=Vector2i(1280,720)
	var world:=HospitalWorld.new()
	tree.root.add_child(world)
	var camera:=world.camera_rig.camera
	var start:=camera.unproject_position(HospitalWorld.cell_position(54))
	var end:=camera.unproject_position(HospitalWorld.cell_position(130))
	var c:=_controller(world)
	c.begin_free_build("diagnosis");c.choose_cell(54);c.choose_cell(130)
	var before:Dictionary=c.placement.duplicate(true)
	_finger(c,true,start);_finger(c,false,start)
	_expect(c.placement==before,"tapping an existing corner does not collapse a selected room to one cell")
	c.begin_free_build("diagnosis");c.choose_cell(54);c.choose_cell(130)
	var at:=camera.unproject_position(HospitalWorld.cell_position(104))
	var moved:=camera.unproject_position(HospitalWorld.cell_position(105))
	_finger(c,true,at);_drag(c,moved);_finger(c,false,moved)
	_expect(c.placement.origin_cell==55 and c.placement.layout.width==5 and c.placement.layout.height==4,"dragging inside a selected room moves the complete rectangle one cell")
	before=c.placement.duplicate(true)
	_finger(c,true,moved);_drag(c,end);_finger(c,true,start,1);_finger(c,false,end);_finger(c,false,start,1)
	_expect(c.placement==before,"adding a second finger rolls back an unfinished rectangle move")
	var jitter:=_controller(world)
	jitter.begin_free_build("diagnosis")
	var edge_before:=camera.unproject_position(Vector3(10.49,0,5))
	var edge_after:=camera.unproject_position(Vector3(10.51,0,5))
	_finger(jitter,true,start);_drag(jitter,edge_before)
	var preview:Dictionary=jitter.placement.duplicate(true)
	_finger(jitter,false,edge_after)
	_expect(preview.layout.width==5 and jitter.placement==preview,"a tiny release movement across a cell border keeps the visible five-column preview")
	print("BUILD PRECISION METRIC: "+JSON.stringify({"source":"software-injected real Godot pointer events","viewport":str(tree.root.get_visible_rect().size),"zoom_size":world.camera_rig.zoom_size,"release_delta_pixels":edge_before.distance_to(edge_after),"preview_width":preview.layout.width,"released_width":jitter.placement.layout.width,"physical_device_measured":false}))
	var deliberate:=_controller(world)
	deliberate.begin_free_build("diagnosis")
	var beyond:=camera.unproject_position(Vector3(10.8,0,5))
	_finger(deliberate,true,start);_drag(deliberate,edge_before);_drag(deliberate,beyond);_finger(deliberate,false,beyond)
	_expect(deliberate.placement.layout.width==6,"deliberately crossing beyond the border still adds the intended next column")
	var vertical:=_controller(world)
	vertical.begin_free_build("diagnosis")
	var row_before:=camera.unproject_position(Vector3(10,0,5.49))
	var row_after:=camera.unproject_position(Vector3(10,0,5.51))
	_finger(vertical,true,start);_drag(vertical,row_before)
	preview=vertical.placement.duplicate(true)
	_finger(vertical,false,row_after)
	_expect(preview.layout.height==4 and vertical.placement==preview,"row-border release jitter preserves the visible height independently of width")
	var diagonal:=_controller(world)
	diagonal.begin_free_build("diagnosis")
	var corner_before:=camera.unproject_position(Vector3(10.49,0,5.49))
	var corner_after:=camera.unproject_position(Vector3(10.51,0,5.51))
	_finger(diagonal,true,start);_drag(diagonal,corner_before)
	preview=diagonal.placement.duplicate(true)
	_finger(diagonal,false,corner_after)
	_expect(diagonal.placement==preview,"diagonal corner jitter does not grow both dimensions on release")
	var blocked_point:=camera.unproject_position(HospitalWorld.cell_position(106))
	var gui:=_controller(world,func(point:Vector2) -> bool:return point.distance_to(blocked_point)<2)
	gui.begin_free_build("diagnosis");gui.choose_cell(54);gui.choose_cell(130)
	before=gui.placement.duplicate(true)
	_finger(gui,true,at);_drag(gui,moved);_finger(gui,false,blocked_point)
	_expect(gui.placement==before,"releasing a whole-room move on GUI restores its original complete draft")
	var outside:=camera.unproject_position(Vector3(0,0,4))
	_finger(gui,true,at);_drag(gui,moved);_finger(gui,false,outside)
	_expect(gui.placement==before,"releasing a whole-room move outside the map restores its original complete draft")
	_finger(gui,true,at);_drag(gui,moved);gui.reset_input();_finger(gui,false,moved)
	_expect(gui.free_build==null and gui.placement.is_empty(),"application reset during a whole-room move clears all gesture ownership")
	world.free()
	tree.root.size=original_size
