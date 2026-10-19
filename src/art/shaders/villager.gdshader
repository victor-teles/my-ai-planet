// Villagers: Kenney's low-poly character with our painted skins, toon-shaded like the rest of
// the world. A mask picks out the tunic (red), hair (green) and skin (blue), which take each
// figure's own colors; the skin texture holds only their brightness there.
// A tribe's fashion can weave a pattern into the tunic in a trim color: the tunic's torso panel
// sits at u 0.15-0.48, v 0.49-0.94 of the skins (collar at the top, belt at the bottom).
shader_type spatial;

uniform sampler2D skin : source_color, filter_linear_mipmap;
uniform sampler2D mask : filter_linear_mipmap;
uniform float bands : hint_range(2.0, 6.0) = 3.0;
uniform vec4 rim_color : source_color = vec4(1.0, 0.80, 0.62, 1.0);
uniform float rim_amount : hint_range(0.0, 1.0) = 0.25;
instance uniform vec4 tunic : source_color = vec4(0.8, 0.3, 0.3, 1.0);
instance uniform vec4 hair : source_color = vec4(0.25, 0.16, 0.12, 1.0);
instance uniform vec4 skin_tone : source_color = vec4(0.94, 0.72, 0.58, 1.0);
instance uniform vec4 trim : source_color = vec4(0.98, 0.80, 0.36, 1.0);
// 0 plain, 1 stripes, 2 hem (the collar and a band above the belt), 3 checks, 4 sash.
instance uniform float pattern = 0.0;

// How much of the trim color shows at a point of the tunic, 0 to 1.
float woven(vec2 uv) {
	int kind = int(pattern + 0.5);
	bool torso = uv.x < 0.5;
	if (kind == 1) {
		return step(0.62, fract(uv.y * 18.0));
	}
	if (kind == 2) {
		return torso && (uv.y < 0.53 || (uv.y > 0.895 && uv.y < 0.935)) ? 1.0 : 0.0;
	}
	if (kind == 3) {
		return mod(floor(uv.x * 26.0) + floor(uv.y * 26.0), 2.0) * 0.55;
	}
	if (kind == 4) {
		return torso && abs(fract((uv.x * 1.4 - uv.y) * 1.6) - 0.5) < 0.07 ? 1.0 : 0.0;
	}
	return 0.0;
}

void fragment() {
	vec3 color = texture(skin, UV).rgb;
	vec3 keys = texture(mask, UV).rgb;
	vec3 cloth = mix(tunic.rgb, trim.rgb, woven(UV));
	color *= mix(vec3(1.0), cloth, keys.r);
	color *= mix(vec3(1.0), hair.rgb, keys.g);
	color *= mix(vec3(1.0), skin_tone.rgb, keys.b);
	ALBEDO = color;
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
