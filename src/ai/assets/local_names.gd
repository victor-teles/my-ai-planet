class_name LocalNames
extends RefCounted
## What a tribe calls its laws and buildings in its own words, for the feed and the panels: the
## stored "names" spec (AI or offline, see NamesKind), else the offline name the tribe would get,
## so nothing waits on the AI. Homes, fields and unknown ids keep their usual names. The sim only
## ever sees the ids.


## The tribe's name for a law, or its usual name ("Surveillance network").
static func law(state: WorldState, tribe: String, law_id: String) -> String:
	var own := local(state, "laws", tribe, law_id)
	return own if own else Laws.name_of(law_id)


## The tribe's name for a kind of building, or its usual name ("temple").
static func building(state: WorldState, tribe: String, type: String) -> String:
	var own := local(state, "buildings", tribe, type)
	return own if own else Buildings.name_of(type)


## The tribe's own name in a group ("laws" or "buildings"), or "" if it has none.
static func local(state: WorldState, group: String, tribe: String, id: String) -> String:
	if state == null or state.tribe_index(tribe) == -1:
		return ""
	if (group == "laws" and not Laws.LAWS.has(id)) or (group == "buildings" and id not in NamesKind.PLACES):
		return ""
	var stored: Dictionary = AssetBook.spec(state, "names", tribe).get(group, {})
	if stored.has(id):
		return String(stored[id])
	return NamesKind.offline_name(group, id, NamesKind.words_of(state, tribe), tribe)


## For EventText.text(): looks up a tribe's own names in this world.
static func lookup(state: WorldState) -> Callable:
	return func(group: String, tribe: String, id: String) -> String: return local(state, group, tribe, id)
