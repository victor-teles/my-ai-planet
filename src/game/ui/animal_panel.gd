class_name AnimalPanel
extends PanelContainer
## The short card for one animal (docs/INTERFACE.md, "Animals, when they arrive"): what it is,
## its age, what it is doing, and one line of its story. Its genes open under Blood.
## Reads the simulation and the herd view; changes neither.

signal closed

const WIDTH := 360.0
const REFRESH_SECONDS := 0.25
## species -> [male, female, young]
const NOUNS := {
	"deer": ["Stag", "Doe", "Fawn"], "boar": ["Boar", "Sow", "Piglet"], "wolf": ["Wolf", "She-wolf", "Wolf cub"],
	"horse": ["Stallion", "Mare", "Foal"], "goat": ["Billy goat", "Nanny goat", "Kid"], "cat": ["Big cat", "Big cat", "Cub"],
	"bear": ["Bear", "She-bear", "Bear cub"], "sheep": ["Ram", "Ewe", "Lamb"], "sheep_flock": ["Ram", "Ewe", "Lamb"],
	"goat_herd": ["Billy goat", "Nanny goat", "Kid"], "cattle": ["Bull", "Cow", "Calf"], "pig": ["Boar", "Sow", "Piglet"],
	"draft_horse": ["Stallion", "Mare", "Foal"], "dog": ["Dog", "Dog", "Puppy"],
}
const LOW_ALLELE := Color(0.84, 0.86, 0.95)
const HIGH_ALLELE := Color(0.30, 0.22, 0.55)

var _id := -1
var _blood_open := false
var _signature := ""
var _since := 0.0
var _name := Label.new()
var _role := Label.new()
var _chips := HFlowContainer.new()
var _body := VBoxContainer.new()
var _scroll := ScrollContainer.new()


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
	_chips.add_theme_constant_override("h_separation", 6)
	_chips.add_theme_constant_override("v_separation", 4)
	column.add_child(_chips)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 7)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_body)
	column.add_child(_scroll)


## Shows an animal by id; -1 (or an animal no longer alive) hides the panel.
func show_animal(state: WorldState, id: int, herds: Herds) -> void:
	if id != _id:
		_blood_open = false
		_scroll.scroll_vertical = 0
	_id = id
	visible = _index(state) != -1
	_signature = ""
	if visible:
		_rebuild(state, herds)


func current_id() -> int:
	return _id if visible else -1


## Opens or closes the Blood section.
func set_blood_open(open: bool) -> void:
	_blood_open = open
	_signature = ""
	_since = REFRESH_SECONDS


## Call every frame: rebuilds a few times a second when what it shows has changed.
func refresh(state: WorldState, herds: Herds) -> void:
	if not visible:
		return
	_since += get_process_delta_time()
	if _since < REFRESH_SECONDS:
		return
	_since = 0.0
	var i := _index(state)
	if i == -1:
		visible = false
		closed.emit()
		return
	var signature := str([_id, _blood_open, herds.activity_of(_id), state.year(), state.animal_condition[i], state.animal_ids.size()])
	if signature != _signature:
		_rebuild(state, herds)


func _index(state: WorldState) -> int:
	if _id < 0:
		return -1
	return Array(state.animal_ids).find(_id)


func _rebuild(state: WorldState, herds: Herds) -> void:
	var i := _index(state)
	if i == -1:
		return
	_signature = str([_id, _blood_open, herds.activity_of(_id), state.year(), state.animal_condition[i], state.animal_ids.size()])
	UiStyle.clear(_body)
	UiStyle.clear(_chips)
	var species_id := state.animal_species[i]
	var genome := state.animal_genomes[i]
	var table := Species.animal_table()
	var female := state.animal_sex[i] == "f"
	var days := state.tick - state.animal_born[i]
	var young := days < AnimalSystem.ADULT_YEARS * WorldState.DAYS_PER_YEAR
	var white := table.shows(genome, "white")
	var noun := noun_of(species_id, female, young)
	_name.text = ("The white %s" % noun.to_lower()) if white else noun
	_role.text = "%s   ·   %s   ·   %s" % [Species.get_species(species_id).get("name", species_id), _age_words(days), herds.activity_of(_id)]
	if white:
		_chips.add_child(UiStyle.chip("White coat", Color(0.95, 0.95, 0.92), 12))
	if _is_sire(state, i):
		_chips.add_child(UiStyle.chip("Sire of the herd", Color(0.98, 0.80, 0.42), 12))
	var condition := state.animal_condition[i]
	if condition < 40:
		_chips.add_child(UiStyle.chip("Thin", Color(0.98, 0.78, 0.72), 12))
	var story := UiStyle.label(story_of(state, i), UiStyle.BODY, true)
	_body.add_child(story)
	var fold := Button.new()
	fold.text = ("▾  Blood" if _blood_open else "▸  Blood")
	fold.flat = true
	fold.focus_mode = Control.FOCUS_NONE
	fold.alignment = HORIZONTAL_ALIGNMENT_LEFT
	fold.add_theme_color_override("font_color", ToonMaterials.INK)
	fold.add_theme_color_override("font_hover_color", UiStyle.ORACLE)
	fold.tooltip_text = "Its genes: two copies of each, one from each parent"
	fold.pressed.connect(func() -> void: set_blood_open(not _blood_open))
	_body.add_child(fold)
	if _blood_open:
		_blood(genome)


## "Doe", "Stag", "Fawn"... from the species and the animal's sex and age.
static func noun_of(species_id: String, female: bool, young: bool) -> String:
	var nouns: Array = NOUNS.get(species_id, [String(Species.get_species(species_id).get("name", "Animal"))].duplicate())
	if nouns.size() < 3:
		return String(nouns[0])
	return String(nouns[2] if young else (nouns[1] if female else nouns[0]))


