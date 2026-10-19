class_name CodexCliProvider
extends CliAIProvider
## OpenAI's Codex CLI (`codex exec`), using the player's existing ChatGPT login or key.
## Read-only sandbox, no user config, MCP servers, web search or saved sessions; our system
## prompt replaces Codex's coding-agent instructions, and --output-schema enforces the reply.
## Codex still sends some tool and skill descriptions (about 10k input tokens per call).

const EFFORT := {
	AIRequest.Tier.SMALL: "low",
	AIRequest.Tier.MEDIUM: "low",
	AIRequest.Tier.LARGE: "medium",
}
## Features that add tools or context a one-shot answer doesn't need.
const DISABLED_FEATURES: Array[String] = [
	"plugins", "apps", "browser_use", "computer_use", "image_generation", "multi_agent", "memories",
	"shell_tool", "skill_search", "tool_suggest", "view_image", "sleep_tool", "skill_mcp_dependency_install",
]

var _models: Dictionary


## models: optional {AIRequest.Tier: model id}; a missing tier uses Codex's default model.
func _init(path: String = "", models: Dictionary = {}) -> void:
	super(path)
	_models = models


func get_id() -> String:
	return "codex_cli"


func get_command() -> String:
	return "codex"


## Where the schema and instruction files go, outside the game folder.
static func work_dir() -> String:
	return OS.get_user_data_dir().path_join("ai_cli")


## Files are named after their content, so concurrent calls can share them safely.
static func schema_path(request: AIRequest) -> String:
	return work_dir().path_join("codex-schema-%s.json" % _schema_text(request).md5_text())


static func instructions_path(request: AIRequest) -> String:
	return work_dir().path_join("codex-system-%s.md" % request.system.md5_text())


func complete(request: AIRequest) -> AIResponse:
	var response: AIResponse = await super(request)
	if response.ok:
		# The strict schema made optional fields nullable; null means "left out".
		response.data = JsonSchema.drop_optional_nulls(response.data, request.schema)
	return response


func _prepare(request: AIRequest) -> String:
	DirAccess.make_dir_recursive_absolute(work_dir())
	for file: Array in [[schema_path(request), _schema_text(request)], [instructions_path(request), request.system]]:
		if FileAccess.file_exists(file[0]):
			continue
		var handle := FileAccess.open(file[0], FileAccess.WRITE)
		if handle == null:
			return "Could not write %s (%s)" % [file[0], error_string(FileAccess.get_open_error())]
		handle.store_string(file[1])
		handle.close()
	return ""


func _needs_closed_stdin() -> bool:
	return true


func _arguments(request: AIRequest) -> PackedStringArray:
	var arguments := PackedStringArray([
		"exec",
		"--json",
		"--skip-git-repo-check",
		"--ephemeral",
		"--ignore-user-config", # no MCP servers, plugins or profiles; the login still works
		"--ignore-rules",
		"--sandbox", "read-only",
		"--cd", work_dir(),
		"--output-schema", schema_path(request),
		"-c", "model_reasoning_effort=" + JSON.stringify(EFFORT[request.tier]),
		"-c", "web_search=\"disabled\"",
		"-c", "include_environment_context=false",
		"-c", "include_permissions_instructions=false",
	])
	if not request.system.is_empty():
		# A JSON string is also a valid TOML string.
		arguments.append_array(["-c", "model_instructions_file=" + JSON.stringify(instructions_path(request))])
	for feature: String in DISABLED_FEATURES:
		arguments.append_array(["--disable", feature])
	if _models.has(request.tier) and not String(_models[request.tier]).is_empty():
		arguments.append_array(["--model", _models[request.tier]])
	arguments.append_array(["--", request.prompt])
	return arguments


## `codex exec --json` prints one event per line. Collects the last agent message, the turn's
## usage and any failure into {"message", "usage", "error"}.
func _parse_stdout(stdout: String) -> Variant:
	var output := {}
	var warnings := PackedStringArray()
	for line: String in stdout.split("\n", false):
		var event: Variant = JSON.parse_string(line)
		if not event is Dictionary:
			continue
		var item: Dictionary = event.get("item", {}) if event.get("item") is Dictionary else {}
		match String(event.get("type", "")):
			"item.completed":
				if item.get("type") == "agent_message":
					output["message"] = String(item.get("text", ""))
				elif item.get("type") == "error":
					warnings.append(String(item.get("message", "")))
			"turn.completed":
				output["usage"] = event.get("usage", {})
			"turn.failed":
				output["error"] = String((event.get("error", {}) as Dictionary).get("message", "turn failed"))
			"error":
				output["error"] = String(event.get("message", "error"))
	if not output.has("message") and not output.has("error") and not warnings.is_empty():
		output["error"] = warnings[-1]
	return output if not output.is_empty() else null


func _read_output(output: Dictionary) -> AIResponse:
	if not output.has("message"):
		return AIResponse.failure(get_id(), "Codex error: " + String(output.get("error", "no reply")).left(300))
	var reply: Variant = ReplyJson.parse_object(output["message"])
	if not reply is Dictionary:
		return AIResponse.failure(get_id(), "Reply was not a JSON object")
	var response := AIResponse.success(get_id(), reply)
	var usage: Dictionary = output.get("usage", {})
	response.input_tokens = int(usage.get("input_tokens", 0))
	response.output_tokens = int(usage.get("output_tokens", 0))
	return response


static func _schema_text(request: AIRequest) -> String:
	return JSON.stringify(JsonSchema.to_strict_wire(request.schema))
