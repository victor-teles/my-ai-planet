class_name NameGen
extends RefCounted
## Offline name generator. The AI can rename things later; this keeps the sim self-sufficient.

const ONSETS: Array[String] = ["k", "t", "m", "n", "r", "s", "v", "l", "h", "w", "z", "b", "d", "g"]
const VOWELS: Array[String] = ["a", "e", "i", "o", "u", "aa", "ai", "ou"]
const CODAS: Array[String] = ["", "", "", "n", "r", "sh", "l", "k"]


static func tribe_name(rng: SimRng) -> String:
	var syllables := rng.randi_range(2, 3)
	var name := ""
	for i: int in syllables:
		name += ONSETS[rng.pick_index(ONSETS.size())] + VOWELS[rng.pick_index(VOWELS.size())]
	name += CODAS[rng.pick_index(CODAS.size())]
	return name.capitalize()


## Shorter, softer names for people: "Teshu", "Mirra", "Kael".
static func person_name(rng: SimRng) -> String:
	var name := ONSETS[rng.pick_index(ONSETS.size())] + VOWELS[rng.pick_index(VOWELS.size())]
	if rng.chance(0.6):
		name += ONSETS[rng.pick_index(ONSETS.size())] + VOWELS[rng.pick_index(4)]
	name += CODAS[rng.pick_index(CODAS.size())]
	return name.capitalize()


## Family names, passed from parent to child: "Oruvan", "Teshkai".
static func family_name(rng: SimRng) -> String:
	var name := ONSETS[rng.pick_index(ONSETS.size())] + VOWELS[rng.pick_index(VOWELS.size())]
	name += ONSETS[rng.pick_index(ONSETS.size())] + VOWELS[rng.pick_index(4)]
	name += ["n", "r", "sh", "k", "l", "v"][rng.pick_index(6)]
	return name.capitalize()
