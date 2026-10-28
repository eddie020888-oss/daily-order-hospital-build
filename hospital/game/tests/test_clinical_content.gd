extends SceneTree

var passed := 0
var failed := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	if value: passed += 1
	else:
		failed += 1
		print("FAIL: "+message)

func _run() -> void:
	var loaded := ContentCatalog.load_checked("res://content")
	check(loaded.ok,"expanded catalog loads")
	if not loaded.ok:
		print(loaded.error)
		quit(1)
		return
	var c: ContentCatalog = loaded.catalog
	check(c.rooms.size()==9 and c.diseases.size()==6 and c.staff.size()==4 and c.levels.has("level_01") and c.levels.has("clinical_02") and c.campaign.levels.size()==24 and c.campaign.long_form.levels.size()==12 and c.levels.size()==26,"legacy9 rooms /6 diseases /4 roles /2 levels preserved alongside12 original and12 long career levels")
	for row in [["general_exam",900,"doctor",160,1,0],["pharmacy",1000,"nurse",120,1,15],["ward",1800,"nurse",300,2,30]]:
		var r: Dictionary = c.rooms[row[0]]
		check([r.cost,r.staff_role,r.service_ticks,r.capacity,r.consumable_cost]==row.slice(1),"clinical purchase/service contract "+row[0])
	check([c.staff.nurse.hire_cost,c.staff.nurse.daily_wage]==[250,40],"nurse purchase/wage contract")
	var level: Dictionary = c.levels.clinical_02
	check([level.initial_cash,level.day_ticks,level.end_tick,level.patience_ticks,level.max_staff,level.max_patients]==[15000,1200,12000,2400,12,40],"second-level economy/time/capacity")
	var counts := {}
	var ids := {}
	for index in range(level.arrivals.size()):
		var arrival: Dictionary = level.arrivals[index]
		check(arrival.tick==200+index*120 and not ids.has(arrival.id),"stable unique arrival %d" % index)
		counts[arrival.disease_id]=counts.get(arrival.disease_id,0)+1
		ids[arrival.id]=true
	check(counts=={"echo":10,"motion":10,"sensory":10,"rhythm_hiccup":10,"pillow_dependency":10,"warmwind_sneeze":10},"ten patients per original disease")
	check(level.arrivals[-1].tick==7280,"last arrival time")
	for level_id in ["level_01","clinical_02"]:
		var state := ClinicState.create(level_id,c)
		check(SnapshotValidator.validate(state.data,c)=="","fresh state validates "+level_id)
		var sim := Simulation.new(c,state)
		var limit: int = c.levels[level_id].max_staff
		for i in range(limit):
			check(sim.submit({"id":"hire_%d" % i,"type":"hire_staff","payload":{"role":"receptionist"}}).ok,"hire within per-level staff limit")
		var before := sim.snapshot()
		check(sim.submit({"id":"overflow","type":"hire_staff","payload":{"role":"receptionist"}}).code=="staff_limit","per-level limit enforced")
		check(sim.snapshot()==before,"staff-limit rejection atomic")
		check(SnapshotValidator.validate(sim.snapshot(),c)=="","full staff-limit snapshot validates")
	_test_invalid_content()
	_test_outcome(c)
	print("CLINICAL CONTENT RESULT: failed=%d passed=%d" % [failed,passed])
	quit(1 if failed>0 else 0)

func _test_invalid_content() -> void:
	var folder := "user://clinical-content-invalid-"+str(Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(folder)
	for mutation in ["unknown_step","wrong_order","fractional_cost","wrong_role","wrong_capacity","bad_goal","bad_level_id"]:
		for name in ["rooms","diseases","staff","level_01","clinical_02"]:
			var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/"+name+".json"))
			if name=="diseases":
				for disease in doc.items:
					if disease.id!="warmwind_sneeze": continue
					if mutation=="unknown_step": disease.care_steps=["mystery"]
					if mutation=="wrong_order": disease.care_steps=["ward","pharmacy","general_exam"]
			if name=="rooms":
				for room in doc.items:
					if room.id!="ward": continue
					if mutation=="fractional_cost": room.consumable_cost=30.5
					if mutation=="wrong_role": room.staff_role="doctor"
					if mutation=="wrong_capacity": room.capacity=1
			if name=="clinical_02":
				if mutation=="bad_goal": doc.goal.completed_min=61
				if mutation=="bad_level_id": doc.id="level_01"
			var file := FileAccess.open(folder.path_join(name+".json"),FileAccess.WRITE)
			file.store_string(JSON.stringify(doc))
			file.close()
		check(not ContentCatalog.load_checked(folder).ok,"reject altered content "+mutation)
	check(ContentCatalog.load_checked("res://content").ok,"original content remains valid")

func _test_outcome(c: ContentCatalog) -> void:
	# Outcome predicate fixtures deliberately isolate challenge rules; real-money
	# conservation and all 60 real exits are covered by the clinical autoplay.
	for row in [[48,0,true,"won"],[47,100,true,"lost"],[48,-1,true,"lost"],[48,100,false,"lost"]]:
		var state := ClinicState.create("clinical_02",c)
		state.data.tick=12000
		state.data.last_payroll_tick=12000
		state.data.metrics.completed=row[0]
		state.data.cash=row[1]
		state.data.arrival_cursor=60
		if not row[2]: state.data.patients={"fixture":{"phase":"ward_service"}}
		Challenge.after_tick(state,c)
		check(state.data.challenge.status==row[3],"clinical goal enforces cures, cash and all actual departures")
