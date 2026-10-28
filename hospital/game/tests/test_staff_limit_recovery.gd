extends SceneTree

# Public commands only. A restart is explicitly not an in-session recovery.
var output := ""
var passed := 0
var failed := 0
var checks: Array=[]
var commands: Array=[]
var evidence: Dictionary={"restart_used":false,"snapshot_mutated":false}
var session: GameSession

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size()):
		var arg: String=args[i]
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=")
		elif arg=="--output" and i+1<args.size(): output=args[i+1]
		elif arg.begins_with("output="): output=arg.trim_prefix("output=")
	output=output.replace("\\","/")
	_run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks.append({"ok":ok,"check":label})
	if ok: passed+=1
	else: failed+=1
	print(("STAFF RECOVERY PASS: " if ok else "STAFF RECOVERY FAIL: ")+label)

func issue(kind: String,payload: Dictionary) -> Dictionary:
	var before: Dictionary=session.sim.snapshot()
	var result: Dictionary=session.issue(kind,payload)
	commands.append({"tick":before.tick,"kind":kind,"payload":payload.duplicate(true),"result":result.duplicate(true),"unchanged_if_rejected":session.sim.snapshot()==before if not result.get("ok",false) else null})
	return result

func _exercise(root: String) -> void:
	var loaded: Dictionary=ContentCatalog.load_checked("res://content")
	check(bool(loaded.get("ok",false)),"real catalog loads")
	if not loaded.get("ok",false): return
	var catalog: ContentCatalog=loaded.catalog
	session=GameSession.new(catalog,root)
	check(session.sim.snapshot().cash==8000 and session.sim.snapshot().staff.is_empty(),"genuine empty 8000-budget new game")
	var techs: Array=[]
	for i in range(8):
		var hired: Dictionary=issue("hire_staff",{"role":"technician"})
		check(bool(hired.get("ok",false)),"public technician hire "+str(i+1))
		if not hired.get("ok",false): return
		techs.append(str(hired.data.staff_id))
	var full: Dictionary=session.sim.snapshot()
	check(full.cash==6400 and full.staff.size()==8,"eight actual hires leave 6400 cash but fill all staff slots")
	for role: String in ["receptionist","doctor"]:
		var before: Dictionary=session.sim.snapshot()
		var rejected: Dictionary=issue("hire_staff",{"role":role})
		check(not rejected.get("ok",false) and rejected.get("code","")=="staff_limit" and session.sim.snapshot()==before,"missing essential "+role+" is blocked by actual limit, atomically")
	evidence.before_recovery=full
	check(SnapshotValidator.validate(full,catalog)=="","actual mis-hire snapshot is legal and recoverable as saved data")
	var saved: Dictionary=session.save_now()
	check(bool(saved.get("ok",false)),"actual mis-hire state saves")
	var restored: Dictionary=SaveStore.load(root,catalog)
	var roundtrip: bool=false
	if restored.get("ok",false): roundtrip=restored.state.to_data()==full
	check(roundtrip,"actual mis-hire state loads without bypass")
	# Required new public recovery contract. These workers have never been
	# assigned, moved, served, held a reservation, or occupied a clinical device.
	for id: String in [str(techs[7]),str(techs[6])]:
		var dismissed: Dictionary=issue("dismiss_staff",{"staff_id":id})
		check(bool(dismissed.get("ok",false)),"unassigned idle worker can be dismissed to recover within this game")
		if not dismissed.get("ok",false):
			evidence.recovery_failure=dismissed
			evidence.recovered_in_same_session=false
			return
	check(session.sim.snapshot().staff.size()==6,"dismissal actually frees two staff slots")
	var reception: Dictionary=issue("hire_staff",{"role":"receptionist"})
	var doctor: Dictionary=issue("hire_staff",{"role":"doctor"})
	check(bool(reception.get("ok",false)) and bool(doctor.get("ok",false)),"same session can now hire both essential roles without restart")
	check(SnapshotValidator.validate(session.sim.snapshot(),catalog)=="","recovered session retains valid staff IDs, ledger and receipts")
	evidence.recovered_in_same_session=bool(reception.get("ok",false)) and bool(doctor.get("ok",false))
	evidence.after_recovery=session.sim.snapshot()
	_extended_recovery(catalog,techs)
	_safety_cases(catalog,root+"-safety")


func _reject(kind: String,payload: Dictionary,code: String,label: String) -> void:
	var before: Dictionary=session.sim.snapshot()
	var result: Dictionary=issue(kind,payload)
	check(not result.get("ok",false) and result.get("code","")==code and session.sim.snapshot()==before,label+" refuses atomically")

