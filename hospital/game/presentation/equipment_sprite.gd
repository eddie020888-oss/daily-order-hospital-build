class_name EquipmentSprite
extends Node3D
## Independent fixed-view 2.5D equipment art; NOT a fullscreen background,
## animated treatment phase, reconstructed 3D apparatus, or seated-patient rig.
## RoomView still owns the canonical EquipmentAssembly origin and quarter yaw.
## Pass an already-created/painted raw GLB fallback; catalog-only additions may
## pass an explicitly marked empty source node because no GLB exists. Never call the equipment
## factory again from inside a replacement equipment() factory (recursion).
##
## Minimal factory insertion, AFTER original raw GLB creation/palette handling:
##   return EquipmentSprite.create(kind, raw_glb, {"enabled": true})
## With no explicit enabled=true, create() returns the original GLB unchanged.
## New version-2 layouts use GridEquipmentFrames for all six facility kinds and
## all four independently authored views. Legacy echo retains its q0 pilot.
## Missing/unsupported frames keep the genuine GLB rather than rotating a PNG.

const EXPECTED_CAMERA_OFFSET := Vector3(18.0,18.0,18.0)
const FRAME_PATHS := [
	"res://assets/equipment/ref-sprites-v1/echo-q0.png",
	"res://assets/equipment/ref-sprites-v1/echo-q1.png",
	"res://assets/equipment/ref-sprites-v1/echo-q2.png",
	"res://assets/equipment/ref-sprites-v1/echo-q3.png",
]
# Actual supplied q0 PNG: 1254 square, alpha>=128 bbox (74,80)-(1204,1155).
# .00195 m/pixel gives visible width 1130*.00195 = 2.2035 m, no stretching.
# This base-centre pixel is an INITIAL VISUAL calibration, not recovered 3D.
const Q0_PIXEL_SIZE := 0.00195
const Q0_FOOT_PIXEL := Vector2(640.0,1024.0)
const ROOM_WALL_CLEARANCE := .13

static var _textures:Dictionary={}
static var _catalog_texture_lru:Array[String]=[]
const CATALOG_TEXTURE_CACHE_LIMIT := 24
var sprite:MeshInstance3D
var pick_area:Area3D
var selected_quadrant := -1
var using_sprite := false
var _fallback:Node3D
var _options:Dictionary={}
var _kind := "echo"
var _started := false
var _last_basis := Basis.IDENTITY
var _last_position := Vector3.INF
var _active_path := ""


static func create(kind:String,raw_glb:Node3D,options:Dictionary={}) -> Node3D:
	if raw_glb==null:
		push_error("EquipmentSprite.create requires a fallback/source node")
		return null
	var supported:bool=kind=="echo" or options.get("footprint_version",1)==2 and (not EquipmentFootprints.profile(kind).is_empty() or GridEquipmentFrames.has_catalog(kind))
	if not supported or options.get("enabled",false)!=true:
		return raw_glb
	if raw_glb.get_parent()!=null:
		push_error("EquipmentSprite.create expects an unparented GLB instance")
		return raw_glb
	var result:=EquipmentSprite.new()
	result.name="EquipmentSpritePilot"
	result._kind=kind
	result._options=options.duplicate(true)
	result._fallback=raw_glb
	result.add_child(raw_glb)
	result._build()
	return result


func _init() -> void:
	set_notify_transform(true)
	set_meta("presentation","fixed-view-equipment-sprite-pilot")
	set_meta("no_simulation_or_seated_actor_change",true)


func _ready() -> void:
	# The caller has now attached us beneath the already-yawed assembly.
	_started=true
	refresh()


func _notification(what:int) -> void:
	if what==NOTIFICATION_TRANSFORM_CHANGED and _started and is_inside_tree():
		_sync(false)


static func quadrant_from_yaw(yaw:float) -> int:
	# RoomView uses global assembly yaw = -equipment.rotation*PI/2.
	return posmod(roundi(-yaw/(PI*.5)),4)


