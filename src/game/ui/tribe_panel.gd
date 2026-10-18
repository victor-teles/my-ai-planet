class_name TribePanel
extends PanelContainer
## One tribe at a glance. Life: its chief and people by age, what it needs, what it has stored,
## who does which work, what it has built (and is building), what it knows, how it gets on with
## its neighbors, and how its blood differs from the rest of the valley. Society: how it is ruled,
## who holds power, how free, watched and afraid its people are, its culture, laws and crises.

signal person_clicked(id: int)
signal tribe_clicked(tribe: String)
signal closed

const WIDTH := 360.0
const REFRESH_SECONDS := 0.5
const TABS: Array[String] = ["Life", "Society"]
const STAGES: Array[String] = ["infant", "child", "youth", "adult", "elder"]
const STAGE_WORDS := {"infant": "Babies", "child": "Children", "youth": "Youths", "adult": "Adults", "elder": "Elders"}
const FACTION_COLORS := {
	"ruler": Color(0.86, 0.62, 0.22), "council": Color(0.36, 0.64, 0.48), "priests": Color(0.58, 0.42, 0.74),
	"warriors": Color(0.80, 0.34, 0.27), "merchants": Color(0.30, 0.54, 0.78),
}
## measure -> [title, whether more is better, what it means]. Read from Society.metrics().
const MEASURES := {
	"freedom": ["Freedom", true, "How free people are to speak, move, marry and refuse."],
	"control": ["Control", false, "How watched and policed people are: the laws, the guards and officials on duty, and the eyes the age's machines give them."],
	"inequality": ["Inequality", false, "How unequally the adults' wealth is spread (a Gini coefficient)."],
	"fear": ["Fear", false, "How afraid people are of their rulers."],
	"legitimacy": ["Legitimacy", true, "Whether the people accept their rulers' right to rule."],
	"unrest": ["Unrest", false, "How angry people are. Past 55, they take to the streets."],
	"dystopia": ["Dystopia", false, "How far the tribe has slid toward a dystopia: watched, unfree, afraid and unequal, under laws built to keep it that way."],
}
## Culture axis -> [the word for -100, the word for +100].
const CULTURE_WORDS := {
	"hierarchy": ["equals", "ranks"], "piety": ["worldly", "devout"],
	"martial": ["peaceable", "warlike"], "openness": ["closed", "open"],
}
## Crisis type -> what to call it; stage -> how it stands.
const CRISIS_WORDS := {"protests": "Protests", "prophet": "A prophet", "succession": "A contested succession"}
const CRISIS_STAGES := {
	"protests": "crowds fill the streets", "tense": "an uneasy quiet after the crackdown",
	"preaching": "preaching a new truth", "contested": "a rival claims the heir's seat",
}
const DARK_INK := Color(0.58, 0.18, 0.30)

var _tribe := ""
var _tab := "Life"
var _signature := ""
var _since := 0.0
var _metrics: Dictionary = {} ## Society.metrics(), worked out with the signature
var _name := Label.new()
var _subtitle := Label.new()
var _tab_buttons: Dictionary = {} ## tab -> Button
var _scroll := ScrollContainer.new()
var _body := VBoxContainer.new()


func _init() -> void:
	theme = UiStyle.theme()
	theme_type_variation = "Card"
	add_theme_stylebox_override("panel", UiStyle.card_box(14))
	custom_minimum_size.x = WIDTH
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	add_child(column)
	UiStyle.inked(_name, UiStyle.TITLE + 2)
	_name.add_theme_font_override("font", UiStyle.font("display"))
	var close := UiStyle.close_button()
	close.pressed.connect(func() -> void: closed.emit())
	column.add_child(UiStyle.header(_name, close, "flag"))
	UiStyle.inked(_subtitle, UiStyle.SMALL + 1)
	_subtitle.add_theme_color_override("font_color", UiStyle.INK_SOFT)
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle.custom_minimum_size.x = WIDTH - 40.0
	column.add_child(_subtitle)
	column.add_child(UiStyle.tabs(TABS, _select_tab, _tab_buttons))
	(_tab_buttons[_tab] as Button).button_pressed = true
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 7)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_body)
	column.add_child(_scroll)


## Shows a tribe; "" hides the panel.
func show_tribe(state: WorldState, tribe: String) -> void:
	if tribe != _tribe:
		_scroll.scroll_vertical = 0
	_tribe = tribe
	visible = state.tribe_index(tribe) != -1
	_signature = ""
	if visible:
		_rebuild(state)


