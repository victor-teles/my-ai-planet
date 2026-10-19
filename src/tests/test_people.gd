extends TestCase


func _event_types(state: WorldState) -> Array:
	return state.events.map(func(event: Dictionary) -> String: return event["type"])


## An adult of the given sex added to a tribe, with fresh genes and traits.
func _adult(state: WorldState, tribe: String, sex: String, years: int = 25) -> int:
	var p := state.add_person(tribe, sex, state.tick - years * WorldState.DAYS_PER_YEAR, Genetics.founder(state.rng, 0), -1, -1, "Testa", "Ana" if sex == "f" else "Bo")
	People.form_traits(state, p)
	return p


func test_founding_band() -> void:
	var state := WorldState.create(42, 1)
	var tribe := state.tribe_names[0]
	var couples := 0
	for p: int in state.person_ids.size():
		var partner := state.index_of(state.person_partners[p])
		if partner != -1:
			assert_eq(state.person_partners[partner], state.person_ids[p], "partners point at each other")
			couples += 1
		assert_true(state.person_homes[p] != -1, "%s has a home" % state.person_names[p])
		assert_eq(state.person_tribes[p], tribe)
		var traits := People.traits_of(state, p)
		assert_eq(traits.size(), 2 if People.age(state, p) >= 15 else 0, "traits once of age (%d years)" % People.age(state, p))
		if state.person_mothers[p] != -1:
			var mother := state.index_of(state.person_mothers[p])
			var father := state.index_of(state.person_fathers[p])
			assert_true(mother != -1 and father != -1, "children have both parents")
			assert_eq(state.person_partners[mother], state.person_fathers[p], "their parents are a couple")
			assert_eq(state.person_generations[p], 2)
	assert_eq(couples, People.FOUNDING_COUPLES * 2)
	assert_true(state.chief_of(tribe) != -1, "the band has a chief")
	assert_eq(state.tribe_population[0], state.person_ids.size())


func test_inheritance_takes_one_copy_from_each_parent() -> void:
	var rng := SimRng.new(5)
	var mother := Genetics.founder(rng, 0)
	var father := Genetics.founder(rng, 3)
	for child: int in 60:
		var heredity := Genetics.inherit(rng, mother, father)
		var genome: PackedByteArray = heredity["genome"]
		var mutated: Array = heredity["mutations"]
		assert_eq(genome.size(), Genetics.GENES.size() * 2)
		for g: int in Genetics.GENES.size():
			if Genetics.GENES[g] in mutated:
				continue
			assert_true(genome[g * 2] in [mother[g * 2], mother[g * 2 + 1]], "first copy of %s from the mother" % Genetics.GENES[g])
			assert_true(genome[g * 2 + 1] in [father[g * 2], father[g * 2 + 1]], "second copy of %s from the father" % Genetics.GENES[g])


func test_frailty_and_narrow_eyes_are_recessive() -> void:
	var genome := Genetics.founder(SimRng.new(1), 0)
	var frail := Genetics.gene_index("frailty") * 2
	genome[frail] = 5
	genome[frail + 1] = 200
	assert_eq(Genetics.frailty_copies(genome), 1)
	assert_true(not Genetics.is_frail(genome), "a carrier is healthy")
	genome[frail + 1] = 10
	assert_true(Genetics.is_frail(genome), "two copies show")
	assert_true(People.max_health(genome, 20) < People.max_health(Genetics.founder(SimRng.new(1), 0), 20) or Genetics.is_frail(Genetics.founder(SimRng.new(1), 0)), "frailty costs health")
	var eyes := Genetics.gene_index("eyes") * 2
	genome[eyes] = 200
	genome[eyes + 1] = 40
	assert_true(not Genetics.has_narrow_eyes(genome))
	genome[eyes + 1] = 140
	assert_true(Genetics.has_narrow_eyes(genome))


func test_genome_hex_round_trip() -> void:
	var genome := Genetics.founder(SimRng.new(9), 2)
	assert_eq(Genetics.from_hex(Genetics.to_hex(genome)), genome)


