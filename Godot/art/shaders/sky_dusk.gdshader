// Era 3 "First Fires" dusk sky: violet zenith, rose horizon, sparse stars and a warm sun glow.
shader_type sky;

uniform vec4 top_color : source_color = vec4(0.16, 0.10, 0.34, 1.0);
uniform vec4 horizon_color : source_color = vec4(0.98, 0.58, 0.52, 1.0);
uniform vec4 bottom_color : source_color = vec4(0.48, 0.26, 0.48, 1.0);
uniform vec4 sun_color : source_color = vec4(1.0, 0.82, 0.58, 1.0);
uniform float star_amount : hint_range(0.0, 1.0) = 0.7;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void sky() {
	float y = EYEDIR.y;
	vec3 color = y > 0.0
		? mix(horizon_color.rgb, top_color.rgb, pow(clamp(y, 0.0, 1.0), 0.55))
		: mix(horizon_color.rgb, bottom_color.rgb, pow(clamp(-y, 0.0, 1.0), 0.6));
	float star = step(0.9975, hash(floor(EYEDIR * 220.0))) * smoothstep(0.2, 0.7, y) * star_amount;
	color += vec3(star);
	if (LIGHT0_ENABLED) {
		color += sun_color.rgb * pow(max(dot(EYEDIR, LIGHT0_DIRECTION), 0.0), 20.0) * 0.55;
	}
	COLOR = color;
}