func current_tribe() -> String:
	return _tribe if visible else ""


## Scrolls the open tab to this many pixels from the top (for screenshots).
func scroll_to(pixels: int) -> void:
	_scroll.scroll_vertical = pixels


## Opens a tab by name: "Life" or "Society".
func select_tab(tab: String) -> void:
	if _tab_buttons.has(tab):
		_select_tab(tab)


func _select_tab(tab: String) -> void:
	_tab = tab
	(_tab_buttons[tab] as Button).button_pressed = true # the group lets go of the others
	_signature = ""
	_since = REFRESH_SECONDS
	_scroll.scroll_vertical = 0


func refresh(state: WorldState) -> void:
	if not visible:
		return
	_since += get_process_delta_time()
	if _since < REFRESH_SECONDS:
		return
	_since = 0.0
	var t := state.tribe_index(_tribe)
	if t == -1:
		visible = false
		return
	if _signature_of(state, t) != _signature:
		_rebuild(state)


func _signature_of(state: WorldState, t: int) -> String:
	if _tab == "Society":
		return _society_signature(state, t)
	var parts: Array = [_tribe, state.tribe_population[t], state.tribe_chiefs[t], roundi(state.tribe_food[t] / 50.0),
		roundi(state.tribe_wood[t] / 5.0), roundi(state.tribe_stone[t] / 5.0), state.tribe_knowledge[t].size(),
		state.tribe_plan[t], state.tribe_project[t], state.month(), state.relations.hash(), state.building_ids.size(),
		roundi(state.tribe_treasury[t]), roundi(state.tribe_metal[t])]
	var project := state.building_index(state.tribe_project[t])
	if project != -1:
		parts.append(state.building_progress[project] / 5)
	for job: String in state.person_jobs:
		parts.append(job.length())
	return str(parts.hash())


func _rebuild(state: WorldState) -> void:
	var t := state.tribe_index(_tribe)
	_signature = _signature_of(state, t)
	var keep_scroll := _scroll.scroll_vertical
	UiStyle.clear(_body)
	var members := state.people_of(_tribe)
	_name.text = "The %s" % _tribe
	_subtitle.text = "%d people  ·  founded in year %d  ·  they drink from %s" % [
		state.tribe_population[t], WorldState.year_of(state.tribe_founded[t]), state.water_names[state.tribe_water[t]],
	]
	if _tab == "Society":
		_society(state, t)
	else:
		_chief(state, t)
		_people(state, members)
		_needs(state, t)
		_stores(state, t)
		_jobs(state, members)
		_buildings(state, t)
		_knowledge(state, t)
		_neighbors(state)
		_blood(state, members)
	_scroll.set_deferred("scroll_vertical", keep_scroll)


func _chief(state: WorldState, t: int) -> void:
	var chief := state.chief_of(_tribe)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(UiStyle.chip("Chief", Color(0.98, 0.80, 0.42)))
	if chief == -1:
		row.add_child(UiStyle.label("none yet: the tribe is choosing", 14))
	else:
		var id := state.person_ids[chief]
		var link := UiStyle.link("%s, %d (%s)" % [People.full_name(state, chief), People.age(state, chief), state.person_traits[chief].replace("|", ", ")], 14)
		link.pressed.connect(func() -> void: person_clicked.emit(id))
		row.add_child(link)
	_body.add_child(row)


## People by stage of life as horizontal bars, women to the left of the line and men to the right.
func _people(state: WorldState, members: Array[int]) -> void:
	_body.add_child(UiStyle.section("PEOPLE  (women | men)"))
	var women := {}
	var men := {}
	var most := 1
	for p: int in members:
		var stage := People.stage(state, p)
		var table := women if People.is_female(state, p) else men
		table[stage] = int(table.get(stage, 0)) + 1
		most = maxi(most, int(table[stage]))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 3)
	for k: int in range(STAGES.size() - 1, -1, -1):
		var stage := STAGES[k]
		var label := UiStyle.label(String(STAGE_WORDS[stage]), UiStyle.SMALL + 1)
		label.custom_minimum_size.x = 66
		grid.add_child(label)
		var left := UiStyle.bar(float(women.get(stage, 0)) / most, 0.0, Color(0.85, 0.52, 0.58))
		left.fill_mode = ProgressBar.FILL_END_TO_BEGIN
		grid.add_child(left)
		grid.add_child(UiStyle.bar(float(men.get(stage, 0)) / most, 0.0, Color(0.48, 0.60, 0.85)))
		var counts := UiStyle.label("%d | %d" % [int(women.get(stage, 0)), int(men.get(stage, 0))], 12)
		counts.custom_minimum_size.x = 44
		grid.add_child(counts)
	_body.add_child(grid)
	var couples := 0
	var expecting := 0
	var sick := 0
	for p: int in members:
		if state.person_partners[p] != -1 and state.person_partners[p] > state.person_ids[p]:
			couples += 1
		if state.person_due[p] != -1:
			expecting += 1
		if state.person_sick[p] > 0:
			sick += 1
	_body.add_child(UiStyle.label("%d couples   ·   %d expecting   ·   %d sick" % [couples, expecting, sick], 13))


