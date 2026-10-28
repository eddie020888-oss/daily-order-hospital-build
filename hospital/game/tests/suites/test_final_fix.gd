extends RefCounted

class FailedPreservation extends SaveFileIO:
	func rename(_from: String, _to: String) -> Error:
		return ERR_CANT_CREATE

class FailedNewSave extends SaveFileIO:
	func write(path: String, value: String) -> Error:
		if path.ends_with("candidate.json"): return ERR_CANT_CREATE
		return super.write(path,value)

var catalog: ContentCatalog

func run(t: TestContext) -> void:
	catalog=ContentCatalog.load_checked("res://content").catalog
	_recovery(t)
	_settlement(t)
	_capacity(t)
	_fifo_and_reservations(t)
	_staff_feedback(t)
	_density(t)

func _session() -> GameSession:
	var session:GameSession=GameSession.new(catalog,ProjectSettings.globalize_path("res://../temp/tests/final-%d-%d" % [Time.get_ticks_usec(),randi()]))
	var legacy_start:Dictionary=session.start_level("level_01")
	assert(legacy_start.get("ok",false),"isolated legacy teaching fixture must initialize")
	return session

func _hud(s: GameSession) -> HospitalHud:
	var h:=HospitalHud.new()
	Engine.get_main_loop().root.add_child(h)
	h.initialize(s,TouchController.new(null,Callable(),s.reserve_command_id),null)
	s.changed.connect(h.present)
	return h

func _corrupt(s: GameSession) -> void:
	var io:=SaveFileIO.new()
	io.mkdir(s.save_root)
	for name in ["main.json","previous.json"]: io.write(s.save_root.path_join(name),"original invalid "+name)
	s.open_saved()

func _recovery(t: TestContext) -> void:
	var s:=_session()
	_corrupt(s)
	var h:=_hud(s)
	t.expect_true(h.controls.has("recover"),"I1 explicit preserved-file recovery HUD action")
	if not h.controls.has("recover"):
		h.free()
		return
	t.expect_true(h.controls.recover.is_visible_in_tree(),"I1 blocked new-game action visible")
	t.expect_true(s.storage_blocked,"I1 no automatic fresh game")
	h.controls.recover.pressed.emit()
	t.expect_false(s.storage_blocked,"I1 explicit HUD recovery unblocks")
	for name in ["main.json","previous.json"]:
		var found:=false
		for file in DirAccess.get_files_at(s.save_root):
			if file.begins_with(name+".retained-") and FileAccess.get_file_as_string(s.save_root.path_join(file))=="original invalid "+name: found=true
		t.expect_true(found,"I1 exact invalid original retained "+name)
	t.expect_true(s.issue("build_room",{"kind":"reception","origin_cell":121,"rotation":0}).ok,"I1 recovered game usable")
	t.expect_true(s.save_now().ok,"I1 recovered state saves")
	var reloaded:=GameSession.new(catalog,s.save_root)
	reloaded.open_saved()
	t.expect_false(reloaded.storage_blocked,"I1 relaunch loads active save")
	t.expect_equal(reloaded.sim.snapshot().rooms.size(),1,"I1 relaunch preserves new play")
	h.free()
	var failed:=_session()
	_corrupt(failed)
	var before:=failed.sim.snapshot()
	failed.call("recover_new_game",FailedPreservation.new())
	t.expect_true(failed.storage_blocked,"I1 preservation failure keeps block")
	t.expect_equal(failed.sim.snapshot(),before,"I1 preservation failure cannot replace model")
	t.expect_equal(FileAccess.get_file_as_string(failed.save_root.path_join("main.json")),"original invalid main.json","I1 failure keeps original bytes")
	var retry:=GameSession.new(catalog,failed.save_root)
	retry.open_saved()
	t.expect_true(retry.storage_blocked,"I1 unfinished recovery stays blocked across relaunch")
	t.expect_contains(failed.notice,"失败","I1 actionable failure explained")
	var no_save:=_session()
	_corrupt(no_save)
	no_save.call("recover_new_game",FailedNewSave.new())
	t.expect_true(no_save.storage_blocked,"I1 new-save failure after archiving stays blocked")
	var interrupted:=GameSession.new(catalog,no_save.save_root)
	interrupted.open_saved()
	t.expect_true(interrupted.storage_blocked,"I1 absent active files plus marker never auto-start")
	t.expect_true(interrupted.call("recover_new_game").ok,"I1 player can retry interrupted recovery")
	for name in ["main.json","previous.json"]:
		var found:=false
		for file in DirAccess.get_files_at(no_save.save_root):
			if file.begins_with(name+".retained-") and FileAccess.get_file_as_string(no_save.save_root.path_join(file))=="original invalid "+name: found=true
		t.expect_true(found,"I1 interrupted recovery exact bytes remain "+name)


