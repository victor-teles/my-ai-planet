extends Node
## Runs the era loop (Session), shows the world as a diorama, and hosts the prototype UI.
## Space: pause.  1/2/3: speed (or choose, while a dilemma card is up).  Click a camp: select a tribe.
## Enter: continue after a reveal.
## S/L: save/load.  F1: debug panel.
## Command-line options (after --): --seed=N  --warmup-years=N  --fast-forward-years=N  --hide-ui
##   --yaw= --pitch= --distance=

const SPEEDS: Array[float] = [2.0, 12.0, 120.0] ## ticks (months) per second
const SAVE_PATH := "user://debug_save.json"
const PARCHMENT := Color(0.99, 0.94, 0.84)
const CLICK_SLOP := 6.0 ## pixels a click may move and still count as a click, not a drag

var session: Session
var diorama: Diorama
var paused := false
var speed_index := 1

var _tick_budget := 0.0
var _ticks_last_second := 0
var _ticks_counted := 0
var _second_timer := 0.0
var _press_position := Vector2.ZERO
var _ui := CanvasLayer.new()
var _banner := Label.new()
var _status := Label.new()
var _debug_label := Label.new()
var _influence := Label.new()
var _target := Label.new()
var _miracle_buttons: Dictionary = {} ## miracle id -> Button
var _reveal := PanelContainer.new()
var _reveal_outcome := Label.new()
var _reveal_title := Label.new()
var _reveal_text := Label.new()
var _reveal_causes := Label.new()
var _card := PanelContainer.new()
var _card_title := Label.new()
var _card_situation := Label.new()
var _card_choices := VBoxContainer.new()
var _card_shown: Dilemma


func _ready() -> void:
	var options := _parse_options()
	var seed_value := int(options.get("seed", Time.get_unix_time_from_system()))
	var sim := Simulation.create(seed_value)
	sim.advance(int(options.get("warmup-years", 0)) * WorldState.MONTHS_PER_YEAR)
	session = Session.new(sim, Oracle.new(AIProviders.from_environment()))

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
	await session.begin()
	session.advance(int(options.get("fast-forward-years", 0)) * WorldState.MONTHS_PER_YEAR)


func _process(delta: float) -> void:
	if not paused and session.phase == Session.Phase.PLAYING:
		_tick_budget += delta * SPEEDS[speed_index]
		var whole := floori(_tick_budget)
		_tick_budget -= whole
		_ticks_counted += session.advance(whole)
	diorama.sync(session.sim.state, delta)

	_second_timer += delta
	if _second_timer >= 1.0:
		_second_timer -= 1.0
		_ticks_last_second = _ticks_counted
		_ticks_counted = 0
	_update_ui()


func _unhandled_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button and button.button_index == MOUSE_BUTTON_LEFT:
		if button.pressed:
			_press_position = button.position
		elif button.position.distance_to(_press_position) < CLICK_SLOP:
			diorama.select_tribe(diorama.pick_tribe(button.position))
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_SPACE:
			paused = not paused
		KEY_1, KEY_2, KEY_3:
			if session.phase == Session.Phase.DECIDING:
				session.choose(key.keycode - KEY_1)
			else:
				speed_index = key.keycode - KEY_1
		KEY_ENTER, KEY_KP_ENTER:
			session.continue_after_reveal()
		KEY_S:
			session.sim.save_to(SAVE_PATH)
		KEY_L:
			_load()
		KEY_F1:
			_debug_label.visible = not _debug_label.visible


func _load() -> void:
	var loaded := Simulation.load_from(SAVE_PATH)
	if loaded == null or loaded.state.seed_value != session.sim.state.seed_value:
		return # the island is built from the seed; loading another world's save needs a rebuild (later)
	session.sim = loaded
	diorama.mark_events_seen(loaded.state)
	if loaded.state.prophecy == null:
		session.begin()


func _parse_options() -> Dictionary:
	var options := {}
	for argument: String in OS.get_cmdline_user_args():
		var parts := argument.trim_prefix("--").split("=", true, 1)
		options[parts[0]] = parts[1] if parts.size() > 1 else true
	return options


# --- UI -----------------------------------------------------------------------------

