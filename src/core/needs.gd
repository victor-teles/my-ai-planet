class_name Needs
extends RefCounted
## What a tribe needs, each from 0 (desperate) to 1 (met): food, water, shelter and safety.
## Derived from the world on demand, so there is nothing extra to save.

const NAMES: Array[String] = ["food", "water", "shelter", "safety"]
const FED_DAYS := 60.0 ## stores per person that count as fully fed
const LOW_WATER := 0.35 ## below this fullness a source can't serve everyone


static func food(state: WorldState, i: int) -> float:
	if state.tribe_hungry_days[i] > 3:
		return 0.0
	return clampf(state.tribe_food[i] / maxf(state.tribe_population[i], 1.0) / FED_DAYS, 0.0, 1.0)


static func water(state: WorldState, i: int) -> float:
	return clampf(state.water_level[state.tribe_water[i]] / LOW_WATER, 0.0, 1.0)


## Beds under a roof for everyone.
static func shelter(state: WorldState, i: int) -> float:
	return clampf(float(home_capacity(state, state.tribe_names[i])) / maxf(state.tribe_population[i], 1.0), 0.0, 1.0)


static func home_capacity(state: WorldState, tribe: String) -> int:
	var beds := 0
	for b: int in state.building_ids.size():
		if state.building_tribes[b] == tribe and state.is_built(b):
			beds += Buildings.capacity(state.building_types[b])
	return beds


## 1 at peace with everyone; falls toward 0 as the tribe's worst rivalry deepens.
static func safety(state: WorldState, i: int) -> float:
	var worst := 0
	for j: int in state.tribe_count():
		if j != i:
			worst = mini(worst, state.relation(state.tribe_names[i], state.tribe_names[j]))
	return 1.0 + worst / 100.0


static func get_need(state: WorldState, i: int, need: String) -> float:
	match need:
		"food":
			return food(state, i)
		"water":
			return water(state, i)
		"shelter":
			return shelter(state, i)
		"safety":
			return safety(state, i)
	return 1.0


## A tribe is only as happy as its worst unmet need lets it be.
static func mood(state: WorldState, i: int) -> float:
	var total := 0.0
	var worst := 1.0
	for need: String in NAMES:
		var value := get_need(state, i, need)
		total += value
		worst = minf(worst, value)
	return 0.5 * worst + 0.5 * total / NAMES.size()


static func mood_word(value: float) -> String:
	if value < 0.3:
		return "desperate"
	if value < 0.55:
		return "uneasy"
	if value < 0.8:
		return "content"
	return "thriving"
