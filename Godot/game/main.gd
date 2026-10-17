extends Node
## M0 debug view: runs the simulation and shows its state as text. Replaced by the diorama in M1/M2.
## Space: pause.  1/2/3: speed.  P: ask the Oracle for a prophecy.  S/L: save/load.

const SPEEDS: Array[float] = [2.0, 12.0, 120.0] ## ticks (months) per second
const SAVE_PATH := "user://debug_save.json"

var sim: Simulation
var oracle: Oracle
var prophecy: Prophecy
var paused := false
var speed_index := 1
var waiting_for_oracle := false
var ai_calls := 0
var ai_cost_usd := 0.0
var _tick_budget := 0.0
var _ticks_last_second := 0
var _ticks_counted := 0
var _second_timer := 0.0
var _label := Label.new()


func _ready() -> void:
	sim = Simulation.create(int(Time.get_unix_time_from_system()))
	oracle = Oracle.new(AIProviders.from_environment())
	var layer := CanvasLayer.new()
	add_child(layer)
	_label.position = Vector2(16, 16)
	_label.add_theme_font_size_override("font_size", 15)
	layer.add_child(_label)


func _process(delta: float) -> void:
	if not paused:
		_tick_budget += delta * SPEEDS[speed_index]
		while _tick_budget >= 1.0:
			_tick_budget -= 1.0
			sim.advance()
			_ticks_counted += 1
			if prophecy and sim.state.month() == 0:
				prophecy.check(sim.state)
	_second_timer += delta
	if _second_timer >= 1.0:
		_second_timer -= 1.0
		_ticks_last_second = _ticks_counted
		_ticks_counted = 0
	_label.text = _overlay_text()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_SPACE:
			paused = not paused
		KEY_1, KEY_2, KEY_3:
			speed_index = key.keycode - KEY_1
		KEY_P:
			_ask_oracle()
		KEY_S:
			sim.save_to(SAVE_PATH)
		KEY_L:
			var loaded := Simulation.load_from(SAVE_PATH)
			if loaded:
				sim = loaded
				prophecy = null


func _ask_oracle() -> void:
	if waiting_for_oracle:
		return
	waiting_for_oracle = true
	prophecy = await oracle.request_prophecy(sim.state)
	waiting_for_oracle = false
	ai_calls += 1
	ai_cost_usd += oracle.last_response.cost_usd


func _overlay_text() -> String:
	var state := sim.state
	var lines := PackedStringArray()
	lines.append("MY AI PLANET  ·  debug view (M0)")
	lines.append("Year %d, month %d   %s x%d   %d ticks/s   seed %d" % [
		state.year(), state.month() + 1, "PAUSED" if paused else "running", int(SPEEDS[speed_index]),
		_ticks_last_second, state.seed_value,
	])
	lines.append("Rain %.2f%s   Population %d   Tribes %d" % [
		state.rainfall, "  (DROUGHT)" if state.drought_months_left > 0 else "", state.total_population(), state.tribe_count(),
	])
	lines.append("")
	for i: int in mini(state.tribe_count(), 12):
		lines.append("  %-12s %4d people   food %5.1f months" % [
			state.tribe_names[i], state.tribe_population[i], state.tribe_food[i] / maxf(state.tribe_population[i], 1.0),
		])
	lines.append("")
	lines.append("Oracle: %s   calls %d   cost $%.4f" % [oracle.provider.get_id(), ai_calls, ai_cost_usd])
	if waiting_for_oracle:
		lines.append("  The Oracle is thinking...")
	elif prophecy:
		lines.append("  \"%s\"" % prophecy.text)
		lines.append("  [%s %s %d by year %d]  %s" % [
			prophecy.metric, prophecy.op, prophecy.target, prophecy.deadline_year, Prophecy.Status.keys()[prophecy.status],
		])
	if oracle.last_response and not oracle.last_response.ok:
		lines.append("  last error: " + oracle.last_response.error.left(120))
	lines.append("")
	for event: Dictionary in state.events.slice(maxi(state.events.size() - 6, 0)):
		lines.append("  year %d: %s %s" % [WorldState.year_of(int(event["tick"])), event["type"], event["data"]])
	lines.append("")
	lines.append("Space pause · 1/2/3 speed · P prophecy · S save · L load")
	return "\n".join(lines)
