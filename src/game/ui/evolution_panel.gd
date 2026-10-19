class_name EvolutionPanel
extends PanelContainer
## The valley's gene pool over the years: one line per tracked gene (the average over everyone
## alive, 0 to 100, the scale zoomed to the range they cover) and the population as a shaded
## area behind them. Click a gene in the legend
## to hide or show its line.

signal closed

const PANEL_SIZE := Vector2(780, 460)
const COLORS := {
	"strength": Color(0.80, 0.33, 0.28), "vitality": Color(0.33, 0.62, 0.36), "longevity": Color(0.45, 0.36, 0.70),
	"fertility": Color(0.88, 0.45, 0.62), "intellect": Color(0.25, 0.48, 0.80), "height": Color(0.62, 0.48, 0.28),
	"temper": Color(0.92, 0.55, 0.18), "sociability": Color(0.20, 0.65, 0.68), "curiosity": Color(0.60, 0.62, 0.20),
}
const POPULATION_COLOR := Color(0.55, 0.45, 0.60, 0.18)

var _hidden: Dictionary = {} ## gene -> true
var _history_size := -1
var _summary := Label.new()
var _drift := Label.new()
var _chart := EvolutionChart.new()
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
	close.tooltip_text = "Close   [E or Esc]"
	close.pressed.connect(func() -> void: closed.emit())
	column.add_child(UiStyle.header(UiStyle.title("Evolution of the valley", UiStyle.DISPLAY - 2), close, "genes"))
	UiStyle.inked(_summary, UiStyle.BODY)
	_summary.add_theme_font_override("font", UiStyle.font("strong"))
	column.add_child(_summary)
	UiStyle.inked(_drift, UiStyle.SMALL + 1)
	_drift.add_theme_color_override("font_color", UiStyle.INK_SOFT)
	_drift.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_drift.custom_minimum_size.x = PANEL_SIZE.x - 48.0
	column.add_child(_drift)
	_chart.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_chart.custom_minimum_size = Vector2(PANEL_SIZE.x - 48.0, 200.0)
	_chart.hidden_genes = _hidden
	column.add_child(_chart)
	_legend.add_theme_constant_override("h_separation", 6)
	_legend.add_theme_constant_override("v_separation", 4)
	for gene: String in Genetics.TRACKED:
		var button := Button.new()
		button.text = "■ %s" % Genetics.INFO[gene]["name"]
		button.theme_type_variation = "ChipButton"
		button.toggle_mode = true
		button.button_pressed = true
		button.focus_mode = Control.FOCUS_NONE
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		for color_name: String in ["font_pressed_color", "font_hover_pressed_color"]:
			button.add_theme_color_override(color_name, (COLORS[gene] as Color).darkened(0.15))
		button.tooltip_text = "Show or hide %s" % String(Genetics.INFO[gene]["name"]).to_lower()
		button.toggled.connect(_on_toggle.bind(gene))
		_legend.add_child(button)
	var population := UiStyle.label("▒ Population", 12)
	population.add_theme_color_override("font_color", Color(0.50, 0.40, 0.58))
	_legend.add_child(population)
	column.add_child(_legend)


## The size it would like; the host fits it to the screen.
func wanted_size() -> Vector2:
	return PANEL_SIZE


## Call every frame while visible; redraws only when a new year has been recorded.
func refresh(state: WorldState) -> void:
	if not visible:
		return
	if state.gene_history.size() == _history_size:
		return
	_history_size = state.gene_history.size()
	_chart.history = state.gene_history
	_chart.queue_redraw()
	var stats := Genetics.pool_stats(state.person_genomes)
	_summary.text = "Year %d  ·  %d people  ·  %d generations  ·  frail %d, carriers %d" % [
		state.year(), state.total_population(), People.max_generation(state), int(stats["frail"]), int(stats["carriers"]),
	]
	_drift.text = _drift_text(state)


## The genes that have moved most since the first record: "Strength +6, Vitality −4 since the first people."
func _drift_text(state: WorldState) -> String:
	if state.gene_history.size() < 2:
		return "Watch the years pass: the gene pool is recorded once a year."
	var first: Dictionary = state.gene_history[0]["genes"]
	var last: Dictionary = state.gene_history[-1]["genes"]
	var changes: Array[Array] = []
	for gene: String in Genetics.TRACKED:
		changes.append([gene, int(last[gene]) - int(first[gene])])
	changes.sort_custom(func(a: Array, b: Array) -> bool: return absi(a[1]) > absi(b[1]))
	var words := PackedStringArray()
	for change: Array in changes.slice(0, 3):
		if int(change[1]) != 0:
			words.append("%s %+d" % [Genetics.INFO[change[0]]["name"], int(change[1])])
	if words.is_empty():
		return "The gene pool hasn't moved since the first people."
	return "Biggest drift since the first people: %s." % ", ".join(words)


