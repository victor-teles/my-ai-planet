// Animals: the toon shading of the props (stepped light, ambient-tinted shadows, a warm rim,
// brush strokes), with each animal's own coat. One material per part of a model; "role" says
// which of the animal's colors the part takes, so a whole herd shares a handful of materials.
// role 0 keeps the tint (eyes, hooves, horns), 1 is the coat, 2 the light belly and muzzle,
// 3 the dark mane or tail, 4 a shaded patch of the coat. Pattern lays spots (1) or stripes (2)
// of the dark color on the coat, as strong as the pattern gene.
shader_type spatial;

uniform vec4 tint : source_color = vec4(1.0);
uniform int role = 0;
uniform float bands : hint_range(2.0, 6.0) = 3.0;
uniform vec4 rim_color : source_color = vec4(1.0, 0.80, 0.62, 1.0);
uniform float rim_amount : hint_range(0.0, 1.0) = 0.25;
uniform float pattern_scale = 1.0; // pattern cells per model unit
uniform sampler2D brush_strokes : filter_linear_mipmap, repeat_enable;
uniform float stroke_scale = 0.35;
uniform float stroke_value : hint_range(0.0, 1.0) = 0.18;
instance uniform vec4 coat : source_color = vec4(0.55, 0.38, 0.24, 1.0);
instance uniform vec4 belly : source_color = vec4(0.86, 0.76, 0.62, 1.0);
instance uniform vec4 dark : source_color = vec4(0.30, 0.20, 0.14, 1.0);
instance uniform float pattern = 0.0; // 0 plain to 1 boldly marked
instance uniform float pattern_kind = 0.0; // 0 none, 1 spots, 2 stripes

varying vec3 model_position;
varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
	model_position = VERTEX;
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float hash3(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

// 0..1: how much of the dark color a point of the coat takes.
float marking(vec3 p) {
	int kind = int(pattern_kind + 0.5);
	if (kind == 0 || pattern < 0.02) {
		return 0.0;
	}
	vec3 q = p * pattern_scale;
	if (kind == 2) {
		float band = fract(q.z * 1.3 + sin(q.y * 2.1) * 0.25);
		return step(1.0 - 0.45 * pattern, band);
	}
	vec3 cell = floor(q);
	vec3 local = fract(q) - 0.5;
	float spot = 0.0;
	if (hash3(cell) < 0.35 + 0.5 * pattern) {
		vec3 offset = vec3(hash3(cell + 1.3), hash3(cell + 2.7), hash3(cell + 5.1)) - 0.5;
		spot = step(length(local - offset * 0.4), 0.18 + 0.2 * pattern);
	}
	return spot;
}

void fragment() {
	vec3 base = tint.rgb;
	if (role == 1 || role == 4) {
		vec3 fur = role == 4 ? coat.rgb * 0.8 : coat.rgb;
		base = mix(fur, dark.rgb, marking(model_position) * clamp(pattern, 0.0, 0.85));
	} else if (role == 2) {
		base = belly.rgb;
	} else if (role == 3) {
		base = dark.rgb;
	}
	vec3 weights = pow(abs(world_normal), vec3(4.0));
	weights /= weights.x + weights.y + weights.z;
	vec3 sp = world_position * stroke_scale;
	float stroke = texture(brush_strokes, sp.zy).r * weights.x + texture(brush_strokes, sp.xz).r * weights.y
		+ texture(brush_strokes, sp.xy).r * weights.z - 0.5;
	base *= 1.0 + stroke * 2.0 * stroke_value;
	ALBEDO = base;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	float half_lambert = dot(NORMAL, LIGHT) * 0.5 + 0.5;
	float lit = clamp(floor(half_lambert * ATTENUATION * bands) / (bands - 1.0), 0.0, 1.0);
	DIFFUSE_LIGHT += lit * LIGHT_COLOR / PI;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0) * half_lambert * ATTENUATION;
	DIFFUSE_LIGHT += step(0.45, rim) * rim_amount * rim_color.rgb * LIGHT_COLOR / PI;
}