func _panel_probe(catalog: ContentCatalog,id: String,enabled: bool) -> void:
	var panel := SelectionPanel.new()
	get_root().add_child(panel)
	panel.select(id,"staff")
	panel.present(session.sim.snapshot(),catalog)
	var button: Button=panel.controls.get("dismiss")
	check(button!=null and button.disabled==(not enabled),"real staff detail dismissal availability matches safe state")
	if button!=null:
		check(button.custom_minimum_size.y>=48.0,"real dismissal control keeps at least 48px touch height")
		if enabled:
			var emitted: Array=[]
			panel.command_requested.connect(func(kind: String,payload: Dictionary) -> void: emitted.append({"kind":kind,"payload":payload}))
			button.pressed.emit()
			check(emitted==[{"kind":"dismiss_staff","payload":{"staff_id":id}}],"real detail button requests the selected worker through the public command signal")
	panel.queue_free()

func _extended_recovery(catalog: ContentCatalog,techs: Array) -> void:
	var good: Dictionary=session.sim.snapshot()
	check(good.cash==6000,"dismissal never refunds sunk recruitment cost")
	check(good.staff.has("staff_009") and good.staff.has("staff_010") and good.next_ids.staff==11,"new hires keep monotonic IDs instead of recycling dismissed identities")
	var first: Dictionary={}
	for row: Dictionary in commands:
		if row.kind=="dismiss_staff" and row.result.get("ok",false):
			first=row.result
			break
	var repeated: Dictionary=session.submit(first.data.command)
	check(repeated==first and session.sim.snapshot()==good,"repeated dismissal command ID returns the same receipt without another mutation")
	_panel_probe(catalog,str(techs[0]),true)
	_reject("dismiss_staff",{},"invalid_payload","missing worker ID")
	_reject("dismiss_staff",{"staff_id":"staff_999"},"unknown_staff","unknown worker")
	_reject("dismiss_staff",{"staff_id":first.data.staff_id},"unknown_staff","new command cannot dismiss the same worker twice")
	for mutation: String in ["returned_id","returned_role","target_id"]:
		# Deliberately corrupted in-memory SAVE-validation negative fixtures only;
		# never installed into the running session or presented as normal play.
		var bad: Dictionary=good.duplicate(true)
		var receipt: Dictionary=bad.command_receipts[first.data.command.id]
		if mutation=="returned_id": receipt.data.staff_id="staff_001"
		elif mutation=="returned_role": receipt.data.role="doctor"
		else: receipt.data.command.payload.staff_id="staff_999"
		check(SnapshotValidator.validate(bad,catalog)!="","corrupted dismissal receipt rejects "+mutation)
	var hired_again: Dictionary=issue("dismiss_staff",{"staff_id":str(techs[5])})
	check(bool(hired_again.get("ok",false)),"one more safely idle worker can leave before payroll")
	var before_pay: Dictionary=session.sim.snapshot()
	var expected_wages := 0
	for employee: Dictionary in before_pay.staff.values(): expected_wages+=int(catalog.staff[employee.role].daily_wage)
	check(expected_wages==220 and before_pay.staff.size()==7,"payroll uses the seven actual remaining roles")
	check(bool(issue("set_paused",{"paused":false}).get("ok",false)),"public clinic starts for actual payroll boundary")
	for _i in range(1200): session.advance_wall_time(GameSession.STEP_USEC)
	var paid: Dictionary=session.sim.snapshot()
	check(paid.tick==1200 and paid.metrics.wages==expected_wages and paid.metrics.fixed_cost==80 and paid.cash==before_pay.cash-expected_wages-80,"actual payroll excludes all dismissed workers without refunding prior capital")
	check(SnapshotValidator.validate(paid,catalog)=="","post-dismissal payroll full snapshot validates")
	check(bool(session.save_now().get("ok",false)),"post-dismissal and payroll state actually saves")
	var loaded: Dictionary=SaveStore.load(session.save_root,catalog)
	check(bool(loaded.get("ok",false)),"post-dismissal and payroll state actually loads")
	if loaded.get("ok",false):
		var sim := Simulation.new(catalog,loaded.state)
		var initial: Dictionary=sim.snapshot()
		check(sim.submit(first.data.command)==first and sim.snapshot()==initial,"loaded old dismissal receipt remains idempotent")
	evidence.payroll_snapshot=paid

