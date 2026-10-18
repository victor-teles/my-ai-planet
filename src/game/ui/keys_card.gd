class_name KeysCard
extends PanelContainer
## Every control on one card: what the mouse does, and the keys that do it faster.

signal closed

const KEYS: Array[Array] = [
	["Space", "Pause or let time run"],
	["1 – 5", "Time's speed (or a choice, while a card is up)"],
	["Tab", "Life in the valley (the feed)"],
	["E", "Evolution of the genes"],
	["H", "The island's societies"],
	["A", "AI settings (time stops while open)"],
	["F", "Follow the person you inspect"],
	["Enter", "Continue after a chronicle"],
	["Esc", "Close the top panel"],
	["S / L", "Save / load (debug)"],
	["F1", "Debug numbers"],
]
const MOUSE: Array[Array] = [
	["Click a person", "See their life, family, DNA, bonds and story"],
	["Click a camp", "See the tribe, and choose it as the miracles' target"],
	["Drag", "Turn the island"],
	["Wheel", "Zoom in and out"],
]


func _init() -> void:
	theme_type_variation = "Card"
	add_theme_stylebox_override("panel", UiStyle.card_box(UiStyle.SPACE_5))
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", UiStyle.SPACE_3)
	add_child(column)
	var close := UiStyle.close_button()
	close.pressed.connect(func() -> void: closed.emit())
	column.add_child(UiStyle.header(UiStyle.title("Controls"), close, "keyboard"))
	var sides := HBoxContainer.new()
	sides.add_theme_constant_override("separation", UiStyle.SPACE_5)
	column.add_child(sides)
	sides.add_child(_list("WITH THE MOUSE", MOUSE, 110.0))
	sides.add_child(_list("KEYS", KEYS, 56.0))


func _list(heading: String, rows: Array[Array], key_width: float) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", UiStyle.SPACE_2)
	box.add_child(UiStyle.section(heading))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", UiStyle.SPACE_3)
	grid.add_theme_constant_override("v_separation", 6)
	for row: Array in rows:
		var key := UiStyle.keycap(String(row[0])) if key_width < 100.0 else UiStyle.strong(UiStyle.label(String(row[0]), UiStyle.SMALL + 1))
		var cell := HBoxContainer.new()
		cell.custom_minimum_size.x = key_width
		cell.add_child(key)
		grid.add_child(cell)
		var what := UiStyle.label(String(row[1]), UiStyle.SMALL + 1)
		what.add_theme_color_override("font_color", UiStyle.INK_SOFT)
		grid.add_child(what)
	box.add_child(grid)
	return box
