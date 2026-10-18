extends TestCase

const FakeProvider := preload("res://tests/fixtures/ai/fake_provider.gd")
const CHRONICLE := {"title": "The Long Rain", "text": "The god sent rain when the springs failed, and the \"Magavik\" fields\ngrew green again.", "causes": ["the god sent rain"]}


class BrokenProvider:
	extends AIProvider
	var reply: Dictionary

	func _init(fake_reply: Dictionary) -> void:
		reply = fake_reply

	func get_id() -> String:
		return "broken"

	func is_available() -> bool:
		return true

	func complete(_request: AIRequest) -> AIResponse:
		return AIResponse.success(get_id(), reply)


func test_offline_prophecy_is_valid() -> void:
	var state := WorldState.create(42)
	var prophecy := await Oracle.new(OfflineTemplatesProvider.new()).request_prophecy(state)
	assert_true(prophecy != null, "offline provider should always produce a prophecy")
	if prophecy:
		assert_eq(prophecy.status, Prophecy.Status.PENDING)


func test_schema_breaking_reply_falls_back_to_offline() -> void:
	var oracle := Oracle.new(BrokenProvider.new({"text": "Doom.", "metric": "happiness"}))
	var prophecy := await oracle.request_prophecy(WorldState.create(42))
	assert_true(prophecy != null, "should fall back")
	assert_eq(oracle.last_response.provider_id, "offline")


func test_rule_breaking_reply_falls_back_to_offline() -> void:
	# Valid shape, but already true now, so it isn't a prediction.
	var reply := {"text": "There will be at least one tribe.", "metric": "tribe_count", "op": ">=", "value": 1, "years_from_now": 20}
	var oracle := Oracle.new(BrokenProvider.new(reply))
	var prophecy := await oracle.request_prophecy(WorldState.create(42))
	assert_true(prophecy != null and prophecy.target != 1, "should use the offline prophecy instead")


func test_prophecy_resolves() -> void:
	var sim := Simulation.create(42)
	var target := sim.state.total_population() + 10
	var prophecy := Prophecy.from_proposal({"text": "More cradles.", "metric": "total_population", "op": ">=", "value": target, "years_from_now": 60}, sim.state)
	assert_true(prophecy != null)
	var deadline := prophecy.deadline_year
	while prophecy.check(sim.state) == Prophecy.Status.PENDING:
		sim.advance(WorldState.DAYS_PER_MONTH)
	assert_eq(prophecy.status, Prophecy.Status.FULFILLED, "seed 42 grows by 10 well before year %d" % deadline)


func test_offline_prophecies_are_always_playable() -> void:
	for seed_value: int in [1, 2, 3, 4, 5, 6]:
		var sim := Simulation.create(seed_value)
		sim.advance(seed_value * 7 * WorldState.DAYS_PER_YEAR)
		var oracle := Oracle.new(OfflineTemplatesProvider.new())
		var prophecy := await oracle.request_prophecy(sim.state)
		assert_true(prophecy != null, "seed %d: the offline prophecy passes the sim's rules" % seed_value)
		if prophecy:
			assert_true(prophecy.deadline_year - sim.state.year() <= 40, "a horizon the player can watch")


func test_new_metrics() -> void:
	var state := WorldState.create(42, 1)
	assert_eq(Prophecy.measure("building_count", state), state.count_buildings(state.tribe_names[0], "tent"), "tents count, the fire doesn't")
	assert_eq(Prophecy.measure("discoveries", state), 0, "the basics aren't discoveries")
	state.learn(0, "pottery")
	state.learn(0, "fishing")
	assert_eq(Prophecy.measure("discoveries", state), 2)
	var prophecy := Prophecy.from_proposal({"text": "A storehouse.", "metric": "building_count", "op": ">=", "value": 99, "years_from_now": 20}, state)
	assert_true(prophecy != null and prophecy.metric == "building_count")


func test_proposal_years_are_clamped() -> void:
	var state := WorldState.create(42)
	var prophecy := Prophecy.from_proposal({"text": "Soon.", "metric": "tribe_count", "op": ">=", "value": 5, "years_from_now": 1}, state)
	assert_eq(prophecy.deadline_year, state.year() + Prophecy.MIN_YEARS)


func test_offline_thoughts_come_from_the_persons_life() -> void:
	var sim := Simulation.create(7)
	sim.advance(15 * WorldState.DAYS_PER_YEAR)
	var oracle := Oracle.new(OfflineTemplatesProvider.new())
	var lines := {}
	for p: int in sim.state.person_ids.size():
		var thought := oracle.offline_thought(sim.state, p)
		assert_true(thought.length() >= 10, "%s thinks something: '%s'" % [sim.state.person_names[p], thought])
		assert_eq(oracle.offline_thought(sim.state, p), thought, "the same thought until the year turns")
		assert_true(not thought.contains("%"), "no blanks left: " + thought)
		lines[thought] = true
	assert_true(lines.size() >= sim.state.total_population() / 3, "people think different things")


func _prophecy_reply(state: WorldState) -> Dictionary:
	return {"text": "The cradles will fill.", "metric": "total_population", "op": ">=", "value": state.total_population() + 30, "years_from_now": 20}


func _oracle(ai: AIProvider) -> Oracle:
	var oracle := Oracle.new(ai, AICache.new())
	oracle.budget = AIBudget.new()
	oracle.gentle = false
	return oracle


