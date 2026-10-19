extends TestCase
## The AI Settings store (AISettings: the saved file, the environment winning, building the
## provider) and per-tier routing (AIRouter), with fake providers.

const FakeProvider := preload("res://tests/fixtures/ai/fake_provider.gd")
const ENV: Array[String] = ["MYAIPLANET_AI", "MYAIPLANET_MODEL", "MYAIPLANET_AI_BUDGET", "MYAIPLANET_GENTLE", "OPENAI_API_KEY"]
const THOUGHT := {"thought": "The rain will come back, I am sure of it."}

var _path := scratch_path("ai_settings.cfg")
var _saved_env := {}


## Tests run in the developer's own environment: set these aside and put them back after.
func _clear_env() -> void:
	for variable: String in ENV:
		_saved_env[variable] = OS.get_environment(variable)
		OS.unset_environment(variable)


func _restore_env() -> void:
	for variable: String in _saved_env:
		if String(_saved_env[variable]).is_empty():
			OS.unset_environment(variable)
		else:
			OS.set_environment(variable, _saved_env[variable])


func _remove_file() -> void:
	if FileAccess.file_exists(_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_path))


func _prophecy(state: WorldState) -> Dictionary:
	return {"text": "The cradles will fill.", "metric": "total_population", "op": ">=", "value": state.total_population() + 30, "years_from_now": 20}


func _oracle(ai: AIProvider) -> Oracle:
	var oracle := Oracle.new(ai, AICache.new())
	oracle.budget = AIBudget.new()
	oracle.gentle = false
	return oracle


func test_settings_round_trip() -> void:
	_remove_file()
	var settings := AISettings.load_from(_path)
	assert_true(not settings.saved, "no file yet: defaults")
	assert_eq(settings.tiers, {"small": AISettings.AUTO, "medium": AISettings.AUTO, "large": AISettings.AUTO})
	assert_eq(settings.cap_usd, AIBudget.DEFAULT_CAP_USD)
	settings.tiers = {"small": "ollama", "medium": "anthropic", "large": "anthropic"}
	settings.set_provider("ollama", {"base_url": "http://192.168.1.5:11434/v1", "models": {"small": "qwen3:8b"}, "strict_schema": false})
	settings.set_provider("anthropic", {"api_key": "sk-test-123", "models": {"large": "claude-opus-5-5"}})
	settings.set_provider("claude_code", {"path": "/opt/bin/claude"})
	settings.cap_usd = 0.25
	settings.max_calls = 40
	settings.gentle = true
	assert_eq(settings.save(), OK)
	var raw := FileAccess.get_file_as_bytes(_path).hex_encode()
	assert_true(not raw.contains("sk-test-123".to_utf8_buffer().hex_encode()), "keys are not saved in plain text")
	var loaded := AISettings.load_from(_path)
	assert_true(loaded.saved)
	assert_eq(loaded.tiers, settings.tiers)
	assert_eq(loaded.provider("ollama"), {
		"api_key": "", "base_url": "http://192.168.1.5:11434/v1", "path": "",
		"models": {"small": "qwen3:8b", "medium": "", "large": ""}, "strict_schema": false,
	})
	assert_eq(loaded.provider("anthropic")["api_key"], "sk-test-123")
	assert_eq(loaded.provider("anthropic")["models"]["large"], "claude-opus-5-5")
	assert_eq(loaded.provider("claude_code")["path"], "/opt/bin/claude")
	assert_eq(loaded.provider("gemini")["strict_schema"], true, "unsaved providers have every field")
	assert_true(is_equal_approx(loaded.cap_usd, 0.25))
	assert_eq(loaded.max_calls, 40)
	assert_eq(loaded.gentle, true)
	_remove_file()


