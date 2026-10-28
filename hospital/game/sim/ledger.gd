class_name Ledger
extends RefCounted

const OPERATING := ["income", "treatment_cost", "recovery_cost", "wages", "fixed_cost"]
const CAPITAL := ["capital_build", "capital_hire", "capital_upgrade", "capital_refund"]

# Entries are the authoritative event-ID set. Costs contribute positive expense
# totals, while operating_profit sums their signed deltas. Capital is excluded.
static func post(state: ClinicState, event_id: String, category: String, delta: int, tick: int) -> bool:
	if event_id.is_empty() or tick < 0 or (category not in OPERATING and category not in CAPITAL):
		return false
	if (category in ["income", "capital_refund"] and delta < 0) or (category not in ["income", "capital_refund"] and delta > 0):
		return false
	for entry in state.data.ledger_entries:
		if entry.event_id == event_id:
			return false
	state.data.cash += delta
	state.data.ledger_entries.append({"event_id":event_id, "category":category, "delta":delta, "tick":tick})
	if category in OPERATING:
		state.data.metrics.operating_profit += delta
		state.data.metrics[category] += delta if category == "income" else -delta
	return true
