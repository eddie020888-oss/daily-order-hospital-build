extends SceneTree

# Real public long_01 construction, production, personal requests and payroll.
# Only malformed detached copies are fixtures; no normal-play field injection.
var output:String=""
var legacy_save:String=""
var passed:int=0
var failed:int=0
var checks:Array=[]
var sequence:int=0
var catalog:ContentCatalog
var people:Script
var people_validator:Script

func _initialize()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=").replace("\\","/")
		elif arg.begins_with("--legacy-save="):legacy_save=arg.trim_prefix("--legacy-save=").replace("\\","/")
	_run.call_deferred()

func check(ok:bool,label:String,detail:Variant=null)->void:
	checks.append({"ok":ok,"check":label,"detail":detail})
	if ok:passed+=1
	else:failed+=1
	print(("PEOPLE PASS: " if ok else "PEOPLE FAIL: ")+label+(" "+str(detail) if detail!=null else ""))

func issue(sim:Simulation,type:String,payload:Dictionary)->Dictionary:
	sequence+=1
	var command:Dictionary={"id":"people_public_%05d"%sequence,"type":type,"payload":payload}
	var result:Dictionary=sim.submit(command)
	check(bool(result.get("ok",false)),"public "+type,result.get("code",""))
	return result

func build(sim:Simulation,kind:String,origin:int=-1,staffed:bool=false)->String:
	var definition:Dictionary=catalog.campaign.facilities[kind]
	var layout:Dictionary=FacilityLayout.default_layout(definition.unit_id,kind,0)
	var chosen:int=origin
	if chosen<0:
		for cell:int in range(GridService.WIDTH*GridService.HEIGHT):
			var proposal:Dictionary={"id":"people_preview","kind":"campaign_department","ruleset":CampaignContent.RULESET,"unit_id":definition.unit_id,"origin_cell":cell,"rotation":0,"layout":layout,"width":layout.width,"height":layout.height,"status":"open"}
			var preview:Dictionary=FacilityLayout.preview(sim._state,proposal)
			if preview.get("ok",false):chosen=cell;break
	if chosen<0:check(false,"real geometry can place "+kind);return ""
	var result:Dictionary=issue(sim,"build_department",{"unit_id":definition.unit_id,"origin_cell":chosen,"layout":layout})
	if not result.get("ok",false):return ""
	var fid:String=str(result.data.facility_ids[0])
	if staffed:
		for role:String in definition.roles:
			var hired:Dictionary=issue(sim,"hire",{"role":role})
			if not hired.get("ok",false):return ""
			if not issue(sim,"assign",{"staff_id":hired.data.staff_id,"facility_id":fid}).get("ok",false):return ""
	return fid

func prepare()->Dictionary:
	var state:ClinicState=ClinicState.create("long_01",catalog)
	check(state!=null,"real long_01 factory")
	if state==null:return {}
	var sim:Simulation=Simulation.new(catalog,state)
	var clinic:String=build(sim,"U01-E1",25,true)
	if clinic=="" or build(sim,"O01",33,true)=="" or build(sim,"O15",40,true)=="":return {}
	var water1:String=build(sim,"O25")
	var water2:String=build(sim,"O25")
	if water1=="" or water2=="" or build(sim,"O26")=="" or build(sim,"O27")=="":return {}
	var delivery:Dictionary=issue(sim,"run_operation",{"facility_kind":"O15"})
	if not delivery.get("ok",false):return {}
	if not issue(sim,"set_paused",{"paused":false}).get("ok",false):return {}
	for _n:int in range(1500):
		if state.data.work_orders[delivery.data.work_order_id].status=="done":break
		sim.advance_ticks(1)
	check(state.data.work_orders[delivery.data.work_order_id].status=="done","real logistics delivery completes before admission")
	check(int(state.data.campaign.get("people_version",0))==1,"new hospital explicitly enables people_version1")
	return {"state":state,"sim":sim,"clinic":clinic,"water_ids":[water1,water2]}

func reject_copy(snapshot:Dictionary,label:String)->void:
	var before:Dictionary=snapshot.duplicate(true)
	var error:String=SnapshotValidator.validate(snapshot,catalog)
	check(error!="" and snapshot==before,label,error)

