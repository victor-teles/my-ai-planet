class_name ProphecyCard
extends PanelContainer
## The goal of the era, at the top of the left column: the Oracle's words, what has to happen in
## plain words, a meter of where the world stands against the target (Prophecy.measure), and the
## years left. Folds into a one-line pill. While the Oracle or the Chronicler is busy, it says so.

signal height_changed

const WIDTH := 300.0
const QUOTE_LINES := 5
## metric -> [what it counts, for the meter's caption]
const NOUNS := {
	"total_population": "people", "tribe_count": "tribes", "largest_tribe_population": "in the largest tribe",
	"building_count": "buildings", "discoveries": "discoveries", "highest_age": "", "max_dystopia": "dystopia",
	"max_inequality": "inequality", "vassal_count": "vassal tribes",
}

var collapsed := false

var _kicker := Label.new()
var _fold: Button
var _body := VBoxContainer.new()
var _quote: Label
var _goal := Label.new()
var _meter := ProphecyMeter.new()
var _meter_box := VBoxContainer.new()
var _footer := HBoxContainer.new()
var _now := Label.new()
var _target := Label.new()
var _time := Label.new()
var _time_icon: TextureRect
var _hint: Label
var _pill := Label.new()
var _pill_time := Label.new()
var _shown_text := ""
var _tween: Tween


func _init() -> void:
	theme_type_variation = "Card"
	add_theme_stylebox_override("panel", _box())
	custom_minimum_size.x = WIDTH
	mouse_filter = Control.MOUSE_FILTER_STOP
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", UiStyle.SPACE_2)
	add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	header.add_child(UiStyle.icon("oracle", 18))
	_kicker.text = "THE ORACLE FORETOLD"
	UiStyle.inked(_kicker, UiStyle.CAPTION)
	_kicker.add_theme_font_override("font", UiStyle.font("caps"))
	_kicker.add_theme_color_override("font_color", UiStyle.ORACLE)
	_kicker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_kicker)
	_pill.visible = false
	UiStyle.inked(_pill, UiStyle.SMALL + 1)
	_pill.add_theme_font_override("font", UiStyle.font("strong"))
	_pill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pill.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_pill.clip_text = true
	header.add_child(_pill)
	UiStyle.inked(_pill_time, UiStyle.SMALL)
	_pill_time.add_theme_color_override("font_color", UiStyle.INK_FAINT)
	_pill_time.visible = false
	header.add_child(_pill_time)
	_fold = UiStyle.ghost_button("chevron_up", "Fold the prophecy", "", 14)
	_fold.custom_minimum_size = Vector2(24, 22)
	_fold.pressed.connect(toggle)
	header.add_child(_fold)
	column.add_child(header)

	_body.add_theme_constant_override("separation", UiStyle.SPACE_2)
	column.add_child(_body)
	_quote = UiStyle.quote("", UiStyle.BODY)
	_quote.max_lines_visible = QUOTE_LINES
	_quote.mouse_filter = Control.MOUSE_FILTER_PASS
	_body.add_child(_quote)
	UiStyle.inked(_goal, UiStyle.BODY)
	_goal.add_theme_font_override("font", UiStyle.font("strong"))
	_goal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(_goal)

	var meter_box := _meter_box
	meter_box.add_theme_constant_override("separation", 2)
	_meter.custom_minimum_size = Vector2(0, 14)
	_meter.mouse_filter = Control.MOUSE_FILTER_PASS
	meter_box.add_child(_meter)
	var numbers := HBoxContainer.new()
	UiStyle.inked(_now, UiStyle.SMALL)
	_now.add_theme_font_override("font", UiStyle.font("strong"))
	_now.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	numbers.add_child(_now)
	UiStyle.inked(_target, UiStyle.SMALL)
	_target.add_theme_color_override("font_color", UiStyle.INK_FAINT)
	numbers.add_child(_target)
	meter_box.add_child(numbers)
	_body.add_child(meter_box)

	var footer := _footer
	footer.add_theme_constant_override("separation", 5)
	_time_icon = UiStyle.icon("hourglass", 15)
	footer.add_child(_time_icon)
	UiStyle.inked(_time, UiStyle.SMALL)
	_time.add_theme_font_override("font", UiStyle.font("strong"))
	footer.add_child(_time)
	_hint = UiStyle.faint("Make it happen, or break it", UiStyle.CAPTION)
	_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint.mouse_filter = Control.MOUSE_FILTER_PASS
	_hint.tooltip_text = "The Oracle has spoken. Help the world toward it, or bend it away: a prophecy that comes true\nand one that is broken both give you Influence, and the Chronicler tells why it went as it did."
	footer.add_child(_hint)
	_body.add_child(footer)


