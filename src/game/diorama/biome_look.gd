class_name BiomeLook
extends RefCounted
## How each biome looks from the sky: the island's ground colors, the color of the kit's leaves,
## grass and stone, which trees grow and how thickly, what grows under them, and how much snow a
## winter leaves. Read from the world recipe's "biome" (see WorldGen.BIOMES); the recipe's
## "trees" and "rocks" then thin or thicken the planting.

## Ground: the island mesh's vertex colors. "bare" is the ground that shows through the grass on
## top (dust on the steppe, rock in the highlands), "bare_amount" how much of the top it covers.
## Foliage: kit material name -> color, replacing Kit.PALETTE's for this biome's props.
## Trees: "pine" is the share of pines, the rest are picked from "leafy"; "scrub" is the share of
## tree spots that grow a big bush instead. Counts are for an island of radius 10 with the
## recipe's density at 1; "rock_scale" sizes the boulders.
const LOOKS := {
	"meadow": {
		"ground": {"grass": Color(0.34, 0.70, 0.36), "grass_light": Color(0.56, 0.82, 0.40), "sand": Color(0.90, 0.80, 0.58),
			"dirt": Color(0.52, 0.32, 0.24), "dirt_light": Color(0.72, 0.50, 0.34), "rock": Color(0.52, 0.36, 0.46),
			"rock_deep": Color(0.30, 0.20, 0.36), "bare": Color(0.72, 0.62, 0.42), "bare_amount": 0.0},
		"foliage": {},
		"pine": 0.55, "scrub": 0.0, "tree_height": 1.0, "rock_scale": 1.0,
		"leafy": ["tree_oak", "tree_default", "tree_detailed", "tree_fat", "tree_oak_dark", "tree_default_dark"],
		"trees": 72, "rocks": 16, "undergrowth": 140,
		"plants": ["plant_bush", "plant_bushLarge", "plant_bushDetailed", "grass_large", "grass", "grass_large",
			"flower_redA", "flower_yellowA", "flower_purpleA", "mushroom_redGroup", "mushroom_tanGroup", "log", "stump_round"],
	},
	"steppe": {
		"ground": {"grass": Color(0.64, 0.56, 0.18), "grass_light": Color(0.82, 0.66, 0.22), "sand": Color(0.92, 0.84, 0.62),
			"dirt": Color(0.62, 0.38, 0.22), "dirt_light": Color(0.82, 0.58, 0.34), "rock": Color(0.60, 0.42, 0.42),
			"rock_deep": Color(0.36, 0.22, 0.32), "bare": Color(0.70, 0.42, 0.22), "bare_amount": 0.22},
		"foliage": {"leafsGreen": Color(0.58, 0.64, 0.26), "leafsDark": Color(0.36, 0.46, 0.24), "grass": Color(0.84, 0.70, 0.30),
			"stone": Color(0.76, 0.62, 0.50), "dirt": Color(0.76, 0.62, 0.50)},
		"pine": 0.1, "scrub": 0.35, "tree_height": 0.85, "rock_scale": 1.15,
		"leafy": ["tree_fat", "tree_default", "tree_oak", "tree_fat"],
		"trees": 64, "rocks": 22, "undergrowth": 160,
		"plants": ["grass", "grass_large", "grass", "grass_large", "grass", "plant_bush", "plant_bushDetailed", "flower_yellowA", "log"],
	},
	"jungle": {
		"ground": {"grass": Color(0.16, 0.54, 0.26), "grass_light": Color(0.36, 0.72, 0.22), "sand": Color(0.86, 0.78, 0.52),
			"dirt": Color(0.44, 0.24, 0.20), "dirt_light": Color(0.64, 0.38, 0.26), "rock": Color(0.42, 0.34, 0.44),
			"rock_deep": Color(0.24, 0.16, 0.32), "bare": Color(0.44, 0.30, 0.22), "bare_amount": 0.0},
		"foliage": {"leafsGreen": Color(0.30, 0.68, 0.24), "leafsDark": Color(0.08, 0.44, 0.32), "grass": Color(0.28, 0.64, 0.26),
			"stone": Color(0.50, 0.56, 0.50), "dirt": Color(0.50, 0.56, 0.50)},
		"pine": 0.0, "scrub": 0.0, "tree_height": 1.25, "rock_scale": 1.0,
		"leafy": ["tree_oak_dark", "tree_default_dark", "tree_detailed", "tree_fat", "tree_oak", "tree_oak_dark"],
		"trees": 80, "rocks": 16, "undergrowth": 220,
		"plants": ["plant_bushLarge", "plant_bushLarge", "plant_bushDetailed", "plant_bushDetailed", "plant_bush", "grass_large",
			"grass_large", "flower_redA", "flower_purpleA", "mushroom_redGroup", "log"],
	},
	"taiga": {
		"ground": {"grass": Color(0.22, 0.44, 0.38), "grass_light": Color(0.38, 0.56, 0.44), "sand": Color(0.78, 0.76, 0.68),
			"dirt": Color(0.40, 0.28, 0.28), "dirt_light": Color(0.58, 0.44, 0.38), "rock": Color(0.44, 0.40, 0.52),
			"rock_deep": Color(0.24, 0.22, 0.36), "bare": Color(0.54, 0.52, 0.58), "bare_amount": 0.12},
		"foliage": {"leafsGreen": Color(0.28, 0.50, 0.42), "leafsDark": Color(0.12, 0.32, 0.34), "grass": Color(0.36, 0.52, 0.40),
			"stone": Color(0.56, 0.56, 0.64), "dirt": Color(0.56, 0.56, 0.64)},
		"pine": 1.0, "scrub": 0.0, "tree_height": 1.15, "rock_scale": 1.0,
		"leafy": ["tree_default_dark"],
		"trees": 64, "rocks": 16, "undergrowth": 120,
		"plants": ["plant_bushDetailed", "plant_bush", "grass", "mushroom_tanGroup", "mushroom_tanGroup", "mushroom_redGroup",
			"log", "log", "stump_round", "stump_round"],
	},
	"highland": {
		"ground": {"grass": Color(0.28, 0.58, 0.38), "grass_light": Color(0.46, 0.68, 0.44), "sand": Color(0.80, 0.74, 0.64),
			"dirt": Color(0.46, 0.34, 0.34), "dirt_light": Color(0.62, 0.50, 0.46), "rock": Color(0.56, 0.50, 0.64),
			"rock_deep": Color(0.30, 0.24, 0.40), "bare": Color(0.44, 0.42, 0.52), "bare_amount": 0.4},
		"foliage": {"leafsGreen": Color(0.46, 0.60, 0.38), "leafsDark": Color(0.22, 0.40, 0.38), "grass": Color(0.50, 0.60, 0.40),
			"stone": Color(0.60, 0.56, 0.68), "dirt": Color(0.60, 0.56, 0.68)},
		"pine": 0.7, "scrub": 0.15, "tree_height": 0.85, "rock_scale": 1.4,
		"leafy": ["tree_fat", "tree_default", "tree_oak_dark"],
		"trees": 64, "rocks": 16, "undergrowth": 110,
		"plants": ["grass", "grass", "grass_large", "plant_bush", "plant_bushDetailed", "flower_purpleA", "flower_yellowA", "stump_round"],
	},
}


static func of(world: Dictionary) -> Dictionary:
	return LOOKS.get(String(world.get("biome", "meadow")), LOOKS["meadow"])


## How many of a kind (trees, rocks, undergrowth) to plant: the biome's count, thickened by the
## recipe's density and spread over the island's area.
static func count(world: Dictionary, kind: String) -> int:
	var look := of(world)
	var island: Dictionary = world.get("island", {})
	var area := pow(float(island.get("radius", 10.0)) / 10.0, 2.0)
	var density := 1.0
	match kind:
		"trees":
			density = float(world.get("trees", 1.0))
		"rocks":
			density = float(world.get("rocks", 1.0))
		"undergrowth":
			density = lerpf(1.0, float(world.get("trees", 1.0)), 0.5)
	return roundi(float(look[kind]) * density * area)


## How white the deepest winter turns this island, from 0 (it never snows) to about 0.6 on the
## coldest isles, where the snow lies in patches with the ground showing through.
static func snow(world: Dictionary) -> float:
	return clampf((float(world.get("winter", 0.8)) - 0.9) * 1.35, 0.0, 0.6)
