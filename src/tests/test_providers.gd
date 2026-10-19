extends TestCase
## Provider request building and reply parsing, without the network.


## Fails strict-schema requests the way a local server without structured outputs does.
class NoStrictServer:
	extends OpenAICompatibleProvider

	func _init() -> void:
		super("ollama", "Ollama", "http://localhost:11434/v1", "", {}, true)

	func complete(_request: AIRequest) -> AIResponse:
		if schema_mode == SchemaMode.STRICT:
			return AIResponse.failure(get_id(), "HTTP 400: response_format json_schema is not supported")
		return AIResponse.success(get_id(), {"ok": true, "word": "pong"})


func _request(task: String = "dilemma", tier: AIRequest.Tier = AIRequest.Tier.LARGE) -> AIRequest:
	var request := AIRequest.new()
	request.task = task
	request.tier = tier
	request.system = "You are the Oracle."
	request.prompt = "Speak."
	request.schema = AIAssets.schema(task)
	request.max_tokens = 1234
	return request


func _prophecy_text() -> String:
	return JSON.stringify({"text": "The river will split the people.", "metric": "tribe_count", "op": ">=", "value": 3, "years_from_now": 20})


# --- JsonSchema strict wire -------------------------------------------------------------------

func _check_strict(wire: Dictionary, path: String) -> void:
	if wire.has("properties"):
		var keys: Array = (wire["properties"] as Dictionary).keys()
		assert_eq(wire["required"], keys, path + " requires every property")
		assert_eq(wire["additionalProperties"], false, path + " forbids extras")
		for key: String in wire["properties"]:
			_check_strict(wire["properties"][key], path + "." + key)
	if wire.has("items"):
		_check_strict(wire["items"], path + "[]")
	for keyword: String in JsonSchema.LOCAL_ONLY_KEYWORDS:
		assert_true(not wire.has(keyword), "%s: %s stripped" % [path, keyword])


func test_strict_wire_follows_openai_rules() -> void:
	for task: String in ["prophecy", "dilemma", "chronicle", "destiny", "thought"]:
		_check_strict(JsonSchema.to_strict_wire(AIAssets.schema(task)), task)
	var effect: Dictionary = JsonSchema.to_strict_wire(AIAssets.schema("dilemma"))["properties"]["choices"]["items"]["properties"]["effects"]["items"]
	assert_eq(effect["properties"]["law"]["type"], ["string", "null"], "optional law becomes nullable")
	assert_eq(effect["properties"]["amount"]["type"], "number", "required fields keep their type")
	assert_true(not AIAssets.schema("dilemma")["properties"]["choices"]["items"]["properties"]["effects"]["items"].get("required", []).has("law"), "the original is untouched")


func test_drop_optional_nulls() -> void:
	var schema := AIAssets.schema("dilemma")
	var reply := {"title": "T", "situation": "S", "tribe": "", "choices": [{"label": "L", "hint": "H", "effects": [{"type": "food", "tribe": "A", "amount": 1, "law": null}]}]}
	var cleaned: Dictionary = JsonSchema.drop_optional_nulls(reply, schema)
	assert_true(not cleaned["choices"][0]["effects"][0].has("law"), "null law dropped")
	assert_eq(cleaned["choices"][0]["effects"][0]["amount"], 1)


# --- SSE --------------------------------------------------------------------------------------

func test_sse_parser_handles_split_chunks() -> void:
	var stream := ": comment\r\nevent: delta\r\ndata: {\"t\":\"é\"}\r\n\r\ndata: line one\ndata: line two\n\ndata: last"
	var bytes := stream.to_utf8_buffer()
	var parser := SseParser.new()
	var events := PackedStringArray()
	for i: int in bytes.size(): # one byte at a time splits every line and the "é"
		events.append_array(parser.feed(bytes.slice(i, i + 1)))
	events.append_array(parser.finish())
	assert_eq(events, PackedStringArray(["{\"t\":\"é\"}", "line one\nline two", "last"]))
	assert_eq(SseParser.parse(stream), events, "parse() gives the same")


