class_name WorldState
extends RefCounted
## The whole simulated world. One tick is one day; a month is 30 days and a year 12 months.
## Tribes, people and buildings are stored as parallel packed arrays (index i is the same
## thing in every array of its group) instead of one object each, so the sim stays fast in GDScript.
## Every person alive is simulated: their DNA, family, job, home, health and bonds.

const SAVE_VERSION := 5
const DAYS_PER_MONTH := 30
const MONTHS_PER_YEAR := 12
const DAYS_PER_YEAR := DAYS_PER_MONTH * MONTHS_PER_YEAR
const MAX_EVENTS := 900
const MAX_LIFE_ENTRIES := 60 ## per person; the first (their birth) is always kept
const MAX_DEAD := 1500 ## the oldest graves are forgotten after this
const MONTH_NAMES: Array[String] = [
	"Deep Winter", "Thaw", "Early Spring", "Spring", "Late Spring", "Early Summer",
	"Summer", "Late Summer", "Harvest", "Autumn", "Late Autumn", "First Frost",
]
const SEASONS: Array[String] = ["winter", "winter", "spring", "spring", "spring", "summer", "summer", "summer", "autumn", "autumn", "autumn", "winter"]
## Saved floats are kept on a grid of 1/1024: Godot's JSON writer misprints the last digit of
## about a quarter of arbitrary doubles, but numbers on this grid survive a round trip bit for bit.
const FLOAT_STEP := 1.0 / 1024.0
const KIN_RELATION := 40 ## a tribe that splits off starts out this friendly with the one it left
const CAPACITY_PER_AREA := 2.6 ## people the island feeds well, per square unit of radius (about 260 on an average island)
const FIELDS_PER_AREA := 0.32 ## fields the island has room for, per square unit of radius

var seed_value: int = 0
var tick: int = 0
var rng: SimRng
## The island this seed made (see WorldGen): biome, climate, ores, shape, first peoples.
var world: Dictionary = {}

# Climate (updated monthly)
var rainfall: float = 1.0 ## 1.0 is a normal month
var drought_months_left: int = 0
var blessed_rain_months: int = 0

# Tribes
var tribe_names := PackedStringArray()
var tribe_food := PackedFloat64Array() ## stored food, in person-days
var tribe_hunt_credit := PackedFloat64Array() ## progress toward the next kill; an empty valley keeps none
var tribe_wood := PackedFloat64Array()
var tribe_stone := PackedFloat64Array()
var tribe_tools := PackedFloat64Array() ## 0..1: how well equipped the workers are
var tribe_cloth := PackedFloat64Array() ## 0..1: how many have warm clothes for winter
var tribe_pots := PackedFloat64Array() ## 0..1: jars to keep food from spoiling
var tribe_water := PackedInt32Array() ## index of the water source the tribe drinks from
var tribe_chiefs := PackedInt32Array() ## person id, or -1 while the tribe chooses
var tribe_founded := PackedInt32Array() ## tick
var tribe_hungry_days := PackedInt32Array() ## days this month the stores were empty
var tribe_project := PackedInt32Array() ## building id under construction, or -1
var tribe_plan := PackedStringArray() ## building type waiting for materials, or ""
var tribe_knowledge: Array[PackedStringArray] = []
## How much work each job puts in per day (job -> float), worked out monthly from the workers.
var tribe_work: Array[Dictionary] = []
var tribe_metal := PackedFloat64Array() ## smelted ore, for the smiths
var tribe_treasury := PackedFloat64Array() ## what taxes bring in, before it pays guards, officials and the ruler
## Society (see Society, SocietySystem, CrisisSystem).
var tribe_culture: Array[Dictionary] = [] ## axis -> -100..100
var tribe_laws: Array[Dictionary] = [] ## law -> tick it was passed
var tribe_power: Array[Dictionary] = [] ## faction -> 0..100
var tribe_legitimacy := PackedInt32Array() ## 0..100: do the people accept their rulers
var tribe_unrest := PackedInt32Array() ## 0..100
var tribe_fear := PackedInt32Array() ## 0..100
var tribe_dynasty := PackedStringArray() ## family name of the ruling house, or ""
var tribe_overlord := PackedStringArray() ## the tribe this one pays tribute to, or ""
var tribe_vassal_since := PackedInt32Array() ## tick it became a vassal, or -1
var tribe_crisis: Array[Dictionary] = [] ## {"type", "stage", "since", ...} or {} when calm
var tribe_ruler := PackedInt32Array() ## the ruler SocietySystem last saw, to time their reign
var tribe_ruler_since := PackedInt32Array() ## tick that ruler took the seat
## The tongue each tribe names its children in (see Language); {} is the old default sound.
var tribe_language: Array[Dictionary] = []
## Derived, not saved: living people per tribe. Kept in step by add/remove/move person.
var tribe_population := PackedInt32Array()
## Derived, not saved: per tribe, what its laws add up to and what its knowledge is worth. Rebuilt
## after any law or tech changes (see law_sums() and tech_bonus()); read every day by the economy.
var _law_sums: Array[Dictionary] = []
var _tech_sums: Array[Dictionary] = []

# Water sources: the pond and the springs. Rain fills them, drinking empties them.
var water_names := PackedStringArray()
var water_capacity := PackedFloat64Array() ## people a full source can serve without falling
var water_level := PackedFloat64Array() ## 0 is dry, 1 is full

# People (the living). See People for what each field means.
var person_ids := PackedInt32Array()
var person_names := PackedStringArray()
var person_families := PackedStringArray() ## family name, passed down from the father (or mother)
var person_sexes := PackedStringArray() ## "f" or "m"
var person_born := PackedInt32Array() ## tick of birth
var person_tribes := PackedStringArray()
var person_mothers := PackedInt32Array() ## id, -1 for the first people
var person_fathers := PackedInt32Array()
var person_partners := PackedInt32Array() ## id of their wife or husband, or -1
var person_genomes: Array[PackedByteArray] = []
var person_traits := PackedStringArray() ## two trait ids joined by "|"; "" until they come of age
var person_jobs := PackedStringArray() ## job id, or "" (children, elders, the sick)
var person_skills: Array[PackedByteArray] = [] ## one byte (0-100) per Jobs.SKILLS
var person_health := PackedInt32Array() ## 0 (dying) to 100
var person_mood := PackedInt32Array() ## 0 (miserable) to 100 (joyful)
var person_homes := PackedInt32Array() ## building id they sleep in, or -1 (under the sky)
var person_due := PackedInt32Array() ## tick a baby is due, or -1
var person_baby_fathers := PackedInt32Array()
var person_sick := PackedInt32Array() ## days of sickness left
var person_grief := PackedInt32Array() ## months of mourning left
var person_attraction := PackedInt32Array() ## 0 the other sex, 1 the same sex, 2 both
var person_generations := PackedInt32Array() ## 1 for the first people
var person_wealth := PackedInt32Array() ## savings, in days of a laborer's keep
var person_status := PackedStringArray() ## "" (a commoner), "noble" or "bonded"
var person_loyalty := PackedInt32Array() ## 0..100: how much they back their rulers; dissidents are below 25
var person_detained := PackedInt32Array() ## months left in custody, or 0
var next_person_id: int = 0
var _index: Dictionary = {} ## id -> index; rebuilt after removals