func test_birth_gives_a_baby_parents_and_a_home() -> void:
	var state := WorldState.create(42, 1)
	var mother := -1
	for p: int in state.person_ids.size():
		if People.is_female(state, p) and state.person_partners[p] != -1:
			mother = p
			break
	var mother_id := state.person_ids[mother]
	var father_id := state.person_partners[mother]
	var home := state.person_homes[mother]
	state.person_baby_fathers[mother] = father_id
	var babies := LifeSystem.give_birth(state, mother)
	assert_true(babies.size() >= 1)
	var baby := state.index_of(babies[0])
	assert_eq(state.person_mothers[baby], mother_id)
	assert_eq(state.person_fathers[baby], father_id)
	assert_eq(state.person_homes[baby], home, "the baby lives with the mother")
	assert_eq(People.age(state, baby), 0)
	assert_eq(state.person_families[baby], state.person_families[state.index_of(father_id)], "takes the father's family name")
	assert_true("birth" in _event_types(state))
	assert_true(not (state.lives[str(babies[0])] as Array).is_empty(), "their life story begins")


func test_death_is_remembered_and_widows_the_partner() -> void:
	var state := WorldState.create(42, 1)
	var p := 0
	while state.person_partners[p] == -1:
		p += 1
	var id := state.person_ids[p]
	var name := state.person_names[p]
	var partner_id := state.person_partners[p]
	var before := state.total_population()
	state.kill_person(p, "accident", {"while": "on the hunt"})
	assert_eq(state.total_population(), before - 1)
	assert_eq(state.tribe_population[0], before - 1)
	assert_true(not state.is_alive(id))
	assert_eq(String(state.dead[str(id)]["cause"]), "accident")
	assert_eq(People.name_of(state, id), name, "the dead are remembered by name")
	var partner := state.index_of(partner_id)
	assert_eq(state.person_partners[partner], -1, "widowed")
	assert_true(state.person_grief[partner] > 0, "the partner grieves")
	var death := state.events.filter(func(event: Dictionary) -> bool: return event["type"] == "death")
	assert_eq(int(death[-1]["data"]["id"]), id)
	for key: String in state.bonds:
		assert_true(not key.split("|").has(str(id)), "their bonds are forgotten")


func test_marriage_in_the_tribe() -> void:
	var state := WorldState.create(42, 1)
	var tribe := state.tribe_names[0]
	var a := _adult(state, tribe, "f")
	var b := _adult(state, tribe, "m")
	SocialSystem.marry(state, a, b)
	assert_eq(state.person_partners[a], state.person_ids[b])
	assert_eq(state.person_partners[b], state.person_ids[a])
	assert_eq(state.events[-1]["type"], "marriage")
	assert_eq(state.person_homes[a], state.person_homes[b], "they share a home")


func test_marriage_across_tribes_moves_the_smaller_side() -> void:
	var state := WorldState.create(42, 1)
	var big := state.tribe_names[0]
	state.add_tribe("Ruu", 1)
	var stayer := _adult(state, big, "f")
	var mover := _adult(state, "Ruu", "m", 30)
	var child := state.add_person("Ruu", "f", state.tick - 5 * WorldState.DAYS_PER_YEAR, Genetics.founder(state.rng, 1), -1, state.person_ids[mover], "Testa", "Kit")
	var relation_before := state.relation(big, "Ruu")
	SocialSystem.marry(state, mover, stayer)
	assert_eq(state.person_tribes[mover], big, "the one from the small tribe moves")
	assert_eq(state.person_tribes[child], big, "young children come along")
	assert_eq(state.tribe_population[state.tribe_index("Ruu")], 0)
	assert_eq(state.relation(big, "Ruu"), relation_before + 8, "the tribes warm to each other")
	assert_eq(String(state.events[-1]["data"]["moved_from"]), "Ruu")


func test_adults_get_jobs_and_youths_apprentice() -> void:
	var sim := Simulation.create(42, 1)
	sim.advance(1) # tick 0 runs the monthly systems
	var state := sim.state
	for p: int in state.person_ids.size():
		var years := People.age(state, p)
		if years >= People.ADULT_AT and years < People.RETIRE_AT:
			assert_true(state.person_jobs[p] in Jobs.DEFINITIONS, "%s (%d) works" % [state.person_names[p], years])
		elif years < WorkSystem.APPRENTICE_AT:
			assert_eq(state.person_jobs[p], "", "children don't work")
	var tribe := state.tribe_names[0]
	var parent := _adult(state, tribe, "m", 35)
	state.person_jobs[parent] = "hunter"
	var youth := state.add_person(tribe, "f", state.tick - 13 * WorldState.DAYS_PER_YEAR, Genetics.founder(state.rng, 0), -1, state.person_ids[parent], "Testa", "Lia")
	WorkSystem.new()._apprentice(state, youth)
	assert_eq(state.person_jobs[youth], "hunter", "learns the father's trade")
	assert_eq(state.events[-1]["type"], "apprentice")


