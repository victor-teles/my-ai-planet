extends TestCase
## The AssetDirector's loop with a stand-in kind: specs are written once per signature, kept in
## the world through a save, and written offline once asset calls have spent their share.

const FakeProvider := preload("res://tests/fixtures/ai/fake_provider.gd")


## A stand-in kind on the thought prompt: one spec per tribe, rewritten when its mark changes.
class MarkKind:
	extends AssetKind
	var marks := {} ## tribe -> what the spec should be written for

	func task() -> String:
		return "thought"

	func subjects(state: WorldState) -> Array[String]:
		var names: Array[String] = []
		names.assign(Array(state.tribe_names))
		return names

	func signature(_state: WorldState, subject: String) -> String:
		return String(marks.get(subject, "first"))

	func context(state: WorldState, subject: String) -> Dictionary:
		return {"tribe": subject, "mark": signature(state, subject)}

	func accept(reply: Dictionary, facts: Dictionary) -> Variant:
		var words := String(reply.get("thought", ""))
		return {"words": words, "tribe": facts["tribe"]} if words.begins_with("The") else null

	func offline(facts: Dictionary, seed_value: int) -> Dictionary:
		return {"thought": "The offline words of %s, %d." % [facts["tribe"], absi(seed_value) % 100]}


func _director(ai: AIProvider) -> AssetDirector:
	var director := AssetDirector.new(Oracle.new(ai, AICache.new()))
	director.kinds.assign([MarkKind.new()])
	return director


func test_writes_each_spec_once_per_signature() -> void:
	var state := WorldState.create(42, 2)
	var fake := FakeProvider.new({"thought": "The banner of the river folk."})
	var director := _director(fake)
	await director.settle(state)
	var tribe := state.tribe_names[0]
	assert_eq(fake.calls, state.tribe_count(), "one call per tribe")
	assert_eq(AssetBook.spec(state, "thought", tribe)["words"], "The banner of the river folk.")
	assert_eq(AssetBook.source(state, "thought", tribe), "fake")
	assert_eq(AssetBook.signature(state, "thought", tribe), "first")
	director.observe(state)
	assert_eq(fake.calls, state.tribe_count(), "nothing is asked again while the signatures hold")
	var kind: MarkKind = director.kinds[0]
	kind.marks[tribe] = "second"
	director.observe(state)
	assert_eq(fake.calls, state.tribe_count(), "checks wait for the next month")
	state.tick += 1
	while not state.is_month_start():
		state.tick += 1
	await director.settle(state)
	assert_eq(fake.calls, state.tribe_count() + 1, "only the changed subject is rewritten")
	assert_eq(AssetBook.signature(state, "thought", tribe), "second")


func test_rejected_and_failed_calls_fall_back_offline() -> void:
	var state := WorldState.create(7, 1)
	var fake := FakeProvider.new({"thought": "Not a spec this kind accepts."})
	var director := _director(fake)
	director.oracle.fallback = FakeProvider.new({}, "offline")
	(director.oracle.fallback as FakeProvider).fail = true
	await director.settle(state)
	var tribe := state.tribe_names[0]
	assert_true(String(AssetBook.spec(state, "thought", tribe)["words"]).begins_with("The offline words"), "the kind's offline spec stands in")
	assert_eq(AssetBook.source(state, "thought", tribe), "offline")
	assert_eq(director.written, {"ai": 0, "offline": 1})


func test_asset_calls_keep_to_their_share_of_the_budget() -> void:
	var state := WorldState.create(42, 3)
	var fake := FakeProvider.new({"thought": "The paid words."})
	var director := _director(fake)
	director.oracle.budget.max_calls = 10 # the share is a tenth: one paid asset call
	await director.settle(state)
	assert_eq(fake.calls, 1, "one call spends the share")
	assert_eq(director.written, {"ai": 1, "offline": state.tribe_count() - 1})
	for tribe: String in state.tribe_names:
		assert_true(AssetBook.has_spec(state, "thought", tribe), "%s still gets a spec" % tribe)


func test_specs_survive_save_and_load_and_never_touch_the_sim() -> void:
	var sim := Simulation.create(5)
	var plain := Simulation.create(5)
	var director := _director(FakeProvider.new({"thought": "The words that stay."}))
	await director.settle(sim.state)
	var loaded := WorldState.from_dict(JSON.parse_string(sim.state.to_json()))
	assert_eq(loaded.assets, sim.state.assets, "the specs come back as they were")
	sim.state.assets.clear()
	sim.advance(2 * WorldState.DAYS_PER_YEAR)
	plain.advance(2 * WorldState.DAYS_PER_YEAR)
	assert_eq(sim.state.checksum(), plain.state.checksum(), "writing specs changes nothing in the sim")


func test_spec_or_offline_never_waits() -> void:
	var state := WorldState.create(3)
	assert_eq(AssetDirector.spec_or_offline(state, "no_such_kind", "x"), {})
	AssetBook.put(state, "thought", "x", {"words": "stored"}, "first", "fake")
	assert_eq(AssetDirector.spec_or_offline(state, "thought", "x"), {"words": "stored"})
