class_name AISettingsPanel
extends PanelContainer
## The AI Settings screen: whose AI the Oracle speaks through. Provider: pick one of the lineup
## (AIProviders.catalog()), fill in what it needs (key, server, models, CLI path), test the
## connection (AIProbe) and, for local servers, list their models. Routing & budget: which provider
## answers each model tier, the session's spending and call caps, and Gentle Mode. Usage: the live
## meter of calls, failures, cache hits, tokens and cost, per provider and per task, the share of
## the budget used, and why the Oracle is offline if it is. Apply saves (AISettings) and swaps the
## provider on the running Oracle.

signal closed
signal applied

const PANEL_SIZE := Vector2(860, 560)
const TABS: Array[String] = ["Provider", "Routing & budget", "Usage"]
const LABEL_WIDTH := 120.0
const REFRESH_SECONDS := 0.5
const KIND_NOTES := {
	"api_key": "Uses your API key: every call costs a little, on your account.",
	"local": "A model server on this computer: free and private. Start it before testing.",
	"cli": "An AI command-line tool you are already logged in to. It answers more slowly.",
	"offline": "The built-in stories: no AI, no cost, always there.",
}
const STRICT_IDS: Array[String] = ["openai", "openrouter", "ollama", "lmstudio"] ## OpenAI-compatible
const URL_IDS: Array[String] = ["openai", "openrouter", "gemini", "ollama", "lmstudio"] ## a server address is used
const TASK_NAMES := {
	"thought": "thoughts", "dilemma": "dilemma cards", "prophecy": "prophecies",
	"chronicle": "chronicles", "destiny": "the last chapter",
	"style": "building styles", "heraldry": "banners", "poster": "posters", "monument": "monuments",
	"language": "languages", "names": "local names",
}
const USAGE_COLUMNS: Array[String] = ["", "Calls", "Failed", "Cached", "Tokens in", "Tokens out", "Cost", "Avg time"]
const GOOD := Color(0.20, 0.45, 0.22)
const BAD := Color(0.70, 0.22, 0.18)

var oracle: Oracle
var settings: AISettings

var _catalog: Array[Dictionary] = AIProviders.catalog()
var _tab := "Provider"
var _tab_buttons: Dictionary = {} ## tab -> Button
var _pages: Dictionary = {} ## tab -> Control
var _scroll := ScrollContainer.new()
var _env_note := Label.new()
var _status := Label.new()
var _since := REFRESH_SECONDS

# Provider page
var _picker := OptionButton.new()
var _picked := "" ## the provider id the form shows
var _kind_note := Label.new()
var _key_row: Control
var _key := LineEdit.new()
var _key_note := Label.new()
var _url_row: Control
var _url := LineEdit.new()
var _models_box := VBoxContainer.new()
var _model_edits: Dictionary = {} ## tier name -> LineEdit
var _list_row := HBoxContainer.new()
var _list_button: Button
var _model_list := HFlowContainer.new()
var _list_note := Label.new()
var _path_row: Control
var _path := LineEdit.new()
var _path_status := Label.new()
var _strict := CheckBox.new()
var _test_button: Button
var _test_result := Label.new()

# Routing & budget page
var _route_pickers: Dictionary = {} ## tier name -> OptionButton
var _auto_note := Label.new()
var _cap := SpinBox.new()
var _calls := SpinBox.new()
var _gentle := CheckBox.new()

# Usage page
var _state_line := Label.new()
var _budget_bar: ProgressBar
var _budget_text := Label.new()
var _cache_text := Label.new()
var _grid := GridContainer.new()


