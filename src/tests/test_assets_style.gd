extends TestCase
## The "style" asset kind (StyleKind): its schema and clamps, its offline writer, its signature,
## a reply's road through the Oracle and the AssetDirector into the world and a save, and the
## buildings and villagers drawn from it.

const FakeProvider := preload("res://tests/fixtures/ai/fake_provider.gd")
const GREYS: Array[int] = [5, 7, 8, 12, 14, 15, 16] ## dark stone, cold stone, cold dark, concrete, slate, steel, iron


func _facts(government: String, age: int = 4, extra: Dictionary = {}) -> Dictionary:
	var facts := {"government": government, "age_level": age, "island": "meadow", "culture": {}, "dystopia": 10, "dystopia_kind": "none"}
	facts.merge(extra, true)
	return facts


func _reply() -> Dictionary:
	return {
		"architecture": {"roof": "dome", "material": "stone", "wall": 4, "roof_color": 14, "trim": 17, "ornament": "carved", "towers": 1, "proportion": "tall"},
		"fashion": {"commoner": 28, "noble": 22, "bonded": 21, "guard": 27, "trim": 24, "pattern": "checks", "accessory": "hood"},
	}


func test_schema_rejects_junk_and_accept_clamps() -> void:
	var kind := StyleKind.new()
	var schema := AIAssets.schema("style")
	var facts := _facts("Kingdom", 1)
	assert_eq(JsonSchema.validate(_reply(), schema), PackedStringArray(), "a good reply fits")
	var reply := _reply()
	reply["architecture"]["towers"] = 5
	reply["architecture"]["wall"] = 99
	assert_eq(JsonSchema.validate(reply, schema).size(), 2, "too many towers and an index off the palette break the schema")
	var spec: Dictionary = kind.accept(reply, facts)
	assert_eq(spec["architecture"]["towers"], StyleKind.MAX_TOWERS, "towers clamped")
	assert_true(int(spec["architecture"]["wall"]) in ArtPalette.GROUPS["walls"], "the wall index is clamped onto the walls")
	# Schema-valid indices from the wrong group are moved onto the right one.
	reply = _reply()
	reply["architecture"]["wall"] = 1 # thatch is no wall
	reply["fashion"]["bonded"] = 23 # flame is no drab cloth
	reply["architecture"]["material"] = "concrete" # not in the Age of Bronze
	spec = kind.accept(reply, facts)
	assert_true(int(spec["architecture"]["wall"]) in ArtPalette.GROUPS["walls"], "wall clamped: %s" % spec)
	assert_true(int(spec["fashion"]["bonded"]) in ArtPalette.GROUPS["drab"], "the bonded stay drab: %s" % spec)
	assert_eq(spec["architecture"]["material"], "stone", "concrete falls back to what the age can build")
	assert_eq(spec["fashion"]["commoner"], 28, "a good index is kept")
	# Words outside the grammar are rejected, by the schema and by accept().
	for junk: Array in [["architecture", "roof", "pagoda"], ["architecture", "ornament", "neon"], ["fashion", "pattern", "tartan"], ["fashion", "accessory", "crown"]]:
		reply = _reply()
		reply[junk[0]][junk[1]] = junk[2]
		assert_true(not JsonSchema.validate(reply, schema).is_empty(), "%s breaks the schema" % junk[2])
		assert_eq(kind.accept(reply, facts), null, "%s is rejected" % junk[2])
	reply = _reply()
	reply["fashion"]["hex"] = "#ff00ff"
	assert_true(not JsonSchema.validate(reply, schema).is_empty(), "no raw colors or extra fields")
	assert_eq(kind.accept({"architecture": "spires"}, facts), null, "a malformed reply is rejected")


func test_offline_is_deterministic_and_accepted() -> void:
	var kind := StyleKind.new()
	var schema := AIAssets.schema("style")
	var looks := {}
	for government: String in ["Council of Elders", "Theocracy", "Total State", "Kingdom", "Corporate State", "Democracy"]:
		for age: int in 5:
			for seed_value: int in 4:
				var facts := _facts(government, age)
				var reply := kind.offline(facts, seed_value)
				assert_eq(reply, kind.offline(facts, seed_value), "same facts and seed, same style")
				assert_eq(JsonSchema.validate(reply, schema), PackedStringArray(), "%s age %d fits the schema" % [government, age])
				assert_eq(kind.accept(reply, facts), reply, "%s age %d: the offline style needs no clamping" % [government, age])
				looks[JSON.stringify(reply)] = true
	assert_true(looks.size() > 60, "offline styles vary (%d different of 120)" % looks.size())


