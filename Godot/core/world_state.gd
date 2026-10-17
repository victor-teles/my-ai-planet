class_name WorldState
extends RefCounted
## The whole simulated world. One tick is one month.
## Tribes are stored as parallel packed arrays (index i is the same tribe in every
## array) instead of one object per tribe, so the sim stays fast in GDScript.

const SAVE_VERSION := 3
const MONTHS_PER_YEAR := 12
const MAX_EVENTS := 200
## Saved floats are kept on a grid of 1/1024: Godot's JSON writer misprints the last digit of
## about a quarter of arbitrary doubles, but numbers on this grid survive a round trip bit for bit.
const FLOAT_STEP := 1.0 / 1024.0

var seed_value: int = 0
var tick: int = 0
var rng: SimRng

# Climate
var rainfall: float = 1.0 ## 1.0 is a normal month
var drought_months_left: int = 0

# Tribes
var tribe_names := PackedStringArray()
var tribe_population := PackedInt32Array()
var tribe_food := PackedFloat64Array() ## stored food, in person-months
var tribe_water := PackedInt32Array() ## index of the water source the tribe drinks from

# Water sources: the pond and the springs. Rain fills them, drinking empties them.
var water_names := PackedStringArray()
var water_capacity := PackedFloat64Array() ## people a full source can serve without falling
var water_level := PackedFloat64Array() ## 0 is dry, 1 is full

# Citizens: the named notables of each tribe (see Citizens). Parallel arrays like the tribes.
var citizen_ids := PackedInt32Array() ## stable, so views can follow someone across deaths and births
var citizen_names := PackedStringArray()
var citizen_tribes := PackedStringArray()
var citizen_born := PackedInt32Array() ## tick of birth
var citizen_traits := PackedStringArray() ## two trait ids joined by "|"
var citizen_sexes := PackedStringArray() ## "f" or "m"
var next_citizen_id: int = 0

## How the tribes feel about each other: "A|B" (names sorted) -> -100 (blood feud) to 100 (kin).
## Pairs that aren't here are 0, so a new tribe starts as strangers to everyone.
var relations: Dictionary = {}
const KIN_RELATION := 40 ## a tribe that splits off starts out this friendly with the one it left

# The player god
const MAX_INFLUENCE := 12.0
const STARTING_INFLUENCE := 5.0
var influence: float = STARTING_INFLUENCE
## Sum of the kindness of every miracle cast: positive is benevolent, negative is wrathful.
var kindness: int = 0
var blessed_rain_months: int = 0
## The Oracle's current prophecy, checked yearly by ProphecySystem. Null between prophecies.
var prophecy: Prophecy
## The last prophecy that came true or broke, kept for the reveal.
var resolved_prophecy: Prophecy

## What happened, newest last. The Oracle reads this to explain cause and effect.
var events: Array[Dictionary] = []
## Increases with every event, so views can tell which events they haven't shown yet.
var next_event_id: int = 0


static func create(new_seed: int) -> WorldState:
	var state := WorldState.new()
	state.seed_value = new_seed
	state.rng = SimRng.new(new_seed)
	state.add_water("the Pond", 260.0)
	state.add_water("%s Spring" % NameGen.tribe_name(state.rng), 130.0)
	state.add_water("%s Spring" % NameGen.tribe_name(state.rng), 130.0)
	var first := state.add_tribe(NameGen.tribe_name(state.rng), 30, 60.0, 0)
	for c: int in Citizens.target_count(state.tribe_population[first]):
		state.add_citizen(state.tribe_names[first], state.rng.randi_range(Citizens.COMING_OF_AGE_MIN, 55))
	return state


func year() -> int:
	return year_of(tick)


@warning_ignore("integer_division")
static func year_of(at_tick: int) -> int:
	return at_tick / MONTHS_PER_YEAR


func month() -> int:
	return tick % MONTHS_PER_YEAR


## 1 (gentle fable) to 5 (grim chronicle): how the AI should write about this world.
## Driven by how kind or wrathful the player has been, and by how the people are doing.
func tone() -> int:
	var level := 2.0 - kindness / 3.0
	if drought_months_left > 0:
		level += 0.5
	if ticks_since("war") < 10 * MONTHS_PER_YEAR:
		level += 0.5
	return clampi(roundi(level), 1, 5)