static func _number(value:Variant) -> bool:
	return (typeof(value)==TYPE_INT or typeof(value)==TYPE_FLOAT) and is_finite(float(value))


static func _texture(path:String) -> Texture2D:
	if _textures.has(path):
		_touch_catalog_texture(path)
		return _textures[path]
	if not path.ends_with(".png") or not ResourceLoader.exists(path):
		return null
	var texture:Texture2D=load(path) as Texture2D
	if texture==null or texture.get_width()<2 or texture.get_height()<2:
		return null
	var image:Image=texture.get_image()
	if image==null:
		return null
	if image.is_compressed() and image.decompress()!=OK:
		return null
	if image.detect_alpha()==Image.ALPHA_NONE:
		return null
	_textures[path]=texture
	_touch_catalog_texture(path)
	return texture

static func _touch_catalog_texture(path:String) -> void:
	if not path.begins_with("res://assets/equipment/catalog-isometric-v1/"):return
	_catalog_texture_lru.erase(path)
	_catalog_texture_lru.append(path)
	while _catalog_texture_lru.size()>CATALOG_TEXTURE_CACHE_LIMIT:
		# Live shader materials retain their own selected texture. Eviction only
		# releases unused library references, never the currently drawn resource.
		_textures.erase(_catalog_texture_lru.pop_front())


func _build() -> void:
	set_meta("equipment_kind",_kind)
	set_meta("canonical_origin_is_unchanged",true)
	set_meta("foot_calibration","q0 visual initial; not a 3D contact measurement")
	sprite=MeshInstance3D.new()
	sprite.name="IndependentEquipmentCutout"
	sprite.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sprite.visible=false
	add_child(sprite)
	# Normal room selection already uses the canonical ground grid. Do not add
	# an unused physics picker unless an explicit host needs that integration.
	if not _options.get("create_pick_area",false):return
	# An Area is a pick-only logical base, never a body/navigation obstacle and
	# never the large square transparent canvas. Existing cell picking remains.
	var footprint:Vector2=_options.get("footprint_size",Vector2(2.0,1.0))
	var height_value:Variant=_options.get("pick_height",1.85)
	if footprint.x<=0 or footprint.y<=0 or not _number(height_value) or float(height_value)<=0:
		return
	pick_area=Area3D.new()
	pick_area.name="EquipmentFootprintPickOnly"
	pick_area.collision_layer=int(_options.get("pick_layer",1))
	pick_area.collision_mask=0
	pick_area.monitoring=false
	pick_area.monitorable=false
	pick_area.input_ray_pickable=true
	pick_area.position=_foot_origin()+Vector3(0,float(height_value)*.5,0)
	pick_area.set_meta("equipment_kind",_kind)
	pick_area.set_meta("pick_only_not_navigation_obstacle",true)
	pick_area.set_meta("logical_footprint_size",footprint)
	var shape:=BoxShape3D.new()
	shape.size=Vector3(footprint.x,float(height_value),footprint.y)
	var collision:=CollisionShape3D.new()
	collision.shape=shape
	pick_area.add_child(collision)
	add_child(pick_area)


func _foot_origin() -> Vector3:
	var value:Variant=_options.get("footprint_origin",Vector3.ZERO)
	return value if value is Vector3 else Vector3.ZERO


func _frame(q:int) -> Dictionary:
	if _options.get("footprint_version",1)==2:
		return GridEquipmentFrames.frame(_kind,q)
	var frame:Dictionary={"path":FRAME_PATHS[q],"enabled":q==0}
	if q==0:
		frame["pixel_size"]=Q0_PIXEL_SIZE
		frame["foot_px"]=Q0_FOOT_PIXEL
	var overrides:Variant=_options.get("frame_overrides",{})
	if overrides is Dictionary:
		var value:Variant=overrides.get(q,overrides.get(str(q),{}))
		if value is Dictionary:
			frame.merge(value,true)
	return frame


## Call after importing a PNG or changing a frame override at runtime.
## No per-frame IO, camera-position following, or camera-size compensation.
func refresh() -> void:
	if is_inside_tree() and _started:
		_sync(true)


