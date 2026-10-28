class_name Simulation
extends RefCounted

var _catalog: ContentCatalog
var _state: ClinicState

func _init(catalog: ContentCatalog, state: ClinicState) -> void:
	_catalog = catalog
	_state = state

func submit(command: Dictionary) -> Dictionary:
	return CommandBus.apply(_state, _catalog, command)

func snapshot() -> Dictionary:
	return _state.to_data()

# Detached scalar polling avoids copying clinical and financial history per frame.
func clock_state() -> Dictionary:
	var d:Dictionary=_state.data
	return {"schema_version":d.get("schema_version",1),"ruleset":d.get("ruleset",""),"level_id":d.level_id,"tick":d.tick,"paused":d.paused,"speed":d.speed,"status":d.challenge.status,"command_sequence":d.get("command_sequence",0)}

# A caller supplies fixed 100ms ticks; speed belongs to the session scheduler.
func advance_ticks(count: int) -> void:
	for _index in range(maxi(0, count)):
		if _state.data.paused or _state.data.challenge.status != "running":
			break
		_state.data.tick += 1
		if CampaignContent.is_campaign(_state.data):
			CampaignClinicalFlow.after_tick(_state,_catalog)
			CampaignOperations.after_tick(_state,_catalog)
			continue
		_advance_clinical_phases()
		_advance_business_phases()

func _advance_clinical_phases() -> void:
	PatientFlow.finish_services(_state, _catalog)
	PatientFlow.move_actors(_state, _catalog)
	PatientFlow.expire_patience(_state, _catalog)
	PatientFlow.admit_arrivals(_state, _catalog)

func _advance_business_phases() -> void:
	Challenge.after_tick(_state, _catalog)