func _init() -> void:
	theme = UiStyle.theme()
	theme_type_variation = "Card"
	add_theme_stylebox_override("panel", UiStyle.card_box(UiStyle.SPACE_5 - 4))
	custom_minimum_size = Vector2(PANEL_SIZE.x, 0.0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	add_child(column)

	var close := UiStyle.close_button()
	close.tooltip_text = "Close without saving   [A or Esc]"
	close.pressed.connect(func() -> void: closed.emit())
	column.add_child(UiStyle.header(UiStyle.title("The Oracle's voice", UiStyle.DISPLAY - 2), close, "oracle"))
	var intro := UiStyle.label("The Oracle can speak through your own AI, or tell its built-in stories offline. Only summaries of the simulated world are sent, nothing about you.", UiStyle.SMALL + 1, true)
	intro.add_theme_color_override("font_color", UiStyle.INK_SOFT)
	intro.custom_minimum_size.x = PANEL_SIZE.x - 48.0
	column.add_child(intro)
	UiStyle.inked(_env_note, 12)
	_env_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_env_note.custom_minimum_size.x = PANEL_SIZE.x - 48.0
	_env_note.add_theme_color_override("font_color", UiStyle.DARK)
	column.add_child(_env_note)

	column.add_child(UiStyle.tabs(TABS, select_tab, _tab_buttons))

	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var pages := VBoxContainer.new()
	pages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(pages)
	column.add_child(_scroll)
	_pages["Provider"] = _build_provider_page()
	_pages["Routing & budget"] = _build_routing_page()
	_pages["Usage"] = _build_usage_page()
	for tab: String in TABS:
		pages.add_child(_pages[tab])

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)
	UiStyle.inked(_status, 13)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(_status)
	var apply := UiStyle.primary_button("Apply and save")
	apply.tooltip_text = "Save these settings and switch the Oracle to them now"
	apply.pressed.connect(apply_settings)
	footer.add_child(apply)
	var done := UiStyle.ink_button("Close")
	done.pressed.connect(func() -> void: closed.emit())
	footer.add_child(done)
	column.add_child(footer)
	select_tab(_tab)


## Shows the screen for this Oracle, with the saved settings in the form (read again from their
## file, so what was typed but never applied is dropped).
func open(ai_oracle: Oracle, ai_settings: AISettings) -> void:
	oracle = ai_oracle
	settings = AISettings.load_from(ai_settings.file_path)
	var overrides := AISettings.environment_overrides()
	_env_note.text = "Set in the environment, which wins over these settings: %s" % ", ".join(overrides) if not overrides.is_empty() else ""
	_env_note.visible = not overrides.is_empty()
	for tier: String in AISettings.TIER_NAMES:
		_select_route(tier, String(settings.tiers[tier]))
	_cap.value = settings.cap_usd
	_calls.value = settings.max_calls
	_gentle.button_pressed = settings.gentle
	_picked = ""
	_pick(_first_choice())
	_status.text = ""
	_since = REFRESH_SECONDS
	visible = true


func select_tab(tab: String) -> void:
	if not TABS.has(tab):
		return
	_tab = tab
	(_tab_buttons[tab] as Button).button_pressed = true
	for page_name: String in _pages:
		(_pages[page_name] as Control).visible = page_name == tab
	_scroll.scroll_vertical = 0
	_since = REFRESH_SECONDS


## Shows one provider in the form (debug and screenshots too).
func pick_provider(id: String) -> void:
	if AIProviders.ids().has(id):
		_pick(id)


## Fills the server address of the provider shown (debug and screenshots).
func set_server(url: String) -> void:
	_url.text = url


## The size it would like; the host fits it to the screen.
func wanted_size() -> Vector2:
	var page := _pages[_tab] as Control
	var chrome := get_combined_minimum_size().y
	return Vector2(PANEL_SIZE.x, clampf(chrome + page.get_combined_minimum_size().y + UiStyle.SPACE_2, 320.0, PANEL_SIZE.y))


## Call every frame while visible: keeps the usage meter fresh.
func refresh(delta: float) -> void:
	if not visible:
		return
	_since += delta
	if _since < REFRESH_SECONDS or oracle == null:
		return
	_since = 0.0
	_auto_note.text = "Automatic picks %s: an API key first (saved or in the environment), then an installed AI CLI, then offline." % _label_of(settings.auto_provider().get_id()) if settings else ""
	if _tab == "Usage":
		_refresh_usage()


# --- Provider page ----------------------------------------------------------------------

