extends SceneTree

var passed := 0
var failed := 0

func _initialize() -> void: _run.call_deferred()

func check(value: bool, label: String) -> void:
	if value: passed+=1
	else: failed+=1
	print(("SPRITE PASS: " if value else "SPRITE FAIL: ")+label)

func _run() -> void:
	var runtime_path := "res://presentation/prerendered_character.gd"
	check(ResourceLoader.exists(runtime_path),"fixed-camera prerendered actor implementation exists")
	if not ResourceLoader.exists(runtime_path):
		print("SPRITE RESULT: passed=%d failed=%d" % [passed,failed]); quit(1); return
	var runtime: Script=load(runtime_path)
	var body: Node3D=runtime.create_for("doctor-02")
	check(body!=null,"D01 manifest produces a runtime body")
	if body==null: quit(1); return
	check(body.manifest.get("source_blend","").ends_with("doctor-consult-editable.blend"),"D01 uses the editable source with repaired face masks and continuous sleeves")
	root.add_child(body)
	body.set_process(false)
	check(body.find_children("*","Skeleton3D",true,false).is_empty(),"runtime body has no skeleton evaluation")
	check(runtime.create_for("doctor-03")==null,"other people never inherit the pilot appearance")
	var sprite: Sprite3D=body.find_child("BakedCharacter",true,false)
	check(sprite!=null and not sprite.no_depth_test and not sprite.shaded,"sprite uses scene depth and does not double-light baked colors")
	check(sprite.billboard==BaseMaterial3D.BILLBOARD_FIXED_Y and not sprite.fixed_size,"vertical sprite keeps feet depth and scales with actual world zoom")
	for direction in range(8):
		body.present_state("Walk",TAU*direction/8.0,1.0)
		check(body.direction_index==direction,"world heading selects direction %d" % direction)
	body.present_state("Walk",-TAU/8.0,1.0)
	check(body.direction_index==7,"negative heading wraps without mirroring")
	body.present_state("Walk",TAU,1.0)
	check(body.direction_index==0,"full revolution wraps to original direction")
	body.advance_animation(.21)
	var elapsed: float=body.animation_time
	var frame: int=body.frame_index
	body.present_state("Walk",PI*.5,1.0)
	check(is_equal_approx(body.animation_time,elapsed) and body.frame_index==frame,"turning and repeated snapshots preserve gait phase")
	check(sprite.texture.resource_path.ends_with("walk-1.png") and sprite.region_rect.position.y==0,"direction chooses the independent high-resolution page")
	body.present_state("Examine",0,1.0)
	check(body.clip_name=="Examine" and body.frame_index==0,"state transition selects actual service clip")
	body.advance_animation(999.0)
	check(body.frame_index>=0 and body.frame_index<8,"long playback stays inside its clip region")
	body.queue_free()
	var catalog: ContentCatalog=ContentCatalog.load_checked("res://content").catalog
	var sim := Scenarios.create_sim(catalog,"benchmark_18","fast","standard")
	sim.advance_ticks(1400)
	var snapshot := sim.snapshot()
	var original := snapshot.duplicate(true)
	var world := HospitalWorld.new()
	world.prefer_simplified_characters=false
	root.add_child(world)
	world.present(snapshot)
	var actor: ActorView=world.actor_views.staff_002
	var data: Dictionary=snapshot.staff.staff_002.duplicate(true)
	check(actor._body_root.get_script()==runtime,"ordinary HospitalWorld selects the sprite for canonical D01")
	check(actor._rig_player==null and actor.left_arm==null,"sprite receives neither live skeleton nor legacy limb pivots")
	check(actor.position==HospitalWorld.actor_position(data),"presentation preserves authoritative position")
	check(is_equal_approx(actor._body_root.global_position.y,.028),"sprite feet use actual room floor height")
	check(actor._body_root.clip_name=="Consult","real-world diagnosis context selects the synchronized seated sequence")
	# The following direct-ActorView unit samples deliberately omit world context.
	actor.consultation_context={}
	data.phase="serving"; data.path=[]; data.move_progress=0
	actor.present(data,true)
	check(actor._body_root.clip_name=="Examine","real serving phase selects service sequence")
	data.phase="moving";data.cell=217;data.path=[217,218,219];data.path_index=0;data.move_progress=1
	actor.present(data,true)
	check(actor._body_root.clip_name=="Walk" and actor._body_root.direction_index==2,"real eastward path selects east walk")
	check(is_equal_approx(actor._body_root.global_position.y,.0005),"assigned staff crossing corridor uses corridor floor")
	actor._process(.1)
	data.move_progress=2;actor.present(data,true)
	var normal_cadence: float=actor._body_root.playback_speed
	actor._process(.05)
	data.move_progress=3;actor.present(data,true)
	check(actor._body_root.playback_speed>normal_cadence,"2x observed movement increases sprite cadence")
	data.cell=218;data.path_index=1;data.move_progress=0
	actor.present(data,true)
	check(actor._body_root.clip_name=="Walk","active route does not flash Idle at a cell boundary")
	data.phase="idle";data.path=[];data.move_progress=0;actor.present(data,true)
	actor._process(2.0)
	data.phase="moving";data.path=[218,219];data.path_index=0;data.move_progress=1;actor.present(data,true)
	check(is_equal_approx(actor._body_root.playback_speed,normal_cadence),"idle interval does not slow a new walking route")
	data.phase="serving";data.path=[];data.move_progress=0;actor.work_target=actor.position+Vector3(-1,0,0)
	actor.present(data,true)
	check(actor._body_root.direction_index==6,"stationary service faces actual work target")
	check(world.actor_views.staff_003._body_root.get_script()!=runtime,"normal adjacent doctor retains independent model")
	check(sim.snapshot()==original,"sprite playback never mutates authoritative simulation")
	world.free()
	print("SPRITE RESULT: passed=%d failed=%d" % [passed,failed])
	quit(1 if failed else 0)
