extends SceneTree

# Focused normal-runtime integration checks. No native window or APK is needed.
var passed := 0
var failed := 0

func _initialize() -> void: _run.call_deferred()

func check(value: bool, label: String) -> void:
	if value: passed+=1
	else: failed+=1
	print(("D01 PASS: " if value else "D01 FAIL: ")+label)

func pose_signature(skeleton: Skeleton3D) -> String:
	var poses := ""
	for bone in range(skeleton.get_bone_count()): poses+=str(skeleton.get_bone_pose(bone))
	return poses.sha256_text()

func _run() -> void:
	var model := SceneArtLibrary.character("doctor","staff_002")
	var skeletons := model.find_children("*","Skeleton3D",true,false)
	var players := model.find_children("*","AnimationPlayer",true,false)
	check(skeletons.size()==1 and skeletons[0].get_bone_count()==20,"canonical doctor-02 uses the actual 20-bone D01 runtime model")
	check(players.size()==1,"normal character resource includes its real AnimationPlayer")
	var other := SceneArtLibrary.character("doctor","staff_003")
	check(other.find_children("*","Skeleton3D",true,false).is_empty() and other.find_child("Body",true,false)!=null,"doctor-03 retains its independent existing body")
	other.free()
	var portrait := SceneArtLibrary.portrait("doctor",1)
	check(portrait.resource_path=="res://assets/models/simple-clinic-v1/doctor-02-portrait.png" and portrait.get_meta("model_asset","")=="doctor-02","only canonical doctor-02 receives its current simplified portrait")
	check(SceneArtLibrary.portrait("doctor",2) is AtlasTexture,"other doctor portraits retain their existing atlas identity")
	model.free()
	if skeletons.is_empty() or players.is_empty():
		check(false,"normal runtime must be rigged before behavior checks can run")
		quit(1); return
	var catalog: ContentCatalog=ContentCatalog.load_checked("res://content").catalog
	var sim := Scenarios.create_sim(catalog,"benchmark_18","fast","standard")
	sim.advance_ticks(1400)
	var snapshot := sim.snapshot()
	var original := snapshot.duplicate(true)
	var world := HospitalWorld.new()
	root.add_child(world)
	# Source-rig fallback remains independently supported; ordinary 2.5D game
	# selection is exercised by test_prerendered_character.gd.
	var fallback := ActorView.new()
	fallback.entity_id="staff_002"
	fallback.prefer_prerendered=false
	fallback.prefer_simplified=false
	world._actor_root.add_child(fallback)
	world.actor_views.staff_002=fallback
	world.present(snapshot)
	var actor: ActorView=world.actor_views.staff_002
	var actor_data: Dictionary=snapshot.staff.staff_002
	var runtime_player := actor._body_root.find_child("AnimationPlayer",true,false) as AnimationPlayer
	check(runtime_player!=null,"explicit 3D fallback retains rigged doctor-02")
	if runtime_player==null:
		world.free(); quit(1); return
	check(actor.left_arm==null and actor._body_root.find_child("ArmLJoint",true,false)==null,"real rig receives no legacy joint wrappers")
	check(actor.position==HospitalWorld.actor_position(actor_data),"authoritative actor position is unchanged by foot placement")
	check(is_equal_approx(actor._body_root.global_position.y,.028),"doctor in diagnosis room stands on actual room floor top")
	actor_data.phase="idle";actor_data.path=[];actor_data.move_progress=0
	actor.present(actor_data,true)
	var skeleton: Skeleton3D=actor._body_root.find_children("*","Skeleton3D",true,false)[0]
	check(String(runtime_player.current_animation).get_file()=="Idle","actual idle state selects Idle")
	var idle_time := runtime_player.current_animation_position
	runtime_player.advance(.1)
	actor.present(actor_data,true)
	check(runtime_player.current_animation_position>idle_time,"repeated snapshots preserve current clip time")
	var idle_pose := pose_signature(skeleton)
	actor_data.phase="serving";actor.present(actor_data,true)
	check(String(runtime_player.current_animation).get_file()=="Examine","actual serving state selects communication lift clip")
	runtime_player.advance(.8)
	check(pose_signature(skeleton)!=idle_pose,"serving clip drives actual skeleton transforms")
	actor_data.phase="moving";actor_data.cell=217;actor_data.room_id="room_002";actor_data.path=[217,218,219];actor_data.path_index=0;actor_data.move_progress=1
	actor.present(actor_data,true)
	check(String(runtime_player.current_animation).get_file()=="Walk","actual movement selects Walk before serving")
	runtime_player.advance(.03)
	check(pose_signature(skeleton)!=idle_pose,"walking clip drives actual skeleton transforms")
	check(runtime_player.get_animation(runtime_player.current_animation).loop_mode==Animation.LOOP_LINEAR,"runtime walk loops its authored seam")
	check(is_equal_approx(actor._body_root.global_position.y,.0005),"assigned doctor still uses hall floor while physically in hall")
	actor._process(.1)
	actor_data.move_progress=2;actor.present(actor_data,true)
	var normal_cadence:=runtime_player.speed_scale
	check(normal_cadence>=1.0 and normal_cadence<=2.0,"1x quarter-cell navigation keeps a readable walking cadence")
	actor._process(.05)
	actor_data.move_progress=3;actor.present(actor_data,true)
	check(runtime_player.speed_scale>normal_cadence and runtime_player.speed_scale<=2.40001,"observed 2x motion increases cadence within the mobile animation limit")
	print("D01 CADENCE: normal=%.4f double=%.4f" % [normal_cadence,runtime_player.speed_scale])
	actor_data.cell=218;actor_data.path_index=1;actor_data.move_progress=0
	actor.present(actor_data,true)
	check(String(runtime_player.current_animation).get_file()=="Walk","cell boundary at progress zero does not flash Idle during an active route")
	actor_data.phase="idle";actor_data.path=[];actor_data.move_progress=0;actor.present(actor_data,true)
	actor._process(2.0)
	actor_data.phase="moving";actor_data.path=[218,219];actor_data.path_index=0;actor_data.move_progress=1;actor.present(actor_data,true)
	check(is_equal_approx(runtime_player.speed_scale,normal_cadence),"a long idle interval cannot slow the first walking step")
	check(sim.snapshot()==original,"rig state changes and playback never mutate simulation")
	world.free()
	print("D01 RESULT: passed=%d failed=%d" % [passed,failed])
	quit(1 if failed else 0)
