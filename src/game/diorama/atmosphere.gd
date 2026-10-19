class_name Atmosphere
extends RefCounted
## The island's air and light, read from how its people live. A dystopia (Society.gloom) drains
## the color, cools the sun and closes the sky in a low grey overcast; factory smog
## (state.pollution) browns the sky, clouds and fog and hangs a haze over everything; a wired
## world's towns glow amber on the horizon. Measured a few times a second (gloom loops over every
## tribe) and eased, so the world darkens over seasons, not frames. Read-only on the simulation.

const MEASURE_EVERY := 0.25 ## seconds between readings of the simulation
const EASE := 0.12 ## of the whole change per second
const GLOOM_FROM := 0.1 ## island dystopia below this leaves the dusk untouched
const GLOOM_FULL := 0.6 ## and at this the world is as dark as it gets
const SMOG_FULL := 70.0 ## pollution at which the haze is thickest
const WIRED_AGE := 4

## The art bible's Era 3 dusk, then the same scene under a dystopia and under smog. Gloom mixes in
## first, smog on top. Shadows never go black: the ambient color only greys and cools.
const CLEAR := {
	"sky_top": Color(0.16, 0.10, 0.34), "sky_horizon": Color(0.98, 0.58, 0.52), "sky_bottom": Color(0.48, 0.26, 0.48),
	"sky_sun": Color(1.0, 0.82, 0.58), "sun_glow": 0.55, "stars": 0.7,
	"sun": Color(1.0, 0.80, 0.62), "sun_energy": 0.95, "ambient": Color(0.50, 0.36, 0.70), "rim": Color(1.0, 0.80, 0.62),
	"fog": Color(0.86, 0.56, 0.62), "fog_density": 0.002, "fog_sky": 0.0,
	"cloud_top": Color(1.0, 0.90, 0.90), "cloud_bottom": Color(0.68, 0.50, 0.74), "cloud_rim": Color(1.0, 0.78, 0.74),
	"water_deep": Color(0.20, 0.45, 0.62), "water_shallow": Color(0.45, 0.80, 0.82),
	"saturation": 1.0, "brightness": 1.0, "contrast": 1.0, "cool": 0.0,
}
const GLOOM := {
	"sky_top": Color(0.10, 0.10, 0.17), "sky_horizon": Color(0.56, 0.54, 0.62), "sky_bottom": Color(0.27, 0.26, 0.35),
	"sky_sun": Color(0.70, 0.72, 0.80), "sun_glow": 0.15, "stars": 0.0,
	"sun": Color(0.80, 0.84, 0.94), "sun_energy": 0.8, "ambient": Color(0.38, 0.38, 0.54), "rim": Color(0.78, 0.82, 0.92),
	"fog": Color(0.46, 0.47, 0.56), "fog_density": 0.009, "fog_sky": 0.15,
	"cloud_top": Color(0.72, 0.72, 0.80), "cloud_bottom": Color(0.36, 0.36, 0.48), "cloud_rim": Color(0.78, 0.78, 0.86),
	"water_deep": Color(0.18, 0.28, 0.38), "water_shallow": Color(0.38, 0.52, 0.58),
	"saturation": 0.5, "brightness": 0.9, "contrast": 1.08, "cool": 1.0,
}
const SMOG := {
	"sky_top": Color(0.24, 0.20, 0.18), "sky_horizon": Color(0.70, 0.56, 0.40), "sky_bottom": Color(0.40, 0.33, 0.28),
	"sky_sun": Color(0.95, 0.62, 0.32), "sun_glow": 0.3, "stars": 0.0,
	"sun": Color(0.96, 0.78, 0.56), "sun_energy": 0.78, "ambient": Color(0.48, 0.42, 0.42), "rim": Color(0.96, 0.74, 0.50),
	"fog": Color(0.58, 0.50, 0.40), "fog_density": 0.02, "fog_sky": 0.35,
	"cloud_top": Color(0.70, 0.62, 0.54), "cloud_bottom": Color(0.40, 0.35, 0.32), "cloud_rim": Color(0.80, 0.66, 0.52),
	"water_deep": Color(0.26, 0.30, 0.26), "water_shallow": Color(0.46, 0.50, 0.40),
	"saturation": 0.7, "brightness": 0.92, "contrast": 1.0, "cool": 0.0,
}

