extends SceneTree
var passed:=0
var failed:=0
func _initialize() -> void:_run.call_deferred()
func check(value:bool,label:String) -> void:
	if value:passed+=1
	else:failed+=1
	print(("SIMPLE PASS: " if value else "SIMPLE FAIL: ")+label)
func pose_signature(skeleton:Skeleton3D) -> String:
	var result:=""
	for bone in range(skeleton.get_bone_count()):result+=str(skeleton.get_bone_pose(bone))
	return result.sha256_text()
func _run() -> void:
	var actors:Array=[]
	for row in [["staff_002",true,"doctor"],["patient_001",false,"echo"]]:
		var actor:=ActorView.new();actor.entity_id=row[0];root.add_child(actor)
		actor.prefer_high_quality=false # This suite deliberately exercises the retained 3D rigs.
		actor.consultation_context={"heading":PI*.5,"progress":.5,"room_id":"room_1","is_staff":row[1]}
		actor.present({"role":row[2],"disease_id":"echo","cell":100,"phase":"serving" if row[1] else "diagnosis_service","room_id":"room_1"},row[1])
		actors.append(actor)
		check(actor._body_root.get_meta("presentation","")=="simplified-skinned-character","%s uses its own simple continuous 3D body"%row[0])
	if failed==0:
		for actor:ActorView in actors:
			var body:Node3D=actor._body_root
			check(actor._prerendered==null,"ordinary simple body is independent of low-frame sprite pages")
			check(body.call("can_consult"),"real exported rig includes the seated clinical sequence")
			check(body.get("clip_name")=="Consult","real service context selects Consult")
			var player:AnimationPlayer=body.get("player")
			var skeleton:Skeleton3D=body.find_children("*","Skeleton3D",true,false)[0]
			var seated_pose:=pose_signature(skeleton)
			print("SIMPLE CLIP: length=",player.get_animation(player.current_animation).length," position=",player.current_animation_position)
			check(is_equal_approx(player.current_animation_position,4.0),"actual half-service seeks exactly four seconds")
			var before:=player.current_animation_position
			body.call("advance_animation",.3)
			check(is_equal_approx(player.current_animation_position,before),"paused clinical pose is frozen")
			body.call("present_progress","Consult",.51,true,1)
			body.call("advance_animation",.025)
			check(player.current_animation_position>4.0 and player.current_animation_position<4.08,"clinical motion interpolates between real ticks")
			body.call("present_progress","Consult",.51,true,2)
			body.call("advance_animation",.0375)
			check(is_equal_approx(player.current_animation_position,player.get_animation(player.current_animation).length*.51),"same-tick speed change accelerates the remaining clinical interpolation")
			body.call("present_state","Walk",1.0,true)
			body.call("advance_animation",.13)
			check(body.get("clip_name")=="Walk" and player.current_animation_position>0,"departure restores continuous walking")
			check(pose_signature(skeleton)!=seated_pose,"walking drives the delivered skeleton rather than only an animation timer")
			body.call("present_state","Idle",1.0,false)
			before=player.current_animation_position
			body.call("advance_animation",.4)
			check(is_equal_approx(player.current_animation_position,before),"pause also freezes the ordinary rig")
		var other:=ActorView.new();other.entity_id="staff_003";root.add_child(other)
		other.present({"role":"doctor","cell":101,"phase":"idle"},true)
		check(other._body_root.get_meta("model_asset","")=="doctor-03","neighbour retains its own identity")
		var has_roster:=not CharacterRoster.entry("doctor-03").is_empty()
		check((other._simplified!=null)==has_roster,"neighbour selects its own registered body when the complete roster is installed")
		if has_roster:check(other._body_root.get_child(0).scene_file_path==CharacterRoster.model_path("doctor-03"),"neighbour uses its independently exported model rather than the original doctor body")
		other.free()
		var moving:=ActorView.new();moving.entity_id="patient_001";moving.presentation_paused=false;moving.presentation_tick=10;root.add_child(moving)
		moving.prefer_high_quality=false
		var data:={"cell":100,"phase":"moving_diagnosis","path":[100,101],"path_index":0,"move_progress":0,"disease_id":"echo"}
		moving.present(data,false)
		data.move_progress=1;moving.presentation_tick=11;moving.present(data,false)
		check(moving.position==HospitalWorld.actor_position(data),"smooth movement retains authoritative actor coordinates")
		check(is_equal_approx(moving._body_root.position.x,-.25),"body starts each new quarter-edge at the previous display point")
		moving._process(.05)
		check(is_equal_approx(moving._body_root.position.x,-.125),"actual actor body moves continuously between snapshots")
		check(is_equal_approx(moving.symptoms.position.x,-.125) and is_equal_approx(moving.cure_feedback.position.x,-.125),"head markers stay attached to the moving body")
		moving.presentation_paused=true;moving.present(data,false);moving._process(.3)
		check(is_zero_approx(moving._body_root.position.x),"same-tick pause aligns and freezes actual actor display")
		moving.free()
	for actor:ActorView in actors:actor.free()
	print("SIMPLE RESULT: passed=%d failed=%d"%[passed,failed]);quit(1 if failed else 0)
