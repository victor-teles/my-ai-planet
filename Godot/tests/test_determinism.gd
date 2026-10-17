extends TestCase

const TICKS := 10000 # about 833 years


func test_same_seed_gives_same_world() -> void:
	var a := Simulation.create(42)
	var b := Simulation.create(42)
	a.advance(TICKS)
	b.advance(TICKS)
	assert_eq(a.state.checksum(), b.state.checksum())


func test_different_seeds_diverge() -> void:
	var a := Simulation.create(1)
	var b := Simulation.create(2)
	a.advance(1200)
	b.advance(1200)
	assert_ne(a.state.checksum(), b.state.checksum())


func test_save_and_load_continue_identically() -> void:
	var original := Simulation.create(7)
	original.advance(1500)
	var path := "user://test_save.json"
	assert_eq(original.save_to(path), OK)
	var loaded := Simulation.load_from(path)
	assert_true(loaded != null, "save should load")
	if loaded == null:
		return
	assert_eq(loaded.state.checksum(), original.state.checksum(), "right after loading")
	original.advance(1500)
	loaded.advance(1500)
	assert_eq(loaded.state.checksum(), original.state.checksum(), "after running both further")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_world_stays_alive_and_grows() -> void:
	# A sanity bound on the placeholder balance, not a balance target.
	var sim := Simulation.create(42)
	sim.advance(2400)
	assert_true(sim.state.total_population() > 30, "population should grow over 200 years, got %d" % sim.state.total_population())
	assert_true(sim.state.tribe_count() >= 2, "tribes should split over 200 years")
