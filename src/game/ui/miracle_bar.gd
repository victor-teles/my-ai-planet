class_name MiracleBar
extends Control
## The god's hand, along the bottom: Influence, a tile per miracle (its icon, name and cost) and
## the tribe the miracles fall on. Hovering a miracle tells what it does and on whom; a miracle
## that can't be cast now looks faded, and clicking it says why (and points at the tribe chip when
## a tribe is what's missing).

signal cast(id: String)
signal clear_target

const TILE := Vector2(66, 54)
const HINT_SECONDS := 3.0
## miracle id -> what it falls on, for the hint
const TARGETS := {"rain": "the whole island", "drought": "the whole island"}

var _panel := PanelContainer.new()
var _influence := Label.new()
var _tiles: Dictionary = {} ## id -> Button
var _costs: Dictionary = {} ## id -> Label
var _reasons: Dictionary = {} ## id -> why it can't be cast now ("" if it can)
var _target_box := PanelContainer.new()
var _target_name := Label.new()
var _target_note := Label.new()
var _target_clear: Button
var _hint := PanelContainer.new()
var _hint_title := Label.new()
var _hint_text := Label.new()
var _hint_reason := Label.new()
var _hovered := ""
var _hint_left := 0.0
var _influence_shown := -1.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.theme_type_variation = "Card"
	var box := UiStyle.card_box(UiStyle.SPACE_2)
	box.content_margin_left = UiStyle.SPACE_3
	box.content_margin_right = UiStyle.SPACE_3
	_panel.add_theme_stylebox_override("panel", box)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_panel.add_child(row)

	# Influence: the god's purse.
	var purse := VBoxContainer.new()
	purse.add_theme_constant_override("separation", -2)
	purse.alignment = BoxContainer.ALIGNMENT_CENTER
	purse.custom_minimum_size.x = 76
	purse.mouse_filter = Control.MOUSE_FILTER_PASS
	purse.tooltip_text = "Influence: what miracles cost.\nIt grows while your people prosper, and when a prophecy comes true or is broken."
	var amount := HBoxContainer.new()
	amount.add_theme_constant_override("separation", 3)
	amount.alignment = BoxContainer.ALIGNMENT_CENTER
	amount.mouse_filter = Control.MOUSE_FILTER_IGNORE
	amount.add_child(UiStyle.icon("star", 18))
	_influence.add_theme_font_override("font", UiStyle.font("display"))
	UiStyle.inked(_influence, 22)
	_influence.mouse_filter = Control.MOUSE_FILTER_IGNORE
	amount.add_child(_influence)
	purse.add_child(amount)
	var caption := UiStyle.section("INFLUENCE")
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	purse.add_child(caption)
	row.add_child(purse)
	row.add_child(_divider())

	for id: String in Miracles.ORDER:
		row.add_child(_tile(id))
	row.add_child(_divider())
	row.add_child(_build_target())

	# The hint ribbon floats above the bar.
	_hint.theme_type_variation = "Plaque"
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.visible = false
	var words := VBoxContainer.new()
	words.add_theme_constant_override("separation", 0)
	_hint.add_child(words)
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 6)
	_hint_title.add_theme_font_override("font", UiStyle.font("strong"))
	UiStyle.inked(_hint_title, UiStyle.BODY)
	title_row.add_child(_hint_title)
	UiStyle.inked(_hint_text, UiStyle.SMALL + 1)
	_hint_text.add_theme_color_override("font_color", UiStyle.INK_SOFT)
	_hint_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_text.custom_minimum_size.x = 420
	words.add_child(title_row)
	words.add_child(_hint_text)
	UiStyle.inked(_hint_reason, UiStyle.SMALL + 1)
	_hint_reason.add_theme_font_override("font", UiStyle.font("strong"))
	_hint_reason.add_theme_color_override("font_color", UiStyle.BAD)
	words.add_child(_hint_reason)
	add_child(_hint)


