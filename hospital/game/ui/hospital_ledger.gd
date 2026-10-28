class_name HospitalLedger
extends VBoxContainer

var _values: Dictionary={}
var _metrics: Array[Label]=[]
var _disposition: Label
var _line_nodes: Dictionary={}
var _titles: Dictionary={}
var _profit_explanation: Label

func _ready() -> void:
	add_theme_constant_override("separation",0)
	var grid:=GridContainer.new()
	grid.columns=3
	grid.add_theme_constant_override("h_separation",10)
	add_child(grid)
	for title in ["现金","经营利润","完成离院"]:
		var card:=PanelContainer.new()
		card.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		var style:=HospitalUiStyle.panel(11,Color("edf2e7"),14)
		style.set_border_width_all(0)
		card.add_theme_stylebox_override("panel",style)
		grid.add_child(card)
		var col:=VBoxContainer.new()
		col.add_theme_constant_override("separation",4)
		card.add_child(col)
		col.add_child(HospitalUiStyle.text(title,14,HospitalUiStyle.MUTED))
		var value:=HospitalUiStyle.text("0",27,HospitalUiStyle.INK,750)
		col.add_child(value)
		_metrics.append(value)
	_section("营业收支")
	for row in [["income","离院收入"],["treatment_cost","治疗耗材"],["recovery_cost","恢复耗材"],["wages","员工工资"],["fixed_cost","固定支出"]]:
		_line(row[0],row[1])
	_section("资本投入 · 不计经营利润")
	for row in [["capital_build","建设"],["capital_hire","招聘"],["capital_upgrade","升级"],["capital_refund","退款"]]:
		_line(row[0],row[1])
	var profit_note:=HospitalUiStyle.summary(self,"经营利润如何计算","离院收入减去耗材、工资和固定支出。建设、招聘与退款单独核算。")
	_profit_explanation=profit_note.get_child(0).get_child(1) as Label
	_section("患者去向")
	_disposition=HospitalUiStyle.text("",16,HospitalUiStyle.MUTED)
	_disposition.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	add_child(_disposition)
	_section("各阶段累计等待")
	for row in SelectionPanel.stage_rows(true):
		_line("wait_"+row[0],row[1])

func _section(copy: String) -> void:
	var gap:=Control.new()
	gap.custom_minimum_size.y=18
	add_child(gap)
	add_child(HospitalUiStyle.text(copy,18,HospitalUiStyle.INK,700))
	var after:=Control.new()
	after.custom_minimum_size.y=8
	add_child(after)

func _line(key: String, copy: String) -> void:
	var inset:=MarginContainer.new()
	inset.add_theme_constant_override("margin_top",10)
	inset.add_theme_constant_override("margin_bottom",10)
	add_child(inset)
	var row:=HBoxContainer.new()
	inset.add_child(row)
	var title:=HospitalUiStyle.text(copy,17)
	title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	row.add_child(title)
	_titles[key]=title
	var value:=HospitalUiStyle.text("0",17,HospitalUiStyle.INK,650)
	row.add_child(value)
	_values[key]=value
	var separator:=HSeparator.new()
	add_child(separator)
	_line_nodes[key]=[inset,separator]

func present(snapshot: Dictionary) -> void:
	if _metrics.is_empty(): return
	var m: Dictionary=snapshot.metrics
	var clinical: bool=snapshot.level_id=="clinical_02"
	_titles.treatment_cost.text="诊疗耗材" if clinical else "治疗耗材"
	_profit_explanation.text="离院收入减去治疗、发药、留观与恢复耗材、工资和固定支出。建设、招聘与退款单独核算。" if clinical else "离院收入减去耗材、工资和固定支出。建设、招聘与退款单独核算。"
	_metrics[0].text=_number(snapshot.cash)
	_metrics[1].text=("+" if m.operating_profit>0 else "")+_number(m.operating_profit)
	_metrics[2].text=str(m.completed)
	for key in ["income","treatment_cost","recovery_cost","wages","fixed_cost"]:
		var value: Label=_values[key]
		value.text=("+" if key=="income" else "−")+_number(m[key])
		value.add_theme_color_override("font_color",HospitalUiStyle.TEAL if key=="income" else Color("a54d3d"))
	var capital:={"capital_build":0,"capital_hire":0,"capital_upgrade":0,"capital_refund":0}
	for entry in snapshot.ledger_entries:
		if capital.has(entry.category): capital[entry.category]+=entry.delta
	for key in capital:
		_values[key].text=("+" if capital[key]>0 else "")+_number(capital[key])
	var state:=ClinicState.new()
	state.data=snapshot.duplicate(true)
	var summary:=Metrics.summary(state)
	var d: Dictionary=summary.dispositions
	_disposition.text="未到院 %d · 院外 %d · 在院未完成 %d\n完成离院 %d · 弃诊离院 %d\n弃诊离院中的 %d 人仍计入在院未完成。" % [d.not_arrived,d.outside,d.in_hospital,d.completed,d.abandoned,d.abandoning]
	for row in SelectionPanel.stage_rows(true):
		var key: String=row[0]
		_values["wait_"+key].text="%.1f 秒" % (summary.wait_by_stage.get(key,0)/10.0)
		for node: Control in _line_nodes["wait_"+key]: node.visible=key not in SelectionPanel.CARE_STAGES or snapshot.level_id=="clinical_02"

static func _number(value: int) -> String:
	var digits:=str(absi(value))
	var formatted:=""
	for i in range(digits.length()):
		if i>0 and (digits.length()-i)%3==0: formatted+=","
		formatted+=digits[i]
	return ("−" if value<0 else "")+formatted
