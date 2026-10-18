class_name GeminiProvider
extends AIProvider
## Google's Gemini through the Gemini API (generateContent) with the player's own API key.
## The reply is constrained to JSON with the request's schema (responseJsonSchema).

const BASE_URL := "https://generativelanguage.googleapis.com/v1beta"
const MODELS := {
	AIRequest.Tier.SMALL: "gemini-3.5-flash-lite",
	AIRequest.Tier.MEDIUM: "gemini-3.8-flash",
	AIRequest.Tier.LARGE: "gemini-4-argon",
}
## Gemini 3+ models take a thinking level instead of a token budget.
const THINKING := {
	AIRequest.Tier.SMALL: "low",
	AIRequest.Tier.MEDIUM: "low",
	AIRequest.Tier.LARGE: "medium",
}

var _api_key: String
var _models: Dictionary
var _base_url: String


## models: optional {AIRequest.Tier: model id} overrides.
func _init(api_key: String, models: Dictionary = {}, base_url: String = "") -> void:
	_api_key = api_key
	_models = MODELS.merged(models, true)
	_base_url = base_url.trim_suffix("/") if base_url else BASE_URL


func get_id() -> String:
	return "gemini"


func is_available() -> bool:
	return not _api_key.is_empty()


func complete(request: AIRequest) -> AIResponse:
	if not is_available():
		return AIResponse.failure(get_id(), "No API key")
	var headers := PackedStringArray(["x-goog-api-key: " + _api_key])
	var result: Dictionary = await HttpJson.post(url(request), headers, build_body(request), request.timeout_sec)
	if not result["ok"]:
		return AIResponse.failure(get_id(), result["error"])
	return read_reply(request, result["body"] if result["body"] is Dictionary else {})


func url(request: AIRequest) -> String:
	return "%s/models/%s:generateContent" % [_base_url, _models[request.tier]]


func build_body(request: AIRequest) -> Dictionary:
	var config := {
		"responseMimeType": "application/json",
		"responseJsonSchema": JsonSchema.to_wire(request.schema),
		"maxOutputTokens": request.max_tokens,
	}
	if String(_models[request.tier]).begins_with("gemini-") and not String(_models[request.tier]).begins_with("gemini-2"):
		config["thinkingConfig"] = {"thinkingLevel": THINKING[request.tier]}
	var body := {
		"contents": [{"role": "user", "parts": [{"text": request.prompt}]}],
		"generationConfig": config,
	}
	if not request.system.is_empty():
		body["systemInstruction"] = {"parts": [{"text": request.system}]}
	return body


func read_reply(request: AIRequest, body: Dictionary) -> AIResponse:
	var candidates: Array = body.get("candidates", []) if body.get("candidates") is Array else []
	if candidates.is_empty():
		var feedback: Dictionary = body.get("promptFeedback", {}) if body.get("promptFeedback") is Dictionary else {}
		return AIResponse.failure(get_id(), "No reply: " + String(feedback.get("blockReason", "no candidates")))
	var candidate: Dictionary = candidates[0]
	var finish_reason := String(candidate.get("finishReason", "STOP"))
	if finish_reason != "STOP":
		return AIResponse.failure(get_id(), "Stopped early: " + finish_reason)
	var text := ""
	var content: Dictionary = candidate.get("content", {}) if candidate.get("content") is Dictionary else {}
	for part: Dictionary in content.get("parts", []):
		if not part.get("thought", false):
			text += String(part.get("text", ""))
	var reply: Variant = JSON.parse_string(text) if not text.is_empty() else null
	if not reply is Dictionary:
		return AIResponse.failure(get_id(), "Reply was not a JSON object")
	var response := AIResponse.success(get_id(), reply)
	var usage: Dictionary = body.get("usageMetadata", {}) if body.get("usageMetadata") is Dictionary else {}
	response.input_tokens = int(usage.get("promptTokenCount", 0))
	# Thinking is billed as output.
	response.output_tokens = int(usage.get("candidatesTokenCount", 0)) + int(usage.get("thoughtsTokenCount", 0))
	response.cost_usd = ModelPrices.estimate(_models[request.tier], response.input_tokens, response.output_tokens)
	return response