func _build_provider_page() -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 8)
	for entry: Dictionary in _catalog:
		_picker.add_item(String(entry["label"]))
	_picker.focus_mode = Control.FOCUS_NONE
	_picker.add_theme_font_size_override("font_size", 15)
	_picker.item_selected.connect(func(index: int) -> void: _choose(String(_catalog[index]["id"])))
	page.add_child(_row("Provider", _picker))
	UiStyle.inked(_kind_note, 13)
	_kind_note.add_theme_color_override("font_color", ToonMaterials.INK.lightened(0.25))
	page.add_child(_kind_note)

	_key.secret = true
	_key.placeholder_text = "paste your API key"
	_key_row = _row("API key", _key)
	page.add_child(_key_row)
	UiStyle.inked(_key_note, 12)
	_key_note.add_theme_color_override("font_color", ToonMaterials.INK.lightened(UiStyle.FAINT))
	page.add_child(_key_note)
	_url_row = _row("Server", _url)
	page.add_child(_url_row)

	_models_box.add_theme_constant_override("separation", 6)
	_models_box.add_child(UiStyle.section("MODELS (EMPTY KEEPS THE DEFAULT)"))
	var models := HBoxContainer.new()
	models.add_theme_constant_override("separation", 8)
	for tier: String in AISettings.TIER_NAMES:
		var edit := LineEdit.new()
		edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		edit.add_theme_font_size_override("font_size", 14)
		edit.tooltip_text = "The model for %s tasks (%s)" % [tier, _tier_tasks(tier)]
		_model_edits[tier] = edit
		var cell := VBoxContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_child(UiStyle.label("%s · %s" % [tier.capitalize(), _tier_tasks(tier)], 12))
		cell.add_child(edit)
		models.add_child(cell)
	_models_box.add_child(models)
	_list_row.add_theme_constant_override("separation", 8)
	_list_button = _small_button("List the server's models")
	_list_button.pressed.connect(list_models)
	_list_row.add_child(_list_button)
	UiStyle.inked(_list_note, 12)
	_list_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_list_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_row.add_child(_list_note)
	_models_box.add_child(_list_row)
	_model_list.add_theme_constant_override("h_separation", 10)
	_models_box.add_child(_model_list)
	page.add_child(_models_box)

	_path.placeholder_text = "found automatically"
	_path.text_changed.connect(func(_text: String) -> void: _update_path_status())
	_path_row = _row("CLI path", _path)
	page.add_child(_path_row)
	UiStyle.inked(_path_status, 13)
	page.add_child(_path_status)

	_strict.text = "Strict JSON schema (turn it off for models that can't follow one)"
	_strict.focus_mode = Control.FOCUS_NONE
	_strict.add_theme_font_size_override("font_size", 13)
	page.add_child(_strict)

	var test_row := HBoxContainer.new()
	test_row.add_theme_constant_override("separation", 10)
	_test_button = UiStyle.ink_button("Test connection")
	_test_button.tooltip_text = "Asks one tiny question to see that it answers, how fast, and whether it follows a schema"
	_test_button.pressed.connect(test_connection)
	test_row.add_child(_test_button)
	var use_all := UiStyle.ink_button("Use for every task")
	use_all.tooltip_text = "Route all three tiers to this provider (see Routing & budget)"
	use_all.pressed.connect(use_for_every_task)
	test_row.add_child(use_all)
	UiStyle.inked(_test_result, 13)
	_test_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_test_result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	test_row.add_child(_test_result)
	page.add_child(test_row)
	return page


## The player picked a provider: show it, and unless the tiers are routed to different providers
## (set on the Routing page), it becomes the one every task goes to once applied.
func _choose(id: String) -> void:
	_pick(id)
	var routes := PackedStringArray()
	for tier: String in AISettings.TIER_NAMES:
		if not routes.has(_route_id(tier)):
			routes.append(_route_id(tier))
	if routes.size() == 1:
		use_for_every_task()
	else:
		_status.remove_theme_color_override("font_color")
		_status.text = "The tiers go to different providers: use \"Use for every task\" or the Routing page to send them to %s." % _label_of(id)