func test_bad_saved_values_fall_back() -> void:
	var file := ConfigFile.new()
	file.set_value("routing", "small", "nonsense")
	file.set_value("routing", "large", "gemini")
	file.set_value("budget", "cap_usd", -3.0)
	file.set_value("budget", "max_calls", -1)
	file.save(_path)
	var loaded := AISettings.load_from(_path)
	assert_eq(loaded.tiers, {"small": AISettings.AUTO, "medium": AISettings.AUTO, "large": "gemini"})
	assert_eq(loaded.cap_usd, 0.0)
	assert_eq(loaded.max_calls, 0)
	_remove_file()


func test_settings_build_one_provider_per_tier() -> void:
	_clear_env()
	var settings := AISettings.new()
	settings.file_path = _path
	settings.tiers = {"small": "ollama", "medium": "offline", "large": "ollama"}
	settings.set_provider("ollama", {"base_url": "http://127.0.0.1:9/v1", "models": {"small": "tiny:1b", "large": "big:8b"}})
	var router := settings.build_provider() as AIRouter
	assert_true(router != null, "different tiers: a router")
	if router:
		assert_eq(router.route(AIRequest.Tier.SMALL).get_id(), "ollama")
		assert_eq(router.route(AIRequest.Tier.MEDIUM).get_id(), "offline")
		assert_true(router.route(AIRequest.Tier.SMALL) == router.route(AIRequest.Tier.LARGE), "tiers on one provider share it")
		assert_eq(router.get_id(), "ollama+offline")
		var ollama := router.route(AIRequest.Tier.LARGE) as OpenAICompatibleProvider
		assert_eq(ollama.get_base_url(), "http://127.0.0.1:9/v1", "the saved server")
	settings.tiers = {"small": "offline", "medium": "offline", "large": "offline"}
	assert_true(settings.build_provider() is OfflineTemplatesProvider, "one provider for every tier: no router")
	var oracle := _oracle(OfflineTemplatesProvider.new())
	settings.tiers = {"small": "ollama", "medium": "ollama", "large": "ollama"}
	settings.cap_usd = 0.3
	settings.max_calls = 12
	settings.gentle = true
	settings.apply(oracle)
	assert_eq(oracle.provider.get_id(), "ollama")
	assert_true(is_equal_approx(oracle.budget.cap_usd, 0.3))
	assert_eq(oracle.budget.max_calls, 12)
	assert_eq(oracle.gentle, true)
	_restore_env()


func test_environment_wins_over_the_settings() -> void:
	_clear_env()
	var settings := AISettings.new()
	settings.tiers = {"small": "ollama", "medium": "ollama", "large": "ollama"}
	settings.set_provider("openai", {"api_key": "saved-key", "models": {"small": "a", "medium": "b", "large": "c"}})
	settings.cap_usd = 0.25
	assert_eq(settings.effective_config("openai")["api_key"], "saved-key")
	assert_eq(AISettings.environment_overrides(), PackedStringArray())
	OS.set_environment("MYAIPLANET_AI", "offline")
	OS.set_environment("OPENAI_API_KEY", "env-key")
	OS.set_environment("MYAIPLANET_MODEL", "tiny")
	OS.set_environment("MYAIPLANET_AI_BUDGET", "0.5")
	OS.set_environment("MYAIPLANET_GENTLE", "1")
	assert_true(settings.build_provider() is OfflineTemplatesProvider, "MYAIPLANET_AI picks the provider")
	var config := settings.effective_config("openai")
	assert_eq(config["api_key"], "env-key", "the environment's key wins")
	assert_eq(config["models"], {"small": "tiny", "medium": "tiny", "large": "tiny"})
	assert_true(is_equal_approx(settings.effective_cap_usd(), 0.5))
	assert_eq(settings.effective_gentle(), true)
	var oracle := _oracle(FakeProvider.new())
	settings.apply(oracle)
	assert_true(oracle.provider is OfflineTemplatesProvider)
	assert_true(is_equal_approx(oracle.budget.cap_usd, 0.5))
	assert_eq(oracle.gentle, true)
	var overrides := AISettings.environment_overrides()
	assert_true("MYAIPLANET_AI=offline" in overrides and "OPENAI_API_KEY" in overrides, str(overrides))
	assert_true(not ", ".join(overrides).contains("env-key"), "never shows a key")
	_restore_env()


