class_name ClaudeCodeProvider
extends AIProvider
## Uses the player's installed Claude Code CLI (and their existing subscription) in print mode.
## Tools, settings and session saving are turned off: it only answers the question.

const MODELS := {
	AIRequest.Tier.SMALL: "haiku",
	AIRequest.Tier.MEDIUM: "sonnet",
	AIRequest.Tier.LARGE: "opus",
}

var _path: String


## Leave path empty to search the usual install folders.
func _init(path: String = "") -> void:
	_path = path if not path.is_empty() else CliLocator.find("claude")


func get_id() -> String:
	return "claude_code"


func is_available() -> bool:
	return not _path.is_empty()


func complete(request: AIRequest) -> AIResponse:
	if not is_available():
		return AIResponse.failure(get_id(), "Claude Code CLI not found")
	var arguments := PackedStringArray([
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
	var result: Dictionary = await CliProcess.run(_path, arguments, request.timeout_sec)
	var output: Variant = JSON.parse_string(String(result["stdout"])) if not String(result["stdout"]).is_empty() else null
	if not output is Dictionary:
		var detail := String(result["stderr"]).strip_edges().left(300)
		return AIResponse.failure(get_id(), "%s %s" % [result["error"], detail])
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