func _anthropic_stream() -> String:
	var text := _prophecy_text()
	var half := text.length() / 2
	var events: Array[Dictionary] = [
		{"type": "message_start", "message": {"model": "claude-opus-5-5", "usage": {"input_tokens": 100, "output_tokens": 1}}},
		{"type": "content_block_start", "index": 0, "content_block": {"type": "text", "text": ""}},
		{"type": "ping"},
		{"type": "content_block_delta", "index": 0, "delta": {"type": "text_delta", "text": text.left(half)}},
		{"type": "content_block_delta", "index": 0, "delta": {"type": "text_delta", "text": text.substr(half)}},
		{"type": "content_block_stop", "index": 0},
		{"type": "message_delta", "delta": {"stop_reason": "end_turn"}, "usage": {"output_tokens": 40}},
		{"type": "message_stop"},
	]
	var lines := PackedStringArray()
	for event: Dictionary in events:
		lines.append("event: %s\ndata: %s\n" % [event["type"], JSON.stringify(event)])
	return "\n".join(lines)


func test_anthropic_stream_adds_up_to_a_complete_reply() -> void:
	var provider := AnthropicProvider.new("key")
	var request := _request("prophecy")
	var stream := {}
	var seen := PackedStringArray()
	for data: String in SseParser.parse(_anthropic_stream()):
		if AnthropicProvider.read_stream_event(stream, data):
			seen.append(stream["text"])
	assert_eq(seen.size(), 2, "text arrives twice")
	assert_eq(seen[1], _prophecy_text(), "on_text gets the whole raw text so far")
	var streamed := provider.read_message(request, AnthropicProvider.stream_message(stream))
	var whole := provider.read_message(request, {"content": [{"type": "text", "text": _prophecy_text()}], "stop_reason": "end_turn", "usage": {"input_tokens": 100, "output_tokens": 40}})
	assert_true(streamed.ok, streamed.error)
	assert_eq(streamed.data, whole.data)
	assert_eq([streamed.input_tokens, streamed.output_tokens], [100, 40])
	assert_true(is_equal_approx(streamed.cost_usd, whole.cost_usd) and streamed.cost_usd > 0.0, "cost from the price table")
	assert_eq(provider.build_body(request, true)["stream"], true)
	assert_true(not provider.build_body(request).has("stream"))


func test_anthropic_stream_errors_and_refusals() -> void:
	var provider := AnthropicProvider.new("key")
	var stream := {}
	AnthropicProvider.read_stream_event(stream, JSON.stringify({"type": "error", "error": {"type": "overloaded_error", "message": "Overloaded"}}))
	assert_true(String(stream.get("error", "")).contains("overloaded"), "error event recorded")
	stream = {}
	AnthropicProvider.read_stream_event(stream, JSON.stringify({"type": "message_delta", "delta": {"stop_reason": "refusal"}, "usage": {"output_tokens": 3}}))
	assert_true(not provider.read_message(_request("prophecy"), AnthropicProvider.stream_message(stream)).ok, "a refusal fails")


# --- OpenAI-compatible ------------------------------------------------------------------------

func test_openai_body_uses_strict_schema() -> void:
	var provider := OpenAICompatibleProvider.openai("sk-test")
	var body := provider.build_body(_request())
	assert_eq(body["model"], "gpt-6.1-sol")
	assert_eq(body["messages"][0], {"role": "system", "content": "You are the Oracle."})
	assert_eq(body["messages"][1], {"role": "user", "content": "Speak."})
	var format: Dictionary = body["response_format"]
	assert_eq(format["type"], "json_schema")
	assert_eq(format["json_schema"]["name"], "dilemma")
	assert_eq(format["json_schema"]["strict"], true)
	assert_eq(format["json_schema"]["schema"], JsonSchema.to_strict_wire(AIAssets.schema("dilemma")))
	assert_eq(body["max_completion_tokens"], 1234, "OpenAI wants max_completion_tokens")
	assert_eq(body["reasoning_effort"], "medium")
	assert_true(provider.headers().has("authorization: Bearer sk-test"))
	assert_true(not provider.is_free())
	var streaming := provider.build_body(_request(), true)
	assert_eq([streaming["stream"], streaming["stream_options"]], [true, {"include_usage": true}])


