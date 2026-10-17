class_name AnthropicProvider
extends AIProvider
## Claude through the Messages API with the player's own API key.
## Uses structured outputs so replies always match the request's schema shape.

const URL := "https://api.anthropic.com/v1/messages"
const API_VERSION := "2023-06-01"
const MODELS := {
	AIRequest.Tier.SMALL: "claude-haiku-5-5",
	AIRequest.Tier.MEDIUM: "claude-sonnet-5-5",
	AIRequest.Tier.LARGE: "claude-opus-5-5",
}
const EFFORT := {
	AIRequest.Tier.SMALL: "low",
	AIRequest.Tier.MEDIUM: "medium",
	AIRequest.Tier.LARGE: "medium",
}
## On a safety refusal, the API retries on a suitable model inside the same call.
## Haiku has no server-side fallback, so it's only sent for the larger tiers.
const FALLBACK_BETA := "server-side-fallback-2026-07-01"

var _api_key: String


func _init(api_key: String) -> void:
	_api_key = api_key


func get_id() -> String:
	return "anthropic"


func is_available() -> bool:
	return not _api_key.is_empty()


func complete(request: AIRequest) -> AIResponse:
	if not is_available():
		return AIResponse.failure(get_id(), "No API key")
	var headers := PackedStringArray(["x-api-key: " + _api_key, "anthropic-version: " + API_VERSION])
	var body := {
		"model": MODELS[request.tier],
		"max_tokens": request.max_tokens,
		"system": request.system,
		"messages": [{"role": "user", "content": request.prompt}],
		"output_config": {
			"effort": EFFORT[request.tier],
			"format": {"type": "json_schema", "schema": JsonSchema.to_wire(request.schema)},
		},
	}
	if request.tier != AIRequest.Tier.SMALL:
		body["fallbacks"] = "default"
		headers.append("anthropic-beta: " + FALLBACK_BETA)

	var result: Dictionary = await HttpJson.post(URL, headers, body, request.timeout_sec)
	if not result["ok"]:
		return AIResponse.failure(get_id(), result["error"])
	var message: Dictionary = result["body"]
	var stop_reason := String(message.get("stop_reason", ""))
	if stop_reason == "refusal" or stop_reason == "max_tokens":
		return AIResponse.failure(get_id(), "Stopped early: " + stop_reason)

	var reply: Variant = null
	for block: Dictionary in message.get("content", []):
		if block.get("type") == "text":
			reply = JSON.parse_string(String(block["text"]))
			break
	if not reply is Dictionary:
		return AIResponse.failure(get_id(), "Reply was not a JSON object")
	var response := AIResponse.success(get_id(), reply)
	var usage: Dictionary = message.get("usage", {})
	response.input_tokens = int(usage.get("input_tokens", 0))
	response.output_tokens = int(usage.get("output_tokens", 0))
	return response
