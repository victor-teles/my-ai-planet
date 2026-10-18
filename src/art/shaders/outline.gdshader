// Ink outline by the inverted-hull method: a slightly larger, inside-out copy drawn in a flat color.
// Used as the next_pass of toon materials. Needs smooth normals to avoid gaps.
shader_type spatial;
render_mode cull_front, unshaded;

uniform vec4 color : source_color = vec4(0.16, 0.10, 0.20, 1.0);
uniform float width : hint_range(0.0, 0.2) = 0.03;

void vertex() {
	VERTEX += NORMAL * width;
}

void fragment() {
	ALBEDO = color.rgb;
}