## Wild animals, one individual each. Ids start at ANIMAL_ID_START so they never meet a person id.
const ANIMAL_ID_START := 1000000
var animal_ids := PackedInt32Array()
var animal_species := PackedStringArray()
var animal_genomes: Array[PackedByteArray] = []
var animal_born := PackedInt32Array() ## tick
var animal_sex := PackedStringArray() ## "f" or "m"
var animal_condition := PackedInt32Array() ## 0 (dying) to 100
var next_animal_id: int = ANIMAL_ID_START
## Species seeded for this biome, and those already logged as gone. Empty on a save from before animals.
var animal_seeded := PackedStringArray()
var animal_wiped := PackedStringArray()
var _index_dirty := true

## The dead, by str(id): {"name", "family", "sex", "born", "died", "cause", "tribe", "mother",
## "father", "partner", "job", "generation", "genome", "traits"}.
var dead: Dictionary = {}
## Life stories, by str(id): [{"t": tick, "text", "kind"}]. Kept after death.
var lives: Dictionary = {}
## How two people feel about each other: "a|b" (ids, smaller first) -> -100 (hate) to 100 (love).
var bonds: Dictionary = {}
## Romantic feeling between two people: "a|b" -> 0 to 100.
var romance: Dictionary = {}

# Buildings
var building_ids := PackedInt32Array()
var building_types := PackedStringArray()
var building_tribes := PackedStringArray()
var building_slots := PackedInt32Array()
var building_progress := PackedInt32Array() ## builder-days put in
var building_done := PackedInt32Array() ## tick it was finished, or -1 while being built
var next_building_id: int = 0

## How the tribes feel about each other: "A|B" (names sorted) -> -100 (blood feud) to 100 (kin).
## Pairs that aren't here are 0, so a new tribe starts as strangers to everyone.
var relations: Dictionary = {}

# The player god
const MAX_INFLUENCE := 12.0
const STARTING_INFLUENCE := 5.0
var influence: float = STARTING_INFLUENCE
## Smoke from the factories hanging over the whole island, 0..100.
var pollution: float = 0.0
## How the island's story ended, once it has: {"kind", "tribe", "year"}. Empty until then.
var destiny: Dictionary = {}
## destiny kind -> years in a row its conditions have held.
var destiny_progress: Dictionary = {}
## Once a year: {"year", "tribes": {name: {"freedom", "control", "inequality", "fear", "dystopia", "government"}}}.
var society_history: Array[Dictionary] = []
## Sum of the kindness of every miracle cast: positive is benevolent, negative is wrathful.
var kindness: int = 0
## The god's disposition (see disposition()), from every miracle cast and dilemma answered:
## how much mercy and wrath they have shown, and when they last meddled.
const MAX_GOD_ACTS := 24
const MEDDLE_YEARS := 10 ## interventions this recent count toward how hands-on the god is
var god_mercy: int = 0
var god_wrath: int = 0
var god_act_ticks := PackedInt32Array() ## ticks of the latest interventions, newest last
var god_act_leanings := PackedInt32Array() ## for each: > 0 merciful, < 0 wrathful, 0 neither
## The Oracle's current prophecy, checked monthly by ProphecySystem. Null between prophecies.
var prophecy: Prophecy
## The last prophecy that came true or broke, kept for the reveal.
var resolved_prophecy: Prophecy

## What happened, newest last. The Oracle reads this to explain cause and effect.
var events: Array[Dictionary] = []
## Increases with every event, so views can tell which events they haven't shown yet.
var next_event_id: int = 0
## Once a year: {"year", "pop", "genes": {gene: 0-100}, "frail", "carriers"}.
var gene_history: Array[Dictionary] = []
## Not saved: the day's chats, quarrels and courtships, for the view to act out. Newest last.
var meetings: Array[Dictionary] = []
var next_meeting_id: int = 0
## AI-authored asset specs (styles, heraldry, posters, languages...), see AssetBook. They change
## how the world looks and what things are called, never the sim's numbers.
var assets: Dictionary = {}


## `bands` forces how many peoples land first (0 lets the seed decide); tests use 1.
static func create(new_seed: int, bands: int = 0) -> WorldState:
	var state := WorldState.new()
	state.seed_value = new_seed
	state.rng = SimRng.new(new_seed)
	state.world = WorldGen.generate(new_seed, bands)
	state.world["camps"] = float(IslandShape.new(state.world, new_seed).camp_count())
	state.add_water("the Pond", WorldGen.pond_capacity(state.world))
	var peoples: Array = state.world["peoples"]
	for k: int in int(state.world["island"]["springs"]):
		# The springs are named by the first people to land.
		state.add_water("%s Spring" % NameGen.tribe_name(state.rng, WorldGen.people_language(peoples[0])), float(state.rng.randi_range(90, 160)))
	for index: int in peoples.size():
		var people: Dictionary = peoples[index]
		var tribe := String(people["name"])
		var t := state.add_tribe(tribe, index % state.water_names.size(), people["culture"], WorldGen.people_language(people))
		People.found_band(state, tribe, int(people["couples"]))
		state.tribe_food[t] = state.tribe_population[t] * 75.0
		state.tribe_wood[t] = 30.0
	# Peoples who landed on the same island start out wary of each other.
	for i: int in state.tribe_count():
		for j: int in range(i + 1, state.tribe_count()):
			state.set_relation(state.tribe_names[i], state.tribe_names[j], state.rng.randi_range(-15, 10))
	# After the people, so animal ids sit above every person and event id minted while founding.
	state.next_animal_id = maxi(ANIMAL_ID_START, maxi(state.next_person_id, state.next_event_id))
	AnimalSystem.seed(state)
	return state


# --- Time ---------------------------------------------------------------------------

func year() -> int:
	return year_of(tick)


@warning_ignore("integer_division")
static func year_of(at_tick: int) -> int:
	return at_tick / DAYS_PER_YEAR


@warning_ignore("integer_division")
func month() -> int:
	return (tick / DAYS_PER_MONTH) % MONTHS_PER_YEAR


func day() -> int:
	return tick % DAYS_PER_MONTH


func season() -> String:
	return SEASONS[month()]


## "Year 12, Harvest" for a tick.
@warning_ignore("integer_division")
static func date_text(at_tick: int) -> String:
	return "Year %d, %s" % [year_of(at_tick), MONTH_NAMES[(at_tick / DAYS_PER_MONTH) % MONTHS_PER_YEAR]]


func is_month_start() -> bool:
	return tick % DAYS_PER_MONTH == 0


func is_year_start() -> bool:
	return tick % DAYS_PER_YEAR == 0


## 1 (gentle fable) to 5 (grim chronicle): how the AI should write about this world.
## Driven by how kind or wrathful the player has been (their standing and their disposition),
## and by how the people are doing: drought, war and a world sliding into dystopia darken it.
func tone() -> int:
	var level := 2.0 - kindness / 3.0
	level += 0.5 * float(god_wrath - god_mercy) / float(god_wrath + god_mercy + 2)
	if drought_months_left > 0:
		level += 0.5
	if ticks_since("war") < 10 * DAYS_PER_YEAR:
		level += 0.5
	level += 1.5 * Society.gloom(self)
	return clampi(roundi(level), 1, 5)


