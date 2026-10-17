class_name PopulationSystem
extends SimSystem
## Gathering, eating, drinking, births, deaths, famine, and tribes splitting when they grow large.

const FOOD_EATEN_PER_PERSON := 1.0 ## per month
const FOOD_GATHERED_PER_PERSON := 1.5 ## per month, at normal rain and no crowding
const TRIBE_CAPACITY := 200.0 ## crowding inside one tribe's land
const VALLEY_CAPACITY := 2000.0 ## crowding across the whole valley
const MAX_STORED_MONTHS := 8.0 ## food spoils beyond this
const BIRTH_RATE := 0.0045 ## per person per month when fed
const HUNGRY_BIRTH_FACTOR := 0.3
const DEATH_RATE := 0.0025 ## per person per month
const STARVATION_RATE := 0.1 ## share of the food shortfall that becomes deaths
const SPLIT_AT_POPULATION := 80
const SPLIT_CHANCE_PER_YEAR := 0.5
const THIRSTY_GATHERING := 0.5 ## share of food a tribe with no water left can still gather
const THIRST_DEATH_FACTOR := 2.0 ## extra deaths at no water, as a multiple of DEATH_RATE


func get_id() -> String:
	return "population"


func update(state: WorldState) -> void:
	var total := state.total_population()
	# Walk backwards so removing an extinct tribe doesn't skip one.
	# Tribes created by a split this tick are appended past the start index and wait until next tick.
	for i: int in range(state.tribe_count() - 1, -1, -1):
		_update_tribe(state, i, total)


## One famine event per tribe per year is enough for the story; hungry months in between are quiet.
func _recent_famine(state: WorldState, tribe_name: String) -> bool:
	for j: int in range(state.events.size() - 1, maxi(state.events.size() - 30, 0) - 1, -1):
		var event := state.events[j]
		if state.tick - int(event["tick"]) >= WorldState.MONTHS_PER_YEAR:
			return false
		if event["type"] == "famine" and event["data"]["tribe"] == tribe_name:
			return true
	return false


## 1 with plenty of room, falling as the tribe and the valley fill up.
static func crowding(state: WorldState, i: int, valley_population: int = -1) -> float:
	if valley_population < 0:
		valley_population = state.total_population()
	return 1.0 / (1.0 + state.tribe_population[i] / TRIBE_CAPACITY + valley_population / VALLEY_CAPACITY)


func _update_tribe(state: WorldState, i: int, valley_population: int) -> void:
	var population := state.tribe_population[i]
	var water := Needs.water(state, i)
	var food := state.tribe_food[i]
	var gathering := FOOD_GATHERED_PER_PERSON * Citizens.chief_effect(state, state.tribe_names[i], "gather")
	food += population * gathering * state.rainfall * crowding(state, i, valley_population) * lerpf(THIRSTY_GATHERING, 1.0, water)
	food -= population * FOOD_EATEN_PER_PERSON

	var fed := food >= 0.0
	if not fed:
		var starvation := STARVATION_RATE * Citizens.chief_effect(state, state.tribe_names[i], "starve")
		var starved := mini(state.rng.round_stochastic(-food / FOOD_EATEN_PER_PERSON * starvation), population)
		population -= starved
		food = 0.0
		if starved >= 3 and not _recent_famine(state, state.tribe_names[i]):
			state.log_event("famine", {"tribe": state.tribe_names[i], "deaths": starved})

	var birth_rate := BIRTH_RATE if fed else BIRTH_RATE * HUNGRY_BIRTH_FACTOR
	population += state.rng.round_stochastic(population * birth_rate)
	var death_rate := DEATH_RATE * (1.0 + THIRST_DEATH_FACTOR * (1.0 - water))
	population -= mini(state.rng.round_stochastic(population * death_rate), population)
	food = minf(food, population * MAX_STORED_MONTHS)

	if population <= 0:
		state.log_event("tribe_extinct", {"tribe": state.tribe_names[i]})
		state.remove_tribe(i)
		return

	state.tribe_population[i] = population
	state.tribe_food[i] = food

	var split_chance := SPLIT_CHANCE_PER_YEAR * Citizens.chief_effect(state, state.tribe_names[i], "split")
	if state.month() == 0 and population >= SPLIT_AT_POPULATION and state.rng.chance(split_chance):
		@warning_ignore("integer_division")
		state.split_tribe(i, population / 2)
