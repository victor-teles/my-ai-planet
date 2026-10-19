class_name ArtPalette
extends RefCounted
## The art bible's swatches, by index. AI-authored specs never name a raw color: they pick an
## index here, and the game clamps it (color()), so whatever the AI writes stays on palette.
## Groups list the indices that suit each use, for the offline generators and for prompts.

const SWATCHES: Array[Dictionary] = [
	{"name": "daub", "color": Color(0.80, 0.64, 0.48)},
	{"name": "thatch", "color": Color(0.86, 0.62, 0.36)},
	{"name": "timber", "color": Color(0.50, 0.34, 0.24)},
	{"name": "soil", "color": Color(0.50, 0.36, 0.30)},
	{"name": "stone", "color": Color(0.78, 0.71, 0.70)},
	{"name": "dark stone", "color": Color(0.58, 0.51, 0.55)},
	{"name": "marble", "color": Color(0.92, 0.87, 0.82)},
	{"name": "cold stone", "color": Color(0.62, 0.64, 0.70)},
	{"name": "cold dark", "color": Color(0.40, 0.42, 0.50)},
	{"name": "brick", "color": Color(0.76, 0.42, 0.33)},
	{"name": "dark brick", "color": Color(0.56, 0.31, 0.29)},
	{"name": "plaster", "color": Color(0.94, 0.86, 0.72)},
	{"name": "concrete", "color": Color(0.80, 0.78, 0.77)},
	{"name": "roof tile", "color": Color(0.82, 0.46, 0.35)},
	{"name": "slate", "color": Color(0.42, 0.40, 0.54)},
	{"name": "steel", "color": Color(0.52, 0.54, 0.62)},
	{"name": "iron", "color": Color(0.28, 0.27, 0.34)},
	{"name": "gold", "color": Color(0.98, 0.80, 0.36)},
	{"name": "grass", "color": Color(0.34, 0.70, 0.36)},
	{"name": "leaf", "color": Color(0.50, 0.72, 0.34)},
	{"name": "pine", "color": Color(0.20, 0.48, 0.44)},
	{"name": "straw", "color": Color(0.80, 0.66, 0.40)},
	{"name": "crimson", "color": Color(0.55, 0.22, 0.19)},
	{"name": "flame", "color": Color(0.90, 0.33, 0.24)},
	{"name": "saffron", "color": Color(0.95, 0.75, 0.25)},
	{"name": "rose", "color": Color(0.98, 0.58, 0.52)},
	{"name": "dusk violet", "color": Color(0.50, 0.36, 0.70)},
	{"name": "night indigo", "color": Color(0.16, 0.10, 0.34)},
	{"name": "sky blue", "color": Color(0.42, 0.62, 0.84)},
	{"name": "teal", "color": Color(0.24, 0.58, 0.60)},
	{"name": "cream", "color": Color(0.96, 0.92, 0.80)},
	{"name": "ink", "color": Color(0.16, 0.10, 0.20)},
]
## Indices that suit each use.
const GROUPS := {
	"walls": [0, 2, 4, 5, 6, 7, 8, 9, 10, 11, 12],
	"roofs": [1, 2, 3, 5, 8, 9, 13, 14, 15, 16, 17, 20, 22],
	"trim": [2, 6, 11, 15, 16, 17, 22, 23, 24, 26, 28, 29, 30],
	"cloth": [0, 1, 3, 11, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30],
	"drab": [3, 5, 7, 8, 12, 14, 16, 21],
	"bright": [17, 18, 22, 23, 24, 25, 26, 28, 29, 30],
	"heraldry": [6, 16, 17, 18, 20, 22, 23, 24, 26, 27, 28, 29, 30, 31],
}


static func size() -> int:
	return SWATCHES.size()


## The swatch at an index; out-of-range indices are clamped onto the palette.
static func color(index: int) -> Color:
	return SWATCHES[clampi(index, 0, SWATCHES.size() - 1)]["color"]


static func name_of(index: int) -> String:
	return SWATCHES[clampi(index, 0, SWATCHES.size() - 1)]["name"]


## Clamps an index onto the palette, then onto a group (the nearest of its indices) if given.
static func clamp_index(index: int, group: String = "") -> int:
	index = clampi(index, 0, SWATCHES.size() - 1)
	if group.is_empty() or index in GROUPS[group]:
		return index
	var best: int = GROUPS[group][0]
	for candidate: int in GROUPS[group]:
		if _distance(color(candidate), color(index)) < _distance(color(best), color(index)):
			best = candidate
	return best


## The swatches as a compact list for prompts: "0 daub, 1 thatch, ...", optionally one group only.
static func describe(group: String = "") -> String:
	var parts := PackedStringArray()
	var indices: Array = GROUPS[group] if group else range(SWATCHES.size())
	for index: int in indices:
		parts.append("%d %s" % [index, name_of(index)])
	return ", ".join(parts)


static func _distance(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length_squared()
