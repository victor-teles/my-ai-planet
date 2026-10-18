class_name AssetBook
extends RefCounted
## The AI-authored (or offline-generated) asset specs of a world, kept in WorldState.assets and
## saved with it, so a world looks the same after a reload and with the AI unplugged.
## Keyed "kind|subject" (e.g. "style|Kolu", "poster|Kolu|curfew"); each entry is
## {"spec": Dictionary, "signature": String, "source": provider id, "tick": int}.
## The signature records what the spec was written for (e.g. "age 2|Theocracy"): when the world
## moves on, the AssetDirector asks for a new one. Specs never change the sim's numbers.


static func key(kind: String, subject: String) -> String:
	return kind + "|" + subject


static func has_spec(state: WorldState, kind: String, subject: String) -> bool:
	return state.assets.has(key(kind, subject))


## The validated spec, or {} if there is none yet.
static func spec(state: WorldState, kind: String, subject: String) -> Dictionary:
	var entry: Dictionary = state.assets.get(key(kind, subject), {})
	return entry.get("spec", {})


## What the stored spec was written for, or "" if there is none.
static func signature(state: WorldState, kind: String, subject: String) -> String:
	var entry: Dictionary = state.assets.get(key(kind, subject), {})
	return String(entry.get("signature", ""))


static func source(state: WorldState, kind: String, subject: String) -> String:
	var entry: Dictionary = state.assets.get(key(kind, subject), {})
	return String(entry.get("source", ""))


static func put(state: WorldState, kind: String, subject: String, spec_value: Dictionary, signature_value: String, source_id: String) -> void:
	state.assets[key(kind, subject)] = {"spec": spec_value, "signature": signature_value, "source": source_id, "tick": state.tick}


static func erase(state: WorldState, kind: String, subject: String) -> void:
	state.assets.erase(key(kind, subject))


## Every subject of a kind that has a spec.
static func subjects(state: WorldState, kind: String) -> Array[String]:
	var found: Array[String] = []
	var prefix := kind + "|"
	for entry_key: String in state.assets:
		if entry_key.begins_with(prefix):
			found.append(entry_key.trim_prefix(prefix))
	found.sort()
	return found