## Ticks since the newest event of this type that is still in the log, or a huge number if none is.
func ticks_since(type: String) -> int:
	for j: int in range(events.size() - 1, -1, -1):
		if events[j]["type"] == type:
			return tick - int(events[j]["tick"])
	return 1 << 30


func tribe_index(tribe_name: String) -> int:
	return Array(tribe_names).find(tribe_name)


func tribe_count() -> int:
	return tribe_names.size()


func total_population() -> int:
	var total := 0
	for population: int in tribe_population:
		total += population
	return total


func add_tribe(tribe_name: String, population: int, food: float, water: int) -> int:
	tribe_names.append(tribe_name)
	tribe_population.append(population)
	tribe_food.append(food)
	tribe_water.append(water)
	return tribe_names.size() - 1


## Removes a tribe and its citizens. To keep the citizens (a merge), move them first.
func remove_tribe(index: int) -> void:
	var gone := tribe_names[index]
	for key: String in relations.keys():
		if gone in key.split("|"):
			relations.erase(key)
	for c: int in range(citizen_ids.size() - 1, -1, -1):
		if citizen_tribes[c] == gone:
			remove_citizen(c)
	tribe_names.remove_at(index)
	tribe_population.remove_at(index)
	tribe_food.remove_at(index)
	tribe_water.remove_at(index)


## Part of a tribe leaves with its share of the food and founds a new tribe at the water
## source with the most room. Returns the new tribe's index.
func split_tribe(index: int, leaving: int) -> int:
	var food := tribe_food[index] * leaving / tribe_population[index]
	tribe_population[index] -= leaving
	tribe_food[index] -= food
	var new_name := NameGen.tribe_name(rng)
	var new_index := add_tribe(new_name, leaving, food, roomiest_water())
	set_relation(tribe_names[index], new_name, KIN_RELATION)
	# The young lead the way out.
	var members := citizens_of(tribe_names[index])
	members.sort_custom(func(a: int, b: int) -> bool: return citizen_born[a] > citizen_born[b])
	for c: int in members.slice(0, mini(Citizens.target_count(leaving), members.size() - 1)):
		citizen_tribes[c] = new_name
	log_event("tribe_split", {"from": tribe_names[index], "to": new_name, "people": leaving})
	return new_index


## Adds a citizen of the given age with a fresh name and traits. Returns their id.
func add_citizen(tribe_name: String, age_years: int) -> int:
	var id := next_citizen_id
	next_citizen_id += 1
	citizen_ids.append(id)
	citizen_names.append(NameGen.person_name(rng))
	citizen_tribes.append(tribe_name)
	citizen_born.append(tick - age_years * MONTHS_PER_YEAR)
	citizen_traits.append("|".join(Citizens.random_traits(rng)))
	citizen_sexes.append("f" if rng.chance(0.5) else "m")
	return id


func remove_citizen(c: int) -> void:
	citizen_ids.remove_at(c)
	citizen_names.remove_at(c)
	citizen_tribes.remove_at(c)
	citizen_born.remove_at(c)
	citizen_traits.remove_at(c)
	citizen_sexes.remove_at(c)


func citizens_of(tribe_name: String) -> Array[int]:
	var members: Array[int] = []
	for c: int in citizen_ids.size():
		if citizen_tribes[c] == tribe_name:
			members.append(c)
	return members


func move_citizens(from_tribe: String, to_tribe: String) -> void:
	for c: int in citizen_ids.size():
		if citizen_tribes[c] == from_tribe:
			citizen_tribes[c] = to_tribe


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


## Event data must hold only strings and whole numbers so it survives a JSON round trip.
## Snaps every saved float to FLOAT_STEP. Runs after each tick and each player action.
func settle() -> void:
	rainfall = snappedf(rainfall, FLOAT_STEP)
	influence = snappedf(influence, FLOAT_STEP)
	for i: int in tribe_count():
		tribe_food[i] = snappedf(tribe_food[i], FLOAT_STEP)
	for w: int in water_names.size():
		water_level[w] = snappedf(water_level[w], FLOAT_STEP)


func log_event(type: String, data: Dictionary = {}) -> void:
	events.append({"id": next_event_id, "tick": tick, "type": type, "data": data})
	next_event_id += 1
	if events.size() > MAX_EVENTS:
		events = events.slice(events.size() - MAX_EVENTS)