# --- The god's disposition ----------------------------------------------------------

## Records one of the god's interventions (a miracle or a dilemma choice). `leaning` > 0 is
## mercy, < 0 is wrath (its size is how much), 0 is neither: it still counts as meddling.
func record_intervention(leaning: int) -> void:
	if leaning > 0:
		god_mercy += leaning
	elif leaning < 0:
		god_wrath -= leaning
	god_act_ticks.append(tick)
	god_act_leanings.append(leaning)
	if god_act_ticks.size() > MAX_GOD_ACTS:
		god_act_ticks.remove_at(0)
		god_act_leanings.remove_at(0)


## How the god has played: {"kindness", "mercy", "wrath", "recent_acts", "leaning", "hand"}.
## "leaning" is benevolent, wrathful, capricious (both) or unknown; "hand" is guiding,
## watchful or hands-off, from how many times they intervened in the last MEDDLE_YEARS years.
func disposition() -> Dictionary:
	var recent := 0
	for at: int in god_act_ticks:
		if tick - at < MEDDLE_YEARS * DAYS_PER_YEAR:
			recent += 1
	var leaning := "unknown"
	if god_mercy + god_wrath >= 2:
		if god_mercy >= 2 * god_wrath:
			leaning = "benevolent"
		elif god_wrath >= 2 * god_mercy:
			leaning = "wrathful"
		else:
			leaning = "capricious"
	var hand := "guiding" if recent >= 6 else "watchful" if recent >= 2 else "hands-off"
	return {"kindness": kindness, "mercy": god_mercy, "wrath": god_wrath, "recent_acts": recent, "leaning": leaning, "hand": hand}


## One sentence on the god's disposition, for the AI prompts.
func disposition_text() -> String:
	var d := disposition()
	var leaning: String = {
		"unknown": "The god has shown little of their nature yet",
		"benevolent": "The god has been benevolent",
		"wrathful": "The god has been wrathful",
		"capricious": "The god has been capricious, both merciful and cruel",
	}[d["leaning"]]
	var hand: String = {
		"guiding": "and keeps a guiding hand on the island",
		"watchful": "and steps in now and then",
		"hands-off": "and lets the island go its own way",
	}[d["hand"]]
	return "%s (mercy %d, wrath %d), %s (%d in the last %d years). The people find the god %s." % [
		leaning, d["mercy"], d["wrath"], hand, d["recent_acts"], MEDDLE_YEARS,
		"kind" if kindness > 1 else "cruel" if kindness < -1 else "hard to read",
	]


## Ticks since the newest event of this type that is still in the log, or a huge number if none is.
## With a tribe, only events about that tribe count. With `within`, the search gives up on events
## older than that (and returns the huge number), which keeps frequent checks cheap.
func ticks_since(type: String, tribe: String = "", within: int = 1 << 30) -> int:
	for j: int in range(events.size() - 1, -1, -1):
		var event := events[j]
		if tick - int(event["tick"]) > within:
			break
		if event["type"] == type and (tribe.is_empty() or String((event["data"] as Dictionary).get("tribe", "")) == tribe):
			return tick - int(event["tick"])
	return 1 << 30


# --- Tribes -------------------------------------------------------------------------

func tribe_index(tribe_name: String) -> int:
	return Array(tribe_names).find(tribe_name)


func tribe_count() -> int:
	return tribe_names.size()


func total_population() -> int:
	return person_ids.size()


## language: the tribe's tongue (see Language), clamped; {} keeps the default sound.
func add_tribe(tribe_name: String, water: int, culture: Dictionary = {}, language: Dictionary = {}) -> int:
	tribe_names.append(tribe_name)
	tribe_food.append(0.0)
	tribe_hunt_credit.append(0.0)
	tribe_wood.append(0.0)
	tribe_stone.append(0.0)
	tribe_tools.append(0.0)
	tribe_cloth.append(0.0)
	tribe_pots.append(0.0)
	tribe_water.append(water)
	tribe_chiefs.append(-1)
	tribe_founded.append(tick)
	tribe_hungry_days.append(0)
	tribe_project.append(-1)
	tribe_plan.append("")
	tribe_knowledge.append(PackedStringArray(Knowledge.STARTING))
	tribe_work.append({})
	tribe_metal.append(0.0)
	tribe_treasury.append(0.0)
	var clean := {}
	for axis: String in Society.CULTURE_AXES:
		clean[axis] = clampi(int(culture.get(axis, 0)), -100, 100)
	tribe_culture.append(clean)
	tribe_laws.append({})
	tribe_power.append({})
	tribe_legitimacy.append(60)
	tribe_unrest.append(0)
	tribe_fear.append(0)
	tribe_dynasty.append("")
	tribe_overlord.append("")
	tribe_vassal_since.append(-1)
	tribe_crisis.append({})
	tribe_ruler.append(-1)
	tribe_ruler_since.append(tick)
	tribe_language.append(Language.clamp_spec(language))
	tribe_population.append(0)
	_law_sums.clear()
	_tech_sums.clear()
	var index := tribe_names.size() - 1
	add_building(tribe_name, "fire", -2).done(self)
	return index


## Removes a tribe and its buildings. Its people must have moved or died first.
func remove_tribe(index: int) -> void:
	var gone := tribe_names[index]
	for key: String in relations.keys():
		if gone in key.split("|"):
			relations.erase(key)
	for b: int in range(building_ids.size() - 1, -1, -1):
		if building_tribes[b] == gone:
			remove_building(b)
	for p: int in range(person_ids.size() - 1, -1, -1):
		if person_tribes[p] == gone:
			remove_person(p) # only reached if a caller forgot to move them
	for array: Variant in [tribe_names, tribe_food, tribe_hunt_credit, tribe_wood, tribe_stone, tribe_tools, tribe_cloth, tribe_pots,
			tribe_water, tribe_chiefs, tribe_founded, tribe_hungry_days, tribe_project, tribe_plan, tribe_population,
			tribe_metal, tribe_treasury, tribe_legitimacy, tribe_unrest, tribe_fear, tribe_dynasty, tribe_overlord, tribe_vassal_since,
			tribe_ruler, tribe_ruler_since]:
		array.remove_at(index)
	for array: Array in [tribe_knowledge, tribe_work, tribe_culture, tribe_laws, tribe_power, tribe_crisis, tribe_language]:
		array.remove_at(index)
	_law_sums.clear()
	_tech_sums.clear()
	# Its vassals are free.
	for t: int in tribe_count():
		if tribe_overlord[t] == gone:
			tribe_overlord[t] = ""
			tribe_vassal_since[t] = -1


## Whether there's still room on the island for a new tribe to settle: one camp per tribe.
func has_room_for_tribe() -> bool:
	return tribe_count() < int(world.get("camps", 5.0))


## How many people the island can feed well: more on a bigger island. Births slow as it fills.
func carrying_capacity() -> float:
	var radius := float((world.get("island", {}) as Dictionary).get("radius", 10.0))
	return CAPACITY_PER_AREA * radius * radius


