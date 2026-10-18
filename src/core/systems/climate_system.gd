class_name ClimateSystem
extends SimSystem
## Seasonal rain with random droughts, scaled by the island's climate (see WorldGen). Uses a lookup
## table instead of sin() so results don't depend on each platform's math library.
## Each island is prone to its own disaster: storms that tear down buildings, locusts that strip the
## fields, blizzards that eat the stores, quakes that bring down stone. And once the factories come,
## their smoke hangs over everyone; rain washes some of it away.

const SEASONAL_RAIN: Array[float] = [0.8, 0.9, 1.1, 1.3, 1.4, 1.3, 1.1, 0.9, 0.8, 0.7, 0.7, 0.8]
const DROUGHT_RAIN_FACTOR := 0.6
const DROUGHT_MIN_MONTHS := 4
const DROUGHT_MAX_MONTHS := 12
const BLESSED_RAIN_FACTOR := 1.35
const DISASTER_CHANCE := 0.07 ## per year
const HAZARD_MONTHS := {"storms": 8, "locusts": 6, "blizzards": 0, "quakes": 4} ## when each strikes, if it does
const SMOG_CLEARS := 0.05 ## share of the smoke that clears each month, more with rain


func get_id() -> String:
	return "climate"


func get_interval() -> int:
	return WorldState.DAYS_PER_MONTH


func update(state: WorldState) -> void:
	var drought_chance := float(state.world.get("drought", 0.045))
	if state.month() == 0 and state.drought_months_left == 0 and state.blessed_rain_months == 0 and state.rng.chance(drought_chance):
		state.drought_months_left = state.rng.randi_range(DROUGHT_MIN_MONTHS, DROUGHT_MAX_MONTHS)
		state.log_event("drought_started", {"months": state.drought_months_left})

	var rain := SEASONAL_RAIN[state.month()] * (0.9 + 0.2 * state.rng.randf()) * float(state.world.get("rain", 1.0))
	if state.drought_months_left > 0:
		rain *= DROUGHT_RAIN_FACTOR
		state.drought_months_left -= 1
		if state.drought_months_left == 0:
			state.log_event("drought_ended")
	if state.blessed_rain_months > 0:
		rain *= BLESSED_RAIN_FACTOR
		state.blessed_rain_months -= 1
	state.rainfall = rain
	state.pollution = maxf(state.pollution - state.pollution * SMOG_CLEARS * clampf(rain, 0.5, 1.5), 0.0)
	var hazard := String(state.world.get("hazard", "storms"))
	if state.month() == int(HAZARD_MONTHS.get(hazard, 8)) and state.tribe_count() > 0 and state.rng.chance(DISASTER_CHANCE):
		_disaster(state, hazard)


func _disaster(state: WorldState, hazard: String) -> void:
	var t := state.rng.pick_index(state.tribe_count())
	var tribe := state.tribe_names[t]
	match hazard:
		"storms", "quakes":
			var standing: Array[int] = []
			for b: int in state.buildings_of(tribe):
				var type := state.building_types[b]
				if type == "fire" or not state.is_built(b):
					continue
				var stone := float(Buildings.TYPES[type]["stone"]) > float(Buildings.TYPES[type]["wood"])
				if (hazard == "quakes") == stone or state.rng.chance(0.3):
					standing.append(b)
			if standing.is_empty():
				return
			var b := standing[state.rng.pick_index(standing.size())]
			var type := state.building_types[b]
			state.log_event("disaster", {"kind": hazard, "tribe": tribe, "building": type})
			state.remove_building(b)
			WorkSystem.settle_homes(state, t)
		"locusts":
			var lost := state.tribe_food[t] * 0.4
			state.tribe_food[t] -= lost
			state.log_event("disaster", {"kind": hazard, "tribe": tribe, "days": roundi(lost / maxf(state.tribe_population[t], 1.0))})
		"blizzards":
			for i: int in state.tribe_count():
				state.tribe_food[i] *= 0.8
				state.tribe_wood[i] *= 0.7
			state.log_event("disaster", {"kind": hazard, "tribe": tribe})