func test_requests_carry_version_and_tier() -> void:
	var sim := Simulation.create(7)
	sim.advance(3 * WorldState.DAYS_PER_YEAR)
	var oracle := _oracle(OfflineTemplatesProvider.new())
	var prophecy := oracle.prophecy_request(sim.state)
	assert_eq(prophecy.prompt_version, AIPrompts.version("prophecy"))
	assert_eq(prophecy.tier, AIRequest.Tier.LARGE)
	assert_eq(oracle.dilemma_request(sim.state).tier, AIRequest.Tier.MEDIUM)
	assert_eq(oracle.thought_request(sim.state, 0).tier, AIRequest.Tier.SMALL)
	assert_true(prophecy.system.contains(sim.state.disposition_text()), "the prompt knows the god's disposition")
	oracle.prompt_versions["prophecy"] = "v1"
	var old := oracle.prophecy_request(sim.state)
	assert_eq(old.prompt_version, "v1")
	assert_true(not old.system.contains("Hard limits"), "the old version still loads as it was")


func test_usage_meter_counts_per_provider_and_task() -> void:
	var state := WorldState.create(42)
	var fake := FakeProvider.new(_prophecy_reply(state))
	fake.cost = 0.002
	var oracle := _oracle(fake)
	assert_true(await oracle.request_prophecy(state) != null)
	await oracle.request_thought(state, 0) # the fake's prophecy breaks the thought schema: offline answers
	var usage := oracle.usage()
	var by_fake: Dictionary = usage["providers"]["fake"]
	assert_eq(by_fake["calls"], 3, "one prophecy, a thought and its retry")
	assert_eq(by_fake["failures"], 2)
	assert_eq(by_fake["input_tokens"], 300)
	assert_eq(by_fake["output_tokens"], 60)
	assert_true(is_equal_approx(by_fake["cost_usd"], 0.006))
	assert_true(by_fake.has("avg_latency_ms"))
	assert_eq(usage["providers"]["offline"]["calls"], 1)
	assert_eq(usage["tasks"]["prophecy"]["calls"], 1)
	assert_eq(usage["tasks"]["thought"]["calls"], 3)
	assert_eq(usage["total"]["calls"], 4)
	assert_eq(oracle.calls, 4, "the debug overlay's counters still work")
	assert_true(is_equal_approx(oracle.cost_usd, 0.006))
	assert_eq(oracle.last_response.provider_id, "offline")
	assert_eq(usage["offline"], false)
	assert_eq(usage["offline_reason"], "")


func test_a_failed_call_is_retried_once_then_offline() -> void:
	var fake := FakeProvider.new()
	fake.fail = true
	var oracle := _oracle(fake)
	var prophecy := await oracle.request_prophecy(WorldState.create(42))
	assert_true(prophecy != null, "offline answered")
	assert_eq(fake.calls, 2, "one retry")
	assert_eq(oracle.last_response.provider_id, "offline")
	assert_eq(oracle.usage()["providers"]["fake"]["failures"], 2)


func test_identical_requests_in_flight_share_one_call() -> void:
	var state := WorldState.create(42)
	var fake := FakeProvider.new(_prophecy_reply(state))
	fake.slow = true
	var oracle := _oracle(fake)
	var results: Array[Prophecy] = []
	var ask := func() -> void: results.append(await oracle.request_prophecy(state))
	ask.call()
	ask.call()
	assert_eq(fake.calls, 1, "the second caller waits for the first call")
	assert_eq(results.size(), 0)
	fake.released.emit()
	assert_eq(results.size(), 2, "both callers got an answer")
	assert_true(results[0] != null and results[1] != null and results[0].text == results[1].text)
	assert_eq(oracle.usage()["providers"]["fake"]["cache_hits"], 1, "the shared call counts as a free hit")
	await oracle.request_prophecy(state)
	assert_eq(fake.calls, 1, "and the answer is cached now")


func test_chronicle_streams_readable_text() -> void:
	var fake := FakeProvider.new(CHRONICLE)
	fake.streaming = true
	var oracle := _oracle(fake)
	var sim := Simulation.create(42)
	sim.advance(WorldState.DAYS_PER_YEAR)
	var prophecy := Prophecy.from_proposal(_prophecy_reply(sim.state), sim.state)
	prophecy.status = Prophecy.Status.BROKEN
	prophecy.resolved_tick = sim.state.tick
	var seen: Array[String] = []
	var chronicle := await oracle.request_chronicle(sim.state, prophecy, func(text: String) -> void: seen.append(text))
	assert_eq(chronicle["text"], CHRONICLE["text"])
	assert_true(seen.size() >= 3, "the story arrived in pieces: %s" % [seen])
	assert_eq(seen[-1], CHRONICLE["text"], "the last piece is the whole accepted text")
	for piece: String in seen:
		assert_true(String(CHRONICLE["text"]).begins_with(piece), "only story text, decoded: '%s'" % piece)
		assert_true(not piece.contains("{") and not piece.contains("title"), "no JSON shown")


func test_destiny_without_streaming_still_calls_on_text_once() -> void:
	var state := WorldState.create(42)
	state.destiny = {"kind": "ashes", "tribe": state.tribe_names[0], "year": 0}
	var seen: Array[String] = []
	var chapter := await _oracle(OfflineTemplatesProvider.new()).request_destiny(state, func(text: String) -> void: seen.append(text))
	assert_eq(seen, [String(chapter["text"])] as Array[String])