## Fields the whole island has room for, shared by every tribe.
func field_room() -> int:
	var radius := float((world.get("island", {}) as Dictionary).get("radius", 10.0))
	return roundi(FIELDS_PER_AREA * radius * radius)


func knows(t: int, tech: String) -> bool:
	return tech in tribe_knowledge[t]


func learn(t: int, tech: String) -> void:
	if not knows(t, tech):
		tribe_knowledge[t].append(tech)
		_tech_sums.clear()


func set_knowledge(t: int, known: PackedStringArray) -> void:
	tribe_knowledge[t] = known
	_tech_sums.clear()


## The age a tribe has reached (see Knowledge.age_of), remembered between discoveries.
func age_of(t: int) -> int:
	return int(_techs(t)["age"])


## What a tribe's knowledge does for an effect (see Knowledge.bonus), remembered between discoveries.
func tech_bonus(t: int, effect: String) -> float:
	return float(_techs(t).get(effect, 1.0))


func _techs(t: int) -> Dictionary:
	if _tech_sums.size() != tribe_count():
		_tech_sums.clear()
		for i: int in tribe_count():
			var sums := {"age": Knowledge.age_of(tribe_knowledge[i])}
			for effect: String in Knowledge.BONUSES:
				sums[effect] = Knowledge.bonus(tribe_knowledge[i], effect)
			_tech_sums.append(sums)
	return _tech_sums[t]


func pass_law(t: int, law: String) -> void:
	tribe_laws[t][law] = tick
	_law_sums.clear()


func drop_law(t: int, law: String) -> void:
	tribe_laws[t].erase(law)
	_law_sums.clear()


## What a tribe's laws add up to: each effect (a product for Laws.MULTIPLY, else a sum), each
## flag (1.0 when any law sets it), and "freedom", "control" and "fear": the laws' totals.
func law_sums(t: int) -> Dictionary:
	if _law_sums.size() != tribe_count():
		_law_sums.clear()
		for i: int in tribe_count():
			var sums := {"freedom": 0.0, "control": 0.0, "fear": 0.0}
			for law: String in tribe_laws[i]:
				var info: Dictionary = Laws.LAWS[law]
				for total: String in ["freedom", "control", "fear"]:
					sums[total] = float(sums[total]) + float(info[total])
				var effects: Dictionary = info["effects"]
				for key: String in effects:
					if key in Laws.MULTIPLY:
						sums[key] = float(sums.get(key, 1.0)) * float(effects[key])
					else:
						sums[key] = float(sums.get(key, 0.0)) + float(effects[key])
			_law_sums.append(sums)
	return _law_sums[t]


func chief_of(tribe_name: String) -> int:
	var t := tribe_index(tribe_name)
	return index_of(tribe_chiefs[t]) if t != -1 else -1


# --- People -------------------------------------------------------------------------

## Adds a person and returns their index. Their genome and parents are decided by the caller.
func add_person(tribe_name: String, sex: String, born_tick: int, genome: PackedByteArray, mother: int, father: int,
		family: String, given_name: String) -> int:
	var id := next_person_id
	next_person_id += 1
	person_ids.append(id)
	person_names.append(given_name)
	person_families.append(family)
	person_sexes.append(sex)
	person_born.append(born_tick)
	person_tribes.append(tribe_name)
	person_mothers.append(mother)
	person_fathers.append(father)
	person_partners.append(-1)
	person_genomes.append(genome)
	person_traits.append("")
	person_jobs.append("")
	var skills := PackedByteArray()
	skills.resize(Jobs.SKILLS.size())
	person_skills.append(skills)
	person_health.append(People.max_health(genome, 20))
	person_mood.append(65)
	person_homes.append(-1)
	person_due.append(-1)
	person_baby_fathers.append(-1)
	person_sick.append(0)
	person_grief.append(0)
	var roll := rng.randf()
	person_attraction.append(0 if roll < 0.9 else (1 if roll < 0.96 else 2))
	var generation := 1
	for parent: int in [mother, father]:
		generation = maxi(generation, People.generation_of(self, parent) + 1)
	person_generations.append(generation)
	person_wealth.append(0)
	person_status.append("")
	person_loyalty.append(60)
	person_detained.append(0)
	var index := person_ids.size() - 1
	_index[id] = index
	var t := tribe_index(tribe_name)
	if t != -1:
		tribe_population[t] += 1
	return index


## Takes a person out of the living arrays. Use kill_person() for a death: this keeps no record.
func remove_person(p: int) -> void:
	var t := tribe_index(person_tribes[p])
	if t != -1:
		tribe_population[t] -= 1
	for array: Variant in [person_ids, person_names, person_families, person_sexes, person_born, person_tribes,
			person_mothers, person_fathers, person_partners, person_traits, person_jobs, person_health, person_mood,
			person_homes, person_due, person_baby_fathers, person_sick, person_grief, person_attraction, person_generations,
			person_wealth, person_status, person_loyalty, person_detained]:
		array.remove_at(p)
	person_genomes.remove_at(p)
	person_skills.remove_at(p)
	_index_dirty = true


## A wild animal. Genome and sex are decided by the caller. Ids never collide with person ids.
func add_animal(species_id: String, sex: String, born_tick: int, genome: PackedByteArray, condition: int) -> int:
	var id := next_animal_id
	next_animal_id += 1
	animal_ids.append(id)
	animal_species.append(species_id)
	animal_genomes.append(genome)
	animal_born.append(born_tick)
	animal_sex.append(sex)
	animal_condition.append(clampi(condition, 0, 100))
	return animal_ids.size() - 1


func remove_animal(index: int) -> void:
	animal_ids.remove_at(index)
	animal_species.remove_at(index)
	animal_genomes.remove_at(index)
	animal_born.remove_at(index)
	animal_sex.remove_at(index)
	animal_condition.remove_at(index)


## Index of a living person by id, or -1 if they aren't alive.
func index_of(id: int) -> int:
	if id < 0:
		return -1
	if _index_dirty:
		_index.clear()
		for p: int in person_ids.size():
			_index[person_ids[p]] = p
		_index_dirty = false
	return int(_index.get(id, -1))


func is_alive(id: int) -> bool:
	return index_of(id) != -1


func people_of(tribe_name: String) -> Array[int]:
	var members: Array[int] = []
	for p: int in person_ids.size():
		if person_tribes[p] == tribe_name:
			members.append(p)
	return members


func move_person(p: int, to_tribe: String) -> void:
	var from := tribe_index(person_tribes[p])
	var to := tribe_index(to_tribe)
	if from != -1:
		tribe_population[from] -= 1
	if to != -1:
		tribe_population[to] += 1
	person_tribes[p] = to_tribe
	person_homes[p] = -1
	if from != -1 and tribe_chiefs[from] == person_ids[p]:
		tribe_chiefs[from] = -1