func _tile(id: String) -> Control:
	var definition: Dictionary = Miracles.DEFINITIONS[id]
	var button := Button.new()
	button.theme_type_variation = "MiracleButton"
	button.text = String(definition["name"])
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = TILE
	button.icon = UiIcons.texture(id, 24)
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(_on_tile.bind(id))
	button.mouse_entered.connect(func() -> void: _hover(id))
	button.mouse_exited.connect(func() -> void: _hover(""))
	# The cost, as a small gold badge in the top right corner.
	var cost := Label.new()
	cost.text = "%d" % int(definition["cost"])
	cost.add_theme_font_override("font", UiStyle.font("strong"))
	cost.add_theme_font_size_override("font_size", UiStyle.CAPTION)
	cost.add_theme_color_override("font_color", UiStyle.INK)
	var badge := StyleBoxFlat.new()
	badge.bg_color = UiStyle.GOLD_SOFT
	badge.border_color = Color(UiStyle.INK, 0.7)
	badge.set_border_width_all(1)
	badge.set_corner_radius_all(99)
	badge.content_margin_left = 5
	badge.content_margin_right = 5
	badge.content_margin_top = 0
	badge.content_margin_bottom = 1
	cost.add_theme_stylebox_override("normal", badge)
	cost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cost.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	cost.position = Vector2(-18, -6)
	button.add_child(cost)
	_tiles[id] = button
	_costs[id] = cost
	return button


func _build_target() -> Control:
	_target_box.theme_type_variation = "Well"
	var box := UiStyle.well_box()
	box.content_margin_top = 4
	box.content_margin_bottom = 4
	_target_box.add_theme_stylebox_override("panel", box)
	_target_box.custom_minimum_size.x = 168
	_target_box.mouse_filter = Control.MOUSE_FILTER_PASS
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_target_box.add_child(row)
	row.add_child(UiStyle.icon("target", 20))
	var words := VBoxContainer.new()
	words.add_theme_constant_override("separation", -2)
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var caption := UiStyle.section("TARGET")
	words.add_child(caption)
	_target_name.add_theme_font_override("font", UiStyle.font("strong"))
	UiStyle.inked(_target_name, UiStyle.BODY)
	_target_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_target_name.custom_minimum_size.x = 112
	words.add_child(_target_name)
	UiStyle.inked(_target_note, UiStyle.CAPTION)
	_target_note.add_theme_color_override("font_color", UiStyle.INK_FAINT)
	_target_note.text = "click a camp or person"
	words.add_child(_target_note)
	row.add_child(words)
	_target_clear = UiStyle.ghost_button("close", "Clear the target", "", 12)
	_target_clear.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_target_clear.pressed.connect(func() -> void: clear_target.emit())
	row.add_child(_target_clear)
	return _target_box


func _divider() -> Control:
	var line := VSeparator.new()
	var style := StyleBoxLine.new()
	style.color = Color(UiStyle.INK, 0.16)
	style.vertical = true
	style.thickness = 1
	line.add_theme_stylebox_override("separator", style)
	line.add_theme_constant_override("separation", 6)
	return line


## Places the bar centered at the bottom of the screen, the hint above it.
func arrange(view: Vector2, margin: float) -> void:
	_panel.reset_size()
	var size_now := _panel.get_combined_minimum_size()
	position = Vector2.ZERO
	size = view
	_panel.position = Vector2(((view.x - size_now.x) / 2.0), view.y - margin - size_now.y).floor()
	_hint.reset_size()
	_hint.position = Vector2((view.x - _hint.size.x) / 2.0, _panel.position.y - _hint.size.y - UiStyle.SPACE_2).floor()


## The bar's height on screen (the docks stop above it).
func bar_height() -> float:
	return _panel.get_combined_minimum_size().y


