class_name Miracles
extends RefCounted
## What the player god can do. Every miracle costs Influence, is logged as an event (so the
## Oracle can cite it), and shifts the player's kindness, which sets the world's tone.

const DEFINITIONS := {
	"rain": {"name": "Rain", "cost": 3.0, "kindness": 1, "needs_tribe": false,
		"description": "Ends any drought and blesses the valley with rain for a year."},
	"harvest": {"name": "Harvest", "cost": 2.0, "kindness": 1, "needs_tribe": true,
		"description": "Fills a tribe's stores with four months of food."},
	"drought": {"name": "Drought", "cost": 2.0, "kindness": -1, "needs_tribe": false,
		"description": "Holds back the rain for a year."},
	"plague": {"name": "Plague", "cost": 3.0, "kindness": -2, "needs_tribe": true,
		"description": "A sickness takes a quarter of a tribe."},
}
const ORDER: Array[String] = ["rain", "harvest", "drought", "plague"]
const HARVEST_MONTHS := 4.0
const PLAGUE_SHARE := 0.25


## Empty string if the miracle can be cast, otherwise the reason it can't.
static func why_not(state: WorldState, id: String, tribe_name: String = "") -> String:
	if not DEFINITIONS.has(id):
		return "Unknown miracle"
	var definition: Dictionary = DEFINITIONS[id]
	if state.influence < float(definition["cost"]):
		return "Not enough Influence"
	if definition["needs_tribe"] and state.tribe_index(tribe_name) == -1:
		return "Choose a tribe first"
	if id == "drought" and state.drought_months_left > 0:
		return "There is already a drought"
	return ""


## Applies the miracle between ticks. Returns false (changing nothing) if it can't be cast.
static func cast(state: WorldState, id: String, tribe_name: String = "") -> bool:
	if not why_not(state, id, tribe_name).is_empty():
		return false
	var definition: Dictionary = DEFINITIONS[id]
	var tribe := state.tribe_index(tribe_name)
	var data := {"miracle": id}
	match id:
		"rain":
			state.drought_months_left = 0
			state.blessed_rain_months = WorldState.MONTHS_PER_YEAR
		"harvest":
			state.tribe_food[tribe] += state.tribe_population[tribe] * HARVEST_MONTHS
			data["tribe"] = tribe_name
		"drought":
			state.drought_months_left = WorldState.MONTHS_PER_YEAR
			state.blessed_rain_months = 0
		"plague":
			var deaths := ceili(state.tribe_population[tribe] * PLAGUE_SHARE)
			state.tribe_population[tribe] -= deaths
			data["tribe"] = tribe_name
			data["deaths"] = deaths
	state.influence -= float(definition["cost"])
	state.kindness += int(definition["kindness"])
	state.log_event("miracle", data)
	return true
