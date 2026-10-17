class_name PopulationSystem
extends SimSystem
## Gathering, eating, births, deaths, famine, and tribes splitting when they grow large.
## Numbers are first-pass placeholders; balancing happens in M2.

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


func get_id() -> String:
	return "population"


func update(state: WorldState) -> void:
	var total := state.total_population()
	# Walk backwards so removing an extinct tribe doesn't skip one.
	# Tribes created by a split this tick are appended past the start index and wait until next tick.
	for i: int in range(state.tribe_count() - 1, -1, -1):
		_update_tribe(state, i, total)


func _update_tribe(state: WorldState, i: int, valley_population: int) -> void:
	var population := state.tribe_population[i]
	var crowding := 1.0 / (1.0 + population / TRIBE_CAPACITY + valley_population / VALLEY_CAPACITY)
	var food := state.tribe_food[i]
	food += population * FOOD_GATHERED_PER_PERSON * state.rainfall * crowding
	food -= population * FOOD_EATEN_PER_PERSON

	var fed := food >= 0.0
	if not fed:
		var starved := mini(state.rng.round_stochastic(-food / FOOD_EATEN_PER_PERSON * STARVATION_RATE), population)
		population -= starved
		food = 0.0
		if starved >= 3:
			state.log_event("famine", {"tribe": state.tribe_names[i], "deaths": starved})

	var birth_rate := BIRTH_RATE if fed else BIRTH_RATE * HUNGRY_BIRTH_FACTOR
	population += state.rng.round_stochastic(population * birth_rate)
	population -= mini(state.rng.round_stochastic(population * DEATH_RATE), population)
	food = minf(food, population * MAX_STORED_MONTHS)

	if population <= 0:
		state.log_event("tribe_extinct", {"tribe": state.tribe_names[i]})
		state.remove_tribe(i)
		return

	state.tribe_population[i] = population
	state.tribe_food[i] = food

	if state.month() == 0 and population >= SPLIT_AT_POPULATION and state.rng.chance(SPLIT_CHANCE_PER_YEAR):
		@warning_ignore("integer_division")
		var leaving := population / 2
		var food_taken := food * leaving / population
		state.tribe_population[i] = population - leaving
		state.tribe_food[i] = food - food_taken
		var new_name := NameGen.tribe_name(state.rng)
		state.add_tribe(new_name, leaving, food_taken)
		state.log_event("tribe_split", {"from": state.tribe_names[i], "to": new_name, "people": leaving})
