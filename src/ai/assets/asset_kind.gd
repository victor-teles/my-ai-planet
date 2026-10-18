class_name AssetKind
extends RefCounted
## One kind of AI-authored asset (an architectural style, a banner, a poster, a language...).
## The golden rule holds: the AI writes a small spec, the kind validates and clamps it (palette
## indices, grammar modules, part limits), and the game builds the art from it. Every kind also
## writes the same spec without AI (offline()), seeded, so offline worlds vary too and a failed
## call never leaves anything unbuilt. The AssetDirector asks for a spec whenever a subject's
## signature changes, and keeps it in the world (AssetBook).
## A kind's task() names its prompt task in prompt_library/manifest.json (with "input": "subject").


## The prompt task, also the kind's key in the AssetBook.
func task() -> String:
	return ""


## Lower goes first when several specs are waiting (and while the asset budget lasts).
func priority() -> int:
	return 50


## Subjects that should have a spec now (tribe names, "tribe|law", building ids...), in a stable order.
func subjects(_state: WorldState) -> Array[String]:
	return []


## What a spec for this subject is written for right now (e.g. "age 2|Theocracy"). A stored spec
## with another signature is stale and gets rewritten; "" means the subject needs no spec now.
func signature(_state: WorldState, _subject: String) -> String:
	return ""


## The facts the prompt gets in its {subject} placeholder. Keep it small: a small model reads it.
func context(_state: WorldState, _subject: String) -> Dictionary:
	return {}


## Turns a schema-valid reply into the spec to store, clamped onto the palette and the grammar;
## null rejects it (then the offline spec is used).
func accept(_reply: Dictionary, _context: Dictionary) -> Variant:
	return null


## A schema-valid reply written without AI: deterministic for seed_value, varied by the context.
func offline(_context: Dictionary, _seed_value: int) -> Dictionary:
	return {}


## Called once a spec is stored. Only a kind that feeds the sim needs it (a language feeds NameGen).
func apply(_state: WorldState, _subject: String, _spec: Dictionary) -> void:
	pass


## The offline spec for a subject right now, accepted like an AI reply: what the game shows
## when there is no stored spec yet (see AssetDirector.spec_or_offline()).
func offline_spec(state: WorldState, subject: String) -> Dictionary:
	var facts := context(state, subject)
	var spec: Variant = accept(offline(facts, seed_for(state, subject)), facts)
	return spec if spec is Dictionary else {}


## The seed for a subject's offline spec: the same world and subject always get the same one.
func seed_for(state: WorldState, subject: String) -> int:
	return hash([state.seed_value, task(), subject, signature(state, subject)])
