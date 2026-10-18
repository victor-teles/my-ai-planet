class_name WorldGen
extends RefCounted
## Every seed makes a different island: its biome and climate, how rich its woods, game, fish,
## soil and stone are, which ores lie under it (an island with no tin has to find bronze the hard
## way), its shape and waters, the disasters it is prone to, and the peoples who first land on it,
## each with a culture of their own. The recipe is saved with the world, so a save never depends on
## this code staying the same.
##
## Recipe keys: "name", "biome", "rain", "drought", "winter", "sickness", "rates" ({forage, hunt,
## fish, farm, wood, stone}: multipliers), "ores" ({copper, tin, iron, coal}: 0 is none, up to 1.5),
## "hazard", "island" ({radius, roughness, hills, pond: [x, z], pond_radius, springs}),
## "trees", "rocks" (how thickly the view plants them), "peoples": [{"name", "couples", "culture"}],
## and, added by WorldState.create from the island's shape, "camps": how many tribes it has room for.
## Every number in a recipe is a float on the save grid (WorldState.FLOAT_STEP), so it survives a
## save and load bit for bit.

## biome -> what it does to life. Rates multiply the economy's base rates; "winter" scales the
## harm of the cold months (0 is none, 1 is today's); "sickness" scales fevers.
const BIOMES := {
	"meadow": {"name": "green meadow isle", "rain": 1.0, "drought": 0.045, "winter": 0.8, "sickness": 1.0,
		"rates": {"forage": 1.0, "hunt": 1.0, "fish": 1.0, "farm": 1.05, "wood": 1.0, "stone": 1.0},
		"trees": 1.0, "rocks": 1.0, "hazard": "storms", "culture": {}},
	"steppe": {"name": "dry, windswept steppe", "rain": 0.78, "drought": 0.085, "winter": 0.7, "sickness": 0.85,
		"rates": {"forage": 0.85, "hunt": 1.2, "fish": 0.75, "farm": 0.9, "wood": 0.65, "stone": 1.1},
		"trees": 0.45, "rocks": 1.3, "hazard": "locusts", "culture": {"martial": 15, "openness": 5}},
	"jungle": {"name": "steaming jungle isle", "rain": 1.3, "drought": 0.02, "winter": 0.0, "sickness": 1.2,
		"rates": {"forage": 1.25, "hunt": 0.9, "fish": 1.1, "farm": 0.9, "wood": 1.3, "stone": 0.75},
		"trees": 1.5, "rocks": 0.6, "hazard": "storms", "culture": {"piety": 15}},
	"taiga": {"name": "cold pine-dark isle", "rain": 0.95, "drought": 0.03, "winter": 1.35, "sickness": 0.9,
		"rates": {"forage": 0.75, "hunt": 1.25, "fish": 1.2, "farm": 0.75, "wood": 1.3, "stone": 1.0},
		"trees": 1.3, "rocks": 1.0, "hazard": "blizzards", "culture": {"hierarchy": 10, "openness": -10}},
	"highland": {"name": "high, rocky isle", "rain": 0.92, "drought": 0.05, "winter": 1.1, "sickness": 0.95,
		"rates": {"forage": 0.85, "hunt": 0.95, "fish": 0.8, "farm": 0.85, "wood": 0.85, "stone": 1.5},
		"trees": 0.75, "rocks": 1.8, "hazard": "quakes", "culture": {"hierarchy": 5, "martial": 5}},
}
const BIOME_ORDER: Array[String] = ["meadow", "steppe", "jungle", "taiga", "highland"]
const ORES: Array[String] = ["copper", "tin", "iron", "coal"]
## Chance an ore is missing from an island entirely.
const ORE_MISSING := {"copper": 0.15, "tin": 0.35, "iron": 0.2, "coal": 0.25}
## Each people's leanings start here and drift for ever after (see Society.CULTURE_AXES).
const CULTURE_SPREAD := 35


