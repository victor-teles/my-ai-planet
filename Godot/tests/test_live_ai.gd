extends TestCase
## Calls real AI providers. Skipped unless MYAIPLANET_LIVE_AI=1, because it costs money and needs setup.


func _live() -> bool:
	return OS.get_environment("MYAIPLANET_LIVE_AI") == "1"


func _check_provider(provider: AIProvider) -> void:
	if not _live() or not provider.is_available():
		print("        skipped (%s)" % ("set MYAIPLANET_LIVE_AI=1" if not _live() else provider.get_id() + " not available"))
		return
	var sim := Simulation.create(42)
	sim.advance(600)
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
	sim.advance(600)
	var oracle := Oracle.new(provider)
	oracle.fallback = provider
	var session := Session.new(sim, oracle)
	session.sim.state.influence = 10.0
	await session.begin()
	session.cast_miracle("harvest", sim.state.tribe_names[0])
	var years := 0
	while session.phase in [Session.Phase.PLAYING, Session.Phase.DECIDING] and years < 600:
		if session.phase == Session.Phase.DECIDING:
			session.choose(0)
		session.advance(WorldState.MONTHS_PER_YEAR)
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
	sim.advance(12 * 90)
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