func _needs(state: WorldState, t: int) -> void:
	_body.add_child(UiStyle.section("NEEDS   ·   %s" % Needs.mood_word(Needs.mood(state, t)).to_upper()))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	for need: String in Needs.NAMES:
		var value := Needs.get_need(state, t, need)
		var label := UiStyle.label(need.capitalize(), UiStyle.SMALL + 1)
		label.custom_minimum_size.x = 66
		grid.add_child(label)
		grid.add_child(UiStyle.bar(value, 0.0))
		grid.add_child(UiStyle.label("%d%%" % roundi(value * 100.0), 12))
	_body.add_child(grid)


func _stores(state: WorldState, t: int) -> void:
	_body.add_child(UiStyle.section("STORES"))
	var days := state.tribe_food[t] / maxf(state.tribe_population[t], 1.0)
	var lines := PackedStringArray()
	lines.append("Food: %d days for everyone%s" % [roundi(days), "   (hungry!)" if state.tribe_hungry_days[t] > 0 else ""])
	lines.append("Wood %d   ·   Stone %d" % [roundi(state.tribe_wood[t]), roundi(state.tribe_stone[t])])
	lines.append("Tools %d%%   ·   Warm clothes %d%%   ·   Jars %d%%" % [roundi(state.tribe_tools[t] * 100.0), roundi(state.tribe_cloth[t] * 100.0), roundi(state.tribe_pots[t] * 100.0)])
	if state.age_of(t) >= 1 or state.tribe_treasury[t] >= 1.0 or state.tribe_metal[t] >= 1.0:
		lines.append("Treasury %d   ·   Metal %d" % [roundi(state.tribe_treasury[t]), roundi(state.tribe_metal[t])])
	_body.add_child(UiStyle.label("\n".join(lines), 13, true))


func _jobs(state: WorldState, members: Array[int]) -> void:
	var counts := {}
	var apprentices := {}
	var idle := 0
	for p: int in members:
		var job := state.person_jobs[p]
		if job.is_empty():
			if People.is_adult(state, p) and People.age(state, p) < People.RETIRE_AT:
				idle += 1
			continue
		if People.age(state, p) < People.ADULT_AT:
			apprentices[job] = int(apprentices.get(job, 0)) + 1
		else:
			counts[job] = int(counts.get(job, 0)) + 1
	_body.add_child(UiStyle.section("WORK"))
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 5)
	row.add_theme_constant_override("v_separation", 4)
	for job: String in Jobs.ORDER:
		var count := int(counts.get(job, 0))
		var young := int(apprentices.get(job, 0))
		if count + young == 0:
			continue
		var text := "%d %s" % [count, Jobs.DEFINITIONS[job]["plural"] if count != 1 else Jobs.name_of(job)]
		if young > 0:
			text += " +%d" % young
		var chip := UiStyle.chip(text, UiStyle.CHIP, 12)
		chip.tooltip_text = "%d at work, %d apprentices" % [count, young]
		row.add_child(chip)
	if idle > 0:
		row.add_child(UiStyle.chip("%d without work" % idle, Color(0.93, 0.89, 0.80), 12))
	_body.add_child(row)


