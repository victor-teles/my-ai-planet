class_name DilemmaCard
extends PanelContainer
## A dilemma: the Oracle's card, its situation, and a row per choice (its number key, what it is
## and a hint of what may follow). The whole row is the button. Time waits while it is up.

signal chosen(index: int)

const WIDTH := 600.0

var _title: Label
var _scroll := ScrollContainer.new()
var _situation := Label.new()
var _choices := VBoxContainer.new()
var _shown: Dilemma


func _init() -> void:
	theme_type_variation = "Card"
	add_theme_stylebox_override("panel", UiStyle.card_box(UiStyle.SPACE_5))
	custom_minimum_size.x = WIDTH
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", UiStyle.SPACE_3)
	add_child(column)

	var kicker := HBoxContainer.new()
	kicker.add_theme_constant_override("separation", 6)
	kicker.alignment = BoxContainer.ALIGNMENT_CENTER
	kicker.add_child(UiStyle.icon("oracle", 18))
	var words := UiStyle.section("A CHOICE FOR THE GOD")
	words.add_theme_color_override("font_color", UiStyle.ORACLE)
	kicker.add_child(words)
	var waits := UiStyle.faint("·   time waits for your answer", UiStyle.CAPTION)
	kicker.add_child(waits)
	column.add_child(kicker)
	_title = UiStyle.title("", UiStyle.DISPLAY)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.custom_minimum_size.x = WIDTH - 60.0
	column.add_child(_title)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	UiStyle.inked(_situation, UiStyle.LEAD)
	_situation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_situation.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_situation.add_theme_constant_override("line_spacing", 3)
	_scroll.add_child(_situation)
	column.add_child(_scroll)
	_choices.add_theme_constant_override("separation", UiStyle.SPACE_2)
	column.add_child(_choices)


## Shows a dilemma (null clears it). Rebuilds the choices only when the card changes.
func show_dilemma(dilemma: Dilemma) -> void:
	if dilemma == _shown:
		return
	_shown = dilemma
	UiStyle.clear(_choices)
	if dilemma == null:
		return
	_title.text = dilemma.title
	_situation.text = dilemma.situation
	_scroll.scroll_vertical = 0
	for i: int in dilemma.choices.size():
		var choice: Dictionary = dilemma.choices[i]
		_choices.add_child(_choice_row(i, String(choice["label"]), String(choice["hint"])))


func shown() -> Dilemma:
	return _shown


## Sizes the card to its text, no taller than the room, centered in it.
func fit_to(room: Rect2) -> void:
	var chrome := get_combined_minimum_size().y
	var needed := chrome + _situation.get_combined_minimum_size().y
	size = Vector2(WIDTH, minf(needed, room.size.y))
	position = (room.position + (room.size - size) / 2.0).floor()
	pivot_offset = size / 2.0


func _choice_row(index: int, label_text: String, hint: String) -> Control:
	var row := PanelContainer.new()
	var normal := _row_box(UiStyle.PAPER_DEEP, Color(UiStyle.INK, 0.8))
	var hover := _row_box(UiStyle.GOLD_SOFT, UiStyle.INK)
	row.add_theme_stylebox_override("panel", normal)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	row.tooltip_text = "Choose this   [%d]" % (index + 1)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", UiStyle.SPACE_3)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(line)
	var number := Label.new()
	number.text = str(index + 1)
	number.add_theme_font_override("font", UiStyle.font("display"))
	number.add_theme_font_size_override("font_size", UiStyle.TITLE)
	number.add_theme_color_override("font_color", UiStyle.PAPER)
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	number.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	number.custom_minimum_size = Vector2(30, 30)
	var disc := StyleBoxFlat.new()
	disc.bg_color = Color(0.24, 0.16, 0.30)
	disc.set_corner_radius_all(15)
	number.add_theme_stylebox_override("normal", disc)
	number.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	number.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(number)
	var words := VBoxContainer.new()
	words.add_theme_constant_override("separation", 1)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var what := UiStyle.strong(UiStyle.label(label_text, UiStyle.LEAD, true))
	what.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.add_child(what)
	if hint:
		var maybe := UiStyle.quote(hint, UiStyle.BODY)
		maybe.mouse_filter = Control.MOUSE_FILTER_IGNORE
		words.add_child(maybe)
	line.add_child(words)
	row.mouse_entered.connect(func() -> void: row.add_theme_stylebox_override("panel", hover))
	row.mouse_exited.connect(func() -> void: row.add_theme_stylebox_override("panel", normal))
	row.gui_input.connect(func(input: InputEvent) -> void:
		var click := input as InputEventMouseButton
		if click and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			chosen.emit(index))
	return row


func _row_box(fill: Color, border: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(UiStyle.BORDER)
	box.set_corner_radius_all(UiStyle.RADIUS_M)
	box.content_margin_left = UiStyle.SPACE_3
	box.content_margin_right = UiStyle.SPACE_4
	box.content_margin_top = UiStyle.SPACE_2
	box.content_margin_bottom = UiStyle.SPACE_2 + 1
	box.anti_aliasing_size = 0.8
	return box