## One line of an animal's life: when it was born and what stands out about it, from facts the
## simulation keeps (its genes, its age, its herd and the hunters of the valley).
static func story_of(state: WorldState, i: int) -> String:
	var table := Species.animal_table()
	var born := state.animal_born[i]
	var genome := state.animal_genomes[i]
	var species_id := state.animal_species[i]
	var line := ""
	if born < 0:
		line = "Born before the first people came to the valley"
	else:
		var month := posmod(born / WorldState.DAYS_PER_MONTH, WorldState.MONTHS_PER_YEAR)
		line = "Born in the %s of year %d" % [WorldState.SEASONS[month], WorldState.year_of(born)]
	var facts: Array[String] = []
	var info := Species.get_species(species_id)
	var prey := String(info.get("diet", "")) != "predator"
	var speed := Genetics.express(genome, "speed", table)
	var hunters := _living_hunters(state)
	var age_years := float(state.tick - born) / float(WorldState.DAYS_PER_YEAR)
	if prey and not hunters.is_empty() and speed > AnimalSystem.SLOW_PREY and age_years >= 1.0:
		facts.append("too quick for the %s" % Herds.plural(String(Species.get_species(hunters[0]).get("name", "wolf"))))
	if _oldest_of_kind(state, i):
		facts.append("the oldest of its kind in the valley")
	if table.shows(genome, "white"):
		facts.append("a white coat that shows once in many generations")
	elif Genetics.express(genome, "size", table) >= 0.7:
		facts.append("bigger than most of its kind")
	if state.animal_condition[i] < 40:
		facts.append("thin after a hard season")
	if facts.is_empty():
		var wary := Genetics.express(genome, "wariness", table)
		facts.append("wary of people" if wary >= 0.55 else ("bold around people" if wary <= 0.4 else "at home in the valley"))
	line += ", " + " and ".join(facts.slice(0, 2)) + "."
	return line


static func _living_hunters(state: WorldState) -> Array[String]:
	var found: Array[String] = []
	for species_id: String in state.animal_species:
		if species_id in AnimalSystem.HUNTERS and species_id not in found:
			found.append(species_id)
	return found


static func _oldest_of_kind(state: WorldState, i: int) -> bool:
	var kin := 0
	for j: int in state.animal_ids.size():
		if j == i or state.animal_species[j] != state.animal_species[i]:
			continue
		kin += 1
		if state.animal_born[j] < state.animal_born[i]:
			return false
	return kin >= 2


## The strongest grown male by size and horns: the one AnimalSystem pairs with the mothers.
static func _is_sire(state: WorldState, i: int) -> bool:
	if state.animal_sex[i] != "m" or state.tick - state.animal_born[i] < AnimalSystem.ADULT_YEARS * WorldState.DAYS_PER_YEAR:
		return false
	var table := Species.animal_table()
	var best := -1
	var best_score := -1.0
	for j: int in state.animal_ids.size():
		if state.animal_species[j] != state.animal_species[i] or state.animal_sex[j] != "m":
			continue
		if state.tick - state.animal_born[j] < AnimalSystem.ADULT_YEARS * WorldState.DAYS_PER_YEAR:
			continue
		var score := Genetics.express(state.animal_genomes[j], "size", table) + Genetics.express(state.animal_genomes[j], "horns", table)
		if best == -1 or score > best_score:
			best = j
			best_score = score
	return best == i


func _age_words(days: int) -> String:
	if days < WorldState.DAYS_PER_YEAR:
		@warning_ignore("integer_division")
		var months := maxi(days / WorldState.DAYS_PER_MONTH, 0)
		return "newborn" if months == 0 else "%d month%s old" % [months, "" if months == 1 else "s"]
	var years := WorldState.year_of(days)
	return "%d year%s old" % [years, "" if years == 1 else "s"]


func _blood(genome: PackedByteArray) -> void:
	var table := Species.animal_table()
	var intro := UiStyle.label("Two copies of every gene, one from each parent. What shows is their average, except the white coat, which needs both copies.", 12, true)
	intro.add_theme_color_override("font_color", ToonMaterials.INK.lightened(0.3))
	_body.add_child(intro)
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 7)
	grid.add_theme_constant_override("v_separation", 5)
	for g: int in Species.GENES.size():
		var gene := Species.GENES[g]
		var info: Dictionary = Species.INFO[gene]
		var title := UiStyle.label(String(info["name"]), UiStyle.SMALL + 1)
		title.custom_minimum_size.x = 74
		grid.add_child(title)
		grid.add_child(_allele(genome[g * 2], "First copy"))
		grid.add_child(_allele(genome[g * 2 + 1], "Second copy"))
		var value := Genetics.express(genome, gene, table)
		var word := Genetics.word(genome, gene, table)
		if gene == "white":
			var copies := table.allele_count(genome, "white")
			value = 1.0 if copies == 2 else 0.0
			word = "white (2 of 2)" if copies == 2 else "colored (%d of 2)" % copies
		grid.add_child(UiStyle.bar(value, 0.0, Color(0.50, 0.58, 0.85)))
		var said := UiStyle.label(word, 12)
		said.add_theme_color_override("font_color", UiStyle.INK_SOFT)
		said.custom_minimum_size.x = 84
		grid.add_child(said)
	_body.add_child(grid)


func _allele(value: int, origin: String) -> Control:
	var swatch := UiStyle.swatch(LOW_ALLELE.lerp(HIGH_ALLELE, value / 255.0), 14.0)
	swatch.tooltip_text = "%s: %d of 255" % [origin, value]
	swatch.mouse_filter = Control.MOUSE_FILTER_PASS
	return swatch
