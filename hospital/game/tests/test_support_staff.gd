extends SceneTree

var passed:=0
var failed:=0
var fixture_root:="E:/CODEX/2026-10-20/医院整体画面继续优化/temp/support-factory-%d"%Time.get_ticks_usec()

func _initialize() -> void:_run.call_deferred()

func check(value:bool,label:String) -> void:
	if value:passed+=1
	else:failed+=1
	print(("SUPPORT PASS: " if value else "SUPPORT FAIL: ")+label)

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(fixture_root)
	_existing_consult_compatibility()
	_three_clip_factory()
	_required_clip_is_not_optional()
	# Root enables this stage only after exporting/copying the actual two models
	# and installing their canonical maps; default RED/GREEN remains asset-free.
	if "--assets" in OS.get_cmdline_user_args():_actual_staff_assets()
	print("SUPPORT RESULT: passed=%d failed=%d"%[passed,failed])
	quit(1 if failed else 0)

func _existing_consult_compatibility() -> void:
	for canonical in ["doctor-02","patient-01"]:
		var body:=SimplifiedCharacter.create_for(canonical)
		check(body!=null,"existing %s still loads its actual exported four-clip model"%canonical)
		if body==null:continue
		root.add_child(body)
		check(body.can_consult(),"existing %s retains its genuine Consult capability"%canonical)
		body.present_progress("Consult",.5,false,1)
		check(body.clip_name=="Consult" and is_equal_approx(body.player.current_animation_position,4.0),"existing %s seeks the real eight-second clinical clip"%canonical)
		check(body.player.get_animation(body.clips.Consult).loop_mode==Animation.LOOP_NONE,"existing %s keeps Consult non-looping"%canonical)
		body.free()

func _fixture_factory(names:Array,path:String) -> Script:
	# A real packed skeleton and AnimationPlayer exercise the production factory.
	# Only the input resource path is changed; no production test seam or missing
	# future staff asset is required to demonstrate the three-clip rejection.
	var scene:=Node3D.new()
	var skeleton:=Skeleton3D.new()
	skeleton.name="Skeleton3D";scene.add_child(skeleton);skeleton.owner=scene
	skeleton.add_bone("head")
	var player:=AnimationPlayer.new()
	player.name="AnimationPlayer";scene.add_child(player);player.owner=scene
	var library:=AnimationLibrary.new()
	for clip:String in names:
		var animation:=Animation.new()
		animation.length=2.0 if clip=="Idle" else 32.0/30.0 if clip=="Walk" else 2.4
		var track:=animation.add_track(Animation.TYPE_ROTATION_3D)
		animation.track_set_path(track,NodePath("Skeleton3D:head"))
		animation.track_insert_key(track,0.0,Quaternion.IDENTITY)
		animation.track_insert_key(track,animation.length*.5,Quaternion(Vector3.RIGHT,.7))
		animation.track_insert_key(track,animation.length,Quaternion.IDENTITY)
		library.add_animation(clip,animation)
	player.add_animation_library("",library)
	var packed:=PackedScene.new()
	var packed_ok:bool=packed.pack(scene)==OK
	check(packed_ok and ResourceSaver.save(packed,path)==OK,"real %s fixture is packed before exercising the factory"%str(names))
	scene.free()
	var factory:=GDScript.new()
	factory.source_code=FileAccess.get_file_as_string("res://presentation/simplified_character.gd").replace("class_name SimplifiedCharacter","").replace("res://assets/models/simple-clinic-v3/doctor-02.glb",path)
	check(factory.reload()==OK,"production factory compiles with the independent existing fixture path")
	return factory

