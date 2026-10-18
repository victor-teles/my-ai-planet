class_name AIProviders
extends RefCounted
## The provider lineup: what kinds exist (catalog, for the AI Settings screen), building one
## from saved settings (create), and picking one from the environment until that screen exists.
## MYAIPLANET_AI = offline | anthropic | openai | openrouter | gemini | ollama | lmstudio
##   | claude_code | codex_cli | gemini_cli | grok_cli. MYAIPLANET_MODEL overrides the model of
## every tier (handy for local models). Keys come from ANTHROPIC_API_KEY, OPENAI_API_KEY,
## OPENROUTER_API_KEY and GEMINI_API_KEY.
## Unset: the first API key found, then an installed CLI, then offline. Local servers are only
## used when chosen, since finding out whether one is running takes a request.

const KEY_ENV := {
	"anthropic": "ANTHROPIC_API_KEY",
	"openai": "OPENAI_API_KEY",
	"openrouter": "OPENROUTER_API_KEY",
	"gemini": "GEMINI_API_KEY",
}
const AUTO_ORDER: Array[String] = ["anthropic", "openai", "gemini", "openrouter", "claude_code", "codex_cli", "gemini_cli", "grok_cli"]
const TIER_KEYS := {"small": AIRequest.Tier.SMALL, "medium": AIRequest.Tier.MEDIUM, "large": AIRequest.Tier.LARGE}


static func from_environment() -> AIProvider:
	var chosen := OS.get_environment("MYAIPLANET_AI")
	if not chosen.is_empty() and ids().has(chosen):
		var config := {"api_key": OS.get_environment(KEY_ENV.get(chosen, ""))}
		var model := OS.get_environment("MYAIPLANET_MODEL")
		if not model.is_empty():
			config["models"] = {"small": model, "medium": model, "large": model}
		return create(chosen, config)
	if not chosen.is_empty():
		push_warning("AIProviders: unknown MYAIPLANET_AI '%s', picking one automatically" % chosen)
	for id: String in AUTO_ORDER:
		var provider := create(id, {"api_key": OS.get_environment(KEY_ENV.get(id, ""))})
		if provider.is_available():
			return provider
	return OfflineTemplatesProvider.new()


## Every provider kind, for the AI Settings screen: {id, label, kind ("api_key" | "local" |
## "cli" | "offline"), needs_key, default_base_url, default_models {small, medium, large}}.
## default_models is empty for kinds whose models aren't chosen here.
static func catalog() -> Array[Dictionary]:
	var presets := OpenAICompatibleProvider.PRESETS
	return [
		_entry("anthropic", "Anthropic (Claude)", "api_key", "https://api.anthropic.com/v1", AnthropicProvider.MODELS),
		_entry("openai", presets["openai"]["label"], "api_key", presets["openai"]["base_url"], presets["openai"]["models"]),
		_entry("gemini", "Google Gemini", "api_key", GeminiProvider.BASE_URL, GeminiProvider.MODELS),
		_entry("openrouter", presets["openrouter"]["label"], "api_key", presets["openrouter"]["base_url"], presets["openrouter"]["models"]),
		_entry("ollama", presets["ollama"]["label"], "local", presets["ollama"]["base_url"], presets["ollama"]["models"]),
		_entry("lmstudio", presets["lmstudio"]["label"], "local", presets["lmstudio"]["base_url"], presets["lmstudio"]["models"]),
		_entry("claude_code", "Claude Code", "cli", "", ClaudeCodeProvider.MODELS),
		_entry("codex_cli", "Codex CLI", "cli", "", {}),
		_entry("gemini_cli", "Gemini CLI", "cli", "", GeminiCliProvider.MODELS),
		_entry("grok_cli", "Grok CLI", "cli", "", {}),
		_entry("offline", "Offline stories", "offline", "", {}),
	]


static func ids() -> PackedStringArray:
	var list := PackedStringArray()
	for entry: Dictionary in catalog():
		list.append(entry["id"])
	return list


## Builds a provider from saved settings: {api_key, base_url, models: {small, medium, large},
## path (CLI only; empty searches the usual folders), strict_schema (OpenAI-compatible only;
## false asks for plain JSON mode)}. Every key is optional. Unknown ids give the offline provider.
static func create(id: String, config: Dictionary = {}) -> AIProvider:
	var api_key := String(config.get("api_key", ""))
	var base_url := String(config.get("base_url", ""))
	var path := String(config.get("path", ""))
	var models := tier_models(config.get("models", {}))
	match id:
		"anthropic":
			return AnthropicProvider.new(api_key, models)
		"gemini":
			return GeminiProvider.new(api_key, models, base_url)
		"openai", "openrouter", "ollama", "lmstudio":
			var provider := OpenAICompatibleProvider.preset(id, api_key, models, base_url)
			if not config.get("strict_schema", true):
				provider.schema_mode = OpenAICompatibleProvider.SchemaMode.JSON_OBJECT
			return provider
		"claude_code":
			return ClaudeCodeProvider.new(path, models)
		"codex_cli":
			return CodexCliProvider.new(path, models)
		"gemini_cli":
			return GeminiCliProvider.new(path, models)
		"grok_cli":
			return GrokCliProvider.new(path)
	return OfflineTemplatesProvider.new()


## {"small": "model-a", ...} -> {AIRequest.Tier.SMALL: "model-a", ...}, skipping empty names.
static func tier_models(names: Dictionary) -> Dictionary:
	var models := {}
	for key: String in TIER_KEYS:
		if not String(names.get(key, "")).is_empty():
			models[TIER_KEYS[key]] = String(names[key])
	return models


static func _entry(id: String, label: String, kind: String, base_url: String, models: Dictionary) -> Dictionary:
	var names := {}
	for key: String in TIER_KEYS:
		if models.has(TIER_KEYS[key]):
			names[key] = models[TIER_KEYS[key]]
	return {
		"id": id,
		"label": label,
		"kind": kind,
		"needs_key": kind == "api_key",
		"default_base_url": base_url,
		"default_models": names,
	}
