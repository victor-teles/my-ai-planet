extends TestCase

## Tests that take over 15 seconds; scripts/test.sh --quick skips them.
const SLOW := ["test_same_seed_gives_same_world", "test_world_lives_and_grows"]

const YEARS := 20


func test_same_seed_gives_same_world() -> void:
	var a := Simulation.create(42)
	var b := Simulation.create(42)
	a.advance(YEARS * WorldState.DAYS_PER_YEAR)
	b.advance(YEARS * WorldState.DAYS_PER_YEAR)
	assert_eq(a.state.checksum(), b.state.checksum())


func test_different_seeds_diverge() -> void:
	var a := Simulation.create(1)
	var b := Simulation.create(2)
	a.advance(WorldState.DAYS_PER_YEAR)
	b.advance(WorldState.DAYS_PER_YEAR)
	assert_ne(a.state.checksum(), b.state.checksum())


func test_save_and_load_continue_identically() -> void:
	var original := Simulation.create(7)
	original.advance(6 * WorldState.DAYS_PER_YEAR + 17) # mid-month, mid-pregnancies
	var path := scratch_path("test_save.json")
	assert_eq(original.save_to(path), OK)
	var loaded := Simulation.load_from(path)
	assert_true(loaded != null, "save should load")
	if loaded == null:
		return
	assert_eq(loaded.state.checksum(), original.state.checksum(), "right after loading")
	original.advance(6 * WorldState.DAYS_PER_YEAR)
	loaded.advance(6 * WorldState.DAYS_PER_YEAR)
	assert_eq(loaded.state.checksum(), original.state.checksum(), "after running both further")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_world_lives_and_grows() -> void:
	# A sanity bound on the balance, not a balance target.
	var sim := Simulation.create(42)
	var founders := sim.state.total_population()
	var counts := {}
	var seen := sim.state.next_event_id - 1
	for decade: int in 6:
		sim.advance(10 * WorldState.DAYS_PER_YEAR)
		for event: Dictionary in sim.state.events:
			if int(event["id"]) > seen:
				counts[event["type"]] = int(counts.get(event["type"], 0)) + 1
		seen = sim.state.next_event_id - 1
	assert_true(sim.state.total_population() > founders, "population should grow over 60 years: %d -> %d" % [founders, sim.state.total_population()])
	for type: String in ["birth", "death", "marriage", "discovery", "building_done", "coming_of_age"]:
		assert_true(int(counts.get(type, 0)) > 0, "some %s in 60 years" % type)
	assert_true(People.max_generation(sim.state) >= 3, "grandchildren of the founders are born")