func _settlement(t: TestContext) -> void:
	var s:=_session()
	var h:=_hud(s)
	t.expect_true(h.has_method("settlement_text"),"I2 readable frozen settlement projection exists")
	if not h.has_method("settlement_text"):
		h.free()
		return
	# Real challenge command replay, then actual early terminal win.
	var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/replay_commands.json"))
	var commands: Array=SaveStore._integers(fixture.commands).value
	for tick in range(9001):
		for row in commands:
			if row.tick==tick:
				var c: Dictionary=row.duplicate(true)
				c.erase("tick")
				s.submit(c)
		if s.sim.snapshot().challenge.status!="running": break
		s.sim.advance_ticks(1)
	t.expect_equal(s.sim.snapshot().challenge.status,"won","I2 settlement real win fixture")
	for snapshot in [s.sim.snapshot(),_failure_snapshot()]:
		s.sim._state.data=snapshot.duplicate(true)
		var before:=s.sim.snapshot()
		h.present()
		h.controls.settlement.pressed.emit()
		var copy: String=h.call("settlement_text",before)
		for text in ["未到院","院外等候","在院未完成","已完成离院","已弃诊离院","弃诊离院中","合计 36","治疗耗材","恢复耗材","工资","固定支出","资本","接待","诊断","治疗","恢复","离院"]:
			t.expect_contains(copy,text,"I2 report contains "+text)
		t.expect_equal(s.sim.snapshot(),before,"I2 opening report never mutates frozen model")
		if before.challenge.status=="lost":
			var st:=ClinicState.new()
			st.data=before
			var summary:=Metrics.summary(st)
			t.expect_equal(before.challenge.reason,"bankruptcy","I2 failure is actual economic outcome")
			t.expect_true(summary.dispositions.not_arrived>0,"I2 bankruptcy retains unarrived patients")
			t.expect_true(summary.dispositions.in_hospital>0,"I2 unfinished patient not fabricated terminal")
			t.expect_true(ClinicState.from_data(before,catalog).ok,"I2 real frozen failure snapshot validates")
	h.free()

func _failure_snapshot() -> Dictionary:
	# Explicit unlocked unit fixture; original 36 arrivals and every price/wage unchanged.
	var state:=ClinicState.create("level_01",catalog)
	state.data.unlocked_room_kinds=Scenarios.ROOM_KINDS.duplicate()
	var sim:=Simulation.new(catalog,state)
	for row in Scenarios.STANDARD:
		sim.submit({"id":"build_"+row[0],"type":"build_room","payload":{"kind":row[0],"origin_cell":row[1],"rotation":row[2]}})
	for i in range(8): sim.submit({"id":"hire_%d" % i,"type":"hire_staff","payload":{"role":"doctor"}})
	sim.submit({"id":"start","type":"set_paused","payload":{"paused":false}})
	sim.advance_ticks(2400)
	return sim.snapshot()

func _capacity(t: TestContext) -> void:
	for add_when_blocked in [false,true]:
		var sim:=Scenarios.create_sim(catalog,"benchmark_18","fast","standard")
		if not add_when_blocked: t.expect_true(sim.submit({"id":"second","type":"build_room","payload":{"kind":"recovery","origin_cell":308,"rotation":2}}).ok,"I3 purchase second recovery")
		var observed:=false
		for tick in range(2000):
			sim.advance_ticks(1)
			var d:=sim.snapshot()
			if add_when_blocked and not d.rooms.has("room_007"):
				for p in d.patients.values():
					if p.phase=="waiting_recovery" and p.wait_reason=="recovery_full":
						t.expect_true(sim.submit({"id":"second","type":"build_room","payload":{"kind":"recovery","origin_cell":308,"rotation":2}}).ok,"I3 add capacity during actual block")
						break
			if not d.rooms.has("room_007"): continue
			for p in d.patients.values():
				if p.phase=="waiting_recovery" and d.slots["room_007:0"].phase=="free" and not GridService.path(sim._state,p.cell,d.slots["room_007:0"].cell).is_empty():
					t.expect_true(false,"I3 eligible spare recovery seat must serve blocked waiter")
					observed=true
					break
				if p.get("slot_id","")=="room_007:0":
					observed=true
					if p.phase=="moving_recovery":
						var held:=""
						for sid in d.slots:
							if d.slots[sid].phase=="blocked" and d.slots[sid].patient_id==p.id: held=sid
						if held!="":
							t.expect_equal(d.slots[held].cell,p.cell,"I3 device retained at reservation")
							t.expect_equal(d.staff[d.rooms[d.slots[held].room_id].staff_id].phase,"blocked","I3 technician remains held")
							while sim._state.data.patients[p.id].cell==d.slots[held].cell: sim.advance_ticks(1)
							t.expect_equal(sim.snapshot().slots[held].phase,"free","I3 actual departure releases device")
					break
			if observed: break
		t.expect_true(observed,"I3 new/second recovery room used")

