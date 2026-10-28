class_name HospitalA2Skin
extends RefCounted

## Native presentation skin derived from the reviewed Pro A2 UI, not a game simulation.
const INK := Color("294f52")
const TEAL := Color("47797a")
const EDGE := Color("254e50")
const PAPER := Color("fff9ea")
const CORAL := Color("d95742")
const GOLD := Color("d8ad62")
const MUTED := Color("627b70")
const ICON_NAMES := ["crest", "build", "staff", "patient", "chart", "bed"]
# Embedded SVGs also survive resource export without reading imported source files.
const SVG_ART := {"crest": "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"48\" height=\"48\" viewBox=\"0 0 48 48\" aria-hidden=\"true\" fill=\"#fff8e9\" stroke=\"#38676a\" stroke-width=\"2\" stroke-linejoin=\"round\" stroke-linecap=\"round\"><path d=\"M12 18H3v18h12m21-18h9v18H33\" fill=\"#d8ad62\"/><path d=\"M7 23h4m-4 6h4m26-6h4m-4 6h4\"/><circle cx=\"24\" cy=\"24\" r=\"17\"/><path d=\"M13 34a15 15 0 0 0 22 0\" stroke=\"#d8ad62\" fill=\"none\"/><path d=\"M20 13h8v7h7v8h-7v7h-8v-7h-7v-8h7z\" fill=\"#d95742\" stroke=\"none\"/><path d=\"M21 16h4\" stroke=\"#fff8e9\"/><path d=\"M19 5h10\" stroke-width=\"3\"/></svg>", "build": "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"48\" height=\"48\" viewBox=\"0 0 48 48\" aria-hidden=\"true\" fill=\"#fff8e9\" stroke=\"#38676a\" stroke-width=\"2\" stroke-linejoin=\"round\" stroke-linecap=\"round\"><path d=\"M8 6h24l6 6v29H8z\"/><path d=\"M32 6v7h6M13 15h16v8h-8v12h-8z\"/><path d=\"M13 23h4m4 5h8v7\" fill=\"none\"/><path d=\"M10 39h25\" stroke=\"#d8ad62\"/><g transform=\"rotate(-26 34 31)\"><rect x=\"29\" y=\"20\" width=\"11\" height=\"23\" rx=\"2\" fill=\"#d8ad62\"/><path d=\"M29 25h4m-4 6h6m-6 6h4\"/><circle cx=\"35\" cy=\"23\" r=\"1\" fill=\"#38676a\" stroke=\"none\"/></g></svg>", "staff": "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"48\" height=\"48\" viewBox=\"0 0 48 48\" aria-hidden=\"true\" fill=\"#fff8e9\" stroke=\"#38676a\" stroke-width=\"2\" stroke-linejoin=\"round\" stroke-linecap=\"round\"><rect x=\"8\" y=\"7\" width=\"32\" height=\"36\" rx=\"5\" fill=\"#d8ad62\"/><rect x=\"8\" y=\"7\" width=\"32\" height=\"33\" rx=\"5\"/><path d=\"M18 5h12v7H18z\" fill=\"#38676a\"/><path d=\"m18 17-6 6 4 6 3-3v11h14V26l3 3 3-6-8-6-5 3z\"/><path d=\"m19 17 7 6 5-6m-5 6v14\" fill=\"none\"/><path d=\"M29 27h6m-3-3v6\" stroke=\"#d95742\"/><path d=\"M17 5h14\" stroke=\"#fff8e9\"/></svg>", "patient": "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"48\" height=\"48\" viewBox=\"0 0 48 48\" aria-hidden=\"true\" fill=\"#fff8e9\" stroke=\"#38676a\" stroke-width=\"2\" stroke-linejoin=\"round\" stroke-linecap=\"round\"><rect x=\"6\" y=\"6\" width=\"29\" height=\"36\" rx=\"3\"/><path d=\"M8 39h25\" stroke=\"#d8ad62\"/><rect x=\"14\" y=\"4\" width=\"13\" height=\"6\" rx=\"2\" fill=\"#d8ad62\"/><path d=\"M16 15h6v5h5v6h-5v5h-6v-5h-5v-6h5z\" fill=\"#d95742\" stroke=\"none\"/><path d=\"M12 35h12\"/><path d=\"M31 19v7a6 6 0 0 0 12 0v-7m-6 13v4a6 6 0 0 1-6 6h-1\" fill=\"none\"/><path d=\"M30 19h3m8 0h3\" stroke-width=\"3\"/><circle cx=\"28\" cy=\"40\" r=\"3\" fill=\"#d8ad62\"/></svg>", "chart": "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"48\" height=\"48\" viewBox=\"0 0 48 48\" aria-hidden=\"true\" fill=\"#fff8e9\" stroke=\"#38676a\" stroke-width=\"2\" stroke-linejoin=\"round\" stroke-linecap=\"round\"><path d=\"M8 7h26v34H8a3 3 0 0 1-3-3V10a3 3 0 0 1 3-3z\"/><path d=\"M11 7v34\"/><path d=\"M17 15h11m-11 7h11m-11 7h6\"/><path d=\"M7 38h21\" stroke=\"#d8ad62\"/><rect x=\"19\" y=\"12\" width=\"4\" height=\"6\" rx=\"1\" fill=\"#d95742\" stroke=\"none\"/><rect x=\"24\" y=\"19\" width=\"4\" height=\"6\" rx=\"1\" fill=\"#d8ad62\" stroke=\"none\"/><circle cx=\"35\" cy=\"33\" r=\"10\" fill=\"#d8ad62\"/><path d=\"M31 27h8m-8 6h8m-4-6v13\"/><path d=\"M29 28a8 8 0 0 1 10-2\" stroke=\"#fff8e9\" fill=\"none\"/></svg>", "bed": "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"48\" height=\"48\" viewBox=\"0 0 48 48\" aria-hidden=\"true\" fill=\"#fff8e9\" stroke=\"#38676a\" stroke-width=\"2\" stroke-linejoin=\"round\" stroke-linecap=\"round\"><path d=\"M5 13v27m38-13v13\" stroke-width=\"3\"/><path d=\"m8 28 3-12h9l5 12\" fill=\"#d8ad62\"/><rect x=\"10\" y=\"17\" width=\"13\" height=\"9\" rx=\"3\" transform=\"rotate(15 16 21)\"/><path d=\"M6 27h35a2 2 0 0 1 2 2v6H5v-6a2 2 0 0 1 1-2z\"/><path d=\"M24 24h14a3 3 0 0 1 3 3v8H24z\" fill=\"#d95742\"/><path d=\"M7 34h15\" stroke=\"#d8ad62\"/><path d=\"M9 40h5m22 0h5\" stroke-width=\"3\"/><path d=\"M28 27h9\" stroke=\"#fff8e9\"/></svg>"}
static var _icons: Dictionary = {}
static var _equipment: Dictionary = {}