func _buildings(state: WorldState, t: int) -> void:
	_body.add_child(UiStyle.section("BUILDINGS   ·   %d beds" % Needs.home_capacity(state, _tribe)))
	var built := {}
	var lines := PackedStringArray()
	for b: int in state.buildings_of(_tribe):
		var type := state.building_types[b]
		if type == "fire":
			continue
		if state.is_built(b):
			built[type] = int(built.get(type, 0)) + 1
		else:
			var work := int(Buildings.TYPES[type]["work"])
			lines.append("⚒ Building a %s: %d%%" % [Buildings.name_of(type), roundi(100.0 * state.building_progress[b] / maxf(work, 1.0))])
	var have := PackedStringArray()
	for type: String in Buildings.TYPES:
		if built.has(type):
			have.append("%d %s" % [built[type], Buildings.name_of(type) + ("s" if int(built[type]) > 1 else "")])
	_body.add_child(UiStyle.label(", ".join(have) if not have.is_empty() else "Only the fire.", 13, true))
	for line: String in lines:
		_body.add_child(UiStyle.label(line, 13, true))
	var plan := state.tribe_plan[t]
	if plan:
		var type := WorkSystem._plan_type(plan)
		var info: Dictionary = Buildings.TYPES[type]
		var needs := PackedStringArray()
		if float(info["wood"]) > state.tribe_wood[t]:
			needs.append("%d more wood" % ceili(float(info["wood"]) - state.tribe_wood[t]))
		if float(info["stone"]) > state.tribe_stone[t]:
			needs.append("%d more stone" % ceili(float(info["stone"]) - state.tribe_stone[t]))
		var what := "rebuild a tent as a hut" if plan.contains("@") else "build a %s" % Buildings.name_of(type)
		var label := UiStyle.label("Planned: %s%s" % [what, " (needs %s)" % " and ".join(needs) if not needs.is_empty() else ""], 13, true)
		label.add_theme_color_override("font_color", ToonMaterials.INK.lightened(0.3))
		_body.add_child(label)


func _knowledge(state: WorldState, t: int) -> void:
	_body.add_child(UiStyle.section("KNOWLEDGE"))
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 5)
	row.add_theme_constant_override("v_separation", 4)
	var open := Knowledge.discoverable(state.tribe_knowledge[t])
	for tech: String in Knowledge.ORDER:
		var known := state.knows(t, tech)
		var chip := UiStyle.chip(Knowledge.name_of(tech), Color(0.84, 0.92, 0.80) if known else Color(0.94, 0.91, 0.85), 12)
		if not known:
			chip.add_theme_color_override("font_color", ToonMaterials.INK.lightened(0.5 if tech not in open else 0.3))
		chip.tooltip_text = "%s: %s" % ["Known" if known else ("Could be discovered next" if tech in open else "Needs " + ", ".join((Knowledge.TECHS[tech]["requires"] as Array).map(func(r: String) -> String: return Knowledge.name_of(r)))), Knowledge.TECHS[tech]["unlocks"]]
		row.add_child(chip)
	_body.add_child(row)


func _neighbors(state: WorldState) -> void:
	var lines := PackedStringArray()
	for other: String in state.tribe_names:
		if other == _tribe:
			continue
		var value := state.relation(_tribe, other)
		lines.append("%s   %s (%+d)" % [other, WorldState.relation_word(value), value])
	if lines.is_empty():
		return
	_body.add_child(UiStyle.section("NEIGHBORS"))
	_body.add_child(UiStyle.label("\n".join(lines), 13, true))


## How this tribe's genes differ from the whole valley's.
func _blood(state: WorldState, members: Array[int]) -> void:
	var genomes: Array[PackedByteArray] = []
	for p: int in members:
		genomes.append(state.person_genomes[p])
	var tribe_stats := Genetics.pool_stats(genomes)
	var valley_stats := Genetics.pool_stats(state.person_genomes)
	var tribe_genes: Dictionary = tribe_stats["genes"]
	var valley_genes: Dictionary = valley_stats["genes"]
	_body.add_child(UiStyle.section("BLOOD   (this tribe vs the valley)"))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 3)
	for gene: String in Genetics.TRACKED:
		var label := UiStyle.label(String(Genetics.INFO[gene]["name"]), UiStyle.SMALL + 1)
		label.custom_minimum_size.x = 82
		grid.add_child(label)
		grid.add_child(UiStyle.bar(int(tribe_genes[gene]) / 100.0, 0.0, Color(0.50, 0.58, 0.85)))
		var difference := int(tribe_genes[gene]) - int(valley_genes[gene])
		var word := UiStyle.label("%d  (%+d)" % [int(tribe_genes[gene]), difference], 12)
		if absi(difference) >= 4:
			word.add_theme_color_override("font_color", Color(0.25, 0.45, 0.25) if difference > 0 else Color(0.60, 0.30, 0.25))
		grid.add_child(word)
	_body.add_child(grid)
	_body.add_child(UiStyle.label("Frail: %d   ·   carriers: %d" % [int(tribe_stats["frail"]), int(tribe_stats["carriers"])], 12))


