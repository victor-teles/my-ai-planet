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


## Where the tool was found (or was given), "" if it wasn't.
func executable() -> String:
	return _path


func is_available() -> bool:
	return not _path.is_empty()


func complete(request: AIRequest) -> AIResponse:
	if not is_available():
		return AIResponse.failure(get_id(), "%s CLI not found" % get_command())
	var prepared := _prepare(request)
	if not prepared.is_empty():
		return AIResponse.failure(get_id(), prepared)
	var result: Dictionary = await CliProcess.run(_path, _arguments(request), request.timeout_sec, _needs_closed_stdin())
	var output: Variant = _parse_stdout(String(result["stdout"]))
	if not output is Dictionary:
		return AIResponse.failure(get_id(), "%s %s" % [result["error"], String(result["stderr"]).strip_edges().left(300)])
	return _read_output(output)


## Runs before the command, e.g. to write files it reads. Returns an error, or "".
func _prepare(_request: AIRequest) -> String:
	return ""


## True for tools that wait for stdin to close (see CliProcess.NO_STDIN_SCRIPT).
func _needs_closed_stdin() -> bool:
	return false


## The tool's output as one Dictionary for _read_output(); null if it isn't there.
func _parse_stdout(stdout: String) -> Variant:
	return JSON.parse_string(stdout) if not stdout.strip_edges().is_empty() else null


func _arguments(_request: AIRequest) -> PackedStringArray:
	return PackedStringArray()


func _read_output(_output: Dictionary) -> AIResponse:
	return AIResponse.failure(get_id(), "Not implemented")
