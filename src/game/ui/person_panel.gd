class_name PersonPanel
extends PanelContainer
## Everything about one person, living or remembered: how they are, what they're doing and their
## place in society, by class, savings, loyalty and custody (Life), their family tree (Family),
## their genes and where each copy came from (DNA), who they love and loathe (Bonds), and their
## life story (Story). Names are links to the people they name.

signal person_clicked(id: int)
signal tribe_clicked(tribe: String)
signal closed
signal follow_toggled(on: bool)

const WIDTH := 360.0
const TABS: Array[String] = ["Life", "Family", "DNA", "Bonds", "Story"]
const REFRESH_SECONDS := 0.25
const STORY_ICONS := {
	"birth": "✶", "death": "✝", "love": "♥", "work": "⚒", "discovery": "✦", "chief": "⚑",
	"grief": "❦", "family": "♡", "home": "⌂", "growth": "❀", "dna": "≋", "health": "✚",
	"conflict": "⚔", "tribe": "⚑", "society": "⚖",
}
## Story kinds drawn in their own color (the rest in faded ink).
const STORY_COLORS := {"society": Color(0.62, 0.22, 0.42), "conflict": Color(0.80, 0.30, 0.25)}
const CLASS_COLORS := {"noble": Color(0.93, 0.84, 0.95), "commoner": Color(0.93, 0.89, 0.80), "bonded": Color(0.80, 0.78, 0.74)}
const GENE_COLORS := {
	"pigment": [Color(0.97, 0.84, 0.72), Color(0.33, 0.21, 0.15)],
	"hair": [Color(0.10, 0.08, 0.08), Color(0.92, 0.82, 0.56)],
}
const LOW_ALLELE := Color(0.84, 0.86, 0.95)
const HIGH_ALLELE := Color(0.30, 0.22, 0.55)

var _id := -1
var _tab := "Life"
var _thought := ""
var _signature := ""
var _since := 0.0
var _name := Label.new()
var _role := Label.new()
var _tribe_link: LinkButton
var _chief_chip: Label
var _class_chip: Label
var _custody_chip: Label
var _follow := CheckButton.new()
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

	var header := HBoxContainer.new()
	UiStyle.inked(_name, UiStyle.TITLE + 2)
	_name.add_theme_font_override("font", UiStyle.font("display"))
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.add_child(_name)
	var close := UiStyle.close_button()
	close.pressed.connect(func() -> void: closed.emit())
	header.add_child(close)
	column.add_child(header)

	UiStyle.inked(_role, UiStyle.SMALL + 1)
	_role.add_theme_color_override("font_color", UiStyle.INK_SOFT)
	_role.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_role.custom_minimum_size.x = WIDTH - 40.0
	column.add_child(_role)

	var badges := HBoxContainer.new()
	badges.add_theme_constant_override("separation", 8)
	_tribe_link = UiStyle.link("", 14)
	_tribe_link.tooltip_text = "See the tribe"
	_tribe_link.pressed.connect(func() -> void: tribe_clicked.emit(_tribe_link.get_meta("tribe", "")))
	badges.add_child(_tribe_link)
	_chief_chip = UiStyle.chip("Chief", Color(0.98, 0.80, 0.42))
	badges.add_child(_chief_chip)
	_class_chip = UiStyle.chip("Commoner", UiStyle.CHIP, 12)
	badges.add_child(_class_chip)
	_custody_chip = UiStyle.chip("In custody", Color(0.98, 0.78, 0.72), 12)
	badges.add_child(_custody_chip)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	badges.add_child(spacer)
	_follow.text = "Follow"
	_follow.focus_mode = Control.FOCUS_NONE
	_follow.tooltip_text = "Keep the camera on this person   [F]"
	_follow.add_theme_font_size_override("font_size", 13)
	for color_name: String in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		_follow.add_theme_color_override(color_name, ToonMaterials.INK)
	_follow.toggled.connect(func(on: bool) -> void: follow_toggled.emit(on))
	badges.add_child(_follow)
	column.add_child(badges)

	column.add_child(UiStyle.tabs(TABS, _select_tab, _tab_buttons))
	(_tab_buttons["Life"] as Button).button_pressed = true

	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 7)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_body)
	column.add_child(_scroll)