func test_offline_makes_the_society_readable() -> void:
	var kind := StyleKind.new()
	for seed_value: int in 8:
		var holy: Dictionary = kind.offline(_facts("Theocracy", 3), seed_value)
		assert_eq(holy["architecture"]["roof"], "spire", "a Theocracy grows spires")
		var grey: Dictionary = kind.offline(_facts("Total State", 4, {"dystopia": 80, "dystopia_kind": "surveillance"}), seed_value)
		assert_eq(grey["architecture"]["ornament"], "grim", "a Total State is grim")
		assert_true(grey["architecture"]["roof"] in ["flat", "stepped"], "and blocky")
		assert_eq(grey["architecture"]["material"], "concrete", "and concrete")
		for key: String in ["wall", "roof_color"]:
			assert_true(int(grey["architecture"][key]) in GREYS, "a Total State is grey: %s" % grey)
		assert_true(int(grey["fashion"]["guard"]) in ArtPalette.GROUPS["drab"] or int(grey["fashion"]["guard"]) == 27, "guards in a dark uniform: %s" % grey)
		assert_true(int(grey["fashion"]["commoner"]) in ArtPalette.GROUPS["drab"], "commoners in grey")
		var free: Dictionary = kind.offline(_facts("Democracy", 4, {"destiny_id": "free_commons"}), seed_value)
		assert_true(int(free["architecture"]["trim"]) in ArtPalette.GROUPS["bright"], "a Free Commons is colorful: %s" % free)
		assert_true(int(free["fashion"]["commoner"]) in ArtPalette.GROUPS["bright"], "and dresses brightly")
		assert_eq(free["architecture"]["towers"], 0, "and raises no towers")
		for style: Dictionary in [holy, grey, free]:
			assert_ne(style["fashion"]["noble"], style["fashion"]["bonded"], "nobles and the bonded dress apart")
			assert_true(int(style["fashion"]["bonded"]) in ArtPalette.GROUPS["drab"], "the bonded wear drab")
	# A free tribe that has slid into a dystopia looks like one.
	assert_eq(StyleKind.regime_of(_facts("Republic", 4, {"dystopia": 70, "dystopia_kind": "military"})), "iron")
	assert_eq(StyleKind.regime_of(_facts("Republic", 4, {"dystopia": 70, "dystopia_kind": "theocratic"})), "holy")
	assert_eq(StyleKind.regime_of(_facts("Republic", 4)), "free")
	# And from a real world: the saved Panopticon is grey.
	var state := WorldState.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/golden/dystopia_seed42_late.json")))
	var realm := String(state.destiny["tribe"])
	var spec := AssetDirector.spec_or_offline(state, "style", realm)
	assert_eq(spec["architecture"]["ornament"], "grim", "the Panopticon's realm is grim: %s" % spec)


func test_signature_follows_age_government_and_destiny() -> void:
	var kind := StyleKind.new()
	var state := WorldState.create(42, 2)
	var tribe := state.tribe_names[0]
	var first := kind.signature(state, tribe)
	assert_true(first.begins_with("age 0|"), first)
	assert_eq(kind.subjects(state), Array(state.tribe_names), "one style per tribe")
	state.learn(0, "bronze")
	var bronze := kind.signature(state, tribe)
	assert_true(bronze.begins_with("age 1|"), "a new age: %s" % bronze)
	state.tribe_power[0] = {"ruler": 10, "council": 10, "priests": 90, "warriors": 10, "merchants": 10}
	assert_eq(kind.signature(state, tribe), "age 1|Theocracy|", "a new government")
	state.destiny = {"kind": "holy_order", "tribe": state.tribe_names[1], "year": 80}
	assert_eq(kind.signature(state, tribe), "age 1|Theocracy|", "another tribe's destiny is not ours")
	state.destiny = {"kind": "holy_order", "tribe": tribe, "year": 80}
	assert_eq(kind.signature(state, tribe), "age 1|Theocracy|holy_order", "our destiny met")
	assert_eq(kind.signature(state, "Nobody"), "", "no tribe, no style")


