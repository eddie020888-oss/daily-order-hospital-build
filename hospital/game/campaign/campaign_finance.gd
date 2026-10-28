class_name CampaignFinance
extends RefCounted

static func post(d: Dictionary, category: String, amount: int, reference: String) -> bool:
	if reference=="": return false
	for entry in d.ledger_entries:
		if entry.get("reference","")==reference and entry.get("category","")==category:
			return not LongCampaign.is_long(d) or int(entry.amount)==amount
	var reserved:=0
	if amount<0 and not reference.begins_with("care:"):
		var patient_ids:Array=d.campaign.live_patient_ids if LongCampaign.is_long(d) else d.get("patients",{}).keys()
		for id:String in patient_ids:reserved+=d.patients[id].get("reservation_cost",0)
	if amount<0 and d.cash+amount<reserved: return false
	d.cash+=amount
	d.ledger_entries.append({"tick":d.tick,"category":category,"amount":amount,"reference":reference,"cash_after":d.cash})
	if category=="income": d.metrics.income+=amount
	elif category not in ["build","hire","sale","loan","repay","grant"]:
		if not d.metrics.has("expenses"): d.metrics.expenses={}
		d.metrics.expenses[category]=d.metrics.expenses.get(category,0)-amount
		if d.metrics.has(category): d.metrics[category]-=amount
	d.metrics.operating_profit=d.metrics.income
	for expense in d.metrics.get("expenses",{}).values(): d.metrics.operating_profit-=expense
	return true
