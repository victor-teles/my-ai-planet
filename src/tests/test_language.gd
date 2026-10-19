extends TestCase
## A people's own language (Language): checked and clamped, pronounceable, deterministic, different
## for each founding people, drifting into dialects when tribes split, saved with the world, and
## changed by the AI only for the names given afterwards.

const GOLDEN := "res://tests/fixtures/golden/dawn_seed42.json"
## A tongue no island would draw by itself: only these letters.
const ODD_TONGUE := {"onsets": ["q", "x", "zh", "qu"], "vowels": ["y", "oo"], "codas": ["x"], "closed": 50, "long": 50}


## Answers the language task with ODD_TONGUE, everything else like the offline templates.
class TongueProvider:
	extends AIProvider

	func get_id() -> String:
		return "tongue"

	func is_available() -> bool:
		return true

	func is_free() -> bool:
		return true

	func complete(request: AIRequest) -> AIResponse:
		if request.task == "language":
			return AIResponse.success(get_id(), ODD_TONGUE.duplicate(true))
		return await OfflineTemplatesProvider.new().complete(request)


## Every letter a tongue can make a name from.
func _letters(language: Dictionary) -> Dictionary:
	var letters := {}
	var spec := Language.resolved(language)
	for group: String in ["onsets", "vowels", "codas"]:
		for sound: String in spec[group]:
			for c: String in sound:
				letters[c] = true
	return letters


func _made_of(name: String, letters: Dictionary) -> bool:
	for c: String in name.to_lower():
		if not letters.has(c):
			return false
	return true


func _pronounceable(name: String) -> bool:
	return RegEx.create_from_string("^[A-Z][a-z]{1,17}$").search(name) != null \
		and RegEx.create_from_string("[aeiouy]").search(name.to_lower()) != null \
		and RegEx.create_from_string("[bcdfghjklmnpqrstvwxz]{5,}").search(name.to_lower()) == null


func _names(language: Dictionary, seed_value: int) -> Array[String]:
	var rng := SimRng.new(seed_value)
	var names: Array[String] = []
	for k: int in 25:
		names.append_array([Language.person_name(rng, language), Language.family_name(rng, language), Language.tribe_name(rng, language), Language.word(rng, language)])
	return names


func _shared(a: Array, b: Array) -> int:
	return a.filter(func(sound: String) -> bool: return sound in b).size()


func test_junk_phonologies_are_rejected_or_clamped() -> void:
	assert_eq(Language.clamp_spec(null), {}, "not a dictionary")
	assert_eq(Language.clamp_spec({"onsets": "k t m", "vowels": ["a", "e"]}), {}, "onsets not a list")
	assert_eq(Language.clamp_spec({"onsets": ["k", "t"], "vowels": ["a", "e"], "codas": []}), {}, "too few onsets")
	assert_eq(Language.clamp_spec({"onsets": ["k", "t", "m"], "vowels": ["a", "k"], "codas": []}), {}, "a consonant is no vowel")
	var clean := Language.clamp_spec({
		"onsets": ["K", " t ", "m", "m", "strz", "kqx", "é", 7, "", "th", "str", "ndr", "rk", "aa"],
		"vowels": ["a", "aaa", "ou", "E", "x", "yy"],
		"codas": ["n", "sh", "w", "nth", "kp", "rds"],
		"closed": 500.0,
		"long": -5,
		"extra": "ignored",
	})
	assert_eq(clean["onsets"], ["k", "t", "m", "th", "str", "ndr"], "lowercased, trimmed, deduped, only sayable clusters")
	assert_eq(clean["vowels"], ["a", "ou", "e"])
	assert_eq(clean["codas"], ["n", "sh", "nth", "rds"])
	assert_eq(clean["closed"], Language.MAX_CLOSED, "clamped")
	assert_eq(clean["long"], 0, "clamped")
	assert_eq(clean.keys().size(), 5, "unknown keys dropped")
	assert_eq(Language.clamp_spec(clean), clean, "clamping is idempotent")
	var open := Language.clamp_spec({"onsets": ["k", "t", "m"], "vowels": ["a", "i"], "codas": [], "closed": 60, "long": 40})
	assert_eq(open["closed"], 0, "no codas, no closed names")
	var many: Array = []
	for c: String in "bdfgklmnprstvz":
		for v: String in ["", "h", "l"]:
			many.append(c + v)
	assert_eq((Language.clamp_spec({"onsets": many, "vowels": ["a", "e"], "codas": []})["onsets"] as Array).size(), Language.MAX_ONSETS, "bounded lists")


