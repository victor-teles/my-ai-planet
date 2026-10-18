extends TestCase
## Golden tests for the prompt library: for every saved state in tests/fixtures/golden/ and every
## task, build the exact request the game sends and check its constraints, then check that the
## offline reply and the recorded real replies (tests/fixtures/*.json) still pass every gate.
## MYAIPLANET_REGEN_GOLDEN=1 scripts/test.sh golden rewrites the saved states (see the README there).

const DIR := "res://tests/fixtures/golden/"
const FIXTURES: Array[String] = ["dawn_seed42", "village_seed7_year30", "wrathful_seed3_year60", "dystopia_seed42_late"]
const PLACEHOLDER := "\\{[a-z_]+\\}"
const PACING := "raise the stakes" ## a DramaManager hint, as the session passes it


func _oracle() -> Oracle:
	var oracle := Oracle.new(OfflineTemplatesProvider.new(), AICache.new())
	oracle.gentle = false
	return oracle


func _load(fixture: String) -> WorldState:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIR + fixture + ".json"))
	var state := WorldState.from_dict(data) if data is Dictionary else null
	assert_true(state != null, "%s loads (if the save format changed: MYAIPLANET_REGEN_GOLDEN=1 scripts/test.sh golden)" % fixture)
	return state


## Every request the game can send from this state: [label, request].
func _requests(oracle: Oracle, state: WorldState) -> Array[Array]:
	var requests: Array[Array] = [
		["prophecy", oracle.prophecy_request(state, PACING)],
		["dilemma", oracle.dilemma_request(state, PACING)],
		["chronicle", oracle.chronicle_request(state, _resolved_prophecy(state))],
		["destiny", oracle.destiny_request(_with_destiny(state))],
	]
	for c: int in _people(state):
		requests.append(["thought of %s" % state.person_names[c], oracle.thought_request(state, c)])
	# Every asset kind, for its first and last subject (a founding tribe and the newest).
	for kind: AssetKind in AssetKinds.all():
		var subjects := kind.subjects(state)
		for subject: String in ([subjects[0], subjects[-1]] if subjects.size() > 1 else subjects):
			requests.append(["%s of %s" % [kind.task(), subject], oracle.asset_request(kind, state, subject)])
	return requests


## A chief and a child, when the world has them.
func _people(state: WorldState) -> Array[int]:
	var people: Array[int] = []
	var chief := state.chief_of(state.tribe_names[0])
	people.append(chief if chief != -1 else 0)
	for c: int in state.person_ids.size():
		if People.stage(state, c) == "child":
			people.append(c)
			break
	return people


func _resolved_prophecy(state: WorldState) -> Prophecy:
	if state.resolved_prophecy:
		return state.resolved_prophecy
	var prophecy := Prophecy.new()
	prophecy.text = "The valley will fill with cradles."
	prophecy.metric = "total_population"
	prophecy.op = ">="
	prophecy.target = state.total_population() + 40
	prophecy.start_tick = maxi(state.tick - 10 * WorldState.DAYS_PER_YEAR, 0)
	prophecy.deadline_year = state.year()
	prophecy.status = Prophecy.Status.BROKEN
	prophecy.resolved_tick = state.tick
	return prophecy


func _with_destiny(state: WorldState) -> WorldState:
	if state.destiny.is_empty():
		state.destiny = {"kind": "ashes", "tribe": state.tribe_names[0], "year": state.year()}
	return state


func _check_request(label: String, request: AIRequest, oracle: Oracle, state: WorldState) -> void:
	var task := request.task
	var placeholder := RegEx.create_from_string(PLACEHOLDER)
	for part: String in [request.system, request.prompt]:
		var unfilled := placeholder.search(part)
		assert_true(unfilled == null, "%s: unfilled %s" % [label, unfilled.get_string() if unfilled else ""])
	var size := request.system.length() + request.prompt.length()
	var budget := int(AIPrompts.entry(task)["max_chars"])
	assert_true(size <= budget, "%s: %d characters, over the budget of %d" % [label, size, budget])
	assert_true(request.schema.has("properties"), "%s: the schema loads" % label)
	assert_eq(request.prompt_version, String(oracle.prompt_versions.get(task, AIPrompts.version(task))), label)
	assert_true(request.system.contains("Tone level: %d " % oracle.tone_for(state)), "%s: the tone is in the prompt" % label)
	if request.prompt_version != "v1":
		assert_true(request.system.contains(state.disposition_text()), "%s: the god's disposition is in the prompt" % label)
		assert_true(request.system.contains("Hard limits"), "%s: the content ceiling is in the prompt" % label)
		assert_eq(request.system.contains("Gentle Mode is on"), oracle.gentle, "%s: Gentle Mode line" % label)
	if task in ["prophecy", "dilemma"] and request.prompt_version.trim_prefix("v").to_int() >= 3:
		assert_true(request.system.contains("The story's pacing: %s." % PACING), "%s: the drama's pacing hint is in the prompt" % label)