## `bands` forces how many peoples land first (0 lets the seed decide); tests use 1.
static func generate(seed_value: int, bands: int = 0) -> Dictionary:
	var rng := SimRng.new(seed_value * 7919 + 104729)
	var biome := BIOME_ORDER[rng.pick_index(BIOME_ORDER.size())]
	var info: Dictionary = BIOMES[biome]
	var rates := {}
	for key: String in info["rates"]:
		rates[key] = _snap(float(info["rates"][key]) * rng_range(rng, 0.88, 1.12))
	var ores := {}
	for ore: String in ORES:
		var missing := float(ORE_MISSING[ore]) * (0.5 if biome == "highland" else 1.0)
		ores[ore] = 0.0 if rng.chance(missing) else _snap(rng_range(rng, 0.5, 1.5) * (1.2 if biome == "highland" else 1.0))
	var radius := _snap(rng_range(rng, 9.4, 12.2))
	var pond_angle := rng.randf() * TAU
	var pond_distance := rng_range(rng, 0.22, 0.42) * radius
	var island := {
		"radius": radius,
		"roughness": _snap(rng_range(rng, 0.14, 0.3)),
		"hills": _snap(rng_range(rng, 0.3, 0.75) * (1.35 if biome == "highland" else 1.0)),
		"pond": [_snap(cos(pond_angle) * pond_distance), _snap(sin(pond_angle) * pond_distance)],
		"pond_radius": _snap(rng_range(rng, 1.7, 2.7)),
		"springs": float(rng.randi_range(1, 4)),
	}
	var peoples: Array = []
	var rolled := 1 if rng.chance(0.45) else (2 if rng.chance(0.7) else 3)
	if bands <= 0:
		bands = rolled
	for k: int in bands:
		var culture := {}
		for axis: String in Society.CULTURE_AXES:
			culture[axis] = float(clampi(rng.randi_range(-CULTURE_SPREAD, CULTURE_SPREAD) + int((info["culture"] as Dictionary).get(axis, 0)), -100, 100))
		peoples.append({"name": NameGen.tribe_name(rng), "couples": 5.0 if bands == 1 else (4.0 if bands == 2 else 3.0), "culture": culture})
	return {
		"name": NameGen.tribe_name(rng),
		"biome": biome,
		"rain": _snap(float(info["rain"]) * rng_range(rng, 0.92, 1.08)),
		"drought": _snap(float(info["drought"]) * rng_range(rng, 0.8, 1.25)),
		"winter": _snap(float(info["winter"])),
		"sickness": _snap(float(info["sickness"])),
		"rates": rates,
		"ores": ores,
		"hazard": String(info["hazard"]),
		"island": island,
		"trees": _snap(float(info["trees"]) * rng_range(rng, 0.85, 1.15)),
		"rocks": _snap(float(info["rocks"]) * rng_range(rng, 0.85, 1.15)),
		"peoples": peoples,
	}


## The pond's capacity grows with its area; springs vary.
static func pond_capacity(world: Dictionary) -> float:
	var r := float(world["island"]["pond_radius"])
	return snappedf(260.0 * (r / 2.3) * (r / 2.3), 1.0)


static func rate(world: Dictionary, key: String) -> float:
	return float((world.get("rates", {}) as Dictionary).get(key, 1.0))


static func ore(world: Dictionary, key: String) -> float:
	return float((world.get("ores", {}) as Dictionary).get(key, 1.0))


## One line for the opening and the AI: "Kolu, a dry, windswept steppe: rich in copper, no tin."
static func describe(world: Dictionary) -> String:
	if world.is_empty():
		return ""
	var rich: Array[String] = []
	var none: Array[String] = []
	for ore_name: String in ORES:
		var amount := ore(world, ore_name)
		if amount == 0.0:
			none.append(ore_name)
		elif amount >= 1.2:
			rich.append(ore_name)
	var parts: Array[String] = []
	if not rich.is_empty():
		parts.append("rich in " + " and ".join(rich))
	if not none.is_empty():
		parts.append("no " + " or ".join(none))
	var line := "%s, a %s" % [world["name"], String(BIOMES[world["biome"]]["name"])]
	return line + (": " + ", ".join(parts) if not parts.is_empty() else "") + "."


static func rng_range(rng: SimRng, low: float, high: float) -> float:
	return low + (high - low) * rng.randf()


static func _snap(value: float) -> float:
	return snappedf(value, WorldState.FLOAT_STEP)
