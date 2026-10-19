class_name AISettings
extends RefCounted
## What the player chose in the AI Settings screen, kept in user://ai_settings.cfg: which provider
## answers each model tier (thoughts on a local model and chronicles on Claude, say), each
## provider's key, server, models, CLI path and schema mode, the session budget and Gentle Mode.
## The file is encrypted with a key tied to this machine, so keys aren't readable at a glance
## or portable to another computer (it is not protection against someone with this machine).
## Environment variables still win when set, so tests and dev runs keep working: MYAIPLANET_AI
## (with MYAIPLANET_MODEL) picks the provider of every tier as AIProviders.from_environment() does,
## the key variables (AIProviders.KEY_ENV) replace saved keys, MYAIPLANET_AI_BUDGET the spending
## cap and MYAIPLANET_GENTLE Gentle Mode.

const PATH := "user://ai_settings.cfg"
const AUTO := "auto" ## a tier left on this picks the first ready provider (see auto_provider())
const TIER_NAMES: Array[String] = ["small", "medium", "large"]
const TEXT_FIELDS: Array[String] = ["api_key", "base_url", "path"]
const PASS_PREFIX := "my-ai-planet:"

var file_path := PATH
var saved := false ## loaded from or written to the file: the player has made a choice
var tiers := {"small": AUTO, "medium": AUTO, "large": AUTO} ## tier name -> provider id or AUTO
var providers := {} ## provider id -> {api_key, base_url, path, models {small, medium, large}, strict_schema}
var cap_usd := AIBudget.DEFAULT_CAP_USD ## 0 = unlimited
var max_calls := AIBudget.DEFAULT_MAX_CALLS ## 0 = unlimited
var gentle := false


## The saved settings, or the defaults when there is no file yet.
static func load_from(path: String = PATH) -> AISettings:
	var settings := AISettings.new()
	settings.file_path = path
	var file := ConfigFile.new()
	# A plain file is an older save from before encryption: it is read once and encrypted on the next save.
	if file.load_encrypted_pass(path, _passphrase()) != OK and file.load(path) != OK:
		return settings
	settings.saved = true
	for tier: String in TIER_NAMES:
		var id := String(file.get_value("routing", tier, AUTO))
		settings.tiers[tier] = id if AIProviders.ids().has(id) else AUTO
	settings.cap_usd = maxf(float(file.get_value("budget", "cap_usd", AIBudget.DEFAULT_CAP_USD)), 0.0)
	settings.max_calls = maxi(int(file.get_value("budget", "max_calls", AIBudget.DEFAULT_MAX_CALLS)), 0)
	settings.gentle = bool(file.get_value("play", "gentle", false))
	for section: String in file.get_sections():
		if not section.begins_with("provider."):
			continue
		var config := {"models": {}, "strict_schema": bool(file.get_value(section, "strict_schema", true))}
		for field: String in TEXT_FIELDS:
			config[field] = String(file.get_value(section, field, ""))
		for tier: String in TIER_NAMES:
			config["models"][tier] = String(file.get_value(section, "model_" + tier, ""))
		settings.providers[section.trim_prefix("provider.")] = config
	return settings


func save() -> Error:
	var file := ConfigFile.new()
	for tier: String in TIER_NAMES:
		file.set_value("routing", tier, tiers[tier])
	file.set_value("budget", "cap_usd", cap_usd)
	file.set_value("budget", "max_calls", max_calls)
	file.set_value("play", "gentle", gentle)
	for id: String in providers:
		var config := provider(id)
		var section := "provider." + id
		for field: String in TEXT_FIELDS:
			file.set_value(section, field, config[field])
		for tier: String in TIER_NAMES:
			file.set_value(section, "model_" + tier, config["models"][tier])
		file.set_value(section, "strict_schema", config["strict_schema"])
	var error := file.save_encrypted_pass(file_path, _passphrase())
	if error == OK:
		saved = true
	return error


static func _passphrase() -> String:
	return PASS_PREFIX + OS.get_unique_id()


