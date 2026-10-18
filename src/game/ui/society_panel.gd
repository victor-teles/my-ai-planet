class_name SocietyPanel
extends PanelContainer
## How the island's societies changed over the years, from state.society_history (one record a
## year): a line per tribe for the chosen measure, and a thick ink line for the whole island
## (weighted by population; the total, for population). Dashed lines mark the years the island
## entered a new age. Pick the measure with the buttons above the chart.

signal closed

const PANEL_SIZE := Vector2(820, 470)
const NAMED_GOVERNMENTS := 6 ## the largest tribes whose governments the summary names
## measure -> [button label, what the island line is]. "smog" is island-wide only.
const MEASURES := {
	"dystopia": ["Dystopia", "the island, by population"],
	"freedom": ["Freedom", "the island, by population"],
	"control": ["Control", "the island, by population"],
	"inequality": ["Inequality", "the island, by population"],
	"fear": ["Fear", "the island, by population"],
	"population": ["Population", "everyone on the island"],
	"smog": ["Smog", "smoke over the island"],
}
## Tribe line colors, given out in the order tribes first appear in the history.
const PALETTE: Array[Color] = [
	Color(0.80, 0.33, 0.28), Color(0.25, 0.48, 0.80), Color(0.33, 0.62, 0.36), Color(0.62, 0.42, 0.74),
	Color(0.92, 0.55, 0.18), Color(0.20, 0.65, 0.68), Color(0.88, 0.45, 0.62), Color(0.60, 0.62, 0.20),
]

var _measure := "dystopia"
var _drawn_key := ""
var _summary := Label.new()
var _governments := Label.new()
var _buttons: Dictionary = {} ## measure -> Button
var _chart := SocietyChart.new()
var _legend := HFlowContainer.new()


func _init() -> void:
	theme = UiStyle.theme()
	theme_type_variation = "Card"
	add_theme_stylebox_override("panel", UiStyle.card_box(UiStyle.SPACE_5 - 4))
	custom_minimum_size = PANEL_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	add_child(column)
	var close := UiStyle.close_button()
	close.tooltip_text = "Close   [H or Esc]"
	close.pressed.connect(func() -> void: closed.emit())
	column.add_child(UiStyle.header(UiStyle.title("The island's societies", UiStyle.DISPLAY - 2), close, "society"))
	UiStyle.inked(_summary, UiStyle.BODY)
	_summary.add_theme_font_override("font", UiStyle.font("strong"))
	column.add_child(_summary)
	UiStyle.inked(_governments, UiStyle.SMALL + 1)
	_governments.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_governments.custom_minimum_size.x = PANEL_SIZE.x - 48.0
	_governments.add_theme_color_override("font_color", UiStyle.INK_SOFT)
	column.add_child(_governments)
	var labels: Array[String] = []
	var by_label := {}
	for measure: String in MEASURES:
		labels.append(String(MEASURES[measure][0]))
		by_label[String(MEASURES[measure][0])] = measure
	var by_button := {}
	var tabs := UiStyle.tabs(labels, func(label: String) -> void: select_measure(String(by_label[label])), by_button, false)
	tabs.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	for label: String in by_button:
		_buttons[by_label[label]] = by_button[label]
	(_buttons[_measure] as Button).button_pressed = true
	column.add_child(tabs)
	_chart.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_chart.custom_minimum_size = Vector2(PANEL_SIZE.x - 48.0, 200.0)
	column.add_child(_chart)
	_legend.add_theme_constant_override("h_separation", 12)
	_legend.add_theme_constant_override("v_separation", 2)
	column.add_child(_legend)


## Shows one measure: "dystopia", "freedom", "control", "inequality", "fear", "population" or "smog".
## The size it would like; the host fits it to the screen.
func wanted_size() -> Vector2:
	return PANEL_SIZE


func select_measure(measure: String) -> void:
	if not MEASURES.has(measure):
		return
	_measure = measure
	(_buttons[measure] as Button).button_pressed = true
	_drawn_key = ""


