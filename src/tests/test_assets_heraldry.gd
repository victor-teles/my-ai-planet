extends TestCase
## Banners, propaganda posters and monuments (HeraldryKind, PosterKind, MonumentKind): their
## specs are clamped and cleaned, written offline with variety, rewritten when the regime changes,
## stored with the world, quoted to the Oracle, drawn headless, and never touch the sim.

const MALICIOUS_SVG := '<svg viewBox="0 0 64 64"><script>alert(1)</script><rect width="64" height="20" fill="p9" style="x"/><image href="file:///x"/><circle cx="32" cy="40" r="12" fill="#ffd060" onload="y()"/></svg>'


## Answers every asset task with its own scripted reply.
class TaskProvider:
	extends AIProvider
	var replies: Dictionary
	var calls := 0

	func _init(task_replies: Dictionary) -> void:
		replies = task_replies

	func get_id() -> String:
		return "fake-ai"

	func is_available() -> bool:
		return true

	func is_free() -> bool:
		return true

	func complete(request: AIRequest) -> AIResponse:
		calls += 1
		if not replies.has(request.task):
			return AIResponse.failure(get_id(), "no reply for " + request.task)
		return AIResponse.success(get_id(), (replies[request.task] as Dictionary).duplicate(true))


func _replies() -> Dictionary:
	return {
		"heraldry": {"motto": "The Eye keeps the hearth", "field": 27, "charge": "eye", "emblem": MALICIOUS_SVG},
		"poster": {"slogan": "Seen is safe", "ground": 22, "ink": 22, "emblem": ""},
		"monument": {"pose": "sword", "inscription": "Asha the Unbowed, who kept the gates", "iconography": "eye"},
	}


## A one-tribe world under a surveillance law, with a finished statue and temple and a prophet.
func _dark_world() -> WorldState:
	var state := WorldState.create(42, 1)
	var tribe := state.tribe_names[0]
	SocietySystem.enact(state, 0, "surveillance_net")
	state.add_building(tribe, "statue", 0).done(state)
	state.add_building(tribe, "temple", 8).done(state)
	state.log_event("prophet", {"tribe": tribe, "id": state.person_ids[1], "name": state.person_names[1]})
	return state


func _monuments(state: WorldState) -> Array[String]:
	return (AssetKinds.find("monument") as MonumentKind).subjects(state)


# --- Specs --------------------------------------------------------------------------

func test_kinds_are_registered_with_prompts_and_schemas() -> void:
	for task: String in ["heraldry", "poster", "monument"]:
		var kind := AssetKinds.find(task)
		assert_true(kind != null, "%s is a kind" % task)
		assert_eq(String(AIPrompts.entry(task)["input"]), "subject", task)
		assert_eq(AIPrompts.tier(task), AIRequest.Tier.SMALL, "%s asks a small model" % task)
		var schema := AIAssets.schema(task)
		assert_eq(schema.get("additionalProperties"), false, task)
		assert_eq((schema["required"] as Array).size(), (schema["properties"] as Dictionary).size(), "%s: every property is required" % task)


func test_heraldry_accepts_a_clean_and_clamped_spec() -> void:
	var kind := HeraldryKind.new()
	var spec: Variant = kind.accept(_replies()["heraldry"], {"tribe": "Kolu"})
	assert_true(spec is Dictionary)
	var emblem := String(spec["emblem"])
	assert_true(emblem.begins_with(SvgGuard.HEAD) and not emblem.contains("script") and not emblem.contains("image") and not emblem.contains("#"), emblem)
	assert_true(int(spec["field"]) in ArtPalette.GROUPS["heraldry"])
	assert_true(emblem.contains('fill="p%d"' % ArtPalette.clamp_index(9, "heraldry")), "a color outside the heraldic palette is clamped onto it")
	assert_eq(kind.accept({"motto": "Off the palette", "field": 9, "charge": "eye", "emblem": ""}, {})["field"], ArtPalette.clamp_index(9, "heraldry"))
	var drawn: Variant = kind.accept({"motto": "No drawing", "field": 27, "charge": "tower", "emblem": "<svg><text>hi</text></svg>"}, {"tribe": "Kolu"})
	assert_true(SvgGuard.shape_count(String(drawn["emblem"])) > 0, "an emblem that doesn't survive is drawn by the game from the charge")
	assert_eq(kind.accept({"motto": "  ", "field": 1, "charge": "sun", "emblem": ""}, {}), null, "an empty motto is rejected")
	assert_eq(kind.accept({"motto": "<b>bold</b>", "field": 1, "charge": "sun", "emblem": ""}, {}), null, "markup in a motto is rejected")
	var hidden: Variant = kind.accept({"motto": "Gold on gold", "field": 17, "charge": "sun", "emblem": '<svg><circle cx="32" cy="32" r="9" fill="p17"/></svg>'}, {})
	assert_true(not String(hidden["emblem"]).contains('"p17"'), "an emblem all in the field's color is recolored to show")


