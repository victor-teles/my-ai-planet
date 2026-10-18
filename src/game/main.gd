extends Node
## Runs the era loop (Session), shows the world as a diorama, and hosts the HUD.
## The HUD (see docs/ART_BIBLE.md, "UI"): the top bar (time controls, the island, the panels'
## buttons), the left column (the prophecy, then the life feed), the right dock (a person or a
## tribe), the miracle bar at the bottom, and modal cards over a dim scrim (a chronicle, a dilemma,
## the charts, the AI settings, the keys).
## Space: pause.  1-5: speed (or choose, while a dilemma card is up).
## Click a person: inspect them (their life, place in society, family, DNA, bonds and story).
## F: follow them.  Click a camp: inspect the tribe (its life, and its Society tab: government,
## rulers, factions, measures, culture, laws, crisis) and choose it for miracles.  Esc: close.
## Tab: life feed.  E: evolution chart.  H: society chart.  Enter: continue after a reveal.
## A: AI settings (also the Oracle button at the top right; time stops while they're open).
## ?: the keys.  S/L: save/load.  F1: debug panel.
## Command-line options (after --): --seed=N  --warmup-years=N  --fast-forward-years=N  --hide-ui
##   --age=N (0-4: every tribe starts knowing everything up to that age, before the warm-up)
##   --inspect=N [--tab=DNA] [--follow]: open the N-th person (tabs: Life, Family, DNA, Bonds, Story)
##   --tribe[=N] [--tab=Society] [--scroll=PIXELS]: open the first (or N-th) tribe (tabs: Life,
##     Society), scrolled down that far
##   --evolution: open the evolution chart.  --society-chart[=measure]: open the society chart
##     (dystopia, freedom, control, inequality, fear, population or smog)
##   --yaw= --pitch= --distance=  --debug-dilemma=res://path/to/dilemma.json
##   --debug-chronicle=res://path/to/chronicle.json
##   --debug-stream=res://path/to/chronicle.json: the reveal as it streams in (half the text written)
##   --ai-settings[=Usage] [--ai-provider=ollama]: open the AI settings (tabs: Provider,
##     "Routing & budget", Usage), showing that provider; [--ai-url=http://...] fills its server,
##     --ai-list lists the server's models, --ai-test tests the connection
##   UI checks: --feed=off|full (the feed hidden, or unfolded to the column's height),
##     --feed-filters (the filters open), --prophecy=folded, --keys (the keys card),
##     --hover-miracle=ID (its hint shown), --paused, --speed=1..5

const SPEEDS: Array[float] = [2.0, 6.0, 20.0, 60.0, 180.0] ## ticks (days) per second
const MAX_FRAME_BACKLOG := 0.1 ## seconds of ticks run per frame at most: a slow sim slows time instead of stalling
const SAVE_PATH := "user://debug_save.json"
const CLICK_SLOP := 6.0 ## pixels a click may move and still count as a click, not a drag
const FOLLOW_DISTANCE := 9.0
const HUD_REFRESH_SECONDS := 0.5 ## the island plaque, the prophecy and the omens change slowly
const OMEN_AT := 5 ## years a destiny's conditions must have held before the top bar warns of it
const SCREEN_SHARE := 0.8 ## how much of the screen the window takes when the game starts
const NOTICE_SECONDS := 12.0
# Layout (logical pixels; the canvas scales with the window).
const MARGIN := 12.0 ## from the screen's edges
const GAP := 8.0 ## between neighbors
const LEFT_DOCK := 300.0 ## the prophecy and the feed
const RIGHT_DOCK := 360.0 ## a person or a tribe

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
var _hud := Control.new() ## docks and bars, under the scrim
var _scrim := ColorRect.new()
var _modal_layer := Control.new() ## modal cards, over the scrim
var _top_bar := TopBar.new()
var _prophecy := ProphecyCard.new()
var _miracles := MiracleBar.new()
var _feed := LifeFeed.new()
var _person_panel := PersonPanel.new()
var _tribe_panel := TribePanel.new()
var _evolution := EvolutionPanel.new()
var _society_chart := SocietyPanel.new()
var _reveal := RevealCard.new()
var _card := DilemmaCard.new()
var _keys := KeysCard.new()
var _ai_panel := AISettingsPanel.new()
var _notice := PanelContainer.new()
var _notice_text := Label.new()
var _debug_box := PanelContainer.new()
var _debug_label := Label.new()
var _hud_since := HUD_REFRESH_SECONDS
var _reveal_shown: Dictionary = {}
var _inspected_id := -1
var _following := false
var _thoughts: Dictionary = {} ## "person id|year" -> what they think
var _thought_key := ""
var _ai_settings: AISettings
var _paused_before_settings := false
var _notice_left := 0.0
var _modal_order: Array[Control] = [] ## visible modals, the last opened on top
var _was_visible: Dictionary = {} ## Control -> whether it showed last frame (to animate it in)