func toggle() -> void:
	collapsed = not collapsed
	_body.visible = not collapsed
	_pill.visible = collapsed
	_pill_time.visible = collapsed
	_kicker.visible = not collapsed
	UiStyle.set_icon(_fold, "chevron_down" if collapsed else "chevron_up", 14)
	_fold.tooltip_text = "Show the prophecy" if collapsed else "Fold the prophecy"
	reset_size()
	height_changed.emit()


## Shows the prophecy now running (or what the Oracle is doing). Cheap; call a few times a second.
func show_prophecy(state: WorldState, prophecy: Prophecy, phase: Session.Phase) -> void:
	var busy := ""
	match phase:
		Session.Phase.FORETELLING:
			busy = "The Oracle is gazing into the future..."
		Session.Phase.CHRONICLING:
			busy = "The Chronicler is writing down what happened..."
		Session.Phase.REVEAL:
			busy = "The chronicle is told. A new prophecy comes next."
	if busy or prophecy == null:
		_show_waiting(busy if busy else "The Oracle is silent.")
		return
	_kicker.text = "THE ORACLE FORETOLD"
	_quote.visible = true
	_goal.visible = true
	_meter_box.visible = true
	_footer.visible = true
	if prophecy.text != _shown_text:
		_shown_text = prophecy.text
		_quote.text = "“%s”" % prophecy.text
		_quote.tooltip_text = prophecy.text
		_meter.value = -1.0 # start the meter from empty for a new prophecy
	var now := Prophecy.measure(prophecy.metric, state)
	_goal.text = goal_text(prophecy)
	_now.text = "Now: %s" % amount_text(prophecy.metric, now)
	_target.text = "Goal: %s %s" % ["≥" if prophecy.op == ">=" else "≤", amount_text(prophecy.metric, prophecy.target)]
	var years := prophecy.deadline_year - state.year()
	_time.text = "%d year%s left" % [years, "" if years == 1 else "s"] if years > 0 else "This is the last year"
	_time.add_theme_color_override("font_color", UiStyle.BAD if years <= 3 else UiStyle.INK)
	_time.tooltip_text = "It must happen before year %d." % prophecy.deadline_year
	_meter.tooltip_text = "%s\n%s now; the prophecy wants %s %s." % [
		goal_text(prophecy), amount_text(prophecy.metric, now), "at least" if prophecy.op == ">=" else "at most",
		amount_text(prophecy.metric, prophecy.target)]
	_set_meter(now, prophecy)
	_pill.text = goal_what(prophecy)
	_pill_time.text = "%d y left" % years if years > 0 else "last year"
	_pill.tooltip_text = prophecy.text


func _show_waiting(text: String) -> void:
	_kicker.text = "THE ORACLE"
	_shown_text = ""
	_quote.visible = true
	_quote.text = text
	_quote.tooltip_text = ""
	_goal.visible = false
	_meter_box.visible = false
	_footer.visible = false
	_pill.text = text
	_pill.tooltip_text = ""
	_pill_time.text = ""


## Animates the meter toward where the world stands.
func _set_meter(now: int, prophecy: Prophecy) -> void:
	var scale_top := float(maxi(maxi(prophecy.target, now), 1)) * 1.25
	if prophecy.metric == "highest_age":
		scale_top = float(maxi(prophecy.target, now) + 1)
	elif prophecy.metric in ["max_dystopia", "max_inequality"]:
		scale_top = 100.0
	var goal := prophecy.target / scale_top
	var value := now / scale_top
	_meter.goal = goal
	_meter.wants_more = prophecy.op == ">="
	if _meter.value < 0.0:
		_meter.value = 0.0 if prophecy.op == ">=" else 1.0
	if absf(_meter.shown - value) < 0.0005 and _meter.value == value:
		return
	_meter.value = value
	if _tween:
		_tween.kill()
	_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_tween.tween_method(_meter.set_shown, _meter.shown, value, UiStyle.MOTION_SLOW)


