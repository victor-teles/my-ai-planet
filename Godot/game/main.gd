extends Node
## Runs the simulation, shows it as a diorama, and hosts the prototype UI.
## Space: pause.  1/2/3: speed.  P: ask the Oracle.  S/L: save/load.  F1: debug panel.
## Command-line options (after --): --seed=N  --warmup-years=N  --hide-ui  --prophecy  --yaw= --pitch= --distance=

const SPEEDS: Array[float] = [2.0, 12.0, 120.0] ## ticks (months) per second
const SAVE_PATH := "user://debug_save.json"

var sim: Simulation
var oracle: Oracle
var prophecy: Prophecy
var diorama: Diorama
var paused := false
var speed_index := 1
var waiting_for_oracle := false
var ai_calls := 0
var ai_cost_usd := 0.0

var _tick_budget := 0.0
var _ticks_last_second := 0
var _ticks_counted := 0
var _second_timer := 0.0
var _ui := CanvasLayer.new()
var _debug_label := Label.new()
var _banner := Label.new()
var _status := Label.new()


func _ready() -> void:
	var options := _parse_options()
	var seed_value := int(options.get("seed", Time.get_unix_time_from_system()))
	sim = Simulation.create(seed_value)
	sim.advance(int(options.get("warmup-years", 0)) * WorldState.MONTHS_PER_YEAR)
	oracle = Oracle.new(AIProviders.from_environment())

	diorama = Diorama.new()
	add_child(diorama)
	diorama.build(seed_value)
	diorama.mark_events_seen(sim.state)
	diorama.sync(sim.state, 0.0)
	var rig := diorama.camera_rig
	rig.yaw = float(options.get("yaw", rig.yaw))
	rig.pitch = float(options.get("pitch", rig.pitch))
	rig.distance = float(options.get("distance", rig.distance))

	_build_ui()
	_ui.visible = not options.has("hide-ui")
	if options.has("prophecy"):
		_ask_oracle()


func _process(delta: float) -> void:
	if not paused:
		_tick_budget += delta * SPEEDS[speed_index]
		while _tick_budget >= 1.0:
			_tick_budget -= 1.0
			sim.advance()
			_ticks_counted += 1
			if prophecy and sim.state.month() == 0:
				prophecy.check(sim.state)
	diorama.sync(sim.state, delta)

	_second_timer += delta
	if _second_timer >= 1.0:
		_second_timer -= 1.0
		_ticks_last_second = _ticks_counted
		_ticks_counted = 0
	_banner.text = _banner_text()
	_status.text = _status_text()
	if _debug_label.visible:
		_debug_label.text = _debug_text()


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
			_load()
		KEY_F1:
			_debug_label.visible = not _debug_label.visible


func _ask_oracle() -> void:
	if waiting_for_oracle:
		return
	waiting_for_oracle = true
	prophecy = await oracle.request_prophecy(sim.state)
	waiting_for_oracle = false
	ai_calls += 1
	ai_cost_usd += oracle.last_response.cost_usd


func _load() -> void:
	var loaded := Simulation.load_from(SAVE_PATH)
	if loaded == null or loaded.state.seed_value != sim.state.seed_value:
		return # the island is built from the seed; loading another world's save needs a rebuild (later)
	sim = loaded
	prophecy = null
	diorama.mark_events_seen(sim.state)


func _parse_options() -> Dictionary:
	var options := {}
	for argument: String in OS.get_cmdline_user_args():
		var parts := argument.trim_prefix("--").split("=", true, 1)
		options[parts[0]] = parts[1] if parts.size() > 1 else true
	return options


func _build_ui() -> void:
	add_child(_ui)
	_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_banner.custom_minimum_size = Vector2(760, 0)
	_banner.position = Vector2(-380, 24)
	_style(_banner, 22, 10)
	_ui.add_child(_banner)

	_status.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_status.position = Vector2(20, -44)
	_style(_status, 16, 8)
	_ui.add_child(_status)

	_debug_label.position = Vector2(16, 16)
	_style(_debug_label, 13, 6)
	_debug_label.visible = false
	_ui.add_child(_debug_label)


func _style(label: Label, size: int, outline: int) -> void:
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color(1.0, 0.96, 0.88))
	label.add_theme_color_override("font_outline_color", ToonMaterials.INK)
	label.add_theme_constant_override("outline_size", outline)


func _banner_text() -> String:
	if waiting_for_oracle:
		return "The Oracle is gazing into the future..."
	if prophecy == null:
		return "Press P to hear the Oracle's prophecy"
	match prophecy.status:
		Prophecy.Status.FULFILLED:
			return "The prophecy came true:\n\"%s\"" % prophecy.text
		Prophecy.Status.BROKEN:
			return "The prophecy was broken:\n\"%s\"" % prophecy.text
	return "\"%s\"\n— until year %d" % [prophecy.text, prophecy.deadline_year]


func _status_text() -> String:
	var state := sim.state
	return "Year %d   ·   %d people in %d tribes%s   ·   %s ×%d   ·   F1 debug" % [
		state.year(), state.total_population(), state.tribe_count(),
		"   ·   DROUGHT" if state.drought_months_left > 0 else "",
		"paused" if paused else "speed", int(SPEEDS[speed_index]),
	]


func _debug_text() -> String:
	var state := sim.state
	var lines := PackedStringArray()
	lines.append("seed %d   tick %d   %d ticks/s   %d fps   rain %.2f" % [
		state.seed_value, state.tick, _ticks_last_second, Engine.get_frames_per_second(), state.rainfall,
	])
	for i: int in mini(state.tribe_count(), 12):
		lines.append("  %-12s %4d people   food %5.1f months" % [
			state.tribe_names[i], state.tribe_population[i], state.tribe_food[i] / maxf(state.tribe_population[i], 1.0),
		])
	lines.append("Oracle: %s   calls %d   cost $%.4f" % [oracle.provider.get_id(), ai_calls, ai_cost_usd])
	if prophecy:
		lines.append("  [%s %s %d by year %d] %s" % [
			prophecy.metric, prophecy.op, prophecy.target, prophecy.deadline_year, Prophecy.Status.keys()[prophecy.status],
		])
	if oracle.last_response and not oracle.last_response.ok:
		lines.append("  last error: " + oracle.last_response.error.left(120))
	for event: Dictionary in state.events.slice(maxi(state.events.size() - 6, 0)):
		lines.append("  year %d: %s %s" % [WorldState.year_of(int(event["tick"])), event["type"], event["data"]])
	lines.append("Space pause · 1/2/3 speed · P prophecy · S save · L load · drag orbit · wheel zoom")
	return "\n".join(lines)
