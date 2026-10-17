extends TestCase


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
	var prophecy := Prophecy.from_proposal({"text": "Two fires.", "metric": "tribe_count", "op": ">=", "value": 2, "years_from_now": 300}, sim.state)
	assert_true(prophecy != null)
	var deadline := prophecy.deadline_year
	while prophecy.check(sim.state) == Prophecy.Status.PENDING:
		sim.advance(WorldState.MONTHS_PER_YEAR)
	assert_eq(prophecy.status, Prophecy.Status.FULFILLED, "seed 42 splits well before year %d" % deadline)


func test_proposal_years_are_clamped() -> void:
	var state := WorldState.create(42)
	var prophecy := Prophecy.from_proposal({"text": "Soon.", "metric": "tribe_count", "op": ">=", "value": 5, "years_from_now": 1}, state)
	assert_eq(prophecy.deadline_year, state.year() + Prophecy.MIN_YEARS)
