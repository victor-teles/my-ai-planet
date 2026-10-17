class_name CliAIProvider
extends AIProvider
## Base for providers that run an AI command-line tool the player already has installed
## and logged in to. Subclasses build the arguments and read the tool's JSON output.

var _path: String


## Leave path empty to search the usual install folders for get_command().
func _init(path: String = "") -> void:
	_path = path if not path.is_empty() else CliLocator.find(get_command())


func get_command() -> String:
	return ""


func is_available() -> bool:
	return not _path.is_empty()


func complete(request: AIRequest) -> AIResponse:
	if not is_available():
		return AIResponse.failure(get_id(), "%s CLI not found" % get_command())
	var result: Dictionary = await CliProcess.run(_path, _arguments(request), request.timeout_sec)
	var stdout := String(result["stdout"])
	var output: Variant = JSON.parse_string(stdout) if not stdout.is_empty() else null
	if not output is Dictionary:
		return AIResponse.failure(get_id(), "%s %s" % [result["error"], String(result["stderr"]).strip_edges().left(300)])
	return _read_output(output)


func _arguments(_request: AIRequest) -> PackedStringArray:
	return PackedStringArray()


func _read_output(_output: Dictionary) -> AIResponse:
	return AIResponse.failure(get_id(), "Not implemented")