func legacy_compatibility()->void:
	if legacy_save=="":return
	check(legacy_save.begins_with("E:/CODEX/") and legacy_save.get_file()=="main.json" and FileAccess.file_exists(legacy_save),"legacy source is a real E main.json")
	if not FileAccess.file_exists(legacy_save):return
	var original_hash:String=FileAccess.get_sha256(legacy_save)
	var loaded:Dictionary=SaveStore.load(legacy_save.get_base_dir(),catalog)
	check(loaded.get("ok",false) and not loaded.get("used_backup",true),"real pre-people schema3 source loads exactly",loaded.get("error",""))
	if loaded.get("ok",false):
		var original:Dictionary=loaded.state.to_data()
		check(not original.campaign.has("people_version"),"retained legacy hospital does not acquire people_version")
		var checked:Dictionary=ClinicState.from_data(original,catalog)
		check(checked.get("ok",false) and checked.state.to_data()==original,"old schema3 whole dictionary is preserved without injected fields")
		if people!=null:check(not people.call("enabled",original),"people feature is strictly disabled for legacy source")
	check(FileAccess.get_sha256(legacy_save)==original_hash,"legacy source bytes are unchanged")

func patient_need(setup:Dictionary)->void:
	var sim:Simulation=setup.sim
	var accepted:Dictionary=issue(sim,"accept_case",{"case_id":"U01-C1"})
	if not accepted.get("ok",false):return
	var pid:String=str(accepted.data.patient_ids[0])
	var before:Dictionary=sim.snapshot()
	var request:Dictionary=issue(sim,"request_patient_need",{"patient_id":pid,"need":"water"})
	if not request.get("ok",false):return
	var initial:Dictionary=before.patients[pid]
	var requested:Dictionary=sim._state.data.patients[pid]
	check(requested.phase=="care_queue" and requested.step_index==initial.step_index,"personal water request preserves clinical phase and cursor")
	check(sim._state.data.cash==before.cash and sim._state.data.resources.water==before.resources.water,"request and reservation cannot charge before arrival")
	var target_fid:String=str(request.get("data",{}).get("facility_id",""))
	check(target_fid in setup.water_ids,"request selects a real water facility")
	var lengths:Dictionary={}
	for fid:String in setup.water_ids:
		var goal:int=int(sim._state.data.facilities[fid].service_cells[0])
		var blockers:Dictionary=CampaignClinicalFlow._work_positions(before,initial,goal)
		var path:Array=GridService.path_avoiding(sim._state,int(initial.cell),goal,blockers)
		if not path.is_empty():lengths[fid]=path.size()
	if lengths.has(target_fid):
		for fid:String in lengths:check(int(lengths[target_fid])<=int(lengths[fid]),"selected water station has shortest actual reachable route",lengths)
	var saw_mid:bool=false
	for _n:int in range(800):
		sim.advance_ticks(1)
		var p:Dictionary=sim._state.data.patients[pid]
		if int(p.move_progress)>0 and int(p.move_progress)<4 and p.get("need_activity",{}).get("state","")=="walking":saw_mid=true;break
	check(saw_mid,"personal trip uses real fractional walking, without teleport")
	if not saw_mid:return
	var middle:Dictionary=sim.snapshot()
	check(middle.cash==before.cash and middle.resources.water==before.resources.water,"mid-edge personal trip has not consumed water or charged money")
	var save_dir:String=output.get_basename()+"-need-mid-save"
	var saved:Dictionary=SaveStore.save(middle,save_dir)
	check(saved.get("ok",false),"actual personal mid-edge atomic save",saved.get("error",""))
	var loaded:Dictionary=SaveStore.load(save_dir,catalog)
	check(loaded.get("ok",false) and not loaded.get("used_backup",true),"personal mid-edge real readback",loaded.get("error",""))
	if not loaded.get("ok",false):return
	check(loaded.state.to_data()==middle,"personal mid-edge full snapshot roundtrips exactly")
	var mirror:Simulation=Simulation.new(catalog,loaded.state)
	var same:bool=true
	for _n:int in range(400):
		sim.advance_ticks(1);mirror.advance_ticks(1)
		if sim.snapshot()!=mirror.snapshot():same=false;break
	check(same,"personal trip and subsequent care replay400ticks exactly")
	var after:Dictionary=sim.snapshot()
	var p:Dictionary=after.patients[pid]
	var visits:Array=p.get("need_history",[])
	check(visits.size()==1 and int(visits[0].get("completed_tick",-1))>=0,"exactly one personal water service truly completes")
	if visits.size()!=1:return
	var h:Dictionary=visits[0]
	check(int(h.completed_tick)-int(h.started_tick)==20,"water service retains twenty actual ticks")
	check(after.resources.water==int(before.resources.water)-1,"one completed personal water visit consumes exactly one real water")
	check(int(h.need_after)==maxi(0,int(h.need_before)-60),"only that actual patient's completed need is restored")
	var charges:int=0
	for entry:Dictionary in after.ledger_entries:
		if str(entry.reference).begins_with("need:"+pid+":"):
			charges+=1;check(entry.category=="operations" and entry.amount==-2 and entry.tick==h.started_tick,"one arrival-anchored water charge matches actual service")
	check(charges==1,"personal visit cannot double charge")
	for _n:int in range(2400):
		if sim._state.data.patients[pid].phase in ["left","abandoned"]:break
		sim.advance_ticks(1)
	check(sim._state.data.patients[pid].phase=="left","same patient resumes full clinical route and physically exits cured")
	check(sim._state.data.campaign.get("people_reservations",{}).is_empty(),"personal target reservation releases after physical departure")
	check(SnapshotValidator.validate(sim.snapshot(),catalog)=="","final people, care, stock and ledger remain strictly valid",SnapshotValidator.validate(sim.snapshot(),catalog))
	var corrupted:Dictionary=middle.duplicate(true)
	corrupted.patients[pid].needs.water+=1
	reject_copy(corrupted,"forged current personal need rejects")
	corrupted=middle.duplicate(true)
	corrupted.patients[pid].need_activity.target_cell+=1
	reject_copy(corrupted,"forged personal target/ownership rejects")
	corrupted=after.duplicate(true);corrupted.resources.water+=1
	reject_copy(corrupted,"personal consumed water cannot be silently restored in a save")