## Shows a provider's fields, keeping what was typed for the one shown before.
func _pick(id: String) -> void:
	if not _picked.is_empty() and settings:
		_store_form()
	_picked = id
	var entry := _entry(id)
	_picker.select(_catalog.find(entry))
	var kind := String(entry["kind"])
	var config := settings.provider(id) if settings else {}
	_kind_note.text = String(KIND_NOTES.get(kind, ""))
	_key_row.visible = bool(entry["needs_key"])
	_key_note.visible = _key_row.visible
	_key.text = String(config.get("api_key", ""))
	var key_env := String(AIProviders.KEY_ENV.get(id, ""))
	_key_note.text = "Keys are saved encrypted in the game's user data folder, and are only sent to the provider."
	if not key_env.is_empty() and not OS.get_environment(key_env).is_empty():
		_key_note.text += "  %s is set and wins." % key_env
	_url_row.visible = URL_IDS.has(id)
	_url.text = String(config.get("base_url", ""))
	_url.placeholder_text = String(entry["default_base_url"])
	var defaults: Dictionary = entry["default_models"]
	_models_box.visible = not defaults.is_empty() or id == "codex_cli"
	var models: Dictionary = config.get("models", {})
	for tier: String in AISettings.TIER_NAMES:
		var edit := _model_edits[tier] as LineEdit
		edit.text = String(models.get(tier, ""))
		edit.placeholder_text = String(defaults.get(tier, "the CLI's default"))
	_list_row.visible = kind == "local"
	_list_note.text = ""
	UiStyle.clear(_model_list)
	_path_row.visible = kind == "cli"
	_path_status.visible = kind == "cli"
	_path.text = String(config.get("path", ""))
	_update_path_status()
	_strict.visible = STRICT_IDS.has(id)
	_strict.button_pressed = bool(config.get("strict_schema", true))
	_test_result.text = ""


## Keeps the form's fields for the provider shown in the working settings (not saved yet).
func _store_form() -> void:
	var models := {}
	for tier: String in AISettings.TIER_NAMES:
		models[tier] = (_model_edits[tier] as LineEdit).text.strip_edges()
	settings.set_provider(_picked, {
		"api_key": _key.text.strip_edges(),
		"base_url": _url.text.strip_edges(),
		"path": _path.text.strip_edges(),
		"models": models,
		"strict_schema": _strict.button_pressed,
	})


func _update_path_status() -> void:
	if _entry(_picked).get("kind") != "cli":
		return
	var cli := AIProviders.create(_picked, {"path": _path.text.strip_edges()}) as CliAIProvider
	var found := cli != null and cli.is_available()
	if _path.text.strip_edges() and not FileAccess.file_exists(_path.text.strip_edges()):
		found = false
	_path_status.text = "✓ detected: %s" % cli.executable() if found else "✗ not found: install it, or give the path to its program"
	_path_status.add_theme_color_override("font_color", GOOD if found else BAD)


## The probe: one tiny SMALL-tier question to the provider as the form describes it.
func test_connection() -> void:
	_store_form()
	var provider := AIProviders.create(_picked, settings.effective_config(_picked))
	_test_button.disabled = true
	_test_result.add_theme_color_override("font_color", ToonMaterials.INK)
	_test_result.text = "Asking %s..." % _label_of(_picked)
	var result: Dictionary = await AIProbe.run(provider)
	_test_button.disabled = false
	var answered := bool(result["ok"])
	if answered and bool(result["structured"]):
		_test_result.text = "✓ Answered in %s and follows the schema." % _duration(float(result["latency_ms"]))
	elif answered:
		_test_result.text = "~ Answered in %s, but not in the schema: it may be too weak for some tasks. %s" % [_duration(float(result["latency_ms"])), String(result["error"]).left(160)]
	else:
		_test_result.text = "✗ %s" % String(result["error"]).left(220)
	_test_result.add_theme_color_override("font_color", GOOD if answered and bool(result["structured"]) else BAD)
	var compatible := provider as OpenAICompatibleProvider
	if compatible and compatible.schema_mode == OpenAICompatibleProvider.SchemaMode.JSON_OBJECT and bool(result["structured"]):
		_strict.button_pressed = false # the probe found that only plain JSON mode works


