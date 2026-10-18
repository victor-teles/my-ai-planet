extends TestCase

const FakeProvider := preload("res://tests/fixtures/ai/fake_provider.gd")


func _request(prompt: String = "the world") -> AIRequest:
	var request := AIRequest.new()
	request.task = "thought"
	request.prompt_version = "v2"
	request.tier = AIRequest.Tier.SMALL
	request.system = "system"
	request.prompt = prompt
	request.schema = {"type": "object"}
	return request


func _prophecy_reply(state: WorldState) -> Dictionary:
	return {"text": "The cradles will fill.", "metric": "total_population", "op": ">=", "value": state.total_population() + 30, "years_from_now": 20}


func test_key_covers_everything_that_shapes_an_answer() -> void:
	var base := AICache.key("fake", _request())
	assert_eq(AICache.key("fake", _request()), base, "the same question, the same key")
	assert_ne(AICache.key("other", _request()), base, "provider")
	assert_ne(AICache.key("fake", _request("another world")), base, "prompt")
	var changes: Array[Callable] = [
		func(r: AIRequest) -> void: r.task = "dilemma",
		func(r: AIRequest) -> void: r.prompt_version = "v1",
		func(r: AIRequest) -> void: r.tier = AIRequest.Tier.LARGE,
		func(r: AIRequest) -> void: r.system = "other system",
		func(r: AIRequest) -> void: r.schema = {"type": "string"},
	]
	for change: Callable in changes:
		var request := _request()
		change.call(request)
		assert_ne(AICache.key("fake", request), base)


func test_least_recently_used_is_forgotten_first() -> void:
	var cache := AICache.new(2)
	cache.store("a", {"n": 1})
	cache.store("b", {"n": 2})
	assert_eq(cache.lookup("a"), {"n": 1})
	cache.store("c", {"n": 3})
	assert_eq(cache.size(), 2)
	assert_eq(cache.lookup("b"), {}, "b was used least recently")
	assert_eq(cache.lookup("a"), {"n": 1})
	assert_eq(cache.lookup("c"), {"n": 3})
	assert_eq(cache.hits, 3)
	assert_eq(cache.misses, 1)


func test_replies_are_copies() -> void:
	var cache := AICache.new()
	var reply := {"list": [1]}
	cache.store("k", reply)
	reply["list"].append(2)
	var first := cache.lookup("k")
	first["list"].append(3)
	assert_eq(cache.lookup("k"), {"list": [1]})


func test_persists_on_disk_when_asked() -> void:
	var dir := "user://test_ai_cache/"
	var cache := AICache.new(4, dir)
	cache.store("k", {"thought": "Rain soon."})
	var later := AICache.new(4, dir)
	assert_eq(later.lookup("k"), {"thought": "Rain soon."}, "a new session finds it on disk")
	later.forget("k")
	assert_eq(AICache.new(4, dir).lookup("k"), {})
	for k: int in 6:
		cache.store("k%d" % k, {"n": k})
	assert_eq(DirAccess.get_files_at(dir).size(), 6)
	AICache.new(1, dir)
	assert_eq(DirAccess.get_files_at(dir).size(), AICache.DISK_FACTOR, "the disk is pruned to a limit")
	for file: String in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(dir).path_join(file))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir))


func test_oracle_answers_repeats_from_the_cache_for_free() -> void:
	var state := WorldState.create(42)
	var fake := FakeProvider.new(_prophecy_reply(state))
	fake.cost = 0.01
	var oracle := Oracle.new(fake, AICache.new())
	oracle.budget = AIBudget.new()
	var first := await oracle.request_prophecy(state)
	var second := await oracle.request_prophecy(state)
	assert_true(first != null and second != null and first.text == second.text)
	assert_eq(fake.calls, 1, "asked once")
	assert_true(oracle.last_response.cached, "the debug overlay can tell")
	var usage := oracle.usage()
	assert_eq(usage["providers"]["fake"]["cache_hits"], 1)
	assert_true(is_equal_approx(usage["providers"]["fake"]["cost_usd"], 0.01), "paid once")
	assert_true(is_equal_approx(oracle.budget.spent_usd, 0.01))
	oracle.prompt_versions["prophecy"] = "v1"
	await oracle.request_prophecy(state)
	assert_eq(fake.calls, 2, "another prompt version is another question")


func test_rejected_replies_are_not_cached() -> void:
	var state := WorldState.create(42)
	var fake := FakeProvider.new({"text": "Doom.", "metric": "happiness"})
	var oracle := Oracle.new(fake, AICache.new())
	await oracle.request_prophecy(state)
	assert_eq(oracle.cache.size(), 0)
	fake.reply = _prophecy_reply(state)
	assert_true(await oracle.request_prophecy(state) != null)
	assert_eq(fake.calls, 3, "two rejected tries, then a fresh call")
	assert_eq(oracle.cache.size(), 1)