func test_local_body_and_json_object_fallback() -> void:
	var provider := OpenAICompatibleProvider.ollama("llama3.1:8b")
	assert_eq(provider.get_base_url(), "http://localhost:11434/v1")
	assert_true(provider.is_available() and provider.is_free(), "local: no key, no cost")
	assert_eq(provider.headers(), PackedStringArray(), "no key, no auth header")
	var body := provider.build_body(_request("prophecy", AIRequest.Tier.SMALL))
	assert_eq(body["model"], "llama3.1:8b")
	assert_eq(body["max_tokens"], 1234)
	assert_true(not body.has("reasoning_effort") and not body.has("max_completion_tokens"), "only OpenAI gets these")
	provider.schema_mode = OpenAICompatibleProvider.SchemaMode.JSON_OBJECT
	body = provider.build_body(_request("prophecy"))
	assert_eq(body["response_format"], {"type": "json_object"})
	var system := String(body["messages"][0]["content"])
	assert_true(system.begins_with("You are the Oracle.") and system.contains("JSON Schema") and system.contains("years_from_now"), "schema described in the system prompt")


func test_openai_reply_parsing() -> void:
	var provider := OpenAICompatibleProvider.openai("sk-test")
	var request := _request("prophecy", AIRequest.Tier.SMALL)
	var reply := {"choices": [{"message": {"role": "assistant", "content": _prophecy_text(), "refusal": null}, "finish_reason": "stop"}], "usage": {"prompt_tokens": 1000, "completion_tokens": 200}}
	var response := provider.read_reply(request, reply)
	assert_true(response.ok, response.error)
	assert_eq(response.data["metric"], "tribe_count")
	assert_eq([response.input_tokens, response.output_tokens], [1000, 200])
	assert_true(is_equal_approx(response.cost_usd, ModelPrices.estimate("gpt-6-luna", 1000, 200)) and response.cost_usd > 0.0, "priced as gpt-6-luna")
	reply["choices"][0]["finish_reason"] = "length"
	assert_true(not provider.read_reply(request, reply).ok, "cut off")
	reply["choices"][0]["finish_reason"] = "stop"
	reply["choices"][0]["message"]["refusal"] = "I can't help with that."
	assert_true(provider.read_reply(request, reply).error.begins_with("Refused"))
	assert_true(not provider.read_reply(request, {"error": {"message": "bad key"}}).ok)


func test_openrouter_cost_and_local_reply() -> void:
	var request := _request("prophecy")
	var reply := {"choices": [{"message": {"content": "```json\n" + _prophecy_text() + "\n```"}, "finish_reason": "stop"}], "usage": {"prompt_tokens": 10, "completion_tokens": 5, "cost": 0.0042}}
	var routed := OpenAICompatibleProvider.openrouter("or-key").read_reply(request, reply)
	assert_true(routed.ok, "fenced JSON is still read: " + routed.error)
	assert_true(is_equal_approx(routed.cost_usd, 0.0042), "OpenRouter's own cost")
	assert_true(OpenAICompatibleProvider.openrouter("or-key").build_body(request)["usage"] == {"include": true})
	reply["usage"].erase("cost")
	assert_eq(OpenAICompatibleProvider.lmstudio().read_reply(request, reply).cost_usd, 0.0, "local models are free")


func test_openai_stream_adds_up_to_a_complete_reply() -> void:
	var provider := OpenAICompatibleProvider.openai("sk-test")
	var request := _request("dilemma")
	var text := JSON.stringify({"title": "Tide", "situation": "The water rises over the low fields of the valley.", "tribe": "", "choices": [
		{"label": "Wait", "hint": "Maybe.", "effects": [{"type": "rain", "tribe": "", "amount": 1, "law": null}]},
		{"label": "Act", "hint": "Maybe not.", "effects": []},
	]})
	var lines := PackedStringArray()
	lines.append("data: " + JSON.stringify({"choices": [{"index": 0, "delta": {"role": "assistant", "content": ""}, "finish_reason": null}]}))
	for i: int in range(0, text.length(), 7):
		lines.append("data: " + JSON.stringify({"choices": [{"index": 0, "delta": {"content": text.substr(i, 7)}, "finish_reason": null}]}))
	lines.append("data: " + JSON.stringify({"choices": [{"index": 0, "delta": {}, "finish_reason": "stop"}]}))
	lines.append("data: " + JSON.stringify({"choices": [], "usage": {"prompt_tokens": 300, "completion_tokens": 90}}))
	lines.append("data: [DONE]")
	var stream := {}
	var last := ""
	for data: String in SseParser.parse("\n\n".join(lines) + "\n\n"):
		if OpenAICompatibleProvider.read_stream_event(stream, data):
			assert_true(String(stream["text"]).begins_with(last), "text only grows")
			last = stream["text"]
	assert_eq(last, text)
	var streamed := provider.read_reply(request, OpenAICompatibleProvider.stream_reply(stream))
	var whole := provider.read_reply(request, {"choices": [{"message": {"content": text}, "finish_reason": "stop"}], "usage": {"prompt_tokens": 300, "completion_tokens": 90}})
	assert_true(streamed.ok, streamed.error)
	assert_eq(streamed.data, whole.data, "same reply either way")
	assert_true(not streamed.data["choices"][0]["effects"][0].has("law"), "strict-mode null dropped")
	assert_eq(JsonSchema.validate(streamed.data, request.schema), PackedStringArray())
	assert_eq([streamed.input_tokens, streamed.output_tokens], [300, 90])
	assert_true(is_equal_approx(streamed.cost_usd, whole.cost_usd))
	var failed := {}
	OpenAICompatibleProvider.read_stream_event(failed, JSON.stringify({"error": {"message": "rate limited"}}))
	assert_true(String(failed.get("error", "")).contains("rate limited"))