# --- Society ------------------------------------------------------------------------

## The Society tab rebuilds when anything it shows has moved. Society.metrics() loops over the
## people, so it is worked out here (twice a second at most) and reused by the rebuild.
func _society_signature(state: WorldState, t: int) -> String:
	_metrics = Society.metrics(state, t)
	var parts: Array = [_tribe, _tab, _metrics, state.tribe_laws[t], state.tribe_power[t], state.tribe_culture[t],
		state.tribe_crisis[t], state.tribe_dynasty[t], state.tribe_overlord[t], state.tribe_chiefs[t],
		Society.vassals_of(state, _tribe), roundi(SocietySystem.reign_years(state, t)), state.destiny_progress, _assets_signature(state, t)]
	return str(parts.hash())


func _society(state: WorldState, t: int) -> void:
	var m := _metrics
	var top := Society.top_faction(state, t)
	var tip := "A government is named after its strongest faction, in the words of its age.\nStrongest: %s (power %d)." % [Society.FACTION_NAMES[top], Society.power(state, t, top)]
	var government := UiStyle.title("%s" % m["government"], UiStyle.LEAD + 2)
	government.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var rank_line := UiStyle.faint("%s  ·  %s" % [m["scale"], Knowledge.age_name(int(m["age"]))], UiStyle.SMALL + 1)
	for label: Label in [government, rank_line]:
		label.mouse_filter = Control.MOUSE_FILTER_PASS
		label.tooltip_text = tip
		_body.add_child(label)
	_rulers(state, t)
	_banner(state)
	_destiny_hint(state, t)
	_crisis(state, t)
	_factions(state, t, top)
	_measures(state, t)
	_classes(state, t)
	_culture(state, t)
	_laws(state, t)
	_slogans(state, t)
	_monuments(state)


## The ruler, their house and how long they've held the seat; whose vassal the tribe is, and its own.
func _rulers(state: WorldState, t: int) -> void:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	row.add_theme_constant_override("v_separation", 4)
	row.add_child(UiStyle.chip("Ruler", Color(0.98, 0.80, 0.42)))
	var ruler := state.chief_of(_tribe)
	if ruler == -1:
		row.add_child(UiStyle.label("the seat is empty", 14))
	else:
		var id := state.person_ids[ruler]
		var link := UiStyle.link(People.full_name(state, ruler), 14)
		link.tooltip_text = "%d years old, %s" % [People.age(state, ruler), state.person_traits[ruler].replace("|", ", ")]
		link.pressed.connect(func() -> void: person_clicked.emit(id))
		row.add_child(link)
		var years := floori(SocietySystem.reign_years(state, t))
		row.add_child(UiStyle.label("for %d year%s" % [years, "" if years == 1 else "s"] if years > 0 else "newly seated", 13))
	var house := Society.dynasty(state, t)
	if house:
		var chip := UiStyle.chip("House %s" % house, Color(0.93, 0.84, 0.95), 12)
		chip.tooltip_text = "Power is inherited: the eldest of house %s rules next." % house
		row.add_child(chip)
	_body.add_child(row)
	var overlord := state.tribe_overlord[t]
	if overlord:
		var lord := HBoxContainer.new()
		lord.add_theme_constant_override("separation", 6)
		var since := state.tribe_vassal_since[t]
		lord.add_child(UiStyle.label("Vassal of", 13))
		lord.add_child(_tribe_link(overlord))
		if since >= 0:
			lord.add_child(UiStyle.label("since year %d: pays tribute" % WorldState.year_of(since), 13))
		_body.add_child(lord)
	var vassals := Society.vassals_of(state, _tribe)
	if not vassals.is_empty():
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 6)
		flow.add_child(UiStyle.label("Vassals:", 13))
		for vassal: String in vassals:
			flow.add_child(_tribe_link(vassal))
		_body.add_child(flow)


func _tribe_link(tribe: String) -> LinkButton:
	var link := UiStyle.link("the %s" % tribe, 13)
	link.tooltip_text = "See the %s" % tribe
	link.pressed.connect(func() -> void: tribe_clicked.emit(tribe))
	return link


