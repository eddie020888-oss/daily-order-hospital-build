class_name GameSession
extends RefCounted

signal changed
signal command_result(result: Dictionary)

const STEP_USEC := 100000
var catalog: ContentCatalog
var sim: Simulation
var save_root: String
var notice := ""
var notice_target: Dictionary={}
var storage_blocked := false
var _backlog := 0
var _background := false
var _serial := 0
var _prefix := "session_%d" % Time.get_ticks_usec()
var _seen_pending := ""
var _reserved_ids: Dictionary={}
var _seen_congestion:=false
var _career_tracks: Dictionary={}
var _presentation_model: Simulation
var _presentation_key: Dictionary={}
var _presentation_cache: Dictionary={}
var _presentation_serial := 0

func _init(content: ContentCatalog, root: String) -> void:
	catalog=content
	save_root=root
	sim=Simulation.new(catalog,_new_state())

func _new_state(level_id: String="") -> ClinicState:
	var target := level_id
	if target=="": target=sim.clock_state().level_id if sim!=null else "level_01"
	_remember_career()
	var fresh := ClinicState.create(target,catalog)
	if fresh==null: return null
	var track:String=_level_track(target)
	if _career_tracks.has(track):
		if fresh.data.get("schema_version",1) in [2,3]: fresh.data.campaign.career=_career_tracks[track].duplicate(true)
		elif track=="full-hospital-v1": fresh.data["campaign_career"]=_career_tracks[track].duplicate(true)
	if not _career_tracks.is_empty():fresh.data["career_tracks"]=_career_tracks.duplicate(true)
	# A private cosmetic RNG never consumes clinical/random business state.
	var cosmetic_rng := RandomNumberGenerator.new()
	cosmetic_rng.randomize()
	fresh.data["appearance_seed"]=cosmetic_rng.randi_range(1,2147483647)
	return fresh

func level_data(level_id: String="") -> Dictionary:
	var target := level_id if level_id!="" else str(sim.clock_state().level_id)
	return catalog.levels.get(target,{}).duplicate(true)

# Menu selection is separate from this explicit, confirmed new-game action.
func start_level(level_id: String) -> Dictionary:
	if storage_blocked: return {"ok":false,"code":"storage_blocked","data":{}}
	if not catalog.levels.has(level_id): return {"ok":false,"code":"unknown_level","data":{}}
	var access:=level_access(level_id)
	if not access.ok: return access
	var fresh := _new_state(level_id)
	if fresh==null: return {"ok":false,"code":"unknown_level","data":{}}
	# Commit the complete career-bearing hospital before replacing a live clinic.
	if fresh.data.get("schema_version",1) in [2,3] or fresh.data.has("campaign_career") or fresh.data.has("career_tracks"):
		var saved:Dictionary=SaveStore.save(fresh.to_data(),save_root)
		if not saved.get("ok",false):
			notice="新关保存失败，当前医院仍保留，请检查存储后重试。"
			changed.emit()
			return {"ok":false,"code":"save_failed","data":saved}
	restart(fresh)
	return {"ok":true,"code":"ok","data":{"level_id":level_id}}

func issue(type: String, payload: Dictionary = {}) -> Dictionary:
	return submit({"id":reserve_command_id(),"type":type,"payload":payload})

# Shared rendering data is detached from the model and recursively read-only.
# snapshot() retains its original mutable-copy contract for saves and previews.
func presentation_snapshot() -> Dictionary:
	var key: Dictionary=sim.clock_state()
	if _presentation_model!=sim or key!=_presentation_key:
		var detached: Dictionary=sim.snapshot()
		_freeze_presentation(detached)
		_presentation_cache=detached
		_presentation_key=key
		_presentation_model=sim
		_presentation_serial+=1
	return _presentation_cache

# An in-memory render revision, never serialized into a clinical save.
func presentation_revision() -> int:
	presentation_snapshot()
	return _presentation_serial

