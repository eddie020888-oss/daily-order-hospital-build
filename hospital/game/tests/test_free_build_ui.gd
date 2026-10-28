extends SceneTree
var passed:=0
var failed:=0
func _initialize() -> void:_run.call_deferred()
func check(value:bool,label:String) -> void:
	if value:passed+=1
	else:failed+=1
	print(("FREE UI PASS: " if value else "FREE UI FAIL: ")+label)
func _run() -> void:
	root.size=Vector2i(1280,720)
	var catalog:ContentCatalog=ContentCatalog.load_checked("res://content").catalog
	var host:Node3D=load("res://main.gd").new()
	host.session=GameSession.new(catalog,"E:/CODEX/2026-10-19/医院自由建造/temp/ui-unused-save")
	root.add_child(host);host.set_process(false);host.hud.flow.close()
	host.feedback.set_application_active(false)
	host.feedback._music_player.stop()
	check(host.touch.has_method("begin_free_build"),"free building controller is available")
	if failed>0:host.free();finish();return
	host.hud._begin_build("diagnosis")
	check(host.touch.get("free_build")!=null,"normal construction palette opens the free room workflow")
	if host.touch.get("free_build")==null:host.free();finish();return
	var before:Dictionary=host.session.sim.snapshot()
	host.touch.choose_cell(100);host.touch.choose_cell(175)
	check(host.session.sim.snapshot()==before,"drawing room bounds does not change money or model")
	host.hud.controls.confirm.pressed.emit()
	check(host.touch.free_build.step==1,"first confirmation advances to placing the door")
	host.touch.choose_cell(174);host.hud.controls.confirm.pressed.emit()
	check(host.touch.free_build.step==2,"door choice advances to equipment placement")
	check(host.session.sim.snapshot()==before,"choosing the door does not purchase an unfinished room")
	host.touch.choose_cell(101);host.hud.controls.confirm.pressed.emit()
	check(host.touch.free_build.step==3,"valid required equipment advances to optional furnishings")
	if host.touch.free_build.step!=3:host.free();finish();return
	host.touch.free_build.select_furniture("plant");host.touch.choose_cell(148)
	check(host.session.sim.snapshot()==before,"furniture remains part of the local draft")
	host.hud.controls.confirm.pressed.emit();host.hud.controls.confirm.pressed.emit()
	var after:Dictionary=host.session.sim.snapshot()
	check(after.rooms.size()==1,"final double confirmation builds exactly one room")
	if after.rooms.size()==1:
		var room:Dictionary=after.rooms.values()[0]
		check(room.has("layout") and room.layout.width==4 and room.layout.height==4,"normal UI commits the player-defined rectangle")
		check(room.layout.footprint_version==2 and room.equipment_cells.size()==4,"normal UI commits the new diagnosis two-by-two body mask")
		check(room.layout.furniture.size()==1 and room.layout.furniture[0].kind=="plant","normal UI commits chosen furniture")
		check(after.cash==7070,"one version2 charge includes four extra floor cells and the optional plant")
		var view:RoomView=host.world.room_views[after.rooms.keys()[0]]
		check(view.find_child("PlayerFurniture",true,false)!=null,"player furniture is rendered in the real room")
		check(SnapshotValidator.validate(after,catalog)=="","completed UI construction is a valid save state")
		host.hud._begin_layout_edit("diagnosis",after.rooms.keys()[0])
		check(not view.visible,"layout editing hides the original room while its independent draft is shown")
		host.touch.cancel()
		check(view.visible,"cancel restores the unchanged original room")
		var id:String=after.rooms.keys()[0]
		host.session.issue("close_room",{"room_id":id})
		var expanded:Dictionary=room.layout.duplicate(true);expanded.width=5
		check(host.session.issue("move_room",{"room_id":id,"origin_cell":100,"rotation":0,"layout":expanded}).ok,"empty room can expand before a whole-room move")
		host.hud._begin_move("diagnosis",id);host.touch.choose_cell(106)
		check(host.hud.placement_details.values.size.text=="5×4","whole-room relocation displays the actual custom dimensions")
		host.touch.cancel()
		after=host.session.sim.snapshot()
	host.hud._begin_build("diagnosis");host.touch.choose_cell(106);host.touch.choose_cell(181);host.touch.cancel()
	check(host.session.sim.snapshot().cash==after.cash and host.session.sim.snapshot().rooms.size()==1,"cancelled construction cannot charge or leave a phantom room")
	# A completed edit draft exercises all three pinned footer actions on a short
	# high-density phone layout; scrolling content must not push them off-screen.
	var existing_id:String=after.rooms.keys()[0]
	host.hud._begin_layout_edit("diagnosis",existing_id)
	for _i in range(3):host.hud.controls.confirm.pressed.emit()
	for row in [[Vector2(1280,720),Vector2(1280,720),160],[Vector2(2560,1440),Vector2(1280,720),640]]:
		host.hud.configure_display(row[0],row[1],row[2],Rect2(Vector2.ZERO,row[0]))
		for _i in range(4):await process_frame
		var screen:=Rect2(Vector2.ZERO,Vector2(root.size))
		for key in ["cancel","build_back","confirm"]:
			var button:Button=host.hud.controls[key]
			var rect:=button.get_global_rect()
			print("FREE UI LAYOUT: ",row[2]," ",key," screen=",screen," rect=",rect," visible=",button.is_visible_in_tree()," step=",host.touch.free_build.step," notice=",host.hud._notice_panel.visible)
			check(button.is_visible_in_tree() and screen.encloses(rect),"%d DPI %s action stays within the phone viewport"%[row[2],key])
		check(not host.hud.controls.confirm.get_global_rect().intersects(host.hud.controls.build_back.get_global_rect()),"phone footer actions remain separate touch targets")
	host.touch.cancel()
	host.free();finish()
func finish() -> void:
	await process_frame
	await process_frame
	print("FREE UI RESULT: passed=%d failed=%d"%[passed,failed]);quit(1 if failed else 0)