func _check_offline_reply(label: String, request: AIRequest) -> void:
	var response := await OfflineTemplatesProvider.new().complete(request)
	assert_true(response.ok, "%s: offline answers" % label)
	assert_eq(JsonSchema.validate(response.data, request.schema), PackedStringArray(), "%s: offline reply fits the schema" % label)
	assert_eq(ContentGuard.check(response.data, true), PackedStringArray(), "%s: offline reply is within even the gentle ceiling" % label)
	var kind := AssetKinds.find(request.task)
	if kind:
		assert_true(kind.accept(response.data, request.context) != null, "%s: the offline spec is accepted as it is" % label)


## First, so the other tests read the fresh files.
func test_regenerate_saved_states() -> void:
	if OS.get_environment("MYAIPLANET_REGEN_GOLDEN") != "1":
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	for fixture: String in FIXTURES:
		var state: WorldState = await _generate(fixture)
		var file := FileAccess.open(ProjectSettings.globalize_path(DIR + fixture + ".json"), FileAccess.WRITE)
		file.store_string(state.to_json())
		print("        wrote %s: year %d, %d people, tone %d" % [fixture, state.year(), state.total_population(), state.tone()])


func test_every_prompt_from_every_saved_state() -> void:
	for fixture: String in FIXTURES:
		var state := _load(fixture)
		if state == null:
			continue
		var oracle := _oracle()
		for entry: Array in _requests(oracle, state):
			var label := "%s %s" % [fixture, entry[0]]
			_check_request(label, entry[1], oracle, state)
			await _check_offline_reply(label, entry[1])


func test_gentle_mode_prompts() -> void:
	for fixture: String in FIXTURES:
		var state := _load(fixture)
		if state == null:
			continue
		var oracle := _oracle()
		oracle.gentle = true
		assert_true(oracle.tone_for(state) <= Oracle.GENTLE_TONE, "%s: Gentle Mode caps the tone" % fixture)
		for entry: Array in _requests(oracle, state):
			_check_request("%s gentle %s" % [fixture, entry[0]], entry[1], oracle, state)


func test_old_prompt_versions_still_load() -> void:
	var state := _load(FIXTURES[1])
	if state == null:
		return
	for task: String in AIPrompts.tasks():
		var versions := AIPrompts.versions(task)
		assert_true(AIPrompts.version(task) in versions, "%s: the manifest's version has files" % task)
		assert_true("v1" in versions, "%s: v1 is kept" % task)
		for version: String in versions:
			var oracle := _oracle()
			oracle.prompt_versions[task] = version
			for entry: Array in _requests(oracle, state):
				if (entry[1] as AIRequest).task == task:
					_check_request("%s %s" % [version, entry[0]], entry[1], oracle, state)


func test_the_sim_accepts_offline_answers_from_every_saved_state() -> void:
	for fixture: String in FIXTURES:
		var state := _load(fixture)
		if state == null:
			continue
		for gentle: bool in [false, true]:
			var oracle := _oracle()
			oracle.gentle = gentle
			var label := "%s%s" % [fixture, " (gentle)" if gentle else ""]
			assert_true(await oracle.request_prophecy(state) != null, label + ": prophecy")
			assert_true(await oracle.request_dilemma(state) != null, label + ": dilemma")
			assert_true(not (await oracle.request_chronicle(state, _resolved_prophecy(state))).is_empty(), label + ": chronicle")
			assert_true(not (await oracle.request_destiny(_with_destiny(state))).is_empty(), label + ": destiny")
			for c: int in _people(state):
				assert_true(not (await oracle.request_thought(state, c)).is_empty(), label + ": thought")
			for kind: AssetKind in AssetKinds.all():
				for subject: String in kind.subjects(state):
					assert_true(not (await oracle.request_asset(kind, state, subject)).is_empty(), "%s: %s of %s" % [label, kind.task(), subject])
			assert_eq(int(oracle.usage()["total"]["failures"]), 0, label + ": nothing was rejected")