func _build_ui() -> void:
	add_child(_ui)

	_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_banner.custom_minimum_size = Vector2(780, 0)
	_banner.position = Vector2(-390, 44)
	_outlined(_banner, 21, 10)
	_ui.add_child(_banner)

	_status.position = Vector2(18, 14)
	_outlined(_status, 14, 7)
	_ui.add_child(_status)

	_debug_label.position = Vector2(18, 40)
	_outlined(_debug_label, 13, 6)
	_debug_label.visible = false
	_ui.add_child(_debug_label)

	_ui.add_child(_build_miracle_bar())
	_ui.add_child(_build_reveal())
	_ui.add_child(_build_card())


func _build_miracle_bar() -> Control:
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", _parchment_box(12, 10))
	bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bar.position.y -= 16
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	bar.add_child(row)
	_inked(_influence, 17)
	_influence.custom_minimum_size.x = 120
	row.add_child(_influence)
	for id: String in Miracles.ORDER:
		var definition: Dictionary = Miracles.DEFINITIONS[id]
		var button := Button.new()
		button.text = "%s  %d" % [definition["name"], int(definition["cost"])]
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_size_override("font_size", 15)
		button.pressed.connect(_on_miracle.bind(id))
		row.add_child(button)
		_miracle_buttons[id] = button
	_inked(_target, 14)
	_target.custom_minimum_size.x = 170
	row.add_child(_target)
	return bar


func _build_reveal() -> Control:
	_reveal.add_theme_stylebox_override("panel", _parchment_box(16, 28))
	_reveal.set_anchors_preset(Control.PRESET_CENTER)
	_reveal.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_reveal.grow_vertical = Control.GROW_DIRECTION_BOTH
	_reveal.custom_minimum_size = Vector2(620, 0)
	_reveal.visible = false
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	_reveal.add_child(column)
	for label: Label in [_reveal_outcome, _reveal_title, _reveal_text, _reveal_causes]:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size.x = 560
		column.add_child(label)
	_inked(_reveal_outcome, 14)
	_reveal_outcome.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_inked(_reveal_title, 28)
	_reveal_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_inked(_reveal_text, 17)
	_inked(_reveal_causes, 15)
	var next := Button.new()
	next.text = "Continue   ⏎"
	next.focus_mode = Control.FOCUS_NONE
	next.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	next.add_theme_font_size_override("font_size", 16)
	next.pressed.connect(session.continue_after_reveal)
	column.add_child(next)
	return _reveal


func _build_card() -> Control:
	_card.add_theme_stylebox_override("panel", _parchment_box(16, 26))
	_card.set_anchors_preset(Control.PRESET_CENTER)
	_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_card.grow_vertical = Control.GROW_DIRECTION_BOTH
	_card.visible = false
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	_card.add_child(column)
	var kicker := Label.new()
	kicker.text = "A CHOICE FOR THE GOD"
	kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_inked(kicker, 13)
	column.add_child(kicker)
	for label: Label in [_card_title, _card_situation]:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size.x = 540
		column.add_child(label)
	_inked(_card_title, 26)
	_card_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_inked(_card_situation, 17)
	_card_choices.add_theme_constant_override("separation", 8)
	column.add_child(_card_choices)
	return _card


## Rebuilds the choice buttons when a new dilemma comes up.
func _show_card(dilemma: Dilemma) -> void:
	_card_shown = dilemma
	for child: Node in _card_choices.get_children():
		child.queue_free()
	if dilemma == null:
		return
	_card_title.text = dilemma.title
	_card_situation.text = dilemma.situation
	for i: int in dilemma.choices.size():
		var choice: Dictionary = dilemma.choices[i]
		var button := Button.new()
		button.text = "%d.  %s" % [i + 1, choice["label"]]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_size_override("font_size", 16)
		button.pressed.connect(session.choose.bind(i))
		_card_choices.add_child(button)
		var hint := Label.new()
		hint.text = "      " + String(choice["hint"])
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.custom_minimum_size.x = 540
		_inked(hint, 14)
		hint.add_theme_color_override("font_color", ToonMaterials.INK.lightened(0.3))
		_card_choices.add_child(hint)


func _on_miracle(id: String) -> void:
	session.cast_miracle(id, diorama.selected_tribe())


