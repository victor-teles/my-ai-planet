extends TestCase


func _session(seed_value: int = 42) -> Session:
	return Session.new(Simulation.create(seed_value), Oracle.new(OfflineTemplatesProvider.new()))


func test_full_loop_prophecy_to_reveal_to_next() -> void:
	var session := _session()
	await session.begin()
	assert_eq(session.phase, Session.Phase.PLAYING)
	assert_true(session.sim.state.prophecy != null, "a prophecy is active")
	var years := 0
	while session.phase == Session.Phase.PLAYING and years < 600:
		session.advance(WorldState.MONTHS_PER_YEAR)
		years += 1
	# The offline chronicle answers immediately, so the reveal is already up.
	assert_eq(session.phase, Session.Phase.REVEAL)
	assert_true(session.sim.state.resolved_prophecy.status != Prophecy.Status.PENDING, "prophecy resolved")
	assert_true(String(session.chronicle.get("text", "")).length() > 40, "chronicle written: %s" % session.chronicle)
	var tick := session.sim.state.tick
	assert_eq(session.advance(12), 0, "time is stopped during the reveal")
	assert_eq(session.sim.state.tick, tick)
	await session.continue_after_reveal()
	assert_eq(session.phase, Session.Phase.PLAYING)
	assert_true(session.sim.state.resolved_prophecy == null, "reveal cleared")


func test_miracles_cost_influence_and_set_tone() -> void:
	var session := _session()
	await session.begin()
	var state := session.sim.state
	var tribe := state.tribe_names[0]
	var before := state.influence
	assert_true(session.cast_miracle("harvest", tribe), "harvest cast")
	assert_eq(state.influence, before - 2.0)
	assert_eq(state.kindness, 1)
	assert_true(not session.cast_miracle("plague", "Nobody"), "needs a real tribe")
	state.influence = 10.0
	assert_true(session.cast_miracle("plague", tribe))
	assert_true(session.cast_miracle("drought"))
	assert_eq(state.kindness, -2)
	assert_eq(state.tone(), 3, "cruelty plus a drought darkens the tone")
	assert_eq(state.events[-1]["type"], "miracle")


func test_rain_ends_drought_and_blocks_new_ones() -> void:
	var state := WorldState.create(1)
	state.drought_months_left = 10
	state.influence = 10.0
	assert_true(Miracles.cast(state, "rain"))
	assert_eq(state.drought_months_left, 0)
	var sim := Simulation.new(state)
	sim.advance(WorldState.MONTHS_PER_YEAR)
	assert_eq(state.drought_months_left, 0, "no drought during the blessing")


func test_prophecy_survives_save_and_load() -> void:
	var session := _session(5)
	await session.begin()
	var path := "user://test_session_save.json"
	session.sim.save_to(path)
	var loaded := Simulation.load_from(path)
	assert_eq(loaded.state.prophecy.text, session.sim.state.prophecy.text)
	assert_eq(loaded.state.checksum(), session.sim.state.checksum())
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
