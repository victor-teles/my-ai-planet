class_name OpenAICompatibleProvider
extends AIProvider
## Any server that speaks OpenAI's Chat Completions API: OpenAI itself, OpenRouter, and local
## model servers (Ollama, LM Studio, llama.cpp). Use a preset, or build one for another server.

## STRICT sends the schema as a strict json_schema response format. Many local models can't
## follow one, so JSON_OBJECT only asks for JSON and describes the schema in the system prompt.
## AIProbe picks the mode that works.
enum SchemaMode { STRICT, JSON_OBJECT }

const PRESETS := {
	"openai": {
		"label": "OpenAI",
		"base_url": "https://api.openai.com/v1",
		"local": false,
		"models": {
			AIRequest.Tier.SMALL: "gpt-6-luna",
			AIRequest.Tier.MEDIUM: "gpt-6.1-sol",
			AIRequest.Tier.LARGE: "gpt-6.1-sol",
		},
	},
	"openrouter": {
		"label": "OpenRouter",
		"base_url": "https://openrouter.ai/api/v1",
		"local": false,
		"models": {
			AIRequest.Tier.SMALL: "anthropic/claude-haiku-5.5",
			AIRequest.Tier.MEDIUM: "anthropic/claude-sonnet-5.5",
			AIRequest.Tier.LARGE: "anthropic/claude-opus-5.5",
		},
	},
	"ollama": {
		"label": "Ollama",
		"base_url": "http://localhost:11434/v1",
		"local": true,
		"models": {
			AIRequest.Tier.SMALL: "qwen3:8b",
			AIRequest.Tier.MEDIUM: "qwen3:8b",
			AIRequest.Tier.LARGE: "qwen3:8b",
		},
	},
	"lmstudio": {
		"label": "LM Studio",
		"base_url": "http://localhost:1234/v1",
		"local": true,
		"models": {
			AIRequest.Tier.SMALL: "qwen/qwen3-8b",
			AIRequest.Tier.MEDIUM: "qwen/qwen3-8b",
			AIRequest.Tier.LARGE: "qwen/qwen3-8b",
		},
	},
}
## OpenAI's reasoning models take an effort; other servers may reject the field.
const OPENAI_EFFORT := {
	AIRequest.Tier.SMALL: "low",
	AIRequest.Tier.MEDIUM: "low",
	AIRequest.Tier.LARGE: "medium",
}

var schema_mode := SchemaMode.STRICT
var _id: String
var _label: String
var _base_url: String
var _api_key: String
var _models: Dictionary
var _local: bool


## models: {AIRequest.Tier: model id}. A local server is free and needs no key.
func _init(id: String, label: String, base_url: String, api_key: String, models: Dictionary, local: bool = false) -> void:
	_id = id
	_label = label
	_base_url = base_url.trim_suffix("/")
	_api_key = api_key
	_models = models
	_local = local


## A provider from PRESETS. Empty arguments keep the preset's URL and models.
static func preset(id: String, api_key: String = "", models: Dictionary = {}, base_url: String = "") -> OpenAICompatibleProvider:
	var entry: Dictionary = PRESETS[id]
	var all_models: Dictionary = (entry["models"] as Dictionary).merged(models, true)
	return OpenAICompatibleProvider.new(id, entry["label"], base_url if base_url else String(entry["base_url"]), api_key, all_models, entry["local"])


static func openai(api_key: String, models: Dictionary = {}) -> OpenAICompatibleProvider:
	return preset("openai", api_key, models)


static func openrouter(api_key: String, models: Dictionary = {}) -> OpenAICompatibleProvider:
	return preset("openrouter", api_key, models)


## model: one model for every tier; empty keeps the preset's.
static func ollama(model: String = "", base_url: String = "") -> OpenAICompatibleProvider:
	return preset("ollama", "", _same_model(model), base_url)


static func lmstudio(model: String = "", base_url: String = "") -> OpenAICompatibleProvider:
	return preset("lmstudio", "", _same_model(model), base_url)


static func _same_model(model: String) -> Dictionary:
	if model.is_empty():
		return {}
	return {AIRequest.Tier.SMALL: model, AIRequest.Tier.MEDIUM: model, AIRequest.Tier.LARGE: model}


func get_id() -> String:
	return _id


func get_label() -> String:
	return _label


func get_base_url() -> String:
	return _base_url


func is_available() -> bool:
	return _local or not _api_key.is_empty()


func is_free() -> bool:
	return _local


func supports_streaming() -> bool:
	return true


func complete(request: AIRequest) -> AIResponse:
	if not is_available():
		return AIResponse.failure(get_id(), "No API key")
	var result: Dictionary = await HttpJson.post(_base_url + "/chat/completions", headers(), build_body(request), request.timeout_sec)
	if not result["ok"]:
		return AIResponse.failure(get_id(), result["error"])
	return read_reply(request, result["body"] if result["body"] is Dictionary else {})


func complete_streaming(request: AIRequest, on_text: Callable) -> AIResponse:
	if not is_available():
		return AIResponse.failure(get_id(), "No API key")
	var stream := {}
	var on_data := func(data: String) -> void:
		if read_stream_event(stream, data):
			on_text.call(stream["text"])
	var result: Dictionary = await HttpJson.post_stream(_base_url + "/chat/completions", headers(), build_body(request, true), on_data, request.timeout_sec)
	if not result["ok"]:
		return AIResponse.failure(get_id(), result["error"])
	if stream.has("error"):
		return AIResponse.failure(get_id(), stream["error"])
	return read_reply(request, stream_reply(stream))