func _ready() -> void:
	_fit_window_to_screen()
	var options := _parse_options()
	var seed_value := int(options.get("seed", Time.get_unix_time_from_system()))
	var sim := Simulation.create(seed_value)
	if options.has("age"):
		_teach_up_to(sim.state, int(options["age"]))
	sim.advance(int(options.get("warmup-years", 0)) * WorldState.DAYS_PER_YEAR)
	sim.state.influence = minf(sim.state.influence, WorldState.STARTING_INFLUENCE) # warm-up isn't the player's
	# The provider comes from the AI Settings (the environment wins; nothing saved: auto-detect).
	_ai_settings = AISettings.load_from()
	var oracle := Oracle.new(OfflineTemplatesProvider.new())
	_ai_settings.apply(oracle)
	oracle.went_offline.connect(_on_oracle_offline)
	session = Session.new(sim, oracle)

	diorama = Diorama.new()
	add_child(diorama)
	diorama.build(sim.state.world, seed_value)
	diorama.mark_events_seen(sim.state)
	diorama.sync(sim.state, 0.0)
	var rig := diorama.camera_rig
	rig.yaw = float(options.get("yaw", rig.yaw))
	rig.pitch = float(options.get("pitch", rig.pitch))
	rig.distance = float(options.get("distance", rig.distance))

	_build_ui()
	_ui.visible = not options.has("hide-ui")
	if options.has("paused"):
		paused = true
	if options.has("speed"):
		speed_index = clampi(int(options["speed"]) - 1, 0, SPEEDS.size() - 1)
	_apply_ui_options(options)
	await session.begin()
	session.advance(int(options.get("fast-forward-years", 0)) * WorldState.DAYS_PER_YEAR)
	if options.has("inspect"):
		_inspect(sim.state.person_ids[clampi(int(options["inspect"]), 0, sim.state.person_ids.size() - 1)])
		_set_following(options.has("follow"))
	if options.has("tab"):
		_person_panel.select_tab(String(options["tab"]))
		_tribe_panel.select_tab(String(options["tab"]))
	if options.has("tribe") and sim.state.tribe_count() > 0:
		var which := int(options["tribe"]) if options["tribe"] is String else 0
		_show_tribe(sim.state.tribe_names[clampi(which, 0, sim.state.tribe_count() - 1)])
	if options.has("scroll"):
		for frame: int in 3: # the panel knows how far it can scroll only after a layout pass
			await get_tree().process_frame
		_tribe_panel.scroll_to(int(options["scroll"]))
	if options.has("evolution"):
		_evolution.visible = true
	if options.has("society-chart"):
		_society_chart.visible = true
		if options["society-chart"] is String:
			_society_chart.select_measure(String(options["society-chart"]))
	if options.has("debug-dilemma"):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(String(options["debug-dilemma"])))
		session.present(Dilemma.from_proposal(data, sim.state))
	if options.has("debug-chronicle"):
		session.present_reveal(JSON.parse_string(FileAccess.get_file_as_string(String(options["debug-chronicle"]))))
	if options.has("debug-stream"):
		var written: Variant = JSON.parse_string(FileAccess.get_file_as_string(String(options["debug-stream"])))
		var text := String((written as Dictionary).get("text", "")) if written is Dictionary else ""
		session.present_chronicling(text.left(roundi(text.length() * 0.5)))
	if options.has("ai-settings"):
		_toggle_settings()
		if options.has("ai-provider"):
			_ai_panel.pick_provider(String(options["ai-provider"]))
		if options["ai-settings"] is String:
			_ai_panel.select_tab(String(options["ai-settings"]))
		if options.has("ai-url"):
			_ai_panel.set_server(String(options["ai-url"]))
		if options.has("ai-list"):
			_ai_panel.list_models()
		if options.has("ai-test"):
			_ai_panel.test_connection()