# --- Gemini -----------------------------------------------------------------------------------

func test_gemini_body() -> void:
	var provider := GeminiProvider.new("g-key")
	var request := _request("prophecy", AIRequest.Tier.MEDIUM)
	assert_eq(provider.url(request), "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash:generateContent")
	var body := provider.build_body(request)
	assert_eq(body["systemInstruction"], {"parts": [{"text": "You are the Oracle."}]})
	assert_eq(body["contents"], [{"role": "user", "parts": [{"text": "Speak."}]}])
	var config: Dictionary = body["generationConfig"]
	assert_eq(config["responseMimeType"], "application/json")
	assert_eq(config["responseJsonSchema"], JsonSchema.to_wire(AIAssets.schema("prophecy")))
	assert_eq(config["maxOutputTokens"], 1234)
	assert_eq(config["thinkingConfig"], {"thinkingLevel": "low"})
	var old := GeminiProvider.new("g-key", {AIRequest.Tier.MEDIUM: "gemini-2.5-flash"}).build_body(request)
	assert_true(not old["generationConfig"].has("thinkingConfig"), "2.5 models reject thinking levels")


func test_gemini_reply_parsing() -> void:
	var provider := GeminiProvider.new("g-key")
	var request := _request("prophecy", AIRequest.Tier.SMALL)
	var text := _prophecy_text()
	var reply := {
		"candidates": [{"content": {"role": "model", "parts": [{"text": "thinking...", "thought": true}, {"text": text.left(10)}, {"text": text.substr(10)}]}, "finishReason": "STOP"}],
		"usageMetadata": {"promptTokenCount": 500, "candidatesTokenCount": 60, "thoughtsTokenCount": 40, "totalTokenCount": 600},
	}
	var response := provider.read_reply(request, reply)
	assert_true(response.ok, response.error)
	assert_eq(response.data["op"], ">=")
	assert_eq([response.input_tokens, response.output_tokens], [500, 100])
	assert_true(is_equal_approx(response.cost_usd, ModelPrices.estimate("gemini-3.5-flash-lite", 500, 100)) and response.cost_usd > 0.0)
	reply["candidates"][0]["finishReason"] = "SAFETY"
	assert_eq(provider.read_reply(request, reply).error, "Stopped early: SAFETY")
	assert_true(provider.read_reply(request, {"promptFeedback": {"blockReason": "PROHIBITED_CONTENT"}}).error.contains("PROHIBITED_CONTENT"))


# --- CLIs -------------------------------------------------------------------------------------

func test_codex_arguments() -> void:
	var request := _request("prophecy", AIRequest.Tier.SMALL)
	var arguments := CodexCliProvider.new("/bin/codex")._arguments(request)
	assert_eq(arguments[0], "exec")
	for flag: String in ["--json", "--skip-git-repo-check", "--ephemeral", "--ignore-user-config"]:
		assert_true(arguments.has(flag), flag)
	assert_eq(arguments[arguments.find("--sandbox") + 1], "read-only")
	assert_eq(arguments[arguments.find("--output-schema") + 1], CodexCliProvider.schema_path(request))
	assert_true(arguments.has("model_reasoning_effort=\"low\""))
	assert_true(arguments.has("model_instructions_file=" + JSON.stringify(CodexCliProvider.instructions_path(request))))
	assert_true(not arguments.has("--model"), "no model: the account's default")
	assert_eq(arguments.slice(-2), PackedStringArray(["--", "Speak."]), "the prompt goes last, after --")
	var with_model := CodexCliProvider.new("/bin/codex", {AIRequest.Tier.SMALL: "gpt-6-luna"})._arguments(request)
	assert_eq(with_model[with_model.find("--model") + 1], "gpt-6-luna")
	assert_eq(CodexCliProvider.schema_path(request), CodexCliProvider.schema_path(_request("prophecy")), "same schema, same file")
	assert_ne(CodexCliProvider.schema_path(request), CodexCliProvider.schema_path(_request("dilemma")))


