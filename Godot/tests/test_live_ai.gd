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


func test_claude_code_cli() -> void:
	await _check_provider(ClaudeCodeProvider.new())


func test_anthropic_api() -> void:
	await _check_provider(AnthropicProvider.new(OS.get_environment("ANTHROPIC_API_KEY")))
