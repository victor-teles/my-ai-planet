class_name LanguageKind
extends AssetKind
## A people's own language: the sounds its names are made of (see Language). Asked once for each
## people who first landed on the island, early, since names are given from the first day; tribes
## that split off later take their parents' tongue with a drift instead, so they need no spec.
## The founders keep their names: the new sounds name the children born from then on, new family
## lines and the tribes that break away. Offline, the people keeps the tongue the island gave it.


func task() -> String:
	return "language"


func priority() -> int:
	return 10


## The founding peoples still on the island, in the order they landed.
func subjects(state: WorldState) -> Array[String]:
	var found: Array[String] = []
	for people: Dictionary in state.world.get("peoples", []):
		var name := String(people.get("name", ""))
		if state.tribe_index(name) != -1:
			found.append(name)
	return found


## Constant: a people's tongue is written once.
func signature(state: WorldState, subject: String) -> String:
	return "people" if subject in subjects(state) else ""


func context(state: WorldState, subject: String) -> Dictionary:
	var t := state.tribe_index(subject)
	var culture := {}
	var heard: Array[String] = []
	if t != -1:
		for axis: String in Society.CULTURE_AXES:
			culture[axis] = int(state.tribe_culture[t].get(axis, 0))
		for p: int in state.people_of(subject):
			heard.append("%s %s" % [state.person_names[p], state.person_families[p]])
			if heard.size() >= 6:
				break
	var biome := String(state.world.get("biome", "meadow"))
	return {
		"people": subject,
		"island": String(WorldGen.BIOMES.get(biome, WorldGen.BIOMES["meadow"])["name"]),
		"culture": culture,
		"sounds_now": Language.resolved(Language.of(state, t)).duplicate(true),
		"names_heard": heard,
	}


## The proposal made safe by Language; null if too little of it can be said aloud.
func accept(reply: Dictionary, _context: Dictionary) -> Variant:
	var spec := Language.clamp_spec(reply)
	return spec if not spec.is_empty() else null


## Offline the people keeps the tongue it has: storing it changes no name.
func offline(facts: Dictionary, _seed_value: int) -> Dictionary:
	var sounds: Dictionary = facts.get("sounds_now", {})
	return (sounds if Language.is_valid(sounds) else Language.DEFAULT).duplicate(true)


## The people names its children in the new tongue from now on (a tongue that is the one it has
## already, as offline, changes nothing).
func apply(state: WorldState, subject: String, spec: Dictionary) -> void:
	var t := state.tribe_index(subject)
	var clean := Language.clamp_spec(spec)
	if t == -1 or clean.is_empty() or clean == Language.resolved(state.tribe_language[t]):
		return
	state.tribe_language[t] = clean
