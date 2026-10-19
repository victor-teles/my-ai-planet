class_name LifeFeed
extends PanelContainer
## The life of the valley as it happens, newest first: births, deaths, loves, work, buildings,
## discoveries, the tribes' politics and the god's own deeds. Filter by kind, or show only the
## big turns of history. Clicking a line about someone inspects them. Bursts of small events
## merge into one line, and when too much happens at once the small ones are dropped (EventPacer).

signal person_clicked(id: int)
signal closed

const MAX_ROWS := 120
const LINES_PER_SECOND := 3.0 ## small lines added at most this often, after a burst of MAX_BURST
const MAX_BURST := 10.0
const COMPACT_HEIGHT := 250.0 ## folded to this (or less) until unfolded to the column's height
const CHIP_COLUMNS := 3

var _hidden: Dictionary = {} ## category -> true when filtered out
var _only_major := false
var _expanded := false
var _dirty := true ## filters changed: rebuild everything
var _last_id := -1
var _pacer := EventPacer.new(LINES_PER_SECOND, MAX_BURST)
var _rows := VBoxContainer.new()
var _scroll := ScrollContainer.new()
var _filters := PanelContainer.new()
var _filter_button: Button
var _filter_count := Label.new()
var _chips: Dictionary = {} ## category -> Button
var _all_chip: Button
var _major_toggle: CheckButton
var _size_button: Button
var _empty := Label.new()
var _state: WorldState
var _local := Callable() ## LocalNames.lookup() for the world shown


func _init() -> void:
	theme = UiStyle.theme()
	theme_type_variation = "Card"
	add_theme_stylebox_override("panel", UiStyle.card_box(UiStyle.SPACE_3))
	mouse_filter = Control.MOUSE_FILTER_STOP
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", UiStyle.SPACE_2)
	add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 2)
	header.add_child(UiStyle.icon("feed", 18))
	var title := UiStyle.title("Life in the valley", 17)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_filter_button = UiStyle.ghost_button("filter", "Filter the feed by kind", "", 15)
	_filter_button.toggle_mode = true
	_filter_button.toggled.connect(set_filters_open)
	header.add_child(_filter_button)
	UiStyle.inked(_filter_count, UiStyle.CAPTION)
	_filter_count.add_theme_font_override("font", UiStyle.font("strong"))
	_filter_count.add_theme_color_override("font_color", UiStyle.ORACLE)
	_filter_count.visible = false
	header.add_child(_filter_count)
	_size_button = UiStyle.ghost_button("expand", "Unfold the feed to the column's height", "", 15)
	_size_button.pressed.connect(func() -> void: set_expanded(not _expanded))
	header.add_child(_size_button)
	var close := UiStyle.close_button()
	close.custom_minimum_size = Vector2(26, 26)
	close.tooltip_text = "Hide the feed   [Tab]"
	close.pressed.connect(func() -> void: closed.emit())
	header.add_child(close)
	column.add_child(header)

	# The filters fold away under the header: a grid of chips and the big-turns switch.
	_filters.theme_type_variation = "Well"
	_filters.visible = false
	var filters := VBoxContainer.new()
	filters.add_theme_constant_override("separation", 6)
	_filters.add_child(filters)
	var grid := GridContainer.new()
	grid.columns = CHIP_COLUMNS
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	for category: String in EventText.CATEGORY_ORDER:
		var info: Array = EventText.CATEGORIES[category]
		var chip := _chip("%s %s" % [info[0], category.capitalize()])
		chip.toggle_mode = true
		chip.button_pressed = true
		chip.tooltip_text = "Show or hide %s events" % category
		var ink: Color = (info[1] as Color).darkened(0.15)
		chip.add_theme_color_override("font_pressed_color", ink)
		chip.add_theme_color_override("font_hover_pressed_color", ink)
		chip.toggled.connect(_on_chip.bind(category))
		grid.add_child(chip)
		_chips[category] = chip
	_all_chip = _chip("Show all")
	_all_chip.tooltip_text = "Show every kind of event"
	_all_chip.pressed.connect(_show_all)
	grid.add_child(_all_chip)
	filters.add_child(grid)
	_major_toggle = CheckButton.new()
	_major_toggle.text = "Only the big turns of history"
	_major_toggle.focus_mode = Control.FOCUS_NONE
	_major_toggle.add_theme_font_size_override("font_size", UiStyle.SMALL + 1)
	_major_toggle.toggled.connect(_on_major)
	filters.add_child(_major_toggle)
	column.add_child(_filters)

	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 1)
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_rows)
	column.add_child(_scroll)
	_empty.text = "Nothing has happened yet."
	UiStyle.inked(_empty, UiStyle.SMALL + 1)
	_empty.add_theme_color_override("font_color", UiStyle.INK_FAINT)


## The height the feed wants in a column with this much room: folded, or all of it.
func wanted_height(room: float) -> float:
	return room if _expanded else minf(COMPACT_HEIGHT + (_filters.get_combined_minimum_size().y + UiStyle.SPACE_2 if _filters.visible else 0.0), room)


func set_expanded(on: bool) -> void:
	_expanded = on
	UiStyle.set_icon(_size_button, "compact" if on else "expand", 15)
	_size_button.tooltip_text = "Fold the feed back" if on else "Unfold the feed to the column's height"


func set_filters_open(on: bool) -> void:
	_filters.visible = on
	_filter_button.set_pressed_no_signal(on)


