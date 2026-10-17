extends SceneTree
## Headless test runner: runs every tests/test_*.gd. Use scripts/test.sh, or:
##   godot --headless --path Godot -s res://tests/run_tests.gd [-- filter]

const TEST_DIR := "res://tests/"


func _initialize() -> void:
	_run()


func _run() -> void:
	var filter := ""
	var user_args := OS.get_cmdline_user_args()
	if not user_args.is_empty():
		filter = user_args[0]
	var passed := 0
	var failed := 0
	var files := Array(DirAccess.get_files_at(TEST_DIR)).filter(
		func(file_name: String) -> bool: return file_name.begins_with("test_") and file_name.ends_with(".gd") and file_name != "test_case.gd"
	)
	files.sort()
	for file_name: String in files:
		var script: GDScript = load(TEST_DIR + file_name)
		for method: Dictionary in script.get_script_method_list():
			var method_name := String(method["name"])
			if not method_name.begins_with("test_"):
				continue
			var test_id := "%s::%s" % [file_name.get_basename(), method_name]
			if filter and not test_id.contains(filter):
				continue
			var test: TestCase = script.new()
			await test.call(method_name)
			if test.failures.is_empty():
				passed += 1
				print("  ok    ", test_id)
			else:
				failed += 1
				print("  FAIL  ", test_id)
				for failure: String in test.failures:
					print("        ", failure)
	print("\n%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