func test_a_home_is_planned_built_and_lived_in() -> void:
	var state := WorldState.create(42, 1)
	var tribe := state.tribe_names[0]
	Dilemma.newcomers(state, tribe, 14) # more people than the tents can sleep
	var beds := Needs.home_capacity(state, tribe)
	assert_true(beds < state.total_population(), "short of beds to begin with")
	Simulation.new(state).advance(WorldState.DAYS_PER_YEAR)
	var types := _event_types(state)
	assert_true("building_started" in types, "the chief starts a project")
	var homes_done := state.events.filter(func(event: Dictionary) -> bool:
		return event["type"] == "building_done" and Buildings.is_home(String(event["data"]["building"])))
	assert_true(not homes_done.is_empty(), "a home is finished within a year")
	assert_true(Needs.home_capacity(state, tribe) > beds, "more beds now")
	WorkSystem.settle_homes(state, 0)
	if Needs.home_capacity(state, tribe) >= state.total_population():
		for p: int in state.person_ids.size():
			assert_true(state.person_homes[p] != -1, "%s has a bed" % state.person_names[p])


func test_settle_homes_beds_everyone_when_there_is_room() -> void:
	var state := WorldState.create(42, 1)
	for p: int in state.person_ids.size():
		state.person_homes[p] = -1
	WorkSystem.settle_homes(state, 0)
	var residents := {}
	for p: int in state.person_ids.size():
		assert_true(state.person_homes[p] != -1, "%s found a bed" % state.person_names[p])
		residents[state.person_homes[p]] = int(residents.get(state.person_homes[p], 0)) + 1
	for b: int in state.building_ids.size():
		assert_true(int(residents.get(state.building_ids[b], 0)) <= Buildings.capacity(state.building_types[b]) + 2, "no home badly overcrowded")


func test_someone_discovers_something() -> void:
	var sim := Simulation.create(42, 1)
	sim.advance(6 * WorldState.DAYS_PER_YEAR)
	var discoveries := sim.state.events.filter(func(event: Dictionary) -> bool: return event["type"] == "discovery")
	assert_true(not discoveries.is_empty(), "seed 42 discovers something within 6 years")
	if not discoveries.is_empty():
		var data: Dictionary = discoveries[0]["data"]
		assert_true(sim.state.knows(sim.state.tribe_index(String(data["tribe"])), String(data["tech"])))
		assert_true(People.name_of(sim.state, int(data["id"])) != "", "by a real person")


func test_split_moves_followers_into_a_new_tribe() -> void:
	var state := WorldState.create(42, 1)
	var old := state.tribe_names[0]
	var leaving: Array[int] = [0, 1, 2, 3, 4, 5]
	var ids: Array[int] = []
	for p: int in leaving:
		ids.append(state.person_ids[p])
	var before := state.total_population()
	var n := RelationsSystem.split_tribe(state, 0, leaving, 0)
	var tribe := state.tribe_names[n]
	assert_eq(state.tribe_population[n], 6)
	assert_eq(state.tribe_population[0] + state.tribe_population[n], before, "nobody is lost")
	for id: int in ids:
		assert_eq(state.person_tribes[state.index_of(id)], tribe)
		assert_true(state.person_homes[state.index_of(id)] != -1, "they carried their tents")
	assert_eq(state.count_buildings(tribe, "tent"), 2)
	assert_eq(state.relation(old, tribe), WorldState.KIN_RELATION)
	assert_eq(state.tribe_chiefs[n], ids[0], "the leader leads")
	assert_eq(state.tribe_knowledge[n], state.tribe_knowledge[0])
	assert_true("tribe_split" in _event_types(state))


func test_describe_gives_the_inspector_everything() -> void:
	var sim := Simulation.create(5, 1)
	sim.advance(10 * WorldState.DAYS_PER_YEAR)
	var info := People.describe(sim.state, 0)
	for key: String in ["name", "age", "role", "is_chief", "traits", "family", "friends", "life_so_far", "tribe", "needs", "doing", "born_with"]:
		assert_true(info.has(key), "has " + key)
	assert_eq((info["needs"] as Dictionary).size(), Needs.NAMES.size())
