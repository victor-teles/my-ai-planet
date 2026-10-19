extends SceneTree
## Headless test runner: runs every tests/test_*.gd. Use scripts/test.sh, or:
##   godot --headless --path src -s res://tests/run_tests.gd [-- [--quick] [--files=a.gd,b.gd] [filter]]
## --quick skips the tests a file lists in its SLOW constant; --files runs only those files
## (scripts/test.sh runs one process per file this way, in parallel).

const TEST_DIR := "res://tests/"


func _initialize() -> void:
	_run()


func _run() -> void:
	var filter := ""
	var quick := false
	var only_files := PackedStringArray()
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--quick":
			quick = true
		elif arg.begins_with("--files="):
			only_files = arg.trim_prefix("--files=").split(",", false)
		else:
			filter = arg
	var passed := 0
	var failed := 0
	var skipped := 0
	var files := Array(DirAccess.get_files_at(TEST_DIR)).filter(
		func(file_name: String) -> bool: return file_name.begins_with("test_") and file_name.ends_with(".gd") and file_name != "test_case.gd"
	)
	if not only_files.is_empty():
		files = files.filter(func(file_name: String) -> bool: return file_name in only_files)
	files.sort()
	for file_name: String in files:
		var script: GDScript = load(TEST_DIR + file_name)
		var slow: Array = script.get_script_constant_map().get("SLOW", [])
		for method: Dictionary in script.get_script_method_list():
			var method_name := String(method["name"])
			if not method_name.begins_with("test_"):
				continue
			var test_id := "%s::%s" % [file_name.get_basename(), method_name]
			if filter and not test_id.contains(filter):
				continue
			if quick and method_name in slow:
				skipped += 1
				continue
			var started := Time.get_ticks_msec()
			var test: TestCase = script.new()
			await test.call(method_name)
			var took := "%.1fs" % ((Time.get_ticks_msec() - started) / 1000.0)
			if test.failures.is_empty():
				passed += 1
				print("  ok    ", test_id, "  ", took)
			else:
				failed += 1
				print("  FAIL  ", test_id, "  ", took)
				for failure: String in test.failures:
					print("        ", failure)
	print("\n%d passed, %d failed%s" % [passed, failed, ", %d slow skipped" % skipped if skipped else ""])
	quit(1 if failed > 0 else 0)