## Shows someone (alive or dead). -1 hides the panel.
func show_person(state: WorldState, id: int) -> void:
	if id != _id:
		_thought = ""
		_scroll.scroll_vertical = 0
		_follow.set_pressed_no_signal(false)
	_id = id
	visible = id != -1 and (state.is_alive(id) or state.dead.has(str(id)))
	_signature = ""
	if visible:
		_rebuild(state)


func current_id() -> int:
	return _id if visible else -1


func set_thought(text: String) -> void:
	_thought = text


## Call every frame: keeps the panel placed and rebuilds the open tab a few times a second
## when what it shows has changed.
func refresh(state: WorldState) -> void:
	if not visible:
		return
	_since += get_process_delta_time()
	if _since < REFRESH_SECONDS:
		return
	_since = 0.0
	if not state.is_alive(_id) and not state.dead.has(str(_id)):
		visible = false
		return
	var signature := _signature_of(state)
	if signature != _signature:
		_rebuild(state)


## Opens a tab by name: "Life", "Family", "DNA", "Bonds" or "Story".
func select_tab(tab: String) -> void:
	if _tab_buttons.has(tab):
		_select_tab(tab)


func _select_tab(tab: String) -> void:
	_tab = tab
	(_tab_buttons[tab] as Button).button_pressed = true # the group lets go of the others
	_signature = ""
	_since = REFRESH_SECONDS
	_scroll.scroll_vertical = 0


## A cheap fingerprint of everything the header and open tab show, so they rebuild only on change.
func _signature_of(state: WorldState) -> String:
	var p := state.index_of(_id)
	var story: Array = state.lives.get(str(_id), [])
	var parts: Array = [_id, _tab, p != -1, story.size(), _thought]
	if p != -1:
		parts.append_array([People.age(state, p), state.person_jobs[p], state.person_partners[p], state.person_tribes[p],
			state.tribe_chiefs[state.tribe_index(state.person_tribes[p])], state.person_traits[p], state.person_status[p],
			state.person_detained[p]])
		match _tab:
			"Life":
				var t := state.tribe_index(state.person_tribes[p])
				parts.append_array([state.person_health[p], state.person_mood[p], state.person_sick[p] > 0, state.person_due[p],
					state.person_grief[p], state.person_homes[p], People.activity(state, p), state.person_wealth[p], state.person_loyalty[p]])
				for need: String in Needs.NAMES:
					parts.append(snappedf(Needs.get_need(state, t, need), 0.05))
				var skill := Jobs.skill_index(state.person_jobs[p])
				if skill != -1:
					parts.append(state.person_skills[p][skill])
			"Family":
				parts.append_array([state.total_population(), state.dead.size()])
			"Bonds":
				for entry: Dictionary in People.strongest_bonds(state, _id, 12):
					parts.append_array([entry["id"], entry["value"], entry["love"]])
	return str(parts)


func _rebuild(state: WorldState) -> void:
	_signature = _signature_of(state)
	var keep_scroll := _scroll.scroll_vertical
	UiStyle.clear(_body)
	_header(state)
	match _tab:
		"Life":
			_life(state)
		"Family":
			_family(state)
		"DNA":
			_dna(state)
		"Bonds":
			_bonds(state)
		"Story":
			_story(state)
	_scroll.set_deferred("scroll_vertical", keep_scroll)


# --- Header -------------------------------------------------------------------------

