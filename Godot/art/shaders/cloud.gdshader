// Painted cloud puffs: bright tops fading to lavender undersides, independent of the sun,
// with a soft glowing rim. Matches the hand-painted reference better than lit shading.
shader_type spatial;
render_mode unshaded;

uniform vec4 top_color : source_color = vec4(1.0, 0.90, 0.90, 1.0);
uniform vec4 bottom_color : source_color = vec4(0.68, 0.50, 0.74, 1.0);
uniform vec4 rim_color : source_color = vec4(1.0, 0.78, 0.74, 1.0);

varying vec3 world_normal;

void vertex() {
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float up = smoothstep(-0.35, 0.75, world_normal.y);
	vec3 color = mix(bottom_color.rgb, top_color.rgb, floor(up * 4.0) / 3.0);
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = mix(color, rim_color.rgb, rim * 0.45);
}