func _safety_cases(catalog: ContentCatalog,root: String) -> void:
	session=GameSession.new(catalog,root)
	var rooms: Dictionary={}
	var employees: Dictionary={}
	for row: Array in [["reception",121],["diagnosis",100],["echo",104],["recovery",140]]:
		var built: Dictionary=issue("build_room",{"kind":row[0],"origin_cell":row[1],"rotation":0})
		check(bool(built.get("ok",false)),"safety case builds real "+str(row[0]))
		if not built.get("ok",false): return
		rooms[row[0]]=str(built.data.room_id)
		if row[0]=="recovery": continue
		var hired: Dictionary=issue("hire_staff",{"role":catalog.rooms[row[0]].staff_role})
		check(bool(hired.get("ok",false)),"safety case recruits real "+str(row[0]))
		if not hired.get("ok",false): return
		employees[row[0]]=str(hired.data.staff_id)
		check(bool(issue("assign_staff",{"staff_id":hired.data.staff_id,"room_id":built.data.room_id}).get("ok",false)),"safety case publicly assigns "+str(row[0]))
	_reject("dismiss_staff",{"staff_id":employees.diagnosis},"staff_assigned","assigned but unstarted doctor")
	_panel_probe(catalog,employees.diagnosis,false)
	check(bool(issue("close_room",{"room_id":rooms.recovery}).get("ok",false)),"ordinary close withholds recovery for actual blocked-device case")
	issue("set_paused",{"paused":false})
	session.advance_wall_time(GameSession.STEP_USEC)
	var moving: Dictionary=session.sim.snapshot().staff[employees.diagnosis]
	check(moving.phase=="moving" and moving.move_progress>0,"normal doctor really starts a path before withdrawal")
	check(bool(issue("assign_staff",{"staff_id":employees.diagnosis,"room_id":""}).get("ok",false)),"unstarted moving doctor can be publicly withdrawn")
	_reject("dismiss_staff",{"staff_id":employees.diagnosis},"staff_moving","withdrawn doctor still on an actual edge")
	_panel_probe(catalog,employees.diagnosis,false)
	var stopped := false
	for _i in range(80):
		session.advance_wall_time(GameSession.STEP_USEC)
		var employee: Dictionary=session.sim.snapshot().staff[employees.diagnosis]
		if employee.phase=="idle" and employee.move_progress==0:
			stopped=true
			break
	check(stopped,"withdrawn doctor actually finishes the safe return walk")
	if not stopped: return
	check(bool(issue("dismiss_staff",{"staff_id":employees.diagnosis}).get("ok",false)),"withdrawn and stopped doctor can now be dismissed")
	var replacement: Dictionary=issue("hire_staff",{"role":"doctor"})
	check(bool(replacement.get("ok",false)),"same safety game hires a fresh doctor")
	if not replacement.get("ok",false): return
	issue("assign_staff",{"staff_id":replacement.data.staff_id,"room_id":rooms.diagnosis})
	var service := false
	for _i in range(600):
		session.advance_wall_time(GameSession.STEP_USEC)
		var patient: Dictionary=session.sim.snapshot().patients.get("patient_001",{})
		if patient.get("phase","")=="reception_service":
			service=true
			break
	check(service,"real first patient is actually served")
	if not service: return
	_reject("dismiss_staff",{"staff_id":employees.reception},"staff_assigned","employee actually serving a patient")
	var blocked := false
	for _i in range(1000):
		session.advance_wall_time(GameSession.STEP_USEC)
		var snap: Dictionary=session.sim.snapshot()
		if snap.staff[employees.echo].phase=="blocked" and snap.patients.get("patient_001",{}).get("phase","")=="waiting_recovery":
			blocked=true
			break
	check(blocked,"actual treatment completion holds the device while recovery is closed")
	if blocked:
		_reject("dismiss_staff",{"staff_id":employees.echo},"staff_assigned","employee in actual blocked clinical handoff")
		_reject("assign_staff",{"staff_id":employees.echo,"room_id":""},"staff_busy","blocked employee cannot bypass dismissal by unsafe withdrawal")
	check(SnapshotValidator.validate(session.sim.snapshot(),catalog)=="","actual safety flow and held clinical ownership validate")
	evidence.safety_snapshot=session.sim.snapshot()

func _run() -> void:
	if output=="" or not output.to_lower().begins_with("e:/codex/") or output.simplify_path()!=output or FileAccess.file_exists(output):
		push_error("Pass fresh --output JSON below E:/CODEX")
		quit(2)
		return
	var root: String=output.get_base_dir().path_join(output.get_file().get_basename()+"-saves")
	if DirAccess.dir_exists_absolute(root) or DirAccess.make_dir_recursive_absolute(root)!=OK:
		push_error("Require a fresh isolated save directory")
		quit(2)
		return
	_exercise(root)
	var f: FileAccess=FileAccess.open(output,FileAccess.WRITE)
	if f==null:
		push_error("Could not write public staff-recovery evidence")
		quit(2)
		return
	f.store_string(JSON.stringify({"passed":passed,"failed":failed,"checks":checks,"command_trace":commands,"evidence":evidence,"scope":"Genuine new GameSession and actual public commands/SaveStore; no cash, phase, state, RNG or source mutations. Restart explicitly does not count as in-session correction. Dismissal is a required new recovery interface, not a fabricated existing feature."},"  "))
	print("STAFF RECOVERY RESULT: passed=%d failed=%d"%[passed,failed])
	quit(1 if failed>0 else 0)
