// Painterly toon shading: stepped light, shadows tinted by the environment's ambient color,
// a thin warm rim, and an optional "dryness" that turns green tones to straw during droughts.
shader_type spatial;

uniform vec4 tint : source_color = vec4(1.0);
uniform float bands : hint_range(2.0, 6.0) = 3.0;
uniform float dryness : hint_range(0.0, 1.0) = 0.0;
uniform vec4 dry_color : source_color = vec4(0.80, 0.66, 0.40, 1.0);
uniform vec4 rim_color : source_color = vec4(1.0, 0.80, 0.62, 1.0);
uniform float rim_amount : hint_range(0.0, 1.0) = 0.25;
uniform vec4 emission_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);

void fragment() {
	vec3 base = COLOR.rgb * tint.rgb;
	float greenness = clamp((base.g - max(base.r, base.b)) * 4.0, 0.0, 1.0);
	base = mix(base, dry_color.rgb * (0.75 + 0.25 * length(base)), dryness * greenness);
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
