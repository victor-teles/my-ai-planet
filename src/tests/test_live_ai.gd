extends TestCase
## Calls real AI providers. Skipped unless MYAIPLANET_LIVE_AI=1, because it costs money and needs setup.


func _live() -> bool:
	return OS.get_environment("MYAIPLANET_LIVE_AI") == "1"


func _check_provider(provider: AIProvider) -> void:
	if not _live() or not provider.is_available():
		print("        skipped (%s)" % ("set MYAIPLANET_LIVE_AI=1" if not _live() else provider.get_id() + " not available"))
		return
	var sim := Simulation.create(42)
	sim.advance(50 * WorldState.DAYS_PER_YEAR)
	var oracle := Oracle.new(provider)
	oracle.fallback = provider # no silent fallback: we want to see this provider's own result
	var prophecy := await oracle.request_prophecy(sim.state)
	var response := oracle.last_response
	assert_true(response.ok, "%s failed: %s" % [provider.get_id(), response.error])
	assert_true(prophecy != null, "reply should pass schema and sim rules: %s" % response.data)
	if prophecy:
		print("        %s: \"%s\" [%s %s %d by year %d] tokens in/out %d/%d, $%.4f" % [
			provider.get_id(), prophecy.text, prophecy.metric, prophecy.op, prophecy.target,
			prophecy.deadline_year, response.input_tokens, response.output_tokens, response.cost_usd,
		])


func _check_chronicle(provider: AIProvider) -> void:
	if not _live() or not provider.is_available():
		print("        skipped")
		return
	var sim := Simulation.create(42)
	sim.advance(50 * WorldState.DAYS_PER_YEAR)
	var oracle := Oracle.new(provider)
	oracle.fallback = provider
	var session := Session.new(sim, oracle)
	session.sim.state.influence = 10.0
	await session.begin()
	session.cast_miracle("harvest", sim.state.tribe_names[0])
	var years := 0
	while session.phase in [Session.Phase.PLAYING, Session.Phase.DECIDING] and years < Prophecy.MAX_YEARS + 1:
		if session.phase == Session.Phase.DECIDING:
			session.choose(0)
		session.advance(WorldState.DAYS_PER_YEAR)
		years += 1
	while session.phase == Session.Phase.CHRONICLING:
		await Frames.next()
	assert_eq(session.phase, Session.Phase.REVEAL)
	assert_true(oracle.last_response.ok, "%s chronicle failed: %s" % [provider.get_id(), oracle.last_response.error])
	print("        %s [%s] %s\n          %s\n          causes: %s\n          total $%.4f" % [
		provider.get_id(), Prophecy.Status.keys()[sim.state.resolved_prophecy.status], session.chronicle.get("title"),
		session.chronicle.get("text"), session.chronicle.get("causes"), oracle.cost_usd,
	])


func _check_dilemma(provider: AIProvider) -> void:
	if not _live() or not provider.is_available():
		print("        skipped")
		return
	var sim := Simulation.create(42)
	sim.advance(60 * WorldState.DAYS_PER_YEAR)
	var oracle := Oracle.new(provider)
	oracle.fallback = provider
	var dilemma := await oracle.request_dilemma(sim.state)
	assert_true(oracle.last_response.ok, "%s dilemma failed: %s" % [provider.get_id(), oracle.last_response.error])
	assert_true(dilemma != null, "dilemma should pass schema and sim rules: %s" % oracle.last_response.data)
	if dilemma:
		var lines := PackedStringArray(["%s: %s (%s)\n          %s" % [provider.get_id(), dilemma.title, dilemma.tribe, dilemma.situation]])
		for choice: Dictionary in dilemma.choices:
			lines.append("          - %s | %s | %s" % [choice["label"], choice["hint"], choice["effects"]])
		lines.append("          $%.4f" % oracle.cost_usd)
		print("        " + "\n".join(lines))


func test_claude_code_dilemma() -> void:
	await _check_dilemma(ClaudeCodeProvider.new())


func test_grok_dilemma() -> void:
	await _check_dilemma(GrokCliProvider.new())


func test_claude_code_cli() -> void:
	await _check_provider(ClaudeCodeProvider.new())


func test_claude_code_chronicle() -> void:
	await _check_chronicle(ClaudeCodeProvider.new())


func test_grok_cli() -> void:
	await _check_provider(GrokCliProvider.new())


func test_grok_chronicle() -> void:
	await _check_chronicle(GrokCliProvider.new())


func test_anthropic_api() -> void:
	await _check_provider(AnthropicProvider.new(OS.get_environment("ANTHROPIC_API_KEY")))


## Streams a short reply: on_text must see it grow, and the result must match complete()'s shape.
func _check_stream(provider: AIProvider) -> void:
	if not _live() or not provider.is_available():
		print("        skipped")
		return
	var updates := []
	var response := await provider.complete_streaming(AIProbe.request(), func(text: String) -> void: updates.append(text))
	assert_true(response.ok, "%s stream failed: %s" % [provider.get_id(), response.error])
	assert_true(not updates.is_empty(), "on_text was called")
	print("        %s streamed %d updates: %s, tokens in/out %d/%d, $%.5f" % [
		provider.get_id(), updates.size(), response.data, response.input_tokens, response.output_tokens, response.cost_usd,
	])


## Local servers are always "available"; only test them when one answers.
func _check_local(id: String) -> void:
	var provider := AIProviders.create(id, {"models": _model_override()}) as OpenAICompatibleProvider
	if _live():
		var listed := await AIProbe.list_models(provider.get_base_url())
		if not listed["ok"]:
			print("        skipped (%s not running)" % id)
			return
		print("        %s models: %s" % [id, ", ".join(listed["models"])])
		var probe := await AIProbe.run(provider)
		print("        probe: %s" % probe)
	await _check_provider(provider)


func _model_override() -> Dictionary:
	var model := OS.get_environment("MYAIPLANET_MODEL")
	return {"small": model, "medium": model, "large": model} if model else {}


func test_openai_api() -> void:
	await _check_provider(AIProviders.create("openai", {"api_key": OS.get_environment("OPENAI_API_KEY")}))


func test_openrouter_api() -> void:
	await _check_provider(AIProviders.create("openrouter", {"api_key": OS.get_environment("OPENROUTER_API_KEY")}))


func test_gemini_api() -> void:
	await _check_provider(AIProviders.create("gemini", {"api_key": OS.get_environment("GEMINI_API_KEY")}))


func test_ollama() -> void:
	await _check_local("ollama")


func test_lmstudio() -> void:
	await _check_local("lmstudio")


func test_codex_cli() -> void:
	await _check_provider(CodexCliProvider.new())


func test_gemini_cli() -> void:
	await _check_provider(GeminiCliProvider.new())


func test_anthropic_streaming() -> void:
	await _check_stream(AnthropicProvider.new(OS.get_environment("ANTHROPIC_API_KEY")))


func test_openai_streaming() -> void:
	await _check_stream(AIProviders.create("openai", {"api_key": OS.get_environment("OPENAI_API_KEY")}))
