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
var _models: Dictionary


## models: optional {AIRequest.Tier: model id} overrides.
func _init(api_key: String, models: Dictionary = {}) -> void:
	_api_key = api_key
	_models = MODELS.merged(models, true)


func get_id() -> String:
	return "anthropic"


func is_available() -> bool:
	return not _api_key.is_empty()


func supports_streaming() -> bool:
	return true


func complete(request: AIRequest) -> AIResponse:
	if not is_available():
		return AIResponse.failure(get_id(), "No API key")
	var result: Dictionary = await HttpJson.post(URL, headers(request), build_body(request), request.timeout_sec)
	if not result["ok"]:
		return AIResponse.failure(get_id(), result["error"])
	return read_message(request, result["body"] if result["body"] is Dictionary else {})


func complete_streaming(request: AIRequest, on_text: Callable) -> AIResponse:
	if not is_available():
		return AIResponse.failure(get_id(), "No API key")
	var stream := {}
	var on_data := func(data: String) -> void:
		if read_stream_event(stream, data):
			on_text.call(stream["text"])
	var result: Dictionary = await HttpJson.post_stream(URL, headers(request), build_body(request, true), on_data, request.timeout_sec)
	if not result["ok"]:
		return AIResponse.failure(get_id(), result["error"])
	if stream.has("error"):
		return AIResponse.failure(get_id(), stream["error"])
	return read_message(request, stream_message(stream))


func headers(request: AIRequest) -> PackedStringArray:
	var list := PackedStringArray(["x-api-key: " + _api_key, "anthropic-version: " + API_VERSION])
	if request.tier != AIRequest.Tier.SMALL:
		list.append("anthropic-beta: " + FALLBACK_BETA)
	return list


func build_body(request: AIRequest, stream: bool = false) -> Dictionary:
	var body := {
		"model": _models[request.tier],
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
	if stream:
		body["stream"] = true
	return body


## Turns a Messages API reply (or the one a stream adds up to) into a response.
func read_message(request: AIRequest, message: Dictionary) -> AIResponse:
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
	response.input_tokens = int(usage.get("input_tokens", 0)) + int(usage.get("cache_read_input_tokens", 0)) + int(usage.get("cache_creation_input_tokens", 0))
	response.output_tokens = int(usage.get("output_tokens", 0))
	response.cost_usd = ModelPrices.estimate(_models[request.tier], response.input_tokens, response.output_tokens)
	return response


## Adds one stream event's data to `stream` (text, stop_reason, usage, error).
## Returns true when it added text.
static func read_stream_event(stream: Dictionary, data: String) -> bool:
	var event: Variant = JSON.parse_string(data)
	if not event is Dictionary:
		return false
	match String(event.get("type", "")):
		"message_start":
			var message: Dictionary = event.get("message", {})
			stream["usage"] = (message.get("usage", {}) as Dictionary).duplicate()
		"content_block_delta":
			var delta: Dictionary = event.get("delta", {})
			if delta.get("type") == "text_delta":
				stream["text"] = String(stream.get("text", "")) + String(delta.get("text", ""))
				return true
		"message_delta":
			stream["stop_reason"] = (event.get("delta", {}) as Dictionary).get("stop_reason", "")
			var usage: Dictionary = stream.get("usage", {})
			usage.merge(event.get("usage", {}), true)
			stream["usage"] = usage
		"error":
			stream["error"] = "Stream error: " + JSON.stringify(event.get("error", {})).left(300)
	return false


## The message a finished stream adds up to, in the shape read_message() expects.
static func stream_message(stream: Dictionary) -> Dictionary:
	return {
		"content": [{"type": "text", "text": stream.get("text", "")}],
		"stop_reason": stream.get("stop_reason", ""),
		"usage": stream.get("usage", {}),
	}
