class_name TopBar
extends Control
## The strip across the top: the date and time controls (pause, five speeds) at the left, the
## island's name, age and people in the middle with chips for what matters now (drought, smog,
## omens, its destiny), and the buttons that open the feed, the charts and the AI at the right.
## Keys stay the fast way in; here they are hints in the tooltips.

signal pause_pressed
signal speed_picked(index: int)
signal nav_pressed(id: String)

const HEIGHT := 46.0
## Speed buttons: the label, relative to the slowest speed.
const SPEED_LABELS: Array[String] = ["1×", "3×", "10×", "30×", "90×"]
## id -> [icon, label, tooltip, key]
const NAV := {
	"feed": ["feed", "Feed", "Life in the valley: everything that happens, newest first", "Tab"],
	"evolution": ["genes", "Genes", "Evolution: how the valley's genes and numbers change over the years", "E"],
	"society": ["society", "Society", "The island's societies over time: dystopia, freedom, control, fear...", "H"],
	"ai": ["oracle", "Oracle", "AI settings: who the Oracle speaks through, the budget and usage", "A"],
	"help": ["keyboard", "", "Keys and controls", "?"],
}

## Days per second at each speed (set by the host), for the tooltips.
var speeds: Array[float] = []

var _date := Label.new()
var _when := Label.new()
var _pause := Button.new()
var _speeds: Array[Button] = []
var _island := Label.new()
var _island_line := Label.new()
var _chips := HBoxContainer.new()
var _nav: Dictionary = {} ## id -> Button
var _ai_dot := Label.new()
var _left := PanelContainer.new()
var _center := PanelContainer.new()
var _right := PanelContainer.new()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size.y = HEIGHT
	for plaque: PanelContainer in [_left, _center, _right]:
		plaque.theme_type_variation = "Plaque"
		plaque.mouse_filter = Control.MOUSE_FILTER_STOP
		add_child(plaque)
	_build_time()
	_build_island()
	_build_nav()


func _build_time() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiStyle.SPACE_2)
	_left.add_child(row)
	var when := VBoxContainer.new()
	when.add_theme_constant_override("separation", -3)
	when.custom_minimum_size.x = 136 # room for "First Frost · the Oracle speaks", so nothing shifts
	_date.add_theme_font_override("font", UiStyle.font("display"))
	UiStyle.inked(_date, 17)
	when.add_child(_date)
	UiStyle.inked(_when, UiStyle.CAPTION)
	_when.add_theme_color_override("font_color", UiStyle.INK_FAINT)
	_when.clip_text = true
	_when.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	when.add_child(_when)
	row.add_child(when)
	_pause.theme_type_variation = "GhostButton"
	_pause.focus_mode = Control.FOCUS_NONE
	_pause.custom_minimum_size = Vector2(32, 32)
	_pause.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pause.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_pause.pressed.connect(func() -> void: pause_pressed.emit())
	row.add_child(_pause)
	var well := PanelContainer.new()
	well.theme_type_variation = "Segmented"
	well.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var speed_row := HBoxContainer.new()
	speed_row.add_theme_constant_override("separation", 1)
	well.add_child(speed_row)
	var group := ButtonGroup.new()
	for i: int in SPEED_LABELS.size():
		var button := Button.new()
		button.text = SPEED_LABELS[i]
		button.theme_type_variation = "TabButton"
		button.toggle_mode = true
		button.button_group = group
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size.x = 34
		button.add_theme_font_size_override("font_size", UiStyle.SMALL)
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.pressed.connect(func() -> void: speed_picked.emit(i))
		speed_row.add_child(button)
		_speeds.append(button)
	row.add_child(well)


func _build_island() -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", -3)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	_center.add_child(column)
	_island.add_theme_font_override("font", UiStyle.font("display"))
	UiStyle.inked(_island, 17)
	_island.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_island.mouse_filter = Control.MOUSE_FILTER_PASS
	column.add_child(_island)
	UiStyle.inked(_island_line, UiStyle.CAPTION)
	_island_line.add_theme_color_override("font_color", UiStyle.INK_FAINT)
	_island_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_island_line)
	for label: Label in [_island, _island_line]: # long names shorten rather than push the neighbors
		label.clip_text = true
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_center.mouse_filter = Control.MOUSE_FILTER_PASS
	# Chips hang under the island plaque: drought, smog, omens, the destiny once met.
	_chips.add_theme_constant_override("separation", UiStyle.SPACE_1 + 2)
	_chips.alignment = BoxContainer.ALIGNMENT_CENTER
	_chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_chips)