## Call every frame. Adds lines for new events; rebuilds only when the filters change.
func refresh(state: WorldState) -> void:
	if state != _state:
		_state = state
		_local = LocalNames.lookup(state) # laws and buildings in the tribes' own words
	if not visible:
		_dirty = true # rebuilt from the log when it shows again
		return
	if _dirty or state.next_event_id - 1 < _last_id:
		_rebuild(state)
		return
	var first := state.events.size()
	while first > 0 and int(state.events[first - 1]["id"]) > _last_id:
		first -= 1
	for j: int in range(first, state.events.size()):
		if _passes(state.events[j]):
			_pacer.push(state.events[j])
	_last_id = state.next_event_id - 1
	var shown := _pacer.take(get_process_delta_time())
	if shown.is_empty():
		return
	# shown is oldest first; each goes on top so the newest ends up on top.
	for item: Dictionary in shown:
		var row := _row(item)
		_rows.add_child(row)
		_rows.move_child(row, 0)
	_trim()
	_stay_on_newest()


## Keeps the newest line in view, unless the player is reading the feed with the mouse over it.
func _stay_on_newest() -> void:
	if not get_global_rect().has_point(get_global_mouse_position()):
		_scroll.set_deferred("scroll_vertical", 0)


func _rebuild(state: WorldState) -> void:
	_dirty = false
	_pacer.clear()
	if _empty.get_parent():
		_empty.get_parent().remove_child(_empty)
	UiStyle.clear(_rows)
	var count := 0
	for j: int in range(state.events.size() - 1, -1, -1):
		var event := state.events[j]
		if not _passes(event):
			continue
		_rows.add_child(_row({"event": event, "count": 1, "major": EventText.is_major(event)}))
		count += 1
		if count >= MAX_ROWS:
			break
	_last_id = state.next_event_id - 1
	if count == 0:
		_rows.add_child(_empty)
	_scroll.set_deferred("scroll_vertical", 0)


func _trim() -> void:
	if _empty.get_parent() == _rows and _rows.get_child_count() > 1:
		_rows.remove_child(_empty)
	while _rows.get_child_count() > MAX_ROWS:
		var last := _rows.get_child(_rows.get_child_count() - 1)
		_rows.remove_child(last)
		last.queue_free()


func _passes(event: Dictionary) -> bool:
	if _only_major and not EventText.is_major(event):
		return false
	return not _hidden.has(EventText.category(event))


## One line: the kind's icon, what happened, and when and where. Takes an EventPacer item;
## a merged burst reads as one line dated by its newest event.
func _row(item: Dictionary) -> Control:
	var event: Dictionary = item["event"]
	var merged := int(item["count"]) > 1
	var row := PanelContainer.new()
	var normal := StyleBoxEmpty.new()
	normal.set_content_margin_all(4)
	row.add_theme_stylebox_override("panel", normal)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 7)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(line)
	var icon := Label.new()
	icon.text = EventText.icon(event)
	icon.custom_minimum_size.x = 18
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	icon.add_theme_font_size_override("font_size", 15)
	icon.add_theme_color_override("font_color", EventText.color(event))
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(icon)
	var words := VBoxContainer.new()
	words.add_theme_constant_override("separation", 0)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(words)
	var text := UiStyle.label(EventPacer.burst_text(item) if merged else EventText.text(event, _local), UiStyle.SMALL + 1, true)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if bool(item["major"]):
		UiStyle.strong(text)
		text.add_theme_font_size_override("font_size", UiStyle.BODY)
	words.add_child(text)
	var meta := WorldState.date_text(int(event["tick"]))
	var tribe := EventText.tribe_of(event)
	if tribe:
		meta += "  ·  the %s" % tribe
	var when := UiStyle.faint(meta, UiStyle.CAPTION)
	when.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.add_child(when)
	var subject := -1 if merged else EventText.subject(event)
	if subject != -1:
		row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		row.tooltip_text = "Click to see who this is"
		var hover := StyleBoxFlat.new()
		hover.bg_color = UiStyle.PAPER_SUNK
		hover.set_corner_radius_all(UiStyle.RADIUS_S)
		hover.set_content_margin_all(4)
		row.mouse_entered.connect(func() -> void: row.add_theme_stylebox_override("panel", hover))
		row.mouse_exited.connect(func() -> void: row.add_theme_stylebox_override("panel", normal))
		row.gui_input.connect(func(input: InputEvent) -> void:
			var click := input as InputEventMouseButton
			if click and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
				person_clicked.emit(subject)
				accept_event())
	else:
		row.mouse_filter = Control.MOUSE_FILTER_PASS
	return row


func _on_chip(on: bool, category: String) -> void:
	if on:
		_hidden.erase(category)
	else:
		_hidden[category] = true
	_dirty = true
	_update_filter_count()


func _show_all() -> void:
	_hidden.clear()
	for category: String in _chips:
		(_chips[category] as Button).set_pressed_no_signal(true)
	_dirty = true
	_update_filter_count()


func _on_major(on: bool) -> void:
	_only_major = on
	_dirty = true
	_update_filter_count()


## A filter chip: a small toggle pill.
func _chip(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.theme_type_variation = "ChipButton"
	button.focus_mode = Control.FOCUS_NONE
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return button


func _update_filter_count() -> void:
	var hidden := _hidden.size() + (1 if _only_major else 0)
	_filter_count.text = "%d" % hidden
	_filter_count.visible = hidden > 0
	_filter_count.tooltip_text = "%d filter%s on" % [hidden, "" if hidden == 1 else "s"]