## Asks a local server which models it has; clicking one fills the model fields.
func list_models() -> void:
	_store_form()
	var config := settings.effective_config(_picked)
	var url := String(config["base_url"]) if String(config["base_url"]) else String(_entry(_picked)["default_base_url"])
	_list_button.disabled = true
	_list_note.text = "Asking the server..."
	var listed: Dictionary = await AIProbe.list_models(url, String(config["api_key"]))
	_list_button.disabled = false
	UiStyle.clear(_model_list)
	if not bool(listed["ok"]):
		_list_note.text = "✗ Couldn't reach it: %s" % String(listed["error"]).left(160)
		return
	var names: PackedStringArray = listed["models"]
	_list_note.text = "%d models. Click one to use it for every tier." % names.size() if not names.is_empty() else "The server has no models yet."
	for model: String in names:
		var link := UiStyle.link(model, 13)
		link.pressed.connect(_use_model.bind(model))
		_model_list.add_child(link)


func _use_model(model: String) -> void:
	for tier: String in AISettings.TIER_NAMES:
		(_model_edits[tier] as LineEdit).text = model


## Routes every tier to the provider shown (applied with the rest).
func use_for_every_task() -> void:
	for tier: String in AISettings.TIER_NAMES:
		_select_route(tier, _picked)
	_status.remove_theme_color_override("font_color")
	_status.text = "Every task goes to %s once you apply." % _label_of(_picked)


# --- Routing & budget page ---------------------------------------------------------------

func _build_routing_page() -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 8)
	page.add_child(UiStyle.section("WHO ANSWERS EACH KIND OF TASK"))
	for tier: String in AISettings.TIER_NAMES:
		var picker := OptionButton.new()
		picker.focus_mode = Control.FOCUS_NONE
		picker.add_theme_font_size_override("font_size", 14)
		picker.add_item("Automatic")
		for entry: Dictionary in _catalog:
			picker.add_item(String(entry["label"]))
		_route_pickers[tier] = picker
		var row := _row("%s tier" % tier.capitalize(), picker)
		var tasks := UiStyle.label(_tier_tasks(tier), 13)
		tasks.custom_minimum_size.x = 260.0
		tasks.add_theme_color_override("font_color", ToonMaterials.INK.lightened(0.25))
		row.add_child(tasks)
		page.add_child(row)
	UiStyle.inked(_auto_note, 12)
	_auto_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_auto_note.custom_minimum_size.x = PANEL_SIZE.x - 60.0
	_auto_note.add_theme_color_override("font_color", ToonMaterials.INK.lightened(UiStyle.FAINT))
	page.add_child(_auto_note)

	page.add_child(UiStyle.section("BUDGET FOR ONE SESSION"))
	_cap.min_value = 0.0
	_cap.max_value = 100.0
	_cap.step = 0.01
	_cap.prefix = "$"
	_calls.min_value = 0
	_calls.max_value = 100000
	_calls.step = 1
	var caps := _row("Spending cap", _cap)
	var calls_label := UiStyle.label("Paid calls", 14)
	calls_label.custom_minimum_size.x = 90.0
	calls_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	caps.add_child(calls_label)
	caps.add_child(_calls)
	for spin: SpinBox in [_cap, _calls]:
		spin.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		spin.custom_minimum_size.x = 150.0
		spin.get_line_edit().add_theme_font_size_override("font_size", 14)
	var no_cap := UiStyle.label("0 = no cap", 12)
	no_cap.add_theme_color_override("font_color", ToonMaterials.INK.lightened(UiStyle.FAINT))
	caps.add_child(no_cap)
	page.add_child(caps)
	var budget_note := UiStyle.label("Local models and offline stories are free. Near the cap, tasks use a cheaper tier; at the cap, the Oracle goes offline.", 12, true)
	budget_note.custom_minimum_size.x = PANEL_SIZE.x - 60.0
	budget_note.add_theme_color_override("font_color", ToonMaterials.INK.lightened(UiStyle.FAINT))
	page.add_child(budget_note)

	page.add_child(UiStyle.section("STORIES"))
	_gentle.text = "Gentle Mode: softer stories, never darker than a fable"
	_gentle.focus_mode = Control.FOCUS_NONE
	_gentle.add_theme_font_size_override("font_size", 14)
	page.add_child(_gentle)
	return page