func staff_wage(setup:Dictionary)->void:
	var sim:Simulation=setup.sim
	var sid:String=str(sim._state.data.facilities[setup.clinic].staff_ids[0])
	sequence+=1
	var command:Dictionary={"id":"people_raise_%05d"%sequence,"type":"set_staff_wage","payload":{"staff_id":sid,"percent":110}}
	var first:Dictionary=sim.submit(command)
	check(first.get("ok",false),"public individual raise is supported",first.get("code",""))
	if not first.get("ok",false):return
	check(int(sim._state.data.staff[sid].get("wage_percent",0))==110,"individual wage percent really changes")
	var after:Dictionary=sim.snapshot()
	check(sim.submit(command)==first and sim.snapshot()==after,"duplicate raise command cannot repeat morale reward or change payroll")
	var lower:Dictionary=sim.submit({"id":"people_lower_%05d"%sequence,"type":"set_staff_wage","payload":{"staff_id":sid,"percent":100}})
	check(not lower.get("ok",true) and sim.snapshot()==after,"unsafe wage reduction is rejected without state change")
	var needed:int=0
	for s:Dictionary in sim._state.data.staff.values():needed+=ceili(float(int(catalog.campaign.roles[s.role].daily_wage)*int(s.get("wage_percent",100)))/100.0)
	issue(sim,"set_paused",{"paused":false})
	var day:int=int(catalog.levels.long_01.day_ticks)
	var next_pay:int=(int(int(sim._state.data.tick)/day)+1)*day
	sim.advance_ticks(next_pay-int(sim._state.data.tick))
	var amount:int=0
	for entry:Dictionary in sim._state.data.ledger_entries:
		if entry.reference=="payroll:"+str(next_pay):amount=int(entry.amount)
	check(amount==-needed,"next real payroll pays actual raised per-employee wage once",{"actual":amount,"expected":-needed})
	check(SnapshotValidator.validate(sim.snapshot(),catalog)=="","real raised-wage payroll and day record strictly validate",SnapshotValidator.validate(sim.snapshot(),catalog))

func _run()->void:
	if not output.begins_with("E:/CODEX/") or output.simplify_path()!=output or FileAccess.file_exists(output) or DirAccess.dir_exists_absolute(output.get_basename()+"-need-mid-save"):
		printerr("Require fresh E output and personal save directory");quit(2);return
	var loaded:Dictionary=ContentCatalog.load_checked("res://content")
	check(loaded.get("ok",false),"actual catalog loads",loaded.get("error",""))
	if loaded.get("ok",false):
		catalog=loaded.catalog
		check(FileAccess.file_exists("res://campaign/campaign_people.gd"),"independent CampaignPeople runtime exists")
		check(FileAccess.file_exists("res://campaign/campaign_people_validator.gd"),"independent people validator exists")
		if FileAccess.file_exists("res://campaign/campaign_people.gd"):people=load("res://campaign/campaign_people.gd")
		if FileAccess.file_exists("res://campaign/campaign_people_validator.gd"):people_validator=load("res://campaign/campaign_people_validator.gd")
		legacy_compatibility()
		var setup:Dictionary=prepare()
		if not setup.is_empty():patient_need(setup);staff_wage(setup)
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	var file:FileAccess=FileAccess.open(output,FileAccess.WRITE)
	if file==null:quit(2);return
	file.store_string(JSON.stringify({"ok":failed==0,"passed":passed,"failed":failed,"checks":checks,"scope":"Actual public long01 build/hire/assign/delivery/admission/personal request/raise; mid-edge save/replay and payroll. Detached corrupt saves are only negative fixtures. No engine run is claimed by the author."},"  "))
	file.close();print("PEOPLE RESULT passed=",passed," failed=",failed);quit(0 if failed==0 else 1)