func _header(state: WorldState) -> void:
	var p := state.index_of(_id)
	if p != -1:
		var tribe := state.person_tribes[p]
		var t := state.tribe_index(tribe)
		_name.text = People.full_name(state, p)
		var sex := "woman" if People.is_female(state, p) else "man"
		var role := People.role(state, p).capitalize()
		_role.text = "%s   ·   %s, %d   ·   generation %d" % [role, sex, People.age(state, p), state.person_generations[p]]
		_tribe_link.text = "of the %s" % tribe
		_tribe_link.set_meta("tribe", tribe)
		_tribe_link.visible = true
		_chief_chip.visible = t != -1 and state.tribe_chiefs[t] == _id
		var rank := Society.class_of(state, p)
		_class_chip.text = rank.capitalize()
		_class_chip.add_theme_stylebox_override("normal", UiStyle.chip_box(CLASS_COLORS.get(rank, UiStyle.CHIP)))
		_class_chip.tooltip_text = String({
			"noble": "Of the ruling house or the richest families. Their children are born noble.",
			"bonded": "Working off a debt they couldn't pay, and their children after them.",
		}.get(rank, "Free, neither noble nor bonded."))
		_class_chip.visible = People.is_adult(state, p) or rank != "commoner"
		var months := state.person_detained[p]
		_custody_chip.visible = months > 0
		_custody_chip.text = "In custody"
		_custody_chip.tooltip_text = "Held by the rulers: %d month%s left." % [months, "" if months == 1 else "s"]
		_follow.visible = true
		return
	var record: Dictionary = state.dead.get(str(_id), {})
	_name.text = "† %s %s" % [record.get("name", "?"), record.get("family", "")]
	var died := WorldState.year_of(int(record.get("died", 0)))
	_role.text = "%s – year %d   ·   %s at %d   ·   generation %d" % [
		_born_text(int(record.get("born", 0))), died, death_phrase(String(record.get("cause", ""))),
		WorldState.year_of(int(record.get("died", 0)) - int(record.get("born", 0))), int(record.get("generation", 0)),
	]
	var tribe_name := String(record.get("tribe", ""))
	_tribe_link.text = "of the %s" % tribe_name
	_tribe_link.set_meta("tribe", tribe_name)
	_tribe_link.visible = state.tribe_index(tribe_name) != -1
	_chief_chip.visible = false
	_class_chip.visible = false
	_custody_chip.visible = false
	_follow.visible = false
	_follow.set_pressed_no_signal(false)


## "died of old age", "died giving birth", "fell in war"...
static func death_phrase(cause: String) -> String:
	match cause:
		"childbirth":
			return "died giving birth"
		"war":
			return "fell in war"
		"accident":
			return "died in an accident"
		"a fight":
			return "was killed in a fight"
		"":
			return "died"
	return "died of %s" % cause


func _born_text(born: int) -> String:
	return "Year %d" % WorldState.year_of(born) if born >= 0 else "Before the valley"


# --- Life ---------------------------------------------------------------------------

func _life(state: WorldState) -> void:
	var p := state.index_of(_id)
	if p == -1:
		var record: Dictionary = state.dead.get(str(_id), {})
		var job := String(record.get("job", ""))
		var line := "%s rests now. %s lived %d years%s, and %s." % [
			record.get("name", "They"), "She" if String(record.get("sex", "")) == "f" else "He",
			WorldState.year_of(int(record.get("died", 0)) - int(record.get("born", 0))),
			" as a %s" % Jobs.name_of(job) if job else "", death_phrase(String(record.get("cause", ""))),
		]
		_body.add_child(UiStyle.label(line, 15, true))
		var traits := String(record.get("traits", "")).split("|", false)
		if not traits.is_empty():
			_body.add_child(UiStyle.section("THEY WERE"))
			_body.add_child(_trait_chips(traits))
		var kids := People.children_of(state, _id)
		if not kids.is_empty():
			var alive := kids.filter(func(k: int) -> bool: return state.is_alive(k)).size()
			_body.add_child(UiStyle.label("Left %d child%s, %d still living." % [kids.size(), "" if kids.size() == 1 else "ren", alive], 14, true))
		return
	var t := state.tribe_index(state.person_tribes[p])
	var doing := People.activity(state, p)
	var job := state.person_jobs[p]
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 4)
	_bar_row(grid, "Health", state.person_health[p] / 100.0, "%d" % state.person_health[p])
	_bar_row(grid, "Mood", state.person_mood[p] / 100.0, _mood_word(state.person_mood[p]))
	var skill := Jobs.skill_index(job)
	if skill != -1:
		var level := state.person_skills[p][skill]
		_bar_row(grid, "Skill", level / 100.0, "%d" % level, Color(0.45, 0.55, 0.80))
	if People.is_adult(state, p):
		var loyalty := state.person_loyalty[p]
		_bar_row(grid, "Loyalty", loyalty / 100.0, _loyalty_word(loyalty))
		var richer := _richer_than(state, p)
		_bar_row(grid, "Wealth", richer, "%d saved" % state.person_wealth[p], Color(0.86, 0.68, 0.30))
		var wealth_bar := grid.get_child(grid.get_child_count() - 2) as Control
		wealth_bar.tooltip_text = "Richer than %d%% of the %s's adults. Savings are counted in days of a laborer's keep." % [roundi(richer * 100.0), state.person_tribes[p]]
	_body.add_child(grid)

	var now := "Doing: %s" % doing
	if job:
		now += " (%s)" % Jobs.name_of(job)
	_body.add_child(UiStyle.label(now, 14, true))
	for note: String in _notes(state, p):
		var label := UiStyle.label(note, 13, true)
		label.add_theme_color_override("font_color", Color(0.55, 0.28, 0.25))
		_body.add_child(label)

	if _thought:
		var thought := UiStyle.quote("“%s”" % _thought, UiStyle.BODY + 1)
		var box := PanelContainer.new()
		box.theme_type_variation = "Well"
		box.tooltip_text = "What they are thinking"
		box.add_child(thought)
		_body.add_child(box)

	_body.add_child(UiStyle.section("PERSONALITY"))
	var traits := People.traits_of(state, p)
	if traits.is_empty():
		_body.add_child(UiStyle.label("Too young to know.", 13))
	else:
		_body.add_child(_trait_chips(traits))

	var skills := _top_skills(state, p, skill)
	if not skills.is_empty():
		_body.add_child(UiStyle.section("ALSO KNOWS"))
		_body.add_child(UiStyle.label(", ".join(skills), 13, true))

	_body.add_child(UiStyle.section("THE %s NEED" % state.person_tribes[p].to_upper()))
	var needs := GridContainer.new()
	needs.columns = 3
	needs.add_theme_constant_override("h_separation", 10)
	for need: String in Needs.NAMES:
		var value := Needs.get_need(state, t, need)
		_bar_row(needs, need.capitalize(), value, "%d%%" % roundi(value * 100.0))
	_body.add_child(needs)