func _select_route(tier: String, id: String) -> void:
	var picker := _route_pickers[tier] as OptionButton
	var index := _catalog.find(_entry(id)) + 1 if AIProviders.ids().has(id) else 0
	picker.select(index)


func _route_id(tier: String) -> String:
	var index := (_route_pickers[tier] as OptionButton).selected
	return AISettings.AUTO if index <= 0 else String(_catalog[index - 1]["id"])


# --- Usage page ----------------------------------------------------------------------------

func _build_usage_page() -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 8)
	UiStyle.inked(_state_line, 15)
	_state_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_state_line.custom_minimum_size.x = PANEL_SIZE.x - 60.0
	page.add_child(_state_line)
	var budget_row := HBoxContainer.new()
	budget_row.add_theme_constant_override("separation", 10)
	budget_row.add_child(UiStyle.label("Budget used", 13))
	_budget_bar = UiStyle.bar(0.0, 220.0, Color(0.45, 0.70, 0.40))
	budget_row.add_child(_budget_bar)
	UiStyle.inked(_budget_text, 13)
	budget_row.add_child(_budget_text)
	page.add_child(budget_row)
	UiStyle.inked(_cache_text, 12)
	_cache_text.add_theme_color_override("font_color", ToonMaterials.INK.lightened(UiStyle.FAINT))
	page.add_child(_cache_text)
	_grid.columns = USAGE_COLUMNS.size()
	_grid.add_theme_constant_override("h_separation", 18)
	_grid.add_theme_constant_override("v_separation", 3)
	page.add_child(_grid)
	return page


func _refresh_usage() -> void:
	var usage := oracle.usage()
	var offline := bool(usage["offline"])
	_state_line.text = "Offline (%s). The world keeps turning on the built-in stories." % usage["offline_reason"] if offline else "Speaking through %s%s." % [_routing_text(), "   ·   Gentle Mode" if usage["gentle"] else ""]
	_state_line.add_theme_color_override("font_color", BAD if offline else GOOD)
	var budget: Dictionary = usage["budget"]
	var share := float(budget["used_share"])
	_budget_bar.value = clampf(share, 0.0, 1.0)
	(_budget_bar.get_theme_stylebox("fill") as StyleBoxFlat).bg_color = UiStyle.need_color(1.0 - share)
	var cap := float(budget["cap_usd"])
	var max_calls := int(budget["max_calls"])
	_budget_text.text = "%d%%   ·   $%.4f of %s   ·   %d of %s paid calls" % [
		roundi(share * 100.0), float(budget["spent_usd"]), "$%.2f" % cap if cap > 0.0 else "no cap",
		int(budget["paid_calls"]), str(max_calls) if max_calls > 0 else "no cap",
	]
	var cache: Dictionary = usage["cache"]
	_cache_text.text = "Answers reused from the cache: %d of %d asked   ·   %d kept in memory" % [int(cache["hits"]), int(cache["hits"]) + int(cache["misses"]), int(cache["size"])]
	UiStyle.clear(_grid)
	for column: String in USAGE_COLUMNS:
		_cell(column, true)
	_stats_rows("BY PROVIDER", usage["providers"], func(id: String) -> String: return _label_of(id))
	_stats_rows("BY TASK", usage["tasks"], func(task: String) -> String: return String(TASK_NAMES.get(task, task)).capitalize())
	var total: Dictionary = usage["total"]
	if int(total["calls"]) + int(total["cache_hits"]) + int(total["failures"]) == 0:
		_cell("No questions asked yet.", false)
		for k: int in USAGE_COLUMNS.size() - 1:
			_cell("", false)
		return
	_cell("THIS SESSION", true, 11)
	for k: int in USAGE_COLUMNS.size() - 1:
		_cell("", false)
	_stats_row("Total", total)


func _stats_rows(heading: String, table: Dictionary, name_of: Callable) -> void:
	if table.is_empty():
		return
	_cell(heading, true, 11)
	for k: int in USAGE_COLUMNS.size() - 1:
		_cell("", false)
	var keys: Array = table.keys()
	keys.sort()
	for key: String in keys:
		_stats_row(String(name_of.call(key)), table[key])


