extends TestCase
## Procedural islands, the ages, and how societies form, darken, break and end.

## Tests that take over 15 seconds; scripts/test.sh --quick skips them.
const SLOW := ["test_a_cruel_regime_breeds_protest_then_revolution_or_repression"]


func test_seeds_make_different_islands() -> void:
	var biomes := {}
	var shapes := {}
	for seed_value: int in 40:
		var world := WorldGen.generate(seed_value)
		biomes[world["biome"]] = true
		shapes[world["island"]["radius"]] = true
		assert_true(int(world["island"]["springs"]) >= 1, "every island has a spring")
		assert_true((world["peoples"] as Array).size() >= 1, "and someone to live on it")
	assert_eq(biomes.size(), WorldGen.BIOME_ORDER.size(), "every biome turns up")
	assert_true(shapes.size() > 30, "and no two islands are the same shape")
	assert_eq(WorldGen.generate(9), WorldGen.generate(9), "the same seed makes the same island")


func test_founding_peoples_bring_their_own_cultures() -> void:
	for seed_value: int in 30:
		var world := WorldGen.generate(seed_value)
		if (world["peoples"] as Array).size() < 2:
			continue
		var state := WorldState.create(seed_value)
		assert_eq(state.tribe_count(), (world["peoples"] as Array).size(), "one tribe per people")
		assert_ne(state.tribe_culture[0], state.tribe_culture[1], "with cultures of their own")
		return
	assert_true(false, "some seed lands two peoples")


func test_ages_follow_their_gate_techs() -> void:
	var state := WorldState.create(42, 1)
	assert_eq(state.age_of(0), 0)
	for tech: String in ["copper_working", "bronze"]:
		state.learn(0, tech)
	assert_eq(state.age_of(0), 1, "bronze opens the Age of Bronze")
	assert_true(state.tech_bonus(0, "war") > 1.0, "and bronze weapons")
	var world := {"ores": {"tin": 0.0}}
	assert_eq(Knowledge.scarcity("bronze", world), Knowledge.NO_ORE, "no tin, little bronze")
	assert_eq(Knowledge.scarcity("writing", world), 1.0, "writing needs no ore")


func test_laws_replace_and_exclude_each_other() -> void:
	var state := WorldState.create(42, 1)
	SocietySystem.enact(state, 0, "elder_council")
	assert_true(Society.flag(state, 0, "elections"), "the council chooses")
	for tech: String in ["copper_working", "bronze", "writing", "mathematics", "philosophy", "iron_working"]:
		state.learn(0, tech)
	assert_true("assembly" in SocietySystem.available(state, 0))
	SocietySystem.enact(state, 0, "assembly")
	assert_true(not Society.has_law(state, 0, "elder_council"), "the assembly replaces the council of elders")
	assert_true("elder_council" not in SocietySystem.available(state, 0), "and it can't come back beside it")
	var before := Society.effect(state, 0, "war")
	SocietySystem.enact(state, 0, "standing_army")
	assert_true(Society.effect(state, 0, "war") > before, "the laws' sums follow new laws at once")
	SocietySystem.repeal(state, 0, "standing_army")
	assert_eq(Society.effect(state, 0, "war"), before, "and repeals")


func test_freedom_falls_as_control_rises() -> void:
	var state := WorldState.create(42, 1)
	var free := Society.freedom(state, 0)
	for tech: String in ["copper_working", "bronze", "writing", "pottery", "rites", "steam_power", "iron_working", "mathematics", "telegraph"]:
		state.learn(0, tech)
	SocietySystem.enact(state, 0, "secret_police")
	SocietySystem.enact(state, 0, "emergency_powers")
	assert_true(Society.control(state, 0) > 30)
	assert_true(Society.freedom(state, 0) < free - 30, "a police state is not free")
	assert_true(Society.dystopia(state, 0) > 20, "it slides toward dystopia")


func test_wealth_is_inherited() -> void:
	var state := WorldState.create(42, 1)
	var parent := -1
	for p: int in state.person_ids.size():
		if not People.children_of(state, state.person_ids[p]).is_empty() and state.person_partners[p] != -1:
			parent = p
			break
	assert_true(parent != -1, "a founder with children")
	var children := People.children_of(state, state.person_ids[parent]).filter(func(id: int) -> bool: return state.is_alive(id))
	var before := 0
	for id: int in children:
		before += state.person_wealth[state.index_of(id)]
	state.person_wealth[parent] = 100 * children.size()
	state.kill_person(parent, "old age")
	var after := 0
	for id: int in children:
		after += state.person_wealth[state.index_of(id)]
	assert_eq(after - before, 100 * children.size(), "the children share what the parent left")