## A death: the person is remembered (record, life story, grave), their family grieves, and
## their partner is widowed. cause: "old age", "sickness", "hunger", "thirst", "accident",
## "childbirth", "war", "plague", "a fight".
func kill_person(p: int, cause: String, extra: Dictionary = {}) -> void:
	var id := person_ids[p]
	var tribe := person_tribes[p]
	var t := tribe_index(tribe)
	var age := People.age(self, p)
	var was_chief := t != -1 and tribe_chiefs[t] == id
	dead[str(id)] = {
		"name": person_names[p], "family": person_families[p], "sex": person_sexes[p], "born": person_born[p],
		"died": tick, "cause": cause, "tribe": tribe, "mother": person_mothers[p], "father": person_fathers[p],
		"partner": person_partners[p], "job": person_jobs[p], "generation": person_generations[p],
		"genome": Genetics.to_hex(person_genomes[p]), "traits": person_traits[p],
	}
	var data := {"id": id, "name": person_names[p], "age": age, "cause": cause, "tribe": tribe, "job": person_jobs[p]}
	if was_chief:
		data["chief"] = 1
	data.merge(extra)
	log_event("death", data)
	if cause == "exile":
		life(id, "Was driven from the island at %d, never to return." % age, "death")
	elif cause in ["the uprising", "the succession war"]:
		life(id, "Fell in %s at %d." % [cause, age], "death")
	else:
		life(id, "Died of %s at %d." % [cause, age] if cause in ["old age", "sickness", "hunger", "thirst", "plague"] else "Died (%s) at %d." % [cause, age], "death")
	# The family mourns.
	var partner := index_of(person_partners[p])
	if partner != -1:
		person_partners[partner] = -1
		person_grief[partner] = 8
		life(person_ids[partner], "Widowed: %s %s died." % [People.partner_word(person_sexes[p]), person_names[p]], "grief")
	for q: int in person_ids.size():
		if q == p:
			continue
		var kin := person_mothers[q] == id or person_fathers[q] == id or person_ids[q] == person_mothers[p] or person_ids[q] == person_fathers[p]
		if kin:
			person_grief[q] = maxi(person_grief[q], 5)
			if person_mothers[q] == id or person_fathers[q] == id:
				life(person_ids[q], "Lost %s %s." % ["their mother" if person_sexes[p] == "f" else "their father", person_names[p]], "grief")
		elif bond(id, person_ids[q]) >= 50:
			person_grief[q] = maxi(person_grief[q], 2)
	_bequeath(p)
	_forget_bonds(id)
	remove_person(p)
	if was_chief and t != -1:
		tribe_chiefs[t] = -1
	if dead.size() > MAX_DEAD:
		# The smallest id is the longest-gone; key order isn't stable across a save and load.
		var oldest := 1 << 30
		for key: String in dead:
			oldest = mini(oldest, key.to_int())
		dead.erase(str(oldest))
		lives.erase(str(oldest))


## What someone leaves behind goes to their children in the tribe, else their partner, else the
## tribe's treasury. Rich families stay rich: inequality builds over generations.
func _bequeath(p: int) -> void:
	var wealth := person_wealth[p]
	if wealth <= 0:
		return
	var id := person_ids[p]
	var heirs: Array[int] = []
	for q: int in person_ids.size():
		if q != p and (person_mothers[q] == id or person_fathers[q] == id) and person_tribes[q] == person_tribes[p]:
			heirs.append(q)
	if heirs.is_empty():
		var partner := index_of(person_partners[p])
		if partner != -1:
			heirs.append(partner)
	if heirs.is_empty():
		var t := tribe_index(person_tribes[p])
		if t != -1:
			tribe_treasury[t] += wealth
		return
	@warning_ignore("integer_division")
	var share := wealth / heirs.size()
	for q: int in heirs:
		person_wealth[q] += share
	person_wealth[p] = 0


func _forget_bonds(id: int) -> void:
	var prefix := "%d|" % id
	var suffix := "|%d" % id
	for table: Dictionary in [bonds, romance]:
		for key: String in table.keys():
			if key.begins_with(prefix) or key.ends_with(suffix):
				table.erase(key)


## Adds a line to someone's life story.
func life(id: int, text: String, kind: String = "") -> void:
	var key := str(id)
	if not lives.has(key):
		lives[key] = []
	var story: Array = lives[key]
	story.append({"t": tick, "text": text, "kind": kind})
	if story.size() > MAX_LIFE_ENTRIES:
		story.remove_at(1)


static func pair_key(a: int, b: int) -> String:
	return "%d|%d" % [a, b] if a < b else "%d|%d" % [b, a]


func bond(a: int, b: int) -> int:
	return int(bonds.get(pair_key(a, b), 0))


func change_bond(a: int, b: int, delta: int) -> int:
	var key := pair_key(a, b)
	var value := clampi(int(bonds.get(key, 0)) + delta, -100, 100)
	if value == 0:
		bonds.erase(key)
	else:
		bonds[key] = value
	return value


func love(a: int, b: int) -> int:
	return int(romance.get(pair_key(a, b), 0))


func change_love(a: int, b: int, delta: int) -> int:
	var key := pair_key(a, b)
	var value := clampi(int(romance.get(key, 0)) + delta, 0, 100)
	if value == 0:
		romance.erase(key)
	else:
		romance[key] = value
	return value


## Remembers a chat, quarrel or courtship for the view. Not saved, never read by the sim.
func meet(a: int, b: int, kind: String) -> void:
	meetings.append({"id": next_meeting_id, "a": a, "b": b, "kind": kind, "tick": tick})
	next_meeting_id += 1
	if meetings.size() > 96:
		meetings = meetings.slice(meetings.size() - 96)


# --- Buildings ----------------------------------------------------------------------

## A building handle: add_building() returns one so callers can finish it on the spot.
class Handle:
	var index: int

	func _init(i: int) -> void:
		index = i

	func done(state: WorldState) -> int:
		state.building_progress[index] = int(Buildings.TYPES.get(state.building_types[index], {}).get("work", 0))
		state.building_done[index] = state.tick
		return index


func add_building(tribe_name: String, type: String, slot: int) -> Handle:
	building_ids.append(next_building_id)
	next_building_id += 1
	building_types.append(type)
	building_tribes.append(tribe_name)
	building_slots.append(slot)
	building_progress.append(0)
	building_done.append(-1)
	return Handle.new(building_ids.size() - 1)


func remove_building(b: int) -> void:
	var id := building_ids[b]
	for p: int in person_ids.size():
		if person_homes[p] == id:
			person_homes[p] = -1
	var t := tribe_index(building_tribes[b])
	if t != -1 and tribe_project[t] == id:
		tribe_project[t] = -1
	for array: Variant in [building_ids, building_types, building_tribes, building_slots, building_progress, building_done]:
		array.remove_at(b)


func building_index(id: int) -> int:
	return Array(building_ids).find(id)


func buildings_of(tribe_name: String) -> Array[int]:
	var found: Array[int] = []
	for b: int in building_ids.size():
		if building_tribes[b] == tribe_name:
			found.append(b)
	return found


## Finished buildings of a type in a tribe.
func count_buildings(tribe_name: String, type: String) -> int:
	var count := 0
	for b: int in building_ids.size():
		if building_tribes[b] == tribe_name and building_types[b] == type and building_done[b] != -1:
			count += 1
	return count


func is_built(b: int) -> bool:
	return building_done[b] != -1


func residents(building_id: int) -> int:
	var count := 0
	for p: int in person_ids.size():
		if person_homes[p] == building_id:
			count += 1
	return count


# --- Water --------------------------------------------------------------------------