## Call every frame while visible; redraws only when a new year has been recorded.
func refresh(state: WorldState) -> void:
	if not visible:
		return
	var history := state.society_history
	var key := "%s|%d|%d" % [_measure, history.size(), int(history[-1]["year"]) if not history.is_empty() else -1]
	if key == _drawn_key:
		return
	_drawn_key = key
	_chart.history = history
	_chart.measure = _measure
	_chart.colors = _tribe_colors(history)
	_chart.queue_redraw()
	_summary.text = _summary_text(state)
	_governments.text = _governments_text(history)
	_rebuild_legend(history)


## The island now: its people-weighted measures and the smoke over it.
func _summary_text(state: WorldState) -> String:
	if state.society_history.is_empty():
		return "Year %d  ·  the first year's record isn't written yet." % state.year()
	var last := state.society_history[-1]
	return "Year %d  ·  the island: dystopia %d, freedom %d, control %d, inequality %d  ·  smog %d" % [
		int(last["year"]), roundi(island_value(last, "dystopia")), roundi(island_value(last, "freedom")),
		roundi(island_value(last, "control")), roundi(island_value(last, "inequality")), int(last.get("pollution", 0)),
	]


## "Now: the Rotelur (120 people), a Theocracy; the Nunaabal (64), a Republic; and 3 smaller tribes."
func _governments_text(history: Array[Dictionary]) -> String:
	if history.is_empty():
		return ""
	var tribes: Dictionary = history[-1]["tribes"]
	if tribes.is_empty():
		return "Nobody is left."
	var names: Array = tribes.keys()
	names.sort_custom(func(a: String, b: String) -> bool: return int(tribes[a].get("population", 0)) > int(tribes[b].get("population", 0)))
	var parts := PackedStringArray()
	for tribe: String in names.slice(0, NAMED_GOVERNMENTS):
		var record: Dictionary = tribes[tribe]
		parts.append("the %s (%d), %s" % [tribe, int(record.get("population", 0)), String(record.get("government", "?"))])
	var rest := names.size() - NAMED_GOVERNMENTS
	if rest > 0:
		parts.append("and %d smaller tribe%s" % [rest, "" if rest == 1 else "s"])
	return "Now: %s." % "; ".join(parts)


func _rebuild_legend(history: Array[Dictionary]) -> void:
	UiStyle.clear(_legend)
	var island := UiStyle.label("━ %s" % MEASURES[_measure][1], 12)
	_legend.add_child(island)
	if _measure == "smog" or history.is_empty():
		return
	var tribes: Dictionary = history[-1]["tribes"]
	for tribe: String in tribes:
		var label := UiStyle.label("■ %s" % tribe, 12)
		label.add_theme_color_override("font_color", _chart.colors.get(tribe, ToonMaterials.INK))
		_legend.add_child(label)
	var age := UiStyle.label("┊ a new age", 12)
	age.add_theme_color_override("font_color", ToonMaterials.INK.lightened(0.4))
	_legend.add_child(age)


func _tribe_colors(history: Array[Dictionary]) -> Dictionary:
	var colors := {}
	for entry: Dictionary in history:
		for tribe: String in entry["tribes"]:
			if not colors.has(tribe):
				colors[tribe] = PALETTE[colors.size() % PALETTE.size()]
	return colors


## One year's measure for the whole island: weighted by population, or the total for population.
static func island_value(entry: Dictionary, measure: String) -> float:
	if measure == "smog":
		return float(entry.get("pollution", 0))
	var tribes: Dictionary = entry["tribes"]
	var total := 0.0
	var people := 0.0
	for tribe: String in tribes:
		var record: Dictionary = tribes[tribe]
		var population := float(record.get("population", 0))
		people += population
		if measure != "population":
			total += float(record.get(measure, 0)) * population
	if measure == "population":
		return people
	return total / people if people > 0.0 else 0.0


## The most advanced age any tribe had reached that year.
static func island_age(entry: Dictionary) -> int:
	var best := 0
	var tribes: Dictionary = entry["tribes"]
	for tribe: String in tribes:
		best = maxi(best, int((tribes[tribe] as Dictionary).get("age", 0)))
	return best


