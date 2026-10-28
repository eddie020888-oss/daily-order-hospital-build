extends SceneTree
var passed := 0
var failed := 0
func _initialize() -> void: _run.call_deferred()
func check(value: bool,label: String) -> void:
	if value:passed+=1
	else:failed+=1
	print(("CONSULT PASS: " if value else "CONSULT FAIL: ")+label)
func _run() -> void:
	var doctor := PrerenderedCharacter.create_for("doctor-02")
	var patient := PrerenderedCharacter.create_for("patient-01")
	check(doctor!=null and doctor.manifest.clips.has("Consult"),"D01 has the independently authored consultation sequence")
	check(patient!=null,"only P01 receives its independent new patient body")
	check(PrerenderedCharacter.create_for("patient-02")==null,"adjacent patients retain their own appearance")
	if doctor!=null:
		var invalid:=doctor.manifest.duplicate(true)
		invalid.clips.Consult.pages[0]="portrait.png"
		var rejected:=PrerenderedCharacter.create_from_manifest("doctor-02",invalid,doctor._directory)
		check(rejected==null,"malformed optional consultation pages reject before partial construction")
		if rejected!=null:rejected.free()
	check(doctor!=null and doctor.has_method("present_progress"),"service animation has a simulation-driven presentation entry")
	if doctor!=null and doctor.has_method("present_progress") and doctor.manifest.clips.has("Consult"):
		root.add_child(doctor)
		doctor.call("present_progress","Consult",PI*.5,.5)
		check(doctor.frame_index==8 and doctor.direction_index==2,"halfway actual consultation selects its middle pose and room heading")
		doctor.advance_animation(30)
		check(doctor.frame_index==8,"paused service cannot advance from wall-clock time")
		doctor.call("present_progress","Consult",PI*.5,1.0)
		check(doctor.frame_index==15,"completed service uses standing end frame rather than looping to start")
		doctor.call("present_progress","Consult",0,-1.0)
		check(doctor.frame_index==0,"early timeline clamps at the initial standing pose")
		doctor.present_state("Walk",0,1)
		doctor.advance_animation(.4)
		check(doctor.frame_index>0,"leaving consultation restores ordinary gait playback")
	var helper_path := "res://presentation/consultation_view.gd"
	check(ResourceLoader.exists(helper_path),"consultation placement uses actual room and slot context")
	if ResourceLoader.exists(helper_path):
		var helper: Script=load(helper_path)
		var catalog: ContentCatalog=ContentCatalog.load_checked("res://content").catalog
		_test_empty_chairs(catalog)
		var sim := Scenarios.create_sim(catalog,"benchmark_18","fast","standard")
		var found := false
		for _i in range(2000):
			sim.advance_ticks(1)
			var snap:=sim.snapshot()
			for id in snap.patients:
				if snap.patients[id].phase!="diagnosis_service":continue
				found=true
				var original:=snap.duplicate(true)
				var context: Dictionary=helper.context(snap,id,false)
				check(not context.is_empty(),"real diagnosis service produces a consultation context")
				if not context.is_empty():
					var room: Dictionary=snap.rooms[snap.patients[id].room_id]
					var staff_context: Dictionary=helper.context(snap,room.staff_id,true)
					check(is_equal_approx(context.progress,staff_context.progress),"doctor and patient share the actual service clock")
					check(is_equal_approx(absf(wrapf(context.heading-staff_context.heading,-PI,PI)),PI),"the two seats face each other")
				check(snap==original,"presentation context never changes the simulation snapshot")
				break
			if found:break
		check(found,"genuine simulation reaches diagnosis")
		if found:
			var snap:=sim.snapshot()
			var patient_id: String="patient_000001"
			var diagnosis_id: String=snap.patients[patient_id].room_id
			for rotation in range(4):
				var rotated:=snap.duplicate(true)
				var geometry:=GridService._room_geometry({"kind":"diagnosis","origin_cell":100,"rotation":rotation})
				geometry.staff_id="staff_002";rotated.rooms[diagnosis_id]=geometry
				rotated.staff.staff_002.cell=geometry.staff_cells[0]
				rotated.patients[patient_id].cell=geometry.service_cells[0]
				for slot in rotated.slots.values():
					if slot.room_id==diagnosis_id:slot.cell=geometry.service_cells[0];slot.remaining_ticks=40
				var a: Dictionary=helper.context(rotated,"staff_002",true)
				var b: Dictionary=helper.context(rotated,patient_id,false)
				check(not a.is_empty() and not b.is_empty() and is_equal_approx(a.progress,.5) and is_equal_approx(b.progress,.5),"rotation %d keeps both actors on the same service timeline" % rotation)
				check(not a.is_empty() and is_zero_approx(wrapf(a.heading-[-PI*.5,PI,PI*.5,0][rotation],-PI,PI)),"rotation %d follows the literal rotated seats" % rotation)
			var world:=HospitalWorld.new();root.add_child(world);world.present(snap)
			var fallback:=snap.duplicate(true)
			var room_id: String=fallback.staff.staff_002.room_id
			fallback.staff.staff_003=fallback.staff.staff_002.duplicate(true)
			fallback.staff.erase("staff_002");fallback.rooms[room_id].staff_id="staff_003"
			fallback.patients.patient_000002=fallback.patients.patient_000001.duplicate(true);fallback.patients.erase("patient_000001")
			for slot in fallback.slots.values():
				if slot.patient_id=="patient_000001":slot.patient_id="patient_000002"
			world.present(fallback)
			var room_view: RoomView=world.room_views[room_id]
			var registered:=not CharacterRoster.entry("doctor-03").is_empty() and not CharacterRoster.entry("patient-02").is_empty()
			check(room_view._consult_chairs[true].visible==registered and room_view._consult_chairs[false].visible==registered,"registered consultation identities use real chairs while old rigid fallback keeps them hidden")
			check(_contacts_match(room_view,registered,registered),"chair contacts follow the actual identities' seated animation capability")
			if registered:
				check(world.actor_views.staff_003._simplified.clip_name=="Consult" and world.actor_views.patient_000002._simplified.clip_name=="Consult","new clinician and patient actually play their genuine seated clips")
			var rigid_world:=HospitalWorld.new()
			rigid_world.prefer_simplified_characters=false
			root.add_child(rigid_world);rigid_world.present(fallback)
			var rigid_room:RoomView=rigid_world.room_views[room_id]
			check(not rigid_room._consult_chairs[true].visible and not rigid_room._consult_chairs[false].visible,"explicit rigid identities never stand inside consultation chairs")
			check(_contacts_match(rigid_room,false,false),"hidden rigid fallback chairs leave no separate or merged contacts")
			rigid_world.free()
			world.present(snap)
			check(room_view._consult_chairs[true].visible and room_view._consult_chairs[false].visible,"independent 3D consultation restores both real chairs")
			check(_contacts_match(room_view,true,true),"restored 3D chairs retain their live unbatched contacts")
			var legacy_world:=HospitalWorld.new()
			legacy_world.prefer_simplified_characters=false
			root.add_child(legacy_world);legacy_world.present(snap)
			var legacy_room:RoomView=legacy_world.room_views[room_id]
			check(not legacy_room._consult_chairs[true].visible and not legacy_room._consult_chairs[false].visible,"legacy 2D consultation keeps its baked chairs without duplicate 3D chairs")
			check(_contacts_match(legacy_room,false,false),"legacy baked-chair consultation also hides both independent chair contacts")
			legacy_world.free()
			var fresh:=ClinicState.create("level_01",catalog)
			world.present(Simulation.new(catalog,fresh).snapshot())
			check(world.actor_views.is_empty() and world.room_views.is_empty(),"restart removes old consultation actors before accessing their deleted rooms")
			world.free()
	if doctor!=null:doctor.free()
	if patient!=null:patient.free()
	var library:=GDScript.new()
	library.source_code=FileAccess.get_file_as_string("res://presentation/scene_art_library.gd").replace("class_name SceneArtLibrary","").replace("res://assets/characters-prerendered/patient-01-consult-v1/portrait.png","res://assets/missing-pilot-portrait.png").replace(SceneArtLibrary.SIMPLE_PORTRAITS["patient-01"],"res://assets/missing-simple-portrait.png")
	# This fixture checks the original atlas fallback with every pilot portrait disabled.
	library.source_code=library.source_code.replace("PrerenderedCharacter.high_quality_portrait_path(canonical)","String()")
	check(library.reload()==OK,"independent missing-portrait fixture compiles")
	if library.can_instantiate():
		var portrait: Variant=library.call("portrait","patient",0)
		check(portrait is AtlasTexture,"missing pilot portrait safely uses its original identity atlas")
	print("CONSULT RESULT: passed=%d failed=%d" % [passed,failed]);quit(1 if failed else 0)

