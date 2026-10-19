extends TestCase
## Laws and places in a tribe's own words (NamesKind, LocalNames): the AI's names are kept only
## for ids the game knows, tidied and short; they are saved with the world; offline names come
## from the tribe's own tongue; the feed and panels show them while the sim keeps the ids.

const AI_NAME := "Hearth of the Many"


## Names the first law it is asked about AI_NAME; everything else like the offline templates.
class NamingProvider:
	extends AIProvider

	func get_id() -> String:
		return "namer"

	func is_available() -> bool:
		return true

	func is_free() -> bool:
		return true

	func complete(request: AIRequest) -> AIResponse:
		if request.task == "names":
			var law := String(request.context["laws"][0]["id"])
			return AIResponse.success(get_id(), {"laws": [{"id": law, "name": "The " + AI_NAME}], "buildings": []})
		return await OfflineTemplatesProvider.new().complete(request)


func _kind() -> AssetKind:
	return AssetKinds.find("names")


func test_only_known_ids_are_kept_tidy_and_short() -> void:
	var state := WorldState.create(42, 1)
	var tribe := state.tribe_names[0]
	var facts := _kind().context(state, tribe)
	var laws: Array = facts["laws"]
	assert_true(laws.size() >= 2, "a new tribe has laws its age may bring")
	var first := String(laws[0]["id"])
	var second := String(laws[1]["id"])
	var reply := {
		"laws": [
			{"id": first, "name": "  The   Circle of  Ash "},
			{"id": first, "name": "A second name for the same law"},
			{"id": "made_up_law", "name": "Nothing"},
			{"id": second, "name": "Law 42"},
			{"id": "surveillance_net", "name": "Eye"}, # a real law, but not one this tribe was asked about
			"not an entry",
		],
		"buildings": [{"id": "temple", "name": "x".repeat(NamesKind.MAX_NAME + 1)}],
	}
	var spec: Variant = _kind().accept(reply, facts)
	assert_true(spec is Dictionary, "a reply with one good name is accepted")
	if spec is Dictionary:
		assert_eq(spec["laws"], {first: "Circle of Ash"}, "trimmed, no leading 'the', the first name for an id, known ids only")
		assert_eq(spec["buildings"], {}, "too long is dropped")
	assert_eq(_kind().accept({"laws": [{"id": "made_up_law", "name": "Nothing"}], "buildings": []}, facts), null, "nothing usable: rejected")
	assert_eq(NamesKind.tidy("the Quiet Hand"), "Quiet Hand")
	assert_eq(NamesKind.tidy("Kolú's Eye-Watch"), "Kolú's Eye-Watch", "letters of any alphabet, apostrophes and hyphens")
	assert_eq(NamesKind.tidy("<b>Eye</b>"), "", "no markup")


func test_signature_follows_age_and_government() -> void:
	var state := WorldState.create(7, 1)
	var tribe := state.tribe_names[0]
	var before := _kind().signature(state, tribe)
	assert_true(before.begins_with("age 0|"), before)
	state.learn(0, "copper_working")
	state.learn(0, "bronze")
	assert_ne(_kind().signature(state, tribe), before, "a new age, new names")
	assert_eq(_kind().signature(state, "Nobody"), "", "no tribe, no names")


func test_offline_names_come_from_the_tribes_own_tongue() -> void:
	var a := WorldState.create(42, 1)
	var b := WorldState.create(43, 1)
	for state: WorldState in [a, b]:
		var tribe := state.tribe_names[0]
		var words := NamesKind.words_of(state, tribe)
		assert_eq(words.size(), NamesKind.WORDS, "%s has words" % tribe)
		assert_eq(NamesKind.words_of(state, tribe), words, "always the same words")
		var name := LocalNames.law(state, tribe, "surveillance_net")
		assert_ne(name, Laws.name_of("surveillance_net"), "a name of their own")
		assert_true(words.any(func(word: String) -> bool: return name.contains(word)) or name.contains(tribe), "%s is in their words" % name)
		assert_eq(LocalNames.law(state, tribe, "surveillance_net"), name, "and the same every time")
		assert_eq(LocalNames.building(state, tribe, "hut"), "hut", "homes keep their usual names")
		assert_eq(LocalNames.law(state, "Nobody", "taxation"), Laws.name_of("taxation"), "no tribe, the usual name")
	assert_ne(LocalNames.law(a, a.tribe_names[0], "surveillance_net"), LocalNames.law(b, b.tribe_names[0], "surveillance_net"), "other tongues, other names")
	# The offline spec names what the prompt asks about, exactly as LocalNames would.
	var tribe := a.tribe_names[0]
	var spec := _kind().offline_spec(a, tribe)
	for law: String in spec["laws"]:
		assert_eq(String(spec["laws"][law]), LocalNames.law(a, tribe, law))


func test_ai_names_are_shown_and_survive_save_and_load() -> void:
	var sim := Simulation.create(42, 1)
	var state := sim.state
	var tribe := state.tribe_names[0]
	var first := String(_kind().context(state, tribe)["laws"][0]["id"])
	var director := AssetDirector.new(Oracle.new(NamingProvider.new(), AICache.new()))
	await director.settle(state)
	assert_eq(AssetBook.source(state, "names", tribe), "namer", "the AI's names were stored")
	assert_eq(LocalNames.law(state, tribe, first), AI_NAME, "and are shown")
	var loaded := WorldState.from_dict(JSON.parse_string(state.to_json()))
	assert_eq(LocalNames.law(loaded, tribe, first), AI_NAME, "after a reload too")
	assert_eq(loaded.checksum(), state.checksum())
	# A law the AI didn't name gets the offline name; the sim's ids never change.
	var other := String(_kind().context(state, tribe)["laws"][1]["id"])
	assert_eq(LocalNames.law(state, tribe, other), NamesKind.offline_name("laws", other, NamesKind.words_of(state, tribe), tribe))
	SocietySystem.enact(state, 0, first)
	assert_true(Society.has_law(state, 0, first), "the sim speaks in ids")
	var passed := {"type": "law_passed", "data": {"tribe": tribe, "law": first, "name": "Ana"}}
	assert_true(EventText.text(passed).contains(Laws.name_of(first).to_lower()), "without local names, the usual one")
	assert_true(EventText.text(passed, LocalNames.lookup(state)).contains("under the " + AI_NAME), EventText.text(passed, LocalNames.lookup(state)))


func test_the_feed_names_places_in_the_tribes_words() -> void:
	var state := WorldState.create(42, 1)
	var tribe := state.tribe_names[0]
	var local := LocalNames.lookup(state)
	var temple := {"type": "building_done", "data": {"tribe": tribe, "building": "temple"}}
	assert_eq(EventText.text(temple), "The %s finished a temple." % tribe)
	assert_eq(EventText.text(temple, local), "The %s finished the %s." % [tribe, LocalNames.building(state, tribe, "temple")])
	var hut := {"type": "building_started", "data": {"tribe": tribe, "building": "hut"}}
	assert_eq(EventText.text(hut, local), "The %s began building a hut." % tribe, "homes keep their usual names")
	var storm := {"type": "disaster", "data": {"tribe": tribe, "kind": "storms", "building": "shrine"}}
	assert_eq(EventText.text(storm), "A storm tore down the %s's shrine." % tribe)
	assert_eq(EventText.text(storm, local), "A storm tore down the %s's %s." % [tribe, LocalNames.building(state, tribe, "shrine")])