## The dark (or free) end this tribe is heading for, once its age makes one possible.
func _destiny_hint(state: WorldState, t: int) -> void:
	if not state.destiny.is_empty():
		return
	var age := state.age_of(t)
	var greatest := DestinySystem.greatest_realm(state) == t
	var progress := DestinySystem.progress(state)
	var words := PackedStringArray()
	var dark := false
	for kind: String in DestinySystem.conditions(state, t):
		if age < int(DestinySystem.KINDS[kind]["age"]):
			continue
		dark = dark or bool(DestinySystem.KINDS[kind]["dark"])
		var text := DestinySystem.name_of(kind)
		if greatest and progress.has(kind):
			text += " (%d of %d years)" % [int(progress[kind]), DestinySystem.HOLD_YEARS]
		words.append(text)
	if words.is_empty():
		return
	var label := UiStyle.label("Headed for: %s" % ", ".join(words), 14, true)
	label.add_theme_color_override("font_color", DARK_INK if dark else Color(0.20, 0.48, 0.30))
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	label.tooltip_text = "If the island's greatest realm stays like this for %d years, that is the island's destiny.%s" % [
		DestinySystem.HOLD_YEARS, "" if greatest else "\nThe %s isn't the greatest realm, so its years don't count yet." % _tribe]
	_body.add_child(label)


func _crisis(state: WorldState, t: int) -> void:
	var crisis: Dictionary = state.tribe_crisis[t]
	if crisis.is_empty():
		return
	var type := String(crisis.get("type", ""))
	var stage := String(crisis.get("stage", ""))
	@warning_ignore("integer_division")
	var months := (state.tick - int(crisis.get("since", state.tick))) / WorldState.DAYS_PER_MONTH
	var box := PanelContainer.new()
	var crisis_box := UiStyle.well_box()
	crisis_box.bg_color = Color(0.98, 0.86, 0.80)
	crisis_box.border_color = Color(UiStyle.DARK, 0.6)
	crisis_box.set_border_width_all(1)
	box.add_theme_stylebox_override("panel", crisis_box)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	box.add_child(column)
	var title := UiStyle.label("CRISIS   ·   %s: %s" % [CRISIS_WORDS.get(type, type.capitalize()), CRISIS_STAGES.get(stage, stage.replace("_", " "))], 13, true)
	title.add_theme_color_override("font_color", DARK_INK)
	column.add_child(title)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 5)
	row.add_child(UiStyle.label("%d month%s" % [months, "" if months == 1 else "s"] if months > 0 else "just begun", 12))
	for key: String in ["leader", "heir", "rival"]:
		var p := state.index_of(int(crisis.get(key, -1)))
		if p == -1:
			continue
		var id := state.person_ids[p]
		row.add_child(UiStyle.label("·  %s:" % ("led by" if key == "leader" else key), 12))
		var link := UiStyle.link(People.full_name(state, p), 12)
		link.pressed.connect(func() -> void: person_clicked.emit(id))
		row.add_child(link)
	column.add_child(row)
	_body.add_child(box)


func _factions(state: WorldState, t: int, top: String) -> void:
	_body.add_child(UiStyle.section("WHO HOLDS POWER"))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 3)
	for faction: String in Society.FACTIONS:
		var value := Society.power(state, t, faction)
		var label := UiStyle.label(String(Society.FACTION_NAMES[faction]).trim_prefix("the ").capitalize(), 13)
		label.custom_minimum_size.x = 92
		if faction == top and value >= 25:
			label.text += "  ★"
		grid.add_child(label)
		grid.add_child(UiStyle.bar(value / 100.0, 0.0, FACTION_COLORS[faction]))
		grid.add_child(UiStyle.label(str(value), 12))
	_body.add_child(grid)


func _measures(state: WorldState, t: int) -> void:
	_body.add_child(UiStyle.section("THE MEASURE OF IT"))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 3)
	for measure: String in MEASURES:
		var info: Array = MEASURES[measure]
		var value := int(_metrics[measure])
		var label := UiStyle.label(String(info[0]), 13)
		label.custom_minimum_size.x = 92
		label.mouse_filter = Control.MOUSE_FILTER_PASS
		label.tooltip_text = String(info[2])
		grid.add_child(label)
		var share := value / 100.0
		grid.add_child(UiStyle.bar(share, 0.0, UiStyle.need_color(share if info[1] else 1.0 - share)))
		grid.add_child(UiStyle.label(str(value), 12))
	_body.add_child(grid)
	if int(_metrics["dystopia"]) >= 25:
		var kind := UiStyle.label("Sliding toward a %s dystopia." % Society.dystopia_kind(state, t), 13, true)
		kind.add_theme_color_override("font_color", DARK_INK)
		_body.add_child(kind)


