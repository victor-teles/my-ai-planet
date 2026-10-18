extends TestCase

const FakeProvider := preload("res://tests/fixtures/ai/fake_provider.gd")


func _session(seed_value: int = 42) -> Session:
	return Session.new(Simulation.create(seed_value), Oracle.new(OfflineTemplatesProvider.new()))


func test_full_loop_prophecy_to_reveal_to_next() -> void:
	var session := _session()
	await session.begin()
	assert_eq(session.phase, Session.Phase.PLAYING)
	assert_true(session.sim.state.prophecy != null, "a prophecy is active")
	var years := 0
	while session.phase in [Session.Phase.PLAYING, Session.Phase.DECIDING] and years < Prophecy.MAX_YEARS + 1:
		if session.phase == Session.Phase.DECIDING:
			session.choose(0)
		session.advance(WorldState.DAYS_PER_YEAR)
		years += 1
	# The offline chronicle answers immediately, so the reveal is already up.
	assert_eq(session.phase, Session.Phase.REVEAL)
	assert_true(session.sim.state.resolved_prophecy.status != Prophecy.Status.PENDING, "prophecy resolved")
	assert_true(String(session.chronicle.get("text", "")).length() > 40, "chronicle written: %s" % session.chronicle)
	var tick := session.sim.state.tick
	assert_eq(session.advance(WorldState.DAYS_PER_MONTH), 0, "time is stopped during the reveal")
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
	var food := state.tribe_food[0]
	assert_true(session.cast_miracle("harvest", tribe), "harvest cast")
	assert_eq(state.influence, before - 2.0)
	assert_eq(state.tribe_food[0], snappedf(food + state.tribe_population[0] * Miracles.HARVEST_DAYS, WorldState.FLOAT_STEP))
	assert_eq(state.kindness, 1)
	assert_true(not session.cast_miracle("plague", "Nobody"), "needs a real tribe")
	state.influence = 10.0
	var people := state.total_population()
	assert_true(session.cast_miracle("plague", tribe))
	var plague: Dictionary = state.events[-1]["data"]
	assert_true(int(plague["deaths"]) > 0, "the plague takes people")
	assert_eq(state.total_population(), people - int(plague["deaths"]))
	var plague_deaths := state.events.filter(func(event: Dictionary) -> bool: return event["type"] == "death" and event["data"]["cause"] == "plague")
	assert_eq(plague_deaths.size(), int(plague["deaths"]), "each death is logged by name")
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
	sim.advance(WorldState.DAYS_PER_YEAR)
	assert_eq(state.drought_months_left, 0, "no drought during the blessing")


func test_muse_inspires_a_discovery() -> void:
	var state := WorldState.create(42)
	state.influence = 10.0
	var tribe := state.tribe_names[0]
	var known := state.tribe_knowledge[0].size()
	assert_true(Miracles.cast(state, "muse", tribe))
	assert_eq(state.tribe_knowledge[0].size(), known + 1, "something new is known")
	var types := state.events.map(func(event: Dictionary) -> String: return event["type"])
	assert_true("miracle" in types and "discovery" in types)
	assert_eq(state.influence, 10.0 - float(Miracles.DEFINITIONS["muse"]["cost"]))
	for k: int in Knowledge.ORDER.size():
		state.influence = 10.0
		Miracles.cast(state, "muse", tribe)
	assert_true(not Miracles.why_not(state, "muse", tribe).is_empty(), "no muse once everything is known")


func test_prophecy_survives_save_and_load() -> void:
	var session := _session(5)
	await session.begin()
	var path := "user://test_session_save.json"
	session.sim.save_to(path)
	var loaded := Simulation.load_from(path)
	assert_eq(loaded.state.prophecy.text, session.sim.state.prophecy.text)
	assert_eq(loaded.state.checksum(), session.sim.state.checksum())
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_dilemma_appears_and_choice_applies() -> void:
	var session := _session(42)
	await session.begin()
	var years := 0
	while session.phase != Session.Phase.DECIDING and years < 40:
		if session.phase == Session.Phase.REVEAL:
			await session.continue_after_reveal()
		session.advance(WorldState.DAYS_PER_YEAR)
		years += 1
	assert_eq(session.phase, Session.Phase.DECIDING, "a dilemma should come within 40 years")
	if session.dilemma == null:
		return
	assert_true(session.dilemma.choices.size() >= 2, "at least two choices")
	var tick := session.sim.state.tick
	assert_eq(session.advance(WorldState.DAYS_PER_MONTH), 0, "time stops while deciding")
	session.choose(0)
	assert_eq(session.phase, Session.Phase.PLAYING)
	assert_eq(session.sim.state.tick, tick)
	assert_eq(session.sim.state.events[-1]["type"], "dilemma", "the choice is recorded for the chronicle")


