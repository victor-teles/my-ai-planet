class_name GrokCliProvider
extends CliAIProvider
## xAI's Grok Build CLI in single-turn mode, using the player's existing login.
## Grok always sends its agent preamble (about 22k input tokens), so calls cost more than Claude Code's.

const EFFORT := {
	AIRequest.Tier.SMALL: "low",
	AIRequest.Tier.MEDIUM: "medium",
	AIRequest.Tier.LARGE: "high",
}


func get_id() -> String:
	return "grok_cli"


func get_command() -> String:
	return "grok"


func _arguments(request: AIRequest) -> PackedStringArray:
	return PackedStringArray([
		"--single", request.prompt,
		"--verbatim",
		"--json-schema", JSON.stringify(JsonSchema.to_wire(request.schema)),
		"--system-prompt-override", request.system,
		"--reasoning-effort", EFFORT[request.tier],
		"--tools", "none",
		"--disable-web-search",
		"--no-subagents",
		"--no-plan",
		"--max-turns", "3",
		# Run outside the game folder so the agent doesn't pick up project files as context.
		"--cwd", OS.get_user_data_dir(),
	])


func _read_output(output: Dictionary) -> AIResponse:
	var reply: Variant = output.get("structuredOutput")
	if not reply is Dictionary:
		var reason := String(output.get("structuredOutputError", output.get("stopReason", "unknown")))
		return AIResponse.failure(get_id(), "No structured output: " + reason)
	var response := AIResponse.success(get_id(), reply)
	var usage: Dictionary = output.get("usage", {})
	response.input_tokens = int(usage.get("input_tokens", 0)) + int(usage.get("cache_read_input_tokens", 0))
	response.output_tokens = int(usage.get("output_tokens", 0))
	response.cost_usd = float(output.get("total_cost_usd", 0.0))
	return response
