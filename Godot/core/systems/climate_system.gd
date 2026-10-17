class_name ClimateSystem
extends SimSystem
## Seasonal rain with random droughts. Uses a lookup table instead of sin() so results
## don't depend on each platform's math library.

const SEASONAL_RAIN: Array[float] = [0.8, 0.9, 1.1, 1.3, 1.4, 1.3, 1.1, 0.9, 0.8, 0.7, 0.7, 0.8]
const DROUGHT_CHANCE_PER_YEAR := 0.08
const DROUGHT_RAIN_FACTOR := 0.6
const DROUGHT_MIN_MONTHS := 6
const DROUGHT_MAX_MONTHS := 18


func get_id() -> String:
	return "climate"


func update(state: WorldState) -> void:
	if state.month() == 0 and state.drought_months_left == 0 and state.rng.chance(DROUGHT_CHANCE_PER_YEAR):
		state.drought_months_left = state.rng.randi_range(DROUGHT_MIN_MONTHS, DROUGHT_MAX_MONTHS)
		state.log_event("drought_started", {"months": state.drought_months_left})

	var rain := SEASONAL_RAIN[state.month()] * (0.9 + 0.2 * state.rng.randf())
	if state.drought_months_left > 0:
		rain *= DROUGHT_RAIN_FACTOR
		state.drought_months_left -= 1
		if state.drought_months_left == 0:
			state.log_event("drought_ended")
	state.rainfall = rain
