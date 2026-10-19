class_name Gait
extends RefCounted
## How one person walks, from age, body, health, mood, traits and what they carry.
## speed is world units per second. A healthy average adult matches Settlement's 0.42.
## drift() is a seeded offset so two people with the same stats do not move in step.

const WALK_SPEED := 0.42
const CHILD_UNTIL := 14
const ELDER_AT := 60


## age in years, height and build in 0..1, health and mood in 0..100.
## load is "", "food", "wood" or "stone". Traits that change the walk: proud, shy, fierce, brave.
static func profile(age_years: int, height: float, build: float, health: float, sick: bool, mood: float, traits: PackedStringArray, load: String) -> Dictionary:
	var height_t := clampf(height, 0.0, 1.0)
	var build_t := clampf(build, 0.0, 1.0)
	var health_t := clampf(health / 100.0, 0.0, 1.0)
	var mood_t := clampf(mood, 0.0, 100.0)
	var speed := WALK_SPEED
	var stride := 1.0
	var limp := 0.0
	var stoop := 0.0
	var head_down := false
	var bounce := 0.0
	var comfort := 0.58
	var pause := 0.04

	# 0.5 is an average adult: no change. Taller people take a longer stride and a little more speed.
	var height_span := height_t - 0.5
	speed *= 1.0 + height_span * 0.12
	stride *= 1.0 + height_span * 0.36
	# Stout is heavier and slower. Slim is a little quicker.
	var build_span := build_t - 0.5
	speed *= 1.0 - build_span * 0.28
	stride *= 1.0 - build_span * 0.12
	speed *= lerpf(0.74, 1.0, health_t)
	if health_t < 0.4:
		limp = maxf(limp, (0.4 - health_t) / 0.4 * 0.55)

	if age_years < CHILD_UNTIL:
		speed *= 1.38
		stride *= 0.78
		bounce = maxf(bounce, 0.62)
		pause = 0.02
		comfort = 0.46
	elif age_years >= ELDER_AT:
		var years_past := clampf(float(age_years - ELDER_AT) / 25.0, 0.0, 1.0)
		speed *= lerpf(0.70, 0.56, years_past)
		stride *= lerpf(0.92, 0.84, years_past)
		stoop = lerpf(0.38, 0.72, years_past)
		pause = lerpf(0.22, 0.48, years_past)

	if sick:
		speed *= 0.68
		limp = maxf(limp, 0.82)
		stoop = minf(1.0, stoop + 0.12)
		pause = minf(1.0, pause + 0.08)

	if mood_t < 35.0:
		var sadness := (35.0 - mood_t) / 35.0
		speed *= lerpf(1.0, 0.76, sadness)
		head_down = true
		stoop = minf(1.0, stoop + sadness * 0.22)
		pause = minf(1.0, pause + sadness * 0.1)
	elif mood_t > 75.0:
		bounce = maxf(bounce, (mood_t - 75.0) / 25.0)

	if traits.has("proud"):
		stoop = maxf(0.0, stoop - 0.45)
	if traits.has("shy"):
		comfort += 0.30
	if traits.has("fierce") or traits.has("brave"):
		speed *= 1.07

	match load:
		"food":
			speed *= 0.93
		"wood":
			speed *= 0.84
		"stone":
			speed *= 0.72

	return {
		"speed": speed,
		"stride": clampf(stride, 0.45, 1.45),
		"limp": clampf(limp, 0.0, 1.0),
		"stoop": clampf(stoop, 0.0, 1.0),
		"head_down": head_down,
		"bounce": clampf(bounce, 0.0, 1.0),
		"comfort": comfort,
		"pause": clampf(pause, 0.0, 1.0),
	}


## Small speed and pause offsets. A fresh generator seeded by seed, never the global RNG.
static func drift(seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	return {
		"speed": rng.randf_range(-0.035, 0.035),
		"pause": rng.randf_range(-0.04, 0.04),
	}