func _sync(force:bool) -> void:
	var basis:Basis=global_basis
	var at:=global_position
	if not force and selected_quadrant>=0 and basis.is_equal_approx(_last_basis) and at.is_equal_approx(_last_position):
		return
	_last_basis=basis
	_last_position=at
	# Pixel units are exact world units. Unsupported parent scale/tilt uses GLB
	# rather than stretching the image or inventing a different source angle.
	if absf(basis.x.length()-1.0)>.001 or absf(basis.y.length()-1.0)>.001 or absf(basis.z.length()-1.0)>.001 or not basis.y.is_equal_approx(Vector3.UP):
		_show_fallback("non-unit or tilted parent transform")
		return
	var yaw:float=atan2(basis.z.x,basis.z.z)
	selected_quadrant=quadrant_from_yaw(yaw)
	var frame:Dictionary=_frame(selected_quadrant)
	if frame.get("enabled",false)!=true or not frame.get("path",null) is String:
		_show_fallback("selected direction not explicitly enabled/calibrated")
		return
	var pixel_value:Variant=frame.get("pixel_size",_options.get("pixel_size",null))
	if not _number(pixel_value) or float(pixel_value)<=0.000001 or float(pixel_value)>.1:
		_show_fallback("missing/invalid metres-per-pixel calibration")
		return
	var texture:Texture2D=_texture(frame.path)
	if texture==null:
		_show_fallback("selected PNG absent or not a real transparent image")
		return
	var size:Vector2=texture.get_size()
	var foot:Variant=frame.get("foot_px",null)
	if foot==null:
		var normalized:Variant=frame.get("foot_uv",_options.get("foot_uv",null))
		if normalized is Vector2:
			foot=normalized*size
	if not foot is Vector2 or not is_finite(foot.x) or not is_finite(foot.y) or foot.x<0 or foot.x>size.x or foot.y<0 or foot.y>size.y:
		_show_fallback("missing/invalid image foot pixel")
		return
	var pixel_size:float=float(pixel_value)
	if _options.get("footprint_version",1)==2 and not _grid_camera_supported():
		_show_fallback("grid-calibrated image requires its exact orthographic camera direction")
		return
	if not _fits_actual_room(foot,pixel_size):
		_show_fallback("original cutout needs space behind/alongside the apparatus; preserve room walls")
		return
	_build_projected_mesh(texture,size,foot,pixel_size)
	sprite.position=Vector3.ZERO
	sprite.scale=Vector3.ONE
	sprite.visible=true
	_fallback.visible=false
	using_sprite=true
	_active_path=frame.path
	set_meta("selected_quadrant",selected_quadrant)
	set_meta("selected_asset",_active_path)
	set_meta("source_pixel_size",size)
	set_meta("foot_pixel",foot)
	set_meta("metres_per_pixel",pixel_size)
	set_meta("using_sprite",true)
	set_meta("fallback_reason","")
	if _options.get("footprint_version",1)==2:
		set_meta("foot_calibration","four physical ground corners calibrated to the actual body rectangle")


func _fits_actual_room(foot:Vector2,pixel_size:float) -> bool:
	var owner:Node=get_parent()
	while owner!=null and not owner.has_meta("visual_room_cells"):owner=owner.get_parent()
	if owner==null:return true
	var cells:Array=owner.get_meta("visual_room_cells")
	var low:=Vector2(INF,INF);var high:=Vector2(-INF,-INF)
	for cell in cells:
		var at:=Vector2(int(cell)%24,int(cell)/24)
		low=low.min(at-Vector2.ONE*.5);high=high.max(at+Vector2.ONE*.5)
	if _options.get("footprint_version",1)==2:
		for corner:Vector2 in _frame(selected_quadrant).get("ground_corners_px",[]):
			var point:Vector3=to_global(_source_point(corner,foot,pixel_size))
			if point.x<low.x-.001 or point.x>high.x+.001 or point.z<low.y-.001 or point.z>high.y+.001:return false
		return true
	# Conservative opaque source bounds measured at the same .5 alpha cutoff.
	# Geometry outside this rectangle is transparent; no opaque image may cross
	# a real room boundary merely to make the prototype appear to fit.
	for limits in [Vector2(80,foot.y),Vector2(foot.y,1155)]:
		for x in [74.0,1204.0]:
			for y in [limits.x,limits.y]:
				var point:Vector3=to_global(_source_point(Vector2(x,y),foot,pixel_size))
				if point.x<low.x+.08 or point.x>high.x-.08 or point.z<low.y+.08 or point.z>high.y-.08:return false
	return true