func test_a_cruel_regime_breeds_protest_then_revolution_or_repression() -> void:
	var outcomes := {}
	var ruled := 0
	for seed_value: int in [3, 5, 8, 13]:
		var sim := Simulation.create(seed_value, 1)
		var state := sim.state
		sim.advance(25 * WorldState.DAYS_PER_YEAR)
		# One small band can starve in a bad drought; a dead island has no regime to hate.
		if state.tribe_count() == 0:
			continue
		ruled += 1
		# A hated regime: everyone resents it, nobody believes in it.
		for p: int in state.person_ids.size():
			state.person_loyalty[p] = 5
		state.tribe_legitimacy[0] = 5
		state.tribe_unrest[0] = 90
		var seen := state.next_event_id
		for month: int in 36:
			state.tribe_unrest[0] = maxi(state.tribe_unrest[0], 85)
			for p: int in state.person_ids.size():
				if state.person_ids[p] != state.tribe_chiefs[0]:
					state.person_loyalty[p] = mini(state.person_loyalty[p], 10)
			sim.advance(WorldState.DAYS_PER_MONTH)
		for event: Dictionary in state.events:
			if int(event["id"]) >= seen and String(event["type"]) in ["protests", "concession", "crackdown", "revolution", "uprising_crushed"]:
				outcomes[event["type"]] = true
	assert_true(ruled >= 3, "most of the four bands live 25 years: %d" % ruled)
	assert_true(outcomes.has("protests"), "anger fills the square: %s" % str(outcomes.keys()))
	assert_true(outcomes.has("revolution") or outcomes.has("uprising_crushed") or outcomes.has("concession") or outcomes.has("crackdown"), "and the rulers answer it")


func test_revolution_tears_down_the_dark_laws() -> void:
	var state := WorldState.create(42, 1)
	for tech: String in ["copper_working", "bronze", "writing", "pottery", "rites", "steam_power", "iron_working", "mathematics", "telegraph"]:
		state.learn(0, tech)
	SocietySystem.enact(state, 0, "secret_police")
	SocietySystem.enact(state, 0, "hereditary_rule")
	var old_ruler := state.tribe_chiefs[0]
	var leader := -1
	for p: int in state.person_ids.size():
		if People.is_adult(state, p) and state.person_ids[p] != old_ruler:
			leader = p
			break
	var crisis := CrisisSystem.new()
	crisis._revolution(state, 0, leader, [])
	assert_ne(state.tribe_chiefs[0], old_ruler, "the ruler falls")
	assert_true(not Society.has_law(state, 0, "secret_police"), "the secret police are disbanded")
	assert_true(not Society.has_law(state, 0, "hereditary_rule"), "and nobody rules by birth")
	assert_eq(state.tribe_dynasty[0], "")


func test_destiny_comes_when_it_holds_for_long_enough() -> void:
	var state := WorldState.create(42, 1)
	for tech: String in Knowledge.ORDER:
		state.learn(0, tech)
	for law: String in ["surveillance_net", "secret_police", "emergency_powers", "social_credit"]:
		SocietySystem.enact(state, 0, law)
	state.tribe_power[0]["ruler"] = 90
	state.tribe_fear[0] = 80
	assert_true("panopticon" in DestinySystem.conditions(state, 0), "the island looks headed for the Panopticon: %s" % str(Society.metrics(state, 0)))
	var system := DestinySystem.new()
	for year: int in DestinySystem.HOLD_YEARS:
		assert_true(state.destiny.is_empty(), "not yet, in year %d" % year)
		system.update(state)
	assert_eq(String(state.destiny.get("kind", "")), "panopticon", "after fifteen years, it is the island's destiny")


func test_birth_permits_refuse_carriers_of_frailty() -> void:
	var state := WorldState.create(42, 1)
	var woman := -1
	var man := -1
	for p: int in state.person_ids.size():
		if state.person_partners[p] != -1 and People.is_female(state, p):
			woman = p
			man = state.index_of(state.person_partners[p])
			break
	state.person_loyalty[woman] = 80
	state.person_loyalty[man] = 80
	state.person_genomes[man][Genetics.gene_index("frailty") * 2] = 0 # one frail copy: a carrier
	assert_true(Genetics.frailty_copies(state.person_genomes[man]) > 0, "he carries frailty")
	assert_true(not LifeSystem._permitted(state, woman, man), "the state refuses them")
	assert_true(String((state.lives[str(state.person_ids[woman])] as Array)[-1]["text"]).begins_with("Was refused a birth permit"))