## Compact, AI-friendly view of the world, including the god's standing with the people.
func summarize(recent_event_count: int = 10) -> Dictionary:
	var tribes: Array[Dictionary] = []
	for i: int in tribe_count():
		var population := tribe_population[i]
		tribes.append({
			"name": tribe_names[i],
			"population": population,
			"food_months": snappedf(tribe_food[i] / maxf(population, 1.0), 0.1),
			"drinks_from": water_names[tribe_water[i]],
			"mood": Needs.mood_word(Needs.mood(self, i)),
		})
		var leader := Citizens.chief(self, tribe_names[i])
		if leader != -1:
			tribes[-1]["chief"] = {"name": citizen_names[leader], "traits": Array(Citizens.traits_of(self, leader))}
	var water: Array[Dictionary] = []
	for w: int in water_names.size():
		water.append({"name": water_names[w], "fullness": snappedf(water_level[w], 0.01), "drinkers": drinkers(w)})
	var bonds: Array[Dictionary] = []
	var keys := relations.keys()
	keys.sort()
	for key: String in keys:
		var value := int(relations[key])
		if absi(value) >= 25:
			bonds.append({"tribes": key.split("|"), "relation": value, "word": relation_word(value)})
	var recent: Array[Dictionary] = []
	for event: Dictionary in events.slice(maxi(events.size() - recent_event_count, 0)):
		recent.append({"year": year_of(int(event["tick"])), "type": event["type"], "data": event["data"]})
	return {
		"year": year(),
		"month": month(),
		"in_drought": drought_months_left > 0,
		"total_population": total_population(),
		"tribes": tribes,
		"water_sources": water,
		"relations": bonds,
		"god": {"influence": snappedf(influence, 0.1), "kindness": kindness},
		"recent_events": recent,
	}


func to_dict() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"seed": str(seed_value),
		"tick": tick,
		"rng": rng.to_dict(),
		"rainfall": rainfall,
		"drought_months_left": drought_months_left,
		"tribe_names": Array(tribe_names),
		"tribe_population": Array(tribe_population),
		"tribe_food": Array(tribe_food),
		"tribe_water": Array(tribe_water),
		"water_names": Array(water_names),
		"water_capacity": Array(water_capacity),
		"water_level": Array(water_level),
		"relations": relations,
		"citizen_ids": Array(citizen_ids),
		"citizen_names": Array(citizen_names),
		"citizen_tribes": Array(citizen_tribes),
		"citizen_born": Array(citizen_born),
		"citizen_traits": Array(citizen_traits),
		"citizen_sexes": Array(citizen_sexes),
		"next_citizen_id": next_citizen_id,
		"events": events,
		"next_event_id": next_event_id,
		"influence": influence,
		"kindness": kindness,
		"blessed_rain_months": blessed_rain_months,
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
	state.rainfall = float(data["rainfall"])
	state.drought_months_left = int(data["drought_months_left"])
	state.tribe_names = PackedStringArray(data["tribe_names"])
	state.tribe_population = PackedInt32Array(data["tribe_population"])
	state.tribe_food = PackedFloat64Array(data["tribe_food"])
	state.tribe_water = PackedInt32Array(data["tribe_water"])
	state.water_names = PackedStringArray(data["water_names"])
	state.water_capacity = PackedFloat64Array(data["water_capacity"])
	state.water_level = PackedFloat64Array(data["water_level"])
	for key: String in data["relations"]:
		state.relations[key] = int(data["relations"][key])
	state.citizen_ids = PackedInt32Array(data["citizen_ids"])
	state.citizen_names = PackedStringArray(data["citizen_names"])
	state.citizen_tribes = PackedStringArray(data["citizen_tribes"])
	state.citizen_born = PackedInt32Array(data["citizen_born"])
	state.citizen_traits = PackedStringArray(data["citizen_traits"])
	state.citizen_sexes = PackedStringArray(data["citizen_sexes"])
	state.next_citizen_id = int(data["next_citizen_id"])
	state.next_event_id = int(data["next_event_id"])
	state.influence = float(data["influence"])
	state.kindness = int(data["kindness"])
	state.blessed_rain_months = int(data["blessed_rain_months"])
	if data["prophecy"] is Dictionary:
		state.prophecy = Prophecy.from_dict(data["prophecy"])
	if data["resolved_prophecy"] is Dictionary:
		state.resolved_prophecy = Prophecy.from_dict(data["resolved_prophecy"])
	for event: Dictionary in data["events"]:
		state.events.append(_whole_numbers_to_int(event))
	return state


## JSON turns every number into a float; event data only ever holds whole numbers.
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