func test_router_dispatches_by_tier() -> void:
	var state := WorldState.create(42)
	var local := FakeProvider.new(THOUGHT, "local")
	local.free = true
	var cloud := FakeProvider.new(_prophecy(state), "cloud")
	cloud.cost = 0.01
	var oracle := _oracle(AIRouter.new({AIRequest.Tier.SMALL: local, AIRequest.Tier.MEDIUM: cloud, AIRequest.Tier.LARGE: cloud}))
	assert_eq(await oracle.request_thought(state, 0), THOUGHT["thought"])
	assert_eq([local.calls, cloud.calls], [1, 0], "thoughts go to the small tier's provider")
	assert_eq(local.last_request.tier, AIRequest.Tier.SMALL)
	assert_true(await oracle.request_prophecy(state) != null)
	assert_eq([local.calls, cloud.calls], [1, 1], "prophecies go to the large tier's provider")
	assert_eq(oracle.last_response.provider_id, "cloud")
	var usage := oracle.usage()
	var providers: Dictionary = usage["providers"]
	assert_eq(providers.keys(), ["local", "cloud"], "usage is kept per provider that answered")
	assert_eq(providers["local"]["calls"], 1)
	assert_true(is_equal_approx(providers["cloud"]["cost_usd"], 0.01))
	assert_eq(usage["budget"]["paid_calls"], 1, "the free local model never counts")
	await oracle.request_thought(state, 0)
	assert_eq(local.calls, 1, "cached per provider")
	assert_eq(oracle.usage()["providers"]["local"]["cache_hits"], 1)


func test_router_forwards_ids_free_and_streaming() -> void:
	var local := FakeProvider.new(THOUGHT, "local")
	local.free = true
	var cloud := FakeProvider.new({"title": "T", "text": "A long story, told slowly.", "causes": []}, "cloud")
	var mixed := AIRouter.new({AIRequest.Tier.SMALL: local, AIRequest.Tier.MEDIUM: local, AIRequest.Tier.LARGE: cloud})
	assert_eq(mixed.get_id(), "local+cloud")
	assert_eq(mixed.members().size(), 2)
	assert_true(not mixed.is_free(), "a paid tier makes it paid")
	assert_true(AIRouter.new({AIRequest.Tier.SMALL: local, AIRequest.Tier.MEDIUM: local, AIRequest.Tier.LARGE: local}).is_free())
	assert_eq(AIRouter.new({AIRequest.Tier.SMALL: local, AIRequest.Tier.MEDIUM: local, AIRequest.Tier.LARGE: local}).get_id(), "local")
	assert_eq(AIRouter.new({AIRequest.Tier.LARGE: cloud}).route(AIRequest.Tier.SMALL).get_id(), "offline", "a missing tier is offline")
	assert_true(not mixed.supports_streaming())
	cloud.streaming = true
	assert_true(mixed.supports_streaming(), "a streaming tier")
	var big := AIRequest.new()
	big.tier = AIRequest.Tier.LARGE
	var small := AIRequest.new()
	small.tier = AIRequest.Tier.SMALL
	assert_true(mixed.provider_for(big) == cloud and mixed.provider_for(small) == local)
	var pieces: Array[String] = []
	var on_text := func(text: String) -> void: pieces.append(text)
	var streamed := await mixed.complete_streaming(big, on_text)
	assert_eq(streamed.provider_id, "cloud")
	assert_eq(pieces.size(), cloud.chunks, "the streaming tier streams")
	pieces.clear()
	var plain := await mixed.complete_streaming(small, on_text)
	assert_true(plain.ok and plain.provider_id == "local", "a tier that can't stream just answers")
	assert_eq(pieces.size(), 0)