func _classes(state: WorldState, t: int) -> void:
	var m := _metrics
	var adults := Society.adults_of(state, t).size()
	var parts := PackedStringArray()
	parts.append("%d noble%s" % [int(m["nobles"]), "" if int(m["nobles"]) == 1 else "s"])
	parts.append("%d bonded" % int(m["bonded"]))
	parts.append("%d in custody" % int(m["detained"]))
	parts.append("%d dissident%s of %d adults" % [int(m["dissidents"]), "" if int(m["dissidents"]) == 1 else "s", adults])
	_body.add_child(UiStyle.section("CLASSES"))
	var label := UiStyle.label("   ·   ".join(parts), 13, true)
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	label.tooltip_text = "Nobles: the ruling house and the richest families, where there are ranks.\nBonded: working off debts, under bonded labor.\nDissidents: adults whose loyalty has fallen below %d." % Society.DISSENT_AT
	_body.add_child(label)


## The four axes as two-sided bars: the word on the side the tribe leans to is darker.
func _culture(state: WorldState, t: int) -> void:
	_body.add_child(UiStyle.section("CULTURE"))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 3)
	for axis: String in Society.CULTURE_AXES:
		var value := int(state.tribe_culture[t].get(axis, 0))
		var words: Array = CULTURE_WORDS[axis]
		var tip := "%s %+d: %s" % [axis.capitalize(), value, "even" if absi(value) < 10 else "leans %s" % words[1 if value > 0 else 0]]
		var left := UiStyle.label(String(words[0]), UiStyle.SMALL + 1)
		left.custom_minimum_size.x = 72
		left.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		var right := UiStyle.label(String(words[1]), UiStyle.SMALL + 1)
		right.custom_minimum_size.x = 60
		for side: Label in [left, right]:
			side.mouse_filter = Control.MOUSE_FILTER_PASS
			side.tooltip_text = tip
		if absi(value) < 10:
			left.add_theme_color_override("font_color", ToonMaterials.INK.lightened(0.2))
			right.add_theme_color_override("font_color", ToonMaterials.INK.lightened(0.2))
		else:
			(left if value > 0 else right).add_theme_color_override("font_color", ToonMaterials.INK.lightened(0.5))
		grid.add_child(left)
		var minus := UiStyle.bar(maxf(-value, 0.0) / 100.0, 0.0, Color(0.55, 0.62, 0.80))
		minus.fill_mode = ProgressBar.FILL_END_TO_BEGIN
		minus.tooltip_text = tip
		grid.add_child(minus)
		var plus := UiStyle.bar(maxf(value, 0.0) / 100.0, 0.0, Color(0.80, 0.58, 0.40))
		plus.tooltip_text = tip
		grid.add_child(plus)
		grid.add_child(right)
	_body.add_child(grid)


## The laws in force, oldest first, with the year each passed; hover for what it does.
func _laws(state: WorldState, t: int) -> void:
	var passed_at: Dictionary = state.tribe_laws[t]
	var laws := Society.laws_of(state, t)
	laws.sort_custom(func(a: String, b: String) -> bool: return int(passed_at[a]) < int(passed_at[b]))
	_body.add_child(UiStyle.section("LAWS   ·   %d IN FORCE" % laws.size()))
	if laws.is_empty():
		_body.add_child(UiStyle.label("No laws yet: only custom.", 13))
		return
	var dark := 0
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 2)
	for law: String in laws:
		var info: Dictionary = Laws.LAWS[law]
		var passed := WorldState.year_of(int(state.tribe_laws[t][law]))
		var name := UiStyle.label(Laws.name_of(law), 14)
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name.mouse_filter = Control.MOUSE_FILTER_PASS
		name.tooltip_text = "%s\nPushed by %s. Passed in year %d." % [info["description"], Society.FACTION_NAMES.get(info["faction"], info["faction"]), passed]
		if Laws.is_dystopian(law):
			dark += 1
			name.text = "▼ " + name.text
			name.add_theme_color_override("font_color", DARK_INK)
			name.tooltip_text += "\nA dark law: it pulls the tribe toward a dystopia."
		grid.add_child(name)
		var year := UiStyle.label("year %d" % passed, 12)
		year.add_theme_color_override("font_color", ToonMaterials.INK.lightened(0.4))
		grid.add_child(year)
	_body.add_child(grid)
	if dark > 0:
		var note := UiStyle.label("▼ dark laws, that pull toward a dystopia. Hover a law for what it does.", 11, true)
		note.add_theme_color_override("font_color", ToonMaterials.INK.lightened(0.4))
		_body.add_child(note)


