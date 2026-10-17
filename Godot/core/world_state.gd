class_name WorldState
extends RefCounted
## The whole simulated world. One tick is one month.
## Tribes are stored as parallel packed arrays (index i is the same tribe in every
## array) instead of one object per tribe, so the sim stays fast in GDScript.

const SAVE_VERSION := 1
const MONTHS_PER_YEAR := 12
const MAX_EVENTS := 200

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

# The player god
const MAX_INFLUENCE := 12.0
var influence: float = 5.0
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
	state.add_tribe(NameGen.tribe_name(state.rng), 30, 60.0)
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
	return clampi(roundi(level), 1, 5)


func tribe_index(tribe_name: String) -> int:
	return Array(tribe_names).find(tribe_name)


func tribe_count() -> int:
	return tribe_names.size()


func total_population() -> int:
	var total := 0
	for population: int in tribe_population:
		total += population
	return total


func add_tribe(tribe_name: String, population: int, food: float) -> int:
	tribe_names.append(tribe_name)
	tribe_population.append(population)
	tribe_food.append(food)
	return tribe_names.size() - 1


func remove_tribe(index: int) -> void:
	tribe_names.remove_at(index)
	tribe_population.remove_at(index)
	tribe_food.remove_at(index)


## Event data must hold only strings and whole numbers so it survives a JSON round trip.
func log_event(type: String, data: Dictionary = {}) -> void:
	events.append({"id": next_event_id, "tick": tick, "type": type, "data": data})
	next_event_id += 1
	if events.size() > MAX_EVENTS:
		events = events.slice(events.size() - MAX_EVENTS)


## Compact, AI-friendly view of the world. Never includes anything about the player.
func summarize(recent_event_count: int = 10) -> Dictionary:
	var tribes: Array[Dictionary] = []
	for i: int in tribe_count():
		var population := tribe_population[i]
		tribes.append({
			"name": tribe_names[i],
			"population": population,
			"food_months": snappedf(tribe_food[i] / maxf(population, 1.0), 0.1),
		})
	var recent: Array[Dictionary] = []
	for event: Dictionary in events.slice(maxi(events.size() - recent_event_count, 0)):
		recent.append({"year": year_of(int(event["tick"])), "type": event["type"], "data": event["data"]})
	return {
		"year": year(),
		"month": month(),
		"in_drought": drought_months_left > 0,
		"total_population": total_population(),
		"tribes": tribes,
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
