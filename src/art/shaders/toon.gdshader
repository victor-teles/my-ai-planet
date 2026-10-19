// Painterly toon shading: stepped light, shadows tinted by the environment's ambient color,
// a thin warm rim, and an optional "dryness" that turns green tones to straw during droughts.
// "snow" settles in brushy patches on whatever faces the sky in a cold island's winter.
// Brush strokes from a painted texture break up flat colors, projected from three sides so
// they follow any surface without UVs.
shader_type spatial;

uniform vec4 tint : source_color = vec4(1.0);
uniform float bands : hint_range(2.0, 6.0) = 3.0;
uniform float dryness : hint_range(0.0, 1.0) = 0.0;
uniform vec4 dry_color : source_color = vec4(0.80, 0.66, 0.40, 1.0);
uniform float snow : hint_range(0.0, 1.0) = 0.0;
uniform vec4 snow_color : source_color = vec4(0.88, 0.92, 1.0, 1.0);
uniform vec4 rim_color : source_color = vec4(1.0, 0.80, 0.62, 1.0);
uniform float rim_amount : hint_range(0.0, 1.0) = 0.25;
uniform vec4 emission_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform sampler2D albedo_texture : source_color, hint_default_white, filter_linear_mipmap; // e.g. a kit's color atlas
uniform sampler2D brush_strokes : filter_linear_mipmap, repeat_enable;
uniform float stroke_scale = 0.35; // texture repeats per world unit
uniform float stroke_value : hint_range(0.0, 1.0) = 0.22;
uniform float stroke_warmth : hint_range(0.0, 1.0) = 0.12;
uniform vec4 warm_color : source_color = vec4(1.0, 0.72, 0.45, 1.0);
uniform vec4 cool_color : source_color = vec4(0.45, 0.42, 0.85, 1.0);

varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec2 strokes_at(vec3 position, vec3 normal) {
	vec3 weights = pow(abs(normal), vec3(4.0));
	weights /= weights.x + weights.y + weights.z;
	vec3 p = position * stroke_scale;
	return texture(brush_strokes, p.zy).rg * weights.x
		+ texture(brush_strokes, p.xz).rg * weights.y
		+ texture(brush_strokes, p.xy).rg * weights.z;
}

void fragment() {
	vec3 base = COLOR.rgb * tint.rgb * texture(albedo_texture, UV).rgb;
	vec2 stroke = strokes_at(world_position, world_normal) - 0.5;
	base *= 1.0 + stroke.x * 2.0 * stroke_value;
	base = mix(base, base * (stroke.y > 0.0 ? warm_color.rgb : cool_color.rgb) * 1.25, abs(stroke.y) * 2.0 * stroke_warmth);
	float greenness = clamp((base.g - max(base.r, base.b)) * 4.0, 0.0, 1.0);
	base = mix(base, dry_color.rgb * (0.75 + 0.25 * length(base)), dryness * greenness);
	if (snow > 0.0) {
		float facing_up = smoothstep(0.45, 0.8, world_normal.y);
		float patch = stroke.x + stroke.y * 0.6 + 0.5;
		float cover = facing_up * smoothstep(1.0 - snow, 1.12 - snow, patch);
		base = mix(base, snow_color.rgb * (0.9 + stroke.x * 0.3), cover);
	}
	ALBEDO = base;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	EMISSION = emission_color.rgb;
}

void light() {
	float half_lambert = dot(NORMAL, LIGHT) * 0.5 + 0.5;
	float lit = clamp(floor(half_lambert * ATTENUATION * bands) / (bands - 1.0), 0.0, 1.0);
	DIFFUSE_LIGHT += lit * LIGHT_COLOR / PI;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0) * half_lambert * ATTENUATION;
	DIFFUSE_LIGHT += step(0.45, rim) * rim_amount * rim_color.rgb * LIGHT_COLOR / PI;
}