func _three_clip_factory() -> void:
	var factory:=_fixture_factory(["Idle","Walk","Examine"],fixture_root+"/three-clips.tscn")
	if not factory.can_instantiate():return
	var body:Variant=factory.call("create_for","doctor-02")
	check(body!=null,"three required clips create a playable support character without inventing Consult")
	if body==null:return
	root.add_child(body)
	check(not body.can_consult(),"three-clip staff does not advertise a seated diagnosis sequence")
	var skeleton:Skeleton3D=body.find_child("Skeleton3D",true,false)
	body.present_state("Walk",1.0,true);body.advance_animation(.2)
	check(body.clip_name=="Walk" and body.player.current_animation_position>0 and not skeleton.get_bone_pose_rotation(0).is_equal_approx(Quaternion.IDENTITY),"walking advances the fixture's real skeleton")
	body.present_state("Walk",1.0,false)
	var before:float=body.player.current_animation_position
	body.advance_animation(.4)
	check(is_equal_approx(body.player.current_animation_position,before),"pausing freezes a three-clip staff model")
	body.present_state("Walk",2.0,true);body.advance_animation(.1)
	check(is_equal_approx(body.player.current_animation_position,before+.2),"staff playback honors the requested double speed")
	body.present_state("Examine",1.0,true);body.advance_animation(.2)
	check(body.clip_name=="Examine" and body.player.get_animation(body.clips.Examine).loop_mode==Animation.LOOP_LINEAR,"serving selects the real repeatable work gesture")
	body.present_progress("Consult",.5,true,1)
	check(body.clip_name=="Examine","an unavailable Consult request preserves the genuine staff work gesture")
	for row in [["receptionist-01",6.1538461538],["technician-03",5.9259259259]]:
		body.set_meta("model_asset",row[0])
		body.present_state("Walk",row[1],true);body.player.seek(0,true)
		body.advance_animation(.04)
		check(is_equal_approx(body.player.current_animation_position,.04*row[1]),"%s supports its real double-speed gait above the old three-times cap"%row[0])
	body.set_meta("model_asset","doctor-02")
	body.present_state("Walk",6.1538461538,true);body.player.seek(0,true);body.advance_animation(.04)
	check(is_equal_approx(body.player.current_animation_position,.12),"existing doctor retains its original three-times animation cap")
	body.free()

func _required_clip_is_not_optional() -> void:
	var factory:=_fixture_factory(["Idle","Walk","Consult"],fixture_root+"/missing-examine.tscn")
	if not factory.can_instantiate():return
	var body:Variant=factory.call("create_for","doctor-02")
	check(body==null,"optional Consult cannot substitute for the mandatory work gesture")
	if body!=null:body.free()

func _pose_signature(skeleton:Skeleton3D,rest:bool=false) -> String:
	var result:=""
	for index in range(skeleton.get_bone_count()):
		result+=str(skeleton.get_bone_rest(index) if rest else skeleton.get_bone_pose(index))
	return result.sha256_text()

func _actual_staff_assets() -> void:
	var rest_signatures:Array[String]=[]
	for row in [["staff_001","receptionist","receptionist-01","R01"],["staff_003","technician","technician-03","T01"]]:
		var actor:=ActorView.new()
		actor.entity_id=row[0];actor.presentation_paused=false
		root.add_child(actor)
		var data:={"role":row[1],"cell":100,"phase":"idle","room_id":"room_1"}
		actor.present(data,true)
		var body:Variant=actor._simplified
		check(body!=null and actor._prerendered==null,"actual %s selects its own new continuous support body"%row[0])
		if body==null:actor.free();continue
		var skeletons:Array=body.find_children("*","Skeleton3D",true,false)
		check(skeletons.size()==1 and skeletons[0].get_bone_count()==20,"actual %s exports its own twenty-bone skeleton"%row[2])
		check(body.clips.size()==3 and not body.can_consult(),"actual %s uses genuine role motion without a fake seated Consult"%row[2])
		if skeletons.size()!=1:actor.free();continue
		var skeleton:Skeleton3D=skeletons[0]
		rest_signatures.append(_pose_signature(skeleton,true))
		data.phase="moving_assignment";data.path=[100,101];data.path_index=0;data.move_progress=1
		actor.presentation_tick+=1
		actor.present(data,true)
		var before:=_pose_signature(skeleton)
		actor._process(.23)
		check(body.clip_name=="Walk" and _pose_signature(skeleton)!=before,"actual %s walking deforms its exported skeleton"%row[2])
		actor.presentation_paused=true;actor.present(data,true)
		before=_pose_signature(skeleton)
		actor._process(.5)
		check(_pose_signature(skeleton)==before,"actual %s pauses without bone drift"%row[2])
		actor.presentation_paused=false;data.phase="serving";data.path=[];data.move_progress=0
		actor.present(data,true)
		before=_pose_signature(skeleton)
		actor._process(.55)
		check(body.clip_name=="Examine" and _pose_signature(skeleton)!=before,"actual %s serving plays its newly authored role gesture"%row[2])
		check(actor.left_arm==null and body.find_child("ArmLJoint",true,false)==null,"actual %s receives no legacy rigid-part wrapper"%row[2])
		var portrait:=SceneArtLibrary.portrait(row[1],SceneArtLibrary.ordinal(row[0]))
		check(not portrait is AtlasTexture and portrait.resource_path.begins_with("res://assets/models/simple-support-v") and portrait.get_meta("model_asset","")==row[2] and portrait.get_meta("artwork_source_id","")==row[3],"actual %s detail portrait belongs to the same new model and reference identity"%row[2])
		_stance_contact(body,skeleton,row[2],.8125 if row[3]=="R01" else .84375)
		_actor_stance_contact(actor,body,skeleton,row[1],row[2])
		actor.free()
	check(rest_signatures.size()==2 and rest_signatures[0]!=rest_signatures[1],"R01 and T01 have independently placed rest joints")
	for row in [["staff_002","receptionist","receptionist-02"],["staff_004","technician","technician-04"]]:
		var neighbour:=ActorView.new();neighbour.entity_id=row[0];root.add_child(neighbour)
		neighbour.present({"role":row[1],"cell":101,"phase":"idle"},true)
		var has_roster:=not CharacterRoster.entry(row[2]).is_empty()
		check((neighbour._simplified!=null)==has_roster and neighbour.get_meta("model_asset","")==row[2],"adjacent %s keeps its identity and selects its own registered body"%row[2])
		if has_roster:check(neighbour._simplified.get_child(0).scene_file_path==CharacterRoster.model_path(row[2]),"adjacent %s uses its independent exported asset"%row[2])
		neighbour.free()

