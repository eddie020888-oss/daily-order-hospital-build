class_name Metrics
extends RefCounted

# Derived views never mutate the model. The denominator includes every arrival,
# including outside, abandoned and unfinished patients, rather than only successes.
static func summary(state: ClinicState) -> Dictionary:
	var d := state.data
	var disposition := {"not_arrived":d.scheduled_arrivals.size()-d.arrival_cursor,"outside":0,"in_hospital":0,"completed":0,"abandoned":0,"abandoning":0}
	var waiting := 0
	var walked := 0
	var visit := 0
	var by_stage := {}
	var patients := {}
	for arrival in d.scheduled_arrivals:
		if not d.patients.has(arrival.id):
			patients[arrival.id] = {"disposition":"not_arrived","arrival_tick":arrival.tick,"disease_id":arrival.disease_id,"tolerance":arrival.tolerance}
	for id in d.patients:
		var p: Dictionary = d.patients[id]
		var category: String = p.phase if p.phase in ["outside","completed","abandoned"] else "in_hospital"
		disposition[category] += 1
		if p.phase == "abandoning":
			disposition.abandoning += 1
		waiting += p.wait_ticks
		walked += p.get("walked_cells",0)
		var end: int = p.get("exit_tick",-1)
		var elapsed: int = maxi(0,(end if end >= 0 else d.tick)-p.get("arrival_tick",d.tick))
		visit += elapsed
		for stage in p.wait_by_stage:
			by_stage[stage] = by_stage.get(stage,0)+p.wait_by_stage[stage]
		patients[id] = {"disposition":category,"phase":p.phase,"arrival_tick":p.get("arrival_tick",-1),"admitted_tick":p.get("admitted_tick",-1),"exit_tick":end,"wait_ticks":p.wait_ticks,"wait_by_stage":p.wait_by_stage.duplicate(true),"walked_cells":p.get("walked_cells",0),"total_ticks":elapsed,"disease_id":p.get("disease_id",""),"tolerance":p.get("tolerance",0),"service_mode":p.get("service_mode","")}
	var arrived: int = d.patients.size()
	return {"waiting_mean_ticks":float(waiting)/arrived if arrived > 0 else 0.0,"waiting_sum_ticks":waiting,"arrived_count":arrived,
		"completed":disposition.completed,"abandoned":disposition.abandoned,"operating_profit":d.metrics.operating_profit,
		"dispositions":disposition,"wait_by_stage":by_stage,"walked_cells":walked,"visit_mean_ticks":float(visit)/arrived if arrived > 0 else 0.0,
		"income":d.metrics.income,"treatment_cost":d.metrics.treatment_cost,"recovery_cost":d.metrics.recovery_cost,"wages":d.metrics.wages,"fixed_cost":d.metrics.fixed_cost,"cash":d.cash,"patients":patients}
