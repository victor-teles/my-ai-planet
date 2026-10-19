class_name NameGen
extends RefCounted
## Offline name generator. The AI can rename things later; this keeps the sim self-sufficient.
## Pass a tribe's tongue (see Language) and the names sound like its people; without one (or with
## the empty one) they come from the old default sound below.

const ONSETS: Array[String] = ["k", "t", "m", "n", "r", "s", "v", "l", "h", "w", "z", "b", "d", "g"]
const VOWELS: Array[String] = ["a", "e", "i", "o", "u", "aa", "ai", "ou"]
const CODAS: Array[String] = ["", "", "", "n", "r", "sh", "l", "k"]


static func tribe_name(rng: SimRng, language: Dictionary = {}) -> String:
	if not language.is_empty():
		return Language.tribe_name(rng, language)
	var syllables := rng.randi_range(2, 3)
	var name := ""
	for i: int in syllables:
		name += ONSETS[rng.pick_index(ONSETS.size())] + VOWELS[rng.pick_index(VOWELS.size())]
	name += CODAS[rng.pick_index(CODAS.size())]
	return name.capitalize()


## Shorter, softer names for people: "Teshu", "Mirra", "Kael".
static func person_name(rng: SimRng, language: Dictionary = {}) -> String:
	if not language.is_empty():
		return Language.person_name(rng, language)
	var name := ONSETS[rng.pick_index(ONSETS.size())] + VOWELS[rng.pick_index(VOWELS.size())]
	if rng.chance(0.6):
		name += ONSETS[rng.pick_index(ONSETS.size())] + VOWELS[rng.pick_index(4)]
	name += CODAS[rng.pick_index(CODAS.size())]
	return name.capitalize()


## Family names, passed from parent to child: "Oruvan", "Teshkai".
static func family_name(rng: SimRng, language: Dictionary = {}) -> String:
	if not language.is_empty():
		return Language.family_name(rng, language)
	var name := ONSETS[rng.pick_index(ONSETS.size())] + VOWELS[rng.pick_index(VOWELS.size())]
	name += ONSETS[rng.pick_index(ONSETS.size())] + VOWELS[rng.pick_index(4)]
	name += ["n", "r", "sh", "k", "l", "v"][rng.pick_index(6)]
	return name.capitalize()