func _foot_world(skeleton:Skeleton3D,index:int) -> Vector3:
	return (skeleton.global_transform*skeleton.get_bone_global_pose(index)).origin

func _stance_contact(body:Variant,skeleton:Skeleton3D,canonical:String,source_speed:float) -> void:
	var foot:int=skeleton.find_bone("foot.L")
	check(foot>=0,"actual %s has its authored stance foot"%canonical)
	if foot<0:return
	var initial_position:Vector3=body.position
	for velocity:float in [2.5,5.0]:
		body.position=initial_position
		body.rotation.y=0
		body.present_state("Walk",velocity/source_speed,true)
		body.advance_animation(.2) # Settle the transition before measuring stance.
		body.player.seek(body.player.get_animation(body.clips.Walk).length*.1,true)
		var before:=_foot_world(skeleton,foot)
		# Source -Y forward becomes +Z in exported glTF. Both samples are within
		# left stance (.10.. .33 of the cycle), not swing or the loop seam.
		body.position+=Vector3(0,0,velocity*.04)
		body.advance_animation(.04)
		var slip:float=_foot_world(skeleton,foot).distance_to(before)
		var tilt:float=skeleton.get_bone_global_pose(foot).basis.get_rotation_quaternion().angle_to(skeleton.get_bone_global_rest(foot).basis.get_rotation_quaternion())
		print("SUPPORT STANCE: ",canonical," velocity=",velocity," slip_m=",slip," foot_tilt_rad=",tilt)
		check(slip<.008 and tilt<.015,"%s stance foot stays planted and flat at %.1f metres per second"%[canonical,velocity])
	body.position=initial_position

func _actor_stance_contact(actor:ActorView,body:Variant,skeleton:Skeleton3D,role:String,canonical:String) -> void:
	var foot:int=skeleton.find_bone("foot.L")
	if foot<0:return
	for speed:int in [1,2]:
		actor.presentation_speed=speed
		actor.presentation_paused=false
		actor.presentation_tick=100+speed*10
		actor.present({"role":role,"cell":100,"phase":"idle","move_progress":0},true)
		actor.presentation_tick+=1
		actor.present({"role":role,"cell":100,"phase":"moving_assignment","path":[100,124],"path_index":0,"move_progress":1},true)
		body.advance_animation(.2)
		body.player.seek(body.player.get_animation(body.clips.Walk).length*.1,true)
		var before:=_foot_world(skeleton,foot)
		actor._process(.04)
		var slip:float=_foot_world(skeleton,foot).distance_to(before)
		print("SUPPORT ACTOR STANCE: ",canonical," presentation_speed=",speed," slip_m=",slip)
		check(slip<.008,"actual %s ActorView matches gait to displayed movement at %dx"%[canonical,speed])
		if speed==2:
			# Only .01 seconds of the real segment remain; a .04 render frame
			# must advance the foot by that remaining distance, not a full stride.
			before=_foot_world(skeleton,foot);actor._process(.04)
			check(_foot_world(skeleton,foot).distance_to(before)<.008,"actual %s keeps stance contact through a partial final display frame"%canonical)
			before=_foot_world(skeleton,foot);actor._process(.04)
			check(_foot_world(skeleton,foot).distance_to(before)<.001,"actual %s cannot drift its planted foot after the display segment ends"%canonical)