# --- Banner, slogans and monuments (AI-authored, or offline until written) --------

## What the stored specs this tab shows were written for, so the tab rebuilds when a new one lands.
func _assets_signature(state: WorldState, t: int) -> String:
	var keys: Array[String] = [AssetBook.key("heraldry", _tribe)]
	for law: String in Society.laws_of(state, t):
		keys.append(AssetBook.key("poster", "%s|%s" % [_tribe, law]))
	for b: int in state.buildings_of(_tribe):
		if state.building_types[b] in MonumentKind.TYPES:
			keys.append(AssetBook.key("monument", str(state.building_ids[b])))
	var parts := PackedStringArray()
	for key: String in keys:
		var entry: Dictionary = state.assets.get(key, {})
		parts.append("%s@%s" % [entry.get("signature", ""), entry.get("tick", "")])
	return ",".join(parts)


## The banner of whoever holds power, and its motto.
func _banner(state: WorldState) -> void:
	var spec := AssetDirector.spec_or_offline(state, "heraldry", _tribe)
	if spec.is_empty():
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiStyle.SPACE_3)
	var picture := TextureRect.new()
	picture.texture = EmblemArt.banner_texture(spec)
	picture.custom_minimum_size = Vector2(40.0, 50.0)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(picture)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	words.add_child(UiStyle.quote("“%s”" % spec["motto"], UiStyle.LEAD))
	var t := state.tribe_index(_tribe)
	var holder := HeraldryKind.holder_of(state, t)
	var whose := "The banner of the people"
	if holder.begins_with("house "):
		whose = "The banner of house %s" % state.tribe_dynasty[t]
	elif holder.begins_with("ruler ") and state.chief_of(_tribe) != -1:
		whose = "The banner of %s's rule" % state.person_names[state.chief_of(_tribe)]
	words.add_child(UiStyle.faint(whose, UiStyle.SMALL))
	row.add_child(words)
	var source := AssetBook.source(state, "heraldry", _tribe)
	row.tooltip_text = "Its banner shows a %s. %s" % [spec["charge"], "Drawn by the AI (%s)." % source if source and source != "offline" else "Drawn without AI."]
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	_body.add_child(row)


## The slogans on the walls, one for every dark law in force.
func _slogans(state: WorldState, t: int) -> void:
	var lines: Array[Label] = []
	for law: String in Society.laws_of(state, t):
		if not Laws.is_dystopian(law):
			continue
		var spec := AssetDirector.spec_or_offline(state, "poster", "%s|%s" % [_tribe, law])
		if spec.is_empty():
			continue
		var line := UiStyle.quote("“%s”" % spec["slogan"], 13)
		line.tooltip_text = "Posted for %s." % Laws.name_of(law).to_lower()
		line.mouse_filter = Control.MOUSE_FILTER_PASS
		lines.append(line)
	if lines.is_empty():
		return
	_body.add_child(UiStyle.section("ON THE WALLS"))
	for line: Label in lines:
		_body.add_child(line)


## What is carved on the statues and over the temple doors.
func _monuments(state: WorldState) -> void:
	var lines: Array[Label] = []
	for b: int in state.buildings_of(_tribe):
		var type := state.building_types[b]
		if type not in MonumentKind.TYPES or not state.is_built(b):
			continue
		var spec := AssetDirector.spec_or_offline(state, "monument", str(state.building_ids[b]))
		if spec.is_empty():
			continue
		var what := "Statue" if type == "statue" else "Temple of the %s" % MonumentKind.ICON_NAMES.get(spec["iconography"], "Sky")
		var line := UiStyle.label("%s:  “%s”" % [what, spec["inscription"]], 13, true)
		line.tooltip_text = "Raised in year %d." % WorldState.year_of(state.building_done[b])
		line.mouse_filter = Control.MOUSE_FILTER_PASS
		lines.append(line)
	if lines.is_empty():
		return
	_body.add_child(UiStyle.section("MONUMENTS"))
	for line: Label in lines:
		_body.add_child(line)
