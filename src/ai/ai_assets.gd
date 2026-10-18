class_name AIAssets
extends RefCounted
## Loads schemas and prompt templates. Prompt files are .md, which Godot does not export
## by default: add "ai/prompt_library/*.md" to the export preset's non-resource filter.

const SCHEMA_DIR := "res://ai/schemas/"
const PROMPT_DIR := "res://ai/prompt_library/"


static func schema(schema_name: String) -> Dictionary:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(SCHEMA_DIR + schema_name + ".json"))
	assert(data is Dictionary, "Missing or invalid schema: " + schema_name)
	return data


## Reads a prompt and fills {placeholders} from values.
static func prompt(prompt_name: String, values: Dictionary = {}) -> String:
	var text := FileAccess.get_file_as_string(PROMPT_DIR + prompt_name + ".md")
	assert(not text.is_empty(), "Missing prompt: " + prompt_name)
	return text.format(values)