func test_nobles_marry_nobles_where_the_law_says_so() -> void:
	# The first island (from seed 42 on) whose founding band has two singles who could court.
	var state: WorldState
	var a := -1
	var b := -1
	for seed_value: int in range(42, 62):
		state = WorldState.create(seed_value, 1)
		var singles: Array[int] = []
		for p: int in state.person_ids.size():
			if state.person_partners[p] == -1 and People.is_adult(state, p) and state.person_attraction[p] == 0:
				singles.append(p)
		for p: int in singles:
			for q: int in singles:
				if state.person_sexes[p] != state.person_sexes[q] and SocialSystem._could_court(state, p, q):
					a = p
					b = q
		if a != -1:
			break
	assert_true(a != -1, "two singles who could court")
	if a == -1:
		return
	state.person_status[a] = "noble"
	assert_true(SocialSystem._could_court(state, a, b), "love can cross the line without the law")
	state.pass_law(0, "class_marriage")
	assert_true(not SocialSystem._could_court(state, a, b), "but not under it")


func test_political_miracles() -> void:
	var state := WorldState.create(42, 1)
	var tribe := state.tribe_names[0]
	state.influence = WorldState.MAX_INFLUENCE
	var ruler := state.tribe_chiefs[0]
	var legitimacy := state.tribe_legitimacy[0]
	assert_true(Miracles.cast(state, "sanctify", tribe))
	assert_true(state.tribe_legitimacy[0] > legitimacy, "the blessed rule seems the will of heaven")
	state.influence = WorldState.MAX_INFLUENCE
	assert_true(Miracles.cast(state, "awaken", tribe))
	assert_true(state.tribe_legitimacy[0] < legitimacy + 30, "open eyes see the rulers plainly")
	state.influence = WorldState.MAX_INFLUENCE
	assert_true(Miracles.cast(state, "smite", tribe))
	assert_true(not state.is_alive(ruler), "the lightning strikes the ruler")
	assert_eq(String(state.dead[str(ruler)]["cause"]), "lightning")


func test_dilemmas_can_pass_and_strike_down_laws() -> void:
	var state := WorldState.create(42, 1)
	var tribe := state.tribe_names[0]
	var card := Dilemma.from_proposal({
		"title": "The Elders Ask", "situation": "The old of the tribe want a say in how it is ruled, and the chief is uneasy.", "tribe": tribe,
		"choices": [
			{"label": "Give them a council", "hint": "", "effects": [{"type": "law", "tribe": tribe, "amount": 5, "law": "elder_council"}]},
			{"label": "Make it a police state", "hint": "", "effects": [{"type": "law", "tribe": tribe, "amount": 1, "law": "made_up_law"}, {"type": "unrest", "tribe": tribe, "amount": 99}]},
		],
	}, state)
	assert_true(card != null)
	assert_eq(float(card.choices[0]["effects"][0]["amount"]), 1.0, "amounts are clamped")
	assert_eq((card.choices[1]["effects"] as Array).size(), 1, "laws that don't exist are dropped")
	card.choose(state, 0)
	assert_true(Society.has_law(state, 0, "elder_council"), "the god's choice becomes law")


func test_society_prophecies_are_measured() -> void:
	var state := WorldState.create(42, 1)
	assert_eq(Prophecy.measure("highest_age", state), 0)
	assert_eq(Prophecy.measure("vassal_count", state), 0)
	state.learn(0, "copper_working")
	state.learn(0, "bronze")
	assert_eq(Prophecy.measure("highest_age", state), 1)
	var prophecy := Prophecy.from_proposal({"text": "Iron will come.", "metric": "highest_age", "op": ">=", "value": 2, "years_from_now": 30}, state)
	assert_true(prophecy != null and prophecy.deadline_year == 30)


func test_late_ages_stay_deterministic_through_save_and_load() -> void:
	var original := Simulation.create(11)
	for t: int in original.state.tribe_count():
		for tech: String in Knowledge.ORDER:
			if int(Knowledge.TECHS[tech]["age"]) <= 3:
				original.state.learn(t, tech)
	original.advance(12 * WorldState.DAYS_PER_YEAR + 45)
	var path := scratch_path("test_society_save.json")
	assert_eq(original.save_to(path), OK)
	var loaded := Simulation.load_from(path)
	assert_true(loaded != null, "the save loads")
	if loaded == null:
		return
	assert_eq(loaded.state.checksum(), original.state.checksum(), "right after loading")
	original.advance(8 * WorldState.DAYS_PER_YEAR)
	loaded.advance(8 * WorldState.DAYS_PER_YEAR)
	assert_eq(loaded.state.checksum(), original.state.checksum(), "factories, laws and crises play out the same")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