## Eased strengths, 0 to 1.
var gloom := 0.0
var smog := 0.0
var city := 0.0

var _environment: Environment
var _sky: ShaderMaterial
var _sun: DirectionalLight3D
var _water: ShaderMaterial
var _grade := Gradient.new()
var _target := Vector3.ZERO ## gloom, smog, city
var _applied := Vector3(-1.0, -1.0, -1.0)
var _timer := 0.0
var _measured := false


func _init(environment: Environment, sky: ShaderMaterial, sun: DirectionalLight3D, water: ShaderMaterial) -> void:
	_environment = environment
	_sky = sky
	_sun = sun
	_water = water
	var lut := GradientTexture1D.new()
	lut.gradient = _grade
	_environment.adjustment_enabled = true
	_environment.adjustment_color_correction = lut


func update(state: WorldState, delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0 or not _measured:
		_timer = MEASURE_EVERY
		_target = _measure(state)
		if not _measured:
			# The first look (a new game, a load, a warm-up) shows the world as it already is.
			gloom = _target.x
			smog = _target.y
			city = _target.z
			_measured = true
	gloom = move_toward(gloom, _target.x, delta * EASE)
	smog = move_toward(smog, _target.y, delta * EASE)
	city = move_toward(city, _target.z, delta * EASE)
	var now := Vector3(gloom, smog, city)
	if now.distance_to(_applied) > 0.002:
		_applied = now
		_apply()


## Forget the eased values, e.g. after loading another world, so the next look snaps to it.
func reset() -> void:
	_measured = false


func _measure(state: WorldState) -> Vector3:
	var dark := clampf((Society.gloom(state) - GLOOM_FROM) / (GLOOM_FULL - GLOOM_FROM), 0.0, 1.0)
	var haze := clampf(state.pollution / SMOG_FULL, 0.0, 1.0)
	var wired := 0.0
	for t: int in state.tribe_count():
		if state.age_of(t) >= WIRED_AGE:
			wired = 1.0
			break
	return Vector3(dark, haze, wired)


func _apply() -> void:
	_sky.set_shader_parameter("top_color", _color("sky_top"))
	_sky.set_shader_parameter("horizon_color", _color("sky_horizon"))
	_sky.set_shader_parameter("bottom_color", _color("sky_bottom"))
	_sky.set_shader_parameter("sun_color", _color("sky_sun"))
	_sky.set_shader_parameter("sun_glow", _number("sun_glow"))
	_sky.set_shader_parameter("star_amount", _number("stars"))
	# Towns light the horizon; smog catches the light and spreads it.
	_sky.set_shader_parameter("city_glow", city * (0.45 + 0.4 * smog))
	_sun.light_color = _color("sun")
	_sun.light_energy = _number("sun_energy")
	_environment.ambient_light_color = _color("ambient")
	_environment.fog_light_color = _color("fog")
	_environment.fog_density = _number("fog_density")
	_environment.fog_sky_affect = _number("fog_sky")
	_environment.adjustment_saturation = _number("saturation")
	_environment.adjustment_brightness = _number("brightness")
	_environment.adjustment_contrast = _number("contrast")
	# Cooling: a per-channel curve that holds back the reds and lifts the blues in the shadows.
	var cool := _number("cool") * 0.45
	_grade.set_color(0, Color(0.0, 0.01, 0.05).lerp(Color.BLACK, 1.0 - cool))
	_grade.set_color(1, Color(0.9, 0.96, 1.0).lerp(Color.WHITE, 1.0 - cool))
	var cloud := ToonMaterials.cloud()
	cloud.set_shader_parameter("top_color", _color("cloud_top"))
	cloud.set_shader_parameter("bottom_color", _color("cloud_bottom"))
	cloud.set_shader_parameter("rim_color", _color("cloud_rim"))
	_water.set_shader_parameter("deep_color", _color("water_deep"))
	_water.set_shader_parameter("shallow_color", _color("water_shallow"))
	ToonMaterials.set_rim(_color("rim"))


func _color(key: String) -> Color:
	return (CLEAR[key] as Color).lerp(GLOOM[key], gloom).lerp(SMOG[key], smog * 0.85)


func _number(key: String) -> float:
	return lerpf(lerpf(float(CLEAR[key]), float(GLOOM[key]), gloom), float(SMOG[key]), smog * 0.85)