func test_poster_and_monument_accept_and_clamp() -> void:
	var poster := PosterKind.new()
	var spec: Variant = poster.accept(_replies()["poster"], {"tribe": "Kolu", "law": "surveillance_net"})
	assert_true(spec is Dictionary)
	assert_ne(spec["ink"], spec["ground"], "print the paper would hide is changed")
	assert_true(SvgGuard.shape_count(String(spec["emblem"])) > 0, "no emblem: the law's own motif")
	assert_eq(poster.accept({"slogan": "x".repeat(90), "ground": 1, "ink": 2, "emblem": ""}, {}), null, "too long a slogan")
	var monument := MonumentKind.new()
	assert_eq(monument.accept({"pose": "dab", "inscription": "Hello there", "iconography": "toaster"}, {}), {"pose": "raised_fist", "inscription": "Hello there", "iconography": "sun"})
	assert_eq(monument.accept({"pose": "sword", "inscription": "x", "iconography": "sun"}, {}), null, "too short an inscription")


func test_offline_specs_are_deterministic_varied_and_valid() -> void:
	var state := _dark_world()
	var tribe := state.tribe_names[0]
	var subjects := {"heraldry": tribe, "poster": "%s|surveillance_net" % tribe, "monument": _monuments(state)[0]}
	for task: String in subjects:
		var kind := AssetKinds.find(task)
		var facts := kind.context(state, subjects[task])
		assert_eq(kind.offline(facts, 7), kind.offline(facts, 7), "%s: the same seed writes the same spec" % task)
		for seed_value: int in 12:
			var reply := kind.offline(facts, seed_value)
			assert_eq(JsonSchema.validate(reply, AIAssets.schema(task)), PackedStringArray(), "%s %d fits its schema" % [task, seed_value])
			assert_eq(ContentGuard.check(reply, true), PackedStringArray(), "%s %d is gentle" % [task, seed_value])
			assert_true(kind.accept(reply, facts) != null, "%s %d is accepted" % [task, seed_value])
	var heraldry := HeraldryKind.new()
	var charges := {}
	var fields := {}
	var mottos := {}
	var emblems := {}
	for seed_value: int in 40:
		var facts := heraldry.context(state, tribe)
		facts["culture"] = {"piety": (seed_value * 37) % 200 - 100, "martial": (seed_value * 53) % 200 - 100, "openness": (seed_value * 71) % 200 - 100, "hierarchy": (seed_value * 13) % 200 - 100}
		var spec: Dictionary = heraldry.accept(heraldry.offline(facts, seed_value), facts)
		charges[spec["charge"]] = true
		fields[spec["field"]] = true
		mottos[spec["motto"]] = true
		emblems[spec["emblem"]] = true
		assert_eq(SvgGuard.sanitize(spec["emblem"], "heraldry"), spec["emblem"], "an accepted emblem is already clean")
	assert_true(charges.size() >= 8, "many charges: %s" % str(charges.keys()))
	assert_true(fields.size() >= 6, "many fields: %s" % str(fields.keys()))
	assert_true(mottos.size() >= 15, "many mottos: %d" % mottos.size())
	assert_true(emblems.size() >= 35, "nearly every banner its own: %d" % emblems.size())
	var slogans := {}
	var poster := PosterKind.new()
	for law: String in PosterKind.SLOGANS:
		assert_true(Laws.is_dystopian(law), "%s is a dark law" % law)
		var facts := {"tribe": tribe, "law": law, "government": "Total State"}
		slogans[poster.accept(poster.offline(facts, 3), facts)["slogan"]] = true
	assert_eq(slogans.size(), PosterKind.SLOGANS.size(), "every law its own slogan")
	for law: String in Laws.LAWS:
		if Laws.is_dystopian(law):
			assert_true(PosterKind.SLOGANS.has(law) and PosterKind.MOTIFS.has(law), "every dark law has offline posters: %s" % law)