func test_recorded_replies_still_pass() -> void:
	var chronicle := _recorded("claude_chronicle")
	assert_eq(JsonSchema.validate(chronicle, AIAssets.schema("chronicle")), PackedStringArray(), "recorded chronicle fits the schema")
	assert_eq(ContentGuard.check(chronicle), PackedStringArray(), "recorded chronicle is within the ceiling")
	var dilemma := _recorded("claude_dilemma")
	assert_eq(JsonSchema.validate(dilemma, AIAssets.schema("dilemma")), PackedStringArray(), "recorded dilemma fits the schema")
	assert_eq(ContentGuard.check(dilemma), PackedStringArray(), "recorded dilemma is within the ceiling")
	for fixture: String in FIXTURES:
		var state := _load(fixture)
		if state:
			assert_true(Dilemma.from_proposal(dilemma, state) != null, "%s: the sim plays the recorded dilemma" % fixture)
	# A real reply that ran far too long: it must keep failing, and fall back.
	assert_true(not JsonSchema.validate(_recorded("long_dilemma"), AIAssets.schema("dilemma")).is_empty(), "the long recorded dilemma is still rejected")


func _recorded(fixture: String) -> Dictionary:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/%s.json" % fixture))
	assert_true(data is Dictionary, fixture + " loads")
	return data if data is Dictionary else {}


# --- Regenerating the saved states -----------------------------------------------------

## Each saved state comes from a seed, some years of play and a few of the god's deeds: all
## deterministic, so regenerating gives the same files until the sim itself changes.
func _generate(fixture: String) -> WorldState:
	match fixture:
		"dawn_seed42":
			return WorldState.create(42)
		"village_seed7_year30":
			return await _play(Simulation.create(7), 30, {5: "harvest", 12: "rain", 20: "muse"})
		"wrathful_seed3_year60":
			return await _play(Simulation.create(3), 60, {10: "plague", 25: "drought", 38: "smite", 50: "plague"})
	# Late and dark: a realm in the Wired Age under every eye, its destiny met.
	var state: WorldState = await _play(Simulation.create(42), 40, {8: "smite", 20: "plague", 30: "sanctify"})
	var t := DestinySystem.greatest_realm(state)
	t = t if t != -1 else 0
	for tech: String in Knowledge.ORDER:
		state.learn(t, tech)
	for law: String in ["surveillance_net", "secret_police", "emergency_powers", "social_credit", "censorship"]:
		SocietySystem.enact(state, t, law)
	state.tribe_power[t]["ruler"] = 90
	state.tribe_fear[t] = 80
	state.pollution = 45.0
	state.destiny = {"kind": "panopticon", "tribe": state.tribe_names[t], "year": state.year()}
	state.settle()
	return state


## Plays some years, casting a miracle in the first tribe on the given years, answering an offline
## dilemma every 10 years, and leaving a prophecy resolved in the last 15 years.
func _play(sim: Simulation, years: int, miracles: Dictionary) -> WorldState:
	var oracle := Oracle.new(OfflineTemplatesProvider.new(), AICache.new())
	for year: int in years:
		var state := sim.state
		if year == years - 15:
			state.prophecy = await oracle.request_prophecy(state)
		if miracles.has(year):
			state.influence = WorldState.MAX_INFLUENCE
			Miracles.cast(state, miracles[year], state.tribe_names[0])
		if year % 10 == 9:
			var card := await oracle.request_dilemma(state)
			if card:
				card.choose(state, year % card.choices.size())
		sim.advance(WorldState.DAYS_PER_YEAR)
	if sim.state.prophecy and not sim.state.resolved_prophecy:
		sim.state.prophecy.status = Prophecy.Status.BROKEN
		sim.state.prophecy.resolved_tick = sim.state.tick
		sim.state.resolved_prophecy = sim.state.prophecy
		sim.state.prophecy = null
	return sim.state