func _on_toggle(on: bool, gene: String) -> void:
	if on:
		_hidden.erase(gene)
	else:
		_hidden[gene] = true
	_chart.queue_redraw()


## The drawing surface: axes, the population area and one line per gene.
class EvolutionChart:
	extends Control

	const MARGIN_LEFT := 34.0
	const MARGIN_RIGHT := 44.0
	const MARGIN_TOP := 8.0
	const MARGIN_BOTTOM := 22.0

	var history: Array[Dictionary] = []
	var hidden_genes: Dictionary = {}

	func _draw() -> void:
		var font := get_theme_default_font()
		var ink := ToonMaterials.INK
		var area := Rect2(MARGIN_LEFT, MARGIN_TOP, size.x - MARGIN_LEFT - MARGIN_RIGHT, size.y - MARGIN_TOP - MARGIN_BOTTOM)
		draw_rect(area, Color(1.0, 0.98, 0.93), true)
		# Genes drift slowly, so the scale zooms to the range they actually cover.
		var low := 100
		var high := 0
		for entry: Dictionary in history:
			var genes: Dictionary = entry["genes"]
			for gene: String in Genetics.TRACKED:
				if not hidden_genes.has(gene):
					low = mini(low, int(genes.get(gene, 50)))
					high = maxi(high, int(genes.get(gene, 50)))
		if high < low:
			low = 0
			high = 100
		low = clampi(floori((low - 3) / 5.0) * 5, 0, 100)
		high = clampi(ceili((high + 3) / 5.0) * 5, 0, 100)
		while high - low < 20:
			low = maxi(low - 5, 0)
			high = mini(high + 5, 100)
		var gene_y := func(value: float) -> float: return area.end.y - area.size.y * (value - low) / float(high - low)
		var step_value := 5 if high - low <= 30 else 10
		for level: int in range(low, high + 1, step_value):
			var y: float = gene_y.call(float(level))
			draw_dashed_line(Vector2(area.position.x, y), Vector2(area.end.x, y), ink.lightened(0.75), 1.0, 4.0)
			draw_string(font, Vector2(2.0, y + 4.0), str(level), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, ink.lightened(0.4))
		draw_rect(area, ink.lightened(0.5), false, 1.0)
		if history.size() < 2:
			draw_string(font, area.get_center() - Vector2(120.0, 0.0), "The first years are still being written.", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, ink.lightened(0.3))
			return
		var first_year := int(history[0]["year"])
		var last_year := maxi(int(history[-1]["year"]), first_year + 1)
		var most := 1
		for entry: Dictionary in history:
			most = maxi(most, int(entry["pop"]))
		var x_of := func(year: int) -> float: return area.position.x + area.size.x * float(year - first_year) / float(last_year - first_year)
		# Population behind everything, on its own scale (right axis).
		var shape := PackedVector2Array([Vector2(area.position.x, area.end.y)])
		for entry: Dictionary in history:
			shape.append(Vector2(float(x_of.call(int(entry["year"]))), area.end.y - area.size.y * float(entry["pop"]) / most))
		shape.append(Vector2(area.end.x, area.end.y))
		draw_colored_polygon(shape, POPULATION_COLOR)
		draw_string(font, Vector2(area.end.x + 4.0, area.position.y + 10.0), str(most), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.50, 0.40, 0.58))
		draw_string(font, Vector2(area.end.x + 4.0, area.position.y + 22.0), "people", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.50, 0.40, 0.58))
		# One line per gene.
		for gene: String in Genetics.TRACKED:
			if hidden_genes.has(gene):
				continue
			var points := PackedVector2Array()
			for entry: Dictionary in history:
				var genes: Dictionary = entry["genes"]
				points.append(Vector2(float(x_of.call(int(entry["year"]))), float(gene_y.call(float(genes.get(gene, 50))))))
			draw_polyline(points, COLORS[gene], 2.0, true)
		# Years along the bottom.
		var step := maxi(1, ceili((last_year - first_year) / 8.0))
		for year: int in range(first_year, last_year + 1, step):
			var x: float = x_of.call(year)
			draw_line(Vector2(x, area.end.y), Vector2(x, area.end.y + 4.0), ink.lightened(0.4))
			draw_string(font, Vector2(x - 12.0, size.y - 4.0), "y%d" % year, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, ink.lightened(0.4))
