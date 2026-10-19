extends TestCase

const FakeProvider := preload("res://tests/fixtures/ai/fake_provider.gd")


func _grim_state() -> WorldState:
	var state := WorldState.create(42)
	state.kindness = -9
	state.drought_months_left = 6
	for k: int in 4:
		state.record_intervention(-2)
	return state


func test_gentle_mode_caps_the_tone_and_tells_the_prompts() -> void:
	var state := _grim_state()
	assert_eq(state.tone(), 5, "a grim world")
	var oracle := Oracle.new(OfflineTemplatesProvider.new(), AICache.new())
	oracle.gentle = false
	assert_eq(oracle.tone_for(state), 5)
	assert_true(not oracle.prophecy_request(state).system.contains("Gentle Mode"))
	oracle.gentle = true
	assert_eq(oracle.tone_for(state), Oracle.GENTLE_TONE)
	for request: AIRequest in [oracle.prophecy_request(state), oracle.dilemma_request(state), oracle.thought_request(state, 0)]:
		assert_true(request.system.contains("Tone level: 2 "), request.task)
		assert_true(request.system.contains("Gentle Mode is on"), request.task)


func test_gentle_mode_rejects_what_the_normal_ceiling_allows() -> void:
	var state := WorldState.create(42)
	var thought := {"thought": "I still dream of the massacre at the ford."}
	for gentle: bool in [false, true]:
		var oracle := Oracle.new(FakeProvider.new(thought), AICache.new())
		oracle.gentle = gentle
		var said := await oracle.request_thought(state, 0)
		assert_eq(said == thought["thought"], not gentle, "gentle %s: %s" % [gentle, said])
		assert_true(not said.is_empty())


func test_environment_switch() -> void:
	OS.set_environment("MYAIPLANET_GENTLE", "1")
	assert_true(Oracle.new(OfflineTemplatesProvider.new(), AICache.new()).gentle)
	OS.unset_environment("MYAIPLANET_GENTLE")
	assert_true(not Oracle.new(OfflineTemplatesProvider.new(), AICache.new()).gentle)


func test_gentle_mode_is_reported_in_usage() -> void:
	var oracle := Oracle.new(OfflineTemplatesProvider.new(), AICache.new())
	oracle.gentle = true
	assert_eq(oracle.usage()["gentle"], true)
