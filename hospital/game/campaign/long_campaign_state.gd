class_name LongCampaignState
extends RefCounted

const RULESET := "full-hospital-v2"

static func create(level_id: String,catalog: ContentCatalog) -> ClinicState:
	if not catalog.levels.has(level_id) or catalog.levels[level_id].get("ruleset","")!=RULESET: return null
	var level: Dictionary=catalog.levels[level_id]
	# This is an initial factory template, never a migration of a running save.
	# The original twelve factories and their authored opening stock stay intact.
	var base_id: String=str(level.get("base_level_id","career_"+level_id.trim_prefix("long_")))
	var state: ClinicState=CampaignState.create(base_id,catalog)
	if state==null: return null
	var d: Dictionary=state.data
	d.schema_version=3; d.ruleset=RULESET
	d.level_id=level_id; d.scenario_id=level_id
	d.cash=int(level.initial_cash)
	d.unlocked_room_kinds=level.get("initial_unlocked_room_kinds",[]).duplicate()
	d.next_ids.case_instance=1
	var cp: Dictionary=d.campaign
	cp.phase_index=0; cp.phase_started_tick=0
	cp.phase_baseline={"tick":0,"completed":0,"abandoned":0,"income":0,"expenses":0,"day_index":0}
	cp.phase_receipts=[]; cp.case_instances={}; cp.admission_events={}
	cp.intake_enabled=false; cp.intake_cursor=0; cp.next_arrival_tick=0; cp.intake_reason=""
	cp.live_patient_ids=[]; cp.active_order_ids=[]; cp.automation={}
	cp.day_records=[]; cp.day_start_tick=0; cp.day_start_income=0; cp.day_start_expenses=0
	cp.day_start_completed=0; cp.day_start_abandoned=0
	cp.course_complete=false; cp.continuing=false
	cp.next_event_tick=int(level.get("event_interval_ticks",12000)); cp.event_serial=0
	cp.career={"ruleset":RULESET,"completed_levels":[],"receipts":{}}
	CampaignExperience.initialize(d)
	CampaignPeople.init_campaign(d)
	CampaignBusiness.initialize(d)
	CampaignManagementEvents.initialize(d)
	cp.clinical_decisions_version=1;cp.clinical_policy="balanced"
	d.metrics.referred=0
	return state
