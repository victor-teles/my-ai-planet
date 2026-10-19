extends TestCase
## Cost guardrails: the session budget, tier routing and the circuit breaker, with fake providers
## and a fake clock.

const FakeProvider := preload("res://tests/fixtures/ai/fake_provider.gd")

var now := 1000.0


func _thought(text: String = "The rain will come back, I am sure of it.") -> Dictionary:
	return {"thought": text}


func _oracle(fake: AIProvider) -> Oracle:
	var oracle := Oracle.new(fake, AICache.new())
	oracle.budget = AIBudget.new()
	oracle.breaker.clock = func() -> float: return now
	return oracle


## Asks a thought with a fresh cache, so every ask is a new question.
func _ask(oracle: Oracle, state: WorldState) -> String:
	oracle.cache = AICache.new()
	return await oracle.request_thought(state, 0)


func test_tiers_follow_the_routing_table_and_drop_when_money_runs_low() -> void:
	var budget := AIBudget.new()
	assert_eq(budget.route("prophecy"), AIRequest.Tier.LARGE)
	assert_eq(budget.route("chronicle"), AIRequest.Tier.LARGE)
	assert_eq(budget.route("destiny"), AIRequest.Tier.LARGE)
	assert_eq(budget.route("dilemma"), AIRequest.Tier.MEDIUM)
	assert_eq(budget.route("thought"), AIRequest.Tier.SMALL)
	budget.spent_usd = budget.cap_usd * 0.8
	assert_eq(budget.route("prophecy"), AIRequest.Tier.MEDIUM, "most of the money is spent")
	assert_eq(budget.route("dilemma"), AIRequest.Tier.SMALL)
	assert_eq(budget.route("thought"), AIRequest.Tier.SMALL, "small stays small")
	budget.routes["thought"] = AIRequest.Tier.LARGE
	assert_eq(budget.route("thought"), AIRequest.Tier.MEDIUM, "an override is routed too")


func test_spending_cap_sends_the_rest_of_the_session_offline() -> void:
	var state := WorldState.create(42)
	var fake := FakeProvider.new(_thought())
	fake.cost = 0.04
	var oracle := _oracle(fake)
	var reasons: Array[String] = []
	oracle.went_offline.connect(func(reason: String) -> void: reasons.append(reason))
	for k: int in 3:
		assert_eq(await _ask(oracle, state), _thought()["thought"])
	assert_eq(fake.calls, 3)
	assert_true(oracle.is_offline(), "$0.12 spent of $0.10")
	assert_eq(reasons.size(), 1, "the drop is announced once")
	var thought := await _ask(oracle, state)
	assert_eq(fake.calls, 3, "no more paid calls")
	assert_ne(thought, _thought()["thought"], "the offline templates answer")
	assert_true(not thought.is_empty())
	var usage := oracle.usage()
	assert_eq(usage["offline"], true)
	assert_true(String(usage["offline_reason"]).begins_with("budget"), usage["offline_reason"])
	assert_true(is_equal_approx(usage["budget"]["spent_usd"], 0.12))


func test_call_cap() -> void:
	var state := WorldState.create(42)
	var fake := FakeProvider.new(_thought())
	var oracle := _oracle(fake)
	oracle.budget.max_calls = 2
	for k: int in 4:
		await _ask(oracle, state)
	assert_eq(fake.calls, 2)
	assert_true(oracle.offline_reason().contains("2 of 2"), oracle.offline_reason())


func test_zero_means_unlimited() -> void:
	var state := WorldState.create(42)
	var fake := FakeProvider.new(_thought())
	fake.cost = 1.0
	var oracle := _oracle(fake)
	oracle.budget.cap_usd = 0.0
	oracle.budget.max_calls = 0
	for k: int in 5:
		await _ask(oracle, state)
	assert_eq(fake.calls, 5)
	assert_true(not oracle.is_offline())


func test_free_providers_never_count() -> void:
	var state := WorldState.create(42)
	var fake := FakeProvider.new(_thought())
	fake.free = true
	fake.cost = 1.0
	var oracle := _oracle(fake)
	oracle.budget.max_calls = 2
	for k: int in 5:
		await _ask(oracle, state)
	assert_eq(fake.calls, 5)
	assert_eq(oracle.budget.paid_calls, 0)
	assert_eq(oracle.budget.spent_usd, 0.0)
	assert_eq(oracle.budget.route("prophecy"), AIRequest.Tier.LARGE, "no downgrade either")
	assert_true(not oracle.is_offline())


func test_circuit_breaker_skips_a_failing_provider_for_a_while() -> void:
	var state := WorldState.create(42)
	var fake := FakeProvider.new(_thought())
	fake.fail = true
	var oracle := _oracle(fake)
	await _ask(oracle, state)
	assert_eq(fake.calls, 2, "tried, retried, then offline")
	await _ask(oracle, state)
	assert_eq(fake.calls, 3, "the third failure in a row opens the breaker")
	var thought := await _ask(oracle, state)
	assert_eq(fake.calls, 3, "skipped while open")
	assert_true(not thought.is_empty(), "offline answers meanwhile")
	assert_true(oracle.offline_reason().contains("3 times"), oracle.offline_reason())
	assert_true(not oracle.is_offline(), "not for good")
	now += oracle.breaker.cooldown_sec - 1.0
	await _ask(oracle, state)
	assert_eq(fake.calls, 3, "still cooling down")
	now += 2.0
	fake.fail = false
	assert_eq(await _ask(oracle, state), _thought()["thought"], "after the cooldown it gets another chance")
	assert_eq(fake.calls, 4)
	assert_eq(oracle.offline_reason(), "")


func test_breaker_reopens_at_once_if_the_second_chance_fails() -> void:
	var breaker := CircuitBreaker.new()
	breaker.clock = func() -> float: return now
	for k: int in breaker.threshold - 1:
		breaker.failure("p")
	assert_true(breaker.allows("p"))
	breaker.failure("p")
	assert_true(breaker.is_open("p"))
	assert_true(is_equal_approx(breaker.seconds_left("p"), breaker.cooldown_sec))
	assert_true(breaker.allows("q"), "other providers are not affected")
	now += breaker.cooldown_sec
	assert_true(breaker.allows("p"), "half open")
	breaker.failure("p")
	assert_true(breaker.is_open("p"), "one more failure closes the door again")
	now += breaker.cooldown_sec
	breaker.success("p")
	breaker.failure("p")
	assert_true(breaker.allows("p"), "a success starts the count over")


func test_budget_from_environment() -> void:
	OS.set_environment("MYAIPLANET_AI_BUDGET", "0.5")
	assert_true(is_equal_approx(AIBudget.from_environment().cap_usd, 0.5))
	OS.unset_environment("MYAIPLANET_AI_BUDGET")
	assert_true(is_equal_approx(AIBudget.from_environment().cap_usd, AIBudget.DEFAULT_CAP_USD))