func _notes(state: WorldState, p: int) -> Array[String]:
	var notes: Array[String] = []
	if state.person_detained[p] > 0:
		var months := state.person_detained[p]
		notes.append("In custody (%d month%s left)." % [months, "" if months == 1 else "s"])
	elif Society.is_dissident(state, p):
		notes.append("A dissident: they have turned against the rulers.")
	if state.person_due[p] != -1:
		notes.append("Expecting a child, due in about %d days." % maxi(state.person_due[p] - state.tick, 0))
	if state.person_sick[p] > 0:
		notes.append("Sick with a fever (%d days left)." % state.person_sick[p])
	if state.person_grief[p] > 0:
		notes.append("In mourning.")
	if state.person_homes[p] == -1:
		notes.append("Sleeps under the sky: no home.")
	else:
		var b := state.building_index(state.person_homes[p])
		if b != -1:
			notes.append("Lives in a %s with %d others." % [Buildings.name_of(state.building_types[b]), state.residents(state.person_homes[p]) - 1])
	if Genetics.is_frail(state.person_genomes[p]):
		notes.append("Frail from birth.")
	return notes


func _top_skills(state: WorldState, p: int, except: int) -> Array[String]:
	var found: Array[String] = []
	for s: int in Jobs.SKILLS.size():
		if s != except and state.person_skills[p][s] >= 15:
			found.append("%s %d" % [Jobs.SKILLS[s], state.person_skills[p][s]])
	return found


func _trait_chips(traits: PackedStringArray) -> Control:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	row.add_theme_constant_override("v_separation", 4)
	for trait_id: String in traits:
		var chip := UiStyle.chip(trait_id.capitalize())
		if People.TRAITS.has(trait_id):
			chip.tooltip_text = "As chief: " + String(People.TRAITS[trait_id]["description"])
		row.add_child(chip)
	return row


func _bar_row(grid: GridContainer, title: String, value: float, word: String, color: Color = Color.TRANSPARENT) -> void:
	var label := UiStyle.label(title, UiStyle.SMALL + 1)
	label.custom_minimum_size.x = 60
	grid.add_child(label)
	grid.add_child(UiStyle.bar(value, 0.0, color))
	var said := UiStyle.label(word, UiStyle.SMALL)
	said.add_theme_color_override("font_color", UiStyle.INK_SOFT)
	said.custom_minimum_size.x = 64
	grid.add_child(said)