func _build_nav() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	_right.add_child(row)
	for id: String in NAV:
		var info: Array = NAV[id]
		var button := Button.new()
		button.text = String(info[1])
		button.theme_type_variation = "NavButton" if id != "help" else "GhostButton"
		button.toggle_mode = id != "help"
		button.focus_mode = Control.FOCUS_NONE
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.custom_minimum_size.y = 32
		UiStyle.set_icon(button, String(info[0]), 18)
		button.tooltip_text = "%s   [%s]" % [info[2], info[3]]
		button.pressed.connect(func() -> void: nav_pressed.emit(id))
		row.add_child(button)
		_nav[id] = button
	# A dot on the Oracle button: green when an AI speaks, grey when offline.
	_ai_dot.text = "●"
	_ai_dot.add_theme_font_size_override("font_size", 10)
	_ai_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ai_dot.position = Vector2(23, 2)
	(_nav["ai"] as Button).add_child(_ai_dot)


## Lays the three plaques out across the given width (the screen's).
func arrange(view: Vector2, margin: float) -> void:
	position = Vector2(0, margin)
	size = Vector2(view.x, HEIGHT)
	for plaque: PanelContainer in [_left, _center, _right]:
		plaque.reset_size()
	var height := HEIGHT
	_left.position = Vector2(margin, 0)
	_left.size.y = height
	_right.size.y = height
	_right.position = Vector2(view.x - margin - _right.size.x, 0)
	# The island plaque stays centered, but never runs into its neighbors.
	var room_left := _left.position.x + _left.size.x + UiStyle.SPACE_2
	var room_right := _right.position.x - UiStyle.SPACE_2
	var width := minf(_preferred_width(), room_right - room_left)
	_center.size = Vector2(width, height)
	_center.position = Vector2(clampf((view.x - width) / 2.0, room_left, room_right - width), 0)
	_chips.reset_size()
	_chips.position = Vector2((view.x - _chips.size.x) / 2.0, height + UiStyle.SPACE_1 + 2)


## The island plaque's natural width: its longer line, plus the padding.
func _preferred_width() -> float:
	var widest := 0.0
	for label: Label in [_island, _island_line]:
		var font := label.get_theme_font("font")
		var size_px := label.get_theme_font_size("font_size")
		widest = maxf(widest, font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x)
	return widest + 28.0


## The date and what time is doing; waiting says why time stands still ("" when it runs).
func show_time(state: WorldState, paused: bool, speed_index: int, waiting: String) -> void:
	_date.text = "Year %d" % state.year()
	var month: String = WorldState.MONTH_NAMES[state.month()]
	if waiting:
		_when.text = "%s · %s" % [month, waiting]
	elif paused:
		_when.text = "%s · paused" % month
	else:
		_when.text = "%s · day %d" % [month, state.day() + 1]
	UiStyle.set_icon(_pause, "play" if paused else "pause", 18)
	_pause.tooltip_text = ("Let time run" if paused else "Pause time") + "   [Space]"
	for i: int in _speeds.size():
		var button := _speeds[i]
		button.set_pressed_no_signal(i == speed_index)
		button.tooltip_text = "Speed %d: %d days a second   [%d]" % [i + 1, int(speeds[i]) if i < speeds.size() else 0, i + 1]
	_left.modulate.a = 0.55 if waiting else 1.0
	_left.tooltip_text = "Time waits while the Oracle speaks or a card is up." if waiting else ""


## The island plaque: name, age and people; the chips under it.
func show_island(state: WorldState, age_name: String, chips: Array[Control]) -> void:
	_island.text = String(state.world.get("name", "The island"))
	_island.tooltip_text = WorldGen.describe(state.world)
	_island_line.text = "%s  ·  %d people in %d tribe%s  ·  %d generation%s" % [
		age_name, state.total_population(), state.tribe_count(), "" if state.tribe_count() == 1 else "s",
		People.max_generation(state), "" if People.max_generation(state) == 1 else "s",
	]
	UiStyle.clear(_chips)
	for chip: Control in chips:
		_chips.add_child(chip)


## Which panels are open (their nav buttons stay lit), and the Oracle's state.
func show_nav(open: Dictionary, ai_text: String, ai_online: bool) -> void:
	for id: String in open:
		if _nav.has(id):
			(_nav[id] as Button).set_pressed_no_signal(bool(open[id]))
	var ai := _nav["ai"] as Button
	ai.tooltip_text = "AI settings: the Oracle speaks through %s. Providers, budget and usage   [A]" % ai_text
	_ai_dot.add_theme_color_override("font_color", UiStyle.GOOD if ai_online else UiStyle.INK_GHOST)


## The plaques' rectangles on screen (for tests and layout checks).
func plaque_rects() -> Array[Rect2]:
	return [_left.get_global_rect(), _center.get_global_rect(), _right.get_global_rect()]