static func _freeze_presentation(value: Variant) -> void:
	if value is Dictionary:
		for child: Variant in value.values(): _freeze_presentation(child)
		value.make_read_only()
	elif value is Array:
		for child: Variant in value: _freeze_presentation(child)
		value.make_read_only()

func reserve_command_id() -> String:
	var receipts: Dictionary=sim.snapshot().command_receipts
	var candidate:=""
	while candidate=="" or receipts.has(candidate) or _reserved_ids.has(candidate):
		_serial+=1
		candidate=_prefix+"_"+str(_serial)
	_reserved_ids[candidate]=true
	return candidate

func submit(command: Dictionary) -> Dictionary:
	if storage_blocked: return {"ok":false,"code":"storage_blocked","data":{}}
	var result:=sim.submit(command)
	if not result.ok: notice_target=_rejection_target(command,result)
	if sim.clock_state().paused: _backlog=0
	command_result.emit(result)
	changed.emit()
	return result

func advance_wall_time(delta_usec: int) -> void:
	if _background or storage_blocked or delta_usec<=0: return
	var clock:Dictionary=sim.clock_state()
	if clock.paused or clock.status!="running":
		_backlog=0
		return
	if clock.schema_version==3 and clock.ruleset=="full-hospital-v2":
		_backlog+=delta_usec*int(clock.speed)
		var advanced:=false
		while _backlog>=STEP_USEC:
			_backlog-=STEP_USEC
			var previous_tick:int=int(clock.tick)
			sim.advance_ticks(1)
			clock=sim.clock_state()
			advanced=advanced or int(clock.tick)!=previous_tick
			if clock.paused or clock.status!="running":
				_backlog=0
				break
		if advanced:changed.emit()
		return
	# Legacy observers and their subtick notifications retain their original order.
	var snapshot:=sim.snapshot()
	_backlog+=delta_usec*int(snapshot.speed)
	while _backlog>=STEP_USEC:
		_backlog-=STEP_USEC
		sim.advance_ticks(1)
		snapshot=sim.snapshot()
		if snapshot.paused or snapshot.challenge.status!="running":
			_backlog=0
			break
	_observe_hint(snapshot)
	_observe_congestion(snapshot)
	changed.emit()

func _observe_hint(snapshot: Dictionary) -> void:
	if snapshot.get("schema_version",1) in [2,3]: return
	var pending: String=snapshot.hint_flags.get("pending","")
	if pending!="" and pending!=_seen_pending:
		_seen_pending=pending
		notice_target={"group":"build","kind":"motion" if pending=="unlock_motion" else "sensory"}
		notice="动作治疗室已解锁。营业已暂停，请建造房间并安排技师，再继续。" if pending=="unlock_motion" else "感官治疗室已解锁。营业已暂停，请建造房间并安排技师，再继续。"

func _rejection_target(command: Dictionary, result: Dictionary) -> Dictionary:
	for key in ["room_id","patient_id","staff_id"]:
		var id: String=result.data.get(key,command.get("payload",{}).get(key,""))
		if id!="": return {"group":{"room_id":"rooms","patient_id":"patients","staff_id":"staff"}[key],"id":id}
	return {}

func _observe_congestion(snapshot: Dictionary) -> void:
	if snapshot.get("schema_version",1) in [2,3]: return
	if _seen_congestion or notice!="": return
	var ids: Array=snapshot.patients.keys()
	ids.sort()
	for id in ids:
		var patient: Dictionary=snapshot.patients[id]
		if patient.get("wait_reason","") not in ["equipment_busy","recovery_full"]: continue
		_seen_congestion=true
		notice="发现患者等候拥堵。可定位相关房间并展开该患者流程，查看累计等待和当前原因。"
		notice_target={"group":"rooms","id":patient.room_id,"patient_id":id,"expand_flow":true}
		break

func dismiss_notice() -> void:
	notice=""
	notice_target={}
	changed.emit()