func add_water(water_name: String, capacity: float) -> void:
	water_names.append(water_name)
	water_capacity.append(capacity)
	water_level.append(1.0)


func drinkers(water: int) -> int:
	var total := 0
	for i: int in tribe_count():
		if tribe_water[i] == water:
			total += tribe_population[i]
	return total


## The water source that could take the most extra people right now.
func roomiest_water() -> int:
	var best := 0
	var best_room := -INF
	for w: int in water_names.size():
		var room := water_capacity[w] * water_level[w] - drinkers(w)
		if room > best_room:
			best = w
			best_room = room
	return best


# --- Tribe relations ----------------------------------------------------------------

static func relation_key(a: String, b: String) -> String:
	return "%s|%s" % [a, b] if a < b else "%s|%s" % [b, a]


func relation(a: String, b: String) -> int:
	return int(relations.get(relation_key(a, b), 0))


func set_relation(a: String, b: String, value: int) -> void:
	var key := relation_key(a, b)
	value = clampi(value, -100, 100)
	if value == 0:
		relations.erase(key)
	else:
		relations[key] = value


func change_relation(a: String, b: String, delta: int) -> void:
	set_relation(a, b, relation(a, b) + delta)


## A word for a relation, for the AI and the UI.
static func relation_word(value: int) -> String:
	if value <= -60:
		return "blood feud"
	if value <= -25:
		return "rivals"
	if value < 25:
		return "wary" if value < 0 else "neutral"
	if value < 60:
		return "friends"
	return "kin"


# --- Bookkeeping --------------------------------------------------------------------

## Event data must hold only strings and whole numbers so it survives a JSON round trip.
## Snaps every saved float to FLOAT_STEP. Runs after each tick and each player action.
func settle() -> void:
	rainfall = snappedf(rainfall, FLOAT_STEP)
	influence = snappedf(influence, FLOAT_STEP)
	for i: int in tribe_count():
		tribe_food[i] = snappedf(tribe_food[i], FLOAT_STEP)
		tribe_hunt_credit[i] = snappedf(tribe_hunt_credit[i], FLOAT_STEP)
		tribe_wood[i] = snappedf(tribe_wood[i], FLOAT_STEP)
		tribe_stone[i] = snappedf(tribe_stone[i], FLOAT_STEP)
		tribe_tools[i] = snappedf(tribe_tools[i], FLOAT_STEP)
		tribe_cloth[i] = snappedf(tribe_cloth[i], FLOAT_STEP)
		tribe_pots[i] = snappedf(tribe_pots[i], FLOAT_STEP)
		tribe_metal[i] = snappedf(tribe_metal[i], FLOAT_STEP)
		tribe_treasury[i] = snappedf(tribe_treasury[i], FLOAT_STEP)
	pollution = snappedf(pollution, FLOAT_STEP)
	for w: int in water_names.size():
		water_level[w] = snappedf(water_level[w], FLOAT_STEP)


func log_event(type: String, data: Dictionary = {}) -> void:
	events.append({"id": next_event_id, "tick": tick, "type": type, "data": data})
	next_event_id += 1
	if events.size() > MAX_EVENTS:
		# Daily life is forgotten before the turns of history the chronicle needs.
		for j: int in events.size():
			if not EventText.is_major(events[j]):
				events.remove_at(j)
				return
		events.remove_at(0)


## Compact, AI-friendly view of the world, including the god's standing with the people.
func summarize(recent_event_count: int = 12) -> Dictionary:
	var tribes: Array[Dictionary] = []
	for i: int in tribe_count():
		var population := tribe_population[i]
		var stages := People.stage_counts(self, tribe_names[i])
		var jobs := {}
		for p: int in people_of(tribe_names[i]):
			if person_jobs[p]:
				jobs[person_jobs[p]] = int(jobs.get(person_jobs[p], 0)) + 1
		var built := {}
		for b: int in buildings_of(tribe_names[i]):
			if is_built(b) and building_types[b] != "fire":
				built[building_types[b]] = int(built.get(building_types[b], 0)) + 1
		tribes.append({
			"name": tribe_names[i],
			"population": population,
			"children": int(stages.get("child", 0)) + int(stages.get("infant", 0)),
			"elders": int(stages.get("elder", 0)),
			"food_months": snappedf(tribe_food[i] / maxf(population, 1.0) / DAYS_PER_MONTH, 0.1),
			"wood": roundi(tribe_wood[i]),
			"drinks_from": water_names[tribe_water[i]],
			"mood": Needs.mood_word(Needs.mood(self, i)),
			"jobs": jobs,
			"buildings": built,
			"knows": Array(tribe_knowledge[i]),
			"society": Society.summary(self, i),
		})
		var leader := chief_of(tribe_names[i])
		if leader != -1:
			tribes[-1]["chief"] = {"name": person_names[leader], "age": People.age(self, leader), "traits": Array(People.traits_of(self, leader))}
		# The words on their banner and walls, once written, so the Oracle can quote them.
		var motto := String(AssetBook.spec(self, "heraldry", tribe_names[i]).get("motto", ""))
		if motto:
			tribes[-1]["motto"] = motto
		var slogans: Array[String] = []
		for law: String in Society.laws_of(self, i):
			var slogan := String(AssetBook.spec(self, "poster", "%s|%s" % [tribe_names[i], law]).get("slogan", ""))
			if slogan:
				slogans.append(slogan)
		if not slogans.is_empty():
			tribes[-1]["slogans"] = slogans.slice(maxi(slogans.size() - 3, 0))
	var water: Array[Dictionary] = []
	for w: int in water_names.size():
		water.append({"name": water_names[w], "fullness": snappedf(water_level[w], 0.01), "drinkers": drinkers(w)})
	var ties: Array[Dictionary] = []
	var keys := relations.keys()
	keys.sort()
	for key: String in keys:
		var value := int(relations[key])
		if absi(value) >= 25:
			ties.append({"tribes": key.split("|"), "relation": value, "word": relation_word(value)})
	var recent: Array[Dictionary] = []
	var major := EventText.major(events)
	for event: Dictionary in major.slice(maxi(major.size() - recent_event_count, 0)):
		recent.append({"year": year_of(int(event["tick"])), "type": event["type"], "data": event["data"]})
	var counts := EventText.count_since(events, tick - DAYS_PER_YEAR)
	var god := disposition()
	var summary := {
		"island": WorldGen.describe(world),
		"year": year(),
		"season": season(),
		"in_drought": drought_months_left > 0,
		"total_population": total_population(),
		"last_year": {"births": int(counts.get("birth", 0)), "deaths": int(counts.get("death", 0)), "marriages": int(counts.get("marriage", 0))},
		"generations": People.max_generation(self),
		"tribes": tribes,
		"water_sources": water,
		"relations": ties,
		"god": {"influence": snappedf(influence, 0.1), "kindness": kindness, "leaning": god["leaning"], "hand": god["hand"]},
		"recent_events": recent,
	}
	if pollution >= 5.0:
		summary["pollution"] = roundi(pollution)
	if not destiny.is_empty():
		summary["destiny"] = destiny
	return summary