## The prophecy as a goal in plain words: "Reach the Age of Bronze before year 50".
static func goal_text(prophecy: Prophecy) -> String:
	return "%s before year %d" % [goal_what(prophecy), prophecy.deadline_year]


## What has to happen, without the deadline: "Reach the Age of Bronze".
static func goal_what(prophecy: Prophecy) -> String:
	var more := prophecy.op == ">="
	var n := prophecy.target
	var what := ""
	match prophecy.metric:
		"total_population":
			what = "Grow to %d people or more" % n if more else "Fall to %d people or fewer" % n
		"tribe_count":
			what = "%d or more tribes" % n if more else "%d tribe%s or fewer" % [n, "" if n == 1 else "s"]
		"largest_tribe_population":
			what = "A tribe of %d or more" % n if more else "No tribe larger than %d" % n
		"building_count":
			what = "%d buildings standing" % n if more else "%d buildings or fewer" % n
		"discoveries":
			what = "%d discoveries made" % n if more else "No more than %d discoveries" % n
		"highest_age":
			what = "Reach the %s" % Knowledge.age_name(n) if more else "No tribe past the %s" % Knowledge.age_name(n)
		"max_dystopia":
			what = "A tribe's dystopia reaches %d" % n if more else "Every tribe's dystopia at %d or less" % n
		"max_inequality":
			what = "A tribe's inequality reaches %d" % n if more else "Every tribe's inequality at %d or less" % n
		"vassal_count":
			what = "%d vassal tribe%s or more" % [n, "" if n == 1 else "s"] if more else "%d vassal tribes or fewer" % n
		_:
			what = "%s %s %d" % [prophecy.metric.replace("_", " ").capitalize(), prophecy.op, n]
	return what


## A value of a metric, in words: "286 people", "the Age of Bronze".
static func amount_text(metric: String, value: int) -> String:
	if metric == "highest_age":
		return Knowledge.age_name(value)
	var noun := String(NOUNS.get(metric, ""))
	return "%d %s" % [value, noun] if noun else str(value)


func _box() -> StyleBoxFlat:
	var box := UiStyle.card_box(UiStyle.SPACE_3)
	box.border_color = UiStyle.INK
	return box


## The meter: a sunk track, a fill to where the world stands and a notch at the goal. The fill
## is gold while the prophecy is still unmet, violet once it would come true.
class ProphecyMeter:
	extends Control

	var value := -1.0 ## where the world stands, 0..1 of the scale (-1: not set yet)
	var shown := 0.0 ## the drawn value, eased toward value by set_shown
	var goal := 0.5 ## the target, 0..1
	var wants_more := true

	func set_shown(drawn: float) -> void:
		shown = drawn
		queue_redraw()

	func _draw() -> void:
		var track := Rect2(Vector2(0, 2), Vector2(size.x, size.y - 4))
		var radius := track.size.y / 2.0
		_round_rect(track, UiStyle.PAPER_SUNK, radius)
		var at := clampf(shown, 0.0, 1.0)
		var met := shown >= goal if wants_more else shown <= goal
		if at > 0.0:
			_round_rect(Rect2(track.position, Vector2(maxf(track.size.x * at, track.size.y), track.size.y)), UiStyle.ORACLE if met else UiStyle.GOLD, radius)
		_round_rect(track, Color(0, 0, 0, 0), radius, Color(UiStyle.INK, 0.55))
		# The goal notch: an ink tick standing out above and below the track.
		var x := clampf(track.size.x * goal, 2.0, track.size.x - 2.0)
		draw_line(Vector2(x, 0), Vector2(x, size.y), UiStyle.INK, 2.0, true)

	func _round_rect(rect: Rect2, fill: Color, radius: float, border: Color = Color(0, 0, 0, 0)) -> void:
		var box := StyleBoxFlat.new()
		box.bg_color = fill
		box.set_corner_radius_all(int(radius))
		box.anti_aliasing_size = 0.8
		if border.a > 0.0:
			box.draw_center = false
			box.border_color = border
			box.set_border_width_all(1)
		draw_style_box(box, rect)
