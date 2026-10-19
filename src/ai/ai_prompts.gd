class_name AIPrompts
extends RefCounted
## The prompt library's manifest (prompt_library/manifest.json): for each task, its current prompt
## version, model tier, reply schema, the placeholder its context fills, and a size budget.
## Prompt files are named <task>.<version>.system.md and .user.md; old versions stay loadable,
## so a change of wording is a new version, never an edit (see tests/test_golden_prompts.gd).

const MANIFEST := "res://ai/prompt_library/manifest.json"
const TIERS := {"small": AIRequest.Tier.SMALL, "medium": AIRequest.Tier.MEDIUM, "large": AIRequest.Tier.LARGE}

static var _manifest: Dictionary = {}


static func manifest() -> Dictionary:
	if _manifest.is_empty():
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
		assert(data is Dictionary, "Missing or invalid prompt manifest")
		_manifest = data
	return _manifest


static func tasks() -> Array[String]:
	var names: Array[String] = []
	names.assign(manifest()["tasks"].keys())
	return names


## {"version", "tier", "schema", "input", "max_chars"} for a task.
static func entry(task: String) -> Dictionary:
	var entries: Dictionary = manifest()["tasks"]
	assert(entries.has(task), "No prompt for task: " + task)
	return entries[task]


static func version(task: String) -> String:
	return String(entry(task)["version"])


static func tier(task: String) -> AIRequest.Tier:
	return TIERS[String(entry(task)["tier"])]


## Every version of a task's prompt that has files in the library, oldest first.
static func versions(task: String) -> Array[String]:
	var found: Array[String] = []
	for file: String in DirAccess.get_files_at(AIAssets.PROMPT_DIR):
		var parts := file.split(".")
		if parts.size() == 4 and parts[0] == task and parts[2] == "system" and parts[3] == "md":
			found.append(parts[1])
	found.sort_custom(func(a: String, b: String) -> bool: return a.trim_prefix("v").to_int() < b.trim_prefix("v").to_int())
	return found


## A task's system prompt at a version, filled from values. Shared snippets ({ceiling}, {gentle})
## come from the manifest; pass "gentle": true in values to switch the Gentle Mode line on.
static func system(task: String, prompt_version: String, values: Dictionary) -> String:
	var filled := values.duplicate()
	var snippets: Dictionary = manifest()["snippets"]
	filled["ceiling"] = AIAssets.prompt(String(snippets["ceiling"])).strip_edges()
	filled["gentle"] = " " + AIAssets.prompt(String(snippets["gentle"])).strip_edges() if values.get("gentle", false) else ""
	return AIAssets.prompt("%s.%s.system" % [task, prompt_version], filled)


## A task's user prompt at a version, with its context (as JSON) in the task's input placeholder.
static func user(task: String, prompt_version: String, context: Dictionary) -> String:
	return AIAssets.prompt("%s.%s.user" % [task, prompt_version], {String(entry(task)["input"]): JSON.stringify(context, "  ")})
