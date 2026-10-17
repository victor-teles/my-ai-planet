// Hand-drawn villager billboards. The sprite sheet holds two walk frames side by side, painted
// with key colors: magenta for the tunic and green for the hair. Each figure swaps them for its
// tribe's tunic color and its own hair color, keeping the painted shading and the ink edges.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

uniform sampler2D sheet : source_color, filter_linear_mipmap;
uniform vec4 light_tint : source_color = vec4(1.0, 0.93, 0.88, 1.0); // dusk light on unlit paint
instance uniform vec4 tunic : source_color = vec4(1.0);
instance uniform vec4 hair : source_color = vec4(0.35, 0.22, 0.16, 1.0);
instance uniform float frame = 0.0;
instance uniform float flip = 0.0;

void vertex() {
	// Turn to face the camera around the vertical axis only, so figures stay upright.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		vec4(normalize(cross(vec3(0.0, 1.0, 0.0), INV_VIEW_MATRIX[2].xyz)), 0.0),
		vec4(0.0, 1.0, 0.0, 0.0),
		vec4(normalize(cross(INV_VIEW_MATRIX[0].xyz, vec3(0.0, 1.0, 0.0))), 0.0),
		MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec2 uv = UV;
	if (flip > 0.5) {
		uv.x = 1.0 - uv.x;
	}
	uv.x = (uv.x + frame) * 0.5;
	vec4 paint = texture(sheet, uv);
	// Steep, so edges where a key color blends into skin or ink still count as fully keyed
	// (no green fringe), while pure ink, skin and the feathers never do.
	float tunic_key = clamp((min(paint.r, paint.b) - paint.g - 0.08) * 6.0, 0.0, 1.0);
	float hair_key = clamp((paint.g - max(paint.r, paint.b) - 0.04) * 6.0, 0.0, 1.0);
	vec3 color = paint.rgb;
	color = mix(color, tunic.rgb * max(paint.r, paint.b), tunic_key);
	color = mix(color, hair.rgb * paint.g, hair_key);
	ALBEDO = color * light_tint.rgb;
	ALPHA = paint.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
