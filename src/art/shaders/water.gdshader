// Flat stylized water with a foam line wherever the water meets terrain.
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform vec4 deep_color : source_color = vec4(0.20, 0.45, 0.62, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.45, 0.80, 0.82, 1.0);
uniform vec4 foam_color : source_color = vec4(0.96, 0.94, 0.88, 1.0);
uniform float foam_width = 0.18;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;

void vertex() {
	VERTEX.y += sin(TIME * 1.3 + VERTEX.x * 2.5 + VERTEX.z * 1.7) * 0.015;
}

void fragment() {
	float depth = textureLod(depth_texture, SCREEN_UV, 0.0).r;
	vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	float water_depth = -view.z / view.w - (-VERTEX.z);
	float shore = 1.0 - smoothstep(0.0, 0.6, water_depth);
	vec3 color = mix(deep_color.rgb, shallow_color.rgb, step(0.35, shore));
	float ripple = sin(TIME * 2.0 - water_depth * 18.0) * 0.5 + 0.5;
	float foam = step(water_depth, foam_width * (0.7 + 0.3 * ripple));
	ALBEDO = mix(color, foam_color.rgb, foam);
	ALPHA = 0.92;
}