func test_names_are_pronounceable_and_deterministic() -> void:
	for seed_value: int in 12:
		var language := Language.generate(SimRng.new(seed_value))
		assert_true(Language.is_valid(language), "seed %d makes a valid tongue" % seed_value)
		assert_eq(Language.clamp_spec(language), language, "a generated tongue is already clamped")
		var letters := _letters(language)
		var names := _names(language, seed_value)
		for name: String in names:
			assert_true(_pronounceable(name), "pronounceable: %s" % name)
			assert_true(_made_of(name, letters), "%s is made of its tongue's sounds" % name)
		assert_eq(_names(language, seed_value), names, "same seed, same names")
	assert_eq(Language.generate(SimRng.new(3)), Language.generate(SimRng.new(3)), "same seed, same tongue")
	# Without a tongue NameGen is what it always was.
	assert_eq(NameGen.person_name(SimRng.new(8)), NameGen.person_name(SimRng.new(8), {}))


func test_founding_peoples_and_islands_sound_different() -> void:
	var state := WorldState.create(42, 3)
	for t: int in state.tribe_count():
		var language := state.tribe_language[t]
		assert_true(Language.is_valid(language), "%s has a tongue" % state.tribe_names[t])
		assert_eq(language, WorldGen.people_language(state.world["peoples"][t]), "the recipe keeps it")
		var letters := _letters(language)
		assert_true(_made_of(state.tribe_names[t], letters), "%s is named in its own tongue" % state.tribe_names[t])
		for p: int in state.people_of(state.tribe_names[t]):
			assert_true(_made_of(state.person_names[p] + state.person_families[p], letters), "%s %s is named in the tongue of the %s" % [state.person_names[p], state.person_families[p], state.tribe_names[t]])
		for u: int in range(t + 1, state.tribe_count()):
			assert_ne(language, state.tribe_language[u], "%s and %s speak differently" % [state.tribe_names[t], state.tribe_names[u]])
	var other := WorldState.create(43, 1)
	assert_ne(other.tribe_language[0], state.tribe_language[0], "another island, another tongue")


func test_splits_drift_into_close_dialects() -> void:
	var changed := 0
	for seed_value: int in 20:
		var parent := Language.generate(SimRng.new(seed_value))
		var dialect := Language.drift(parent, SimRng.new(seed_value + 100))
		assert_true(Language.is_valid(dialect), "a dialect is a valid tongue")
		if dialect != parent:
			changed += 1
		assert_true(_shared(dialect["onsets"], parent["onsets"]) >= (parent["onsets"] as Array).size() - 2, "most consonants stay")
		assert_true(_shared(dialect["vowels"], parent["vowels"]) >= (parent["vowels"] as Array).size() - 2, "most vowels stay")
		assert_true(absi(int(dialect["closed"]) - int(parent["closed"])) <= 10 and absi(int(dialect["long"]) - int(parent["long"])) <= 10, "the rhythm moves a little")
	assert_true(changed >= 18, "nearly every split drifts (%d of 20)" % changed)
	# A breakaway tribe takes its dialect, and its name is in it.
	var state := WorldState.create(42, 1)
	var leaving: Array[int] = [0, 1, 2, 3, 4, 5]
	var n := RelationsSystem.split_tribe(state, 0, leaving, 0)
	assert_true(Language.is_valid(state.tribe_language[n]), "the new tribe has a tongue")
	assert_ne(state.tribe_language[n], state.tribe_language[0], "a dialect of its own")
	assert_true(_made_of(state.tribe_names[n], _letters(state.tribe_language[n])), "%s is named in its dialect" % state.tribe_names[n])
	assert_true(_shared(state.tribe_language[n]["onsets"], state.tribe_language[0]["onsets"]) >= (state.tribe_language[0]["onsets"] as Array).size() - 2, "close to its parents' tongue")
	assert_eq(state.tribe_language.size(), state.tribe_count(), "kept in step with the tribes")
	var dialect: Dictionary = state.tribe_language[n]
	for p: int in state.people_of(state.tribe_names[n]):
		state.move_person(p, state.tribe_names[0])
	state.remove_tribe(n)
	assert_eq(state.tribe_language.size(), state.tribe_count(), "and when one is gone")
	assert_true(dialect not in state.tribe_language, "its dialect went with it")


