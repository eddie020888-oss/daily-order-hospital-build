extends SceneTree

# External feature RED/GREEN; missing new APIs fail checks, never a parse error.
# Resource identity and save compatibility only, not all-person gameplay capture.
const COUNTS := {"doctor":60,"technician":8,"receptionist":8,"patient":48}
const PINS := {"doctor":1,"patient":0,"receptionist":0,"technician":2}
var output_dir := ""
var passed := 0
var failed := 0
var checks: Array[Dictionary] = []
var library: Script
var has_seed_api := false
var coverage: Dictionary = {}

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("output="):output_dir=arg.trim_prefix("output=").replace("\\","/")
	_run.call_deferred()

func check(value: bool,label: String) -> void:
	checks.append({"check":label,"ok":value})
	if value:passed+=1
	else:
		failed+=1
		printerr("APPEARANCE FAIL: "+label)

func _method(script: Script,name: String,minimum_args: int) -> bool:
	for method in script.get_script_method_list():
		if str(method.name)==name:return method.args.size()>=minimum_args
	return false

func _index(family: String,index: int,seed: int) -> int:
	var result: Variant=library.call("seeded_index",family,index,seed)
	if not result is int:
		check(false,"seeded_index must return integer")
		return -1
	return int(result)

func _mapping(seed: int) -> Array:
	var mapping: Array = []
	for family: String in COUNTS:
		for index in range(36 if family=="patient" else 8):
			mapping.append(SceneArtLibrary.asset_id(family,_index(family,index,seed)))
	return mapping

func _resolver_checks() -> void:
	for family: String in COUNTS:
		var seen_all: Dictionary = {}
		for index in range(int(COUNTS[family])*2):
			check(_index(family,index,0)==posmod(index,int(COUNTS[family])),family+" seed0 preserves exact legacy index "+str(index))
		for seed in range(1,60):
			var seen: Dictionary = {}
			var valid := true
			var stable := true
			var pins := true
			for index in range(36 if family=="patient" else 8):
				var resolved := _index(family,index,seed)
				valid=valid and resolved>=0 and resolved<int(COUNTS[family]) and not seen.has(resolved)
				stable=stable and resolved==_index(family,index,seed)
				var pinned: int=PINS[family]
				pins=pins and (resolved==pinned if index==pinned else resolved!=pinned)
				seen[resolved]=true;seen_all[resolved]=true
			check(valid,family+" ordinary ID range family-valid and duplicate-free seed"+str(seed))
			check(stable,family+" repeat resolver stable seed"+str(seed))
			check(pins,family+" retained canonical excluded from remaining deck seed"+str(seed))
		check(seen_all.size()==int(COUNTS[family]),family+" full family reachable over finite seeds1..59")
		coverage[family]=seen_all.size()
	for index in range(36):
		for disease in ["echo","motion","sensory"]:
			check(_index(disease,index,17)==_index("patient",index,17),"patient appearance independent of disease "+str(index)+" "+disease)
	var before := _mapping(23)
	_mapping(41)
	check(before==_mapping(23),"other session seed cannot mutate an existing mapping")

func _storage_checks(catalog: ContentCatalog) -> void:
	var legacy := ClinicState.create("level_01",catalog).to_data()
	check(not legacy.has("appearance_seed"),"old ClinicState without field remains representable")
	var legacy_dir := output_dir.path_join("legacy-save")
	var legacy_save := SaveStore.save(legacy,legacy_dir)
	check(legacy_save.ok,"actual old snapshot save succeeds")
	var old_session := GameSession.new(catalog,legacy_dir)
	old_session.open_saved()
	check(not old_session.storage_blocked and int(old_session.sim.snapshot().get("appearance_seed",0))==0,"open_saved old missing seed stays legacy0, never rerolls")
	if has_seed_api:check(_mapping(0)==_mapping(int(old_session.sim.snapshot().get("appearance_seed",0))),"old saved identities remain exact legacy mapping")
	var fresh_dir := output_dir.path_join("new-save")
	var fresh := GameSession.new(catalog,fresh_dir)
	var snapshot := fresh.sim.snapshot()
	var new_seed: Variant=snapshot.get("appearance_seed",null)
	var positive := new_seed is int and int(new_seed)>0
	check(positive,"new GameSession persists positive integer appearance_seed")
	var mapping_before: Array=_mapping(int(new_seed)) if positive and has_seed_api else []
	var saved := fresh.save_now()
	check(saved.ok,"new session actual SaveStore save succeeds")
	var reopened := GameSession.new(catalog,fresh_dir)
	reopened.open_saved()
	check(not reopened.storage_blocked and reopened.sim.snapshot().get("appearance_seed",null)==new_seed,"actual save/open restores seed without redraw")
	if positive and has_seed_api:check(mapping_before==_mapping(int(reopened.sim.snapshot().appearance_seed)),"all ordinary role appearances stable through actual save/open")
	for bad in [-1,0,1.5,"7",true,null]:
		var invalid: Dictionary=legacy.duplicate(true)
		invalid["appearance_seed"]=bad
		check(not SnapshotValidator.validate(invalid,catalog).is_empty(),"validator rejects present nonpositive/noninteger seed "+str(bad))
	var seeded: Dictionary=legacy.duplicate(true)
	seeded["appearance_seed"]=17
	check(SnapshotValidator.validate(seeded,catalog).is_empty(),"validator accepts optional positive seed with unchanged clinical state")
	var clinical_before: Dictionary=snapshot.duplicate(true)
	clinical_before.erase("appearance_seed")
	check(clinical_before==legacy,"new seed changes no clinical state, budget, ID, scheduled patient or numeric field")
	fresh.restart()
	var restart_seed: Variant=fresh.sim.snapshot().get("appearance_seed",null)
	check(restart_seed is int and int(restart_seed)>0,"restart creates positive seed for the new session")
	# Do not demand random seeds differ on every call: valid random draws can collide.
	var recovery_dir := output_dir.path_join("recovered-save")
	var recovery_session := GameSession.new(catalog,recovery_dir)
	recovery_session.storage_blocked=true
	var recovered := recovery_session.recover_new_game()
	var disk := SaveStore.load(recovery_dir,catalog)
	check(recovered.ok and disk.ok and not recovery_session.storage_blocked,"explicit recovery actually saves a valid new game")
	if recovered.ok and disk.ok:
		var memory_seed: Variant=recovery_session.sim.snapshot().get("appearance_seed",null)
		var disk_seed: Variant=disk.state.to_data().get("appearance_seed",null)
		check(memory_seed is int and int(memory_seed)>0 and disk_seed==memory_seed,"recovery writes and runs the same fresh seed without second draw")