func test_an_ai_style_goes_through_the_director_into_the_save() -> void:
	var state := WorldState.create(42)
	var reply := _reply()
	reply["architecture"]["wall"] = 1 # schema-valid, but no wall color: clamped on the way
	var fake := FakeProvider.new(reply)
	var oracle := Oracle.new(fake, AICache.new())
	oracle.budget = AIBudget.new()
	var director := AssetDirector.new(oracle)
	director.kinds.assign([AssetKinds.find("style")]) # the fake only writes styles
	await director.settle(state)
	var tribe := state.tribe_names[0]
	assert_eq(AssetBook.source(state, "style", tribe), "fake", "the AI's style is stored")
	assert_eq(AssetBook.signature(state, "style", tribe), StyleKind.new().signature(state, tribe))
	var spec := AssetBook.spec(state, "style", tribe)
	assert_eq(spec["architecture"]["roof"], "dome", "the AI's roof")
	assert_true(int(spec["architecture"]["wall"]) in ArtPalette.GROUPS["walls"], "clamped before it was stored")
	assert_eq(fake.calls, state.tribe_count(), "one small call per tribe")
	assert_true(fake.last_request.prompt.contains(state.tribe_names[-1]), "the prompt names its tribe")
	assert_eq(AssetDirector.spec_or_offline(state, "style", tribe), spec, "views read the stored spec")
	var loaded := WorldState.from_dict(JSON.parse_string(state.to_json()))
	assert_eq(AssetBook.spec(loaded, "style", tribe), spec, "the style survives a save and a load")
	assert_eq(StyledBuildings.key("temple", AssetBook.spec(loaded, "style", tribe)), StyledBuildings.key("temple", spec), "and draws the same")
	# A failed call falls back to the offline style, so nothing waits.
	var other := WorldState.create(7)
	var broken := FakeProvider.new()
	broken.fail = true
	var fallback := Oracle.new(broken, AICache.new())
	fallback.budget = AIBudget.new()
	await AssetDirector.new(fallback).settle(other)
	for name: String in other.tribe_names:
		assert_true(not AssetBook.spec(other, "style", name).is_empty(), "%s has a style anyway" % name)


func test_buildings_and_villagers_wear_the_style() -> void:
	var kind := StyleKind.new()
	var holy: Dictionary = kind.accept(kind.offline(_facts("Theocracy", 4), 1), _facts("Theocracy", 4))
	var grey: Dictionary = kind.accept(kind.offline(_facts("Total State", 4, {"dystopia": 80, "dystopia_kind": "surveillance"}), 1), _facts("Total State", 4))
	var tint := Color(0.8, 0.4, 0.3)
	for type: String in StyledBuildings.TYPES:
		assert_ne(StyledBuildings.key(type, holy), StyledBuildings.key(type, grey), "%s: two styles, two keys" % type)
		for style: Dictionary in [holy, grey]:
			var model := BuildingArt.make(type, tint, 4, style)
			var body := model.get_node_or_null("Body") as MeshInstance3D
			assert_true(body != null and body.mesh.get_surface_count() == 1, "%s is one merged mesh" % type)
			assert_true(body != null and body.get_child_count() == 1, "%s has its outline hull" % type)
			model.free()
	assert_eq(StyledBuildings.key("mine", holy), "", "a mine keeps its own look")
	assert_eq(StyledBuildings.key("temple", {}), "", "no style, the default look")
	var plain := BuildingArt.make("temple", tint, 4)
	assert_true(plain.get_node_or_null("Body") != null, "the default temple still builds")
	plain.free()
	# Villagers: each class in its own color; the guard's sash, the commoner's accessory.
	var looks := {}
	for cls: String in ["commoner", "noble", "bonded", "guard"]:
		looks[cls] = VillagerArt.wear(VillagerArt.appearance(3, false, 30, false, tint), holy["fashion"], cls, tint)
	assert_eq(looks["guard"]["pattern"], "sash")
	assert_eq(looks["bonded"]["pattern"], "plain")
	assert_true(looks["noble"].get("noble", false), "nobles get the circlet and cloak")
	assert_ne(looks["noble"]["tunic"], looks["bonded"]["tunic"])
	var commoner := looks["commoner"] as Dictionary
	commoner["accessory"] = "hat"
	var figure := VillagerArt.make(commoner)
	var head := figure.get_meta("head") as Node3D
	assert_true(head.get_node_or_null("Accessory") != null, "the commoner wears the tribe's hat")
	VillagerArt.set_headgear(figure, "helmet", Color.GRAY, tint)
	assert_true(not (head.get_node("Accessory") as Node3D).visible, "the hat comes off under a helmet")
	figure.free()
	var unstyled := VillagerArt.wear(VillagerArt.appearance(3, false, 30, false, tint), {}, "bonded", tint)
	assert_true(not unstyled.has("pattern"), "no fashion, the old drab dress")