func _source_point(pixel:Vector2,foot:Vector2,pixel_size:float) -> Vector3:
	if _options.get("footprint_version",1)==2:
		var frame:=_frame(maxi(0,selected_quadrant))
		return _foot_origin()+global_basis.inverse()*GridEquipmentProjection.point(pixel,frame.ground_corners_px,frame.body_size)
	var outward:Vector3=EXPECTED_CAMERA_OFFSET.normalized()
	var right:Vector3=Vector3.UP.cross(outward).normalized()
	var camera_up:Vector3=outward.cross(right).normalized()
	var ground_out:=Vector3(outward.x,0,outward.z).normalized()
	var world_foot:=to_global(_foot_origin())+Vector3(0,.030,0)
	var point:=world_foot+right*(pixel.x-foot.x)*pixel_size
	var screen_up:float=(foot.y-pixel.y)*pixel_size
	if screen_up>=0:
		point+=Vector3.UP*screen_up/camera_up.y
	else:
		point+=ground_out*(-screen_up)/(-camera_up.dot(ground_out))
	return to_local(point)


func _build_projected_mesh(texture:Texture2D,size:Vector2,foot:Vector2,pixel_size:float) -> void:
	# A depth proxy for fixed-view art: the upper section is vertical, while
	# the photographed foreground footprint lies on the room floor. Both parts
	# retain the exact source projection. This avoids the diagonal rear-wall
	# intersection caused by a single camera-facing billboard, with depth test
	# still enabled. It does not recover the apparatus' hidden 3D surfaces.
	if _options.get("footprint_version",1)==2:
		var frame:=_frame(selected_quadrant)
		sprite.mesh=GridEquipmentProjection.mesh(size,frame.ground_corners_px,frame.body_size,global_basis.inverse(),_room_proxy_interior())
	else:
		var builder:=SurfaceTool.new()
		builder.begin(Mesh.PRIMITIVE_TRIANGLES)
		for limits in [Vector2(0,foot.y),Vector2(foot.y,size.y)]:
			var corners:Array[Vector2]=[Vector2(0,limits.x),Vector2(size.x,limits.x),Vector2(size.x,limits.y),Vector2(0,limits.y)]
			for index in [0,1,2,0,2,3]:
				builder.set_uv(corners[index]/size)
				builder.set_normal(EXPECTED_CAMERA_OFFSET.normalized())
				builder.add_vertex(_source_point(corners[index],foot,pixel_size))
		sprite.mesh=builder.commit()
	var shader:=Shader.new()
	shader.code="""shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
uniform sampler2D equipment_texture : source_color, filter_linear_mipmap, repeat_disable;
void fragment(){
  vec4 colour=texture(equipment_texture,UV);
  if(colour.a<0.5){discard;}
  ALBEDO=colour.rgb;
}
"""
	if _kind=="diagnosis":
		shader.code="""shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
uniform sampler2D equipment_texture : source_color, filter_linear_mipmap, repeat_disable;
// Preserve the accepted soft-gold finish; clarity=0 is the production baseline.
uniform float diagnosis_finish_strength : hint_range(0.0,1.0) = 0.70;
uniform float diagnosis_gold_desaturation : hint_range(0.0,0.8) = 0.45;
uniform float diagnosis_gold_highlight_compression : hint_range(0.0,0.4) = 0.18;
uniform float diagnosis_clarity_strength : hint_range(0.0,1.0) = 0.72;

vec3 finish_to_display(vec3 c) {
    if (OUTPUT_IS_SRGB) { return c; }
    return mix(c*12.92, 1.055*pow(max(c,vec3(0.0)),vec3(1.0/2.4))-0.055, step(vec3(0.0031308),c));
}
vec3 finish_to_render(vec3 c) {
    if (OUTPUT_IS_SRGB) { return c; }
    return mix(c/12.92, pow((c+0.055)/1.055,vec3(2.4)), step(vec3(0.04045),c));
}
float diagnosis_gold_mask(vec3 c) {
    float peak=max(c.r,max(c.g,c.b));
    float low=min(c.r,min(c.g,c.b));
    float saturation=(peak-low)/max(peak,0.0001);
    float red=max(c.r,0.0001);
    float green_share=c.g/red;
    float blue_share=c.b/red;
    float yellow_hue=smoothstep(0.67,0.80,green_share)
        *(1.0-smoothstep(0.98,1.05,green_share));
    float blue_protection=1.0-smoothstep(0.40,0.58,blue_share);
    return yellow_hue*blue_protection*smoothstep(0.25,0.46,saturation)
        *smoothstep(0.12,0.30,c.r);
}
vec3 clarity_ramp(float value,vec3 shadow,vec3 middle,vec3 light) {
    // A wide middle plateau reduces fine variation without UV/neighbor blur.
    vec3 result=mix(shadow,middle,smoothstep(0.08,0.36,value));
    return mix(result,light,smoothstep(0.70,0.99,value));
}
vec3 diagnosis_clarity(vec3 original,vec3 finished) {
    float peak=max(original.r,max(original.g,original.b));
    float low=min(original.r,min(original.g,original.b));
    float saturation=(peak-low)/max(peak,0.0001);
    float red=max(original.r,0.0001);
    float green=max(original.g,0.0001);
    float green_share=original.g/red;
    float blue_share=original.b/red;
    // Protect blue/cyan instrumentation; keep dark structural edges.
    float blue_guard=1.0-smoothstep(1.04,1.16,original.b/green);
    float body_guard=smoothstep(0.10,0.25,peak)*blue_guard;
    float warm=smoothstep(0.03,0.14,original.r-original.g)
        *(1.0-smoothstep(0.60,0.80,blue_share))*body_guard;
    float teal=smoothstep(1.05,1.30,green_share)
        *smoothstep(1.03,1.22,blue_share)*body_guard;
    float cream=smoothstep(0.62,0.82,blue_share)
        *(1.0-smoothstep(0.17,0.35,saturation))
        *smoothstep(0.50,0.76,peak)*blue_guard;
    float total=warm+teal+cream;
    if (total<0.0001) { return finished; }
    float luminance=dot(finished,vec3(0.2126,0.7152,0.0722));
    // Gold versus timber is an approximate chroma split, not recovered PBR IDs.
    float gold_like=smoothstep(0.56,0.80,green_share);
    vec3 wood=clarity_ramp(luminance,vec3(0.25,0.17,0.11),
        vec3(0.58,0.42,0.27),vec3(0.78,0.65,0.45));
    vec3 gold=clarity_ramp(luminance,vec3(0.30,0.26,0.18),
        vec3(0.68,0.59,0.41),vec3(0.87,0.80,0.62));
    vec3 cool=clarity_ramp(luminance,vec3(0.055,0.18,0.19),
        vec3(0.16,0.36,0.37),vec3(0.35,0.56,0.56));
    vec3 ivory=clarity_ramp(luminance,vec3(0.62,0.57,0.48),
        vec3(0.84,0.80,0.70),vec3(0.95,0.93,0.87));
    // Cream is deliberately gentler; silhouettes and alpha never enter this path.
    float cream_weight=cream*0.45;
    vec3 palette=(warm*mix(wood,gold,gold_like)+teal*cool+cream_weight*ivory)
        /max(warm+teal+cream_weight,0.0001);
    float amount=clamp(diagnosis_clarity_strength,0.0,1.0)
        *clamp(warm+teal+cream_weight,0.0,1.0);
    return mix(finished,palette,amount);
}
void fragment() {
    vec4 colour=texture(equipment_texture,UV);
    if (colour.a<0.5) { discard; }
    vec3 result=colour.rgb;
    if (diagnosis_finish_strength>0.0) {
        vec3 display=finish_to_display(colour.rgb);
        float amount=clamp(diagnosis_finish_strength,0.0,1.0)*diagnosis_gold_mask(display);
        if (amount>0.0) {
            float luminance=dot(display,vec3(0.2126,0.7152,0.0722));
            vec3 muted=mix(display,vec3(luminance),diagnosis_gold_desaturation);
            float peak=max(display.r,max(display.g,display.b));
            muted*=1.0-diagnosis_gold_highlight_compression*smoothstep(0.70,0.98,peak);
            result=finish_to_render(mix(display,muted,amount));
        }
    }
    if (diagnosis_clarity_strength>0.0) {
        vec3 original=finish_to_display(colour.rgb);
        vec3 finished=finish_to_display(result);
        result=finish_to_render(diagnosis_clarity(original,finished));
    }
    ALBEDO=result;
}"""
	var material:=ShaderMaterial.new();material.shader=shader
	material.set_shader_parameter("equipment_texture",texture)
	if _kind=="diagnosis":
		material.set_shader_parameter("diagnosis_finish_strength",clampf(float(_options.get("diagnosis_finish_strength",0.70)),0.0,1.0))
		material.set_shader_parameter("diagnosis_clarity_strength",clampf(float(_options.get("diagnosis_clarity_strength",0.72)),0.0,1.0))
	sprite.material_override=material
	set_meta("depth_proxy","vertical upper and floor foreground; fixed-view projection preserved")
	if _options.get("footprint_version",1)==2:set_meta("depth_proxy","wall-aware ray depth with pinned grid ground corners; not reconstructed 3D")