func open_saved() -> void:
	notice_target={}
	var committed:=FileAccess.file_exists(save_root.path_join("recovery.pending"))
	for name in ["main.json","previous.json","main.swap.json"]:
		committed=committed or FileAccess.file_exists(save_root.path_join(name))
	if not committed: return
	var result: Dictionary={"ok":false} if FileAccess.file_exists(save_root.path_join("recovery.pending")) else SaveStore.load(save_root,catalog)
	if not result.ok:
		storage_blocked=true
		notice="存档无法读取，已保留原文件。可点“保留原档并开新局”恢复游玩；当前不会自动覆盖。"
	else:
		sim=Simulation.new(catalog,result.state)
		_career_tracks.clear()
		_remember_career()
		issue("set_paused",{"paused":true})
		_seen_pending=sim.snapshot().hint_flags.get("pending","")
		notice="主存档损坏，已载入备用存档；营业保持暂停。" if result.used_backup else "已载入存档；营业保持暂停。"
	_backlog=0
	changed.emit()

func save_now() -> Dictionary:
	notice_target={}
	_remember_career()
	var snapshot:Dictionary=sim.snapshot()
	if _career_tracks.is_empty():snapshot.erase("career_tracks")
	else:snapshot["career_tracks"]=_career_tracks.duplicate(true)
	var result: Dictionary={"ok":false,"error":"storage_blocked"} if storage_blocked else SaveStore.save(snapshot,save_root)
	notice="已保存。" if result.ok else "保存失败。当前有效营业状态仍保留；请检查存储空间与权限。"
	changed.emit()
	return result

func handle_focus_lost() -> void:
	if _background: return
	issue("set_paused",{"paused":true})
	_backlog=0
	_background=true
	save_now()

func handle_focus_gained() -> void:
	_background=false
	_backlog=0
	# No wall clock is retained, and focus restoration never starts the clinic.

func recover_new_game(file_io: Variant = null) -> Dictionary:
	if not storage_blocked: return {"ok":false,"error":"not_blocked"}
	var fresh:=_new_state()
	var result:=SaveStore.recover_new_game(fresh.to_data(),save_root,file_io)
	if result.ok:
		storage_blocked=false
		restart(fresh)
		notice="原存档已独立保留，新一局已保存。可以开始布置医院。"
	else:
		notice="保留原档并开新局失败，营业仍已锁定。原有文件或独立保留副本仍在；请检查空间与权限后重试。"
	changed.emit()
	return result

func restart(fresh: ClinicState=null) -> void:
	if storage_blocked: return
	sim=Simulation.new(catalog,_new_state() if fresh==null else fresh)
	_backlog=0
	_seen_pending=""
	_seen_congestion=false
	notice_target={}
	if is_long_campaign(): notice=level_data().get("name","长线医院")+"已就绪。从开业目标开始，准备接待与诊疗，逐步扩大医院。"
	elif is_campaign(): notice=level_data().get("name","职业医院")+"已就绪。先查看当前病例缺项，准备科室、设备与人员后接收。"
	else: notice="新一局已就绪。先布置接待、诊断和声环治疗，再开始营业。" if sim.snapshot().level_id=="level_01" else "联合诊疗已就绪。先安排检查、药房、留观护理与原有诊疗岗位，再开始营业。"
	changed.emit()

func preview(proposal: Dictionary) -> Dictionary:
	var state:=ClinicState.new()
	state.data=sim.snapshot()
	return GridService.preview(state,proposal)

func is_campaign() -> bool:
	if sim==null:return false
	var clock:Dictionary=sim.clock_state()
	var ruleset:String=str(catalog.levels.get(str(clock.level_id),{}).get("ruleset",""))
	return clock.schema_version==2 and ruleset=="full-hospital-v1" or clock.schema_version==3 and ruleset=="full-hospital-v2"

func is_long_campaign() -> bool:
	if sim==null:return false
	var clock:Dictionary=sim.clock_state()
	return clock.schema_version==3 and catalog.levels.get(str(clock.level_id),{}).get("ruleset","")=="full-hospital-v2"

func _level_track(level_id:String) -> String:
	return "full-hospital-v2" if catalog.levels.get(level_id,{}).get("ruleset","")=="full-hospital-v2" else "full-hospital-v1"

