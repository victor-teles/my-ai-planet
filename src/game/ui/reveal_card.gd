class_name RevealCard
extends PanelContainer
## The chronicle when a prophecy resolves (or the island meets its destiny): a ribbon with the
## outcome, the Oracle's words, the Chronicler's title and story, why it went that way, and
## Continue. While the story streams in, the text follows the newest words and Continue waits.
## The host places it (fit_to) in the room between the top bar and the bottom of the screen.

signal continue_pressed

const WIDTH := 600.0

var _ribbon := Label.new()
var _quote: Label
var _title: Label
var _scroll := ScrollContainer.new()
var _story := VBoxContainer.new()
var _text := Label.new()
var _why: Label
var _causes := VBoxContainer.new()
var _continue: Button
var _streaming := false


func _init() -> void:
	theme_type_variation = "Card"
	add_theme_stylebox_override("panel", UiStyle.card_box(UiStyle.SPACE_5))
	custom_minimum_size.x = WIDTH
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", UiStyle.SPACE_3)
	add_child(column)

	_ribbon.add_theme_font_override("font", UiStyle.font("caps"))
	_ribbon.add_theme_font_size_override("font_size", UiStyle.SMALL)
	_ribbon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(_ribbon)
	_quote = UiStyle.quote("", UiStyle.BODY + 1)
	_quote.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_quote.custom_minimum_size.x = WIDTH - 60.0
	column.add_child(_quote)
	_title = UiStyle.title("", UiStyle.DISPLAY + 2)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.custom_minimum_size.x = WIDTH - 60.0
	column.add_child(_title)

	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_story.add_theme_constant_override("separation", UiStyle.SPACE_3)
	_story.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiStyle.inked(_text, UiStyle.LEAD)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_text.add_theme_constant_override("line_spacing", 3)
	_story.add_child(_text)
	_why = UiStyle.section("WHY IT WENT THIS WAY")
	_story.add_child(_why)
	_causes.add_theme_constant_override("separation", UiStyle.SPACE_1 + 2)
	_story.add_child(_causes)
	_scroll.add_child(_story)
	column.add_child(_scroll)

	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	footer.add_theme_constant_override("separation", UiStyle.SPACE_2)
	_continue = UiStyle.primary_button("Continue")
	_continue.pressed.connect(func() -> void: continue_pressed.emit())
	footer.add_child(_continue)
	footer.add_child(UiStyle.keycap("Enter"))
	column.add_child(footer)


## The finished chronicle. outcome: [ribbon text, whether it is a happy or a dark ending].
func show_chronicle(ribbon: String, dark: bool, quote_text: String, title_text: String, story: String, causes: Array) -> void:
	_streaming = false
	_set_ribbon(ribbon, dark)
	_quote.text = quote_text
	_quote.visible = not quote_text.is_empty()
	_title.text = title_text
	_text.text = story
	UiStyle.clear(_causes)
	for cause: Variant in causes:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", UiStyle.SPACE_2)
		var dot := UiStyle.label("✦", UiStyle.SMALL)
		dot.add_theme_color_override("font_color", UiStyle.GOLD)
		dot.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		row.add_child(dot)
		row.add_child(UiStyle.label(String(cause), UiStyle.BODY + 1, true))
		_causes.add_child(row)
	_why.visible = not causes.is_empty()
	_causes.visible = not causes.is_empty()
	_continue.disabled = false
	_continue.text = "Continue"
	_scroll.scroll_vertical = 0


## The story as it streams in: Continue waits, the text follows the newest words.
func show_streaming(ribbon: String, dark: bool, quote_text: String, story_so_far: String) -> void:
	if not _streaming:
		_streaming = true
		_set_ribbon(ribbon, dark)
		_quote.text = quote_text
		_quote.visible = not quote_text.is_empty()
		_title.text = "The Chronicler writes..."
		_why.visible = false
		_causes.visible = false
		_continue.disabled = true
		_continue.text = "The Chronicler is still writing..."
	_text.text = story_so_far
	_scroll.set_deferred("scroll_vertical", int(_story.size.y))


func is_streaming() -> bool:
	return _streaming


## Sizes the card to its story, no taller than the room, centered in it.
func fit_to(room: Rect2) -> void:
	var chrome := get_combined_minimum_size().y
	var needed := chrome + _story.get_combined_minimum_size().y
	size = Vector2(WIDTH, minf(needed, room.size.y))
	position = (room.position + (room.size - size) / 2.0).floor()
	pivot_offset = size / 2.0


func _set_ribbon(text: String, dark: bool) -> void:
	_ribbon.text = text
	var box := UiStyle.chip_box(Color(0.94, 0.84, 0.90) if dark else Color(0.86, 0.93, 0.80))
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 3
	box.content_margin_bottom = 4
	_ribbon.add_theme_stylebox_override("normal", box)
	_ribbon.add_theme_color_override("font_color", UiStyle.DARK if dark else UiStyle.GOOD)
