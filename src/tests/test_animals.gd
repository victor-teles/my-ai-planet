extends TestCase
## Wild animals are individuals. Same seed, same herds; a kill is that animal's meat.


func test_seed_42_herds_match_the_species_table() -> void:
	var state := Simulation.create(42).state
	var biome := String(state.world["biome"])
	var wild := Species.wild_in(biome)
	assert_true(not wild.is_empty(), "seed 42 has a biome with game")
	var people := {}
	for id: int in state.person_ids:
		people[id] = true
	for species_id: String in wild:
		var info := Species.get_species(species_id)
		var count := 0
		var sexes := PackedStringArray()
		for i: int in state.animal_ids.size():
			if state.animal_species[i] != species_id:
				continue
			count += 1
			sexes.append(state.animal_sex[i])
			assert_eq(state.animal_genomes[i].size(), 24)
			assert_true(state.animal_sex[i] == "f" or state.animal_sex[i] == "m")
			assert_true(state.animal_condition[i] >= 70 and state.animal_condition[i] <= 100)
			var age := -state.animal_born[i]
			var span := int(info["lifespan"]) * WorldState.DAYS_PER_YEAR
			assert_true(age >= 0 and age <= span, "%s age %d" % [species_id, age])
			assert_true(not people.has(state.animal_ids[i]), "animal id collides with a person")
			assert_true(state.animal_ids[i] >= WorldState.ANIMAL_ID_START)
		assert_eq(count, int(info["herd"]), species_id)
		for n: int in range(1, sexes.size()):
			assert_ne(sexes[n], sexes[n - 1], "%s alternates sex" % species_id)
	for species_id: String in Species.domestic_ids():
		assert_true(species_id not in Array(state.animal_species), "%s is not seeded" % species_id)
	assert_eq(state.animal_ids.size(), _herd_total(wild))


func test_same_seed_matches_at_the_start_and_after_two_years() -> void:
	var a := Simulation.create(42)
	var b := Simulation.create(42)
	assert_eq(a.state.checksum(), b.state.checksum(), "tick 0")
	a.advance(2 * WorldState.DAYS_PER_YEAR)
	b.advance(2 * WorldState.DAYS_PER_YEAR)
	assert_eq(a.state.checksum(), b.state.checksum(), "year 2")


func test_save_and_load_restores_the_herd() -> void:
	var sim := Simulation.create(42)
	sim.advance(40)
	var path := "user://test_animals.json"
	assert_eq(sim.save_to(path), OK)
	var loaded := Simulation.load_from(path)
	assert_true(loaded != null, "save should load")
	if loaded == null:
		return
	assert_eq(loaded.state.checksum(), sim.state.checksum())
	assert_eq(loaded.state.animal_ids.size(), sim.state.animal_ids.size())
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var data := sim.state.to_dict()
	for key: String in ["animal_ids", "animal_species", "animal_genomes", "animal_born", "animal_sex", "animal_condition", "next_animal_id", "animal_seeded", "animal_wiped"]:
		data.erase(key)
	var bare := WorldState.from_dict(data)
	assert_true(bare != null)
	assert_eq(bare.animal_ids.size(), 0)
	assert_eq(bare.animal_genomes.size(), 0)
	assert_eq(bare.animal_species.size(), 0)
	assert_eq(bare.animal_seeded.size(), 0)


func test_a_wolf_kills_the_slower_deer() -> void:
	var state := WorldState.new()
	state.rng = SimRng.new(1)
	state.tick = 0
	var slow := state.add_animal("deer", "f", 0, _genome(0), 100)
	var fast := state.add_animal("deer", "m", 0, _genome(255), 100)
	var wolf := state.add_animal("wolf", "f", 0, _genome(128), 90)
	var slow_id := state.animal_ids[slow]
	var fast_id := state.animal_ids[fast]
	var wolf_id := state.animal_ids[wolf]
	AnimalSystem.new().update(state)
	assert_eq(state.animal_ids.size(), 2)
	assert_true(_has_id(state, fast_id), "the fast deer lives")
	assert_true(_has_id(state, wolf_id), "the wolf lives")
	assert_true(not _has_id(state, slow_id), "the slow deer was eaten")


func test_overhunt_can_wipe_a_prey_species() -> void:
	var state := Simulation.create(42).state
	var before := _prey_counts(state)
	assert_true(not before.is_empty(), "the valley starts with prey")
	for _day: int in 60:
		state.tribe_work[0]["hunter"] = 8000.0
		EconomySystem.new().update(state)
		state.settle()
		state.tick += 1
	var after := _prey_counts(state)
	var wiped_id := ""
	for species_id: String in before:
		if int(before[species_id]) > 0 and int(after.get(species_id, 0)) == 0:
			wiped_id = species_id
			break
	assert_true(wiped_id != "", "a prey species reached 0: %s -> %s" % [str(before), str(after)])
	var logged := false
	for event: Dictionary in state.events:
		if String(event["type"]) != "hunt":
			continue
		var data: Dictionary = event["data"]
		if data.get("wiped", false) == true and String(data.get("species", "")) == wiped_id:
			logged = true
	assert_true(logged, "a wipe event for %s" % wiped_id)