func _loyalty_word(loyalty: int) -> String:
	if loyalty < Society.DISSENT_AT:
		return "dissident"
	if loyalty < 45:
		return "wavering"
	if loyalty < 75:
		return "loyal"
	return "devoted"


## The share of their tribe's adults this person is richer than, 0 to 1.
func _richer_than(state: WorldState, p: int) -> float:
	var adults := Society.adults_of(state, state.tribe_index(state.person_tribes[p]))
	if adults.size() < 2:
		return 0.5
	var poorer := 0
	for other: int in adults:
		if state.person_wealth[other] < state.person_wealth[p]:
			poorer += 1
	return poorer / float(adults.size() - 1)


func _mood_word(mood: int) -> String:
	if mood < 25:
		return "miserable"
	if mood < 45:
		return "low"
	if mood < 65:
		return "fine"
	if mood < 82:
		return "happy"
	return "joyful"


# --- Family -------------------------------------------------------------------------

func _family(state: WorldState) -> void:
	var parents := People.parents_of(state, _id)
	_people_section(state, "PARENTS", parents.filter(func(id: int) -> bool: return id != -1), "One of the first people: no parents remembered.")
	var partner := _partner_of(state, _id)
	if partner != -1:
		_people_section(state, "PARTNER", [partner], "")
	_people_section(state, "CHILDREN", People.children_of(state, _id), "No children.")
	_people_section(state, "BROTHERS AND SISTERS", _siblings(state, _id, parents), "None.")
	var grandparents: Array = []
	for parent: int in parents:
		if parent != -1:
			for grandparent: int in People.parents_of(state, parent):
				if grandparent != -1 and _known(state, grandparent):
					grandparents.append(grandparent)
	if not grandparents.is_empty():
		_people_section(state, "GRANDPARENTS", grandparents, "")
	var grandchildren: Array = []
	for child: int in People.children_of(state, _id):
		grandchildren.append_array(People.children_of(state, child))
	if not grandchildren.is_empty():
		_people_section(state, "GRANDCHILDREN", grandchildren, "")


func _people_section(state: WorldState, title: String, ids: Array, empty: String) -> void:
	_body.add_child(UiStyle.section(title))
	var shown := 0
	for id: int in ids:
		if not _known(state, id):
			continue
		_body.add_child(_person_link(state, id))
		shown += 1
	if shown == 0:
		var label := UiStyle.label(empty if empty else "Forgotten.", 13)
		label.add_theme_color_override("font_color", ToonMaterials.INK.lightened(0.4))
		_body.add_child(label)


func _known(state: WorldState, id: int) -> bool:
	return id != -1 and (state.is_alive(id) or state.dead.has(str(id)))


## "Mirra Oruvan, 34, healer" or "† Kael Oruvan (year 3–58, old age)" as a link.
func _person_link(state: WorldState, id: int) -> Control:
	var p := state.index_of(id)
	var text := ""
	if p != -1:
		text = "%s, %d, %s" % [People.full_name(state, p), People.age(state, p), People.role(state, p)]
		if state.person_tribes[p] != _tribe_of(state, _id):
			text += " (the %s)" % state.person_tribes[p]
	else:
		var record: Dictionary = state.dead[str(id)]
		text = "† %s %s (%s–%d, %s)" % [record["name"], record["family"], _born_text(int(record["born"])).trim_prefix("Year ").to_lower(), WorldState.year_of(int(record["died"])), record["cause"]]
	var link := UiStyle.link(text, 14)
	link.pressed.connect(func() -> void: person_clicked.emit(id))
	if p == -1:
		link.add_theme_color_override("font_color", ToonMaterials.INK.lightened(0.35))
	return link


func _tribe_of(state: WorldState, id: int) -> String:
	var p := state.index_of(id)
	if p != -1:
		return state.person_tribes[p]
	return String((state.dead.get(str(id), {}) as Dictionary).get("tribe", ""))


func _partner_of(state: WorldState, id: int) -> int:
	var p := state.index_of(id)
	if p != -1:
		return state.person_partners[p]
	return int((state.dead.get(str(id), {}) as Dictionary).get("partner", -1))


