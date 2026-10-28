class_name HospitalUiStyle
extends RefCounted

# Modern hospital instruments: a quiet frame, restrained depth and clear data.
const INK := Color("243f47")
const TEAL := Color("256970")
const PAPER := Color("e5eeeb")
const MUTED := Color("405e66")
const LINE := Color("a4bbb8")
const GOLD := Color("966a27")
const SOFT := Color("d1e2de")
const DEEP := Color("183f48")
const IVORY := Color("f3f3e8")
const DANGER := Color("a14a3d")
const DEVICE_NAMES := {"reception":"接待柜台与叫号机","diagnosis":"检查椅与诊断台","echo":"声环梳理台","motion":"动作编排台","sensory":"感官分轨舱","recovery":"安静恢复椅"}
const ICONS := {
	"coin":"M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18ZM15 8h-4a2 2 0 0 0 0 4h2a2 2 0 0 1 0 4H9m3-10v12",
	"home":"M3 21V8l9-5 9 5v13H3Zm5 0v-6h8v6M8 8h1m6 0h1M8 11h1m6 0h1",
	"people":"M9 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8ZM2 21v-3a7 7 0 0 1 14 0v3M16 4a4 4 0 0 1 0 8m3 3a6 6 0 0 1 3 6",
	"person":"M12 12a4 4 0 1 0 0-8 4 4 0 0 0 0 8ZM4 21v-2a8 8 0 0 1 16 0v2",
	"chart":"M4 20V10m8 10V4m8 16v-8M2 22h20",
	"play":"m8 4 12 8-12 8V4Z", "pause":"M8 5v14M16 5v14",
	"close":"m6 6 12 12M18 6 6 18", "back":"m14 5-7 7 7 7",
	"save":"M4 3h13l4 4v14H3V3h1Zm3 0v6h10V3M7 21v-7h10v7",
	"settings":"M12 8a4 4 0 1 0 0 8 4 4 0 0 0 0-8ZM9 3h6l1 3 3 1 2 4-2 3v4l-4 3-3-1-3 1-4-3v-4l-2-3 2-4 3-1 1-3Z",
	"clock":"M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18Zm0 4v5l4 2",
	"bed":"M3 20V5m0 10h18v5M3 9h6v6m0-5h9a3 3 0 0 1 3 3v2",
	"alert":"m12 3 10 18H2L12 3Zm0 6v5m0 3v1", "rotate":"M4 8a9 9 0 1 1 1 10M3 3v6h6",
	"plus":"M12 5v14M5 12h14"
	,"check":"m5 12 4 4L19 6",
	"medical":"M9 3h6v6h6v6h-6v6H9v-6H3V9h6V3Z",
	"help":"M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18Zm-3 6a3 3 0 1 1 5 2c-2 1-2 2-2 3m0 3v.2",
	"sound":"M4 10h4l5-4v12l-5-4H4v-4Zm12-2a6 6 0 0 1 0 8m3-11a10 10 0 0 1 0 14",
	"lock":"M6 10h12v11H6V10Zm3 0V6a3 3 0 0 1 6 0v4m-3 4v3",
	"arrow":"M4 12h16m-6-6 6 6-6 6",
	"shield":"M12 3 3 6v6c0 5 9 9 9 9s9-4 9-9V6l-9-3Zm-4 9 3 3 5-6"
}
static var _icons: Dictionary = {}
static var _fonts: Dictionary = {}
static var _bevels: Dictionary = {}
const TOOL_ART := {
	"home":'<path d="m7 19 10-12" stroke="#243c44" stroke-width="6"/><path d="m7 19 10-12" stroke="#b68b51" stroke-width="4"/><path d="m11 5 4-3 7 6-4 4Z" fill="#d5e1df" stroke="#304f58" stroke-width="1.3"/><path d="m13 5 5 4" stroke="#ffffff" stroke-width="1.5"/>',
	"people":'<path d="M2 22v-5a6 6 0 0 1 12 0v5M12 22v-4a5 5 0 0 1 10 0v4" fill="#e7eddf" stroke="#2e5662" stroke-width="1.3"/><circle cx="8" cy="8" r="4" fill="#be8c66" stroke="#37525b"/><circle cx="17" cy="9" r="3.6" fill="#e1b38a" stroke="#37525b"/><path d="m5 14 3 4 3-4M15 15l2 4 2-4" fill="#4c8f9c" stroke="#315e6c"/>',
	"person":'<path d="M5 3h14v19H5Z" fill="#f0eee0" stroke="#385c65" stroke-width="1.4"/><path d="M9 2h6v4H9Z" fill="#82b4b2" stroke="#385c65"/><path d="M11 8h2v3h3v2h-3v3h-2v-3H8v-2h3Z" fill="#b95848"/><path d="M8 18h8" stroke="#466b76" stroke-width="1.5"/>',
	"chart":'<path d="M3 4h18v17H3Z" fill="#e4eadc" stroke="#33575f" stroke-width="1.5"/><path d="M5 18h14M7 16v-4m5 4V8m5 8V6" stroke="#3b8999" stroke-width="2"/><circle cx="18" cy="18" r="4" fill="#d2ad5b" stroke="#71572f"/><path d="M18 15v6m2-5h-3v2h2v2h-3" stroke="#786036" stroke-width=".9" fill="none"/>'
}