func test_languages_survive_save_and_load() -> void:
	var sim := Simulation.create(11)
	sim.advance(3 * WorldState.DAYS_PER_YEAR)
	var loaded := WorldState.from_dict(JSON.parse_string(sim.state.to_json()))
	assert_eq(loaded.tribe_language, sim.state.tribe_language)
	assert_eq(loaded.checksum(), sim.state.checksum(), "a world with languages round-trips")


func test_old_saves_speak_the_default_sound() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(GOLDEN))
	assert_true(data is Dictionary and not (data as Dictionary).has("tribe_language"), "the golden save is from before languages")
	var state := WorldState.from_dict(data)
	assert_true(state != null, "it loads")
	if state == null:
		return
	assert_eq(state.tribe_language.size(), state.tribe_count())
	for language: Dictionary in state.tribe_language:
		assert_eq(language, {}, "the default sound")
	var sim := Simulation.new(state)
	sim.advance(2 * WorldState.DAYS_PER_YEAR)
	assert_eq(sim.state.tribe_language.size(), sim.state.tribe_count(), "it plays on")
	var reloaded := WorldState.from_dict(JSON.parse_string(sim.state.to_json()))
	assert_eq(reloaded.checksum(), sim.state.checksum(), "and saves again")


func test_an_ai_tongue_names_only_those_born_after() -> void:
	var sim := Simulation.create(42, 1)
	var state := sim.state
	var tribe := state.tribe_names[0]
	var founders := {}
	for p: int in state.person_ids.size():
		founders[state.person_ids[p]] = state.person_names[p] + " " + state.person_families[p]
	var director := AssetDirector.new(Oracle.new(TongueProvider.new(), AICache.new()))
	await director.settle(state)
	assert_eq(AssetBook.source(state, "language", tribe), "tongue", "the AI's tongue was stored")
	assert_eq(state.tribe_language[0], Language.clamp_spec(ODD_TONGUE), "and is spoken now")
	for p: int in state.person_ids.size():
		assert_eq(state.person_names[p] + " " + state.person_families[p], founders[state.person_ids[p]], "founders keep their names")
	assert_eq(tribe, state.tribe_names[0], "the people keep their name")
	var seen := state.next_event_id
	sim.advance(6 * WorldState.DAYS_PER_YEAR)
	var odd := _letters(ODD_TONGUE)
	var newborn := 0
	for event: Dictionary in state.events:
		var data: Dictionary = event["data"]
		if int(event["id"]) >= seen and event["type"] == "birth" and String(data.get("named_after", "")).is_empty() and String(data.get("tribe", tribe)) == tribe:
			newborn += 1
			assert_true(_made_of(String(data["name"]), odd), "%s is named in the new tongue" % data["name"])
	assert_true(newborn > 0, "children were born and named")


func test_the_offline_tongue_changes_nothing() -> void:
	var a := Simulation.create(9)
	var b := Simulation.create(9)
	var director := AssetDirector.new(Oracle.new(OfflineTemplatesProvider.new(), AICache.new()))
	await director.settle(a.state)
	assert_eq(AssetBook.subjects(a.state, "language").size(), (a.state.world["peoples"] as Array).size(), "every founding people has its spec")
	assert_eq(a.state.tribe_language, b.state.tribe_language, "the tongue is the one the island gave")
	a.advance(3 * WorldState.DAYS_PER_YEAR)
	b.advance(3 * WorldState.DAYS_PER_YEAR)
	assert_eq(a.state.person_names, b.state.person_names, "the same children get the same names")
