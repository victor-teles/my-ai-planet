extends TestCase


## The founding tribe grown (or not) to `first` people, and a second tribe of `second` newcomers,
## both drinking from the pond.
func _two_tribes(first: int, second: int) -> WorldState:
	var state := WorldState.create(42, 1)
	if first > state.tribe_population[0]:
		Dilemma.newcomers(state, state.tribe_names[0], first - state.tribe_population[0])
	state.tribe_food[0] = state.tribe_population[0] * 120.0
	state.add_tribe("Rivals", 0)
	Dilemma.newcomers(state, "Rivals", second)
	state.tribe_food[1] = second * 120.0
	People.choose_chief(state, 1, "founding")
	return state


func _deaths(state: WorldState, cause: String) -> Array:
	return state.events.filter(func(event: Dictionary) -> bool: return event["type"] == "death" and event["data"]["cause"] == cause)


func test_crowded_pond_runs_low_and_tribes_move() -> void:
	var state := _two_tribes(40, 40)
	state.water_capacity[0] = 30.0
	var sim := Simulation.new(state)
	sim.advance(2 * WorldState.DAYS_PER_MONTH)
	assert_true(state.water_level[0] < 0.8, "80 people drain a pond made for 30, got %.2f" % state.water_level[0])
	sim.advance(WorldState.DAYS_PER_YEAR)
	var types := state.events.map(func(event: Dictionary) -> String: return event["type"])
	assert_true("tribe_moved" in types, "a thirsty tribe moves to a spring")
	assert_true(state.tribe_water[0] != state.tribe_water[1], "they no longer share")
	assert_true(_deaths(state, "thirst").is_empty(), "they move before anyone dies of thirst")


func test_sharing_a_failing_spring_makes_rivals() -> void:
	var state := _two_tribes(30, 30)
	state.water_level[0] = 0.1
	RelationsSystem.new().update(state)
	assert_true(state.relation(state.tribe_names[0], "Rivals") < 0, "shared thirst sours them")


func test_rivals_go_to_war_and_people_fall() -> void:
	var state := _two_tribes(40, 20)
	var names := [state.tribe_names[0], "Rivals"]
	var before := state.total_population()
	var system := RelationsSystem.new()
	for year: int in 40:
		state.set_relation(names[0], names[1], -100)
		system.update(state)
		if state.ticks_since("war") == 0:
			break
	assert_eq(state.ticks_since("war"), 0, "a blood feud ends in war within 40 years")
	var fallen := _deaths(state, "war")
	assert_true(not fallen.is_empty(), "named people fall in battle")
	assert_eq(state.total_population(), before - fallen.size())
	for death: Dictionary in fallen:
		assert_true(state.dead.has(str(death["data"]["id"])), "%s is remembered" % death["data"]["name"])
	assert_true(state.relation(names[0], names[1]) > -100, "war exhausts the hatred")


func test_small_friend_merges() -> void:
	var state := _two_tribes(50, 6)
	var big := state.tribe_names[0]
	var total := state.total_population()
	var system := RelationsSystem.new()
	for year: int in 40:
		if state.tribe_count() == 1:
			break
		state.set_relation(big, "Rivals", 80)
		system.update(state)
	assert_eq(state.tribe_count(), 1, "the small tribe joins its friend")
	assert_eq(state.tribe_population[0], total, "everyone moves over")
	for p: int in state.person_ids.size():
		assert_eq(state.person_tribes[p], big)
	assert_true("tribes_merged" in state.events.map(func(event: Dictionary) -> String: return event["type"]))


func test_dilemma_relation_effect() -> void:
	var state := _two_tribes(30, 20)
	var first := state.tribe_names[0]
	var proposal := {
		"title": "Test", "situation": "Something happens.", "tribe": first,
		"choices": [
			{"label": "Make peace", "hint": "", "effects": [{"type": "relation", "tribe": "Rivals", "amount": 99}]},
			{"label": "Talk to yourself", "hint": "", "effects": [{"type": "relation", "tribe": first, "amount": 10}]},
		],
	}
	var dilemma := Dilemma.from_proposal(proposal, state)
	assert_eq(dilemma.choices[1]["effects"].size(), 0, "a tribe can't have a relation with itself")
	dilemma.choose(state, 0)
	assert_eq(state.relation(first, "Rivals"), 40, "clamped to 40")


func test_dilemma_population_effects_are_people() -> void:
	var state := WorldState.create(42, 1)
	var tribe := state.tribe_names[0]
	var before := state.total_population()
	var dilemma := Dilemma.from_proposal({
		"title": "Test", "situation": "Strangers and fevers.", "tribe": tribe,
		"choices": [
			{"label": "Welcome them", "hint": "", "effects": [{"type": "population", "tribe": tribe, "amount": 15}]},
			{"label": "Let it pass", "hint": "", "effects": [{"type": "population", "tribe": tribe, "amount": -25}]},
		],
	}, state)
	dilemma.choose(state, 0)
	var joined := state.total_population() - before
	assert_true(joined >= 1, "strangers join")
	assert_true("newcomers" in state.events.map(func(event: Dictionary) -> String: return event["type"]))
	dilemma.choose(state, 1)
	assert_true(not _deaths(state, "sickness").is_empty(), "sickness takes people")
	assert_true(state.total_population() < before + joined)


func test_relations_and_water_survive_save_and_load() -> void:
	var sim := Simulation.create(3, 1)
	sim.advance(12 * WorldState.DAYS_PER_YEAR)
	var loaded := Simulation.new(WorldState.from_dict(JSON.parse_string(sim.state.to_json())))
	assert_eq(loaded.state.checksum(), sim.state.checksum())
	sim.advance(3 * WorldState.DAYS_PER_YEAR)
	loaded.advance(3 * WorldState.DAYS_PER_YEAR)
	assert_eq(loaded.state.checksum(), sim.state.checksum())