static func tool_icon(key: String, pixels: int=28) -> Texture2D:
	if not TOOL_ART.has(key):return icon(key,pixels)
	var cache_key:="tool:"+key+":"+str(pixels)
	if not _icons.has(cache_key):
		var svg:='<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 24 24" stroke-linejoin="round" stroke-linecap="round">%s</svg>'%[pixels,pixels,TOOL_ART[key]]
		_icons[cache_key]=DPITexture.create_from_string(svg)
	return _icons[cache_key]

static func font(weight: int=400) -> FontVariation:
	if not _fonts.has(weight):
		var variation:=FontVariation.new()
		variation.base_font=load("res://assets/fonts/NotoSansSC-VF.ttf")
		variation.variation_opentype={2003265652:float(weight)}
		_fonts[weight]=variation
	return _fonts[weight]

static func icon(key: String, pixels: int=24) -> Texture2D:
	var cache_key:=key+":"+str(pixels)
	if _icons.has(cache_key): return _icons[cache_key]
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 24 24" fill="none" stroke="#ffffff" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="%s"/></svg>' % [pixels,pixels,ICONS.get(key,ICONS.home)]
	# Retain logical size while rasterizing the same SVG for each draw density.
	var texture := DPITexture.create_from_string(svg)
	_icons[cache_key] = texture
	return texture

static func panel(radius: int=18, color: Color=PAPER, padding: int=20) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.border_color = LINE
	s.set_border_width_all(1)
	s.set_corner_radius_all(mini(radius,6))
	s.set_content_margin_all(padding)
	s.shadow_size = 0
	return s

static func bevel(fill: Color=SOFT, padding: int=10, depressed: bool=false) -> StyleBoxTexture:
	var key:=fill.to_html()+":"+str(padding)+":"+str(depressed)
	if not _bevels.has(key):
		var top:=fill.darkened(.035) if depressed else fill.lightened(.075)
		var bottom:=fill.darkened(.015)
		var edge:=fill.darkened(.20) if fill.get_luminance()>.35 else fill.lightened(.12)
		var svg:='<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64"><defs><linearGradient id="surface" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#%s"/><stop offset="1" stop-color="#%s"/></linearGradient></defs><rect x=".5" y=".5" width="63" height="63" rx="6" fill="url(#surface)" stroke="#%s" stroke-width="1"/><path d="M7 1.5h50" stroke="#ffffff" stroke-opacity="%s" stroke-width="1"/></svg>'%[top.to_html(false),bottom.to_html(false),edge.to_html(false),"0.10" if depressed else "0.35"]
		var style:=StyleBoxTexture.new()
		style.texture=DPITexture.create_from_string(svg)
		for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:
			style.set_texture_margin(side,8)
		style.set_content_margin_all(padding)
		_bevels[key]=style
	# Share the SVG texture, while each widget owns its padding and patch margins.
	return _bevels[key].duplicate() as StyleBoxTexture

