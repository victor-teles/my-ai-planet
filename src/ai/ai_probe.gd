class_name AIProbe
extends RefCounted
## The capability probe behind "Test connection": one tiny SMALL-tier JSON question that shows
## whether a provider answers at all, how fast, and whether it follows a schema. Weak models
## that can't should be given less to do. Also lists the models a local server has.

const SCHEMA := {
	"type": "object",
	"additionalProperties": false,
	"required": ["ok", "word"],
	"properties": {
		"ok": {"type": "boolean"},
		"word": {"type": "string", "enum": ["pong"]},
	},
}


## Returns {"ok": bool (it answered), "latency_ms": int, "structured": bool (the answer matched
## the schema), "error": String, "provider": id}. An OpenAI-compatible provider whose server
## rejects strict schemas is switched to JSON mode when that works, and keeps that mode.
static func run(provider: AIProvider) -> Dictionary:
	if provider is OfflineTemplatesProvider:
		return {"ok": true, "latency_ms": 0, "structured": true, "error": "", "provider": provider.get_id()}
	var result := await _ask(provider)
	var compatible := provider as OpenAICompatibleProvider
	if compatible and not result["structured"] and compatible.schema_mode == OpenAICompatibleProvider.SchemaMode.STRICT:
		compatible.schema_mode = OpenAICompatibleProvider.SchemaMode.JSON_OBJECT
		var retry := await _ask(provider)
		if retry["structured"]:
			return retry
		compatible.schema_mode = OpenAICompatibleProvider.SchemaMode.STRICT
	return result


static func request() -> AIRequest:
	var probe := AIRequest.new()
	probe.task = "probe"
	probe.tier = AIRequest.Tier.SMALL
	probe.system = "You are a connection test for a game. Answer exactly as asked."
	probe.prompt = "Reply with ok set to true and word set to \"pong\"."
	probe.schema = SCHEMA.duplicate(true)
	probe.max_tokens = 2000 # reasoning models think before they answer
	probe.timeout_sec = 60.0
	return probe


## The model ids an OpenAI-compatible server offers (Ollama, LM Studio, OpenRouter...):
## {"ok": bool, "models": PackedStringArray, "error": String}.
static func list_models(base_url: String, api_key: String = "") -> Dictionary:
	var headers := PackedStringArray()
	if not api_key.is_empty():
		headers.append("authorization: Bearer " + api_key)
	var result: Dictionary = await HttpJson.get_json(base_url.trim_suffix("/") + "/models", headers)
	if not result["ok"]:
		return {"ok": false, "models": PackedStringArray(), "error": result["error"]}
	return {"ok": true, "models": parse_model_list(result["body"]), "error": ""}


## Reads {"data": [{"id": ...}, ...]}, the OpenAI model list format.
static func parse_model_list(body: Variant) -> PackedStringArray:
	var models := PackedStringArray()
	if body is Dictionary and body.get("data") is Array:
		for entry: Variant in body["data"]:
			if entry is Dictionary and entry.get("id") is String:
				models.append(entry["id"])
	models.sort()
	return models


static func _ask(provider: AIProvider) -> Dictionary:
	var started := Time.get_ticks_msec()
	var probe := request()
	var response := await provider.complete(probe)
	var structured := response.ok and JsonSchema.validate(response.data, SCHEMA).is_empty()
	var error := response.error
	if response.ok and not structured:
		error = "The reply didn't match the schema: %s" % JSON.stringify(response.data).left(200)
	return {
		"ok": response.ok,
		"latency_ms": Time.get_ticks_msec() - started,
		"structured": structured,
		"error": error,
		"provider": provider.get_id(),
	}