## Brothers and sisters, living or remembered, oldest first.
func _siblings(state: WorldState, id: int, parents: Array[int]) -> Array:
	var found: Array = []
	for parent: int in parents:
		if parent == -1:
			continue
		for child: int in People.children_of(state, parent):
			if child != id and child not in found:
				found.append(child)
	return found


# --- DNA ----------------------------------------------------------------------------

func _dna(state: WorldState) -> void:
	var genome := _genome(state)
	if genome.size() < Genetics.GENES.size() * 2:
		_body.add_child(UiStyle.label("Their blood is forgotten.", 14))
		return
	var parents := People.parents_of(state, _id)
	var founder := parents[0] == -1 and parents[1] == -1
	var explain := "Two copies of every gene: one from the mother (left), one from the father (right). What shows is their average, except eye shape and frailty, which need both copies." if not founder \
		else "One of the first people: two copies of every gene, from ancestors nobody remembers."
	var intro := UiStyle.label(explain, 12, true)
	intro.add_theme_color_override("font_color", ToonMaterials.INK.lightened(0.3))
	_body.add_child(intro)
	var notable := Genetics.notable(genome)
	if not notable.is_empty():
		var row := HFlowContainer.new()
		row.add_theme_constant_override("h_separation", 6)
		row.add_theme_constant_override("v_separation", 4)
		for word: String in notable:
			row.add_child(UiStyle.chip(word, Color(0.86, 0.90, 0.98), 12))
		_body.add_child(row)
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 7)
	grid.add_theme_constant_override("v_separation", 5)
	for g: int in Genetics.GENES.size():
		var gene := Genetics.GENES[g]
		if gene == "frailty":
			continue
		var info: Dictionary = Genetics.INFO[gene]
		var name := UiStyle.label(String(info["name"]), UiStyle.SMALL + 1)
		name.custom_minimum_size.x = 74
		grid.add_child(name)
		grid.add_child(_allele(gene, genome[g * 2], "From the mother" if not founder else "First copy"))
		grid.add_child(_allele(gene, genome[g * 2 + 1], "From the father" if not founder else "Second copy"))
		var value := Genetics.express(genome, gene)
		var word := Genetics.word(genome, gene)
		if gene == "eyes":
			var copies := int(genome[g * 2] >= Genetics.RECESSIVE_AT) + int(genome[g * 2 + 1] >= Genetics.RECESSIVE_AT)
			value = 1.0 if copies == 2 else 0.0
			word = "narrow (2 of 2)" if copies == 2 else "round (%d of 2)" % copies
		grid.add_child(UiStyle.bar(value, 0.0, Color(0.50, 0.58, 0.85)))
		grid.add_child(_clipped(word, 12, 84.0))
	_body.add_child(grid)
	_body.add_child(UiStyle.section("INHERITED FRAILTY"))
	var frailty: String = ["Healthy: no frailty allele.", "Carrier: one frailty allele, no effect. Their children may be frail if the other parent carries it too.", "Frail: two frailty alleles. Weaker health and a shorter life."][Genetics.frailty_copies(genome)]
	_body.add_child(UiStyle.label(frailty, 13, true))
	var story: Array = state.lives.get(str(_id), [])
	var mutations: Array[String] = []
	for entry: Dictionary in story:
		if String(entry.get("kind", "")) == "dna":
			mutations.append(String(entry["text"]))
	if not mutations.is_empty():
		_body.add_child(UiStyle.section("CHANGES IN THE BLOOD"))
		for line: String in mutations:
			_body.add_child(UiStyle.label("≋  " + line, 13, true))


func _genome(state: WorldState) -> PackedByteArray:
	var p := state.index_of(_id)
	if p != -1:
		return state.person_genomes[p]
	var record: Dictionary = state.dead.get(str(_id), {})
	return Genetics.from_hex(String(record.get("genome", "")))


## One copy of a gene as a colored square: pale to deep, or skin and hair colors for those genes.
func _allele(gene: String, value: int, origin: String) -> Control:
	var low := LOW_ALLELE
	var high := HIGH_ALLELE
	if GENE_COLORS.has(gene):
		var pair: Array = GENE_COLORS[gene]
		low = pair[0]
		high = pair[1]
	var swatch := UiStyle.swatch(low.lerp(high, value / 255.0), 14.0)
	swatch.tooltip_text = "%s: %d of 255" % [origin, value]
	swatch.mouse_filter = Control.MOUSE_FILTER_PASS
	return swatch