func _process(delta: float) -> void:
	if not paused and session.phase == Session.Phase.PLAYING:
		_tick_budget = minf(_tick_budget + delta * SPEEDS[speed_index], SPEEDS[speed_index] * MAX_FRAME_BACKLOG + 1.0)
		var whole := floori(_tick_budget)
		_tick_budget -= whole
		_ticks_counted += session.advance(whole)
	diorama.sync(session.sim.state, delta)
	var rig := diorama.camera_rig
	if _following and _inspected_id != -1:
		var at: Variant = diorama.person_position(_inspected_id)
		if at != null:
			rig.focus = at
			if rig.distance > FOLLOW_DISTANCE + 4.0:
				rig.distance = move_toward(rig.distance, FOLLOW_DISTANCE, delta * 20.0)
	else:
		rig.focus = Vector3.ZERO

	_second_timer += delta
	if _second_timer >= 1.0:
		_second_timer -= 1.0
		_ticks_last_second = _ticks_counted
		_ticks_counted = 0
	_update_ui(delta)


func _unhandled_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button and button.button_index == MOUSE_BUTTON_LEFT:
		if button.pressed:
			_press_position = button.position
		elif button.position.distance_to(_press_position) < CLICK_SLOP:
			_on_world_click(button.position)
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if _ai_panel.visible:
		if key.keycode in [KEY_A, KEY_ESCAPE]:
			_toggle_settings()
		return # time is stopped and the other keys wait while the settings are open
	match key.keycode:
		KEY_SPACE:
			_toggle_pause()
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
			if session.phase == Session.Phase.DECIDING:
				if session.dilemma and key.keycode - KEY_1 < session.dilemma.choices.size():
					session.choose(key.keycode - KEY_1)
			else:
				_set_speed(key.keycode - KEY_1)
		KEY_ENTER, KEY_KP_ENTER:
			session.continue_after_reveal()
		KEY_ESCAPE:
			if not _close_top_modal():
				_inspect(-1)
				_show_tribe("")
		KEY_TAB:
			_toggle_feed()
		KEY_E:
			_toggle_chart(_evolution)
		KEY_H:
			_toggle_chart(_society_chart)
		KEY_F:
			_set_following(not _following)
		KEY_S:
			session.sim.save_to(SAVE_PATH)
		KEY_L:
			_load()
		KEY_F1:
			_debug_box.visible = not _debug_box.visible
		KEY_A:
			_toggle_settings()
		KEY_SLASH, KEY_QUESTION:
			_keys.visible = not _keys.visible


## A person under the cursor is inspected; otherwise a camp is selected and the tribe shown.
func _on_world_click(screen_position: Vector2) -> void:
	var person := diorama.pick_person(screen_position)
	if person != -1:
		_inspect(person)
		return
	var tribe := diorama.pick_tribe(screen_position)
	diorama.select_tribe(tribe)
	_inspect(-1)
	_show_tribe(tribe)


## Opens the person panel on someone (living or dead); -1 closes it.
func _inspect(id: int) -> void:
	var state := session.sim.state
	var known := state.is_alive(id) or state.dead.has(str(id))
	_inspected_id = id if known else -1
	if _inspected_id == -1:
		_person_panel.visible = false
		diorama.focus_person(-1)
		_set_following(false)
		return
	_tribe_panel.visible = false
	_person_panel.show_person(state, id)
	_person_panel.visible = true
	var p := state.index_of(id)
	diorama.focus_person(id, state.person_names[p] if p != -1 else "")
	if p != -1:
		diorama.select_tribe(state.person_tribes[p])
		_refresh_thought(p)
	else:
		_set_following(false)


func _show_tribe(tribe: String) -> void:
	if tribe.is_empty() or session.sim.state.tribe_index(tribe) == -1:
		_tribe_panel.visible = false
		return
	_person_panel.visible = false
	_inspected_id = -1
	diorama.focus_person(-1)
	_set_following(false)
	_tribe_panel.show_tribe(session.sim.state, tribe)
	_tribe_panel.visible = true
	diorama.select_tribe(tribe)