static func style(variant: String="paper", padding: int=8) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	var fills := {"enamel":TEAL, "paper":PAPER, "primary":CORAL,
		"selected":Color("fff0d9"), "quiet":Color("e8e7d4"),
		"danger":Color("f6e2d3"), "clock":Color("254f54"), "muted":Color("e2e6d8")}
	box.bg_color = fills.get(variant, PAPER)
	box.border_color = EDGE if variant in ["enamel", "clock"] else Color("b5c5b7")
	box.set_border_width_all(1)
	box.border_width_bottom = 3 if variant in ["primary", "enamel", "quiet"] else 2
	box.set_corner_radius_all(7 if variant in ["enamel", "primary", "quiet", "danger"] else 3)
	box.set_content_margin_all(padding)
	box.shadow_color = Color(0.10,0.22,0.22,0.16)
	box.shadow_size = 2
	box.shadow_offset = Vector2(0,1)
	if variant == "primary": box.border_color = Color("b64a34")
	elif variant == "selected":
		box.border_color = CORAL
		box.set_border_width_all(2)
	elif variant == "danger": box.border_color = Color("c18d73")
	return box

static func panel(control: PanelContainer, variant: String="enamel") -> void:
	control.add_theme_stylebox_override("panel",style(variant))

static func button(control: Button, variant: String="paper", font_size: int=16, icon_name: String="") -> void:
	control.custom_minimum_size = control.custom_minimum_size.max(Vector2(48,48))
	control.set_meta("minimum_size",control.custom_minimum_size)
	control.add_theme_font_override("font",HospitalUiStyle.font(650))
	control.add_theme_font_size_override("font_size",font_size)
	control.add_theme_constant_override("h_separation",7)
	control.clip_text = false
	var normal := style(variant,8)
	control.add_theme_stylebox_override("normal",normal)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = normal.bg_color.lightened(0.035)
	control.add_theme_stylebox_override("hover",hover)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = normal.bg_color.darkened(0.06)
	pressed.border_width_bottom = 1
	pressed.shadow_size = 0
	control.add_theme_stylebox_override("pressed",pressed)
	var disabled := style("muted",8)
	disabled.shadow_size = 0
	control.add_theme_stylebox_override("disabled",disabled)
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color.TRANSPARENT
	focus.border_color = PAPER if variant in ["primary","enamel","clock"] else CORAL
	focus.set_border_width_all(2)
	focus.set_corner_radius_all(5)
	for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]: focus.set_expand_margin(side,-3)
	control.add_theme_stylebox_override("focus",focus)
	var ink := PAPER if variant in ["primary","enamel","clock"] else Color("9a4634") if variant == "danger" else INK
	for state: String in ["font_color","font_hover_color","font_pressed_color","font_hover_pressed_color","font_focus_color"]:
		control.add_theme_color_override(state,ink)
	control.add_theme_color_override("font_disabled_color",MUTED)
	for state: String in ["icon_normal_color","icon_hover_color","icon_pressed_color","icon_hover_pressed_color","icon_focus_color"]:
		control.add_theme_color_override(state,Color.WHITE)
	control.add_theme_color_override("icon_disabled_color",Color(1,1,1,0.45))
	if icon_name != "":
		control.icon = HospitalUiStyle.icon(icon_name,24) if variant in ["primary","enamel","clock"] and icon_name not in ICON_NAMES else icon(icon_name,32 if icon_name in ICON_NAMES else 24)
	control.expand_icon = true
	control.add_theme_constant_override("icon_max_width",36)

static func icon(name: String, pixels: int=32) -> Texture2D:
	var key := name+":"+str(pixels)
	if not _icons.has(key):
		var svg := ""
		if name in ICON_NAMES:
			svg = str(SVG_ART[name])
			svg = svg.replace('width="48" height="48"','width="%d" height="%d"' % [pixels,pixels])
		else:
			svg = '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 24 24" fill="none" stroke="#294f52" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="%s"/></svg>' % [pixels,pixels,HospitalUiStyle.ICONS.get(name,HospitalUiStyle.ICONS.medical)]
		_icons[key] = DPITexture.create_from_string(svg)
	return _icons[key]

static func equipment_texture(kind: String) -> Texture2D:
	if not _equipment.has(kind):
		var frame := GridEquipmentFrames.frame(kind,0)
		var path := str(frame.get("path",""))
		_equipment[kind] = load(path) if path != "" and ResourceLoader.exists(path) else HospitalUiStyle.thumbnail(kind)
	return _equipment[kind]