func _production_binding_checks() -> void:
	for seed in [0,17,58]:
		for family: String in COUNTS:
			for index in [int(PINS[family]),3 if int(PINS[family])!=3 else 4]:
				var actor := ActorView.new()
				actor.entity_id=("staff_%03d" if family!="patient" else "patient_%06d") % (index+1)
				actor.appearance_seed=seed
				root.add_child(actor)
				actor.present({"role":family,"disease_id":"echo","cell":100,"phase":"idle"},family!="patient")
				var expected := SceneArtLibrary.asset_id(family,_index(family,index,seed))
				var portrait := HospitalUiStyle.portrait(family,index,seed)
				check(actor.get_meta("model_asset","")==expected and actor._body_root.get_meta("model_asset","")==expected,"actual ActorView uses stable seeded canonical "+expected)
				check(portrait!=null and portrait.get_meta("model_asset","")==expected,"actual UI same-seed portrait matches body "+expected)
				actor.free()
	var world := HospitalWorld.new()
	root.add_child(world)
	var snapshot := {"staff":{"staff_003":{"role":"doctor","cell":100,"phase":"idle"}},"patients":{},"rooms":{},"slots":{},"paused":true,"speed":1,"tick":0,"appearance_seed":17}
	world.present(snapshot)
	check(world.actor_views.staff_003.appearance_seed==17 and world.actor_views.staff_003.get_meta("model_asset","")==SceneArtLibrary.asset_id("doctor",_index("doctor",2,17)),"HospitalWorld forwards saved seed to new ActorView")
	snapshot.appearance_seed=58
	world.present(snapshot)
	check(world.actor_views.staff_003.appearance_seed==58 and world.actor_views.staff_003.get_meta("model_asset","")==SceneArtLibrary.asset_id("doctor",_index("doctor",2,58)),"HospitalWorld refreshes existing same-ID actor with new session seed")
	snapshot.erase("appearance_seed")
	world.present(snapshot)
	check(world.actor_views.staff_003.appearance_seed==0 and world.actor_views.staff_003.get_meta("model_asset","")=="doctor-03","HospitalWorld missing old-save seed restores exact legacy identity")
	world.free()

func _run() -> void:
	if not output_dir.begins_with("E:/CODEX/") or "/../" in output_dir or DirAccess.dir_exists_absolute(output_dir):
		printerr("fresh output=E:/CODEX/... required")
		quit(1);return
	DirAccess.make_dir_recursive_absolute(output_dir)
	library=load("res://presentation/scene_art_library.gd")
	has_seed_api=_method(library,"seeded_index",3)
	check(has_seed_api,"uniform SceneArtLibrary.seeded_index(role,index,seed) exists")
	check(_method(library,"portrait",3),"SceneArtLibrary.portrait accepts optional seed")
	check(_method(load("res://ui/hospital_ui_style.gd"),"portrait",3),"UI portrait forwards same optional seed")
	var actor := ActorView.new()
	var has_actor_seed := false
	for property in actor.get_property_list():
		if str(property.name)=="appearance_seed":has_actor_seed=true
	check(has_actor_seed,"ActorView receives explicit appearance_seed default0")
	actor.free()
	if has_seed_api:
		_resolver_checks()
		_production_binding_checks()
	var loaded := ContentCatalog.load_checked("res://content")
	check(loaded.ok,"actual normal catalog loads")
	if loaded.ok:_storage_checks(loaded.catalog)
	var report := {"passed":passed,"failed":failed,"checks":checks,"finite_seed_family_coverage":coverage,
		"scope":"seed0 legacy mapping, ordinary initial staff indices0..7 and patient0..35 per family, finite seeds1..59, real SaveStore/GameSession reload. Not infinite ID uniqueness or 124 simultaneous entities.",
		"has_seeded_index":has_seed_api,"simulation_attributes_modified_by_tool":false,
		"validator_scope":"Constructed invalid snapshots only for validation input; never overwrite game saves or pretend clinical phases.",
		"art_accepted":false,"mobile_hardware_tested":false,"script_sha256":FileAccess.get_sha256(get_script().resource_path)}
	var file := FileAccess.open(output_dir.path_join("manifest.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "));file.close()
	print("APPEARANCE RESULT: passed=%d failed=%d" % [passed,failed])
	quit(1 if failed else 0)
