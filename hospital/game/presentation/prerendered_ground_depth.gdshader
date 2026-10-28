shader_type spatial;
render_mode unshaded, cull_disabled, depth_prepass_alpha;

uniform sampler2D character_atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform float center_height = 1.0;
uniform float vertical_compensation = 1.2247448714;
varying float ground_height;

void vertex() {
	// Match Sprite3D's fixed-Y billboard, including its authored world scale.
	mat4 upright = mat4(
		vec4(normalize(cross(vec3(0.0, 1.0, 0.0), MAIN_CAM_INV_VIEW_MATRIX[2].xyz)), 0.0),
		vec4(0.0, 1.0, 0.0, 0.0),
		vec4(normalize(cross(MAIN_CAM_INV_VIEW_MATRIX[0].xyz, vec3(0.0, 1.0, 0.0))), 0.0),
		MODEL_MATRIX[3]);
	upright *= mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * upright;
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	ground_height = MODEL_MATRIX[3].y - center_height * length(MODEL_MATRIX[1].xyz) / vertical_compensation;
}

void fragment() {
	vec4 pixel = texture(character_atlas, UV) * COLOR;
	ALBEDO = pixel.rgb;
	ALPHA = pixel.a;
	vec3 world_point = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 to_camera = PROJECTION_MATRIX[3][3] != 0.0
		? INV_VIEW_MATRIX[2].xyz : normalize(CAMERA_POSITION_WORLD - world_point);
	// Only recover pixels behind their own ground plane. Moving depth along
	// this view ray leaves screen position, atlas UV and baked colors intact.
	float recovery = max(ground_height + 0.001 - world_point.y, 0.0);
	DEPTH = FRAGCOORD.z;
	if (recovery > 0.0 && to_camera.y > 0.001) {
		vec3 contact = world_point + to_camera * (recovery / to_camera.y);
		vec4 projected = PROJECTION_MATRIX * VIEW_MATRIX * vec4(contact, 1.0);
		float ndc_depth = projected.z / projected.w;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
		DEPTH = ndc_depth * 0.5 + 0.5;
#else
		DEPTH = ndc_depth;
#endif
	}
}
