class_name TestCase
extends RefCounted
## Base class for tests. Every method starting with "test_" runs; it may use `await`.

var failures := PackedStringArray()


func assert_true(condition: bool, message: String = "expected true") -> void:
	if not condition:
		failures.append(message)


func assert_eq(actual: Variant, expected: Variant, message: String = "") -> void:
	if typeof(actual) != typeof(expected) or actual != expected:
		failures.append("%sexpected %s, got %s" % [message + ": " if message else "", var_to_str(expected), var_to_str(actual)])


func assert_ne(actual: Variant, unexpected: Variant, message: String = "") -> void:
	if typeof(actual) == typeof(unexpected) and actual == unexpected:
		failures.append("%sdid not expect %s" % [message + ": " if message else "", var_to_str(actual)])


## A user:// path of this process only, so test runs in other checkouts can't overwrite it.
func scratch_path(file_name: String) -> String:
	return "user://test_%d_%s" % [OS.get_process_id(), file_name]