func headers() -> PackedStringArray:
	var list := PackedStringArray()
	if not _api_key.is_empty():
		list.append("authorization: Bearer " + _api_key)
	if _id == "openrouter":
		list.append("x-title: My AI Planet")
	return list


func build_body(request: AIRequest, stream: bool = false) -> Dictionary:
	var system := request.system
	var format := {}
	if schema_mode == SchemaMode.STRICT:
		format = {"type": "json_schema", "json_schema": {"name": _schema_name(request), "strict": true, "schema": JsonSchema.to_strict_wire(request.schema)}}
	else:
		# JSON mode needs the word "JSON" in the messages, which the instructions provide.
		system = (system + "\n\n" if system else "") + ReplyJson.instructions(request.schema)
		format = {"type": "json_object"}
	var body := {
		"model": _models[request.tier],
		"messages": [{"role": "system", "content": system}, {"role": "user", "content": request.prompt}],
		"response_format": format,
	}
	if _id == "openai":
		body["max_completion_tokens"] = request.max_tokens
		body["reasoning_effort"] = OPENAI_EFFORT[request.tier]
	else:
		body["max_tokens"] = request.max_tokens
	if _id == "openrouter":
		body["usage"] = {"include": true}
	if stream:
		body["stream"] = true
		body["stream_options"] = {"include_usage": true}
	return body


## Turns a Chat Completions reply (or the one a stream adds up to) into a response.
func read_reply(request: AIRequest, body: Dictionary) -> AIResponse:
	var choices: Array = body.get("choices", [])
	if choices.is_empty():
		return AIResponse.failure(get_id(), "No reply: " + JSON.stringify(body.get("error", body)).left(300))
	var choice: Dictionary = choices[0]
	var message: Dictionary = choice.get("message", {})
	var finish_reason := String(choice.get("finish_reason", "")) if choice.get("finish_reason") != null else ""
	if message.get("refusal") != null and not String(message["refusal"]).is_empty():
		return AIResponse.failure(get_id(), "Refused: " + String(message["refusal"]).left(300))
	if finish_reason == "length" or finish_reason == "content_filter":
		return AIResponse.failure(get_id(), "Stopped early: " + finish_reason)
	var content: Variant = message.get("content")
	var reply: Variant = ReplyJson.parse_object(String(content)) if content is String else null
	if not reply is Dictionary:
		return AIResponse.failure(get_id(), "Reply was not a JSON object")
	var response := AIResponse.success(get_id(), JsonSchema.drop_optional_nulls(reply, request.schema))
	var usage: Dictionary = body.get("usage", {}) if body.get("usage") is Dictionary else {}
	response.input_tokens = int(usage.get("prompt_tokens", 0))
	response.output_tokens = int(usage.get("completion_tokens", 0))
	if usage.get("cost") is float or usage.get("cost") is int:
		response.cost_usd = float(usage["cost"]) # OpenRouter reports what it charged
	elif not _local:
		response.cost_usd = ModelPrices.estimate(_models[request.tier], response.input_tokens, response.output_tokens)
	return response


## Adds one stream event's data to `stream` (text, refusal, finish_reason, usage, error).
## Returns true when it added text.
static func read_stream_event(stream: Dictionary, data: String) -> bool:
	if data == "[DONE]":
		return false
	var chunk: Variant = JSON.parse_string(data)
	if not chunk is Dictionary:
		return false
	if chunk.get("error") is Dictionary:
		stream["error"] = "Stream error: " + String((chunk["error"] as Dictionary).get("message", "unknown")).left(300)
		return false
	if chunk.get("usage") is Dictionary:
		stream["usage"] = chunk["usage"]
	var choices: Array = chunk.get("choices", []) if chunk.get("choices") is Array else []
	if choices.is_empty():
		return false
	var choice: Dictionary = choices[0]
	if choice.get("finish_reason") is String:
		stream["finish_reason"] = choice["finish_reason"]
	var delta: Dictionary = choice.get("delta", {}) if choice.get("delta") is Dictionary else {}
	if delta.get("refusal") is String:
		stream["refusal"] = String(stream.get("refusal", "")) + String(delta["refusal"])
	if delta.get("content") is String and not String(delta["content"]).is_empty():
		stream["text"] = String(stream.get("text", "")) + String(delta["content"])
		return true
	return false


## The reply a finished stream adds up to, in the shape read_reply() expects.
static func stream_reply(stream: Dictionary) -> Dictionary:
	return {
		"choices": [{
			"message": {"content": stream.get("text", ""), "refusal": stream.get("refusal")},
			"finish_reason": stream.get("finish_reason", ""),
		}],
		"usage": stream.get("usage", {}),
	}


## Schema names may only use letters, digits, "_" and "-".
static func _schema_name(request: AIRequest) -> String:
	var name := RegEx.create_from_string("[^A-Za-z0-9_-]").sub(request.task, "_", true)
	return name if name else "reply"
