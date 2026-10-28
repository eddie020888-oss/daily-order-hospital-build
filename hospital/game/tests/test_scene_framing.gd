extends SceneTree
var passed:=0
var failed:=0
func _initialize() -> void:_run.call_deferred()
func check(value:bool,copy:String) -> void:
	if value:passed+=1
	else:failed+=1
	print(("FRAME PASS: " if value else "FRAME FAIL: ")+copy)
func _run() -> void:
	root.size=Vector2i(1280,720)
	var catalog:ContentCatalog=ContentCatalog.load_checked("res://content").catalog
	var host:Node3D=load("res://main.gd").new()
	host.session=GameSession.new(catalog,"E:/CODEX/2026-10-20/医院整体画面修正/temp/framing-%d"%Time.get_ticks_usec())
	root.add_child(host);host.set_process(false);host.hud.flow.close()
	host.feedback.set_application_active(false);host.feedback._music_player.stop()
	host.session.sim=Scenarios.create_sim(catalog,"benchmark_18","fast","standard")
	host.session.sim.advance_ticks(300)
	host.hud.present();host.world.present(host.session.sim.snapshot())
	var before:Dictionary=host.session.sim.snapshot()
	var patient:String=before.patients.keys()[0]
	for row in [[Vector2(1280,720),Vector2(1280,720),160],[Vector2(2560,1440),Vector2(1280,720),640]]:
		host.hud.configure_display(row[0],row[1],row[2],Rect2(Vector2.ZERO,row[0]))
		host.hud.select_entity(patient,"patients")
		for _i in range(5):await process_frame
		var panel:Rect2=host.hud._right.get_global_rect()
		var left:float=(host.hud._safe.position.x+12)*host.hud.scale.x
		var right:float=panel.position.x-18*host.hud.scale.x
		var patient_floor:Vector3=HospitalWorld.cell_position(before.patients[patient].cell)
		var screen:Vector2=host.world.camera_rig.camera.unproject_position(patient_floor)
		check(absf(screen.x-(left+right)*.5)<2,"%d DPI located patient is centered in the uncovered world area"%row[2])
		check(host.world.camera_rig.screen_to_cell(screen)==before.patients[patient].cell,"%d DPI framed patient ground remains touch-pickable"%row[2])
		host.hud._close_drawers()
		for _i in range(3):await process_frame
		screen=host.world.camera_rig.camera.unproject_position(patient_floor)
		check(absf(screen.x-640)<2,"%d DPI closing drawer restores full-width composition"%row[2])
	var room_id:String=before.rooms.keys()[0]
	var center:=Vector3.ZERO
	for cell in before.rooms[room_id].cells:center+=HospitalWorld.cell_position(cell)
	center/=before.rooms[room_id].cells.size()
	host.world.camera_rig.set_zoom(5.5)
	host.hud.select_entity(room_id,"rooms")
	check(host.world.camera_rig.target.distance_to(center)<.001,"room focus uses its actual footprint center")
	var clear:=Rect2(Vector2((host.hud._safe.position.x+12)*host.hud.scale.x,(host.hud._top_frame.position.y+host.hud._top_frame.size.y+8)*host.hud.scale.y),Vector2.ZERO)
	clear.end=Vector2(host.hud._right.get_global_rect().position.x-18*host.hud.scale.x,(host.hud._dock.position.y-8)*host.hud.scale.y)
	var footprint_fits:=true
	for cell in before.rooms[room_id].cells:
		for offset in [Vector3(-.5,0,-.5),Vector3(.5,0,.5),Vector3(-.5,2.05,-.5),Vector3(.5,2.05,.5)]:
			footprint_fits=footprint_fits and clear.has_point(host.world.camera_rig.camera.unproject_position(HospitalWorld.cell_position(cell)+offset))
	check(footprint_fits,"explicit room focus fits floor and top of equipment into the uncovered scene")
	host.world.camera_rig.set_zoom(6.25)
	for _i in range(3):host.hud.present()
	check(is_equal_approx(host.world.camera_rig.zoom_size,6.25),"ordinary UI refresh respects later manual zoom")
	var long_room:={"cells":[]}
	for y in range(1,8):
		for x in range(1,23):long_room.cells.append(y*24+x)
	host.world.camera_rig.set_scene_anchor(Vector2(.18,.5),Vector2(.36,.68))
	host.world.focus_room(long_room)
	var long_room_fits:=true
	var narrow_scene:=Rect2(Vector2(0,115.2),Vector2(460.8,489.6))
	for cell in long_room.cells:
		for dx in [-.5,.5]:
			for dy in [0,2.05]:
				for dz in [-.5,.5]:long_room_fits=long_room_fits and narrow_scene.has_point(host.world.camera_rig.camera.unproject_position(HospitalWorld.cell_position(cell)+Vector3(dx,dy,dz)))
	check(long_room_fits,"maximum legal 22 by 7 room fits beside a short-screen drawer")
	var fitted_size:float=host.world.camera_rig.zoom_size
	host.world.camera_rig.set_zoom(fitted_size-1)
	host.world.camera_rig.set_zoom(fitted_size)
	check(is_equal_approx(host.world.camera_rig.zoom_size,fitted_size),"manual zoom can return to the long-room fitted view without a hard jump")
	var near_closed:=true
	var backs_closed:=true
	var near_count:=0
	var owners:Dictionary={}
	for id in before.rooms:
		for cell in before.rooms[id].cells:owners[cell]=id
	var shared_closed:=true
	var shared_count:=0
	var dependency_id:=""
	var dependency_mid:=Vector3.ZERO
	for id in before.rooms:
		var room:Dictionary=before.rooms[id]
		for edge in room.wall_edges:
			var a:=HospitalWorld.cell_position(edge[0]);var b:=HospitalWorld.cell_position(edge[1]);var middle:Vector3=(a+b)*.5
			var inside:Vector3=a if room.cells.has(edge[0]) else b
			var normal:Vector3=(inside-middle).normalized()
			var shared:bool=owners.has(edge[0]) and owners.has(edge[1]) and owners[edge[0]]!=owners[edge[1]]
			for wall in host.world.room_views[id].wall_segments:
				if Vector2(wall.position.x-middle.x,wall.position.z-middle.z).length()>.01:continue
				if normal.x<-.5 or normal.z<-.5:
					near_count+=1;near_closed=near_closed and wall.get_aabb().size.y>=1.98
				elif not shared:backs_closed=backs_closed and wall.get_aabb().size.y>=1.98
				if shared:
					shared_count+=1;shared_closed=shared_closed and wall.get_aabb().size.y>=1.98
					if normal.x>.5 or normal.z>.5:dependency_id=id;dependency_mid=middle
	check(near_count>0 and near_closed,"south and east near walls retain a full opaque room perimeter")
	check(backs_closed,"far walls retain the full-height room backdrop")
	check(shared_count>0 and shared_closed,"both rendered sides of a shared divider retain full-height walls")
	if dependency_id!="":
		host.world.present({"rooms":{dependency_id:before.rooms[dependency_id]},"staff":{},"patients":{},"slots":{}})
		var restored:=false
		for wall in host.world.room_views[dependency_id].wall_segments:
			if Vector2(wall.position.x-dependency_mid.x,wall.position.z-dependency_mid.z).length()<.01:restored=wall.get_aabb().size.y>=1.98
		check(restored,"removing a neighbour retains the unchanged room's full-height perimeter")
		host.world.present(before)
		var closed_again:=false
		for wall in host.world.room_views[dependency_id].wall_segments:
			if Vector2(wall.position.x-dependency_mid.x,wall.position.z-dependency_mid.z).length()<.01:closed_again=wall.get_aabb().size.y>=1.98
		check(closed_again,"restoring a neighbour retains the shared full-height perimeter")
	check(before==host.session.sim.snapshot(),"framing and closed-wall presentation do not mutate the hospital")
	host.free();await process_frame;await process_frame
	print("SCENE FRAMING RESULT: passed=%d failed=%d"%[passed,failed]);quit(1 if failed else 0)
