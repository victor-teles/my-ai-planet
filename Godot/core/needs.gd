class_name Needs
extends RefCounted
## What a tribe needs, each from 0 (desperate) to 1 (met): food, water, room and safety.
## Derived from the world on demand, so there is nothing extra to save.

const NAMES: Array[String] = ["food", "water", "room", "safety"]
const FED_MONTHS := 2.0 ## stores that count as fully fed
const LOW_WATER := 0.35 ## below this fullness a source can't serve everyone


static func food(state: WorldState, i: int) -> float:
	return clampf(state.tribe_food[i] / maxf(state.tribe_population[i], 1.0) / FED_MONTHS, 0.0, 1.0)


static func water(state: WorldState, i: int) -> float:
	return clampf(state.water_level[state.tribe_water[i]] / LOW_WATER, 0.0, 1.0)


static func room(state: WorldState, i: int) -> float:
	return clampf(2.0 * PopulationSystem.crowding(state, i) - 0.6, 0.0, 1.0)


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
		"room":
			return room(state, i)
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