func test_monuments_read_the_ruler_and_the_prophets() -> void:
	var state := _dark_world()
	var kind := MonumentKind.new()
	var subjects := kind.subjects(state)
	assert_eq(subjects.size(), 2, "the statue and the temple")
	var statue := kind.context(state, subjects[0])
	var temple := kind.context(state, subjects[1])
	assert_eq(statue["monument"], "statue")
	assert_eq(String(statue["ruler"]["name"]), People.full_name(state, state.chief_of(state.tribe_names[0])), "the statue is of the ruler")
	assert_eq(temple["monument"], "temple")
	assert_eq(String(temple["prophets"][0]["name"]), state.person_names[1], "the temple knows its prophet")
	var signature := kind.signature(state, subjects[0])
	state.tribe_chiefs[0] = state.person_ids[2]
	assert_eq(kind.signature(state, subjects[0]), signature, "a monument keeps its words when rulers change")
	assert_eq(kind.signature(state, "999999"), "", "a monument that isn't there needs nothing")
	# Every prompt for them is filled, small and tone-aware, like the golden prompts.
	var oracle := Oracle.new(OfflineTemplatesProvider.new(), AICache.new())
	oracle.gentle = false
	for subject: String in subjects:
		var request := oracle.asset_request(kind, state, subject)
		for part: String in [request.system, request.prompt]:
			assert_true(RegEx.create_from_string("\\{[a-z_]+\\}").search(part) == null, "no unfilled placeholder")
		assert_true(request.system.length() + request.prompt.length() <= int(AIPrompts.entry("monument")["max_chars"]))
		assert_true(request.system.contains("Tone level: %d " % oracle.tone_for(state)))
		var response := await OfflineTemplatesProvider.new().complete(request)
		assert_eq(JsonSchema.validate(response.data, request.schema), PackedStringArray())
		assert_true(kind.accept(response.data, request.context) != null)


# --- Signatures ---------------------------------------------------------------------

func test_a_new_house_or_a_coup_replaces_the_banner() -> void:
	var state := WorldState.create(42, 1)
	var kind := HeraldryKind.new()
	var tribe := state.tribe_names[0]
	var first := kind.signature(state, tribe)
	assert_true(not first.is_empty())
	state.tribe_dynasty[0] = "Asha"
	var housed := kind.signature(state, tribe)
	assert_ne(housed, first, "a ruling house takes the banner")
	assert_true(housed.begins_with("house Asha"), housed)
	var powers: Dictionary = state.tribe_power[0]
	powers["warriors"] = 80
	powers["ruler"] = 20
	var old_chief := state.tribe_chiefs[0]
	CrisisSystem.new()._coup(state, 0)
	assert_ne(state.tribe_chiefs[0], old_chief, "the general takes the seat")
	var after := kind.signature(state, tribe)
	assert_ne(after, housed, "the coup replaces the banner")
	assert_true(after.begins_with("ruler %d" % state.tribe_chiefs[0]), after)
	# A second general in the same junta is a new ruler, and a new banner.
	powers["ruler"] = 10
	CrisisSystem.new()._coup(state, 0)
	var junta := kind.signature(state, tribe)
	assert_ne(junta, after, "every strongman flies his own colors")
	powers["warriors"] = 5
	powers["priests"] = 70
	assert_eq(kind.signature(state, tribe), "the people|priests", "the priests take over: new colors")
	state.tribe_population[0] += 40
	assert_eq(kind.signature(state, tribe), "the people|priests", "a government renamed by the head count is not a new regime")


func test_dark_laws_put_posters_up_and_take_them_down() -> void:
	var state := WorldState.create(42, 1)
	var kind := PosterKind.new()
	var tribe := state.tribe_names[0]
	SocietySystem.enact(state, 0, "shared_stores")
	assert_eq(Array(kind.subjects(state)), [], "a fair law needs no poster")
	SocietySystem.enact(state, 0, "emergency_powers")
	var subject := "%s|emergency_powers" % tribe
	assert_eq(Array(kind.subjects(state)), [subject], "a dark law puts one up")
	var signature := kind.signature(state, subject)
	assert_true(not signature.is_empty())
	SocietySystem.repeal(state, 0, "emergency_powers")
	assert_eq(Array(kind.subjects(state)), [], "repealed, it comes down")
	assert_eq(kind.signature(state, subject), "")
	state.tick += WorldState.DAYS_PER_YEAR
	SocietySystem.enact(state, 0, "emergency_powers")
	assert_ne(kind.signature(state, subject), signature, "passed again, a new poster")


# --- The director, the world and the view -------------------------------------------

