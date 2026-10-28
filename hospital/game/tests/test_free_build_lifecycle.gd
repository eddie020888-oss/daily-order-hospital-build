extends SceneTree

var passed:=0
var failed:=0
var catalog:ContentCatalog

func _initialize() -> void:
	_run.call_deferred()

func check(value:bool,label:String) -> void:
	if value:passed+=1
	else:failed+=1
	print(("BUILD LIFECYCLE PASS: " if value else "BUILD LIFECYCLE FAIL: ")+label)

func _run() -> void:
	catalog=ContentCatalog.load_checked("res://content").catalog
	_invalid_cell_preserves_each_step()
	await _editing_room_lifecycle()
	print("BUILD LIFECYCLE RESULT: passed=%d failed=%d"%[passed,failed])
	quit(1 if failed else 0)

func _layout() -> Dictionary:
	return {"width":5,"height":5,"door":{"side":"south","offset":1},"equipment":{"x":1,"y":0,"rotation":0},"furniture":[{"kind":"plant","x":3,"y":3,"rotation":0}]}

func _invalid_cell_preserves_each_step() -> void:
	# A negative or out-of-grid pick must not be interpreted as redrawing the
	# rectangle, dropping the door/equipment/furniture and rewinding the step.
	for step in range(4):
		for invalid_cell in [-1,432]:
			var controller:=TouchController.new(null,Callable(),func() -> String:return "draft_receipt")
			controller.begin_free_build("diagnosis","room_001",_layout(),54)
			for _i in range(step):controller.advance_build_step()
			var before:Dictionary=controller.free_build.capture_state()
			var proposal_before:Dictionary=controller.placement.duplicate(true)
			controller.choose_cell(invalid_cell)
			check(controller.free_build!=null and controller.free_build.step==step and controller.free_build.capture_state()==before and controller.placement==proposal_before,"invalid cell %d preserves the complete draft at step%d"%[invalid_cell,step])
	var legacy:=TouchController.new()
	legacy.begin_placement("reception")
	legacy.choose_cell(-1)
	check(legacy.placement.origin_cell==-1 and legacy.free_build==null,"legacy invalid-origin preview remains available")

func _editing_room_lifecycle() -> void:
	# A rebuilt room node defaults to visible. The HUD must reapply its preview
	# visibility ownership on present, then restore the current node on exit.
	root.size=Vector2i(1280,720)
	var host:Node3D=load("res://main.gd").new()
	host.session=GameSession.new(catalog,"E:/CODEX/2026-10-20/医院整体画面修正/temp/build-lifecycle-%d/save"%Time.get_ticks_usec())
	root.add_child(host)
	host.set_process(false)
	host.feedback.set_application_active(false)
	host.feedback._music_player.stop()
	host.hud.flow.close()
	var built:Dictionary=host.session.issue("build_room",{"kind":"diagnosis","origin_cell":54,"rotation":0,"layout":_layout()})
	check(built.ok,"fixture builds a real five by five custom room")
	if not built.ok:
		host.free()
		return
	var id:String=built.data.room_id
	host.session.issue("close_room",{"room_id":id})
	host.session.issue("set_paused",{"paused":false})
	host.session.sim.advance_ticks(1)
	host.session.issue("set_paused",{"paused":true})
	check(host.session.sim.snapshot().rooms[id].status=="closed","fixture room is closed and empty before layout editing")
	host.hud._begin_layout_edit("diagnosis",id)
	var authority_before:Dictionary=host.session.sim.snapshot()
	check(not host.world.room_views[id].visible,"editing hides the old room behind its independent draft")
	host.world._remove_view(host.world.room_views,id)
	host._present()
	check(not host.world.room_views[id].visible,"recreating the room view during present cannot reveal it through the draft")
	check(host.session.sim.snapshot()==authority_before,"recreating preview views does not mutate simulation state")
	host.touch.cancel()
	check(host.world.room_views[id].visible and host.session.sim.snapshot()==authority_before,"cancel restores the current room view with the authoritative room unchanged")
	host.hud._begin_layout_edit("diagnosis",id)
	var draft_receipt:String=host.touch.placement.id
	host.hud.controls.reposition.pressed.emit()
	check(host.touch.free_build.step==0 and host.touch.placement.origin_cell==-1 and host.touch.free_build.layout.door.is_empty() and host.touch.free_build.layout.equipment.is_empty() and host.touch.free_build.layout.furniture.is_empty() and host.touch.placement.id==draft_receipt,"explicit redraw clears dependent choices while retaining the intended room and receipt")
	host.touch.cancel()

	host.hud._begin_move("diagnosis",id)
	host.touch.choose_cell(60)
	check(host.hud.placement_details.values.size.text=="5×5","relocating a custom room displays its actual five by five footprint")
	host.touch.cancel()
	host.touch.begin_placement("reception")
	host.touch.choose_cell(60)
	check(host.hud.placement_details.values.size.text=="3×3","legacy relocation detail retains its own template footprint")
	host.touch.cancel()

	host.hud._begin_layout_edit("diagnosis",id)
	host.hud._begin_build("recovery")
	check(host.world.room_views[id].visible,"switching from layout editing to a new build restores the old room")
	host.touch.cancel()
	host.hud._begin_layout_edit("diagnosis",id)
	for _i in range(3):host.touch.advance_build_step()
	host.touch.select_furniture("bin")
	host.touch.choose_cell(130)
	var cash_before:int=host.session.sim.snapshot().cash
	host.touch.confirm()
	var committed:Dictionary=host.session.sim.snapshot()
	check(committed.rooms[id].layout.furniture.size()==2 and committed.cash==cash_before-30,"completed edit commits its real additional furniture transaction")
	check(host.world.room_views[id].visible and host.touch.free_build==null,"completed edit restores the committed room view")
	host.hud._begin_layout_edit("diagnosis",id)
	authority_before=host.session.sim.snapshot()
	host.hud._navigate("patients")
	check(host.world.room_views[id].visible and host.touch.free_build==null and host.session.sim.snapshot()==authority_before,"leaving construction restores the room without publishing the draft")

	host.hud._begin_layout_edit("diagnosis",id)
	var canvas:Node=host.hud.get_parent()
	canvas.remove_child(host.hud)
	check(host.world.room_views[id].visible,"removing the editing HUD restores the surviving world room")
	host._present()
	check(host.world.room_views[id].visible and host.hud._preview_root.get_child_count()==0,"an off-tree HUD cannot hide the room or recreate a ghost draft on a later present")
	canvas.add_child(host.hud)
	host.touch.cancel()
	host.free()
	await process_frame
	await process_frame
