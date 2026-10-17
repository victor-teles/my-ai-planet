extends TestCase


## A world with two tribes of the given sizes, both drinking from the pond.
func _two_tribes(first: int, second: int) -> WorldState:
	var state := WorldState.create(42)
	state.tribe_population[0] = first
	state.tribe_food[0] = first * 4.0
	state.add_tribe("Rivals", second, second * 4.0, 0)
	return state


func test_crowded_spring_runs_low_and_tribes_move() -> void:
	var state := _two_tribes(60, 60)
	state.water_capacity[0] = 50.0
	var sim := Simulation.new(state)
	sim.advance(8)
	assert_true(state.water_level[0] < 0.5, "120 people drain a pond made for 50, got %.2f" % state.water_level[0])
	sim.advance(2 * WorldState.MONTHS_PER_YEAR)
	var types := state.events.map(func(event: Dictionary) -> String: return event["type"])
	assert_true("water_low" in types, "running low is logged")
	assert_true("tribe_moved" in types, "a thirsty tribe moves to a spring")
	assert_true(state.tribe_water[0] != state.tribe_water[1], "they no longer share")


func test_sharing_a_failing_spring_makes_rivals() -> void:
	var state := _two_tribes(60, 60)
	state.water_level[0] = 0.1
	state.water_capacity[1] = 0.0 # nowhere to move to
	state.water_capacity[2] = 0.0
	RelationsSystem.new().update(state)
	assert_true(state.relation(state.tribe_names[0], "Rivals") < 0, "shared thirst sours them")


func test_split_starts_as_kin() -> void:
	var state := WorldState.create(42)
	state.tribe_population[0] = 90
	var child := state.split_tribe(0, 45)
	assert_eq(state.relation(state.tribe_names[0], state.tribe_names[child]), WorldState.KIN_RELATION)
	assert_eq(state.tribe_population[0], 45)


func test_rivals_go_to_war() -> void:
	var state := _two_tribes(80, 40)
	var names := [state.tribe_names[0], "Rivals"]
	var system := RelationsSystem.new()
	for year: int in 40:
		state.set_relation(names[0], names[1], -100)
		system.update(state)
		if state.ticks_since("war") == 0:
			break
	var war: Dictionary = state.events[-1]
	assert_eq(war["type"], "war", "a blood feud ends in war within 40 years")
	assert_true(state.tribe_population[0] + state.tribe_population[1] < 120, "war kills")
	assert_true(state.relation(names[0], names[1]) > -100, "war exhausts the hatred")


func test_small_friend_merges() -> void:
	var state := _two_tribes(100, 12)
	var big := state.tribe_names[0]
	var system := RelationsSystem.new()
	for year: int in 40:
		if state.tribe_count() == 1:
			break
		state.set_relation(big, "Rivals", 80)
		system.update(state)
	assert_eq(state.tribe_count(), 1, "the small tribe joins its friend")
	assert_eq(state.tribe_population[0], 112)
	assert_eq(state.events[-1]["type"], "tribes_merged")


func test_dilemma_relation_effect() -> void:
	var state := _two_tribes(60, 60)
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


func test_relations_and_water_survive_save_and_load() -> void:
	var sim := Simulation.create(3)
	sim.advance(2400)
	var loaded := Simulation.new(WorldState.from_dict(JSON.parse_string(sim.state.to_json())))
	assert_eq(loaded.state.checksum(), sim.state.checksum())
	sim.advance(600)
	loaded.advance(600)
	assert_eq(loaded.state.checksum(), sim.state.checksum())