## The drawing surface: axes, age marks, a line per tribe and the island's line on top.
class SocietyChart:
	extends Control

	const MARGIN_LEFT := 34.0
	const MARGIN_RIGHT := 16.0
	const MARGIN_TOP := 20.0
	const MARGIN_BOTTOM := 22.0

	var history: Array[Dictionary] = []
	var measure := "dystopia"
	var colors: Dictionary = {} ## tribe -> Color

	func _draw() -> void:
		var font := get_theme_default_font()
		var ink := ToonMaterials.INK
		var area := Rect2(MARGIN_LEFT, MARGIN_TOP, size.x - MARGIN_LEFT - MARGIN_RIGHT, size.y - MARGIN_TOP - MARGIN_BOTTOM)
		draw_rect(area, Color(1.0, 0.98, 0.93), true)
		var top := 100.0
		if measure == "population":
			top = 10.0
			for entry: Dictionary in history:
				top = maxf(top, SocietyPanel.island_value(entry, "population"))
			top = ceilf(top / 50.0) * 50.0
		var y_of := func(value: float) -> float: return area.end.y - area.size.y * clampf(value / top, 0.0, 1.0)
		for k: int in 5:
			var level := top * k / 4.0
			var y: float = y_of.call(level)
			draw_dashed_line(Vector2(area.position.x, y), Vector2(area.end.x, y), ink.lightened(0.75), 1.0, 4.0)
			draw_string(font, Vector2(2.0, y + 4.0), str(roundi(level)), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, ink.lightened(0.4))
		draw_rect(area, ink.lightened(0.5), false, 1.0)
		if history.size() < 2:
			draw_string(font, area.get_center() - Vector2(130.0, 0.0), "The first years are still being written.", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, ink.lightened(0.3))
			return
		var first_year := int(history[0]["year"])
		var last_year := maxi(int(history[-1]["year"]), first_year + 1)
		var x_of := func(year: int) -> float: return area.position.x + area.size.x * float(year - first_year) / float(last_year - first_year)
		# The years the island entered a new age.
		var age := SocietyPanel.island_age(history[0])
		for entry: Dictionary in history:
			var now := SocietyPanel.island_age(entry)
			if now > age:
				var x: float = x_of.call(int(entry["year"]))
				draw_dashed_line(Vector2(x, area.position.y), Vector2(x, area.end.y), ink.lightened(0.35), 1.5, 5.0)
				draw_string(font, Vector2(x + 3.0, area.position.y - 5.0), Knowledge.age_name(now), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, ink.lightened(0.2))
			age = maxi(age, now)
		# A line per tribe, broken where the tribe didn't exist.
		if measure != "smog":
			for tribe: String in colors:
				var points := PackedVector2Array()
				for entry: Dictionary in history:
					var tribes: Dictionary = entry["tribes"]
					if tribes.has(tribe):
						var record: Dictionary = tribes[tribe]
						points.append(Vector2(float(x_of.call(int(entry["year"]))), float(y_of.call(float(record.get(measure, 0))))))
					elif not points.is_empty():
						_line(points, colors[tribe], 1.6)
						points = PackedVector2Array()
				_line(points, colors[tribe], 1.6)
		# The island on top, in ink.
		var island := PackedVector2Array()
		for entry: Dictionary in history:
			island.append(Vector2(float(x_of.call(int(entry["year"]))), float(y_of.call(SocietyPanel.island_value(entry, measure)))))
		draw_polyline(island, ink, 3.0, true)
		# Years along the bottom.
		var step := maxi(1, ceili((last_year - first_year) / 8.0))
		for year: int in range(first_year, last_year + 1, step):
			var x: float = x_of.call(year)
			draw_line(Vector2(x, area.end.y), Vector2(x, area.end.y + 4.0), ink.lightened(0.4))
			draw_string(font, Vector2(x - 12.0, size.y - 4.0), "y%d" % year, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, ink.lightened(0.4))

	func _line(points: PackedVector2Array, color: Color, width: float) -> void:
		if points.size() >= 2:
			draw_polyline(points, color, width, true)
		elif points.size() == 1:
			draw_circle(points[0], width, color)
