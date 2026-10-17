class_name CliLocator
extends RefCounted
## Finds command-line tools. Games launched from Steam or the macOS Finder don't get the
## user's shell PATH, so common install folders are searched as well.


static func find(command: String) -> String:
	var home := OS.get_environment("USERPROFILE" if OS.get_name() == "Windows" else "HOME")
	var folders := PackedStringArray(OS.get_environment("PATH").split(";" if OS.get_name() == "Windows" else ":", false))
	folders.append_array([
		home.path_join(".local/bin"),
		home.path_join(".claude/local"),
		home.path_join(".npm-global/bin"),
		"/opt/homebrew/bin",
		"/usr/local/bin",
		"/usr/bin",
	])
	if OS.get_name() == "Windows":
		folders.append(OS.get_environment("APPDATA").path_join("npm"))
	var names := PackedStringArray([command])
	if OS.get_name() == "Windows":
		names = PackedStringArray([command + ".exe", command + ".cmd"])
	for folder: String in folders:
		for file_name: String in names:
			var path := folder.path_join(file_name)
			if FileAccess.file_exists(path):
				return path
	return ""
