extends TestCase


func test_new_world_has_named_citizens_and_a_chief() -> void:
	var state := WorldState.create(42)
	var tribe := state.tribe_names[0]
	assert_eq(state.citizens_of(tribe).size(), Citizens.target_count(30))
	var chief := Citizens.chief(state, tribe)
	assert_true(chief != -1, "the tribe has a chief")
	for c: int in state.citizens_of(tribe):
		assert_true(state.citizen_names[c].length() >= 2, "named")
		assert_eq(Citizens.traits_of(state, c).size(), 2, "two traits")
		assert_true(Citizens.age(state, c) <= Citizens.age(state, chief), "the chief is the oldest")


func test_citizens_follow_tribe_sizes() -> void:
	var sim := Simulation.create(7)
	sim.advance(150 * WorldState.MONTHS_PER_YEAR + 1) # just after a yearly update
	var state := sim.state
	for tribe: String in state.tribe_names:
		var count := state.citizens_of(tribe).size()
		assert_true(count >= 1 and count <= Citizens.MAX_PER_TRIBE, "%s has %d citizens" % [tribe, count])
	for c: int in state.citizen_ids.size():
		assert_true(state.tribe_index(state.citizen_tribes[c]) != -1, "%s belongs to a living tribe" % state.citizen_names[c])


func test_chiefs_die_and_are_succeeded() -> void:
	var sim := Simulation.create(11)
	sim.advance(120 * WorldState.MONTHS_PER_YEAR)
	var types := sim.state.events.map(func(event: Dictionary) -> String: return event["type"])
	assert_true("new_chief" in types, "in 120 years some chief has been replaced")


func test_chief_traits_steer_the_tribe() -> void:
	var state := WorldState.create(42)
	var tribe := state.tribe_names[0]
	state.citizen_traits[Citizens.chief(state, tribe)] = "wise|devout"
	assert_eq(Citizens.chief_effect(state, tribe, "starve"), 0.6)
	assert_eq(Citizens.chief_effect(state, tribe, "faith"), 0.04)
	assert_eq(Citizens.chief_effect(state, tribe, "war"), 1.0, "no war trait")
	assert_eq(Citizens.chief_effect(state, tribe, "relation"), 0.0)


func test_split_and_merge_move_citizens() -> void:
	var state := WorldState.create(42)
	state.tribe_population[0] = 90
	CitizenSystem.new().update(state)
	var parent := state.tribe_names[0]
	var before := state.citizens_of(parent).size()
	var child := state.tribe_names[state.split_tribe(0, 45)]
	var moved := state.citizens_of(child).size()
	assert_true(moved > 0, "some citizens leave with the new tribe")
	assert_eq(state.citizens_of(parent).size() + moved, before, "nobody is lost")
	assert_true(Citizens.chief(state, parent) != -1, "the old chief stays")
	state.move_citizens(child, parent)
	state.remove_tribe(state.tribe_index(child))
	assert_eq(state.citizens_of(parent).size(), before, "a merge keeps everyone")


func test_describe_gives_the_inspector_everything() -> void:
	var sim := Simulation.create(5)
	sim.advance(80 * WorldState.MONTHS_PER_YEAR)
	var info := Citizens.describe(sim.state, 0)
	for key: String in ["name", "age", "is_chief", "traits", "tribe", "needs", "mood", "drinks_from", "neighbors"]:
		assert_true(info.has(key), "has " + key)
	assert_eq((info["needs"] as Dictionary).size(), Needs.NAMES.size())