## One provider's saved settings with every field present ("" for unset text and models).
func provider(id: String) -> Dictionary:
	var stored: Dictionary = providers.get(id, {})
	var config := {"models": {}, "strict_schema": bool(stored.get("strict_schema", true))}
	for field: String in TEXT_FIELDS:
		config[field] = String(stored.get(field, ""))
	var models: Dictionary = stored.get("models", {})
	for tier: String in TIER_NAMES:
		config["models"][tier] = String(models.get(tier, ""))
	return config


func set_provider(id: String, config: Dictionary) -> void:
	providers[id] = config.duplicate(true)


## What AIProviders.create() gets: the saved settings, with the environment's key and model
## (MYAIPLANET_MODEL) winning when set.
func effective_config(id: String) -> Dictionary:
	var config := provider(id)
	var key := OS.get_environment(String(AIProviders.KEY_ENV.get(id, "")))
	if AIProviders.KEY_ENV.has(id) and not key.is_empty():
		config["api_key"] = key
	var model := OS.get_environment("MYAIPLANET_MODEL")
	if not model.is_empty():
		config["models"] = {"small": model, "medium": model, "large": model}
	return config


## The environment variables overriding these settings right now (names, never key values).
static func environment_overrides() -> PackedStringArray:
	var found := PackedStringArray()
	for variable: String in ["MYAIPLANET_AI", "MYAIPLANET_MODEL", "MYAIPLANET_AI_BUDGET", "MYAIPLANET_GENTLE"]:
		var value := OS.get_environment(variable)
		if not value.is_empty():
			found.append("%s=%s" % [variable, value])
	for id: String in AIProviders.KEY_ENV:
		if not OS.get_environment(AIProviders.KEY_ENV[id]).is_empty():
			found.append(String(AIProviders.KEY_ENV[id]))
	return found


## The first ready provider: a saved or environment API key, then an installed CLI, then offline
## (the order of AIProviders.AUTO_ORDER). Local servers are only used when chosen.
func auto_provider() -> AIProvider:
	for id: String in AIProviders.AUTO_ORDER:
		var candidate := AIProviders.create(id, effective_config(id))
		if candidate.is_available():
			return candidate
	return OfflineTemplatesProvider.new()


## The provider the Oracle should use: MYAIPLANET_AI when set, otherwise one per tier from these
## settings (an AIRouter when the tiers differ).
func build_provider() -> AIProvider:
	if not OS.get_environment("MYAIPLANET_AI").is_empty():
		return AIProviders.from_environment()
	var by_id := {} ## provider id -> the one instance tiers share
	var routes := {}
	for tier: String in TIER_NAMES:
		var id := String(tiers[tier])
		var built: AIProvider = by_id.get(id)
		if built == null:
			built = auto_provider() if id == AUTO else AIProviders.create(id, effective_config(id))
			built = by_id.get(built.get_id(), built) # "auto" may pick a provider another tier names
			by_id[id] = built
			by_id[built.get_id()] = built
		routes[AIProviders.TIER_KEYS[tier]] = built
	var router := AIRouter.new(routes)
	var members := router.members()
	return members[0] if members.size() == 1 else router


## The spending cap in force: MYAIPLANET_AI_BUDGET when set, else the saved one.
func effective_cap_usd() -> float:
	var cap := OS.get_environment("MYAIPLANET_AI_BUDGET")
	return maxf(cap.to_float(), 0.0) if cap.is_valid_float() else cap_usd


## Gentle Mode in force: MYAIPLANET_GENTLE when set ("1" is on), else the saved choice.
func effective_gentle() -> bool:
	var value := OS.get_environment("MYAIPLANET_GENTLE")
	return value == "1" if not value.is_empty() else gentle


## Puts these settings to work on a running Oracle: provider, budget caps and Gentle Mode.
func apply(oracle: Oracle) -> void:
	oracle.budget.cap_usd = effective_cap_usd()
	oracle.budget.max_calls = max_calls
	oracle.gentle = effective_gentle()
	oracle.set_provider(build_provider())