func to_dict() -> Dictionary:
	var genomes: Array[String] = []
	var skills: Array[String] = []
	for p: int in person_ids.size():
		genomes.append(Genetics.to_hex(person_genomes[p]))
		skills.append(person_skills[p].hex_encode())
	var animal_hex: Array[String] = []
	for genome: PackedByteArray in animal_genomes:
		animal_hex.append(Genetics.to_hex(genome))
	var knowledge: Array = []
	for known: PackedStringArray in tribe_knowledge:
		knowledge.append(Array(known))
	return {
		"version": SAVE_VERSION,
		"seed": str(seed_value),
		"tick": tick,
		"rng": rng.to_dict(),
		"world": world,
		"rainfall": rainfall,
		"drought_months_left": drought_months_left,
		"blessed_rain_months": blessed_rain_months,
		"tribe_names": Array(tribe_names),
		"tribe_food": Array(tribe_food),
		"tribe_hunt_credit": Array(tribe_hunt_credit),
		"tribe_wood": Array(tribe_wood),
		"tribe_stone": Array(tribe_stone),
		"tribe_tools": Array(tribe_tools),
		"tribe_cloth": Array(tribe_cloth),
		"tribe_pots": Array(tribe_pots),
		"tribe_water": Array(tribe_water),
		"tribe_chiefs": Array(tribe_chiefs),
		"tribe_founded": Array(tribe_founded),
		"tribe_hungry_days": Array(tribe_hungry_days),
		"tribe_project": Array(tribe_project),
		"tribe_plan": Array(tribe_plan),
		"tribe_knowledge": knowledge,
		"tribe_work": tribe_work,
		"tribe_metal": Array(tribe_metal),
		"tribe_treasury": Array(tribe_treasury),
		"tribe_culture": tribe_culture,
		"tribe_laws": tribe_laws,
		"tribe_power": tribe_power,
		"tribe_legitimacy": Array(tribe_legitimacy),
		"tribe_unrest": Array(tribe_unrest),
		"tribe_fear": Array(tribe_fear),
		"tribe_dynasty": Array(tribe_dynasty),
		"tribe_overlord": Array(tribe_overlord),
		"tribe_vassal_since": Array(tribe_vassal_since),
		"tribe_crisis": tribe_crisis,
		"tribe_ruler": Array(tribe_ruler),
		"tribe_ruler_since": Array(tribe_ruler_since),
		"tribe_language": tribe_language,
		"water_names": Array(water_names),
		"water_capacity": Array(water_capacity),
		"water_level": Array(water_level),
		"person_ids": Array(person_ids),
		"person_names": Array(person_names),
		"person_families": Array(person_families),
		"person_sexes": Array(person_sexes),
		"person_born": Array(person_born),
		"person_tribes": Array(person_tribes),
		"person_mothers": Array(person_mothers),
		"person_fathers": Array(person_fathers),
		"person_partners": Array(person_partners),
		"person_genomes": genomes,
		"person_traits": Array(person_traits),
		"person_jobs": Array(person_jobs),
		"person_skills": skills,
		"person_health": Array(person_health),
		"person_mood": Array(person_mood),
		"person_homes": Array(person_homes),
		"person_due": Array(person_due),
		"person_baby_fathers": Array(person_baby_fathers),
		"person_sick": Array(person_sick),
		"person_grief": Array(person_grief),
		"person_attraction": Array(person_attraction),
		"person_generations": Array(person_generations),
		"person_wealth": Array(person_wealth),
		"person_status": Array(person_status),
		"person_loyalty": Array(person_loyalty),
		"person_detained": Array(person_detained),
		"next_person_id": next_person_id,
		"dead": dead,
		"lives": lives,
		"bonds": bonds,
		"romance": romance,
		"building_ids": Array(building_ids),
		"building_types": Array(building_types),
		"building_tribes": Array(building_tribes),
		"building_slots": Array(building_slots),
		"building_progress": Array(building_progress),
		"building_done": Array(building_done),
		"next_building_id": next_building_id,
		"relations": relations,
		"animal_ids": Array(animal_ids),
		"animal_species": Array(animal_species),
		"animal_genomes": animal_hex,
		"animal_born": Array(animal_born),
		"animal_sex": Array(animal_sex),
		"animal_condition": Array(animal_condition),
		"next_animal_id": next_animal_id,
		"animal_seeded": Array(animal_seeded),
		"animal_wiped": Array(animal_wiped),
		"events": events,
		"next_event_id": next_event_id,
		"gene_history": gene_history,
		"influence": influence,
		"kindness": kindness,
		"god_mercy": god_mercy,
		"god_wrath": god_wrath,
		"god_act_ticks": Array(god_act_ticks),
		"god_act_leanings": Array(god_act_leanings),
		"pollution": pollution,
		"destiny": destiny,
		"destiny_progress": destiny_progress,
		"society_history": society_history,
		"assets": assets,
		"prophecy": prophecy.to_dict() if prophecy else null,
		"resolved_prophecy": resolved_prophecy.to_dict() if resolved_prophecy else null,
	}