func test_codex_output() -> void:
	var provider := CodexCliProvider.new("/bin/codex")
	# Captured from `codex exec --json` 0.155.1.
	var stdout := "\n".join([
		"{\"type\":\"thread.started\",\"thread_id\":\"01a14c57\"}",
		"{\"type\":\"turn.started\"}",
		"{\"type\":\"item.completed\",\"item\":{\"id\":\"item_0\",\"type\":\"error\",\"message\":\"Skill descriptions were shortened to fit the skills context budget.\"}}",
		"{\"type\":\"item.completed\",\"item\":{\"id\":\"item_1\",\"type\":\"agent_message\",\"text\":%s}}" % JSON.stringify(_prophecy_text()),
		"{\"type\":\"turn.completed\",\"usage\":{\"input_tokens\":9712,\"cached_input_tokens\":0,\"cache_write_input_tokens\":0,\"output_tokens\":19,\"reasoning_output_tokens\":0}}",
	]) + "\n"
	var output: Variant = provider._parse_stdout(stdout)
	assert_true(output is Dictionary)
	var response := provider._read_output(output)
	assert_true(response.ok, response.error)
	assert_eq(response.data["metric"], "tribe_count")
	assert_eq([response.input_tokens, response.output_tokens], [9712, 19])
	var failed := provider._read_output(provider._parse_stdout("{\"type\":\"turn.started\"}\n{\"type\":\"turn.failed\",\"error\":{\"message\":\"model not found\"}}\n"))
	assert_true(not failed.ok and failed.error.contains("model not found"), failed.error)
	assert_eq(provider._parse_stdout(""), null)
	assert_eq(provider._needs_closed_stdin(), true)


func test_gemini_cli_arguments_and_output() -> void:
	var provider := GeminiCliProvider.new("/bin/gemini")
	var request := _request("prophecy", AIRequest.Tier.LARGE)
	var arguments := provider._arguments(request)
	var prompt := arguments[arguments.find("--prompt") + 1]
	assert_true(prompt.begins_with("You are the Oracle.\n\nSpeak.\n\n") and prompt.contains("JSON Schema"), "system, prompt, then the schema")
	assert_eq(arguments[arguments.find("--output-format") + 1], "json")
	assert_eq(arguments[arguments.find("--model") + 1], "pro")
	assert_eq(arguments[arguments.find("--extensions") + 1], "none")
	var output := {
		"response": "Here it is:\n```json\n" + _prophecy_text() + "\n```",
		"stats": {"models": {"gemini-2.5-pro": {"api": {"totalRequests": 1}, "tokens": {"input": 800, "prompt": 900, "candidates": 50, "total": 1000, "cached": 100, "thoughts": 30, "tool": 0}}}},
	}
	var response := provider._read_output(output)
	assert_true(response.ok, response.error)
	assert_eq(response.data["years_from_now"], 20.0)
	assert_eq([response.input_tokens, response.output_tokens], [900, 80])
	assert_true(not provider._read_output({"error": {"type": "ApiError", "message": "quota"}}).ok)


func test_cli_stdin_wrapper() -> void:
	var plain := CliProcess.command_line("/bin/tool", PackedStringArray(["a b", "$HOME"]))
	assert_eq(plain, PackedStringArray(["/bin/tool", "a b", "$HOME"]))
	if OS.get_name() != "Windows":
		var wrapped := CliProcess.command_line("/bin/tool", PackedStringArray(["a b", "$HOME"]), true)
		assert_eq(wrapped, PackedStringArray(["/bin/sh", "-c", CliProcess.NO_STDIN_SCRIPT, "/bin/tool", "a b", "$HOME"]), "arguments stay separate words")
		var result: Dictionary = await CliProcess.run("/bin/cat", PackedStringArray(), 5.0, true)
		assert_true(result["ok"], "cat sees stdin closed and exits: %s" % result["error"])