## Refreshes Influence, the tiles and the target. playing: whether miracles can be cast at all.
func show_state(state: WorldState, tribe: String, playing: bool, delta: float) -> void:
	if not is_equal_approx(_influence_shown, state.influence):
		_influence_shown = state.influence
		_influence.text = "%.1f" % state.influence
	for id: String in _tiles:
		var button := _tiles[id] as Button
		var definition: Dictionary = Miracles.DEFINITIONS[id]
		var reason := Miracles.why_not(state, id, tribe) if playing else "Time is waiting: answer the Oracle first."
		if reason == "Not enough Influence":
			reason = "Not enough Influence: it costs %d, you have %.1f." % [int(definition["cost"]), state.influence]
		elif reason == "Choose a tribe first":
			reason = "Choose a tribe first: click a camp or a person on the island."
		_reasons[id] = reason
		button.modulate.a = 1.0 if reason.is_empty() else 0.45
		button.tooltip_text = "%s (costs %d Influence, on %s)\n%s%s" % [
			definition["name"], int(definition["cost"]), _target_of(id, tribe), definition["description"],
			"\n\n" + reason if reason else "",
		]
		var short := state.influence < float(definition["cost"])
		(_costs[id] as Label).add_theme_color_override("font_color", UiStyle.BAD if short else UiStyle.INK)
	var chosen := not tribe.is_empty()
	_target_name.text = "the %s" % tribe if chosen else "No tribe chosen"
	_target_name.add_theme_color_override("font_color", UiStyle.INK if chosen else UiStyle.INK_FAINT)
	_target_note.visible = not chosen
	_target_clear.visible = chosen
	_target_box.tooltip_text = "Miracles that fall on one tribe fall on the %s." % tribe if chosen else "Click a camp or a person on the island to choose the tribe your miracles fall on."
	if _hint_left > 0.0:
		_hint_left -= delta
		if _hint_left <= 0.0 and _hovered.is_empty():
			_hint.visible = false
	if not _hovered.is_empty():
		_fill_hint(_hovered, tribe, false)


func _target_of(id: String, tribe: String) -> String:
	if TARGETS.has(id):
		return String(TARGETS[id])
	return "the %s" % tribe if tribe else "one tribe"


func _hover(id: String) -> void:
	_hovered = id
	if id.is_empty():
		if _hint_left <= 0.0:
			_hint.visible = false
		return
	_hint.visible = true
	_hint_left = 0.0


func _on_tile(id: String) -> void:
	var reason := String(_reasons.get(id, ""))
	if reason.is_empty():
		cast.emit(id)
		return
	# Can't be cast: say why, and nudge the eye toward what's missing.
	_fill_hint(id, "", true)
	_hint.visible = true
	_hint_left = HINT_SECONDS
	var nudge: Control = _target_box if reason.begins_with("Choose a tribe") else _tiles[id] as Control
	var tween := nudge.create_tween()
	nudge.pivot_offset = nudge.size / 2.0
	tween.tween_property(nudge, "scale", Vector2(1.06, 1.06), 0.08).set_ease(Tween.EASE_OUT)
	tween.tween_property(nudge, "scale", Vector2.ONE, 0.16).set_ease(Tween.EASE_IN_OUT)


func _fill_hint(id: String, tribe: String, clicked: bool) -> void:
	var definition: Dictionary = Miracles.DEFINITIONS[id]
	_hint_title.text = "%s  ·  %d Influence  ·  on %s" % [definition["name"], int(definition["cost"]), _target_of(id, tribe if tribe else _chosen_tribe())]
	_hint_text.text = String(definition["description"])
	var reason := String(_reasons.get(id, ""))
	_hint_reason.text = reason
	_hint_reason.visible = not reason.is_empty()
	if clicked:
		_hint_reason.add_theme_color_override("font_color", UiStyle.BAD)


func _chosen_tribe() -> String:
	return _target_name.text.trim_prefix("the ") if _target_clear.visible else ""


## Shows a miracle's hint as if it were hovered (screenshots and checks).
func preview(id: String) -> void:
	if _tiles.has(id):
		_hovered = id
		_hint.visible = true


## For tests and checks: why a miracle can't be cast right now ("" if it can).
func reason_for(id: String) -> String:
	return String(_reasons.get(id, ""))


func panel_rect() -> Rect2:
	return _panel.get_global_rect()