func _set_following(on: bool) -> void:
	_following = on and _inspected_id != -1 and session.sim.state.is_alive(_inspected_id)


## Shows a thought right away from the offline templates; a real AI's version replaces it when it
## arrives. Thoughts are kept for a year so clicking around doesn't keep asking the AI.
func _refresh_thought(p: int) -> void:
	var state := session.sim.state
	var id := state.person_ids[p]
	var key := _thought_key_for(p)
	_thought_key = key
	if _thoughts.has(key):
		_person_panel.set_thought(_thoughts[key])
		return
	var oracle := session.oracle
	_thoughts[key] = oracle.offline_thought(state, p)
	_person_panel.set_thought(_thoughts[key])
	if oracle.offline_for("thought"):
		return
	var thought := await oracle.request_thought(state, p)
	if thought:
		_thoughts[key] = thought
		if _inspected_id == id:
			_person_panel.set_thought(thought)


func _thought_key_for(p: int) -> String:
	var state := session.sim.state
	return "%d|%d" % [state.person_ids[p], state.year()]


func _load() -> void:
	var loaded := Simulation.load_from(SAVE_PATH)
	if loaded == null or loaded.state.seed_value != session.sim.state.seed_value:
		return # the island is built from the seed; loading another world's save needs a rebuild (later)
	session.sim = loaded
	diorama.mark_events_seen(loaded.state)
	if loaded.state.prophecy == null:
		session.begin()


## On high-density screens the default window opens at half its intended size; open at a
## comfortable share of the screen instead. The 16:9 canvas scales to fill it.
func _fit_window_to_screen() -> void:
	var window := get_window()
	if window.mode != Window.MODE_WINDOWED or DisplayServer.get_name() == "headless":
		return
	var usable := Vector2(DisplayServer.screen_get_usable_rect(window.current_screen).size)
	var width := minf(usable.x * SCREEN_SHARE, usable.y * SCREEN_SHARE * 16.0 / 9.0)
	if width > window.size.x:
		window.size = Vector2i(roundi(width), roundi(width * 9.0 / 16.0))
		window.move_to_center()


## For screenshots and testing: every tribe learns every tech of the ages up to this one.
func _teach_up_to(state: WorldState, age: int) -> void:
	for t: int in state.tribe_count():
		for tech: String in Knowledge.ORDER:
			if int(Knowledge.TECHS[tech]["age"]) <= age:
				state.learn(t, tech)


func _parse_options() -> Dictionary:
	var options := {}
	for argument: String in OS.get_cmdline_user_args():
		var parts := argument.trim_prefix("--").split("=", true, 1)
		options[parts[0]] = parts[1] if parts.size() > 1 else true
	return options


## The UI-only options, for screenshots and checks.
func _apply_ui_options(options: Dictionary) -> void:
	match String(options.get("feed", "")):
		"off":
			_feed.visible = false
		"full":
			_feed.set_expanded(true)
	if options.has("feed-filters"):
		_feed.set_filters_open(true)
	if String(options.get("prophecy", "")) == "folded":
		_prophecy.toggle()
	if options.has("keys"):
		_keys.visible = true
	if options.has("hover-miracle"):
		_miracles.preview(String(options["hover-miracle"]))


# --- Time ---------------------------------------------------------------------------

func _toggle_pause() -> void:
	paused = not paused


func _set_speed(index: int) -> void:
	speed_index = clampi(index, 0, SPEEDS.size() - 1)
	paused = false


# --- Panels -------------------------------------------------------------------------

func _toggle_feed() -> void:
	_feed.visible = not _feed.visible


## The charts are modal and one at a time.
func _toggle_chart(chart: Control) -> void:
	var open := not chart.visible
	_evolution.visible = false
	_society_chart.visible = false
	chart.visible = open


func _on_nav(id: String) -> void:
	match id:
		"feed":
			_toggle_feed()
		"evolution":
			_toggle_chart(_evolution)
		"society":
			_toggle_chart(_society_chart)
		"ai":
			_toggle_settings()
		"help":
			_keys.visible = not _keys.visible


## Opens the AI settings (stopping time) or closes them (time runs as it did before).
func _toggle_settings() -> void:
	if _ai_panel.visible:
		_ai_panel.visible = false
		paused = _paused_before_settings
		return
	_paused_before_settings = paused
	paused = true
	_ai_panel.open(session.oracle, _ai_settings)


