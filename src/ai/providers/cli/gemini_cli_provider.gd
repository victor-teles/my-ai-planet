class_name GeminiCliProvider
extends CliAIProvider
## Google's Gemini CLI in headless mode (`gemini -p ... --output-format json`), using the
## player's existing login. It has no schema flag and no system prompt flag (only the
## GEMINI_SYSTEM_MD environment variable, which CliProcess can't set), so the system prompt
## and the schema go into the prompt and the reply is dug out of the text.

const MODELS := {
	AIRequest.Tier.SMALL: "flash-lite",
	AIRequest.Tier.MEDIUM: "flash",
	AIRequest.Tier.LARGE: "pro",
}

var _models: Dictionary


## models: optional {AIRequest.Tier: model name or alias} overrides.
func _init(path: String = "", models: Dictionary = {}) -> void:
	super(path)
	_models = MODELS.merged(models, true)


func get_id() -> String:
	return "gemini_cli"


func get_command() -> String:
	return "gemini"


func _needs_closed_stdin() -> bool:
	return true # -p appends stdin to the prompt, so it waits for stdin to close


func _arguments(request: AIRequest) -> PackedStringArray:
	return PackedStringArray([
		"--prompt", full_prompt(request),
		"--output-format", "json",
		"--model", _models[request.tier],
		"--approval-mode", "default", # headless: tools that need approval can't run
		"--extensions", "none",
	])


static func full_prompt(request: AIRequest) -> String:
	var parts := PackedStringArray()
	if not request.system.is_empty():
		parts.append(request.system)
	parts.append(request.prompt)
	parts.append(ReplyJson.instructions(request.schema))
	return "\n\n".join(parts)


## {"response": text, "stats": {"models": {name: {"tokens": {...}}}}, "error": {...}}
func _read_output(output: Dictionary) -> AIResponse:
	if output.get("error") is Dictionary:
		return AIResponse.failure(get_id(), "Gemini CLI error: " + String((output["error"] as Dictionary).get("message", "unknown")).left(300))
	var reply: Variant = ReplyJson.parse_object(String(output.get("response", "")))
	if not reply is Dictionary:
		return AIResponse.failure(get_id(), "Reply was not a JSON object")
	var response := AIResponse.success(get_id(), reply)
	var stats: Dictionary = output.get("stats", {}) if output.get("stats") is Dictionary else {}
	var models: Dictionary = stats.get("models", {}) if stats.get("models") is Dictionary else {}
	for model: String in models:
		var tokens: Dictionary = (models[model] as Dictionary).get("tokens", {})
		response.input_tokens += int(tokens.get("prompt", 0))
		response.output_tokens += int(tokens.get("candidates", 0)) + int(tokens.get("thoughts", 0))
	return response