func _contacts_match(room_view:RoomView,staff_visible:bool,patient_visible:bool) -> bool:
	if room_view._consult_contacts.size()!=2:return false
	for is_staff in [true,false]:
		var contact:Node3D=room_view._consult_contacts.get(is_staff)
		if not is_instance_valid(contact) or contact.is_queued_for_deletion() or contact.get_parent()!=room_view:return false
		if contact.visible!=(staff_visible if is_staff else patient_visible):return false
	return true

func _test_empty_chairs(catalog:ContentCatalog) -> void:
	var state:=ClinicState.create("level_01",catalog)
	state.data.unlocked_room_kinds=Scenarios.ROOM_KINDS.duplicate()
	var sim:=Simulation.new(catalog,state)
	var built:Dictionary=sim.submit({"id":"empty_diagnosis","type":"build_room","payload":{"kind":"diagnosis","origin_cell":100,"rotation":0}})
	check(built.ok,"empty diagnosis fixture is constructed through its real command")
	if not built.ok:return
	var world:=HospitalWorld.new()
	# doctor-01 now has a registered rig; explicitly retain this fixture's rigid fallback.
	world.prefer_simplified_characters=false
	root.add_child(world);world.present(sim.snapshot())
	var room_view:RoomView=world.room_views[built.data.room_id]
	check(room_view._consult_chairs[true].visible and room_view._consult_chairs[false].visible,"unassigned empty diagnosis room displays both purchased real chairs")
	check(_contacts_match(room_view,true,true),"empty-room chair contacts remain real nodes excluded from static batching")
	room_view.hide_consult_chair(false)
	check(not room_view._consult_chairs[false].visible and _contacts_match(room_view,true,false),"hiding one baked chair hides exactly its contact")
	room_view.set_consult_chair_visibility(true,true)
	check(_contacts_match(room_view,true,true),"chair and contact visibility can be restored after a hide")
	# The first hired doctor keeps the original doctor-01 fallback identity.
	# An occupied standing fallback must hide its chair, while the unoccupied
	# patient seat remains visible independently of the doctor's capabilities.
	var hire:Dictionary=sim.submit({"id":"fallback_doctor","type":"hire_staff","payload":{"role":"doctor"}})
	check(hire.ok,"fallback doctor is hired through the normal command")
	if hire.ok:
		var assignment:Dictionary=sim.submit({"id":"fallback_assign","type":"assign_staff","payload":{"staff_id":hire.data.staff_id,"room_id":built.data.room_id}})
		check(assignment.ok,"fallback doctor has a real room assignment")
		if assignment.ok:
			world.present(sim.snapshot())
			check(not room_view._consult_chairs[true].visible and room_view._consult_chairs[false].visible,"standing fallback staff does not hide an empty patient chair")
			check(_contacts_match(room_view,false,true),"staff and patient contacts follow independent real occupancy")
	world.free()