## Closes the top modal the player may close (a chart, the keys). Chronicles and dilemmas wait
## for their button. Returns whether one was closed.
func _close_top_modal() -> bool:
	for k: int in range(_modal_order.size() - 1, -1, -1):
		var modal := _modal_order[k]
		if modal == _ai_panel:
			_toggle_settings()
			return true
		if modal in [_evolution, _society_chart, _keys]:
			modal.visible = false
			return true
	return false


func _on_scrim_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		var top: Control = _modal_order[-1] if not _modal_order.is_empty() else null
		if top in [_evolution, _society_chart, _keys]:
			top.visible = false


func _on_oracle_offline(reason: String) -> void:
	_notice_text.text = "The Oracle's voice fades: %s. The world keeps turning offline." % reason
	_notice_left = NOTICE_SECONDS


# --- Building the HUD ---------------------------------------------------------------

func _build_ui() -> void:
	add_child(_ui)
	get_tree().root.theme = UiStyle.theme() # popups and tooltips too
	for layer: Control in [_hud, _modal_layer]:
		layer.set_anchors_preset(Control.PRESET_FULL_RECT)
		layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.theme = UiStyle.theme()
		layer.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_ui.add_child(_hud)
	_scrim.color = UiStyle.SCRIM
	_scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	_scrim.visible = false
	_scrim.gui_input.connect(_on_scrim_input)
	_ui.add_child(_scrim)
	_ui.add_child(_modal_layer)

	# Docks and bars.
	_hud.add_child(_prophecy)
	_hud.add_child(_feed)
	_feed.person_clicked.connect(_inspect)
	_feed.closed.connect(_toggle_feed)
	_person_panel.visible = false
	_person_panel.person_clicked.connect(_inspect)
	_person_panel.tribe_clicked.connect(_show_tribe)
	_person_panel.closed.connect(_inspect.bind(-1))
	_person_panel.follow_toggled.connect(_set_following)
	_hud.add_child(_person_panel)
	_tribe_panel.visible = false
	_tribe_panel.person_clicked.connect(_inspect)
	_tribe_panel.tribe_clicked.connect(_show_tribe)
	_tribe_panel.closed.connect(_show_tribe.bind(""))
	_hud.add_child(_tribe_panel)
	_miracles.cast.connect(func(id: String) -> void: session.cast_miracle(id, diorama.selected_tribe()))
	_miracles.clear_target.connect(func() -> void: diorama.select_tribe(""))
	_hud.add_child(_miracles)
	_build_debug()

	# Modals.
	_evolution.visible = false
	_evolution.closed.connect(func() -> void: _evolution.visible = false)
	_society_chart.visible = false
	_society_chart.closed.connect(func() -> void: _society_chart.visible = false)
	_reveal.continue_pressed.connect(session.continue_after_reveal)
	_card.chosen.connect(session.choose)
	_keys.closed.connect(func() -> void: _keys.visible = false)
	_ai_panel.closed.connect(_toggle_settings)
	for modal: Control in [_reveal, _card, _evolution, _society_chart, _keys, _ai_panel]:
		_modal_layer.add_child(modal)

	# The top bar stays over the scrim: time and the panels are always in reach.
	_top_bar.theme = UiStyle.theme()
	_top_bar.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_top_bar.speeds = SPEEDS
	_top_bar.pause_pressed.connect(_toggle_pause)
	_top_bar.speed_picked.connect(_set_speed)
	_top_bar.nav_pressed.connect(_on_nav)
	_ui.add_child(_top_bar)
	_build_notice()


func _build_notice() -> void:
	_notice.theme = UiStyle.theme()
	_notice.theme_type_variation = "Plaque"
	_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_notice.visible = false
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiStyle.SPACE_2)
	row.add_child(UiStyle.icon("oracle", 18))
	UiStyle.inked(_notice_text, UiStyle.BODY)
	_notice_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_notice_text.custom_minimum_size.x = 420
	row.add_child(_notice_text)
	_notice.add_child(row)
	_ui.add_child(_notice)


