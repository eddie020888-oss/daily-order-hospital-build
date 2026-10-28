class_name RoomSurfaceMaterial
extends RefCounted
## World-registered wall finish and the existing floor appearance.
## The floor may reuse the approved 2.5D original's FLOOR appearance at its
## fixed world registration. This is not a new light bake or a 3D rebuild.
## All coordinates are world coordinates, so SceneArtLibrary.batch_static can
## bake node transforms into vertices without shifting the material mapping.

const SOURCE := "res://assets/environment/reference-hall-v1/09-empty-hospital.png"
static var _walls:Dictionary={}
static var _floor:ShaderMaterial
static var _wall_shader:Shader


static func wall_material(color:Color) -> ShaderMaterial:
	var key:String=color.to_html()
	if _walls.has(key):
		return _walls[key]
	if _wall_shader==null:
		_wall_shader=Shader.new()
		_wall_shader.code="""
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform vec4 base_color : source_color = vec4(0.94, 0.902, 0.843, 1.0);
varying vec3 surface_world;
varying vec3 surface_world_normal;
float grain_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1,311.7))) * 43758.5453);
}
float fine_grain(vec2 p) {
	vec2 i=floor(p);
	vec2 f=fract(p);
	f=f*f*(3.0-2.0*f);
	return mix(mix(grain_hash(i),grain_hash(i+vec2(1.0,0.0)),f.x),
		mix(grain_hash(i+vec2(0.0,1.0)),grain_hash(i+vec2(1.0)),f.x),f.y);
}
void vertex() {
	surface_world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
	surface_world_normal=normalize(mat3(MODEL_MATRIX)*NORMAL);
}
void fragment() {
	// Quiet plaster/stone grain, never masonry lines through cell-sized walls.
	// Existing indexed rounded cross-sections still supply all actual bevels.
	vec2 p=vec2(surface_world.x+surface_world.z,surface_world.y);
	float grain=fine_grain(p*37.0)*0.7+fine_grain(p*113.0)*0.3;
	float foot=smoothstep(0.028,0.20,surface_world.y);
	vec3 stone=base_color.rgb*(0.996+0.008*grain);
	// Fixed-view finish: use the actual rounded normals for a bounded soft
	// light gradient. This keeps approved cream/teal below clipping, independent
	// of the equipment's bright brass reflection sky. Geometry still casts
	// actual directional shadows onto the independently lit room floor.
	float soft_light=0.86+0.12*max(dot(normalize(surface_world_normal),normalize(vec3(-0.6,0.9,0.5))),0.0);
	vec3 finish=stone*soft_light*mix(0.94,1.0,foot);
	// A bounded lit share receives real room shadows without washing out
	// the established cream/teal palette under the equipment reflection sky.
	ALBEDO=finish*0.18;
	EMISSION=finish*0.82;
	ROUGHNESS=0.78;
	METALLIC=0.0;
	SPECULAR=0.12;
}
"""
	var material:=ShaderMaterial.new()
	material.shader=_wall_shader
	material.set_shader_parameter("base_color",color)
	material.set_meta("room_surface_finish","clinic_wall_v2_soft_normal_gradient")
	material.set_meta("receives_real_lighting_and_shadows",true)
	material.set_meta("real_lighting_fraction",0.18)
	_walls[key]=material
	return material


static func floor_material() -> ShaderMaterial:
	if _floor!=null:
		return _floor
	var shader:=Shader.new()
	shader.code="""
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform sampler2D original_hall : source_color, filter_linear, repeat_disable;
uniform bool has_original = false;
uniform vec3 reference_target = vec3(11.5,0.0,7.5);
uniform vec3 reference_right = vec3(0.7071067812,0.0,-0.7071067812);
uniform vec3 reference_up = vec3(-0.4082482905,0.8164965809,-0.4082482905);
uniform vec2 reference_size = vec2(39.1111111111,22.0);
uniform vec4 stone_color : source_color = vec4(0.941176,0.901961,0.843137,1.0);
uniform float lit_fraction : hint_range(0.0,0.5) = 0.22;
varying vec3 surface_world;
float tile_hash(vec2 p) {
	return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);
}
void vertex() {
	surface_world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
}
void fragment() {
	// Source fallback is only a close-value half-metre cream stone finish.
	// A narrow anti-aliased seam replaces the former coarse grey square look.
	vec2 q=surface_world.xz*2.0;
	vec2 f=fract(q);
	float edge=min(min(f.x,1.0-f.x),min(f.y,1.0-f.y));
	float aa=max(fwidth(edge),0.001);
	float seam=1.0-smoothstep(0.009-aa,0.009+aa,edge);
	vec3 fallback=stone_color.rgb*(0.985+0.025*tile_hash(floor(q)));
	fallback*=1.0-seam*0.045;
	vec3 appearance=fallback;
	if (has_original) {
		// Fixed default-camera projection, NOT SCREEN_UV/current camera UV.
		// y=0 matches the mathematical floor and the world-space original art.
		vec3 p=vec3(surface_world.x,0.0,surface_world.z)-reference_target;
		vec2 uv=vec2(0.5+dot(p,reference_right)/reference_size.x,
			0.5-dot(p,reference_up)/reference_size.y);
		vec3 original=texture(original_hall,clamp(uv,vec2(0.0),vec2(1.0))).rgb;
		float inside=step(0.0,uv.x)*step(uv.x,1.0)*step(0.0,uv.y)*step(uv.y,1.0);
		// Reject dark foliage/teal/wood where the original's exterior scenery
		// overlaps an edge of the mathematical grid. Never print that scenery
		// as a dark instrument/plant picture onto a new room's floor.
		float minimum=min(original.r,min(original.g,original.b));
		float chroma=max(original.r,max(original.g,original.b))-minimum;
		float cream_confidence=smoothstep(0.12,0.34,minimum)
			*(1.0-smoothstep(0.35,0.65,chroma))
			*(1.0-smoothstep(0.08,0.20,original.g-original.r));
		appearance=mix(fallback,original,inside*cream_confidence);
	}
	// Preserve the original's baked warm brightness, while keeping a modest
	// physically lit share for new wall/actor shadows. This is intentionally
	// not a claim that the reference's illustrated lighting was reconstructed.
	ALBEDO=appearance*lit_fraction;
	EMISSION=appearance*(1.0-lit_fraction);
	ROUGHNESS=0.88;
	METALLIC=0.0;
	SPECULAR=0.08;
}
"""
	_floor=ShaderMaterial.new()
	_floor.shader=shader
	if ResourceLoader.exists(SOURCE):
		var texture:Texture2D=load(SOURCE) as Texture2D
		if texture!=null:
			_floor.set_shader_parameter("original_hall",texture)
			_floor.set_shader_parameter("has_original",true)
	_floor.set_meta("room_surface_finish","fixed_world_original_09_floor_projection")
	_floor.set_meta("original_is_2_5d_art_not_a_3d_bake",true)
	_floor.set_meta("real_lighting_fraction",0.22)
	_floor.set_meta("source",SOURCE)
	return _floor
