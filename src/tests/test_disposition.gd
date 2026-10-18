extends TestCase
## The god's disposition: how the player intervenes, saved with the world and feeding the tone.


func test_miracles_shape_the_disposition() -> void:
	var state := WorldState.create(42)
	var tribe := state.tribe_names[0]
	assert_eq(state.disposition()["leaning"], "unknown")
	assert_eq(state.disposition()["hand"], "hands-off")
	for id: String in ["rain", "harvest", "muse"]:
		state.influence = WorldState.MAX_INFLUENCE
		assert_true(Miracles.cast(state, id, tribe), id)
	var d := state.disposition()
	assert_eq(d["mercy"], 2)
	assert_eq(d["wrath"], 0)
	assert_eq(d["recent_acts"], 3, "the muse is meddling too")
	assert_eq(d["leaning"], "benevolent")
	assert_eq(d["hand"], "watchful")
	for id: String in ["plague", "plague", "drought"]:
		state.influence = WorldState.MAX_INFLUENCE
		assert_true(Miracles.cast(state, id, tribe), id)
	d = state.disposition()
	assert_eq(d["wrath"], 5)
	assert_eq(d["leaning"], "wrathful")
	assert_eq(d["hand"], "guiding", "six interventions in ten years")
	assert_true(state.disposition_text().begins_with("The god has been wrathful"), state.disposition_text())


func test_meddling_fades_with_the_years() -> void:
	var state := WorldState.create(42)
	for k: int in 8:
		state.record_intervention(0)
	assert_eq(state.disposition()["hand"], "guiding")
	state.tick += WorldState.MEDDLE_YEARS * WorldState.DAYS_PER_YEAR
	assert_eq(state.disposition()["hand"], "hands-off")
	for k: int in WorldState.MAX_GOD_ACTS + 5:
		state.record_intervention(1)
	assert_eq(state.god_act_ticks.size(), WorldState.MAX_GOD_ACTS, "only the latest are kept")
	assert_eq(state.god_mercy, WorldState.MAX_GOD_ACTS + 5, "but every act of mercy counts")


func test_dilemma_choices_lean_merciful_or_wrathful() -> void:
	var state := WorldState.create(42)
	var tribe := state.tribe_names[0]
	var proposal := {
		"title": "The Well", "situation": "The well is failing and the people are thirsty.", "tribe": tribe,
		"choices": [
			{"label": "Send rain", "hint": "", "effects": [{"type": "rain", "tribe": "", "amount": 6}, {"type": "food", "tribe": tribe, "amount": 2}]},
			{"label": "Let them suffer", "hint": "", "effects": [{"type": "kindness", "tribe": "", "amount": -2}, {"type": "law", "tribe": tribe, "amount": 1, "law": "secret_police"}]},
			{"label": "Wait", "hint": "", "effects": [{"type": "influence", "tribe": "", "amount": 1}]},
		],
	}
	var dilemma := Dilemma.from_proposal(proposal, state)
	assert_eq(Dilemma.leaning(dilemma.choices[0]), 2)
	assert_eq(Dilemma.leaning(dilemma.choices[1]), -2)
	assert_eq(Dilemma.leaning(dilemma.choices[2]), 0)
	dilemma.choose(state, 1)
	assert_eq(state.god_wrath, 2)
	assert_eq(state.god_act_ticks.size(), 1)


func test_wrath_darkens_the_tone_more_than_mercy() -> void:
	var kind := WorldState.create(42)
	var cruel := WorldState.create(42)
	for k: int in 3:
		kind.influence = WorldState.MAX_INFLUENCE
		cruel.influence = WorldState.MAX_INFLUENCE
		Miracles.cast(kind, "harvest", kind.tribe_names[0])
		Miracles.cast(cruel, "plague", cruel.tribe_names[0])
	assert_true(cruel.tone() >= kind.tone() + 2, "kind %d, cruel %d" % [kind.tone(), cruel.tone()])
	assert_true(kind.tone() >= 1 and cruel.tone() <= 5)


func test_disposition_survives_save_and_load() -> void:
	var sim := Simulation.create(9)
	sim.advance(2 * WorldState.DAYS_PER_YEAR)
	sim.state.influence = WorldState.MAX_INFLUENCE
	Miracles.cast(sim.state, "plague", sim.state.tribe_names[0])
	sim.advance(WorldState.DAYS_PER_YEAR)
	sim.state.influence = WorldState.MAX_INFLUENCE
	Miracles.cast(sim.state, "rain")
	var path := "user://test_disposition_save.json"
	assert_eq(sim.save_to(path), OK)
	var loaded := Simulation.load_from(path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	assert_eq(loaded.state.disposition(), sim.state.disposition())
	assert_eq(loaded.state.god_act_ticks, sim.state.god_act_ticks)
	assert_eq(loaded.state.god_act_leanings, sim.state.god_act_leanings)
	assert_eq(loaded.state.checksum(), sim.state.checksum())
	sim.advance(3 * WorldState.DAYS_PER_YEAR)
	loaded.advance(3 * WorldState.DAYS_PER_YEAR)
	assert_eq(loaded.state.checksum(), sim.state.checksum(), "and they go on identically")


func test_older_saves_load_with_a_god_of_unknown_nature() -> void:
	var state := WorldState.create(42)
	state.record_intervention(-2)
	var data := state.to_dict()
	for key: String in ["god_mercy", "god_wrath", "god_act_ticks", "god_act_leanings"]:
		data.erase(key)
	var loaded := WorldState.from_dict(JSON.parse_string(JSON.stringify(data)))
	assert_true(loaded != null)
	assert_eq(loaded.disposition()["leaning"], "unknown")
	assert_eq(loaded.god_act_ticks.size(), 0)


func test_same_deeds_give_the_same_world() -> void:
	var a := Simulation.create(11)
	var b := Simulation.create(11)
	for sim: Simulation in [a, b]:
		sim.advance(WorldState.DAYS_PER_YEAR)
		sim.state.influence = WorldState.MAX_INFLUENCE
		Miracles.cast(sim.state, "plague", sim.state.tribe_names[0])
		sim.advance(WorldState.DAYS_PER_YEAR)
	assert_eq(a.state.checksum(), b.state.checksum())
	assert_eq(a.state.disposition_text(), b.state.disposition_text())


func test_asking_the_oracle_never_touches_the_world() -> void:
	var sim := Simulation.create(5)
	sim.advance(8 * WorldState.DAYS_PER_YEAR)
	var before := sim.state.checksum()
	var oracle := Oracle.new(OfflineTemplatesProvider.new(), AICache.new())
	await oracle.request_prophecy(sim.state)
	await oracle.request_dilemma(sim.state)
	await oracle.request_thought(sim.state, 0)
	oracle.prophecy_request(sim.state)
	assert_eq(sim.state.checksum(), before, "the sim's RNG and state are untouched by AI work")