func _build_debug() -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.14, 0.08, 0.20, 0.82)
	box.set_corner_radius_all(UiStyle.RADIUS_M)
	box.set_content_margin_all(UiStyle.SPACE_3)
	_debug_box.add_theme_stylebox_override("panel", box)
	_debug_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_debug_box.visible = false
	_debug_label.add_theme_font_size_override("font_size", UiStyle.SMALL)
	_debug_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.86))
	_debug_box.add_child(_debug_label)
	_hud.add_child(_debug_box)


# --- Every frame --------------------------------------------------------------------

func _update_ui(delta: float) -> void:
	var state := session.sim.state
	var playing := session.phase == Session.Phase.PLAYING
	var waiting := ""
	match session.phase:
		Session.Phase.FORETELLING:
			waiting = "the Oracle speaks"
		Session.Phase.CHRONICLING, Session.Phase.REVEAL:
			waiting = "a chronicle"
		Session.Phase.DECIDING:
			waiting = "your choice"
	if _ai_panel.visible and waiting.is_empty():
		waiting = "AI settings open"
	_top_bar.show_time(state, paused, speed_index, waiting)
	_top_bar.show_nav({
		"feed": _feed.visible, "evolution": _evolution.visible, "society": _society_chart.visible, "ai": _ai_panel.visible,
	}, _oracle_text(), not session.oracle.is_offline())
	_hud_since += delta
	if _hud_since >= HUD_REFRESH_SECONDS:
		_hud_since = 0.0
		_update_island(state)
		_prophecy.show_prophecy(state, state.prophecy, session.phase)
	_miracles.show_state(state, diorama.selected_tribe(), playing, delta)

	# The dilemma card, and the chronicle (streaming in, then whole).
	_card.visible = session.phase == Session.Phase.DECIDING
	_card.show_dilemma(session.dilemma)
	var streaming := session.phase == Session.Phase.CHRONICLING and not session.story_so_far.is_empty()
	_reveal.visible = session.phase == Session.Phase.REVEAL or streaming
	var destiny_told := session.chronicle.has("destiny")
	if streaming:
		var outcome := _outcome(state, session.writing_destiny, String(state.destiny.get("kind", "")))
		_reveal.show_streaming(outcome[0], outcome[1], outcome[2], session.story_so_far)
	elif _reveal.visible and (state.resolved_prophecy or destiny_told):
		if session.chronicle != _reveal_shown or _reveal.is_streaming():
			_reveal_shown = session.chronicle
			var outcome := _outcome(state, destiny_told, String(session.chronicle.get("destiny", "")))
			_reveal.show_chronicle(outcome[0], outcome[1], outcome[2], String(session.chronicle.get("title", "")),
				String(session.chronicle.get("text", "")), session.chronicle.get("causes", []))

	_feed.refresh(state)
	if _person_panel.visible:
		_person_panel.refresh(state)
		var p := state.index_of(_inspected_id)
		if p != -1 and _thought_key_for(p) != _thought_key:
			_refresh_thought(p)
	if _tribe_panel.visible:
		_tribe_panel.refresh(state)
	if _evolution.visible:
		_evolution.refresh(state)
	if _society_chart.visible:
		_society_chart.refresh(state)
	if _debug_box.visible:
		_debug_label.text = _debug_text()
	_ai_panel.refresh(delta)
	_notice_left -= delta
	_notice.visible = _notice_left > 0.0
	_animate_shown()
	_layout()


## Lays out every visible piece for the screen's size: the top bar, the left column (prophecy,
## then feed), the right dock, the miracle bar, and the modals centered under the top bar.
func _layout() -> void:
	var view := get_viewport().get_visible_rect().size
	_top_bar.arrange(view, MARGIN)
	_miracles.arrange(view, MARGIN)
	var top := MARGIN + TopBar.HEIGHT + GAP
	var bottom := view.y - MARGIN - _miracles.bar_height() - GAP
	# Left column: the prophecy, then the feed in what's left.
	_prophecy.reset_size()
	_prophecy.position = Vector2(MARGIN, top) + UiStyle.slide_of(_prophecy)
	_prophecy.size.x = LEFT_DOCK
	var feed_top := top + _prophecy.size.y + GAP
	var feed_room := maxf(bottom - feed_top, 120.0)
	_feed.size = Vector2(LEFT_DOCK, _feed.wanted_height(feed_room))
	_feed.position = Vector2(MARGIN, feed_top) + UiStyle.slide_of(_feed)
	# Right dock: one inspector at a time, the full height.
	for panel: Control in [_person_panel, _tribe_panel]:
		if panel.visible:
			panel.size = Vector2(RIGHT_DOCK, bottom - top)
			panel.position = Vector2(view.x - MARGIN - RIGHT_DOCK, top) + UiStyle.slide_of(panel)
	_debug_box.position = Vector2(MARGIN + LEFT_DOCK + GAP, top + 30.0)
	# Modals: centered in the room under the top bar.
	var room := Rect2(MARGIN, top, view.x - 2.0 * MARGIN, view.y - top - MARGIN)
	_reveal.fit_to(room)
	_card.fit_to(room)
	for modal: Control in [_evolution, _society_chart, _keys, _ai_panel]:
		if modal.visible:
			_center_in(modal, room)
	_notice.reset_size()
	_notice.position = Vector2((view.x - _notice.size.x) / 2.0, top + 34.0).floor()