# --- Bonds --------------------------------------------------------------------------

func _bonds(state: WorldState) -> void:
	if not state.is_alive(_id):
		_body.add_child(UiStyle.label("The living still remember them; the dead hold no grudges.", 14, true))
		return
	var entries := People.strongest_bonds(state, _id, 12)
	var partner := _partner_of(state, _id)
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["id"]) == partner and int(b["id"]) != partner)
	if entries.is_empty():
		_body.add_child(UiStyle.label("Nobody they feel strongly about yet.", 14))
		return
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 4)
	for entry: Dictionary in entries:
		var other := int(entry["id"])
		var value := int(entry["value"])
		var love := int(entry["love"])
		var text := String(entry["name"])
		if other == partner:
			text += " (%s)" % People.partner_word(_sex_of(state, other))
		var link := UiStyle.link(text, 14)
		link.pressed.connect(func() -> void: person_clicked.emit(other))
		link.custom_minimum_size.x = 100
		grid.add_child(link)
		grid.add_child(UiStyle.bar((value + 100) / 200.0, 0.0, _bond_color(value)))
		var word := "%s %+d" % [_bond_word(value), value]
		if love > 0:
			word += "  ♥%d" % love
		var label := _clipped(word, 12, 116.0)
		if love > 0:
			label.add_theme_color_override("font_color", Color(0.70, 0.25, 0.40))
		grid.add_child(label)
	_body.add_child(grid)


## A label that never widens the panel: long text is cut with an ellipsis.
func _clipped(text: String, font_size: int, width: float) -> Label:
	var label := UiStyle.label(text, font_size)
	label.custom_minimum_size.x = width
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.tooltip_text = text
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	return label


func _sex_of(state: WorldState, id: int) -> String:
	var p := state.index_of(id)
	return state.person_sexes[p] if p != -1 else String((state.dead.get(str(id), {}) as Dictionary).get("sex", ""))


func _bond_word(value: int) -> String:
	if value >= 60:
		return "dear friend"
	if value >= 30:
		return "friend"
	if value <= -60:
		return "enemy"
	if value <= -30:
		return "dislikes"
	return "knows"


func _bond_color(value: int) -> Color:
	if value <= -30:
		return Color(0.85, 0.36, 0.30)
	if value < 30:
		return Color(0.80, 0.74, 0.60)
	return Color(0.45, 0.70, 0.40)


# --- Story --------------------------------------------------------------------------

func _story(state: WorldState) -> void:
	var story: Array = state.lives.get(str(_id), [])
	if story.is_empty():
		_body.add_child(UiStyle.label("Nothing remembered yet.", 14))
		return
	for k: int in range(story.size() - 1, -1, -1):
		var entry: Dictionary = story[k]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var icon := Label.new()
		icon.text = String(STORY_ICONS.get(String(entry.get("kind", "")), "•"))
		icon.custom_minimum_size.x = 16
		icon.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		icon.add_theme_font_size_override("font_size", 15)
		icon.add_theme_color_override("font_color", STORY_COLORS.get(String(entry.get("kind", "")), ToonMaterials.INK.lightened(0.25)))
		row.add_child(icon)
		var words := VBoxContainer.new()
		words.add_theme_constant_override("separation", 0)
		words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		words.add_child(UiStyle.label(String(entry["text"]), 14, true))
		var date := UiStyle.label("%s, aged %d" % [WorldState.date_text(int(entry["t"])), _age_at(state, int(entry["t"]))], 11)
		date.add_theme_color_override("font_color", ToonMaterials.INK.lightened(0.4))
		words.add_child(date)
		row.add_child(words)
		_body.add_child(row)


func _age_at(state: WorldState, at_tick: int) -> int:
	var p := state.index_of(_id)
	var born := state.person_born[p] if p != -1 else int((state.dead.get(str(_id), {}) as Dictionary).get("born", at_tick))
	return maxi(WorldState.year_of(at_tick - born), 0)