func _remember_career() -> void:
	if sim==null: return
	var current:Dictionary=sim.snapshot()
	for ruleset:String in current.get("career_tracks",{}):
		var saved:Variant=current.career_tracks[ruleset]
		if saved is Dictionary and not saved.get("completed_levels",[]).is_empty():_career_tracks[ruleset]=saved.duplicate(true)
	var value:Dictionary=current.get("campaign",{}).get("career",{}) if current.get("schema_version",1) in [2,3] else current.get("campaign_career",{})
	var track:String=_level_track(str(current.level_id))
	if value.has("completed_levels") and value.has("receipts"):
		if value.completed_levels.is_empty():_career_tracks.erase(track)
		else:_career_tracks[track]=value.duplicate(true)

func _career_for(ruleset:String) -> Dictionary:
	return _career_tracks.get(ruleset,{"ruleset":ruleset,"completed_levels":[],"receipts":{}}).duplicate(true)

func campaign_levels() -> Array:
	var result:Array=[]
	for level:Dictionary in catalog.levels.values():
		if level.get("ruleset","")=="full-hospital-v1": result.append(level.duplicate(true))
	result.sort_custom(func(a:Dictionary,b:Dictionary)->bool: return int(a.order)<int(b.order))
	return result

func long_campaign_levels() -> Array:
	var result:Array=[]
	for level:Dictionary in catalog.levels.values():
		if level.get("ruleset","")=="full-hospital-v2":result.append(level.duplicate(true))
	result.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return int(a.order)<int(b.order))
	return result

func level_access(level_id:String) -> Dictionary:
	if not catalog.levels.has(level_id): return {"ok":false,"code":"unknown_level","data":{}}
	var target:Dictionary=catalog.levels[level_id]
	var ruleset:String=str(target.get("ruleset",""))
	if ruleset not in ["full-hospital-v1","full-hospital-v2"]: return {"ok":true,"code":"ok","data":{}}
	_remember_career()
	var career:Dictionary=_career_for(ruleset)
	var levels:Array=long_campaign_levels() if ruleset=="full-hospital-v2" else campaign_levels()
	var index:int=-1
	for i in range(levels.size()):
		if levels[i].id==level_id: index=i;break
	if index<0: return {"ok":false,"code":"unknown_level","data":{}}
	if index==0: return {"ok":true,"code":"ok","data":{}}
	var previous:Dictionary=levels[index-1]
	if previous.id not in career.get("completed_levels",[]) or not career.get("receipts",{}).has(previous.id):
		return {"ok":false,"code":"level_locked","data":{"required_level":previous.id,"required_name":previous.name}}
	var error:String=CampaignProgress.validate(career,catalog)
	if error!="": return {"ok":false,"code":"career_invalid","data":{"reason":error}}
	return {"ok":true,"code":"ok","data":{}}

func next_level_info() -> Dictionary:
	if not is_campaign(): return {"ok":false,"code":"not_campaign","data":{}}
	var snapshot:Dictionary=sim.snapshot()
	_remember_career()
	var career:Dictionary=_career_for(_level_track(str(snapshot.level_id)))
	var passed:bool=bool(snapshot.campaign.get("course_complete",false)) if is_long_campaign() else snapshot.challenge.status=="won"
	if not passed or not career.receipts.has(snapshot.level_id):
		return {"ok":false,"code":"level_not_won","data":{}}
	if CampaignProgress.validate(career,catalog)!="": return {"ok":false,"code":"career_invalid","data":{}}
	var levels:Array=long_campaign_levels() if is_long_campaign() else campaign_levels()
	for index in range(levels.size()):
		if levels[index].id==snapshot.level_id:
			if index+1>=levels.size(): return {"ok":false,"code":"career_complete","data":{}}
			return {"ok":true,"code":"ok","data":{"level":levels[index+1].duplicate(true)}}
	return {"ok":false,"code":"unknown_level","data":{}}

func next_level() -> Dictionary:
	var next:Dictionary=next_level_info()
	if not next.ok: return next
	return start_level(next.data.level.id)