func _center_in(modal: Control, room: Rect2) -> void:
	var wanted := modal.get_combined_minimum_size()
	if modal.has_method("wanted_size"):
		wanted = modal.call("wanted_size")
	var fitted := Vector2(minf(wanted.x, room.size.x), minf(wanted.y, room.size.y))
	modal.size = fitted
	modal.position = (room.position + (room.size - fitted) / 2.0).floor()
	modal.pivot_offset = fitted / 2.0


## Animates what just appeared (docks slide in from their side, modals pop in), keeps the
## modal stack in opening order and puts the scrim under the top modal.
func _animate_shown() -> void:
	var slides := {_feed: Vector2(-UiStyle.SLIDE, 0), _person_panel: Vector2(UiStyle.SLIDE, 0),
		_tribe_panel: Vector2(UiStyle.SLIDE, 0), _prophecy: Vector2(-UiStyle.SLIDE, 0)}
	for control: Control in slides:
		if control.visible and not _was_visible.get(control, false):
			UiStyle.appear(control, slides[control])
		_was_visible[control] = control.visible
	# A chronicle or a dilemma takes the stage: the charts and the keys make way.
	for story: Control in [_reveal, _card]:
		if story.visible and not _was_visible.get(story, false):
			for lesser: Control in [_evolution, _society_chart, _keys]:
				lesser.visible = false
	for modal: Control in [_reveal, _card, _evolution, _society_chart, _keys, _ai_panel]:
		var was := bool(_was_visible.get(modal, false))
		if modal.visible and not was:
			_modal_order.erase(modal)
			_modal_order.append(modal)
			UiStyle.pop_in(modal)
		elif not modal.visible and was:
			_modal_order.erase(modal)
		_was_visible[modal] = modal.visible
	_scrim.visible = not _modal_order.is_empty()
	for k: int in _modal_order.size():
		_modal_layer.move_child(_modal_order[k], k)


## The top bar's island plaque and the chips under it: drought, smog, omens, the destiny.
func _update_island(state: WorldState) -> void:
	var age := 0
	for t: int in state.tribe_count():
		age = maxi(age, state.age_of(t))
	var chips: Array[Control] = []
	if state.drought_months_left > 0:
		chips.append(_status_chip("drought", "Drought", UiStyle.WARN, "No rain for %d more months: the fields dry, the stores shrink." % state.drought_months_left))
	if state.pollution >= 5.0:
		chips.append(_status_chip("smog", "Smog %d" % roundi(state.pollution), UiStyle.INK_SOFT, "Smoke from the factories hangs over the island (0 to 100)."))
	if state.destiny.is_empty():
		var progress := DestinySystem.progress(state)
		var kinds: Array = progress.keys()
		kinds.sort_custom(func(a: String, b: String) -> bool: return int(progress[a]) > int(progress[b]))
		for kind: String in kinds.slice(0, 2):
			if int(progress[kind]) >= OMEN_AT:
				var dark := bool((DestinySystem.KINDS.get(kind, {}) as Dictionary).get("dark", true))
				chips.append(_status_chip("skull" if dark else "bloom", "%s  %d/%d years" % [DestinySystem.name_of(kind), int(progress[kind]), DestinySystem.HOLD_YEARS],
					UiStyle.DARK if dark else UiStyle.GOOD,
					"An omen: if the island's greatest realm stays this way for %d years, that is how the island's story ends." % DestinySystem.HOLD_YEARS))
	else:
		var kind := String(state.destiny["kind"])
		var info: Dictionary = DestinySystem.KINDS.get(kind, {})
		var tribe := String(state.destiny.get("tribe", ""))
		chips.append(_status_chip("skull" if bool(info.get("dark", true)) else "bloom", "Destiny: %s" % DestinySystem.name_of(kind),
			UiStyle.DARK if bool(info.get("dark", true)) else UiStyle.GOOD,
			"%s\n%s in year %d." % [info.get("text", ""), "Under the %s," % tribe if tribe else "It came", int(state.destiny.get("year", state.year()))]))
	_top_bar.show_island(state, Knowledge.age_name(age), chips)