func _room_proxy_interior() -> Rect2:
	var owner:Node=get_parent()
	while owner!=null and not owner.has_meta("visual_room_cells"):owner=owner.get_parent()
	if owner==null:return Rect2()
	var cells:Array=owner.get_meta("visual_room_cells")
	if cells.is_empty():return Rect2()
	var low:=Vector2(INF,INF);var high:=Vector2(-INF,-INF)
	for cell in cells:
		var at:=Vector2(int(cell)%24,int(cell)/24)
		low=low.min(at-Vector2.ONE*.5);high=high.max(at+Vector2.ONE*.5)
	var foot:=to_global(_foot_origin())
	var origin:=Vector2(foot.x,foot.z)
	low+=Vector2.ONE*ROOM_WALL_CLEARANCE-origin
	high-=Vector2.ONE*ROOM_WALL_CLEARANCE+origin
	return Rect2(low,high-low)

func _grid_camera_supported() -> bool:
	var viewport:=get_viewport()
	if viewport==null:return false
	var camera:=viewport.get_camera_3d()
	if camera==null or camera.projection!=Camera3D.PROJECTION_ORTHOGONAL:return false
	return camera.global_basis.z.is_equal_approx(EXPECTED_CAMERA_OFFSET.normalized())


func _show_fallback(reason:String) -> void:
	sprite.visible=false
	sprite.mesh=null
	_fallback.visible=true
	using_sprite=false
	_active_path=""
	set_meta("selected_quadrant",selected_quadrant)
	set_meta("selected_asset","")
	set_meta("using_sprite",false)
	set_meta("fallback_reason",reason)


func frame_state() -> Dictionary:
	var state:={"quadrant":selected_quadrant,"using_sprite":using_sprite,
		"asset_path":_active_path,"fallback_reason":get_meta("fallback_reason","")}
	if _options.get("footprint_version",1)==2:
		state.alignment_version=2
		var frame:=_frame(maxi(0,selected_quadrant))
		state.source_ground_corners=frame.get("ground_corners_px",[]).duplicate()
		state.ground_corners=[]
		for pixel:Vector2 in state.source_ground_corners:state.ground_corners.append(to_global(_source_point(pixel,frame.foot_px,frame.pixel_size)))
	return state