func test_dilemma_rejects_unknown_tribes_and_clamps() -> void:
	var state := WorldState.create(42)
	var real := state.tribe_names[0]
	var proposal := {
		"title": "Test", "situation": "Something happens.", "tribe": real,
		"choices": [
			{"label": "A", "hint": "", "effects": [{"type": "food", "tribe": real, "amount": 99}, {"type": "food", "tribe": "Ghosts", "amount": 1}]},
			{"label": "B", "hint": "", "effects": [{"type": "teleport", "tribe": "", "amount": 1}]},
		],
	}
	var dilemma := Dilemma.from_proposal(proposal, state)
	assert_true(dilemma != null)
	assert_eq(dilemma.choices[0]["effects"].size(), 1, "effect on an unknown tribe dropped")
	assert_eq(dilemma.choices[0]["effects"][0]["amount"], 4.0, "amount clamped")
	assert_eq(dilemma.choices[1]["effects"].size(), 0, "unknown effect type dropped")
	proposal["tribe"] = "Ghosts"
	assert_true(Dilemma.from_proposal(proposal, state) == null, "a dilemma about a tribe that doesn't exist is rejected")


func test_chronicle_text_reaches_the_session_while_chronicling() -> void:
	var session := _session()
	await session.begin()
	var seen: Array[Array] = []
	var collect := func(text: String) -> void: seen.append([session.phase, text])
	session.story_streamed.connect(collect)
	var years := 0
	while session.phase in [Session.Phase.PLAYING, Session.Phase.DECIDING] and years < Prophecy.MAX_YEARS + 1:
		if session.phase == Session.Phase.DECIDING:
			session.choose(0)
		session.advance(WorldState.DAYS_PER_YEAR)
		years += 1
	session.story_streamed.disconnect(collect) # the callback holds the session: don't leak it
	assert_eq(session.phase, Session.Phase.REVEAL)
	assert_true(seen.size() >= 1, "the offline chronicle doesn't stream, but its final text still arrives")
	if seen.is_empty():
		return
	assert_eq(seen[-1][0], Session.Phase.CHRONICLING, "while the Chronicler writes")
	assert_eq(seen[-1][1], session.chronicle["text"])
	assert_eq(session.story_so_far, session.chronicle["text"])
	await session.continue_after_reveal()
	assert_eq(session.story_so_far, "", "cleared for the next chronicle")


func test_a_streaming_chronicle_arrives_in_pieces() -> void:
	var fake := FakeProvider.new({"title": "The Long Rain", "text": "The god sent rain when the springs failed, and the fields grew green again.", "causes": ["the god sent rain"]})
	fake.streaming = true
	fake.free = true
	var oracle := Oracle.new(fake, AICache.new())
	oracle.budget = AIBudget.new()
	oracle.breaker.threshold = 1000 # the fake answers every task with a chronicle: the others fall back
	var session := Session.new(Simulation.create(42), oracle)
	await session.begin()
	var pieces: Array[String] = []
	var collect := func(text: String) -> void:
		if session.phase == Session.Phase.CHRONICLING:
			pieces.append(text)
	session.story_streamed.connect(collect)
	var years := 0
	while session.phase in [Session.Phase.PLAYING, Session.Phase.DECIDING] and years < Prophecy.MAX_YEARS + 1:
		if session.phase == Session.Phase.DECIDING:
			session.choose(0)
		session.advance(WorldState.DAYS_PER_YEAR)
		years += 1
	session.story_streamed.disconnect(collect)
	assert_eq(session.phase, Session.Phase.REVEAL)
	assert_true(pieces.size() >= 3, "the story came in pieces: %s" % [pieces])
	assert_eq(pieces[-1] if not pieces.is_empty() else "", fake.reply["text"])


func test_pacing_hint_reaches_the_prompts() -> void:
	var state := Simulation.create(42).state
	var fake := FakeProvider.new({"text": "The cradles will fill.", "metric": "total_population", "op": ">=", "value": state.total_population() + 30, "years_from_now": 20})
	var oracle := Oracle.new(fake, AICache.new())
	oracle.budget = AIBudget.new()
	var session := Session.new(Simulation.create(42), oracle)
	await session.begin()
	assert_eq(fake.last_request.task, "prophecy")
	assert_true(fake.last_request.system.contains("The story's pacing: %s." % session.drama.pacing_hint()), "the drama's hint is in the prophecy prompt")
	var dilemma := oracle.dilemma_request(session.sim.state, "raise the stakes")
	assert_true(dilemma.system.contains("The story's pacing: raise the stakes."))
	assert_true(oracle.dilemma_request(session.sim.state).system.contains("The story's pacing: %s." % Oracle.DEFAULT_PACING), "a default without a hint")