func test_offline_state_with_a_router() -> void:
	var cloud := FakeProvider.new({}, "cloud")
	var half := _oracle(AIRouter.new({AIRequest.Tier.SMALL: OfflineTemplatesProvider.new(), AIRequest.Tier.LARGE: cloud, AIRequest.Tier.MEDIUM: cloud}))
	assert_eq(half.offline_reason(), "", "one tier offline is not the Oracle offline")
	assert_true(half.offline_for("thought"), "thoughts route to the offline stories")
	assert_true(not half.offline_for("prophecy"))
	var none := _oracle(AIRouter.new({}))
	assert_true(none.is_offline())
	assert_true(none.offline_reason().begins_with("no AI provider"))


func test_new_settings_bring_a_spent_session_back() -> void:
	var state := WorldState.create(42)
	var cloud := FakeProvider.new(THOUGHT, "cloud")
	cloud.cost = 0.2
	var oracle := _oracle(cloud)
	oracle.budget.cap_usd = 0.1
	var reasons: Array[String] = []
	oracle.went_offline.connect(func(reason: String) -> void: reasons.append(reason))
	await oracle.request_thought(state, 0)
	assert_eq(reasons.size(), 1, "the budget ran out")
	assert_true(oracle.offline_reason().begins_with("budget"))
	assert_true(oracle.offline_for("thought"))
	var settings := AISettings.new()
	settings.cap_usd = 1.0
	_clear_env()
	oracle.budget.cap_usd = settings.effective_cap_usd()
	_restore_env()
	oracle.set_provider(cloud)
	assert_eq(oracle.offline_reason(), "", "a higher cap lets the Oracle speak again")


func test_settings_panel_applies_to_the_running_oracle() -> void:
	_clear_env()
	_remove_file()
	var oracle := _oracle(OfflineTemplatesProvider.new())
	var stored := AISettings.new()
	stored.file_path = _path
	var panel := AISettingsPanel.new()
	panel.open(oracle, stored)
	assert_true(panel.visible)
	panel.pick_provider("ollama")
	panel.set_server("http://127.0.0.1:9/v1")
	panel.use_for_every_task()
	panel.apply_settings()
	assert_eq(oracle.provider.get_id(), "ollama", "the running Oracle switched")
	var saved := AISettings.load_from(_path)
	assert_eq(saved.tiers, {"small": "ollama", "medium": "ollama", "large": "ollama"})
	assert_eq(saved.provider("ollama")["base_url"], "http://127.0.0.1:9/v1")
	panel.pick_provider("offline")
	await panel.test_connection()
	assert_true(panel._test_result.text.begins_with("✓"), panel._test_result.text)
	panel.select_tab("Usage")
	panel._refresh_usage()
	assert_true(panel._state_line.text.begins_with("Speaking through Ollama"), panel._state_line.text)
	panel.free()
	_remove_file()
	_restore_env()


## Picking a provider is choosing it: with every tier on Automatic, an API key in the environment
## must not win over the provider the player picked.
func test_picking_a_provider_routes_every_task_to_it() -> void:
	_clear_env()
	_remove_file()
	OS.set_environment("OPENAI_API_KEY", "env-key")
	var oracle := _oracle(OfflineTemplatesProvider.new())
	var stored := AISettings.new()
	stored.file_path = _path
	var panel := AISettingsPanel.new()
	panel.open(oracle, stored)
	var ids: Array = panel._catalog.map(func(entry: Dictionary) -> String: return String(entry["id"]))
	panel._picker.item_selected.emit(ids.find("claude_code"))
	panel.apply_settings()
	assert_eq(oracle.provider.get_id(), "claude_code", "the picked provider answers, not the environment's key")
	assert_true(panel._status.text.contains("Claude Code"), panel._status.text)
	# Tiers routed to different providers are left alone.
	panel._select_route("small", "ollama")
	panel._picker.item_selected.emit(ids.find("openai"))
	assert_eq(panel._route_id("small"), "ollama")
	assert_eq(panel._route_id("large"), "claude_code")
	panel.free()
	_remove_file()
	_restore_env()