func _update_ui() -> void:
	var state := session.sim.state
	_banner.text = _banner_text()
	_status.text = "Year %d   ·   %d people in %d tribes%s   ·   %s ×%d   ·   F1 debug" % [
		state.year(), state.total_population(), state.tribe_count(),
		"   ·   DROUGHT" if state.drought_months_left > 0 else "",
		"paused" if paused else "speed", int(SPEEDS[speed_index]),
	]
	_influence.text = "✦ Influence %.1f" % state.influence
	var tribe := diorama.selected_tribe()
	_target.text = "Tribe: %s" % tribe if tribe else "Click a camp to choose a tribe"
	for id: String in _miracle_buttons:
		var button := _miracle_buttons[id] as Button
		var reason := Miracles.why_not(state, id, tribe)
		button.disabled = not reason.is_empty() or session.phase != Session.Phase.PLAYING
		button.tooltip_text = "%s\n%s" % [Miracles.DEFINITIONS[id]["description"], reason]

	_card.visible = session.phase == Session.Phase.DECIDING
	if session.dilemma != _card_shown:
		_show_card(session.dilemma)

	_reveal.visible = session.phase == Session.Phase.REVEAL
	if _reveal.visible and state.resolved_prophecy:
		var came_true := state.resolved_prophecy.status == Prophecy.Status.FULFILLED
		_reveal_outcome.text = ("THE PROPHECY CAME TRUE" if came_true else "THE PROPHECY WAS BROKEN") + "\n\"%s\"" % state.resolved_prophecy.text
		_reveal_title.text = String(session.chronicle.get("title", ""))
		_reveal_text.text = String(session.chronicle.get("text", ""))
		var causes := PackedStringArray()
		for cause: Variant in session.chronicle.get("causes", []):
			causes.append("•  " + String(cause))
		_reveal_causes.text = "\n".join(causes)
	if _debug_label.visible:
		_debug_label.text = _debug_text()


func _banner_text() -> String:
	var prophecy := session.sim.state.prophecy
	match session.phase:
		Session.Phase.FORETELLING:
			return "The Oracle is gazing into the future..."
		Session.Phase.CHRONICLING:
			return "The Chronicler is writing down what happened..."
		Session.Phase.REVEAL, Session.Phase.DECIDING:
			return ""
	if prophecy == null:
		return "The Oracle is silent."
	return "\"%s\"\n— before year %d" % [prophecy.text, prophecy.deadline_year]


func _debug_text() -> String:
	var state := session.sim.state
	var oracle := session.oracle
	var lines := PackedStringArray()
	lines.append("seed %d   tick %d   %d ticks/s   %d fps   rain %.2f   kindness %d   tone %d" % [
		state.seed_value, state.tick, _ticks_last_second, Engine.get_frames_per_second(), state.rainfall,
		state.kindness, state.tone(),
	])
	for i: int in mini(state.tribe_count(), 12):
		lines.append("  %-12s %4d people   food %5.1f months" % [
			state.tribe_names[i], state.tribe_population[i], state.tribe_food[i] / maxf(state.tribe_population[i], 1.0),
		])
	lines.append("Oracle: %s   calls %d   cost $%.4f" % [oracle.provider.get_id(), oracle.calls, oracle.cost_usd])
	if state.prophecy:
		var prophecy := state.prophecy
		lines.append("  [%s %s %d by year %d] now %d" % [
			prophecy.metric, prophecy.op, prophecy.target, prophecy.deadline_year, Prophecy.measure(prophecy.metric, state),
		])
	if oracle.last_response and not oracle.last_response.ok:
		lines.append("  last error: " + oracle.last_response.error.left(120))
	for event: Dictionary in state.events.slice(maxi(state.events.size() - 6, 0)):
		lines.append("  year %d: %s %s" % [WorldState.year_of(int(event["tick"])), event["type"], event["data"]])
	return "\n".join(lines)


func _outlined(label: Label, size: int, outline: int) -> void:
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color(1.0, 0.96, 0.88))
	label.add_theme_color_override("font_outline_color", ToonMaterials.INK)
	label.add_theme_constant_override("outline_size", outline)


func _inked(label: Label, size: int) -> void:
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", ToonMaterials.INK)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


func _parchment_box(radius: int, padding: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = PARCHMENT
	box.border_color = ToonMaterials.INK
	box.set_border_width_all(3)
	box.set_corner_radius_all(radius)
	box.set_content_margin_all(padding)
	box.shadow_color = Color(0.16, 0.10, 0.20, 0.35)
	box.shadow_size = 8
	box.shadow_offset = Vector2(0, 4)
	return box
