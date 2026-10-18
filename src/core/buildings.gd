class_name Buildings
extends RefCounted
## What a tribe can build. The chief picks the next project from what the tribe needs and
## knows; materials are set aside when work starts, then builders put in the days.
## Every building sits on a numbered slot around the fire, so the view can place it.

## type -> {"name", "tech", "wood", "stone", "work" (builder-days), "home" (people it sleeps),
##   "ring" (which ring of slots it prefers: 0 inner, 1 middle, 2 outer)}
const TYPES := {
	"tent": {"name": "tent", "tech": "shelter", "wood": 10.0, "stone": 0.0, "work": 24, "home": 5, "ring": 0},
	"hut": {"name": "hut", "tech": "carpentry", "wood": 30.0, "stone": 6.0, "work": 70, "home": 6, "ring": 0},
	"longhouse": {"name": "longhouse", "tech": "carpentry", "wood": 70.0, "stone": 12.0, "work": 200, "home": 14, "ring": 1},
	"workshop": {"name": "workshop", "tech": "stone_tools", "wood": 20.0, "stone": 10.0, "work": 70, "home": 0, "ring": 1},
	"healer_hut": {"name": "healer's hut", "tech": "herbal_lore", "wood": 20.0, "stone": 0.0, "work": 60, "home": 0, "ring": 1},
	"storehouse": {"name": "storehouse", "tech": "pottery", "wood": 35.0, "stone": 15.0, "work": 110, "home": 0, "ring": 1},
	"shrine": {"name": "shrine", "tech": "rites", "wood": 0.0, "stone": 35.0, "work": 130, "home": 0, "ring": 1},
	"field": {"name": "field", "tech": "agriculture", "wood": 4.0, "stone": 0.0, "work": 45, "home": 0, "ring": 2},
	"palisade": {"name": "palisade", "tech": "carpentry", "wood": 90.0, "stone": 0.0, "work": 260, "home": 0, "ring": -1},
	# Later ages. Homes grow denser; the seats of power, of faith and of watching rise with them.
	"stone_house": {"name": "stone house", "tech": "masonry", "wood": 20.0, "stone": 40.0, "work": 120, "home": 8, "ring": 0},
	"rowhouse": {"name": "row house", "tech": "steam_power", "wood": 30.0, "stone": 60.0, "work": 180, "home": 16, "ring": 1},
	"apartment": {"name": "apartment block", "tech": "electricity", "wood": 20.0, "stone": 120.0, "work": 320, "home": 36, "ring": 1},
	"mine": {"name": "mine", "tech": "copper_working", "wood": 25.0, "stone": 0.0, "work": 90, "home": 0, "ring": 3},
	"smithy": {"name": "smithy", "tech": "copper_working", "wood": 20.0, "stone": 25.0, "work": 100, "home": 0, "ring": 1},
	"school": {"name": "school", "tech": "writing", "wood": 35.0, "stone": 20.0, "work": 120, "home": 0, "ring": 1},
	"temple": {"name": "temple", "tech": "masonry", "wood": 20.0, "stone": 90.0, "work": 300, "home": 0, "ring": 1},
	"great_house": {"name": "great house", "tech": "masonry", "wood": 40.0, "stone": 70.0, "work": 260, "home": 0, "ring": 0},
	"market": {"name": "market", "tech": "coinage", "wood": 40.0, "stone": 20.0, "work": 120, "home": 0, "ring": 2},
	"stone_wall": {"name": "stone wall", "tech": "masonry", "wood": 0.0, "stone": 160.0, "work": 360, "home": 0, "ring": -1},
	"barracks": {"name": "barracks", "tech": "bronze", "wood": 40.0, "stone": 40.0, "work": 160, "home": 0, "ring": 2},
	"watchtower": {"name": "watchtower", "tech": "bronze", "wood": 30.0, "stone": 30.0, "work": 100, "home": 0, "ring": 3},
	"statue": {"name": "statue of the ruler", "tech": "masonry", "wood": 0.0, "stone": 50.0, "work": 140, "home": 0, "ring": 0},
	"prison": {"name": "prison", "tech": "masonry", "wood": 20.0, "stone": 60.0, "work": 160, "home": 0, "ring": 3},
	"factory": {"name": "factory", "tech": "steam_power", "wood": 40.0, "stone": 80.0, "work": 260, "home": 0, "ring": 3},
	"broadcast_tower": {"name": "broadcast tower", "tech": "radio", "wood": 10.0, "stone": 40.0, "work": 200, "home": 0, "ring": 3},
	"surveillance_mast": {"name": "surveillance mast", "tech": "computing", "wood": 0.0, "stone": 20.0, "work": 120, "home": 0, "ring": 3},
}
## Slots per ring, and the first slot number of each ring. Slot -1 is the wall (around everything).
const RING_SIZES: Array[int] = [7, 10, 12, 14]
## Homes, from the humblest to the densest. A tribe builds the best it knows and slowly rebuilds the rest.
const HOMES: Array[String] = ["tent", "hut", "longhouse", "stone_house", "rowhouse", "apartment"]
## Buildings that stand around the whole village rather than on a slot.
const WALLS: Array[String] = ["palisade", "stone_wall"]


static func name_of(type: String) -> String:
	return String(TYPES[type]["name"]) if TYPES.has(type) else type


static func ring_start(ring: int) -> int:
	var start := 0
	for r: int in ring:
		start += RING_SIZES[r]
	return start


## The ring a slot is on.
static func ring_of(slot: int) -> int:
	var start := 0
	for r: int in RING_SIZES.size():
		if slot < start + RING_SIZES[r]:
			return r
		start += RING_SIZES[r]
	return RING_SIZES.size() - 1


static func slot_count() -> int:
	return ring_start(RING_SIZES.size())


static func is_home(type: String) -> bool:
	return type in HOMES


static func capacity(type: String) -> int:
	return int(TYPES[type]["home"]) if TYPES.has(type) else 0


## The first free slot for a new building of this type: its preferred ring first, then the
## rings around it. The palisade goes around everything (slot -1).
static func free_slot(state: WorldState, tribe: String, type: String) -> int:
	var ring := int(TYPES[type]["ring"])
	if ring < 0:
		return -1
	var taken := {}
	for b: int in state.buildings_of(tribe):
		taken[state.building_slots[b]] = true
	var order: Array[int] = [ring]
	for r: int in RING_SIZES.size():
		if r != ring:
			order.append(r)
	for r: int in order:
		for slot: int in range(ring_start(r), ring_start(r) + RING_SIZES[r]):
			if not taken.has(slot):
				return slot
	return -3 # no room left: the view tucks it at the edge