func test_a_kill_adds_that_animals_meat() -> void:
	var state := _one_slow_deer()
	var deer := state.animal_ids[0]
	var work := ceili(1.0 / AnimalSystem._hunt_chance(0.0))
	var expected := float(work) * EconomySystem.RATES["hunter"] * EconomySystem.HUNT_SEASON[state.month()] * WorldGen.rate(state.world, "hunt")
	var before := state.tribe_food[0]
	var meat := AnimalSystem.meat_from_hunt(state, 0, float(work))
	assert_eq(meat, expected)
	assert_eq(state.tribe_food[0], before + expected)
	assert_true(not _has_id(state, deer))
	assert_eq(_prey_total(state), 0)
	# The economy's own day, with that same work written into the tribe.
	var hunted := _one_slow_deer()
	var target := hunted.animal_ids[0]
	hunted.tribe_work[0]["hunter"] = float(work)
	EconomySystem.new().update(hunted)
	assert_true(not _has_id(hunted, target), "the economy's hunt removes the deer")


## Evade 1 is a rare shot. A half-full seeded herd pays half the daily rate.
func test_hunt_chance_is_small_and_a_half_herd_pays_half() -> void:
	var chance := AnimalSystem._hunt_chance(1.0)
	assert_true(chance >= 0.0008 and chance <= 0.0012, "evade 1 chance %s" % chance)
	assert_eq(AnimalSystem._hunt_chance(0.0), AnimalSystem.HUNT_EASY)
	assert_true(AnimalSystem._hunt_chance(2.0) < chance, "a fast wary animal is harder")
	var state := Simulation.create(42).state
	var i := state.animal_ids.size() - 1
	while i >= 0 and AnimalSystem.prey_count(state) > 9:
		if _is_prey(state, i):
			state.remove_animal(i)
		i -= 1
	state.animal_prey_seeded = 18
	assert_eq(AnimalSystem.prey_count(state), 9)
	assert_eq(AnimalSystem.hunt_fullness(state), 0.5)
	var before := state.tribe_food[0]
	var meat := AnimalSystem.meat_from_hunt(state, 0, 4.0)
	var expected := 4.0 * EconomySystem.RATES["hunter"] * EconomySystem.HUNT_SEASON[state.month()] * WorldGen.rate(state.world, "hunt") * 0.5
	assert_eq(meat, expected)
	assert_eq(state.tribe_food[0], before + expected)


## More hunter-days remove more animals. A light hunt leaves the herd alive.
func test_more_hunt_work_removes_more_prey() -> void:
	var heavy := Simulation.create(42).state
	var light := Simulation.create(42).state
	var start := _prey_total(heavy)
	for _day: int in 90:
		AnimalSystem.meat_from_hunt(heavy, 0, 400.0)
		heavy.tick += 1
		AnimalSystem.meat_from_hunt(light, 0, 1.0)
		light.tick += 1
	var heavy_left := _prey_total(heavy)
	var light_left := _prey_total(light)
	assert_true(start - heavy_left > start - light_left, "heavier work removes more prey: %d vs %d from %d" % [start - heavy_left, start - light_left, start])
	assert_true(light_left > 0, "a light hunt left no prey: %d" % light_left)


## Seed 42, year 5: pop 57, prey 17 (horse 10, goat 7), food eaten at least 72623.7, none wiped.
## Food eaten is a lower bound: the stock at each dawn, before that day's gathering.
func test_seed_42_year_5_still_has_prey_and_food() -> void:
	var sim := Simulation.create(42)
	var eaten := 0.0
	for _day: int in 5 * WorldState.DAYS_PER_YEAR:
		var stock := 0.0
		for t: int in sim.state.tribe_count():
			stock += sim.state.tribe_food[t]
		var demand := 0.0
		for p: int in sim.state.person_ids.size():
			demand += float(EconomySystem.EATS[People.stage(sim.state, p)])
		eaten += minf(demand, stock)
		sim.advance(1)
	var prey := _prey_total(sim.state)
	var counts := _prey_counts(sim.state)
	print("    year 5 seed 42: pop %d, prey %d %s, food eaten at least %.1f, wiped %s" % [
		sim.state.total_population(), prey, str(counts), eaten, str(Array(sim.state.animal_wiped)),
	])
	assert_true(sim.state.total_population() > 40, "population %d" % sim.state.total_population())
	assert_true(eaten > 0.0, "food eaten")
	assert_true(prey > 0, "prey left: %s wiped %s" % [str(counts), str(Array(sim.state.animal_wiped))])


func _one_slow_deer() -> WorldState:
	var state := Simulation.create(42).state
	while state.animal_ids.size() > 0:
		state.remove_animal(state.animal_ids.size() - 1)
	var genome := _genome(0)
	var size_at := Species.animal_table().index_of("size") * 2
	genome[size_at] = 180
	genome[size_at + 1] = 180
	state.add_animal("deer", "f", state.tick, genome, 80)
	state.animal_prey_seeded = 1
	return state


func _genome(speed: int) -> PackedByteArray:
	var genome := PackedByteArray()
	genome.resize(24)
	var at := Species.animal_table().index_of("speed") * 2
	genome[at] = speed
	genome[at + 1] = speed
	return genome


func _has_id(state: WorldState, id: int) -> bool:
	return id in Array(state.animal_ids)


func _herd_total(wild: Array[String]) -> int:
	var total := 0
	for species_id: String in wild:
		total += int(Species.get_species(species_id)["herd"])
	return total


func _prey_counts(state: WorldState) -> Dictionary:
	var counts := {}
	for i: int in state.animal_ids.size():
		if not _is_prey(state, i):
			continue
		var species_id := state.animal_species[i]
		counts[species_id] = int(counts.get(species_id, 0)) + 1
	return counts


func _prey_total(state: WorldState) -> int:
	var total := 0
	for i: int in state.animal_ids.size():
		if _is_prey(state, i):
			total += 1
	return total


func _is_prey(state: WorldState, index: int) -> bool:
	var info := Species.get_species(state.animal_species[index])
	if String(info.get("diet", "")) == "predator":
		return false
	return "meat" in info.get("gives", [])