func test_ai_specs_round_trip_through_the_director_and_a_save() -> void:
	var state := _dark_world()
	var tribe := state.tribe_names[0]
	var provider := TaskProvider.new(_replies())
	var oracle := Oracle.new(provider, AICache.new())
	oracle.gentle = false
	var director := AssetDirector.new(oracle)
	await director.settle(state)
	var monuments := _monuments(state)
	assert_eq(director.written, {"ai": 4, "offline": 0}, "the banner, the poster and both monuments")
	assert_eq(AssetBook.source(state, "heraldry", tribe), "fake-ai")
	var banner := AssetBook.spec(state, "heraldry", tribe)
	assert_eq(banner["motto"], "The Eye keeps the hearth")
	assert_true(not String(banner["emblem"]).contains("script") and String(banner["emblem"]).begins_with(SvgGuard.HEAD), "stored clean")
	assert_eq(AssetBook.spec(state, "poster", "%s|surveillance_net" % tribe)["slogan"], "Seen is safe")
	assert_eq(AssetBook.spec(state, "monument", monuments[0])["pose"], "sword")
	var summary: Dictionary = state.summarize()["tribes"][0]
	assert_eq(summary["motto"], "The Eye keeps the hearth", "the Oracle can quote the motto")
	assert_eq(summary["slogans"], ["Seen is safe"], "and the slogans")
	var loaded := WorldState.from_dict(JSON.parse_string(state.to_json()))
	for key: String in ["heraldry|" + tribe, "poster|%s|surveillance_net" % tribe, "monument|" + monuments[0], "monument|" + monuments[1]]:
		var parts := key.split("|", true, 1)
		assert_eq(AssetBook.spec(loaded, parts[0], parts[1]), AssetBook.spec(state, parts[0], parts[1]), "%s survives a save" % key)
		assert_eq(AssetDirector.spec_or_offline(loaded, parts[0], parts[1]), AssetBook.spec(state, parts[0], parts[1]))
	# Nothing is stale after a reload, so nothing is asked again.
	var again := AssetDirector.new(oracle)
	var calls := provider.calls
	await again.settle(loaded)
	assert_eq(provider.calls, calls, "a reloaded world asks for nothing")
	# A coup makes the banner stale; a reply that crosses the content ceiling falls back offline.
	(loaded.tribe_power[0] as Dictionary)["warriors"] = 90
	CrisisSystem.new()._coup(loaded, 0)
	provider.replies["heraldry"] = {"motto": "As an AI, I salute", "field": 3, "charge": "sun", "emblem": ""}
	await AssetDirector.new(oracle).settle(loaded)
	assert_eq(AssetBook.signature(loaded, "heraldry", tribe), HeraldryKind.new().signature(loaded, tribe), "the banner was rewritten for the new regime")
	assert_eq(AssetBook.source(loaded, "heraldry", tribe), "offline", "by the offline writer, since the AI's crossed the line")
	assert_ne(AssetBook.spec(loaded, "heraldry", tribe)["motto"], "As an AI, I salute")


func test_specs_never_change_the_simulation() -> void:
	var with_assets := Simulation.create(42)
	var plain := Simulation.create(42)
	var director := AssetDirector.new(Oracle.new(OfflineTemplatesProvider.new(), AICache.new()))
	for month: int in 24:
		with_assets.advance(WorldState.DAYS_PER_MONTH)
		director.observe(with_assets.state)
	plain.advance(24 * WorldState.DAYS_PER_MONTH)
	assert_true(not with_assets.state.assets.is_empty(), "specs were written")
	with_assets.state.assets = {}
	assert_eq(with_assets.state.checksum(), plain.state.checksum(), "and the world is the same without them")


func test_banners_and_posters_rasterize_headless() -> void:
	var state := _dark_world()
	var tribe := state.tribe_names[0]
	var spec := AssetDirector.spec_or_offline(state, "heraldry", tribe)
	var banner := EmblemArt.banner_texture(spec)
	assert_eq(banner.get_size(), Vector2(128, 160))
	assert_true(EmblemArt.banner_texture(spec) == banner, "cached by content")
	var corner := banner.get_image().get_pixel(2, 2)
	var field := ArtPalette.color(int(spec["field"]))
	assert_true(absf(corner.r - field.r) < 0.03 and absf(corner.g - field.g) < 0.03 and absf(corner.b - field.b) < 0.03, "the field fills the banner: %s vs %s" % [corner, field])
	var poster := EmblemArt.poster_texture(AssetDirector.spec_or_offline(state, "poster", "%s|surveillance_net" % tribe))
	assert_eq(poster.get_size(), Vector2(128, 176))
	assert_eq(EmblemArt.texture("").get_size(), Vector2(4, 4), "nothing to draw is a small ink square, not a crash")
	for icon: String in MonumentKind.ICONS:
		assert_eq(EmblemArt.texture(EmblemArt.plaque_svg(icon)).get_size(), Vector2(128, 128), icon)