static func apply_theme(theme: Theme) -> void:
	theme.default_font=font(400)
	theme.default_font_size = 18
	theme.set_color("font_color","Label",INK)
	theme.set_color("font_color","Button",INK)
	theme.set_color("font_hover_color","Button",INK)
	theme.set_color("font_pressed_color","Button",Color.WHITE)
	theme.set_color("font_hover_pressed_color","Button",Color.WHITE)
	theme.set_color("font_disabled_color","Button",MUTED)
	theme.set_color("font_focus_color","Button",INK)
	theme.set_color("icon_normal_color","Button",INK)
	theme.set_color("icon_hover_color","Button",INK)
	theme.set_color("icon_pressed_color","Button",Color.WHITE)
	theme.set_color("icon_hover_pressed_color","Button",Color.WHITE)
	theme.set_color("icon_disabled_color","Button",Color("9aaba2"))
	theme.set_font("font","Button",font(600))
	theme.set_font_size("font_size","Button",18)
	theme.set_stylebox("panel","PanelContainer",panel())
	theme.set_constant("separation","VBoxContainer",8)
	theme.set_constant("separation","HBoxContainer",6)
	for key in ["normal","hover","pressed","disabled"]:
		var color: Color = {"normal":SOFT,"hover":Color("e2efea"),"pressed":TEAL,"disabled":Color("d9e2dc")}[key]
		var s := bevel(color,10,key=="pressed")
		theme.set_stylebox(key,"Button",s)
	var focus := panel(0,Color(0,0,0,0),10)
	focus.border_color = TEAL
	focus.set_corner_radius_all(5)
	focus.set_border_width_all(2)
	focus.expand_margin_left=-2
	focus.expand_margin_right=-2
	focus.expand_margin_top=-2
	focus.expand_margin_bottom=-2
	focus.shadow_size = 0
	theme.set_stylebox("focus","Button",focus)
	var separator:=StyleBoxLine.new()
	separator.color=LINE
	separator.thickness=1
	theme.set_stylebox("separator","HSeparator",separator)
	theme.set_constant("separation","HSeparator",1)
	var track_background:=StyleBoxEmpty.new()
	track_background.content_margin_left=4
	track_background.content_margin_right=4
	theme.set_stylebox("scroll_focus","VScrollBar",track_background)
	theme.set_stylebox("grabber","VScrollBar",bevel(SOFT,0))
	theme.set_stylebox("grabber_highlight","VScrollBar",bevel(PAPER,0))
	theme.set_stylebox("grabber_pressed","VScrollBar",bevel(TEAL,0,true))
	theme.set_stylebox("scroll","VScrollBar",track_background)
	theme.set_icon("increment","VScrollBar",ImageTexture.new())
	theme.set_icon("decrement","VScrollBar",ImageTexture.new())
	var tooltip:=panel(10,DEEP,10)
	tooltip.border_color=Color("416970")
	theme.set_stylebox("panel","TooltipPanel",tooltip)
	theme.set_color("font_color","TooltipLabel",PAPER)
	theme.set_font_size("font_size","TooltipLabel",15)

static func text(copy: String, size: int=18, color: Color=INK, weight: int=400) -> Label:
	var label := Label.new()
	label.text = copy
	label.add_theme_font_size_override("font_size",size)
	label.add_theme_color_override("font_color",color)
	label.add_theme_font_override("font",font(weight))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

static func thumbnail(kind: String) -> Texture2D:
	return SceneArtLibrary.thumbnail(kind)

