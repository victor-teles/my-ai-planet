class_name CliProcess
extends RefCounted
## Runs a command without a shell (arguments are passed as a list, never interpolated)
## and collects its output while the game keeps rendering.


## Returns {"ok": bool, "exit_code": int, "stdout": String, "stderr": String, "error": String}.
static func run(path: String, arguments: PackedStringArray, timeout_sec: float) -> Dictionary:
	var info := OS.execute_with_pipe(path, arguments, false)
	if info.is_empty():
		return {"ok": false, "exit_code": -1, "stdout": "", "stderr": "", "error": "Could not start " + path}
	var stdio: FileAccess = info["stdio"]
	var stderr: FileAccess = info["stderr"]
	var pid: int = info["pid"]
	var deadline := Time.get_ticks_msec() + int(timeout_sec * 1000.0)
	var out := PackedByteArray()
	var err := PackedByteArray()
	while OS.is_process_running(pid):
		out.append_array(_drain(stdio))
		err.append_array(_drain(stderr))
		if Time.get_ticks_msec() > deadline:
			OS.kill(pid)
			return {"ok": false, "exit_code": -1, "stdout": "", "stderr": "", "error": "Timed out after %d s" % timeout_sec}
		await Frames.next()
	out.append_array(_drain(stdio))
	err.append_array(_drain(stderr))
	var exit_code := OS.get_process_exit_code(pid)
	return {
		"ok": exit_code == 0,
		"exit_code": exit_code,
		"stdout": out.get_string_from_utf8(),
		"stderr": err.get_string_from_utf8(),
		"error": "" if exit_code == 0 else "Exited with code %d" % exit_code,
	}


static func _drain(pipe: FileAccess) -> PackedByteArray:
	var bytes := PackedByteArray()
	while true:
		var chunk := pipe.get_buffer(65536)
		if chunk.is_empty():
			break
		bytes.append_array(chunk)
	return bytes