func _density(t: TestContext) -> void:
	var h:=_hud(_session())
	for output in [Vector2(2400,1350),Vector2(2640,1080)]:
		for factor in [1.0,0.5]:
			h.configure_display(output,output*factor,480,Rect2(Vector2(72,0),output-Vector2(144,0)))
			var b:Button=h.controls.staff
			var chinese:Label=h._nav_labels.staff
			t.expect_true(b.is_visible_in_tree() and chinese.is_visible_in_tree() and chinese.text=="员工","I4 samples an actual visible Chinese navigation label")
			var physical_font:float=chinese.get_theme_font_size("font_size")*chinese.get_global_transform().get_scale().x/factor/3.0
			t.expect_true(physical_font>=17,"I4 effective Chinese button font at least17dp native/scaled")
			t.expect_true(b.custom_minimum_size.y*b.get_global_transform().get_scale().y/factor>=144,"I4 48dp touch height native/scaled")
	h.free()

func _fifo_and_reservations(t: TestContext) -> void:
	var sim:=Scenarios.create_sim(catalog,"benchmark_18","fast","standard")
	sim.submit({"id":"close","type":"close_room","payload":{"room_id":"room_006"}})
	var waiters: Array=[]
	for tick in range(2000):
		sim.advance_ticks(1)
		waiters=sim._state.data.patients.values().filter(func(p): return p.phase=="waiting_recovery")
		if waiters.size()>=2: break
	t.expect_true(waiters.size()>=2,"I3 two genuine treatment-blocked FIFO waiters")
	if waiters.size()<2: return
	# A tie fixture makes dictionary insertion order deliberately disagree with ID order.
	waiters.sort_custom(func(a,b): return a.id>b.id)
	var tied_tick: int=mini(waiters[0].queue_enter_tick,waiters[1].queue_enter_tick)
	for p in waiters: p.queue_enter_tick=tied_tick
	var ids: Array=waiters.map(func(p): return p.id)
	ids.sort()
	t.expect_true(sim.submit({"id":"open","type":"reopen_room","payload":{"room_id":"room_006"}}).ok,"I3 reopen original capacity")
	t.expect_true(sim.submit({"id":"new","type":"build_room","payload":{"kind":"recovery","origin_cell":308,"rotation":2}}).ok,"I3 add second capacity for FIFO tie")
	sim.advance_ticks(1)
	t.expect_equal(sim.snapshot().slots["room_006:0"].patient_id,ids[0],"I3 stable ID FIFO tie takes first available room")
	t.expect_equal(sim.snapshot().slots["room_007:0"].patient_id,ids[1],"I3 next FIFO patient takes second room")
	var reserved: String=sim.snapshot().slots["room_006:0"].patient_id
	t.expect_true(sim.submit({"id":"drain","type":"close_room","payload":{"room_id":"room_006"}}).ok,"I3 close reserved recovery room drains")
	sim.advance_ticks(1)
	t.expect_equal(sim.snapshot().slots["room_006:0"].patient_id,reserved,"I3 active reservation remains owned while draining")
	t.expect_equal(sim.snapshot().patients[reserved].slot_id,"room_006:0","I3 no detaching active reservation")

func _staff_feedback(t: TestContext) -> void:
	var s:=_session()
	s.sim=Scenarios.create_sim(catalog,"benchmark_18","fast","standard")
	var h:=_hud(s)
	var serving:=""
	for tick in range(500):
		s.sim.advance_ticks(1)
		for id in s.sim.snapshot().staff:
			if s.sim.snapshot().staff[id].phase=="serving": serving=id; break
		if serving!="": break
	var result:=s.issue("assign_staff",{"staff_id":serving,"room_id":""})
	t.expect_equal(result.code,"staff_busy","M5 actual busy command rejected")
	t.expect_true(result.data.remaining_ticks>0,"M5 actual service supplies remaining ticks")
	t.expect_contains(s.notice,"还需","M5 HUD supplies remaining duration")
	for tick in range(1500):
		s.sim.advance_ticks(1)
		var blocked:=""
		for p in s.sim.snapshot().patients.values():
			if p.phase=="waiting_recovery":
				for slot in s.sim.snapshot().slots.values():
					if slot.phase=="blocked" and slot.patient_id==p.id: blocked=s.sim.snapshot().rooms[slot.room_id].staff_id
		if blocked!="":
			s.issue("assign_staff",{"staff_id":blocked,"room_id":""})
			t.expect_contains(s.notice,"移交","M5 blocked handoff explained")
			t.expect_false(s.notice.contains("0秒"),"M5 blocked zero never promises availability")
			break
	h.free()