static func portrait(role: String, index: int,appearance_seed: int=0) -> Texture2D:
	return SceneArtLibrary.portrait(role,index,appearance_seed)

static func picture(texture: Texture2D, size: Vector2, radius: float=-1.0) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = texture
	rect.custom_minimum_size = size
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var resolved:=radius
	if resolved<0: resolved=19.0 if size==Vector2(94,94) else 13.0 if size==Vector2(66,66) else 10.0
	if resolved>0:
		var clipping:=ShaderMaterial.new()
		clipping.shader=preload("res://ui/rounded_picture.gdshader")
		clipping.set_shader_parameter("radius",resolved)
		clipping.set_shader_parameter("rect_size",size.max(Vector2.ONE))
		rect.material=clipping
		rect.resized.connect(func() -> void: clipping.set_shader_parameter("rect_size",rect.size.max(Vector2.ONE)))
	return rect

static func icon_picture(key: String, pixels: int) -> TextureRect:
	var rect:=picture(icon(key,pixels),Vector2(pixels,pixels),0)
	# Parent cards may follow taller text; keep the whole SVG square and centered.
	rect.size_flags_horizontal=Control.SIZE_SHRINK_CENTER
	rect.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	return rect

static func primary(button: Button) -> void:
	button.add_theme_stylebox_override("normal",bevel(TEAL,10))
	button.add_theme_stylebox_override("hover",bevel(Color("2b7278"),10))
	button.add_theme_stylebox_override("pressed",bevel(DEEP,10,true))
	button.add_theme_stylebox_override("disabled",bevel(Color("d9e2dc"),10,true))
	var focus:=panel(0,Color(0,0,0,0),10)
	focus.border_color=IVORY
	focus.set_corner_radius_all(4)
	focus.set_border_width_all(1)
	for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:focus.set_expand_margin(side,-3)
	button.add_theme_stylebox_override("focus",focus)
	button.add_theme_color_override("font_color",Color.WHITE)
	button.add_theme_color_override("font_hover_color",Color.WHITE)
	button.add_theme_color_override("font_focus_color",Color.WHITE)
	button.add_theme_color_override("font_pressed_color",Color.WHITE)
	button.add_theme_color_override("font_hover_pressed_color",Color.WHITE)
	button.add_theme_color_override("font_disabled_color",MUTED)
	button.add_theme_color_override("icon_normal_color",Color.WHITE)
	button.add_theme_color_override("icon_hover_color",Color.WHITE)
	button.add_theme_color_override("icon_hover_pressed_color",Color.WHITE)

static func circle(button: Button) -> void:
	# The old caller name remains compatible; console controls are rectangular.
	button.add_theme_stylebox_override("normal",bevel(SOFT,8))
	button.add_theme_stylebox_override("hover",bevel(PAPER,8))
	button.add_theme_stylebox_override("pressed",bevel(TEAL,8,true))

static func summary(parent: Node, title: String, copy: String, amber: bool=false, heading_size: int=17, copy_size: int=15) -> PanelContainer:
	var card:=PanelContainer.new()
	var style:=panel(1,Color("e5d8b2") if amber else IVORY,10)
	card.add_theme_stylebox_override("panel",style)
	parent.add_child(card)
	var body:=VBoxContainer.new()
	body.add_theme_constant_override("separation",5)
	card.add_child(body)
	var heading:=text(title,heading_size,INK,700)
	heading.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	body.add_child(heading)
	var detail:=text(copy,copy_size,MUTED,400)
	detail.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	body.add_child(detail)
	return card

static func tag(copy: String, amber: bool=false) -> Label:
	var label:=text(copy,14,Color("8b5a22") if amber else TEAL,600)
	label.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
	var style:=panel(1,Color("e5d8b2") if amber else IVORY,4)
	style.content_margin_left=8
	style.content_margin_right=8
	style.set_border_width_all(0)
	label.add_theme_stylebox_override("normal",style)
	return label

