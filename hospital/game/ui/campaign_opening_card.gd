class_name CampaignOpeningCard
extends Panel

signal action_requested(focus: Dictionary)

var title_label: Label
var text_label: Label
var phase_label: Label
var action_button: Button
var _focus: Dictionary = {}

func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel",HospitalA2Skin.style("paper",12))
	phase_label=Label.new()
	phase_label.add_theme_font_size_override("font_size",12)
	phase_label.add_theme_color_override("font_color",HospitalA2Skin.MUTED)
	add_child(phase_label)
	title_label=Label.new()
	title_label.add_theme_font_override("font",HospitalUiStyle.font(700))
	title_label.add_theme_font_size_override("font_size",19)
	title_label.add_theme_color_override("font_color",HospitalA2Skin.INK)
	title_label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(title_label)
	text_label=Label.new()
	text_label.add_theme_font_size_override("font_size",13)
	text_label.add_theme_color_override("font_color",HospitalA2Skin.INK)
	text_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	text_label.max_lines_visible=3
	text_label.clip_text=true
	add_child(text_label)
	action_button=Button.new()
	HospitalA2Skin.button(action_button,"primary",16)
	action_button.pressed.connect(func()->void:action_requested.emit(_focus.duplicate(true)))
	add_child(action_button)
	hide()

func present(current: Dictionary,available: bool,bounds: Rect2) -> void:
	if title_label==null:return
	visible=available and bool(current.get("visible",false))
	if not visible:return
	_focus=current.get("focus",{}).duplicate(true)
	phase_label.text="院长值班 · "+str(current.get("phase_name","开业"))
	title_label.text=str(current.get("title","经营医院"))
	text_label.text=str(current.get("text",""))
	action_button.text=str(current.get("button","查看"))
	action_button.disabled=_focus.is_empty()
	var short:bool=bounds.size.y<330
	title_label.add_theme_font_size_override("font_size",17 if short else 19)
	text_label.add_theme_font_size_override("font_size",12 if short else 13)
	var width:float=minf(292,maxf(220,bounds.size.x*.40))
	var height:float=180 if short else 190
	size=Vector2(width,height)
	position=Vector2(bounds.position.x,maxf(bounds.position.y,bounds.end.y-height))
	phase_label.position=Vector2(12,10);phase_label.size=Vector2(width-24,18)
	title_label.position=Vector2(12,33);title_label.size=Vector2(width-24,24)
	title_label.tooltip_text=title_label.text
	text_label.position=Vector2(12,63);text_label.size=Vector2(width-24,51)
	text_label.tooltip_text=text_label.text
	action_button.position=Vector2(12,height-60);action_button.size=Vector2(width-24,48)
