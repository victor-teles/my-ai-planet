class_name ClaudeCodeProvider
extends CliAIProvider
## Claude Code in print mode, using the player's existing login.
## Tools, settings, MCP servers and session saving are turned off: it only answers the question.

const MODELS := {
	AIRequest.Tier.SMALL: "haiku",
	AIRequest.Tier.MEDIUM: "sonnet",
	AIRequest.Tier.LARGE: "opus",
}


func get_id() -> String:
	return "claude_code"


func get_command() -> String:
	return "claude"


func _arguments(request: AIRequest) -> PackedStringArray:
	return PackedStringArray([
		"-p",
		"--output-format", "json",
		"--model", MODELS[request.tier],
		"--tools", "",
		"--setting-sources", "",
		"--strict-mcp-config", # no MCP servers: their tool definitions can add 40k+ tokens per call
		"--no-session-persistence",
		"--system-prompt", request.system,
		"--json-schema", JSON.stringify(JsonSchema.to_wire(request.schema)),
		request.prompt,
	])


func _read_output(output: Dictionary) -> AIResponse:
	if output.get("is_error", false):
		return AIResponse.failure(get_id(), "Claude Code error: " + String(output.get("result", "unknown")).left(300))
	var reply: Variant = output.get("structured_output")
	if not reply is Dictionary:
		return AIResponse.failure(get_id(), "No structured output in the reply")
	var response := AIResponse.success(get_id(), reply)
	var usage: Dictionary = output.get("usage", {})
	response.input_tokens = int(usage.get("input_tokens", 0)) + int(usage.get("cache_read_input_tokens", 0)) + int(usage.get("cache_creation_input_tokens", 0))
	response.output_tokens = int(usage.get("output_tokens", 0))
	response.cost_usd = float(output.get("total_cost_usd", 0.0))
	return response