func _status_chip(icon_name: String, text: String, ink: Color, tip: String) -> Control:
	var chip := PanelContainer.new()
	var box := UiStyle.chip_box(UiStyle.PAPER)
	box.border_color = ink
	box.content_margin_left = 6
	box.shadow_color = UiStyle.SHADOW
	box.shadow_size = 4
	box.shadow_offset = Vector2(0, 2)
	chip.add_theme_stylebox_override("panel", box)
	chip.tooltip_text = tip
	chip.mouse_filter = Control.MOUSE_FILTER_STOP
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(UiStyle.icon(icon_name, 14))
	var label := UiStyle.strong(UiStyle.label(text, UiStyle.SMALL))
	label.add_theme_color_override("font_color", ink)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)
	chip.add_child(row)
	return chip


## [ribbon, dark, quote] for the chronicle card.
func _outcome(state: WorldState, destiny: bool, kind: String) -> Array:
	if destiny:
		var info: Dictionary = DestinySystem.KINDS.get(kind, {})
		return ["THE ISLAND'S DESTINY:  %s" % DestinySystem.name_of(kind).to_upper(), bool(info.get("dark", true)), String(info.get("text", ""))]
	var prophecy := state.resolved_prophecy
	if prophecy == null:
		return ["THE CHRONICLE", false, ""]
	var came_true := prophecy.status == Prophecy.Status.FULFILLED
	return ["THE PROPHECY CAME TRUE" if came_true else "THE PROPHECY WAS BROKEN", not came_true, "“%s”" % prophecy.text]


func _oracle_text() -> String:
	var oracle := session.oracle
	return "the built-in stories (offline)" if oracle.is_offline() else oracle.provider.get_id().replace("_", " ")


func _debug_text() -> String:
	var state := session.sim.state
	var oracle := session.oracle
	var lines := PackedStringArray()
	lines.append("seed %d   tick %d   %d ticks/s   %d fps   rain %.2f   kindness %d   tone %d" % [
		state.seed_value, state.tick, _ticks_last_second, Engine.get_frames_per_second(), state.rainfall,
		state.kindness, state.tone(),
	])
	for i: int in mini(state.tribe_count(), 12):
		lines.append("  %-12s %4d people   food %5.0f days   wood %4.0f   stone %4.0f" % [
			state.tribe_names[i], state.tribe_population[i], state.tribe_food[i] / maxf(state.tribe_population[i], 1.0),
			state.tribe_wood[i], state.tribe_stone[i],
		])
	lines.append("Oracle: %s   calls %d   cost $%.4f" % [oracle.provider.get_id(), oracle.calls, oracle.cost_usd])
	var offline := oracle.offline_reason()
	if offline:
		lines.append("  offline: " + offline)
	if state.prophecy:
		var prophecy := state.prophecy
		lines.append("  [%s %s %d by year %d] now %d" % [
			prophecy.metric, prophecy.op, prophecy.target, prophecy.deadline_year, Prophecy.measure(prophecy.metric, state),
		])
	var drama := session.drama
	lines.append("Drama: tension %.0f   target %.0f   next card in %d days   (%s)" % [
		drama.tension(), drama.target(), drama.days_until_next(), drama.pacing_hint(),
	])
	if oracle.last_response and not oracle.last_response.ok:
		lines.append("  last error: " + oracle.last_response.error.left(120))
	for event: Dictionary in state.events.slice(maxi(state.events.size() - 6, 0)):
		lines.append("  %s: %s" % [WorldState.date_text(int(event["tick"])), EventText.text(event)])
	return "\n".join(lines)
