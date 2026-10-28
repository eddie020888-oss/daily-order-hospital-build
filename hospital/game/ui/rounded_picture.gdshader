shader_type canvas_item;
uniform float radius = 13.0;
uniform vec2 rect_size = vec2(66.0);
varying vec2 local_position;
void vertex() {
	local_position = VERTEX;
}
void fragment() {
	vec2 half_size = rect_size * 0.5;
	float r = min(radius, min(half_size.x, half_size.y));
	vec2 q = abs(local_position - half_size) - half_size + vec2(r);
	float distance = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;
	COLOR.a *= 1.0 - smoothstep(-0.5, 0.5, distance);
}
