shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

// A single opaque, fixed-world 2.5D surface. Reference coordinates are fixed;
// the extended painting has no navigation, picking or simulated land.
uniform sampler2D hall_texture : source_color, filter_linear, repeat_disable;
uniform vec2 art_uv_scale = vec2(1.0);
uniform vec4 overscan_color : source_color;
uniform vec4 garden_grass : source_color;
uniform vec4 garden_leaf : source_color;
uniform vec4 garden_stone : source_color;
uniform vec4 garden_flower : source_color;
uniform sampler2D campus_texture : source_color, filter_linear, repeat_disable;
uniform bool has_campus_art = false;
uniform vec2 campus_center = vec2(0.51, 0.49);
uniform float campus_scale = 3.9;
varying vec3 backdrop_world;

float garden_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float round_bed(vec2 p, vec2 half_size, float radius) {
	vec2 q = abs(p) - half_size;
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
}

vec3 courtyard(vec2 p) {
	// World metres and the same tile axes as the hospital; never SCREEN_UV.
	vec2 tile = p * 1.25;
	vec2 within = fract(tile);
	float seam_edge = min(min(within.x, 1.0-within.x), min(within.y, 1.0-within.y));
	float aa = max(fwidth(seam_edge), 0.002);
	float seam = 1.0-smoothstep(0.014-aa, 0.014+aa, seam_edge);
	float variation = garden_hash(floor(tile));
	vec3 paving = overscan_color.rgb * (0.77+0.095*variation);
	paving *= 1.0-0.065*seam;
	vec3 grass = garden_grass.rgb * (0.90+0.10*garden_hash(floor(p*3.0)));
	// A calm paved apron surrounds the real hospital. Garden walks continue
	// outward in both world axes, including every permitted corner pan/fit.
	vec2 distance_to_hospital = abs(p-vec2(11.5, 8.5))-vec2(13.0, 10.0);
	float outside = max(distance_to_hospital.x, distance_to_hospital.y);
	float apron = 1.0-smoothstep(2.5, 3.2, outside);
	vec2 path_distance = abs(mod(p-vec2(1.5, 0.5), vec2(10.0))-vec2(5.0));
	float walk = 1.0-smoothstep(1.05, 1.17, min(path_distance.x, path_distance.y));
	vec3 finish = mix(grass, paving, max(apron, walk));
	// Static low planting islands: warm stone edging, soil, rounded foliage
	// and a few pale blossoms. No tall props obscure independent live rooms.
	vec2 garden_cell = floor((p-vec2(1.5, 0.5))/10.0);
	float seed = garden_hash(garden_cell);
	vec2 local = mod(p-vec2(1.5, 0.5), vec2(10.0))-vec2(2.4, 2.4);
	local -= vec2(seed-0.5, garden_hash(garden_cell+17.0)-0.5)*0.7;
	float allowed = smoothstep(0.6, 1.4, outside) * step(0.16, seed);
	float bed = round_bed(local, vec2(1.02, 0.86), 0.20);
	float shadow = (1.0-smoothstep(0.0, 0.12, round_bed(local-vec2(0.18, 0.22), vec2(1.12, 0.98), 0.24)))*allowed;
	finish *= 1.0-shadow*0.13;
	float rim = (1.0-smoothstep(-0.02, 0.025, bed))*allowed;
	finish = mix(finish, garden_stone.rgb*(0.91+0.045*local.y), rim);
	float soil = (1.0-smoothstep(-0.24, -0.19, bed))*allowed;
	finish = mix(finish, garden_leaf.rgb*0.57, soil);
	float leaf_a = length((local-vec2(-0.46, 0.03))/vec2(0.71, 0.67));
	float leaf_b = length((local-vec2(0.45, 0.12))/vec2(0.66, 0.68));
	float leaf_c = length((local-vec2(0.0, -0.42))/vec2(0.65, 0.55));
	float foliage = (1.0-smoothstep(0.94, 1.03, min(leaf_a, min(leaf_b, leaf_c))))*soil;
	float soft_light = 1.01-0.12*local.x-0.07*local.y;
	finish = mix(finish, garden_leaf.rgb*soft_light, foliage);
	vec2 flower_grid = fract(local*2.7+seed)-vec2(0.5);
	float petal = (1.0-smoothstep(0.085, 0.14, length(flower_grid)))*foliage;
	petal *= step(0.67, garden_hash(floor(local*2.7+seed)+garden_cell));
	finish = mix(finish, garden_flower.rgb, petal);
	return finish;
}

void vertex() {
	backdrop_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 image_uv = (UV-vec2(0.5))*art_uv_scale+vec2(0.5);
	vec3 original = vec3(0.0);
	if (!has_campus_art) original = texture(hall_texture, clamp(image_uv, vec2(0.0), vec2(1.0))).rgb;
	vec2 outside_uv = max(-image_uv, image_uv-vec2(1.0));
	float image_inside = 1.0-smoothstep(0.0, 0.02, max(outside_uv.x, outside_uv.y));
	// The fixed (1,1,1) viewing ray intersects the same y=0 plane used by
	// CameraRig picking. Pan and zoom cannot make the paving swim or repeat.
	vec2 floor_world = backdrop_world.xz-vec2(backdrop_world.y);
	// The extended painting already contains the hospital and its courtyard.
	// Display it as one coherent world surface: overlaying the cropped old
	// photograph would reintroduce rectangular paving edges or doubled walls.
	// The untouched historical original remains the missing-asset fallback.
	float transition = has_campus_art ? 1.0 : 1.0-image_inside;
	if (transition <= 0.0) {
		ALBEDO = original;
	} else {
		vec2 campus_uv = (image_uv-vec2(0.5))/campus_scale+campus_center;
		float edge = min(min(campus_uv.x, 1.0-campus_uv.x), min(campus_uv.y, 1.0-campus_uv.y));
		float painted = has_campus_art ? smoothstep(0.0, 0.06, edge) : 0.0;
		vec3 surrounding;
		if (painted >= 0.999) {
			surrounding = texture(campus_texture, campus_uv).rgb;
		} else {
			surrounding = courtyard(floor_world);
			if (painted > 0.0) surrounding = mix(surrounding, texture(campus_texture, clamp(campus_uv, vec2(0.0), vec2(1.0))).rgb, painted);
		}
		ALBEDO = mix(original, surrounding, transition);
	}
}