static func from_dict(data: Dictionary) -> WorldState:
	if int(data.get("version", 0)) != SAVE_VERSION:
		push_error("Unsupported save version: %s" % data.get("version"))
		return null
	var state := WorldState.new()
	state.seed_value = String(data["seed"]).to_int()
	state.tick = int(data["tick"])
	state.rng = SimRng.from_dict(data["rng"])
	state.world = data["world"] # every number in it is a float on the save grid, so it round-trips as is
	state.rainfall = float(data["rainfall"])
	state.drought_months_left = int(data["drought_months_left"])
	state.blessed_rain_months = int(data["blessed_rain_months"])
	state.tribe_names = PackedStringArray(data["tribe_names"])
	state.tribe_food = PackedFloat64Array(data["tribe_food"])
	# Saves from before hunt credit start each tribe with none owed.
	var hunt_credit: Array = data.get("tribe_hunt_credit", [])
	state.tribe_hunt_credit = PackedFloat64Array()
	for t: int in state.tribe_names.size():
		state.tribe_hunt_credit.append(float(hunt_credit[t]) if t < hunt_credit.size() else 0.0)
	state.tribe_wood = PackedFloat64Array(data["tribe_wood"])
	state.tribe_stone = PackedFloat64Array(data["tribe_stone"])
	state.tribe_tools = PackedFloat64Array(data["tribe_tools"])
	state.tribe_cloth = PackedFloat64Array(data["tribe_cloth"])
	state.tribe_pots = PackedFloat64Array(data["tribe_pots"])
	state.tribe_water = PackedInt32Array(data["tribe_water"])
	state.tribe_chiefs = PackedInt32Array(data["tribe_chiefs"])
	state.tribe_founded = PackedInt32Array(data["tribe_founded"])
	state.tribe_hungry_days = PackedInt32Array(data["tribe_hungry_days"])
	state.tribe_project = PackedInt32Array(data["tribe_project"])
	state.tribe_plan = PackedStringArray(data["tribe_plan"])
	for known: Array in data["tribe_knowledge"]:
		state.tribe_knowledge.append(PackedStringArray(known))
	for work: Dictionary in data["tribe_work"]:
		var clean := {}
		for job: String in work:
			clean[job] = float(work[job])
		state.tribe_work.append(clean)
	state.tribe_metal = PackedFloat64Array(data["tribe_metal"])
	state.tribe_treasury = PackedFloat64Array(data["tribe_treasury"])
	for table: String in ["tribe_culture", "tribe_laws", "tribe_power", "tribe_crisis"]:
		var target: Array = state.get(table)
		for entry: Dictionary in data[table]:
			target.append(_whole_numbers_to_int(entry))
	state.tribe_legitimacy = PackedInt32Array(data["tribe_legitimacy"])
	state.tribe_unrest = PackedInt32Array(data["tribe_unrest"])
	state.tribe_fear = PackedInt32Array(data["tribe_fear"])
	state.tribe_dynasty = PackedStringArray(data["tribe_dynasty"])
	state.tribe_overlord = PackedStringArray(data["tribe_overlord"])
	state.tribe_vassal_since = PackedInt32Array(data["tribe_vassal_since"])
	state.tribe_ruler = PackedInt32Array(data["tribe_ruler"])
	state.tribe_ruler_since = PackedInt32Array(data["tribe_ruler_since"])
	# Saves from before languages speak the default sound.
	var languages: Array = data.get("tribe_language", [])
	for t: int in state.tribe_names.size():
		state.tribe_language.append(Language.clamp_spec(languages[t]) if t < languages.size() else {})
	state.water_names = PackedStringArray(data["water_names"])
	state.water_capacity = PackedFloat64Array(data["water_capacity"])
	state.water_level = PackedFloat64Array(data["water_level"])
	state.person_ids = PackedInt32Array(data["person_ids"])
	state.person_names = PackedStringArray(data["person_names"])
	state.person_families = PackedStringArray(data["person_families"])
	state.person_sexes = PackedStringArray(data["person_sexes"])
	state.person_born = PackedInt32Array(data["person_born"])
	state.person_tribes = PackedStringArray(data["person_tribes"])
	state.person_mothers = PackedInt32Array(data["person_mothers"])
	state.person_fathers = PackedInt32Array(data["person_fathers"])
	state.person_partners = PackedInt32Array(data["person_partners"])
	for hex: String in data["person_genomes"]:
		state.person_genomes.append(Genetics.from_hex(hex))
	state.person_traits = PackedStringArray(data["person_traits"])
	state.person_jobs = PackedStringArray(data["person_jobs"])
	for hex: String in data["person_skills"]:
		state.person_skills.append(hex.hex_decode())
	state.person_health = PackedInt32Array(data["person_health"])
	state.person_mood = PackedInt32Array(data["person_mood"])
	state.person_homes = PackedInt32Array(data["person_homes"])
	state.person_due = PackedInt32Array(data["person_due"])
	state.person_baby_fathers = PackedInt32Array(data["person_baby_fathers"])
	state.person_sick = PackedInt32Array(data["person_sick"])
	state.person_grief = PackedInt32Array(data["person_grief"])
	state.person_attraction = PackedInt32Array(data["person_attraction"])
	state.person_generations = PackedInt32Array(data["person_generations"])
	state.person_wealth = PackedInt32Array(data["person_wealth"])
	state.person_status = PackedStringArray(data["person_status"])
	state.person_loyalty = PackedInt32Array(data["person_loyalty"])
	state.person_detained = PackedInt32Array(data["person_detained"])
	state.next_person_id = int(data["next_person_id"])
	state.dead = _whole_numbers_to_int(data["dead"])
	state.lives = _whole_numbers_to_int(data["lives"])
	for key: String in data["bonds"]:
		state.bonds[key] = int(data["bonds"][key])
	for key: String in data["romance"]:
		state.romance[key] = int(data["romance"][key])
	state.building_ids = PackedInt32Array(data["building_ids"])
	state.building_types = PackedStringArray(data["building_types"])
	state.building_tribes = PackedStringArray(data["building_tribes"])
	state.building_slots = PackedInt32Array(data["building_slots"])
	state.building_progress = PackedInt32Array(data["building_progress"])
	state.building_done = PackedInt32Array(data["building_done"])
	state.next_building_id = int(data["next_building_id"])
	for key: String in data["relations"]:
		state.relations[key] = int(data["relations"][key])
	# A save from before animals has none of these keys: leave the herds empty, do not reseed.
	if data.has("animal_ids"):
		state.animal_ids = PackedInt32Array(data["animal_ids"])
		state.animal_species = PackedStringArray(data["animal_species"])
		for hex_text: String in data["animal_genomes"]:
			state.animal_genomes.append(Genetics.from_hex(hex_text))
		state.animal_born = PackedInt32Array(data["animal_born"])
		state.animal_sex = PackedStringArray(data["animal_sex"])
		state.animal_condition = PackedInt32Array(data["animal_condition"])
		state.next_animal_id = int(data["next_animal_id"])
		state.animal_seeded = PackedStringArray(data.get("animal_seeded", []))
		state.animal_wiped = PackedStringArray(data.get("animal_wiped", []))
	state.next_event_id = int(data["next_event_id"])
	state.influence = float(data["influence"])
	state.kindness = int(data["kindness"])
	# Saves from before the disposition existed load with a god who hasn't shown their nature.
	state.god_mercy = int(data.get("god_mercy", 0))
	state.god_wrath = int(data.get("god_wrath", 0))
	state.god_act_ticks = PackedInt32Array(data.get("god_act_ticks", []))
	state.god_act_leanings = PackedInt32Array(data.get("god_act_leanings", []))
	state.pollution = float(data["pollution"])
	state.destiny = _whole_numbers_to_int(data["destiny"])
	state.destiny_progress = _whole_numbers_to_int(data["destiny_progress"])
	for entry: Dictionary in data["society_history"]:
		state.society_history.append(_whole_numbers_to_int(entry))
	state.assets = _whole_numbers_to_int(data.get("assets", {})) # saves from before M3.5 have none
	if data["prophecy"] is Dictionary:
		state.prophecy = Prophecy.from_dict(data["prophecy"])
	if data["resolved_prophecy"] is Dictionary:
		state.resolved_prophecy = Prophecy.from_dict(data["resolved_prophecy"])
	for event: Dictionary in data["events"]:
		state.events.append(_whole_numbers_to_int(event))
	for entry: Dictionary in data["gene_history"]:
		state.gene_history.append(_whole_numbers_to_int(entry))
	state.tribe_population.resize(state.tribe_names.size())
	state.tribe_population.fill(0)
	for p: int in state.person_ids.size():
		var t := state.tribe_index(state.person_tribes[p])
		if t != -1:
			state.tribe_population[t] += 1
	return state


## JSON turns every number into a float; saved data only ever holds whole numbers outside the
## arrays converted above.
static func _whole_numbers_to_int(value: Variant) -> Variant:
	if value is float and is_equal_approx(value, roundf(value)):
		return int(value)
	if value is Dictionary:
		var result := {}
		for key: Variant in value:
			result[key] = _whole_numbers_to_int(value[key])
		return result
	if value is Array:
		var result := []
		for item: Variant in value:
			result.append(_whole_numbers_to_int(item))
		return result
	return value


func to_json() -> String:
	return JSON.stringify(to_dict(), "", true, true)


## Same seed and same inputs must always give the same checksum.
func checksum() -> String:
	return to_json().sha256_text()