# --- Catalog, create, probe -------------------------------------------------------------------

func test_catalog_create_round_trip() -> void:
	var catalog := AIProviders.catalog()
	assert_eq(catalog.size(), 11)
	var kinds := {}
	for entry: Dictionary in catalog:
		for key: String in ["id", "label", "kind", "needs_key", "default_base_url", "default_models"]:
			assert_true(entry.has(key), "%s has %s" % [entry.get("id"), key])
		kinds[entry["kind"]] = true
		var provider := AIProviders.create(entry["id"], {"api_key": "key", "base_url": entry["default_base_url"], "models": entry["default_models"]})
		assert_eq(provider.get_id(), entry["id"], "create builds what the catalog lists")
		if entry["kind"] in ["api_key", "local", "offline"]:
			assert_true(provider.is_available(), entry["id"] + " is ready with a key")
		assert_eq(provider.is_free(), entry["kind"] in ["local", "offline"], entry["id"] + " free?")
		assert_eq(entry["needs_key"], entry["kind"] == "api_key")
	assert_eq(kinds.keys().size(), 4)
	assert_eq(AIProviders.ids().size(), catalog.size())
	assert_true(not AIProviders.create("openai", {}).is_available(), "no key, not available")


func test_create_applies_settings() -> void:
	var openai := AIProviders.create("openai", {"api_key": "k", "models": {"small": "gpt-5-nano", "medium": ""}}) as OpenAICompatibleProvider
	assert_eq(openai.build_body(_request("prophecy", AIRequest.Tier.SMALL))["model"], "gpt-5-nano", "chosen model")
	assert_eq(openai.build_body(_request("prophecy", AIRequest.Tier.MEDIUM))["model"], "gpt-6.1-sol", "empty keeps the default")
	var ollama := AIProviders.create("ollama", {"base_url": "http://192.168.1.5:11434/v1/", "strict_schema": false}) as OpenAICompatibleProvider
	assert_eq(ollama.get_base_url(), "http://192.168.1.5:11434/v1")
	assert_eq(ollama.schema_mode, OpenAICompatibleProvider.SchemaMode.JSON_OBJECT)
	var anthropic := AIProviders.create("anthropic", {"api_key": "k", "models": {"large": "claude-sonnet-5-5"}}) as AnthropicProvider
	assert_eq(anthropic.build_body(_request())["model"], "claude-sonnet-5-5")
	var gemini := AIProviders.create("gemini", {"api_key": "k", "models": {"large": "gemini-3.8-flash"}}) as GeminiProvider
	assert_true(gemini.url(_request()).contains("gemini-3.8-flash"))
	assert_eq(AIProviders.create("nonsense").get_id(), "offline")
	assert_eq(AIProviders.tier_models({"small": "a", "large": "c"}), {AIRequest.Tier.SMALL: "a", AIRequest.Tier.LARGE: "c"})


func test_probe() -> void:
	var offline := await AIProbe.run(OfflineTemplatesProvider.new())
	assert_eq([offline["ok"], offline["structured"]], [true, true])
	var server := NoStrictServer.new()
	var result := await AIProbe.run(server)
	assert_true(result["ok"] and result["structured"], "JSON mode works: %s" % result)
	assert_eq(result["provider"], "ollama")
	assert_eq(server.schema_mode, OpenAICompatibleProvider.SchemaMode.JSON_OBJECT, "the provider keeps the mode that worked")
	assert_true(result.has("latency_ms") and result.has("error"))
	assert_eq(AIProbe.parse_model_list({"object": "list", "data": [{"id": "qwen3:8b"}, {"id": "llama3.1:8b"}, {"name": "no id"}]}), PackedStringArray(["llama3.1:8b", "qwen3:8b"]))
	assert_eq(AIProbe.parse_model_list(null), PackedStringArray())


func test_unreachable_server_fails_cleanly() -> void:
	var listed := await AIProbe.list_models("http://127.0.0.1:9/v1")
	assert_true(not listed["ok"] and not String(listed["error"]).is_empty(), "nothing listens on port 9")
	var response := await OpenAICompatibleProvider.ollama("", "http://127.0.0.1:9/v1").complete_streaming(_request("prophecy"), func(_text: String) -> void: pass)
	assert_true(not response.ok, "streaming to nowhere fails instead of hanging")