func _stats_row(row_name: String, stats: Dictionary) -> void:
	var avg := float(stats["avg_latency_ms"])
	for text: String in [
		row_name, str(int(stats["calls"])), str(int(stats["failures"])), str(int(stats["cache_hits"])),
		str(int(stats["input_tokens"])), str(int(stats["output_tokens"])), "$%.4f" % float(stats["cost_usd"]),
		_duration(avg) if avg > 0.0 else "–",
	]:
		_cell(text, false)


func _cell(text: String, heading: bool, font_size: int = 13) -> void:
	var label := UiStyle.label(text, font_size)
	if heading:
		label.add_theme_color_override("font_color", ToonMaterials.INK.lightened(0.2))
		label.add_theme_font_size_override("font_size", 12 if font_size == 13 else font_size)
	_grid.add_child(label)


# --- Applying ------------------------------------------------------------------------------

## Saves the form and switches the running Oracle to it.
func apply_settings() -> void:
	_store_form()
	for tier: String in AISettings.TIER_NAMES:
		settings.tiers[tier] = _route_id(tier)
	settings.cap_usd = _cap.value
	settings.max_calls = int(_calls.value)
	settings.gentle = _gentle.button_pressed
	var error := settings.save()
	settings.apply(oracle)
	_status.add_theme_color_override("font_color", GOOD if error == OK else BAD)
	_status.text = "Saved. The Oracle now speaks through %s." % _routing_text() if error == OK else "Applied, but couldn't save (%s)." % error_string(error)
	if not OS.get_environment("MYAIPLANET_AI").is_empty():
		_status.text += " MYAIPLANET_AI still wins while it is set."
	_since = REFRESH_SECONDS
	applied.emit()


## "Claude Code" or "Ollama (small), Anthropic (Claude) (medium, large)".
func _routing_text() -> String:
	var router := oracle.provider as AIRouter
	if router == null:
		return _label_of(oracle.provider.get_id())
	var parts := PackedStringArray()
	for member: AIProvider in router.members():
		var tiers := PackedStringArray()
		for tier: String in AISettings.TIER_NAMES:
			if router.route(AIProviders.TIER_KEYS[tier]) == member:
				tiers.append(tier)
		parts.append("%s (%s)" % [_label_of(member.get_id()), ", ".join(tiers)])
	return ", ".join(parts)


# --- Helpers -------------------------------------------------------------------------------

## The provider to show first: the one answering the large tier, or the automatic pick.
func _first_choice() -> String:
	var large := String(settings.tiers["large"])
	if large != AISettings.AUTO:
		return large
	var routed: String = oracle.provider.members()[-1].get_id() if oracle else ""
	return routed if AIProviders.ids().has(routed) else String(_catalog[0]["id"])


func _entry(id: String) -> Dictionary:
	for entry: Dictionary in _catalog:
		if entry["id"] == id:
			return entry
	return _catalog[-1]


func _label_of(id: String) -> String:
	for entry: Dictionary in _catalog:
		if entry["id"] == id:
			return String(entry["label"])
	return id


## "thoughts" or "prophecies, chronicles, the last chapter": the tasks the manifest puts on a tier.
func _tier_tasks(tier: String) -> String:
	var names := PackedStringArray()
	for task: String in AIPrompts.tasks():
		if AIPrompts.tier(task) == AIProviders.TIER_KEYS[tier]:
			names.append(String(TASK_NAMES.get(task, task)))
	return ", ".join(names) if not names.is_empty() else "nothing yet"


func _row(text: String, field: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var label := UiStyle.label(text, 14)
	label.custom_minimum_size.x = LABEL_WIDTH
	row.add_child(label)
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if field is LineEdit:
		(field as LineEdit).add_theme_font_size_override("font_size", 14)
	row.add_child(field)
	return row


func _small_button(text: String) -> Button:
	var button := UiStyle.ink_button(text)
	button.add_theme_font_size_override("font_size", 13)
	return button


func _duration(ms: float) -> String:
	return "%.1f s" % (ms / 1000.0) if ms >= 1000.0 else "%d ms" % roundi(ms)
